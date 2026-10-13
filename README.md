<div align="center">

<img src="assets/logo.png" width="96" alt="LabScale">

# LabScale

**AI upscaling and 60 FPS boost for photos and video** — by Labstory Studio

Free · open source · runs entirely on your computer

macOS (Apple Silicon) · Windows

[Download](https://github.com/labby245/lab-scale/releases/latest) ·
[Baca dalam Bahasa Indonesia](README.id.md) ·
[Instagram @labstory.studio](https://www.instagram.com/labstory.studio/)

</div>

---

LabScale makes small or blurry photos and videos bigger and sharper with AI,
and makes choppy video smooth. Drop in a file or a whole folder, pick what you
want, press **Process**.

## Why LabScale

- 🆓 **Free, for good** — no account, no watermark, no limit on how many files.
- 🔒 **Private** — everything happens on your computer. Nothing is uploaded,
  and your original files are never changed.
- 🎬 **Photos *and* video** — enlarge up to 4×, and turn choppy video into
  smooth 60 FPS.
- 📁 **Many at once** — drop a whole folder, then compare before and after
  side by side.

## What it does

- **Upscale 1×–4×.** You choose by what the picture is: a photo, a design or
  illustration, anime, or anime video. There is also a quick draft mode, and a
  plain non-AI option.
- **Smooth video to 60 FPS** by generating the frames in between.
- **Whole folders at once.** Every file shows as a thumbnail, and the one being
  worked on has its own progress bar. A folder's results are collected in one
  `<folder>_upscaled` folder.
- **Before / after viewer.** Click any file to compare the original and the
  result full-window, dragging a divider across. ←/→ moves between files.
- **Cancel anytime.** LabScale also checks there is enough free disk space
  before a long video job, instead of filling your disk halfway.
- **English and Indonesian**, switchable in one click.
- For the technically curious: video comes out as H.264, HEVC or AV1, using
  your GPU's hardware encoder when it has one (VideoToolbox on Mac, NVENC on
  NVIDIA), and the audio is kept.

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

The AI features need a GPU that supports Vulkan — most NVIDIA, AMD and Intel
GPUs from about 2016 onward, with an up-to-date driver. On older laptops
LabScale still runs: it says the AI features are unavailable, and the non-AI
upscale and the 60 FPS boost keep working.

## Good to know

- **Video upscaling with AI is heavy.** Every frame is upscaled one by one, so
  it suits short clips. LabScale estimates the temporary disk space a job needs
  and tells you up front if it will not fit.
- **2× costs as much as 4×** with most AI models — they only have 4× weights,
  so LabScale runs at 4× and scales down. "Anime video" is the exception: it
  has its own 2× and 3× weights and is much faster.
- **Three optional models are downloaded when you pick them** — UltraMix
  Balanced, UltraSharp and Remacri (about 33 MB each). They are licensed for
  **non-commercial use only** (CC BY-NC-SA 4.0); the models that come with the
  installer have no such restriction.
- **Updates.** LabScale checks GitHub for a newer version when it starts and
  shows a small banner if there is one. It never downloads or installs
  anything by itself.
- **Something went wrong?** Click the ⓘ icon → **Open log folder**, and attach
  `labscale.log` to a [new issue](https://github.com/labby245/lab-scale/issues).

## Built with

LabScale is a Flutter app that drives three excellent open-source tools:

- [FFmpeg](https://ffmpeg.org) — decoding, encoding, filters
- [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) (ncnn Vulkan) — AI upscaling
- [RIFE](https://github.com/hzwer/Practical-RIFE) (ncnn Vulkan) — AI frame interpolation

Full credits and licences: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Building from source: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (Indonesian).

## Also from Labstory Studio

**[Fotolane](https://github.com/labby245/fotolane-releases)** — automatic event
photo prep. Thousands of event photos, resized and sorted for upload without
babysitting.

## Licence

LabScale's code is [MIT](LICENSE). The bundled tools and models keep their own
licences — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
