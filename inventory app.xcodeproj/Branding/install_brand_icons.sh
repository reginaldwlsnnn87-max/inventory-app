#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="${1:-$SCRIPT_DIR/BrandIconsSource}"

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
  echo "Create it and add brand icons first." >&2
  exit 1
fi

echo "Using asset catalog: $ASSET_CATALOG"
echo "Using icon source dir: $SOURCE_DIR"

icon_keys=(
  netflix
  youtube
  youtube_tv
  prime_video
  disney_plus
  apple_tv
  plex
)

imageset_for() {
  case "$1" in
    netflix) echo "TVApp.netflix.imageset" ;;
    youtube) echo "TVApp.youtube.imageset" ;;
    youtube_tv) echo "TVApp.youtubeTV.imageset" ;;
    prime_video) echo "TVApp.primeVideo.imageset" ;;
    disney_plus) echo "TVApp.disneyPlus.imageset" ;;
    apple_tv) echo "TVApp.appleTV.imageset" ;;
    plex) echo "TVApp.plex.imageset" ;;
    *) return 1 ;;
  esac
}

find_source_file() {
  local key="$1"
  local ext
  for ext in png jpg jpeg pdf; do
    if [[ -f "$SOURCE_DIR/$key.$ext" ]]; then
      echo "$SOURCE_DIR/$key.$ext"
      return 0
    fi
  done
  return 1
}

write_imageset_contents() {
  local dir="$1"
  cat >"$dir/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon-1x.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "icon-2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "icon-3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
}

installed=()
missing=()

for key in "${icon_keys[@]}"; do
  if ! src_file="$(find_source_file "$key")"; then
    missing+=("$key")
    continue
  fi

  imageset_name="$(imageset_for "$key")"
  imageset_dir="$ASSET_CATALOG/$imageset_name"
  mkdir -p "$imageset_dir"

  sips -s format png -z 64 64 "$src_file" --out "$imageset_dir/icon-1x.png" >/dev/null
  sips -s format png -z 128 128 "$src_file" --out "$imageset_dir/icon-2x.png" >/dev/null
  sips -s format png -z 192 192 "$src_file" --out "$imageset_dir/icon-3x.png" >/dev/null
  write_imageset_contents "$imageset_dir"

  installed+=("$key")
done

echo "Installed ${#installed[@]} brand icon sets."
if [[ ${#installed[@]} -gt 0 ]]; then
  echo "Installed: ${installed[*]}"
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing source files: ${missing[*]}"
  echo "Add files to: $SOURCE_DIR"
  echo "Expected names: netflix.png, youtube.png, youtube_tv.png, prime_video.png, disney_plus.png, apple_tv.png, plex.png"
fi
