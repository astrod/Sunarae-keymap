# Shared by build/test scripts. Keep target settings and core files in one place.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
build_dir="$project_dir/build"
app_dir="$project_dir/dist/Sunarae.app"
probe_dir="$build_dir/InputProbe.app"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
target_arch="$(uname -m)"
swift_target="$target_arch-apple-macosx$minimum_macos"
library="$build_dir/libhangul.a"
core_sources=(Sources/Composer.swift Sources/KeyMap.swift Sources/TextClient.swift
              Sources/TextDelivery.swift Sources/InputSession.swift)
check_sources=(Tests/TestSupport.swift Tests/SessionChecks.swift Tests/SunaraeChecks.swift
               Tests/EditingChecks.swift Tests/main.swift)
swift_flags=(-swift-version 5 -target "$swift_target" -I vendor/libhangul "$library")

build_library() {
    # These three small C files are always rebuilt. A test must never silently
    # use yesterday's library after a source or generated-header change.
    mkdir -p "$build_dir"
    local source
    local objects=()
    for source in hangulctype hangulinputcontext hangulkeyboard; do
        xcrun clang -O2 -fPIC -mmacosx-version-min="$minimum_macos" -DENABLE_EXTERNAL_KEYBOARDS=0 \
            -Wno-tautological-constant-out-of-range-compare -I vendor/libhangul \
            -c "vendor/libhangul/$source.c" -o "$build_dir/$source.o"
        objects+=("$build_dir/$source.o")
    done
    xcrun ar rcs "$library" "${objects[@]}"
}
