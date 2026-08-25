# Handoff — lanjut di macOS

Catatan serah-terima dari sesi migrasi Flask/Python → Flutter (25 Agustus 2026). Semua pekerjaan di bawah ini dikerjakan dan diverifikasi **di Windows saja**. Bagian macOS ditulis tapi belum pernah dieksekusi.

## Di mana posisinya sekarang

Tiga commit di `main`, sudah di-push ke `labby245/lab-scale`:

| Commit | Isi |
|---|---|
| `db112c2` | Hapus fitur watermark / background / auto-detect, rebrand ke LabScale |
| `56fc982` | Migrasi stack ke Flutter desktop (Windows + macOS) |
| `d586106` | Perbaikan temuan code review — blocker build + 8 bug perilaku |

**Status terverifikasi di Windows:** `flutter analyze` bersih · 38 test lolos · clone bersih build sampai `.exe` · app jalan · `dist/LabScale-2.0.0-windows-x64.zip` (157 MB).

## Mulai di Mac

```bash
git clone https://github.com/labby245/lab-scale
cd lab-scale

# Flutter 3.47.1 / Dart 3.13.1 — versi yang dipakai di Windows.
# Di Mac install normal (brew install --cask flutter atau dari docs.flutter.dev).
flutter --version

flutter pub get
tools/fetch_binaries.sh      # unduh ffmpeg + ncnn ke ./bin (gitignored)
flutter run -d macos
```

`bin/` tidak ada di git — isinya besar dan berlisensi terpisah, jadi harus di-fetch di tiap mesin.

## Yang BELUM pernah diuji di macOS

Ini bagian yang perlu perhatian Anda, bukan sekadar "tinggal jalan":

1. **`tools/package_macos.sh` belum pernah dieksekusi.** Ditulis berdasarkan alur codesign/notarize standar, tapi nol kali dijalankan. Harapkan ada yang perlu disetel.
2. **Entitlements** — App Sandbox sengaja **dimatikan** di `macos/Runner/{Release,DebugProfile}.entitlements`. Alasannya ada di komentar file itu: app men-spawn binary helper (`ffmpeg`, `realesrgan-ncnn-vulkan`, `rife-ncnn-vulkan`) dan menulis ke `~/Documents/LabScale` — dua hal yang mustahil di dalam sandbox tanpa security-scoped bookmark per file. Target distribusi Developer ID, bukan Mac App Store. Kalau nanti Anda mau masuk App Store, ini harus dirombak total.
3. **media_kit / libmpv** — dipakai untuk preview video. `com.apple.security.cs.disable-library-validation` sudah diaktifkan karena dylib-nya bertanda tangan berbeda dari app. Belum diuji apakah cukup saat notarisasi.
4. **Real-ESRGAN & RIFE via MoltenVK** — di Windows keduanya jalan di Vulkan dan sudah terbukti (test integrasi lolos). Di Mac jalurnya lewat MoltenVK/Metal; secara teori sama, praktiknya belum dicek.
5. **VideoToolbox** — `FfmpegRunner.selectEncoder` sudah punya cabang `h264_videotoolbox` / `hevc_videotoolbox` beserta preset kualitasnya, tapi cabang itu belum pernah dieksekusi.

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

Dua hal ini ditemukan dengan cara yang mahal, jadi tercatat di sini:

- **`ffmpeg -encoders` berbohong.** Encoder terdaftar ≠ encoder bisa dipakai. Di mesin Windows ini `h264_nvenc` terdaftar tapi driver NVIDIA-nya terlalu tua (nvenc API 13.0 < 13.1), dan **setiap video gagal** dengan `exit -40`. `FfmpegRunner.encoders()` sekarang trial-encode satu frame per hardware encoder sebelum mempercayainya. Jangan pernah kembali ke pengecekan berbasis daftar.
- **Pattern `.gitignore` tanpa anchor.** `models/` (untuk sisa YOLO) diam-diam ikut menelan `lib/models/`, sehingga dua file inti tidak ter-commit dan clone bersih tidak bisa di-build. Semua pattern folder proyek sekarang di-anchor `/…/`. **Kalau menambah entry folder baru, anchor ke root**, dan verifikasi dengan clone bersih — bukan dengan working tree.

Pelajaran umum dari yang kedua: `flutter analyze` + `flutter test` + `flutter build` di working tree **tidak** membuktikan repo bisa dibangun orang lain. Sebelum rilis, `git clone` ke folder kosong lalu build dari situ.

## Sisa pekerjaan

| Item | Catatan |
|---|---|
| Ikon aplikasi | Masih ikon default Flutter di kedua platform. Butuh `.icns` (macOS) + `.ico` (Windows). |
| Uji macOS end-to-end | Jalankan `flutter test` di Mac — 38 test yang sama harusnya lolos; jalur ncnn lewat Metal yang perlu dibuktikan. |
| Rilis | Belum ada tag maupun GitHub Release. `dist/` gitignored. |

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
