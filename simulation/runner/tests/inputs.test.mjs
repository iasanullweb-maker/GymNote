// 입력 계약 검증: ID, 성공 조건, capture 변형, PNG/SHA, 경로 탈출, 심볼릭 링크, 민감 정보.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { FIXED_CAPTURE_IDS } from '../lib/inputs.mjs';
import {
  PNG_BYTES, canSymlink, makeRoot, manifest, persona, run, scenario, sha,
} from './helpers.mjs';

const roots = [];
const fresh = (opts) => { const r = makeRoot(opts); roots.push(r); return r; };
after(() => roots.forEach((r) => r.cleanup()));

function expectReject(root, pattern, ...extra) {
  const r = run(root, '--validate-only', ...extra);
  assert.equal(r.code, 1, `거부돼야 한다\n${r.stdout}`);
  assert.match(r.stderr, pattern);
  return r;
}

const pendingAll = () => FIXED_CAPTURE_IDS.map((id) => ({ id, status: 'pending', width: 834, height: 1194, textScale: 'standard' }));

describe('persona / scenario 계약', () => {
  test('중복 persona ID 를 거부한다', () => {
    const { root, write } = fresh();
    write('simulation/personas/dup.json', persona('persona-1'));
    expectReject(root, /persona ID 중복 'persona-1'/);
  });

  test('중복 scenario ID 를 거부한다', () => {
    const { root, write } = fresh();
    write('simulation/scenarios/dup.json', scenario('scenario-2'));
    expectReject(root, /scenario ID 중복 'scenario-2'/);
  });

  test('스키마 위반(누락 필드·추가 필드·잘못된 enum·kebab-case 아님)을 거부한다', () => {
    const cases = [
      [{ ...persona('persona-1'), synthetic: false }, /synthetic: 값은 true/],
      [(() => { const p = persona('persona-1'); delete p.goals; return p; })(), /필수 필드 'goals'/],
      [{ ...persona('persona-1'), email: 'x' }, /허용되지 않은 필드 'email'/],
      [{ ...persona('persona-1'), attention: 'busy' }, /attention: 허용 값/],
      [persona('Persona_1'), /id: 형식/],
    ];
    for (const [data, pattern] of cases) {
      const { root, write } = fresh();
      write('simulation/personas/p1.json', data);
      expectReject(root, pattern);
    }
  });

  test('성공 조건(checks)이 없거나 비어 있으면 거부한다', () => {
    for (const [checks, pattern] of [
      [[], /checks: 항목이 1개 이상/],
      [[{ id: 'blank', kind: 'app-state', description: '   ' }], /성공 조건 설명이 비어 있다/],
      [[{ id: 'same', kind: 'manual', description: 'a' }, { id: 'same', kind: 'manual', description: 'b' }], /검사 ID 중복 'same'/],
      [[{ id: 'x', kind: 'guess', description: 'a' }], /kind: 허용 값/],
    ]) {
      const { root, write } = fresh();
      write('simulation/scenarios/s1.json', scenario('scenario-1', { checks }));
      expectReject(root, pattern);
    }
    const { root, write } = fresh();
    const s = scenario('scenario-1');
    delete s.checks;
    write('simulation/scenarios/s1.json', s);
    expectReject(root, /필수 필드 'checks'/);
  });

  test('unknown capture ID 와 startCaptureId 불일치를 거부한다', () => {
    let { root, write } = fresh();
    write('simulation/scenarios/s1.json', scenario('scenario-1', { captureIds: ['records-overview', 'settings-home'] }));
    expectReject(root, /capture manifest에 없는 capture ID 'settings-home'/);

    ({ root, write } = fresh());
    write('simulation/scenarios/s1.json', scenario('scenario-1', { startCaptureId: 'plan-month' }));
    expectReject(root, /startCaptureId 'plan-month'가 captureIds에 없다/);
  });

  test('maxSteps 범위와 fixtureId 상수를 검사한다', () => {
    let { root, write } = fresh();
    write('simulation/scenarios/s1.json', scenario('scenario-1', { maxSteps: 41 }));
    expectReject(root, /maxSteps: 40 이하/);
    ({ root, write } = fresh());
    write('simulation/scenarios/s1.json', scenario('scenario-1', { fixtureId: 'demo-v2' }));
    expectReject(root, /fixtureId: 값은 "demo-v1"/);
  });

  test('JSON 문법 오류는 파일 이름과 함께 거부한다', () => {
    const { root, write } = fresh();
    write('simulation/personas/p2.json', '{ "id": ');
    expectReject(root, /simulation\/personas\/p2\.json: JSON 형식 오류/);
  });

  test('토큰·이메일·전화번호처럼 보이는 입력을 거부한다(합성 데이터만 허용)', () => {
    const samples = [
      'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.c2lnbmF0dXJl',
      'sk-SYNTHETICabcdefghijklmnop',
      'contact me at someone@example.com',
      '연락처 010-1234-5678',
    ];
    for (const value of samples) {
      const { root, write } = fresh();
      write('simulation/personas/p1.json', persona('persona-1', { context: value }));
      expectReject(root, /합성 데이터만 입력한다/);
    }
  });

  test('폴더 입력은 바로 아래 *.json 만 읽고 README·하위 폴더는 무시한다', () => {
    const { root, write } = fresh();
    write('simulation/scenarios/tests/broken.json', '{ not json');
    const r = run(root, '--validate-only', '--json');
    assert.equal(r.code, 0, r.stderr);
    assert.equal(JSON.parse(r.stdout).scenarios, 5);
  });

  test('없는 입력 파일은 missing-file 로 거부한다', () => {
    const { root } = fresh();
    expectReject(root, /missing-file/, '--captures', 'simulation/capture/none.json');
    fs.rmSync(path.join(root, 'simulation', 'personas'), { recursive: true });
    expectReject(root, /missing-file/);
  });
});

