/* Islamia BOS · Notifications (#/notifications) and the header bell.
   The job: show the notes the server made for this person (red exceptions waiting, approvals waiting, low stock, expiring batches, overdue dues,
   shops that did not close the day, big cash gaps, stale backup ...), newest first, with an unread badge. Tapping a note opens its screen and marks it read.
   No push: the unread count is polled every 60 seconds while the app is open (one cheap RPC).
   Server (supabase/phase46.sql): notifications_for_me(p_limit, p_unread_only, p_level), notifications_unread_count(), notification_read(p_id), notification_read_all(),
   and for the owner backup_status() + the backup_runs table (last backup runs).
   Header bell (the lead adds it, see docs/regs/notifications.md):  B.notifications.badge()  returns the bell button HTML; the number inside every
   element with class "nt-badge" is kept up to date by the poll. Switches and thresholds live in the Switchboard (#/switchboard) - this page links there. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('নোটিফিকেশন', 'Notifications', 'Notification'), all: L('সব', 'All', 'সব'), unread: L('না-পড়া', 'Unread', 'না-পড়া'), lvl: L('গুরুত্ব', 'Level', 'গুরুত্ব'),
  lAll: L('সব স্তর', 'All levels', 'সব level'), lInfo: L('তথ্য', 'Info', 'Info'), lWarn: L('সতর্কতা', 'Warning', 'Warning'), lBad: L('জরুরি', 'Urgent', 'Urgent'),
  readAll: L('সব পড়া হয়েছে', 'Mark all read', 'সব read'), none: L('কোনো নোটিফিকেশন নেই', 'No notifications', 'কোনো notification নেই'), settings: L('কোনটা জানাবে — সুইচবোর্ডে', 'What to be told about - Switchboard', 'কোনটা জানাবে — Switchboard'),
  backup: L('স্বয়ংক্রিয় ব্যাকআপ', 'Automatic backup', 'Auto backup'), lastOk: L('শেষ সফল', 'Last good one', 'শেষ OK'), never: L('এখনো হয়নি', 'None yet', 'এখনো হয়নি'),
  hoursAgo: L('ঘণ্টা আগে', 'hours ago', 'ঘণ্টা আগে'), stale: L('পুরনো হয়ে গেছে', 'Out of date', 'পুরনো'), fresh: L('ঠিক আছে', 'Up to date', 'ঠিক আছে'), notSet: L('এখনো চালু করা হয়নি (OPS_SETUP দেখুন)', 'Not set up yet (see OPS_SETUP)', 'এখনো set up হয়নি (OPS_SETUP দেখুন)'),
  runs: L('সাম্প্রতিক রান', 'Recent runs', 'Recent run'), rows: L('সারি', 'rows', 'row'), loadFail: L('লোড করা যায়নি', 'Could not load', 'Load হয়নি'),
  now: L('এইমাত্র', 'just now', 'এইমাত্র'), min: L('মিনিট আগে', 'min ago', 'মিনিট আগে'), hr: L('ঘণ্টা আগে', 'h ago', 'ঘণ্টা আগে'), day: L('দিন আগে', 'd ago', 'দিন আগে'),
  bell: L('নোটিফিকেশন', 'Notifications', 'Notification'), notAllowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
};
const T = (k) => lab(X[k]);
const LV = { info: ['lInfo', 'info'], warn: ['lWarn', 'warn'], bad: ['lBad', 'bad'] };
const D = { rows: [], unread: false, level: '', count: 0, bk: null, runs: [] };
const eText = (e) => { const m = String((e && e.message) || ''); return /not allowed/.test(m) ? T('notAllowed') : (m || 'error'); };

// ---------- the bell + the 60 s poll ----------
let timer = null, started = false;
const signedIn = () => !!(S && S.ctx && S.ctx.profile && S.ctx.profile.status === 'active');
function paint(n) {
  D.count = n;
  document.querySelectorAll('.nt-badge').forEach((el) => { el.textContent = n > 99 ? '99+' : String(n); el.hidden = !(n > 0); });
  try { window.dispatchEvent(new CustomEvent('bos:notif-count', { detail: { n } })); } catch (e) { /* old browser */ }
}
async function refresh() {
  if (!signedIn() || document.hidden) return D.count;
  try {
    const r = await sb.rpc('notifications_unread_count');
    if (!r.error && r.data !== null && r.data !== undefined) paint(Number(r.data) || 0);
  } catch (e) { /* offline: keep the last number */ }
  return D.count;
}
function start() {
  if (started) return; started = true;
  const css = document.createElement('style');
  css.textContent = '.nt-bell{position:relative;min-width:40px;min-height:40px}.nt-bell .nt-badge{position:absolute;top:2px;right:0;min-width:18px;height:18px;line-height:18px;border-radius:9px;font-size:11px;padding:0 4px;background:var(--sig-bad,#c0392b);color:#fff;text-align:center}'
    + '.nt-row{cursor:pointer}.nt-row.unread{border-inline-start:4px solid var(--sig-bad,#c0392b)}.nt-row.read{opacity:.7}.nt-row.warn.unread{border-inline-start-color:#d68910}.nt-row.info.unread{border-inline-start-color:#2e86c1}';
  document.head.appendChild(css);
  timer = setInterval(refresh, 60000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
  refresh();
}
function badge() {
  start();
  return `<button type="button" class="nt-bell" data-act="go" data-v="notifications" aria-label="${esc(T('bell'))}">🔔<span class="nt-badge" ${D.count > 0 ? '' : 'hidden'}>${D.count > 99 ? '99+' : D.count}</span></button>`;
}
B.notifications = { badge, count: () => D.count, refresh, start, stop: () => { if (timer) clearInterval(timer); timer = null; started = false; } };

// ---------- the page ----------
function ago(iso) {
  const ms = Date.now() - new Date(iso).getTime(); if (!(ms >= 0)) return '';
  const m = Math.floor(ms / 60000);
  if (m < 1) return T('now');
  if (m < 60) return m + ' ' + T('min');
  if (m < 1440) return Math.floor(m / 60) + ' ' + T('hr');
  return Math.floor(m / 1440) + ' ' + T('day');
}
const ttl = (n) => lab({ bn: n.title_bn, mix: n.title_bn, en: n.title_en || n.title_bn });
const bdy = (n) => (n.body_bn || n.body_en) ? lab({ bn: n.body_bn || n.body_en, mix: n.body_bn || n.body_en, en: n.body_en || n.body_bn }) : '';
function rowHTML(n) {
  const lv = LV[n.level] || LV.info;
  return `<div class="card nt-row ${esc(n.level)} ${n.is_read ? 'read' : 'unread'}" role="button" tabindex="0" data-act="nt_open" data-id="${esc(n.id)}" data-route="${esc(n.route || '')}">
    <div class="row between"><b>${esc(ttl(n))}</b><span class="chip ${lv[1]}">${esc(T(lv[0]))}</span></div>
    ${bdy(n) ? `<div class="muted" style="font-size:.85rem;margin-top:4px">${esc(bdy(n))}</div>` : ''}
    <div class="muted" style="font-size:.78rem;margin-top:4px">${esc(ago(n.created_at))}${n.is_read ? '' : ' · ●'}</div></div>`;
}
function backupHTML() {
  if (!S.ctx.is_owner) return '';
  const b = D.bk;
  if (!b) return '';
  const head = !b.configured && !b.last_ok ? `<div class="notice warn">${esc(T('notSet'))}</div>`
    : `<div class="row between"><span>${esc(T('lastOk'))}: <b>${b.last_ok ? esc(String(b.age_hours)) + ' ' + esc(T('hoursAgo')) : esc(T('never'))}</b></span><span class="chip ${b.stale ? 'bad' : 'ok'}">${esc(b.stale ? T('stale') : T('fresh'))}</span></div>`;
  const runs = D.runs.map((r) => `<div class="row between muted" style="font-size:.8rem"><span>${esc(String(r.finished_at || '').slice(0, 16).replace('T', ' '))}</span><span>${esc(r.status)} · ${esc(String(r.tables ?? ''))} · ${esc(String(r.rows ?? ''))} ${esc(T('rows'))}</span></div>`).join('');
  return `<details data-ctl="off" class="card"><summary><b>${esc(T('backup'))}</b></summary><div class="stack" style="margin-top:6px">${head}${runs ? `<b style="font-size:.85rem">${esc(T('runs'))}</b>${runs}` : ''}</div></details>`;
}
function draw() {
  const el = $('#nt_body'); if (!el) return;
  const opts = ['', 'info', 'warn', 'bad'].map((v) => `<option value="${v}" ${D.level === v ? 'selected' : ''}>${esc(v ? T(LV[v][0]) : T('lAll'))}</option>`).join('');
  el.innerHTML = `<div class="card stack">
      <div class="row wrap"><select id="nt_unread" aria-label="${esc(T('unread'))}"><option value="0" ${D.unread ? '' : 'selected'}>${esc(T('all'))}</option><option value="1" ${D.unread ? 'selected' : ''}>${esc(T('unread'))}</option></select>
      <select id="nt_level" aria-label="${esc(T('lvl'))}">${opts}</select>
      <button type="button" class="mini" data-act="nt_all">${esc(T('readAll'))}</button></div>
      <a href="#/switchboard" data-act="go" data-v="switchboard" class="muted" style="font-size:.85rem">${esc(T('settings'))}</a></div>
    ${D.rows.length ? D.rows.map(rowHTML).join('') : `<p class="muted">${esc(T('none'))}</p>`}${backupHTML()}`;
}
async function load() {
  const [r, bk, runs] = await Promise.all([
    sb.rpc('notifications_for_me', { p_limit: 100, p_unread_only: D.unread, p_level: D.level || null }),
    S.ctx.is_owner ? sb.rpc('backup_status') : Promise.resolve({ data: null }),
    S.ctx.is_owner ? sb.from('backup_runs').select('finished_at,status,tables,rows').order('finished_at', { ascending: false }).limit(8) : Promise.resolve({ data: [] }),
  ]);
  if (r.error) throw r.error;
  D.rows = Array.isArray(r.data) ? r.data : [];
  D.bk = bk && !bk.error ? bk.data : null; D.runs = (runs && runs.data) || [];
}
async function show() {
  try { await load(); draw(); await refresh(); } catch (e) { const el = $('#nt_body'); if (el) el.innerHTML = `<p class="muted">${esc(T('loadFail'))}: ${esc(eText(e))}</p>`; }
}
Object.assign(H, {
  nt_open: async (a) => {
    const id = Number(a.dataset.id), route = (a.dataset.route || '').trim();
    try { const r = await sb.rpc('notification_read', { p_id: id }); if (r.error) throw r.error; D.rows.forEach((n) => { if (n.id === id) n.is_read = true; }); } catch (e) { toast(eText(e)); }
    refresh();
    if (route && /^[a-z0-9_\/-]{1,60}$/i.test(route)) location.hash = '#/' + route; else draw();
  },
  nt_all: async () => {
    const r = await sb.rpc('notification_read_all'); if (r.error) return toast(eText(r.error));
    await show();
  },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'nt_unread') { D.unread = e.target.value === '1'; show(); }
  if (e.target.id === 'nt_level') { D.level = e.target.value; show(); }
});
document.addEventListener('keydown', (e) => {
  const row = e.target && e.target.closest && e.target.closest('.nt-row');
  if (row && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); H.nt_open(row); }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="nt_body"><p class="muted">…</p></div>', true);
  start();
  try { await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { notifications: view });
})();
