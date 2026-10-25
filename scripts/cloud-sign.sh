#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PUV_ROOT"
PUV_TEAM_ID="${PUV_TEAM_ID:-N7Z52F27XK}"
PUV_DEVELOPMENT_IDENTITY="${PUV_DEVELOPMENT_IDENTITY:-$(python3 - <<'PY'
import re, subprocess
text=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
identities=re.findall(r'"(Apple Development:[^"]+)"',text)
if not identities:
    raise SystemExit('Xcode Apple Development signing identity is required for cloud export')
print(identities[0])
PY
)}"
PUV_ARCHIVE="$PUV_ROOT/dist/Puv.xcarchive"
if [[ -d "$PUV_ARCHIVE" ]]; then rm -rf "$PUV_ARCHIVE"; fi
if [[ -d dist/DeveloperID ]]; then rm -rf dist/DeveloperID; fi
mkdir -p "$PUV_ARCHIVE/Products/Applications"
ditto dist/Puv.app "$PUV_ARCHIVE/Products/Applications/Puv.app"
codesign --force --options runtime --timestamp --sign "$PUV_DEVELOPMENT_IDENTITY" "$PUV_ARCHIVE/Products/Applications/Puv.app"
# Xcode's export service can use cloud-managed Developer ID certificates without exporting private keys.
python3 - "$PUV_TEAM_ID" "$PUV_DEVELOPMENT_IDENTITY" <<'PY'
import datetime, plistlib, sys
from pathlib import Path
root=Path('dist')
info=plistlib.load(open(root/'Puv.app/Contents/Info.plist','rb'))
properties={'ApplicationPath':'Applications/Puv.app','CFBundleIdentifier':info['CFBundleIdentifier'],
            'CFBundleShortVersionString':info['CFBundleShortVersionString'],'CFBundleVersion':info['CFBundleVersion'],
            'SigningIdentity':sys.argv[2],'Team':sys.argv[1]}
plistlib.dump({'ArchiveVersion':2,'Name':'Puv','SchemeName':'Puv','CreationDate':datetime.datetime.now(datetime.timezone.utc),
              'ApplicationProperties':properties},open(root/'Puv.xcarchive/Info.plist','wb'))
plistlib.dump({'method':'developer-id','teamID':sys.argv[1],'signingStyle':'automatic','destination':'export'},
             open(root/'ExportOptions.plist','wb'))
PY
xcodebuild -exportArchive -archivePath "$PUV_ARCHIVE" -exportOptionsPlist dist/ExportOptions.plist \
    -exportPath dist/DeveloperID -allowProvisioningUpdates
codesign --verify --strict --verbose=2 dist/DeveloperID/Puv.app
