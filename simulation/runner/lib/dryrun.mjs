// 입력 검증 → 실행 계획 → dry-run 세션·보고서 작성.
import fs from 'node:fs';
import path from 'node:path';
import {
  CODE_ROOT, crossCheck, hashPrompts, loadCaptureManifest, loadPersonas, loadScenarios, variantKey,
} from './inputs.mjs';
import { RunnerError, assertNoLinks, isInside, realRoot, toPosixRelative } from './paths.mjs';
import { readCodeCommit } from './git.mjs';
import { assessSession, buildDryRunSession, sessionKey } from './session.mjs';
import { renderSummary } from './report.mjs';

export const RUNNER_VERSION = '0.1.0';
export const RUN_ID_PATTERN = /^[a-z0-9][a-z0-9-]{2,79}$/;
export const PROMPT_VERSION_PATTERN = /^[a-z0-9][a-z0-9.-]{0,31}$/;
export const MAX_REPEAT = 10;

export const DEFAULT_INPUTS = Object.freeze({
  personas: 'simulation/personas',
  scenarios: 'simulation/scenarios',
  captures: 'simulation/capture/manifest.json',
});
export const EXAMPLE_INPUTS = Object.freeze({
  personas: 'simulation/contracts/examples/persona.json',
  scenarios: 'simulation/contracts/examples/scenario.json',
  captures: 'simulation/contracts/examples/capture-manifest.json',
});
export const RUNS_DIR = 'simulation/runs';

export const BOUNDARIES = Object.freeze([
  'live 모델 호출: 구현하지 않음. 후속 어댑터는 persona·현재 화면 이미지·userGoal만 사용자 입력으로 받고, checks·코드·미래 화면은 받지 않는다.',
  '앱 자동 조작(scripted-native/agent-native): 구현하지 않음. 실제 실행 전·후 저장 스냅샷을 app-state 검사 증거로 넘겨야 한다.',
  'screen-review: 구현하지 않음. 구현 시에도 app-state·manual 검사는 not-evaluated로 남긴다(assessSession이 강제).',
  '후속 단계가 만든 세션은 assessSession()으로 같은 판정 규칙을 통과해야 저장한다.',
]);

function ensureVersionWarning() {
  const major = Number(process.versions.node.split('.')[0]);
  return major >= 24 ? null : `Node ${process.versions.node}에서 실행됨. 지원 기준은 Node 24 이상이며 이 버전에서의 동작은 보증하지 않는다.`;
}

/** 입력을 읽고 모든 검사를 수행한다. 오류가 하나라도 있으면 RunnerError(validation)를 던진다. */
export function prepare(options) {
  const root = realRoot(options.root ?? CODE_ROOT);
  const inputs = { ...(options.examples ? EXAMPLE_INPUTS : DEFAULT_INPUTS) };
  for (const key of ['personas', 'scenarios', 'captures']) if (options[key]) inputs[key] = options[key];

  const repeat = options.repeat ?? 3;
  if (!Number.isInteger(repeat) || repeat < 1 || repeat > MAX_REPEAT) {
    throw new RunnerError('usage', `--repeat 는 1~${MAX_REPEAT} 정수여야 한다`);
  }
  const promptVersion = options.promptVersion ?? 'v1';
  if (!PROMPT_VERSION_PATTERN.test(promptVersion)) {
    throw new RunnerError('usage', `--prompt-version 형식이 잘못됐다: ${promptVersion}`);
  }

  const personas = loadPersonas(root, inputs.personas);
  const scenarios = loadScenarios(root, inputs.scenarios);
  const manifest = loadCaptureManifest(root, inputs.captures);
  const errors = [...personas.errors, ...scenarios.errors, ...manifest.errors];
  if (errors.length === 0) errors.push(...crossCheck(scenarios, manifest));
  if (errors.length > 0) {
    const err = new RunnerError('validation', `입력 검증 실패 (${errors.length}건)`);
    err.details = errors;
    throw err;
  }
  const warnings = [...manifest.warnings];
  const versionWarning = ensureVersionWarning();
  if (versionWarning) warnings.push(versionWarning);

  const code = readCodeCommit(root);
  if (code.status === 'unavailable') warnings.push(`실행 코드 SHA를 확인하지 못해 appCommit=null로 기록한다: ${code.reason}`);
  const captureCommit = manifest.item.data.appCommit;
  if (captureCommit && code.commit && captureCommit !== code.commit) {
    warnings.push(`캡처 appCommit(${captureCommit})과 실행 코드 SHA(${code.commit})가 다르다. 화면과 코드 버전을 함께 확인해야 한다`);
  }
  return {
    root, inputs, repeat, promptVersion, personas, scenarios, manifest, code, warnings,
    prompts: hashPrompts(root, promptVersion),
  };
}

function defaultRunId(now, code) {
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'z').toLowerCase();
  return `dry-${stamp}-${code.commit ? code.commit.slice(0, 7) : 'nogit'}`;
}

