import test from 'node:test';
import assert from 'node:assert/strict';
import { credentials, deriveIdentity, createUsernameAuth } from '../supabase/functions/notebyme-api/username-auth.js';

const pepper = 'a-server-only-random-pepper-at-least-32-characters';
test('username login preserves leading-zero PINs and normalizes names', () => {
  assert.deepEqual(credentials({ username: '  Ngọc_01  ', password: '0042' }), { username: 'ngọc_01', password: '0042' });
  assert.deepEqual(credentials({ username: 'Ngo\u0323c_01', password: '0042' }), { username: 'ngọc_01', password: '0042' });
});
test('only exactly four ASCII digits are accepted', () => {
  for (const password of ['123', '12345', '12a4', ' 1234', '１２３４', 1234]) {
    assert.throws(() => credentials({ username: 'ngoc', password }), error => error.code === 'INVALID_PIN');
  }
});
test('emails, whitespace-only names and oversized names are rejected', () => {
  for (const username of ['person@example.com', ' ', 'two names', 'a'.repeat(33), '../']) {
    assert.throws(() => credentials({ username, password: '1234' }), error => error.code === 'INVALID_USERNAME');
  }
});
test('server pepper derives a stable strong credential without changing the username identity', async () => {
  const first = await deriveIdentity('ngoc', '0042', pepper);
  const repeated = await deriveIdentity('ngoc', '0042', pepper);
  const anotherPin = await deriveIdentity('ngoc', '0043', pepper);
  const anotherUser = await deriveIdentity('other', '0042', pepper);
  assert.deepEqual(first, repeated); assert.equal(first.email, anotherPin.email);
  assert.notEqual(first.password, anotherPin.password); assert.notEqual(first.email, anotherUser.email);
  assert.ok(first.password.length >= 32); assert.notEqual(first.password, '0042');
});
test('registration creates a confirmed internal identity and logs in immediately', async () => {
  let created;
  const login = createUsernameAuth({
    getPepper: async () => pepper,
    createUser: async input => { created = input; return { error: null }; },
    signIn: async () => ({ data: { user: { id: 'user-id' }, session: { access_token: 'private-access', refresh_token: 'private-refresh' } } })
  });
  const session = await login('ngoc', '0042', true);
  assert.equal(created.email_confirm, true); assert.equal(session.userId, 'user-id');
  assert.equal(session.accessToken, 'private-access'); assert.notEqual(created.password, '0042');
});
test('duplicate usernames fail without attempting login', async () => {
  let attempted = false;
  const login = createUsernameAuth({ getPepper: async () => pepper,
    createUser: async () => ({ error: { code: 'email_exists' } }),
    signIn: async () => { attempted = true; }
  });
  await assert.rejects(login('ngoc', '0042', true), error => error.code === 'USERNAME_TAKEN');
  assert.equal(attempted, false);
});
test('unknown username and wrong PIN share the same login error', async () => {
  const login = createUsernameAuth({ getPepper: async () => pepper, createUser: async () => ({}),
    signIn: async () => ({ error: { status: 400, code: 'invalid_credentials' } })
  });
  await assert.rejects(login('ngoc', '9999'), error => error.status === 401 && error.code === 'LOGIN_FAILED');
});
