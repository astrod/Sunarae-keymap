#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/build-common.sh"
artifact_dir="$project_dir/dist"
[[ -d "$artifact_dir/Sunarae.app" && -x "$artifact_dir/Support/input-source" ]] || {
    echo '먼저 make build를 실행해 주세요.' >&2; exit 1;
}
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact_dir/Sunarae.app/Contents/Info.plist")"
package_dir="$(mktemp -d "$build_dir/package.XXXXXX")"
trap 'rm -rf -- "$package_dir"' EXIT
mkdir -p "$package_dir/Scripts/Payload/Support"
ditto "$artifact_dir/Sunarae.app" "$package_dir/Scripts/Payload/Sunarae.app"
cp "$artifact_dir/Support/input-source" "$artifact_dir/Support/install.sh" "$package_dir/Scripts/Payload/Support/"
cp LICENSE THIRD_PARTY.md "$package_dir/Scripts/Payload/"
cp scripts/package-postinstall.sh "$package_dir/Scripts/postinstall"
chmod +x "$package_dir/Scripts/postinstall"
# Current-user installation uses the same checked replacement as the CLI.
# Keeping the app in Scripts avoids replacing an active input method before
# the script has checked the current source and staged a recoverable copy.
pkgbuild --nopayload --scripts "$package_dir/Scripts" \
    --identifier local.inputmethod.Sunarae.installer --version "$version" "$package_dir/Component.pkg"
cat > "$package_dir/Distribution.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
  <title>두벌식 순아래 $version</title>
  <welcome file="welcome.html" mime-type="text/html"/>
  <conclusion file="conclusion.html" mime-type="text/html"/>
  <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
  <options customize="never" require-scripts="true" hostArchitectures="$target_arch"/>
  <volume-check><allowed-os-versions><os-version min="$minimum_macos"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="sunarae"/></choices-outline>
  <choice id="sunarae" visible="false"><pkg-ref id="local.inputmethod.Sunarae.installer"/></choice>
  <pkg-ref id="local.inputmethod.Sunarae.installer" version="$version">Component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$package_dir/Distribution.xml" --package-path "$package_dir" \
    --resources Resources/Installer "$package_dir/Sunarae.pkg"
package_path="$artifact_dir/Sunarae-$version-$target_arch.pkg"
mv "$package_dir/Sunarae.pkg" "$package_path"
echo "Built: $package_path"
