# 친구·기록·실행 화면 개선: Codex / Claude 분담

2026-10-09 사용자 요청으로 분담했다. 최초 가입 안내·튜토리얼·사용자 조사는 제외한다. 기존 아이디어 자동화와 UX 시뮬레이션 소유 범위는 변경하지 않는다. Codex 담당은 구현·격리 DB/구문 검증을 완료했으며 실행 탭·전체 iOS 검사·운영 적용은 남아 있다.

## 작업 폴더

| 담당 | 절대 경로 | 브랜치 | 상태 |
|---|---|---|---|
| Codex | `C:/Users/Donghyun/.codex/worktrees/346d/GymNote` | `codex/friends-records-ui` | 담당 구현·격리 DB/구문 검사 완료. 자세한 결과는 reports/ui-codex.md |
| Claude | `C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/claude-workout-flow` | `codex/claude-workout-flow` | 실행 탭 구현 `17ce159`, Actions 문서 `a0dd283`까지 완료. 아래 인수인계 기준으로 이어서 작업 |
| 로컬 통합 대상 | `C:/Users/Donghyun/Documents/2026_IASA/GymNote` | `main` | 최종 검토·검증 후 직렬 통합 |

Claude 워크트리는 실제 생성했으며, Claude 실행·채팅 메시지 전달은 하지 않았다. Claude 워크트리의 기존 배정표에는 이 새 분담이 아직 없으므로 이 문서와 아래 최신 인수인계를 우선한다.

## Claude 후속 인수인계 (2026-10-09)

Claude가 이어서 작업할 기준은 `codex/claude-workout-flow`의 `a0dd283c5c1932dfb8e943998ccad7688d95e017`이다. 실행 탭 구현은 `17ce159`에 있으며, Codex 통합 후보 `codex/workout-integration-review`의 `93cd1b3`에서 친구·기록 UI와 함께 교차 검토 중이다. Claude 워크트리의 담당 파일만 수정하고, 친구·기록·서버·공통 문서는 건드리지 않는다.

통합 후보에서 이미 고정된 공유 API는 다음과 같다.

- `moveExecutionExercise(_:before:on:)`는 제거되었고 `moveExecutionExercises(fromOffsets:toOffset:on:)`, `moveExecutionExercise(_:_:on:)`를 사용한다.
- `AddRecordView` 호출 형태는 유지된다.
- `AppModel.addRecord(_:) -> Bool`는 유지되며, 저장 결과가 필요하면 `saveRecord(_:)`의 `.rejected/.saved/.newBest`를 사용한다.
- `AccountModel.refreshRecordCatalog()`는 관리자 권한 확인을 `busy` 계정 작업에서 분리하고, 이전 관리자 상태를 확인 결과 전까지 유지하며, 취소 오류를 사용자 오류로 표시하지 않는다.

Claude 후속 작업은 macOS CI의 `Validate GymNote` iPad 시뮬레이터 결과를 확인하고 필요한 실행 탭 수정만 커밋하는 것이다. 반드시 확인할 항목은 편집 모드 없이 길게 눌러 끌기, 완료/미완료 경계에서의 이동, iPhone SE 세로·가로, iPad, 큰 글자와 휴식 중 하단 배너가 탭 막대·마지막 버튼을 가리지 않는지, 운동 중 → 운동 완료 → 운동 일지에 저장됨 애니메이션의 실제 저장 성공 연동이다. 현재 Windows에서는 Swift/Xcode를 실행할 수 없으므로 macOS CI 결과를 근거로 기록한다.

후속 커밋은 담당 파일만 포함하고 `docs/parallel-work/reports/ui-claude.md`에 변경·CI 링크·실기기 미실행 여부를 갱신한다. Codex는 해당 커밋을 다시 교차 검토한 뒤 `C:/Users/Donghyun/Documents/2026_IASA/GymNote`의 `main`에 UX 통합 잠금을 사용해 로컬 병합한다. 원격 `main` push, 운영 SQL 적용, 릴리스 배포는 별도 승인 없이는 하지 않는다.

## Claude: 실행 탭 완성

수정 가능 파일: `App/TodayView.swift`, `App/GymNoteApp.swift`, `App/AppModel.swift`, `Shared/Models.swift`, `Tests/WorkoutFlowTests.swift`(신규), `scripts/test_models.swift`, `docs/parallel-work/reports/ui-claude.md`(신규). 필요하면 실행 흐름 회귀를 위해 `scripts/test_accounts.swift`도 수정한다. 다른 파일의 변경 필요는 보고서에 요청하고, Codex 담당 파일은 수정하지 않는다.

