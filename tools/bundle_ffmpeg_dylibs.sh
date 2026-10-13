#!/usr/bin/env bash
#
# Makes a Homebrew ffmpeg/ffprobe in <bin_dir> self-contained (macOS).
#
# Homebrew's ffmpeg is not static: the 400 KB executable loads libavcodec and
# a dozen more libraries from /opt/homebrew. Copied into an app as-is it runs
# on the machine that built it and crashes on every Mac without Homebrew —
# which is to say, on nearly every Mac it is shipped to.
#
# This walks the dependency tree with `otool -L`, copies every non-system
# dylib next to the executables, rewrites each load path to @loader_path, and
# re-signs ad hoc (install_name_tool invalidates the old signature, and Apple
# Silicon refuses to run unsigned code). It then proves the result works with
# an empty environment, so a library that still points outside the folder
# fails here instead of on a user's machine.
#
# Usage: tools/bundle_ffmpeg_dylibs.sh <bin_dir>

set -euo pipefail

BIN_DIR="${1:?usage: bundle_ffmpeg_dylibs.sh <bin_dir>}"
cd "$BIN_DIR"

for exe in ffmpeg ffprobe; do
  [[ -f "$exe" ]] || { echo "ERROR: $BIN_DIR/$exe tidak ada" >&2; exit 1; }
done

# Non-system dependencies of one Mach-O file, one absolute path per line.
deps_of() {
  otool -L "$1" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//' \
    | grep -vE '^(/usr/lib/|/System/|@)' || true
}

# ── Collect ──────────────────────────────────────────────────────────────────
#
# Keyed by basename: the same library is often referenced through two paths
# (Cellar/ffmpeg/8.1.2/lib/… from the executable, opt/ffmpeg/lib/… from a
# sibling library), and both must end up pointing at the one copy.
queue=()
while IFS= read -r d; do [[ -n "$d" ]] && queue+=("$d"); done < <(deps_of ffmpeg; deps_of ffprobe)

copied=()
while ((${#queue[@]})); do
  dep="${queue[0]}"
  queue=("${queue[@]:1}")
  name="$(basename "$dep")"
  [[ " ${copied[*]-} " == *" $name "* ]] && continue
  [[ -f "$dep" ]] || { echo "ERROR: dependency $dep tidak ditemukan" >&2; exit 1; }
  cp -f "$dep" "./$name"
  chmod 755 "./$name"
  copied+=("$name")
  while IFS= read -r d; do [[ -n "$d" ]] && queue+=("$d"); done < <(deps_of "$dep")
done

# ── Rewrite ──────────────────────────────────────────────────────────────────
for file in ffmpeg ffprobe "${copied[@]}"; do
  if [[ "$file" == *.dylib ]]; then
    install_name_tool -id "@loader_path/$file" "$file" 2>/dev/null
  fi
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$file" 2>/dev/null
  done < <(deps_of "$file")
  codesign --force --sign - "$file" 2>/dev/null
done

echo "  ${#copied[@]} dylib ikut dibundel (load path → @loader_path)" >&2

# ── Verify ───────────────────────────────────────────────────────────────────
leftover="$(for f in ffmpeg ffprobe "${copied[@]}"; do deps_of "$f"; done | sort -u)"
if [[ -n "$leftover" ]]; then
  echo "ERROR: masih ada library di luar folder:" >&2
  echo "$leftover" >&2
  exit 1
fi

# A real encode and probe with no PATH and no DYLD_* variables: nothing can be
# borrowed from the build machine.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
env -i ./ffmpeg -nostdin -v error -f lavfi -i color=c=black:s=64x64:d=0.1:r=5 \
  -frames:v 1 -c:v libx264 -pix_fmt yuv420p "$tmp/probe.mp4"
env -i ./ffprobe -v error -show_entries stream=codec_name -of csv=p=0 "$tmp/probe.mp4" \
  | grep -q h264 || { echo "ERROR: ffprobe tidak bisa membaca hasil enkode" >&2; exit 1; }
echo "  verifikasi OK — enkode + probe jalan tanpa Homebrew" >&2
