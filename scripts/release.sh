#!/usr/bin/env bash
# Build MacsKeyBored for other people: a release build for Apple silicon and Intel, signed, and packed in
# a disk image to drag into Applications.
#   scripts/release.sh [channel]      →  dist/MacsKeyBored-<version>-<channel>.dmg   (channel: beta.1)
#
# Signing. Set these to ship a build anyone can open with a double-click:
#   MACSKEYBORED_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#       signs with the hardened runtime. Every build signed with that certificate keeps the
#       Accessibility permission people gave an earlier one, so they grant it once, ever.
#   MACSKEYBORED_NOTARY_PROFILE=<profile>
#       has Apple notarize the app and the disk image, and staples the tickets, so Gatekeeper opens
#       them without asking. Store the profile once with:
#       xcrun notarytool store-credentials <profile> --apple-id <email> --team-id <TEAMID>
# Without an identity it makes a test build, ad-hoc signed: macOS makes each person approve it once in
# System Settings › Privacy & Security before it opens. Its signature asks only for MacsKeyBored's bundle
# identifier, so the Accessibility permission carries over from one test build to the next; any other
# ad-hoc app claiming that identifier would get it too, which is fine among testers, not for a wide release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHANNEL="${1:-beta.1}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD)"
NAME="MacsKeyBored-$VERSION${CHANNEL:+-$CHANNEL}"
DIST="$ROOT/dist"
APP="$DIST/MacsKeyBored.app"
DMG="$DIST/$NAME.dmg"
IDENTITY="${MACSKEYBORED_SIGN_IDENTITY:-}"
PROFILE="${MACSKEYBORED_NOTARY_PROFILE:-}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -n "$PROFILE" && -z "$IDENTITY" ]]; then
  echo "MACSKEYBORED_NOTARY_PROFILE needs MACSKEYBORED_SIGN_IDENTITY too: Apple only notarizes Developer ID builds." >&2
  exit 1
fi

echo "==> Testing"
swift test 2>&1 | tail -1

echo "==> Building $NAME (build $BUILD) for Apple silicon and Intel"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release --product macskeybored "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/macskeybored"
lipo -info "$BIN"

rm -rf "$DIST"
mkdir -p "$DIST"
"$ROOT/scripts/make_app.sh" "$BIN" "$APP" "$VERSION" "$BUILD"

echo "==> Signing"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "    No MACSKEYBORED_SIGN_IDENTITY: an ad-hoc test build."
  codesign --force --sign - -r='designated => identifier "com.jgray.macskeybored"' "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

if [[ -n "$PROFILE" ]]; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP" "$DIST/MacsKeyBored.zip"
  notarize "$DIST/MacsKeyBored.zip"
  xcrun stapler staple "$APP"
  rm "$DIST/MacsKeyBored.zip"
fi

echo "==> Packing $DMG"
STAGE="$DIST/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[[ -z "$IDENTITY" ]] && cp "$ROOT/scripts/How to open MacsKeyBored.txt" "$STAGE/"
hdiutil create -quiet -volname "MacsKeyBored" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
if [[ -n "$PROFILE" ]]; then
  echo "==> Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  echo "==> Gatekeeper"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

# Named by file alone, so `shasum -c` works wherever the two files are downloaded to.
(cd "$DIST" && shasum -a 256 "$NAME.dmg" | tee "$NAME.dmg.sha256")
echo "==> Done: $DMG"
