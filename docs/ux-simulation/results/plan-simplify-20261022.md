# 날짜 계획 단순화·운동 추가 중복 제거 (2026-10-22, 미배포)

## 사용자 요청
- 운동 추가 시트에서 같은 운동이 ‘내 운동 목록’과 ‘운동 종목’에 두 번 나오지 않게.
- 계획 설정을 더 단순·직관적으로. 계획 이름은 모두 자동.

## 변경
- 운동 추가(`ExercisePicker`): 활성 운동 종목을 한 번씩만 보여 주는 ‘운동’ 구역 하나. 내 운동 목록에 같은 이름(`AppData.exerciseKey`)의 저장 설정이 있으면 행에 세트·횟수를 표시하고 그 설정의 새 복사본으로 시작(`ExerciseChoice`). 미등록 종목의 저장 운동은 추가할 수 없으므로 표시하지 않음. 튜토리얼 단계 1개로 축소.
- 날짜 계획(`ScheduledDayEditor`): ‘운동’ 목록 + 버튼 묶음(운동 추가 · 기본 루틴 불러오기 · 다른 날 계획으로 바꾸기). 구역 머리말·긴 설명 제거, 지난 날짜 안내 문구 제거(기록 보기 링크는 유지). 코치마크 대상 ID는 그대로.
- 자동 이름: `DayPlan.displayTitle`이 저장된 `title`을 무시하고 운동 구성에서 만든다. 앱·위젯·일지·요약 표시를 모두 `displayTitle`로 통일. `PlanEditorSession.rename`·첫 운동 이름 자동 저장 제거. 지난 운동 입력의 ‘일지 제목’ 입력 제거(제목 검증 제거). 주간 목록·위젯에서 이름과 운동 목록이 중복되지 않게 조정.
- 테스트: `test_models.swift` 자동 이름 단언, `PlanEditorTests` rename 제거·`ExerciseChoice` 테스트 추가. UX 시나리오 `record-previous-workout`의 일지 제목 조건 제거. DESIGN.md 날짜 계획 편집 규칙 갱신.

## 검증
- `git diff --check` 통과, 변경 경로 수동 코드 검토.
- 미실행: Swift 컴파일·XCTest·Swift 스크립트·앱/위젯 Release 빌드·화면 캡처. 이 환경(Windows + Linux VM)에 Swift/Xcode 없음. 작은 UI 변경 유예 규칙에 따라 다음 묶음 검증 또는 배포 전 CI에서 해소.
