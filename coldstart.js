/* Islamia BOS · bos112 · offline COLD START.
   Problem: the app closed and reopened with no internet showed the login screen (my_context failed), so offline POS only worked if the app was already open when the signal dropped.
   Now: the last good sign-in snapshot is kept on this phone and used ONLY when my_context fails with a NETWORK error. The app opens in "offline mode" (slim banner, POS + sale queue, other screens say
   "Needs internet"), retries every 30 s and on 'online', and when the server answers it refreshes the context without reloading the page. Nothing is trusted past the server's word:
   an inactive / removed user is signed out the moment my_context is reachable again.
   WHAT IS KEPT (localStorage, keys bos_cs_*, version 1, try/catch everywhere, size-capped): the my_context answer (profile, roles, permissions, locations), the environment POS needs
   (locations, rules, option lists, item list with SELL prices, grant definitions) and the POS item list. NEVER kept: the Supabase token / password / PIN (the session itself stays in supabase-js
   storage), cost prices (the item queries here never select them), staff directory, any other business data. The snapshot restores only what the person already had.
   SAFETY WINDOW: a fixed internal cap of 14 days (MAX_AGE_DAYS) since the last successful my_context; older = offline start refused, the login screen asks for internet.
   Sign-out, a deactivated/removed profile and a failed sign-in clear the snapshot. The sale queue (bos_pos_queue_*) is NOT touched: queued sales replay once (client id) after reconnect. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A) return;
const { S, esc } = A;
const MAX_AGE_DAYS = 14, MAX_AGE_MS = MAX_AGE_DAYS * 86400000, VER = 1;
const CAP = { ctx: 300000, env: 1500000, items: 1500000 };      // characters; bigger = not saved (the old snapshot stays)
const PFX = 'bos_cs_';
const L = B.L, lab = B.lab;
const X = {
  banner: L('Offline — সংরক্ষিত তথ্য ব্যবহার হচ্ছে', 'Offline — using saved data', 'Offline — saved data ব্যবহার হচ্ছে'),
  needs: L('এর জন্য internet লাগবে', 'Needs internet', 'এর জন্য Internet লাগবে'),
  needsT: L('এই স্ক্রিন সার্ভার থেকে তথ্য আনে। Internet এলে নিজে থেকেই খুলবে। এর মধ্যে POS-এ সেল চলবে — সেল জমা থাকবে, নেট এলে যাবে।', 'This screen reads from the server. It opens by itself when the internet is back. Meanwhile POS keeps working: sales are saved and sent when you are online.', 'এই screen server থেকে তথ্য আনে। Internet এলে নিজে থেকেই খুলবে। এর মধ্যে POS চলবে — sale জমা থাকবে, net এলে যাবে।'),
  first: L('প্রথমবার সাইন-ইনের জন্য internet লাগবে', 'Internet needed for first sign-in', 'প্রথমবার sign-in-এর জন্য Internet লাগবে'),
  old: L('ফোনে রাখা তথ্য ১৪ দিনের বেশি পুরোনো — সাইন-ইনের জন্য internet লাগবে', 'Saved data is older than 14 days — internet is needed to sign in', 'Phone-এর saved data ১৪ দিনের বেশি পুরোনো — sign-in-এর জন্য Internet লাগবে'),
  out: L('সাইন-আউট হয়েছে — আবার সাইন-ইন করুন', 'You were signed out — please sign in again', 'Sign-out হয়েছে — আবার sign-in করুন'),
  pos: L('POS', 'POS', 'POS'), home: L('হোম', 'Home', 'Home'),
};
const T = (k) => lab(X[k]);

// ---------- storage (every access guarded) ----------
const ls = { get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }, set(k, v) { try { localStorage.setItem(k, v); return true; } catch (e) { return false; } }, del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } } };
const rd = (k) => { try { const o = JSON.parse(ls.get(k)); return o && o.v === VER && typeof o.at === 'number' ? o : null; } catch (e) { return null; } };
const wr = (k, body, cap) => { let s; try { s = JSON.stringify({ v: VER, at: Date.now(), ...body }); } catch (e) { return false; } if (s.length > cap) return false; return ls.set(k, s); };
const fresh = (o, now) => !!o && (now || Date.now()) - o.at <= MAX_AGE_MS && o.at - (now || Date.now()) < 3600000;   // not older than the cap, not from the future (clock rolled back)

// network error = the request never reached the server (or a gateway said so). An answer from the server (auth, permission, inactive) is NOT a network error.
const isNet = (e) => {
  if (!e) return false;
  if (e.code && !/^(?:0|)$/.test(String(e.code))) return false;                                    // PostgREST / Postgres / auth error code = the server answered
  if ([502, 503, 504].includes(Number(e.status))) return true;
  if (e.status && Number(e.status) !== 0) return false;
  return /failed to fetch|fetch failed|networkerror|network request|load failed|network|timeout|timed out|offline|err_internet|bad gateway|service unavailable|gateway/i.test(e.message || '') || (!navigator.onLine && !e.code);
};

// the signed-in user id from supabase-js's own storage (the token itself is never read into our snapshot)
function storedUid() {
  try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && /^sb-.*-auth-token$/.test(k)) { const o = JSON.parse(localStorage.getItem(k)); const u = o && (o.user || (o.currentSession && o.currentSession.user)); if (u && u.id) return String(u.id); } } } catch (e) { /* none */ }
  return null;
}

