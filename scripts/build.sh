#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
mkdir -p "$app_dir/Contents/"{MacOS,Resources}
build_library

xcrun swiftc -O "${swift_flags[@]}" \
    -framework AppKit -framework InputMethodKit -framework Carbon \
    Sources/*.swift -o "$app_dir/Contents/MacOS/Sunarae"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
xcrun swift scripts/make-icons.swift "$build_dir"
iconutil -c icns "$build_dir/Sunarae.iconset" -o "$app_dir/Contents/Resources/Sunarae.icns"
cp "$build_dir/MenuIcon.tiff" "$app_dir/Contents/Resources/"
cp vendor/libhangul/COPYING "$app_dir/Contents/Resources/libhangul-LICENSE"
cp spec/sunarae.json spec/sunarae-reference.txt "$app_dir/Contents/Resources/"
if [[ -f THIRD_PARTY.md ]]; then cp THIRD_PARTY.md "$app_dir/Contents/Resources/"; fi

codesign --force --sign - --timestamp=none --options runtime \
    --entitlements Resources/Sunarae.entitlements "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist" Resources/Sunarae.entitlements
mkdir -p dist/Support
xcrun swiftc -O -target "$swift_target" -framework Carbon \
    scripts/InputSourceTool.swift -o dist/Support/input-source
codesign --force --sign - --timestamp=none dist/Support/input-source
cp scripts/install.sh scripts/uninstall.sh dist/Support/
cp scripts/Install.command scripts/Uninstall.command dist/
chmod +x dist/Support/*.sh dist/*.command
if [[ -f README.md ]]; then cp README.md dist/README.md; fi
cp CONTRIBUTING.md dist/CONTRIBUTING.md
cp THIRD_PARTY.md dist/THIRD_PARTY.md
mkdir -p dist/docs
cp docs/INPUT-VERIFICATION-*.md dist/docs/
echo "Built: $app_dir"
