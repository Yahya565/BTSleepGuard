#!/bin/zsh
# Builds a universal (Apple silicon + Intel) BTSleepGuard.app into the given folder (default: ./build).
# Needs the Xcode Command Line Tools. Used by `install.sh --build` and for release packages.
set -euo pipefail

SRC=${0:A:h}
OUT=${1:-$SRC/build}
APP="$OUT/BTSleepGuard.app"
EXE="$APP/Contents/MacOS/BTSleepGuard"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "${EXE:h}"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
for arch in arm64 x86_64; do
  swiftc -O -wmo -target "$arch-apple-macos12" -Xlinker -dead_strip -o "$TMP/$arch" "$SRC/BTSleepGuard.swift"
done
lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$EXE"
strip -x "$EXE"
codesign --force --sign - "$APP"   # ad-hoc signature so macOS can remember the Bluetooth permission
print -- "$APP"
