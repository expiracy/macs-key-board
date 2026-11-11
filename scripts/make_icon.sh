#!/usr/bin/env bash
# Draw the icon from code (MacsBoredLogo) into App/AppIcon.icns, for the SwiftPM-built bundle, and
# into the layers of App/AppIcon.icon, which Xcode builds the signed app's icon from.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product macsbored
WORK="$(mktemp -d)"
"$(swift build --show-bin-path)/macsbored" --export-icon "$WORK/png"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  cp "$WORK/png/icon_${size}.png" "$SET/icon_${size}x${size}.png"
  cp "$WORK/png/icon_$((size * 2)).png" "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o "$ROOT/App/AppIcon.icns"
mkdir -p "$ROOT/App/AppIcon.icon/Assets"
cp "$WORK/png/marks-light.png" "$WORK/png/marks-dark.png" "$ROOT/App/AppIcon.icon/Assets/"
rm -rf "$WORK"
echo "Wrote App/AppIcon.icns and App/AppIcon.icon"
