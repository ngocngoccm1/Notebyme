import { ApiError } from './errors.js';
import { hash, randomId, checkPassword } from './crypto.js';

const ROUTES = new Set(['/health', '/session', '/login', '/register', '/logout', '/notes', '/events', '/admin/session', '/admin/login', '/admin/logout', '/admin/logs']);
const CLIENT_EVENTS = new Set(['client.startup_failed', 'client.sync_failed', 'client.unhandled_error']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function readBody(request, maximum = 2 * 1024 * 1024) {
  if (!/^application\/json(?:;|$)/i.test(request.headers.get('content-type') || '')) throw new ApiError(415, 'JSON_REQUIRED');
  if (Number(request.headers.get('content-length')) > maximum) throw new ApiError(413, 'REQUEST_TOO_LARGE');
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, 'INVALID_JSON');
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > maximum) { await reader.cancel(); throw new ApiError(413, 'REQUEST_TOO_LARGE'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new ApiError(400, 'INVALID_JSON'); }
}

function credentials(data) {
  if (typeof data.email !== 'string' || typeof data.password !== 'string' || data.email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(data.email.trim()) || data.password.length < 6 || data.password.length > 1024) {
    throw new ApiError(400, 'INVALID_CREDENTIALS');
  }
  return { email: data.email.trim(), password: data.password };
}

function validateNotes(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 100) throw new ApiError(400, 'INVALID_NOTES');
  const ids = new Set();
  return value.map(note => {
    if (!note || !UUID.test(note.id) || ids.has(note.id) || typeof note.title !== 'string' || typeof note.body !== 'string' ||
        note.title.length > 500 || note.body.length > 100000 || typeof note.deleted !== 'boolean' ||
        typeof note.updated_at !== 'string' || !Number.isFinite(Date.parse(note.updated_at))) throw new ApiError(400, 'INVALID_NOTES');
    ids.add(note.id);
    // user_id and all other client-supplied fields are discarded.
    return { id: note.id, title: note.title, body: note.body, deleted: note.deleted, updated_at: new Date(note.updated_at).toISOString() };
  });
}

