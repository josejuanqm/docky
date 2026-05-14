#!/bin/bash
#
# build-mas.sh
#
# Validates the App Store target compiles cleanly with
# `APP_STORE_SANDBOX` active. Run after creating the
# "Docky (App Store)" scheme in Xcode (see MAS_STATUS.md step 1).
#
# What this checks:
#   1. No ungated private-API surface (delegates to check-mas-clean.sh).
#   2. The MAS scheme builds without compile errors.
#   3. The resulting .app bundle does NOT contain references to
#      `/System/Library/PrivateFrameworks/SkyLight.framework` in any
#      embedded binary.
#   4. The resulting .app bundle does NOT contain
#      `mediaremote-adapter.pl` or `MediaRemoteAdapter.framework`.
#
# Run before every MAS submission. Output a final OK / FAIL summary.
#

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Docky (App Store)"
CONFIGURATION="Release"

#
# 1. Source-level private-API leak check.
#
echo "==> Running scripts/check-mas-clean.sh"
./scripts/check-mas-clean.sh

#
# 2. Compile the MAS scheme.
#
echo
echo "==> Building scheme: $SCHEME ($CONFIGURATION)"
DERIVED_DATA=$(mktemp -d)
trap 'rm -rf "$DERIVED_DATA"' EXIT

if ! xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    build > "$DERIVED_DATA/build.log" 2>&1; then
    echo "FAILED: build error. See $DERIVED_DATA/build.log"
    grep "error:" "$DERIVED_DATA/build.log" | head -20
    exit 1
fi

APP_PATH=$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -name "*.app" -maxdepth 2 -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "FAILED: no .app produced under $DERIVED_DATA"
    exit 1
fi

echo "    .app at: $APP_PATH"

#
# 3. Binary scan for private framework references.
#
echo
echo "==> Scanning embedded binaries for private framework references"

LEAKS=$(find "$APP_PATH" -type f \( -name '*.dylib' -o -name 'Docky' -o -path '*/MacOS/*' \) -exec strings {} \; 2>/dev/null \
    | grep -E "SkyLight|MediaRemote\.framework" || true)

if [ -n "$LEAKS" ]; then
    echo "FAILED: private framework name found in MAS binary:"
    echo "$LEAKS" | head -10
    exit 1
fi

#
# 4. Bundle resource scan.
#
echo
echo "==> Scanning bundled resources for excluded files"

if find "$APP_PATH" -name "mediaremote-adapter.pl" -o -name "MediaRemoteAdapter.framework" | grep -q .; then
    echo "FAILED: excluded resource present in MAS .app:"
    find "$APP_PATH" -name "mediaremote-adapter.pl" -o -name "MediaRemoteAdapter.framework"
    exit 1
fi

echo
echo "==> OK: MAS build is clean. Ready for Archive → Validate → Distribute."
