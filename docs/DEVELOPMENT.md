# LabScale — catatan development

Dokumen untuk yang membangun LabScale dari source. Untuk pengguna, lihat [README](../README.md) / [README.id](../README.id.md).

Upscale AI dan boost 60 FPS untuk foto & video — aplikasi desktop Flutter untuk **Windows dan macOS**. Semua pemrosesan berjalan **lokal**, tidak ada yang dikirim ke cloud, dan file asli tidak pernah diubah.

## Fitur

- **Upscale** — tiga pilihan yang diberi label menurut *peruntukannya*, bukan nama modelnya: Desain & ilustrasi (UltraMix Balanced), Foto (x4plus), dan Video (`realesr-general-x4v3`). Lanczos tanpa AI hanya muncul di komputer yang tidak bisa menjalankan AI. Skala 1×–4×.
- **Sharpness** — unsharp mask yang bisa diatur, diterapkan dalam satu pass bersama enkode.
- **Boost ke 60 FPS** — interpolasi frame lewat RIFE AI (di GPU) atau FFmpeg `minterpolate` (di CPU). Diukur di M1 (720p, 4 detik → 60 fps): jalur RIFE 15,4 detik, minterpolate 18,0 detik — RIFE bukan soal kecepatan.
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

**Model upscale: dibundel vs diunduh.** Yang ikut installer hanya bobot berlisensi bebas — daftarnya di [`tools/bundled_models.txt`](../tools/bundled_models.txt), dibaca kedua packager: x4plus dan `upscayl-lite-4x` (itu `realesr-general-x4v3` milik xinntao, BSD-3, dengan nama lain). UltraMix Balanced berlisensi **CC BY-NC-SA 4.0** — tidak boleh masuk installer berlisensi MIT, jadi app mengunduhnya sendiri saat dipilih ([`lib/core/model_store.dart`](../lib/core/model_store.dart)): dari satu commit Upscayl yang dikunci, diverifikasi sha256, ke folder per-user (`~/Library/Application Support/com.labby245.labscale/models` atau `%APPDATA%\…\models`). Di dropdown, model itu diberi label "unduh 33 MB" dan menampilkan kredit + catatan non-komersial. `--extra-models` / `-ExtraModels` tetap ada untuk menaruhnya di `bin/` saat development.

Diukur di M1 — gambar 1920×1280 dikecilkan 4× lalu di-upscale balik, dinilai terhadap aslinya. UltraSharp, Remacri, x4plus-anime, dan AnimeVideoV3 dihapus dari menu di 2.2.0:

| Model | Desain (SSIM) | Foto (rasio detail) | Detik |
|---|---|---|---|
| Ultramix Balanced | **0,9931** | **0,99×** | 6,6 |
| UltraSharp | 0,9875 | 1,05× | 6,4 |
| Remacri | 0,9871 | 1,59× | 6,6 |
| ESRGAN x4+ *(bawaan)* | 0,9827 | 0,93× | 6,5 |
| Upscayl Lite | 0,9784 | 0,72× | **0,7** |
| Lanczos | 0,9768 | 0,18× | 0,4 |

Rasio detail 1,00× berarti detail halus kembali sebanyak aslinya; di bawah itu buram, di atas itu mengarang.

Untuk 2.2.0 diuji lagi di M1 dengan dua sumber, masing-masing dikecilkan 4× lalu di-upscale balik: poster desain datar dan potongan 1920×1080 dari footage udara 4K asli. Detik = waktu Real-ESRGAN per gambar untuk footage (960×540 → 3840×2160):

| Model | SSIM poster | Detik per frame footage |
|---|---|---|
| UltraMix Balanced | **0,966** | 6,1 |
| x4plus | 0,949 | 6,3 |
| `realesr-general-x4v3` | 0,946 | **0,8** |
| AnimeVideoV3 | 0,938 | 0,6 |
| Lanczos | 0,955 | — |

Di footage, AnimeVideoV3 sama cepatnya dengan `realesr-general-x4v3`, tapi hasilnya tetap buram, nyaris seperti Lanczos. `realesr-general-x4v3` mengembalikan detail yang terlihat, jadi model itu yang jadi pilihan "Video". SSIM footage tidak dipakai sebagai penentu: Lanczos menang di angka itu karena tidak mengarang tekstur, padahal hasilnya paling buram.

