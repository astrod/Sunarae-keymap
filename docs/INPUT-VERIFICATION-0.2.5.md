# 0.2.5 입력 전달 최적화

0.2.4의 실제 입력 처리 시간은 앱 조회·글자 전달 API 호출 안에서 대부분 걸렸다. 0.2.5는 InputSession의 불필요한 호출을 줄이고, 앱 조회 중 확정 요청이 겹칠 때 조합 상태를 보호한다. Composer와 결합표는 바꾸지 않았다. 쉼표 대체 시프트와 두 번 눌러 쉼표를 넣는 규칙도 같다.

## 변경

1. 일반 텍스트의 조합 종료는 내부 상태만 비운다. Enter·Space·Tab·방향키·단축키·일반 문장부호에서 새 글자를 보낼 필요가 없으면 앱을 조회하지 않는다. marked text를 확정할 때는 기존 확인을 유지한다.
2. 쉼표가 일반 문장부호로 쓰여 현재 글자를 그대로 확정하면 같은 글자를 다시 보내지 않는다. 조합을 바꾸거나 지우는 입력에서는 커서와 문자열을 확인한다.
3. 출력의 앞부분이 기존 글자와 같으면 새 뒷부분만 현재 커서에 덧붙인다. `안 → 안ㄴ`에서 `안`까지 다시 교체하지 않는다. 덧붙인 위치는 다음 키에서 한 번 확인한다. `ㄱ → 가`처럼 기존 글자가 바뀌면 기존 범위를 교체한다.
4. 첫 삽입 뒤 위치를 확인할 때 후보 범위를 먼저 정하고 한 번만 읽는다. 예상 커서 위치는 같지만 글자가 바뀌었다면 같은 범위를 다시 읽지 않는다.
5. 입력·확정 처리의 중복 진입 방지를 앱 조회 전부터 적용한다. 이전에는 쓰기 중에만 막았으므로, 조회 중 확정 요청이 조합 상태를 지울 수 있었다. 내부 종료 처리와 외부 확정 요청의 진입점을 분리했다.

## 동작 검사

- 실제 NSTextView를 감싼 검사 클라이언트에서 선택 범위·문자열·marked range 조회 도중 확정 요청을 보냈다. 수정 전 `ㄱ` 뒤에 `ㅏ`를 입력하면 `가` 대신 `ㅏ` 또는 `ㄱㅏ`가 나오는 경로를 재현했다. 수정 후 `가 → 각`으로 이어졌다. 사용자가 보고한 오타의 실제 원인이 이 경로였다고 입증한 것은 아니다.
- 중복 호출·불필요한 쓰기와 위 상태 오류를 확인하는 초기 검사: 수정 전 12,782개 중 34개 실패.
- 덧붙이기, 덧붙이기 직전 앱 편집, 이후 위치 확인과 Backspace 검사를 추가한 최종 결과: **12,801개 검사 모두 통과**.
- 기존 현대 한글 11,172자, 정순·역순 받침 경계, 쉼표 두 번, 외부 편집, 입력창 초기화, 클라이언트 변경, Enter·단축키 전달 검사를 유지했다.
- Composer와 InputController는 0.2.4 백업과 파일 내용이 같음을 확인했다.

실행 명령: `./scripts/test.sh`. 기록: `build/tests-before-0.2.5.txt`, `build/tests-after-0.2.5.txt`.

## 앱 호출 수 비교

같은 Composer와 실제 NSTextView에 0.2.4와 0.2.5의 InputSession을 각각 연결했다. 고정 키 입력 후 Enter까지 처리하고, 결과 문자열이 기대값과 같으며 Enter가 앱으로 전달되는지 확인했다. 앱이 처리한 일반 키는 IME 호출 수에 넣지 않았다.

| 고정 입력 | 앱 호출 수 | 기존 범위를 교체한 횟수 | 보낸 UTF-16 단위 수 |
|---|---:|---:|---:|
| 안녕하세요. 두꺼비로 한글을 입력합니다. | 137 → 129 | 39 → 33 | 56 → 50 |
| 쉼표 복원·세미콜론·콜론·꺾쇠 예문 | 78 → 69 | 20 → 16 | 32 → 28 |
| 안녕하세요 | 38 → 36 | 11 → 9 | 16 → 14 |

이 수치는 호출과 전달량의 비교다. 같은 프로세스의 NSTextView를 사용했으므로 실제 프로세스 사이 통신 시간이나 화면 표시 지연을 측정한 결과가 아니다. 호출 감소 비율을 그대로 반응 속도 향상 비율로 읽으면 안 된다.

[호출 수 원본](verification/0.2.5-call-counts.json), 검사 코드 `Tests/ClientCallProbe.swift`.

재현 명령:

```sh
xcrun swiftc -O -swift-version 5 -I vendor/libhangul build/libhangul.a -framework AppKit Sources/Composer.swift build/backups/0.2.4/InputSession.swift Tests/ClientCallProbe.swift -o build/ClientCallProbe-before
build/ClientCallProbe-before
xcrun swiftc -O -swift-version 5 -I vendor/libhangul build/libhangul.a -framework AppKit Sources/Composer.swift Sources/InputSession.swift Tests/ClientCallProbe.swift -o build/ClientCallProbe-after
build/ClientCallProbe-after
```

## 설치와 확인 범위

0.2.5(9) 빌드, 서명·Info.plist 검사와 자체 검사 `composition_ok=true network_blocked=true errno=1`을 통과했다. 기존 앱을 업데이트하고 입력 소스를 dukkeobi로 복원했다. 설치한 실행 파일과 빌드의 SHA-256 일치 및 설치 앱 서명을 확인했다. 측정용 코드는 포함하지 않는다.

업데이트 후 실제 타이핑의 시간 분포, 체감 지연, 오타율은 아직 다시 측정하지 않았다. 특히 기본 두벌식과의 비교 자료는 없다. 앞서 잰 4.56ms 평균은 0.2.4의 자료다.

기존 앱과 주요 소스는 `build/backups/0.2.4`에 보관했다.
