# 작업 배정표

## 현재 운영: 텔레그램 세 세션 (2026-10-09)

사용자 요청으로 B(텔레그램 연결), C(Codex 실행), D(관리자 화면·운영 검증)의 별도 워크트리에서 다시 병행한다. 현재 작업 범위와 시작 절차는 [세 세션 안내](THREE_SESSIONS.md)를 우선 적용한다. 기존 unified 구현은 완료 이력으로 보존하며 d919에서 동시 구현을 진행하지 않는다. 이 대화는 배정·공통 문서 정리만 담당한다. 아래 단일 대화 전환 내용은 이전 운영 이력이다.


2026-10-09 사용자 요청에 따라 기존 A/B/C/D의 아이디어 자동화 구현을 하나의 대화로 통합했다. 현재 담당은 `C:/Users/Donghyun/.codex/worktrees/d919/GymNote`, `codex/telegram-automation-unified`다. 기존 역할 워크트리와 보고서는 준비 이력으로 보존한다. 이 전환은 다른 CLI 프로세스를 종료하거나 메시지를 보내지 않는다.

| 작업 ID | 담당 파일 | 완료 기준 |
|---|---|---|
| IDEA-UNIFIED-1 | automation/**, docs/parallel-work/ASSIGNMENTS.md·GUIDE.md·workspaces.json·reports/unified.md, scripts/parallel_work.ps1, HANDOFF.md | 텔레그램 허용 발신자 수신·메모/실행 분리·영속 중복 방지, Codex 작업 큐·검토·검증·직렬 통합, 인증된 로컬 관리자, 회귀 검사·로컬 main 통합 |
| UI-CODEX-1 | `346d/GymNote`, `codex/friends-records-ui`; 구체 파일은 [UI_HANDOFF.md](UI_HANDOFF.md)의 Codex 범위 | 친구·기록 화면, 친구 기능 탈퇴, 공통 종목 조회·갱신 검증, 최종 교차 검토·로컬 통합 |
| UI-CLAUDE-1 | 원본 저장소 `.worktrees/claude-workout-flow`, `codex/claude-workout-flow`; 구체 파일은 [UI_HANDOFF.md](UI_HANDOFF.md)의 Claude 범위 | 실행 탭 표시·세트 진행도·완료 정렬·길게 눌러 순서 변경·저장 완료 애니메이션, 기록 보존 회귀 |

UI 분담은 2026-10-09 사용자의 추가 지시에 따른 별도 작업이다. 최초 가입 안내·튜토리얼·사용자 조사는 제외한다. 아이디어 자동화 및 UX 시뮬레이션의 기존 소유 범위는 유지한다. 공통 배정표·HANDOFF의 UI 변경은 Codex가 관리하며 다른 작업의 동시 변경을 보존한다.

아래는 통합 전 준비 상태다.

| 역할 | 작업 | 상태 | 교차 변경·의존성 |
|---|---|---|---|
| A | 4개 대화 지침·프롬프트·워크트리·통합 절차 구성 | 환경 구성·검증·로컬 통합 완료 | 기존 UX 환경 보존 |
| B | 다음 사용자 요청의 메시지 연동 작업 | 준비 | 공통 작업 입력 규격 준수 |
| C | 다음 사용자 요청의 에이전트 실행 작업 | 준비 | 상태 전이·시간 및 비용 제한 |
| D | 작업 입력·조회·중지·승인 관리자 화면 | 준비 | 모의 API로 독립 검증 |

각 구현 작업 배정 시 작업 ID, 구체적인 소유 파일, 완료 기준, 의존하는 API/커밋을 이 표에 추가한다. 아이디어 자동화 시스템은 HANDOFF.md의 백로그이며 이번 구성만으로 구현을 시작하지 않는다.
