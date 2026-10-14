<#
.SYNOPSIS
  Downloads the external CLI tools LabScale drives into ./bin.

.DESCRIPTION
  LabScale shells out to three binaries. They are deliberately not committed to
  git (they are large and separately licensed), so this script fetches them into
  the gitignored ./bin folder that both `flutter run` and the packaged app look
  in.

    ffmpeg / ffprobe        decode, encode, filter        (GPLv3, gyan.dev)
    realesrgan-ncnn-vulkan  AI upscaling on Vulkan        (BSD-3)
    rife-ncnn-vulkan        AI frame interpolation        (MIT)

.EXAMPLE
  pwsh tools/fetch_binaries.ps1
#>
[CmdletBinding()]
param(
    [string]$BinDir = (Join-Path $PSScriptRoot '..' 'bin'),
    [switch]$Force,
    # Fetch RIFE v4.25 instead of v4.6. Costs a 788 MB download: every model
    # past v4.6 needs an ncnn build newer than nihui's 2022 release (the old
    # binary rejects them all with "layer MemoryData not exists or
    # registered"), and the only published Windows build of it ships inside one
    # archive with ~50 models. Only what is needed is kept.
    [switch]$RifeLatest,
    # UltraMix Balanced into bin/models, for development. It is CC BY-NC-SA
    # 4.0, so the installer leaves it out and the app downloads it when
    # picked (lib/core/model_store.dart).
    [switch]$ExtraModels
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
    param(
        [string]$SourceDir,
        [string[]]$Executables,
        [string[]]$ModelDirNames,
        [string[]]$SupportFiles
    )

    foreach ($exe in $Executables) {
        $found = Get-ChildItem -Path $SourceDir -Filter $exe -Recurse -File |
            Select-Object -First 1
        if (-not $found) { throw "'$exe' tidak ditemukan di arsip yang diunduh" }
        Copy-Item $found.FullName (Join-Path $BinDir $exe) -Force
        Write-Host "  -> bin/$exe" -ForegroundColor Green
    }

    # Runtime DLLs shipped alongside the ncnn tools (OpenMP, etc). Without these
    # the executables resolve but refuse to start on a machine lacking the
    # matching VC++ redistributable.
    foreach ($support in $SupportFiles) {
        $found = Get-ChildItem -Path $SourceDir -Filter $support -Recurse -File |
            Select-Object -First 1
        if (-not $found) { continue }
        Copy-Item $found.FullName (Join-Path $BinDir $support) -Force
        Write-Host "  -> bin/$support" -ForegroundColor Green
    }

    foreach ($modelDir in $ModelDirNames) {
        $found = Get-ChildItem -Path $SourceDir -Filter $modelDir -Recurse -Directory |
            Select-Object -First 1
        if (-not $found) { continue }
        $dest = Join-Path $BinDir $modelDir
        # Copy-Item -Recurse onto an existing directory nests it
        # (bin/models/models) instead of replacing it, so clear the target first.
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
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
    Write-Host "[1/4] FFmpeg" -ForegroundColor Cyan
    if (-not (Test-AlreadyPresent 'ffmpeg.exe')) {
        # Pinned to one version, not gyan.dev's moving "latest": a GPL binary
        # has to be matched by its exact source in every release, which a URL
        # that changes under us cannot promise.
        $dir = Get-Archive `
            -Url 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip' `
            -FileName 'ffmpeg.zip'
        Copy-Payload -SourceDir $dir -Executables @('ffmpeg.exe', 'ffprobe.exe')
    }

    # ── Real-ESRGAN ───────────────────────────────────────────────────────────
    Write-Host "`n[2/4] Real-ESRGAN (ncnn-vulkan)" -ForegroundColor Cyan
    if (-not (Test-AlreadyPresent 'realesrgan-ncnn-vulkan.exe')) {
        $dir = Get-Archive `
            -Url 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip' `
            -FileName 'realesrgan.zip'
        Copy-Payload -SourceDir $dir `
            -Executables @('realesrgan-ncnn-vulkan.exe') `
            -SupportFiles @('vcomp140.dll') `
            -ModelDirNames @('models')
    }

    # ── RIFE ──────────────────────────────────────────────────────────────────
    Write-Host "`n[3/4] RIFE (ncnn-vulkan)" -ForegroundColor Cyan
    # -RifeLatest must run even when a binary is already installed: that binary
    # is almost certainly the old one, which is exactly what needs replacing.
    if ($RifeLatest -or (-not (Test-AlreadyPresent 'rife-ncnn-vulkan.exe'))) {
        if ($RifeLatest) {
            Write-Host '  mengunduh rilis TNTwise (788 MB) — hanya yang perlu disimpan' -ForegroundColor Yellow
            $dir = Get-Archive `
                -Url 'https://github.com/TNTwise/rife-ncnn-vulkan/releases/download/20250112/windows.zip' `
                -FileName 'rife-latest.zip'
            Copy-Payload -SourceDir $dir `
                -Executables @('rife-ncnn-vulkan.exe') `
                -SupportFiles @('vcomp140.dll') `
                -ModelDirNames @('rife-v4.25')
        }
        else {
            $dir = Get-Archive `
                -Url 'https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-windows.zip' `
                -FileName 'rife.zip'
            Copy-Payload -SourceDir $dir `
                -Executables @('rife-ncnn-vulkan.exe') `
                -SupportFiles @('vcomp140.dll') `
                -ModelDirNames @('rife-v4.6')
            Write-Host '  RIFE v4.6 (2022). Pakai -RifeLatest untuk v4.25 yang lebih baik.' -ForegroundColor Yellow
        }
    }

    # ── Model upscale tambahan ────────────────────────────────────────────────
    Write-Host "`n[4/4] Model upscale tambahan" -ForegroundColor Cyan
    # Pinned to the commit whose hashes lib/core/model_store.dart checks.
    # upscayl-lite-4x is xinntao's realesr-general-x4v3 (BSD-3) renamed, and
    # ships in the installer; UltraMix only with -ExtraModels.
    $names = @('upscayl-lite-4x')
    if ($ExtraModels) {
        $names += @('ultramix-balanced-4x')
    }
    else {
        Write-Host '  UltraMix dilewati - app mengunduhnya saat dipilih.' -ForegroundColor Yellow
    }
    & {
        $base = 'https://raw.githubusercontent.com/upscayl/upscayl/a00d55fee90e0f9435d5eaa86e76700df8199af8/resources/models'
        $modelsDir = Join-Path $BinDir 'models'
        New-Item -ItemType Directory -Force -Path $modelsDir | Out-Null
        foreach ($name in $names) {
            $paramPath = Join-Path $modelsDir "$name.param"
            if ((-not $Force) -and (Test-Path $paramPath)) {
                Write-Host "  $name sudah ada - lewati" -ForegroundColor Yellow
                continue
            }
            # Staged first, then moved as a pair: writing straight into
            # models/ meant an interrupted .bin left a valid-looking .param
            # behind, and the skip check above keys on that .param.
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "labscale-$name"
            New-Item -ItemType Directory -Force -Path $tmp | Out-Null
            try {
                foreach ($ext in @('param', 'bin')) {
                    Invoke-WebRequest -Uri "$base/$name.$ext" `
                        -OutFile (Join-Path $tmp "$name.$ext")
                }
                foreach ($ext in @('param', 'bin')) {
                    Move-Item -Force (Join-Path $tmp "$name.$ext") $modelsDir
                }
                Write-Host "  -> models/$name" -ForegroundColor Green
            }
            catch {
                Write-Host "  gagal mengunduh $name - dilewati" -ForegroundColor Red
            }
            finally {
                Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host "`nSelesai. Isi bin/:" -ForegroundColor Cyan
    Get-ChildItem $BinDir | ForEach-Object { Write-Host "  $($_.Name)" }
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
