#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
build_library
xcrun swiftc -g "${swift_flags[@]}" -framework AppKit \
    "${core_sources[@]}" "${check_sources[@]}" -o "$build_dir/SunaraeTests"
"$build_dir/SunaraeTests"
xcrun swiftc -g "${swift_flags[@]}" -framework AppKit -framework Carbon -framework InputMethodKit \
    "${core_sources[@]}" Sources/InputSource.swift Sources/InputController.swift Tests/MenuChecks.swift \
    -o "$build_dir/SunaraeMenuTests"
"$build_dir/SunaraeMenuTests"
