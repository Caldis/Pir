#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PIR_ROOT"
"$PIR_ROOT/scripts/swift.sh" test --jobs 2 --parallel --num-workers 2
python3 scripts/check-localizations.py
npm run build --prefix website
node --check website/main.js
node --check website/artwork.js
python3 scripts/check-website.py
python3 -B -m unittest discover -s Tests/ReleaseTools
for PIR_SCRIPT in scripts/*.sh; do
    bash -n "$PIR_SCRIPT"
done
for PIR_SCRIPT in scripts/release/*.sh; do
    bash -n "$PIR_SCRIPT"
done
