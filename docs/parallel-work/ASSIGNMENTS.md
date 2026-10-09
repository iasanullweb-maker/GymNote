# 작업 배정표

2026-10-09 사용자 요청에 따라 기존 A/B/C/D의 아이디어 자동화 구현을 하나의 대화로 통합했다. 현재 담당은 `C:/Users/Donghyun/.codex/worktrees/d919/GymNote`, `codex/telegram-automation-unified`다. 기존 역할 워크트리와 보고서는 준비 이력으로 보존한다. 이 전환은 다른 CLI 프로세스를 종료하거나 메시지를 보내지 않는다.

| 작업 ID | 담당 파일 | 완료 기준 |
|---|---|---|
| IDEA-UNIFIED-1 | automation/**, docs/parallel-work/ASSIGNMENTS.md·GUIDE.md·workspaces.json·reports/unified.md, scripts/parallel_work.ps1, HANDOFF.md | 텔레그램 허용 발신자 수신·메모/실행 분리·영속 중복 방지, Codex 작업 큐·검토·검증·직렬 통합, 인증된 로컬 관리자, 회귀 검사·로컬 main 통합 |

아래는 통합 전 준비 상태다.

| 역할 | 작업 | 상태 | 교차 변경·의존성 |
|---|---|---|---|
| A | 4개 대화 지침·프롬프트·워크트리·통합 절차 구성 | 환경 구성·검증·로컬 통합 완료 | 기존 UX 환경 보존 |
| B | 다음 사용자 요청의 메시지 연동 작업 | 준비 | 공통 작업 입력 규격 준수 |
| C | 다음 사용자 요청의 에이전트 실행 작업 | 준비 | 상태 전이·시간 및 비용 제한 |
| D | 작업 입력·조회·중지·승인 관리자 화면 | 준비 | 모의 API로 독립 검증 |

각 구현 작업 배정 시 작업 ID, 구체적인 소유 파일, 완료 기준, 의존하는 API/커밋을 이 표에 추가한다. 아이디어 자동화 시스템은 HANDOFF.md의 백로그이며 이번 구성만으로 구현을 시작하지 않는다.
