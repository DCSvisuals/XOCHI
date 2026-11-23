#!/bin/bash
# Rebuild XOCHI.app from the source files in this folder.
# Copies the launcher into the bundle, embeds the icon, sets the
# bundle identity, and ad-hoc signs the finished app.
# Does not open the app, copy it to /Applications, or reset Terminal permission.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")" && pwd)"
ICON_SOURCE="$PROJECT/Assets/XOCHI.png"
BUILD_DIR="$PROJECT/build"
IDENTIFIER="com.davidcarranco.xochi"
VERSION="$(sed -n 's/^XO_VERSION="\(.*\)"/\1/p' "$PROJECT/Common.sh" | head -1)"
VERSION="${VERSION:-0.1}"

for file in \
  Xochi.sh \
  Common.sh \
  Tui.sh \
  Recipes/Ollama.sh \
  Recipes/Hermes.sh \
  Recipes/OpenClaw.sh \
  Recipes/Custom.sh \
  Recipes/Models.sh \
  Xochi.applescript \
  Assets/XOCHI.png
do
  if [[ ! -f "$PROJECT/$file" ]]; then
    printf 'Missing file: %s\n' "$file" >&2
    exit 1
  fi
done

printf 'Checking shell syntax...\n'
for file in \
  "$PROJECT/Xochi.sh" \
  "$PROJECT/Common.sh" \
  "$PROJECT/Tui.sh" \
  "$PROJECT/Recipes/"*.sh
do
  /bin/bash -n "$file"
done

mkdir -p "$BUILD_DIR"
STAGE="$(mktemp -d "$BUILD_DIR/.stage.XXXXXX")"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

APP="$STAGE/XOCHI.app"
RESOURCES="$APP/Contents/Resources"
SCRIPTS="$RESOURCES/XOCHI"
ICONSET="$STAGE/XOCHI.iconset"
MASTER="$STAGE/icon-master.png"

mkdir -p "$ICONSET"

printf 'Preparing icon...\n'
/usr/bin/sips -s format png -Z 1024 "$ICON_SOURCE" --out "$MASTER" >/dev/null
/usr/bin/sips -p 1024 1024 "$MASTER" --out "$MASTER" >/dev/null

while read -r SIZE NAME; do
  /usr/bin/sips -z "$SIZE" "$SIZE" "$MASTER" --out "$ICONSET/$NAME" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

/usr/bin/iconutil -c icns "$ICONSET" -o "$STAGE/XOCHI.icns"

printf 'Compiling AppleScript application...\n'
/usr/bin/osacompile -o "$APP" "$PROJECT/Xochi.applescript"

printf 'Bundling launcher and recipes...\n'
mkdir -p "$SCRIPTS/Recipes"
cp "$PROJECT/Xochi.sh" "$PROJECT/Common.sh" "$PROJECT/Tui.sh" "$SCRIPTS/"
cp "$PROJECT/Recipes/"*.sh "$SCRIPTS/Recipes/"
chmod 755 "$SCRIPTS/Xochi.sh"
chmod 644 "$SCRIPTS/Common.sh" "$SCRIPTS/Tui.sh" "$SCRIPTS/Recipes/"*.sh

# Never copy editor backups or runtime state into the signed bundle.
rm -f "$SCRIPTS"/*.before-* "$SCRIPTS/Recipes"/*.before-*
rm -rf "$SCRIPTS/var"

cp "$STAGE/XOCHI.icns" "$RESOURCES/XOCHI.icns"
cp "$RESOURCES/XOCHI.icns" "$RESOURCES/applet.icns"

PLIST="$APP/Contents/Info.plist"

set_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Delete :$key" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
}

printf 'Setting application identity...\n'
set_string CFBundleIdentifier "$IDENTIFIER"
set_string CFBundleName "XOCHI"
set_string CFBundleDisplayName "XOCHI"
set_string CFBundleVersion "$VERSION"
set_string CFBundleShortVersionString "$VERSION"
set_string NSAppleEventsUsageDescription \
  "XOCHI needs permission to control Terminal to open its dashboard and launch local agents."

/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
set_string CFBundleIconFile "XOCHI.icns"
/usr/bin/plutil -lint "$PLIST"

if [[ -d "$APP/Contents/_CodeSignature" ]]; then
  rm -rf "$APP/Contents/_CodeSignature"
fi

if [[ -e "$BUILD_DIR/XOCHI.app" ]]; then
  BACKUP="$BUILD_DIR/XOCHI.previous.$(date +%Y%m%d-%H%M%S).$$.app"
  mv "$BUILD_DIR/XOCHI.app" "$BACKUP"
  printf 'Previous build preserved:\n%s\n' "$BACKUP"
fi

mv "$APP" "$BUILD_DIR/XOCHI.app"
# The staged app has been moved. Do not delete it with the stage trap.
APP="$BUILD_DIR/XOCHI.app"
trap - EXIT
rm -rf "$STAGE"

printf 'Signing the completed application...\n'
/usr/bin/codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null

printf '\nXOCHI %s built and signed:\n%s\n' "$VERSION" "$APP"
printf '\nOpen it with:\nopen "%s"\n' "$APP"
