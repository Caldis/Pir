#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIR_SPARKLE_ACCOUNT="$(python3 "$PIR_ROOT/scripts/local-config.py" get PIR_SPARKLE_ACCOUNT)"
PIR_PUBLIC_KEY="$("$PIR_ROOT/scripts/sparkle-tool.sh" generate_keys --account "$PIR_SPARKLE_ACCOUNT" -p)"
python3 - "$PIR_ROOT/Resources/Info.plist" "$PIR_PUBLIC_KEY" <<'PY'
import base64, pathlib, plistlib, sys
path, key = pathlib.Path(sys.argv[1]), sys.argv[2].strip()
if len(base64.b64decode(key, validate=True)) != 32:
    raise SystemExit('Invalid Sparkle public key')
info = plistlib.loads(path.read_bytes())
if info.get('SUPublicEDKey') != key:
    raise SystemExit('Existing configured Sparkle key differs from Pir application; existing public key preserved')
print('Existing Sparkle public key matches Pir; private key remains in the login Keychain')
PY
