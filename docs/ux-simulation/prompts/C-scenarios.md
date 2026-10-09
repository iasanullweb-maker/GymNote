GymNote UX 시뮬레이션 기반 작업의 C(가상 사용자·시나리오) 담당이야. 이 메시지는 구현 요청이야.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/ux-scenarios
브랜치: codex/ux-scenarios
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

모든 파일 작업과 도구 명령의 workdir를 위 작업 폴더로 지정해줘. 대화가 원본 main에서 열렸더라도 지정 워크트리에서 작업해줘.

먼저 이 워크트리의 실제 경로, git branch --show-current, git status --short, git worktree list를 확인해줘. AGENTS.md, docs/ux-simulation/PARALLEL_WORK.md, docs/ux-simulation/CONTRACT.md, simulation/contracts/*.schema.json을 읽고 담당 범위 안에서 구현해줘.

다른 대화도 동시에 작업 중이야. 공통 규격·다른 담당 파일·HANDOFF.md·기존 AppModel/Models/project.yml/CI를 임의 수정하지 마. 필요한 변경은 본인 results 문서에 요청으로 남겨줘. 아직 없는 상대 산출물은 명시적인 합성 테스트 입력으로 대신하고 실제 통합 완료로 보고하지 마. 운영 사용자 데이터·토큰·실제 서버는 사용하지 마. 유료 모델 호출, 원격 push, Actions 실행, 배포, 운영 DB 변경은 이번 요청에 포함되지 않아.

본인 변경만 코드 검토·관련 검사·git diff --check 후 커밋해줘. 전역 Git 설정을 바꾸지 말고 git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit 을 사용해줘. 커밋 메시지에 [skip ci]를 포함하고 이번 담당 파일만 명시해줘.

AGENTS.md 규칙에 따라 완료 후 로컬 main 통합까지 진행해줘. 스크립트 scripts/ux_simulation_integrate.ps1을 본인 브랜치로 실행해 통합을 직렬화하고, 원본 main의 다른 변경은 보존해줘. 잠금이 있거나 main이 더러우면 임의 삭제/reset/stash 하지 말고 상태를 보고해줘. 충돌은 실제 의미를 확인해 해결해줘. 완료 보고에는 변경, 검증·전체 iOS 빌드 미실행 여부, 커밋, 로컬 통합, push·배포 여부를 적어줘.

담당 파일: simulation/personas/**, simulation/scenarios/**, simulation/prompts/**, docs/ux-simulation/results/scenarios.md.

해야 할 작업:
1. persona.schema.json에 맞는 사용자 4개를 만든다. 예: 앱 첫 사용자, 운동 중 주의가 분산된 사용자, 지난 운동을 몰아서 기록하는 사용자, 친구 경쟁 첫 사용자. 연령·성별 고정관념 대신 경험·목표·주의·읽기 상황을 지정한다.
2. scenario.schema.json에 맞는 5개 시나리오를 만든다: 운동 시작/실제 횟수/세트 완료, 계획 상세에서 다른 탭 후 복귀, 지난 운동 입력, 편집 취소와 기존 기록 보존, 친구 추가와 공개 끄기. 날짜는 demo-v1 기준 시각에 맞춘다. capture ID는 CONTRACT.md의 10개만 사용한다.
3. 사용자에게 보일 목표와 평가자 전용 성공 조건을 분리한다. 목표에 클릭 순서·버튼 위치·구현 정답을 알려주지 않는다. 성공 조건은 실제 저장 상태로 확인 가능한 app-state, 화면 이해 관찰인 observation-only, 사람 확인인 manual로 분류한다. 현재 screen-review만으로 app-state 성공을 주장할 수 없음을 명시한다.
4. simulation/prompts/user-v1.md, planner-v1.md를 만든다. 사용자에게 persona+현재 화면+목표만 준다. 기획자는 실행 후 관찰·캡처 증거를 받아 문제/근거/개선안/재검증 항목을 작성한다. 모델의 내부 사고 과정은 수집하지 않고 짧은 관찰 메모만 사용한다.
5. 사용자·시나리오 참조 일관성, 성공 조건 누락, 알려준 정답, 반복 실행 결과를 실제 사용자 발생률로 오해하는 표현을 검사한다. 검사 방법·제약을 본인 결과 문서에 기록한다.

사용할 통합 명령: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-scenarios
