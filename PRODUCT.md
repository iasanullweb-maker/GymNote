# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

- 지금은 만든 사람 본인과 친구들이 쓰지만, **나중에 일반 공개를 목표**로 한다. 처음 설치한 사람도 설명 없이 오늘 운동을 시작하고 기록할 수 있어야 한다.
- 맨몸·웨이트 운동(푸쉬업, 풀업, 신디 같은 고정 종목 포함)을 루틴으로 반복하는 사람.
- 사용 장면 두 가지 모두 실제로 쓴다.
  - **아이패드를 세워 두고** 운동하면서 멀리서 본다 (기숙사·헬스장 거치).
  - **아이폰을 손에 들고** 세트 사이에 빠르게 조작한다.

## Product Purpose

짜 둔 루틴에서 오늘 할 운동을 보여 주고, 세트를 체크하고, 세트 사이 휴식 시간을 재고, 실제 횟수를 일지와 최고 기록으로 남긴다. 성공은 "운동하는 동안 앱 때문에 멈추지 않는 것"과 "지난번보다 나아졌는지 바로 아는 것"이다.

## Positioning

운동 중 손이 바쁜 상황을 위해 만든 개인 기록 앱이다. 앱을 열지 않아도 홈·잠금 화면 위젯, Live Activity 휴식 타이머, Siri("헬스노트 휴식 시작")로 같은 동작을 할 수 있고, 친구·그룹과 공통 종목 최고 기록을 겨룬다.

## Operating Context

- 탭: 실행(오늘 운동) · 계획(캘린더 루틴) · 기록(최고 기록·일지) · 친구 · 설정.
- 운동 / 일상(할 일·습관) 두 작업 공간을 상단 전환 버튼으로 오간다.
- 위젯(중·대·특대, 잠금 화면), Live Activity, 단축어/Siri가 앱 밖 진입점이다.
- 배포는 AltStore 사이드로드(무료 Apple ID)와 GitHub Actions 빌드. Mac·Xcode 없이 개발한다.

## Capabilities and Constraints

- SwiftUI 네이티브, iOS 17+, iPad·iPhone 공용 앱 하나(`TARGETED_DEVICE_FAMILY 1,2`). 폭 600pt 미만은 `gymnoteCompactLayout`.
- 앱과 위젯이 App Group 저장소를 공유한다.
- 계정: 이메일 인증번호·Google 로그인(Supabase). 로그인 전에도 게스트로 운동 기능을 쓴다. Apple 로그인은 유료 개발자 계정이 없어 비활성.
- 화면 확인은 GitHub Actions의 iPad 시뮬레이터 캡처(`Tests/UXSimulationCaptureTests.swift`)와 사용자의 실기기 확인으로 한다.

## Brand Commitments

- 이름: 헬스노트 (GymNote).
- iOS 기본 스타일(시스템 컨트롤·목록·탭 바·SF Symbols)을 유지한다.
- 운동 중에도 누르기 쉬운 **크고 넉넉한 버튼**을 유지한다.

## Evidence on Hand

- 앱 아이콘: `docs/icon.png`, `App/Assets.xcassets/AppIcon.appiconset`.
- 실제 사용자 후기·사용자 수·벤치마크는 없다. 만들어 내지 않는다.

## Product Principles

1. 운동 흐름을 끊지 않는다. 세트 완료·휴식 시작은 한 번의 탭으로 끝난다.
2. 기록이 동기가 된다. 최고 기록을 깨거나 루틴을 끝낸 순간은 분명하게 알려 준다.
3. 처음 보는 사람도 이해할 수 있어야 한다(일반 공개 목표). 내부 용어 대신 쉬운 한국어를 쓴다.
4. 저장 실패는 숨기지 않는다. 입력한 내용은 남기고 다시 시도할 수 있게 한다.

## Accessibility & Inclusion

- 멀리서 보는 아이패드와 땀 난 손의 아이폰 모두에서 읽히고 눌려야 한다. 터치 영역은 44×44pt 이상, 운동 중 핵심 버튼은 52pt 이상을 유지한다.
