#!/bin/bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: uninstall.sh ARTIFACT_DIRECTORY' >&2; exit 1; }
source_tool="$1/Support/input-source"
installed_app="$HOME/Library/Input Methods/Sunarae.app"
[[ -x "$source_tool" ]] || { echo '삭제 도구가 없어요. 먼저 빌드해 주세요.' >&2; exit 1; }
if [[ -e "$installed_app" ]]; then
    "$source_tool" inspect "$installed_app" >/dev/null
    "$source_tool" disable-bundle "$installed_app"
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        command_path="$(ps -p "$pid" -o comm= || true)"
        if [[ "$command_path" == "$installed_app/Contents/MacOS/Sunarae" ]]; then kill -TERM "$pid"; fi
    done < <(pgrep -u "$(id -u)" -x Sunarae || true)
    "$source_tool" trash "$installed_app"
else
    "$source_tool" disable
fi
echo '입력 소스에서 두벌식 순아래를 제거하고 앱을 휴지통으로 이동했어요.'
