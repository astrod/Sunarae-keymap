#!/bin/bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: uninstall.sh ARTIFACT_DIRECTORY' >&2; exit 1; }
source_tool="$1/Support/input-source"
[[ -x "$source_tool" ]] || { echo '삭제 도구가 없어요. 먼저 빌드해 주세요.' >&2; exit 1; }
for installed_app in "$HOME/Library/Input Methods/Sunarae.app" "$HOME/Library/Input Methods/Dukkeobi.app"; do
    [[ ! -e "$installed_app" ]] || [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")" == 'local.inputmethod.Dukkeobi' ]] || {
        echo '같은 이름의 다른 앱이 있어 삭제를 중단했어요.' >&2; exit 1;
    }
done
"$source_tool" disable
for installed_app in "$HOME/Library/Input Methods/Sunarae.app" "$HOME/Library/Input Methods/Dukkeobi.app"; do
    [[ -e "$installed_app" ]] || continue
    executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$installed_app/Contents/Info.plist")"
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        command_path="$(ps -p "$pid" -o comm= || true)"
        if [[ "$command_path" == "$installed_app/Contents/MacOS/$executable" ]]; then kill -TERM "$pid"; fi
    done < <(pgrep -u "$(id -u)" -x "$executable" || true)
    "$source_tool" trash "$installed_app"
done
echo '입력 소스에서 두벌식 순아래를 제거하고 앱을 휴지통으로 이동했어요.'
