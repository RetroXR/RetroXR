#!/usr/bin/env pwsh
# download_pdfium.ps1 — Downloads pre-built PDFium static libraries from bblanchon/pdfium-binaries.
# Run from the repository root: .\Tools\download_pdfium.ps1

$ErrorActionPreference = "Stop"
$repo = "bblanchon/pdfium-binaries"
$dest = Join-Path $PSScriptRoot "..\..\godot-pdfium\external\pdfium"

# Platforms to download
$platforms = @(
    @{ Name = "win-x64";        Archive = "pdfium-win-x64.tgz";         LibDir = "win-x64"       },
    @{ Name = "android-arm64";  Archive = "pdfium-android-arm64.tgz";   LibDir = "android-arm64"  }
)

# Resolve latest release URL
$latestUrl = "https://github.com/$repo/releases/latest"
Write-Host "Resolving latest release from $latestUrl ..."

foreach ($plat in $platforms) {
    $url = "https://github.com/$repo/releases/latest/download/$($plat.Archive)"
    $archivePath = Join-Path $env:TEMP $plat.Archive
    $extractDir  = Join-Path $env:TEMP "pdfium-$($plat.Name)"

    Write-Host "`n=== Downloading $($plat.Name) ==="
    Write-Host "  URL: $url"
    Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing
    Write-Host "  Saved to: $archivePath"

    # Extract .tgz (tar + gzip)
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    New-Item -ItemType Directory -Force $extractDir | Out-Null
    tar -xzf $archivePath -C $extractDir
    Write-Host "  Extracted to: $extractDir"

    # Copy headers (only need to do once — they're identical across platforms)
    $srcInclude = Join-Path $extractDir "include"
    $destInclude = Join-Path $dest "include"
    if (Test-Path $srcInclude) {
        Write-Host "  Copying headers to $destInclude"
        if (-not (Test-Path $destInclude)) { New-Item -ItemType Directory -Force $destInclude | Out-Null }
        Copy-Item -Path "$srcInclude\*" -Destination $destInclude -Recurse -Force
    }

    # Copy static library
    $destLib = Join-Path $dest "lib" $plat.LibDir
    if (-not (Test-Path $destLib)) { New-Item -ItemType Directory -Force $destLib | Out-Null }

    $srcLib = Join-Path $extractDir "lib"
    if (Test-Path $srcLib) {
        Write-Host "  Copying libs to $destLib"
        Copy-Item -Path "$srcLib\*" -Destination $destLib -Recurse -Force
    }

    # Also copy .dll if present (Windows shared build fallback)
    $srcBin = Join-Path $extractDir "bin"
    if (Test-Path $srcBin) {
        Write-Host "  Copying binaries to $destLib"
        Copy-Item -Path "$srcBin\*" -Destination $destLib -Recurse -Force
    }

    # Cleanup
    Remove-Item -Force $archivePath
    Remove-Item -Recurse -Force $extractDir
}

# Copy LICENSE if present
$licSrc = Join-Path $env:TEMP "pdfium-license-check"
Write-Host "`n=== Done ==="
Write-Host "PDFium headers: $dest\include\"
Write-Host "PDFium libs:    $dest\lib\"
Write-Host "`nDirectory structure:"
Get-ChildItem -Path $dest -Recurse -Name | ForEach-Object { Write-Host "  $_" }
