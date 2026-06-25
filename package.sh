#!/bin/bash
# Builds a shareable arm64 LangSwitcher.zip containing the app and a
# double-click installer for a friend on Apple Silicon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/build/dist/LangSwitcher"
APP="$STAGE/LangSwitcher.app"
MACOS_DIR="$APP/Contents/MacOS"
ZIP="$ROOT/build/LangSwitcher.zip"

rm -rf "$ROOT/build/dist" "$ZIP"
mkdir -p "$MACOS_DIR"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# arm64-only build.
swiftc -O -target arm64-apple-macosx13.0 \
    "$ROOT/Sources/"*.swift \
    -o "$MACOS_DIR/LangSwitcher" \
    -framework Cocoa -framework ServiceManagement -framework QuartzCore -framework Carbon

# Ad-hoc sign: required for the app to run at all on Apple Silicon, and needs
# no certificate on the recipient's machine.
codesign --force --deep --sign - "$APP"

# Double-click installer the friend runs.
cat > "$STAGE/Install LangSwitcher.command" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/LangSwitcher.app"
DEST="/Applications/LangSwitcher.app"

echo "Installing LangSwitcher..."
killall LangSwitcher 2>/dev/null
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
# Clear the "downloaded from the internet" quarantine so it launches cleanly.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
open "$DEST"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "Almost done! One manual step:"
echo "  In the window that just opened (Privacy & Security > Accessibility),"
echo "  turn ON the switch next to LangSwitcher."
echo ""
echo "Then double-tap Shift to convert the last word or your selection"
echo "between English and Russian layouts. You can close this window."
EOF
chmod +x "$STAGE/Install LangSwitcher.command"

# Short readme for the friend.
cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
LangSwitcher — fix text typed in the wrong keyboard layout (English <-> Russian).

INSTALL
1. Double-click "Install LangSwitcher.command".
2. macOS will block it with a warning like "Apple could not verify..."
   This is normal for free apps. Click Done (or Cancel) to dismiss it.
3. Open  System Settings > Privacy & Security  and scroll down to the
   "Security" section. You'll see a line:
       "Install LangSwitcher.command" was blocked...
   Click  Open Anyway  next to it, and confirm with your password/Touch ID.
   (If it asks once more when it actually starts, click Open.)
4. A Terminal window runs the installer, then System Settings opens to
   Privacy & Security > Accessibility. Turn ON the LangSwitcher switch.

   --- If step 3 doesn't show "Open Anyway" ---
   Open the Terminal app and paste this line, then press Return:
       xattr -dr com.apple.quarantine ~/Downloads/LangSwitcher
   (adjust the path if you unzipped somewhere other than Downloads),
   then double-click "Install LangSwitcher.command" again.

USE
- Type a word in the wrong layout (e.g. "рщгыу"), then press Shift twice
  quickly -> it becomes "house". Works both directions.
- Or select any text and double-tap Shift to convert the selection.

It runs in the background with no icon and starts automatically at login.
EOF

# Strip extended attributes, then zip with -X (no AppleDouble/._ sidecars).
# zip preserves the executable bit; the ad-hoc signature lives inside the
# Mach-O / _CodeSignature, not in xattrs, so it survives.
xattr -cr "$STAGE"
( cd "$ROOT/build/dist" && zip -r -X -q "$ZIP" LangSwitcher )

echo ""
echo "Shareable file: $ZIP"
