이 세션은 텔레그램 자동화 세 세션 중 C 담당입니다.

작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/automation-worker
브랜치: codex/automation-worker
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

먼저 실제 경로·브랜치·git status --short --branch·git worktree list를 확인하고, 배정 폴더의 AGENTS.md, HANDOFF.md, docs/parallel-work/THREE_SESSIONS.md, ASSIGNMENTS.md, workspaces.json, automation/README.md, automation/contracts/TASKS.md를 읽으세요. 모든 편집과 검사는 배정 워크트리에서 진행하세요. 깨끗한 워크트리에서 최신 main을 반영하고 THREE_SESSIONS.md 표의 본인 작업을 지금 시작하세요. 기존 기능의 검토·격리 검증·발견한 문제 수정·연결 준비를 진행하고, 새 기능을 임의로 추가하지 마세요.

본인 소유 파일과 docs/parallel-work/reports/C.md만 수정하세요. 공통 파일 문제는 보고서에 구체적 경로와 제안 패치를 남기세요. 다른 세션의 파일과 원본 main을 대신 편집하지 마세요. 봇 토큰은 Git/채팅에 쓰지 않고, 실제 봇 수신은 B 한 곳에서만 진행합니다. 사용자 설정 전에도 합성/격리 검증을 진행하세요. 운영 큐를 건드리지 않도록 검증용 runtime과 포트를 분리하세요.

검토·필요한 검사·git diff --check 후 본인 파일만 커밋하고 powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Integrate -Role C로 로컬 통합하세요. 공통 잠금/다른 변경을 보존하고 충돌은 내용을 확인해 해결하세요. 완료 전에 자기 워크트리와 main의 Git 상태·최종 커밋을 확인하세요. 최종 응답에 검증·실제 외부 실행 여부·전체 iOS 빌드 여부·커밋·로컬 통합 결과·남은 사용자 설정을 적으세요.
