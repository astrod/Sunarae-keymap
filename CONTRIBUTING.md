# 코드 관리

일반적인 수정은 **파일 수정 → `make check`**로 확인합니다. 입력기를 설치하거나 선택하는 일은 이 명령에 포함하지 않습니다.
현재 앱 버전은 `Resources/Info.plist`에서 관리합니다.

## 어느 파일을 고치나

| 변경할 내용 | 위치 | 확인 방법 |
|---|---|---|
| 순아래 결합 규칙 | `spec/sunarae.json` | 아래 규칙 생성 명령, `make check` |
| 조합 엔진과 한 키 되돌리기 | `Sources/Composer.swift`, `vendor/libhangul/` | `Tests/SunaraeChecks.swift` |
| 키·단축키 처리 | `Sources/KeyMap.swift`, `Sources/InputSession.swift` | `Tests/SessionChecks.swift` |
| 앱에 글자 삽입·교체·삭제 | `Sources/TextDelivery.swift`, `Sources/InputController.swift` | 세션·편집 검사와 실제 시험창 |
| 검사에 쓰는 텍스트 클라이언트 | `Tests/TestSupport.swift` | `make test` |
| 빌드 대상·소스 목록·공통 컴파일 설정 | `scripts/build-common.sh` | `make check`, `make calls`, `make probe` |
| 앱 표시 이름·버전·최소 macOS | `Resources/Info.plist` | `make build` |

조합 규칙을 고칠 때는 생성된 C 헤더를 직접 편집하지 않습니다.

```sh
python3 scripts/generate_combinations.py
make check
```

원본과 다른 규칙을 추가하면 `spec/sources.json`, `vendor/libhangul/CHANGES.md`, 사용법도 함께 갱신합니다.
libhangul 원본 코드는 별도 경계로 유지하며, 다른 파일로 옮기는 작업과 동작 변경을 한 번에 섞지 않습니다.

## 검사 구조

- `Tests/main.swift`: 검사 시작과 결과 집계.
- `Tests/TestSupport.swift`: 공통 도우미와 실제 NSTextView를 감싼 클라이언트.
- `Tests/SunaraeChecks.swift`: 현대 한글 조합·순아래·되돌리기.
- `Tests/SessionChecks.swift`: 확정·커서·문서 교체·중첩 호출.
- `Tests/EditingChecks.swift`: 연속 삭제·붙여넣기·실행 취소.
- `Tests/InputProbe.swift`, `Tests/DeletionProbe.swift`: 별도 시험창에서의 네이티브/WebKit 검사.

`make test`는 기존 `build/libhangul.a`를 믿지 않고 세 C 파일을 새로 빌드합니다. 라이브러리가 없어도 실행할 수 있습니다.
`make check`는 규칙 파일 확인, 앱 빌드, 전체 검사, 서명된 앱의 자체 검사를 순서대로 실행합니다.
여러 빌드 명령은 같은 중간 파일을 쓰므로 별도 터미널에서 동시에 실행하지 않습니다. 하나의 `make` 실행은 순서를 지킵니다.

문자 전달 코드를 바꿨다면 `make web-probe`로 시험창을 빌드하고 실제 키로 확인합니다. 네트워크가 필요한 단계는 웹 시험창의 npm 설치뿐입니다.
시험 항목은 마지막 음절 뒤 Enter로 목록 잇기, 반복 자음 삭제 후 새 글자 입력, 일반/Vim 모드입니다.
사용 중인 키보드와 마우스를 쓰는 시험은 사용자와 시간을 맞춘 뒤 진행합니다.

## 생성 파일과 과거 기록

`Sources`, `Resources`, `scripts`, `Tests`, `spec`, `vendor`가 현재 소스입니다.
`build`, `dist`, `tmp`는 결과물·임시 자료이므로 `.gitignore`에서 제외합니다.
`build/backups`에는 복구용 백업도 있으니 작업 폴더를 정리할 때 백업을 먼저 따로 보관합니다.
현재 설계는 `docs/IMPLEMENTATION.md`, 순아래 검증은 `docs/INPUT-VERIFICATION-0.3.0.md`를 봅니다.
`docs`의 0.2.x 기록과 `docs/archive`는 이전 두꺼비의 기록입니다.

현재 소스 디렉터리는 Git 저장소가 아닙니다. 이번 변경 전 상태는 `build/backups/sunarae-0.3.0-before-maintenance-20260913.tgz`에 보관했습니다.
현재 입력기 동작을 담당하는 `Sources`와 `vendor`는 이번 관리 구조 정리에서 변경하지 않았습니다.
