#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIR_APP="${1:?Usage: embed-sparkle.sh /path/to/Pir.app}"
PIR_FRAMEWORK="$(python3 - "$PIR_ROOT" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1]) / '.build/artifacts'
for framework in sorted(root.rglob('Sparkle.framework')):
    binary = framework / 'Sparkle'
    if not binary.exists():
        continue
    architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    if {'arm64', 'x86_64'}.issubset(architectures):
        print(framework)
        break
else:
    raise SystemExit('Sparkle Universal framework is missing; run scripts/swift.sh build first')
PY
)"
[[ -f "$PIR_APP/Contents/Info.plist" ]] || { printf '%s\n' 'Pir app bundle is required' >&2; exit 1; }
mkdir -p "$PIR_APP/Contents/Frameworks"
rm -rf "$PIR_APP/Contents/Frameworks/Sparkle.framework"
ditto "$PIR_FRAMEWORK" "$PIR_APP/Contents/Frameworks/Sparkle.framework"
"$PIR_ROOT/scripts/sign-update-components.sh" "$PIR_APP" -
