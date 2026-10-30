/* Islamia BOS · Pay requests (R1). Nobody has to ask for money by word of mouth: a request is written in the app, one responsible person decides, the payment goes through the existing functions.
   Screens: #/payrequest (staff: ask for salary or an advance, see the status and dates), #/partyrequest (any staff: ask to pay a supplier),
   #/payapprovals (the chosen person: waiting, due today, later, all; approve on the date asked or on another date, reject with a reason, pay), #/payreqsettings (owner: who decides, switches, limits).
   Server: supabase/phase120.sql (pay_request_state / submit / decide / cancel / pay / list / counts / approver_set / exception_open; set_rule for the switches). Nothing is decided in the browser:
   a hidden button is also a refused request on the server. Payment source: the shared picker BOS.moneySrc (cash, mobile banking, bank: chosen at the moment of paying).
   UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const money = (n) => { const v = Number(n); return Number.isFinite(v) ? v.toLocaleString('en-IN', { maximumFractionDigits: 2 }) : '-'; };
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const dt = (s) => String(s || '').slice(0, 10);

const X = {
  t_staff: L('বেতন / অগ্রিমের অনুরোধ', 'Ask for salary or advance', 'বেতন / Advance চাওয়া'), t_party: L('সরবরাহকারীকে টাকা দেওয়ার অনুরোধ', 'Ask to pay a supplier', 'Supplier-কে payment request'),
  t_appr: L('টাকা দেওয়ার অনুরোধ - সিদ্ধান্ত', 'Pay requests to decide', 'Pay request - সিদ্ধান্ত'), t_set: L('অনুরোধের সিদ্ধান্তদাতা ও নিয়ম', 'Pay request settings', 'Pay request settings'),
  off: L('এই সুবিধা এখনো চালু হয়নি। মালিক চালু করলে এখান থেকে অনুরোধ পাঠানো যাবে।', 'This is not switched on yet. When the owner switches it on you can send a request from here.', 'এই সুবিধা এখনো চালু হয়নি।'),
  goset: L('চালু করতে নিয়ম পাতায় যান', 'Go to the settings page to switch it on', 'Settings-এ যান'),
  kind: L('কী চান', 'What do you need', 'কী চান'), k_advance: L('অগ্রিম', 'Advance', 'Advance'), k_salary: L('বেতন (পাওনা বেতন)', 'Salary (due pay)', 'Salary (পাওনা)'), k_supplier: L('সরবরাহকারী', 'Supplier', 'Supplier'),
  amount: L('টাকা', 'Amount', 'Amount'), reason: L('কারণ', 'Reason', 'কারণ'), needed: L('কবে লাগবে', 'Needed by', 'কবে লাগবে'), send: L('অনুরোধ পাঠান', 'Send the request', 'Request পাঠান'),
  forwho: L('কার জন্য', 'For', 'কার জন্য'), me: L('আমার নিজের', 'Myself', 'আমার নিজের'), supplier: L('সরবরাহকারী', 'Supplier', 'Supplier'), place: L('জায়গা', 'Place', 'Place'),
  bill: L('কোন বিল / কিস্তি', 'Which bill or due', 'কোন bill / due'), askedby: L('সরবরাহকারীর পক্ষে কে জানিয়েছেন (ঐচ্ছিক)', 'Who at the supplier asked (optional)', 'Supplier-এর কে বলেছেন (ঐচ্ছিক)'),
  mine: L('আমার অনুরোধ', 'My requests', 'আমার request'), none: L('কিছু নেই।', 'Nothing here.', 'কিছু নেই।'), sent: L('অনুরোধ পাঠানো হয়েছে', 'Request sent', 'Request পাঠানো হয়েছে'),
  s_received: L('পৌঁছেছে, সিদ্ধান্তের অপেক্ষায়', 'Received, waiting for a decision', 'পৌঁছেছে, অপেক্ষায়'), s_approved: L('অনুমোদিত', 'Approved', 'Approved'), s_rejected: L('নাকচ', 'Rejected', 'Rejected'),
  s_paid: L('দেওয়া হয়েছে', 'Paid', 'Paid'), s_cancelled: L('বাতিল', 'Cancelled', 'Cancelled'), paydate: L('দেওয়ার ডেট', 'Pay date', 'Pay date'),
  changed: L('আপনার চাওয়া ডেট ছিল', 'You asked for', 'আপনি চেয়েছিলেন'), asked: L('চাওয়া', 'asked', 'asked'), appramt: L('অনুমোদিত টাকা', 'Approved amount', 'Approved amount'),
  history: L('ইতিহাস', 'History', 'History'), cancel: L('বাতিল করুন', 'Cancel it', 'Cancel'), cancelq: L('কেন বাতিল করছেন?', 'Why are you cancelling?', 'কেন cancel?'),
  tab_wait: L('অপেক্ষায়', 'Waiting', 'Waiting'), tab_due: L('আজ দেওয়ার', 'Due today', 'Due today'), tab_later: L('পরে', 'Later', 'Later'), tab_all: L('সব', 'All', 'All'),
  approve: L('অ্যাপ্রুভ', 'Approve', 'Approve'), reject: L('নাকচ', 'Reject', 'Reject'), pay: L('এখন দিন', 'Pay now', 'Pay now'), overdue: L('দেরি হয়েছে', 'Overdue', 'Overdue'),
  asks: L('চেয়েছেন', 'asks', 'asks'), onbehalf: L('অন্যের হয়ে লেখা', 'entered for someone', 'অন্যের হয়ে'), note: L('নোট', 'Note', 'Note'),
  decide_h: L('অ্যাপ্রুভ: কবে ও কত', 'Approve: when and how much', 'Approve: কবে ও কত'), date_on: L('এই ডেটে দেওয়া হবে', 'Pay on', 'এই Dateে দেওয়া হবে'),
  rejq: L('কেন নাকচ করছেন? (স্টাফ দেখবে)', 'Why is it rejected? (the staff member will see this)', 'কেন reject? (staff দেখবে)'),
  pay_h: L('টাকা দিন', 'Pay this request', 'Pay করুন'), paymode: L('কীভাবে দিচ্ছেন', 'Paid by', 'Paid by'), cash: L('নগদ', 'Cash', 'Cash'), mobile: L('মোবাইল ব্যাংকিং', 'Mobile banking', 'Mobile'), bank: L('ব্যাংক', 'Bank', 'Bank'),
  ins: L('কিস্তি (অগ্রিম, ঐচ্ছিক)', 'Instalment (advance, optional)', 'কিস্তি (ঐচ্ছিক)'), recfrom: L('কোন মাস থেকে কাটবে (ঐচ্ছিক)', 'Recover from month (optional)', 'কোন মাস থেকে (ঐচ্ছিক)'),
  paid_ok: L('পেমেন্ট হয়েছে', 'Paid', 'Paid'), save: L('সেভ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), back: L('ফিরুন', 'Back', 'Back'),
  who: L('কে সিদ্ধান্ত দেবে', 'Who decides', 'কে decide'), m_owner: L('মালিক', 'The owner', 'Owner'), m_role: L('একটি ভূমিকার সবাই', 'Everyone with a role', 'একটি role'), m_user: L('একজন নির্দিষ্ট ব্যক্তি', 'One named person', 'একজন person'), m_same: L('স্টাফ অনুরোধের মতোই', 'Same as staff requests', 'Staff-এর মতোই'),
  role: L('ভূমিকা', 'Role', 'Role'), person: L('ব্যক্তি', 'Person', 'Person'), ownerAlways: L('মালিক সবসময় সিদ্ধান্ত দিতে পারেন।', 'The owner can always decide.', 'Owner সবসময় decide করতে পারেন।'),
  sw_staff: L('স্টাফ বেতন / অগ্রিম চাইতে পারবে', 'Staff can ask for salary or advance', 'Staff request পাঠাতে পারবে'), sw_req: L('অনুমোদিত অনুরোধ ছাড়া বেতন / অগ্রিম নয় (মুখের কথায় নয়)', 'No salary or advance without an approved request (verbal request policy)', 'Approved request ছাড়া payment নয়'),
  sw_kinds: L('কোনটিতে লাগবে', 'Applies to', 'কোনটিতে'), sw_exc: L('অনুরোধ ছাড়া দিতে হলে', 'If it must be paid without a request', 'Request ছাড়া দিতে হলে'),
  sw_pstaff: L('সরবরাহকারীর পেমেন্টের অনুরোধ চালু', 'Supplier payment requests', 'Supplier request চালু'), sw_preq: L('অনুমোদিত অনুরোধ ছাড়া সরবরাহকারীকে পেমেন্ট নয়', 'No supplier payment without an approved request', 'Request ছাড়া supplier payment নয়'),
  lim_h: L('সীমা (ফাঁকা = সীমা নেই)', 'Limits (blank = no limit)', 'Limit (ফাঁকা = নেই)'), lim_n: L('একজন মাসে সর্বোচ্চ অনুরোধ', 'Most requests per person per month', 'মাসে max request'), lim_c: L('অগ্রিমের সর্বোচ্চ মোট (টাকা)', 'Advance ceiling (Tk)', 'Advance ceiling (Tk)'),
  on: L('চালু', 'On', 'On'), offs: L('বন্ধ', 'Off', 'Off'), ex_link: L('ব্যতিক্রম তালিকা দেখুন', 'See the Exceptions list', 'Exceptions দেখুন'), gate: L('পেমেন্টের পাহারা', 'Payment check', 'Payment check'),
  exh: L('অনুরোধ ছাড়া পেমেন্ট: কারণ লিখুন', 'Pay without a request: write the reason', 'Request ছাড়া payment: কারণ'), exgo: L('একবার অনুমতি নিন', 'Allow one payment', 'একবার অনুমতি'),
  e_requests_off: L('এই সুবিধা বন্ধ আছে।', 'This is switched off.', 'বন্ধ আছে।'), e_no_employee_profile: L('আপনার নামে কর্মচারীর রেকর্ড জোড়া নেই। অফিসে জানান।', 'Your login is not linked to an employee record. Tell the office.', 'Employee record জোড়া নেই।'),
  e_monthly_request_limit: L('এই মাসে আর অনুরোধ পাঠানো যাবে না (সীমা শেষ)।', 'The limit of requests for this month is reached.', 'এই মাসের limit শেষ।'), e_advance_ceiling: L('অগ্রিমের সর্বোচ্চ সীমা পেরিয়ে যাবে।', 'This would pass the advance ceiling.', 'Advance ceiling পেরিয়ে যাবে।'),
  e_bad_amount: L('টাকার অঙ্ক ঠিক নয়।', 'The amount is not valid.', 'Amount ঠিক নয়।'), e_reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)।', 'Write a reason (at least 3 characters).', 'কারণ লিখুন।'), e_bad_date: L('ডেট ঠিক নয়।', 'The date is not valid.', 'Date ঠিক নয়।'),
  e_approver_only: L('এই সিদ্ধান্ত শুধু নির্ধারিত ব্যক্তি দিতে পারেন।', 'Only the person chosen for this can decide.', 'শুধু নির্ধারিত ব্যক্তি।'), e_self_approval: L('নিজের অনুরোধ নিজে অ্যাপ্রুভ করা যায় না।', 'You cannot decide your own request.', 'নিজের request নিজে নয়।'),
  e_self_payment: L('নিজের অনুরোধের টাকা নিজে দেওয়া যায় না।', 'You cannot pay your own request.', 'নিজের request নিজে pay নয়।'), e_request_not_pending: L('এটি আগেই নিষ্পত্তি হয়েছে।', 'This was already settled.', 'আগেই নিষ্পত্তি।'),
  e_request_not_approved: L('অনুমোদিত নয় বা আগেই দেওয়া হয়েছে।', 'Not approved, or already paid.', 'Approved নয় / paid।'), e_not_due_yet: L('দেওয়ার ডেট এখনো আসেনি।', 'The pay date has not come yet.', 'Date আসেনি।'),
  e_note_required: L('কারণ লিখুন।', 'Write a reason.', 'কারণ লিখুন।'), e_mode_required: L('কীভাবে দিচ্ছেন তা বাছুন।', 'Choose how it is paid.', 'কীভাবে বাছুন।'), e_more_than_due: L('এই মাসের পাওনা বেতনের চেয়ে বেশি।', 'More than the salary due.', 'পাওনার চেয়ে বেশি।'),
  e_no_payroll_due: L('এই কর্মীর অনুমোদিত বেতন শিটে পাওনা নেই।', 'No approved payroll amount is due for this person.', 'Payroll-এ পাওনা নেই।'), e_pay_request_required: L('অনুমোদিত অনুরোধ ছাড়া এই পেমেন্ট করা যাবে না।', 'No approved request backs this payment.', 'Approved request নেই।'),
  e_overpaid: L('সরবরাহকারীর বকেয়ার চেয়ে বেশি।', 'More than the supplier balance.', 'বকেয়ার চেয়ে বেশি।'), e_not_allowed: L('অনুমতি নেই।', 'You are not allowed.', 'অনুমতি নেই।'), e_held_by_payment_limit: L('সরবরাহকারী পেমেন্টের সীমায় আটকে গেছে (মালিক দেবেন)।', 'Held by the supplier payment limit (the owner can pay it).', 'Payment limit-এ আটকেছে।'),
  e_bad_role: L('এই ভূমিকা নেওয়া যাবে না।', 'That role cannot be used.', 'Role নেওয়া যাবে না।'), e_no_one_holds_role: L('এই ভূমিকায় কেউ নেই।', 'Nobody holds that role.', 'Role-এ কেউ নেই।'), e_unknown_user: L('ব্যক্তি পাওয়া যায়নি।', 'Person not found.', 'Person নেই।'),
  e_exceptions_off: L('অনুরোধ ছাড়া দেওয়ার কোনো উপায় রাখা হয়নি।', 'No way past is allowed.', 'ব্যতিক্রম বন্ধ।'), e_owner_only: L('শুধু মালিক এই অনুমতি দিতে পারেন।', 'Only the owner can allow this.', 'শুধু owner।'), e_not_required: L('এই পেমেন্টে অনুরোধ লাগে না।', 'No request is needed for this payment.', 'Request লাগে না।'),
};
const T = (k) => lab(X[k] || L(k, k, k));
const ERRK = Object.keys(X).filter((k) => k.startsWith('e_')).map((k) => k.slice(2)).sort((a, b) => b.length - a.length);
const eText = (e) => { const m = String((e && e.message) || '').replace(/\s+/g, '_'); const k = ERRK.find((x) => m.includes(x)); return k ? T('e_' + k) : (m || 'error'); };
const D = { st: null, tab: 'due', rows: [], mine: [], sup: [], emp: [], busy: false, cid: null };
const B2 = (B.payRequests = B.payRequests || { approver: false });

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;
const kindName = (k) => T('k_' + k);
async function loadState() { try { D.st = await call('pay_request_state', {}); B2.approver = !!(D.st.approver_staff || D.st.approver_party); } catch (e) { D.st = null; } return D.st; }
const probe = () => { loadState().catch(() => {}); };
// only ask the server once a person is signed in AND approved (an anonymous or pending visitor has no right to this call)
const signedIn = () => !!(S.ctx && S.ctx.profile && S.ctx.profile.status === 'active');
let prqTries = 0; const prqTimer = setInterval(() => { if (++prqTries > 120) return clearInterval(prqTimer); if (signedIn()) { clearInterval(prqTimer); probe(); } }, 500);

// ---------- one request card ----------
function statusLine(r) {
  const st = r.status;
  if (st === 'received') return chip(T('s_received'), 'warn');
  if (st === 'rejected') return chip(T('s_rejected'), 'bad') + (r.decision_note ? ` <span class="muted">${esc(r.decision_note)}</span>` : '');
  if (st === 'cancelled') return chip(T('s_cancelled'));
  if (st === 'paid') return chip(T('s_paid'), 'ok') + ` <span class="muted">${esc(dt(r.paid_at))} · ${esc(money(r.paid_amount))}</span>`;
  const ch = r.date_changed ? ` <span class="muted prq-changed">${esc(T('changed'))} ${esc(dt(r.needed_by))}</span>` : '';
  return chip(T('s_approved') + ' · ' + T('paydate') + ' ' + dt(r.pay_date), r.overdue ? 'bad' : 'ok') + ch + (r.approved_amount && Number(r.approved_amount) !== Number(r.amount) ? ` <span class="muted">${esc(T('appramt'))} ${esc(money(r.approved_amount))}</span>` : '')
    + (r.decision_note ? ` <span class="muted">${esc(r.decision_note)}</span>` : '');
}
function timeline(r) {
  const ev = r.events || [];
  if (!ev.length) return '';
  return `<details class="prq-hist"><summary>${esc(T('history'))}</summary>${ev.map((e) => `<div class="muted">${esc(dt(e.at))} · ${esc(e.action)}${e.by ? ' · ' + esc(e.by) : ''}${e.note ? ' · ' + esc(e.note) : ''}</div>`).join('')}</details>`;
}
function card(r, o = {}) {
  const who = o.approver ? `<div class="muted">${esc(r.subject || '-')} ${esc(T('asks'))}${r.on_behalf && r.kind !== 'supplier' ? ' · ' + esc(T('onbehalf')) : ''}${r.asked_by_name ? ' · ' + esc(r.asked_by_name) : ''}</div>` : (r.kind === 'supplier' ? `<div class="muted">${esc(r.subject || '')}</div>` : '');
  const bill = r.bill_ref ? `<div class="muted">${esc(T('bill'))}: ${esc(r.bill_ref)}</div>` : '';
  const btns = [];
  if (r.can_decide && r.status === 'received') btns.push(`<button type="button" class="btn primary" data-act="prq_decide" data-v="${r.id}">${esc(T('approve'))}</button><button type="button" class="btn" data-act="prq_reject" data-v="${r.id}">${esc(T('reject'))}</button>`);
  if (r.can_pay) btns.push(`<button type="button" class="btn primary" data-act="prq_pay" data-v="${r.id}">${esc(T('pay'))}</button>`);
  if (r.can_decide && r.status === 'approved') btns.push(`<button type="button" class="mini" data-act="prq_decide" data-v="${r.id}">⋮ ${esc(T('paydate'))}</button>`);
  if (r.can_cancel) btns.push(`<button type="button" class="mini" data-act="prq_cancel" data-v="${r.id}">⋮ ${esc(T('cancel'))}</button>`);
  return `<div class="card stack prq-card" data-id="${r.id}" data-status="${esc(r.status)}" data-kind="${esc(r.kind)}"><div class="row between"><b>${esc(kindName(r.kind))}</b><b>${esc(money(r.amount))}</b></div>${who}
    <div>${esc(r.reason)}</div>${bill}<div class="muted">${esc(T('needed'))}: ${esc(dt(r.needed_by))} · ${esc(dt(r.requested_at))}</div><div class="row wrap">${statusLine(r)}${r.overdue ? chip(T('overdue'), 'bad') : ''}</div>
    ${btns.length ? `<div class="row wrap">${btns.join('')}</div>` : ''}${timeline(r)}</div>`;
}

// ---------- staff page ----------
function offBlock() {
  return `<div class="card stack" id="prq_off"><p>${esc(T('off'))}</p>${D.st && D.st.is_owner ? `<a href="#/payreqsettings" data-act="go" data-v="payreqsettings">${esc(T('goset'))}</a>` : ''}</div>`;
}
async function staffView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('t_staff'), '<div id="prq_body"><p class="muted">…</p></div>', true);
  try {
    await loadState();
    if (!D.st || !D.st.staff_on) { $('#prq_body').innerHTML = offBlock(); return; }
    if (D.st.can_on_behalf) { try { const r = await sb.from('employees').select('id,full_name_en,full_name_bn,employee_no,status').in('status', ['active', 'on_leave']).order('employee_no'); D.emp = r.data || []; } catch (e) { D.emp = []; } }
    D.cid = rid();
    await drawStaff();
  } catch (e) { fail(e); }
}
async function drawStaff() {
  const rows = (await call('pay_request_list', { p_scope: 'mine', p_limit: 100 })).rows.filter((r) => r.kind !== 'supplier');
  const st = D.st || {};
  const empSel = st.can_on_behalf ? fld('prq_emp', T('forwho'), `<select id="prq_emp"><option value="">${esc(T('me'))}</option>${D.emp.map((e) => `<option value="${esc(e.id)}">${esc(e.employee_no || '')} ${esc(e.full_name_en || e.full_name_bn)}</option>`).join('')}</select>`) : '';
  const form = `<div class="card stack" id="prq_form">${fld('prq_kind', T('kind'), `<select id="prq_kind"><option value="advance">${esc(T('k_advance'))}</option><option value="salary">${esc(T('k_salary'))}</option></select>`)}${empSel}
    ${fld('prq_amt', T('amount'), inp('prq_amt', '', 'inputmode="decimal" maxlength="14"'))}${fld('prq_reason', T('reason'), inp('prq_reason', '', 'maxlength="300"'))}
    ${fld('prq_date', T('needed'), `<input id="prq_date" type="date" min="${today()}" value="${addDays(today(), 2)}">`)}<button type="button" class="btn primary full" data-act="prq_send">${esc(T('send'))}</button>
    ${st.max_per_month ? `<div class="muted">${esc(T('lim_n'))}: ${esc(st.max_per_month)}</div>` : ''}</div>`;
  $('#prq_body').innerHTML = form + `<h3>${esc(T('mine'))}</h3><div id="prq_list">${rows.map((r) => card(r)).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}

// ---------- party page ----------
async function partyView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('t_party'), '<div id="prq_body"><p class="muted">…</p></div>', true);
  try {
    await loadState();
    if (!D.st || !D.st.party_on) { $('#prq_body').innerHTML = offBlock(); return; }
    try { const r = await sb.rpc('supplier_pick'); D.sup = r && !r.error ? r.data || [] : []; } catch (e) { D.sup = []; }
    D.cid = rid();
    await drawParty();
  } catch (e) { fail(e); }
}
async function drawParty() {
  const rows = (await call('pay_request_list', { p_scope: 'mine', p_limit: 100 })).rows.filter((r) => r.kind === 'supplier');
  const locs = (B.s2 && B.s2.LOCS ? B.s2.LOCS() : []);
  const nm = (l) => (A.nm ? A.nm(l) : l.name || l.name_en || l.id);
  const form = `<div class="card stack" id="prq_form">${fld('prq_sup', T('supplier'), `<select id="prq_sup"><option value="">—</option>${D.sup.map((s) => `<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('')}</select>`)}
    ${fld('prq_loc', T('place'), `<select id="prq_loc">${locs.map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select>`)}
    ${fld('prq_amt', T('amount'), inp('prq_amt', '', 'inputmode="decimal" maxlength="14"'))}${fld('prq_bill', T('bill'), inp('prq_bill', '', 'maxlength="80"'))}
    ${fld('prq_reason', T('reason'), inp('prq_reason', '', 'maxlength="300"'))}${fld('prq_by', T('askedby'), inp('prq_by', '', 'maxlength="80"'))}
    ${fld('prq_date', T('needed'), `<input id="prq_date" type="date" min="${today()}" value="${addDays(today(), 2)}">`)}<button type="button" class="btn primary full" data-act="prq_sendp">${esc(T('send'))}</button></div>`;
  $('#prq_body').innerHTML = form + `<h3>${esc(T('mine'))}</h3><div id="prq_list">${rows.map((r) => card(r)).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}

// ---------- approver page ----------
const TABS = [['wait', 'tab_wait', 'inbox'], ['due', 'tab_due', 'due'], ['later', 'tab_later', 'upcoming'], ['all', 'tab_all', 'all']];
async function apprView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('t_appr'), '<div id="prq_body"><p class="muted">…</p></div>', true);
  try { await loadState(); await drawAppr(); } catch (e) { fail(e); }
}
async function drawAppr(tab) {
  if (tab) D.tab = tab;
  const c = (D.st && D.st.counts) || {};
  const scope = (TABS.find((x) => x[0] === D.tab) || TABS[1])[2];
  const rows = (await call('pay_request_list', { p_scope: scope, p_limit: 200 })).rows;
  const bar = `<div class="row wrap" id="prq_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="prq_tab" data-v="${k}">${esc(T(l))}${k === 'wait' && c.inbox ? ' (' + c.inbox + ')' : k === 'due' && c.due ? ' (' + c.due + ')' : ''}</button>`).join('')}</div>`;
  D.rows = rows;
  $('#prq_body').innerHTML = bar + (rows.map((r) => card(r, { approver: true })).join('') || `<p class="muted">${esc(T('none'))}</p>`)
    + (D.st && D.st.is_owner ? `<p><a href="#/payreqsettings" data-act="go" data-v="payreqsettings">${esc(T('t_set'))}</a> · <a href="#/exceptions" data-act="go" data-v="exceptions">${esc(T('ex_link'))}</a></p>` : '');
}

// ---------- owner settings ----------
const KEYS = ['pay_requests_on', 'pay_requests_required', 'pay_requests_required_kinds', 'pay_request_exception_mode', 'pay_request_max_per_month', 'pay_request_advance_ceiling', 'party_requests_on', 'party_requests_required'];
async function setView() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('t_set'), '<div id="prq_body"><p class="muted">…</p></div>', true);
  try {
    await loadState();
    const r = await sb.from('rules').select('key,kind,value,default_value,choices,label_en,hint_en').in('key', KEYS); D.rules = r.data || [];
    const p = await sb.from('profiles').select('id,full_name,staff_id,status').eq('status', 'active').order('full_name'); D.people = p.data || [];
    const ro = await sb.from('roles').select('code,name_en,active').eq('active', true).order('sort'); D.roles = (ro.data || []).filter((x) => x.code !== 'owner');
    drawSet();
  } catch (e) { fail(e); }
}
const cur = (k) => { const r = (D.rules || []).find((x) => x.key === k) || {}; return r.value !== null && r.value !== undefined ? r.value : r.default_value; };
const swc = (k, label) => `<div class="card row between prq-sw" data-key="${k}"><span>${esc(label)}</span><button type="button" class="tog ${cur(k) === true ? 'on' : ''}" data-act="prq_sw" data-v="${k}">${esc(cur(k) === true ? T('on') : T('offs'))}</button></div>`;
const selc = (k, label, opts) => `<div class="card stack prq-sel" data-key="${k}"><label for="prqs_${k}">${esc(label)}</label><div class="row"><select id="prqs_${k}">${opts.map((o) => `<option value="${o}" ${cur(k) === o ? 'selected' : ''}>${esc(o)}</option>`).join('')}</select><button type="button" class="mini" data-act="prq_selsave" data-v="${k}">${esc(T('save'))}</button></div></div>`;
function apprBlock(scope) {
  const a = ((D.st && D.st.approver) || {})[scope] || {}, modes = scope === 'party' ? ['same', 'owner', 'role', 'user'] : ['owner', 'role', 'user'];
  const shown = scope === 'party' && D.st && D.st.approver.party_same ? 'same' : a.mode;
  return `<div class="card stack prq-appr" data-scope="${scope}"><b>${esc(T('who'))}${scope === 'party' ? ' · ' + esc(T('t_party')) : ''}</b>
    <select id="prqa_mode_${scope}">${modes.map((m) => `<option value="${m}" ${shown === m ? 'selected' : ''}>${esc(T('m_' + m))}</option>`).join('')}</select>
    <select id="prqa_role_${scope}" aria-label="${esc(T('role'))}"><option value="">${esc(T('role'))}</option>${D.roles.map((x) => `<option value="${esc(x.code)}" ${a.role === x.code ? 'selected' : ''}>${esc(x.name_en || x.code)}</option>`).join('')}</select>
    <select id="prqa_user_${scope}" aria-label="${esc(T('person'))}"><option value="">${esc(T('person'))}</option>${D.people.map((x) => `<option value="${esc(x.id)}" ${a.user === x.id ? 'selected' : ''}>${esc(x.full_name || x.staff_id)}</option>`).join('')}</select>
    <button type="button" class="btn primary" data-act="prq_appr" data-v="${scope}">${esc(T('save'))}</button><div class="muted">${esc(T('ownerAlways'))}</div></div>`;
}
function drawSet() {
  const g = (D.st && D.st.gate) || {};
  const lim = (k, label) => `<div class="card stack prq-lim" data-key="${k}"><label for="prql_${k}">${esc(label)}</label><div class="row"><input id="prql_${k}" inputmode="decimal" autocomplete="off" value="${esc(cur(k) ?? '')}"><button type="button" class="mini" data-act="prq_limsave" data-v="${k}">${esc(T('save'))}</button></div></div>`;
  $('#prq_body').innerHTML = `<h3>${esc(T('t_staff'))}</h3>${swc('pay_requests_on', T('sw_staff'))}${apprBlock('staff')}${swc('pay_requests_required', T('sw_req'))}${selc('pay_requests_required_kinds', T('sw_kinds'), ['both', 'advance', 'salary'])}
    ${selc('pay_request_exception_mode', T('sw_exc'), ['reason', 'owner', 'never'])}<h3>${esc(T('lim_h'))}</h3>${lim('pay_request_max_per_month', T('lim_n'))}${lim('pay_request_advance_ceiling', T('lim_c'))}
    <h3>${esc(T('t_party'))}</h3>${swc('party_requests_on', T('sw_pstaff'))}${apprBlock('party')}${swc('party_requests_required', T('sw_preq'))}
    <div class="row wrap">${chip(T('gate') + ': ' + [g.advance, g.salary, g.supplier].filter(Boolean).length + '/3', [g.advance, g.salary, g.supplier].every(Boolean) ? 'ok' : 'warn')}<a href="#/exceptions" data-act="go" data-v="exceptions">${esc(T('ex_link'))}</a></div>`;
}

// ---------- actions ----------
const byId = (id) => (D.rows || []).find((r) => r.id === Number(id));
Object.assign(H, {
  prq_send: act(async () => {
    const amt = Number(norm(val('prq_amt'))); if (!(amt > 0)) return toast(T('e_bad_amount'));
    if (val('prq_reason').length < 3) return toast(T('e_reason_required'));
    await call('pay_request_submit', { p_kind: val('prq_kind'), p_amount: amt, p_reason: val('prq_reason'), p_needed_by: val('prq_date'), p_employee: val('prq_emp') || null, p_client: D.cid });
    toast(T('sent')); D.cid = rid(); await drawStaff();
  }),
  prq_sendp: act(async () => {
    const amt = Number(norm(val('prq_amt'))); if (!(amt > 0)) return toast(T('e_bad_amount'));
    if (!val('prq_sup')) return toast(T('supplier'));
    if (val('prq_reason').length < 3) return toast(T('e_reason_required'));
    await call('pay_request_submit', { p_kind: 'supplier', p_amount: amt, p_reason: val('prq_reason'), p_needed_by: val('prq_date'), p_employee: null, p_client: D.cid, p_supplier: val('prq_sup'), p_bill: null, p_bill_ref: val('prq_bill') || null, p_asked_by: val('prq_by') || null, p_loc: Number(val('prq_loc')) || null });
    toast(T('sent')); D.cid = rid(); await drawParty();
  }),
  prq_cancel: act(async (a) => {
    const n = window.prompt(T('cancelq')); if (!n || n.trim().length < 3) return;
    await call('pay_request_cancel', { p_id: Number(a.dataset.v), p_note: n.trim() });
    const h = location.hash; if (/partyrequest/.test(h)) await drawParty(); else if (/payapprovals/.test(h)) { await loadState(); await drawAppr(); } else await drawStaff();
  }),
  prq_tab: act(async (a) => { await drawAppr(a.dataset.v); }),
  prq_decide: (a) => {
    const r = byId(a.dataset.v); if (!r) return;
    openSheet(`<h3>${esc(T('decide_h'))}</h3><div class="stack">${fld('prqd_date', T('date_on'), `<input id="prqd_date" type="date" min="${today()}" value="${esc(dt(r.pay_date || r.needed_by) < today() ? today() : dt(r.pay_date || r.needed_by))}">`)}
      <div class="muted">${esc(T('needed'))}: ${esc(dt(r.needed_by))}</div>${fld('prqd_amt', T('appramt'), inp('prqd_amt', r.approved_amount || r.amount, 'inputmode="decimal"'))}${fld('prqd_note', T('note'), inp('prqd_note', '', 'maxlength="300"'))}
      <button type="button" class="btn primary" data-act="prq_decide_go" data-v="${r.id}">${esc(T('approve'))}</button></div>`);
  },
  prq_decide_go: act(async (a) => {
    const amt = Number(norm(val('prqd_amt'))); if (!(amt > 0)) return toast(T('e_bad_amount'));
    await call('pay_request_decide', { p_id: Number(a.dataset.v), p_approve: true, p_pay_date: val('prqd_date') || null, p_amount: amt, p_note: val('prqd_note') || null });
    closeSheet(); toast(T('saved')); await loadState(); await drawAppr();
  }),
  prq_reject: act(async (a) => {
    const n = window.prompt(T('rejq')); if (!n || n.trim().length < 3) return;
    await call('pay_request_decide', { p_id: Number(a.dataset.v), p_approve: false, p_pay_date: null, p_amount: null, p_note: n.trim() });
    toast(T('saved')); await loadState(); await drawAppr();
  }),
  prq_pay: async (a) => {
    const r = byId(a.dataset.v); if (!r) return;
    if (B.moneySrc) { try { await B.moneySrc.prefetch(r.kind === 'advance' ? 'salary_advance' : r.kind === 'salary' ? 'salary_payment' : 'supplier_payment', r.location_id); } catch (e) { /* no picker */ } }
    const ev = r.kind === 'advance' ? 'salary_advance' : r.kind === 'salary' ? 'salary_payment' : 'supplier_payment';
    openSheet(`<h3>${esc(T('pay_h'))}</h3><div class="stack"><div><b>${esc(r.subject || '')}</b> · ${esc(money((r.approved_amount || r.amount) - r.paid_amount))}</div>
      ${fld('prqp_mode', T('paymode'), `<select id="prqp_mode"><option value="cash">${esc(T('cash'))}</option><option value="mobile">${esc(T('mobile'))}</option><option value="bank">${esc(T('bank'))}</option></select>`)}
      ${B.moneySrc ? B.moneySrc.slot('pp', ev, { loc: r.location_id }) : ''}
      ${r.kind === 'advance' ? fld('prqp_ins', T('ins'), inp('prqp_ins', '', 'inputmode="decimal"')) + fld('prqp_from', T('recfrom'), '<input id="prqp_from" type="month">') : ''}
      ${fld('prqp_note', T('note'), inp('prqp_note', '', 'maxlength="150"'))}<button type="button" class="btn primary" data-act="prq_pay_go" data-v="${r.id}">${esc(T('pay'))}</button></div>`);
  },
  prq_pay_go: act(async (a) => {
    if (D.busy) return; D.busy = true;
    try {
      const acc = B.moneySrc ? B.moneySrc.get('pp') : null, ins = norm(val('prqp_ins')), fm = val('prqp_from');
      await call('pay_request_pay', { p_id: Number(a.dataset.v), p_mode: val('prqp_mode') || null, p_money_account: acc ? Number(acc) : null, p_ref: null, p_note: val('prqp_note') || null, p_instalment: ins ? Number(ins) : null, p_recover_from: fm ? fm + '-01' : null });
      closeSheet(); toast(T('paid_ok')); await loadState(); await drawAppr();
    } finally { D.busy = false; }
  }),
  prq_sw: act(async (a) => { const k = a.dataset.v; await call('set_rule', { p_key: k, p_value: cur(k) !== true }); await setView(); }),
  prq_selsave: act(async (a) => { const k = a.dataset.v; await call('set_rule', { p_key: k, p_value: val('prqs_' + k) }); toast(T('saved')); await setView(); }),
  prq_limsave: act(async (a) => { const k = a.dataset.v, raw = norm(val('prql_' + k)); await call('set_rule', { p_key: k, p_value: raw === '' ? null : Number(raw) }); toast(T('saved')); await setView(); }),
  prq_appr: act(async (a) => {
    const sc = a.dataset.v, mode = val('prqa_mode_' + sc);
    await call('pay_request_approver_set', { p_scope: sc, p_mode: mode, p_role: mode === 'role' ? val('prqa_role_' + sc) : null, p_user: mode === 'user' ? val('prqa_user_' + sc) : null, p_note: null });
    toast(T('saved')); await setView();
  }),
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { payrequest: staffView, partyrequest: partyView, payapprovals: apprView, payreqsettings: setView });
})();