/** 출력 폴더는 <root>/simulation/runs 아래로 제한하고, 기존 run-id는 덮어쓰지 않는다. */
function createRunDir(root, outDir, runId) {
  const runsRoot = path.join(root, ...RUNS_DIR.split('/'));
  const base = path.resolve(root, outDir ?? RUNS_DIR);
  if (!isInside(runsRoot, base)) {
    throw new RunnerError('path-escape', `출력은 ${RUNS_DIR}/ 아래로만 쓸 수 있다 (${outDir})`);
  }
  assertNoLinks(root, base, '출력 경로');
  fs.mkdirSync(base, { recursive: true });
  assertNoLinks(root, base, '출력 경로');
  const runDir = path.join(base, runId);
  try {
    fs.mkdirSync(runDir); // recursive 없이: 이미 있으면 EEXIST
  } catch (err) {
    if (err.code === 'EEXIST') {
      throw new RunnerError('run-exists', `이미 있는 run-id 다. 덮어쓰지 않는다: ${toPosixRelative(root, runDir)}`);
    }
    throw err;
  }
  fs.mkdirSync(path.join(runDir, 'sessions'));
  return runDir;
}

function writeNew(file, text) {
  fs.writeFileSync(file, text, { encoding: 'utf8', flag: 'wx' });
}

/** dry-run을 수행하고 생성한 파일 위치와 수량을 돌려준다. */
export function runDry(options) {
  const p = prepare(options);
  const now = options.now ?? new Date();
  const runId = options.runId ?? defaultRunId(now, p.code);
  if (!RUN_ID_PATTERN.test(runId)) {
    throw new RunnerError('usage', `run-id 는 소문자·숫자·'-' 3~80자여야 한다: ${runId}`);
  }

  const variant = p.manifest.variant;
  const plannedCaptures = p.manifest.captures.filter((c) => variantKey(c) === variantKey(variant));
  const captureById = new Map(plannedCaptures.map((c) => [c.id, c]));

  // 모든 세션을 메모리에서 먼저 만들고 검사한다. 하나라도 규칙을 어기면 아무것도 쓰지 않는다.
  const sessions = [];
  const entries = [];
  for (const persona of p.personas.items.map((i) => i.data)) {
    for (const scenario of p.scenarios.items.map((i) => i.data)) {
      for (let iteration = 1; iteration <= p.repeat; iteration += 1) {
        const session = buildDryRunSession({
          runId, persona, scenario, iteration, appCommit: p.code.commit, promptVersion: p.promptVersion,
        });
        const problems = assessSession(session, scenario, { personaId: persona.id });
        if (problems.length > 0) {
          throw new RunnerError('internal', `생성한 세션이 판정 규칙을 어긴다: ${problems.join('; ')}`);
        }
        const file = `sessions/${sessionKey(persona.id, scenario.id, iteration)}.json`;
        sessions.push({ file, session });
        entries.push({
          index: entries.length + 1,
          sessionFile: file,
          personaId: persona.id,
          scenarioId: scenario.id,
          iteration,
          startCaptureId: scenario.startCaptureId,
          captures: scenario.captureIds.map((id) => ({
            id,
            status: captureById.get(id)?.status ?? 'missing-variant',
            evidencePath: captureById.get(id)?.evidencePath ?? null,
          })),
          status: 'not-run',
        });
      }
    }
  }

  const run = {
    runnerFormat: 1,
    runId,
    mode: 'dry-run',
    synthetic: true,
    createdAt: now.toISOString(),
    generator: { name: 'gymnote-ux-sim-runner', version: RUNNER_VERSION, node: process.versions.node },
    code: p.code,
    promptVersion: p.promptVersion,
    prompts: p.prompts,
    inputs: {
      personas: p.personas.items.map((i) => ({ id: i.data.id, path: i.rel, sha256: i.sha256 })),
      scenarios: p.scenarios.items.map((i) => ({ id: i.data.id, path: i.rel, sha256: i.sha256 })),
      captureManifest: {
        path: p.manifest.item.rel, sha256: p.manifest.item.sha256, appCommit: p.manifest.item.data.appCommit,
      },
    },
    captureVariant: variant,
    captures: p.manifest.captures,
    plan: {
      repeat: p.repeat,
      personaCount: p.personas.items.length,
      scenarioCount: p.scenarios.items.length,
      sessionCount: sessions.length,
    },
    execution: { executedSessions: 0, modelRequests: 0, appAutomation: 'not-run', liveModel: 'not-implemented' },
    notRunChecks: p.scenarios.items.flatMap((i) => i.data.checks.map((c) => ({
      scenarioId: i.data.id,
      checkId: c.id,
      kind: c.kind,
      result: 'not-evaluated',
      reason: c.kind === 'app-state'
        ? 'dry-run: 앱 실행·저장 스냅샷 없음'
        : c.kind === 'manual' ? 'dry-run: 사람 확인 필요, 수행 안 함' : 'dry-run: 가상 사용자 관찰 없음',
    }))),
    boundaries: BOUNDARIES,
    warnings: p.warnings,
  };
  const plan = { runId, sessionCount: entries.length, entries };

  const runDir = createRunDir(p.root, options.outDir, runId);
  writeNew(path.join(runDir, 'run.json'), `${JSON.stringify(run, null, 2)}\n`);
  writeNew(path.join(runDir, 'plan.json'), `${JSON.stringify(plan, null, 2)}\n`);
  for (const { file, session } of sessions) {
    writeNew(path.join(runDir, ...file.split('/')), `${JSON.stringify(session, null, 2)}\n`);
  }
  writeNew(path.join(runDir, 'summary.md'), renderSummary(run, plan));

  return { runId, runDir, relativeRunDir: toPosixRelative(p.root, runDir), sessionCount: sessions.length, warnings: p.warnings };
}
