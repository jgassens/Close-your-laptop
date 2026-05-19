#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "${0:A:h}/.." && pwd)"
APP_PATH="${CYL_APP_PATH:-/Applications/Close Your Laptop.app}"
WATCHER_SOURCE="$APP_PATH/Contents/Resources/CloseYourLaptopWatcher"
INSTALL_DIR="$HOME/Library/Application Support/Close Your Laptop"
WATCHER_DEST="$INSTALL_DIR/CloseYourLaptopWatcher"
PLIST_PATH="$HOME/Library/LaunchAgents/com.gassensmith.closeyourlaptop.watcher.plist"
LABEL="com.gassensmith.closeyourlaptop.watcher"
UID_VALUE="$(id -u)"

if [[ ! -x "$WATCHER_SOURCE" ]]; then
  swift build -c release --product CloseYourLaptopWatcher
  BUILD_BIN_PATH="$(swift build -c release --show-bin-path)"
  WATCHER_SOURCE="$BUILD_BIN_PATH/CloseYourLaptopWatcher"
  APP_PATH="${CYL_APP_PATH:-$ROOT_DIR/dist/Close Your Laptop.app}"
fi

if [[ ! -x "$WATCHER_SOURCE" ]]; then
  print -u2 "CloseYourLaptopWatcher was not found."
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"
/usr/bin/ditto --noextattr --noqtn --norsrc "$WATCHER_SOURCE" "$WATCHER_DEST"
chmod +x "$WATCHER_DEST"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$WATCHER_DEST</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CYL_APP_PATH</key>
    <string>$APP_PATH</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>/tmp/close-your-laptop-watcher.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/close-your-laptop-watcher.err</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$PLIST_PATH"
launchctl enable "gui/$UID_VALUE/$LABEL"
launchctl kickstart -k "gui/$UID_VALUE/$LABEL"

print "Installed $LABEL"
print "$PLIST_PATH"
