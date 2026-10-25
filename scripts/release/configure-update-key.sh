#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$PIR_ROOT/scripts/sparkle-tool.sh" generate_keys --account me.caldis.pir >/dev/null
PIR_PUBLIC_KEY="$("$PIR_ROOT/scripts/sparkle-tool.sh" generate_keys --account me.caldis.pir -p)"
python3 - "$PIR_ROOT/Resources/Info.plist" "$PIR_PUBLIC_KEY" <<'PY'
import base64, pathlib, plistlib, sys
path, key = pathlib.Path(sys.argv[1]), sys.argv[2].strip()
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('Invalid Sparkle public key')
info = plistlib.loads(path.read_bytes())
info['SUPublicEDKey'] = key
path.write_bytes(plistlib.dumps(info, sort_keys=False))
print('Pir update public key configured; private key remains in the login Keychain')
PY
