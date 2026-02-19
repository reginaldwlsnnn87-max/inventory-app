# Pulse Remote App Icon Setup

Use this guide to install your production app icon into `AppIcon.appiconset`.

## 1) Add Source Files

Place files in:

`/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj/Branding/AppIconSource`

Supported source formats: `png`, `jpg`, `jpeg`

Required (one of these):

- `pulse_remote.png`
- `app_icon.png`

Optional variants:

- `pulse_remote_dark.png` or `app_icon_dark.png`
- `pulse_remote_tinted.png` or `app_icon_tinted.png`

## 2) Run Installer

```bash
bash "/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj/Branding/install_app_icon.sh"
```

What it does:

- Converts icon source files to `1024x1024` PNG
- Writes `AppIcon.appiconset/Contents.json` cleanly
- Installs:
  - `icon-1024.png` (required)
  - `icon-1024-dark.png` (optional)
  - `icon-1024-tinted.png` (optional)

## 3) Build Check

```bash
xcodebuild -project "/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj" -scheme "Pulse Remote" -destination "generic/platform=iOS Simulator" build
```

## Production Icon Notes

- Keep one strong center shape (power glyph + ring).
- Remove tiny corner details that blur at small sizes.
- Avoid fine glow details thinner than 2-3 px at 1024.
- Verify legibility at 180, 120, 60, and 40 px exports.
