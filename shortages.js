/* Islamia BOS · Shortages (#/shortages): cash short / over from counts, and goods short in transit.
   Server: supabase/phase81.sql (cash_short_list / cash_short_decide / cash_short_void, transit_short_list / _set_cost / _claim / _recover / _writeoff).
   Nothing is posted to the books until the owner decides; every decision needs a note. The server is the authority, buttons only mirror it. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum } = U;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('কম / বেশি ও পথে কম মাল', 'Shortages', 'কম / বেশি ও পথে কম'),
  tabCash: L('ক্যাশ কম / বেশি', 'Cash short / over', 'Cash কম / বেশি'), tabTransit: L('পথে কম মাল', 'Short in transit', 'পথে কম মাল'),
  short: L('কম', 'Short', 'কম'), over: L('বেশি', 'Over', 'বেশি'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  open: L('অপেক্ষায়', 'Open', 'Open'), approved: L('অনুমোদিত', 'Approved', 'Approved'), rejected: L('বাতিল করা হয়েছে', 'Rejected', 'Rejected'), void: L('বাতিল (উল্টানো)', 'Voided', 'Voided'),
  claimed: L('বাহকের কাছে দাবি', 'Claimed from carrier', 'Carrier-এর কাছে দাবি'), recovered: L('ফেরত পাওয়া গেছে', 'Recovered', 'Recovered'), written_off: L('ক্ষতি ধরা হয়েছে', 'Written off', 'Written off'),
  approve: L('অ্যাপ্রুভ', 'Approve', 'Approve'), reject: L('বাতিল করুন', 'Reject', 'Reject'), voidIt: L('অ্যাপ্রুভ তুলে নিন', 'Void', 'Void'),
  claim: L('বাহকের কাছে দাবি', 'Claim from carrier', 'Carrier-এর কাছে দাবি'), recover: L('টাকা ফেরত পেলাম', 'Money recovered', 'Money ফেরত পেলাম'), writeoff: L('ক্ষতি ধরুন', 'Write off', 'Write off'),
  setCost: L('দাম লিখুন', 'Enter cost', 'দাম লিখুন'), costMissing: L('দাম জানা নেই', 'Cost missing', 'দাম জানা নেই'),
  note: L('কারণ / নোট (কমপক্ষে ৩ অক্ষর)', 'Reason / note (at least 3 letters)', 'কারণ / note'), amount: L('টাকা', 'Amount', 'Amount'), unitCost: L('প্রতি একক দাম', 'Cost per unit', 'প্রতি unit দাম'),
  mode: L('কোন মাধ্যমে পেলেন', 'Received through', 'কোন মাধ্যমে'), cash: L('নগদ', 'Cash', 'Cash'), bank: L('ব্যাংক', 'Bank', 'Bank'), mobile: L('মোবাইল', 'Mobile', 'Mobile'),
  employee: L('কর্মীর কাছ থেকে আদায় (কর্মী বাছুন)', 'Collect from employee (choose)', 'কর্মীর কাছ থেকে আদায়'), choose: L('বাছুন', 'Choose', 'বাছুন'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('থাক', 'Cancel', 'Cancel'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), posted: L('খাতায় লেখা হয়েছে', 'In the books', 'Books-এ আছে'),
  waiting: L('খাতায় লেখা বন্ধ আছে (নিয়মে চালু করুন)', 'Posting is off (turn it on in Rules)', 'Posting off (Rules-এ চালু করুন)'),
  need: L('অনুমোদনের পর কিছু খাতায় লেখা হয় না যতক্ষণ না মালিক সিদ্ধান্ত নেন।', 'Nothing is written to the books until the owner decides.', 'মালিক সিদ্ধান্ত না নিলে খাতায় কিছু লেখা হয় না।'),
  outstanding: L('দাবির বাকি', 'Claim outstanding', 'দাবির বাকি'), value: L('মূল্য', 'Value', 'মূল্য'), qty: L('কম', 'Short qty', 'কম qty'),
  confirmDup: L('একই দিনে একই জায়গায় হাতে লেখা জার্নাল আছে। তবুও অ্যাপ্রুভ করবেন?', 'A manual journal for cash short already exists on that day and place. Approve anyway?', 'Manual journal আছে। তবুও approve?'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  rBearer: L('বাহকের ক্ষতি কে বহন করবে', 'Who bears carrier loss', 'Carrier loss কে বহন করবে'), rPost: L('খাতায় লেখা', 'Posting to books', 'Books-এ লেখা'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), ask: L('মালিক প্রতিবার ঠিক করেন', 'Owner decides each time', 'Owner প্রতিবার ঠিক করেন'),
  carrier: L('বাহক (আগে দাবি করতে হবে)', 'Carrier (claim first)', 'Carrier (আগে claim)'), shop: L('দোকান (সরাসরি ক্ষতি)', 'Shop (write off)', 'Shop (সরাসরি ক্ষতি)'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: X.noperm, note_required: L('কারণ লিখুন', 'Write a reason'), already_decided: L('এর সিদ্ধান্ত আগেই হয়ে গেছে', 'Already decided'),
  own_count: L('যিনি গুনেছেন তিনি নিজের গোনার সিদ্ধান্ত নিতে পারবেন না', 'Nobody decides the count they made'),
  possible_duplicate: L('একই কম/বেশি হয়তো আগেই হাতে লেখা হয়েছে', 'This may already be booked by hand'),
  employee_required: L('কোন কর্মীর কাছ থেকে আদায় হবে বাছুন', 'Choose the employee to collect from'),
  before_start: L('হিসাব শুরুর তারিখের আগের তারিখ', 'Before the accounting start date'), period_locked: L('এই মাস বন্ধ', 'This period is locked'),
  mapping_missing: L('হিসাবের লিংক নেই (Accounts-এ ঠিক করুন)', 'An account link is missing (fix it in Accounts)'), cost_missing: L('আগে দাম লিখুন', 'Enter the cost first'),
  claim_first: L('নিয়ম অনুযায়ী আগে বাহকের কাছে দাবি করতে হবে', 'By the setting, claim from the carrier first'), shop_bears: L('নিয়ম অনুযায়ী ক্ষতি দোকানের, দাবি নয়', 'By the setting the shop bears this, no claim'),
  not_claimed: L('আগে দাবি করুন', 'Claim first'), bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid'), bad_mode: L('মাধ্যম বাছুন', 'Choose cash, bank or mobile'),
  bad_date: L('তারিখ ঠিক নয়', 'Date is not valid'), data_needed: L('হিসাব শুরুর তারিখ ঠিক করা নেই', 'The accounting start date is not set'),
  not_approved: L('অনুমোদিত নয়', 'Not approved'), cost_known: L('দাম আগেই জানা আছে', 'Cost is already known'), accounting_off: L('হিসাব বন্ধ আছে', 'Accounting is off'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const D = { tab: 'cash', cash: [], transit: [], panel: null, rules: {} };
const rule = (k, d) => (D.rules[k] === undefined || D.rules[k] === null ? d : D.rules[k]);

async function load() {
  const [c, t, r, e] = await Promise.all([
    sb.rpc('cash_short_list', { p_status: null, p_limit: 200 }), sb.rpc('transit_short_list', { p_status: null, p_limit: 200 }),
    sb.from('rules').select('key,value,default_value').in('key', ['cash_short_post_on', 'cash_short_treatment', 'transit_short_bearer']),
    sb.from('employees').select('id,employee_no,full_name_bn,full_name_en').order('employee_no').limit(300),
  ]);
  if (c.error) throw c.error; if (t.error) throw t.error;
  D.cash = c.data || []; D.transit = t.data || []; D.emps = (e && e.data) || [];
  D.rules = {}; ((r && r.data) || []).forEach((x) => { D.rules[x.key] = x.value !== null && x.value !== undefined ? x.value : x.default_value; });
}
const stLab = (s) => T(s) || s;
const badge = (s) => `<span class="muted">· ${esc(stLab(s))}</span>`;
const empName = (x) => esc(x.employee_no ? x.employee_no + ' · ' : '') + esc(lab(L(x.full_name_bn || '', x.full_name_en || x.full_name_bn || '', x.full_name_bn || '')));

function facts() {
  const post = rule('cash_short_post_on', false) === true || rule('cash_short_post_on', false) === 'true';
  const br = rule('transit_short_bearer', 'ask');
  return `<div class="card muted">${esc(T('need'))}<br>${esc(T('rPost'))}: <b>${esc(post ? T('on') : T('off'))}</b> · ${esc(T('rBearer'))}: <b>${esc(T(br === 'carrier' ? 'carrier' : br === 'shop' ? 'shop' : 'ask'))}</b></div>`;
}
function panelHTML(id, kind) {
  const p = D.panel; if (!p || p.id !== id) return '';
  const noteF = `<div><label for="sh_note">${esc(T('note'))}</label><input id="sh_note" autocomplete="off"></div>`;
  let f = noteF;
  if (p.act === 'approve' && p.needEmp) f = `<div><label for="sh_emp">${esc(T('employee'))}</label><select id="sh_emp"><option value="">${esc(T('choose'))}</option>${(D.emps || []).map((x) => `<option value="${esc(x.id)}">${empName(x)}</option>`).join('')}</select></div>` + f;
  if (p.act === 'setcost') f = `<div><label for="sh_cost">${esc(T('unitCost'))}</label><input id="sh_cost" inputmode="decimal" autocomplete="off"></div>` + f;
  if (p.act === 'recover') f = `<div><label for="sh_amt">${esc(T('amount'))}</label><input id="sh_amt" inputmode="decimal" autocomplete="off" value="${esc(p.outstanding)}"></div>
    <div><label for="sh_mode">${esc(T('mode'))}</label><select id="sh_mode"><option value="cash">${esc(T('cash'))}</option><option value="bank">${esc(T('bank'))}</option><option value="mobile">${esc(T('mobile'))}</option></select></div>` + f;
  return `<div class="stack sh-panel" data-panel="${esc(id)}">${f}<div class="row"><button class="full" data-act="sh_cancel">${esc(T('cancel'))}</button><button class="full primary" data-act="sh_go">${esc(T('save'))}</button></div></div>`;
}
function cashHTML() {
  if (!D.cash.length) return `<p class="muted">${esc(T('none'))}</p>`;
  return D.cash.map((c) => {
    const isShort = c.amount < 0;
    const acts = c.can_decide && c.status === 'open'
      ? `<div class="row"><button class="primary" data-act="sh_open" data-k="approve" data-id="${esc(c.id)}" data-short="${isShort ? 1 : 0}">${esc(T('approve'))}</button><button data-act="sh_open" data-k="reject" data-id="${esc(c.id)}">${esc(T('reject'))}</button></div>`
      : (c.status === 'approved' ? `<div class="row"><button class="mini" data-act="sh_open" data-k="void" data-id="${esc(c.id)}">⋮ ${esc(T('voidIt'))}</button></div>` : '');
    const post = c.status === 'approved' ? (c.posted ? ' · ' + T('posted') : ' · ' + T('waiting')) : '';
    return `<div class="card" data-case="${esc(c.id)}"><div class="row between"><b>${esc(T(isShort ? 'short' : 'over'))} ${money(Math.abs(c.amount))}</b>${badge(c.status)}</div>
      <div class="muted">${esc(c.case_date)} · ${esc(c.location || '')} ${c.form_code ? '· ' + esc(c.form_code) : ''}${esc(post)} ${c.decide_note ? '· ' + esc(c.decide_note) : ''}</div>${acts}${panelHTML(c.id, 'cash')}</div>`;
  }).join('');
}
function transitHTML() {
  if (!D.transit.length) return `<p class="muted">${esc(T('none'))}</p>`;
  const br = rule('transit_short_bearer', 'ask');
  return D.transit.map((s) => {
    const it = lab(L(s.item_bn || '', s.item_en || '', s.item_bn || ''));
    let acts = '';
    if (s.can_decide) {
      if (s.cost_missing) acts = `<div class="row"><button class="primary" data-act="sh_open" data-k="setcost" data-id="${esc(s.id)}">${esc(T('setCost'))}</button></div>`;
      else if (s.status === 'open') acts = `<div class="row">${br === 'shop' ? '' : `<button class="primary" data-act="sh_open" data-k="claim" data-id="${esc(s.id)}">${esc(T('claim'))}</button>`}${br === 'carrier' ? '' : `<button data-act="sh_open" data-k="writeoff" data-id="${esc(s.id)}">${esc(T('writeoff'))}</button>`}</div>`;
      else if (s.status === 'claimed') acts = `<div class="row"><button class="primary" data-act="sh_open" data-k="recover" data-id="${esc(s.id)}" data-out="${esc(s.outstanding_claim)}">${esc(T('recover'))}</button><button data-act="sh_open" data-k="writeoff" data-id="${esc(s.id)}">${esc(T('writeoff'))}</button></div>`;
    }
    return `<div class="card" data-short="${esc(s.id)}"><div class="row between"><b>${esc(it)} · ${esc(T('qty'))} ${esc(s.qty_short)}</b>${badge(s.status)}</div>
      <div class="muted">${esc(s.received_on)} · ${esc(s.from_name || '')} → ${esc(s.to_name || '')} · ${s.cost_missing ? esc(T('costMissing')) : esc(T('value')) + ' ' + money(s.value)}
      ${s.status === 'claimed' ? ' · ' + esc(T('outstanding')) + ' ' + money(s.outstanding_claim) : ''} ${s.note ? '· ' + esc(s.note) : ''}</div>${acts}${panelHTML(s.id, 'transit')}</div>`;
  }).join('');
}
function body() {
  const tabs = `<div class="row"><button class="${D.tab === 'cash' ? 'primary' : ''}" data-act="sh_tab" data-v="cash">${esc(T('tabCash'))} (${D.cash.filter((x) => x.status === 'open').length})</button>
    <button class="${D.tab === 'transit' ? 'primary' : ''}" data-act="sh_tab" data-v="transit">${esc(T('tabTransit'))} (${D.transit.filter((x) => x.status === 'open' || x.status === 'claimed').length})</button></div>`;
  return tabs + facts() + (D.tab === 'cash' ? cashHTML() : transitHTML());
}
async function show() { const el = $('#sh_body'); if (!el) return; await load(); el.innerHTML = body(); }
const val = (id) => ($(id) || {}).value || '';

async function go() {
  const p = D.panel; if (!p) return;
  const note = val('#sh_note').trim();
  if (note.length < 3) return toast(lab(ERR.note_required));
  let r;
  if (p.act === 'approve') {
    const emp = val('#sh_emp');
    if (p.needEmp && !emp) return toast(lab(ERR.employee_required));
    r = await sb.rpc('cash_short_decide', { p_id: p.id, p_approve: true, p_note: note, p_employee: emp || null, p_force: !!p.force });
    if (r.error && !p.force && /possible_duplicate/.test(r.error.message) && window.confirm(T('confirmDup'))) { D.panel.force = true; return go(); }
    if (r.error && /employee_required/.test(r.error.message) && !p.needEmp) { D.panel.needEmp = true; $('#sh_body').innerHTML = body(); return toast(lab(ERR.employee_required)); }
  } else if (p.act === 'reject') r = await sb.rpc('cash_short_decide', { p_id: p.id, p_approve: false, p_note: note });
  else if (p.act === 'void') r = await sb.rpc('cash_short_void', { p_id: p.id, p_note: note });
  else if (p.act === 'claim') r = await sb.rpc('transit_short_claim', { p_id: p.id, p_note: note });
  else if (p.act === 'writeoff') r = await sb.rpc('transit_short_writeoff', { p_id: p.id, p_note: note });
  else if (p.act === 'setcost') {
    const c = nnum(val('#sh_cost')); if (!(c > 0)) return toast(lab(ERR.bad_amount));
    r = await sb.rpc('transit_short_set_cost', { p_id: p.id, p_unit_cost: c, p_note: note });
  } else if (p.act === 'recover') {
    const a = nnum(val('#sh_amt')); if (!(a > 0)) return toast(lab(ERR.bad_amount));
    r = await sb.rpc('transit_short_recover', { p_id: p.id, p_amount: a, p_mode: val('#sh_mode') || null, p_note: note });
  }
  if (!r || r.error) return toast(eText(r && r.error));
  D.panel = null; toast(T('saved')); await show();
}
Object.assign(H, {
  sh_tab: (a) => { D.tab = a.dataset.v; D.panel = null; $('#sh_body').innerHTML = body(); },
  sh_open: (a) => {
    const k = a.dataset.k; D.panel = { id: a.dataset.id, act: k, outstanding: a.dataset.out || '' };
    if (k === 'approve' && a.dataset.short === '1' && rule('cash_short_treatment', 'expense') === 'staff_receivable') D.panel.needEmp = true;
    $('#sh_body').innerHTML = body();
  },
  sh_cancel: () => { D.panel = null; $('#sh_body').innerHTML = body(); },
  sh_go: () => go().catch(fail),
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="sh_body"><p class="muted">…</p></div>', true);
  try { await show(); } catch (e) { const el = $('#sh_body'); if (el && /not allowed/.test(String(e && e.message))) el.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; else fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { shortages: view });
})();
