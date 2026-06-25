# LangSwitcher

A headless macOS background app. Press **Shift twice quickly** to fix text typed
in the wrong keyboard layout (US-QWERTY ⇄ Russian ЙЦУКЕН).

- Type `рщгыу`, double-tap Shift → it becomes `house`.
- Or select any text and double-tap Shift to convert the selection.

Direction is auto-detected: Cyrillic → Latin, otherwise Latin → Cyrillic.
No window, no Dock icon, no menu bar. Launches at login.

## Build

```sh
./build.sh
```

This produces `build/LangSwitcher.app` (ad-hoc signed).

## Install / run

1. Move the app where you want it to live (so the path stays stable):
   ```sh
   cp -R build/LangSwitcher.app /Applications/
   open /Applications/LangSwitcher.app
   ```
2. On first launch macOS prompts for **Accessibility** access. Grant it in
   **System Settings → Privacy & Security → Accessibility** (toggle LangSwitcher on).
   The app polls every 2s and starts working the moment access is granted.
3. It registers itself to **launch at login** automatically.

> Always rebuild with `build.sh` (it re-signs ad-hoc) and run from the **same
> path**. If you move the app, you may need to re-grant Accessibility.

## How it works

- A `CGEventTap` detects two Shift presses within 350 ms with no key in between.
- It copies the current selection (⌘C); if nothing is selected it selects the
  previous word (⇧⌥←) and copies that.
- The text is remapped per-character between layouts and pasted back (⌘V).
- Your original clipboard contents are restored afterward.

## Tuning

- Double-tap window: `maxInterval` in `Sources/DoubleShiftDetector.swift`.
- Paste/copy timing: the `usleep` values in `Sources/Switcher.swift`.
