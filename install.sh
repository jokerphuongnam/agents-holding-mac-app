#!/usr/bin/env bash
# One-line install (recommended):
#   curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash
#
# Clones/updates this repo → runs Scripts/generate.sh (SwiftGen + XcodeGen via SPM).
# Requires: git, swift (Xcode). No Homebrew.
set -euo pipefail

# When piped via curl|bash, keep git/other tools from consuming stdin.
exec </dev/null

REPO_URL="${AGENTS_HOLDING_MAC_REPO:-https://github.com/jokerphuongnam/agents-holding-mac-app.git}"
REPO_REF="${AGENTS_HOLDING_MAC_REF:-main}"
DEST="${AGENTS_HOLDING_MAC_DEST:-$HOME/Documents/Agents/agents-holding-mac-app}"
FROM_LOCAL=""
OPEN_XCODE=1
SKIP_GENERATE=0

usage() {
  cat <<'USAGE'
Install agents-holding-mac-app (SwiftUI mission control).

  curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash

Options (with bash -s):
  curl -fsSL …/install.sh | bash -s -- --dest ~/Documents/Agents/agents-holding-mac-app
  curl -fsSL …/install.sh | bash -s -- --ref main
  curl -fsSL …/install.sh | bash -s -- --from-local /path/to/agents-holding-mac-app
  curl -fsSL …/install.sh | bash -s -- --no-open
  curl -fsSL …/install.sh | bash -s -- --skip-generate
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="${2:-}"; shift 2 ;;
    --repo) REPO_URL="${2:-}"; shift 2 ;;
    --ref) REPO_REF="${2:-}"; shift 2 ;;
    --from-local) FROM_LOCAL="${2:-}"; shift 2 ;;
    --no-open) OPEN_XCODE=0; shift ;;
    --skip-generate) SKIP_GENERATE=1; shift ;;
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

need_cmd git
need_cmd swift

resolve_pkg() {
  local root="$1"
  [[ -f "$root/Scripts/generate.sh" && -f "$root/project.yml" && -f "$root/swiftgen.yml" ]] || return 1
  echo "$root"
}

PKG=""
if [[ -n "$FROM_LOCAL" ]]; then
  FROM_LOCAL="$(cd "$FROM_LOCAL" && pwd)"
  PKG="$(resolve_pkg "$FROM_LOCAL" || true)"
  [[ -n "$PKG" ]] || {
    echo "error: --from-local is not agents-holding-mac-app: $FROM_LOCAL" >&2
    exit 1
  }
  DEST="$PKG"
  echo "[install] source=local $PKG"
else
  mkdir -p "$(dirname "$DEST")"
  if [[ -d "$DEST/.git" ]]; then
    echo "[install] updating $DEST ($REPO_REF)"
    git -C "$DEST" remote set-url origin "$REPO_URL" 2>/dev/null || true
    git -C "$DEST" fetch --depth 1 origin "$REPO_REF"
    git -C "$DEST" checkout -q "$REPO_REF" 2>/dev/null || git -C "$DEST" checkout -q -B "$REPO_REF" "origin/$REPO_REF"
    git -C "$DEST" reset --hard "origin/$REPO_REF"
  else
    echo "[install] cloning $REPO_URL ($REPO_REF) → $DEST"
    rm -rf "$DEST"
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$DEST"
  fi
  PKG="$(resolve_pkg "$DEST" || true)"
  [[ -n "$PKG" ]] || {
    echo "error: tree missing Scripts/generate.sh + project.yml: $DEST" >&2
    exit 1
  }
  echo "[install] source=git $(git -C "$DEST" rev-parse --short HEAD)"
fi

if [[ "$SKIP_GENERATE" -eq 0 ]]; then
  echo "[install] generate (SwiftGen + XcodeGen via SPM)…"
  bash "$PKG/Scripts/generate.sh"
else
  echo "[install] skip generate"
fi

XCODEPROJ="$PKG/AgentsHoldingApp.xcodeproj"
if [[ "$OPEN_XCODE" -eq 1 ]]; then
  if [[ -d "$XCODEPROJ" ]] && command -v open >/dev/null 2>&1; then
    echo "[install] opening Xcode…"
    open "$XCODEPROJ"
  else
    echo "[install] open manually: open $XCODEPROJ"
  fi
fi

echo
echo "[install] done → $PKG"
echo "  open $XCODEPROJ"
echo "  # re-run anytime:"
echo "  curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash"
