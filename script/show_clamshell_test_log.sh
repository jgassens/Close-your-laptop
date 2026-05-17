#!/usr/bin/env zsh
set -euo pipefail

MINUTES="${1:-90}"
APP_SUBSYSTEM="com.gassensmith.closeyourlaptop"

echo "Close Your Laptop events from the last ${MINUTES} minute(s):"
/usr/bin/log show \
  --last "${MINUTES}m" \
  --style compact \
  --predicate "subsystem == \"${APP_SUBSYSTEM}\"" || true

echo
echo "Recent macOS sleep/wake/clamshell events:"
/usr/bin/pmset -g log \
  | /usr/bin/awk '
      $4 == "Sleep" ||
      $4 == "Wake" ||
      $4 == "DarkWake" ||
      $4 == "WakeTime" ||
      $4 == "WakeDetails" ||
      ($4 == "PM" && $5 == "Client" && $6 == "Acks") ||
      ($4 == "Kernel" && $5 == "Client" && $6 == "Acks") ||
      /Clamshell/ ||
      /lid/ { print }
    ' \
  | /usr/bin/tail -n 120 || true

echo
echo "Recent Close Your Laptop / Claude / Codex assertion entries:"
/usr/bin/pmset -g log \
  | /usr/bin/grep -Ei 'CloseYourLaptop|Claude|Codex' \
  | /usr/bin/tail -n 100 || true
