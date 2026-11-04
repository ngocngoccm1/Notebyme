import { request, clearSession, explain, report } from './api.js';
import { NotesStore } from './notes-store.js';
import { synchronize } from './sync.js';

const $ = id => document.getElementById(id);
let store = null, selected = null, epoch = 0, syncing = false, syncAgain = false;
let timer, saveTimer, listTimer, cacheOkay = true;
let controller = new AbortController();
const fmt = timestamp => new Date(timestamp).toLocaleString('vi-VN', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

function status(text) { $('status').textContent = text + (cacheOkay ? '' : ' · Không lưu được vào bộ nhớ thiết bị'); }
function persist() { if (store) cacheOkay = store.persist(); }
function renderList() {
  if (!store) return;
  const query = $('search').value.trim().toLocaleLowerCase();
  const notes = store.notes.filter(n => !n.deleted && `${n.title} ${n.body}`.toLocaleLowerCase().includes(query))
    .sort((a, b) => b.updated_at.localeCompare(a.updated_at));
  const fragment = document.createDocumentFragment();
  for (const note of notes) {
    const button = document.createElement('button');
    button.className = 'item' + (note.id === selected ? ' active' : '');
    const title = document.createElement('div'); title.className = 'item-title'; title.textContent = note.title.trim() || 'Không có tiêu đề';
    const preview = document.createElement('div'); preview.className = 'item-preview'; preview.textContent = note.body.replace(/\s+/g, ' ').slice(0, 100) || 'Ghi chú trống';
    const date = document.createElement('div'); date.className = 'item-date'; date.textContent = fmt(note.updated_at) + (note.dirty ? ' · Chưa đồng bộ' : '');
    button.append(title, preview, date); button.onclick = () => pick(note.id); fragment.append(button);
  }
  if (!notes.length) {
    const empty = document.createElement('div'); empty.className = 'empty-list'; empty.textContent = query ? 'Không tìm thấy ghi chú' : 'Chưa có ghi chú'; fragment.append(empty);
  }
  $('items').replaceChildren(fragment);
}
function render() {
  renderList();
  const note = store?.notes.find(n => n.id === selected && !n.deleted);
  $('editArea').classList.toggle('hidden', !note); $('empty').classList.toggle('hidden', !!note); $('editorBar').classList.toggle('hidden', !note);
  if (note && document.activeElement !== $('title') && document.activeElement !== $('body')) { $('title').value = note.title; $('body').value = note.body; }
}
function pick(id) {
  selected = id; document.activeElement?.blur(); render();
  const note = store.notes.find(n => n.id === id);
  if (note) { $('title').value = note.title; $('body').value = note.body; }
  $('shell').classList.add('open');
}
function schedule() { clearTimeout(timer); timer = setTimeout(sync, 1300); }
function updateNote() {
  if (!store || !selected) return;
  store.update(selected, { title: $('title').value, body: $('body').value });
  clearTimeout(saveTimer); saveTimer = setTimeout(() => { persist(); status(cacheOkay ? 'Đã lưu trên thiết bị' : 'Chưa lưu trên thiết bị'); }, 250);
  clearTimeout(listTimer); listTimer = setTimeout(renderList, 150);
  status('Đang lưu...'); schedule();
}
function resetSession() {
  epoch++; controller.abort(); controller = new AbortController();
  clearTimeout(timer); clearTimeout(saveTimer); clearTimeout(listTimer);
  syncing = false; syncAgain = false; store = null; selected = null; cacheOkay = true;
  $('title').value = ''; $('body').value = ''; $('search').value = ''; $('items').replaceChildren();
}
function showAuth(message = '') {
  resetSession(); $('app').classList.add('hidden'); $('auth').classList.remove('hidden');
  $('authMsg').textContent = message; $('password').value = '';
}
async function startSession(user) {
  resetSession();
  store = new NotesStore(user.id); selected = null;
  $('password').value = ''; $('auth').classList.add('hidden'); $('app').classList.remove('hidden'); $('shell').classList.remove('open');
  render(); status('Đã tải ghi chú trên thiết bị'); await sync();
}
async function sync() {
  if (!store || !navigator.onLine) { if (store) status('Offline · Thay đổi được giữ trên thiết bị'); return; }
  if (syncing) { syncAgain = true; return; }
  syncing = true; syncAgain = false;
  const local = store, generation = epoch, signal = controller.signal;
  const current = () => epoch === generation && store === local && !signal.aborted;
  persist(); status('Đang đồng bộ...');
  try {
    if (!await synchronize(local, (path, options) => request(path, { ...options, signal }), current, persist)) return;
    render();
    status(local.notes.some(note => note.dirty) ? 'Còn thay đổi chưa gửi' : 'Đã đồng bộ');
  } catch (error) {
    if (!current()) return;
    if (error.status === 401) { showAuth(explain(error)); return; }
    status(explain(error)); report('client.sync_failed');
  } finally {
    if (current()) {
      syncing = false;
      if (syncAgain) schedule();
    }
  }
}

function authBusy(busy) { $('loginBtn').disabled = busy; $('registerBtn').disabled = busy; }
$('authForm').onsubmit = async event => {
  event.preventDefault(); authBusy(true); $('authMsg').textContent = 'Đang đăng nhập...';
  try {
    const data = await request('/login', { method: 'POST', data: { email: $('email').value.trim(), password: $('password').value } });
    await startSession(data.user);
  } catch (error) { $('authMsg').textContent = explain(error); }
  finally { $('password').value = ''; authBusy(false); }
};
$('registerBtn').onclick = async () => {
  if (!$('email').reportValidity()) return;
  if ($('password').value.length < 8) { $('authMsg').textContent = 'Mật khẩu tài khoản mới cần ít nhất 8 ký tự.'; return; }
  authBusy(true);
  try {
    const data = await request('/register', { method: 'POST', data: { email: $('email').value.trim(), password: $('password').value } });
    if (data.user) await startSession(data.user);
    else $('authMsg').textContent = 'Kiểm tra email để xác nhận tài khoản, sau đó đăng nhập.';
  } catch (error) { $('authMsg').textContent = explain(error); }
  finally { $('password').value = ''; authBusy(false); }
};
$('logoutBtn').onclick = async () => {
  const old = store;
  if (old?.notes.some(note => note.dirty) && !confirm('Có thay đổi chưa đồng bộ. Đăng xuất sẽ xóa bản ghi chú trên thiết bị này. Bạn vẫn muốn đăng xuất?')) return;
  $('logoutBtn').disabled = true;
  try {
    await request('/logout', { method: 'POST', data: {} });
    clearSession(); old?.clear(); showAuth('Đã đăng xuất và xóa bản ghi chú trên thiết bị.');
  } catch (error) {
    if (error.status === 401) { clearSession(); old?.clear(); showAuth(explain(error)); }
    else status(explain(error));
  } finally { $('logoutBtn').disabled = false; }
};
$('addBtn').onclick = () => { if (!store) return; const note = store.create(); persist(); pick(note.id); $('title').focus(); status('Đã tạo ghi chú trên thiết bị'); schedule(); };
$('deleteBtn').onclick = () => {
  if (!store || !selected || !confirm('Xóa ghi chú này?')) return;
  store.update(selected, { deleted: true }); selected = null; persist(); $('shell').classList.remove('open'); render(); schedule();
};
$('backBtn').onclick = () => { $('shell').classList.remove('open'); document.activeElement?.blur(); };
$('search').oninput = () => { clearTimeout(listTimer); listTimer = setTimeout(renderList, 100); };
$('title').oninput = updateNote; $('body').oninput = updateNote; $('syncBtn').onclick = sync;
async function init() {
  $('authMsg').textContent = 'Đang kết nối máy chủ...';
  try { const data = await request('/session'); if (data.user) await startSession(data.user); else showAuth(); }
  catch (error) { showAuth(explain(error)); report('client.startup_failed'); }
}
$('retryBtn').onclick = init;
window.addEventListener('online', sync);
window.addEventListener('pagehide', persist);
document.addEventListener('visibilitychange', () => { if (document.hidden) persist(); else sync(); });
window.addEventListener('unhandledrejection', () => report('client.unhandled_error'));
window.addEventListener('error', () => report('client.unhandled_error'));
setInterval(() => { if (store && !document.hidden) sync(); }, 60000);
if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => {});
init();
