#!/bin/bash
set -euo pipefail
PIR_ACTION="${1:?Usage: scripts/swift.sh build|test [arguments]}"
shift
PIR_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
# The Clang linker driver resolves SDK metadata from -isysroot on current Swift toolchains.
exec swift "$PIR_ACTION" --sdk "$PIR_SDK_PATH" \
    -Xswiftc -Xclang-linker -Xswiftc -isysroot \
    -Xswiftc -Xclang-linker -Xswiftc "$PIR_SDK_PATH" "$@"
