/* Islamia BOS · Step Vis: who SEES which option. Owner screen (#/optviews) for supabase/phase91.sql + the small hook nav.js / ia.js call.
   Per person (and per role as the default) every screen / form has a view mode: Show (as today), Hide (not shown at all), Locked (shown, disabled; tapping it opens an "ask the owner" sheet).
   IMPORTANT: this is only UI tidiness. It never grants or removes a permission (grants / RLS stay the only security). A hidden option that the person may use still opens by its direct link;
   a locked option the person is not permitted to use is still refused by the server.
   Hook (all guarded): B.optviews.load() once, B.optviews.apply(entries) in nav.js entries(), B.optviews.hidden(key) in ia.js visible(). If the data is missing everything behaves as before.
   Language rule: English mode is ALL English; Bangla mode keeps common words in English; the mix is Bangla + English words. Handlers are prefixed ov_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A) return;
const { sb, S, esc, toast, openSheet, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const PROTECTED = ['r:home', 'r:optviews'];
const MODES = ['show', 'hide', 'locked'];

const X = {
  title: L('কে কী দেখবে', 'Who sees what', 'কে কী দেখবে (Show / Hide)'),
  intro: L('প্রতিটি অপশনের পাশে ঠিক করুন: দেখান (এখনকার মতো), লুকান (একদম দেখা যাবে না) বা তালা (দেখা যাবে কিন্তু চলবে না)। এটা শুধু পর্দা গোছানো — কারও অনুমতি বাড়ে না বা কমে না।',
    'Pick for each option: Show (as today), Hide (not shown at all) or Locked (visible but cannot be used). This only tidies the screen - it never gives or removes a permission.',
    'প্রতিটি option-এর পাশে ঠিক করুন: Show (এখনকার মতো), Hide (একদম দেখা যাবে না) বা Locked (দেখা যাবে কিন্তু চলবে না)। এটা শুধু screen গোছানো — কারও permission বাড়ে না বা কমে না।'),
  note: L('লুকানো অপশনও সরাসরি লিংকে খুলে যায় যদি অনুমতি থাকে; আসল নিরাপত্তা অনুমতিতেই।', 'A hidden option still opens by its direct link if the person has the permission; real security stays in the permissions.',
    'Hidden option-ও direct link-এ খোলে যদি permission থাকে; আসল security permission-এই।'),
  ownerOnly: L('শুধু মালিক এটা বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner এটা বদলাতে পারেন'),
  who: L('কার জন্য', 'For whom', 'কার জন্য'), people: L('ব্যক্তি', 'People', 'ব্যক্তি'), roles: L('ভূমিকার ডিফল্ট', 'Role defaults', 'Role-এর default'), pick: L('— বেছে নিন —', '- choose -', '— বেছে নিন —'),
  show: L('দেখান', 'Show', 'Show'), hide: L('লুকান', 'Hide', 'Hide'), locked: L('তালা', 'Locked', 'Locked'),
  granted: L('অনুমতি আছে', 'Granted', 'Granted'), notGranted: L('অনুমতি নেই', 'Not granted', 'Not granted'), fromRole: L('ভূমিকা থেকে', 'from role', 'role থেকে'), noInfo: L('অনুমতি: রোলের ডিফল্ট', 'Permission: role default', 'Permission: role default'),
  bHide: L('অনুমতি নেই এমন সব লুকান', 'Hide all not granted', 'Not granted সব Hide'), bShow: L('সব দেখান', 'Show all', 'সব Show'), bLock: L('অনুমতি নেই এমন সবে তালা', 'Locked for not granted', 'Not granted সবে Locked'),
  bReset: L('সব ডিফল্টে ফেরান', 'Reset all to default', 'সব default-এ ফেরান'),
  loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  lockTitle: L('এটা বন্ধ করা আছে', 'This option is locked', 'এটা locked আছে'), lockBody: L('এটা এখন আপনার জন্য চালু নেই। দরকার হলে মালিককে অনুমতির জন্য বলুন।', 'This option is not available to you right now. Ask the owner for permission if you need it.', 'এটা এখন আপনার জন্য চালু নেই। দরকার হলে owner-কে permission-এর জন্য বলুন।'),
  close: L('বন্ধ', 'Close', 'Close'), lockTag: L('তালা', 'locked', 'locked'),
  recTitle: L('পরামর্শ (শুধু পরামর্শ — বাধ্যতামূলক নয়)', 'Recommendations (advice only - never blocking)', 'Recommendation (শুধু পরামর্শ — বাধ্যতামূলক নয়)'),
  recMissing: L('সাধারণত দরকার, কিন্তু নেই', 'Usually needed, not given', 'সাধারণত দরকার, কিন্তু নেই'), recCombo: L('একসাথে না থাকাই ভালো', 'Better not held together', 'একসাথে না থাকাই ভালো'),
  recUnused: L('দরকার না হলে লুকান', 'Hide if never needed', 'দরকার না হলে Hide'), apply: L('প্রয়োগ', 'Apply', 'Apply'), ignore: L('উপেক্ষা', 'Ignore', 'Ignore'), unignore: L('ফেরান', 'Undo', 'Undo'),
  ignored: L('উপেক্ষা করা', 'ignored', 'ignored'), hint: L('পরামর্শ: লুকান', 'Suggest: Hide', 'Suggest: Hide'), applied: L('প্রয়োগ হয়েছে', 'Applied', 'Applied'),
  eNotPersonal: L('এই অনুমতি ভূমিকা থেকে এসেছে — ভূমিকায় বদলান', 'This permission comes from the role - change it in the role', 'এই permission role থেকে এসেছে — role-এ বদলান'),
  eProtected: L('এই অপশন লুকানো বা তালা দেওয়া যায় না', 'This option cannot be hidden or locked', 'এই option hide বা lock করা যায় না'),
  eMissingDb: L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part is not installed yet', 'এই অংশের database এখনও চালু হয়নি'),
};
const T = (k) => lab(X[k]);

// ---------- the person's own views (cache) ----------
const V = { uid: null, map: {}, loaded: false, p: null };
const curUid = () => (S && S.ctx && S.ctx.profile && S.ctx.profile.id) || null;
function setMap(rows) {
  const m = {};
  (Array.isArray(rows) ? rows : []).forEach((r) => { if (r && typeof r.key === 'string' && MODES.includes(r.mode) && r.mode !== 'show' && !PROTECTED.includes(r.key)) m[r.key] = r.mode; });
  V.map = m;
}
function load() {
  const me = curUid();
  if (!me) return Promise.resolve(false);
  if (V.uid !== me) { V.uid = me; V.loaded = false; V.map = {}; V.p = null; }
  if (V.loaded) return Promise.resolve(true);
  if (V.p) return V.p;
  const call = (async () => { const r = await sb.rpc('my_option_views'); if (r && !r.error && Array.isArray(r.data)) { setMap(r.data); V.loaded = true; return true; } return false; })();
  const cap = new Promise((res) => setTimeout(() => res(false), 2000));
  V.p = Promise.race([call.catch(() => false), cap]).then((ok) => { V.p = null; return ok; });
  return V.p;
}
const mode = (key) => V.map[key] || 'show';
const hidden = (key) => V.map[key] === 'hide';
// nav.js entries(): hidden ones leave the list; locked ones stay, enabled-looking but tagged, and the click is caught below
function apply(list) {
  try {
    if (!Array.isArray(list) || !Object.keys(V.map).length) return list;
    return list.filter((e) => !(e && hidden(e.key))).map((e) => {
      if (e && mode(e.key) === 'locked' && !e.vlock) { e.vlock = true; e.ok = true; e.label = String(e.label) + ' · ' + T('lockTag'); }
      return e;
    });
  } catch (err) { return list; }
}
function keyOfRoute(v) {
  const p = String(v || '').replace(/^#?\/?/, '').split('/').filter(Boolean);
  if (!p.length) return null;
  if (p[0] === 'form' && p[1]) return 'f:' + p[1];
  if (p[0] === 'entry' && p[1] === 'new' && p[2]) return 'f:' + p[2];
  const rr = B.ia && B.ia.resolve ? B.ia.resolve(p.join('/')) : null;
  return rr ? 'r:' + rr.route : 'r:' + p[0];
}
function lockedSheet(label) {
  openSheet(`<h2>${esc(T('lockTitle'))}</h2>${label ? `<p><b>${esc(label)}</b></p>` : ''}<p>${esc(T('lockBody'))}</p><button class="primary full" data-act="closesheet">${esc(T('close'))}</button>`);
}
document.addEventListener('click', (e) => {
  try {
    if (!Object.keys(V.map).length) return;
    const a = e.target && e.target.closest ? e.target.closest('[data-act="nav_go"],[data-act="go"]') : null;
    if (!a || !a.dataset || !a.dataset.v) return;
    const k = keyOfRoute(a.dataset.v);
    if (!k || mode(k) !== 'locked') return;
    e.preventDefault(); e.stopPropagation(); if (e.stopImmediatePropagation) e.stopImmediatePropagation();
    const rec = k.startsWith('r:') && B.ia && B.ia.byRoute ? B.ia.byRoute(k.slice(2)) : null;
    lockedSheet(rec && B.ia.label ? B.ia.label(rec) : '');
  } catch (err) { /* never block navigation because of this hook */ }
}, true);

