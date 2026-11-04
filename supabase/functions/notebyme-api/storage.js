import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

export function createStorage(url, key) {
  const sb = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: (input, options = {}) => fetch(input, { ...options, signal: AbortSignal.timeout(12000) }) }
  });
  async function checked(query) {
    const { data, error } = await query;
    if (error) throw new Error('BACKEND_STORAGE_FAILED');
    return data;
  }
  return {
    setting: key => checked(sb.from('backend_settings').select('value').eq('key', key).maybeSingle()).then(row => row?.value),
    limit: (key, maximum, seconds) => checked(sb.rpc('backend_rate_limit', { p_key: key, p_limit: maximum, p_seconds: seconds })),
    clearLimit: key => checked(sb.from('backend_rate_limits').delete().eq('key', key)),
    createSession: row => checked(sb.from('backend_sessions').insert(row)),
    getSession: tokenHash => checked(sb.from('backend_sessions').select('*').eq('token_hash', tokenHash).gt('expires_at', new Date().toISOString()).maybeSingle()),
    updateSession: (tokenHash, cipher) => checked(sb.from('backend_sessions').update({ cipher }).eq('token_hash', tokenHash)),
    claimSession: (tokenHash, lease) => checked(sb.rpc('backend_claim_session', { p_hash: tokenHash, p_lease: lease })),
    releaseSession: (tokenHash, lease, cipher) => checked(sb.rpc('backend_release_session', { p_hash: tokenHash, p_lease: lease, p_cipher: cipher })),
    deleteSession: tokenHash => checked(sb.from('backend_sessions').delete().eq('token_hash', tokenHash)),
    log: row => checked(sb.from('backend_logs').insert(row)),
    logs: (level, limit) => {
      let query = sb.from('backend_logs').select('id,created_at,level,event,code,request_id,status,duration_ms,route,count').order('created_at', { ascending: false }).limit(limit);
      if (level) query = query.eq('level', level);
      return checked(query);
    },
    cleanup: () => checked(sb.rpc('backend_cleanup'))
  };
}
