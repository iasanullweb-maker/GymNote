// CLI 단위 시나리오: dry-run 계획·출력·덮어쓰기·경로 제한.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { assessSession } from '../lib/session.mjs';
import { CLI, cleanEnv, makeRoot, run, scenario } from './helpers.mjs';

const roots = [];
const fresh = (opts) => { const r = makeRoot(opts); roots.push(r); return r; };
after(() => roots.forEach((r) => r.cleanup()));

const readJson = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

describe('도움말과 사용법', () => {
  test('--help 는 0으로 끝나고 주요 옵션을 설명한다', () => {
    const r = spawnSync(process.execPath, [CLI, '--help'], { encoding: 'utf8', env: cleanEnv() });
    assert.equal(r.status, 0);
    for (const opt of ['--dry-run', '--personas', '--scenarios', '--captures', '--repeat', '--out-dir', '--run-id']) {
      assert.match(r.stdout, new RegExp(opt));
    }
  });

  test('모드 없이 실행하면 사용법 오류(2)이고 아무것도 쓰지 않는다', () => {
    const { root } = fresh();
    const r = run(root);
    assert.equal(r.code, 2);
    assert.equal(fs.existsSync(path.join(root, 'simulation', 'runs')), false);
  });

  test('알 수 없는 옵션과 잘못된 반복 수는 거부한다', () => {
    const { root } = fresh();
    assert.equal(run(root, '--dry-run', '--live').code, 2);
    assert.equal(run(root, '--dry-run', '--repeat', '0').code, 2);
    assert.equal(run(root, '--dry-run', '--repeat', '11').code, 2);
    assert.equal(run(root, '--dry-run', '--repeat', '2.5').code, 2);
  });
});