// ---------- owner screen ----------
const D = { people: [], roles: [], forms: [], who: null, data: null, perm: null, reco: null, ents: [] };
const uuid = () => { try { return crypto.randomUUID(); } catch (e) { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }); } };
const own = () => !!(S && S.ctx && S.ctx.is_owner);
function errText(e) {
  const m = String((e && e.message) || e || '');
  if (/not_personal_grant/.test(m)) return T('eNotPersonal');
  if (/protected_option/.test(m)) return T('eProtected');
  if (/Could not find the function|schema cache|PGRST202|does not exist/i.test(m)) return T('eMissingDb');
  return null;
}
function bad(e) { const t = errText(e); if (t) toast(t); else A.fail(e); }

// the same context object nav.js builds, but for the CHOSEN person (so ia.js ok() predicates tell granted / not granted)
function ctxFor(d) {
  const perms = d.perms || {}, o = !!d.is_owner, GF = {}, roles = d.roles || [], locs = d.locations || [];
  (d.grants || []).forEach((g) => { GF[g] = true; });
  const P = (c, k) => o || !!(perms[c] && perms[c][k]);
  return { own: o, roles, P, GF, locOk: () => o || roles.includes('management') || locs.length > 0,
    canPos: () => o || !!(perms.POS && (perms.POS.enter || perms.POS.view)), anyApprove: () => o || Object.values(perms).some((p) => p.approve),
    ctlOk: () => o || GF.rollout_manage === true || GF.head_management === true || GF.location_manage === true || GF.settings_approve === true || GF.list_manage === true, formLive: () => true };
}
// every option the owner can set, grouped like ia.js: [{g, label, items:[{key,label,granted}]}]
function options(c) {
  const ia = B.ia, out = {};
  (ia.GID || []).forEach((g) => { out[g] = []; });
  (B.IA || []).filter((r) => r.status === 'live' && r.drawer !== false && r.id !== 'home').forEach((r) => {
    let ok = null; if (c) { try { ok = !!r.ok(c); } catch (e) { ok = false; } }
    (out[r.group] = out[r.group] || []).push({ key: 'r:' + r.route, label: ia.label(r), granted: ok });
  });
  (D.forms || []).filter((f) => f.area !== 'master' && f.code !== 'POS' && ia.AREA_G[f.area]).forEach((f) => {
    (out[ia.AREA_G[f.area]] = out[ia.AREA_G[f.area]] || []).push({ key: 'f:' + f.code, label: f.code + ' · ' + A.nm(f), granted: c ? c.P(f.code, 'view') : null });
  });
  return (ia.GID || []).filter((g) => (out[g] || []).length).map((g) => ({ g, label: ia.groupLabel(g), items: out[g] }));
}
// effective mode shown in the chips: the person's own row, else role default, else show
function effMode() {
  const m = {}, src = {};
  if (!D.who) return { m, src };
  if (D.who.kind === 'r') { (D.data || []).forEach((r) => { m[r.key] = r.mode; src[r.key] = 'role'; }); return { m, src }; }
  ((D.data && D.data.effective) || []).forEach((r) => { m[r.key] = r.mode; src[r.key] = r.src; });
  return { m, src };
}
function chips(key, cur, src) {
  const prot = PROTECTED.includes(key);
  return `<div class="row ov-chips" role="group">${MODES.map((m) => `<button class="mini ${cur === m ? 'on primary' : ''}" data-act="ov_set" data-k="${esc(key)}" data-m="${m}" aria-pressed="${cur === m}" ${prot && m !== 'show' ? 'disabled' : ''}>${esc(T(m))}</button>`).join('')}${src === 'role' ? `<small class="muted">${esc(T('fromRole'))}</small>` : ''}</div>`;
}
function unusedMap() { const m = {}; ((D.reco && D.reco.unused) || []).forEach((u) => { m[u.key] = u; }); return m; }
function drawList() {
  const el = $('#ov_list'); if (!el) return;
  if (!D.who) { el.innerHTML = ''; return; }
  const { m, src } = effMode(), un = unusedMap();
  const grp = options(D.perm);
  el.innerHTML = grp.map((g) => `<div class="card"><b>${esc(g.label)}</b>${g.items.map((it) => {
    const cur = m[it.key] || 'show', u = un[it.key];
    const st = it.granted === null ? `<span class="muted">${esc(T('noInfo'))}</span>` : `<span class="chip ${it.granted ? 'ok' : 'warn'}">${esc(T(it.granted ? 'granted' : 'notGranted'))}</span>`;
    const hint = u && !u.ignored && cur !== 'hide' ? `<div class="notice info"><small>${esc(T('hint'))} · ${esc(lab(u.reason))}</small> <button class="mini" data-act="ov_reco_apply" data-i="${esc(u.item)}">${esc(T('apply'))}</button></div>` : '';
    return `<div class="ov-row" data-k="${esc(it.key)}"><div>${esc(it.label)} ${st}</div>${chips(it.key, cur, src[it.key])}${hint}</div>`;
  }).join('')}</div>`).join('');
}
function recItem(kind, it, text) {
  return `<div class="${it.ignored ? 'muted' : ''}"><div>${esc(text)}${it.ignored ? ' (' + esc(T('ignored')) + ')' : ''}</div><small class="muted">${esc(lab(it.reason))}</small>
    <div class="row">${kind !== 'combo' || !it.ignored ? `<button class="mini" data-act="ov_reco_apply" data-i="${esc(it.item)}">${esc(T('apply'))}</button>` : ''}
    <button class="mini" data-act="${it.ignored ? 'ov_reco_unign' : 'ov_reco_ign'}" data-i="${esc(it.item)}">${esc(T(it.ignored ? 'unignore' : 'ignore'))}</button></div></div>`;
}
function drawReco() {
  const el = $('#ov_reco'); if (!el) return;
  const r = D.reco;
  if (!D.who || D.who.kind !== 'u' || !r || r.is_owner) { el.innerHTML = ''; return; }
  const sec = (title, arr) => (arr.length ? `<div class="hsec">${esc(title)}<small>${arr.length}</small></div>${arr.join('')}` : '');
  const html = sec(T('recMissing'), (r.recommended_missing || []).map((i) => recItem('miss', i, lab(i.label))))
    + sec(T('recCombo'), (r.not_recommended_combo || []).map((i) => recItem('combo', i, i.a + ' + ' + i.b)))
    + sec(T('recUnused'), (r.unused || []).map((i) => recItem('unused', i, i.key)));
  el.innerHTML = html ? `<div class="notice info"><b>${esc(T('recTitle'))}</b></div>${html}` : '';
}
async function view() {
  shell(T('title'), `<p class="muted">${esc(T('intro'))}</p><div class="notice info">${esc(T('note'))}</div>${own() ? '<div id="ov_body"><p class="muted">' + esc(T('loading')) + '</p></div>' : `<div class="notice warn">${esc(T('ownerOnly'))}</div>`}`, true);
  if (!own()) return;
  try {
    const [p, r, f] = await Promise.all([sb.from('profiles').select('id,staff_id,full_name,status').order('staff_id'), sb.from('roles').select('code,name_bn,name_en').order('sort'), sb.from('forms').select('code,area,name_bn,name_mix,name_en,sort,enabled').order('sort')]);
    D.people = (p && p.data) || []; D.roles = (r && r.data) || []; D.forms = (f && f.data) || [];
  } catch (e) { D.people = []; D.roles = []; D.forms = []; }
  const body = $('#ov_body'); if (!body) return;
  body.innerHTML = `<label>${esc(T('who'))}</label><select id="ov_who"><option value="">${esc(T('pick'))}</option>
    <optgroup label="${esc(T('people'))}">${D.people.map((u) => `<option value="u:${esc(u.id)}">${esc(u.staff_id)} · ${esc(u.full_name)}</option>`).join('')}</optgroup>
    <optgroup label="${esc(T('roles'))}">${D.roles.map((x) => `<option value="r:${esc(x.code)}">${esc(A.nm(x, 'name_bn', 'name_en') || x.code)}</option>`).join('')}</optgroup></select>
    <div class="stack" id="ov_bulk"></div><div id="ov_reco"></div><div id="ov_list"></div>`;
  D.who = null;
}
function bulkButtons() {
  const el = $('#ov_bulk'); if (!el) return;
  el.innerHTML = D.who ? `<button class="full" data-act="ov_bulk" data-m="hide_ng">${esc(T('bHide'))}</button><button class="full" data-act="ov_bulk" data-m="show_all">${esc(T('bShow'))}</button>
    <button class="full" data-act="ov_bulk" data-m="locked_ng">${esc(T('bLock'))}</button><button class="full" data-act="ov_bulk" data-m="reset">${esc(T('bReset'))}</button>` : '';
}
async function pick(val) {
  D.who = null; D.data = null; D.perm = null; D.reco = null;
  const m = /^([ur]):(.+)$/.exec(val || '');
  if (m) {
    D.who = { kind: m[1], id: m[2] };
    if (m[1] === 'u') {
      const r = await sb.rpc('option_views_for_user', { p_user: m[2] });
      if (r.error) { D.who = null; bad(r.error); } else { D.data = r.data; D.perm = ctxFor(r.data); }
      if (D.who) { try { const q = await sb.rpc('permission_recommendations', { p_user: m[2] }); D.reco = q && !q.error ? q.data : null; } catch (e) { D.reco = null; } }
    } else {
      const r = await sb.rpc('role_option_views', { p_role: m[2] });
      if (r.error) { D.who = null; bad(r.error); } else D.data = r.data || [];
    }
  }
  bulkButtons(); drawReco(); drawList();
}
async function refresh() { const keep = D.who ? D.who.kind + ':' + D.who.id : ''; await pick(keep); }
// the call exactly as the server wants it (also used by the tests)
function setArgs(who, key, m, cid) {
  return who.kind === 'u' ? ['set_option_view', { p_user: who.id, p_key: key, p_mode: m, p_client: cid || uuid() }] : ['set_role_option_view', { p_role: who.id, p_key: key, p_mode: m, p_client: cid || uuid() }];
}
function bulkArgs(who, items, cid) {
  return who.kind === 'u' ? ['set_option_view_bulk', { p_user: who.id, p_items: items, p_client: cid || uuid() }] : ['set_role_option_view_bulk', { p_role: who.id, p_items: items, p_client: cid || uuid() }];
}
async function setOne(key, m) {
  if (!D.who) return;
  const [fn, a] = setArgs(D.who, key, m);
  const r = await sb.rpc(fn, a); if (r.error) return bad(r.error);
  toast(T('saved')); await refresh();
}
// which items a bulk button touches. 'default' removes a choice.
function bulkItems(kind) {
  const { m } = effMode(), items = [];
  options(D.perm).forEach((g) => g.items.forEach((it) => {
    if (PROTECTED.includes(it.key)) return;
    const cur = m[it.key] || 'show', ng = it.granted === false;
    if (kind === 'hide_ng' && ng && cur !== 'hide') items.push({ key: it.key, mode: 'hide' });
    else if (kind === 'locked_ng' && ng && cur !== 'locked') items.push({ key: it.key, mode: 'locked' });
    else if (kind === 'show_all' && cur !== 'show') items.push({ key: it.key, mode: 'show' });
    else if (kind === 'reset' && m[it.key] !== undefined) items.push({ key: it.key, mode: 'default' });
  }));
  return items;
}
async function bulk(kind) {
  if (!D.who) return;
  if (D.who.kind === 'r' && (kind === 'hide_ng' || kind === 'locked_ng')) return;   // a role has no single permission status
  const items = bulkItems(kind);
  for (let i = 0; i < items.length; i += 400) {
    const [fn, a] = bulkArgs(D.who, items.slice(i, i + 400));
    const r = await sb.rpc(fn, a); if (r.error) return bad(r.error);
  }
  toast(T('saved')); await refresh();
}
async function recApply(item) {
  if (!D.who || D.who.kind !== 'u') return;
  const r = await sb.rpc('reco_apply', { p_user: D.who.id, p_item: item, p_client: uuid() }); if (r.error) return bad(r.error);
  toast(T('applied')); await refresh();
}
async function recIgnore(item, on) {
  if (!D.who || D.who.kind !== 'u') return;
  const r = await sb.rpc('reco_ignore_set', { p_user: D.who.id, p_item: item, p_ignore: on, p_client: uuid() }); if (r.error) return bad(r.error);
  await refresh();
}
A.H = A.H || {};
Object.assign(A.H, {
  ov_set: (a) => setOne(a.dataset.k, a.dataset.m),
  ov_bulk: (a) => bulk(a.dataset.m),
  ov_reco_apply: (a) => recApply(a.dataset.i),
  ov_reco_ign: (a) => recIgnore(a.dataset.i, true),
  ov_reco_unign: (a) => recIgnore(a.dataset.i, false),
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'ov_who') pick(e.target.value).catch(A.fail); });
B.optviews = { X, T, load, apply, hidden, mode, keyOfRoute, ctxFor, options, bulkItems, setArgs, bulkArgs, lockedSheet, pick, _state: V, _d: D, PROTECTED };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { optviews: view });
})();
