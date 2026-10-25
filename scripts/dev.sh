#!/bin/bash
set -euo pipefail
PIR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIR_CONFIGURATION=debug "$PIR_ROOT/scripts/build.sh"
open "$PIR_ROOT/dist/Pir.app"
