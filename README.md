# LabScale

Upscale AI dan boost 60 FPS untuk foto & video — aplikasi desktop Flutter untuk **Windows dan macOS**. Semua pemrosesan berjalan **lokal**, tidak ada yang dikirim ke cloud, dan file asli tidak pernah diubah.

## Fitur

- **Upscale** — Real-ESRGAN (foto / anime / video anime) atau Lanczos untuk hasil cepat tanpa AI. Skala 1×–4×.
- **Sharpness** — unsharp mask yang bisa diatur, diterapkan dalam satu pass bersama enkode.
- **Boost ke 60 FPS** — motion interpolation via RIFE AI (5–10× lebih cepat dan jauh lebih halus) atau FFmpeg `minterpolate`.
- **Batch / folder** — drop satu folder, semua media di dalamnya diproses berurutan, dan hasilnya dikumpulkan ke satu folder `<nama folder>_upscaled` di dalam folder output. Semuanya muncul sebagai grid thumbnail, dan saat batch jalan file yang sedang dikerjakan memakai progress bar di atas gambarnya sendiri — tidak perlu membaca log untuk tahu sudah sampai mana.
- **Bandingkan sebelum/sesudah** — klik foto mana pun untuk membukanya di viewer **setinggi jendela penuh**, dengan pembatas yang bisa digeser kiri-kanan. Panah ←/→ berpindah antar file, Esc menutup. Untuk video, yang dibandingkan satu frame, dan tombol **Putar** memutar hasilnya.
- **Kualitas & codec** — Fast → Ultra (lossless), H.264 / HEVC / AV1, dengan NVENC (Windows) atau VideoToolbox (macOS) otomatis bila tersedia.
- **Audio dipertahankan** — audio AAC di-copy apa adanya, format lain di-transcode ke AAC 192k.

## Arsitektur

LabScale adalah aplikasi Flutter murni. Tidak ada runtime Python, tidak ada server lokal. Dart mengorkestrasi tiga binary CLI:

| Tool | Peran | GPU |
|---|---|---|
| `ffmpeg` / `ffprobe` | probe, ekstrak frame, filter, enkode | NVENC / VideoToolbox |
| `realesrgan-ncnn-vulkan` | upscale AI | Vulkan (Win) / Metal via MoltenVK (Mac) |
| `rife-ncnn-vulkan` | interpolasi frame AI (RIFE v4.25) | Vulkan / Metal |

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

**RIFE v4.25 (opsional).** Default-nya v4.6 dari rilis nihui 2022, karena unduhannya ringan. Untuk model yang jauh lebih baik, tambahkan `--rife-latest` (bash) atau `-RifeLatest` (PowerShell). Harganya unduhan ~790 MB: **setiap model RIFE setelah v4.6 butuh build ncnn yang lebih baru** — binary lama menolak semuanya dengan `layer MemoryData not exists or registered` — dan satu-satunya build yang dipublikasikan ada di dalam satu arsip berisi ~50 model. Hanya yang diperlukan yang disimpan.

Diukur di M1, 24 frame 1920×1080: v4.6 4,5 detik, v4.25 6,0 detik. Binary barunya tidak menurunkan performa model lama (4,4 detik).

### Di mana binary dicari

Berurutan:

1. `<folder exe>/bin/` — Windows
2. `<LabScale.app>/Contents/Resources/bin/` — macOS
3. folder yang sama dengan executable
4. `bin/` di root proyek (agar `flutter run` jalan tanpa bundling)
5. `PATH`

Status bar di dasar jendela menunjukkan sekilas mana yang ketemu (satu titik per tool). Tombol **Setup & Status** di sebelah kanannya membuka rincian lengkap beserta **Cek ulang**, kalau Anda baru menaruh binary tanpa restart.

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

Butuh **Xcode lengkap** (Command Line Tools saja tidak cukup) dan **CocoaPods** — media_kit punya podspec:

```bash
brew install cocoapods
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

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

Folder default `~/Documents/LabScale` (Windows: `%USERPROFILE%\Documents\LabScale`), bisa diganti lewat **Folder Output** di kartu Operasi — pilihannya diingat antar sesi, dan kembali ke default kalau folder itu hilang saat app dibuka lagi.

File yang dipilih satu-satu mendarat langsung di folder output. **Folder yang di-drop hasilnya dikumpulkan** ke `<nama folder>_upscaled` di dalamnya, apa pun struktur di dalam folder aslinya:

```
~/Documents/LabScale/
  foto_lanczos-4x.png                    ← file yang dipilih sendiri
  Foto Liburan_upscaled/                 ← dari folder "Foto Liburan"
    pantai_esrgan-real-4x.png
    sunset_esrgan-real-4x.png
```

Nama file membawa suffix yang menjelaskan operasinya:

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
  core/
    thumbnailer.dart       # poster frame lewat FFmpeg untuk grid & pembanding
  ui/
    theme.dart  home_page.dart
    widgets/
      file_stage.dart      # drop zone yang berubah jadi grid
      file_grid.dart       # tile + status per file
      media_stage.dart     # panggung gambar/video/pembanding
      compare_slider.dart  # pembatas sebelum/sesudah
      ops_card.dart  log_card.dart  setup_panel.dart  ...
    compare_view.dart      # viewer setinggi jendela penuh

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
- **Upscale AI abu-abu / gagal** — `realesrgan-ncnn-vulkan` belum ada di `bin/`. Cek Setup & Status di status bar.
- **Real-ESRGAN lambat pada video** — diproses per-frame; pakai untuk klip pendek atau pilih Lanczos.
- **Vulkan error di Windows** — update driver GPU; ncnn butuh driver Vulkan yang layak.
- **Gatekeeper menolak app di Mac** — build belum di-notarisasi. Lihat bagian Build & bundle.

## Lisensi

MIT. Binary yang diunduh `tools/fetch_binaries.*` punya lisensi masing-masing (FFmpeg: LGPL/GPL, Real-ESRGAN: BSD-3, RIFE ncnn: MIT).
