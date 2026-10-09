# UX 시뮬레이션 공통 계약 v1

## 데이터 파일

simulation/contracts/의 JSON Schema 2020-12가 입력·출력 형식의 기준이다. 스키마 변경은 A만 수행한다. examples/는 실행하지 않은 합성 예시이며 실제 결과가 아니다. 모든 데이터는 UTF-8 JSON으로 저장한다. ID는 소문자 kebab-case, schemaVersion은 1이다.

| 데이터 | 파일 / 담당 |
|---|---|
| 사용자 | simulation/personas/*.json / C |
| 시나리오 | simulation/scenarios/*.json / C |
| 캡처 manifest | simulation/capture/manifest.json / B |
| 세션 | simulation/runs/<run-id>/sessions/*.json / D, 생성물은 Git 제외 |

## 고정 초기 상태

fixtureId=demo-v1, 기준 시각=2026-10-12T09:00:00+09:00, timezone=Asia/Seoul, locale=ko_KR. ID와 날짜·운동·계획·일지 값은 재실행에도 같다. 모든 진입점은 같은 기준 fixture를 새로 만들고 화면에 맞게 사본의 운동 진행 상태를 선택한다. sourceCommit은 준비 당시 코드가 아니라 실제 캡처한 코드 SHA를 appCommit으로 기록한다.

화면이 실제 Date()를 직접 사용하는 곳은 데이터 날짜 고정만으로 시간이 고정되지 않는다. B는 이를 찾아 캡처용 wrapper로 가능한 범위를 고정하고, 불가능한 부분과 실행 날짜 의존성을 보고한다. 실제 날짜를 고정했다고 거짓으로 기록하지 않는다. 화면 캡처용 주입 때문에 제품의 저장·로그인 코드를 수정하지 않는다.

## 고정 화면 ID 10개

| captureId | 화면 |
|---|---|
| workout-ready | 오늘 운동 시작 전 |
| workout-active | 운동 진행·실제 횟수 입력 |
| workout-rest | 휴식 타이머 |
| plan-month | 계획 월간 캘린더 |
| plan-date-detail | 선택 날짜 계획 상세 |
| records-overview | 기록 첫 화면 |
| journal-calendar | 운동 일지 캘린더 |
| journal-entry | 지난 운동 입력 |
| friends-home | 현재 별도 친구 탭의 관리 화면 |
| friends-ranking | 기록 탭의 친구 순위 |

기본 834×1194pt, textScale=standard. 같은 ID의 변형은 width/height/textScale 조합으로 구분한다. B는 기본 10개를 먼저 만들고 큰 글씨·분할 화면은 추가할 수 있다. 최소 한 변형에서 고유 ID 10개가 모두 있어야 한다. 이미지 relativePath는 manifest 파일 위치 기준의 상대 경로이며 .., 절대 경로, 심볼릭 링크로 입력 루트를 벗어나면 거부한다. PNG는 실제 파일 존재와 SHA-256 일치를 확인한다. 크기는 Swift 렌더 bounds의 pt 단위다.

## 평가 의미

- dry-run: 입력 검증과 실행 계획 작성만. status=not-run, outcome=not-evaluated, model=null, usage.requests=0. 이미지 없음은 누락 상태로 기록한다.
- screen-review: 화면 이해도·진입점 발견에 대한 합성 관찰만. 앱 저장·탭 이동을 실제 수행한 성공으로 간주하지 않는다. app-state 검사는 not-evaluated로 남긴다.
- scripted-native: 실제 정해진 앱 조작과 상태 검사. 페르소나가 자유롭게 탐색했다고 보고하지 않는다.
- agent-native: 후속 단계. 가상 사용자가 관찰→행동을 결정하고 실제 앱 환경이 실행한다.

시나리오의 userGoal은 사용자에게 보일 목표다. checks는 평가자 전용이고 사용자 입력에 넣지 않는다. persona·현재 화면·목표만 사용자에게 제공한다. 코드, 전체 미래 화면, 성공 검사 내용은 사용자에게 주지 않는다. planner는 캡처와 짧은 관찰·행동 기록을 보고 근거가 붙은 개선안을 만들며 사용자의 실행 중에 힌트를 주지 않는다. 내부 사고 과정 대신 짧은 관찰 메모만 수집한다.

## 성공 판정과 보고서

observation-only는 가상 관찰, app-state는 실제 상태 증거, manual은 사람 확인이 필요하다. 근거가 없거나 해당 실행 모드가 검사를 수행하지 못하면 not-evaluated. 스크린샷을 봤다는 이유만으로 저장 성공·개인정보 보호·알림 도착을 pass로 표시하지 않는다.

동일 persona/scenario를 3회 반복하더라도 실제 사용자 3명의 의견이나 실제 발생률로 해석하지 않는다. 보고서는 표본 수 대신 합성 실행 수, 미실행 수, 증거 위치, 앱·모델·프롬프트 버전을 표시한다. 모델 지연시간은 사람의 작업 소요시간과 분리한다.

## 공통 검증 도구와 캡처 보관

A의 simulation/contracts/validate.mjs는 v1 계약의 구조·참조·실행 상태를 검사한다. audit.mjs는 B/C 실제 입력과 캡처 파일 준비 상태를 점검한다. 명령과 범위는 simulation/contracts/README.md를 따른다. 사용자·시나리오·캡처가 아직 없으면 awaiting-inputs이며 평가 성공으로 표시하지 않는다.

Git에 포함되는 simulation/capture/manifest.json은 캡처 전 pending 목록일 수 있다. 실제 PNG와 생성 manifest는 simulation/runs/<capture-run>/ 아래에 함께 저장하고, 생성 manifest의 relativePath는 그 디렉터리 안의 PNG를 가리킨다. tracked manifest에서 ../runs 경로를 사용하지 않는다. 실제 실행은 생성 manifest 경로를 명시적으로 전달한다. 생성 manifest의 appCommit은 실제 캡처한 코드 SHA다.
