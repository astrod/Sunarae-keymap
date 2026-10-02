#!/bin/bash
set -euo pipefail
# This package is only for Installer's current-user home domain.
# Refuse a root/system invocation rather than touch another user's input methods.
if [[ "$(id -u)" == 0 ]]; then
    echo '현재 사용자용 설치만 지원해요. sudo 없이 설치 프로그램에서 열어 주세요.' >&2
    exit 1
fi
unset SUNARAE_INPUT_METHODS_DIR
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$script_dir/Payload/Support/install.sh" "$script_dir/Payload" --switch-to-abc
