param(
    [string]$Source = "$HOME\Desktop\WaifuX-Scene-Testset\A-basic-2947302287",
    [string]$Zip = "$HOME\Desktop\WaifuX-Scene-A-basic-2947302287.zip"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) {
    throw "Tier A scene folder not found: $Source"
}

if (Test-Path $Zip) {
    Remove-Item -Force $Zip
}

Write-Host "Packing Tier A scene for Intel Mac testing..." -ForegroundColor Cyan
Compress-Archive -Path $Source -DestinationPath $Zip -CompressionLevel Optimal

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Transfer this file to the Intel Mac:"
Write-Host "  $Zip"
