# 날짜 계획 시트 디자인 리뷰 (2026-10-21, Impeccable critique · 네이티브 단일 평가)

대상: 계획 탭 → 날짜 길게 누르기 → `ScheduledDayEditor`(App/RoutineView.swift)와 여기서 여는 `PlanCopyView`·`ExercisePicker`·`ExerciseDraftForm`·`StarterWorkoutView`. 근거: 사용자 iPad 실기기 스크린샷(0.1.119, 다크), CI 캡처 `plan-date-detail` iPad·iPhone·큰 글씨, 코드 읽기. 사용자가 2026-10-21 모든 항목을 할 일로 승인.

## Nielsen 점수 (21/40)

| 기준 | 점수 | 근거 |
|---|---|---|
| 상태 가시성 | 2 | 삭제·순서·이름 변경에 저장 표시·실패 안내 없음 |
| 실제 세계 일치 | 3 | 쉬운 말, 반말·존댓말 섞임 |
| 사용자 통제·자유 | 1 | 삭제·교체 되돌리기 없음 |
| 일관성 | 2 | 길게 누르기 결과가 날짜마다 다름, 추가 경로가 나뉨 |
| 오류 예방 | 1 | 휴식 가져오기 한 번에 계획 삭제 |
| 인식 vs 기억 | 2 | 가져오기 목록이 계획 이름만 보여 줌 |
| 유연성·효율 | 2 | 숫자 +/−만, 내 운동 목록 미사용 |
| 미니멀 디자인 | 3 | iOS 기본 구성 |
| 오류 회복 | 2 | 추가·수정만 저장 실패 안내 |
| 도움말 | 3 | 각 칸 footer 설명 |

## 우선 항목 (코드 위치)

1. **휴식 계획 가져오기가 확인 없이 계획을 비운다.** `PlanCopyView`: 날짜/요일 목록에 휴식(빈 계획)도 나오고 `onCopy(source)`가 그대로 `scheduledPlans[key] = copy`로 교체. 교체 안내는 요일 Section footer에만 있어 위쪽 '날짜에서 가져오기'에서는 보이지 않음.
2. **추가와 교체가 바로 위아래에 섞임.** '기본 루틴 선택해서 추가'(`appendStarterWorkout`, 뒤에 추가) vs '다른 날짜 / 기존 요일 계획 가져오기'(교체). '운동 추가'는 위 Section, 기본 루틴은 아래 Section.
3. **삭제·순서·이름 변경이 저장 확인 경로를 거치지 않고 되돌리기가 없다.** `ScheduledDayEditor.plan` Binding setter가 `model.data.scheduledPlans`에 직접 쓴다(`shortSwipeAction`, `onMove`, `TextField`). 추가·수정은 `model.saveEdit` + 실패 문구. PRODUCT.md 원칙 4 위반.
4. **내 '운동 목록'이 운동 추가에 없다.** `ExercisePicker`는 `CatalogExerciseSection`(관리자 종목)만, `CatalogRecordType.makeExercise()` 기본값(예: 10회)으로 시작. `exerciseLibrary` 기본 세트·횟수는 `ManualWorkoutView`에서만 사용. `saveToLibrary`는 항상 false인 죽은 상태(켜는 UI 없음).
5. **계획 이름 기본값이 '운동'.** 휴식일에 추가하면 `updated.title = "운동"`. 주간 목록·가져오기 목록이 이름만 보여 줘 구분 불가. 운동 이름 요약(예: "푸쉬업·풀업") 표시 검토.

## 작은 항목

- 기록이 있는 날을 길게 누르면 `WorkoutJournalDayDetail`이 열려 그날 계획 편집 불가(`RoutineView` sheet 분기).
- 지난 날짜 계획을 그대로 수정 가능(반복은 오늘·지난 날짜 제외라 안내와 어긋남).
- 말투 혼용: "교체해. … 유지돼."(PlanCopyView), "반복하면 … 덮어써."(RoutineView) vs "정하세요/시작해요".
- 운동 행을 누르면 수정 화면이 열리지만 › 표시 없음(`Button` + `ExerciseSummary`).
- 툴바 '편집'(EditButton)이 계획 이름 편집처럼 읽힘.
- 목표 횟수는 Stepper(1…9999)만, 직접 입력 불가. 표기 "세트: 3" vs 다른 화면 "3세트".
- `PlanCopyView` 날짜 기본값이 오늘 → 오늘 계획 편집 중이면 버튼이 이유 없이 비활성.

## 좋은 점

- 큰 글씨(accessibility3) 캡처에서 잘림 없이 줄바꿈.
- 주황은 누를 수 있는 글자에만(DESIGN.md Spotlight·Semantic 규칙 준수).

리뷰 스냅샷(.impeccable/critique)은 저장하지 않았다.
