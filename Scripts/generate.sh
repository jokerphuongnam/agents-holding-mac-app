#!/usr/bin/env bash
# Regenerate codegen + Xcode project for AgentsHoldingApp.
# Requires only: Swift toolchain (Xcode). No Homebrew.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> AgentsHoldingApp generate ($ROOT)"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found (install Xcode / Command Line Tools)" >&2
  exit 1
fi

BUILD_TOOLS="$ROOT/BuildTools"
if [[ ! -f "$BUILD_TOOLS/Package.swift" ]]; then
  echo "error: missing BuildTools/Package.swift" >&2
  exit 1
fi

find_checkout() {
  local prefix="$1"
  find "$BUILD_TOOLS/.build/checkouts" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | head -1 || true
}

# Strip Finder/xattr detritus that breaks codesign on SPM resource bundles (SwiftGen).
scrub_checkout() {
  local pkg="$1"
  if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$pkg" 2>/dev/null || true
    # Also scrub nested build products if present
    if [[ -d "$pkg/.build" ]]; then
      xattr -cr "$pkg/.build" 2>/dev/null || true
    fi
  fi
}

run_spm_tool() {
  # $1 = checkout directory name prefix (SwiftGen / XcodeGen)
  # $2 = executable product name
  # remaining = args for the tool
  local checkout_prefix="$1"
  local product="$2"
  shift 2

  local pkg
  pkg="$(find_checkout "$checkout_prefix")"
  if [[ -z "${pkg}" || ! -f "${pkg}/Package.swift" ]]; then
    echo "error: ${checkout_prefix} checkout missing under BuildTools/.build/checkouts" >&2
    exit 1
  fi

  scrub_checkout "$pkg"

  # Reuse previously built binary when possible (faster; avoids re-codesign flakes).
  local bin=""
  for candidate in \
    "$pkg/.build/debug/${product}" \
    "$pkg/.build/release/${product}" \
    "$pkg/.build/out/Products/Debug/${product}" \
    "$pkg/.build/arm64-apple-macosx/debug/${product}" \
    "$pkg/.build/arm64-apple-macosx/release/${product}"
  do
    if [[ -x "$candidate" ]]; then
      bin="$candidate"
      break
    fi
  done

  if [[ -n "$bin" ]]; then
    echo "    running cached ${product}: ${bin}"
    "$bin" "$@"
    return
  fi

  echo "    building & running ${product} from ${pkg}…"
  # Disable automatic codesign issues on some macOS/SPM combos
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=- \
    swift run --package-path "$pkg" "$product" "$@" \
    || {
      echo "    retry after xattr scrub…"
      scrub_checkout "$pkg"
      find "$pkg/.build" -name '*.bundle' -exec xattr -cr {} \; 2>/dev/null || true
      CODE_SIGNING_ALLOWED=NO swift run --package-path "$pkg" "$product" "$@"
    }
}

echo "    resolving BuildTools SPM (SwiftGen + XcodeGen)…"
swift package --package-path "$BUILD_TOOLS" resolve

mkdir -p AgentsHoldingApp/Generated
run_spm_tool SwiftGen swiftgen config run --config "$ROOT/swiftgen.yml"
echo "    ok  AgentsHoldingApp/Generated/Strings+Generated.swift"

if [[ "${SKIP_XCODEGEN:-0}" != "1" ]]; then
  run_spm_tool XcodeGen xcodegen generate --spec "$ROOT/project.yml"
  echo "    ok  AgentsHoldingApp.xcodeproj"
else
  echo "    skip xcodegen (SKIP_XCODEGEN=1)"
fi

echo "==> generate done (Swift toolchain only — no Homebrew)"
