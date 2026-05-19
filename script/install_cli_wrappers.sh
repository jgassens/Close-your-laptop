#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "${0:A:h}/.." && pwd)"
WRAPPER_DIR="${CYL_WRAPPER_DIR:-$HOME/bin}"
APP_BINARY="${CYL_APP_BINARY:-/Applications/Close Your Laptop.app/Contents/MacOS/CloseYourLaptop}"

if [[ ! -x "$APP_BINARY" && -x "$ROOT_DIR/dist/Close Your Laptop.app/Contents/MacOS/CloseYourLaptop" ]]; then
  APP_BINARY="$ROOT_DIR/dist/Close Your Laptop.app/Contents/MacOS/CloseYourLaptop"
fi

if [[ ! -x "$APP_BINARY" ]]; then
  print -u2 "CloseYourLaptop app binary was not found. Set CYL_APP_BINARY and retry."
  exit 1
fi

mkdir -p "$WRAPPER_DIR"

find_real_command() {
  local name="$1"
  local candidate
  for candidate in ${(f)"$(whence -a "$name" 2>/dev/null || true)"}; do
    [[ "$candidate" == "$WRAPPER_DIR/$name" ]] && continue
    [[ -x "$candidate" ]] || continue
    print -r -- "$candidate"
    return 0
  done
  return 1
}

install_or_backup() {
  local path="$1"
  if [[ -e "$path" ]] && ! /usr/bin/grep -q "Close Your Laptop generated wrapper" "$path" 2>/dev/null; then
    mv "$path" "$path.backup.$(date +%Y%m%d%H%M%S)"
  fi
}

SIDECAR="$WRAPPER_DIR/with-close-your-laptop"
install_or_backup "$SIDECAR"
cat >"$SIDECAR" <<SCRIPT
#!/usr/bin/env zsh
# Close Your Laptop generated wrapper
set -u

kind="\$1"
real_cmd="\$2"
shift 2

app_binary="$APP_BINARY"
token="\${kind}.\$\$.\$(/usr/bin/uuidgen)"

cleanup() {
  "\$app_binary" --session-end --token "\$token" >/dev/null 2>&1 || true
}

trap cleanup EXIT HUP INT TERM

"\$app_binary" --session-begin --kind "\$kind" --token "\$token" --pid "\$\$" >/dev/null 2>&1 || true
app_path="\${app_binary%/Contents/MacOS/CloseYourLaptop}"
if [[ -d "\$app_path" ]]; then
  /usr/bin/open -gj "\$app_path" >/dev/null 2>&1 || true
else
  /usr/bin/open -gj -a "Close Your Laptop" >/dev/null 2>&1 || true
fi

"\$real_cmd" "\$@"
status=\$?
cleanup
exit "\$status"
SCRIPT
chmod +x "$SIDECAR"

for pair in codex:codex claude:claude; do
  name="${pair%%:*}"
  kind="${pair##*:}"
  real_path="$(find_real_command "$name" || true)"
  if [[ -z "$real_path" ]]; then
    print "Skipped $name: command not found before installing wrapper."
    continue
  fi

  wrapper_path="$WRAPPER_DIR/$name"
  install_or_backup "$wrapper_path"
  cat >"$wrapper_path" <<SCRIPT
#!/usr/bin/env zsh
# Close Your Laptop generated wrapper
exec "$SIDECAR" "$kind" "$real_path" "\$@"
SCRIPT
  chmod +x "$wrapper_path"
  print "Installed $wrapper_path -> $real_path"
done

print "Make sure $WRAPPER_DIR appears before Homebrew or other command directories in PATH."
