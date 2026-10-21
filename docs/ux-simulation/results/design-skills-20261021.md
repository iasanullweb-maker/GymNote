# 디자인 스킬·DESIGN.md·iPhone/다크 화면 캡처 (2026-10-21, Claude)

## 요청

사용자 요청: Emil Kowalski 디자인 스킬, Impeccable, Taste 스킬, Figma MCP, Playwright를 조사한 뒤 GymNote 적용안 1~3번을 바로 진행.

1. Impeccable 설치 → PRODUCT.md·DESIGN.md 작성 (Codex와 공유)
2. Emil 스킬은 애니메이션·다듬기 작업용으로 설치
3. Playwright 대신 시뮬레이터 화면 캡처 CI 확장

Taste 스킬·Figma MCP는 사용자와 합의해 보류했다.

## 변경

- `.claude/skills/`(Claude Code)와 `.agents/skills/`(Codex)에 외부 스킬 설치. 출처와 바이트 동일(LICENSE 추가만), 공백 검사는 `.gitattributes`에서 해당 경로만 제외.
  - impeccable: [pbakaus/impeccable](https://github.com/pbakaus/impeccable) `dad8dbb3aac21ad1fa236c110315ef4abece23e8`, Apache-2.0. 실행 파일은 저장소에 없고 첫 실행 때 `~/.impeccable/`에 내려받는다.
  - emil-design-eng, apple-design, write-swift, review-animations, find-animation-opportunities, improve-animations, break-ui: [emilkowalski/skills](https://github.com/emilkowalski/skills) `2d228630ba1446365f614a108cb8252f1feda202`, MIT. 웹·React Native·Sonner 전용 7개(animate, animate-expo, mobile-native, ask-sonner, pick-ui-library, prototype, animation-performance)는 제외.
- `PRODUCT.md`: impeccable init. 사용자 답변(2026-10-21): 나중에 일반 공개 목표, 아이패드 거치·아이폰 손에 들고 둘 다, 애플 기본 스타일 유지·크고 누르기 쉬운 버튼.
- `DESIGN.md` + `.impeccable/design.json`: impeccable document(scan). 기존 SwiftUI 코드에서 시스템 색(운동 주황·일상 청록·완료 초록·오류 빨강), 텍스트 스타일, 모서리 8~28pt, 상태 카드 머티리얼·그림자, 52~56pt 운동 버튼을 추출. 콘셉트(Creative North Star)는 사용자 선택 "기록을 깨는 코치".
- `AGENTS.md`: 화면 작업 전에 PRODUCT.md·DESIGN.md를 읽는 규칙. `docs/GYMNOTE_SKILLS.md`: 외부 디자인 스킬 표와 사용 원칙.
- `App/WorkoutJournalView.swift`: `init(initialDate: Date = Date())` 추가. 제품 동작은 그대로(기본값 오늘)이며 캡처 테스트만 고정 날짜를 넣는다.
- `Tests/UXSimulationCaptureTests.swift`·`UXSimulationFixtures.swift`: journal-calendar 건너뜀 해소(고정 일지 날짜 2026-10-08), iPhone 393×852 변형 6개, 다크 모드 변형 3개(`--dark` 접미사, `appearance` 메타데이터). `simulation/capture/README.md`·`manifest.json`의 journal-calendar 제약 문구 갱신.

## 검증

- 기준 main `025587b`, 검증 소스 `f2c8d36682baa35351455a339b5e072a1b0f5b40`(기존 main 병합 포함).
- 검증 브랜치 `codex/design-skills-20261021` → [Build IPA 39537037520](https://github.com/iasanullweb-maker/GymNote/actions/runs/39537037520): checks/ios(iPad XCTest·Swift 회귀)·database·account-deletion·tooling·앱/위젯 Release build·release-gate 성공, publish는 main 아님으로 건너뜀. main push·배포 없음.
- 캡처 산출물 `iPad-test-results`에서 UXSimulationCaptureTests PNG 17장 확인(기존 8 + 신규 9: journal-calendar iPad, iPhone 6, 다크 3). 캡처 테스트는 빈 화면·렌더 실패 시 XCTFail이므로 job 성공은 17장 모두 렌더됐음을 뜻한다. 이미지를 직접 열어 iPhone·다크·일지 캘린더 화면을 눈으로 확인했다.
- 로컬(노트북 VM, Node 22): `simulation/capture/test-collect.mjs`, `contracts/test_validate.mjs`, `contracts/audit.mjs --require-panel`, `scenarios/tests/validate.mjs`, runner 테스트 56개, `ux-sim/run.mjs --validate-only` 통과. `git diff --check` 통과.
- impeccable `context`가 PRODUCT.md·DESIGN.md·platform=ios를 인식, `doctor` "No drift found".

## 캡처에서 본 것

- iPhone 폭에서 실행·계획·기록·일지·지난 운동 기록 화면이 잘리지 않고 compact 레이아웃으로 보인다. 다크 모드에서도 주황 버튼·글자 대비가 유지된다.
- **확인 필요:** journal-calendar 캡처에서 달력은 10월 8일이 선택됐는데 아래 목록 머리글이 "2026년 10월 7일 (수)"로 보였다(항목 자체 날짜는 10월 8일). 머리글은 `selectedDate.formatted(...)`로 시스템 시간대를 쓰고, 테스트는 서울 시간대를 주입하지만 시뮬레이터 기본 시간대는 UTC라 생긴 캡처 환경 차이일 가능성이 높다. 한국 시간대 실기기에서 같은 증상이 없는지 확인한다.
- `plan-month`·`journal-calendar`의 오늘 강조(21일)는 실제 실행 날짜를 따른다(기존 제약).

## 미실행·제약

- Windows/VM에 Swift가 없어 로컬 Swift 컴파일은 하지 않았고 CI로 대신했다.
- CI 아티팩트·로그 다운로드 경로(blob.core.windows.net)가 작업 환경 네트워크 정책으로 막혀, 이미지는 노트북의 내장 브라우저에서 아티팩트를 열어 확인했다. 다음 대화도 같은 방법이 필요할 수 있다.
- 실기기 화면 확인 없음. 디자인 변경 자체는 없다(문서·스킬·캡처 테스트).
