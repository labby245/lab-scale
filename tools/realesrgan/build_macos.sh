#!/usr/bin/env bash
#
# Builds the macOS realesrgan-ncnn-vulkan that LabScale ships, from source.
#
# Why not xinntao's 2022 release: its ncnn predates the GridSample layer, so it
# cannot run the "Foto" model (RealPLKSR with a DySample upsampler). This build
# is the same program (MIT) on a current ncnn (BSD-3-Clause) with MoltenVK
# (Apache-2.0) linked in statically, plus labscale.patch:
#
#   - every ncnn layer is compiled in (the original whitelist turned off layers
#     converted models need);
#   - a model containing GridSample runs in fp32 — in fp16 its sampling grid
#     drifts visibly; every other model keeps fp16 and its speed. Such a
#     model normalises per tile, so small tiles came out up to a level apart
#     from their neighbours: unless -t is given it gets tiles of at least
#     400 px (no measurable step), and tiles below 400 px a 32 px overlap
#     instead of 10;
#   - 400 px auto tiles when the GPU budget is large (Apple Silicon), ~7%
#     faster than 200.
#
# Existing models produce the same output as the 2022 binary (PSNR > 58 dB,
# i.e. rounding). Every source is pinned to a commit or a SHA-256.
#
# Needs Xcode command line tools, cmake and git. Takes ~5 minutes on an M1.
#
# Usage: tools/realesrgan/build_macos.sh <output-binary>
#        tools/realesrgan/build_macos.sh --build-id
#
# Next to the binary it writes <output-binary>.build-id; --build-id prints the
# id this script would write, so callers can tell a stale build apart.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bump BUILD_ID whenever a pin or labscale.patch changes: fetch_binaries.sh
# rebuilds when the binary in bin/ was made from a different one.
BUILD_ID='2026-11-15.1'
REALESRGAN_COMMIT='37026f49824c5cf84062e7c6a5dd71445dcf610f'   # xinntao, 2022-04-24
NCNN_COMMIT='d1f6ac67e9fc91390cc70f7168573fd2626f1d66'         # Tencent, 2026-11-13
LIBWEBP_COMMIT='845d5476a866141ba35ac133f856fa62f0b7445f'      # v1.4.0
MOLTENVK_VERSION='v1.4.2'
MOLTENVK_SHA256='f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e'
# MoltenVK's static library is built for macOS 12, so nothing lower is
# honest; the app itself needs macOS 14 (package_macos.sh checks).
DEPLOYMENT_TARGET='12.0'

[[ $# -eq 1 ]] || { echo "usage: $0 <output-binary> | --build-id" >&2; exit 2; }
if [[ "$1" == "--build-id" ]]; then echo "$BUILD_ID"; exit 0; fi
OUT="$1"

for tool in cmake git curl shasum; do
  command -v "$tool" >/dev/null || { echo "ERROR: '$tool' tidak ditemukan" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
JOBS="$(sysctl -n hw.ncpu)"

# A shallow fetch of one exact commit: reproducible, and no history to download.
checkout() {
  local url="$1" commit="$2" dir="$3"
  git init -q "$dir"
  git -C "$dir" fetch -q --depth 1 "$url" "$commit"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

echo "  sumber (dikunci ke commit)…"
checkout https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan.git "$REALESRGAN_COMMIT" "$WORK/resr"
rm -rf "$WORK/resr/src/ncnn" "$WORK/resr/src/libwebp"
checkout https://github.com/Tencent/ncnn.git "$NCNN_COMMIT" "$WORK/resr/src/ncnn"
# glslang is whatever the pinned ncnn pins as its submodule — read from the
# checkout, so bumping NCNN_COMMIT cannot leave a stale glslang behind.
NCNN_DIR="$WORK/resr/src/ncnn"
GLSLANG_URL="$(git -C "$NCNN_DIR" config -f .gitmodules submodule.glslang.url)"
GLSLANG_COMMIT="$(git -C "$NCNN_DIR" ls-tree HEAD glslang | awk '$2 == "commit" {print $3}')"
[[ -n "$GLSLANG_URL" && -n "$GLSLANG_COMMIT" ]] \
  || { echo "ERROR: pin glslang tidak ditemukan di ncnn" >&2; exit 1; }
rm -rf "$NCNN_DIR/glslang"
checkout "$GLSLANG_URL" "$GLSLANG_COMMIT" "$NCNN_DIR/glslang"
checkout https://github.com/webmproject/libwebp.git "$LIBWEBP_COMMIT" "$WORK/resr/src/libwebp"
git -C "$WORK/resr" apply "$HERE/labscale.patch"

echo "  MoltenVK ${MOLTENVK_VERSION}…"
curl -fsSL --retry 3 -o "$WORK/mvk.tar" \
  "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_VERSION/MoltenVK-macos.tar"
echo "$MOLTENVK_SHA256  $WORK/mvk.tar" | shasum -a 256 -c - >/dev/null \
  || { echo "ERROR: sha256 MoltenVK tidak cocok" >&2; exit 1; }
tar -xf "$WORK/mvk.tar" -C "$WORK"
MVK="$WORK/MoltenVK/MoltenVK"

# Real-ESRGAN compiles its own pre/post-processing shaders at build time; ncnn
# compiles its layers at run time with the glslang it links in.
echo "  glslangValidator…"
cmake -S "$WORK/resr/src/ncnn/glslang" -B "$WORK/glslang-host" -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_GLSLANG_BINARIES=ON -DENABLE_OPT=OFF -DENABLE_SPVREMAPPER=OFF -DENABLE_HLSL=OFF \
  -DGLSLANG_TESTS=OFF -DENABLE_CTEST=OFF >/dev/null
cmake --build "$WORK/glslang-host" --target glslang-standalone -j "$JOBS" >/dev/null

echo "  realesrgan-ncnn-vulkan (arm64)…"
# NCNN_SIMPLEVK=OFF links the Vulkan API directly — here MoltenVK's static
# library — so the binary needs no libvulkan beside it. NCNN_SIMPLEOMP is
# ncnn's own OpenMP runtime: nothing to ship, no libomp dependency.
cmake -S "$WORK/resr/src" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DUSE_STATIC_MOLTENVK=ON -DNCNN_SIMPLEVK=OFF -DNCNN_OPENMP=ON -DNCNN_SIMPLEOMP=ON \
  -DVulkan_INCLUDE_DIR="$MVK/include" \
  -DVulkan_LIBRARY="$MVK/static/MoltenVK.xcframework/macos-arm64_x86_64/libMoltenVK.a" \
  -DGLSLANGVALIDATOR_EXECUTABLE="$WORK/glslang-host/StandAlone/glslang" >/dev/null
cmake --build "$WORK/build" -j "$JOBS" >/dev/null

BIN="$WORK/build/realesrgan-ncnn-vulkan"
[[ "$(lipo -archs "$BIN")" == "arm64" ]] || { echo "ERROR: arsitektur tak terduga" >&2; exit 1; }
# Nothing but system frameworks and libraries may be linked.
if otool -L "$BIN" | tail -n +2 | grep -vqE '^\s+(/System/Library/|/usr/lib/)'; then
  echo "ERROR: binary memuat library di luar sistem:" >&2
  otool -L "$BIN" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
cp -f "$BIN" "$OUT"
chmod +x "$OUT"
echo "$BUILD_ID" > "$OUT.build-id"
