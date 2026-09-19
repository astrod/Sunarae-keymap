# 0.2.8 마지막 자모 삭제

`ㄹㄹㄹㄹㄹ`을 입력한 뒤 첫 Backspace를 누르면 마지막 ㄹ이 지워지지 않는 문제를 수정했다. 일반 텍스트 경로에서 마지막 조합 자모 한 글자를 지울 때, 두꺼비가 키를 소비하고 빈 문자열 교체를 요청하던 처리를 바꿨다. 이제 내부 조합 상태를 비우고 원래 Backspace를 앱에 넘긴다.

`각 → 가 → ㄱ`, `싫 → 시 → ㅅ`의 중간 자모 삭제는 기존처럼 두꺼비가 처리한다. 실제 marked text를 사용하는 입력창의 삭제도 유지한다. 커서·기존 글자 확인은 그대로 수행한다.

## 재현과 수정 확인

전용 InputProbe의 WKWebView와 CodeMirror에서 CUA의 `pressKey`로 **설치된 시스템 입력기**를 거쳐 확인했다. 고정 예문만 입력했으며 사용자의 SilverBullet 문서는 수정하지 않았다.

- 0.2.7: `f` 5번 뒤 Backspace 1번을 보냈을 때 `ㄹㄹㄹㄹㄹ`이 그대로 남았다. Backspace의 DOM keydown 코드는 IME 처리 상태를 나타내는 229였고, 삭제 beforeinput/input 이벤트가 없었다.
- 0.2.8 일반 모드: 같은 입력에서 ㄹ이 4개로 줄었다. Backspace keydown 코드는 8이었고 `deleteContentBackward` 이벤트가 뒤따랐다. 5번 삭제하면 ㄹ 5개가 모두 사라졌다.
- 일반 모드에서 이어서 `각 → 가 → ㄱ → 빈칸`을 확인했다. 다시 `가`를 입력한 뒤 Enter를 누르면 다음 목록 항목이 생겼다.
- Vim 입력 모드에서도 `f` 5번과 Backspace 5번을 한 묶음으로 보내 모두 지워지는 것을 확인했다. 화면을 확인한 뒤 `tlu`로 싫을 입력하고, 다시 화면을 확인한 뒤 Backspace 3번으로 `시 → ㅅ → 빈칸`을 확인했다.

기록:

- [수정 전 시스템 입력](verification/0.2.8-deletion-before-system.json)
- [수정 후 일반 모드](verification/0.2.8-deletion-after-system.json)
- [수정 후 Vim 모드](verification/0.2.8-deletion-after-system-vim.json)

처음에는 키 이벤트 없이 NSTextInputClient API만 직접 호출하는 검사에서 문제가 나타나지 않았다. 같은 WebKit이라도 이벤트 처리 도중의 IMK 경로가 다르므로, 그 결과만으로 시스템 입력을 검증할 수 없었다. `Deletion API check` 버튼은 이 낮은 단계의 검사이며 실제 입력기를 거친 검사와 구분한다. 이 검사에서 문서 내용·선택 위치는 전용 편집기의 응답으로 갱신한다.

## 자동 검사

**16,110개 검사 모두 통과**했다. 새 검사를 구버전에 적용했을 때에는 587개가 실패했다. 빈 문자열 교체를 무시하는 입력창을 모델로 삼아 첫 삭제 누락과 한 글자 잔류를 확인했다.

- ㄹ·ㄱ·ㅋ·ㅅ·ㅣ를 1회, 5회, 30회 입력한 뒤 한 글자씩 삭제
- 빈 문서, 목록 표식 뒤, 이모지 뒤의 삭제
- Backspace 반복과 모두 지운 뒤 새 한글 입력
- 일반 텍스트와 marked text 경로의 차이
- 기존 11,172자 조합, 겹받침·대체 시프트·편집 검사

검사는 IME가 false를 반환하면 실제 NSTextView의 `deleteBackward`를 실행하도록 했다. 이전 검사 중에는 반환값을 무시해 앱이 담당하는 삭제를 실행하지 않던 부분이 있어 함께 고쳤다.

## 남은 범위

아래에서 기록한 연속 삭제 뒤 입력 순서 문제는 [0.2.9에서 수정했다](INPUT-VERIFICATION-0.2.9.md). 다음 문단은 0.2.8 검사 당시의 기록이다.

CUA로 삭제와 새 자모 입력을 약 5–20ms 간격으로 한꺼번에 보낸 별도 Vim 검사에서, 다음 글자의 IME 삽입이 앞선 Backspace의 웹 keydown보다 먼저 실행되는 경우가 있었다. 그때 새로 쓴 자음이 앞선 Backspace에 지워졌다. 모든 Backspace가 앱에 전달되었으므로 첫 삭제를 소비하던 이번 문제와 구분한다. 이 일반적인 이벤트 순서 문제까지 해결했다는 주장은 하지 않는다. 해당 스트레스 기록은 `build/0.2.8-vim-fast-input.json`에 남겼다. 타이머나 임의 지연은 제품에 추가하지 않았다.

전용 검사에는 SilverBullet의 전체 확장·설정이 들어 있지 않다. 사용자가 신고한 증상을 같은 WebKit·CodeMirror와 시스템 입력 경로에서 재현하고 고쳤으며, 사용자 SilverBullet 문서에서의 최종 사용 확인은 별도다.

## 설치

0.2.8(12)의 빌드·서명·자체 검사를 통과한 뒤 설치했다. 설치 실행 파일과 dist의 SHA-256은 `88d26054aef53342b06ed6eb79f4a213e48b9fc013c23904bd31b9b8c1f7503b`로 같다. 자체 검사 결과는 `composition_ok=true network_blocked=true errno=1`이다. 진단 측정용 plist 키는 없다.

이전 앱·소스·검사는 `build/backups/0.2.7`에 보관했다. [검증 요약](verification/0.2.8.json).
