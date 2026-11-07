#!/bin/bash
# Installs or updates Ledge from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/gabesgh/ledge/main/install.sh | bash
#
# Set LEDGE_INSTALL_DIR to install somewhere other than /Applications,
# and LEDGE_NO_OPEN=1 to skip launching it afterwards.
set -euo pipefail

REPO="gabesgh/ledge"
DIR="${LEDGE_INSTALL_DIR:-/Applications}"
APP="$DIR/Ledge.app"
BASE="https://github.com/$REPO/releases/latest/download"

fail() { echo "ledge: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Ledge is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "Ledge needs macOS 14 Sonoma or later."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading the latest Ledge release..."
curl -fsSL "$BASE/Ledge.zip" -o "$tmp/Ledge.zip" || fail "download failed. Is there a release yet?"
curl -fsSL "$BASE/Ledge.zip.sha256" -o "$tmp/Ledge.zip.sha256" || fail "checksum download failed."

expected="$(awk '{print $1}' "$tmp/Ledge.zip.sha256")"
actual="$(shasum -a 256 "$tmp/Ledge.zip" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || fail "checksum mismatch, not installing."

ditto -x -k "$tmp/Ledge.zip" "$tmp/unpacked"
codesign --verify --deep --strict "$tmp/unpacked/Ledge.app" || fail "the app's signature doesn't verify."

updating=0
if [[ -d "$APP" ]]; then
  updating=1
  pkill -f "$APP/Contents/MacOS/Ledge" 2>/dev/null || true
  sleep 0.5
fi

mkdir -p "$DIR"
if [[ -w "$DIR" ]]; then
  rm -rf "$APP"
  ditto "$tmp/unpacked/Ledge.app" "$APP"
else
  echo "Installing into $DIR needs your password."
  sudo rm -rf "$APP"
  sudo ditto "$tmp/unpacked/Ledge.app" "$APP"
fi

# Each release is a new build, so the old Accessibility entry no longer matches
# it. Clearing it lets Ledge ask again cleanly instead of failing silently.
if (( updating )); then
  tccutil reset Accessibility com.gshimoon.ledge >/dev/null 2>&1 || true
fi

version="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"
echo "Installed Ledge $version in $DIR."

if [[ "${LEDGE_NO_OPEN:-0}" != "1" ]]; then
  open "$APP"
  echo "Ledge will ask for Accessibility access. Turn it on in System Settings and you're set."
fi
