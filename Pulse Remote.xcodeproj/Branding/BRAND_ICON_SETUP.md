# Brand Icon Setup

This project supports official app logos for quick-launch tiles.

For the app launcher icon (`AppIcon.appiconset`), use:

`/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj/Branding/APP_ICON_SETUP.md`

## 1) Add Source Icon Files

Place source files in:

`/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj/Branding/BrandIconsSource`

Use these exact filenames (PNG preferred, JPG/PDF also supported):

- `netflix.png`
- `youtube.png`
- `youtube_tv.png`
- `prime_video.png`
- `disney_plus.png`
- `apple_tv.png`
- `plex.png`

Recommended source size: at least `512x512` (square).

## 2) Run Import Script

From the project root:

```bash
bash "/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj/Branding/install_brand_icons.sh"
```

What it does:

- Generates `1x/2x/3x` icon files for each app (`64/128/192` px)
- Writes each imageset `Contents.json`
- Installs icons into `/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote/Assets.xcassets/TVApp.*.imageset`

## 3) Build

```bash
xcodebuild -project "/Users/reggieboi/coding folder/Pulse Remote/Pulse Remote.xcodeproj" -scheme "Pulse Remote" -destination "generic/platform=iOS Simulator" build
```

## Runtime Fallback Order

App now renders icons in this order:

1. Bundled asset icon (`TVApp.*`)
2. LG-provided icon URL from launch points
3. Branded in-app fallback glyph
