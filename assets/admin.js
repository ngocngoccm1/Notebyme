import { request, clearSession, explain } from './api.js';
const $ = id => document.getElementById(id);
let entries = [];
function showLogin(message = '') { $('adminAuth').classList.remove('hidden'); $('logPanel').classList.add('hidden'); $('adminMessage').textContent = message; $('adminPassword').value = ''; $('logRows').replaceChildren(); entries = []; }
function render() {
  const search = $('logSearch').value.toLocaleLowerCase().trim();
  const rows = entries.filter(row => !search || `${row.event} ${row.code || ''} ${row.request_id} ${row.route || ''}`.toLocaleLowerCase().includes(search));
  const fragment = document.createDocumentFragment();
  for (const row of rows) {
    const tr = document.createElement('tr');
    const values = [new Date(row.created_at).toLocaleString('vi-VN'), row.level, row.event, [row.code, row.route].filter(Boolean).join(' · '), row.status || '', row.request_id];
    for (const value of values) { const td = document.createElement('td'); td.textContent = value; tr.append(td); }
    fragment.append(tr);
  }
  if (!rows.length) { const tr = document.createElement('tr'); const td = document.createElement('td'); td.colSpan = 6; td.textContent = 'Không có sự kiện phù hợp.'; tr.append(td); fragment.append(tr); }
  $('logRows').replaceChildren(fragment); $('logSummary').textContent = `${rows.length} sự kiện · Cập nhật ${new Date().toLocaleTimeString('vi-VN')}`;
}
async function refresh() {
  $('refreshLogs').disabled = true;
  try {
    const data = await request(`/admin/logs?limit=200&level=${encodeURIComponent($('logLevel').value)}`, { admin: true });
    entries = data.entries; render(); $('adminMessage').textContent = '';
  } catch (error) { if (error.status === 401) showLogin(explain(error)); else $('adminMessage').textContent = explain(error); }
  finally { $('refreshLogs').disabled = false; }
}
async function showPanel() { $('adminAuth').classList.add('hidden'); $('logPanel').classList.remove('hidden'); await refresh(); }
$('adminForm').onsubmit = async event => {
  event.preventDefault(); $('adminLoginBtn').disabled = true;
  try { await request('/admin/login', { method: 'POST', data: { password: $('adminPassword').value }, admin: true }); $('adminPassword').value = ''; await showPanel(); }
  catch (error) { $('adminMessage').textContent = explain(error); }
  finally { $('adminPassword').value = ''; $('adminLoginBtn').disabled = false; }
};
$('adminLogoutBtn').onclick = async () => {
  try { await request('/admin/logout', { method: 'POST', data: {}, admin: true }); clearSession(true); showLogin('Đã đăng xuất quản trị.'); }
  catch (error) { if (error.status === 401) showLogin(); else $('adminMessage').textContent = explain(error); }
};
$('refreshLogs').onclick = refresh; $('logLevel').onchange = refresh; $('logSearch').oninput = render;
try { await request('/admin/session', { admin: true }); await showPanel(); }
catch (error) { showLogin(error.status === 401 ? '' : explain(error)); }
