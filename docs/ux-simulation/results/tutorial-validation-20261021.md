# 튜토리얼 전체 검증·화면 확인 (2026-10-21)

- 승인: 사용자가 전체 iOS 빌드·테스트·실제 화면 확인 후 문제 없으면 배포하도록 요청했다. 대상은 튜토리얼 변경이며 병행 채팅의 로컬 위젯 수정 `6e9e826`은 이번 배포 범위에 포함하지 않는다.
- 최종 검증 제품/검사 소스 `4be7d8c184c107da9bf566a558585b2f027d5094`, [Build IPA 39564868505](https://github.com/iasanullweb-maker/GymNote/actions/runs/39564868505). checks/ios·database·account-deletion·tooling, 앱/위젯 Release 빌드, release-gate 모두 성공. 검증 브랜치이므로 publish skipped.
- XCTest 181개: 177 통과·기존 캡처 4개 건너뜀·실패 0. TabCoachmarkTests 6개, 새 RootView 튜토리얼 캡처 테스트(18개 PNG) 통과. 실제 측정 카드 경계가 창 내부인지, 일반 세로 화면의 조작 대상이 강조되는지 자동 검증한다.
- 앞선 `a6fb3fc` run 39563347398은 SettingsView의 Section 제목+footer 초기화 오류로 실패해 `1e7a1bc`에서 수정했다. 그 뒤 run 39563751571은 검사·빌드 성공이었으나 실제 캡처에서 카드 잘림·강조 누락을 발견해 배포하지 않았다. `4be7d8c`에서 TabView/toolbar 경계를 넘는 환경 콜백 기반 글로벌 좌표 측정과 카드/설명 높이 직접 측정으로 고치고 같은 전체 검증을 다시 통과했다.
- 18개 실제 SwiftUI 시뮬레이터 PNG를 직접 확인했다. iPad 834×1194, iPhone 크기 393×852, 가로 852×393, 다크·Dynamic Type accessibility3, 200/700/1600ms 샘플. 일반 화면에서 시작/+ 버튼·선택 날짜·기록 전환·휴식 설정에 정확한 테두리와 카드/진행 버튼을 확인했다. 친구 게스트 화면 및 매우 큰 글자/짧은 가로 화면처럼 대상이 없거나 충분한 공간이 없으면 가짜 강조 없이 카드/진행을 유지한다. 큰 글자는 버튼을 아래 한 줄 전체로 배치한다.
- 캡처는 GitHub의 iPad Pro 11-inch(M4) 시뮬레이터에서 크기별 UIWindow로 실제 RootView를 렌더한 것이다. 독립 물리 iPhone/iPad·VoiceOver·터치 제스처·전체 프레임 동영상 확인은 아니다. 격리 합성 모델과 기본 저장소를 사용하고 RootView lifecycle만 비활성화해 알림 요청/실제 계정·파일 재로딩을 막았다. 정상 앱의 기본 lifecycle은 유지된다.
- 근거: 위 run의 iPad-test-results artifact 12329537495, manifest의 UXSimulationCaptureTests/testTutorialRootScreens. 로컬 PNG/로그는 원본 `.validation-tools/tutorial-ci/39564868505/`와 `ios-final.log`. 실제 화면 검토에서 발견한 오류를 고친 후 최종 18장 확인 완료.
- 이 기록 이후 제품·검사·CI 입력을 바꾸지 않고 문서만 추가해 배포한다. 공개 run·버전·IPA 해시·AltStore 대조는 배포 결과 문서에 후속 기록한다. 사용자 설치·실기기 확인은 미완료로 유지한다.
