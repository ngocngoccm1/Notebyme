import { ApiError } from './errors.js';
import { encode } from './crypto.js';
const encoder = new TextEncoder();

export function credentials(data) {
  if (typeof data.username !== 'string') throw new ApiError(400, 'INVALID_USERNAME');
  const username = data.username.trim().normalize('NFC').toLocaleLowerCase('vi-VN').normalize('NFC');
  if (username.length < 1 || username.length > 32 || !/^[\p{L}\p{M}\p{N}_.-]+$/u.test(username) || !/[\p{L}\p{N}]/u.test(username)) {
    throw new ApiError(400, 'INVALID_USERNAME');
  }
  if (typeof data.password !== 'string' || !/^[0-9]{4}$/.test(data.password)) throw new ApiError(400, 'INVALID_PIN');
  return { username, password: data.password };
}

export async function deriveIdentity(username, pin, pepper) {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode('notebyme-username:' + username));
  const name = [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
  const key = await crypto.subtle.importKey('raw', encoder.encode(pepper), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(username + '\0' + pin));
  // Managed Auth requires an internal identifier. This synthetic, confirmed
  // identity is never shown to users and never sends email. The server-side
  // pepper lets the PIN meet Auth's password policy without storing plaintext.
  return { email: name.slice(0, 48) + '@users.notebyme.invalid', password: encode(signature) + 'aA1!' };
}

export function createUsernameAuth({ getPepper, signIn, createUser }) {
  let pepper;
  return async (username, pin, register = false) => {
    pepper ||= await getPepper();
    if (typeof pepper !== 'string' || pepper.length < 32) throw new ApiError(503, 'BACKEND_NOT_CONFIGURED');
    const identity = await deriveIdentity(username, pin, pepper);
    if (register) {
      const { error } = await createUser({ ...identity, email_confirm: true });
      if (['email_exists', 'user_already_exists'].includes(error?.code)) throw new ApiError(409, 'USERNAME_TAKEN');
      if (error) throw new ApiError(503, 'REGISTRATION_FAILED');
    }
    const { data, error } = await signIn(identity);
    if (error?.status === 429) throw new ApiError(429, 'RATE_LIMITED');
    if ([400, 401, 403].includes(error?.status)) throw new ApiError(401, 'LOGIN_FAILED');
    if (error || !data?.session || !data.user) throw new ApiError(503, 'AUTH_UNAVAILABLE');
    return { userId: data.user.id, accessToken: data.session.access_token, refreshToken: data.session.refresh_token };
  };
}
