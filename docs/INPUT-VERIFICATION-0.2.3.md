# 0.2.3 조합 종료 시 중복 조회 제거

0.2.2의 `input`은 모든 키에서 `reconcile`을 실행한 뒤, Space·Enter·Tab·방향키·Command/Control/Option 단축키에서는 `commit`을 호출했다. `commit`도 `reconcile`을 실행하므로 같은 키에서 문서 확인을 두 번 했다.

조합을 끝내는 키는 `commit` 안에서 한 번만 확인하도록 호출 위치를 바꿨다. Backspace와 한글 입력은 처리 전에 기존 확인을 유지한다. 앱 전환 등으로 `commit`을 직접 호출하는 경로도 기존 확인을 유지한다. 조합 엔진, 결합표, 대체 시프트와 앱에 글자를 쓰는 방식은 변경하지 않았다.

## 검사

실제 NSTextView를 사용하는 어댑터에서 문서 조회 호출 수를 기록했다. Enter, Space, Tab, 왼쪽 방향키, Command-C, Control-Space, Option-R을 일반 텍스트와 marked text 경로에서 각각 검사했다.

- 수정 전: 중복 조회에 대한 검사 21개 실패.
- 수정 후: 12,021개 검사 모두 통과.
- 일반 텍스트 경로: 선택 범위 조회 2→1회, 기존 글자 조회 2→1회. 조합 종료에서 추가 텍스트 삽입은 여전히 0회.
- marked text 경로: marked range 조회 2→1회. 정상 조합은 한 번 확정하며 앱이 이미 지운 조합을 다시 넣지 않는다.
- 기존 한글·겹받침·대체 시프트·Backspace·커서 이동·외부 편집·입력창 초기화 검사도 통과했다.
- 앱 빌드와 서명 검증 통과. 자체 검사 결과는 `composition_ok=true network_blocked=true errno=1`이다.
- 기존 설치를 0.2.3(7)로 업데이트하고 입력 소스를 두꺼비로 복원했다. 업데이트 뒤의 체감 지연 감소는 아직 측정하지 않았다.

## 받침 결합의 비용

조합 엔진은 정해진 결합표를 키 입력 즉시 적용한다. 정순·역순 받침 결합을 위해 다음 키를 기다리는 타이머는 없다.

최적화 빌드에서 고정 입력을 20,000번씩 7회 반복했다. 각 반복의 초기화와 결과 문자열 길이 확인을 포함한 평균 시간을 키 수로 나누고, 7개 평균의 중앙값을 구했다.

| 입력 | 키당 평균 시간의 중앙값 |
|---|---:|
| 기본 입력 `rkrk` | 0.154µs |
| 정순 받침 `rkfr` | 0.133µs |
| 역순 받침 `rkrf` | 0.131µs |
| 역순 받침 뒤 모음 `rkrfk` | 0.130µs |
| 대체 시프트 `r;k` | 0.114µs |
| `안녕하세요` | 0.150µs |

이는 짧은 고정 입력의 로컬 계산 비용이다. 모든 입력의 최대 지연이나 실제 키 입력부터 화면 표시까지의 시간은 아니다. 앱과의 통신, 글자 교체, 화면 그리기는 포함하지 않았다. 이 결과만으로 체감 버벅임의 원인을 확정할 수 없지만, 조합 계산에 긴 대기가 들어 있다는 근거는 없다.

측정 코드와 원본 결과는 `build/composition-benchmark/main.swift`, `build/composition-benchmark/result.json`에 있다. 실행 명령:

```sh
xcrun swiftc -O -swift-version 5 -I vendor/libhangul build/libhangul.a Sources/Composer.swift build/composition-benchmark/main.swift -o build/composition-benchmark/run
build/composition-benchmark/run
```

기존 0.2.2 앱과 소스는 `build/backups/0.2.2`에 보관했다.
