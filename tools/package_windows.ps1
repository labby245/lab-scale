<#
.SYNOPSIS
  Builds LabScale for Windows and produces a distributable zip.

.DESCRIPTION
  Runs `flutter build windows --release`, copies ./bin (ffmpeg + ncnn tools)
  next to the executable so the packaged app finds them, and zips the result
  into ./dist.

.EXAMPLE
  pwsh tools/package_windows.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipBinaries
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$binDir = Join-Path $root 'bin'
$distDir = Join-Path $root 'dist'
$releaseDir = Join-Path $root 'build\windows\x64\runner\Release'

Push-Location $root
try {
    if (-not $SkipBinaries -and -not (Test-Path (Join-Path $binDir 'ffmpeg.exe'))) {
        Write-Host 'bin/ffmpeg.exe belum ada — menjalankan fetch_binaries.ps1' -ForegroundColor Yellow
        & (Join-Path $PSScriptRoot 'fetch_binaries.ps1')
    }

    Write-Host "`n== flutter build windows --release ==" -ForegroundColor Cyan
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build gagal (exit $LASTEXITCODE)" }

    if (-not (Test-Path $releaseDir)) { throw "Folder rilis tidak ditemukan: $releaseDir" }

    # The app resolves tools from <exeDir>/bin, so copy ./bin into the payload.
    #
    # Only what the app actually invokes is shipped. A dev bin/ typically also
    # holds nine legacy RIFE model variants (~430 MB) that LabScale never loads,
    # so mirroring the folder wholesale would quadruple the download.
    $payloadFiles = @(
        'ffmpeg.exe',
        'ffprobe.exe',
        'realesrgan-ncnn-vulkan.exe',
        'rife-ncnn-vulkan.exe',
        'vcomp140.dll'          # OpenMP runtime the ncnn binaries link against
    )
    $payloadDirs = @(
        'models',               # Real-ESRGAN weights
        'rife-v4.6'             # the only RIFE model LabScale asks for
    )

    if (Test-Path $binDir) {
        Write-Host "`n== menyalin bin/ ke payload ==" -ForegroundColor Cyan
        $payloadBin = Join-Path $releaseDir 'bin'
        if (Test-Path $payloadBin) { Remove-Item $payloadBin -Recurse -Force }
        New-Item -ItemType Directory -Force $payloadBin | Out-Null

        foreach ($name in $payloadFiles) {
            $src = Join-Path $binDir $name
            if (Test-Path $src) {
                Copy-Item $src (Join-Path $payloadBin $name) -Force
                Write-Host "  $name"
            }
            elseif ($name -in @('ffmpeg.exe', 'ffprobe.exe')) {
                throw "$name wajib ada di bin/ — jalankan tools/fetch_binaries.ps1"
            }
            else {
                Write-Host "  $name (tidak ada — dilewati)" -ForegroundColor Yellow
            }
        }
        foreach ($name in $payloadDirs) {
            $src = Join-Path $binDir $name
            if (Test-Path $src) {
                Copy-Item $src (Join-Path $payloadBin $name) -Recurse -Force
                Write-Host "  $name/"
            }
        }
    }
    else {
        Write-Host 'bin/ kosong — app akan mencari tool di PATH' -ForegroundColor Yellow
    }

    $version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
    $versionName = $version.Split('+')[0]

    New-Item -ItemType Directory -Force $distDir | Out-Null
    $zipPath = Join-Path $distDir "LabScale-$versionName-windows-x64.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Write-Host "`n== mengemas zip ==" -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath

    $sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "`nSelesai: $zipPath ($sizeMb MB)" -ForegroundColor Green
}
finally {
    Pop-Location
}
