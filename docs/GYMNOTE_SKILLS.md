# GymNote 작업 스킬

프로젝트 원본은 `.agents/skills/`의 일곱 폴더다. 상시 규칙은 AGENTS.md, 상황별 절차는 스킬, 실행은 기존 검사·통합 도구가 담당한다. 배정표·워크플로·검사 명령은 실행 시 현재 저장소에서 확인하며 과거 경로·커밋을 스킬에 고정하지 않는다. HANDOFF 상단에 앞으로 적용할 스킬을 명시했다.

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
