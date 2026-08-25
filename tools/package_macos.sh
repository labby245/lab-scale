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
# Signing is optional. Without SIGN_IDENTITY the script still produces a working
# local build; it just cannot be distributed to other Macs without Gatekeeper
# warnings.
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
PAYLOAD_DIRS=(models rife-v4.6)   # Real-ESRGAN weights + the one RIFE model

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

for name in "${PAYLOAD_DIRS[@]}"; do
  if [[ -d "$BIN_DIR/$name" ]]; then
    cp -R "$BIN_DIR/$name" "$RESOURCE_BIN/$name"
    echo "  $name/"
  fi
done

# ── Sign ─────────────────────────────────────────────────────────────────────
#
# Signed inside-out, deepest code first. `codesign --deep` is deliberately NOT
# used: Apple documents it as unsuitable for distribution signing because it
# re-signs nested code (FlutterMacOS.framework, the media_kit libmpv dylibs)
# with the enclosing bundle's options rather than their own, which is a routine
# cause of notarization rejections. --deep on *--verify* is fine and is used
# below.
if [[ -n "$SIGN_IDENTITY" ]]; then
  info "codesign"
  ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"

  sign_one() {
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$1"
    echo "  signed $(basename "$1")"
  }

  # Stale extended attributes make codesign fail with "resource fork ... not allowed".
  xattr -cr "$BUILD_APP"

  # 1. Dylibs and frameworks, deepest path first.
  while IFS= read -r item; do
    sign_one "$item"
  done < <(find "$BUILD_APP/Contents/Frameworks" \
             \( -name '*.dylib' -o -name '*.framework' \) -depth 2>/dev/null | awk '{ print length, $0 }' \
           | sort -rn | cut -d' ' -f2-)

  # 2. The bundled CLI helpers.
  while IFS= read -r binary; do
    sign_one "$binary"
  done < <(find "$RESOURCE_BIN" -type f -perm -u+x)

  # 3. The app bundle itself — the only place entitlements apply.
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$BUILD_APP"

  codesign --verify --deep --strict --verbose=2 "$BUILD_APP"
  ok "app ditandatangani"
else
  warn "SIGN_IDENTITY tidak diset — melewati codesign."
  warn "Build ini hanya untuk mesin ini sendiri, belum bisa didistribusikan."
fi

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
