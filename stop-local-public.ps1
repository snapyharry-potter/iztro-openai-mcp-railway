$ErrorActionPreference = "Stop"

$runtimeDir = Join-Path $PSScriptRoot ".runtime"
$serverPidFile = Join-Path $runtimeDir "server.pid"
$tunnelPidFile = Join-Path $runtimeDir "tunnel.pid"
$tunnelProviderFile = Join-Path $runtimeDir "tunnel-provider.txt"
$publicUrlFile = Join-Path $runtimeDir "public-url.txt"

function Stop-FromPidFile {
  param([string]$PidFile, [string]$Label)

  if (-not (Test-Path $PidFile)) {
    Write-Host "$Label is not running."
    return
  }

  $pidValue = (Get-Content $PidFile -Raw).Trim()
  if (-not $pidValue) {
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host "$Label pid file was empty."
    return
  }

  try {
    Stop-Process -Id ([int]$pidValue) -Force -ErrorAction Stop
    Write-Host "Stopped $Label (PID $pidValue)."
  } catch {
    Write-Host "$Label process was already stopped."
  }

  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

Stop-FromPidFile -PidFile $tunnelPidFile -Label "Tunnel"
Stop-FromPidFile -PidFile $serverPidFile -Label "MCP server"
Remove-Item $tunnelProviderFile -Force -ErrorAction SilentlyContinue
Remove-Item $publicUrlFile -Force -ErrorAction SilentlyContinue
