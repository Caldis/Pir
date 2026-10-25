#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PIR_ROOT"
PIR_TEAM_ID="${PIR_TEAM_ID:-N7Z52F27XK}"
PIR_DEVELOPMENT_IDENTITY="${PIR_DEVELOPMENT_IDENTITY:-$(python3 - <<'PY'
import re, subprocess
text=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
identities=re.findall(r'"(Apple Development:[^"]+)"',text)
if not identities:
    raise SystemExit('Xcode Apple Development signing identity is required for cloud export')
print(identities[0])
PY
)}"
PIR_ARCHIVE="$PIR_ROOT/dist/Pir.xcarchive"
if [[ -d "$PIR_ARCHIVE" ]]; then rm -rf "$PIR_ARCHIVE"; fi
if [[ -d dist/DeveloperID ]]; then rm -rf dist/DeveloperID; fi
mkdir -p "$PIR_ARCHIVE/Products/Applications"
ditto dist/Pir.app "$PIR_ARCHIVE/Products/Applications/Pir.app"
"$PIR_ROOT/scripts/sign-update-components.sh" "$PIR_ARCHIVE/Products/Applications/Pir.app" "$PIR_DEVELOPMENT_IDENTITY"
codesign --force --options runtime --timestamp --sign "$PIR_DEVELOPMENT_IDENTITY" "$PIR_ARCHIVE/Products/Applications/Pir.app"
# Xcode's export service can use cloud-managed Developer ID certificates without exporting private keys.
python3 - "$PIR_TEAM_ID" "$PIR_DEVELOPMENT_IDENTITY" <<'PY'
import datetime, plistlib, sys
from pathlib import Path
root=Path('dist')
info=plistlib.load(open(root/'Pir.app/Contents/Info.plist','rb'))
properties={'ApplicationPath':'Applications/Pir.app','CFBundleIdentifier':info['CFBundleIdentifier'],
            'CFBundleShortVersionString':info['CFBundleShortVersionString'],'CFBundleVersion':info['CFBundleVersion'],
            'SigningIdentity':sys.argv[2],'Team':sys.argv[1]}
plistlib.dump({'ArchiveVersion':2,'Name':'Pir','SchemeName':'Pir','CreationDate':datetime.datetime.now(datetime.timezone.utc),
              'ApplicationProperties':properties},open(root/'Pir.xcarchive/Info.plist','wb'))
plistlib.dump({'method':'developer-id','teamID':sys.argv[1],'signingStyle':'automatic','destination':'export'},
             open(root/'ExportOptions.plist','wb'))
PY
xcodebuild -exportArchive -archivePath "$PIR_ARCHIVE" -exportOptionsPlist dist/ExportOptions.plist \
    -exportPath dist/DeveloperID -allowProvisioningUpdates
codesign --verify --strict --verbose=2 dist/DeveloperID/Pir.app
