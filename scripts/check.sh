#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PUV_ROOT"
swift test --jobs 2 --parallel --num-workers 2
npm run build --prefix website
node --check website/main.js
python3 scripts/check-website.py
for PUV_SCRIPT in scripts/*.sh; do
    bash -n "$PUV_SCRIPT"
done
