# B 고정 데이터·화면 캡처 결과

2026-10-09. 작업 워크트리: .worktrees/ux-capture, 브랜치 codex/ux-capture. 시작 커밋 174da81. 통합 대상은 원본 main이다.

## 구현

- Tests/UXSimulationFixtures.swift: demo-v1 기준 시각·고정 UUID·10월 계획·공통 종목 기록·완료 일지·진행 세트·지난 운동 초안 factory. 테스트마다 새 AppData/AppModel 사본. 현재 날짜로 만든 AppData 초기 seed는 반환 전에 교체한다.
- Tests/UXSimulationCaptureTests.swift: 계약의 고유 10개 ID별 XCTest 진입점, 기본 834×1194pt/ko_KR/Asia/Seoul, plan-date-detail accessibility3 및 workout-active 417pt 변형. 실제 제품 View를 직접 호스팅하며 성공 렌더만 keepAlways PNG와 실제 렌더 시각 metadata 첨부물로 남긴다.
- simulation/capture/manifest.json: 기본 10개 모두 pending. 실제 iOS 렌더 미실행으로 appCommit=null이며 이미지 경로·SHA를 꾸며 넣지 않았다.
- simulation/capture/collect.mjs: 실제 내보낸 PNG 매핑을 검증하고 무시된 simulation/runs/의 새 출력 폴더로 연결한다. 경로 탈출·심볼릭 링크·중복 변형·기존 출력 덮어쓰기 차단, PNG 청크/CRC/크기 검사, 바이트 기반 SHA-256 생성. 실패는 증거 error와 failed, 미실행/skip은 pending을 유지한다.
- simulation/capture/test-collect.mjs, README.md: 명시적인 합성 PNG 입력 검사와 전용 Mac 시뮬레이터·Xcode 첨부물 내보내기·manifest 연결 명령. 합성 검사 이미지를 앱 결과로 저장하지 않는다.
- App/UXSimulationPreview.swift는 필요하지 않아 만들지 않았다. 기존 AppModel/Models/테스트/project.yml/CI/HANDOFF/다른 담당 파일은 수정하지 않았다.

## 격리와 캡처 한계

previewData 모델은 파일 저장·알림·Live Activity·자동 공개를 차단한다. 계정은 client:nil/offline/monitorConnectivity:false로 생성하고 기존 DEBUG SharedStore.testingDirectory를 임시 경로로 먼저 지정한다. 계정 생성의 카탈로그 잠금 파일은 임시 경로에만 생긴다. 모델의 lazy account도 이 격리 계정으로 대입한다. bootstrap/login/Keychain/실제 서버 요청은 호출하지 않는다. 수동 일지 초안은 별도 defaultAppStorage suite와 합성 userID를 사용하고 종료 후 제거한다.

단, XCTest 시작 전에 정상 앱 호스트가 부팅한다. B 파일만으로 앱 전체 부팅을 차단할 수 없으므로 Mac 실행은 사용자 기록·계정이 전혀 없는 새 전용 시뮬레이터와 빈 Supabase 빌드 설정을 전제로 한다. 실제 사용자 기기나 기존 계정이 들어 있는 시뮬레이터에 실행하지 않는다. 캡처는 직접 View 범위이며 RootView 탭 바/고정 상태 카드 전체 탐색 증거가 아니다.

실제 Date()는 고정하지 않았다. plan-month의 오늘 강조, UIKit 시각, ManualWorkoutView의 최대 날짜/검증은 실행 날짜에 의존하며 metadata에 실제 시각을 남긴다. workout-ready는 idle 모델의 Date() 의존으로 기준 날짜(서울 2026-10-12)가 아니면 skip한다. 다음 4개는 현재 제품의 안전한 주입점이 없어 실행하더라도 skip/pending이며 가짜 이미지로 대체하지 않는다.

| ID | 실제 타입·이유 |
|---|---|
| workout-rest | WorkoutStatusBanner: TimelineView context.date와 timer 시각 주입 불가 |
| journal-calendar | WorkoutJournalView: private selectedDate=Date()의 고정 날짜 초기화 불가 |
| friends-home | 별도 친구 탭 FriendsView: private authenticated SocialModel overview 주입 불가 |
| friends-ranking | 기록의 FriendRankingView: private authenticated overview/entries 주입 불가 |

## 검증

- 성공: Node REPL에서 runTests() 실행. 합성 PNG 실제 바이트 복사/SHA, pending 10개·null commit, failed 증거, 잘못된 파일/크기/CRC/중복/ID/경로 탈출, 출력 덮어쓰기 거부 검사.
- 성공: capture-manifest.schema.json 규칙을 따라 저장된 pending manifest와 collector의 pending 결과를 검사. 고유 기본 ID 10개이며 미캡처 경로·해시 없음.
- 미실행: Windows가 합성 symlink 생성에 EPERM을 반환하여 live filesystem 심볼릭 링크 검사는 건너뜀. 경로 방어 코드 검토 및 나머지 경로 검사는 통과.
- 코드 검토: 실제 View 타입/생명주기·previewOnly 가드·AccountModel 카탈로그 잠금/오프라인 refresh 가드·ManualWorkoutView AppStorage·Date() 의존 확인.
- 미실행: Swift 컴파일, fixture/계정 격리 XCTest, 실제 iOS 렌더, 전체 iOS 빌드. Windows PATH에 Swift/XcodeGen/Node 실행기가 없음. Node 검사만 Codex 내장 REPL을 사용했으며 일반 Node CLI 설치 완료로 보고하지 않는다.
- 커밋 전 담당 파일 git diff --cached --check를 실행한다. 실제 실행 결과와 최종 커밋 SHA는 완료 응답 및 아래 Git 조회로 확인한다.

## 커밋·통합

이 결과 문서를 포함한 B 작업 커밋은 다음 명령으로 식별한다: git log -1 --format=%H -- docs/ux-simulation/results/capture.md. 작성자는 커밋 명령에만 Codex/codex@users.noreply.github.com을 적용하고 메시지에 [skip ci]를 넣는다. 담당 파일만 명시하여 커밋한다.

커밋 후 scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-capture로 통합 잠금·원본 main·추적 변경을 검사하고 로컬 통합한다. 잠금/main 변경이 있으면 강제로 삭제/reset/stash하지 않는다. 통합 시도 결과는 완료 응답을 따른다. 원격 push·Actions 실행·유료 모델 호출·배포·운영 DB 변경은 요청 범위 밖이며 수행하지 않았다.

## A에게 남기는 후속 요청

추후 승인된 제품 변경에서 clock 주입, WorkoutJournalView의 선택 날짜 initializer, AccountModel/SocialModel의 명시적인 합성 상태 초기화, 앱 호스트의 테스트 전용 부팅 격리를 검토할 것. 이 단계에서는 기존 제품 파일을 수정하지 않았다. C/D의 실제 산출물 연결 및 실제 iOS 캡처 실행은 완료로 보고하지 않는다. PNG가 없는 pending manifest로 D의 dry-run을 연결한 뒤, Mac 결과만 근거로 captured/failed 상태를 업데이트할 것.
