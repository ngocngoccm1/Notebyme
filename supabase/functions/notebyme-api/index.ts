import { createGateway } from './gateway.js';
import { createStorage } from './storage.js';
import { createCipher } from './crypto.js';
import { createHandler } from './handler.js';

const url = Deno.env.get('SUPABASE_URL')!;
const serverKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const userKey = Deno.env.get('SUPABASE_ANON_KEY')!;
Deno.serve(createHandler({
  storage: createStorage(url, serverKey),
  gateway: createGateway(url, userKey),
  cipher: createCipher(serverKey)
}));
