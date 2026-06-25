#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/LangSwitcher.app"
MACOS_DIR="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS_DIR"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

swiftc -O \
    "$ROOT/Sources/"*.swift \
    -o "$MACOS_DIR/LangSwitcher" \
    -framework Cocoa \
    -framework ServiceManagement \
    -framework QuartzCore \
    -framework Carbon

# Sign with a stable self-signed identity if present, so the Accessibility
# grant survives rebuilds. Falls back to ad-hoc (grant must be re-given each
# rebuild). See README for how to create the identity.
IDENTITY="LangSwitcher Self-Signed"
if security find-identity -v 2>/dev/null | grep -q "$IDENTITY" \
   || security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed: ad-hoc (no stable identity found)"
fi

echo "Built: $APP"
