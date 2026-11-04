import { mkdir, writeFile, access } from 'node:fs/promises';
import { randomId, passwordDigest } from '../supabase/functions/notebyme-api/crypto.js';

try { await access('.env'); throw new Error('.env already exists. Preserve it before generating a new admin password.'); }
catch (error) { if (error.code !== 'ENOENT') throw error; }
const password = randomId(), salt = randomId();
const digest = await passwordDigest(password, salt);
await mkdir('.data', { recursive: true, mode: 0o700 });
await writeFile('.env', `LOG_ADMIN_PASSWORD=${password}\n`, { mode: 0o600 });
const settings = JSON.stringify({ salt, digest });
await writeFile('.data/admin-bootstrap.sql', `insert into public.backend_settings (key,value) values ('admin_password','${settings}'::jsonb) on conflict (key) do update set value=excluded.value;\ndelete from public.backend_sessions where role='admin';\n`, { mode: 0o600 });
console.log('Password: .env (ignored by Git). Apply .data/admin-bootstrap.sql in Supabase SQL Editor.');
