#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PIR_ROOT"
PIR_NOTARY_PROFILE="${PIR_NOTARY_PROFILE:-notarytool}"
: "${PIR_SIGN_IDENTITY:?Set PIR_SIGN_IDENTITY to a local Developer ID Application identity (certificate name or SHA1)}"
scripts/check.sh
scripts/build.sh
PIR_APP="$PIR_ROOT/dist/Pir.app"
scripts/sign-update-components.sh "$PIR_APP" "$PIR_SIGN_IDENTITY"
codesign --force --options runtime --timestamp --sign "$PIR_SIGN_IDENTITY" "$PIR_APP"
codesign --verify --strict --verbose=2 "$PIR_APP"
codesign -dvv "$PIR_APP" 2>&1 | tee dist/signature.txt
if ! rg -q 'Authority=Developer ID Application:' dist/signature.txt; then
    printf '%s\n' 'Release requires a Developer ID Application signature' >&2
    exit 1
fi
ditto -c -k --keepParent "$PIR_APP" dist/Pir-notarize.zip
xcrun notarytool submit dist/Pir-notarize.zip --keychain-profile "$PIR_NOTARY_PROFILE" --wait --output-format json > dist/notarization.json
python3 -c 'import json; assert json.load(open("dist/notarization.json"))["status"] == "Accepted", "Notarization requires Accepted status"'
xcrun stapler staple "$PIR_APP"
xcrun stapler validate "$PIR_APP"
spctl --assess --type execute --verbose=2 "$PIR_APP"
PIR_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PIR_APP/Contents/Info.plist")"
PIR_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/pir-dmg.XXXXXX")"
trap 'rm -rf "$PIR_STAGE"' EXIT
ditto "$PIR_APP" "$PIR_STAGE/Pir.app"
ln -s /Applications "$PIR_STAGE/Applications"
PIR_DMG="dist/Pir-${PIR_VERSION}-universal.dmg"
hdiutil create -volname Pir -srcfolder "$PIR_STAGE" -ov -format UDZO "$PIR_DMG"
codesign --timestamp --sign "$PIR_SIGN_IDENTITY" "$PIR_DMG"
xcrun notarytool submit "$PIR_DMG" --keychain-profile "$PIR_NOTARY_PROFILE" --wait --output-format json > dist/dmg-notarization.json
python3 -c 'import json; assert json.load(open("dist/dmg-notarization.json"))["status"] == "Accepted", "Disk image notarization requires Accepted status"'
xcrun stapler staple "$PIR_DMG"
xcrun stapler validate "$PIR_DMG"
hdiutil verify "$PIR_DMG"
(cd dist && shasum -a 256 "$(basename "$PIR_DMG")" > SHA256SUMS)
printf '%s\n' "$PIR_DMG"
