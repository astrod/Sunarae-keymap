#!/bin/bash
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: diagnose.sh ARTIFACT_DIRECTORY' >&2; exit 1; }
artifact_dir="$1"
source_tool="$artifact_dir/Support/input-source"
input_dir="${SUNARAE_INPUT_METHODS_DIR:-$HOME/Library/Input Methods}"
[[ -x "$source_tool" ]] || { echo '진단 도구가 없어요. 먼저 빌드해 주세요.' >&2; exit 1; }
result=0

show_bundle() {
    local label="$1" bundle="$2" version build
    echo "$label: $bundle"
    if [[ ! -d "$bundle" ]]; then
        echo '  상태: 없음'
        return
    fi
    if version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist" 2>/dev/null)" &&
       build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle/Contents/Info.plist" 2>/dev/null)"; then
        echo "  버전: $version ($build)"
    else
        echo '  버전: 읽기 실패'
        result=1
    fi
    if codesign --verify --deep --strict "$bundle"; then
        echo '  서명: 정상'
    else
        echo '  서명: 검증 실패'
        result=1
    fi
}

echo '두벌식 순아래 진단'
echo "macOS: $(sw_vers -productVersion) / $(uname -m)"
show_bundle '빌드 파일' "$artifact_dir/Sunarae.app"
show_bundle '설치 파일' "$input_dir/Sunarae.app"
if [[ -e "$input_dir/Dukkeobi.app" ]]; then show_bundle '이전 이름의 설치 파일' "$input_dir/Dukkeobi.app"; fi
if current_source="$("$source_tool" current)" && [[ -n "$current_source" && "$current_source" != unknown ]]; then
    echo "현재 입력기: $current_source"
else
    echo '현재 입력기: 조회 실패'
    result=1
fi
echo '순아래 등록 상태:'
if ! "$source_tool" status; then result=1; fi
echo '진단은 버전·서명·등록 상태만 읽으며 입력 내용은 수집하지 않습니다.'
exit "$result"
