$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectRoot
try {
    New-Item -ItemType Directory -Force -Path 'build\storage_probe' | Out-Null
    & dart compile js tool/browser_storage_probe.dart -o build/storage_probe/probe.js
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & node scripts/browser_storage_test.cjs
    $probeExitCode = $LASTEXITCODE
}
finally { Pop-Location }
exit $probeExitCode
