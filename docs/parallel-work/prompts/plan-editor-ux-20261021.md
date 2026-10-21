# 다음 세션 프롬프트: 날짜 계획 시트 UX 개선 (2026-10-21 작성)

아래 블록 전체를 새 대화(Claude Code 또는 Codex)에 붙여 넣는다.

~~~text
GymNote 저장소(노트북 Documents\2026_IASA\GymNote)에서 '날짜 계획 시트' UX 개선을 이어서 진행해줘.

먼저 읽을 것:
- AGENTS.md, CLAUDE.md, HANDOFF.md, TODOLIST_HANDOFF.md
- PRODUCT.md, DESIGN.md (디자인 기준. 시스템 색, 운동=주황 한 색, Dynamic Type, 운동 중 버튼 52pt 이상, 해요체)
- TODOLIST_HANDOFF.md의 "날짜 계획 시트 UX 개선 (2026-10-21 리뷰)" 항목 전체
- docs/ux-simulation/results/plan-editor-review-20261021.md (리뷰 근거와 코드 위치)

대상 화면: 계획 탭 → 캘린더 날짜 길게 누르기/‘선택한 날짜 계획 설정’ → ScheduledDayEditor (App/RoutineView.swift).
여기서 열리는 PlanCopyView(계획 가져오기), ExercisePicker(운동 추가), ExerciseDraftForm(운동 수정), StarterWorkoutView(기본 루틴)도 범위다.

진행 순서:
1. TODOLIST의 1·2번(실수로 계획이 지워지는 문제)부터. 휴식 계획 가져오기·교체 동작을 고치기 전에 바꿀 방식을 나에게 짧게 확인받아.
2. 3번(되돌리기·저장 실패 안내), 4번(내 운동 목록 쓰기), 5번(계획 이름 기본값) 순서로 진행.
3. 나머지 작은 항목은 한 번에 묶어도 된다. 말투는 해요체로 통일.
각 단계 시작 전에 /impeccable(또는 $impeccable) critique로 해당 부분을 다시 보고, 바꾼 디자인 결정은 DESIGN.md에 반영해.

작업 방식:
- 늘 하던 대로 별도 워크트리에서 작업하고, 검토·검증 후 기존 작업 브랜치(main)에 로컬 통합해.
- 검증은 codex/** 검증 브랜치 push → Build IPA run의 전체 검사·Release·release-gate. 화면은 Tests의 캡처 테스트(UXSimulationCaptureTests, DisplayTests)에 필요한 상태를 추가해 iPad·iPhone·다크로 직접 확인해.
- 저장·데이터 동작이 바뀌면(삭제·교체·되돌리기) 모델 테스트를 함께 추가해.
- main push와 배포는 내가 따로 승인할 때만.
- 끝나면 HANDOFF.md·TODOLIST_HANDOFF.md·결과 문서를 갱신하고, 커밋 ID·통합 여부·검사 범위·push/배포 여부를 알려줘.
~~~
