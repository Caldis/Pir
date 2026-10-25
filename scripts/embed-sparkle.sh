#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUV_APP="${1:?Usage: embed-sparkle.sh /path/to/Puv.app}"
PUV_FRAMEWORK="$(python3 - "$PUV_ROOT" <<'PY'
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
[[ -f "$PUV_APP/Contents/Info.plist" ]] || { printf '%s\n' 'Puv app bundle is required' >&2; exit 1; }
mkdir -p "$PUV_APP/Contents/Frameworks"
rm -rf "$PUV_APP/Contents/Frameworks/Sparkle.framework"
ditto "$PUV_FRAMEWORK" "$PUV_APP/Contents/Frameworks/Sparkle.framework"
"$PUV_ROOT/scripts/sign-update-components.sh" "$PUV_APP" -
