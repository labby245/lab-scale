#!/usr/bin/env bash
#
# Gathers the source code of the GPL programs LabScale ships, for attaching to
# a GitHub Release next to the installers.
#
# The bundled FFmpeg builds are GPL-3.0 (x264 and x265 are compiled in), and
# GPLv3 §6(d) asks that whoever distributes the binary offers the matching
# source from the same place. A link to ffmpeg.org alone does not promise that
# the exact version stays up, so the tarballs themselves go on the release.
#
# Output: dist/ffmpeg-sources-<app version>.tar containing
#   ffmpeg-<version>.tar.xz for the macOS build and for the Windows build,
#   the x264 / x265 sources Homebrew built from, and BUILD-INFO.txt with each
#   build's configure flags.
#
# Run on the Mac that built the .dmg (it reads bin/ffmpeg), after
# tools/fetch_binaries.sh. Usage: tools/collect_gpl_sources.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/bin"
DIST_DIR="$ROOT/dist"

# The Windows build, pinned in tools/fetch_binaries.ps1. Kept in step by hand;
# the check below fails loudly if the two disagree.
WINDOWS_FFMPEG_VERSION="9.0.2"
grep -q "codexffmpeg/releases/download/$WINDOWS_FFMPEG_VERSION/" "$ROOT/tools/fetch_binaries.ps1" || {
  echo "ERROR: WINDOWS_FFMPEG_VERSION ($WINDOWS_FFMPEG_VERSION) tidak sama dengan fetch_binaries.ps1" >&2
  exit 1
}

APP_VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | head -1 | sed 's/version:[[:space:]]*//' | cut -d+ -f1)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

mac_version="$(env -i "$BIN_DIR/ffmpeg" -version | head -1 | awk '{print $3}')"
echo "macOS ffmpeg $mac_version · Windows ffmpeg $WINDOWS_FFMPEG_VERSION" >&2

echo "  ffmpeg-$mac_version.tar.xz (macOS)" >&2
curl -fL --retry 3 -s -o "$OUT/ffmpeg-$mac_version.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$mac_version.tar.xz"

# ── Windows: gyan.dev essentials build ───────────────────────────────────────
#
# gyan builds from a git commit, not the release tarball, and lists every
# bundled library's version in its README (kept in tools/windows/). The GPL
# components are attached as source; the full component list goes alongside,
# and THIRD_PARTY_NOTICES.md offers the rest on request.
GYAN_README="$ROOT/tools/windows/ffmpeg-$WINDOWS_FFMPEG_VERSION-essentials-README.txt"
[[ -f "$GYAN_README" ]] || { echo "ERROR: $GYAN_README tidak ada — salin README.txt dari zip gyan versi ini" >&2; exit 1; }
win_commit="$(sed -n 's#^Source Code: https://github.com/FFmpeg/FFmpeg/commit/##p' "$GYAN_README")"
mkdir -p "$OUT/windows"
cp "$GYAN_README" "$OUT/windows/gyan-build-README.txt"
fetch() {  # name url
  echo "  windows/$1" >&2
  curl -fL --retry 3 -s -o "$OUT/windows/$1" "$2"
}
fetch "ffmpeg-$win_commit.tar.gz" "https://github.com/FFmpeg/FFmpeg/archive/$win_commit.tar.gz"
# GPL components, at the versions in the README above. x264 "v0.165.3223"
# is revision 3223 on master: the commit right after r3222 (b35605ac).
fetch "x264-r3223-0480cb05.tar.bz2" "https://code.videolan.org/videolan/x264/-/archive/0480cb05fa18/x264-0480cb05fa18.tar.bz2"
fetch "x265-4.3-45-g116b875.tar.gz" "https://github.com/Multicorewareinc/x265/archive/116b875.tar.gz"
fetch "vid.stab-e2445c4.tar.gz" "https://github.com/georgmartius/vid.stab/archive/e2445c4.tar.gz"
fetch "xvidcore-1.3.7.tar.gz" "https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz"

# x264 and x265 at the versions Homebrew built from. Read off the formula,
# which describes the *installed* build only while the two versions match —
# true right after `brew install`/`upgrade`, which is how CI and a fresh
# fetch_binaries run get it. Otherwise this stops rather than attach the
# wrong source.
for formula in x264 x265; do
  installed="$(brew list --versions "$formula" | awk '{print $2}')"
  read -r stable url revision < <(brew info --json=v2 "$formula" | python3 -c '
import json, sys
f = json.load(sys.stdin)["formulae"][0]
s = f["urls"]["stable"]
print(f["versions"]["stable"], s["url"], s.get("revision") or "-")')
  if [[ "$installed" != "$stable"* ]]; then
    echo "ERROR: $formula terpasang $installed, formula $stable — jalankan 'brew upgrade ffmpeg' lalu fetch_binaries.sh --force" >&2
    exit 1
  fi
  if [[ "$url" == *.git ]]; then
    # A git source pinned to a revision: GitLab serves any commit as a tarball.
    url="${url%.git}/-/archive/$revision/$formula-$revision.tar.bz2"
  fi
  name="$formula-$installed-$(basename "$url")"
  curl -fL --retry 3 -s -o "$OUT/$name" "$url"
  echo "  $name" >&2
done

{
  echo "LabScale $APP_VERSION — FFmpeg build information"
  echo
  echo "== macOS: Homebrew ffmpeg $mac_version =="
  env -i "$BIN_DIR/ffmpeg" -hide_banner -buildconf
  echo
  echo "== Windows: gyan.dev essentials build $WINDOWS_FFMPEG_VERSION =="
  echo "https://github.com/GyanD/codexffmpeg/releases/tag/$WINDOWS_FFMPEG_VERSION"
  echo "Built from FFmpeg commit $win_commit. Every bundled library and its"
  echo "version: windows/gyan-build-README.txt. Source of FFmpeg and of the GPL"
  echo "libraries (x264, x265, vid.stab, Xvid) is in windows/. Source of any other"
  echo "listed library is available on request: hello@labstory.id"
} > "$OUT/BUILD-INFO.txt"

mkdir -p "$DIST_DIR"
tarball="$DIST_DIR/ffmpeg-sources-$APP_VERSION.tar"
tar -cf "$tarball" -C "$OUT" .
echo "OK: $tarball ($(du -h "$tarball" | cut -f1))" >&2
