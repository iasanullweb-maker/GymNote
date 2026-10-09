// 세션 상태 판정 규칙과 스키마 부분 집합 검증기.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, test } from 'node:test';
import { CONTRACTS_DIR, loadSchema } from '../lib/inputs.mjs';
import { UnsupportedSchemaError, assertSupportedSchema, validate } from '../lib/schema.mjs';
import { assessSession, buildDryRunSession } from '../lib/session.mjs';
import { persona, scenario } from './helpers.mjs';

const sc = scenario('scenario-1');
const base = () => buildDryRunSession({
  runId: 'unit', persona: persona('persona-1'), scenario: sc, iteration: 1, appCommit: null, promptVersion: 'v1',
});

/** 후속 모드의 가상 완료 세션(테스트 전용 합성 값). */
function completed(mode, checks, outcome) {
  return {
    ...base(),
    mode,
    model: 'synthetic-model',
    status: 'completed',
    outcome,
    observations: [{ step: 1, captureId: 'records-overview', action: 'inspect', note: '합성 관찰' }],
    checks,
    usage: { requests: 1, inputTokens: 10, outputTokens: 5 },
  };
}
const ev = ['simulation/capture/images/records-overview.png'];

describe('dry-run 세션', () => {
  test('생성한 dry-run 세션은 계약과 판정 규칙을 통과한다', () => {
    assert.deepEqual(assessSession(base(), sc, { personaId: 'persona-1' }), []);
  });

  test('계약 examples/session.json 도 판정 규칙을 통과한다', () => {
    const example = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'examples', 'session.json'), 'utf8'));
    const exampleScenario = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'examples', 'scenario.json'), 'utf8'));
    assert.deepEqual(assessSession(example, exampleScenario), []);
  });

  test('dry-run 을 성공·완료·모델 호출로 꾸민 경우를 거부한다', () => {
    const cases = [
      [{ outcome: 'success' }, /not-run 이면 outcome=not-evaluated/],
      [{ status: 'completed' }, /dry-run 은 status=not-run/],
      [{ model: 'synthetic-model' }, /model=null/],
      [{ usage: { requests: 1, inputTokens: 0, outputTokens: 0 } }, /usage.requests=0/],
      [{ usage: { requests: 0, inputTokens: 12, outputTokens: 0 } }, /토큰 사용량/],
      [{ observations: [{ step: 1, captureId: 'records-overview', action: 'inspect', note: '지어낸 관찰' }] }, /관찰 기록이 있다/],
    ];
    for (const [patch, pattern] of cases) {
      const errors = assessSession({ ...base(), ...patch }, sc);
      assert.ok(errors.some((e) => pattern.test(e)), `${JSON.stringify(patch)} → ${errors.join(' / ')}`);
    }
  });

  test('not-run 세션에서 pass 판정이나 증거 없는 판정을 거부한다', () => {
    const s = base();
    s.checks[0] = { id: 'entry-found', result: 'pass', evidence: [] };
    const errors = assessSession(s, sc);
    assert.ok(errors.some((e) => /증거 경로가 없다/.test(e)));
    assert.ok(errors.some((e) => /판정된 검사가 있다/.test(e)));
  });
});

describe('검사 목록 일치', () => {
  test('누락·미지·중복 검사를 거부한다', () => {
    const missing = base();
    missing.checks.pop();
    assert.ok(assessSession(missing, sc).some((e) => /'human-check' 결과 누락/.test(e)));

    const unknown = base();
    unknown.checks.push({ id: 'invented', result: 'not-evaluated', evidence: [] });
    assert.ok(assessSession(unknown, sc).some((e) => /시나리오에 없는 검사 'invented'/.test(e)));

    const dup = base();
    dup.checks.push({ ...dup.checks[0] });
    assert.ok(assessSession(dup, sc).some((e) => /중복/.test(e)));
  });

  test('persona·scenario 불일치를 거부한다', () => {
    assert.ok(assessSession(base(), sc, { personaId: 'persona-2' }).some((e) => /personaId/.test(e)));
    assert.ok(assessSession(base(), scenario('scenario-9')).some((e) => /scenarioId/.test(e)));
  });
});

