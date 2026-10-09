# A 교차 검토 상태 — 2026-10-09

이 기록은 실제 모델/앱 실행 결과가 아닌 데이터와 코드 검토 스냅샷이다. 최신 상태는 audit.mjs로 다시 확인한다.

## 확인한 산출물

- A 6e5ec7b: 공통 규격 검증·준비 검사와 회귀 41개. 로컬 main 병합 0c790be.
- C f96bb13 및 완료 기록 2c7071b: 사용자 4개·시나리오 5개·프롬프트가 main에 통합됨. 공통 검증기에서도 각 문서의 형식·ID·참조가 통과했다.
- B: 검토 시 ux-capture 워크트리에서 스테이징 중인 manifest와 fixture를 읽기 전용으로 검토했다. 아직 미커밋 B 산출물은 main 통합 결과로 보고하지 않는다.
- D: 검토 시 main에 scripts/ux-sim/run.mjs와 runner 결과 문서가 없어 실행기 연결은 미검증이다.

## B/C 잠정 연결 검사

C의 실제 JSON과 B의 스테이징 중 manifest를 메모리에서 validatePanel에 전달했다. 사용자 4개·시나리오 5개·화면 10개 참조가 통과했고 조합은 20개(3회 반복하면 계획 60회)다. B manifest의 화면 10개는 모두 pending이며 appCommit=null이다. 이는 캡처·실행 성공이 아니다.

B fixture 정적 검토 결과: 첫 푸쉬업 계획은 3세트, workout-ready에 진행 중 운동이 없음, 2026-10-14 식별 가능한 계획, 수동 푸쉬업 값 15/18(편집 목표 50과 다름)이 C의 요구와 맞는다. Swift/XCTest를 실행하지 않았으므로 이 검토를 실제 앱 저장·화면 성공으로 처리하지 않는다.

## 남은 실행 환경 조건

1. TodayView·일지·타이머의 실제 Date()/TimelineView 의존성을 제어해야 날짜 고정과 휴식 상태 재현을 보장할 수 있다. 현재 B는 없는 clock 주입을 성공했다고 하지 않고 제약을 기록한다.
2. 친구 화면은 합성 로그인·SocialModel overview/ranking·합성 상대 코드 ABCD2345·공개 기록 주입이 필요하다. B의 현재 fixture에는 인증된 social 상태 주입이 없어 친구 시나리오의 app-state/manual 검사를 수행할 수 없다. 운영 로그인·DB로 이를 보완하지 않는다.
3. 실제 저장/화면 상태 관찰·편집 취소 흔적이 없으면 app-state는 not-evaluated다. C의 userGoal에 평가자 사전조건이나 클릭 정답을 알려주지 않는다.
4. B/D 완료 커밋 통합 후 실제 manifest 경로로 공통 audit와 실행기 dry-run을 연결해 검사한다. 이미지 캡처는 Mac/Xcode 또는 승인된 후속 CI에서 별도로 실행한다.

## 다음 검사

~~~powershell
node simulation/contracts/audit.mjs --require-panel
node simulation/contracts/audit.mjs --manifest simulation/runs/capture-run/manifest.json --require-captures
~~~

기본 audit는 담당 입력이 없을 때 awaiting-inputs를 명확히 표시한다. 이미지가 pending인 패널은 실행 계획 준비와 화면 평가 준비를 구분한다. 모델 요청은 0이며 전체 iOS 빌드/실제 사용자 검증은 이번 A 작업에서 미실행이다.
