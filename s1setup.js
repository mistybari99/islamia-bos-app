/* Islamia BOS · Cost marks & intake bot (#/s1setup): (1) the items whose cost is REALLY zero ("cost is free" mark, so they are not treated as an unknown cost) and the list of tracked items whose cost is still
   unknown (the cost_missing list); (2) the dedicated intake bot for online orders (can create orders and receive messages, has no POS right). OWNER / COST-RIGHT HOLDERS ONLY.
   The two switches of this step (partner_base_estimate, packaging_return_mode) are ordinary rules and show in the switchboard; nothing is set here by default.
   Server: supabase/phase80.sql (item_cost_free_set, item_cost_flags_list, cost_unknown_items, intake_bot_create, intake_bot_check). Handlers are prefixed s1_. Loaded after costattrib.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const owner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('খরচ চিহ্ন ও ইনটেক বট', 'Cost marks & intake bot', 'Cost চিহ্ন ও intake bot'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  noperm: L('অনুমতি নেই — খরচ দেখার অধিকার লাগবে', 'Not allowed — the cost right is needed', 'অনুমতি নেই — cost right লাগবে'), saved: L('সংরক্ষণ হয়েছে', 'Saved', 'Saved'),
  sqlMissing: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase80)', 'The database part is not installed yet (phase80)', 'Database অংশ চালু হয়নি (phase80)'),
  tFree: L('খরচ সত্যিই শূন্য', 'Cost really zero', 'Cost সত্যিই শূন্য'), tBot: L('ইনটেক বট', 'Intake bot', 'Intake bot'),
  freeNote: L('যে আইটেমের খরচ সত্যিই ০ (যেমন নিজেদের পানি), সেটা এখানে চিহ্নিত করুন। চিহ্ন না দিলে ০ বা ফাঁকা খরচ "অজানা" ধরা হয় এবং রিপোর্ট "সাময়িক" থাকে।',
    'Mark an item whose cost is really 0 (for example your own water). Without the mark, a blank or 0 cost counts as unknown and the reports stay provisional.',
    'যে item-এর cost সত্যিই ০ (যেমন নিজেদের পানি), সেটা এখানে mark করুন। mark না দিলে ০ বা ফাঁকা cost "অজানা" ধরা হয়, report "সাময়িক" থাকে।'),
  marked: L('চিহ্ন দেওয়া আইটেম', 'Marked items', 'Mark করা item'), unknown: L('খরচ অজানা', 'Cost unknown', 'Cost অজানা'),
  costMissing: L('খরচ অজানা', 'Cost missing', 'Cost অজানা'), place: L('জায়গা', 'Place', 'Place'), all: L('সব জায়গা', 'All places', 'সব জায়গা'),
  markFree: L('খরচ শূন্য চিহ্ন দিন', 'Mark cost as zero', 'Cost শূন্য mark দিন'), unmark: L('চিহ্ন তুলুন', 'Remove the mark', 'Mark তুলুন'),
  askReason: L('কেন খরচ শূন্য? (কমপক্ষে ৩ অক্ষর)', 'Why is the cost zero? (at least 3 characters)', 'কেন cost শূন্য? (কমপক্ষে ৩ অক্ষর)'), qty: L('পরিমাণ', 'Qty', 'Qty'),
  botNote: L('ইনটেক বট শুধু অনলাইন অর্ডার ঢোকাতে ও বার্তা নিতে পারে; বিক্রি (POS), অর্ডার বদল, ইনবক্স দেখা পারে না। আগে থেকে POS-এর অনুমতি আছে এমন ব্যক্তিকে বট করা যায় না।',
    'The intake bot can only create online orders and receive messages. It cannot sell (POS), edit orders or read the inbox. A user who already has a POS right cannot be made a bot.',
    'Intake bot শুধু online order ঢোকাতে ও message নিতে পারে; বিক্রি (POS), order বদল, inbox দেখা পারে না। আগে থেকে POS অনুমতি আছে এমন user-কে bot করা যায় না।'),
  user: L('ব্যবহারকারী', 'User', 'User'), makeBot: L('বট হিসেবে চালু করুন', 'Set up as bot', 'Bot হিসেবে চালু করুন'), check: L('যাচাই', 'Check', 'যাচাই'),
  isBot: L('বট চালু', 'Bot is on', 'Bot চালু'), hasRole: L('ইনটেক রোল আছে', 'Has the intake role', 'Intake role আছে'), posEnter: L('POS অনুমতি আছে', 'Has a POS right', 'POS অনুমতি আছে'),
  yes: L('হ্যাঁ', 'Yes', 'হ্যাঁ'), no: L('না', 'No', 'না'), ownerOnly: L('শুধু মালিক', 'Owner only', 'শুধু মালিক'), pick: L('— বাছুন —', '— choose —', '— বাছুন —')
};
const T = (k) => lab(X[k]);
const ERR = {
  reason_required: L('কারণ লিখতে হবে (কমপক্ষে ৩ অক্ষর)', 'A reason is needed (at least 3 characters)', 'কারণ লিখতে হবে (কমপক্ষে ৩ অক্ষর)'),
  bot_has_pos_role: L('এই ব্যক্তির POS-এর অনুমতি আছে — বট করা যাবে না', 'This user already has a POS right and cannot be a bot', 'এই user-এর POS অনুমতি আছে — bot করা যাবে না'),
  owner_cannot_be_bot: L('মালিক বট হতে পারে না', 'The owner cannot be a bot', 'মালিক bot হতে পারে না'), user_not_found: L('ব্যবহারকারী পাওয়া যায়নি', 'User not found', 'User পাওয়া যায়নি'),
  location_not_found: L('জায়গা পাওয়া যায়নি', 'Place not found', 'জায়গা পাওয়া যায়নি'), not_found: L('আইটেম পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি')
};
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/could not find the function|schema cache|does not exist/i.test(m)) return toast(T('sqlMissing')); return toast(m || 'error'); };
const D = { tab: 'free', locs: [], loc: '', flags: [], unk: [], people: [], check: null, botUser: '', botLoc: '' };
const nm = (r) => esc(r.code + ' · ' + lab({ bn: r.name_bn, mix: r.name_bn, en: r.name_en || r.name_bn }));

async function loadFree() {
  const [lo, fl, un] = await Promise.all([sb.from('locations').select('id,name_bn,name_en').order('id'), sb.rpc('item_cost_flags_list'), sb.rpc('cost_unknown_items', { p_loc: D.loc === '' ? null : Number(D.loc) })]);
  if (fl.error) throw fl.error; if (un.error) throw un.error;
  D.locs = lo.data || []; D.flags = fl.data || []; D.unk = un.data || [];
}
async function loadBot() {
  const [lo, pe] = await Promise.all([sb.from('locations').select('id,name_bn,name_en').order('id'), sb.from('profiles').select('id,staff_id,full_name,status').eq('status', 'active').order('full_name')]);
  D.locs = lo.data || []; D.people = pe.data || [];
}
const locOpts = (withAll) => (withAll ? `<option value="">${esc(T('all'))}</option>` : `<option value="">${esc(T('pick'))}</option>`) + D.locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(withAll ? D.loc : D.botLoc) ? 'selected' : ''}>${esc(lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }))}</option>`).join('');

function paneFree() {
  return `<div class="card stack"><div class="muted">${esc(T('freeNote'))}</div></div>
    <h4>${esc(T('marked'))}</h4>${D.flags.length ? D.flags.map((r) => `<div class="card row between wrap"><span><b>${nm(r)}</b>${r.reason ? `<div class="muted">${esc(r.reason)}</div>` : ''}</span><button type="button" class="mini" data-act="s1_unfree" data-id="${esc(r.item_id)}">${esc(T('unmark'))}</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    <h4>${esc(T('unknown'))}</h4><div class="card stack"><label>${esc(T('place'))}<select id="s1_loc">${locOpts(true)}</select></label></div>
    ${D.unk.length ? D.unk.map((r) => `<div class="card row between wrap"><span><b>${nm(r)}</b> <span class="chip warn">${esc(T('costMissing'))}</span><div class="muted">${esc(T('qty'))}: ${esc(String(r.qty))}</div></span><button type="button" class="mini" data-act="s1_free" data-id="${esc(r.item_id)}">${esc(T('markFree'))}</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}`;
}
function paneBot() {
  if (!owner()) return `<p class="muted">${esc(T('ownerOnly'))}</p>`;
  const c = D.check;
  return `<div class="card stack"><div class="muted">${esc(T('botNote'))}</div>
    <label>${esc(T('user'))}<select id="s1_user"><option value="">${esc(T('pick'))}</option>${D.people.map((p) => `<option value="${esc(p.id)}" ${p.id === D.botUser ? 'selected' : ''}>${esc((p.staff_id ? p.staff_id + ' · ' : '') + (p.full_name || p.id))}</option>`).join('')}</select></label>
    <label>${esc(T('place'))}<select id="s1_bloc">${locOpts(false)}</select></label>
    <div class="row wrap"><button type="button" class="btn primary" data-act="s1_botmake">${esc(T('makeBot'))}</button><button type="button" class="btn" data-act="s1_botcheck">${esc(T('check'))}</button></div></div>` +
    (c ? `<div class="card stack"><div>${esc(T('isBot'))}: <b>${esc(c.is_bot ? T('yes') : T('no'))}</b></div><div>${esc(T('hasRole'))}: <b>${esc(c.has_intake_role ? T('yes') : T('no'))}</b></div><div>${esc(T('posEnter'))}: <b>${esc(c.pos_enter ? T('yes') : T('no'))}</b></div></div>` : '');
}
function draw() {
  const el = $('#s1_body'); if (!el) return;
  const tabs = [['free', 'tFree'], ['bot', 'tBot']];
  el.innerHTML = `<div class="tabs" style="display:flex;gap:6px;margin-bottom:8px">${tabs.map((t) => `<button type="button" data-act="s1_tab" data-v="${t[0]}" class="${D.tab === t[0] ? 'on' : ''}" style="min-width:0;flex:1 1 40%">${esc(T(t[1]))}</button>`).join('')}</div>${D.tab === 'free' ? paneFree() : paneBot()}`;
}
async function reload() { try { if (D.tab === 'free') await loadFree(); else await loadBot(); draw(); } catch (e) { errMsg(e); } }
Object.assign(H, {
  s1_tab: async (a) => { D.tab = a.dataset.v; await reload(); },
  s1_free: async (a) => {
    const why = window.prompt(T('askReason')); if (why === null) return; if (String(why).trim().length < 3) return toast(lab(ERR.reason_required));
    const r = await sb.rpc('item_cost_free_set', { p_item: a.dataset.id, p_free: true, p_reason: String(why).trim(), p_client: rid() }); if (r.error) return errMsg(r.error); toast(T('saved')); await reload();
  },
  s1_unfree: async (a) => { const r = await sb.rpc('item_cost_free_set', { p_item: a.dataset.id, p_free: false, p_reason: null, p_client: rid() }); if (r.error) return errMsg(r.error); toast(T('saved')); await reload(); },
  s1_botmake: async () => {
    const u = ($('#s1_user') || {}).value, l = Number(($('#s1_bloc') || {}).value); if (!u || !l) return toast(T('pick'));
    D.botUser = u; D.botLoc = String(l);
    const r = await sb.rpc('intake_bot_create', { p_user: u, p_loc: l }); if (r.error) return errMsg(r.error);
    const c = await sb.rpc('intake_bot_check', { p_user: u }); D.check = c.error ? null : c.data; toast(T('saved')); draw();
  },
  s1_botcheck: async () => { const u = ($('#s1_user') || {}).value; if (!u) return toast(T('pick')); D.botUser = u; const c = await sb.rpc('intake_bot_check', { p_user: u }); if (c.error) return errMsg(c.error); D.check = c.data; draw(); }
});
document.addEventListener('change', async (e) => { const t = e.target; if (t && t.id === 's1_loc') { D.loc = t.value; await reload(); } });

async function view() {
  shell(T('title'), `<div id="s1_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try {
    let ok = owner(); if (!ok) { try { ok = !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { ok = false; } }
    if (!ok) { const b = $('#s1_body'); if (b) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
    await loadFree(); draw();
  } catch (e) { const b = $('#s1_body'); if (b && /not allowed|permission/i.test((e && e.message) || '')) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; else errMsg(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { s1setup: view });
})();
