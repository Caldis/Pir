#!/bin/bash
set -euo pipefail
PUV_ACTION="${1:?Usage: scripts/swift.sh build|test [arguments]}"
shift
PUV_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
# The Clang linker driver resolves SDK metadata from -isysroot on current Swift toolchains.
exec swift "$PUV_ACTION" --sdk "$PUV_SDK_PATH" \
    -Xswiftc -Xclang-linker -Xswiftc -isysroot \
    -Xswiftc -Xclang-linker -Xswiftc "$PUV_SDK_PATH" "$@"
