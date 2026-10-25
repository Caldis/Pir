#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PUV_ROOT"
PUV_NOTARY_PROFILE="${PUV_NOTARY_PROFILE:-notarytool}"
scripts/check.sh
scripts/build.sh
PUV_APP="$PUV_ROOT/dist/Puv.app"
if [[ -n "${PUV_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$PUV_SIGN_IDENTITY" "$PUV_APP"
else
    scripts/cloud-sign.sh
    ditto dist/DeveloperID/Puv.app "$PUV_APP"
fi
codesign --verify --strict --verbose=2 "$PUV_APP"
codesign -dvv "$PUV_APP" 2>&1 | tee dist/signature.txt
if ! rg -q 'Authority=Developer ID Application:' dist/signature.txt; then
    printf '%s\n' 'Release requires a Developer ID Application signature' >&2
    exit 1
fi
ditto -c -k --keepParent "$PUV_APP" dist/Puv-notarize.zip
xcrun notarytool submit dist/Puv-notarize.zip --keychain-profile "$PUV_NOTARY_PROFILE" --wait --output-format json > dist/notarization.json
python3 -c 'import json; assert json.load(open("dist/notarization.json"))["status"] == "Accepted", "Notarization requires Accepted status"'
xcrun stapler staple "$PUV_APP"
xcrun stapler validate "$PUV_APP"
spctl --assess --type execute --verbose=2 "$PUV_APP"
PUV_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PUV_APP/Contents/Info.plist")"
PUV_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/puv-dmg.XXXXXX")"
trap 'rm -rf "$PUV_STAGE"' EXIT
ditto "$PUV_APP" "$PUV_STAGE/Puv.app"
ln -s /Applications "$PUV_STAGE/Applications"
PUV_DMG="dist/Puv-${PUV_VERSION}-universal.dmg"
hdiutil create -volname Puv -srcfolder "$PUV_STAGE" -ov -format UDZO "$PUV_DMG"
if [[ -n "${PUV_SIGN_IDENTITY:-}" ]]; then
    codesign --timestamp --sign "$PUV_SIGN_IDENTITY" "$PUV_DMG"
fi
xcrun notarytool submit "$PUV_DMG" --keychain-profile "$PUV_NOTARY_PROFILE" --wait --output-format json > dist/dmg-notarization.json
python3 -c 'import json; assert json.load(open("dist/dmg-notarization.json"))["status"] == "Accepted", "Disk image notarization requires Accepted status"'
xcrun stapler staple "$PUV_DMG"
xcrun stapler validate "$PUV_DMG"
hdiutil verify "$PUV_DMG"
(cd dist && shasum -a 256 "$(basename "$PUV_DMG")" > SHA256SUMS)
printf '%s\n' "$PUV_DMG"
