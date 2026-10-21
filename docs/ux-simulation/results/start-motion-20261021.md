# 운동 시작 애니메이션: 버튼이 운동 중 바로 변신 (2026-10-21, Claude)

## 요청

사용자: 운동 시작을 누르면 화면 아래 '운동 중(시간)' 바가 갑자기 튀어나와 개연성이 없다. B(버튼이 바로 변신)로 가고, 직접 보고 A(아래에서 올라오기)로 바꿀 수 있게.

## 원인

`model.startWorkout()`이 애니메이션 없이 호출되고 `WorkoutStatusBanner`에 전환이 없어 바와 목록 아래 여백이 한 프레임에 생겼다. 위쪽 시작 버튼도 즉시 '운동 중'으로 바뀌어, 누른 곳(위)과 변화(아래)가 이어지지 않았다.

## 구현

- `App/WorkoutStartMotion.swift`: 방식 설정 `WorkoutStartAnimationStyle`(morph=B 기본, rise=A, AppStorage `workoutStartAnimationStyle`), 상태 `WorkoutStartMotion`(idle → waitingForBar → flying → idle), 날아가는 판 `WorkoutStartFlight`(Animatable, 모서리 12→28·주황→머티리얼·버튼 글자 페이드·그림자 생김), 눌림 `PressScaleButtonStyle`(97%).
- 순서: 누름(97%·중간 진동) → 버튼 글자 '운동 중'으로 페이드 → B: 시작 버튼 global frame에서 실행 탭 바 frame으로 판이 스프링(0.5초, bounce 0.12) 이동 후 진짜 바와 교대 / A: 바가 아래에서 스프링(0.45초, bounce 0.18)으로 올라옴 → 두 방식 모두 바 테두리 한 번 반짝임. 목록 아래 여백도 같은 스프링으로 늘어남.
- 끝내기·시작 취소: 아래로 더 빠르게(0.3초, 튕김 없음) 내려감.
- 동작 줄이기: 이동·눌림·반짝임 없이 페이드만.
- 바 위치가 0.8초 안에 안 오면 판을 거두고 바를 바로 보임. 버튼 위치를 모르면 A처럼 처리. 위젯·Siri 등 버튼 밖에서 시작하면 애니메이션 없음(기존과 같음).
- 설정 → 화면 → '운동 시작 애니메이션'에서 기기별로 선택.
- 시작·바는 목록 셀(UIKit 호스팅)과 탭 safeAreaInset이라 이름 붙인 좌표계 대신 global 좌표를 쓰고, RootView `mainTabs` 맨 위 overlay에서 overlay의 global 원점을 빼서 그린다.

## 검증

- 단위: `Tests/WorkoutStartMotionTests.swift`(기본값, 버튼 위치 없음, 변신 흐름·반짝임 1회, 무시·취소, 바 위치 미도착 대비).
- 렌더: `DisplayTests.testWorkoutStartFlightRendersButtonToBarStages`(시작·중간·도착) — CI 캡처로 판 모양 확인.
- 기준 main `6ede94e`. 1차 소스 `00bfbec`의 run 39545880848은 단위 테스트 1개 실패(화면 없는 테스트에서 withAnimation 완료가 즉시 와 flying 상태를 건너뜀 — 앱 동작 문제 아님). 테스트만 고친 최종 소스 `999d88a`의 [Build IPA 39546432147](https://github.com/iasanullweb-maker/GymNote/actions/runs/39546432147): iPad XCTest·Swift 회귀·DB·계정 삭제·tooling·앱/위젯 Release·release-gate 성공, publish 건너뜀.
- 통합 직전 main `b12b4f4`(신디 운동 설정 `App/RoutineView.swift` 포함)를 병합한 소스 `beeff54`로 [Build IPA 39547230881](https://github.com/iasanullweb-maker/GymNote/actions/runs/39547230881) 재실행: 전체 검사·Release·release-gate 성공(publish 건너뜀). 이 run은 신디 설정 변경도 포함한 결과다.
- 판 캡처 3장(시작·중간·도착)을 직접 열어 시작=주황 버튼과 같은 모양·글자, 중간=주황이 반쯤 빠지며 커짐, 도착=반투명 둥근 바 모양·주황 테두리임을 확인했다. 기존 workout-active 캡처(TodayView, 환경 없이 렌더)도 통과.
- 미실행: 실제 움직임(속도·튕김·교대 순간의 깜빡임, 목록 스크롤 중 시작, 가로 iPad, iPhone)은 시뮬레이터 캡처로 확인할 수 없어 실기기 확인 대기.
