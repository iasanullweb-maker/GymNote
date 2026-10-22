# 운동 시작 변신 착지·시계 앱식 휴식 타이머 (2026-10-22)

## 요청
1. 운동 시작 애니메이션에서 바 크기가 갑자기 작아져 부자연스러움 → 다시 제작.
2. 휴식 타이머를 애플 시계 앱 타이머처럼, 기존 −/+ 제거.

## 변경
- `App/GymNoteApp.swift`, `App/TodayView.swift`(WorkoutStatusBanner `onCardFrame`), `App/WorkoutStartMotion.swift`(크기 튕김 제거, 후반 내용 미리 보이기, 착지 크로스페이드 0.2초, bounce 0.08).
- `App/RestTimerPanel.swift`(신규), `App/TodayView.swift` 휴식 섹션 교체, `App/AppModel.swift` setDefaultRest, `App/SettingsView.swift` −/+ 간격 제거, `App/TabCoachmarks.swift` 문구, `DESIGN.md`.

## 검증
- 실행: 코드 검토, `git diff --check`.
- 미실행: Swift 컴파일, XCTest, 앱/위젯 Release 빌드, 화면 캡처(Windows에 Swift/Xcode 없음). 다음 묶음 검증·배포 전 CI 전체 검사로 해소.
- push·배포: 없음.
