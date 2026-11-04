import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../supabase/functions/notebyme-api/handler.js';
import { createCipher, hash, randomId, passwordDigest } from '../supabase/functions/notebyme-api/crypto.js';
import { ApiError } from '../supabase/functions/notebyme-api/errors.js';

const origin = 'https://notes.example';
const uid = 'b7cf6ac1-1c05-4cc9-9502-cb1dca04bea1';
const noteId = '0bd5cc14-fbfa-4e75-970e-6f7339644d39';
const privateAccess = 'PRIVATE_SUPABASE_ACCESS_TOKEN';
const privateRefresh = 'PRIVATE_SUPABASE_REFRESH_TOKEN';
const adminPassword = 'a-long-random-admin-password';

async function fixture() {
  const logs = [], rows = new Map(), saved = [];
  const salt = randomId();
  const digest = await passwordDigest(adminPassword, salt);
  const cipher = createCipher('test-server-key-never-sent-to-browser');
  const settings = { allowed_origins: [origin], admin_password: { salt, digest } };
  const storage = {
    setting: async key => settings[key], limit: async () => true, clearLimit: async () => {},
    createSession: async row => rows.set(row.token_hash, structuredClone(row)),
    getSession: async key => rows.get(key), deleteSession: async key => rows.delete(key),
    claimSession: async (key, lease) => { const row = rows.get(key); if (!row || row.lease) return null; row.lease = lease; return { ...row }; },
    releaseSession: async (key, lease, value) => { const row = rows.get(key); if (row?.lease === lease) { row.cipher = value; delete row.lease; } },
    log: async row => logs.push(row), logs: async () => logs, cleanup: async () => {}
  };
  const gateway = {
    login: async () => ({ userId: uid, accessToken: privateAccess, refreshToken: privateRefresh }),
    authenticate: async session => session,
    notes: async () => [], save: async (auth, notes) => saved.push({ userId: auth.userId, notes }), logout: async () => {}
  };
  const handler = createHandler({ storage, gateway, cipher });
  async function call(path, { method = 'GET', data, token, admin, requestOrigin = origin } = {}) {
    const headers = { Origin: requestOrigin };
    if (data !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers['X-App-Session'] = token;
    if (admin) headers['X-Admin-Session'] = admin;
    const response = await handler(new Request('https://backend.example/functions/v1/notebyme-api' + path, { method, headers, body: data === undefined ? undefined : JSON.stringify(data) }));
    return { response, data: response.status === 204 ? null : await response.json() };
  }
  async function login() { return (await call('/login', { method: 'POST', data: { username: 'ngoc', password: '0123' } })).data.session; }
  return { call, login, storage, gateway, logs, rows, saved, cipher };
}

test('preflight works without exposing keys and denies another website', async () => {
  const f = await fixture();
  const allowed = await f.call('/notes', { method: 'OPTIONS' });
  assert.equal(allowed.response.status, 204);
  assert.equal(allowed.response.headers.get('Access-Control-Allow-Origin'), origin);
  const denied = await f.call('/health', { requestOrigin: 'https://evil.example' });
  assert.equal(denied.response.headers.get('Access-Control-Allow-Origin'), null);
  const deniedMutation = await f.call('/login', { method: 'POST', requestOrigin: 'https://evil.example', data: {} });
  assert.equal(deniedMutation.response.status, 403);
});

test('login returns only an opaque app session; database stores encrypted Supabase credentials', async () => {
  const f = await fixture(); const token = await f.login();
  assert.match(token, /^[A-Za-z0-9_-]{43}$/);
  const row = f.rows.get(await hash(token));
  assert.ok(row); assert.ok(!JSON.stringify(row).includes(privateAccess));
  assert.equal((await f.cipher.open(row.cipher)).refreshToken, privateRefresh);
  assert.ok(f.logs.every(row => !('password' in row) && !('username' in row)));
  const session = await f.call('/session', { token });
  assert.deepEqual(session.data.user, { id: uid });
  assert.ok(!JSON.stringify(session.data).includes(privateAccess));
});

test('unauthenticated users and regular users cannot read backend logs', async () => {
  const f = await fixture();
  assert.equal((await f.call('/notes')).response.status, 401);
  assert.equal((await f.call('/admin/logs')).response.status, 401);
  const token = await f.login();
  assert.equal((await f.call('/admin/logs', { admin: token })).response.status, 401);
});

test('note owner is derived from verified server session, never from request body', async () => {
  const f = await fixture(); const token = await f.login();
  const note = { id: noteId, user_id: 'attacker-selected-owner', title: 'private title', body: 'private content', updated_at: new Date().toISOString(), deleted: false };
  const result = await f.call('/notes', { method: 'PUT', token, data: { notes: [note] } });
  assert.equal(result.response.status, 200);
  assert.equal(f.saved[0].userId, uid);
  assert.equal(f.saved[0].notes[0].user_id, undefined);
  assert.ok(!JSON.stringify(f.logs).includes('private content'));
  assert.ok(!JSON.stringify(f.logs).includes('private title'));
});

test('upstream errors never leak exception messages, credentials or note data', async () => {
  const f = await fixture();
  f.gateway.login = async () => { throw new Error('service_role SECRET_PRIVATE_PASSWORD'); };
  const result = await f.call('/login', { method: 'POST', data: { username: 'ngoc', password: '0123' } });
  assert.equal(result.response.status, 503);
  assert.equal(result.data.error, 'BACKEND_UNAVAILABLE');
  assert.match(result.data.requestId, /^[0-9a-f-]{36}$/);
  assert.ok(!JSON.stringify({ result: result.data, logs: f.logs }).includes('SECRET_PRIVATE_PASSWORD'));
});

test('admin login is separate, supports log reading and revokes session on logout', async () => {
  const f = await fixture();
  const login = await f.call('/admin/login', { method: 'POST', data: { password: adminPassword } });
  assert.equal(login.response.status, 200);
  const admin = login.data.session;
  assert.equal((await f.call('/admin/logs', { admin })).response.status, 200);
  assert.equal((await f.call('/notes', { token: admin })).response.status, 401);
  await f.call('/admin/logout', { method: 'POST', admin, data: {} });
  assert.equal((await f.call('/admin/logs', { admin })).response.status, 401);
  assert.ok(!JSON.stringify(f.logs).includes(adminPassword));
});

test('expired upstream sessions are removed and cannot be reused', async () => {
  const f = await fixture(); const token = await f.login();
  f.gateway.authenticate = async () => { throw new ApiError(401, 'SESSION_EXPIRED'); };
  assert.equal((await f.call('/notes', { token })).response.status, 401);
  assert.equal(f.rows.size, 0);
});

test('public client error reporting ignores arbitrary messages and tokens', async () => {
  const f = await fixture();
  await f.call('/events', { method: 'POST', data: { event: 'client.startup_failed', password: 'secret!', message: privateRefresh } });
  assert.ok(!JSON.stringify(f.logs).includes(privateRefresh));
  assert.ok(!JSON.stringify(f.logs).includes('secret!'));
  assert.equal((await f.call('/events', { method: 'POST', data: { event: 'attacker_event' } })).response.status, 400);
});

test('server-side rate limit blocks brute force before authentication', async () => {
  const f = await fixture(); let called = false;
  f.storage.limit = async () => false;
  f.gateway.login = async () => { called = true; };
  const result = await f.call('/login', { method: 'POST', data: { username: 'ngoc', password: '0123' } });
  assert.equal(result.response.status, 429); assert.equal(called, false);
});

test('tampering with encrypted credentials fails authentication', async () => {
  const cipher = createCipher('test-key'); const sealed = await cipher.seal({ accessToken: privateAccess });
  const [iv, content] = sealed.split('.');
  const altered = (content[0] === 'A' ? 'B' : 'A') + content.slice(1);
  await assert.rejects(cipher.open(`${iv}.${altered}`));
});

test('logout revokes the app session even if upstream sign-out is unavailable', async () => {
  const f = await fixture(); const token = await f.login();
  f.gateway.logout = async () => { throw new ApiError(503, 'LOGOUT_UPSTREAM_FAILED'); };
  assert.equal((await f.call('/logout', { method: 'POST', token, data: {} })).response.status, 200);
  assert.equal((await f.call('/session', { token })).response.status, 401);
});

test('five failed PIN attempts lock the normalized username before further checks', async () => {
  const f = await fixture(); let attempts = 0; const counts = new Map();
  f.storage.limit = async (key, max) => {
    if (!key.startsWith('pin:')) return true;
    counts.set(key, (counts.get(key) || 0) + 1); return counts.get(key) <= max;
  };
  f.gateway.login = async () => { attempts++; throw new ApiError(401, 'LOGIN_FAILED'); };
  for (let i = 0; i < 5; i++) assert.equal((await f.call('/login', { method: 'POST', data: { username: i % 2 ? 'Ngoc' : 'ngoc', password: '0000' } })).response.status, 401);
  const blocked = await f.call('/login', { method: 'POST', data: { username: 'NGOC', password: '0000' } });
  assert.equal(blocked.response.status, 429); assert.equal(blocked.data.error, 'LOGIN_RATE_LIMITED'); assert.equal(attempts, 5);
});
