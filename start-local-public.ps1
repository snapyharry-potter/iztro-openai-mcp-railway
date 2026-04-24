$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$runtimeDir = Join-Path $projectRoot ".runtime"
$nodeDir = "C:\Program Files\nodejs"
$nodeExe = Join-Path $nodeDir "node.exe"
$npmCmd = Join-Path $nodeDir "npm.cmd"
$sshExe = "C:\Windows\System32\OpenSSH\ssh.exe"
$cloudflaredExe = Join-Path $runtimeDir "cloudflared.exe"

$serverPidFile = Join-Path $runtimeDir "server.pid"
$tunnelPidFile = Join-Path $runtimeDir "tunnel.pid"
$tunnelProviderFile = Join-Path $runtimeDir "tunnel-provider.txt"
$publicUrlFile = Join-Path $runtimeDir "public-url.txt"
$serverOut = Join-Path $runtimeDir "server.out.log"
$serverErr = Join-Path $runtimeDir "server.err.log"
$cloudflareOut = Join-Path $runtimeDir "cloudflare-tunnel.out.log"
$cloudflareErr = Join-Path $runtimeDir "cloudflare-tunnel.err.log"
$sshTunnelOut = Join-Path $runtimeDir "ssh-tunnel.out.log"
$sshTunnelErr = Join-Path $runtimeDir "ssh-tunnel.err.log"

function Test-RunningProcess {
  param([string]$PidFile)

  if (-not (Test-Path $PidFile)) {
    return $null
  }

  $pidValue = (Get-Content $PidFile -Raw).Trim()
  if (-not $pidValue) {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    return $null
  }

  try {
    return Get-Process -Id ([int]$pidValue) -ErrorAction Stop
  } catch {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    return $null
  }
}

function Wait-ForHealth {
  param([string]$Url, [int]$Attempts = 30)

  for ($i = 0; $i -lt $Attempts; $i++) {
    try {
      $response = Invoke-WebRequest $Url -UseBasicParsing -TimeoutSec 3
      if ($response.StatusCode -eq 200) {
        return $true
      }
    } catch {
    }
    Start-Sleep -Seconds 1
  }

  return $false
}

function Get-TunnelUrl {
  param([string[]]$Paths)

  foreach ($path in $Paths) {
    if (-not (Test-Path $path)) {
      continue
    }

    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
      $content = ""
    }
    $cloudflareMatch = [regex]::Match($content, "https://[a-z0-9-]+\.trycloudflare\.com")
    if ($cloudflareMatch.Success) {
      return $cloudflareMatch.Value
    }

    $localhostRunMatch = [regex]::Match($content, "tunneled with tls termination, (https://[^\s]+)")
    if ($localhostRunMatch.Success) {
      return $localhostRunMatch.Groups[1].Value
    }
  }

  return $null
}

function Ensure-Cloudflared {
  if (Test-Path $cloudflaredExe) {
    return
  }

  $downloadUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
  Invoke-WebRequest $downloadUrl -OutFile $cloudflaredExe -UseBasicParsing
}

function Start-CloudflareTunnel {
  foreach ($path in @($cloudflareOut, $cloudflareErr)) {
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }

  Ensure-Cloudflared

  $process = Start-Process `
    -FilePath $cloudflaredExe `
    -ArgumentList @(
      "tunnel",
      "--url", "http://127.0.0.1:3000",
      "--no-autoupdate"
    ) `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $cloudflareOut `
    -RedirectStandardError $cloudflareErr `
    -PassThru

  Set-Content -Path $tunnelPidFile -Value $process.Id
  Set-Content -Path $tunnelProviderFile -Value "cloudflare"

  for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Seconds 2
    $url = Get-TunnelUrl -Paths @($cloudflareOut, $cloudflareErr)
    if ($url) {
      Set-Content -Path $publicUrlFile -Value ($url + "/mcp")
      return $url
    }
    if ($process.HasExited) {
      break
    }
  }

  try {
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
    }
  } catch {
  }

  Remove-Item $tunnelPidFile -Force -ErrorAction SilentlyContinue
  Remove-Item $tunnelProviderFile -Force -ErrorAction SilentlyContinue
  return $null
}

function Start-LocalhostRunTunnel {
  foreach ($path in @($sshTunnelOut, $sshTunnelErr)) {
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }

  $process = Start-Process `
    -FilePath $sshExe `
    -ArgumentList @(
      "-o", "StrictHostKeyChecking=no",
      "-o", "ServerAliveInterval=30",
      "-o", "ExitOnForwardFailure=yes",
      "-R", "80:127.0.0.1:3000",
      "nokey@localhost.run"
    ) `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $sshTunnelOut `
    -RedirectStandardError $sshTunnelErr `
    -PassThru

  Set-Content -Path $tunnelPidFile -Value $process.Id
  Set-Content -Path $tunnelProviderFile -Value "localhost.run"

  for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Seconds 2
    $url = Get-TunnelUrl -Paths @($sshTunnelOut, $sshTunnelErr)
    if ($url) {
      Set-Content -Path $publicUrlFile -Value ($url + "/mcp")
      return $url
    }
    if ($process.HasExited) {
      break
    }
  }

  throw "Localhost.run tunnel URL was not detected. Check $sshTunnelOut and $sshTunnelErr"
}

