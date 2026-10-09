# GymNote 4개 대화 병행 작업

## 현재 운영 전환 (2026-10-09)

사용자가 텔레그램 아이디어 기록·자동 실행 작업을 한 대화에서 진행하도록 요청했다. 현재 소유 범위와 경로는 ASSIGNMENTS.md의 IDEA-UNIFIED-1 및 workspaces.json의 unified 항목을 따른다. 기존 A/B/C/D 폴더·프롬프트·보고서는 보존하며 새 병행 구현을 시작하지 않는다. 통합 구현 실행은 automation/README.md를 따른다. 로컬 통합은 `scripts/parallel_work.ps1 -Mode Integrate -Unified`로 같은 UX 통합 잠금을 사용한다. 아래 문서는 이전 병행 준비 이력이다.

작성: 2026-10-09. 이 대화는 A(총괄), 나머지 세 대화는 B/C/D를 맡는다. 기본 분담은 아이디어 자동화 시스템이며, 개별 기능은 사용자가 요청한 작업과 아래 배정표로 정한다. 환경 준비가 새 기능 실행·배포 승인이라는 뜻은 아니다.

## 작업 폴더와 시작

정확한 절대 경로·브랜치는 workspaces.json, 복사할 시작 메시지는 prompts/A.md~D.md에 있다. A는 현재 대화의 폴더를 유지한다. B/C/D는 main 폴더에서 편집하지 않는다. Codex 앱 대화에서도 모든 도구의 workdir를 배정 폴더로 지정한다. 도구의 샌드박스가 해당 폴더를 허용하지 않으면 그 폴더를 프로젝트로 열거나 적절한 권한으로 접근하며 원본 main에서 대신 수정하지 않는다.

