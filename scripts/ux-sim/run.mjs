#!/usr/bin/env node
// GymNote UX 시뮬레이션 실행기 CLI (의존성 없음, Node 24 이상 기준).
// 이번 단계는 입력 검증과 비용 없는 dry-run만 수행한다.
import { parseArgs } from 'node:util';
import {
  DEFAULT_INPUTS, EXAMPLE_INPUTS, MAX_REPEAT, RUNS_DIR, prepare, runDry,
} from '../../simulation/runner/lib/dryrun.mjs';
import { RunnerError } from '../../simulation/runner/lib/paths.mjs';
import { UnsupportedSchemaError } from '../../simulation/runner/lib/schema.mjs';

const HELP = `GymNote UX 시뮬레이션 실행기 (dry-run 전용)

사용법:
  node scripts/ux-sim/run.mjs --dry-run [옵션]
  node scripts/ux-sim/run.mjs --validate-only [옵션]

모드:
  --dry-run              입력을 검증하고 persona×scenario×반복 실행 계획,
                         not-run 세션 JSON, Markdown 요약을 만든다.
                         모델 호출·앱 조작을 하지 않는다(model=null, requests=0).
  --validate-only        입력 검증만 하고 파일을 쓰지 않는다.
  live 모델 호출과 앱 자동 조작은 아직 구현하지 않았다.

입력 (작업 루트 기준 상대 경로, 루트 밖·심볼릭 링크는 거부):
  --personas <폴더|파일>  기본 ${DEFAULT_INPUTS.personas}
  --scenarios <폴더|파일> 기본 ${DEFAULT_INPUTS.scenarios}
  --captures <파일>       기본 ${DEFAULT_INPUTS.captures}
  --examples             세 입력을 계약 예시로 바꾼다
                         (${EXAMPLE_INPUTS.personas} 등)
  --root <폴더>          작업 루트. 기본은 이 저장소 루트

실행 계획과 출력:
  --repeat <n>           persona/scenario 조합별 반복 수, 1~${MAX_REPEAT}, 기본 3
                         (persona 4 × scenario 5 × 3 = 합성 세션 60개)
  --run-id <id>          소문자·숫자·'-' 3~80자. 기본 dry-<UTC 시각>-<코드 SHA 7자>
  --out-dir <폴더>       ${RUNS_DIR}/ 아래만 허용, 기본 ${RUNS_DIR}
                         결과: <out-dir>/<run-id>/{run.json,plan.json,summary.md,sessions/*.json}
                         같은 run-id가 있으면 덮어쓰지 않고 실패한다.
  --prompt-version <v>   기본 v1 (simulation/prompts/{user,planner}-<v>.md 해시 기록)
  --json                 결과를 JSON 한 줄로 출력
  -h, --help             이 도움말

종료 코드: 0 성공, 1 입력 검증·경로·덮어쓰기 오류, 2 사용법 오류
`;

function fail(code, message, details = []) {
  process.stderr.write(`오류: ${message}\n`);
  for (const d of details) process.stderr.write(`  - ${d}\n`);
  process.exit(code);
}

let args;
try {
  ({ values: args } = parseArgs({
    options: {
      help: { type: 'boolean', short: 'h' },
      'dry-run': { type: 'boolean' },
      'validate-only': { type: 'boolean' },
      examples: { type: 'boolean' },
      root: { type: 'string' },
      personas: { type: 'string' },
      scenarios: { type: 'string' },
      captures: { type: 'string' },
      repeat: { type: 'string' },
      'run-id': { type: 'string' },
      'out-dir': { type: 'string' },
      'prompt-version': { type: 'string' },
      json: { type: 'boolean' },
    },
    strict: true,
    allowPositionals: false,
  }));
} catch (err) {
  fail(2, `${err.message}\n--help 로 사용법을 확인한다.`);
}

if (args.help) {
  process.stdout.write(HELP);
  process.exit(0);
}
if (args['dry-run'] === args['validate-only']) {
  fail(2, '--dry-run 또는 --validate-only 중 하나를 지정한다. live 실행은 아직 구현하지 않았다.');
}
let repeat;
if (args.repeat !== undefined) {
  if (!/^\d+$/.test(args.repeat)) fail(2, `--repeat 는 정수여야 한다: ${args.repeat}`);
  repeat = Number(args.repeat);
}

const options = {
  root: args.root,
  examples: args.examples ?? false,
  personas: args.personas,
  scenarios: args.scenarios,
  captures: args.captures,
  repeat,
  runId: args['run-id'],
  outDir: args['out-dir'],
  promptVersion: args['prompt-version'],
};

try {
  if (args['validate-only']) {
    const p = prepare(options);
    const result = {
      ok: true,
      mode: 'validate-only',
      personas: p.personas.items.length,
      scenarios: p.scenarios.items.length,
      repeat: p.repeat,
      plannedSessions: p.personas.items.length * p.scenarios.items.length * p.repeat,
      captures: p.manifest.captures.length,
      warnings: p.warnings,
    };
    if (args.json) process.stdout.write(`${JSON.stringify(result)}\n`);
    else {
      process.stdout.write(`입력 검증 통과: persona ${result.personas}, scenario ${result.scenarios}, 반복 ${result.repeat} → 계획 가능한 합성 세션 ${result.plannedSessions}개. 파일을 쓰지 않았다.\n`);
      for (const w of result.warnings) process.stdout.write(`경고: ${w}\n`);
    }
  } else {
    const r = runDry(options);
    const result = { ok: true, mode: 'dry-run', runId: r.runId, runDir: r.relativeRunDir, sessions: r.sessionCount, modelRequests: 0, warnings: r.warnings };
    if (args.json) process.stdout.write(`${JSON.stringify(result)}\n`);
    else {
      process.stdout.write(`dry-run 완료: ${r.relativeRunDir} (합성 세션 ${r.sessionCount}개, 모두 not-run/not-evaluated, 모델 요청 0)\n`);
      for (const w of r.warnings) process.stdout.write(`경고: ${w}\n`);
    }
  }
} catch (err) {
  if (err instanceof RunnerError) {
    fail(err.code === 'usage' ? 2 : 1, `[${err.code}] ${err.message}`, err.details ?? []);
  }
  if (err instanceof UnsupportedSchemaError) {
    fail(1, `[contract-unsupported] 계약 스키마에 실행기가 지원하지 않는 키워드가 있다. 검증기를 먼저 갱신해야 한다: ${err.message}`);
  }
  throw err;
}
