<div align="center">

<img src="assets/logo.png" width="96" alt="LabScale">

# LabScale

**AI upscaling and 60 FPS boost for photos and video** — by Labstory Studio

Free · open source · runs entirely on your computer

macOS (Apple Silicon) · Windows

[Download](https://apps.labstory.id/produk/labscale) ·
[Baca dalam Bahasa Indonesia](README.id.md) ·
[labstory.id](https://labstory.id) ·
[Instagram @labstory.studio](https://www.instagram.com/labstory.studio/)

</div>

---

LabScale enlarges small, low-resolution photos and videos with AI, and makes
choppy video smoother at 60 FPS. Drop in a file or a whole folder, pick what
you want, press **Process**.

## Why LabScale

- 🆓 **Free** — open source, no account, no watermark, no limit on how many
  files.
- 🔒 **Private** — your photos and videos are processed on your computer and
  never uploaded, and your original files are never changed. LabScale only
  goes online to check for a new version and, if you pick one, to download an
  optional model.
- 🎬 **Photos *and* video** — enlarge up to 4×, and make choppy video
  smoother at 60 FPS.
- 📁 **Many at once** — drop a whole folder, then compare before and after
  with a draggable divider.

## What it does

- **Upscale 1×–4×, three simple choices:** **Design & illustration** (logos,
  posters, text), **Photo** (camera and phone shots) and **Video** (fast, for
  real footage). The choices are curated by a professional photographer at
  Labstory Studio: Design and Photo are the models used in day-to-day client
  work, and Video was picked after side-by-side tests on real footage.
- **60 FPS video** by generating the frames in between: with the RIFE AI
  model on a supported GPU, otherwise with FFmpeg's built-in interpolation.
- **Whole folders at once.** Every file shows as a thumbnail, and the one being
  worked on has its own progress bar. A folder's results are collected in one
  `<folder>_upscaled` folder.
- **Before / after viewer.** Click any file to compare the original and the
  result full-window, dragging a divider across. ←/→ moves between files.
- **Cancel anytime.** Before an AI video job, LabScale also checks there is
  enough free disk space, instead of filling your disk halfway.
- **English and Indonesian**, switchable in one click.
- For the technically curious: video comes out as H.264, HEVC or AV1, and the
  audio is kept. LabScale uses the hardware encoder when there is one:
  VideoToolbox on Mac, NVENC on NVIDIA. On Intel and AMD GPUs it tries Quick
  Sync and AMF, not yet tested on real hardware; if a hardware encoder fails,
  the file is encoded again on the CPU.

## Install

### macOS (Apple Silicon, macOS 14 or newer)

1. Download `LabScale-<version>-macos.dmg` from
   [Releases](https://github.com/labby245/lab-scale/releases/latest).
2. Open it and drag **LabScale** into **Applications**.
3. The first time, macOS will say it cannot verify the app — LabScale is not
   (yet) signed with a paid Apple developer certificate. Click **Done**, then
   open **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway** next to LabScale. You only do this once.

Intel Macs are not supported.

### Windows (10 / 11, 64-bit)

1. Download `LabScale-Setup-<version>.exe` from
   [Releases](https://github.com/labby245/lab-scale/releases/latest).
   (Prefer no installer? Take the `.zip` and run `labscale.exe` from it.)
2. If Windows SmartScreen shows "Windows protected your PC", click
   **More info → Run anyway**. The installer does not need administrator
   rights.

### Why the warning?

LabScale is free, so it is not signed with a paid code signing certificate
(Windows) or Apple developer certificate (Mac). That is why Windows and macOS
show a warning the first time; this is common for free open-source apps. The
installers are built from this repository's source code by
[GitHub Actions](.github/workflows/release.yml), and every release includes
`SHA256SUMS.txt` so you can check your download is intact:

- Mac: `shasum -a 256 LabScale-<version>-macos.dmg`
- Windows (Command Prompt): `certutil -hashfile LabScale-Setup-<version>.exe SHA256`

The result should match the line for that file in `SHA256SUMS.txt`.

## System requirements — will my computer handle it?

The AI features (AI upscaling and RIFE) run on the **GPU** through Vulkan.
Without a GPU that supports it, LabScale still opens and works, but only for
non-AI upscaling (Lanczos) and the FFmpeg 60 FPS boost, which run on the CPU.

| | Basic features only | Minimum for AI | Recommended |
|---|---|---|---|
| **Mac** | — | Apple M1, macOS 14, 8 GB RAM | Apple M1 or newer, 16 GB RAM for video |
| **Windows** | Windows 10/11 64-bit, GPU without Vulkan | GPU with Vulkan, 2 GB VRAM, 8 GB RAM | GeForce GTX 1650 / Radeon RX 570 class or better, 4 GB VRAM, 16 GB RAM |
| **Example Windows GPUs** | Intel HD Graphics 3rd–5th gen (e.g. HD 4000), old Fermi-based GeForce (e.g. GT 720M) | Intel HD/UHD 6th gen (2015) or newer, NVIDIA GeForce GTX 650 / GT 740M (Kepler) or newer, AMD Radeon HD 7000 / R7 / R9 (GCN) or newer | NVIDIA GTX 10/16 or RTX, AMD RX 400 or newer |
| **What you can do** | Non-AI upscale, FFmpeg 60 FPS (slow on old CPUs) | AI photo upscaling; short AI video | AI photo and video upscaling, RIFE 60 FPS |
| **Disk space** | ~400 MB for the app | same, plus temporary space for video | 20 GB+ free for long AI video |

**The surest check:** open LabScale and look at the dots in the bottom bar. If
**Real-ESRGAN** and **RIFE** are green, the AI features run on your computer.
If they are grey, click **Setup & Status** to see why.

For a sense of speed, measured on a MacBook Pro M1: one 1920×1280 photo takes
about 6.5–7 seconds with Photo, or about 0.7 seconds with Video. On a laptop without a Vulkan GPU (for example a 3rd-gen Core i3 with a
GT 720M), the AI features are unavailable and the FFmpeg 60 FPS boost is very
slow.

**What we have tested ourselves:** a MacBook Pro M1 (all features) and a
Windows 10 laptop without Vulkan (basic features). The Windows GPU list above
comes from each vendor's published Vulkan support, not from us testing every
GPU. The status dots in the app remain the surest check.

## Good to know

- **Video upscaling with AI is heavy.** Every frame is upscaled one by one, so
  it suits short clips. LabScale estimates the temporary disk space a job needs
  and tells you up front if it will not fit.
- **2× costs as much as 4×** — the AI models only have 4× weights, so
  LabScale runs at 4× and scales down. For long video, pick **Video**: it is
  about 8× faster than Photo.
- **Design & illustration is downloaded when you first pick it** — its model,
  UltraMix Balanced (about 33 MB), is licensed for **non-commercial use only**
  (CC BY-NC-SA 4.0). Photo and Video come with the installer and have no such
  restriction, so use those for commercial work.
- **Updates.** LabScale checks GitHub for a newer version when it starts and
  shows a small banner if there is one. It never downloads or installs
  anything by itself.
- **Something went wrong?** Click the ⓘ icon → **Open log folder**, and attach
  `labscale.log` to a [new issue](https://github.com/labby245/lab-scale/issues).
- **Other questions?** Email
  [hello@labstory.id](mailto:hello@labstory.id).

## Built with

LabScale is a Flutter app that drives three excellent open-source tools:

- [FFmpeg](https://ffmpeg.org) — decoding, encoding, filters
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (ncnn Vulkan) — AI upscaling
- [RIFE](https://github.com/hzwer/Practical-RIFE) (ncnn Vulkan) — AI frame interpolation

Full credits and licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Building from source: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (Indonesian).

## Also from Labstory Studio

**[Fotolane](https://apps.labstory.id/produk/fotolane)** — automatic event
photo prep. Thousands of event photos, resized and sorted for upload without
babysitting.

## Licence

LabScale's code is [MIT](LICENSE). The bundled tools and models keep their own
licences — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
