# GymNote 작업 스킬

프로젝트 원본은 `.agents/skills/`의 일곱 gymnote-* 폴더다(외부 디자인 스킬은 아래 [외부 디자인 스킬](#외부-디자인-스킬) 참고). 상시 규칙은 AGENTS.md, 상황별 절차는 스킬, 실행은 기존 검사·통합 도구가 담당한다. 배정표·워크플로·검사 명령은 실행 시 현재 저장소에서 확인하며 과거 경로·커밋을 스킬에 고정하지 않는다. HANDOFF 상단에 앞으로 적용할 스킬을 명시했다.

| 스킬 | 사용 예 |
|---|---|
| gymnote-task | `$gymnote-task로 운동 화면 변경을 구현하고 검증·커밋·로컬 통합까지 진행해줘.` |
| gymnote-verify | `$gymnote-verify로 이번 계정 저장 변경의 회귀 검사를 실행해줘.` |
| gymnote-ux-check | `$gymnote-ux-check로 계획 편집 저장·취소와 탭 복귀 흐름을 확인해줘.` |
| gymnote-debug | `$gymnote-debug로 앱 실행 오류를 조사하고 원인과 재현 근거를 알려줘.` |
| gymnote-data-change | `$gymnote-data-change로 계정 저장 변경을 구현하고 권한·기록 보존을 검증해줘.` |
| gymnote-release | `$gymnote-release로 이번 변경의 배포 준비 상태와 대상 커밋을 확인해줘.` |
| gymnote-handoff | `$gymnote-handoff로 이번 결과와 남은 작업을 담당 보고서에 기록해줘.` |

작업 시작·마무리는 task, 검사는 verify, 결과 기록은 handoff를 사용하고 전문 스킬은 관련 작업에만 추가한다. 단순 질문에는 Git 변경을 만들지 않는다. 현재 목록에 없는 스킬도 `.agents/skills/<이름>/SKILL.md`를 직접 읽어 사용할 수 있다.

일반 자동 선택을 허용한다. 직접 호출하면 의도를 명확히 전달할 수 있다. 현재 대화에 이미 로드된 스킬 목록은 설치 후 즉시 갱신되지 않을 수 있으므로 새 대화에서 호출한다. 스킬 파일을 명시해서 읽도록 요청하는 방법도 있다.

## 배치와 공유

Codex 프로젝트 스킬 원본은 `.agents/skills/`에서 관리한다. 개인 설치 시 각 스킬 폴더 전체를 사용자 Codex skills 디렉터리에 복사하고 이미 다른 내용이 있으면 덮어쓰기 전에 비교한다. 개인 사본 업데이트도 원본과 비교한다. 개인 설치본은 현재 작업 디렉터리에서 GymNote 루트를 찾으므로 다른 워크트리에도 적용할 수 있다.

Claude Code와 공유하려면 스킬 폴더 전체를 해당 프로젝트 `.claude/skills/` 또는 사용자 `~/.claude/skills/`에 배치한다. `agents/openai.yaml`은 Codex UI 메타데이터이며 본문 절차는 특정 에이전트에 종속되지 않는다. Claude의 도구·권한과 적용 CLAUDE.md도 따른다. Claude 등록·호출 성공은 실제 확인 전 완료로 보고하지 않는다.

배치 기준: [Codex 스킬 문서](https://learn.chatgpt.com/docs/build-skills), [Claude Code 스킬 문서](https://code.claude.com/docs/en/skills). Codex는 `$gymnote-task`, Claude Code는 `/gymnote-task`처럼 호출한다.

배포 스킬은 준비·실행·확인을 구분한다. 원격 push·Actions·배포·운영 DB·외부 메시지·유료 실행 권한은 현재 요청에서 확인하며 스킬 설치로 추가되지 않는다. 운영 서버 적용과 앱 배포도 별도로 확인한다.

## 작성 검증 범위

전체 재검증과 수정 근거는 [일곱 스킬 검증 결과](GYMNOTE_SKILLS_VALIDATION.md)에 기록했다. 형식 검사 외에 독립 시나리오 검토와 관련 명령의 로컬 실행을 확인했으며, 실제 운영 배포·iPad 동작 검증과는 구분한다.

skill-creator의 quick_validate.py로 각 SKILL.md의 이름·frontmatter를 검사하고 UI YAML, 내부 참조와 저장소 경로를 확인한다. 작은 문서·스킬 변경이므로 앱 코드 변경, 전체 iOS 빌드·XCTest, 원격 실행·배포를 요구하지 않는다. 구조 검사는 실제 사용 시 판단 품질을 보장하지 않으므로 첫 작업 결과를 보고 필요한 부분만 개선한다.

2026-10-09 작성 검사: 처음 세 스킬에 이어 배포·오류 조사·데이터 변경·인수인계 네 스킬을 추가했다. 일곱 스킬의 공식 구조 검사, UI YAML·호출 이름·자동 선택 설정, 내부 링크·검사 경로, HANDOFF 적용 표 확인을 통과했다. 개인 Codex 설치/갱신 후 원본과 파일별 SHA-256 일치를 확인했다. 앱 코드·전체 iOS 빌드·XCTest·원격 push·배포·운영 DB·Claude 설치/호출은 수행하지 않았다. 최종 커밋·로컬 통합 결과는 작업 완료 응답에 기록한다.

## 외부 디자인 스킬

2026-10-21 추가. 화면 디자인 판단을 돕는 외부 스킬이며 gymnote-* 일곱 스킬의 검증 범위와 별개다. 같은 내용을 Claude Code용 `.claude/skills/`와 Codex용 `.agents/skills/`에 둔다. 디자인 기준 문서는 저장소 루트의 `PRODUCT.md`(제품·사용자)와 `DESIGN.md`(색·글자·모양·컴포넌트 규칙), `.impeccable/design.json`(보조 메타데이터)이다.

| 스킬 | 출처 | 언제 쓰나 | 호출 예 |
|---|---|---|---|
| impeccable | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) `dad8dbb`, Apache-2.0 | 새 화면 설계(shape), 디자인 리뷰(critique), 접근성·기술 점검(audit, 네이티브용 audit.native), 아이폰/아이패드 적응(adapt), 출시 전 마무리(polish) | `/impeccable critique 실행 탭`, `$impeccable shape 친구 탭` |
| emil-design-eng | [emilkowalski/skills](https://github.com/emilkowalski/skills) `2d22863`, MIT | UI 다듬기·애니메이션 결정의 기본 철학 | `/emil-design-eng` |
| apple-design | 같은 저장소 | 스프링·제스처·시트·머티리얼 같은 애플식 동작 원칙(웹 예시는 SwiftUI로 옮겨 적용) | `/apple-design` |
| review-animations | 같은 저장소 | 애니메이션 변경 리뷰(직접 호출 전용) | `/review-animations` |
| find-animation-opportunities | 같은 저장소 | 애니메이션을 넣을 곳/넣지 말 곳 찾기(읽기 전용) | `/find-animation-opportunities` |
| improve-animations | 같은 저장소 | 전체 모션 점검과 개선 계획(읽기 전용) | `/improve-animations` |
| break-ui | 같은 저장소 | 긴 이름·0개·큰 숫자 같은 최악의 데이터로 화면 깨짐 찾기 | `/break-ui 기록 탭` |
| write-swift | 같은 저장소 | 최신 Swift 작성·동시성 오류·성능 문제 | `/write-swift` |

사용 원칙:

- 앱은 SwiftUI 네이티브다. 스킬의 CSS·웹 예시는 원칙만 가져와 SwiftUI로 옮기고, `DESIGN.md`의 규칙(시스템 색, Dynamic Type, 큰 버튼)이 우선한다.
- impeccable은 처음 실행할 때 `.claude/skills/impeccable/scripts/impeccable context`(Windows는 `impeccable.cmd`)가 실행 파일을 사용자 홈 `~/.impeccable/`에 한 번 내려받는다. 저장소에는 실행 파일을 넣지 않는다. 내려받기가 막히면 PRODUCT.md·DESIGN.md를 직접 읽고 진행한다.
- impeccable의 live·generate 명령과 `detect`는 웹 페이지용이라 이 앱에는 쓰지 않는다.
- 화면 확인은 브라우저가 아니라 CI의 시뮬레이터 캡처(`Tests/UXSimulationCaptureTests.swift`, Build IPA/Validate run의 `iPad-test-results` 아티팩트 `build/test-attachments`)로 한다. iPad 834×1194, iPhone 393×852, 다크 모드 변형이 있다.
- 스킬 갱신 시 출처 저장소의 해당 폴더 전체를 두 위치에 다시 복사하고, 출처 커밋을 이 표에 갱신한다.