if (-not (Test-Path $runtimeDir)) {
  New-Item -ItemType Directory -Path $runtimeDir | Out-Null
}

if (-not (Test-Path $nodeExe)) {
  throw "Cannot find Node.js at $nodeExe"
}

if (-not (Test-Path $sshExe)) {
  throw "Cannot find ssh.exe at $sshExe"
}

$env:Path = "$nodeDir;$env:Path"

if (-not (Test-Path (Join-Path $projectRoot "node_modules"))) {
  & $npmCmd install
}

$serverProcess = Test-RunningProcess -PidFile $serverPidFile
if (-not $serverProcess) {
  foreach ($path in @($serverOut, $serverErr)) {
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }

  $serverProcess = Start-Process `
    -FilePath $nodeExe `
    -ArgumentList "src/index.js" `
    -WorkingDirectory $projectRoot `
    -RedirectStandardOutput $serverOut `
    -RedirectStandardError $serverErr `
    -PassThru

  Set-Content -Path $serverPidFile -Value $serverProcess.Id
}

if (-not (Wait-ForHealth -Url "http://127.0.0.1:3000/health")) {
  throw "Local MCP server did not become healthy. Check $serverErr"
}

$tunnelProcess = Test-RunningProcess -PidFile $tunnelPidFile
$publicBase = $null
$provider = $null

if ($tunnelProcess -and (Test-Path $tunnelProviderFile)) {
  $provider = (Get-Content $tunnelProviderFile -Raw).Trim()
  if ($provider -eq "cloudflare") {
    $publicBase = Get-TunnelUrl -Paths @($cloudflareOut, $cloudflareErr)
  } elseif ($provider -eq "localhost.run") {
    $publicBase = Get-TunnelUrl -Paths @($sshTunnelOut, $sshTunnelErr)
  }

  if ($publicBase) {
    Set-Content -Path $publicUrlFile -Value ($publicBase + "/mcp")
  }
}

if (-not $tunnelProcess -or -not $publicBase) {
  if ($tunnelProcess) {
    try {
      Stop-Process -Id $tunnelProcess.Id -Force -ErrorAction SilentlyContinue
    } catch {
    }
  }

  $publicBase = Start-CloudflareTunnel
  if ($publicBase) {
    $provider = "cloudflare"
  } else {
    $publicBase = Start-LocalhostRunTunnel
    $provider = "localhost.run"
  }
}

if (-not $publicBase) {
  throw "Tunnel URL was not detected."
}

Set-Content -Path $publicUrlFile -Value ($publicBase + "/mcp")

Write-Host ""
Write-Host "Local server is ready."
Write-Host "Local health:  http://127.0.0.1:3000/health"
Write-Host "Local MCP:     http://127.0.0.1:3000/mcp"
Write-Host ""
Write-Host "Provider:      $provider"
Write-Host "Public base:   $publicBase"
Write-Host "Public health: $publicBase/health"
Write-Host "Public MCP:    $publicBase/mcp"
Write-Host ""
Write-Host "Use the Public MCP URL in ChatGPT Developer mode with No Authentication."
