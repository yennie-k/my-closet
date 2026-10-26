# Keep native Flutter test artifacts out of non-ASCII Windows user temp paths.
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testTemp = Join-Path $projectRoot 'build\test_temp'
New-Item -ItemType Directory -Force -Path $testTemp | Out-Null
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
Push-Location $projectRoot
try {
    $env:TEMP = $testTemp
    $env:TMP = $testTemp
    & flutter test @args
    $testExitCode = $LASTEXITCODE
}
finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    Pop-Location
}
exit $testExitCode
