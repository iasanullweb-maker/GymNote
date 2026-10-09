# 텔레그램 자동화 세 세션 시작

2026-10-09 사용자 요청. 자동화 구현은 이미 로컬 main에 통합됐다. 새 세션은 기존 기능 검토·검증과 발견한 문제 수정, 실제 연결 준비를 담당한다. 봇 생성부터 실제 실행까지 HANDOFF.md의 1~6번은 아직 미완료이며 검증 결과 없이 체크하지 않는다.

| 세션 | 역할·워크트리 | 소유 파일 | 바로 시작할 작업 |
|---|---|---|---|
| B | 텔레그램 연결 · .worktrees/automation-ingress | automation/ingress/**, docs/parallel-work/reports/B.md | 허용 user/chat·중복 방지·메모/실행 구분·상태 알림 경로 검토 및 합성 검증, 연결 단계 1~4의 준비/문제 진단 |
| C | Codex 실행 · .worktrees/automation-worker | automation/worker/**, docs/parallel-work/reports/C.md | 격리 Git·가짜 에이전트로 큐/취소/재시작/검토/로컬 통합 검증, 단계 5~6 준비 |
| D | 관리자 화면·운영 검증 · .worktrees/automation-admin | automation/admin/**, docs/parallel-work/reports/D.md | localhost 관리자 인증·메모/실행 요청·상태/이력/중지 흐름 검증, 설정 절차·회복 절차의 불일치 보고 |

원본 경로: C:/Users/Donghyun/Documents/2026_IASA/GymNote. 각 브랜치·절대 경로는 workspaces.json, 시작 문서는 prompts/B.md·C.md·D.md다. 세션마다 해당 폴더를 프로젝트로 열고 자기 시작 문서를 읽도록 요청한다. main에서 읽기 시작했다면 모든 편집/검사를 배정 워크트리로 옮긴다. 깨끗한 본인 워크트리만 최신 main으로 갱신하고, 다른 변경을 reset/stash하지 않는다.

공통 파일 automation/service.py·store.py·check.py·README.md·config.example.json·contracts/**·공용 테스트·HANDOFF.md·배정표·스크립트는 세 세션이 동시에 수정하지 않는다. 필요한 교차 변경은 자기 보고서에 경로·문제·제안 패치를 남기고 공통 담당에 배정을 요청한다. 기존 App/Shared/supabase/simulation 영역은 범위 밖이다. Claude 어댑터·새 기능 전체 구현은 이번 검증 범위에 포함하지 않는다.

실제 봇 설정은 B에서 한 번만 안내·진행한다. 토큰은 로컬 환경변수에만 두고 Git/채팅/로그에 쓰지 않는다. 사용자 입력 전에는 합성 검증을 진행하며 getUpdates 수신기를 여러 개 실행하지 않는다. 실제 Telegram 발송은 사용자가 지정한 봇/개인 대화에서 연결 확인을 진행하도록 지시했을 때 수행한다. 실제 Codex 실행은 사용자 로그인 완료와 /run 테스트 요청 후 진행한다. D는 기본적으로 Telegram/자동 실행을 끈 격리 localhost 환경을 사용한다. 각 서비스의 포트와 SQLite/runtime 디렉터리를 분리해 운영 큐에 검증 작업을 넣지 않는다.

각 세션은 담당 변경·보고서를 검사하고 명시적 파일만 커밋한 뒤 scripts/parallel_work.ps1 -Mode Integrate -Role B|C|D로 공통 잠금 아래 로컬 main에 통합한다. 완료 직전 자기 워크트리와 main의 Git 상태를 확인하고 커밋·통합 결과를 보고한다. 문서만 수정했어도 미커밋으로 남기지 않는다. 실제 외부 연결/유료 실행/앱 빌드의 실행 여부를 구분하며 원격 push·배포는 별도 승인 범위를 따른다.
