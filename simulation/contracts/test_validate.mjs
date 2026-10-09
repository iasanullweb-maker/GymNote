import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, symlinkSync } from 'node:fs';
import { resolve } from 'node:path';
import { tmpdir, platform } from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { validateSchema, validateDocument, validatePanel, validateSession, validateRelativePath } from './validate.mjs';
import { auditRepository } from './audit.mjs';

export function runContractTests() {
  let count = 0;
  function test(name, fn) { fn(); count++; }
  const example = name => JSON.parse(readFileSync(new URL('examples/' + name + '.json', import.meta.url), 'utf8'));
  const mutate = (name, fn) => { const value = example(name); fn(value); return value; };
  for (const name of ['persona', 'scenario', 'capture-manifest', 'session']) test(name + ' example', () => validateDocument(name, example(name)));
  test('object constants ignore property order', () => validateSchema({ const: { a: 1, b: 2 } }, { b: 2, a: 1 }));
  test('unsupported schema keyword rejected', () => assert.throws(() => validateSchema({ if: { format: 'date' }, then: {} }, {}), /unsupported/));
  test('unknown data field rejected', () => assert.throws(() => validateDocument('persona', mutate('persona', x => x.token = 'synthetic-test-value')), /unexpected/));
  test('non-synthetic persona rejected', () => assert.throws(() => validateDocument('persona', mutate('persona', x => x.synthetic = false))));
  test('step budget rejected', () => assert.throws(() => validateDocument('scenario', mutate('scenario', x => x.maxSteps = 41))));
  test('unknown screen rejected', () => assert.throws(() => validateDocument('scenario', mutate('scenario', x => x.captureIds.push('unknown-screen'))), /unknown screen/));
  test('start screen must be listed', () => assert.throws(() => validateDocument('scenario', mutate('scenario', x => x.startCaptureId = 'workout-ready')), /not listed/));
  test('duplicate scenario checks rejected', () => assert.throws(() => validateDocument('scenario', mutate('scenario', x => x.checks.push(x.checks[0]))), /duplicate/));
  test('duplicate capture variant rejected', () => assert.throws(() => validateDocument('capture-manifest', mutate('capture-manifest', x => x.captures.push(x.captures[0]))), /duplicate/));
  test('ten duplicates do not count as ten screens', () => assert.throws(() => validateDocument('capture-manifest', mutate('capture-manifest', x => x.captures = Array(10).fill(x.captures[0])))));
  test('split variants do not imply complete screen set', () => assert.throws(() => validateDocument('capture-manifest', mutate('capture-manifest', x => x.captures[0].width = 400)), /complete/));
  test('captured needs path and hash', () => assert.throws(() => validateDocument('capture-manifest', mutate('capture-manifest', x => x.captures[0].status = 'captured'))));
  test('captured needs app commit', () => assert.throws(() => validateDocument('capture-manifest', mutate('capture-manifest', x => Object.assign(x.captures[0], { status: 'captured', relativePath: 'one.png', sha256: 'a'.repeat(64) }))), /actual app commit/));
  for (const path of ['../one.png', '/one.png', 'C:/one.png', 'a\\b.png', './one.png', 'a//b.png', 'a:stream', 'bad\0path']) test('unsafe path', () => assert.throws(() => validateRelativePath(path)));
  test('safe path accepted', () => validateRelativePath('images/one.png'));
  test('dry-run cannot claim success', () => assert.throws(() => validateDocument('session', mutate('session', x => x.outcome = 'success'))));
  test('dry-run cannot claim model request', () => assert.throws(() => validateDocument('session', mutate('session', x => x.usage.requests = 1))));
  test('dry-run cannot contain evaluated check', () => assert.throws(() => validateDocument('session', mutate('session', x => x.checks[0].result = 'pass'))));
  test('pass needs evidence', () => assert.throws(() => validateDocument('session', mutate('session', x => { x.mode = 'screen-review'; x.status = 'completed'; x.outcome = 'inconclusive'; x.checks[0].result = 'pass'; })), /evidence/));
  test('session matches scenario', () => validateSession(example('session'), example('scenario')));
  test('screen-review cannot pass app-state', () => assert.throws(() => validateSession(mutate('session', x => { x.mode = 'screen-review'; x.status = 'completed'; x.outcome = 'inconclusive'; x.checks[1].result = 'pass'; x.checks[1].evidence = ['synthetic-image']; }), example('scenario')), /app-state/));
  test('session must include every check', () => assert.throws(() => validateSession(mutate('session', x => x.checks.pop()), example('scenario')), /every/));
  test('duplicate personas rejected', () => assert.throws(() => validatePanel({ personas: [example('persona'), example('persona')], scenarios: [example('scenario')], manifest: example('capture-manifest') }), /duplicate/));
  const temporary = mkdtempSync(resolve(tmpdir(), 'gymnote-ux-contracts-'));
  test('missing worker outputs reported pending', () => { const result = auditRepository(temporary); assert.equal(result.status, 'awaiting-inputs'); assert.equal(result.modelRequests, 0); assert.equal(result.plannedRunsAtThreeRepeats, 0); assert.equal(result.dryRunReady, false); });
  test('manifest path outside root rejected even when missing', () => assert.throws(() => auditRepository(temporary, { manifestPath: '../missing.json' }), /relative path/));
  for (const dir of ['personas', 'scenarios', 'capture']) mkdirSync(resolve(temporary, 'simulation', dir), { recursive: true });
  for (let i = 0; i < 4; i++) { const p = mutate('persona', x => x.id = 'persona-' + i); writeFileSync(resolve(temporary, 'simulation/personas', p.id + '.json'), JSON.stringify(p)); }
  for (let i = 0; i < 5; i++) { const s = mutate('scenario', x => x.id = 'scenario-' + i); writeFileSync(resolve(temporary, 'simulation/scenarios', s.id + '.json'), JSON.stringify(s)); }
  const manifest = example('capture-manifest');
  const manifestFile = resolve(temporary, 'simulation/capture/manifest.json');
  writeFileSync(manifestFile, JSON.stringify(manifest));
  test('four by five by three plans sixty without evaluation', () => { const result = auditRepository(temporary); assert.equal(result.plannedRunsAtThreeRepeats, 60); assert.equal(result.dryRunReady, true); assert.equal(result.screenReviewReady, false); assert.equal(result.pendingCaptures, 10); assert.equal(result.nativeEvaluationPerformed, false); });
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6deAAAAAASUVORK5CYII=', 'base64');
  writeFileSync(resolve(temporary, 'simulation/capture/one.png'), png);
  manifest.appCommit = 'a'.repeat(40);
  Object.assign(manifest.captures[0], { status: 'captured', relativePath: 'one.png', sha256: '0'.repeat(64) });
  writeFileSync(manifestFile, JSON.stringify(manifest));
  test('incorrect PNG hash rejected', () => assert.throws(() => auditRepository(temporary), /SHA-256/));
  manifest.captures[0].sha256 = createHash('sha256').update(png).digest('hex');
  writeFileSync(manifestFile, JSON.stringify(manifest));
  test('one verified image does not imply ten ready screens', () => { const result = auditRepository(temporary); assert.equal(result.captures[0].fileVerified, true); assert.equal(result.screenReviewReady, false); });
  writeFileSync(resolve(temporary, 'simulation/capture/one.png'), Buffer.from('not png'));
  manifest.captures[0].sha256 = createHash('sha256').update('not png').digest('hex');
  writeFileSync(manifestFile, JSON.stringify(manifest));
  test('non-PNG rejected even if hash matches', () => assert.throws(() => auditRepository(temporary), /PNG signature/));
  // Directory symlinks work on Windows via junctions without administrator rights.
  const outside = mkdtempSync(resolve(tmpdir(), 'gymnote-ux-outside-'));
  writeFileSync(resolve(outside, 'outside.png'), png);
  symlinkSync(outside, resolve(temporary, 'simulation/capture/escape'), platform() === 'win32' ? 'junction' : 'dir');
  manifest.captures[0].relativePath = 'escape/outside.png';
  manifest.captures[0].sha256 = createHash('sha256').update(png).digest('hex');
  writeFileSync(manifestFile, JSON.stringify(manifest));
  test('symlink escaping capture directory rejected', () => assert.throws(() => auditRepository(temporary), /escapes/));
  return { passed: count, modelRequests: 0, temporaryArtifacts: temporary };
}
if (typeof process !== 'undefined' && process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) console.log(JSON.stringify(runContractTests(), null, 2));
