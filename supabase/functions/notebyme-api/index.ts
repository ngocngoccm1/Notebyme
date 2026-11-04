import { createGateway } from './gateway.js';
import { createStorage } from './storage.js';
import { createCipher } from './crypto.js';
import { createHandler } from './handler.js';

const url = Deno.env.get('SUPABASE_URL')!;
const serverKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const userKey = Deno.env.get('SUPABASE_ANON_KEY')!;
const storage = createStorage(url, serverKey);
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };
Deno.serve(createHandler({
  storage,
  gateway: createGateway(url, userKey, serverKey, storage),
  cipher: createCipher(serverKey),
  defer: task => EdgeRuntime.waitUntil(task)
}));
