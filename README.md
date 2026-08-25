# LabScale

Upscale AI dan boost 60 FPS untuk foto & video — aplikasi desktop Flutter untuk **Windows dan macOS**. Semua pemrosesan berjalan **lokal**, tidak ada yang dikirim ke cloud, dan file asli tidak pernah diubah.

## Fitur

- **Upscale** — Real-ESRGAN (foto / anime / video anime) atau Lanczos untuk hasil cepat tanpa AI. Skala 1×–4×.
- **Sharpness** — unsharp mask yang bisa diatur, diterapkan dalam satu pass bersama enkode.
- **Boost ke 60 FPS** — motion interpolation via RIFE AI (5–10× lebih cepat dan jauh lebih halus) atau FFmpeg `minterpolate`.
- **Batch / folder** — drop satu folder, semua media di dalamnya diproses berurutan.
- **Kualitas & codec** — Fast → Ultra (lossless), H.264 / HEVC / AV1, dengan NVENC (Windows) atau VideoToolbox (macOS) otomatis bila tersedia.
- **Audio dipertahankan** — audio AAC di-copy apa adanya, format lain di-transcode ke AAC 192k.

## Arsitektur

LabScale adalah aplikasi Flutter murni. Tidak ada runtime Python, tidak ada server lokal. Dart mengorkestrasi tiga binary CLI:

| Tool | Peran | GPU |
|---|---|---|
| `ffmpeg` / `ffprobe` | probe, ekstrak frame, filter, enkode | NVENC / VideoToolbox |
| `realesrgan-ncnn-vulkan` | upscale AI | Vulkan (Win) / Metal via MoltenVK (Mac) |
| `rife-ncnn-vulkan` | interpolasi frame AI | Vulkan / Metal |

Video mengambil salah satu dari dua jalur:

- **Direct** — satu pass FFmpeg yang mencakup Lanczos, `minterpolate`, dan unsharp. Dipakai bila tidak ada stage AI.
- **Frames** — dekode ke PNG → (RIFE) → (Real-ESRGAN) → enkode ulang. Wajib bila ada stage ncnn.

> Melanjutkan pekerjaan ini di mesin lain (khususnya macOS)? Baca [HANDOFF.md](HANDOFF.md) — berisi status verifikasi per platform, apa yang belum teruji, dan jebakan yang sudah pernah kena.

## Setup development

```bash
flutter pub get

# Unduh ffmpeg + binary ncnn ke ./bin
#   Windows:
pwsh tools/fetch_binaries.ps1
#   macOS:
tools/fetch_binaries.sh

flutter run -d windows    # atau: flutter run -d macos
```

`bin/` sengaja tidak masuk git — isinya besar dan berlisensi terpisah.

### Di mana binary dicari

Berurutan:

1. `<folder exe>/bin/` — Windows
2. `<LabScale.app>/Contents/Resources/bin/` — macOS
3. folder yang sama dengan executable
4. `bin/` di root proyek (agar `flutter run` jalan tanpa bundling)
5. `PATH`

Panel **Setup & Status** di dalam app menunjukkan mana yang ketemu, dan punya tombol **Cek ulang** kalau Anda baru menaruh binary tanpa restart.

FFmpeg wajib ada. Real-ESRGAN dan RIFE opsional — tanpa keduanya, upscale tetap jalan lewat Lanczos dan 60 FPS tetap jalan lewat `minterpolate`.

## Build & bundle

### Windows

```powershell
pwsh tools/package_windows.ps1
```

Menghasilkan `dist/LabScale-<versi>-windows-x64.zip` berisi `labscale.exe`, DLL Flutter, dan `bin/`.

Butuh Visual Studio 2022 dengan workload **Desktop development with C++**.

### macOS

```bash
tools/package_macos.sh
```

Menghasilkan `dist/LabScale-<versi>-macos.dmg`.

Untuk distribusi ke Mac lain, set identitas signing dulu:

```bash
export SIGN_IDENTITY="Developer ID Application: Nama Anda (TEAMID)"

# Sekali saja — simpan kredensial notarisasi di keychain:
xcrun notarytool store-credentials labscale-notary \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
export NOTARY_PROFILE=labscale-notary

tools/package_macos.sh
```

Tanpa `SIGN_IDENTITY`, script tetap menghasilkan `.app` dan `.dmg` yang jalan di mesin Anda sendiri, hanya belum bisa didistribusikan tanpa peringatan Gatekeeper.

**Catatan App Sandbox:** LabScale menargetkan Developer ID, bukan Mac App Store. Sandbox sengaja dimatikan di `macos/Runner/*.entitlements` karena app men-spawn binary helper dan menulis ke `~/Documents/LabScale` — keduanya tidak mungkin di dalam sandbox tanpa security-scoped bookmark per file.

## Output

Hasil disimpan di `~/Documents/LabScale` (Windows: `%USERPROFILE%\Documents\LabScale`), dengan suffix yang menjelaskan operasi:

```
klip_esrgan-real-2x_sharp30_60fps.mp4
foto_lanczos-4x.png
```

## Struktur proyek

```text
lib/
  main.dart
  core/
    binaries.dart          # resolusi path tool eksternal
    ffmpeg_runner.dart     # preset codec, probe, filter, enkode
    esrgan_runner.dart     # realesrgan-ncnn-vulkan
    rife_runner.dart       # rife-ncnn-vulkan
    pipeline.dart          # orkestrasi stage + routing direct/frames
    job_log.dart           # stream log & progress
  models/
    process_options.dart   # opsi immutable + keputusan routing
    media_file.dart        # penemuan file & folder
  state/
    app_controller.dart    # state app, preferensi, eksekusi job
  ui/
    theme.dart  home_page.dart  widgets/

tools/
  fetch_binaries.ps1 / .sh    # unduh ffmpeg + ncnn ke bin/
  package_windows.ps1         # build + zip
  package_macos.sh            # build + sign + dmg + notarize

test/                         # unit test routing & filter chain
windows/  macos/              # runner native
```

## Test

```bash
flutter analyze
flutter test
```

## Troubleshooting

- **"FFmpeg tidak ditemukan"** — jalankan `tools/fetch_binaries.*`, atau install FFmpeg ke PATH.
- **Upscale AI abu-abu / gagal** — `realesrgan-ncnn-vulkan` belum ada di `bin/`. Cek panel Setup & Status.
- **Real-ESRGAN lambat pada video** — diproses per-frame; pakai untuk klip pendek atau pilih Lanczos.
- **Vulkan error di Windows** — update driver GPU; ncnn butuh driver Vulkan yang layak.
- **Gatekeeper menolak app di Mac** — build belum di-notarisasi. Lihat bagian Build & bundle.

## Lisensi

MIT. Binary yang diunduh `tools/fetch_binaries.*` punya lisensi masing-masing (FFmpeg: LGPL/GPL, Real-ESRGAN: BSD-3, RIFE ncnn: MIT).
