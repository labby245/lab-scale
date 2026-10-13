<div align="center">

<img src="assets/logo.png" width="96" alt="LabScale">

# LabScale

**Upscale AI dan boost 60 FPS untuk foto & video** — oleh Labstory Studio

Gratis · open source · semuanya diproses di komputermu sendiri

macOS (Apple Silicon) · Windows

[Unduh](https://github.com/labby245/lab-scale/releases/latest) ·
[Read in English](README.md) ·
[Instagram @labstory.studio](https://www.instagram.com/labstory.studio/)

</div>

---

LabScale membuat foto dan video yang kecil atau buram jadi lebih besar dan
tajam dengan AI, dan membuat video yang patah-patah jadi mulus. Masukkan satu
file atau satu folder, pilih yang kamu mau, tekan **Proses**.

## Kenapa LabScale

- 🆓 **Gratis selamanya** — tanpa akun, tanpa watermark, tanpa batas jumlah
  file.
- 🔒 **Privat** — semuanya diproses di komputermu. Tidak ada yang diunggah,
  dan file aslimu tidak pernah diubah.
- 🎬 **Foto *dan* video** — perbesar sampai 4×, dan ubah video patah-patah
  jadi mulus 60 FPS.
- 📁 **Sekali banyak** — masukkan satu folder, lalu bandingkan sebelum dan
  sesudahnya berdampingan.

## Fiturnya

- **Upscale 1×–4×.** Kamu memilih menurut jenis gambarnya: foto, desain atau
  ilustrasi, anime, atau video anime. Ada juga mode draf cepat dan pilihan
  biasa tanpa AI.
- **Video mulus 60 FPS**, dengan membuat frame-frame di antaranya.
- **Satu folder sekaligus.** Setiap file tampil sebagai thumbnail, dan file
  yang sedang dikerjakan punya progress bar sendiri. Hasil dari satu folder
  dikumpulkan di folder `<nama folder>_upscaled`.
- **Bandingkan sebelum / sesudah.** Klik file mana saja untuk membandingkan
  asli dan hasilnya selebar jendela, dengan pembatas yang bisa digeser.
  ←/→ untuk pindah file.
- **Bisa dibatalkan kapan saja.** LabScale juga mengecek ruang disk sebelum
  pekerjaan video yang panjang, bukan baru ketahuan penuh di tengah jalan.
- **Bahasa Indonesia dan Inggris**, ganti dengan satu klik.
- Untuk yang ingin tahu detail teknis: video disimpan sebagai H.264, HEVC,
  atau AV1, memakai encoder hardware GPU kalau ada (VideoToolbox di Mac,
  NVENC di NVIDIA), dan audionya tetap ikut.

## Cara pasang

### macOS (Apple Silicon, macOS 14 atau lebih baru)

1. Unduh `LabScale-<versi>-macos.dmg` dari
   [Releases](https://github.com/labby245/lab-scale/releases/latest).
2. Buka, lalu seret **LabScale** ke **Applications**.
3. Saat pertama dibuka, macOS bilang app ini tidak bisa diverifikasi — LabScale
   (belum) ditandatangani sertifikat developer Apple berbayar. Klik **Done**,
   buka **System Settings → Privacy & Security**, gulir ke bawah, lalu klik
   **Open Anyway** di samping LabScale. Cukup sekali.

Mac Intel tidak didukung.

### Windows (10 / 11, 64-bit)

1. Unduh `LabScale-Setup-<versi>.exe` dari
   [Releases](https://github.com/labby245/lab-scale/releases/latest).
   (Tidak mau installer? Ambil `.zip`-nya dan jalankan `labscale.exe`.)
2. Kalau Windows SmartScreen menampilkan "Windows protected your PC", klik
   **More info → Run anyway**. Installer-nya tidak butuh hak administrator.

Fitur AI butuh GPU yang mendukung Vulkan — kebanyakan GPU NVIDIA, AMD, dan
Intel sejak sekitar 2016, dengan driver terbaru. Di laptop yang lebih tua
LabScale tetap bisa dipakai: app memberi tahu bahwa fitur AI tidak tersedia,
sedangkan upscale tanpa AI dan boost 60 FPS tetap jalan.

## Perlu diketahui

- **Upscale video dengan AI itu berat.** Setiap frame di-upscale satu per satu,
  jadi cocok untuk klip pendek. LabScale memperkirakan ruang disk sementara
  yang dibutuhkan dan memberi tahu di awal kalau tidak cukup.
- **2× sama beratnya dengan 4×** di kebanyakan model AI — modelnya hanya punya
  bobot 4×, jadi LabScale menjalankan 4× lalu memperkecilnya. Pengecualiannya
  "Video anime": punya bobot 2× dan 3× sendiri dan jauh lebih cepat.
- **Tiga model opsional diunduh saat kamu memilihnya** — UltraMix Balanced,
  UltraSharp, dan Remacri (sekitar 33 MB masing-masing). Lisensinya hanya untuk
  **pemakaian non-komersial** (CC BY-NC-SA 4.0); model yang ikut installer
  tidak punya batasan itu.
- **Pembaruan.** Saat dibuka, LabScale mengecek GitHub apakah ada versi baru
  dan menampilkan banner kecil kalau ada. LabScale tidak pernah mengunduh atau
  memasang apa pun sendiri.
- **Ada masalah?** Klik ikon ⓘ → **Buka folder log**, lalu lampirkan
  `labscale.log` di [issue baru](https://github.com/labby245/lab-scale/issues).

## Dibangun dengan

LabScale adalah app Flutter yang menjalankan tiga tool open source:

- [FFmpeg](https://ffmpeg.org) — dekode, enkode, filter
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (ncnn Vulkan) — upscale AI
- [RIFE](https://github.com/hzwer/Practical-RIFE) (ncnn Vulkan) — interpolasi frame AI

Kredit dan lisensi lengkap: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Membangun dari source: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Juga dari Labstory Studio

**[Fotolane](https://github.com/labby245/fotolane-releases)** — siapkan foto
event secara otomatis. Ribuan foto event di-resize dan dipilah siap unggah
tanpa perlu ditunggui.

## Lisensi

Kode LabScale berlisensi [MIT](LICENSE). Tool dan model yang dibundel punya
lisensi masing-masing — lihat [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
