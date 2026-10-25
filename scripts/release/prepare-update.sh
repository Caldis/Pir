#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIR_APP="${1:?Usage: prepare-update.sh /path/to/Pir.app stable|beta release-notes.html}"
PIR_CHANNEL="${2:?Release channel is required}"
PIR_NOTES="${3:?Release notes HTML is required}"
[[ "$PIR_CHANNEL" == stable || "$PIR_CHANNEL" == beta ]] || { printf '%s\n' 'Channel must be stable or beta' >&2; exit 1; }
[[ -f "$PIR_NOTES" ]] || { printf '%s\n' 'Release notes file is required' >&2; exit 1; }
codesign --verify --deep --strict "$PIR_APP"
codesign -dvv "$PIR_APP" 2>&1 | python3 -c 'import sys; assert "Authority=Developer ID Application:" in sys.stdin.read(), "Updates require a Developer ID Application signature"'
xcrun stapler validate "$PIR_APP"
PIR_PUBLIC_KEY="$("$PIR_ROOT/scripts/sparkle-tool.sh" generate_keys --account me.caldis.pir -p)"
PIR_NAME="$(python3 "$PIR_ROOT/scripts/release/update-feed.py" name "$PIR_APP" "$PIR_CHANNEL" "$PIR_PUBLIC_KEY" "$PIR_ROOT/release/appcast.xml")"
mkdir -p "$PIR_ROOT/dist/updates"
PIR_ZIP="$PIR_ROOT/dist/updates/$PIR_NAME"
ditto -c -k --norsrc --noextattr --keepParent "$PIR_APP" "$PIR_ZIP"
PIR_SIGNATURE="$("$PIR_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.pir -p "$PIR_ZIP")"
"$PIR_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.pir --verify "$PIR_ZIP" "$PIR_SIGNATURE"
python3 "$PIR_ROOT/scripts/release/update-feed.py" prepare "$PIR_APP" "$PIR_CHANNEL" "$PIR_PUBLIC_KEY" \
    "$PIR_ROOT/release/appcast.xml" "$PIR_ZIP" "$PIR_SIGNATURE" "$PIR_NOTES" "$PIR_ROOT/dist/updates/appcast.xml"
"$PIR_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.pir "$PIR_ROOT/dist/updates/appcast.xml" >/dev/null
"$PIR_ROOT/scripts/sparkle-tool.sh" sign_update --account me.caldis.pir --verify "$PIR_ROOT/dist/updates/appcast.xml"
cp "$PIR_ROOT/dist/updates/appcast.xml" "$PIR_ROOT/release/appcast.xml"
(cd "$PIR_ROOT/dist/updates" && shasum -a 256 "$PIR_NAME" appcast.xml > SHA256SUMS)
printf '%s\n' "$PIR_ZIP" "$PIR_ROOT/dist/updates/appcast.xml"