export function createHandler({ storage, gateway, cipher, functionName = 'notebyme-api' }) {
  let originsCache;
  async function origins() {
    if (!originsCache || originsCache.until < Date.now()) {
      const value = await storage.setting('allowed_origins');
      if (!Array.isArray(value) || !value.length) throw new ApiError(503, 'BACKEND_NOT_CONFIGURED');
      originsCache = { value, until: Date.now() + 60000 };
    }
    return originsCache.value;
  }
  async function rate(key, maximum, seconds) {
    if (!await storage.limit(key, maximum, seconds)) throw new ApiError(429, 'RATE_LIMITED');
  }
  async function record(event, { requestId, code, status, duration, route, count, level = 'info' }) {
    const row = {
      request_id: requestId, event, level,
      ...(code ? { code } : {}), ...(status ? { status } : {}),
      ...(ROUTES.has(route) ? { route } : {}),
      ...(Number.isFinite(duration) ? { duration_ms: Math.round(Math.max(0, duration)) } : {}),
      ...(Number.isInteger(count) ? { count } : {})
    };
    try { await storage.log(row); }
    catch { console.error(JSON.stringify({ event: 'logger.storage_failed', requestId })); }
  }
  async function session(request, role) {
    const token = request.headers.get(role === 'admin' ? 'x-admin-session' : 'x-app-session');
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new ApiError(401, role === 'admin' ? 'ADMIN_REQUIRED' : 'SESSION_EXPIRED');
    const tokenHash = await hash(token);
    const row = await storage.getSession(tokenHash);
    if (!row || row.role !== role) throw new ApiError(401, role === 'admin' ? 'ADMIN_REQUIRED' : 'SESSION_EXPIRED');
    return { tokenHash, row };
  }
  async function establish(data, role = 'user') {
    const token = randomId();
    await storage.createSession({
      token_hash: await hash(token), role, user_id: data?.userId || null,
      cipher: data ? await cipher.seal(data) : null,
      expires_at: new Date(Date.now() + (role === 'admin' ? 3600000 : 43200000)).toISOString()
    });
    return token;
  }
  async function withUser(request, requestId, callback) {
    const { tokenHash } = await session(request, 'user');
    await rate(`session:${tokenHash}`, 120, 60);
    let row;
    for (let attempt = 0; attempt < 8; attempt++) {
      row = await storage.claimSession(tokenHash, requestId);
      if (row) break;
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    if (!row) throw new ApiError(409, 'SESSION_BUSY');
    let refreshed;
    try {
      const tokens = await cipher.open(row.cipher);
      const auth = await gateway.authenticate(tokens);
      if (auth.userId !== row.user_id) throw new ApiError(401, 'SESSION_EXPIRED');
      refreshed = await cipher.seal({ userId: auth.userId, accessToken: auth.accessToken, refreshToken: auth.refreshToken });
      return await callback(auth, tokenHash);
    } catch (error) {
      if (error.status === 401) await storage.deleteSession(tokenHash);
      throw error;
    } finally {
      await storage.releaseSession(tokenHash, requestId, refreshed || row.cipher);
    }
  }

  return async request => {
    const started = performance.now();
    const requestId = crypto.randomUUID();
    const responseHeaders = new Headers({
      'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'X-Request-ID': requestId,
      'Access-Control-Expose-Headers': 'X-Request-ID', 'Vary': 'Origin'
    });
    let route;
    let status = 200;
    let event = 'http.completed';
    let count;
    let code;
    let result;
    try {
      const path = new URL(request.url).pathname;
      const prefix = `/functions/v1/${functionName}`;
      // The deployed gateway may forward either the full path or just /<slug>.
      route = path.startsWith(prefix) ? path.slice(prefix.length) : path.startsWith(`/${functionName}`) ? path.slice(functionName.length + 1) : path;
      route ||= '/health';
      const origin = request.headers.get('origin');
      const allowed = await origins();
      if (origin && allowed.includes(origin)) responseHeaders.set('Access-Control-Allow-Origin', origin);
      else if (route !== '/health' || request.method !== 'GET') throw new ApiError(403, 'ORIGIN_REJECTED');
      if (request.method === 'OPTIONS') {
        responseHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS');
        responseHeaders.set('Access-Control-Allow-Headers', 'content-type, x-app-session, x-admin-session');
        responseHeaders.set('Access-Control-Max-Age', '600');
        return new Response(null, { status: 204, headers: responseHeaders });
      }
      const endpoint = `${request.method} ${route}`;
      await rate('public:requests', 300, 60);
      if (endpoint === 'GET /health') result = { ok: true };
      else if (endpoint === 'POST /login' || endpoint === 'POST /register') {
        await rate('public:auth', 30, 60);
        const data = credentials(await readBody(request, 4096));
        const register = route === '/register';
        if (register && data.password.length < 8) throw new ApiError(400, 'PASSWORD_TOO_SHORT');
        const auth = await gateway.login(data.email, data.password, register);
        result = auth ? { user: { id: auth.userId }, session: await establish(auth) } : { user: null, confirmationRequired: true };
        event = register ? 'auth.register' : 'auth.login';
      } else if (endpoint === 'GET /session') {
        if (!request.headers.get('x-app-session')) result = { user: null };
        else result = await withUser(request, requestId, async auth => ({ user: { id: auth.userId } }));
      } else if (endpoint === 'GET /notes') {
        const notes = await withUser(request, requestId, auth => gateway.notes(auth));
        result = { notes }; count = notes.length; event = 'notes.loaded';
      } else if (endpoint === 'PUT /notes') {
        const notes = validateNotes((await readBody(request)).notes);
        await withUser(request, requestId, auth => gateway.save(auth, notes));
        result = { saved: notes.map(note => note.id) }; count = notes.length; event = 'notes.saved';
      } else if (endpoint === 'POST /logout') {
        await withUser(request, requestId, async (auth, tokenHash) => {
          try { await gateway.logout(auth); }
          catch { code = 'LOGOUT_UPSTREAM_FAILED'; }
          finally { await storage.deleteSession(tokenHash); }
        });
        result = { ok: true }; event = 'auth.logout';
      } else if (endpoint === 'POST /admin/login') {
        await rate('public:admin-login', 8, 900);
        const data = await readBody(request, 2048);
        const password = await storage.setting('admin_password');
        if (!password) throw new ApiError(503, 'ADMIN_NOT_CONFIGURED');
        if (typeof data.password !== 'string' || data.password.length > 1024 || !await checkPassword(data.password, password)) {
          throw new ApiError(401, 'ADMIN_LOGIN_FAILED');
        }
        result = { session: await establish(null, 'admin') }; event = 'admin.login';
      } else if (endpoint === 'GET /admin/session') {
        await session(request, 'admin'); result = { ok: true };
      } else if (endpoint === 'GET /admin/logs') {
        const admin = await session(request, 'admin');
        await rate(`admin:${admin.tokenHash}`, 60, 60);
        const params = new URL(request.url).searchParams;
        const level = params.get('level') || undefined;
        const limit = Number(params.get('limit') || 100);
        if ((level && !['info', 'warn', 'error'].includes(level)) || !Number.isInteger(limit) || limit < 1 || limit > 200) throw new ApiError(400, 'INVALID_FILTER');
        result = { entries: await storage.logs(level, limit) };
      } else if (endpoint === 'POST /admin/logout') {
        const admin = await session(request, 'admin');
        await storage.deleteSession(admin.tokenHash); result = { ok: true }; event = 'admin.logout';
      } else if (endpoint === 'POST /events') {
        await rate('public:events', 30, 60);
        const data = await readBody(request, 2048);
        if (!CLIENT_EVENTS.has(data.event)) throw new ApiError(400, 'INVALID_EVENT');
        event = data.event; result = { ok: true }; code = 'CLIENT_ERROR';
      } else throw new ApiError(404, 'NOT_FOUND');
    } catch (error) {
      status = error instanceof ApiError ? error.status : 503;
      code = error instanceof ApiError ? error.code : 'BACKEND_UNAVAILABLE';
      result = { error: code };
      event = 'http.failed';
      if (status === 429) responseHeaders.set('Retry-After', '60');
    }
    // Bound application-log writes for unauthenticated abuse. Successful health
    // probes and rate-limited retries do not fill the durable log table.
    const shouldLog = status !== 429 && !(route === '/health' && status === 200) &&
      (status < 400 || await storage.limit('logs:failures', 20, 60).catch(() => false));
    if (shouldLog) await record(event, { requestId, code, status, route, count, duration: performance.now() - started, level: status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info' });
    // Bounded retention. Cleanup never includes note data.
    if (Math.random() < 0.01) await storage.cleanup().catch(() => {});
    return new Response(JSON.stringify({ ...result, requestId }), { status, headers: responseHeaders });
  };
}
