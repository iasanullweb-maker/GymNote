이 대화는 GymNote 4개 병행 대화의 B(메시지 연동) 담당이야.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/automation-ingress
브랜치: codex/automation-ingress
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

모든 명령의 workdir와 파일 작업을 위 폴더로 지정해줘. 기존 작업 중인 대화라면 먼저 미커밋 변경과 기존 요청을 확인하고 보존해줘. 원본 main이나 다른 담당 폴더에서 대신 편집하지 마.

실제 경로·브랜치·git status --short·git worktree list를 확인하고 AGENTS.md, HANDOFF.md, docs/parallel-work/GUIDE.md, ASSIGNMENTS.md, workspaces.json, automation/contracts/TASKS.md를 읽어줘. Claude Code도 같은 규칙을 따라줘. automation/ingress/**를 담당해줘. 텔레그램을 우선 후보로 두되 연결 어댑터를 분리하고, 발신자 인증·중복 이벤트 방지·메모와 실행 요청 구분을 설계해줘. 초기에는 합성 메시지로 검증하고 실제 봇 등록·외부 메시지 발송은 별도 승인 범위를 확인해줘.

이 대화를 포함해 4개 대화가 동시에 작업해. 본인 소유 범위와 reports/B.md만 수정하고, 공통 파일이나 교차 변경이 필요하면 보고서에 요청해줘. 기존 UX 시뮬레이션 워크트리와 소유 파일은 건드리지 마. 다른 작업을 stage·reset·임의 stash로 덮어쓰지 마. 토큰·인증 정보를 Git이나 채팅에 복사하지 마.

지금 구현할 구체적인 기능이 전달되지 않았다면 담당 영역을 파악하고 준비 상태를 보고해줘. 새 기능을 임의 착수하지 마. 사용자 요청을 받으면 범위 내 구현·코드 검토·필요한 검사를 완료하고 git diff --check 후 본인 파일만 명시적으로 stage·커밋해줘. 기존 Git 작성자 설정이 없다면 Codex의 기존 작성자 정보는 git -c user.name=Codex -c user.email=codex@users.noreply.github.com으로 이번 커밋에만 적용해줘. 환경·문서 변경 커밋에는 [skip ci]를 사용하고 기능 변경은 필요한 CI를 생략하지 마.

완료 시 사용자 상시 요청대로 powershell -NoProfile -File scripts/parallel_work.ps1 -Mode Integrate -Role B 로 로컬 main에 통합해줘. 공통 잠금이 바쁘면 기다렸다 다시 시도하고, main 미커밋 변경은 보존해줘. 충돌은 내용을 검토해 해결하고 사용자 판단이 꼭 필요한 경우에만 질문해줘. 원격 push·Actions 실행·배포·운영 DB 변경은 해당 요청의 승인 범위를 따라줘.

최종 응답에 변경 내용, 검증 결과·미실행한 전체 iOS 빌드, 커밋, 로컬 통합 여부, 남은 의존성을 적어줘. 본인 보고서는 docs/parallel-work/reports/B.md에 남겨줘.
