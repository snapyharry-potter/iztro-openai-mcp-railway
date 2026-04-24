$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$parentDir = Split-Path $projectRoot -Parent
$stagingDir = Join-Path $parentDir "iztro-openai-mcp-railway-ready"
$zipPath = Join-Path $parentDir "iztro-openai-mcp-railway-ready.zip"

if (Test-Path $stagingDir) {
  Remove-Item -Recurse -Force $stagingDir
}

if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}

New-Item -ItemType Directory -Path $stagingDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingDir "src") | Out-Null

Copy-Item (Join-Path $projectRoot "package.json") $stagingDir
Copy-Item (Join-Path $projectRoot "package-lock.json") $stagingDir
Copy-Item (Join-Path $projectRoot "railway.json") $stagingDir
Copy-Item (Join-Path $projectRoot "README.md") $stagingDir
Copy-Item (Join-Path $projectRoot ".gitignore") $stagingDir
Copy-Item (Join-Path $projectRoot "get-public-url.ps1") $stagingDir
Copy-Item (Join-Path $projectRoot "start-local-public.ps1") $stagingDir
Copy-Item (Join-Path $projectRoot "stop-local-public.ps1") $stagingDir
Copy-Item (Join-Path $projectRoot "pack-railway.ps1") $stagingDir
Copy-Item (Join-Path $projectRoot "src\\index.js") (Join-Path $stagingDir "src")

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath

Write-Host "Created: $zipPath"
