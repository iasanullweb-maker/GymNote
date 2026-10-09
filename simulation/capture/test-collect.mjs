import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm, access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { deflateSync } from 'node:zlib';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { collect, safeRelative, pngBounds, IDS } from './collect.mjs';

// Explicitly synthetic codec input; never placed in the product capture manifest.
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(kind, data) {
  const type = Buffer.from(kind), size = Buffer.alloc(4), crc = Buffer.alloc(4);
  size.writeUInt32BE(data.length); crc.writeUInt32BE(crc32(Buffer.concat([type, data])));
  return Buffer.concat([size, type, data, crc]);
}
function syntheticPNG() {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(2, 0); header.writeUInt32BE(1, 4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR', header),
    chunk('IDAT', deflateSync(Buffer.from([0,255,0,0,0,255,0]))), chunk('IEND', Buffer.alloc(0))]);
}
export async function runTests() {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'gymnote-capture-test-'));
  const attachmentsRoot = path.join(directory, 'attachments');
  await mkdir(attachmentsRoot);
  const bytes = syntheticPNG();
  await writeFile(path.join(attachmentsRoot, 'synthetic.png'), bytes);
  const receipt = { id: 'plan-month', status: 'captured', width: 2, height: 1, textScale: 'standard', relativePath: 'synthetic.png' };
  const input = { attachmentsRoot, receipts: [receipt], appCommit: 'a'.repeat(40) };
  let symlinkCheck = 'passed';
  try {
    const pending = await collect({ ...input, receipts: [], validateOnly: true });
    assert.equal(pending.appCommit, null);
    assert.equal(pending.captures.length, 10);
    assert.deepEqual(pending.captures.map(c=>c.id), IDS);
    assert(pending.captures.every(c=>c.status==='pending' && !('relativePath' in c) && !('sha256' in c)));
    const result = await collect({ ...input, output: path.join(directory, 'output') });
    const captured = result.captures.find(c=>c.status==='captured');
    assert.equal(result.appCommit, 'a'.repeat(40));
    assert.equal(captured.sha256, createHash('sha256').update(bytes).digest('hex'));
    assert.deepEqual(await readFile(path.join(directory, 'output', captured.relativePath)), bytes);
    assert.equal(result.captures.filter(c=>c.width===834 && c.height===1194).length, 10);
    assert.equal(JSON.parse(await readFile(path.join(directory, 'output/manifest.json'), 'utf8')).fixtureId, 'demo-v1');
    await assert.rejects(collect({ ...input, output: path.join(directory, 'output') }), /EEXIST/);
    for (const bad of ['../escape.png', '/absolute.png', 'C:/absolute.png', 'a/../b.png', 'a\\b.png', './file.png', 'a//b', '']) assert.throws(()=>safeRelative(bad), /Unsafe/);
    await assert.rejects(collect({ ...input, receipts: [{...receipt, relativePath:'missing.png'}], validateOnly:true }), /ENOENT/);
    await assert.rejects(collect({ ...input, receipts: [receipt, receipt], validateOnly:true }), /Duplicate/);
    await assert.rejects(collect({ ...input, appCommit:'unrendered', validateOnly:true }), /SHA/);
    await assert.rejects(collect({ ...input, receipts: [{...receipt,width:834}], validateOnly:true }), /dimensions/);
    await assert.rejects(collect({ ...input, receipts: [{...receipt,id:'invented-screen'}], validateOnly:true }), /Invalid/);
    await assert.rejects(collect({ ...input, receipts: [{...receipt,status:'failed',error:''}], validateOnly:true }), /evidence/);
    const failed = await collect({ ...input, receipts: [{id:'plan-month',width:834,height:1194,textScale:'standard',status:'failed',error:'Synthetic failure evidence for exporter test'}], validateOnly:true });
    assert.equal(failed.captures.find(c=>c.id==='plan-month').status,'failed');
    assert.equal(failed.appCommit,null);
    assert.throws(()=>pngBounds(Buffer.from('not a screenshot')), /PNG/);
    assert.throws(()=>pngBounds(bytes.subarray(0,bytes.length-1)), /Truncated/);
    const corrupt=Buffer.from(bytes); corrupt[29]^=1;
    assert.throws(()=>pngBounds(corrupt), /CRC/);
    const invalidOutput=path.join(directory,'must-not-exist');
    await assert.rejects(collect({ ...input, receipts:[{...receipt,relativePath:'../outside.png'}], output:invalidOutput }), /Unsafe/);
    await assert.rejects(access(invalidOutput), /ENOENT/);
    try {
      await symlink(path.join(attachmentsRoot,'synthetic.png'),path.join(attachmentsRoot,'linked.png'));
      await assert.rejects(collect({ ...input,receipts:[{...receipt,relativePath:'linked.png'}],validateOnly:true }), /Symlink/);
    } catch(error) { if (['EPERM','EACCES','ENOTSUP'].includes(error.code)) symlinkCheck='not-run: OS denied synthetic symlink creation'; else throw error; }
    return { exporter: 'passed', symlinkCheck, input: 'explicit synthetic PNG; not an app render' };
  } finally { await rm(directory,{recursive:true,force:true}); }
}
if (typeof process !== "undefined" && process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) runTests().then(result=>console.log(JSON.stringify(result))).catch(error=>{console.error(error);process.exitCode=1;});
