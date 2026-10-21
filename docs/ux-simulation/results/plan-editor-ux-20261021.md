# 날짜 계획 편집 UX 개선 (2026-10-21, 기술 완료·미배포)

- 사용자 지정 프롬프트에 따라 시작. 별도 워크트리 .worktrees/plan-editor-ux, 브랜치 codex/plan-editor-ux-20261021, 시작 main a776f8b. 사용자에게 휴식 가져오기 비활성·추가/교체 분리·교체 확인창을 쉬운 예로 설명했고 “일단 해보고 나중에 확인하자”로 승인받았다.
- 실제 사용자 확인은 별도다. main push·배포 승인은 없다. codex/** 검증 브랜치 push와 Build IPA 전체 검사·Release·release-gate, 캡처 검토는 지정 프롬프트에서 승인한 범위다.

## 구현

1. 휴식/빈 계획은 목록에 남기고 비활성+이유 표시. 같은 날짜도 이유 표시. 기본 가져올 날짜는 편집 대상 전날. 교체 전 원본·대상·현재/새 계획 이름과 운동 목록/개수를 별도 확인 시트에 보여 준다. 선택 후 대상 내용이 바뀌면 교체를 거부하고 다시 선택하도록 안내한다.
2. ‘계획한 운동’, ‘운동 추가’(개별 종목·기본 루틴), ‘계획 교체’를 구분한다.
3. PlanEditorSession이 삭제·되돌리기·이름·순서·추가·교체를 saveEdit에 연결한다. 세션은 열릴 때 store generation을 고정하고 계정 변경 후 저장을 거부한다. 삭제 undo는 그 날짜의 before/after만 보관하며 현재 날짜 계획이 after와 같을 때만 복원한다. 전체 계정 복원 없음. 자동 만료 없음. 저장 실패 시 원본과 undo 토큰을 유지한다. 이름 입력은 별도 시트의 draft로 실패 후에도 남는다.
4. 내 운동 목록을 운동 추가에 함께 표시한다. 선택한 운동은 새 UUID를 부여한 복사본으로 세트·횟수·setReps를 보존하고 원본 템플릿은 바꾸지 않는다. 등록 해제 종목은 이유와 함께 비활성. 사용하지 않던 saveToLibrary Bool을 제거한다.
5. 휴식일의 첫 운동 추가는 운동 이름을 기본 제목으로 쓰고, 빈 제목은 DayPlan.displayTitle에서 이름 요약을 표시한다. 기존 ‘운동’ 등 명시적으로 저장한 사용자 제목은 보존한다. 새 데이터 필드/마이그레이션 없음.
6. 운동 계획 달력 길게 누르기는 기록 유무와 관계없이 계획 편집. 기록 링크는 계획 화면 안에 별도 제공. 과거 계획 수정은 허용하되 저장된 기록 불변을 안내하고 진행 중 날짜는 편집 차단. 해요체, 행 ›, 순서 편집 툴바, ‘N세트’, 공통/세트별 횟수 직접 입력과 1~9999 검증을 적용한다. 일상 캘린더의 기존 동작은 별도 범위로 보존한다.

## 단계별 디자인 재검토

- impeccable critique의 네이티브 Assessment A(분리된 읽기 전용 에이전트)로 1·2를 재검토: 현재 날짜/요일 버튼이 즉시 전체 교체하고 빈 배열 allSatisfy가 삭제를 막지 않음을 확인. 추가·교체 분리, 비활성 이유 상시 표시, 같은 개수여도 운동 내용 비교를 제안해 반영했다.
- 3·4·5·6도 구현 전 별도 코드 재검토: 이름 draft·generation 검사, 동일 날짜 후속 변경 보호 undo, 원본 복사 독립성, 기존 사용자 제목 보존, 과거 일지/진행 세션 불변, 숫자 입력 검증을 반영했다.
- 네이티브이므로 웹 detector는 해당 없음. 이 코드 기반 판단을 화면 캡처/실기기 성공으로 간주하지 않는다. 구체 디자인 결정은 DESIGN.md에 기록했다.

## 검사 계획과 현재 상태

- Tests/PlanEditorTests.swift에 실제 저장/실패 주입·삭제 undo·후속 변경 보호·계정 세대 변경·순서/이름 저장·라이브러리 복사·진행 중 차단 테스트를 추가했다.
- scripts/test_models.swift에 빈 교체 거부·복제 ID/상세 횟수·이름 보존·숫자 입력 경계 모델 회귀를 추가했다.
- UXSimulationCaptureTests에 가져오기/교체 확인/내 운동 선택/상세 횟수/이름/하단 동작을 iPad·iPhone·다크로 추가하며 큰 글자 상태도 캡처한다.
- 로컬 Windows에 Swift/Xcode 없음. 정적 검토 후 검증 브랜치 push → 같은 SHA의 Build IPA 전체 검사·Release·release-gate와 캡처 직접 확인이 로컬 통합 전 조건이다. 실행 결과는 확인 후 갱신한다.

## 구현 후 추가 검토와 중간 캡처

- 독립 코드 리뷰에서 기본 루틴의 계정 세대 우회 경로를 발견해 isCurrentOwner 진입 차단·계정 변경 시 열린 시트 종료·StarterWorkoutView.expectedOwner 저장 재검사로 수정했다. 후속 리뷰에서 기존 P1 해소와 추가 명백한 문제 없음 확인.
- RepetitionDraft를 추출해 공통→상세, 개별 수정, 세트 증감, invalid 입력 유지/복구, 상세→공통 전환을 모델 회귀로 검증하도록 추가했다. 오래된 상세 횟수 배열 길이 불일치는 폼 시작 시 복구한다. 저장할 때는 모든 값이 유효해야 한다.
- 중간 run 39554348734의 합성 캡처를 확인해 큰 글자에서 횟수 항목명이 글자 단위로 줄바꿈되는 문제와 교체 확인 제목 잘림을 발견했다. 횟수 이름과 입력/조절을 두 줄로 나누고 보조 편집창은 inline 제목으로 수정했다. 휴식 원본 비활성 이유가 보이는 하단 캡처도 추가했다.
- 중간 캡처는 공개 아티팩트를 nightly.link의 공식 공개 다운로드 경로로 읽었다(https://nightly.link/). 중간 run들은 후속 push로 취소됐으므로 최종 성공 근거로 사용하지 않는다.
- 최종 제품/검사 소스 ab82b71. 해당 소스의 Build IPA 39555785924가 성공했고 최종 캡처를 직접 확인했다. 아래에 근거와 범위를 기록한다.
- 스냅샷: .impeccable/critique/2026-10-21T06-22-54Z__app-routineview-swift.md (구현 전·후 코드 평가 이력, 캡처 확인 전 판단임을 명시).

## 최종 검증·한계

- 검증 SHA: ab82b71d64ae166f8e1f027558877d5381b78ac5. 대상 기준 main: a776f8bf09614ead2ea34b1276c06075fba34097. [Build IPA 39555785924](https://github.com/iasanullweb-maker/GymNote/actions/runs/39555785924)에서 checks/ios·database·account-deletion·tooling, 앱/위젯 Release build, release-gate 모두 성공. publish는 main이 아니므로 의도대로 skipped.
- iPad XCTest: 177개, 기존 4개 건너뜀, 실패 0. 새 PlanEditorTests 8개 전부 통과. 건너뜀은 고정 시계 없는 workout-ready/rest와 인증된 합성 상태 없는 friends-home/ranking 캡처로 이번 계획 편집 검사는 건너뛰지 않았다.
- 같은 SHA에서 swiftc Shared/Models.swift scripts/test_models.swift와 실행 결과 'Plan editor model checks passed' 확인. 계정·수동 기록·병합·일상·기록·친구 순위·서명 회귀도 CI 통과. 앱 밖 도구 검사는 CI tooling job으로 통과.
- 로컬 Windows: 변경 Swift 9개 Tree-sitter 문법 오류 없음, 제품 diff·저장/계정/undo 경계 수동 검토, git diff --check 통과. 로컬 Swift/Xcode 실행은 하지 않았으며 실제 컴파일·XCTest·Release 근거는 위 CI다.
- 최종 iPad-test-results 아티팩트 12325418423(13,036,681바이트)를 공식 GitHub API로 내려받아, 그 SHA의 iPad 834×1194·iPhone 393×852·다크·큰 글자 캡처 16장을 직접 봤다. 큰 글자 횟수 라벨/값의 글자 단위 줄바꿈과 교체 제목 잘림 해소, 휴식 원본 비활성 이유, 추가/교체 구분, 내 운동 목록 및 등록 해제 표시, 이름 저장창을 확인했다.
- 직접 확인한 파일: plan-actions iPhone 라이트/다크, plan-copy iPad, plan-copy-rest iPhone 다크, plan-replacement-confirmation iPad·iPhone 라이트/큰 글자 다크, plan-exercise-picker iPad/iPhone 다크, plan-name iPhone 라이트/다크, plan-repetitions iPad/iPhone 라이트/큰 글자 다크, plan-date-detail iPad 큰 글자/다크. 원본은 manifest.json의 suggestedHumanReadableName으로 대조했다. 로컬 보관: 원본 폴더 .validation-tools/plan-editor-ci/39555785924/{results.zip,ios.log,test-attachments,review}.
- 미실행/한계: 실제 기기 터치·VoiceOver·실제 숫자 키보드 입력 및 교체 성공 후 두 시트 종료 동작은 이번 직접 조작 검증에 포함하지 않았다. 캡처는 실제 SwiftUI 화면의 합성 상태 렌더이며 전체 사용자 동작 성공을 뜻하지 않는다. 다음 승인 배포 후 사용자가 확인한다.
- 원격에는 codex/plan-editor-ux-20261021 검증 브랜치만 push했다. 로컬 GCM 다계정 선택 문제는 저장소 계정을 명시해 해결했다(인증값/개인 계정 정보는 기록하지 않음). main push·릴리스/AltStore 게시·운영 데이터 변경 없음.
- 이 검증 후 추가한 것은 결과·HANDOFF·TODOLIST·critique Markdown뿐이다. 제품/검사/CI 입력이 검증 SHA와 같은 것을 대조한 뒤 원본 잠금·브랜치/양쪽 상태/기준 SHA 확인 아래 main에 fast-forward 통합한다. 최종 문서 커밋·실제 통합 결과는 완료 응답에 제공한다.

## 승인 후 정식 배포 (2026-10-21)

사용자 “배포 진행해” 승인 후 통합 main a34b782를 push하고 Build #133 / 39557827990으로 전체 검사·Release·게이트·publish를 통과했다. 앱/위젯 0.1.133 (133), build-133/latest SHA와 실제 IPA·AltStore 소스가 일치한다. [배포 대조 결과](release-133-20261021.md). 설치·실기기 조작 확인은 여전히 대기다.