// ---------- the snapshot ----------
function save(ctx) {
  try {
    const p = ctx && ctx.profile; if (!p || !p.id || p.status !== 'active') return false;
    return wr(PFX + 'ctx_' + p.id, { uid: p.id, ctx }, CAP.ctx);
  } catch (e) { return false; }
}
// -> { ctx, at } or { refused: 'none' | 'old' }
function load(uid) {
  if (!uid) return { refused: 'none' };
  const o = rd(PFX + 'ctx_' + uid);
  if (!o || o.uid !== uid || !o.ctx || !o.ctx.profile || o.ctx.profile.id !== uid) return { refused: 'none' };
  if (!fresh(o)) return { refused: 'old' };
  if (o.ctx.profile.status !== 'active') return { refused: 'none' };
  return { ctx: o.ctx, at: o.at };
}
function clear() { try { const ks = []; for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && k.startsWith(PFX)) ks.push(k); } ks.forEach((k) => ls.del(k)); } catch (e) { /* ignore */ } }
const uidNow = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || null;
const SECRETISH = /secret|password|passwd|token|api[_-]?key|service_role/i;

// POS item list (the same rows pos.js loads; sell prices only)
const ITEM_FIELDS = ['id', 'code', 'name_bn', 'name_en', 'name_mix', 'category', 'category_bn', 'sub_category', 'unit', 'sell_price', 'is_active', 'barcode', 'sellable', 'hidden', 'item_type'];   // allow-list: no cost, ever
function itemsSave(rows) {
  const u = uidNow(); if (!u || !Array.isArray(rows) || !rows.length) return false;
  return wr(PFX + 'items_' + u, { items: rows.map((r) => { const o = {}; ITEM_FIELDS.forEach((k) => { if (k in r) o[k] = r[k]; }); return o; }) }, CAP.items);
}
function itemsLoad() { const u = uidNow(); const o = u && rd(PFX + 'items_' + u); return o && fresh(o) && Array.isArray(o.items) ? o.items : null; }

