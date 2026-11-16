#!/bin/zsh
# BTSleepGuard installer — https://github.com/Yahya565/BTSleepGuard
#
#   Install:    curl -fsSL https://raw.githubusercontent.com/Yahya565/BTSleepGuard/main/install.sh | zsh
#   Uninstall:  curl -fsSL https://raw.githubusercontent.com/Yahya565/BTSleepGuard/main/install.sh | zsh -s -- --uninstall
#
#   ./install.sh                      pick your headphones from a list
#   ./install.sh "Soundcore P3i" ...  pick by name or address, no questions asked
#   ./install.sh --build              compile from source instead of downloading (needs Xcode Command Line Tools)
#   ./install.sh --uninstall          remove everything
set -euo pipefail

REPO=Yahya565/BTSleepGuard
ZIP_URL=${BTSG_ZIP_URL:-https://github.com/$REPO/releases/latest/download/BTSleepGuard.zip}
LABEL=local.btsleepguard
APP="$HOME/Applications/BTSleepGuard.app"
EXE="$APP/Contents/MacOS/BTSleepGuard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SETTINGS_URL="x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
SELF=${0:A}
SRC=${SELF:h}

if [[ -t 1 ]]; then B=$'\e[1m' G=$'\e[32m' R=$'\e[31m' D=$'\e[2m' N=$'\e[0m'; else B= G= R= D= N=; fi
step() { print -- "${B}→${N} $*" }
ok()   { print -- "${G}✓${N} $*" }
die()  { print -u2 -- "${R}✗${N} $*"; exit 1 }

# Questions go through the terminal directly, so they work even when this script is piped from curl.
can_ask() { /bin/sh -c ': </dev/tty' 2>/dev/null }
ask()     { local reply; print -n -- "$1" >/dev/tty; read -r reply </dev/tty || true; print -- "$reply" }

usage() { sed -n '2,10s/^# \{0,1\}//p' "$SELF" 2>/dev/null || print "See https://github.com/$REPO" }

uninstall() {
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$APP"
  ok "BTSleepGuard removed."
}

# Paired devices as "<0 if audio else 1>\t<name>\t<address>", headphones/speakers first.
list_devices() {
  /usr/bin/osascript -l JavaScript -e '
    const app = Application.currentApplication(); app.includeStandardAdditions = true;
    const data = JSON.parse(app.doShellScript("/usr/sbin/system_profiler SPBluetoothDataType -json"));
    const audio = /head|audio|speaker/i, seen = {}, rows = [];
    for (const ctl of data.SPBluetoothDataType || [])
      for (const group of ["device_connected", "device_not_connected"])
        for (const entry of ctl[group] || [])
          for (const [name, info] of Object.entries(entry)) {
            const addr = info.device_address;
            if (!addr || seen[addr]) continue;
            seen[addr] = true;
            rows.push([audio.test(info.device_minorType || "") ? 0 : 1, name, addr]);
          }
    rows.sort((a, b) => a[0] - b[0] || a[1].localeCompare(b[1]));
    rows.map(r => r.join("\t")).join("\n");' 2>/dev/null
}

typeset -a NAMES ADDRS ROWS F

pick_devices() {
  ROWS=("${(@f)$(list_devices)}"); ROWS=(${ROWS:#})
  (( ${#ROWS} )) || die "No paired Bluetooth devices found. Pair your headphones in System Settings → Bluetooth, then run this again."

  print -- "\n${B}Which headphones should be kept off your Mac while it sleeps?${N}\n"
  local i
  for i in {1..${#ROWS}}; do
    F=("${(@ps:\t:)ROWS[i]}")
    print -- "  ${B}$i)${N} ${F[2]}  ${D}${F[3]}${N}"
  done

  local def= reply n
  [[ ${ROWS[1]%%$'\t'*} == 0 ]] && def=1
  reply=$(ask $'\n'"Type a number${def:+ and press Enter [default: $def]} (several: 1,3): ")
  reply=${reply:-$def}
  [[ -n $reply ]] || die "No device chosen."
  for n in ${(s:,:)${reply// /,}}; do
    [[ $n == <-> ]] && (( n >= 1 && n <= ${#ROWS} )) || die "\"$n\" isn't one of the numbers above."
    F=("${(@ps:\t:)ROWS[n]}")
    NAMES+=("${F[2]}"); ADDRS+=("${F[3]}")
  done
}

resolve_args() {
  ROWS=("${(@f)$(list_devices)}"); ROWS=(${ROWS:#})
  local dev row found
  for dev in "$@"; do
    if [[ $dev =~ '^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$' ]]; then
      NAMES+=("$dev"); ADDRS+=("$dev"); continue
    fi
    found=0
    for row in $ROWS; do
      F=("${(@ps:\t:)row}")
      if [[ ${F[2]:l} == "${dev:l}" ]]; then NAMES+=("${F[2]}"); ADDRS+=("${F[3]}"); found=1; fi
    done
    (( found )) || die "No paired Bluetooth device is named \"$dev\". Run without a name to choose from a list."
  done
}

# The new app is prepared in $STAGE first, so a failed download/build leaves any existing install running.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

download_app() {
  step "Downloading BTSleepGuard"
  curl -fsSL "$ZIP_URL" -o "$STAGE/app.zip" || die "Download failed. Check your internet connection and try again."
  ditto -x -k "$STAGE/app.zip" "$STAGE"
  codesign --verify "$STAGE/BTSleepGuard.app" 2>/dev/null || die "The downloaded app failed its integrity check."
  xattr -dr com.apple.quarantine "$STAGE/BTSleepGuard.app" 2>/dev/null || true
}

build_app() {
  [[ -f $SRC/build.sh && -f $SRC/BTSleepGuard.swift ]] || die "--build must be run from a clone: git clone https://github.com/$REPO"
  command -v swiftc >/dev/null || die "Building needs the Xcode Command Line Tools. Install them with: xcode-select --install"
  step "Building from source"
  zsh "$SRC/build.sh" "$STAGE" >/dev/null
}

swap_in_app() {
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -rf "$APP"; mkdir -p "${APP:h}"
  mv "$STAGE/BTSleepGuard.app" "$APP"
}

write_agent() {
  mkdir -p "${PLIST:h}"
  {
    print -- '<?xml version="1.0" encoding="UTF-8"?>'
    print -- '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    print -- '<plist version="1.0"><dict>'
    print -- "  <key>Label</key><string>$LABEL</string>"
    print -- '  <key>ProgramArguments</key><array>'
    print -- "    <string>$EXE</string>"
    local a; for a in $ADDRS; do print -- "    <string>$a</string>"; done
    print -- '  </array>'
    print -- '  <key>RunAtLoad</key><true/>'
    print -- '  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'
    print -- '  <key>LimitLoadToSessionType</key><string>Aqua</string>'
    print -- '</dict></plist>'
  } > "$PLIST"
  plutil -lint -s "$PLIST"
}

# Starts (or restarts) the agent and prints the Bluetooth access it reports: granted / pending / denied.
start_agent() {
  local since; since=$(date '+%Y-%m-%d %H:%M:%S')
  if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$UID/$LABEL" >/dev/null
  else
    launchctl bootstrap "gui/$UID" "$PLIST"
  fi
  local s _
  for _ in {1..40}; do
    s=$(/usr/bin/log show --start "$since" --style compact \
          --predicate "subsystem == \"$LABEL\" AND eventMessage BEGINSWITH \"bluetooth access\"" 2>/dev/null \
        | awk '/bluetooth access/ { v = $NF } END { print v }')
    [[ -n $s ]] && { print -- "$s"; return }
    sleep 0.5
  done
}

ensure_access() {
  local s=$1 attempt
  [[ $s == granted ]] && return 0
  if ! can_ask; then
    print -- "${B}!${N} Allow BTSleepGuard under System Settings → Privacy & Security → Bluetooth."
    return 0
  fi
  for attempt in 1 2 3; do
    if [[ $s == denied ]]; then
      open "$SETTINGS_URL"
      print -- "\n${B}One last step:${N} in the System Settings window that just opened, turn on ${B}BTSleepGuard${N}."
    else
      print -- "\n${B}One last step:${N} macOS is asking if ${B}BTSleepGuard${N} may use Bluetooth. Click ${B}Allow${N}."
    fi
    ask "Press Enter when you've done that… " >/dev/null
    s=$(start_agent)
    [[ $s == granted ]] && return 0
  done
  print -- "${B}!${N} Bluetooth access still looks off. Turn on BTSleepGuard in System Settings → Privacy & Security → Bluetooth."
}

main() {
  local build=0 a; typeset -a devices
  for a in "$@"; do
    case $a in
      --uninstall) uninstall; return ;;
      --build)     build=1 ;;
      -h|--help)   usage; return ;;
      -*)          die "Unknown option: $a (try --help)" ;;
      *)           devices+=("$a") ;;
    esac
  done

  (( ${$(sw_vers -productVersion)%%.*} >= 12 )) || die "BTSleepGuard needs macOS 12 (Monterey) or newer."

  print -- "${B}BTSleepGuard${N} ${D}— keeps your headphones off your Mac while it sleeps${N}"
  if (( ${#devices} )); then
    resolve_args "${devices[@]}"
  elif can_ask; then
    pick_devices
  else
    die "Pass your headphones' name, e.g.:  curl -fsSL … | zsh -s -- \"Soundcore P3i\""
  fi

  if (( build )); then build_app; else download_app; fi
  swap_in_app
  write_agent
  step "Starting"
  ensure_access "$(start_agent)"

  print
  ok "Done! ${B}${(j:, :)NAMES}${N} will be disconnected if they connect while your Mac is asleep."
  print -- "  ${D}It starts automatically at login. To change devices, run the installer again.${N}"
  print -- "  ${D}To remove it: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | zsh -s -- --uninstall${N}"
}

main "$@"
