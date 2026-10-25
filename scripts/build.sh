#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUV_CONFIGURATION="${PUV_CONFIGURATION:-release}"
cd "$PUV_ROOT"
"$PUV_ROOT/scripts/swift.sh" build --jobs 2 -c "$PUV_CONFIGURATION" --arch arm64 --arch x86_64 --product Puv
PUV_BIN="$("$PUV_ROOT/scripts/swift.sh" build -c "$PUV_CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
PUV_APP="$PUV_ROOT/dist/Puv.app"
PUV_PREVIOUS_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PUV_APP/Contents/Info.plist" 2>/dev/null || true)"
mkdir -p "$PUV_ROOT/dist"
if [[ -e "$PUV_APP" ]]; then
    rm -rf "$PUV_APP"
fi
mkdir -p "$PUV_APP/Contents/MacOS" "$PUV_APP/Contents/Resources"
cp "$PUV_BIN/Puv" "$PUV_APP/Contents/MacOS/Puv"
cp Resources/Info.plist "$PUV_APP/Contents/Info.plist"
for PUV_BUNDLE_NAME in Puv_Puv.bundle Vortex_Vortex.bundle; do
    PUV_BUNDLE="$PUV_BIN/$PUV_BUNDLE_NAME"
    [[ -d "$PUV_BUNDLE" ]] && ditto "$PUV_BUNDLE" "$PUV_APP/Contents/Resources/$PUV_BUNDLE_NAME"
done
for PUV_ASSET in assets/brand/AppIcon.icns assets/brand/MenuBarTemplate.png assets/brand/MenuBarTemplate@2x.png; do
    [[ -f "$PUV_ASSET" ]] && cp "$PUV_ASSET" "$PUV_APP/Contents/Resources/"
done
for PUV_NOTICE in LICENSE THIRD_PARTY_NOTICES.md; do
    [[ -f "$PUV_NOTICE" ]] && cp "$PUV_NOTICE" "$PUV_APP/Contents/Resources/"
done
if [[ -d licenses ]]; then ditto licenses "$PUV_APP/Contents/Resources/licenses"; fi
if [[ -n "${PUV_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PUV_VERSION" "$PUV_APP/Contents/Info.plist"
fi
PUV_BUILD="${PUV_BUILD:-$(python3 - "$PUV_PREVIOUS_BUILD" <<'PY'
import datetime, re, sys
from zoneinfo import ZoneInfo
day = datetime.datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d')
previous = re.fullmatch(r'([0-9]{8})\.([1-9][0-9]*)', sys.argv[1])
sequence = int(previous[2]) + 1 if previous and previous[1] == day else 1
print(f'{day}.{sequence}')
PY
)}"
PUV_DISPLAY_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PUV_APP/Contents/Info.plist")"
python3 "$PUV_ROOT/scripts/version-metadata.py" "$PUV_DISPLAY_VERSION" "$PUV_BUILD" > /dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PUV_BUILD" "$PUV_APP/Contents/Info.plist"
"$PUV_ROOT/scripts/embed-sparkle.sh" "$PUV_APP"
codesign --force --sign - "$PUV_APP"
codesign --verify --deep --strict "$PUV_APP"
lipo -info "$PUV_APP/Contents/MacOS/Puv"
python3 scripts/check-build-sdk.py "$PUV_APP/Contents/MacOS/Puv"
printf '%s\n' "$PUV_APP"
