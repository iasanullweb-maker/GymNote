# D 실행기 결과 보고

작성: 2026-10-09. 담당: D(실행기·평가 보고서). 워크트리 `.worktrees/ux-runner`, 브랜치 `codex/ux-runner`, 시작 커밋 `174da81`.

## 변경 파일

| 파일 | 역할 |
|---|---|
| `scripts/ux-sim/run.mjs` | CLI. `--help`, `--dry-run`, `--validate-only`, 입력 경로, `--repeat`, `--run-id`, `--out-dir`, `--prompt-version`, `--examples`, `--json` |
| `simulation/runner/lib/schema.mjs` | JSON Schema 2020-12 부분 집합 검증기. 지원하지 않는 키워드를 만나면 오류로 멈춘다 |
| `simulation/runner/lib/paths.mjs` | 루트 밖 입력·출력 거부, 심볼릭 링크 거부, manifest relativePath 해석 |
| `simulation/runner/lib/inputs.mjs` | persona/scenario/manifest 읽기, 교차 참조, PNG 서명·SHA-256, 민감 정보 패턴, 프롬프트 해시 |
| `simulation/runner/lib/session.mjs` | dry-run 세션 생성, 상태 판정 규칙 `assessSession` |
| `simulation/runner/lib/dryrun.mjs` | 실행 계획, `simulation/runs/<run-id>/` 출력, 덮어쓰기 방지 |
| `simulation/runner/lib/git.mjs` | 실제 `git rev-parse HEAD`와 미커밋 여부 기록. 확인하지 못하면 null로 남기고 사유를 기록 |
| `simulation/runner/lib/report.mjs` | Markdown 요약 |
| `simulation/runner/tests/*.mjs` | `node:test` 테스트 56개와 합성 입력 생성기 |
| `simulation/runner/README.md` | 실행 방법, 출력 형식, 검증 범위, 판정 규칙, 후속 연결 경계 |
| `docs/ux-simulation/results/runner.md` | 이 문서 |

공통 계약, examples, 다른 담당 파일, HANDOFF.md, AppModel/Models/project.yml/CI는 수정하지 않았다.

## 동작 요약

- `--dry-run`: 입력을 검증한 뒤 persona × scenario × 반복 계획을 만들고, `run.json`, `plan.json`, `sessions/*.json`, `summary.md`를 새 run 폴더에 쓴다. 모든 세션은 `status=not-run`, `outcome=not-evaluated`, `model=null`, `usage.requests=0`, 빈 관찰, 모든 검사 `not-evaluated`(증거 없음)다.
- 보고서는 합성 실행 수·미실행 수·pending 캡처·미실행 검사를 표시하고 사람 검증이 필요하다고 적는다. 실제 사용자의 비율·만족도·소요시간으로 표현하지 않고, 결과가 없으므로 문제·개선안을 작성하지 않는다.
- 기록 항목: 입력 파일 SHA-256, 실행 코드의 실제 Git SHA와 미커밋 여부, 캡처 manifest의 appCommit(코드 SHA와 다르면 경고), 프롬프트 버전과 `simulation/prompts/{user,planner}-<v>.md` 해시(없으면 missing), 실행 모드, 미실행 검사와 사유, 캡처 증거 경로.
- 출력은 `simulation/runs/` 아래로만 쓴다(`.gitignore` 대상). 기존 run-id는 덮어쓰지 않는다. 입력 검증에 실패하면 출력 폴더를 만들지 않는다.
- live 모델 호출, screen-review, 앱 자동 조작은 구현하지 않았다. 후속 연결 경계는 README와 각 `run.json`의 `boundaries`에 적었다.

## 검증 범위

스키마 검증기는 현재 계약이 쓰는 키워드만 지원한다: type/const/enum/pattern/minLength/minimum/maximum/minItems/uniqueItems/items/required/properties/additionalProperties:false/allOf/if-then. `format`, `oneOf` 같은 다른 키워드가 계약에 추가되면 `[contract-unsupported]`로 멈춘다. 스키마 파일은 `simulation/contracts/`에서 직접 읽는다.

스키마 외 검사:

- unknown capture ID(manifest·시나리오 모두)
- persona/scenario ID 중복, 검사 ID 중복
- 성공 조건 누락이나 빈 설명, `startCaptureId ∉ captureIds`
- 같은 ID에 같은 width/height/textScale 조합 중복. 크기·글씨가 다르면 같은 ID라도 허용한다. 고정 ID 10개를 모두 가진 변형이 하나 이상 있어야 한다.
- captured PNG의 존재·일반 파일 여부·PNG 서명·SHA-256
- relativePath의 `..`, `.`, 절대 경로, 드라이브 문자, 역슬래시, 심볼릭 링크
- 토큰·이메일·전화번호 형태의 입력 문자열

## 실행한 명령과 결과

