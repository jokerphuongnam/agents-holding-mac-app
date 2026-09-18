#!/usr/bin/env bash
# Regenerate codegen for AgentsHoldingApp.
# SwiftGen comes from SPM (BuildTools/) — no `brew install swiftgen` needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> AgentsHoldingApp generate ($ROOT)"

mkdir -p AgentsHoldingApp/Generated

# --- Resolve / run SwiftGen via local SPM package BuildTools ---
BUILD_TOOLS="$ROOT/BuildTools"
if [[ ! -f "$BUILD_TOOLS/Package.swift" ]]; then
  echo "error: missing BuildTools/Package.swift (SwiftGen SPM wrapper)" >&2
  exit 1
fi

echo "    resolving SwiftGen (SPM BuildTools)…"
swift package --package-path "$BUILD_TOOLS" resolve

# Prefer running the dependency executable from its checkout (product `swiftgen`).
SWIFTGEN_PKG="$(find "$BUILD_TOOLS/.build/checkouts" -maxdepth 1 -type d -name 'SwiftGen*' 2>/dev/null | head -1 || true)"
if [[ -z "${SWIFTGEN_PKG}" || ! -f "${SWIFTGEN_PKG}/Package.swift" ]]; then
  echo "error: SwiftGen checkout not found under BuildTools/.build/checkouts" >&2
  echo "       try: swift package --package-path BuildTools resolve" >&2
  exit 1
fi

echo "    running swiftgen from ${SWIFTGEN_PKG}…"
# Args after product name are passed to swiftgen (do not insert a bare `--`).
swift run --package-path "$SWIFTGEN_PKG" swiftgen config run --config "$ROOT/swiftgen.yml"
echo "    ok  AgentsHoldingApp/Generated/Strings+Generated.swift"

# --- XcodeGen (optional) ---
if [[ "${SKIP_XCODEGEN:-0}" != "1" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
    echo "    ok  AgentsHoldingApp.xcodeproj"
  else
    echo "    skip xcodegen (not installed; brew install xcodegen)"
  fi
fi

echo "==> generate done"
