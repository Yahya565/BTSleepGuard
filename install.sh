#!/bin/zsh
# Builds BTSleepGuard and installs it as a per-user LaunchAgent (starts at login, restarts if it crashes).
#
# Usage: ./install.sh "<device name or address>" [...]
#   ./install.sh "Soundcore P3i"
#   ./install.sh "AirPods Pro" AA:BB:CC:DD:EE:FF
set -euo pipefail

NAME=BTSleepGuard
LABEL=local.btsleepguard
SRC=${0:A:h}
APP="$HOME/Applications/$NAME.app"
EXE="$APP/Contents/MacOS/$NAME"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if (( $# == 0 )); then
  print -u2 'usage: ./install.sh "<device name or address>" [...]'
  print -u2 '       (use the name exactly as shown in System Settings → Bluetooth; the device must be paired)'
  exit 64
fi

# Accepts a Bluetooth address as-is, or looks a paired device up by its name (case-insensitive).
resolve() {
  if [[ $1 =~ '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$' ]]; then print -- $1; return; fi
  system_profiler SPBluetoothDataType 2>/dev/null | awk -v n="${1:l}" '
    { l = tolower($0); sub(/^ +/, "", l) }
    l == n ":"         { hit = 1; next }
    hit && /Address:/  { print $2; exit }
    hit && /:$/        { hit = 0 }'
}

ADDRS=()
for dev in "$@"; do
  addr=$(resolve "$dev")
  if [[ -z $addr ]]; then
    print -u2 "✗ couldn't find a paired Bluetooth device named \"$dev\". Pair it first, or pass its address."
    exit 1
  fi
  print "→ $dev → $addr"
  ADDRS+=("$addr")
done

if ! command -v swiftc >/dev/null; then
  print -u2 "✗ swiftc not found. Install the Command Line Tools: xcode-select --install"
  exit 1
fi

print "→ building"
mkdir -p "$APP/Contents/MacOS" "${PLIST:h}"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
swiftc -O -wmo -Xlinker -dead_strip -o "$EXE" "$SRC/$NAME.swift"
strip -x "$EXE"
codesign --force --sign - "$APP"   # ad-hoc signature so macOS can track the Bluetooth permission

print "→ writing LaunchAgent"
{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXE</string>
EOF
  for a in "${ADDRS[@]}"; do print "        <string>$a</string>"; done
  cat <<EOF
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
} > "$PLIST"
plutil -lint -s "$PLIST"

print "→ (re)starting"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

print "✓ installed. Guarding: ${ADDRS[*]}"
print "  If macOS asks for Bluetooth access for BTSleepGuard, click Allow."
print "  Logs: log stream --predicate 'subsystem == \"$LABEL\"'"
