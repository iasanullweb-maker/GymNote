import { stripTypeScriptTypes } from 'node:module';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = (await readFile('supabase/functions/delete-account/index.ts', 'utf8')).replace(/^import .*;\r?\n/m, '');
const javascript = stripTypeScriptTypes(source);
let handler;
let verified = false;
let active = true;
let deleted = [];
let getUserCalled = 0;
const uid = '00000000-0000-0000-0000-000000000001';
const context = vm.createContext({
  Response, Request, atob,
  Deno: { env: { get: key => ({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'server-secret', SUPABASE_ANON_KEY: 'public-key' }[key]) }, serve: fn => { handler = fn; } },
  createClient: (_url, _key, options) => options.global ? {
    rpc: async () => ({ data: active, error: null })
  } : {
    auth: {
      getUser: async () => { getUserCalled++; return { data: { user: verified ? { id: uid } : null }, error: verified ? null : new Error('invalid') }; },
      admin: { deleteUser: async id => { deleted.push(id); return { error: null }; } },
    },
  },
});
vm.runInContext(javascript, context);
const token = claims => 'header.' + Buffer.from(JSON.stringify(claims)).toString('base64url') + '.signature';
const call = async (claims, { method = 'POST', authorization = true } = {}) => handler(new Request('https://test/delete-account', {
  method,
  headers: authorization ? { Authorization: 'Bearer ' + token(claims) } : {},
  ...(method === 'POST' ? { body: JSON.stringify({ user_id: 'someone-else' }) } : {}),
}));
const claims = { sub: uid, session_id: 'session', amr: [{ method: 'otp', timestamp: Math.floor(Date.now()/1000) }] };
assert.equal((await call(claims, { method: 'GET' })).status, 405);
assert.equal((await call(claims, { authorization: false })).status, 401);
assert.equal((await call(claims)).status, 401, 'Forged token must fail getUser');
assert.equal(deleted.length, 0);
verified = true;
assert.equal((await call({ ...claims, sub: 'other' })).status, 401);
assert.equal((await call({ ...claims, amr: [] })).status, 403);
assert.equal((await call({ ...claims, amr: [{ method: 'otp', timestamp: Math.floor(Date.now()/1000) - 301 }], iat: Math.floor(Date.now()/1000) })).status, 403, 'Refreshing iat does not count as reauth');
assert.equal((await call({ ...claims, amr: [{ method: 'otp', timestamp: Math.floor(Date.now()/1000) + 60 }] })).status, 403);
const nowSeconds = Math.floor(Date.now()/1000);
assert.equal((await call({ ...claims, amr: [{ method: 'token_refresh', timestamp: nowSeconds }] })).status, 403, 'Refresh is not re-authentication');
assert.equal((await call({ ...claims, amr: [{ method: 'password', timestamp: nowSeconds }] })).status, 403, 'Only OTP or provider OAuth count');
assert.equal((await call({ ...claims, amr: [{ method: 'oauth', timestamp: nowSeconds - 301 }] })).status, 403, 'Old social login must re-authenticate');
assert.equal((await call({ ...claims, amr: [{ method: 'oauth', timestamp: nowSeconds + 60 }] })).status, 403);
assert.equal(deleted.length, 0);
active = false;
assert.equal((await call({ ...claims, amr: [{ method: 'oauth', timestamp: nowSeconds }] })).status, 401, 'Revoked social session cannot delete');
assert.equal((await call(claims)).status, 401, 'Revoked session cannot delete');
assert.equal(deleted.length, 0);
active = true;
assert.equal((await call(claims)).status, 200);
assert.deepEqual(deleted, [uid], 'Only the authenticated user can be deleted, regardless of body');
assert.equal((await call({ ...claims, amr: [{ method: 'token_refresh', timestamp: nowSeconds }, { method: 'oauth', timestamp: nowSeconds - 10 }] })).status, 200, 'Recent Google/Apple login re-authenticates');
assert.deepEqual(deleted, [uid, uid]);
assert(getUserCalled > 0);
console.log('Delete-account handler passed: authentication, ownership, OTP/OAuth re-auth age, revoked sessions, deletion target');
