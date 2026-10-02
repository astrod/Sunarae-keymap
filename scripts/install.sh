#!/bin/bash
set -euo pipefail
[[ $# == 1 || ( $# == 2 && ( "$2" == '--register-only' || "$2" == '--switch-to-abc' ) ) ]] || {
    echo 'Usage: install.sh ARTIFACT_DIRECTORY [--register-only|--switch-to-abc]' >&2; exit 1;
}
artifact_dir="$1"
registration_mode=register
if [[ "${2:-}" == '--register-only' ]]; then registration_mode=register-only; fi
source_app="$artifact_dir/Sunarae.app"
source_tool="$artifact_dir/Support/input-source"
input_dir="${SUNARAE_INPUT_METHODS_DIR:-$HOME/Library/Input Methods}"
installed_app="$input_dir/Sunarae.app"
expected_id='local.inputmethod.Sunarae'
[[ -x "$source_tool" && -d "$source_app" ]] || { echo '설치 파일이 없어요. 먼저 빌드해 주세요.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" == "$expected_id" ]] || exit 1
codesign --verify --deep --strict "$source_app"
previous_id=''
previous_enabled=false
if [[ -e "$installed_app" ]]; then
    previous_id="$("$source_tool" inspect "$installed_app")" || { echo '같은 이름의 다른 앱이 있어 설치를 중단했어요.' >&2; exit 1; }
    [[ -n "$previous_id" ]] || exit 1
    previous_enabled="$("$source_tool" enabled "$installed_app")"
    [[ "$previous_enabled" == true || "$previous_enabled" == false ]] || exit 1
fi
read_current() {
    current_source="$("$source_tool" current)" || return 1
    [[ -n "$current_source" && "$current_source" != unknown ]]
}
using_app() {
    [[ "$current_source" == "$expected_id"* || ( -n "$previous_id" && "$current_source" == "$previous_id"* ) ]]
}
read_current || { echo '현재 입력기를 확인하지 못해 설치를 중단했어요.' >&2; exit 1; }
if using_app; then
    if [[ "${2:-}" != '--switch-to-abc' ]]; then
        echo '업데이트 전 입력기를 ABC 또는 다른 입력기로 바꿔 주세요.' >&2; exit 1
    fi
    "$source_tool" select-abc
    for ((attempt=0; attempt<20; attempt++)); do
        read_current || { echo '전환 상태를 확인하지 못해 설치를 중단했어요.' >&2; exit 1; }
        if ! using_app; then break; fi
        sleep 0.05
    done
    if using_app; then echo '입력기 전환이 끝나지 않았어요. 다시 설치해 주세요.' >&2; exit 1; fi
fi
mkdir -p "$input_dir"
stage_dir="$(mktemp -d "$input_dir/.Sunarae-install.XXXXXX")"
registered=false
moved_new=false
restore_old=false
cleanup() {
    local status=$?
    if [[ "$registered" == false ]]; then
        if [[ "$moved_new" == true && -d "$installed_app" ]]; then
            "$source_tool" disable || true
            if ! mv "$installed_app" "$stage_dir/Failed.app"; then echo "복구 파일 보관 위치: $stage_dir" >&2; return 1; fi
        fi
        if [[ -d "$stage_dir/Previous.app" ]]; then
            if ! mv "$stage_dir/Previous.app" "$installed_app"; then echo "복구 파일 보관 위치: $stage_dir" >&2; return 1; fi
        fi
        if [[ "$restore_old" == true && -d "$installed_app" ]]; then
            mode=register-only
            if [[ "$previous_enabled" == true ]]; then mode=register; fi
            "$source_tool" "$mode" "$installed_app" || true
        fi
    fi
    rm -rf -- "$stage_dir"
    return "$status"
}
trap cleanup EXIT
ditto "$source_app" "$stage_dir/New.app"
codesign --verify --deep --strict "$stage_dir/New.app"
# Recheck immediately before stopping the running input method.
read_current || { echo '현재 입력기를 확인하지 못해 설치를 중단했어요.' >&2; exit 1; }
if using_app; then echo '순아래가 다시 선택되어 설치를 중단했어요.' >&2; exit 1; fi
if [[ -n "$previous_id" ]]; then
    restore_old=true
    if [[ "$previous_id" != "$expected_id" ]]; then "$source_tool" disable-bundle "$installed_app"; fi
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        command_path="$(ps -p "$pid" -o comm= || true)"
        if [[ "$command_path" == "$installed_app/Contents/MacOS/Sunarae" ]]; then kill -TERM "$pid"; fi
    done < <(pgrep -u "$(id -u)" -x Sunarae || true)
    mv "$installed_app" "$stage_dir/Previous.app"
fi
mv "$stage_dir/New.app" "$installed_app"
moved_new=true
"$source_tool" "$registration_mode" "$installed_app"
registered=true
echo "설치 위치: $installed_app"
if [[ -n "$previous_id" && "$previous_id" != "$expected_id" ]]; then
    echo '새 입력기 ID로 옮겼어요. Esc 전환과 한영 전환 키는 새로 설정해 주세요.'
fi
echo '설치 후 특정 앱에서 영문만 나오면 내용을 보관하고 해당 앱을 완전히 종료한 뒤 다시 열어 주세요.'
