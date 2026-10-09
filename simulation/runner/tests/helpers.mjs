// 테스트 전용 합성 입력 생성기. 실제 사용자 데이터·토큰·서버를 쓰지 않는다.
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FIXED_CAPTURE_IDS } from '../lib/inputs.mjs';

export const CLI = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'scripts', 'ux-sim', 'run.mjs');

// 1×1 투명 PNG (합성 이미지)
export const PNG_BYTES = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);
export const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');

export function persona(id, extra = {}) {
  return {
    schemaVersion: 1, id, name: `합성 사용자 ${id}`, synthetic: true,
    experience: 'first-time', context: '테스트용 합성 맥락이다.', goals: ['운동을 기록하고 싶다.'],
    attention: 'normal', readingStyle: 'brief', ...extra,
  };
}

export function scenario(id, extra = {}) {
  return {
    schemaVersion: 1, id, title: `합성 시나리오 ${id}`, userGoal: '합성 목표를 수행해 주세요.',
    fixtureId: 'demo-v1', startCaptureId: 'records-overview',
    captureIds: ['records-overview', 'journal-calendar', 'journal-entry'],
    allowedActionTypes: ['inspect', 'tap', 'scroll', 'input', 'back', 'stop'], maxSteps: 10,
    checks: [
      { id: 'entry-found', kind: 'observation-only', description: '진입점을 찾는지 본다.' },
      { id: 'saved', kind: 'app-state', description: '저장 스냅샷 차이를 확인한다.' },
      { id: 'human-check', kind: 'manual', description: '사람이 확인한다.' },
    ],
    ...extra,
  };
}

export function manifest(captures) {
  return {
    schemaVersion: 1, fixtureId: 'demo-v1', anchorTime: '2026-10-12T09:00:00+09:00',
    timezone: 'Asia/Seoul', locale: 'ko_KR', appCommit: null,
    captures: captures ?? FIXED_CAPTURE_IDS.map((id) => ({
      id, status: 'pending', width: 834, height: 1194, textScale: 'standard',
    })),
  };
}

/** 4 persona × 5 scenario + pending 10개 manifest를 가진 임시 작업 루트. */
export function makeRoot({ personas = 4, scenarios = 5, captures } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-sim-test-'));
  const write = (rel, data) => {
    const file = path.join(root, ...rel.split('/'));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, typeof data === 'string' || Buffer.isBuffer(data) ? data : `${JSON.stringify(data, null, 2)}\n`);
    return file;
  };
  for (let i = 1; i <= personas; i += 1) write(`simulation/personas/p${i}.json`, persona(`persona-${i}`));
  for (let i = 1; i <= scenarios; i += 1) write(`simulation/scenarios/s${i}.json`, scenario(`scenario-${i}`));
  write('simulation/scenarios/README.md', '# 무시되는 문서\n');
  write('simulation/capture/manifest.json', manifest(captures));
  return { root, write, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

/**
 * GIT_DIR·GIT_WORK_TREE 등 GIT_* 환경 변수를 뺀 환경.
 * 상속된 GIT_DIR이 있으면 임시 루트의 git 명령이 실제 저장소를 건드릴 수 있으므로
 * 테스트의 모든 하위 프로세스는 이 환경으로만 실행한다.
 */
export function cleanEnv() {
  return Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.toUpperCase().startsWith('GIT_')));
}

export function run(root, ...args) {
  const r = spawnSync(process.execPath, [CLI, '--root', root, ...args], { encoding: 'utf8', env: cleanEnv() });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

export function canSymlink() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ux-sim-link-'));
  try {
    fs.writeFileSync(path.join(dir, 'a'), 'x');
    fs.symlinkSync(path.join(dir, 'a'), path.join(dir, 'b'), 'file');
    return true;
  } catch {
    return false;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