// environment (ENV in entry.js): locations, rules, option lists, grant defs, item master (sell price)
const E = () => B.ENV;
function envSave() {
  const e = E(), u = uidNow(); if (!e || !u || e._cs) return false;
  if (!(e.locs && e.locs.length) || !e.rules) return false;           // a half-failed load is never saved over a good one
  const rules = {}; Object.keys(e.rules).forEach((k) => { if (!SECRETISH.test(k)) rules[k] = e.rules[k]; });
  if (!Object.keys(rules).length) { const old = rd(PFX + 'env_' + u); if (old && old.env && Object.keys(old.env.rules || {}).length) return false; }   // a failed rules read never replaces a good snapshot
  return wr(PFX + 'env_' + u, { env: { locs: e.locs, rules, lists: e.lists || {}, grantDefs: e.grantDefs || {}, items: (e.items || []).map((i) => ({ id: i.id, code: i.code, name_bn: i.name_bn, name_en: i.name_en, name_mix: i.name_mix, unit: i.unit, sell_price: i.sell_price, is_active: i.is_active })) } }, CAP.env);
}
function envApply() {                     // fill what the server could not give from the snapshot; mark ENV so it is re-read when the internet is back
  const e = E(), u = uidNow(), o = u && rd(PFX + 'env_' + u); if (!e || !o || !fresh(o) || !o.env) return false;
  const c = o.env;
  if (!(e.locs && e.locs.length)) e.locs = c.locs || [];
  if (!e.rules || !Object.keys(e.rules).length) e.rules = c.rules || {};
  if (!e.lists || !Object.keys(e.lists).length) e.lists = c.lists || {};
  if (!e.grantDefs || !Object.keys(e.grantDefs).length) e.grantDefs = c.grantDefs || {};
  if (!(e.items && e.items.length)) { e.items = c.items || []; e.byCode = new Map(e.items.map((i) => [i.code, i])); }
  if (!e.staff) e.staff = []; if (!e.sup) e.sup = [];
  e._cs = true; return true;
}
// wrap loadStatic: a good load is saved; a failed one is completed from the snapshot; a snapshot-filled ENV is re-read once the internet is back
function wrapEnv() {
  const orig = B.loadStatic; if (typeof orig !== 'function' || orig.__cs) return;
  const w = async function () {
    const e = E();
    if (e && e._cs && navigator.onLine && !S.offline) { e.staff = e.items = e.locs = e.lists = e.rules = e.sup = null; e.grantDefs = null; e._cs = false; }
    await orig.apply(this, arguments);
    try {
      const x = E(); const bad = !(x.locs && x.locs.length) || !x.rules;
      if (bad) { if (!envApply()) x._cs = true; } else if (!x._cs) envSave();
    } catch (er) { /* snapshot is a convenience */ }
  };
  w.__cs = true; B.loadStatic = w;
}

// ---------- the banner and the "Needs internet" state ----------
function paint() {
  let el = document.getElementById('cs_banner');
  if (!S.offline) { if (el) el.remove(); return; }
  if (!el) { el = document.createElement('div'); el.id = 'cs_banner'; el.setAttribute('role', 'status'); const app = document.getElementById('app'); app.parentNode.insertBefore(el, app); }
  el.className = 'cs-banner'; el.textContent = T('banner');
}
function needsNet(page) {
  const A2 = window.BOS_APP; S.csNeeds = true;
  A2.shell(T('needs'), `<div class="card stack center" id="cs_needs"><h2>${esc(T('needs'))}</h2><p>${esc(T('needsT'))}</p>
    <button class="primary full" data-act="go" data-v="pos">${esc(T('pos'))}</button><button class="full" data-act="go" data-v="home">${esc(T('home'))}</button></div>`, 'home');
}
// screens that work with the saved data + the local queue; everything else reads the server
const OFFLINE_OK = new Set(['home', 'pos']);
const allowed = (page) => OFFLINE_OK.has(page);

window.addEventListener('online', paint);
window.addEventListener('offline', paint);
wrapEnv();
B.cs = window.BOS_CS = { MAX_AGE_DAYS, MAX_AGE_MS, isNet, storedUid, save, load, clear, itemsSave, itemsLoad, envSave, envApply, paint, needsNet, allowed, T, msg: T, wrapEnv };
})();
