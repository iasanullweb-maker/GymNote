import { readFileSync, readdirSync, realpathSync, existsSync, statSync } from 'node:fs';
import { resolve, relative, isAbsolute, dirname, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { CAPTURE_IDS, ContractError, validateDocument, validatePanel, validateRelativePath } from './validate.mjs';

function contained(root, target) {
  const result = relative(realpathSync(root), realpathSync(target));
  if (result === '..' || result.startsWith('..' + sep) || isAbsolute(result)) throw new ContractError('input escapes its allowed directory');
  return target;
}
function readJson(root, file) {
  contained(root, file);
  if (!statSync(file).isFile() || statSync(file).size > 1024 * 1024) throw new ContractError('JSON input must be a file no larger than 1 MiB');
  return JSON.parse(readFileSync(file, 'utf8'));
}
function documents(root, directory) {
  const path = resolve(root, directory);
  if (!existsSync(path)) return [];
  contained(root, path);
  return readdirSync(path).filter(name => name.endsWith('.json')).sort().map(name => readJson(path, resolve(path, name)));
}
export function auditRepository(root, { manifestPath } = {}) {
  root = realpathSync(root);
  const personas = documents(root, 'simulation/personas');
  const scenarios = documents(root, 'simulation/scenarios');
  personas.forEach(value => validateDocument('persona', value));
  scenarios.forEach(value => validateDocument('scenario', value));
  for (const [label, values] of [['personas', personas], ['scenarios', scenarios]]) {
    if (new Set(values.map(value => value.id)).size !== values.length) throw new ContractError('duplicate ' + label + ' IDs');
  }
  if (manifestPath !== undefined) validateRelativePath(manifestPath);
  const manifestFile = resolve(root, manifestPath ?? 'simulation/capture/manifest.json');
  const manifest = existsSync(manifestFile) ? readJson(root, manifestFile) : null;
  if (manifest) validateDocument('capture-manifest', manifest);
  const missing = [];
  if (personas.length < 4) missing.push('at least four personas');
  if (scenarios.length < 5) missing.push('at least five scenarios');
  if (!manifest) missing.push('capture manifest');
  if (personas.length && scenarios.length && manifest) validatePanel({ personas, scenarios, manifest });
  const imageChecks = [];
  for (const capture of manifest?.captures ?? []) {
    const entry = { id: capture.id, width: capture.width, height: capture.height, textScale: capture.textScale, status: capture.status, fileVerified: false };
    if (capture.status === 'captured') {
      const file = resolve(dirname(manifestFile), capture.relativePath);
      contained(dirname(manifestFile), file);
      if (!statSync(file).isFile() || statSync(file).size > 32 * 1024 * 1024) throw new ContractError('PNG input must be a file no larger than 32 MiB');
      const bytes = readFileSync(file);
      if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
          || bytes.readUInt32BE(8) !== 13 || bytes.toString('ascii', 12, 16) !== 'IHDR'
          || !bytes.readUInt32BE(16) || !bytes.readUInt32BE(20)) throw new ContractError('capture must have a valid PNG signature and IHDR dimensions');
      if (createHash('sha256').update(bytes).digest('hex') !== capture.sha256) throw new ContractError('capture SHA-256 mismatch: ' + capture.id);
      entry.fileVerified = true;
    }
    imageChecks.push(entry);
  }
  const dryRunReady = missing.length === 0;
  const completeVariants = new Map();
  for (const capture of imageChecks.filter(c => c.fileVerified)) {
    const variant = [capture.width, capture.height, capture.textScale].join(':');
    if (!completeVariants.has(variant)) completeVariants.set(variant, new Set());
    completeVariants.get(variant).add(capture.id);
  }
  const screenReviewReady = dryRunReady && [...completeVariants.values()].some(ids => CAPTURE_IDS.every(id => ids.has(id)));
  return {
    schemaVersion: 1, synthetic: true, status: missing.length ? 'awaiting-inputs' : 'inputs-validated',
    dryRunReady, screenReviewReady, nativeEvaluationPerformed: false, modelRequests: 0,
    personas: personas.length, scenarios: scenarios.length, plannedRunsAtThreeRepeats: personas.length * scenarios.length * 3,
    appCommit: manifest?.appCommit ?? null, missing, captures: imageChecks,
    pendingCaptures: imageChecks.filter(c => c.status === 'pending').length,
    failedCaptures: imageChecks.filter(c => c.status === 'failed').length,
    note: 'Checks input contracts and PNG signature/hash only; performs no model evaluation, UI interaction, or image decoding.',
  };
}
export function runCli(args) {
  let root = fileURLToPath(new URL('../../', import.meta.url));
  let manifestPath; let requirePanel = false; let requireCaptures = false;
  for (let i = 0; i < args.length; i++) {
    const argument = args[i];
    if (argument === '--help') {
      console.log('node simulation/contracts/audit.mjs [--root PATH] [--manifest PATH] [--require-panel] [--require-captures]'); return 0;
    }
    if (argument === '--root' || argument === '--manifest') {
      const value = args[++i]; if (!value || value.startsWith('--')) throw new ContractError(argument + ' requires a value');
      if (argument === '--root') root = resolve(value); else manifestPath = value;
    } else if (argument === '--require-panel') requirePanel = true;
    else if (argument === '--require-captures') requireCaptures = true;
    else throw new ContractError('unknown argument ' + argument);
  }
  const report = auditRepository(root, { manifestPath });
  console.log(JSON.stringify(report, null, 2));
  return (requirePanel && !report.dryRunReady) || (requireCaptures && !report.screenReviewReady) ? 1 : 0;
}
if (typeof process !== 'undefined' && process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try { process.exitCode = runCli(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
