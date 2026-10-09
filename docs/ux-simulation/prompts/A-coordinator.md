이 대화는 GymNote UX 시뮬레이션 기반 작업의 A(공통 규격·통합) 담당이야.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/ux-coordinator
브랜치: codex/ux-coordinator
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

모든 파일 작업과 도구 명령의 workdir를 위 작업 폴더로 지정해줘. 대화가 원본 main에서 열렸더라도 지정 워크트리에서 작업해줘.

먼저 이 워크트리의 실제 경로, git branch --show-current, git status --short, git worktree list를 확인해줘. AGENTS.md, docs/ux-simulation/PARALLEL_WORK.md, docs/ux-simulation/CONTRACT.md, simulation/contracts/*.schema.json을 읽고 담당 범위 안에서 구현해줘.

다른 대화도 동시에 작업 중이야. 공통 규격과 HANDOFF.md는 A 소유 범위에서 수정하고, 다른 담당 파일·기존 AppModel/Models/project.yml/CI는 임의 수정하지 마. 필요한 변경은 본인 results 문서에 요청으로 남겨줘. 아직 없는 상대 산출물은 명시적인 합성 테스트 입력으로 대신하고 실제 통합 완료로 보고하지 마. 운영 사용자 데이터·토큰·실제 서버는 사용하지 마. 유료 모델 호출, 원격 push, Actions 실행, 배포, 운영 DB 변경은 이번 요청에 포함되지 않아.

본인 변경만 코드 검토·관련 검사·git diff --check 후 커밋해줘. 전역 Git 설정을 바꾸지 말고 git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit 을 사용해줘. 커밋 메시지에 [skip ci]를 포함하고 이번 담당 파일만 명시해줘.

AGENTS.md 규칙에 따라 완료 후 로컬 main 통합까지 진행해줘. 스크립트 scripts/ux_simulation_integrate.ps1을 본인 브랜치로 실행해 통합을 직렬화하고, 원본 main의 다른 변경은 보존해줘. 잠금이 있거나 main이 더러우면 임의 삭제/reset/stash 하지 말고 상태를 보고해줘. 충돌은 실제 의미를 확인해 해결해줘. 완료 보고에는 변경, 검증·전체 iOS 빌드 미실행 여부, 커밋, 로컬 통합, push·배포 여부를 적어줘.

현재 준비된 계약 4개와 환경·프롬프트를 유지하고 B/C/D 산출물을 검토·통합해줘. 담당은 simulation/contracts/**, PARALLEL_WORK.md, CONTRACT.md, prompts/**, workspaces.json, scripts/ux_simulation_integrate.ps1, scripts/ux_simulation_setup.ps1, .gitignore, HANDOFF.md야. 각 대화가 자기 범위를 검증하고 통합한 뒤 실제 파일 참조·ID·캡처 상태·dry-run 보고서를 연결해 확인해줘. 아직 상대 작업이 없으면 완료로 꾸미지 말고 준비 상태를 보고해줘. 전체 iOS 검증은 필요성과 실행 권한을 확인한 후 통합 검증 단계에서 진행해줘.
