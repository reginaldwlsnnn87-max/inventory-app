#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="${1:-$SCRIPT_DIR/AppIconSource}"

resolve_asset_catalog() {
  local candidates=(
    "$PROJECT_ROOT/../inventory app/Assets.xcassets"
    "$PROJECT_ROOT/Assets.xcassets"
  )

  local path
  for path in "${candidates[@]}"; do
    if [[ -d "$path" ]]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

find_first_source() {
  local base="$1"
  local ext
  for ext in png jpg jpeg; do
    if [[ -f "$SOURCE_DIR/$base.$ext" ]]; then
      echo "$SOURCE_DIR/$base.$ext"
      return 0
    fi
  done
  return 1
}

if ! ASSET_CATALOG="$(resolve_asset_catalog)"; then
  echo "error: could not find Assets.xcassets." >&2
  echo "Looked in:" >&2
  echo "  $PROJECT_ROOT/../inventory app/Assets.xcassets" >&2
  echo "  $PROJECT_ROOT/Assets.xcassets" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "error: sips is required but not available on this machine." >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "error: source folder not found: $SOURCE_DIR" >&2
  echo "Create it and add your icon source files first." >&2
  exit 1
fi

if ! PRIMARY_SOURCE="$(find_first_source "pulse_remote")"; then
  if ! PRIMARY_SOURCE="$(find_first_source "app_icon")"; then
    echo "error: missing app icon source file." >&2
    echo "Expected one of:" >&2
    echo "  $SOURCE_DIR/pulse_remote.png (or .jpg/.jpeg)" >&2
    echo "  $SOURCE_DIR/app_icon.png (or .jpg/.jpeg)" >&2
    exit 1
  fi
fi

DARK_SOURCE="$(find_first_source "pulse_remote_dark" || true)"
if [[ -z "$DARK_SOURCE" ]]; then
  DARK_SOURCE="$(find_first_source "app_icon_dark" || true)"
fi

TINTED_SOURCE="$(find_first_source "pulse_remote_tinted" || true)"
if [[ -z "$TINTED_SOURCE" ]]; then
  TINTED_SOURCE="$(find_first_source "app_icon_tinted" || true)"
fi

ICONSET_DIR="$ASSET_CATALOG/AppIcon.appiconset"
mkdir -p "$ICONSET_DIR"

# Remove stale icon files so actool does not report unassigned children.
find "$ICONSET_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -delete

echo "Using asset catalog: $ASSET_CATALOG"
echo "Using icon source dir: $SOURCE_DIR"
echo "Primary icon: $PRIMARY_SOURCE"
if [[ -n "$DARK_SOURCE" ]]; then
  echo "Dark icon: $DARK_SOURCE"
fi
if [[ -n "$TINTED_SOURCE" ]]; then
  echo "Tinted icon: $TINTED_SOURCE"
fi

sips -s format png -z 1024 1024 "$PRIMARY_SOURCE" --out "$ICONSET_DIR/icon-1024.png" >/dev/null

dark_entry=
if [[ -n "$DARK_SOURCE" ]]; then
  sips -s format png -z 1024 1024 "$DARK_SOURCE" --out "$ICONSET_DIR/icon-1024-dark.png" >/dev/null
  dark_entry='      "filename" : "icon-1024-dark.png",'
else
  rm -f "$ICONSET_DIR/icon-1024-dark.png"
fi

tinted_entry=
if [[ -n "$TINTED_SOURCE" ]]; then
  sips -s format png -z 1024 1024 "$TINTED_SOURCE" --out "$ICONSET_DIR/icon-1024-tinted.png" >/dev/null
  tinted_entry='      "filename" : "icon-1024-tinted.png",'
else
  rm -f "$ICONSET_DIR/icon-1024-tinted.png"
fi

cat >"$ICONSET_DIR/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
$dark_entry
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
$tinted_entry
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Installed app icon set into: $ICONSET_DIR"
echo "Done."
