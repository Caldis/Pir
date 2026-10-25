#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PUV_APP="${1:?Usage: prepare-update.sh /path/to/Puv.app stable|beta release-notes.html}"
PUV_CHANNEL="${2:?Release channel is required}"
PUV_NOTES="${3:?Release notes HTML is required}"
[[ "$PUV_CHANNEL" == stable || "$PUV_CHANNEL" == beta ]] || { printf '%s\n' 'Channel must be stable or beta' >&2; exit 1; }
[[ -f "$PUV_NOTES" ]] || { printf '%s\n' 'Release notes file is required' >&2; exit 1; }
codesign --verify --deep --strict "$PUV_APP"
codesign -dvv "$PUV_APP" 2>&1 | python3 -c 'import sys; assert "Authority=Developer ID Application:" in sys.stdin.read(), "Updates require a Developer ID Application signature"'
xcrun stapler validate "$PUV_APP"
PUV_PUBLIC_KEY="$("$PUV_ROOT/scripts/sparkle-tool.sh" generate_keys --account me.caldis.puv -p)"
PUV_NAME="$(python3 "$PUV_ROOT/scripts/release/update-feed.py" name "$PUV_APP" "$PUV_CHANNEL" "$PUV_PUBLIC_KEY" "$PUV_ROOT/release/appcast.xml")"
mkdir -p "$PUV_ROOT/dist/updates"
PUV_ZIP="$PUV_ROOT/dist/updates/$PUV_NAME"
ditto -c -k --norsrc --noextattr --keepParent "$PUV_APP" "$PUV_ZIP"
PUV_SIGNATURE="$("$PUV_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.puv -p "$PUV_ZIP")"
"$PUV_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.puv --verify "$PUV_ZIP" "$PUV_SIGNATURE"
python3 "$PUV_ROOT/scripts/release/update-feed.py" prepare "$PUV_APP" "$PUV_CHANNEL" "$PUV_PUBLIC_KEY" \
    "$PUV_ROOT/release/appcast.xml" "$PUV_ZIP" "$PUV_SIGNATURE" "$PUV_NOTES" "$PUV_ROOT/dist/updates/appcast.xml"
"$PUV_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.puv "$PUV_ROOT/dist/updates/appcast.xml" >/dev/null
"$PUV_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.puv --verify "$PUV_ROOT/dist/updates/appcast.xml"
cp "$PUV_ROOT/dist/updates/appcast.xml" "$PUV_ROOT/release/appcast.xml"
(cd "$PUV_ROOT/dist/updates" && shasum -a 256 "$PUV_NAME" appcast.xml > SHA256SUMS)
printf '%s\n' "$PUV_ZIP" "$PUV_ROOT/dist/updates/appcast.xml"
