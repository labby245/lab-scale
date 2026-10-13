# Third-party notices

LabScale's own code is MIT-licensed (see `LICENSE`). The installers also ship
the programs and model weights below. LabScale runs each of them as a
separate program; none is linked into LabScale itself, and each keeps its own
licence. Full licence texts are in the `licenses/` folder.

## Programs bundled in the installers

### FFmpeg — GPL-3.0-or-later

Decoding, encoding and filtering. Copyright © the FFmpeg developers.
<https://ffmpeg.org>

The builds LabScale ships are configured with `--enable-gpl --enable-version3`,
so the binary as distributed is under the **GNU General Public License v3**
(`licenses/GPL-3.0.txt`). It includes, among others:

| Component | Licence |
|---|---|
| x264 | GPL-2.0-or-later |
| x265 | GPL-2.0-or-later |
| LAME | LGPL-2.0-or-later |
| SVT-AV1, libvpx, opus, dav1d | BSD |
| libvmaf | BSD-2-Clause-Patent |
| OpenSSL 3 (macOS build) | Apache-2.0 |

- **macOS:** Homebrew's `ffmpeg` formula, with its libraries copied into the
  app bundle by `tools/bundle_ffmpeg_dylibs.sh`.
- **Windows:** the "essentials" build by Gyan Doshi,
  <https://www.gyan.dev/ffmpeg/builds/> (version pinned in
  `tools/fetch_binaries.ps1`).

**Source code.** Every GitHub Release of LabScale carries, as the release
asset `ffmpeg-sources-<version>.tar` (collected by
`tools/collect_gpl_sources.sh`):

- macOS: the FFmpeg release tarball it was built from, plus x264 and x265 at
  the versions Homebrew built;
- Windows: FFmpeg at the exact commit gyan.dev built from, the GPL libraries
  in that build (x264, x265, vid.stab, Xvid), and gyan's list of every bundled
  library with its exact version.

**Written offer.** For three years after we distribute a given release, we
will provide the complete corresponding source of any other library inside
these FFmpeg builds (the LGPL and permissively licensed ones listed in the
build information) on request, at no charge beyond the cost of providing
it: email **hello@labstory.id**.

### Real-ESRGAN ncnn Vulkan — MIT

`realesrgan-ncnn-vulkan`, AI upscaling.
Copyright © 2021 Xintao Wang. Copyright © 2019 nihui (realsr-ncnn-vulkan).
<https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan>

### RIFE ncnn Vulkan — MIT

`rife-ncnn-vulkan`, AI frame interpolation. Copyright © 2020 nihui.
<https://github.com/nihui/rife-ncnn-vulkan>,
<https://github.com/TNTwise/rife-ncnn-vulkan>

### ncnn — BSD-3-Clause

Neural network inference, compiled into both tools above.
Copyright © 2017 THL A29 Limited, a Tencent company.
<https://github.com/Tencent/ncnn>
Includes libwebp (BSD-3-Clause, Google), stb (public domain / MIT) and, on
Windows, dirent (MIT). The macOS builds include MoltenVK (Apache-2.0, The
Khronos Group) and the LLVM OpenMP runtime (Apache-2.0 with LLVM exception).

### mpv / libmpv (via media_kit) — LGPL

Video preview inside the app, through the `media_kit` Flutter package (MIT).
The bundled libmpv and its FFmpeg are built without GPL parts: LGPL-2.1-or-later
on macOS, LGPL-3.0-or-later on Windows. They are dynamically linked and can be
replaced. Build sources:
<https://github.com/media-kit/libmpv-darwin-build>,
<https://github.com/media-kit/libmpv-win32-video-cmake>

## AI models bundled in the installers

| Model | Licence | Author |
|---|---|---|
| RealESRGAN x4plus, x4plus-anime | BSD-3-Clause | Xintao Wang |
| realesr-animevideov3 (x2, x3, x4) | BSD-3-Clause | Xintao Wang |
| realesr-general-x4v3 (shown as "Quick draft", file `upscayl-lite-4x`) | BSD-3-Clause | Xintao Wang |
| RIFE v4.6 / v4.25 | MIT | hzwer (Practical-RIFE) |

<https://github.com/xinntao/Real-ESRGAN>, <https://github.com/hzwer/Practical-RIFE>

```
BSD 3-Clause License

Copyright (c) 2021, Xintao Wang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

The MIT licence text that applies to Real-ESRGAN ncnn Vulkan (© 2021 Xintao
Wang, © 2019 nihui), RIFE ncnn Vulkan (© 2020 nihui) and the RIFE weights
(© 2021 hzwer; the original RIFE code © Megvii Inc.) is identical to the one
in `LICENSE`, with those copyright lines.

## AI models downloaded on demand

These are **not** in the installers. LabScale downloads one only when you pick
it, from a pinned commit of <https://github.com/upscayl/upscayl>
(`resources/models`), and checks it against a fixed SHA-256 before use.

| Model | Licence | Author | Original |
|---|---|---|---|
| UltraMix Balanced | CC BY-NC-SA 4.0 | Kim2091 | <https://huggingface.co/Kim2091/UltraSharp> |
| UltraSharp | CC BY-NC-SA 4.0 | Kim2091 | <https://huggingface.co/Kim2091/UltraSharp> |
| Remacri | CC BY-NC-SA 4.0 | Foolhardy | <https://openmodeldb.info/models/4x-Remacri> |

CC BY-NC-SA 4.0 (`licenses/CC-BY-NC-SA-4.0.txt`) allows **non-commercial use
only**. If you use LabScale commercially, use the bundled models instead.
