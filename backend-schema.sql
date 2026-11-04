-- Run after schema.sql. Backend tables are accessible only to Edge Functions.
create table if not exists public.backend_settings (
  key text primary key,
  value jsonb not null
);
-- Stable server-only PIN pepper. Never replace it for an existing installation.
insert into public.backend_settings (key, value)
values ('pin_pepper', to_jsonb(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')))
on conflict (key) do nothing;
create table if not exists public.backend_sessions (
  token_hash text primary key,
  role text not null check (role in ('user', 'admin')),
  user_id uuid references auth.users(id) on delete cascade,
  cipher text,
  expires_at timestamptz not null,
  lease_id uuid,
  leased_until timestamptz,
  created_at timestamptz not null default now(),
  check ((role = 'user' and user_id is not null and cipher is not null) or
         (role = 'admin' and user_id is null and cipher is null))
);
create index if not exists backend_sessions_expiry_idx on public.backend_sessions (expires_at);
create table if not exists public.backend_logs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  request_id uuid not null,
  level text not null check (level in ('info', 'warn', 'error')),
  event text not null check (event ~ '^[a-z_.]{1,64}$'),
  code text check (code ~ '^[A-Z_]{1,64}$'),
  status integer,
  duration_ms integer,
  route text,
  count integer
);
create index if not exists backend_logs_created_idx on public.backend_logs (created_at desc);
create table if not exists public.backend_rate_limits (
  key text primary key,
  count integer not null,
  expires_at timestamptz not null
);
alter table public.backend_settings enable row level security;
alter table public.backend_sessions enable row level security;
alter table public.backend_logs enable row level security;
alter table public.backend_rate_limits enable row level security;
drop policy if exists backend_settings_no_client_access on public.backend_settings;
create policy backend_settings_no_client_access on public.backend_settings as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists backend_sessions_no_client_access on public.backend_sessions;
create policy backend_sessions_no_client_access on public.backend_sessions as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists backend_logs_no_client_access on public.backend_logs;
create policy backend_logs_no_client_access on public.backend_logs as restrictive for all to anon, authenticated using (false) with check (false);
drop policy if exists backend_rate_limits_no_client_access on public.backend_rate_limits;
create policy backend_rate_limits_no_client_access on public.backend_rate_limits as restrictive for all to anon, authenticated using (false) with check (false);
revoke all on public.backend_settings, public.backend_sessions, public.backend_logs, public.backend_rate_limits from public, anon, authenticated;
grant select, insert, update, delete on public.backend_settings, public.backend_sessions, public.backend_logs, public.backend_rate_limits to service_role;

create or replace function public.backend_rate_limit(p_key text, p_limit integer, p_seconds integer)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare current_count integer;
begin
  if p_limit < 1 or p_limit > 1000 or p_seconds < 1 or p_seconds > 900 or length(p_key) > 200 then
    return false;
  end if;
  insert into public.backend_rate_limits as r (key, count, expires_at)
  values (p_key, 1, now() + make_interval(secs => p_seconds))
  on conflict (key) do update set
    count = case when r.expires_at <= now() then 1 else r.count + 1 end,
    expires_at = case when r.expires_at <= now() then excluded.expires_at else r.expires_at end
  returning count into current_count;
  return current_count <= p_limit;
end;
$$;
create or replace function public.backend_claim_session(p_hash text, p_lease uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  update public.backend_sessions as s
  set lease_id = p_lease, leased_until = now() + interval '45 seconds'
  where token_hash = p_hash and role = 'user' and expires_at > now()
    and (leased_until is null or leased_until <= now())
  returning to_jsonb(s);
$$;
create or replace function public.backend_release_session(p_hash text, p_lease uuid, p_cipher text)
returns void language sql security invoker set search_path = '' as $$
  update public.backend_sessions set cipher = p_cipher, lease_id = null, leased_until = null
  where token_hash = p_hash and lease_id = p_lease;
$$;
create or replace function public.backend_cleanup()
returns void language plpgsql security invoker set search_path = '' as $$
begin
  delete from public.backend_sessions where expires_at < now();
  delete from public.backend_rate_limits where expires_at < now() - interval '1 day';
  delete from public.backend_logs where created_at < now() - interval '14 days';
end;
$$;
revoke all on function public.backend_rate_limit(text, integer, integer), public.backend_claim_session(text, uuid), public.backend_release_session(text, uuid, text), public.backend_cleanup() from public, anon, authenticated;
grant execute on function public.backend_rate_limit(text, integer, integer), public.backend_claim_session(text, uuid), public.backend_release_session(text, uuid, text), public.backend_cleanup() to service_role;

-- Soft delete is the application's only delete path. User RLS remains enabled.
revoke all on public.notes from anon;
revoke truncate, references, trigger, delete on public.notes from authenticated;
grant select, insert, update on public.notes to authenticated;
create index if not exists notes_user_id_id_idx on public.notes (user_id, id);
