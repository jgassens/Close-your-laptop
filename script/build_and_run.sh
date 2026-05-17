#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
EXTRA_ARGS=("${@:2}")
APP_NAME="Close Your Laptop"
PRODUCT_NAME="CloseYourLaptop"
BUNDLE_ID="com.gassensmith.closeyourlaptop"
MIN_SYSTEM_VERSION="13.0"
CONFIGURATION="release"
APP_VERSION="${CYL_VERSION:-0.1.0}"
APP_BUILD="${CYL_BUILD:-1}"
UPDATE_FEED_URL="${CYL_UPDATE_FEED_URL:-https://jgassens.github.io/close-your-laptop/appcast.xml}"
SPARKLE_PUBLIC_KEY="${CYL_SPARKLE_PUBLIC_KEY:-HK2FMFt1/JlsEm52nLZ7X4cXo1nmLLJpAoRzB3y7tYQ=}"
CODESIGN_IDENTITY="${CYL_CODESIGN_IDENTITY:--}"

if [[ "$MODE" == "--debug" || "$MODE" == "debug" ]]; then
  CONFIGURATION="debug"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

cd "$ROOT_DIR"

pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

swift build -c "$CONFIGURATION"
BUILD_BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/$PRODUCT_NAME"
SPARKLE_FRAMEWORK_SOURCE="$(find "$ROOT_DIR/.build/artifacts/sparkle/Sparkle" -path '*/macos-arm64_x86_64/Sparkle.framework' -type d | head -n 1)"

if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Sparkle.framework was not found. Run 'swift package resolve' and retry." >&2
  exit 1
fi

if [[ ! -f "$APP_ICON_SOURCE" ]]; then
  swift script/generate_app_icon.swift >/dev/null
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/ditto --noextattr --noqtn --norsrc "$SPARKLE_FRAMEWORK_SOURCE" "$APP_FRAMEWORKS/Sparkle.framework"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$UPDATE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_BUNDLE"
CODESIGN_FLAGS=(--force --deep --sign "$CODESIGN_IDENTITY")
if [[ "${CYL_HARDENED_RUNTIME:-0}" == "1" ]]; then
  CODESIGN_FLAGS+=(--options runtime)
fi
/usr/bin/codesign "${CODESIGN_FLAGS[@]}" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PRODUCT_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$PRODUCT_NAME" >/dev/null
    ;;
  --build-only|build)
    echo "$APP_BUNDLE"
    ;;
  --update-diagnostics|update-diagnostics)
    "$APP_BINARY" --update-diagnostics "${EXTRA_ARGS[@]}"
    ;;
  --check-appcast|check-appcast)
    "$APP_BINARY" --check-appcast "${EXTRA_ARGS[@]}"
    ;;
  --print-appcast|print-appcast)
    "$APP_BINARY" --print-appcast "${EXTRA_ARGS[@]}"
    ;;
  --sparkle-tools|sparkle-tools)
    "$APP_BINARY" --sparkle-tools
    ;;
  --sign-update|sign-update)
    "$APP_BINARY" --sign-update "${EXTRA_ARGS[@]}"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2
    exit 2
    ;;
esac
