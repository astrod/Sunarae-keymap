#!/bin/bash
set -euo pipefail
[[ $# == 1 || ( $# == 2 && "$2" == '--register-only' ) ]] || {
    echo 'Usage: install.sh ARTIFACT_DIRECTORY [--register-only]' >&2; exit 1;
}
artifact_dir="$1"
registration_mode=register
if [[ "${2:-}" == '--register-only' ]]; then registration_mode=register-only; fi
source_app="$artifact_dir/Sunarae.app"
source_tool="$artifact_dir/Support/input-source"
# Packaging checks use an isolated directory and a stub registration tool.
input_dir="${SUNARAE_INPUT_METHODS_DIR:-$HOME/Library/Input Methods}"
installed_app="$input_dir/Sunarae.app"
legacy_app="$input_dir/Dukkeobi.app"
# Keep the registered identity so this upgrades the existing input source.
expected_id='local.inputmethod.Dukkeobi'

[[ -x "$source_tool" && -d "$source_app" ]] || { echo '설치 파일이 없어요. 먼저 빌드해 주세요.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" == "$expected_id" ]] || exit 1
codesign --verify --deep --strict "$source_app"
if [[ "$("$source_tool" current)" == "$expected_id"* ]]; then
    echo '업데이트 전 입력기를 ABC 또는 다른 입력기로 바꿔 주세요.' >&2
    exit 1
fi
previous_app=''
for candidate_app in "$installed_app" "$legacy_app"; do
    if [[ -e "$candidate_app" ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_app/Contents/Info.plist")" == "$expected_id" ]] || {
            echo '같은 이름의 다른 앱이 있어 설치를 중단했어요.' >&2; exit 1;
        }
        [[ -z "$previous_app" ]] || { echo '구버전과 새 버전이 함께 있어요. 설치 경로를 확인해 주세요.' >&2; exit 1; }
        previous_app="$candidate_app"
    fi
done
mkdir -p "$input_dir"
stage_dir="$(mktemp -d "$input_dir/.Sunarae-install.XXXXXX")"
registered=false
moved_new=false
cleanup() {
    if [[ "$registered" == false ]]; then
        if [[ "$moved_new" == true && -d "$installed_app" ]]; then mv "$installed_app" "$stage_dir/Failed.app"; fi
        if [[ -d "$stage_dir/Previous.app" ]]; then
            mv "$stage_dir/Previous.app" "$previous_app"
            "$source_tool" register-only "$previous_app" || true
        fi
    fi
    rm -rf -- "$stage_dir"
}
trap cleanup EXIT
ditto "$source_app" "$stage_dir/New.app"
codesign --verify --deep --strict "$stage_dir/New.app"
if [[ -n "$previous_app" ]]; then
    previous_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$previous_app/Contents/Info.plist")"
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        command_path="$(ps -p "$pid" -o comm= || true)"
        if [[ "$command_path" == "$previous_app/Contents/MacOS/$previous_executable" ]]; then kill -TERM "$pid"; fi
    done < <(pgrep -u "$(id -u)" -x "$previous_executable" || true)
    mv "$previous_app" "$stage_dir/Previous.app"
fi
mv "$stage_dir/New.app" "$installed_app"
moved_new=true
"$source_tool" "$registration_mode" "$installed_app"
registered=true
echo "설치 위치: $installed_app"
