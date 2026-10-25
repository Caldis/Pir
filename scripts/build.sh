#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIR_CONFIGURATION="${PIR_CONFIGURATION:-release}"
cd "$PIR_ROOT"
"$PIR_ROOT/scripts/swift.sh" build --jobs 2 -c "$PIR_CONFIGURATION" --arch arm64 --arch x86_64 --product Pir
PIR_BIN="$("$PIR_ROOT/scripts/swift.sh" build -c "$PIR_CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
PIR_APP="$PIR_ROOT/dist/Pir.app"
PIR_PREVIOUS_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PIR_APP/Contents/Info.plist" 2>/dev/null || true)"
mkdir -p "$PIR_ROOT/dist"
if [[ -e "$PIR_APP" ]]; then
    rm -rf "$PIR_APP"
fi
mkdir -p "$PIR_APP/Contents/MacOS" "$PIR_APP/Contents/Resources"
cp "$PIR_BIN/Pir" "$PIR_APP/Contents/MacOS/Pir"
cp Resources/Info.plist "$PIR_APP/Contents/Info.plist"
for PIR_BUNDLE_NAME in Pir_Pir.bundle Vortex_Vortex.bundle; do
    PIR_BUNDLE="$PIR_BIN/$PIR_BUNDLE_NAME"
    [[ -d "$PIR_BUNDLE" ]] && ditto "$PIR_BUNDLE" "$PIR_APP/Contents/Resources/$PIR_BUNDLE_NAME"
done
for PIR_ASSET in assets/brand/AppIcon.icns assets/brand/MenuBarTemplate.png assets/brand/MenuBarTemplate@2x.png; do
    [[ -f "$PIR_ASSET" ]] && cp "$PIR_ASSET" "$PIR_APP/Contents/Resources/"
done
for PIR_NOTICE in LICENSE THIRD_PARTY_NOTICES.md; do
    [[ -f "$PIR_NOTICE" ]] && cp "$PIR_NOTICE" "$PIR_APP/Contents/Resources/"
done
if [[ -d licenses ]]; then ditto licenses "$PIR_APP/Contents/Resources/licenses"; fi
if [[ -n "${PIR_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PIR_VERSION" "$PIR_APP/Contents/Info.plist"
fi
PIR_BUILD="${PIR_BUILD:-$(python3 - "$PIR_PREVIOUS_BUILD" <<'PY'
import datetime, re, sys
from zoneinfo import ZoneInfo
day = datetime.datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d')
previous = re.fullmatch(r'([0-9]{8})\.([1-9][0-9]*)', sys.argv[1])
sequence = int(previous[2]) + 1 if previous and previous[1] == day else 1
print(f'{day}.{sequence}')
PY
)}"
PIR_DISPLAY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PIR_APP/Contents/Info.plist")"
python3 "$PIR_ROOT/scripts/version-metadata.py" "$PIR_DISPLAY_VERSION" "$PIR_BUILD" > /dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PIR_BUILD" "$PIR_APP/Contents/Info.plist"
"$PIR_ROOT/scripts/embed-sparkle.sh" "$PIR_APP"
codesign --force --sign - "$PIR_APP"
codesign --verify --deep --strict "$PIR_APP"
lipo -info "$PIR_APP/Contents/MacOS/Pir"
python3 scripts/check-build-sdk.py "$PIR_APP/Contents/MacOS/Pir"
printf '%s\n' "$PIR_APP"
