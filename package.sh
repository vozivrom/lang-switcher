#!/bin/bash
# Builds a shareable arm64 DMG. The version in ./VERSION is the single source
# of truth: it is stamped into the bundle and used to name the DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
STAGE="$ROOT/build/dmg"
APP="$STAGE/LangSwitcher.app"
MACOS_DIR="$APP/Contents/MacOS"
DMG="$ROOT/build/LangSwitcher-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$MACOS_DIR" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

"$ROOT/make-icon.sh" >/dev/null
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# arm64-only build.
swiftc -O -target arm64-apple-macosx13.0 \
    "$ROOT/Sources/"*.swift \
    -o "$MACOS_DIR/LangSwitcher" \
    -framework Cocoa -framework SwiftUI -framework ServiceManagement -framework QuartzCore -framework Carbon

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Never ship a DMG whose name disagrees with the binary inside it.
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ "$BUNDLE_VERSION" != "$VERSION" ]; then
    echo "ERROR: bundle is $BUNDLE_VERSION but VERSION says $VERSION" >&2
    exit 1
fi

# Sign with the stable identity when it's available.
#
# An ad-hoc signature's designated requirement is the binary's own hash, so
# macOS treats every build as a different app and the user has to re-grant
# Accessibility on each update. Signing with a certificate pins the requirement
# to the certificate instead, so grants survive updates. The certificate is
# embedded in the signature, so recipients need nothing installed — Gatekeeper
# still warns once, because it isn't an Apple-issued Developer ID.
IDENTITY="LangSwitcher Self-Signed"
if security find-identity -v 2>/dev/null | grep -q "$IDENTITY" \
   || security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed: ad-hoc (updates will reset the user's permissions)"
fi

# Drag-to-install layout.
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
LangSwitcher — fix text typed in the wrong keyboard layout.

INSTALL
1. Drag LangSwitcher onto the Applications folder in this window.
2. Open Applications and double-click LangSwitcher.
3. macOS will say it "cannot verify the developer". This is expected for a
   free app that isn't registered with Apple. Click Done.
4. Open  System Settings > Privacy & Security , scroll to the Security
   section, and click  Open Anyway  next to LangSwitcher. Confirm.
5. Turn ON LangSwitcher under  Privacy & Security > Accessibility .
   It needs this to read the word you're fixing and type the replacement.

USE
- Type a word in the wrong layout (e.g. "рщгыу") and press Shift twice
  quickly -> it becomes "house". Press again to cycle to the next layout.
- Or select any text and double-tap Shift to convert the selection.
- Click the globe icon in the menu bar to choose your languages and whether
  it converts the last word or the whole text.

It starts automatically at login and has no Dock icon.
EOF

xattr -cr "$STAGE"
hdiutil create -volname "LangSwitcher" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"

echo ""
echo "Shareable file: $DMG"
echo "SHA256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
