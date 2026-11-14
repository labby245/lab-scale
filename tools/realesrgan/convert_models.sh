#!/usr/bin/env bash
#
# Produces the ncnn weights of the macOS "Foto" model from Phhofm's original
# checkpoint: 4xBHI_realplksr_dysample_real (CC BY 4.0), converted by
# export_realplksr.py. The weights are unchanged; only their format is.
#
# Everything is pinned: the checkpoint by SHA-256, the Python packages by
# version, and the converted files by SHA-256 — the conversion is
# deterministic, so a mismatch means something upstream moved and the result
# is refused rather than shipped.
#
# The Python environment (torch, ~1 GB) is kept in a cache folder and reused.
#
# Usage: tools/realesrgan/convert_models.sh <models-dir>

set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <models-dir>" >&2; exit 2; }
MODELS_DIR="$1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STEM='4xBHI-realplksr-real'
SRC_URL='https://github.com/Phhofm/models/releases/download/4xbhi_realplksr/4xBHI_realplksr_dysample_real.safetensors'
SRC_SHA256='e4cbccc2e3c1890c4f5268f575ad1aee2e224cf3f37e2fc74451eb5bfa6a75c2'
PARAM_SHA256='d12396ec5f71e25a6b0aadff62af879331c42bdb5695264ba7a3215cd3009a2a'
BIN_SHA256='083f09c499ebb5e26b7ff37be5f64539a3ad06f71532eae9705b5f19766682ee'
PACKAGES=(torch==2.14.1 spandrel==0.4.2 pnnx==20261020 numpy==2.2.6 safetensors==0.8.0)

CACHE="${LABSCALE_CACHE:-$HOME/Library/Caches/labscale}/model-convert"
VENV="$CACHE/venv"
STAMP="$VENV/.packages"

sha_ok() { echo "$2  $1" | shasum -a 256 -c - >/dev/null 2>&1; }

if [[ -f "$MODELS_DIR/$STEM.param" && -f "$MODELS_DIR/$STEM.bin" ]] \
   && sha_ok "$MODELS_DIR/$STEM.param" "$PARAM_SHA256" \
   && sha_ok "$MODELS_DIR/$STEM.bin" "$BIN_SHA256"; then
  echo "  $STEM sudah ada dan cocok — lewati"
  exit 0
fi

mkdir -p "$CACHE"
if [[ ! -x "$VENV/bin/python" || "$(cat "$STAMP" 2>/dev/null)" != "${PACKAGES[*]}" ]]; then
  echo "  menyiapkan Python (torch, sekali saja; disimpan di $CACHE)…"
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/python" -m pip install -q --disable-pip-version-check "${PACKAGES[@]}"
  echo "${PACKAGES[*]}" > "$STAMP"
fi

CKPT="$CACHE/$(basename "$SRC_URL")"
if ! sha_ok "$CKPT" "$SRC_SHA256"; then
  echo "  mengunduh bobot asli (30 MB)…"
  curl -fsSL --retry 3 -o "$CKPT.part" "$SRC_URL"
  sha_ok "$CKPT.part" "$SRC_SHA256" || { rm -f "$CKPT.part"; echo "ERROR: sha256 bobot tidak cocok" >&2; exit 1; }
  mv -f "$CKPT.part" "$CKPT"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "  mengonversi ke ncnn…"
# -I: the checkpoint is downloaded data; keep the script's folder and the
# current directory off the import path.
if ! "$VENV/bin/python" -I "$HERE/export_realplksr.py" "$CKPT" "$WORK" "$STEM" \
     > "$WORK/export.log" 2>&1; then
  cat "$WORK/export.log" >&2
  echo "ERROR: konversi gagal" >&2
  exit 1
fi
grep '^rewrite' "$WORK/export.log" | sed 's/^/  /'

sha_ok "$WORK/$STEM.param" "$PARAM_SHA256" && sha_ok "$WORK/$STEM.bin" "$BIN_SHA256" \
  || { echo "ERROR: hasil konversi tidak cocok dengan sha256 yang dikunci" >&2; exit 1; }

mkdir -p "$MODELS_DIR"
mv -f "$WORK/$STEM.param" "$WORK/$STEM.bin" "$MODELS_DIR/"
echo "  -> models/$STEM"
