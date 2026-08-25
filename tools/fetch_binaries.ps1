<#
.SYNOPSIS
  Downloads the external CLI tools LabScale drives into ./bin.

.DESCRIPTION
  LabScale shells out to three binaries. They are deliberately not committed to
  git (they are large and separately licensed), so this script fetches them into
  the gitignored ./bin folder that both `flutter run` and the packaged app look
  in.

    ffmpeg / ffprobe        decode, encode, filter        (LGPL/GPL build)
    realesrgan-ncnn-vulkan  AI upscaling on Vulkan        (BSD-3)
    rife-ncnn-vulkan        AI frame interpolation        (MIT)

.EXAMPLE
  pwsh tools/fetch_binaries.ps1
#>
[CmdletBinding()]
param(
    [string]$BinDir = (Join-Path $PSScriptRoot '..' 'bin'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$BinDir = [System.IO.Path]::GetFullPath($BinDir)
New-Item -ItemType Directory -Force $BinDir | Out-Null

$staging = Join-Path ([System.IO.Path]::GetTempPath()) "labscale-fetch-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force $staging | Out-Null

function Get-Archive {
    param([string]$Url, [string]$FileName)

    $target = Join-Path $staging $FileName
    Write-Host "  downloading $FileName ..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $target
    $sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-Host "  got $FileName ($sizeMb MB)" -ForegroundColor DarkGray

    $extractDir = Join-Path $staging ([System.IO.Path]::GetFileNameWithoutExtension($FileName))
    Expand-Archive -Path $target -DestinationPath $extractDir -Force
    return $extractDir
}

function Copy-Payload {
    param([string]$SourceDir, [string[]]$Executables, [string[]]$ModelDirNames)

    foreach ($exe in $Executables) {
        $found = Get-ChildItem -Path $SourceDir -Filter $exe -Recurse -File |
            Select-Object -First 1
        if (-not $found) { throw "'$exe' tidak ditemukan di arsip yang diunduh" }
        Copy-Item $found.FullName (Join-Path $BinDir $exe) -Force
        Write-Host "  -> bin/$exe" -ForegroundColor Green
    }

    foreach ($modelDir in $ModelDirNames) {
        $found = Get-ChildItem -Path $SourceDir -Filter $modelDir -Recurse -Directory |
            Select-Object -First 1
        if (-not $found) { continue }
        $dest = Join-Path $BinDir $modelDir
        Copy-Item $found.FullName $dest -Recurse -Force
        Write-Host "  -> bin/$modelDir/" -ForegroundColor Green
    }
}

function Test-AlreadyPresent {
    param([string]$Name)
    if ($Force) { return $false }
    if (Test-Path (Join-Path $BinDir $Name)) {
        Write-Host "  $Name sudah ada — lewati (pakai -Force untuk unduh ulang)" -ForegroundColor Yellow
        return $true
    }
    return $false
}

try {
    Write-Host "`nBin dir: $BinDir`n" -ForegroundColor Cyan

    # ── FFmpeg ────────────────────────────────────────────────────────────────
    Write-Host "[1/3] FFmpeg" -ForegroundColor Cyan
    if (-not (Test-AlreadyPresent 'ffmpeg.exe')) {
        $dir = Get-Archive `
            -Url 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' `
            -FileName 'ffmpeg.zip'
        Copy-Payload -SourceDir $dir -Executables @('ffmpeg.exe', 'ffprobe.exe')
    }

    # ── Real-ESRGAN ───────────────────────────────────────────────────────────
    Write-Host "`n[2/3] Real-ESRGAN (ncnn-vulkan)" -ForegroundColor Cyan
    if (-not (Test-AlreadyPresent 'realesrgan-ncnn-vulkan.exe')) {
        $dir = Get-Archive `
            -Url 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip' `
            -FileName 'realesrgan.zip'
        Copy-Payload -SourceDir $dir `
            -Executables @('realesrgan-ncnn-vulkan.exe') `
            -ModelDirNames @('models')
    }

    # ── RIFE ──────────────────────────────────────────────────────────────────
    Write-Host "`n[3/3] RIFE (ncnn-vulkan)" -ForegroundColor Cyan
    if (-not (Test-AlreadyPresent 'rife-ncnn-vulkan.exe')) {
        $dir = Get-Archive `
            -Url 'https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-windows.zip' `
            -FileName 'rife.zip'
        Copy-Payload -SourceDir $dir `
            -Executables @('rife-ncnn-vulkan.exe') `
            -ModelDirNames @('rife-v4.6')
    }

    Write-Host "`nSelesai. Isi bin/:" -ForegroundColor Cyan
    Get-ChildItem $BinDir | ForEach-Object { Write-Host "  $($_.Name)" }
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
