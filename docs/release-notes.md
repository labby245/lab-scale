**New in 2.1.2:**

- Results are now saved to a LabScale folder in your user folder (for example C:\Users\name\LabScale or ~/LabScale) instead of Documents, so large videos don't get synced to OneDrive or iCloud. A folder you picked yourself is kept.
- On Windows, LabScale now also tries Intel (Quick Sync) and AMD (AMF) hardware encoders. We haven't tested this on Intel/AMD GPUs ourselves yet, so if a hardware encoder fails, the video is automatically encoded again on the CPU.
- Temporary files from interrupted jobs (for example after a force quit) are now cleaned up automatically when LabScale starts.
- The About dialog now has a Contact button (hello@labstory.id) and a link to the LabScale website.
- The 60 FPS engine labels no longer make speed claims we couldn't back up.

**LabScale** enlarges small, low-resolution photos and videos with AI, and makes choppy video smoother at 60 FPS.

- 🆓 **Free** — open source, no account, no watermark, no limit on how many files.
- 🔒 **Private** — your photos and videos are processed on your computer and never uploaded.
- 🎬 **Photos and video** — enlarge up to 4×, smoother video at 60 FPS.
- 📁 **Many at once** — drop a whole folder, compare before and after.

### Which file do I download?

| Your computer | Download |
|---|---|
| **Mac** with Apple Silicon (M1 or newer), macOS 14+ | `LabScale-…-macos.dmg` |
| **Windows** 10 / 11 | `LabScale-Setup-….exe` |
| Windows, without installing | `LabScale-…-windows-x64.zip` |

You do **not** need `ffmpeg-sources-….tar` or `SHA256SUMS.txt` — they are there for licence compliance and for checking downloads.

### Opening it the first time

- **Mac:** drag LabScale into Applications and open it. When macOS says it cannot verify the app, click **Done**, go to **System Settings → Privacy & Security**, and click **Open Anyway**. Only once.
- **Windows:** if SmartScreen says "Windows protected your PC", click **More info → Run anyway**. No administrator rights needed.

---
**Baru di 2.1.2:**

- Hasil kini disimpan di folder LabScale di folder pengguna (misalnya C:\Users\nama\LabScale atau ~/LabScale), bukan di Dokumen, supaya video besar tidak ikut tersinkron ke OneDrive atau iCloud. Folder yang sudah kamu pilih sendiri tetap dipakai.
- Di Windows, LabScale kini juga mencoba encoder hardware Intel (Quick Sync) dan AMD (AMF). Dukungan ini belum kami uji langsung di GPU Intel/AMD, jadi kalau encoder hardware gagal, video otomatis dienkode ulang dengan CPU.
- File sementara dari proses yang terhenti (misalnya karena app ditutup paksa) kini dibersihkan otomatis saat LabScale dibuka.
- Dialog Tentang kini punya tombol Kontak (hello@labstory.id) dan tautan ke situs LabScale.
- Label engine 60 FPS tidak lagi menyebut klaim kecepatan yang tidak terbukti.

**LabScale** memperbesar foto dan video beresolusi rendah dengan AI, dan membuat video patah-patah jadi lebih mulus di 60 FPS.

- 🆓 **Gratis** — open source, tanpa akun, tanpa watermark, tanpa batas jumlah file.
- 🔒 **Privat** — foto dan videomu diproses di komputermu sendiri dan tidak diunggah.
- 🎬 **Foto dan video** — perbesar sampai 4×, video lebih mulus di 60 FPS.
- 📁 **Sekali banyak** — masukkan satu folder, bandingkan sebelum dan sesudah.

### Unduh yang mana?

| Komputermu | Unduh |
|---|---|
| **Mac** Apple Silicon (M1 atau lebih baru), macOS 14+ | `LabScale-…-macos.dmg` |
| **Windows** 10 / 11 | `LabScale-Setup-….exe` |
| Windows, tanpa instal | `LabScale-…-windows-x64.zip` |

File `ffmpeg-sources-….tar` dan `SHA256SUMS.txt` **tidak perlu** diunduh — keduanya untuk kepatuhan lisensi dan pengecekan unduhan.

### Membuka pertama kali

- **Mac:** seret LabScale ke Applications lalu buka. Saat macOS bilang app tidak bisa diverifikasi, klik **Done**, buka **System Settings → Privacy & Security**, lalu klik **Open Anyway**. Cukup sekali.
- **Windows:** kalau SmartScreen menampilkan "Windows protected your PC", klik **More info → Run anyway**. Tidak perlu hak administrator.
