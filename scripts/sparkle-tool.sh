#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUV_TOOL="${1:?Usage: sparkle-tool.sh tool [arguments]}"
shift
PUV_EXECUTABLE="$(python3 - "$PUV_ROOT" "$PUV_TOOL" "${PUV_SPARKLE_TOOLS:-}" <<'PY'
import os, pathlib, sys
root, tool, override = sys.argv[1:]
if tool not in {'generate_keys', 'sign_update', 'generate_appcast'}:
    raise SystemExit('Unsupported Sparkle tool')
candidates = [pathlib.Path(override) / tool] if override else []
candidates += sorted((pathlib.Path(root) / '.build/artifacts').rglob('bin/' + tool))
for path in candidates:
    if path.is_file() and os.access(path, os.X_OK):
        print(path)
        break
else:
    raise SystemExit('Sparkle tools are missing; run scripts/swift.sh build or set PUV_SPARKLE_TOOLS to the official distribution bin directory')
PY
)"
exec "$PUV_EXECUTABLE" "$@"
