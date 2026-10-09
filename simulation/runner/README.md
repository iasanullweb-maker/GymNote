# UX 시뮬레이션 실행기 (D)

의존성 없는 Node `.mjs` CLI다. 지원 기준은 **Node 24 이상**이다. 이번 단계에서는 입력 검증과 비용이 들지 않는 dry-run만 구현한다.

## 실행

```powershell
node scripts/ux-sim/run.mjs --help
node scripts/ux-sim/run.mjs --validate-only                 # 파일을 쓰지 않음
node scripts/ux-sim/run.mjs --dry-run                       # 기본 입력, 반복 3
node scripts/ux-sim/run.mjs --dry-run --examples --repeat 1 # 계약 examples만 사용
node --test "simulation/runner/tests/*.test.mjs"            # 테스트(따옴표로 Node가 glob 처리)
```

Windows 기본 PATH에는 Node가 없다. 실행하려면 Node 24 이상을 따로 준비해야 한다. 실행기는 Node를 설치하거나 외부 API를 호출하지 않는다. Node 24 미만에서는 경고를 남기고 계속 실행하지만 그 버전에서의 동작은 보증하지 않는다.

기본 입력은 `simulation/personas/`, `simulation/scenarios/`(바로 아래 `*.json`만 읽음), `simulation/capture/manifest.json`이다. persona 4개 × scenario 5개 × 반복 3회를 넣으면 합성 세션 60개를 계획한다.

## 출력

`simulation/runs/<run-id>/`에 쓴다. 이 폴더는 `.gitignore` 대상이다.

| 파일 | 내용 |
|---|---|
| `run.json` | 입력 파일 SHA-256, 실제 Git HEAD SHA와 미커밋 여부, 프롬프트 버전·해시, 캡처 상태·증거 경로, 미실행 검사, 경고, 후속 경계 |
| `plan.json` | persona × scenario × 반복 계획과 세션별 화면 캡처 상태 |
| `sessions/<persona>--<scenario>--r<n>.json` | `session.schema.json` 형식. `status=not-run`, `outcome=not-evaluated`, `model=null`, `usage.requests=0`, 관찰은 빈 배열, 모든 검사는 `not-evaluated` |
| `summary.md` | 사람이 읽는 요약. 합성 실행 수, 미실행 수, pending 캡처, 미실행 검사를 적고 사람 검증이 필요하다고 표시 |

세션의 `runId`는 `<run-id>/<persona>--<scenario>--r<n>` 형식이다. 세션 스키마에는 반복 번호 필드가 없어 이 값과 파일 이름으로 반복을 구분한다. 출력 경로는 `simulation/runs/` 아래만 허용한다. 같은 run-id가 이미 있으면 실패하고 기존 파일을 덮어쓰지 않는다. 입력 검증에 실패하면 출력 폴더를 만들지 않는다.

## 검증 범위

`lib/schema.mjs`는 JSON Schema 2020-12 전체를 구현하지 않는다. 현재 계약 스키마가 쓰는 키워드만 지원한다: `type, const, enum, pattern, minLength, minimum, maximum, minItems, uniqueItems, items, required, properties, additionalProperties:false, allOf, if/then`. 계약에 다른 키워드가 추가되면 조용히 무시하지 않고 오류로 멈춘다. 스키마는 `simulation/contracts/`에서 직접 읽으며, 실행기 쪽에 사본을 두지 않는다.

스키마 외에 다음 검사를 추가로 한다.

- persona/scenario ID 중복, 시나리오 내 검사 ID 중복, 비어 있는 성공 조건 설명이나 userGoal
- `startCaptureId ∈ captureIds`, 시나리오가 참조하는 capture ID가 manifest에 있는지
- manifest의 capture ID가 고정 10개 안에 있는지, 같은 ID·width·height·textScale 조합 중복, 고정 ID 10개를 모두 가진 변형이 하나 이상 있는지. 기본 834×1194/standard 변형을 우선 사용한다.
- captured 항목: `relativePath`가 manifest 폴더 기준 상대 경로인지(절대 경로·드라이브 문자·역슬래시·`.`/`..` 거부), 심볼릭 링크가 아닌지, 실제 일반 파일인지, PNG 서명과 SHA-256이 맞는지
- 입력 경로는 작업 루트 안에 있어야 하며, 경로 중간이나 대상이 심볼릭 링크면 거부
- 토큰·이메일·전화번호로 보이는 문자열 거부. 합성 데이터만 받는다.

## 판정 규칙 (`assessSession`)

생성한 세션과 후속 단계가 넘겨줄 세션에 같은 규칙을 적용한다.

- dry-run: `not-run`, `not-evaluated`, `model=null`, 요청·토큰 0, 관찰 없음
- `not-run`이면 판정된 검사나 관찰이 있으면 안 된다.
- `success`/`failure`는 `completed` 상태에서만 허용한다. `success`는 실패 검사가 없고 pass가 하나 이상 있어야 하며, `failure`는 fail이 하나 이상 있어야 한다.
- pass/fail에는 증거 경로가 있어야 한다.
- dry-run·screen-review에서는 app-state 검사를 판정하지 않는다. manual 검사는 모든 자동 모드에서 `not-evaluated`다.
- 검사 목록은 시나리오와 정확히 같아야 하고(누락·추가·중복 금지), 관찰은 step 1부터 순서대로, 시나리오의 화면·행동·maxSteps 범위 안에 있어야 한다.

## 후속 연결 경계 (미구현)

- live 모델 어댑터: 사용자 역할 입력은 persona, 현재 화면 이미지, userGoal만 받는다. checks·코드·미래 화면은 넣지 않는다. planner는 캡처와 관찰·행동 기록을 받는다. 결과 세션은 `assessSession`을 통과해야 저장한다. `usage`에는 실제 요청 수와 토큰 수를 기록한다.
- 앱 조작 어댑터(scripted-native/agent-native): 실행 전·후 저장 스냅샷 경로를 app-state 검사 증거로 넘겨야 한다.
- CLI는 `--dry-run`/`--validate-only` 외의 실행 모드를 받지 않는다.
