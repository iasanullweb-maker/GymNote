import { readFile, writeFile, mkdir, lstat, realpath } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const IDS = ['workout-ready', 'workout-active', 'workout-rest', 'plan-month', 'plan-date-detail', 'records-overview', 'journal-calendar', 'journal-entry', 'friends-home', 'friends-ranking'];
const template = () => ({ schemaVersion: 1, fixtureId: 'demo-v1', anchorTime: '2026-10-12T09:00:00+09:00', timezone: 'Asia/Seoul', locale: 'ko_KR', appCommit: null,
  captures: IDS.map(id => ({ id, status: 'pending', width: 834, height: 1194, textScale: 'standard' })) });
function variant(c) {
  if (!IDS.includes(c.id) || !Number.isInteger(c.width) || c.width < 1 || !Number.isInteger(c.height) || c.height < 1 || !['standard', 'accessibility'].includes(c.textScale)) throw new Error('Invalid capture ID/bounds/textScale');
  return c.id + '--' + c.width + 'x' + c.height + '--' + c.textScale;
}
export function safeRelative(value) {
  if (typeof value !== 'string' || !value || value.includes('\\') || value.includes(':') || value.includes('\0') || path.posix.isAbsolute(value) || value.split('/').some(p => p === '..' || p === '.' || !p)) throw new Error('Unsafe relative path: ' + value);
  return value;
}
export async function resolveImage(root, relative) {
  safeRelative(relative);
  let current = path.resolve(root);
  if ((await lstat(current)).isSymbolicLink()) throw new Error('Attachment root must not be a symlink');
  const actualRoot = await realpath(current);
  for (const segment of relative.split('/')) {
    current = path.join(current, segment);
    if ((await lstat(current)).isSymbolicLink()) throw new Error('Symlink is not allowed: ' + relative);
  }
  const actual = await realpath(current);
  const fromRoot = path.relative(actualRoot, actual);
  if (fromRoot.startsWith('..') || path.isAbsolute(fromRoot) || !(await lstat(actual)).isFile()) throw new Error('Image escapes input root');
  return actual;
}
export function pngBounds(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 45 || !bytes.subarray(0, 8).equals(signature) || bytes.readUInt32BE(8) !== 13 || bytes.toString('ascii', 12, 16) !== 'IHDR') throw new Error('Not a PNG with IHDR');
  // Validate chunk bounds, CRCs, IDAT and IEND: renamed text/truncated PNGs are rejected.
  let offset = 8, hasData = false, ended = false;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw new Error('Truncated PNG chunk');
    const size = bytes.readUInt32BE(offset), end = offset + 12 + size;
    if (end > bytes.length) throw new Error('Truncated PNG data');
    const kind = bytes.toString('ascii', offset + 4, offset + 8);
    let crc = 0xffffffff;
    for (const byte of bytes.subarray(offset + 4, end - 4)) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    if (((crc ^ 0xffffffff) >>> 0) !== bytes.readUInt32BE(end - 4)) throw new Error('PNG CRC mismatch');
    if (kind === 'IDAT') hasData = true;
    if (kind === 'IEND') { if (size !== 0 || end !== bytes.length) throw new Error('Invalid IEND'); ended = true; }
    offset = end;
  }
  if (!hasData || !ended) throw new Error('Incomplete PNG');
  return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}
export async function collect({ attachmentsRoot, receipts, appCommit, output, validateOnly = false }) {
  if (!/^[a-f0-9]{40}$/.test(appCommit)) throw new Error('Actual captured checkout SHA required');
  if (!Array.isArray(receipts)) throw new Error('Receipts must be an array');
  const manifest = template(), seen = new Set(), images = [];
  for (const receipt of receipts) {
    const name = variant(receipt);
    if (seen.has(name)) throw new Error('Duplicate capture variant: ' + name);
    seen.add(name);
    let capture = { id: receipt.id, width: receipt.width, height: receipt.height, textScale: receipt.textScale, status: receipt.status };
    if (receipt.status === 'captured') {
      const source = await resolveImage(attachmentsRoot, receipt.relativePath);
      const bytes = await readFile(source), bounds = pngBounds(bytes);
      if (bounds.width !== receipt.width || bounds.height !== receipt.height) throw new Error('PNG dimensions differ from scale=1 rendered bounds');
      const sha256 = createHash('sha256').update(bytes).digest('hex');
      capture = { ...capture, relativePath: 'images/' + name + '.png', sha256 };
      images.push({ source, bytes, target: capture.relativePath });
    } else if (receipt.status === 'failed') {
      if (typeof receipt.error !== 'string' || !receipt.error.trim()) throw new Error('Failed capture requires error evidence');
      capture.error = receipt.error;
    } else if (receipt.status !== 'pending') throw new Error('Unknown capture status');
    const index = manifest.captures.findIndex(c => variant(c) === name);
    if (index < 0) manifest.captures.push(capture); else manifest.captures[index] = capture;
  }
  manifest.appCommit = images.length ? appCommit : null;
  if (validateOnly) return manifest;
  if (!output) throw new Error('Output directory required');
  // All input checks finish before creating output. Never reuse a run directory.
  await mkdir(output, { recursive: false });
  await mkdir(path.join(output, 'images'));
  for (const image of images) await writeFile(path.join(output, image.target), image.bytes, { flag: 'wx' });
  await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
  return manifest;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('node simulation/capture/collect.mjs --attachments <export-dir> --receipts <mapping.json> --app-commit <40-char-captured-SHA> --output simulation/runs/<new-run>/capture');
    console.log('Mapping: {"captures":[{"id":"plan-month","width":834,"height":1194,"textScale":"standard","status":"captured","relativePath":"actual-exported-file.png"}]}');
    return;
  }
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--attachments', '--receipts', '--app-commit', '--output'].includes(args[i]) || !args[i + 1] || options[args[i]]) throw new Error('Invalid/repeated argument');
    options[args[i]] = args[i + 1];
  }
  if (Object.keys(options).length !== 4) throw new Error('All four options required; see --help');
  const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const runs = path.join(repository, 'simulation/runs');
  const output = path.resolve(options['--output']);
  const relative = path.relative(runs, output);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) throw new Error('Output must be inside ignored simulation/runs/');
  // Check existing ancestors to avoid a symlink redirect of output outside runs.
  let current = repository;
  for (const segment of path.relative(repository, path.dirname(output)).split(path.sep)) {
    current = path.join(current, segment);
    try { if ((await lstat(current)).isSymbolicLink()) throw new Error('Output ancestor is a symlink'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const mapping = JSON.parse(await readFile(options['--receipts'], 'utf8'));
  await mkdir(path.dirname(output), { recursive: true });
  const manifest = await collect({ attachmentsRoot: options['--attachments'], receipts: mapping.captures, appCommit: options['--app-commit'], output });
  console.log(JSON.stringify({ manifest: path.join(output, 'manifest.json'), captured: manifest.captures.filter(c => c.status === 'captured').length, pending: manifest.captures.filter(c => c.status === 'pending').length, failed: manifest.captures.filter(c => c.status === 'failed').length }));
}
if (typeof process !== "undefined" && process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main().catch(error => { console.error(error.message); process.exitCode = 1; });
