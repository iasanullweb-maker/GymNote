// Kakao skill + relay Edge Function checks with a fake database. No network, Kakao or Supabase access.
import { stripTypeScriptTypes } from 'node:module';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = (await readFile('supabase/functions/kakao-skill/index.ts', 'utf8')).replace(/^import .*;\r?\n/m, '');
const javascript = stripTypeScriptTypes(source);
const SKILL = 'skill-' + 'a'.repeat(40);
const RELAY = 'relay-' + 'b'.repeat(40);
let env;
let calls;
let replies;
const resetEnv = () => {
  env = { SUPABASE_URL: 'https://test.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service-secret',
          KAKAO_SKILL_TOKEN: SKILL, AUTOMATION_RELAY_TOKEN: RELAY, KAKAO_BOT_IDS: 'bot-1, bot-2',
          KAKAO_USER_KEYS: 'user-1', KAKAO_DISCOVERY: 'false' };
};
const resetDb = () => {
  calls = [];
  replies = {
    automation_kakao_receive: { data: '11111111-1111-4111-8111-111111111111', error: null },
    automation_kakao_status: { data: { tasks: [], waitingCount: 0, waiting: [], replies: [] }, error: null },
    automation_kakao_claim: { data: [], error: null },
    automation_kakao_ack: { data: true, error: null },
    automation_kakao_publish: { data: 1, error: null },
  };
};
let handler;
const context = vm.createContext({
  Response, Request, URL, TextEncoder, TextDecoder, crypto: globalThis.crypto,
  Deno: { env: { get: (key) => env[key] }, serve: (fn) => { handler = fn; } },
  createClient: (url, key) => {
    assert.equal(url, 'https://test.supabase.co');
    assert.equal(key, 'service-secret');
    return { rpc: async (name, args) => { calls.push(JSON.parse(JSON.stringify({ name, args }))); return replies[name]; } };
  },
});
vm.runInContext(javascript, context);
resetEnv();
resetDb();

const payload = (utterance, { user = 'user-1', bot = 'bot-1', type = 'botUserKey' } = {}) =>
  ({ bot: { id: bot }, userRequest: { user: { id: user, type }, utterance } });
const call = (path, body, { method = 'POST', headers = {} } = {}) => handler(new Request('https://test.supabase.co/functions/v1' + path, {
  method, headers: { 'Content-Type': 'application/json', ...headers },
  ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
}));
const skill = (utterance, identity, headers = { 'x-api-key': SKILL }) => call('/kakao-skill', payload(utterance, identity), { headers });
const text = async (response) => {
  const value = await response.json();
  assert.equal(value.version, '2.0');
  return value.template.outputs.map((output) => output.simpleText.text).join('\n');
};
const received = () => calls.filter((entry) => entry.name === 'automation_kakao_receive');

// Routing, method and authentication.
assert.equal((await call('/other', {})).status, 404);
assert.equal((await call('/kakao-skill/admin', {})).status, 404);
assert.equal((await call('/kakao-skill', null, { method: 'GET' })).status, 405);
assert.equal((await skill('메모 hi', undefined, {})).status, 401);
assert.equal((await skill('메모 hi', undefined, { 'x-api-key': SKILL + 'x' })).status, 401);
assert.equal((await skill('메모 hi', undefined, { 'x-api-key': RELAY })).status, 401, 'Relay token is not a skill token');
env.KAKAO_SKILL_TOKEN = 'short';
assert.equal((await skill('메모 hi', undefined, { 'x-api-key': 'short' })).status, 401, 'Weak configured token is refused');
resetEnv();
assert.equal((await skill('메모 hi', undefined, { 'x-api-key': SKILL, Origin: 'https://evil' })).status, 403);
assert.equal((await call('/kakao-skill', '{not json', { headers: { 'x-api-key': SKILL } })).status, 400);
assert.equal((await call('/kakao-skill', payload('hi'), { headers: { 'x-api-key': SKILL, 'Content-Type': 'text/plain' } })).status, 400);
assert.equal((await call('/kakao-skill', payload('x'.repeat(40000)), { headers: { 'x-api-key': SKILL } })).status, 413);
assert.equal((await call('/kakao-skill', { bot: null }, { headers: { 'x-api-key': SKILL } })).status, 400);
assert.equal((await skill('hi', { type: 'appUserId' })).status, 400);
assert.equal((await skill('   ')).status, 400);
assert.equal(calls.length, 0, 'Rejected requests never touch the database');

