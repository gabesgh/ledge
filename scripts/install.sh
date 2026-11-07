#!/bin/zsh
# Builds a Release copy of Ledge, installs it in /Applications and opens it.
# Accessibility permission sticks across reinstalls because the signature stays the same.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project Ledge.xcodeproj -scheme Ledge -configuration Release \
  -derivedDataPath build/DerivedData build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP="build/DerivedData/Build/Products/Release/Ledge.app"
pkill -x Ledge 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Ledge.app
ditto "$APP" /Applications/Ledge.app
open /Applications/Ledge.app
echo "Installed /Applications/Ledge.app"
