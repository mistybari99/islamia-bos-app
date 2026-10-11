/* Islamia BOS · Rules & options hub (owner): business rules (switches / numbers / choices), "who may do what" grants per role,
   and the emergency-request flow (staff asks at once, the owner approves for a short time, later sets the standing grant).
   The server enforces every rule; this screen only edits them. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const pick = (r, k) => (S.lang === 'en' ? r[k + '_en'] : S.lang === 'mix' ? r[k + '_mix'] : r[k + '_bn']) || r[k + '_bn'] || r[k + '_en'] || '';
const MODS = {
  pos: L('সেল ও গ্রাহক', 'Sales & customers', 'Sale ও Customer'), books: L('হিসাব বন্ধ', 'Closing the books', 'হিসাব বন্ধ'), entries: L('ফর্ম এন্ট্রি', 'Form entries', 'Form Entry'),
  emergency: L('জরুরি অনুরোধ', 'Emergency requests', 'জরুরি Request'),
};
const X = {
  title: L('নিয়ম ও অপশন', 'Rules & options', 'নিয়ম ও Option'), tabRules: L('নিয়ম', 'Rules', 'Rules'), tabGrants: L('কে কী পারবে', 'Who may do what', 'কে কী পারবে'), tabMore: L('অন্যান্য অপশন', 'More options', 'অন্যান্য Option'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), dflt: L('ডিফল্ট', 'default', 'default'), reset: L('ডিফল্টে ফেরান', 'Back to default', 'Default এ ফেরান'),
  badv: L('মান ঠিক নয়', 'The value is not valid', 'মান ঠিক নয়'), baddate: L('তারিখ YYYY-MM-DD ফরম্যাটে লিখুন, যেমন 2026-09-30', 'Write the date as YYYY-MM-DD, e.g. 2026-09-30', 'Date YYYY-MM-DD ফরম্যাটে লিখুন, যেমন 2026-09-30'),
  grantHint: L('মালিক সবসময় পারেন। নিচে যে ভূমিকায় টিক থাকবে সে এই কাজ নিজে করতে পারবে। বাকিরা আটকে গেলে "জরুরি অনুরোধ" পাঠাবে।', 'The owner always may. A role that is switched on can do the action itself. Others who are blocked send an emergency request.', 'Owner সবসময় পারেন। যে role এ On থাকবে সে নিজে করতে পারবে। বাকিরা আটকে গেলে "জরুরি request" পাঠাবে।'),
  once: L('জরুরি অনুমোদন একবারের জন্য', 'an emergency approval works once', 'জরুরি অনুমোদন একবারের জন্য'), window: L('জরুরি অনুমোদন অল্প সময় চলে', 'an emergency approval lasts a short time', 'জরুরি অনুমোদন অল্প সময় চলে'),
  // emergency
  emTitle: L('জরুরি অনুরোধ', 'Emergency requests', 'জরুরি Request'), pending: L('অপেক্ষায়', 'Waiting', 'অপেক্ষায়'), recent: L('সাম্প্রতিক সিদ্ধান্ত', 'Recent decisions', 'সাম্প্রতিক সিদ্ধান্ত'),
  approve: L('এবার অনুমোদন', 'Approve this time', 'এবার অনুমোদন'), reject: L('বাতিল', 'Reject', 'বাতিল'), note: L('নোট (বাতিলে লাগবে)', 'Note (needed to reject)', 'Note (বাতিলে লাগবে)'),
  none: L('কোনো অনুরোধ নেই ✓', 'No requests ✓', 'কোনো request নেই ✓'), who: L('কে', 'Who', 'কে'), why: L('কারণ', 'Reason', 'কারণ'), after: L('এরপর "কে কী পারবে" থেকে ঠিক করুন কাকে স্থায়ীভাবে দেবেন।', 'Afterwards decide in "Who may do what" who gets it for good.', 'এরপর "কে কী পারবে" থেকে ঠিক করুন কাকে স্থায়ীভাবে দেবেন।'),
  decided: L('সিদ্ধান্ত হয়েছে', 'Decided', 'সিদ্ধান্ত হয়েছে'), mins: L('মিনিট', 'min', 'min'),
  st_pending: L('অপেক্ষায়', 'waiting', 'অপেক্ষায়'), st_approved: L('অনুমোদিত — এখন আবার চেষ্টা করুন', 'approved — try again now', 'অনুমোদিত — এখন আবার চেষ্টা করুন'), st_rejected: L('বাতিল', 'rejected', 'বাতিল'), st_used: L('ব্যবহার হয়েছে', 'used', 'ব্যবহার হয়েছে'), st_expired: L('মেয়াদ শেষ', 'expired', 'মেয়াদ শেষ'), st_cancelled: L('ফিরিয়ে নেওয়া', 'cancelled', 'ফিরিয়ে নেওয়া'),
  // staff sheet
  blocked: L('এই কাজ করতে আপনার অনুমতি নেই', 'You do not have permission for this', 'এই কাজ করতে আপনার অনুমতি নেই'), reason: L('কারণ লিখুন (মালিক এটা দেখবেন)', 'Write the reason (the owner will read it)', 'কারণ লিখুন (Owner দেখবেন)'),
  ask: L('জরুরি অনুমোদন চাই', 'Ask for emergency approval', 'জরুরি অনুমোদন চাই'), sent: L('অনুরোধ গেছে — মালিক অনুমোদন দিলে আবার চেষ্টা করুন', 'Request sent — try again once the owner approves', 'Request গেছে — Owner অনুমোদন দিলে আবার চেষ্টা করুন'),
  notAvail: L('এই কাজের জন্য জরুরি অনুরোধ বন্ধ আছে — মালিককে ফোন করুন', 'Emergency requests are off for this — call the owner', 'এই কাজের জন্য জরুরি request বন্ধ — Owner কে ফোন করুন'),
  mine: L('আমার অনুরোধ', 'My requests', 'আমার Request'), close: L('বন্ধ', 'Close', 'Close'), needreason: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 letters)', 'কারণ লিখুন (কমপক্ষে ৩ অক্ষর)'),
  ctx: L('কী করতে গিয়েছিলেন', 'What was attempted', 'কী করতে গিয়েছিলেন'),
  // hub links
  lnLists: L('তালিকা সম্পাদনা — খরচের খাত, মার্কেটিং খাত, বিকাশ/নগদ', 'Edit lists — expense heads, marketing heads, bKash/Nagad', 'List Edit — খরচের খাত, Marketing খাত, bKash/Nagad'),
  lnLoc: L('লোকেশন সীমা — ক্যাশ গরমিল, খরচ, ডিসকাউন্ট ইত্যাদির সীমা', 'Location limits — cash gap, expense, discount etc.', 'Location limit — Cash গরমিল, খরচ, Discount ইত্যাদির limit'),
  lnForm: L('ফর্মের নিয়ম — আগে গোনা, লাল-নিয়ন্ত্রণ, চালু/বন্ধ', 'Form rules — count first, red control, on/off', 'Form এর নিয়ম — আগে গোনা, Red control, On/Off'),
  lnMatrix: L('ভূমিকা × ফর্ম অনুমতি', 'Role × form permissions', 'Role × Form অনুমতি'), lnStaff: L('স্টাফ ও অনুমোদন (ভূমিকা, লোকেশন)', 'Staff & approval (roles, locations)', 'Staff ও অনুমোদন (Role, Location)'),
  lnSet: L('সাধারণ সেটিংস', 'General settings', 'সাধারণ Settings'), lnLog: L('পরিবর্তনের লগ', 'Change log', 'পরিবর্তনের Log'), lnBackup: L('ব্যাকআপ', 'Backup', 'Backup'),
  lnNum: L('নম্বরের ফাঁক-অডিট', 'Number gap audit', 'Number ফাঁক-Audit'), lnBiz: L('ব্যবসার হিসাব', 'Business analysis', 'ব্যবসার Analysis'),
};
const T = (k) => lab(X[k]);
const R = { tab: 'rules', rules: [], defs: [], roles: [], grants: [] };

async function load() {
  const [r, d, ro, g] = await Promise.all([sb.from('rules').select('*').order('sort'), sb.from('grant_defs').select('*').order('sort'), sb.from('roles').select('*').order('sort'), sb.from('rule_grants').select('*')]);
  if (r.error) throw r.error;
  R.rules = r.data || []; R.defs = d.data || []; R.roles = (ro.data || []).filter((x) => x.active && x.code !== 'owner'); R.grants = g.data || [];
}
async function viewHub() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  try { await load(); } catch (e) { return shell(T('title'), `<div class="notice bad">${esc(lab(L('এই অংশ চালু করতে নতুন SQL চালাতে হবে।', 'The new SQL must be run to switch this part on.', 'এই অংশ চালু করতে নতুন SQL চালাতে হবে।')))}</div>`, true); }
  drawHub();
}
function drawHub() {
  shell(T('title'), `<div class="row wrap" style="margin-bottom:10px">${[['rules', 'tabRules'], ['grants', 'tabGrants'], ['more', 'tabMore']].map(([k, l]) => `<button class="tog ${R.tab === k ? 'on' : ''}" data-act="rh_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div><div id="rh_body"></div>`, true);
  if (R.tab === 'rules') drawRules(); else if (R.tab === 'grants') drawGrants(); else drawMore();
}
const cur = (r) => (r.value !== null && r.value !== undefined ? r.value : r.default_value);
function ctl(r) {
  const v = cur(r), isDef = r.value === null || r.value === undefined;
  let c = '';
  if (r.kind === 'switch') c = `<button class="tog ${v === true ? 'on' : ''}" data-act="rh_switch" data-k="${esc(r.key)}">${esc(v === true ? T('on') : T('off'))}</button>`;
  else if (r.kind === 'choice') c = `<select data-rh="${esc(r.key)}">${(r.choices || []).map((x) => `<option value="${esc(x)}" ${v === x ? 'selected' : ''}>${esc(x)}</option>`).join('')}</select>`;
  else c = `<div class="row"><input id="rh_${esc(r.key)}" ${r.kind === 'number' ? 'inputmode="decimal"' : ''} value="${esc(v === null || v === undefined ? '' : String(v))}" placeholder="${esc(r.unit || '')}" style="flex:1">${r.unit && r.kind === 'number' ? `<span class="muted">${esc(r.unit)}</span>` : ''}<button class="primary" data-act="rh_save" data-k="${esc(r.key)}">${esc(T('save'))}</button></div>`;
  return `<div class="card stack"><div class="row between"><b>${esc(pick(r, 'label'))}</b>${isDef ? `<span class="chip">${esc(T('dflt'))}</span>` : `<button class="mini" data-act="rh_reset" data-k="${esc(r.key)}" title="${esc(T('reset'))}">↺</button>`}</div>
    ${pick(r, 'hint') ? `<div class="muted" style="font-size:.85rem">${esc(pick(r, 'hint'))}</div>` : ''}${c}</div>`;
}
function drawRules() {
  const mods = [...new Set(R.rules.map((r) => r.module))];
  $('#rh_body').innerHTML = mods.map((m) => `<h2>${esc(lab(MODS[m] || L(m, m)))}</h2>${R.rules.filter((r) => r.module === m).map(ctl).join('')}`).join('');
}
function drawGrants() {
  const mods = [...new Set(R.defs.map((d) => d.module))];
  $('#rh_body').innerHTML = `<div class="notice ok">${esc(T('grantHint'))}</div>` + mods.map((m) => `<h2>${esc(lab(MODS[m] || L(m === 'access' ? 'অনুমতি' : m, m === 'access' ? 'Access' : m, m === 'access' ? 'Access' : m)))}</h2>` + R.defs.filter((d) => d.module === m).map((d) => `<div class="card stack"><b>${esc(pick(d, 'label'))}</b>
      <div class="muted" style="font-size:.8rem">${esc(T(d.window_type === 'window' ? 'window' : 'once'))}</div>
      <div class="row wrap">${R.roles.map((ro) => { const on = R.grants.some((g) => g.grant_code === d.grant_code && g.role_code === ro.code && g.allowed); return `<button class="tog ${on ? 'on' : ''}" data-act="rh_grant" data-g="${esc(d.grant_code)}" data-r="${esc(ro.code)}">${esc(nm(ro))}</button>`; }).join('')}</div></div>`).join('')).join('');
}
function drawMore() {
  const links = [['lists', 'lnLists'], ['locset', 'lnLoc'], ['rules', 'lnForm'], ['matrix', 'lnMatrix'], ['staff', 'lnStaff'], ['settings', 'lnSet'], ['numaudit', 'lnNum'], ['biz', 'lnBiz'], ['logs', 'lnLog'], ['backup', 'lnBackup']];
  $('#rh_body').innerHTML = links.map(([to, k]) => `<div class="card item" data-act="go" data-v="${to}" style="cursor:pointer"><div class="nm">${esc(T(k))}</div><span class="muted" style="font-size:1.4rem">›</span></div>`).join('');
}
async function setRule(key, value) { const { error } = await sb.rpc('set_rule', { p_key: key, p_value: value }); if (error) { if (/bad_value/.test(error.message || '')) toast(T('badv')); else fail(error); return false; } await B.reloadRules(); await load(); toast(T('saved')); drawHub(); return true; }

// ---------- emergency: owner queue ----------
const GL = (code) => { const d = B.grantDefs()[code]; return d ? pick(d, 'label') : code; };
const ago = (iso) => new Date(iso).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Asia/Dhaka' });
const ctxText = (c) => Object.entries(c || {}).map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : v}`).join(' · ');
async function viewEmergency() {
  shell(T('emTitle'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic();
  const r = await sb.from('emergency_requests').select('*').order('id', { ascending: false }).limit(60); if (r.error) return fail(r.error);
  const pend = r.data.filter((x) => x.status === 'pending'), rest = r.data.filter((x) => x.status !== 'pending').slice(0, 15);
  const locN = (id) => (id ? nm((B.ENV.locs || []).find((l) => l.id === id)) : '');
  const mins = B.rule('em_minutes', 30);
  shell(T('emTitle'), `<div class="notice ok">${esc(T('after'))}</div><h2>${esc(T('pending'))} (${pend.length})</h2>
    ${pend.map((x) => `<div class="card stack"><div class="row between"><b>${esc(GL(x.grant_code))}</b><span class="muted" style="font-size:.8rem">${esc(ago(x.created_at))}</span></div>
      <div>${esc(T('who'))}: <b>${esc(x.requested_staff || '')}</b>${x.location_id ? ' · ' + esc(locN(x.location_id)) : ''}</div><div>${esc(T('why'))}: ${esc(x.reason)}</div>
      ${ctxText(x.context) ? `<div class="muted" style="font-size:.85rem">${esc(T('ctx'))}: ${esc(ctxText(x.context))}</div>` : ''}
      <input id="em_n_${x.id}" placeholder="${esc(T('note'))}"><div class="row"><button class="danger full" data-act="em_decide" data-v="${x.id}" data-ok="0">${esc(T('reject'))}</button>
      <button class="primary full" data-act="em_decide" data-v="${x.id}" data-ok="1">${esc(T('approve'))} (${mins} ${esc(T('mins'))})</button></div></div>`).join('') || `<p class="muted center">${esc(T('none'))}</p>`}
    ${rest.length ? `<h2>${esc(T('recent'))}</h2>${rest.map((x) => `<div class="card"><div class="row between"><span>${esc(GL(x.grant_code))} · ${esc(x.requested_staff || '')}</span><span class="chip">${esc(T('st_' + x.status))}</span></div>
      <div class="muted" style="font-size:.8rem">${esc(x.reason)}${x.decision_note ? ' — ' + esc(x.decision_note) : ''}</div></div>`).join('')}` : ''}
    <button class="full" style="margin-top:10px" data-act="go" data-v="rulehub">${esc(T('tabGrants'))} ›</button>`, true);
}

// ---------- emergency: the staff side ----------
// error text from the server -> which grant would allow it
const ERRGRANT = { discount_needs_approval: 'discount_over_limit', override_needs_approval: 'price_override', over_credit_limit: 'credit_over_limit', customer_required: 'sale_without_customer', period_closed: 'closed_period_edit', insufficient_stock: 'sell_below_zero' };
const em = {
  grantFor: (msg) => { for (const k of Object.keys(ERRGRANT)) if (String(msg || '').includes(k)) return ERRGRANT[k]; return null; },
  allowed(code) { const d = B.grantDefs()[code]; if (!d || !d.emergency_rule) return false; return B.rule('em_enabled', true) === true && B.rule(d.emergency_rule, false) === true; },
  // show why it was blocked and, when allowed, the request form. message = the friendly reason text.
  offer({ grant, loc, context, message }) {
    const ok = em.allowed(grant);
    openSheet(`<h2>${esc(T('blocked'))}</h2><div class="notice warn">${esc(message || GL(grant))}</div><div class="muted" style="margin-bottom:8px">${esc(GL(grant))}</div>
      ${ok ? `<label>${esc(T('reason'))}</label><textarea id="em_reason" rows="3"></textarea><div class="row" style="margin-top:10px"><button class="full" data-act="closesheet">${esc(T('close'))}</button>
        <button class="primary full" data-act="em_send" data-g="${esc(grant)}" data-l="${loc === null || loc === undefined ? '' : loc}" data-c="${esc(JSON.stringify(context || {}))}">${esc(T('ask'))}</button></div>`
      : `<div class="notice bad">${esc(T('notAvail'))}</div><button class="full" data-act="closesheet">${esc(T('close'))}</button>`}
      <button class="full" style="margin-top:8px" data-act="em_mine">${esc(T('mine'))}</button>`);
  },
  async mine() {
    const r = await sb.rpc('my_emergency'); if (r.error) return fail(r.error);
    openSheet(`<h2>${esc(T('mine'))}</h2>${(r.data || []).map((x) => `<div class="card"><div class="row between"><b>${esc(GL(x.grant_code))}</b><span class="chip ${x.status === 'approved' ? 'ok' : ''}">${esc(T('st_' + x.status))}</span></div>
      <div class="muted" style="font-size:.8rem">${esc(x.reason)}${x.decision_note ? ' — ' + esc(x.decision_note) : ''}${x.status === 'approved' && x.valid_until ? ' · ' + esc(ago(x.valid_until)) : ''}</div>
      ${x.status === 'pending' ? `<button class="full" data-act="em_cancel" data-v="${x.id}">${esc(T('reject'))}</button>` : ''}</div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}<button class="full" data-act="closesheet">${esc(T('close'))}</button>`);
  },
};
B.emergency = em;

Object.assign(A.H, {
  rh_tab: (a) => { R.tab = a.dataset.v; drawHub(); },
  rh_switch: (a) => { const r = R.rules.find((x) => x.key === a.dataset.k); return setRule(r.key, !(cur(r) === true)); },
  rh_reset: (a) => setRule(a.dataset.k, null),
  rh_save: (a) => { const r = R.rules.find((x) => x.key === a.dataset.k), raw = norm(($('#rh_' + r.key).value || '').trim());
    if (raw === '') return setRule(r.key, null);
    if (r.kind === 'number') { const n = Number(raw); if (!Number.isFinite(n) || n < 0) return toast(T('badv')); return setRule(r.key, n); }
    if (r.key === 'period_closed_until') { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw), d = m && new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])); if (!m || d.getUTCFullYear() !== +m[1] || d.getUTCMonth() !== +m[2] - 1 || d.getUTCDate() !== +m[3]) return toast(T('baddate')); }
    return setRule(r.key, raw); },
  rh_grant: async (a) => { const on = R.grants.some((g) => g.grant_code === a.dataset.g && g.role_code === a.dataset.r && g.allowed);
    const { error } = await sb.rpc('set_grant', { p_code: a.dataset.g, p_role: a.dataset.r, p_allowed: !on }); if (error) return fail(error); await load(); drawHub(); },
  em_decide: async (a) => { const id = Number(a.dataset.v), ok = a.dataset.ok === '1', note = ($('#em_n_' + id).value || '').trim();
    if (!ok && !note) return toast(T('note'));
    const { error } = await sb.rpc('decide_emergency', { p_id: id, p_approve: ok, p_note: note || null }); if (error) return fail(error); toast(T('decided')); viewEmergency(); },
  em_send: async (a) => { const reason = ($('#em_reason').value || '').trim(); if (reason.length < 3) return toast(T('needreason'));
    let ctx = {}; try { ctx = JSON.parse(a.dataset.c || '{}'); } catch (e) { ctx = {}; }
    const { error } = await sb.rpc('request_emergency', { p_grant: a.dataset.g, p_loc: a.dataset.l === '' ? null : Number(a.dataset.l), p_context: ctx, p_reason: reason });
    if (error) { if (/emergency_off|emergency_not_available/.test(error.message || '')) return toast(T('notAvail')); if (/too_many_pending/.test(error.message || '')) return toast(T('mine')); return fail(error); }
    closeSheet(); toast(T('sent')); },
  em_mine: () => em.mine(),
  em_form: (a) => em.offer({ grant: 'form_access', loc: S.formLoc, context: { form: a.dataset.v, action: 'enter' }, message: lab(L('এই ফর্মে এন্ট্রি দেওয়ার অনুমতি আপনার নেই', 'You do not have permission to enter this form', 'এই form এ entry দেওয়ার অনুমতি আপনার নেই')) }),
  em_cancel: async (a) => { const { error } = await sb.rpc('cancel_emergency', { p_id: Number(a.dataset.v) }); if (error) return fail(error); em.mine(); },
});
document.addEventListener('change', async (e) => { const k = e.target.dataset && e.target.dataset.rh; if (k) await setRule(k, e.target.value); });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { rulehub: viewHub, emergency: viewEmergency });
})();
