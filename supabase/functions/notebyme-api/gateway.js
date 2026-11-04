import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { ApiError } from './errors.js';
import { createUsernameAuth } from './username-auth.js';
function authError(error, fallback) {
  if (error?.status === 429) throw new ApiError(429, 'RATE_LIMITED');
  if ([400, 401, 403].includes(error?.status)) throw new ApiError(401, fallback || 'SESSION_EXPIRED');
  throw new ApiError(503, 'AUTH_UNAVAILABLE');
}

export function createGateway(url, key, serverKey, storage) {
  const client = () => createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (input, options = {}) => fetch(input, { ...options, signal: AbortSignal.timeout(12000) }) }
  });
  const admin = createClient(url, serverKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (input, options = {}) => fetch(input, { ...options, signal: AbortSignal.timeout(12000) }) } });
  return {
    login: createUsernameAuth({
      getPepper: () => storage.setting('pin_pepper'),
      signIn: identity => client().auth.signInWithPassword(identity),
      createUser: identity => admin.auth.admin.createUser(identity)
    }),
    async authenticate(session) {
      const sb = client();
      const { data, error } = await sb.auth.setSession({ access_token: session.accessToken, refresh_token: session.refreshToken });
      if (error) authError(error);
      const verified = await sb.auth.getUser();
      if (verified.error) authError(verified.error);
      if (!verified.data.user || verified.data.user.id !== session.userId) throw new ApiError(401, 'SESSION_EXPIRED');
      return {
        sb, userId: verified.data.user.id,
        accessToken: data.session.access_token, refreshToken: data.session.refresh_token
      };
    },
    async notes(auth) {
      const rows = [];
      let cursor;
      while (true) {
        let query = auth.sb.from('notes').select('id,title,body,updated_at,deleted')
          .eq('user_id', auth.userId).order('id').limit(500);
        if (cursor) query = query.gt('id', cursor);
        const { data, error } = await query;
        if (error) throw new ApiError(503, 'NOTES_READ_FAILED');
        if (!data.length) return rows;
        rows.push(...data);
        cursor = data.at(-1).id;
        if (rows.length > 50000) throw new ApiError(413, 'NOTES_LIMIT_EXCEEDED');
      }
    },
    async save(auth, notes) {
      const { error } = await auth.sb.from('notes').upsert(notes.map(note => ({ ...note, user_id: auth.userId })), { onConflict: 'id' });
      if (error) throw new ApiError(503, 'NOTES_WRITE_FAILED');
    },
    async logout(auth) {
      const { error } = await auth.sb.auth.signOut({ scope: 'local' });
      if (error) throw new ApiError(503, 'LOGOUT_UPSTREAM_FAILED');
    }
  };
}
