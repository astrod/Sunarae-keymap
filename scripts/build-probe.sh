#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
build_library
mkdir -p "$probe_dir/Contents/MacOS"
xcrun swiftc "${swift_flags[@]}" -framework AppKit -framework WebKit -framework Carbon \
    "${core_sources[@]}" Tests/InputProbe.swift \
    -o "$probe_dir/Contents/MacOS/InputProbe"
cat > "$probe_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.sunarae.InputProbe</string>
<key>CFBundleName</key><string>Input Probe</string>
<key>CFBundleExecutable</key><string>InputProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$probe_dir"
echo "$probe_dir"
