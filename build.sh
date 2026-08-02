#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/LangSwitcher.app"
MACOS_DIR="$APP/Contents/MacOS"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

"$ROOT/make-icon.sh" >/dev/null
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

swiftc -O \
    "$ROOT/Sources/"*.swift \
    -o "$MACOS_DIR/LangSwitcher" \
    -framework Cocoa \
    -framework SwiftUI \
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