describe('화면 기반 평가(screen-review) 판정', () => {
  const checks = (saved, human = 'not-evaluated') => [
    { id: 'entry-found', result: 'pass', evidence: ev },
    { id: 'saved', result: saved, evidence: saved === 'not-evaluated' ? [] : ev },
    { id: 'human-check', result: human, evidence: human === 'not-evaluated' ? [] : ev },
  ];

  test('관찰 검사만 판정하고 app-state 는 not-evaluated 로 둔 세션은 통과한다', () => {
    assert.deepEqual(assessSession(completed('screen-review', checks('not-evaluated'), 'success'), sc), []);
  });

  test('스크린샷만으로 app-state 를 pass/fail 처리하면 거부한다', () => {
    for (const r of ['pass', 'fail']) {
      const errors = assessSession(completed('screen-review', checks(r), r === 'pass' ? 'success' : 'failure'), sc);
      assert.ok(errors.some((e) => /screen-review에서는 app-state 검사 'saved'/.test(e)), errors.join(' / '));
    }
  });

  test('manual 검사는 어떤 모드에서도 자동 판정하지 않는다', () => {
    const errors = assessSession(completed('scripted-native', checks('pass', 'pass'), 'success'), sc);
    assert.ok(errors.some((e) => /manual 검사 'human-check'/.test(e)));
  });

  test('scripted-native 는 증거가 있으면 app-state 를 판정할 수 있다', () => {
    assert.deepEqual(assessSession(completed('scripted-native', checks('pass'), 'success'), sc), []);
  });
});

describe('outcome 일관성', () => {
  const allPassish = [
    { id: 'entry-found', result: 'pass', evidence: ev },
    { id: 'saved', result: 'not-evaluated', evidence: [] },
    { id: 'human-check', result: 'not-evaluated', evidence: [] },
  ];

  test('실패 검사가 있는데 success, 실패 근거 없이 failure 를 거부한다', () => {
    const withFail = allPassish.map((c) => (c.id === 'entry-found' ? { ...c, result: 'fail' } : c));
    assert.ok(assessSession(completed('screen-review', withFail, 'success'), sc).some((e) => /outcome=success/.test(e)));
    assert.ok(assessSession(completed('screen-review', allPassish, 'failure'), sc).some((e) => /outcome=failure/.test(e)));
  });

  test('pass 근거 없이 success 를 거부한다', () => {
    const none = allPassish.map((c) => ({ ...c, result: 'not-evaluated', evidence: [] }));
    assert.ok(assessSession(completed('screen-review', none, 'success'), sc).some((e) => /통과한 검사 근거 없이/.test(e)));
  });

  test('blocked/error 상태에서 success 를 거부한다', () => {
    const s = { ...completed('screen-review', allPassish, 'success'), status: 'error' };
    assert.ok(assessSession(s, sc).some((e) => /status=completed 에서만/.test(e)));
  });

  test('관찰 단계 순서·화면·행동·maxSteps 를 검사한다', () => {
    const s = completed('screen-review', allPassish, 'inconclusive');
    s.observations = [
      { step: 2, captureId: 'friends-home', action: 'tap', note: '합성' },
    ];
    const errors = assessSession(s, scenario('scenario-1', { allowedActionTypes: ['inspect', 'stop'] }));
    assert.ok(errors.some((e) => /step 은 1/.test(e)));
    assert.ok(errors.some((e) => /시나리오에 없는 화면 'friends-home'/.test(e)));
    assert.ok(errors.some((e) => /허용되지 않은 행동 'tap'/.test(e)));

    const long = completed('screen-review', allPassish, 'inconclusive');
    long.observations = Array.from({ length: 11 }, (_, i) => ({ step: i + 1, captureId: 'records-overview', action: 'inspect', note: '합성' }));
    assert.ok(assessSession(long, sc).some((e) => /maxSteps/.test(e)));
  });
});

describe('스키마 부분 집합 검증기', () => {
  test('계약 스키마 4개는 지원 키워드만 사용한다', () => {
    for (const name of ['persona', 'scenario', 'capture-manifest', 'session']) {
      assert.doesNotThrow(() => loadSchema(name));
    }
  });

  test('지원하지 않는 키워드가 추가되면 조용히 무시하지 않는다', () => {
    assert.throws(() => assertSupportedSchema({ type: 'object', properties: { a: { format: 'date-time' } } }), UnsupportedSchemaError);
    assert.throws(() => assertSupportedSchema({ oneOf: [] }), UnsupportedSchemaError);
    assert.throws(() => assertSupportedSchema({ additionalProperties: true }), UnsupportedSchemaError);
  });

  test('타입별 키워드는 해당 타입에만 적용한다(nullable SHA)', () => {
    const schema = { type: ['string', 'null'], pattern: '^[0-9a-f]{40}$' };
    assert.deepEqual(validate(schema, null), []);
    assert.deepEqual(validate(schema, 'a'.repeat(40)), []);
    assert.equal(validate(schema, 'xyz').length, 1);
    assert.equal(validate({ type: 'integer' }, 1.5).length, 1);
    assert.equal(validate({ type: 'object' }, []).length, 1);
  });

  test('if/then 은 조건이 맞을 때만 적용한다', () => {
    const schema = loadSchema('capture-manifest').properties.captures.items;
    const pending = { id: 'workout-ready', status: 'pending', width: 1, height: 1, textScale: 'standard' };
    assert.deepEqual(validate(schema, pending), []);
    assert.ok(validate(schema, { ...pending, status: 'captured' }).some((e) => /relativePath/.test(e)));
  });
});
