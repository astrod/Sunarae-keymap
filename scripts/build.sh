#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
dist_dir="$project_dir/dist"
# Stage beside dist so publication uses renames on the same filesystem.
stage_dir="$(mktemp -d "$project_dir/.Sunarae-build.XXXXXX")"
artifact_dir="$stage_dir/Ready"
app_dir="$artifact_dir/Sunarae.app"
published=false
cleanup() {
    local status=$?
    if [[ "$published" == false && -e "$stage_dir/Previous" ]]; then
        if [[ -e "$dist_dir" ]] || ! mv "$stage_dir/Previous" "$dist_dir"; then
            echo "이전 빌드를 복원하지 못했어요. 보관 위치: $stage_dir/Previous" >&2
            return 1
        fi
    fi
    rm -rf -- "$stage_dir"
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$app_dir/Contents/"{MacOS,Resources}
build_library

xcrun swiftc -O "${swift_flags[@]}" \
    -framework AppKit -framework InputMethodKit -framework Carbon \
    Sources/*.swift -o "$app_dir/Contents/MacOS/Sunarae"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
xcrun swift scripts/make-icons.swift "$stage_dir/icons"
iconutil -c icns "$stage_dir/icons/Sunarae.iconset" -o "$app_dir/Contents/Resources/Sunarae.icns"
cp "$stage_dir/icons/MenuIcon.tiff" "$app_dir/Contents/Resources/"
cp vendor/libhangul/COPYING "$app_dir/Contents/Resources/libhangul-LICENSE"
cp spec/sunarae.json spec/sunarae-reference.txt "$app_dir/Contents/Resources/"
if [[ -f THIRD_PARTY.md ]]; then cp THIRD_PARTY.md "$app_dir/Contents/Resources/"; fi

codesign --force --sign - --timestamp=none --options runtime \
    --entitlements Resources/Sunarae.entitlements "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist" Resources/Sunarae.entitlements
mkdir -p "$artifact_dir/Support"
xcrun swiftc -O -target "$swift_target" -framework Carbon \
    scripts/InputSourceTool.swift -o "$artifact_dir/Support/input-source"
codesign --force --sign - --timestamp=none "$artifact_dir/Support/input-source"
codesign --verify --strict "$artifact_dir/Support/input-source"
cp scripts/install.sh scripts/uninstall.sh scripts/diagnose.sh "$artifact_dir/Support/"
cp scripts/Install.command scripts/Uninstall.command scripts/Diagnose.command "$artifact_dir/"
chmod +x "$artifact_dir/Support/"*.sh "$artifact_dir/"*.command
if [[ -f README.md ]]; then cp README.md "$artifact_dir/README.md"; fi
cp CONTRIBUTING.md THIRD_PARTY.md "$artifact_dir/"
mkdir -p "$artifact_dir/docs"
cp docs/INPUT-VERIFICATION-*.md "$artifact_dir/docs/"
cp docs/IMPLEMENTATION.md "$artifact_dir/docs/"

if [[ -e "$dist_dir" ]]; then mv "$dist_dir" "$stage_dir/Previous"; fi
mv "$artifact_dir" "$dist_dir"
published=true
echo "Built: $dist_dir/Sunarae.app"
