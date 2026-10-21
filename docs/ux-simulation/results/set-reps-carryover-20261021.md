# 세트 횟수 이어가기·세트별 상세 횟수 (2026-10-21)

## 사용자 요청

- 세트 완료 후 다음 세트 횟수가 계획 값으로 되돌아가 운동 중 불편 → 직전 세트 횟수를 이어 간다.
- 계획에서 기본은 숫자 하나, '상세 설정'을 켜면 세트별로 횟수를 정한다.

## 변경

- `Exercise.setReps: [Int]?` 추가(없으면 기존과 동일, 값이 있을 때만 저장). `detail`은 `12·10·8회`처럼 자동 생성되고 세트 수와 동기화된다. 예전 앱은 `detail`만 읽는다.
- 다음 세트 기본 횟수 규칙(`WorkoutSession.suggestedReps`): 세트별 상세 계획 값 → 직전 세트 실제 횟수 → 계획 횟수(첫 세트). 실행 탭과 위젯/Live Activity 완료(`changeSets`) 모두 같은 규칙.
- 계획 운동 설정 화면: `세트별 횟수 상세 설정` 토글, 켜면 세트마다 Stepper. 신디 설정 화면은 변경 없음.
- 완료 세트 목록의 `실제 / 계획` 표시와 수정 초기값, 지난 운동 직접 기록 가져오기가 세트별 계획을 쓴다.
- 기존 검사 `다음 세트는 계획 기준`을 새 규칙(직전 세트 이어감)으로 바꾸고 `setRepsChecks`를 추가했다.

## 검증

- 로컬(노트북 VM·클라우드)에는 Swift 컴파일러가 없어 작업 브랜치 `claude/set-reps-carryover`를 push하고 Build IPA를 수동 실행했다(main 아님, publish 건너뜀).
- 소스 `1f08967`(기준 main `b12b4f4` 병합 포함)의 [Build IPA 39546891353](https://github.com/iasanullweb-maker/GymNote/actions/runs/39546891353): checks(ios·database·account-deletion·tooling)·Release build·release-gate 모두 성공, publish 건너뜀(미배포).
- 병합 충돌: main의 신디 설정 화면 변경(`4a3e905`)과 `RoutineView` 충돌 → 신디 화면은 그대로 두고 일반 운동 분기에만 상세 횟수 UI를 넣었다.
- 실기기 확인은 다음 배포 후(TODOLIST 참고).
