const encoder = new TextEncoder();
export const encode = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
export const decode = text => Uint8Array.from(atob(text.replaceAll('-', '+').replaceAll('_', '/')), char => char.charCodeAt(0));
export const randomId = () => encode(crypto.getRandomValues(new Uint8Array(32)));
export async function hash(text) { return encode(await crypto.subtle.digest('SHA-256', encoder.encode(text))); }

export function createCipher(secret) {
  const key = crypto.subtle.digest('SHA-256', encoder.encode(secret))
    .then(bytes => crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']));
  return {
    async seal(value) {
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const bytes = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key, encoder.encode(JSON.stringify(value)));
      return `${encode(iv)}.${encode(bytes)}`;
    },
    async open(value) {
      const [iv, bytes] = value.split('.');
      const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: decode(iv) }, await key, decode(bytes));
      return JSON.parse(new TextDecoder().decode(plain));
    }
  };
}

export async function passwordDigest(password, salt) {
  const key = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
  return encode(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: decode(salt), iterations: 210000 }, key, 256));
}
export async function checkPassword(password, config) {
  const actual = await passwordDigest(password, config.salt);
  let different = actual.length ^ config.digest.length;
  for (let i = 0; i < actual.length; i++) different |= actual.charCodeAt(i) ^ config.digest.charCodeAt(i);
  return different === 0;
}
