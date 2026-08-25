# LabScale

Upscale AI dan boost 60 FPS untuk foto & video — semuanya diproses **lokal**, tanpa cloud.

Pilih file (atau seluruh folder), aktifkan operasi yang diinginkan, lalu proses. Hasil disimpan di `outputs/` dan file asli tidak pernah diubah.

## Fitur

- **Upscale** — Real-ESRGAN (foto / anime / video anime) atau Lanczos untuk hasil cepat tanpa AI. Skala 1×–4×.
- **Sharpness** — unsharp mask yang bisa diatur, dipakai bersama upscale.
- **Boost ke 60 FPS** — motion interpolation via FFmpeg `minterpolate` atau RIFE AI (5–10× lebih cepat dan lebih halus).
- **Batch / folder** — drag & drop satu folder, semua media di dalamnya diproses berurutan.
- **Kualitas & codec** — Fast → Ultra (lossless), H.264 / HEVC / AV1, dengan NVENC otomatis jika GPU tersedia.
- **Audio dipertahankan** — audio asli di-copy (atau di-transcode ke AAC 192k jika perlu).

## Kebutuhan

- **Python** 3.10+
- **FFmpeg** — `ffmpeg` dan `ffprobe` harus ada di PATH

macOS (Homebrew):
```bash
brew install ffmpeg
```

Windows (winget):
```powershell
winget install Gyan.FFmpeg
```

## Menjalankan

```bash
python -m venv .venv
# Windows:  .venv\Scripts\activate
# macOS:    source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
python app.py
```

Browser akan terbuka otomatis ke `http://127.0.0.1:5000`. Di Windows bisa juga langsung klik `start.bat`.

Server mati sendiri setelah 60 detik tanpa heartbeat dari browser — tutup tab, app berhenti.

## Fitur AI opsional

Panel **⚙️ Setup & Status** di bawah UI menunjukkan apa yang sudah aktif.

| Fitur | Install |
|---|---|
| Upscale AI (Real-ESRGAN) | `pip install realesrgan basicsr` |
| Interpolasi AI (RIFE) | `python scripts/install_rife.py` |

Tanpa Real-ESRGAN, upscale tetap jalan lewat Lanczos. Tanpa RIFE, 60 FPS tetap jalan lewat FFmpeg `minterpolate`.

Untuk GPU NVIDIA, install PyTorch build CUDA:
```bash
pip install torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu121
```

## Mode kualitas

| Mode | H.264 | HEVC | AV1 (CPU) |
|---|---|---|---|
| Fast | veryfast, CRF 23 | veryfast, CRF 26 | cpu-used 8, CRF 32 |
| Balanced | medium, CRF 20 | medium, CRF 23 | cpu-used 5, CRF 28 |
| Better | slow, CRF 18 | slow, CRF 21 | cpu-used 4, CRF 24 |
| Best | veryslow, CRF 16 | veryslow, CRF 19 | cpu-used 2, CRF 22 |
| Ultra | placebo, CRF 0 | veryslow, CRF 12 | cpu-used 1, CRF 18 |

Encoder NVENC dipilih otomatis jika GPU mendukung.

## Struktur proyek

```text
lab-scale/
  app.py                    # Flask routes
  requirements.txt
  start.bat                 # launcher Windows
  templates/index.html      # UI
  static/
    app.js                  # frontend
    style.css
  utils/
    pipeline.py             # orkestrasi video & image
    ffmpeg_ops.py           # encode / probe / preset codec
    frame_ops.py            # ekstraksi frame + sharpness
    upscale_ops.py          # Real-ESRGAN
    interpolation_ops.py    # FFmpeg minterpolate
    rife_ops.py             # RIFE ncnn-vulkan
    gpu.py                  # deteksi GPU & encoder
    jobs.py                 # job store + log
    schemas.py              # validasi request (pydantic)
    logging_config.py
  scripts/install_rife.py
  tests/
  uploads/  outputs/  temp/ # gitignored
```

## API

| Endpoint | Body | Return |
|---|---|---|
| `POST /upload` | multipart `video` | `{ filename, originalBase, isImage }` |
| `POST /process` | `{ filename, upscale, upscale_model, upscale_scale, fps_boost, interp_engine, sharpness, quality, codec, job_id }` | `{ outputFilename, outputDir, outputPath }` |
| `POST /process-image` | sama, tanpa `fps_boost` / `codec` | `{ outputFilename, outputDir, outputPath }` |
| `POST /process-bulk` | `{ files: [...], ...opsi }` | `{ results, summary, outputDir }` |
| `GET /process-log/<job_id>` | — | `{ logs, done }` |
| `GET /capabilities` | — | `{ esrgan, rife }` |
| `GET /encoder-info` | — | encoder + status GPU |
| `POST /open-folder` | `{ path }` | `{ ok }` |

## Test

```bash
pytest
```

## Troubleshooting

- **"ffmpeg failed"** — pastikan `ffmpeg` dan `ffprobe` ada di PATH.
- **Upload terlalu besar** — batas default 2 GB (`MAX_CONTENT_LENGTH` di `app.py`).
- **ESRGAN lambat pada video** — Real-ESRGAN diproses per-frame; gunakan untuk klip pendek atau pilih Lanczos.
- **Out of memory saat upscale** — tile size dipilih otomatis dari VRAM; turunkan skala output jika masih gagal.

## Lisensi

MIT
