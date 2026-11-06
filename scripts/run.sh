#!/usr/bin/env bash
# Build MacsKeyBored with SwiftPM, wrap it in a small .app bundle, sign it, and open it.
#
# Accessibility remembers a grant against the app's designated requirement. An ad-hoc signature's
# default requirement is that one build's hash, so every rebuild would need granting again; the
# ad-hoc signature here requires only the bundle identifier, which every build shares, so one grant
# lasts across rebuilds. Set MACSKEYBORED_SIGN_IDENTITY to a code-signing identity to sign with that.
#   scripts/run.sh            build, quit any running copy, open the new one
#   scripts/run.sh --build    build and bundle only
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product macskeybored
BIN="$(swift build --show-bin-path)/macskeybored"

APP="$ROOT/.build/MacsKeyBored.app"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
"$ROOT/scripts/make_app.sh" "$BIN" "$APP" "$(tr -d '[:space:]' < "$ROOT/VERSION")" "$BUILD_NUMBER"

if [[ -n "${MACSKEYBORED_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "$MACSKEYBORED_SIGN_IDENTITY" --timestamp=none "$APP"
else
  /usr/bin/codesign --force --sign - --timestamp=none \
    -r='designated => identifier "com.jgray.macskeybored"' "$APP"
fi

[[ "${1:-}" == "--build" ]] && { echo "$APP"; exit 0; }
pkill -x MacsKeyBored 2>/dev/null || true
sleep 0.5
open "$APP"
echo "MacsKeyBored running from $APP"
