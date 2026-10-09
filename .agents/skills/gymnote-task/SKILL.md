---
name: gymnote-task
description: GymNote 기능 수정과 문서 작업의 시작 범위 확인부터 검토, 커밋, 로컬 통합, 인수인계까지 진행한다. GymNote 구현·수정·작업 마무리 요청에 사용하며 단순 질문에는 Git 변경을 만들지 않는다.
---

# GymNote 작업 진행

## 시작과 범위

- 현재 작업 디렉터리에서 `git rev-parse --show-toplevel`로 저장소 루트를 확인한다. 이 스킬이 개인 폴더에 설치되어 있어도 저장소 경로를 스킬 위치에서 추정하지 않는다. 루트의 `AGENTS.md`, 적용되는 하위 지침, `HANDOFF.md`의 최신 관련 항목을 읽는다. GymNote 저장소가 아니면 적용하지 않는다.
- `git status --short --branch`, `git worktree list --porcelain`, `git log -1 --oneline`을 확인하고 시작 커밋·기존 변경·통합 대상 브랜치를 기록한다. detached HEAD에서 수정할 때는 기존 변경을 보존하고 `codex/` 작업 브랜치를 만든다.
- 병행 작업이면 `docs/parallel-work/GUIDE.md`, `ASSIGNMENTS.md`, `workspaces.json`을 읽고 현재 경로·브랜치와 배정을 대조한다. GUIDE가 다른 시작 문서를 우선하도록 지정하면 그 문서를 따른다. 역할 A를 임의로 자칭하지 않는다. 현재 배정과 과거 이력이 함께 있으면 최신 사용자 지시와 현재 배정을 우선한다.
- 요청을 관찰 가능한 완료 조건과 담당 파일로 정리한다. 공통 파일이나 다른 작업의 소유 범위를 건드려야 하면 배정 조율이 필요한 부분만 확인하고 독립 작업은 계속한다. 환경 준비를 새 기능 구현·외부 실행 승인으로 해석하지 않는다.

## 구현과 검증

- 기존 구현·테스트·규격을 필요한 만큼만 읽고 요청된 변경을 수행한다. 변경별 검증은 `gymnote-verify`가 사용 가능하면 활용한다. 없으면 `.github/workflows/check.yml`, `build.yml`과 담당 영역 README에서 현재 검사 명령을 확인한다.
- UI 흐름 검증에는 사용 가능한 `gymnote-ux-check` 또는 `docs/ux-simulation/REAL_DEVICE.md`, `simulation/web/README.md`를 따른다. 수정 후 관련 회귀만 재검증하며 웹 결과를 실제 Swift 앱의 동작 근거로 사용하지 않는다.
- 로그인·권한·데이터 저장 변경은 필요한 검사를 바로 실행한다. 작은 UI·문서 변경에 전체 iOS 빌드를 매번 실행하지 않고, 미실행과 그 이유를 명시한다.
- 오류 조사에는 `gymnote-debug`, 계정·저장·서버 변경에는 `gymnote-data-change`, 배포 요청에는 `gymnote-release`를 필요한 경우만 적용한다. 목록에 없으면 루트의 `.agents/skills/<이름>/SKILL.md`를 읽는다. 전문 스킬을 모두 매번 로드하지 않는다.
- push·Actions 실행·배포·운영 DB 변경·외부 메시지·유료 실행에는 해당 요청의 승인 범위를 적용한다. 스킬 호출 자체는 추가 승인이 아니다. 이미 승인된 작업에는 같은 승인을 다시 요청하지 않는다.

## 검토와 완료

- 본인 diff를 검토하고 검사 결과를 확인한다. `git diff --check`와 새 파일 검토를 수행하고, 본인 파일만 명시적으로 stage·커밋한다. 담당 보고서가 배정되어 있으면 변경·검증/미실행·의존성을 거기에 기록한다. HANDOFF와 공통 배정표는 소유 범위를 따른다.
- 결과 기록은 `gymnote-handoff` 또는 저장소의 해당 스킬 파일을 따라 확인된 상태와 다음 작업을 남긴다. 사용자가 HANDOFF 편집을 직접 요청했다면 그 범위에서 편집하며 다른 문단·작업을 보존한다.
- 워크트리 작업은 [로컬 통합 절차](references/integration.md)를 따라 시작 당시 기존 작업 브랜치에 통합한다. 통합 대상의 브랜치·진행 중 Git 작업·미커밋 변경을 통합 직전에 다시 확인한다.
- 완료 응답 직전에 본인과 원본 폴더의 `git status --short --branch`, 최종 커밋과 통합 ancestry를 확인한다. 변경 요지, 검사 결과/미실행, 전체 iOS 빌드 여부, 커밋 ID, 로컬 통합 여부, push·배포 여부를 보고한다. 막혔으면 끝난 단계와 남은 단계·원인을 구체적으로 적는다.
