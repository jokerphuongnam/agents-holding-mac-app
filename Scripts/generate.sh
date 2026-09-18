#!/usr/bin/env bash
# Regenerate codegen artifacts for AgentsHoldingApp.
# Run from repo root or any cwd; safe to run before every Xcode build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> AgentsHoldingApp generate ($ROOT)"

# --- SwiftGen (Localizable.strings → Strings+Generated.swift) ---
if ! command -v swiftgen >/dev/null 2>&1; then
  echo "error: swiftgen not found. Install: brew install swiftgen" >&2
  exit 1
fi

mkdir -p AgentsHoldingApp/Generated
swiftgen config run --config "$ROOT/swiftgen.yml"
echo "    ok  AgentsHoldingApp/Generated/Strings+Generated.swift"

# --- XcodeGen (optional; project.yml → .xcodeproj) ---
if [[ "${SKIP_XCODEGEN:-0}" != "1" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
    echo "    ok  AgentsHoldingApp.xcodeproj"
  else
    echo "    skip xcodegen (not installed)"
  fi
fi

echo "==> generate done"
