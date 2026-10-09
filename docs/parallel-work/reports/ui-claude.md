# UI 분담 — Claude: 실행 탭 완성

- 작업 폴더: `C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/claude-workout-flow`
- 브랜치: `codex/claude-workout-flow` (시작점 `5c20bde` 구현 초안)
- 기준 문서: `docs/parallel-work/UI_HANDOFF.md`. 최초 작업은 커밋 `05ae172`의 판, 후속 작업은 Codex 워크트리(`346d`)의 'Claude 후속 인수인계 (2026-10-09)'를 직접 읽고 따랐다(읽기만 함).
- 제외: 최초 가입 안내·튜토리얼·사용자 조사. 친구·기록·AccountModel·서버·공통 문서는 수정하지 않았다.
- 상태: 구현 완료. 통합 후보 `81ea364`의 macOS CI에서 **컴파일·모델/계정 검사 통과, 실행 탭 XCTest 실패 없음**. 실기기·화면 확인은 미실행. main 통합 안 함(Codex 담당).

## 후속 작업 (2026-10-09, `a0dd283` 이후)

- **CI 확인**: 통합 후보 `codex/workout-integration-review`의 `81ea364`(내 `17ce159` 포함, 원격에 올라간 최신 판)에서 [Validate GymNote #37935579499](https://github.com/iasanullweb-maker/GymNote/actions/runs/37935579499)와 [Build IPA #37935579428](https://github.com/iasanullweb-maker/GymNote/actions/runs/37935579428)을 확인했다. `93cd1b3`는 원격에 없어 CI가 돌지 않았다.
  - `ios` 작업의 "Model and account regression checks" 단계 **성공**: `executionOrderChecks`와 `test_accounts.swift` 순서 병합 검사가 macOS에서 컴파일·실행돼 통과했다.
  - "iPad simulator build and security regression tests" 단계 **실패**. 앱·테스트 컴파일은 성공했고, 실패 주석은 Codex 담당 `RecordCatalogTests.testCancelledRefreshPreservesCatalogWithoutShowingAnError`(`RecordCatalogTests.swift:87`, 취소 뒤에도 "공통 종목을 갱신하지 못했어요"가 남음) **1건뿐**이다. `WorkoutFlowTests`에는 실패 주석이 없다.
  - 한계: 원본 로그·`.xcresult`·화면 캡처 산출물(`iPad-test-results`)은 GitHub 밖 저장소 호스트에 있어 이 환경에서 받을 수 없었다. 통과 판단은 단계 결과와 실패 주석에 근거한다.
  - `Build IPA` 성공(Release 빌드).
- **Codex 수정 반영**: `81ea364`에서 Codex가 고친 `AppModel.completeSet`을 이 브랜치에 그대로 가져왔다. 세트 저장이 실패해 되돌려졌는데도 휴식 타이머를 새로 시작하던 내 버그다(완료 세트 수가 실제로 늘었을 때만 휴식 시작). 같은 커밋의 `WorkoutFlowTests` 휴식 유지 단언도 가져왔다.
- **회귀 추가**: `testFailedSetDoesNotStartRest`(마지막이 아닌 세트 저장 실패 시 기록·휴식 모두 없음). 이 테스트는 아직 CI에서 돌지 않았다.
- 공유 API는 후속 인수인계의 최신 정의와 같다(`moveExecutionExercises(fromOffsets:toOffset:on:)`·`moveExecutionExercise(_:_:on:)`, `AddRecordView` 호출 유지, `addRecord(_:) -> Bool` 유지·`saveRecord(_:)`). 변경 없음.

### 확인 항목별 상태

| 항목 | 근거 | 실기기·화면 |
|---|---|---|
| 편집 모드 없이 길게 눌러 순서 이동 | `ForEach.onMove`(iOS 16+), 모델 이동 규칙은 CI 모델 검사 통과 | **미실행** — 시뮬레이터 XCTest는 터치 끌기를 검사하지 않음 |
| 완료/미완료 경계 이동 | CI 모델 검사(`executionOrderChecks`)·`WorkoutFlowTests` 통과 | **미실행**(놓은 뒤 묶음 끝으로 돌아가는 모습) |
| iPhone SE 세로·가로, iPad, 큰 글자, 휴식 중 하단 배너 | 코드 검토(각 탭 하단 safeAreaInset, 좁은 높이 대응, 글자 상한) | **미실행** — CI 화면 캡처 산출물을 받지 못함, 실기기 없음 |
| 운동 중 → 운동 완료 → 저장됨 애니메이션 | `savedWorkout`은 실제 저장 성공 시에만 설정, `WorkoutFlowTests` 통과 | **미실행**(애니메이션 모습) |
| 실제 저장 성공·저장 실패·자동 마지막 세트 | `WorkoutFlowTests`(저장 성공/실패/0세트/자동 마지막 세트 성공·실패/계정 전환) 실패 없음 | 해당 없음 |
| macOS GitHub Actions XCTest | 위 링크. 실행 탭 실패 0, Codex 테스트 1건 실패 | — |

## 변경 파일

| 파일 | 변경 |
|---|---|
| `Shared/Models.swift` | 실행 탭 순서 모델: `executionExercises(on:)`, `isExecutionFinished`, `moveExecutionExercises(fromOffsets:toOffset:on:)`(List.onMove 규칙), `moveExecutionExercise(_:_:on:)`·`canMoveExecutionExercise`(접근성 위로/아래로/맨 위로/맨 아래로), `ExecutionMove`. 초안의 `moveExecutionExercise(_:before:on:)`는 제거 |
| `App/AppModel.swift` | `savedWorkout`(실제 저장 성공 시에만 설정)·`dismissSavedWorkout`, `finishWorkout`/자동 마지막 세트에서 저장 확인 후 표시, 순서 변경 래퍼, `saveRecord` → `.rejected/.saved/.newBest`(`addRecord(_:) -> Bool`은 기존 호출용으로 유지) |
| `App/TodayView.swift` | 끌어서 순서 바꾸기를 `onDrag/onDrop` → `ForEach.onMove`로 교체, 접근성 이동 동작, 완료/완료 취소 애니메이션, 종목 기록 메뉴 개선(시트가 닫힌 뒤 결과 알림, 신기록이 아니어도 "기록을 저장했어요"), 탭마다 하던 공통 종목 요청 제거, 상태 배너 높이 축소·가로 화면 대응, `WorkoutCompletionBanner` 추가 |
| `App/GymNoteApp.swift` | 종료 애니메이션을 `model.savedWorkout` 기준으로 변경(운동 중 → 운동 완료 → 운동 일지에 저장됨 → 사라짐, VoiceOver 안내), 배너 글자 크기 상한, 60초 공통 종목 갱신에 30초 재진입 제한·진행 중 요청 비취소 |
| `scripts/test_models.swift` | `executionOrderChecks`: 아래/맨 끝/맨 위/여러 개/제자리/범위 밖, 완료 묶음 경계, 완료 취소 복귀, 재실행(디코딩), 일지 저장 후 보존, 새 운동 순서, 자정 경과, 중복 ID, 휴식일 |
| `scripts/test_accounts.swift` | 순서 변경과 위젯 세트 완료 동시 저장 병합, 다른 곳에서 끝낸 일지를 오래된 순서 변경이 덮어쓰지 않음 |
| `Tests/WorkoutFlowTests.swift` (신규) | AppModel 흐름: 순서 변경 후 진행·재실행 보존, 순서 저장 실패 되돌림, 저장 성공 시에만 종료 표시, 저장 실패 시 활성 운동·휴식 보존, 0세트 취소, 자동 마지막 세트(성공/실패), 계정 전환, 실행 탭 기록 입력(횟수·라운드·정수 검증·저장 실패) |

## 완료 기준별 결과

### 운동 중 표시가 탭·버튼·스크롤을 가리지 않음
- 초안의 배치(각 탭 콘텐츠 `safeAreaInset(edge: .bottom)`)를 유지했다. 탭 막대 위에 붙고 목록은 그 높이만큼 하단 여백을 받아 마지막 버튼까지 스크롤된다. 대안(오버레이·TabView 바깥 inset)은 탭 막대나 목록을 덮으므로 택하지 않았다.
- 배너는 시간과 세트 수를 한 줄에 두고(넘치면 두 줄), 좁은 폭(<600pt) 또는 세로 공간이 좁을 때(`verticalSizeClass == .compact`, 가로 iPhone) 여백·글자를 줄인다.
- 큰 글자: 배너와 종료 표시에 `dynamicTypeSize(...accessibility2)` 상한을 둬 화면을 덮지 않게 했다. 본문 목록은 상한 없음.
- 휴식 상태: 남은 시간 + 세트 수 + 진행도, "건너뛰기". 운동 없이 휴식만 켠 경우 세트 표시는 숨긴다.

### 완료/전체 세트 수와 진행도
- 배너: `n / m 세트` + 진행 막대(VoiceOver는 막대가 "m세트 중 n세트 완료"로 한 번 읽음). 종료 표시에도 세트 수·소요 분·진행 막대.

### 완료한 운동 하단 표시 + 순서 보존
- 화면 목록 = 미완료(저장 순서) + 완료(저장 순서). **저장 순서는 완료로 바꾸지 않는다** → 완료 취소하면 원래 자리로 돌아온다.
- 진행 중 운동은 세션 기록으로 완료 여부를 판단하므로 자정이 지나도 시작한 운동 기준으로 유지된다.

### 길게 눌러 끌어서 순서 바꾸기
- `ForEach.onMove`(iOS 16+에서 편집 모드 없이 길게 눌러 끌기)로 교체했다.
  - 아래로·맨 끝 이동: onMove의 삽입 위치 규칙(옮기기 전 목록 기준 0...count)을 모델이 그대로 받아 처리한다.
  - 끌기 취소: 시스템이 원위치로 되돌리고 모델 호출이 없다(초안의 `draggingExercise` 상태가 남는 문제 제거).
  - 외부 텍스트 드롭: onMove는 같은 ForEach 안의 행만 받으므로 앱 밖 텍스트·다른 섹션 드롭이 순서를 바꾸지 않는다.
  - 저장: 초안은 `dropEntered`마다 순서를 바꿔 끄는 동안 여러 번 저장·동기화 예약을 했다. 이제 놓을 때 한 번만 저장한다.
- 완료/미완료 경계: 각 묶음은 자기가 차지하던 저장 자리 안에서만 재배치된다. 미완료 운동을 완료 묶음으로 끌면 미완료 묶음 끝, 완료 운동을 위로 끌면 완료 묶음 안에 남는다.
- 접근성: 운동 이름 요소에 "위로/아래로/맨 위로/맨 아래로 이동" 동작을 가능한 방향만 제공한다(같은 규칙으로 저장).
- 진행 중 운동: 세션 ID·운동 ID·세트 수·실제 횟수·무게는 그대로이고 `plan.exercises` 순서만 바뀐다. 저장된 일지(`workouts`)는 건드리지 않는다. 같은 날 일정이 같은 운동들로 이뤄져 있으면 일정 순서도 맞춰 "새 운동 시작"에도 순서가 유지된다(일정의 세트·횟수 값은 그대로).
- 위젯이 같은 시각에 세트를 완료해도 `applyingEdits` 병합에서 순서(앱)와 진행(위젯)이 함께 남는 것을 검사에 추가했다.
- 같은 ID가 두 번 들어간 예전 계획은 어느 항목인지 알 수 없어 순서 변경을 거부한다.

### 운동 마치기 애니메이션
- `AppModel.savedWorkout`은 `workouts`에 그 운동이 **실제로 남아 있을 때만** 설정된다. 저장 실패(되돌림)·0세트 시작 취소·위젯/다른 기기에서 끝난 운동(재로드)에는 표시하지 않는다. 초안은 `activeWorkout` 변화를 관찰했기 때문에 위젯·동기화로 끝난 운동에도 표시될 수 있었다.
- 저장 실패: `finishWorkout()`이 false를 돌려주고 활성 운동·휴식 타이머를 유지하며 저장소 알림이 뜬다.
- 자동 마지막 세트: 같은 경로로 저장 확인 후 표시, 휴식은 켜지 않는다.
- 빠른 새 운동 시작·계정 전환: 표시를 즉시 거두고 진행 중 애니메이션 작업을 취소한다. 단계 상태를 운동 ID별로 둬 새 저장은 항상 "운동 중"부터 시작한다.
- 탭 이동: 상태가 RootView/AppModel에 있어 모든 탭 하단에서 이어진다.
- 모션 줄이기: 애니메이션 없이 문구만 바뀌고 첫 단계 대기를 줄인다. 마지막 단계에서 VoiceOver에 "운동 일지에 저장됨"을 알린다.

### 최고 기록 입력(실행 탭)
- `종목 기록 남기기` 메뉴 → `AddRecordView(types:fixedTypeID:onSave:)`(기존 호출 형태 유지). 공통 종목의 횟수(정수)·라운드+추가 횟수·측정 단위(kg·초 등 소수 허용)를 `AddRecordView`가 그대로 받는다.
- 결과 알림은 시트가 닫힌 뒤 띄운다(시트와 알림이 동시에 떠 알림이 사라지는 문제 방지). 신기록이면 "🎉 신기록!", 아니면 "기록을 저장했어요", 저장 실패면 저장소 알림만.

### 앱 활성 중 60초 공통 종목 갱신
- 활성일 때만 반복, 비활성·백그라운드에서 반복 중단(`task(id: scenePhase)` 취소).
- 진행 중 요청은 비구조 Task로 끝까지 받아 취소 오류가 "갱신 실패" 문구로 보이지 않게 했다.
- 30초 안에 다시 활성되면 바로 요청하지 않는다. 동시 요청은 `AccountModel.catalogLoading`이 걸러 낸다.
- 최초 기동: 연결 확인 전 호출은 `isOnline` 조건으로 즉시 반환되고, 연결 후 `AccountModel.autoRefreshProviders()`가 갱신한다.
- 실행 탭이 나타날 때마다 하던 갱신 요청은 제거했다(탭 이동 때마다 화면이 다시 만들어져 요청이 반복됐음).

## 검증

| 검사 | 결과 |
|---|---|
| tree-sitter-swift 구문 분석 (변경한 Swift 7개 파일, 후속 2개 포함) | 통과, 오류 0 |
| 순서 알고리즘 Python 이식 + `executionOrderChecks`와 같은 시나리오 재현 (34개 단언) | 통과 — 검사 스크립트의 기대값을 이것으로 확인 |
| `swiftc Shared/Models.swift scripts/test_models.swift` 실행 | **통과** (CI `81ea364`, 모델·계정 검사 단계) |
| `swiftc ... scripts/test_accounts.swift` 실행 | **통과** (같은 단계) |
| `xcodebuild test` (iPad 시뮬레이터, `WorkoutFlowTests` 포함) | 컴파일 성공, `WorkoutFlowTests` 실패 없음. 작업 전체는 Codex 테스트 1건으로 실패. 후속 추가 테스트 1개는 미실행 |
| Build IPA (Release) | **통과** (CI `81ea364`) |
| 화면 캡처(iPhone SE·가로·iPad·큰 글자·휴식 상태), VoiceOver, 실기기 터치 | **미실행** |

최초 작업 때는 Windows PC·Claude 작업 환경 모두 Swift 툴체인이 없어 구문만 확인했고, 후속에서 위 CI 결과로 컴파일·검사를 확인했다. 기존 절차대로 로컬 통합 후 사용자 승인으로 push해 GitHub Actions **Validate GymNote**(모델·계정 회귀 검사 스크립트, iPad 시뮬레이터 XCTest)와 **Build IPA**에서 확인한다. 새로 추가한 `executionOrderChecks`, `test_accounts.swift` 병합 검사, `WorkoutFlowTests`가 통과하는지 특히 본다(Mac 준비는 사용자 결정으로 보류 중).

배포 후 아이패드에서 AltStore로 업데이트해 꼭 볼 것(아이폰 화면 검증은 보류 중):
1. 편집 모드가 아닌 상태에서 운동 행을 길게 눌러 끌기가 되는지(iOS 16+ onMove 동작). 행 안 버튼 탭과 충돌이 없는지.
2. 미완료 운동을 완료 묶음 쪽으로 끌었을 때 미완료 끝으로 돌아가는 모습이 어색하지 않은지.
3. iPad 세로/가로·분할 화면, 접근성 큰 글자, 휴식 중에 배너가 탭 막대·마지막 버튼을 가리지 않는지. 운동 마치기 애니메이션(운동 중 → 운동 완료 → 운동 일지에 저장됨).

## 남은 문제·Codex 확인 요청 (내가 수정하지 않은 파일)

1. (Codex `81ea364`에서 처리: 관리자 확인을 `busy`에서 분리·이전 상태 유지) ~~`AccountModel.refreshRecordCatalog()`가 매번 `catalogAdminUserID = nil`로 지우고 `refreshCatalogAdmin()`에서 `startOperation("관리자 권한을 확인하는 중…")`을 연다.** 60초 갱신과 함께 쓰면 관리자 화면이 1분마다 깜빡이고, 확인하는 동안 `busy`라 다른 계정 작업(백업 등)이 막히거나 진행 문구가 뜰 수 있다. 제안: 결과가 나올 때까지 이전 값 유지, 같은 사용자를 최근 확인했으면 건너뛰기, 또는 이 확인을 `busy` 작업에서 분리.~~
2. **CI 실패 원인(Codex 확인 필요)**: `81ea364`의 `RecordCatalogTests.testCancelledRefreshPreservesCatalogWithoutShowingAnError`가 `RecordCatalogTests.swift:87`에서 실패한다. 취소 후에도 `catalogMessage`가 "공통 종목을 갱신하지 못했어요. 저장된 목록을 사용합니다."로 남는다. 취소가 `URLError(.cancelled)` 등 다른 형태로 도착하거나, 취소 판정 전에 메시지를 설정하는 경로가 남은 것으로 보인다. 원래 요청: 같은 함수가 취소(`CancellationError`/`URLError.cancelled`)도 "공통 종목을 갱신하지 못했어요"로 표시한다. 내 60초 갱신은 취소하지 않게 했지만 `RecordsView`·`SettingsView`의 `.task`는 탭을 떠나면 취소된다. 취소는 무시하길 제안.
3. (통합 후보 `ef039d2`에서 처리) 병합 시: `codex/friends-records-ui`는 `5c20bde` 이전에서 갈라져 이 네 파일(`TodayView`·`GymNoteApp`·`AppModel`·`Models`)이 초안 이전 상태로 보인다. 이 파일들은 이 브랜치 판을 기준으로 합쳐야 한다.
4. `RecordsView`는 `model.addRecord(_:) -> Bool`(신기록 여부)을 계속 쓸 수 있다. 신기록이 아닐 때도 저장됨을 알리려면 새 `model.saveRecord(_:)`(`.rejected/.saved/.newBest`)를 쓰면 된다. `AddRecordView` 인터페이스는 바꾸지 않았다.
5. 키보드가 올라오는 화면(친구 탭 입력 등)에서는 하단 배너도 키보드 위로 올라온다. 대부분의 편집은 시트라 영향이 작아 이번 범위에서 바꾸지 않았다.
