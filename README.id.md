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

LabScale membuat foto dan video kecil jadi lebih besar dan tajam dengan AI, dan
membuat video yang patah-patah jadi mulus di 60 frame per detik. Masukkan satu
file atau satu folder, pilih yang kamu mau, tekan **Proses**.

Tidak ada yang diunggah ke mana pun. Semua langkah berjalan di komputermu
sendiri, memakai GPU-mu sendiri, dan file aslimu tidak pernah diubah.

## Fiturnya

- **Upscale 1×–4×** dengan model yang dipilih menurut *peruntukannya*: foto
  realistis, desain & ilustrasi, anime & manga, video anime, atau draf cepat.
  Atau Lanczos biasa tanpa AI.
- **Boost ke 60 FPS** dengan interpolasi frame RIFE AI (atau bawaan FFmpeg).
- **Satu folder sekaligus.** Setiap file tampil sebagai thumbnail, dan file
  yang sedang dikerjakan punya progress bar sendiri. Hasil dari satu folder
  dikumpulkan di folder `<nama folder>_upscaled`.
- **Bandingkan sebelum / sesudah.** Klik file mana saja untuk membandingkan
  asli dan hasilnya selebar jendela, dengan pembatas yang bisa digeser.
  ←/→ untuk pindah file.
- **Kualitas & codec** — H.264, HEVC, atau AV1, memakai encoder hardware GPU
  (VideoToolbox di Mac, NVENC di NVIDIA) kalau ada. Audio tetap ikut.
- **Bisa dibatalkan kapan saja**, dan LabScale mengecek ruang disk sebelum
  memulai pekerjaan video yang panjang, bukan baru ketahuan penuh di tengah
  jalan.
- **Bahasa Indonesia dan Inggris**, ganti dengan satu klik.

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

Fitur AI butuh GPU yang mendukung Vulkan — praktis semua GPU NVIDIA, AMD, atau
Intel beberapa tahun terakhir, dengan driver yang terbaru.

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
