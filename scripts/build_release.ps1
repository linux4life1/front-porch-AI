param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"

if ($Clean) {
    Write-Host "=== Clean build ==="
    & cmd.exe /c "cd /d `"$ProjectRoot`" && flutter clean 2>&1"
}

Write-Host "=== Building ==="
& cmd.exe /c "cd /d `"$ProjectRoot`" && flutter build windows --release 2>&1"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

Write-Host "=== Patching onnxruntime.dll ==="
$SherpaDll = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\sherpa_onnx_windows-1.13.4\windows\onnxruntime.dll"
if (Test-Path $SherpaDll) {
    Copy-Item -Path $SherpaDll -Destination "$ReleaseDir\onnxruntime.dll" -Force
    $ver = (Get-Item "$ReleaseDir\onnxruntime.dll").VersionInfo.FileVersion
    Write-Host "  onnxruntime.dll -> $ver"
} else {
    Write-Warning "  sherpa_onnx_windows onnxruntime.dll not found at $SherpaDll"
}

$SherpaShared = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\sherpa_onnx_windows-1.13.4\windows\onnxruntime_providers_shared.dll"
if (Test-Path $SherpaShared) {
    Copy-Item -Path $SherpaShared -Destination "$ReleaseDir\onnxruntime_providers_shared.dll" -Force
    Write-Host "  onnxruntime_providers_shared.dll patched"
} else {
    Write-Warning "  sherpa_onnx_windows providers DLL not found"
}

Write-Host "=== Done ==="