**Kenapa 2× tidak lebih cepat dari 4×.** Semua model di menu hanya punya bobot 4×, jadi permintaan 2× dijalankan di 4× lalu diperkecil FFmpeg — waktu GPU dan ruang sementara sama seperti 4× penuh. Log menyebutkannya (`jaringan 4× lalu diperkecil`). Pada jalur video ini berarti frame sementara berukuran 4×, bukan 2×: klip 1080p panjang bisa memakan puluhan GB di folder temp. Kalau ruang sempit, proses per potongan.

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

Rilis resmi dibangun GitHub Actions, bukan dari laptop — lihat [Rilis](#rilis). Build lokal tetap bisa untuk mencoba.

### Windows

```powershell
pwsh tools/package_windows.ps1
```

Menghasilkan `dist/LabScale-Setup-<versi>.exe` (installer per-user tanpa UAC, kalau [Inno Setup](https://jrsoftware.org/isinfo.php) terpasang — `choco install innosetup`) dan `dist/LabScale-<versi>-windows-x64.zip` (portable). Keduanya membawa `LICENSE`, `THIRD_PARTY_NOTICES.md`, dan `licenses/`.

Butuh Visual Studio 2022 dengan workload **Desktop development with C++**. FFmpeg Windows dikunci ke build gyan.dev versi tertentu di `fetch_binaries.ps1` (bukan "latest") supaya source-nya bisa dicocokkan per rilis.

Script PowerShell-nya bisa diperiksa dari macOS juga — `brew install powershell` memberi `pwsh`, cukup untuk mem-parse dan menjalankan jalur unduhan model.

### macOS

```bash
tools/package_macos.sh
```

Menghasilkan `dist/LabScale-<versi>-macos.dmg`. **Hanya Apple Silicon, macOS 14+.**

Tiga hal yang dijaga script ini, semuanya pernah atau hampir bikin build yang jalan di Mac ini tapi mati di Mac lain:

- **ffmpeg Homebrew tidak statis.** `fetch_binaries.sh` menjalankan [`tools/bundle_ffmpeg_dylibs.sh`](../tools/bundle_ffmpeg_dylibs.sh): 17 dylib disalin ke `bin/`, load path ditulis ulang ke `@loader_path`, lalu dibuktikan dengan enkode sungguhan tanpa environment. Packager menolak ffmpeg yang masih menunjuk ke `/opt/homebrew`.
- **Bottle Homebrew mengikuti macOS mesinnya.** ffmpeg yang di-fetch di macOS 15 tidak jalan di 14. Packager membandingkan `minos` setiap binary dengan `LSMinimumSystemVersion` app (14.0) dan menolak kalau lebih baru. Build pribadi: `ALLOW_NEWER_TOOLS=1 tools/package_macos.sh`. Rilis dibangun di runner `macos-14`, jadi cocok.
- **Arsitektur.** ffmpeg-nya arm64, jadi app dibangun arm64 saja (`EXCLUDED_ARCHS` di `macos/Runner/Configs/Release.xcconfig`). Mac Intel mendapat pesan sistem "tidak didukung", bukan app yang terbuka lalu gagal di enkode pertama.

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

Tanpa `SIGN_IDENTITY`, semuanya ditandatangani **ad hoc** — cara rilis saat ini, sama seperti Fotolane. App jalan di Mac mana pun (Apple Silicon), tapi saat pertama dibuka pengguna perlu menyetujuinya sekali di **System Settings → Privacy & Security → Open Anyway** (README menjelaskannya). Tidak menandatangani sama sekali bukan pilihan: menyalin `bin/` ke bundle merusak segel Xcode, dan app hasil unduhan dengan segel rusak dilaporkan "damaged" tanpa jalan keluar. Developer ID ($99/tahun) menghilangkan langkah persetujuan itu.

**Catatan App Sandbox:** LabScale menargetkan Developer ID, bukan Mac App Store. Sandbox sengaja dimatikan di `macos/Runner/*.entitlements` karena app men-spawn binary helper dan menulis ke `~/LabScale` — keduanya tidak mungkin di dalam sandbox tanpa security-scoped bookmark per file.

## Rilis

1. Naikkan `version:` di `pubspec.yaml`, tulis [`docs/release-notes.md`](release-notes.md), lalu perbarui [`labstory-product.json`](../labstory-product.json): `version`, `releasedAt`, dan entri `changelog` baru paling atas (teks biasa, Bahasa Indonesia, sapaan "kamu", maksimal 5 rilis). File ini dibaca apps.labstory.id tiap 10 menit untuk bagian "Spesifikasi" dan "Yang baru" di halaman produk, tanpa deploy situs. Formatnya ada di `labstory-platform/docs/API_CONTRACT.md` §11, dan `test/labstory_product_test.dart` gagal kalau versinya tidak sama dengan pubspec. Kalau spesifikasi berubah, ubah juga di sini. Teks pemasaran, FAQ, dan gambar tetap lewat sesi labstory-platform.
2. `flutter analyze && flutter test` di Mac yang punya `bin/` lengkap (test ncnn hanya jalan di sana; CI ubuntu melewatinya).
3. `git tag v<versi> && git push origin v<versi>`.
4. Workflow [Release](../.github/workflows/release.yml) membangun `.dmg` (macos-14), installer + zip Windows, `ffmpeg-sources-<versi>.tar`, dan `SHA256SUMS.txt`, lalu menaruhnya di **draft** release.
5. Periksa draft-nya, lalu **Publish**. Pemeriksaan update di app ([`lib/core/update_check.dart`](../lib/core/update_check.dart)) membaca `releases/latest` lewat GitHub API — hanya rilis yang sudah dipublikasikan yang terlihat.

**Kewajiban GPL.** FFmpeg yang dibundel adalah build GPL-3.0 (ada x264/x265), jadi setiap rilis wajib menyertakan source versi yang persis sama. [`tools/collect_gpl_sources.sh`](../tools/collect_gpl_sources.sh) mengumpulkannya: tarball ffmpeg untuk kedua platform + x264/x265 sesuai formula Homebrew, plus `BUILD-INFO.txt`. Script menolak jalan kalau versi Homebrew terpasang berbeda dari formula, karena source yang dilampirkan harus cocok dengan binary-nya.

## Output

Folder default `~/LabScale` (Windows: `%USERPROFILE%\LabScale`) — sengaja bukan Documents, yang di banyak PC dialihkan ke OneDrive dan di Mac bisa tersinkron ke iCloud, sehingga hasil video berukuran besar ikut terunggah diam-diam. Sebelum 2.1.2 default-nya Documents\LabScale. Bisa diganti lewat **Folder Output** di kartu Operasi — pilihannya diingat antar sesi, dan kembali ke default kalau folder itu hilang saat app dibuka lagi.

File yang dipilih satu-satu mendarat langsung di folder output. **Folder yang di-drop hasilnya dikumpulkan** ke `<nama folder>_upscaled` di dalamnya, apa pun struktur di dalam folder aslinya:

```
~/LabScale/
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
    binaries.dart          # resolusi path tool eksternal + folder model per-user
    ffmpeg_runner.dart     # preset codec, probe, filter, enkode
    esrgan_runner.dart     # realesrgan-ncnn-vulkan
    rife_runner.dart       # rife-ncnn-vulkan
    pipeline.dart          # orkestrasi stage + routing direct/frames
    job_log.dart           # stream log & progress + pembatalan (kill tool)
    disk_space.dart        # perkiraan ruang frame sementara vs ruang kosong
    model_store.dart       # unduh model CC BY-NC-SA, terverifikasi sha256
    update_check.dart      # cek rilis terbaru di GitHub
    app_log.dart           # log persisten untuk laporan bug
    app_links.dart         # URL repo, rilis, issue
  l10n/
    strings.dart           # semua teks, Indonesia + Inggris
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
  bundle_ffmpeg_dylibs.sh     # jadikan ffmpeg Homebrew mandiri
  bundled_models.txt          # bobot yang boleh masuk installer
  package_windows.ps1         # build + installer Inno Setup + zip
  windows/labscale.iss        # skrip installer
  package_macos.sh            # build + sign + dmg (+ notarize)
  collect_gpl_sources.sh      # source FFmpeg/x264/x265 untuk tiap rilis

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
- **Real-ESRGAN lambat pada video** — diproses per-frame; pakai untuk klip pendek atau pilih "Video", yang sekitar 8× lebih cepat dari "Foto".
- **Vulkan error di Windows** — update driver GPU; ncnn butuh driver Vulkan yang layak.
- **Gatekeeper menolak app di Mac** — build ad hoc, belum di-notarisasi. Setujui sekali di System Settings → Privacy & Security → Open Anyway.
- **"Ruang disk tidak cukup"** — jalur frame memerlukan ruang sementara besar; perkiraannya ada di log. Lihat `lib/core/disk_space.dart`.
- **Log untuk laporan bug** — Tentang LabScale (ikon ⓘ) → Buka folder log; berkasnya `labscale.log`.

## Lisensi

Kode LabScale: MIT ([LICENSE](../LICENSE)). Tool dan model yang dibundel punya lisensi masing-masing — rinciannya di [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), teks lengkapnya di [`licenses/`](../licenses).
