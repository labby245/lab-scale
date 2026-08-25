#!/usr/bin/env bash
#
# Downloads the external CLI tools LabScale drives into ./bin (macOS).
#
# LabScale shells out to three binaries. They are deliberately not committed to
# git (large, separately licensed), so this script fetches them into the
# gitignored ./bin folder that both `flutter run` and the packaged app look in.
#
#   ffmpeg / ffprobe        decode, encode, filter    (evermeet.cx build)
#   realesrgan-ncnn-vulkan  AI upscaling via Metal    (BSD-3)
#   rife-ncnn-vulkan        AI frame interpolation    (MIT)
#
# Usage: tools/fetch_binaries.sh [--force] [--rife-latest]
#
#   --rife-latest   Fetch RIFE v4.25 instead of v4.6. Costs a 792 MB download:
#                   every model past v4.6 needs an ncnn build newer than
#                   nihui's 2022 release (the old binary rejects them all with
#                   "layer MemoryData not exists or registered"), and the only
#                   published macOS build of it ships inside one archive with
#                   ~50 models. Only two members are kept; the archive is
#                   deleted afterwards.

set -euo pipefail

FORCE=0
RIFE_LATEST=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --rife-latest) RIFE_LATEST=1 ;;
    *) echo "opsi tidak dikenal: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/bin"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$BIN_DIR"

info()  { printf '\033[36m%s\033[0m\n' "$*"; }
ok()    { printf '  \033[32m-> %s\033[0m\n' "$*"; }
skip()  { printf '  \033[33m%s\033[0m\n' "$*"; }

already_present() {
  local name="$1"
  if [[ $FORCE -eq 0 && -e "$BIN_DIR/$name" ]]; then
    skip "$name sudah ada — lewati (pakai --force untuk unduh ulang)"
    return 0
  fi
  return 1
}

fetch_zip() {
  local url="$1" name="$2"
  local archive="$STAGING/$name.zip"
  local out="$STAGING/$name"
  printf '  downloading %s ...\n' "$name" >&2
  curl -fsSL "$url" -o "$archive"
  mkdir -p "$out"
  unzip -qo "$archive" -d "$out"
  echo "$out"
}

# Copies the first match of each executable, strips quarantine, marks +x.
install_exe() {
  local src_dir="$1"; shift
  for exe in "$@"; do
    local found
    found="$(find "$src_dir" -name "$exe" -type f -print -quit)"
    [[ -n "$found" ]] || { echo "ERROR: '$exe' tidak ditemukan di arsip" >&2; exit 1; }
    cp -f "$found" "$BIN_DIR/$exe"
    chmod +x "$BIN_DIR/$exe"
    xattr -d com.apple.quarantine "$BIN_DIR/$exe" 2>/dev/null || true
    ok "bin/$exe"
  done
}

install_models() {
  local src_dir="$1"; shift
  for dir_name in "$@"; do
    local found
    found="$(find "$src_dir" -name "$dir_name" -type d -print -quit)"
    [[ -n "$found" ]] || continue
    rm -rf "${BIN_DIR:?}/$dir_name"
    cp -R "$found" "$BIN_DIR/$dir_name"
    ok "bin/$dir_name/"
  done
}

printf '\nBin dir: %s\n\n' "$BIN_DIR"

# ── FFmpeg ───────────────────────────────────────────────────────────────────
info "[1/3] FFmpeg"
if ! already_present ffmpeg; then
  if command -v brew >/dev/null 2>&1 && brew list ffmpeg >/dev/null 2>&1; then
    # A Homebrew ffmpeg is already trusted and notarized; reuse it.
    cp -f "$(brew --prefix)/bin/ffmpeg" "$BIN_DIR/ffmpeg"
    cp -f "$(brew --prefix)/bin/ffprobe" "$BIN_DIR/ffprobe"
    chmod +x "$BIN_DIR/ffmpeg" "$BIN_DIR/ffprobe"
    ok "bin/ffmpeg (dari Homebrew)"
    ok "bin/ffprobe (dari Homebrew)"
  else
    d1="$(fetch_zip 'https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip' ffmpeg)"
    install_exe "$d1" ffmpeg
    d2="$(fetch_zip 'https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip' ffprobe)"
    install_exe "$d2" ffprobe
  fi
fi

# ── Real-ESRGAN ──────────────────────────────────────────────────────────────
info $'\n[2/3] Real-ESRGAN (ncnn-vulkan)'
if ! already_present realesrgan-ncnn-vulkan; then
  d="$(fetch_zip \
    'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip' \
    realesrgan)"
  install_exe "$d" realesrgan-ncnn-vulkan
  install_models "$d" models
fi

# ── RIFE ─────────────────────────────────────────────────────────────────────
info $'\n[3/3] RIFE (ncnn-vulkan)'
if ! already_present rife-ncnn-vulkan; then
  if [[ $RIFE_LATEST -eq 1 ]]; then
    skip "mengunduh rilis TNTwise (792 MB) — hanya 2 berkas yang disimpan"
    archive="$STAGING/rife-latest.zip"
    curl -fL --retry 3 --progress-bar \
      'https://github.com/TNTwise/rife-ncnn-vulkan/releases/download/20250112/macos.zip' \
      -o "$archive"
    unzip -qo "$archive" 'macos/rife-ncnn-vulkan' 'macos/rife-v4.25/*' -d "$STAGING/rife-latest"
    rm -f "$archive"
    install_exe "$STAGING/rife-latest" rife-ncnn-vulkan
    install_models "$STAGING/rife-latest" rife-v4.25
  else
    d="$(fetch_zip \
      'https://github.com/nihui/rife-ncnn-vulkan/releases/download/20221029/rife-ncnn-vulkan-20221029-macos.zip' \
      rife)"
    install_exe "$d" rife-ncnn-vulkan
    install_models "$d" rife-v4.6
    skip "RIFE v4.6 (2022). Pakai --rife-latest untuk v4.25 yang lebih baik."
  fi
fi

info $'\nSelesai. Isi bin/:'
ls -1 "$BIN_DIR" | sed 's/^/  /'
