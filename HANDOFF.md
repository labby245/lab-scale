# Handoff — lanjut di macOS

Catatan serah-terima dari sesi migrasi Flask/Python → Flutter (25 Agustus 2026), dilanjutkan di macOS pada hari yang sama.

**Status per sesi macOS (MacBook Apple M1, macOS 15.7.7, arm64):** jalur macOS kini terverifikasi ujung ke ujung — analyze, 38 test, GPU lewat Metal, build release, `.app` yang jalan, dan `.dmg`. Yang belum: signing dengan Developer ID sungguhan dan notarisasi.

## Di mana posisinya sekarang

Tiga commit di `main`, sudah di-push ke `labby245/lab-scale`:

| Commit | Isi |
|---|---|
| `db112c2` | Hapus fitur watermark / background / auto-detect, rebrand ke LabScale |
| `56fc982` | Migrasi stack ke Flutter desktop (Windows + macOS) |
| `d586106` | Perbaikan temuan code review — blocker build + 8 bug perilaku |

**Status terverifikasi di Windows:** `flutter analyze` bersih · 38 test lolos · clone bersih build sampai `.exe` · app jalan · `dist/LabScale-2.0.0-windows-x64.zip` (157 MB).

## Mulai di Mac

Sudah dikerjakan di mesin ini; ditulis ulang di sini untuk mesin berikutnya.

```bash
brew install --cask flutter    # cask-nya tepat 3.47.1 / Dart 3.13.1 — sama dengan Windows
brew install cocoapods         # wajib: media_kit punya podspec
flutter pub get
tools/fetch_binaries.sh        # unduh ffmpeg + ncnn ke ./bin (gitignored)
flutter test                   # 38 test — tidak butuh Xcode
flutter run -d macos           # butuh Xcode lengkap
```

`bin/` tidak ada di git — isinya besar dan berlisensi terpisah, jadi harus di-fetch di tiap mesin.

### Xcode lengkap masih wajib

`flutter build macos`, `flutter run -d macos`, dan `tools/package_macos.sh` memanggil `xcodebuild`. Command Line Tools saja tidak cukup:

```bash
# install Xcode dari App Store, lalu:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Sampai itu dilakukan, `flutter doctor` akan terus melaporkan *"Xcode installation is incomplete"* dan semua jalur build macOS tertahan.

## Status pengujian macOS

Yang **sudah terbukti** di M1 (sesi 25 Agustus, semuanya dijalankan sungguhan):

| Hal | Bukti |
|---|---|
| `flutter analyze` | bersih |
| `flutter test` | 38/38 lolos — angka yang sama dengan Windows |
| Real-ESRGAN via MoltenVK | ncnn memilih `[0 Apple M1]`, upscale 320×180 → 2× berhasil |
| RIFE via MoltenVK | 4 frame → 8 frame, model `rife-v4.6` |
| Jalur ncnn di dalam pipeline | test integrasi "Real-ESRGAN frame path" & "RIFE frame path" lolos — bukan sekadar binary polos |
| VideoToolbox | `h264_videotoolbox` & `hevc_videotoolbox` lolos trial-probe **dan** enkode nyata; preset `-q:v` menskala benar (45 → 134 KB, 90 → 745 KB pada klip 640×360 2 detik) |
| Arsitektur binary | ffmpeg/ffprobe arm64 native (dari Homebrew); kedua binary ncnn universal (x86_64 + arm64) — tidak ada yang lewat Rosetta |

Ditambah, setelah Xcode 26.3 terpasang:

| Hal | Bukti |
|---|---|
| `flutter build macos --release` | `LabScale.app` 92,9 MB terbangun |
| `tools/package_macos.sh` | **jalan tuntas pada percobaan pertama**, exit 0 → `dist/LabScale-2.0.0-macos.dmg` (108 MB) |
| App berjalan | UI render benar, dua kolom, RSS 114 MB |
| Resolusi binary di dalam bundle | ketiga titik status hijau di build release — app menemukan `Contents/Resources/bin`, bukan PATH |
| Ikon | terkompilasi ke `Assets.car` (1,1 MB) dan tampil di Dock |
| Mekanika blok signing | dilatih dengan signature ad-hoc di salinan bundle: 23 framework + 4 helper CLI tertandatangani inside-out, `codesign --verify --deep --strict` → *valid on disk*, *satisfies its Designated Requirement*, entitlements hanya menempel di bundle app |

Yang **masih belum teruji**:

1. **Signing dengan Developer ID sungguhan.** Yang dilatih baru ad-hoc (`--sign -`), tanpa `--timestamp` — ad-hoc memang menolak timestamp. Jadi urutan dan enumerasinya terbukti, sertifikat dan timestamp-nya belum.
2. **Notarisasi.** Belum pernah dikirim ke Apple. Ini juga satu-satunya cara membuktikan poin berikutnya.
3. **media_kit / libmpv saat notarisasi** — `com.apple.security.cs.disable-library-validation` sudah diaktifkan karena dylib-nya bertanda tangan berbeda dari app. Bundle-nya membawa 23 framework (Mpv, Avcodec, Avfilter, dst.), jadi ini bagian yang paling mungkin rewel.
4. **Entitlements** — App Sandbox sengaja **dimatikan** di `macos/Runner/{Release,DebugProfile}.entitlements`. Alasannya ada di komentar file itu: app men-spawn binary helper dan menulis ke `~/Documents/LabScale` — dua hal yang mustahil di dalam sandbox tanpa security-scoped bookmark per file. Target distribusi Developer ID, bukan Mac App Store. Kalau nanti mau masuk App Store, ini harus dirombak total.

### Signing & notarisasi

```bash
export SIGN_IDENTITY="Developer ID Application: Nama Anda (TEAMID)"

