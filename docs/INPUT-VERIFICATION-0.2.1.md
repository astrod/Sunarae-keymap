# 0.2.1 입력 전달 수정과 검증

확인한 오류는 문서 접근 지원 여부를 길이 0인 substring 조회로 판정한 것이다. 이 Mac의 실제 NSTextView는 `{0,0}`, `{2,0}`, 문서 끝의 `{3,0}`에 모두 `nil`을 반환했다. 같은 문서에서 글자 `가`의 `{2,1}` 조회는 정상 문자열을 반환했다. 빈 범위 조회의 실패는 문서 접근 미지원의 증거가 아니다.

수정 전 테스트의 `ViewClient.text`는 NSString의 `substring`을 호출해 빈 문자열을 반환했다. 이를 실제 NSTextView의 `attributedSubstring(forProposedRange:actualRange:)`로 바꾸자 69개 검사가 실패했다. marked text 호출이 계속 발생하고 Enter에서 추가 확정 삽입을 하는 것도 확인했다.

수정한 IMKClient는 macOS가 공개한 `kTSMDocumentSupportDocumentAccessPropertyTag` 지원 여부를 `supportsProperty`로 확인한다. 유효한 선택 범위도 확인하며, 다음 입력에서 기존 글자의 위치와 내용을 검증하는 안전 검사는 유지한다. 두겹이 조합과 대체 시프트는 변경하지 않았다. 지금 확인된 오류를 고치는 데 기능 삭제는 필요하지 않았다.

| 검사 | 결과 | 검사하지 않은 범위 |
|---|---|---|
| 실제 AppKit 조회를 사용하는 조합·편집 검사 | 수정 전 69개 실패, 수정 후 11,914개 모두 통과 | 실제 IMK 프로세스 간 호출 |
| WKWebView + CodeMirror의 확정된 `- 어렵다`에서 Enter | `- 어렵다\n- `, 일반 모드와 Vim 입력 모드 모두 통과 | 한글을 만드는 시스템 입력 경로 |
| 서명된 입력기의 self-check | composition_ok=true, network_blocked=true | 앱별 입력 호환성 |
| 검사 앱의 자동 한글 입력 | 기본 두벌식을 선택해도 영문으로 입력됨. 앱 비활성 상태 확인 | 성공으로 계산하지 않음 |
| 실제 키보드 → 0.2.1 → 설치된 SilverBullet | 사용자가 Enter 한 번으로 목록이 이어진다고 확인 | 자동 재현 결과는 아님 |

CodeMirror 검사는 목록 문자열을 테스트가 직접 추가하지 않는다. 실제 Markdown 키맵에 Enter 이벤트를 전달하고 결과 문서를 검사한다. 다만 예문 자체는 검사 코드가 문서에 넣으므로, 이 결과를 실제 IME 입력 검증으로 확대하지 않는다. 기본 NSTextView 검사에서 사용하던 수동 `\n- ` 삽입도 제거했다.

검사 환경은 macOS 26.6.2, WebKit 21624.5.1.11.3이다. CodeMirror 패키지는 [SilverBullet 2.10.0의 lockfile](https://github.com/silverbulletmd/silverbullet/blob/2b2a7c719bb3546df8c78ddeaf95256535ee2dd3/package-lock.json)을 확인해 view 6.41.0, state 6.6.0, lang-markdown 6.5.0, codemirror-vim 6.3.0으로 고정했다. 별도 검사기는 SilverBullet의 전체 설정이나 실제 로드된 클라이언트를 복제한 것은 아니다.

검사를 다시 실행하는 방법:

```sh
./scripts/build.sh
./scripts/test.sh
./dist/Dukkeobi.app/Contents/MacOS/Dukkeobi --self-check
bash scripts/build-probe.sh
bash scripts/build-web-probe.sh
```

`build/InputProbe.app`의 **Editor regression** 버튼은 일반 모드와 Vim 모드의 목록 명령을 검사한다. **Native: Apple / Native: dukkeobi** 또는 **Web: Apple / Web: dukkeobi**를 선택한 뒤 검사 창에 `어렵다`와 Enter를 직접 입력하면, 이 창 안의 API 호출 또는 웹 이벤트를 비교할 수 있다. 웹 검사에서는 필요하면 Vim mode를 선택한 뒤 입력 소스를 누른다. Run fixed sample은 입력기 호출과 실제 한글 출력이 확인될 때만 입력 경로 검사로 인정한다.

이 별도 검사 앱은 고정 예문용이며, 이 창의 입력 내용과 호출 기록을 `build/input-probe.jsonl`에 저장한다. 일반 입력기에는 이 기록 기능을 넣지 않았다. 검사 창 이외의 입력을 감시하거나 네트워크로 전송하지 않는다.

최종 확인은 설치된 SilverBullet에서 두꺼비로 `- 어렵다`를 직접 입력한 직후 Enter 한 번으로 목록이 이어지는 것이다. 실패하면 검사 창의 같은 입력과 비교해 문서 접근 지원 결과, marked text 발생 여부, Enter 이벤트와 편집기 조합 상태를 좁혀서 확인한다. 기능 삭제나 더 큰 전달 방식 변경은 이 결과를 보고 결정한다.

0.2.0 복원 파일은 `build/backups/0.2.0`에 있다. 다른 입력기를 선택한 뒤 `./scripts/install.sh "$PWD/build/backups/0.2.0" --register-only`로 복원할 수 있다. 이 버전에도 원래 Enter 문제는 남아 있다.