// Allowlists and discovery.
assert.equal((await skill('메모 hi', { bot: 'bot-x' })).status, 403);
assert.equal((await skill('메모 hi', { user: 'stranger' })).status, 403);
assert.equal((await skill('내정보', { user: 'stranger' })).status, 403, 'Discovery off hides identifiers');
env.KAKAO_DISCOVERY = 'true';
const discovered = await text(await skill('내정보', { user: 'stranger' }));
assert.match(discovered, /bot-1/);
assert.match(discovered, /stranger/);
assert.equal((await skill('내정보', { user: 'stranger', bot: 'bot-x' })).status, 403, 'Discovery is bot-scoped');
assert.equal((await skill('메모 hi', { user: 'stranger' })).status, 403, 'Discovery only answers whoami');
resetEnv();
assert.equal(calls.length, 0);

// Commands that answer immediately.
assert.match(await text(await skill('도움말')), /PC가 꺼져 있어도 접수/);
assert.match(await text(await skill('/whoami')), /발견 모드/);
for (const bad of ['실행', '실행 키만', '실행 bad/key 내용', '재시도 key-1', '재시도 bad/key task', '중지', '중지 a b', '/unknown 명령', '메모']) {
  const response = await skill(bad);
  assert.equal(response.status, 200, bad);
  await text(response);
}
assert.equal(received().length, 0, 'Malformed commands are not stored');

// Stored requests: memo, plain text, run, retry and cancel go to the mailbox unchanged (trimmed).
for (const utterance of ['  운동 아이디어  ', '메모 두 번째', '실행 smoke-1 문서에 한 줄 추가', '재시도 retry-1 task-1', '중지 task-1']) {
  const response = await skill(utterance);
  assert.equal(response.status, 200);
  const value = await response.json();
  assert.equal(value.template.quickReplies[0].messageText, '상태');
}
assert.deepEqual(received().map((entry) => entry.args.p_utterance),
  ['운동 아이디어', '메모 두 번째', '실행 smoke-1 문서에 한 줄 추가', '재시도 retry-1 task-1', '중지 task-1']);
assert.ok(received().every((entry) => entry.args.p_bot === 'bot-1' && entry.args.p_user === 'user-1'));
replies.automation_kakao_receive = { data: null, error: null };
assert.match(await text(await skill('메모 너무 많음')), /100건/);
replies.automation_kakao_receive = { data: null, error: new Error('db down') };
const unavailable = await skill('메모 실패');
assert.equal(unavailable.status, 503);
assert.doesNotMatch(await text(unavailable), /db down/);
resetDb();

// Status rendering from cloud snapshots.
assert.equal(await text(await skill('상태')), '등록한 작업이 없습니다.');
replies.automation_kakao_status = { data: {
  tasks: [{ id: 'task-1', text: 'task-1\n상태: 완료', updated: '2026-10-12T08:00:00Z' }],
  waitingCount: 4, waiting: [{ received: '2026-10-12T09:00:00Z', preview: '실행 smoke-2 문서' }],
  replies: [{ processed: '2026-10-12T08:30:00Z', text: '자동 작업 실행이 꺼져 있거나 일시 중지되어 있습니다.' }] }, error: null };
const listed = await text(await skill('상태'));
assert.match(listed, /PC 처리 대기 4건/);
assert.match(listed, /실행 smoke-2/);
assert.match(listed, /자동 작업 실행이 꺼져/);
assert.match(listed, /상태: 완료/);
assert.match(listed, /17:00/, 'Times shown in Korea time');
assert.equal(calls.at(-1).args.p_task, null);
assert.match(await text(await skill('상태 task-1')), /상태: 완료/);
assert.equal(calls.at(-1).args.p_task, 'task-1');
replies.automation_kakao_status = { data: { tasks: [], waitingCount: 0, waiting: [], replies: [] }, error: null };
assert.match(await text(await skill('상태 task-9')), /찾을 수 없습니다/);
resetDb();

