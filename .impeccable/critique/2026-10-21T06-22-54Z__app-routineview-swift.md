---
target_identity: "file:C:\\Users\\Donghyun\\Documents\\2026_IASA\\GymNote\\.worktrees\\plan-editor-ux\\App\\RoutineView.swift"
target_fingerprint: "sha256:8ce77010a4561e51cf706e67133052f7b94401d2be0a70204f1cc3508059c0d5"
target_path: "C:\\Users\\Donghyun\\Documents\\2026_IASA\\GymNote\\.worktrees\\plan-editor-ux\\App\\RoutineView.swift"
timestamp: 2026-10-21T06-22-54Z
slug: app-routineview-swift
---
# 날짜 계획 편집: 단계별 네이티브 코드 critique

범위: ScheduledDayEditor·PlanCopyView·ExercisePicker·ExerciseDraftForm·StarterWorkoutView.
증거: 소스 코드와 기존 리뷰 문서. 이번 평가에서 실제 화면 캡처는 아직 확인하지 않았다.
방식: 분리된 Assessment A, iOS 네이티브여서 웹 detector는 해당 없음.

## 디자인 구체성

기존 iOS Form·Section·DatePicker를 유지한다. 핵심은 표현을 바꾸는 것이 아니라 날짜별 계획을 실수 없이 추가·교체·복구할 수 있게 만드는 것이다.

## 구현 전 Nielsen 점수

| 기준 | 점수 |
|---|---:|
| 상태 가시성 | 2 |
| 실제 세계 일치 | 3 |
| 사용자 통제 | 2 |
| 일관성 | 2 |
| 오류 예방 | 1 |
| 인식 우선 | 2 |
| 효율 | 3 |
| 미니멀 디자인 | 3 |
| 오류 회복 | 2 |
| 도움말 | 2 |
| 합계 | 22/40 |

장점: 네이티브 기본 컴포넌트, 복제 운동에 새 UUID 부여, 기존 명시적 저장 실패 처리.
인지 부담: 사용자가 추가와 교체의 의미를 외워야 하고 빈 원본의 파괴적 결과를 미리 알 수 없다.
정서: 초보 사용자는 가져오기를 추가로 오해하고, 기존 계획이 많은 사용자는 준비한 내용 유실에 불안해진다.

## 단계별 우선 결정

1~2. 빈 계획/동일 날짜에 비활성 이유를 직접 표시. 개수뿐 아니라 현재/새 운동 목록도 비교. 추가는 한 그룹, 교체는 별도 그룹과 확인.
3. 이름 draft 저장, 날짜별 before/after undo, 실패 토큰 유지와 store generation 검사. 전체 AppData 복원 금지.
4. 내 운동 목록은 설정을 보존한 새 ID 복사본. 등록 해제는 이유와 비활성.
5. 기존 제목이 수동 지정인지 알 수 없으므로 일괄 마이그레이션 금지. 새 휴식일 첫 추가의 이름을 개선하고 빈 이름은 요약.
6. 날짜 길게 누르기는 운동 계획 편집으로 일관되게. 기록은 별도 링크. 과거 기록 불변, 진행 중 편집 차단. 숫자 raw draft 검증과 큰 글자 확인.

## 구현 후 코드 재검토

- P1: 이전 에디터에서 계정 전환 후 새 기본 루틴 창으로 새 계정에 저장할 수 있는 경로. isCurrentOwner로 진입 차단/계정 변경 시 시트 정리, StarterWorkoutView에도 expectedOwner 전달로 저장 시 원래 generation 검사하도록 수정.
- 오래된 세트별 횟수 배열 길이 불일치로 폼 복구가 막히는 위험: 초기화 시 길이 정규화하고 RepetitionDraft로 모드 전환·크기·입력을 검증. 모델 회귀에 상태 전환과 잘못된 입력 복구 추가.
- 두 시트 성공 종료와 실제 VoiceOver/키보드 입력 흐름은 소스 판단만으로 성공 처리하지 않으며 CI 캡처·사용자 후속 확인이 필요.

Questions skipped: 사용자가 1·2 변경 방식을 승인했으며 이후 구현·검증 진행을 요청했다.

## 최종 캡처 확인 (부모 작업, 2026-10-21)

검증 SHA ab82b71의 Build IPA 39555785924 전체 검사/Release/release-gate 성공 후 캡처 16장 직접 확인.
큰 글자에서 횟수 라벨의 글자 단위 줄바꿈은 두 줄 입력 행으로 해소됐고, 교체 확인 제목은 inline으로 모두 보였다.
휴식 원본은 이유와 함께 회색 비활성, 추가/교체 영역은 분리되어 보인다. 내 운동 목록·이름 저장창도 iPad/iPhone·다크에서 확인했다.
실제 기기 입력·VoiceOver·교체 후 두 시트 닫기를 조작한 증거는 아니며 다음 배포 후 확인한다.
