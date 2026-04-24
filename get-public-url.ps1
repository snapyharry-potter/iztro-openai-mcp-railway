$ErrorActionPreference = "Stop"

$runtimeDir = Join-Path $PSScriptRoot ".runtime"
$providerFile = Join-Path $runtimeDir "tunnel-provider.txt"
$cloudflareOut = Join-Path $runtimeDir "cloudflare-tunnel.out.log"
$cloudflareErr = Join-Path $runtimeDir "cloudflare-tunnel.err.log"
$sshTunnelOut = Join-Path $runtimeDir "ssh-tunnel.out.log"
$sshTunnelErr = Join-Path $runtimeDir "ssh-tunnel.err.log"
$publicUrlFile = Join-Path $runtimeDir "public-url.txt"

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

if (-not (Test-Path $providerFile)) {
  throw "No active tunnel metadata was found in $providerFile"
}

$provider = (Get-Content $providerFile -Raw).Trim()
$publicBase = $null

if ($provider -eq "cloudflare") {
  $publicBase = Get-TunnelUrl -Paths @($cloudflareOut, $cloudflareErr)
} elseif ($provider -eq "localhost.run") {
  $publicBase = Get-TunnelUrl -Paths @($sshTunnelOut, $sshTunnelErr)
} else {
  throw "Unknown tunnel provider: $provider"
}

if (-not $publicBase) {
  throw "Could not detect a public tunnel URL from the log files."
}

$publicMcp = $publicBase + "/mcp"
Set-Content -Path $publicUrlFile -Value $publicMcp
Write-Output $publicMcp