describe('dry-run 계획과 출력', () => {
  test('4×5×3 = 60개 not-run 세션, plan, run, summary를 만든다', () => {
    const { root } = fresh();
    const r = run(root, '--dry-run', '--run-id', 'plan-60', '--json');
    assert.equal(r.code, 0, r.stderr);
    const out = JSON.parse(r.stdout);
    assert.equal(out.sessions, 60);
    assert.equal(out.modelRequests, 0);

    const dir = path.join(root, 'simulation', 'runs', 'plan-60');
    const sessions = fs.readdirSync(path.join(dir, 'sessions'));
    assert.equal(sessions.length, 60);
    const plan = readJson(path.join(dir, 'plan.json'));
    assert.equal(plan.entries.length, 60);
    assert.equal(new Set(plan.entries.map((e) => `${e.personaId}/${e.scenarioId}/${e.iteration}`)).size, 60);

    const sc = scenario('scenario-1');
    for (const file of sessions) {
      const s = readJson(path.join(dir, 'sessions', file));
      assert.equal(s.status, 'not-run');
      assert.equal(s.outcome, 'not-evaluated');
      assert.equal(s.model, null);
      assert.equal(s.usage.requests, 0);
      assert.deepEqual(s.observations, []);
      assert.ok(s.checks.every((c) => c.result === 'not-evaluated' && c.evidence.length === 0));
      if (s.scenarioId === 'scenario-1') assert.deepEqual(assessSession(s, sc, { personaId: s.personaId }), []);
    }

    const runJson = readJson(path.join(dir, 'run.json'));
    assert.equal(runJson.plan.sessionCount, 60);
    assert.equal(runJson.execution.modelRequests, 0);
    assert.equal(runJson.inputs.personas.length, 4);
    assert.ok(runJson.inputs.personas.every((p) => /^[0-9a-f]{64}$/.test(p.sha256)));
    assert.match(runJson.inputs.captureManifest.sha256, /^[0-9a-f]{64}$/);
    assert.equal(runJson.code.status, 'unavailable'); // 임시 루트는 Git 저장소가 아니다
    assert.equal(runJson.code.commit, null);
    assert.ok(runJson.notRunChecks.every((c) => c.result === 'not-evaluated'));

    const md = fs.readFileSync(path.join(dir, 'summary.md'), 'utf8');
    assert.match(md, /계획된 합성 세션 \| 60/);
    assert.match(md, /실행된 세션 \| 0/);
    assert.match(md, /pending — 이미지 없음/);
    assert.match(md, /사람 검증이 필요/);
    assert.match(md, /실제 사용자 수·비율·만족도·작업 소요시간이 아니다/);
    assert.match(md, /실행 결과가 없어 문제나 개선안을 작성하지 않았다/);
    assert.doesNotMatch(md, /\| (pass|success) \|/);
  });

  test('계약 examples만으로 검증·dry-run 할 수 있다', () => {
    // 저장소의 계약 examples를 읽으므로 --root 없이 실행하되 출력은 별도 out-dir 대신 validate-only로 확인한다.
    const r = spawnSync(process.execPath, [CLI, '--validate-only', '--examples', '--json'], { encoding: 'utf8', env: cleanEnv() });
    assert.equal(r.status, 0, r.stderr);
    const out = JSON.parse(r.stdout);
    assert.equal(out.plannedSessions, 3);
  });

  test('--validate-only 는 파일을 쓰지 않는다', () => {
    const { root } = fresh();
    assert.equal(run(root, '--validate-only').code, 0);
    assert.equal(fs.existsSync(path.join(root, 'simulation', 'runs')), false);
  });

  test('같은 run-id 로 다시 실행하면 거부하고 기존 결과를 바꾸지 않는다', () => {
    const { root } = fresh();
    assert.equal(run(root, '--dry-run', '--run-id', 'same-id').code, 0);
    const file = path.join(root, 'simulation', 'runs', 'same-id', 'run.json');
    const before = fs.readFileSync(file);
    const again = run(root, '--dry-run', '--run-id', 'same-id', '--repeat', '1');
    assert.equal(again.code, 1);
    assert.match(again.stderr, /run-exists/);
    assert.deepEqual(fs.readFileSync(file), before);
  });

  test('잘못된 run-id 형식은 거부한다', () => {
    const { root } = fresh();
    for (const id of ['../x', 'UPPER', 'a/b', 'x']) {
      assert.notEqual(run(root, '--dry-run', '--run-id', id).code, 0, id);
    }
    assert.equal(fs.existsSync(path.join(root, 'x')), false);
  });

  test('출력은 simulation/runs 아래로만 제한한다', () => {
    const { root } = fresh();
    for (const out of ['..', 'simulation', 'simulation/runs-evil', 'simulation/runs/../../outside']) {
      const r = run(root, '--dry-run', '--out-dir', out, '--run-id', 'escape-test');
      assert.equal(r.code, 1, out);
      assert.match(r.stderr, /path-escape/);
    }
    const ok = run(root, '--dry-run', '--out-dir', 'simulation/runs/nightly', '--run-id', 'nested-ok');
    assert.equal(ok.code, 0, ok.stderr);
    assert.ok(fs.existsSync(path.join(root, 'simulation', 'runs', 'nightly', 'nested-ok', 'summary.md')));
  });

  test('검증 실패 시 출력 폴더를 만들지 않는다', () => {
    const { root, write } = fresh();
    write('simulation/scenarios/bad.json', scenario('scenario-1'));
    const r = run(root, '--dry-run', '--run-id', 'no-output');
    assert.equal(r.code, 1);
    assert.equal(fs.existsSync(path.join(root, 'simulation', 'runs', 'no-output')), false);
  });
});

describe('Git 코드 SHA 기록', () => {
  const git = spawnSync('git', ['--version']);
  test('Git 저장소 루트면 실제 HEAD SHA를 appCommit 으로 남긴다', { skip: git.status !== 0 && 'git 없음' }, () => {
    const { root } = fresh();
    // GIT_* 를 제거한 환경에서만 실행해 실제 저장소를 건드리지 않는다.
    const env = cleanEnv();
    const g = (...a) => spawnSync('git', ['-C', root, ...a], { encoding: 'utf8', env });
    assert.notEqual(g('rev-parse', '--git-dir').status, 0, '임시 루트가 이미 Git 저장소 안에 있으면 중단한다');
    assert.equal(g('init', '-q').status, 0);
    assert.equal(fs.realpathSync(g('rev-parse', '--show-toplevel').stdout.trim()), fs.realpathSync(root));
    g('add', '-A');
    const c = g('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-q', '-m', 'synthetic');
    assert.equal(c.status, 0, c.stderr);
    const head = g('rev-parse', 'HEAD').stdout.trim();
    assert.equal(run(root, '--dry-run', '--run-id', 'git-sha', '--repeat', '1').code, 0);
    const dir = path.join(root, 'simulation', 'runs', 'git-sha');
    const runJson = readJson(path.join(dir, 'run.json'));
    assert.equal(runJson.code.commit, head);
    assert.equal(runJson.code.dirty, false);
    const first = fs.readdirSync(path.join(dir, 'sessions'))[0];
    assert.equal(readJson(path.join(dir, 'sessions', first)).appCommit, head);
  });
});
