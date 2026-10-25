#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PUV_ROOT"
"$PUV_ROOT/scripts/swift.sh" test --jobs 2 --parallel --num-workers 2
npm run build --prefix website
node --check website/main.js
node --check website/artwork.js
python3 scripts/check-website.py
python3 -B -m unittest discover -s Tests/ReleaseTools
for PUV_SCRIPT in scripts/*.sh; do
    bash -n "$PUV_SCRIPT"
done
for PUV_SCRIPT in scripts/release/*.sh; do
    bash -n "$PUV_SCRIPT"
done
