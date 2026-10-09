# 텔레그램 자동화 새 세션 인계

이 세션은 텔레그램 자동화 작업 전체를 하나의 세션에서 이어받습니다. 사용자는 세 세션이 아니라 새로운 세션 하나를 요청했습니다. 이전 B/C/D 병행 프롬프트는 사용하지 마세요.

- 작업 폴더: C:/Users/Donghyun/.codex/worktrees/d919/GymNote
- 브랜치: codex/telegram-automation-unified
- 통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

실제 경로·브랜치·git status --short --branch·git worktree list를 확인하세요. 기존 미커밋 변경을 보존하고, 깨끗한 담당 워크트리에 최신 main을 반영하세요. 모든 파일 편집과 검사는 이 워크트리에서 진행하며 원본 main에서 대신 수정하지 마세요. 해당 경로가 샌드박스 밖이면 이 폴더를 프로젝트로 열거나 필요한 권한을 요청하세요.

AGENTS.md, HANDOFF.md의 텔레그램 자동화 최신 상태와 연결 절차 1~6번, automation/README.md, automation/contracts/TASKS.md, docs/parallel-work/ASSIGNMENTS.md·workspaces.json·reports/unified.md를 읽으세요. 소유 범위는 IDEA-UNIFIED-1을 따릅니다. 기존 구현은 Telegram 수신·메모/실행 구분·SQLite 저장·Codex 큐/별도 검토/로컬 통합·관리자 화면·결과 알림·사전 점검이며 회귀 46개 통과 기록이 있습니다. 실제 봇 연결과 Codex 작업 실행은 아직 미확인입니다. 새 세션에서 현재 상태를 다시 확인하고 오래된 B/C/D 이력을 현재 작업으로 혼동하지 마세요.

지금 사용자에게 기록해 둔 1~6번 절차의 현재 진행 상태를 확인하고 완료를 돕는 작업을 시작하세요. 토큰·허용 ID·Codex 인증이 아직 없으면 사용자 입력에 의존하지 않는 사전 점검·합성/격리 검증·실행 안내 확인부터 진행하세요. 필요한 입력은 로컬 환경변수/설정으로 받으며 봇 토큰을 채팅/Git/로그에 복사하지 마세요. 같은 봇의 수신기를 여러 개 실행하지 마세요. 실제 봇 연결·발송은 사용자가 지정한 봇과 개인 대화에서 연결 확인을 진행하도록 지시했을 때, 실제 Codex 작업은 로그인 및 사용자의 /run 테스트 요청 후 진행하세요. 이미 확보된 승인과 설정을 반복해서 묻지 마세요. 검증 없이 1~6번을 완료로 표시하지 마세요. Claude 어댑터와 질문 답변 세션 재개는 남은 기능이며 이번 설정 확인에 임의로 끼워 넣지 마세요.

변경과 검증/미실행 결과를 docs/parallel-work/reports/unified.md에 기록하세요. 본인 파일만 명시적으로 커밋하고 scripts/parallel_work.ps1 -Mode Integrate -Unified로 공통 잠금 아래 로컬 main에 통합하세요. 문서 변경도 미커밋으로 남기지 마세요. 완료 직전 담당 워크트리와 main의 Git 상태·최종 커밋을 확인하세요. 최종 응답에 커밋·로컬 통합 여부·검증 결과·실제 외부 연결/유료 실행 여부·전체 iOS 빌드 여부·남은 사용자 설정을 명시하세요. 원격 push·배포·운영 DB 변경은 해당 승인 범위를 따릅니다.
