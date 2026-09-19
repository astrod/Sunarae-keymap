#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
build_library
xcrun swiftc -O "${swift_flags[@]}" -framework AppKit \
    "${core_sources[@]}" Tests/ClientCallProbe.swift -o "$build_dir/SunaraeClientCallProbe"
"$build_dir/SunaraeClientCallProbe"
