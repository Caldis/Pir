#!/bin/bash
set -euo pipefail
PUV_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUV_CONFIGURATION=debug "$PUV_ROOT/scripts/build.sh"
open "$PUV_ROOT/dist/Puv.app"