| 대화 | 담당 | 기본 소유 범위 |
|---|---|---|
| A 현재 대화 | 요구사항·배정·공통 규격·통합 | AGENTS.md, CLAUDE.md, HANDOFF.md, docs/parallel-work/**（reports/B~D 제외）, automation/contracts/**, scripts/parallel_work.ps1 |
| B | 메시지 수신·인증·중복 방지 | automation/ingress/**, reports/B.md |
| C | 에이전트 실행·작업 상태·복구 | automation/worker/**, reports/C.md |
| D | 관리자 화면·작업 조회·제어 | automation/admin/**, reports/D.md |

소유 범위는 기본값이다. 새 파일·교차 변경은 ASSIGNMENTS.md에 실제 경로를 배정한다. 이미 다른 작업이 소유한 파일은 기본 소유 범위보다 우선한다. 같은 파일을 두 대화가 수정하지 않는다. automation/contracts/TASKS.md의 규격을 먼저 읽는다. B는 작업 입력, C는 실행 상태, D는 상태 조회·제어를 사용한다. 각 영역의 테스트·의존성 파일도 본인 디렉터리 안에 둔다. 공용 package.json이나 CI 변경은 A에게 요청한다. 기존 App/·Shared/·Supabase 코드는 이번 환경 준비에서 수정하지 않는다.

기존 UX 시뮬레이션의 워크트리·규격·소유 파일은 보존한다. simulation/**, docs/ux-simulation/**, scripts/ux_simulation_*.ps1, UXSimulation*.swift는 이 4개 대화의 자동 작업 범위가 아니다.

## 환경 명령

PowerShell에서 본인의 폴더를 사용한다. 스크립트는 외부 다운로드·로그인·API 호출·원격 push를 하지 않는다.

~~~powershell
# 생성된 4개 폴더·브랜치·공통 Git 저장소·프롬프트 확인
powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Status
# 이미 구성된 환경에도 안전하게 재실행 가능. 기존 폴더를 덮어쓰지 않음.
powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Setup
# 본인 역할의 CLI 시작. 경로만 설정하고 실제 작업 프롬프트는 화면에 출력.
powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Start -Role B -Client codex
# Claude Code가 설치·인증된 환경에서
powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Start -Role C -Client claude
~~~

CLI가 없으면 설치되지 않았다고 보고하고 위 prompts 파일을 앱 대화에 붙여 넣는다. 새 계정의 CODEX_HOME 분리·인증은 docs/CODEX_CLI_HANDOFF.md를 따른다. 환경 스크립트는 계정 상태·전역 설정·모델 설정을 변경하지 않는다. Windows에서 전체 iOS 빌드는 기존 macOS CI나 Mac/Xcode가 필요하며, 이번 환경 구성에서는 실행하지 않는다.

## 시작·작업·보고

1. 실제 cwd, 브랜치, git status, git worktree list와 AGENTS.md, HANDOFF.md, 이 문서, ASSIGNMENTS.md를 읽는다.
2. 요청된 작업이 없으면 코드 구조와 담당 영역을 파악하고 준비 상태를 알린다. 백로그를 임의로 모두 구현하지 않는다.
3. 최신 main과의 차이를 확인한다. 깨끗한 본인 워크트리에서 필요할 때 main을 병합한다. 작업 중인 파일을 reset·stash로 치우지 않는다.
4. 본인 담당 파일만 수정·검토·필요한 검사 후 명시적 경로로 stage·커밋한다. git add . / -A는 사용하지 않는다. Git 작성자 설정이 없으면 저장소 기존 Codex 정보는 해당 커밋의 git -c 옵션으로만 적용한다. Claude는 유효한 기존 작성자 설정을 존중한다.
5. reports/B.md 등 본인 보고서에 변경·검증/미실행·의존성·남은 요청을 기록한다. 커밋 해시는 최종 응답에서 제공한다. HANDOFF.md와 배정표는 A가 관리한다.
6. AGENTS.md의 자동 통합 요청대로 아래 스크립트를 실행한다. 통합 실패는 완료로 보고하지 않는다.

각 대화의 보고서는 Git 커밋 후 다른 대화에서 git show <branch>:docs/parallel-work/reports/<역할>.md로 읽을 수 있다. 본인 워크트리의 파일은 다른 워크트리에 자동 복사되지 않는다. main 통합 뒤 필요할 때 갱신한다. 이 파일 공유는 채팅 메시지 자동 전달이나 카카오톡 자동 실행을 구현한 것이 아니다. 기존 대화에 메시지를 보내려면 사용자의 명시적 지시가 필요하다.

## 한 번에 하나씩 로컬 통합

~~~powershell
powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Integrate -Role B
~~~

스크립트는 본인 경로·브랜치·깨끗한 상태, 공통 저장소, main 브랜치·진행 중 병합·추적 파일 미커밋 변경을 확인한다. UX 시뮬레이션과 동일한 .validation-tools/ux-integration.lock 잠금을 사용하므로 두 체계도 동시에 main에 병합하지 않는다. 잠금이 바쁘면 잠시 후 재시도하고 다른 작업을 계속한다. 오래된 잠금도 실행 중인 소유자가 없다는 확인 없이 삭제하지 않는다. 스크립트 없이 main을 변경하는 다른 대화에는 이 잠금 규칙을 먼저 전달해야 한다.

main에 다른 추적 파일 미커밋 변경이 있으면 보존하고 해당 변경의 커밋 후 통합을 이어간다. 미추적 파일은 보존하며 충돌 경로는 Git이 병합을 거부한다. 충돌은 실제 내용을 검토해 해결한다. 본인 스크립트가 만든 병합 충돌은 해당 대화가 우선 해결하고 진행 중 병합이 끝나기 전 다른 통합을 시작하지 않는다. 강제 push/reset/임의 stash는 사용하지 않는다.

관련 검사 결과를 먼저 검토하고 통합한다. 작은 UI 수정은 가벼운 검사, 로그인·권한·저장 변경은 즉시 필요한 검사를 수행한다. 전체 iOS 검사·빌드는 변경을 모아 통합 검증 또는 배포 직전에 실행한다. 원격 push·Actions 실행·배포·운영 SQL 변경은 각 요청의 승인 범위를 따른다.

## 관련 자료

- [워크트리 공식 안내](https://learn.chatgpt.com/docs/environments/git-worktrees)
- [Codex CLI 옵션](https://learn.chatgpt.com/docs/cli/reference)
- [Claude Code 프로그램 연동](https://code.claude.com/docs/en/headless)