describe('capture manifest', () => {
  test('pending 10개는 통과하고 이미지가 없어도 captured 로 취급하지 않는다', () => {
    const { root } = fresh();
    const r = run(root, '--dry-run', '--run-id', 'pending-only', '--json');
    assert.equal(r.code, 0, r.stderr);
    const runJson = JSON.parse(fs.readFileSync(path.join(root, 'simulation', 'runs', 'pending-only', 'run.json'), 'utf8'));
    assert.ok(runJson.captures.every((c) => c.status === 'pending' && c.evidencePath === null));
  });

  test('계약에 없는 capture ID 를 거부한다', () => {
    const { root } = fresh({ captures: [...pendingAll(), { id: 'settings-home', status: 'pending', width: 834, height: 1194, textScale: 'standard' }] });
    expectReject(root, /계약에 없는 capture ID/);
  });

  test('같은 ID 는 크기·글씨 변형으로 구분하고, 같은 조합 중복은 거부한다', () => {
    const variant = { id: 'workout-ready', status: 'pending', width: 834, height: 1194, textScale: 'accessibility' };
    const ok = fresh({ captures: [...pendingAll(), variant, { ...variant, width: 597 }] });
    assert.equal(run(ok.root, '--validate-only').code, 0);

    const dup = fresh({ captures: [...pendingAll(), pendingAll()[0]] });
    expectReject(dup.root, /같은 ID·크기·글씨 조합이 중복/);
  });

  test('한 변형에 고정 ID 10개가 모두 없으면 거부한다', () => {
    const caps = pendingAll();
    caps[9] = { ...caps[9], textScale: 'accessibility' }; // friends-ranking 을 다른 변형으로 옮김
    const extra = { ...caps[0], id: 'workout-active' }; // 개수는 10 이상 유지
    const { root } = fresh({ captures: [...caps, { ...extra, textScale: 'accessibility' }] });
    expectReject(root, /고정 capture ID 10개를 모두 가진 크기·글씨 변형이 없다/);
  });

  function capturedRoot(entry, png = PNG_BYTES) {
    const caps = pendingAll();
    caps[0] = { ...caps[0], status: 'captured', relativePath: 'images/workout-ready.png', sha256: sha(png), ...entry };
    const r = fresh({ captures: caps });
    if (png) r.write('simulation/capture/images/workout-ready.png', png);
    return r;
  }

  test('captured PNG 가 있고 SHA 가 맞으면 증거 경로를 남긴다', () => {
    const { root } = capturedRoot({});
    assert.equal(run(root, '--dry-run', '--run-id', 'captured-ok').code, 0);
    const runJson = JSON.parse(fs.readFileSync(path.join(root, 'simulation', 'runs', 'captured-ok', 'run.json'), 'utf8'));
    const c = runJson.captures.find((x) => x.id === 'workout-ready');
    assert.equal(c.evidencePath, 'simulation/capture/images/workout-ready.png');
    const md = fs.readFileSync(path.join(root, 'simulation', 'runs', 'captured-ok', 'summary.md'), 'utf8');
    assert.match(md, /captured 1, pending 9/);
  });

  test('captured 인데 PNG 가 없으면 거부한다', () => {
    const caps = pendingAll();
    caps[0] = { ...caps[0], status: 'captured', relativePath: 'images/none.png', sha256: '0'.repeat(64) };
    const { root } = fresh({ captures: caps });
    expectReject(root, /이미지 파일이 없다/);
  });

  test('captured 에 relativePath/sha256 이 없으면 거부한다', () => {
    const caps = pendingAll();
    caps[0] = { ...caps[0], status: 'captured' };
    const { root } = fresh({ captures: caps });
    expectReject(root, /필수 필드 'relativePath'/);
  });

  test('SHA-256 이 다르면 거부한다', () => {
    const { root } = capturedRoot({ sha256: 'a'.repeat(64) });
    expectReject(root, /SHA-256 불일치/);
  });

  test('대문자·짧은 SHA 형식은 스키마에서 거부한다', () => {
    const { root } = capturedRoot({ sha256: sha(PNG_BYTES).toUpperCase() });
    expectReject(root, /sha256: 형식/);
  });

  test('PNG 서명이 아닌 파일을 거부한다', () => {
    const fake = Buffer.from('not a png file');
    const { root } = capturedRoot({ sha256: sha(fake) }, fake);
    expectReject(root, /PNG 파일 서명이 아니다/);
  });

  test('relativePath 의 경로 탈출·절대 경로·역슬래시를 거부한다', () => {
    for (const rel of ['../personas/p1.json', 'images/../../x.png', '/etc/passwd', 'C:/x.png', 'images\\x.png', './images/x.png', '//server/share.png']) {
      const { root } = capturedRoot({ relativePath: rel });
      expectReject(root, /path-escape|허용하지 않는다|구분자/, '--json');
    }
  });

  test('pending 항목의 relativePath 는 증거로 쓰지 않고 경고한다', () => {
    const caps = pendingAll();
    caps[0] = { ...caps[0], relativePath: 'images/later.png' };
    const { root } = fresh({ captures: caps });
    const r = run(root, '--validate-only', '--json');
    assert.equal(r.code, 0, r.stderr);
    assert.ok(JSON.parse(r.stdout).warnings.some((w) => /증거로 사용하지 않는다/.test(w)));
  });
});

