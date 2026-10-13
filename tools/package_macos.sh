#!/usr/bin/env bash
#
# Builds LabScale for macOS and produces a signed .app + .dmg.
#
# Steps:
#   1. flutter build macos --release
#   2. copy ./bin into LabScale.app/Contents/Resources/bin
#   3. codesign every bundled binary, then the app (hardened runtime)
#   4. package a .dmg into ./dist
#   5. optionally notarize + staple
#
# Without SIGN_IDENTITY everything is signed ad hoc. That build runs on any
# Apple Silicon Mac, but Gatekeeper asks the user to approve it once in
# System Settings → Privacy & Security ("Open Anyway"). Unsigned is not an
# option: copying bin/ into the bundle breaks the seal Xcode made, and a
# downloaded app with a broken seal is reported as "damaged" with no way past.
#
# Environment:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE  keychain profile made with `xcrun notarytool store-credentials`
#
# Usage: tools/package_macos.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT/bin"
DIST_DIR="$ROOT/dist"
APP_NAME="LabScale"
BUILD_APP="$ROOT/build/macos/Build/Products/Release/$APP_NAME.app"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

info() { printf '\n\033[36m== %s ==\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

cd "$ROOT"

if [[ ! -x "$BIN_DIR/ffmpeg" ]]; then
  warn "bin/ffmpeg belum ada — menjalankan fetch_binaries.sh"
  "$ROOT/tools/fetch_binaries.sh"
fi

info "flutter build macos --release"
flutter build macos --release

[[ -d "$BUILD_APP" ]] || { echo "ERROR: $BUILD_APP tidak ditemukan" >&2; exit 1; }

# ── Bundle the CLI tools ─────────────────────────────────────────────────────
#
# Only what the app actually invokes is shipped. A dev bin/ typically also holds
# nine legacy RIFE model variants (~430 MB) that LabScale never loads, so
# mirroring the folder wholesale would quadruple the download.
info "menyalin bin/ ke Contents/Resources/bin"
RESOURCE_BIN="$BUILD_APP/Contents/Resources/bin"
rm -rf "$RESOURCE_BIN"
mkdir -p "$RESOURCE_BIN"

PAYLOAD_FILES=(ffmpeg ffprobe realesrgan-ncnn-vulkan rife-ncnn-vulkan)
PAYLOAD_DIRS=()
BUNDLED_MODELS=()
while IFS= read -r line; do
  line="${line%%#*}"; line="${line//[[:space:]]/}"
  [[ -n "$line" ]] && BUNDLED_MODELS+=("$line")
done < "$ROOT/tools/bundled_models.txt"

# Only the RIFE model the app would actually pick, in the same order as
# Binaries._modelDirNames. Shipping the rest would add ~10 MB each for weights
# that never load.
for candidate in rife-v4.25 rife-v4.15 rife-v4.6; do
  if [[ -d "$BIN_DIR/$candidate" ]]; then
    PAYLOAD_DIRS+=("$candidate")
    break
  fi
done

for name in "${PAYLOAD_FILES[@]}"; do
  if [[ -f "$BIN_DIR/$name" ]]; then
    cp -f "$BIN_DIR/$name" "$RESOURCE_BIN/$name"
    chmod +x "$RESOURCE_BIN/$name"
    echo "  $name"
  elif [[ "$name" == "ffmpeg" || "$name" == "ffprobe" ]]; then
    echo "ERROR: $name wajib ada di bin/ — jalankan tools/fetch_binaries.sh" >&2
    exit 1
  else
    warn "  $name (tidak ada — dilewati)"
  fi
done

# The libraries a Homebrew ffmpeg loads, made relative by
# tools/bundle_ffmpeg_dylibs.sh. A static ffmpeg has none.
for lib in "$BIN_DIR"/*.dylib; do
  [[ -e "$lib" ]] || continue
  cp -f "$lib" "$RESOURCE_BIN/"
done

for name in "${PAYLOAD_DIRS[@]}"; do
  if [[ -d "$BIN_DIR/$name" ]]; then
    cp -R "$BIN_DIR/$name" "$RESOURCE_BIN/$name"
    echo "  $name/"
  fi
done

# Only the Real-ESRGAN weights whose licences allow redistribution go in the
# bundle. The rest are offered for download inside the app (lib/core/
# model_store.dart), which also keeps the download ~130 MB smaller.
mkdir -p "$RESOURCE_BIN/models"
for stem in "${BUNDLED_MODELS[@]}"; do
  for ext in param bin; do
    src="$BIN_DIR/models/$stem.$ext"
    [[ -f "$src" ]] || { echo "ERROR: bin/models/$stem.$ext tidak ada" >&2; exit 1; }
    cp -f "$src" "$RESOURCE_BIN/models/"
  done
  echo "  models/$stem"
done

# Homebrew bottles target the macOS they were built on, so an ffmpeg fetched
# on macOS 15 refuses to start on 14 — while the app itself would launch there
# and only fail at the first encode. Compare against the app's own minimum.
app_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$BUILD_APP/Contents/Info.plist")"
too_new=()
for f in "$RESOURCE_BIN"/*; do
  [[ -f "$f" ]] || continue
  minos="$(otool -l "$f" 2>/dev/null | awk '/LC_BUILD_VERSION/{b=1} b&&/minos/{print $2; exit}')"
  [[ -n "$minos" ]] || continue
  if [[ "$(printf '%s\n%s\n' "$app_min" "$minos" | sort -V | tail -1)" != "$app_min" ]]; then
    too_new+=("$(basename "$f") (macOS $minos)")
  fi
done
if ((${#too_new[@]})); then
  echo "ERROR: app mendukung macOS $app_min, tapi binary ini butuh yang lebih baru:" >&2
  printf '  %s\n' "${too_new[@]}" >&2
  echo "Bangun rilis di CI (macos-14), atau set ALLOW_NEWER_TOOLS=1 untuk build pribadi." >&2
  [[ "${ALLOW_NEWER_TOOLS:-}" == 1 ]] || exit 1
fi

# The licences travel with the binaries they cover.
cp -f "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$BUILD_APP/Contents/Resources/"
rm -rf "$BUILD_APP/Contents/Resources/licenses"
cp -R "$ROOT/licenses" "$BUILD_APP/Contents/Resources/licenses"

# Refuse to ship an ffmpeg that still reaches outside the bundle. This is the
# exact failure that once made every build work here and nowhere else.
outside="$(for f in "$RESOURCE_BIN"/ffmpeg "$RESOURCE_BIN"/ffprobe "$RESOURCE_BIN"/*.dylib; do
  [[ -e "$f" ]] || continue
  otool -L "$f" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//'
done | grep -vE '^(/usr/lib/|/System/|@loader_path/)' | sort -u || true)"
if [[ -n "$outside" ]]; then
  echo "ERROR: ffmpeg masih memuat library dari luar bundle:" >&2
  echo "$outside" >&2
  echo "Jalankan: tools/bundle_ffmpeg_dylibs.sh bin" >&2
  exit 1
fi

# ── Sign ─────────────────────────────────────────────────────────────────────
#
# Signed inside-out, deepest code first. `codesign --deep` is deliberately NOT
# used: Apple documents it as unsuitable for distribution signing because it
# re-signs nested code (FlutterMacOS.framework, the media_kit libmpv dylibs)
# with the enclosing bundle's options rather than their own, which is a routine
# cause of notarization rejections. --deep on *--verify* is fine and is used
# below.
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
  info "codesign (Developer ID)"
  SIGN_ARGS=(--timestamp --options runtime --sign "$SIGN_IDENTITY")
else
  info "codesign (ad hoc)"
  warn "SIGN_IDENTITY tidak diset — ditandatangani ad hoc."
  warn "Pengguna perlu menyetujui app sekali di Privacy & Security."
  # Ad hoc signatures reject --timestamp, and the hardened runtime's library
  # validation would refuse dylibs that share no Team ID with the app.
  SIGN_ARGS=(--sign -)
fi

sign_one() {
  codesign --force "${SIGN_ARGS[@]}" "$1"
  echo "  signed ${1#"$BUILD_APP"/}"
}

# Stale extended attributes make codesign fail with "resource fork ... not allowed".
xattr -cr "$BUILD_APP"

# 1. Dylibs and frameworks, deepest path first.
while IFS= read -r item; do
  sign_one "$item"
done < <(find "$BUILD_APP/Contents/Frameworks" \
           \( -name '*.dylib' -o -name '*.framework' \) -depth 2>/dev/null | awk '{ print length, $0 }' \
         | sort -rn | cut -d' ' -f2-)

# 2. The bundled CLI helpers and the libraries ffmpeg loads.
while IFS= read -r binary; do
  sign_one "$binary"
done < <(find "$RESOURCE_BIN" -type f \( -perm -u+x -o -name '*.dylib' \))

# 3. The app bundle itself — the only place entitlements apply.
codesign --force "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$BUILD_APP"

codesign --verify --deep --strict --verbose=2 "$BUILD_APP"
ok "app ditandatangani"

# ── DMG ──────────────────────────────────────────────────────────────────────
info "mengemas dmg"
VERSION_NAME="$(grep '^version:' pubspec.yaml | head -1 | sed 's/version:[[:space:]]*//' | cut -d+ -f1)"
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION_NAME-macos.dmg"
rm -f "$DMG_PATH"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$BUILD_APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp -f "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
ok "dmg: $DMG_PATH"

# ── Notarize ─────────────────────────────────────────────────────────────────
if [[ -n "$NOTARY_PROFILE" && -n "$SIGN_IDENTITY" ]]; then
  info "notarisasi"
  codesign --force --timestamp --options runtime \
    --sign "$SIGN_IDENTITY" "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  ok "dmg dinotarisasi dan di-staple"
else
  warn "NOTARY_PROFILE tidak diset — melewati notarisasi."
  warn "Siapkan sekali dengan:"
  warn "  xcrun notarytool store-credentials labscale-notary \\"
  warn "    --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PW"
fi

ok $'\nSelesai.'
