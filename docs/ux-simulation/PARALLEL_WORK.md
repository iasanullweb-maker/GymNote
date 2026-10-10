# GymNote UX 시뮬레이션 병행 작업

작성: 2026-10-09. 이번 단계는 가상 사용자 사용성 점검의 기반 구축이다. 아래 작업 4개는 동일한 준비 커밋에서 시작한다. 새 대화 3개는 prompts/의 시작 메시지를 사용한다. 현재 대화가 A를 담당한다.

## 환경과 담당 범위

통합 대상: C:\Users\Donghyun\Documents\2026_IASA\GymNote, 시작 브랜치 main. 워크트리는 이 폴더의 .worktrees 아래에 생성한다.

| 대화 | 워크트리 / 브랜치 | 소유 파일 | 산출물 |
|---|---|---|---|
| A 현재 대화 | .worktrees/ux-coordinator / codex/ux-coordinator | simulation/contracts/**, docs/ux-simulation/PARALLEL_WORK.md, CONTRACT.md, prompts/**, workspaces.json, scripts/ux_simulation_integrate.ps1, scripts/ux_simulation_setup.ps1, HANDOFF.md, .gitignore | 공통 규격, 작업 환경, 통합 검토 |
| B 캡처 | .worktrees/ux-capture / codex/ux-capture | Tests/UXSimulationFixtures.swift, Tests/UXSimulationCaptureTests.swift, App/UXSimulationPreview.swift, simulation/capture/**, docs/ux-simulation/results/capture.md | 고정 데이터, 10개 화면 캡처 정의·실행 방법 |
| C 시나리오 | .worktrees/ux-scenarios / codex/ux-scenarios | simulation/personas/**, simulation/scenarios/**, simulation/prompts/**, docs/ux-simulation/results/scenarios.md | 사용자 조건 4개, 시나리오 5개, 사용자·기획자 프롬프트 |
| D 실행기 | .worktrees/ux-runner / codex/ux-runner | scripts/ux-sim/**, simulation/runner/**, docs/ux-simulation/results/runner.md | 입력 검증, 비용 없는 dry-run, 증거 기반 JSON·Markdown 보고서 |

기존 AGENTS.md를 우선 읽는다. 이 문서는 파일 소유 범위와 통합 순서를 구체화한다. 다른 담당 파일이 필요하면 해당 결과 문서에 요청을 남긴다. App/AppModel.swift, Shared/Models.swift, project.yml, 기존 테스트, CI, 운영 SQL은 이 단계에서 변경하지 않는다. B의 새 Swift 파일은 기존 XcodeGen의 App/·Tests/ 경로에 자동 포함된다. 별도 UI 테스트 타깃은 후속 단계다.

## 2026-10-10: 실기기 subagent 파일럿 준비

사용자의 subagent 가상 사용자 준비 요청은 기존 UX 총괄 워크트리에서 진행한다. 추가 소유 범위는 `docs/ux-simulation/pilot/**`, `scripts/ux_simulation_prepare_pilot.py`, `docs/ux-simulation/results/subagent-pilot.md`다. 기존 C의 persona/시나리오/프롬프트와 D의 runner는 수정하지 않는다. 역할 준비 subagent는 읽기 전용으로 초보·주의 분산·기획자 설계를 검토하고 부모만 파일을 편집한다. 실제 사용자 실행은 새 독립 컨텍스트로 시작하며 단일 실기기 조작은 부모가 직렬 중계한다. [실행 안내](pilot/README.md)를 따른다.

## 공통 계약과 독립 작업

CONTRACT.md와 simulation/contracts/*.schema.json을 v1 기준으로 사용한다. 각 담당은 examples/를 테스트용 입력으로 읽을 수 있지만 수정하지 않는다. 담당끼리 아직 없는 파일은 자신이 소유하는 테스트 디렉터리에 명시적인 합성 샘플을 만들어 검증하고, 실제 상대 산출물과의 통합 검증은 A가 진행한다.

- B가 아직 캡처를 못 만들었다면 pending으로 기록한다. 이미지 파일이 없는 캡처를 captured로 표시하지 않는다.
- C는 계약의 capture ID만 참조하고 구현 코드·정답 경로를 사용자 프롬프트에 넣지 않는다.
- D는 pending 캡처를 정상 처리하며 실제 평가 결과를 꾸며내지 않는다. dry-run은 not-run/not-evaluated로 남긴다.
- 실제 사용자 의견, 가상 사용자 관찰, 모델 오류, 앱 오류를 구분한다. 코드나 프롬프트 개선은 근거를 붙인 제안으로 남긴다.

## 런타임과 권한

Git은 확인됐고 이 세션 PATH에서는 Node·Python·Swift·XcodeGen이 발견되지 않았다. 현재 Codex의 Node REPL로 JSON 검사와 파일 작업은 가능하지만 독립 CLI 실행 환경이 준비됐다는 뜻은 아니다. D는 의존성 없는 Node 24 이상 .mjs 실행기를 작성하고 node scripts/ux-sim/run.mjs --help 명령을 제공한다. Node 설치는 별도 환경 준비가 필요하며 설치됐다고 보고하지 않는다. B의 렌더·XCTest는 Mac/Xcode 또는 후속 GitHub Actions 실행이 필요하다.

운영 계정·기록·토큰을 사용하지 않는다. demo-v1 데이터는 합성 데이터로 만들고 네트워크 호출을 차단한다. 유료 모델 API 호출, 원격 push, Actions 실행, 배포, 운영 DB 변경은 이번 요청의 범위에 포함되지 않는다. 모델 연결은 후속 단계로 남기고 필요한 입력·출력 경계만 준비한다.

## 검증과 완료 보고

각 대화는 범위 내 코드 검토, git diff --check, 실행 가능한 관련 검사를 수행한다. B는 Windows의 코드 검토를 실제 iOS 렌더 성공으로 보고하지 않는다. C는 참조 ID·미리 알려준 정답·검증 가능한 성공 조건을 확인한다. D는 누락 이미지, 잘못된 JSON·ID, 파일 경로 탈출, 상태 판정, 중복 실행 덮어쓰기와 샘플 데이터 입력을 검증한다.

results/의 본인 파일에 변경 파일·명령·성공/미실행 결과·커밋·남은 요청을 기록한다. HANDOFF.md는 A가 관리한다. 기록 후 본인 파일만 커밋한다. 작성자는 이번 명령에만 적용한다:

~~~powershell
git -c user.name=Codex -c user.email=codex@users.noreply.github.com commit -m "작업 범위에 맞는 메시지 [skip ci]" -- <이번 작업 파일>
~~~

## 로컬 통합: 한 번에 한 대화

AGENTS.md의 자동 로컬 통합 규칙을 유지한다. 각 대화는 검토·검증·커밋을 마친 뒤 아래 스크립트로 시작 당시 main에 병합한다. 스크립트는 통합 잠금을 얻고 원본 폴더 main·미커밋 변경·본인 워크트리 상태를 다시 확인한다. 바쁘거나 기존 폴더의 추적 파일에 미커밋 변경이 있으면 강제로 진행하지 않고 상태를 보고한다. 잠금 파일을 임의 삭제하지 않는다. 다른 작업의 미추적 파일은 스테이징·삭제하지 않고 보존하며, 병합 대상 경로와 충돌하면 Git이 병합을 거부한다.

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ux_simulation_integrate.ps1 -SourceBranch codex/ux-capture
~~~

Windows 실행 정책이 .ps1 실행을 막을 수 있어 위 명령은 해당 PowerShell 프로세스에서만 Bypass를 지정한다. 전역 실행 정책은 변경하지 않는다.

C/D는 자기 브랜치를 전달한다. 병합 충돌이 있으면 reset·stash·강제 push·임의 merge abort로 덮지 말고 실제 diff를 검토해 해결한다. 서로 다른 원본 문서 변경을 보존한다. 완료 응답에는 통합 여부, 검증 결과, 전체 iOS 빌드 미실행 여부, push·배포 여부를 적는다. A는 세 작업의 통합 후 실제 입력 연결과 공통 검사 결과를 검토한다.

## 완료 기준

4개 계약 + 별도 워크트리 + 복사 가능한 프롬프트, 고정 합성 데이터·10개 캡처 정의, 4개 사용자·5개 시나리오, API 호출 없는 dry-run·보고서가 준비되면 기반 작업 완료다. 실제 화면 캡처·LLM 평가·앱 직접 조작의 완료 여부는 각각 별도로 기록한다.

## A 공통 검사 사용

공통 계약의 선택적 재사용 API와 통합 준비 검사 명령은 simulation/contracts/README.md에 있다. v1 스키마는 유지한다. 입력이 아직 없는 상황, pending 캡처, 실제 이미지 검증을 구분한다. B/C/D의 작업을 대신 수행하지 않고 실제 입력 연결은 해당 커밋 통합 후 검사한다.
