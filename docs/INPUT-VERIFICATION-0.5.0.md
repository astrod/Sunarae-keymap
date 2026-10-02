# Sunarae 0.5.0 (19)

## 변경

앱·입력 소스·IMK 연결 ID를 `local.inputmethod.Sunarae`로 통일했다.
사용하지 않는 배열 보관 파일과 과거 시험 자료를 제거했다.
macOS 기본 설치 프로그램에서 여는 현재 사용자용 `.pkg`를 추가했다.

이전 ID는 설치된 순아래 앱의 정보를 읽어 확인하며 코드에 이름을 나열하지 않는다.
새 ID로 옮길 때는 기존 입력 소스를 해제하고 설정을 기본값으로 시작한다.
설치 전 ABC 전환, 교체 직전 현재 입력기 재확인, 실패 시 파일과 활성화 상태 복원을 검사한다.

## 확인 상태

- 조합·세션·편집 268,581개 검사 통과.
- IMK 메뉴, 전환 키 검증·저장·충돌·키 반복 검사 통과.
- 설치·복구·빌드·진단 검사 6개 및 `.pkg` 내용 검사 1개 통과.
- 기존 ID의 활성화 여부를 달리한 설치 성공·실패·목록 갱신 대기, ABC 전환 실패·미완료·교체 직전 재선택을 대역으로 확인했다.
- `make calls`: 바꾼 순아래 예문과 기존 문장부호·단어 출력 확인.
- 서명된 앱 자체 검사: `composition_ok=true network_blocked=true errno=1`.
- `installer -dominfo`: `CurrentUserHomeDirectory`만 허용.
- `installer -showChoicesXML`: 현재 사용자 대상으로 패키지를 읽고 설치 항목을 표시함.
- 패키지를 풀어 새 앱 ID·TIS ID·연결 이름, 앱 서명과 postinstall 내용을 확인했다.

## 실제 설치 확인

2026-10-03 이 Mac에서 `.pkg`를 macOS 기본 설치 프로그램으로 열어 교체했다.

- 현재 사용자 홈 폴더 대상 설치가 성공했다. 관리자 암호는 요청하지 않았다.
- 설치된 앱의 버전은 `0.5.0 (19)`, 앱·입력 소스 ID는 `local.inputmethod.Sunarae`다.
- 설치된 실행 파일의 SHA-256이 배포 앱과 일치한다: `01e96ea95e40d7e799600338aed62fb5e044fc1868cbc9bb07279a6305f86d87`.
- 이전 입력 소스를 해제하고 기존 앱을 교체했다. 현재 선택은 ABC다.

새 입력기를 설정에서 추가했지만, 새 프로세스가 읽은 입력 소스 목록에는 활성 상태로
반영되지 않았다. 등록 도구를 다시 실행하면 `registered=true enabled=false`가 나오며,
설정에서 추가한 뒤에도 시험창의 사용 가능 목록에는 ABC와 기본 두벌식만 보였다.
입력기 연결 서비스 재시작으로도 풀리지 않았고, `imklaunchagent`에는
`LaunchInputMethod() Error, status=-50`가 남았다.

## 다시 로그인한 뒤 입력 확인

사용자가 로그아웃·다시 로그인하고 입력 소스를 추가한 뒤
`registered=true enabled=true selected=true`와 새 ID를 확인했다.
승인 창의 표시·승인 과정은 직접 관찰하지 않았다.

첫 시험에서는 순아래를 선택했어도 영문이 나왔다. 기본 두벌식으로 전환해 한글 입력을
확인한 뒤 순아래를 다시 선택하자, 설치 파일을 바꾸지 않고 아래 시험을 통과했다.
첫 선택 당시 시험창은 비활성 상태였으므로, 이 증상의 원인을 연결 이름이나 설치 파일로
단정하지 않는다. 앞서 수집한 연결 오류만으로 실제 입력 실패 원인을 확정할 수는 없다.

- NSTextView: `rkk → 까`, Enter 한 번으로 `- 까\n`.
- WebKit + CodeMirror: `djfuqek → 어렵다`, Enter 한 번으로 `- 어렵다\n- `.
- 웹 Enter 이벤트: `keyCode=13`, `isComposing=false`, 편집기 `composing=false`.
- 웹 연속 삭제: `ㄹㄹㄹㄹㄹ` 입력 직후 Backspace 다섯 번으로 모두 제거.
- 삭제 직후 `rkk → 까` 입력, Backspace로 `까 → 가 → ㄱ → 빈칸` 확인.

글자 입력·Enter에서는 조합 표시를 유지하지 않았다. 삭제 과정에서는 WebKit의
`deleteCompositionText`와 `compositionend` 이벤트가 발생했지만, 편집기의
`composing` 상태는 false였으며 삭제 뒤 글자가 남지 않았다.

시험창을 닫은 뒤에도 순아래가 활성화·선택된 상태를 확인했다. 이번 실제 입력 시험은
전용 NSTextView·WebKit 시험창에서 진행했다. SilverBullet·Chrome·Codex 각각에서
직접 입력하거나 Esc·사용자 지정 전환 키를 다시 시험한 것은 아니다.

`.pkg`는 Developer ID 서명·공증을 받지 않았다.
