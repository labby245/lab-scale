<#
.SYNOPSIS
  Builds LabScale for Windows: a per-user installer plus a portable zip.

.DESCRIPTION
  Runs `flutter build windows --release`, copies ./bin (ffmpeg + ncnn tools)
  next to the executable so the packaged app finds them, then writes
  dist/LabScale-<version>-windows-x64.zip and, when Inno Setup's ISCC is on
  PATH, dist/LabScale-Setup-<version>.exe.

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

    # Version from pubspec.yaml, passed explicitly (see package_macos.sh).
    $pubVersion = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
    Write-Host "`n== flutter build windows --release ($pubVersion) ==" -ForegroundColor Cyan
    & flutter build windows --release --build-name=$($pubVersion.Split('+')[0]) --build-number=$($pubVersion.Split('+')[1])
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
    $payloadDirs = @()

    # Only the Real-ESRGAN weights whose licences allow redistribution; the
    # rest are downloaded by the app on demand. Same list as package_macos.sh.
    $bundledModels = Get-Content (Join-Path $PSScriptRoot 'bundled_models.txt') |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ }

    # Only the RIFE model the app would actually pick, in the same order as
    # Binaries._modelDirNames. Shipping the rest would add ~10 MB each for
    # weights that never load.
    foreach ($candidate in @('rife-v4.25', 'rife-v4.15', 'rife-v4.6')) {
        if (Test-Path (Join-Path $binDir $candidate)) {
            $payloadDirs += $candidate
            break
        }
    }

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

        $payloadModels = Join-Path $payloadBin 'models'
        New-Item -ItemType Directory -Force $payloadModels | Out-Null
        foreach ($stem in $bundledModels) {
            foreach ($ext in @('param', 'bin')) {
                $src = Join-Path $binDir "models\$stem.$ext"
                if (-not (Test-Path $src)) { throw "bin/models/$stem.$ext tidak ada" }
                Copy-Item $src $payloadModels -Force
            }
            Write-Host "  models/$stem"
        }
    }
    else {
        Write-Host 'bin/ kosong — app akan mencari tool di PATH' -ForegroundColor Yellow
    }

    # The licences travel with the binaries they cover.
    foreach ($doc in @('LICENSE', 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item (Join-Path $root $doc) (Join-Path $releaseDir $doc) -Force
    }
    $licensesOut = Join-Path $releaseDir 'licenses'
    if (Test-Path $licensesOut) { Remove-Item $licensesOut -Recurse -Force }
    Copy-Item (Join-Path $root 'licenses') $licensesOut -Recurse -Force

    $version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
    $versionName = $version.Split('+')[0]

    New-Item -ItemType Directory -Force $distDir | Out-Null
    $zipPath = Join-Path $distDir "LabScale-$versionName-windows-x64.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Write-Host "`n== mengemas zip ==" -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath

    $sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "zip: $zipPath ($sizeMb MB)" -ForegroundColor Green

    # The installer is what most people should download: Start menu entry,
    # uninstaller, no admin prompt. The zip stays for those who want portable.
    $iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    if (-not $iscc) {
        $default = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
        if (Test-Path $default) { $iscc = Get-Item $default }
    }
    if ($iscc) {
        Write-Host "`n== membangun installer ==" -ForegroundColor Cyan
        & $iscc.Source "/DAppVersion=$versionName" "/DSourceDir=$releaseDir" `
            "/DOutputDir=$distDir" (Join-Path $PSScriptRoot 'windows\labscale.iss')
        if ($LASTEXITCODE -ne 0) { throw "ISCC gagal (exit $LASTEXITCODE)" }
        Write-Host "installer: $(Join-Path $distDir "LabScale-Setup-$versionName.exe")" -ForegroundColor Green
    }
    else {
        Write-Host 'Inno Setup (ISCC) tidak ditemukan — installer dilewati, zip saja.' -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
