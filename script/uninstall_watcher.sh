#!/usr/bin/env zsh
set -euo pipefail

LABEL="com.gassensmith.closeyourlaptop.watcher"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_VALUE="$(id -u)"

launchctl bootout "gui/$UID_VALUE" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -f "$HOME/Library/Application Support/Close Your Laptop/CloseYourLaptopWatcher"

print "Uninstalled $LABEL"
