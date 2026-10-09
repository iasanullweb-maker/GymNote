GymNote UX 시뮬레이션 기반 작업의 D(실행기·평가 보고서) 담당이야. 이 메시지는 구현 요청이야.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/ux-runner
브랜치: codex/ux-runner
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

모든 파일 작업과 도구 명령의 workdir를 위 작업 폴더로 지정해줘. 대화가 원본 main에서 열렸더라도 지정 워크트리에서 작업해줘.

먼저 이 워크트리의 실제 경로, git branch --show-current, git status --short, git worktree list를 확인해줘. AGENTS.md, docs/ux-simulation/PARALLEL_WORK.md, docs/ux-simulation/CONTRACT.md, simulation/contracts/*.schema.json을 읽고 담당 범위 안에서 구현해줘.

다른 대화도 동시에 작업 중이야. 공통 규격·다른 담당 파일·HANDOFF.md·기존 AppModel/Models/project.yml/CI를 임의 수정하지 마. 필요한 변경은 본인 results 문서에 요청으로 남겨줘. 아직 없는 상대 산출물은 명시적인 합성 테스트 입력으로 대신하고 실제 통합 완료로 보고하지 마. 운영 사용자 데이터·토큰·실제 서버는 사용하지 마. 유료 모델 호출, 원격 push, Actions 실행, 배포, 운영 DB 변경은 이번 요청에 포함되지 않아.

본인 변경만 코드 검토·관련 검사·git diff --check 후 커밋해줘. 전역 Git 설정을 바꾸지 말고 git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit 을 사용해줘. 커밋 메시지에 [skip ci]를 포함하고 이번 담당 파일만 명시해줘.

AGENTS.md 규칙에 따라 완료 후 로컬 main 통합까지 진행해줘. 스크립트 scripts/ux_simulation_integrate.ps1을 본인 브랜치로 실행해 통합을 직렬화하고, 원본 main의 다른 변경은 보존해줘. 잠금이 있거나 main이 더러우면 임의 삭제/reset/stash 하지 말고 상태를 보고해줘. 충돌은 실제 의미를 확인해 해결해줘. 완료 보고에는 변경, 검증·전체 iOS 빌드 미실행 여부, 커밋, 로컬 통합, push·배포 여부를 적어줘.

담당 파일: scripts/ux-sim/**, simulation/runner/**, docs/ux-simulation/results/runner.md. 의존성 없는 Node 24 이상 .mjs CLI를 사용한다. 현재 PATH에 Node가 없으므로 실행 방법·환경 제약을 명시한다. 설치나 외부 API 호출을 자동 진행하지 않는다.

해야 할 작업:
1. scripts/ux-sim/run.mjs와 --help를 제공한다. persona/scenario/capture manifest 입력 경로, 반복 횟수, 출력 경로, dry-run 모드를 받는다. 4×5×3=60 실행 계획을 만들 수 있게 한다. C/B가 아직 없으면 계약 examples로 검증한다.
2. 공통 JSON 계약을 검사한다. 전체 JSON Schema 구현 대신 필요한 계약 검증을 수동 구현하면 지원 범위를 명시하고 실제 사용하는 스키마 필드와 일치시키며 잘못된 값은 거부한다. unknown ID·중복 persona/scenario·누락 성공 조건·cap ID·PNG 존재/SHA를 검증한다. 캡처의 같은 ID는 기기/글씨 변형 조합으로 구분한다.
3. dry-run은 LLM·앱 조작을 실행하지 않는다. status=not-run/outcome=not-evaluated/model=null/requests=0이다. pending 이미지는 보고서에 pending으로 표시하고 평가가 성공했다고 하지 않는다. 화면 기반 평가에서는 app-state 검사를 pass로 처리하지 않는다. 이번에는 live 모델 호출과 앱 자동 조작을 구현하지 않고 후속 연결 경계만 명시한다.
4. simulation/runs/<run-id>/ 아래 session.schema.json 형식의 JSON·실행 계획·Markdown 요약을 만든다. 입력 파일 해시, 실제 Git 코드 SHA, 프롬프트 버전, 실행 모드, 미실행 검사와 증거 경로를 남긴다. 결과가 없는 세션에서 문제나 개선안을 꾸며내지 않는다.
5. 입력/출력 경로 탈출·심볼릭 링크, 누락 파일, 부정확한 SHA, 반복 실행 덮어쓰기, 잘못된 상태 판정, 개인정보/토큰 입력 없는 합성 사례를 의미 있는 테스트로 검증한다. 출력은 기본 무시된 simulation/runs에 제한하고 기존 run-id를 덮어쓰지 않는다.
6. 보고서에는 가상 실행 수와 사람 검증 필요를 표시하고 실행 횟수를 실제 사용자의 비율·만족도·소요시간으로 표현하지 않는다.

사용할 통합 명령: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-runner
