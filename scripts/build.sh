#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUV_CONFIGURATION="${PUV_CONFIGURATION:-release}"
cd "$PUV_ROOT"
swift build --jobs 2 -c "$PUV_CONFIGURATION" --arch arm64 --arch x86_64 --product Puv
PUV_BIN="$(swift build -c "$PUV_CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
PUV_APP="$PUV_ROOT/dist/Puv.app"
mkdir -p "$PUV_ROOT/dist"
if [[ -e "$PUV_APP" ]]; then
    rm -rf "$PUV_APP"
fi
mkdir -p "$PUV_APP/Contents/MacOS" "$PUV_APP/Contents/Resources"
cp "$PUV_BIN/Puv" "$PUV_APP/Contents/MacOS/Puv"
cp Resources/Info.plist "$PUV_APP/Contents/Info.plist"
for PUV_BUNDLE in "$PUV_BIN"/*.bundle; do
    [[ -d "$PUV_BUNDLE" ]] && ditto "$PUV_BUNDLE" "$PUV_APP/Contents/Resources/$(basename "$PUV_BUNDLE")"
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
PUV_BUILD="${PUV_BUILD:-$(date +%Y%m%d).1}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PUV_BUILD" "$PUV_APP/Contents/Info.plist"
codesign --force --sign - "$PUV_APP"
codesign --verify --strict "$PUV_APP"
lipo -info "$PUV_APP/Contents/MacOS/Puv"
printf '%s\n' "$PUV_APP"
