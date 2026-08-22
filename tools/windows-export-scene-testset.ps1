param(
    [string]$SteamLibrary = "E:\SteamLibrary",
    [string]$Destination = "$HOME\Desktop\WaifuX-Scene-Testset"
)

$ErrorActionPreference = "Stop"

$WorkshopRoot = Join-Path $SteamLibrary "steamapps\workshop\content\431960"
$WallpaperEngineRoot = Join-Path $SteamLibrary "steamapps\common\wallpaper_engine"

$Tests = @(
    [PSCustomObject]@{
        Tier = "A-basic"
        WorkshopID = "2947302287"
        Title = "Angled Waves"
    },
    [PSCustomObject]@{
        Tier = "B-audio-effects"
        WorkshopID = "3034129787"
        Title = "Azusawa Kohane | 4K | PJSK | Project Sekai | AUDIO RESPONSIVE"
    },
    [PSCustomObject]@{
        Tier = "C-complex-realtime"
        WorkshopID = "3509243656"
        Title = "三体实时演算 | Three-Body problem - SYKM"
    }
)

if (-not (Test-Path $WorkshopRoot)) {
    throw "Wallpaper Engine Workshop root not found: $WorkshopRoot"
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$Manifest = @()

foreach ($Test in $Tests) {
    $Source = Join-Path $WorkshopRoot $Test.WorkshopID
    if (-not (Test-Path $Source)) {
        Write-Warning "Missing Workshop item $($Test.WorkshopID): $Source"
        continue
    }

    $TargetName = "$($Test.Tier)-$($Test.WorkshopID)"
    $Target = Join-Path $Destination $TargetName

    Write-Host "Copying $($Test.Title)" -ForegroundColor Cyan
    Write-Host "  $Source"
    Write-Host "  -> $Target"

    if (Test-Path $Target) {
        Remove-Item -Recurse -Force $Target
    }

    Copy-Item -Recurse -Force $Source $Target

    $ProjectJson = Join-Path $Target "project.json"
    $SceneJson = Join-Path $Target "scene.json"
    $ScenePkg = Join-Path $Target "scene.pkg"

    $SizeBytes = (Get-ChildItem $Target -Recurse -File | Measure-Object Length -Sum).Sum

    $Manifest += [PSCustomObject]@{
        Tier = $Test.Tier
        WorkshopID = $Test.WorkshopID
        Title = $Test.Title
        SourcePath = $Source
        ExportPath = $Target
        SizeMB = [math]::Round($SizeBytes / 1MB, 2)
        HasProjectJson = Test-Path $ProjectJson
        HasSceneJson = Test-Path $SceneJson
        HasScenePkg = Test-Path $ScenePkg
    }
}

$ManifestPath = Join-Path $Destination "scene-testset-manifest.csv"
$Manifest | Export-Csv $ManifestPath -NoTypeInformation -Encoding UTF8

$InfoPath = Join-Path $Destination "wallpaper-engine-paths.txt"
@(
    "WallpaperEngineRoot=$WallpaperEngineRoot"
    "WorkshopRoot=$WorkshopRoot"
    "AssetsCandidate=$(Join-Path $WallpaperEngineRoot 'assets')"
    "AssetsPCCandidate=$(Join-Path $WallpaperEngineRoot 'assets-pc')"
) | Set-Content -Path $InfoPath -Encoding UTF8

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test set: $Destination"
Write-Host "Manifest: $ManifestPath"
Write-Host "Wallpaper Engine paths: $InfoPath"
Write-Host ""
Write-Host "Do NOT upload the full Wallpaper Engine assets directory. Keep it local for later Mac testing."
