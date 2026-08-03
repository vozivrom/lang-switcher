#!/bin/bash
# Runs the logic tests. Exits non-zero if any fail.
#
# Covers the parts that can be tested without a running app: layout conversion,
# cycling, and settings. The keystroke and Accessibility paths need a real app
# with permissions and a focused text field, so they aren't covered here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/tests"

mkdir -p "$ROOT/build"

swiftc -O \
    "$ROOT/Tests/main.swift" \
    "$ROOT/Sources/Layout.swift" \
    "$ROOT/Sources/CycleEngine.swift" \
    "$ROOT/Sources/Settings.swift" \
    "$ROOT/Sources/Notifications.swift" \
    "$ROOT/Sources/AppLayoutMemory.swift" \
    "$ROOT/Sources/InputSource.swift" \
    "$ROOT/Sources/Hotkey.swift" \
    "$ROOT/Sources/UpdateChecker.swift" \
    -o "$BIN" \
    -framework Cocoa -framework Carbon

"$BIN"