// Relay endpoints for the PC.
const relay = (action, body, headers = { 'x-relay-token': RELAY }) => call('/kakao-skill/relay/' + action, body, { headers });
assert.equal((await relay('claim', {}, {})).status, 401);
assert.equal((await relay('claim', {}, { 'x-relay-token': SKILL })).status, 401, 'Skill token is not a relay token');
assert.equal((await relay('claim', {}, { 'x-relay-token': RELAY, Origin: 'https://evil' })).status, 403);
assert.equal((await relay('unknown', {})).status, 404);
assert.equal((await call('/kakao-skill/relay/claim', null, { method: 'GET', headers: { 'x-relay-token': RELAY } })).status, 405);
for (const limit of [0, 21, 1.5, '3']) assert.equal((await relay('claim', { limit })).status, 400, 'limit ' + limit);
assert.equal(calls.length, 0);
replies.automation_kakao_claim = { data: [{ item_id: '11111111-1111-4111-8111-111111111111', item_claim: '22222222-2222-4222-8222-222222222222',
  item_bot: 'bot-1', item_user: 'user-1', item_utterance: '메모 hi', item_received: '2026-10-12T08:00:00Z' }], error: null };
const claimed = await (await relay('claim', { limit: 5 })).json();
assert.deepEqual(claimed.items, [{ id: '11111111-1111-4111-8111-111111111111', claim: '22222222-2222-4222-8222-222222222222',
  bot: 'bot-1', user: 'user-1', utterance: '메모 hi', received: '2026-10-12T08:00:00Z' }]);
assert.deepEqual(calls.at(-1), { name: 'automation_kakao_claim', args: { p_limit: 5 } });
const ack = { id: '11111111-1111-4111-8111-111111111111', claim: '22222222-2222-4222-8222-222222222222', taskId: 'task-1', reply: '아이디어 저장' };
assert.deepEqual(await (await relay('ack', ack)).json(), { ok: true });
assert.deepEqual(calls.at(-1).args, { p_id: ack.id, p_claim: ack.claim, p_task: 'task-1', p_reply: '아이디어 저장' });
assert.equal((await relay('ack', { ...ack, taskId: null })).status, 200);
for (const bad of [{ ...ack, id: 'not-uuid' }, { ...ack, claim: 'x' }, { ...ack, reply: '' }, { ...ack, reply: 'x'.repeat(1001) }, { ...ack, taskId: ' t' }]) {
  assert.equal((await relay('ack', bad)).status, 400);
}
replies.automation_kakao_ack = { data: false, error: null };
assert.deepEqual(await (await relay('ack', ack)).json(), { ok: false }, 'Stale lease is reported, not hidden');
const snapshot = { id: 'task-1', actor: 'kakao:' + 'c'.repeat(64), statusText: 'task-1\n상태: 완료', created: '2026-10-12T08:00:00+00:00' };
const before = calls.length;
assert.deepEqual(await (await relay('publish', { tasks: [] })).json(), { count: 0 });
assert.equal(calls.length, before, 'Empty publish skips the database');
assert.deepEqual(await (await relay('publish', { tasks: [snapshot] })).json(), { count: 1 });
assert.deepEqual(calls.at(-1).args.p_tasks, [snapshot]);
for (const bad of [{ tasks: {} }, { tasks: [{ ...snapshot, actor: 'admin' }] }, { tasks: [snapshot, snapshot] },
                   { tasks: [{ ...snapshot, statusText: '' }] }, { tasks: [{ ...snapshot, created: 'yesterday' }] },
                   { tasks: Array.from({ length: 201 }, (_, n) => ({ ...snapshot, id: 't' + n })) }]) {
  assert.equal((await relay('publish', bad)).status, 400);
}
replies.automation_kakao_publish = { data: null, error: new Error('db down') };
const failed = await relay('publish', { tasks: [snapshot] });
assert.equal(failed.status, 503);
assert.deepEqual(await failed.json(), { error: 'rejected' });
console.log('Kakao skill/relay function checks passed');