완료 기준:

- 운동 중 표시가 하단 탭·버튼·스크롤 내용을 침범하지 않는다. 좁은 화면, iPad, 큰 글자, 휴식 상태에서도 확인한다. 현재 초안은 각 탭 콘텐츠의 하단 safeAreaInset으로 이동했다. 더 적합한 배치가 있으면 이 소유 범위 안에서 수정한다.
- 운동 중 표시에 완료/전체 세트 수와 진행도를 포함한다.
- 완료한 운동은 목록 아래에 자동 표시한다. 나머지 운동의 사용자가 정한 순서는 유지하고, 완료 취소·재실행·자정 경과·일지 저장 후에도 진행 기록이 보존된다.
- 운동을 길게 눌러 끌어서 순서를 바꿀 수 있다. 현재 `moveExecutionExercise(_:before:on:)`는 대상 앞에만 삽입하므로 **아래로 이동·맨 끝 이동을 완성**해야 한다. 드래그 취소 후 상태 정리, 외부 텍스트 드롭 거부, 완료 항목과 미완료 항목 경계, 접근성 순서 변경도 확인한다. 진행 중 운동의 순서 변경은 세트 ID·실제 횟수·무게를 바꾸거나 저장된 일지를 덮어쓰면 안 된다.
- 운동 마치기에서 **운동 중 → 운동 완료 → 운동 일지에 저장됨** 애니메이션을 보여 준다. 실제 저장 성공일 때만 저장 완료를 표시하고, 저장 실패 시 활성 운동·휴식 상태를 보존한다. 0세트 시작 취소에는 저장 완료를 표시하지 않는다. 자동 마지막 세트 완료, 빠른 새 운동 시작, 계정 전환, 탭 이동, 모션 줄이기도 확인한다.
- 최고 기록 입력 버튼은 실행 탭에서 제공한다. 현재 `종목 기록 남기기` 메뉴와 `AddRecordView` 연결이 초안에 있다. Codex는 최고 기록 화면의 추가/수정 진입점을 제거하므로 이 경로를 유지한다. 공통 횟수·라운드·측정 단위 종목을 입력할 수 있어야 한다.
- `GymNoteApp.swift` 초안에는 앱 활성 중 60초 간격 공통 종목 갱신이 포함돼 있다. 이 부분은 Codex의 `AccountModel.refreshRecordCatalog()` 개선과 함께 동작해야 한다. 중복 요청·백그라운드 취소·최초 기동을 확인한다.

검증: 순서 변경·완료 분리·진행 기록 보존·재실행·저장 실패 회귀를 추가한다. 가능한 Swift 모델 검사와 iOS 검사를 수행하고, 불가능한 검사는 정확하게 미실행으로 기록한다. 이 Windows 환경에는 Swift/Xcode가 없고, 전체 iOS 빌드는 아직 실행하지 않았다. UI 초안은 화면 캡처로 검증하지 않았다.

## Codex: 친구·기록·공통 종목

담당 파일: `App/FriendsView.swift`, `App/SocialModel.swift`, `App/AuthClient.swift`, `App/AccountModel.swift`, `App/RecordsView.swift`, `App/ResponsiveLayout.swift`, `supabase/migrations/202610090003_social_withdraw.sql`, `scripts/test_social_withdraw.sql`, `scripts/test_record_catalog.sql`, `Tests/RecordCatalogTests.swift`, `Tests/AccountTests.swift`, `.github/workflows/check.yml`, `docs/SOCIAL_SETUP.md`, `docs/RECORD_CATALOG_SETUP.md`, `docs/parallel-work/UI_HANDOFF.md`, `docs/parallel-work/ASSIGNMENTS.md`, `docs/parallel-work/reports/ui-codex.md`, `HANDOFF.md`.

완료 기준:

- 친구 가입 화면을 로그인 화면처럼 읽기 쉽게 변경한다. 친구 추가는 친구 목록 첫 줄로 옮기고 중복 상단 버튼은 제거한다.
- 친구 기능 탈퇴를 추가한다. 앱 계정·개인 운동 기록을 보존하면서 닉네임·친구 코드·관계·그룹 참여·공개 기록을 제거한다. 그룹장 이전·빈 그룹 삭제·재가입·권한·동시 요청을 검증한다. 새 마이그레이션 초안은 아직 운영 서버에 적용하지 않았다.
- 기록 순서는 **운동 일지 → 친구 → 최고 기록**, 기본 화면은 운동 일지로 한다. 최고 기록의 +와 해당 화면에서 값을 갱신하는 경로를 제거하고 기록 조회를 유지한다. 입력·갱신은 실행 탭 또는 지난 운동 기록에서 한다. 기록 → 친구 → 순위 보기의 친구 추가 버튼을 삭제한다.
- 관리자 추가 종목이 다른 이용자에게 보이지 않는다는 의심을 확인한다. 서버의 `list_record_catalog()`는 이미 익명·일반 사용자에게 허용돼 있다. 클라이언트 캐시 저장 실패가 최신 목록 표시까지 막던 부분은 초안에서 분리했다. 관리자 추가 → 일반 사용자 조회·활성 상태·앱 화면 갱신을 회귀 검사한다. 공통 최고 기록 종목과 개인 루틴 목록은 별개이므로 증거 없이 모든 개인 목록을 공통 목록으로 바꾸지 않는다. 실제 두 계정 재현은 아직 하지 않았다.

## 공유 API와 통합

- `AddRecordView`의 기존 호출 형태 `types:`, `fixedTypeID:`, `onSave:`를 유지한다. 인터페이스 변경이 필요하면 먼저 보고서에 기록하여 양쪽 호출을 조율한다.
- Codex는 `RecordSection`의 `onAdd` 매개변수를 제거하며 `ResponsiveLayout.swift`도 함께 수정한다. Claude는 이 두 파일을 수정하지 않는다.
- 각 담당은 자기 파일만 명시적으로 stage·커밋하고 본인 보고서에 변경, 검사 통과/미실행, 남은 문제를 적는다. 미완료 초안은 완료 처리하거나 main에 통합하지 않는다.
- 이 두 워크트리는 기존 A/B/C/D 및 Unified 배정 경로가 아니므로 `parallel_work.ps1 -Role ...`로 잘못된 역할을 지정하지 않는다. 직접 병합할 때 같은 `C:/Users/Donghyun/Documents/2026_IASA/GymNote/.validation-tools/ux-integration.lock`을 CreateNew로 얻고 main 브랜치·미커밋 변경·진행 중 Git 작업을 재확인한다. 다른 소유자의 잠금·변경을 보존한다. 최종 교차 검토·로컬 통합은 Codex가 총괄한다.
- 원격 push·Actions 실행·배포·운영 SQL 적용은 이번 분담에서 실행하지 않는다. 전체 iOS 검사·빌드는 통합 검증 시 Mac/Xcode 환경에서 수행한다.

## Claude에 전달할 시작 메시지

```text
GymNote 실행 탭 개선을 맡아줘.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/claude-workout-flow
브랜치: codex/claude-workout-flow
체크포인트: a0dd283 (17ce159 실행 탭 구현 및 Actions 검증 문서 반영 후속 기준)

먼저 cwd, 브랜치, git status, AGENTS.md를 확인하고,
C:/Users/Donghyun/.codex/worktrees/346d/GymNote/docs/parallel-work/UI_HANDOFF.md를 읽어줘.
그 문서의 Claude 담당 파일과 완료 기준에 따라 실행 탭을 완성하고 검토·검증해줘.
최초 가입 안내·튜토리얼·사용자 조사는 제외야.
친구·기록·AccountModel·서버·공통 문서는 Codex 담당이므로 수정하지 마.
특히 드래그의 아래/맨 끝 이동, 완료 운동 하단 표시, 세트 진행도,
하단 탭과 겹치지 않는 상태 표시, 실제 저장 성공에 맞는 종료 애니메이션을 확인해줘.
실행 탭의 종목 기록 입력과 앱 활성 중 공통 종목 갱신은 유지해줘.
결과와 검증·미실행·교차 변경 필요사항은 docs/parallel-work/reports/ui-claude.md에 기록하고
담당 파일만 커밋해줘. 최종 main 교차 검토·직렬 통합은 Codex가 맡아.
현재 통합 후보 `codex/workout-integration-review`의 `93cd1b3`에는 네 실행 탭 변경과 Codex 친구·기록 변경이 함께 들어가 있다. 공유 API는 위 인수인계의 최신 정의를 따르고, 다른 작업자의 변경을 덮어쓰거나 강제 push/reset/임의 stash를 하지 마.
```