| 명령 | 환경 | 결과 |
|---|---|---|
| `node --test "simulation/runner/tests/*.test.mjs"` | Linux Node 22.22.0 (클라우드 작업 공간) | 56개 통과, 실패 0, 건너뜀 0 |
| 같은 명령, `GIT_DIR=/nonexistent` 상속 | Linux Node 22.22.0 | 56개 통과. 테스트 하위 프로세스가 `GIT_*` 환경을 쓰지 않음을 확인 |
| 같은 명령 | 사용자 PC 폴더를 연 Linux VM, Node 22.23.2 | 56개 통과 (아래 사고 기록 참조) |
| 일부러 규칙 3개를 깬 변형(SHA 비교 생략, screen-review app-state 허용, run 폴더 덮어쓰기) | Linux Node 22 | 해당 테스트 3개가 실패해 테스트가 규칙을 실제로 검사함을 확인한 뒤 원복 |
| `node scripts/ux-sim/run.mjs --validate-only --examples` | 워크트리 | 통과, 계획 가능 세션 3개 |
| `run.mjs --dry-run`: C의 persona 4·scenario 5(main `f96bb13`) + B 워크트리의 미통합 pending manifest를 임시 루트에 복사해 실행 | 임시 폴더 | 합성 세션 60개, 모두 not-run/not-evaluated, 모델 요청 0. pending 10개가 summary에 pending으로 표시됨 |
| `git diff --check` | 워크트리 | 통과(커밋 전 확인) |

- Node 24에서는 실행하지 않았다. 코드는 Node 22에도 있는 API(`node:test`, `util.parseArgs`, `fs`, `crypto`)만 쓰며, 24 미만에서는 경고를 남긴다. Windows PATH에는 Node가 없으므로 Windows에서 실행하려면 Node 24 이상을 따로 준비해야 한다.
- Windows에서 심볼릭 링크를 만들 권한이 없으면 심볼릭 링크 테스트 4개는 건너뛴다. 이번 실행 환경에서는 모두 실행됐다.
- 위의 C·B 입력 dry-run은 실행기 동작 확인용이다. A의 실제 통합 검증을 대신하지 않는다.
- 로컬 main 통합(`d4c3529`, B `2fe7110` 이후) 뒤 main에서 `node --test`(56개 통과)와 기본 경로 `node scripts/ux-sim/run.mjs --validate-only`(persona 4, scenario 5, 반복 3 → 계획 60, 캡처 10)를 확인했다. 파일은 쓰지 않았다.
- 전체 iOS 빌드·XCTest는 실행하지 않았다(이번 변경은 Swift 코드와 무관).

## 작업 중 사고와 복구

이 작업은 사용자 PC 폴더를 Linux VM에 마운트해 진행했다. 이 환경의 Git은 Windows 경로로 기록된 worktree gitdir를 찾지 못해 `GIT_DIR`/`GIT_WORK_TREE`를 지정해 사용했다. 이 상태에서 테스트를 처음 실행했을 때 Git SHA 테스트의 `git init/add/commit`이 상속된 환경 변수 때문에 임시 폴더가 아니라 실제 워크트리에 적용됐다. 그 결과는 다음과 같고, 모두 이 담당의 변경만 되돌렸다.

1. `codex/ux-runner`에 작성자 Test, 메시지 synthetic인 커밋 `ddbf627`이 생겼다. 담당 파일 13개만 들어 있었다. `git reset --soft 174da81`로 브랜치만 되돌리고 파일은 유지했다. 원격에는 올라가지 않았다.
2. 공유 `.git/config`에 `core.worktree=/sessions/…/ux-runner`가 추가됐다. 해당 키만 제거했고, core 설정이 작업 전과 같은지(repositoryformatversion, filemode=false, bare, logallrefupdates, ignorecase, autocrlf=false) 확인했다.
3. `.git/worktrees/ux-runner/HEAD.lock`(0바이트, 07:38 UTC 생성)이 남아 있어 삭제했다. `.git/objects/maintenance.lock`(06:23 UTC)은 이 작업 이전의 다른 프로세스 것이라 건드리지 않았다.
4. 그때 만든 `simulation/runs/sha-check` 출력은 삭제했다.

재발 방지: 테스트의 모든 하위 프로세스(CLI·git)는 `GIT_*` 환경 변수를 제거한 환경으로 실행한다. Git 테스트는 임시 루트가 이미 저장소 안에 있으면 시작 전에 중단한다. 이후 `GIT_DIR`을 지정한 상태로 다시 실행해 브랜치·설정이 바뀌지 않음을 확인했다.

## A에게 요청

- `.gitignore`의 `simulation/runs/`는 실행기 출력 위치와 일치한다. 변경은 필요 없다.
- 세션 스키마에는 반복 번호·실행 계획 ID 필드가 없다. 실행기는 세션 `runId`를 `<run-id>/<persona>--<scenario>--r<n>`로 기록한다. 공식 필드가 필요하면 스키마 v2에서 검토해 달라.
- 계약 스키마에 새 키워드를 추가할 때는 `simulation/runner/lib/schema.mjs`의 지원 목록도 함께 갱신해야 한다. 그렇지 않으면 실행기가 `[contract-unsupported]`로 멈춘다(의도된 동작).
- 통합 후 실제 B manifest로 기본 경로 dry-run(`node scripts/ux-sim/run.mjs --dry-run`)을 확인해 달라.

## 미실행·범위 밖

live 모델 호출, 유료 API, 앱 자동 조작, screen-review 평가, Node 24 실행, Windows PowerShell에서의 실행, 원격 push, Actions, 배포, 운영 DB 변경은 하지 않았다.
