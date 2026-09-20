#!/usr/bin/env bash
# One-line install → /Applications:
#   curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash
#
# Downloads the prebuilt DMG from GitHub Releases and installs the .app into
# /Applications (prompts for admin if needed) — no clone, no local compile.
set -euo pipefail

exec </dev/null

REPO="${AGENTS_HOLDING_MAC_REPO:-jokerphuongnam/agents-holding-mac-app}"
ASSET_NAME="${AGENTS_HOLDING_MAC_DMG:-AgentsHolding-mac.dmg}"
TAG="${AGENTS_HOLDING_MAC_TAG:-latest}" # latest | v1.0.1
INSTALL_DIR="${AGENTS_HOLDING_MAC_APP_DIR:-/Applications}"
OPEN_APP=1
KEEP_DMG=0

usage() {
  cat <<'USAGE'
Install prebuilt Agents Holding macOS app from GitHub Releases into /Applications.

  curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash

Options (bash -s):
  --tag v1.0.1          Release tag (default: latest)
  --asset NAME.dmg      Asset filename (default: AgentsHolding-mac.dmg)
  --dir /Applications   Install directory (default: /Applications)
  --no-open             Do not launch the app after install
  --keep-dmg            Keep downloaded DMG in ~/Downloads
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift 2 ;;
    --asset) ASSET_NAME="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --no-open) OPEN_APP=0; shift ;;
    --keep-dmg) KEEP_DMG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: need '$1' on PATH" >&2
    exit 1
  }
}

need_cmd curl
need_cmd hdiutil
need_cmd ditto

api_url() {
  if [[ "$TAG" == "latest" ]]; then
    echo "https://api.github.com/repos/${REPO}/releases/latest"
  else
    echo "https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
  fi
}

echo "[install] fetching release metadata ($TAG)…"
META="$(curl -fsSL "$(api_url)")" || {
  echo "error: could not fetch release from GitHub ($REPO $TAG)." >&2
  echo "       Publish a Release with asset $ASSET_NAME first:" >&2
  echo "         ./Scripts/package-dmg.sh && gh release create v1.0.1 dist/$ASSET_NAME --latest" >&2
  exit 1
}

DMG_URL=""
if command -v python3 >/dev/null 2>&1; then
  DMG_URL="$(
    printf '%s' "$META" | python3 -c '
import json, sys
asset = sys.argv[1]
data = json.load(sys.stdin)
for a in data.get("assets") or []:
    if a.get("name") == asset:
        print(a.get("browser_download_url") or "")
        break
' "$ASSET_NAME" 2>/dev/null || true
  )"
fi
if [[ -z "$DMG_URL" ]]; then
  DMG_URL="$(printf '%s' "$META" | grep -oE "https://[^\"]+/${ASSET_NAME//./\\.}" | head -1 || true)"
fi

if [[ -z "$DMG_URL" ]]; then
  echo "error: asset '$ASSET_NAME' not found on release $TAG" >&2
  echo "       Upload $ASSET_NAME to https://github.com/${REPO}/releases" >&2
  exit 1
fi

TMPDIR_DL="$(mktemp -d "${TMPDIR:-/tmp}/agents-holding-mac.XXXXXX")"
DMG_PATH="$TMPDIR_DL/$ASSET_NAME"
cleanup() {
  if [[ "$KEEP_DMG" -eq 1 ]]; then
    mkdir -p "$HOME/Downloads"
    cp -f "$DMG_PATH" "$HOME/Downloads/$ASSET_NAME" 2>/dev/null || true
    echo "[install] kept DMG → ~/Downloads/$ASSET_NAME"
  fi
  # detach any leftover mount
  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_DL"
}
trap cleanup EXIT

echo "[install] downloading $DMG_URL"
curl -fL --progress-bar -o "$DMG_PATH" "$DMG_URL"

echo "[install] mounting DMG…"
ATTACH_OUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "error: could not mount DMG" >&2
  exit 1
fi

APP_SRC="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -type d | head -1)"
if [[ -z "$APP_SRC" ]]; then
  echo "error: no .app inside DMG ($MOUNT_POINT)" >&2
  exit 1
fi
APP_NAME="$(basename "$APP_SRC")"

DEST_APP="$INSTALL_DIR/$APP_NAME"
echo "[install] installing → $DEST_APP"

run_priv() {
  # Use sudo only when the install dir is not writable (typical for /Applications).
  if [[ -d "$INSTALL_DIR" && -w "$INSTALL_DIR" ]] || mkdir -p "$INSTALL_DIR" 2>/dev/null; then
    if [[ -w "$INSTALL_DIR" ]]; then
      "$@"
      return
    fi
  fi
  echo "[install] admin password required to write $INSTALL_DIR"
  sudo "$@"
}

run_priv mkdir -p "$INSTALL_DIR"
run_priv rm -rf "$DEST_APP"
run_priv ditto "$APP_SRC" "$DEST_APP"
# Clear quarantine so Gatekeeper does not block first launch of a curl-installed app.
if command -v xattr >/dev/null 2>&1; then
  run_priv xattr -cr "$DEST_APP" 2>/dev/null || true
fi

hdiutil detach "$MOUNT_POINT" -quiet || true
MOUNT_POINT=""

if [[ "$OPEN_APP" -eq 1 ]]; then
  echo "[install] launching…"
  open "$DEST_APP"
fi

echo
echo "[install] done → $DEST_APP"
echo "  Re-run: curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash"
