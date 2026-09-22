#!/usr/bin/env bash
# Build a distributable DMG (Release) for GitHub Releases.
# Usage:
#   ./Scripts/package-dmg.sh
#   ./Scripts/package-dmg.sh --skip-generate
#
# Output: dist/AgentsHolding-mac.dmg
# Upload that asset to a GitHub Release so install.sh can curl it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_GENERATE=0
CONFIGURATION=Release
SCHEME=AgentsHoldingApp
DERIVED="${ROOT}/build/DerivedData"
DIST="${ROOT}/dist"
VOL_NAME="Agents Holding"
DMG_NAME="AgentsHolding-mac.dmg"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-generate) SKIP_GENERATE=1; shift ;;
    --debug) CONFIGURATION=Debug; shift ;;
    -h|--help)
      echo "Usage: $0 [--skip-generate] [--debug]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: need '$1' on PATH" >&2
    exit 1
  }
}

need_cmd swift
need_cmd xcodebuild
need_cmd hdiutil

if [[ "$SKIP_GENERATE" -eq 0 ]]; then
  bash "$ROOT/Scripts/generate.sh"
fi

echo "==> xcodebuild $CONFIGURATION ($SCHEME)"
rm -rf "$DERIVED"
# Avoid codesign flakes from Finder xattrs during Release build.
xcodebuild \
  -project "$ROOT/AgentsHoldingApp.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$(find "$DERIVED/Build/Products/$CONFIGURATION" -maxdepth 1 -name '*.app' -type d | head -1)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: .app not found under $DERIVED/Build/Products/$CONFIGURATION" >&2
  exit 1
fi
echo "    app: $APP"

STAGE="$DIST/dmg-root"
rm -rf "$STAGE" "$DIST/$DMG_NAME"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$(basename "$APP")"
# Strip resource forks / xattrs that break Gatekeeper & codesign
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$STAGE"
fi
# Ad-hoc sign for local distribution (not notarized)
codesign --force --deep --sign - "$STAGE/$(basename "$APP")" || true
# Drag-to-Applications convenience
ln -s /Applications "$STAGE/Applications"

echo "==> creating $DIST/$DMG_NAME"
mkdir -p "$DIST"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DIST/$DMG_NAME"

echo
echo "==> done: $DIST/$DMG_NAME"
echo "Upload to GitHub Release (tag), e.g.:"
echo "  gh release create v1.1.0 \"$DIST/$DMG_NAME\" --title \"v1.1.0\" --latest --notes \"Agents Holding macOS\""
echo "install.sh will download the latest Release asset named $DMG_NAME"
