GymNote UX 시뮬레이션 기반 작업의 B(고정 데이터·화면 캡처) 담당이야. 이 메시지는 구현 요청이야.
작업 폴더: C:/Users/Donghyun/Documents/2026_IASA/GymNote/.worktrees/ux-capture
브랜치: codex/ux-capture
통합 대상: C:/Users/Donghyun/Documents/2026_IASA/GymNote의 main

모든 파일 작업과 도구 명령의 workdir를 위 작업 폴더로 지정해줘. 대화가 원본 main에서 열렸더라도 지정 워크트리에서 작업해줘.

먼저 이 워크트리의 실제 경로, git branch --show-current, git status --short, git worktree list를 확인해줘. AGENTS.md, docs/ux-simulation/PARALLEL_WORK.md, docs/ux-simulation/CONTRACT.md, simulation/contracts/*.schema.json을 읽고 담당 범위 안에서 구현해줘.

다른 대화도 동시에 작업 중이야. 공통 규격·다른 담당 파일·HANDOFF.md·기존 AppModel/Models/project.yml/CI를 임의 수정하지 마. 필요한 변경은 본인 results 문서에 요청으로 남겨줘. 아직 없는 상대 산출물은 명시적인 합성 테스트 입력으로 대신하고 실제 통합 완료로 보고하지 마. 운영 사용자 데이터·토큰·실제 서버는 사용하지 마. 유료 모델 호출, 원격 push, Actions 실행, 배포, 운영 DB 변경은 이번 요청에 포함되지 않아.

본인 변경만 코드 검토·관련 검사·git diff --check 후 커밋해줘. 전역 Git 설정을 바꾸지 말고 git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit 을 사용해줘. 커밋 메시지에 [skip ci]를 포함하고 이번 담당 파일만 명시해줘.

AGENTS.md 규칙에 따라 완료 후 로컬 main 통합까지 진행해줘. 스크립트 scripts/ux_simulation_integrate.ps1을 본인 브랜치로 실행해 통합을 직렬화하고, 원본 main의 다른 변경은 보존해줘. 잠금이 있거나 main이 더러우면 임의 삭제/reset/stash 하지 말고 상태를 보고해줘. 충돌은 실제 의미를 확인해 해결해줘. 완료 보고에는 변경, 검증·전체 iOS 빌드 미실행 여부, 커밋, 로컬 통합, push·배포 여부를 적어줘.

담당 파일: Tests/UXSimulationFixtures.swift, Tests/UXSimulationCaptureTests.swift, App/UXSimulationPreview.swift(필요하면 DEBUG 전용), simulation/capture/**, docs/ux-simulation/results/capture.md.

해야 할 작업:
1. 기존 DisplayTests와 AppModel(previewData:)를 읽고 demo-v1 합성 데이터 factory를 만든다. 기준 시각·UUID·계획·일지 값은 고정하고 매 테스트에 새 사본을 쓴다. Date() 의존성과 네트워크·Keychain·실제 파일 쓰기 발생 여부를 확인한다. 운영 데이터 저장 코드를 변경하지 않는다.
2. CONTRACT.md의 고유 화면 ID 10개에 대한 캡처 진입점을 새 테스트에 만든다. 최신 앱은 친구 관리가 별도 친구 탭이고 기록에는 친구 순위가 있다. 실제 타입을 확인해 반영한다. 기본 834×1194pt, ko_KR, Asia/Seoul. 가능한 경우 큰 글씨·분할 화면 변형을 추가한다. 접근 불가능한 화면은 이유를 기록하고 가짜 이미지로 대체하지 않는다.
3. 새 캡처 XCTest는 keepAlways 첨부물과 안정적인 파일 이름을 남긴다. 실제 PNG를 manifest로 연결하고 SHA-256을 생성할 방법을 simulation/capture/ 아래에 제공한다. 이미지 relativePath는 manifest 기준이며 ../나 절대 경로를 허용하지 않는다.
4. simulation/capture/manifest.json에 계약 형식으로 기본 10개를 등록한다. 실제 렌더를 못 실행한 항목은 pending으로, 실패는 failed로 기록한다. 캡처하지 않은 파일 이름·SHA를 실제 결과처럼 넣지 않는다. generated PNG는 simulation/runs/ 등 무시된 폴더에 저장하는 방법을 문서화한다.
5. fixture의 고정 값·계정/네트워크 격리를 확인하는 의미 있는 테스트와 Mac 실행 명령을 준비한다. Windows에서 실행하지 못한 iOS 렌더·XCTest는 미실행이라고 적는다. 기존 테스트와 project.yml을 수정하지 않는다. 기존 Tests/ 자동 포함을 이용한다.

사용할 통합 명령: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-capture