describe('입력 경로 제한과 심볼릭 링크', () => {
  test('작업 루트 밖의 입력 경로를 거부한다', () => {
    const { root } = fresh();
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-sim-outside-'));
    try {
      fs.writeFileSync(path.join(outside, 'p.json'), JSON.stringify(persona('outside-1')));
      expectReject(root, /path-escape/, '--personas', '../outside.json');
      expectReject(root, /path-escape/, '--personas', path.join(outside, 'p.json'));
    } finally {
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });

  const linkSkip = !canSymlink() && '이 환경에서 심볼릭 링크를 만들 수 없다';

  test('심볼릭 링크 PNG 를 거부한다', { skip: linkSkip }, () => {
    const caps = pendingAll();
    caps[0] = { ...caps[0], status: 'captured', relativePath: 'images/link.png', sha256: sha(PNG_BYTES) };
    const { root, write } = fresh({ captures: caps });
    const real = write('simulation/capture/real.png', PNG_BYTES);
    fs.mkdirSync(path.join(root, 'simulation', 'capture', 'images'));
    fs.symlinkSync(real, path.join(root, 'simulation', 'capture', 'images', 'link.png'), 'file');
    expectReject(root, /심볼릭 링크/);
  });

  test('루트 밖을 가리키는 심볼릭 링크 폴더 입력을 거부한다', { skip: linkSkip }, () => {
    const { root } = fresh();
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-sim-outside-'));
    try {
      fs.writeFileSync(path.join(outside, 'p.json'), JSON.stringify(persona('outside-1')));
      fs.symlinkSync(outside, path.join(root, 'simulation', 'linked-personas'), 'dir');
      expectReject(root, /심볼릭 링크/, '--personas', 'simulation/linked-personas');
    } finally {
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });

  test('폴더 안의 심볼릭 링크 JSON 을 거부한다', { skip: linkSkip }, () => {
    const { root } = fresh();
    fs.symlinkSync(path.join(root, 'simulation', 'personas', 'p1.json'), path.join(root, 'simulation', 'personas', 'p9.json'), 'file');
    expectReject(root, /심볼릭 링크/);
  });

  test('simulation/runs 가 심볼릭 링크면 출력하지 않는다', { skip: linkSkip }, () => {
    const { root } = fresh();
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-sim-outside-'));
    try {
      fs.symlinkSync(outside, path.join(root, 'simulation', 'runs'), 'dir');
      const r = run(root, '--dry-run', '--run-id', 'link-out');
      assert.equal(r.code, 1);
      assert.match(r.stderr, /심볼릭 링크/);
      assert.deepEqual(fs.readdirSync(outside), []);
    } finally {
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });
});
