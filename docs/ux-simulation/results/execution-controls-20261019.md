# 실행 화면 시작 상태 바·횟수 조절 가독성 (2026-10-19)

## 변경

- 사용자 요청: 실행 탭에서 운동 시작을 누른 바가 운동 중 표시로 바뀌고, 세트 완료 양쪽의 −/+가 잘 보이도록 변경.
- 대상: `App/TodayView.swift`만 제품 변경. 기존 main 기준 `f455e86852f4281e9a0255cb640cdb3d92f4f793`, 구현·검증 소스 `9dd632f`. 작업 브랜치 `codex/execution-controls-20261019`, 워크트리 `.worktrees/execution-controls`, 통합 대상은 시작 당시 `main`.
- 시작 바: 전체 너비·최소 높이 52pt, 주황 바탕·검정 글씨. 실제 `activeWorkout`이 생기면 같은 위치·최소 높이의 운동 아이콘/‘운동 중’ 상태 바로 전환한다. 진행 상태는 기존 모델을 관찰하며 별도의 시작 상태를 저장하지 않는다. 종료하면 기존 저장 여부에 따라 ‘새 운동 시작’으로 돌아온다.
- 횟수 조절: −/+를 가운데 완료 버튼에서 8pt 간격으로 분리, 각각 52×56pt 터치 영역과 굵은 24pt 아이콘·주황 테두리·옅은 배경 적용. 중앙 완료 버튼은 주황 배경·검정 글씨로 표시하며 긴 문구·큰 글자에는 줄바꿈/세로 확장을 허용한다. 장식 테두리는 터치를 받지 않는다.
- 시작 전, 미등록 종목, 0회/9999회 경계, 완료 종목·측정 종목의 기존 동작과 VoiceOver 조절 이름을 유지한다. 운동 시작/세트 완료/되돌리기/자동 저장 함수와 저장 모델은 수정하지 않았다.

## 검증과 한계

- Windows 번들 Python 3.12.14와 원본 `.validation-tools/swift-parser`의 tree-sitter 0.26.0 / tree-sitter-swift 0.7.4로 `9dd632f`의 `App/TodayView.swift`를 파싱: ERROR·missing 노드 0. Swift 컴파일이나 SwiftUI 레이아웃 검증은 아니다.
- `git diff --check f455e86..9dd632f` 통과. 본인 diff 검토: activeWorkout 기반 표시, 원래 종목 등록/휴식일 시작 제한, ±1 및 0...9999 범위, 완료 후 조절 숨김, 시작 전 비활성, 가운데만 완료 실행, 각 버튼 별도 터치·접근성 라벨을 확인했다.
- 제품 변경 범위는 TodayView 하나이며 계정·위젯·동기화·저장·테스트·CI 입력은 동일하다. 새 테스트는 단순 표시 구현을 반복하는 검사로 추가하지 않았다.
- Windows에 Swift/Xcode가 없어 XCTest·전체 iOS 검사·앱/위젯 Release 빌드·네이티브 화면 캡처/실기기 터치를 실행하지 않았다. 작은 UI 변경의 검사 유예 규칙을 적용하며, TODOLIST에 기술 검증 대기를 남긴다. 다음 묶음 통합 검증 또는 배포 전에 통합 제품 코드의 전체 iOS 검증·Release 빌드로 해소한다.
- 실사용 확인: 새 앱 배포 후 시작→운동 중→종료→새 운동 시작 전환, 재실행/탭 왕복의 상태 유지, 밝은/어두운 화면·작은 화면·큰 글자에서 −/+와 완료 버튼 분리·가독성, 0/9999 경계와 완료/되돌리기를 확인해야 한다. 현재 설치된 0.1.113에는 이 변경이 없다.
- 로컬 통합은 공통 잠금 안에서 기준 HEAD·추적 파일 상태·진행 중 Git 작업·fast-forward 조건을 재확인하여 수행한다. 최종 문서 커밋·통합 결과는 완료 응답에 제공한다. 원격 push·CI 실행·배포·운영 변경은 하지 않는다.

## 후속 전체 검증·배포 시도

- 사용자 배포 승인 후 `7a3acab1732c998dec544f3a1a2422a9a0c83e7f`를 `codex/execution-controls-20261019`에 push하고 workflow_dispatch로 [Build IPA #114 / 39193930660](https://github.com/iasanullweb-maker/GymNote/actions/runs/39193930660)를 실행했다.
- `checks / ios`, `checks / database`, `checks / account-deletion`, `checks / tooling`, `build`, `release-gate` 모두 success. publish는 main 아닌 검증 브랜치여서 skipped. 구현 당시 전체 iOS 검사/Release 빌드 대기는 해소했으나 네이티브 화면의 사용자 확인은 별도다.
- 이후 검증한 같은 SHA의 main 일반 push를 실행 요청했지만 자동 승인 검토가 제한 시간 내 끝나지 않아 프로세스 생성 전에 거절됐다. 도구가 허용한 한 차례 재시도도 같은 사유로 거절됐다. 실행이 위험하다고 판정한 결과는 아니다.
- main push·정식 workflow_dispatch·릴리스·AltStore 소스 갱신은 미실행이다. 마지막 확인한 원격 main은 `ee37d269c40d0a4d4e2d78aadd4e2ee96d77a8d3`. 재개 시 원격/로컬 상태·공개 릴리스를 재조회하고 main push 실행 권한을 확보한다. 검증용 #114 IPA를 정식 배포 완료로 안내하지 않는다.
- 이 후속 기록은 문서 변경만이며 제품·테스트·설정·서버·빌드/CI 입력은 검증 SHA와 같다. 정식 배포가 가능해지면 고정 SHA와 승인 범위를 다시 확인하고 정식 run의 게이트·IPA 버전/크기/해시·릴리스·AltStore source.json을 대조한다.
