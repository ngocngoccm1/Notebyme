import { API_URL } from './config.js';

const namespace = 'notebyme-backend-v1';
const keys = { user: `${namespace}:user-session`, admin: `${namespace}:admin-session` };
const memory = new Map();
function read(key) { try { return sessionStorage.getItem(key); } catch { return memory.get(key) || null; } }
function write(key, value) {
  if (value) memory.set(key, value); else memory.delete(key);
  try { if (value) sessionStorage.setItem(key, value); else sessionStorage.removeItem(key); } catch { /* In-memory session still works. */ }
}

export class ApiError extends Error {
  constructor(code, status = 0, requestId = '') { super(code); this.code = code; this.status = status; this.requestId = requestId; }
}
export function clearSession(admin = false) { write(admin ? keys.admin : keys.user, null); }

export async function request(path, { method = 'GET', data, signal, admin = false, retry = 0 } = {}) {
  const headers = {};
  const token = read(admin ? keys.admin : keys.user);
  if (token) headers[admin ? 'X-Admin-Session' : 'X-App-Session'] = token;
  if (data !== undefined) headers['Content-Type'] = 'application/json';
  let response;
  try {
    response = await fetch(API_URL + path, {
      method, headers, body: data === undefined ? undefined : JSON.stringify(data),
      cache: 'no-store', credentials: 'omit', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(25000)]) : AbortSignal.timeout(25000)
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    if (method === 'GET' && retry < 1) return request(path, { method, data, signal, admin, retry: retry + 1 });
    throw new ApiError('NETWORK_ERROR');
  }
  let result;
  try { result = await response.json(); } catch { throw new ApiError('BACKEND_UNAVAILABLE', response.status); }
  if (!response.ok) {
    if (result.error === 'SESSION_BUSY' && retry < 2 && !signal?.aborted) {
      await new Promise(resolve => setTimeout(resolve, 500));
      return request(path, { method, data, signal, admin, retry: retry + 1 });
    }
    if (response.status === 401) clearSession(admin);
    throw new ApiError(result.error || 'BACKEND_UNAVAILABLE', response.status, result.requestId);
  }
  if (result.session) {
    write(admin ? keys.admin : keys.user, result.session);
    delete result.session;
  }
  return result;
}

const messages = {
  NETWORK_ERROR: 'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
  BACKEND_UNAVAILABLE: 'Máy chủ đang gặp sự cố.', BACKEND_NOT_CONFIGURED: 'Máy chủ chưa sẵn sàng.',
  AUTH_UNAVAILABLE: 'Dịch vụ đăng nhập đang gặp sự cố.', LOGIN_FAILED: 'Tên đăng nhập hoặc mật khẩu không đúng.',
  REGISTRATION_FAILED: 'Chưa thể tạo tài khoản. Vui lòng thử lại sau.',
  USERNAME_TAKEN: 'Tên đăng nhập này đã được sử dụng.',
  INVALID_USERNAME: 'Tên đăng nhập từ 1 đến 32 ký tự, gồm chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.',
  INVALID_PIN: 'Mật khẩu cần đúng 4 chữ số.',
  LOGIN_RATE_LIMITED: 'Đã thử sai quá nhiều lần. Vui lòng chờ 15 phút rồi thử lại.',
  SESSION_EXPIRED: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
  ADMIN_REQUIRED: 'Đăng nhập quản trị để xem nhật ký.', ADMIN_LOGIN_FAILED: 'Mật khẩu quản trị không đúng.',
  ADMIN_NOT_CONFIGURED: 'Trang nhật ký chưa được cấu hình.', RATE_LIMITED: 'Bạn thao tác quá nhanh. Vui lòng thử lại sau.',
  INVALID_NOTES: 'Ghi chú quá dài hoặc dữ liệu không hợp lệ. Tiêu đề tối đa 500 ký tự, nội dung tối đa 100.000 ký tự.',
  NOTES_READ_FAILED: 'Chưa tải được ghi chú từ máy chủ.', NOTES_WRITE_FAILED: 'Chưa gửi được thay đổi lên máy chủ.',
  SESSION_BUSY: 'Một thao tác khác đang chạy. Vui lòng thử lại.', ORIGIN_REJECTED: 'Địa chỉ website chưa được máy chủ cho phép.'
};
export function explain(error) {
  return (messages[error.code] || 'Thao tác chưa thành công. Vui lòng thử lại.') + (error.requestId ? ` Mã tra cứu: ${error.requestId}` : '');
}
export function report(event) {
  if (['client.startup_failed', 'client.sync_failed', 'client.unhandled_error'].includes(event)) {
    request('/events', { method: 'POST', data: { event } }).catch(() => {});
  }
}