# sekali saja
xcrun notarytool store-credentials labscale-notary \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW
export NOTARY_PROFILE=labscale-notary

tools/package_macos.sh
```

Tanpa `SIGN_IDENTITY` script tetap menghasilkan `.app` + `.dmg` yang jalan di mesin Anda sendiri, hanya belum bisa didistribusikan.

## Jebakan yang sudah kena sekali — jangan terulang

Keempat hal ini ditemukan dengan cara yang mahal, jadi tercatat di sini:

- **`ffmpeg -encoders` berbohong.** Encoder terdaftar ≠ encoder bisa dipakai. Di mesin Windows ini `h264_nvenc` terdaftar tapi driver NVIDIA-nya terlalu tua (nvenc API 13.0 < 13.1), dan **setiap video gagal** dengan `exit -40`. `FfmpegRunner.encoders()` sekarang trial-encode satu frame per hardware encoder sebelum mempercayainya. Jangan pernah kembali ke pengecekan berbasis daftar.
- **Pattern `.gitignore` tanpa anchor.** `models/` (untuk sisa YOLO) diam-diam ikut menelan `lib/models/`, sehingga dua file inti tidak ter-commit dan clone bersih tidak bisa di-build. Semua pattern folder proyek sekarang di-anchor `/…/`. **Kalau menambah entry folder baru, anchor ke root**, dan verifikasi dengan clone bersih — bukan dengan working tree.

- **Fungsi bash yang "mengembalikan" path lewat stdout.** `fetch_zip()` di `tools/fetch_binaries.sh` mencetak baris progres *dan* path hasil ke stdout yang sama, jadi `d="$(fetch_zip ...)"` menangkap keduanya dan `find` menerima argumen sampah — script mati di langkah Real-ESRGAN. Ini kena begitu script itu pertama kali dijalankan di macOS. Progres sekarang diarahkan ke stderr. **Di bash, stdout sebuah fungsi adalah nilai baliknya — semua pesan untuk manusia harus ke stderr.**

- **Restorasi jendela otomatis Cocoa membatalkan ukuran default, diam-diam.** `MainFlutterWindow` tidak pernah menyetel ukuran, jadi macOS memakai default `.xib` 800×600 — di bawah breakpoint dua-kolom 1040pt, sehingga app **selalu** terbuka dalam mode satu kolom yang harus di-scroll, sementara Windows sudah lama membuka di 1360×900. Yang bikin lama: `setContentSize` dipanggil, tidak error, dan tetap tidak berpengaruh — `contentMinSize` di baris sebelahnya jelas berlaku, jadi jelas kodenya jalan. Penyebabnya restorasi jendela otomatis yang memasang frame lama **setelah** `awakeFromNib` selesai. Memindahkan kode ke sesudah `super.awakeFromNib()` tidak menolong. Yang menolong: `isRestorable = false` lalu mengelola frame sendiri lewat `setFrameUsingName` / `setFrameAutosaveName`, sehingga ukuran default hanya berlaku saat belum ada frame tersimpan dan resize pengguna tetap diingat. **Kalau ukuran jendela yang Anda setel tidak berpengaruh di macOS, curigai restorasi lebih dulu — bukan kode Anda.**

Pelajaran umum dari jebakan kedua: `flutter analyze` + `flutter test` + `flutter build` di working tree **tidak** membuktikan repo bisa dibangun orang lain. Sebelum rilis, `git clone` ke folder kosong lalu build dari situ. Pelajaran dari yang ketiga sejalur: script yang belum pernah dieksekusi belum bisa disebut ada.

## Sisa pekerjaan

| Item | Catatan |
|---|---|
| Signing + notarisasi | Butuh sertifikat Developer ID. Semua langkah lain sudah terbukti. |
| Script PowerShell | ~~belum diverifikasi~~ — `brew install powershell` memberi `pwsh` di macOS. Keduanya di-parse bersih, dan `fetch_binaries.ps1 -ExtraModels` dijalankan sungguhan sampai keempat model terunduh. |
| Uji interaksi manual | Drag & drop, batch berjalan, viewer, dan slider pembanding belum pernah disentuh tangan manusia. Grid terverifikasi lewat tangkapan layar app sungguhan; sisanya lewat 22 widget test. Klik sintetis berhenti bekerja di mesin ini di tengah sesi — gejala *secure input* — jadi otomasi GUI bukan jalan yang bisa diandalkan di sini. |
| Ikon Windows | `.ico` sudah diganti tapi belum di-build ulang di Windows. |
| Rilis | Belum ada tag maupun GitHub Release. `dist/` gitignored. |

~~Uji macOS end-to-end~~ — selesai, lihat tabel "Status pengujian macOS" di atas.

### Ikon aplikasi

Sumbernya master 1024×1024 dari `~/Downloads/Logo LabScale` — huruf "Ls" biru di latar navy dengan panah diagonal sebagai motif upscale.

- **macOS** — 7 PNG (16–1024) disalin ke `macos/Runner/Assets.xcassets/AppIcon.appiconset/`. `Contents.json` bawaan Flutter sudah menunjuk nama file yang sama persis, jadi tidak diubah.
- **Windows** — `windows/runner/resources/app_icon.ico` dibangun ulang dari master, 7 ukuran (16/24/32/48/64/128/256), naik dari 3 ukuran milik ikon default.

Dua catatan:

1. PNG per-ukuran yang disediakan ternyata murni downscale dari master (RMSE 0,001–0,003 terhadap Lanczos-downscale), jadi `.ico` dibangun dari master saja — tidak ada tuning per-ukuran yang hilang.
2. `.ico`-nya 364 KB karena ImageMagick di mesin ini selalu menulis entri sebagai BMP, bukan PNG. Berfungsi normal di Windows, hanya lebih besar dari perlunya. Kalau mau ramping, bangun ulang `.ico` di Windows.

Ikon macOS sudah terbukti: masuk `Assets.car` dan tampil di Dock. Ikon Windows belum di-build ulang sejak diganti.

## Model AI

**Upscale.** Binary `realesrgan-ncnn-vulkan` memuat model apa pun berarsitektur ESRGAN dari folder `models/` lewat `-n <nama>`, jadi model komunitas bisa dijatuhkan begitu saja. Yang menghalangi hanya `UpscaleModel` di `lib/models/process_options.dart` yang masih enum hardcoded.

Diukur di M1 dengan metode turun-4×-lalu-naik-4× dibanding aslinya (SSIM + rasio detail terhadap asli):

| Model | desain SSIM | foto: rasio detail | detik |
|---|---|---|---|
| ultramix-balanced-4x | **0,9931** | **0,99×** | 6,6 |
| ultrasharp-4x | 0,9875 | 1,05× | 6,4 |
| remacri-4x | 0,9871 | 1,59× | 6,6 |
| realesrgan-x4plus *(default)* | 0,9827 | 0,93× | 6,5 |
| upscayl-lite-4x | 0,9784 | 0,72× | **0,7** |
| high-fidelity-4x | 0,9769 | 0,39× | 6,5 |
| Lanczos | 0,9768 | 0,18× | 0,4 |

Hati-hati membaca SSIM pada foto: di sana Lanczos justru tertinggi karena membuang detail sehingga tidak pernah salah menebak, sementara model GAN dihukum karena mengarang detail. Untuk foto, rasio detail mendekati 1,00× yang berarti.

`upscayl-standard-4x` dan `digital-art-4x` milik Upscayl **byte-identical** dengan `realesrgan-x4plus` dan `realesrgan-x4plus-anime` — hanya ganti nama. Lisensi tiap model komunitas perlu ditelusuri sebelum dibundel; Upscayl sendiri AGPL-3.0 sementara LabScale MIT.

**RIFE.** Lihat catatan `--rife-latest` di README. Intinya: model dan binary terikat berpasangan, tidak bisa salah satu saja.

## Alur UI

Bentuknya menyusul FreeScaler dalam dua hal yang diminta: **satu area besar yang sekaligus drop zone dan galeri**, dan **progress per file di atas gambarnya**.

- `FileStage` (`lib/ui/widgets/file_stage.dart`) adalah kolom kiri. Kosong ia jadi undangan drop; terisi, rectangle yang sama berubah jadi grid. Drop target-nya membungkus seluruh kartu, jadi menjatuhkan file ke grid yang sudah terisi tetap bekerja. Ini menggantikan kartu "Pilih File" lama yang jadi mati begitu tugasnya selesai.
- `FileGrid` memberi tiap file satu tile dengan poster, nama, ukuran, dan statusnya. Saat batch jalan, tile yang tidak sedang dikerjakan meredup ke opacity 0,45 dan tile aktif memakai overlay progress + persentase. Bar-nya *indeterminate* selama tahap yang tidak melaporkan progres (ekstraksi frame), lalu jadi terukur.
- `CompareView` (`lib/ui/compare_view.dart`) adalah viewer setinggi jendela penuh, dibuka dengan mengklik tile. Sempat ada panel preview inline di dalam workspace, tapi bentuk kolomnya membatasi tingginya ke beberapa ratus piksel — terlalu kecil untuk menilai hasil upscale, yang justru satu-satunya alasan pembanding itu ada. Sekarang grid memegang seluruh kolom dan perbandingan memakai seluruh jendela (tombol hijau macOS bikin satu layar penuh). ←/→ berpindah antar file dan membungkus di ujung, Esc menutup.
- `MediaStage` dipisah dari kartu mana pun supaya viewer dan (kalau nanti dibutuhkan lagi) panel apa pun bisa menampilkan hal yang sama pada ukuran berbeda. Ia yang memegang state pemutar media_kit dan pilihan Banding/Putar.
- `CompareSlider` menempatkan hasil di atas aslinya dan meng-clip sisi "sebelum" ke kiri pembatas. Keduanya digambar `BoxFit.contain` di kotak yang sama, dan karena upscale mempertahankan rasio aspek, keduanya jatuh tepat bertindihan — jadi apa pun yang bergerak saat digeser adalah perbedaan nyata, bukan artefak layout.
- Poster dibuat `Thumbnailer` lewat FFmpeg, bukan decoder Flutter. Mahal satu subprocess per file, tapi TIFF jadi ikut jalan (Flutter tidak bisa mendekodenya sama sekali), sumber 6000px tidak pernah didekode penuh hanya untuk mengisi tile 170px, dan video serta foto lewat jalur yang sama.

Status per file diturunkan dari panjang `_results`: hasil ditambahkan berurutan, jadi sebuah file punya hasil persis ketika indeksnya di bawah jumlah yang sudah terkumpul. Tidak ada state per-tile yang perlu dijaga sinkron.

## Layout satu layar

Workspace-nya dirancang muat dalam satu jendela tanpa scroll halaman:

- `_WideWorkspace` (≥ 1040pt) — dua kolom setinggi jendela. Preview memakai `expand: true` sehingga menyerap sisa tinggi; hanya kolom kontrol yang punya scrollbar sendiri, karena hanya ia yang bisa tumbuh (Real-ESRGAN dan RIFE sama-sama memekar saat dinyalakan).
- `_NarrowWorkspace` (< 1040pt) — kembali bertumpuk dan seluruh halaman men-scroll. `contentMinSize` 940×640 sengaja di bawah breakpoint, jadi jendela terkecil memang mendarat di mode ini.
- Panel Setup & Status yang dulu kartu selebar halaman kini jadi status bar tipis yang selalu terlihat, dengan rincian pindah ke dialog. Kartu lamanya yang mendorong halaman melewati satu layar demi panel yang cuma dilirik sekali.

`FileGrid(expand: true)` dan `FileStage(expand: true)` memakai `Expanded`, jadi **hanya aman di parent yang tingginya terbatas**. Jalur `_NarrowWorkspace` yang men-scroll memakai varian shrink-wrap-nya.

## Sisa di disk mesin Windows

Sudah gitignored, aman dihapus manual kapan saja — tidak disentuh:
`.venv/`, `labels/`, `uploads/`, `outputs/`, `temp/`, dan ~430 MB varian model RIFE lawas di `bin/` (hanya `rife-v4.6` yang dipakai; packager memang cuma menyalin yang terpakai).

## Orientasi cepat ke kode

```
lib/models/process_options.dart   ← mulai dari sini: opsi immutable +
                                     SEMUA keputusan routing (needsFrames,
                                     useRife, useEsrgan, effectiveSharpness)
lib/core/pipeline.dart            ← orkestrasi: direct vs frames path
lib/core/ffmpeg_runner.dart       ← preset codec, probe, filter chain, enkode
lib/core/binaries.dart            ← urutan pencarian tool eksternal
lib/state/app_controller.dart     ← state UI, preferensi, eksekusi job
```

Aturan yang dipegang pipeline: **RIFE hilang → fallback ke minterpolate** (dijanjikan README dan UI), tapi **Real-ESRGAN hilang → gagal dengan pesan jelas**, tidak diam-diam turun ke Lanczos — hasilnya akan beda jauh dari yang diminta user.
