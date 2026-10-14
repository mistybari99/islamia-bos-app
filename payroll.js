/* Islamia BOS · Payroll (#/payroll): month + place -> Preview (trial, writes nothing, full calculation trail and warnings) -> Create run (draft) ->
   adjust lines (bonus / deduction / +- adjustment, each with a reason) -> Approve (owner; locks the month's attendance) -> Pay (cash / bank / mobile,
   all lines or one, in part) -> payslip print, CSV export, month summary by place. Also staff advances (recovered by instalments), festival bonus of
   the month (matches the bonus rules of each pay structure) and a final-settlement preview for someone leaving mid-month.
   Server: supabase/phase42.sql - payroll_preview / payroll_create / payroll_refresh / payroll_line_adjust / payroll_approve / payroll_pay /
   payroll_payment_void / payroll_void / payroll_settlement_preview / payroll_bonus_event_save / staff_advance_add / staff_advance_void / staff_advances_list.
   Salary privacy: nothing is fetched unless the person is the owner or holds salary_view / payroll_manage at the place. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const prevMonth = () => { const d = new Date(today() + 'T00:00:00Z'); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString().slice(0, 7); };
const X = {
  title: L('বেতন শিট', 'Payroll', 'Payroll'), place: L('জায়গা', 'Place', 'Place'), month: L('মাস', 'Month', 'Month'), summary: L('সব জায়গা - মাসের সারাংশ', 'All places - month summary', 'সব জায়গা - summary'),
  s1: L('১ আগে দেখুন', '1 Preview', '১ Preview'), s2: L('২ শিট তৈরি', '2 Create', '২ Create'), s3: L('৩ সমন্বয়', '3 Adjust', '৩ Adjust'), s4: L('৪ অনুমোদন', '4 Approve', '৪ Approve'), s5: L('৫ বেতন দিন', '5 Pay', '৫ Pay'),
  preview: L('আগে দেখুন (ট্রায়াল - কিছু লেখা হবে না)', 'Preview (trial - nothing is saved)', 'Preview (trial - কিছু save হবে না)'), trial: L('ট্রায়াল: কিছু লেখা হয়নি', 'Trial: nothing was saved', 'Trial: কিছু save হয়নি'),
  create: L('বেতন শিট তৈরি করুন (খসড়া)', 'Create the payroll (draft)', 'Payroll তৈরি (draft)'), refresh: L('হাজিরা থেকে আবার হিসাব', 'Recalculate from attendance', 'Attendance থেকে আবার হিসাব'),
  approve: L('অনুমোদন ও মাস বন্ধ', 'Approve and lock the month', 'Approve ও মাস lock'), approveQ: L('অনুমোদনের পর এই মাসের হাজিরা ও বেতন আর বদলানো যাবে না। অনুমোদন করবেন?', 'After approval this month\'s attendance and pay cannot change. Approve?', 'Approve করলে মাস lock হবে। করবেন?'),
  pay: L('বেতন দিন', 'Pay', 'Pay'), payAll: L('বাকি সবাইকে বেতন দিন', 'Pay everyone still unpaid', 'বাকি সবাইকে pay'), voidRun: L('শিট বাতিল', 'Void this payroll', 'Payroll বাতিল'), csv: L('CSV নামান', 'Export CSV', 'CSV export'),
  people: L('জন', 'people', 'জন'), gross: L('মোট আয়', 'Gross', 'Gross'), ded: L('কর্তন', 'Deductions', 'Deductions'), net: L('হাতে পাবেন', 'Net pay', 'Net'), paid: L('দেওয়া হয়েছে', 'Paid', 'Paid'),
  draft: L('খসড়া', 'Draft', 'Draft'), approved: L('অনুমোদিত', 'Approved', 'Approved'), pstatus: L('পরিশোধিত', 'Paid', 'Paid'), void: L('বাতিল', 'Void', 'Void'), unpaid: L('বাকি', 'Unpaid', 'Unpaid'), partly: L('আংশিক', 'Part paid', 'Part paid'),
  noRun: L('এই মাসের শিট এখনো হয়নি', 'No payroll for this month yet', 'এই মাসের payroll হয়নি'), noperm: L('বেতন দেখার অনুমতি নেই', 'You are not allowed to see pay', 'Salary দেখার permission নেই'),
  payslip: L('পে-স্লিপ', 'Payslip', 'Payslip'), print: L('প্রিন্ট', 'Print', 'Print'), addBonus: L('＋ বোনাস', '＋ Bonus', '＋ Bonus'), addDed: L('＋ কর্তন', '＋ Deduction', '＋ Deduction'), adjust: L('± সমন্বয়', '± Adjustment', '± Adjust'),
  name: L('নাম', 'Name', 'Name'), amount: L('টাকা', 'Amount', 'Amount'), reason: L('কারণ (জরুরি)', 'Reason (required)', 'কারণ (জরুরি)'), save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), remove: L('বাদ', 'Remove', 'Remove'),
  mode: L('কীভাবে', 'Paid by', 'Paid by'), cash: L('নগদ', 'Cash', 'Cash'), bank: L('ব্যাংক', 'Bank', 'Bank'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), date: L('তারিখ', 'Date', 'Date'), ref: L('রেফারেন্স', 'Reference', 'Reference'), note: L('নোট', 'Note', 'Note'),
  why: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন'), trail: L('হিসাবের ধাপ', 'How it was calculated', 'হিসাবের ধাপ'), warnings: L('সতর্কতা', 'Warnings', 'Warnings'),
  earn: L('আয়', 'Earnings', 'Earnings'), basic: L('মূল বেতন', 'Basic', 'Basic'), allow: L('ভাতা', 'Allowances', 'Allowances'), ot: L('ওভারটাইম', 'Overtime', 'Overtime'), bonus: L('বোনাস', 'Bonus', 'Bonus'),
  absent: L('অনুপস্থিতি', 'Absence', 'Absence'), late: L('দেরি', 'Late arrivals', 'Late'), unpaidD: L('বিনা বেতনের দিন', 'Unpaid days', 'Unpaid days'), notEmp: L('চাকরির বাইরের দিন', 'Days not employed', 'চাকরির বাইরের দিন'),
  struct: L('কাঠামোর কর্তন (PF ইত্যাদি)', 'Structure deductions (PF etc.)', 'Structure কর্তন'), advance: L('অগ্রিম কাটা', 'Advance recovery', 'Advance কাটা'), other: L('অন্য কর্তন', 'Other deductions', 'অন্য কর্তন'), adj: L('সমন্বয়', 'Adjustments', 'Adjustments'),
  days: L('দিন', 'Days', 'Days'), paidDays: L('বেতনের দিন', 'Paid days', 'Paid days'), lateCount: L('দেরি (বার)', 'Lates', 'Lates'), otH: L('ওভারটাইম (ঘণ্টা)', 'OT hours', 'OT hours'), sign: L('গ্রহীতার সই', 'Received by', 'Received by'), round: L('পূর্ণ টাকায়', 'Rounding', 'Rounding'),
  tRun: L('বেতন শিট', 'Payroll', 'Payroll'), tAdv: L('অগ্রিম', 'Advances', 'Advances'), tMore: L('বোনাস ও চূড়ান্ত হিসাব', 'Bonus & settlement', 'Bonus ও settlement'),
  addAdv: L('＋ অগ্রিম দিন', '＋ Give an advance', '＋ Advance'), who: L('কর্মচারী', 'Employee', 'Employee'), inst: L('মাসে কত করে কাটা (ফাঁকা = এক বারে)', 'Monthly instalment (empty = all at once)', 'মাসে কত কাটা (ফাঁকা = একবারে)'),
  recFrom: L('কোন মাস থেকে কাটা', 'Recover from month', 'কোন মাস থেকে কাটা'), outst: L('বাকি', 'Owed', 'Owed'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), modeNone: L('টাকা আগে দেওয়া (০২-৩ ফর্মে লেখা)', 'Already paid out (written on form 02-3)', 'আগে দেওয়া (০২-৩)'),
  festival: L('এই মাসে উৎসব বোনাস', 'Festival bonus paid this month', 'এই মাসে festival bonus'), festName: L('বোনাসের নাম (বেতন কাঠামোর মতো, যেমন Eid)', 'Bonus name (as in the pay structures, e.g. Eid)', 'Bonus নাম (যেমন Eid)'),
  settle: L('চূড়ান্ত হিসাব (চাকরি ছাড়লে)', 'Final settlement (leaving)', 'Final settlement'), lastDay: L('শেষ কাজের দিন', 'Last working day', 'শেষ কাজের দিন'), show: L('দেখুন (কিছু লেখা হবে না)', 'Show (nothing is saved)', 'দেখুন'),
  advLeft: L('পরেও বাকি থাকবে অগ্রিম', 'Advance still owed after this', 'পরেও বাকি advance'), due: L('বাকি পাওনা', 'Due', 'Due'),
  w_no_pay_structure: L('বেতন কাঠামো নেই - শিটে আসবে না', 'No pay structure - left out', 'Pay structure নেই'), w_no_joining_date: L('যোগদানের তারিখ নেই', 'No joining date', 'Joining date নেই'),
  w_days_not_computed: L('দিনের হাজিরা হিসাব হয়নি (বেতনসহ ধরা হলো)', 'days without attendance (counted as paid)', 'দিনের হাজিরা নেই'), w_month_not_finished: L('দিন এখনো বাকি (মাস শেষ হয়নি)', 'days still to come', 'দিন বাকি'),
  w_unapproved_days: L('দিন হাতে লেখা, অনুমোদন বাকি', 'manual days waiting approval', 'manual দিন approval বাকি'), w_single_punch_days: L('দিন একবার আঙুল', 'days with one punch', 'দিন একবার punch'),
  w_ot_waiting_approval_min: L('মিনিট ওভারটাইম অনুমোদনের অপেক্ষায় (ধরা হয়নি)', 'OT minutes waiting approval (not paid)', 'OT মিনিট approval বাকি'), w_ot_not_paid_no_rule: L('ওভারটাইম আছে কিন্তু নিয়ম নেই', 'Overtime but no OT rule', 'OT আছে, rule নেই'),
  w_bonus_not_eligible: L('বোনাসের যোগ্য নয় (চাকরির মেয়াদ কম)', 'not eligible for bonus (service too short)', 'Bonus-এর যোগ্য নয়'), w_advance_recovery_capped: L('বেতন কম, অগ্রিম পুরো কাটা যায়নি', 'Pay too low to recover the full instalment', 'পুরো advance কাটা যায়নি'),
  w_negative_net: L('হাতে পাওয়া ঋণাত্মক!', 'Net pay is negative!', 'Net negative!'), w_register_02_3_advance: L('০২-৩ রেজিস্টারে অগ্রিম বাকি - এখানে যোগ করলে কাটা হবে', 'advance owed in register 02-3 - add it here to recover', '০২-৩-এ advance বাকি'),
  w_already_in_run: L('আগেই একটি শিটে আছে', 'Already in a payroll', 'আগেই payroll-এ'),
  k_basic: L('মূল বেতন', 'Basic', 'Basic'), k_days: L('চাকরির দিন / মাসের দিন', 'Days employed / in month', 'Days employed / month'), k_day_rate: L('এক দিনের বেতন', 'One day\'s pay', 'Day rate'),
  k_not_employed: L('চাকরির বাইরের দিন', 'Days not employed', 'Not employed'), k_absent: L('অনুপস্থিত', 'Absent', 'Absent'), k_unpaid: L('বিনা বেতনের দিন', 'Unpaid days', 'Unpaid'), k_daily_pay: L('দৈনিক মজুরি', 'Daily pay', 'Daily pay'),
  k_hourly_pay: L('ঘণ্টা হিসাবে', 'Hourly pay', 'Hourly pay'), k_allowances: L('ভাতা', 'Allowances', 'Allowances'), k_late: L('দেরি', 'Late', 'Late'), k_ot: L('ওভারটাইম', 'Overtime', 'Overtime'), k_advance: L('অগ্রিম কাটা', 'Advance', 'Advance'),
  k_structure_deductions: L('কাঠামোর কর্তন', 'Structure deductions', 'Structure কর্তন'),
};
const T = (k) => lab(X[k]);
const ERR = {
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), payroll_off: L('বেতন শিট এখন বন্ধ (সুইচবোর্ড)', 'Payroll is switched off (Switchboard)', 'Payroll বন্ধ'), bad_month: L('মাস ঠিক নয় (ভবিষ্যতের মাস নয়)', 'Month is not valid (not a future month)', 'মাস ঠিক নয়'),
  run_exists: L('এই মাস ও জায়গার শিট আগেই আছে', 'A payroll for this month and place already exists', 'Payroll আগেই আছে'), payroll_locked: L('শিট অনুমোদিত - আর বদলানো যাবে না', 'The payroll is approved - it cannot change', 'Payroll lock'),
  run_not_approved: L('আগে অনুমোদন লাগবে', 'Approve it first', 'আগে approve'), nothing_to_pay: L('দেওয়ার মতো কিছু বাকি নেই', 'Nothing left to pay', 'কিছু বাকি নেই'), more_than_due: L('পাওনার চেয়ে বেশি', 'More than is due', 'পাওনার চেয়ে বেশি'),
  negative_net: X.w_negative_net, run_has_payments: L('বেতন দেওয়া হয়ে গেছে - আগে পেমেন্ট বাতিল করুন', 'Salaries were paid - void the payments first', 'আগে payment বাতিল'), run_empty: L('শিটে কেউ নেই', 'Nobody in this payroll', 'Payroll খালি'),
  reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (3+ letters)', 'কারণ লিখুন'), bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount ঠিক নয়'), bad_mode: L('নগদ / ব্যাংক / মোবাইল বাছুন', 'Choose cash / bank / mobile', 'Mode বাছুন'),
  bad_date: L('তারিখ ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'), name_required: L('নাম লিখুন', 'Write the name', 'নাম লিখুন'), advance_partly_recovered: L('অগ্রিম থেকে কাটা শুরু হয়ে গেছে', 'Recovery has started on this advance', 'Advance কাটা শুরু হয়েছে'),
  advance_changed_refresh: L('অগ্রিম বদলেছে - আগে আবার হিসাব করুন', 'Advances changed - recalculate first', 'আগে আবার হিসাব'), period_closed: L('এই তারিখের হিসাব বন্ধ', 'This date is closed', 'Date বন্ধ'), bad_instalment: L('কিস্তি ঠিক নয়', 'Instalment is not valid', 'কিস্তি ঠিক নয়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : (m || 'error'); };
const P = { loc: undefined, month: prevMonth(), tab: 'run', run: null, lines: [], pv: null, can: {}, emps: [], client: rid() };
const m01 = () => P.month + '-01';
async function can(code, loc) {
  if (S.ctx.is_owner) return true;
  const k = code + '|' + loc; if (k in P.can) return P.can[k];
  P.can[k] = await U.grant(code, loc); return P.can[k];
}
const seeOk = async (loc) => S.ctx.is_owner || await can('salary_view', loc) || await can('payroll_manage', loc);
const n2 = (v) => money(Number(v) || 0);
const css = document.createElement('style'); css.id = 'prcss';
css.textContent = `.pr-steps{display:flex;gap:4px;flex-wrap:wrap;margin:8px 0}.pr-steps span{font-size:12px;padding:2px 8px;border-radius:12px;border:1px solid var(--hair)}.pr-steps span.on{background:var(--ok-bg);border-color:transparent}
.pr-row{display:flex;gap:8px;align-items:center;justify-content:space-between}.pr-row .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}.pr-num{font-variant-numeric:tabular-nums}b.pr-num{white-space:nowrap}.pr-pick{display:flex;flex-wrap:wrap;gap:8px}.pr-pick>div{flex:1 1 150px;min-width:0}.pr-pick select,.pr-pick input{width:100%;max-width:100%}
.pr-tbl{width:100%;border-collapse:collapse;font-size:12px}.pr-tbl td{padding:3px 2px;border-bottom:1px solid var(--hair);vertical-align:top}.pr-tbl td:last-child{text-align:right;white-space:nowrap}
.pr-w{display:flex;flex-wrap:wrap;gap:4px;margin-top:4px}#pr_print{display:none}@media print{body>*:not(#pr_print){display:none!important}#pr_print{display:block!important}}
.pr-paper{max-width:560px;margin:0 auto;font-size:13px}.pr-paper h2{margin:0 0 4px}.pr-paper .sig{margin-top:40px;border-top:1px solid #000;width:200px;padding-top:4px}`;
if (!document.getElementById('prcss')) document.head.appendChild(css);
const locName = (id) => { const l = (B.ENV && B.ENV.locs || []).find((x) => x.id === id); return l ? nm(l) : String(id || ''); };
const nameOf = (l) => (S.lang === 'en' && l.name_en ? l.name_en : l.name || '');
function warnChips(ws) {
  return (ws || []).map((w) => { const [k, v] = String(w).split(':'); const t = X['w_' + k]; const bad = k === 'negative_net' || k === 'no_pay_structure';
    return `<span class="chip ${bad ? 'bad' : 'warn'}">${v ? esc(v) + ' ' : ''}${esc(t ? lab(t) : k)}</span>`; }).join('');
}
const stChip = (s) => `<span class="chip ${s === 'paid' ? 'ok' : s === 'approved' ? 'info' : s === 'void' ? 'bad' : 'warn'}">${esc(T(s === 'paid' ? 'pstatus' : s))}</span>`;
const payChip = (s) => `<span class="chip ${s === 'paid' ? 'ok' : s === 'partly' ? 'warn' : ''}">${esc(T(s === 'paid' ? 'pstatus' : s))}</span>`;
function lineCard(l, i, live) {
  return `<div class="card" data-line="${i}"><div class="pr-row"><div class="nm"><b>${esc(nameOf(l))}</b> <span class="muted">${esc(l.employee_no || '')}</span></div><b class="pr-num">${l.skip ? '–' : esc(n2(l.net))}</b>
      <button class="mini" data-act="pr_line" data-i="${i}" aria-label="⋮">⋮</button></div>
    ${l.skip ? '' : `<div class="muted pr-num">${esc(T('gross'))} ${esc(n2(l.gross))} · ${esc(T('ded'))} ${esc(n2(l.deductions))} · ${esc(T('paidDays'))} ${esc(l.paid_days)}/${esc(l.days_in_month)}${live ? ' · ' + payChip(l.payment_status) : ''}</div>`}
    <div class="pr-w">${warnChips(l.warnings)}</div></div>`;
}
function totalsHTML(lines) {
  const s = (k) => lines.filter((l) => !l.skip).reduce((a, l) => a + (Number(l[k]) || 0), 0);
  return `<div class="card pr-row"><span>${lines.filter((l) => !l.skip).length} ${esc(T('people'))}</span><span class="pr-num">${esc(T('gross'))} ${esc(n2(s('gross')))}</span><b class="pr-num">${esc(T('net'))} ${esc(n2(s('net')))}</b></div>`;
}
function steps(n) { return `<div class="pr-steps">${['s1', 's2', 's3', 's4', 's5'].map((k, i) => `<span class="${i < n ? 'on' : ''}">${esc(T(k))}</span>`).join('')}</div>`; }

async function loadRun() {
  const r = await sb.from('payroll_runs').select('*').eq('month', m01()).order('id', { ascending: false });
  const runs = (r.data || []).filter((x) => x.status !== 'void');
  P.run = runs.find((x) => x.location_id === P.loc) || null;
  P.lines = [];
  if (P.run) { const l = await sb.from('payroll_lines').select('*').eq('run_id', P.run.id).order('employee_no'); P.lines = (l.data || []).filter((x) => x.active !== false); }
  return runs;
}
async function runHTML() {
  if (!(await seeOk(P.loc))) return `<p class="muted">${esc(T('noperm'))}</p>`;
  const mg = await can('payroll_manage', P.loc);
  await loadRun();
  const r = P.run;
  if (!r) {
    const pv = P.pv && P.pv.month === m01() && P.pv.location_id === P.loc ? P.pv : null;
    return `${steps(pv ? 1 : 0)}<p class="muted">${esc(T('noRun'))}</p><button class="full" data-act="pr_preview">${esc(T('preview'))}</button>
      ${pv ? `<p class="chip info">${esc(T('trial'))}</p>${totalsHTML(pv.lines)}<div id="pr_lines">${pv.lines.map((l, i) => lineCard(l, i, false)).join('')}</div>
        ${mg ? `<button class="full primary" data-act="pr_create">${esc(T('create'))}</button>` : ''}` : ''}`;
  }
  const n = r.status === 'draft' ? 3 : r.status === 'approved' ? 4 : 5;
  const own = !!S.ctx.is_owner;
  const acts = r.status === 'draft' ? `${mg ? `<button class="full" data-act="pr_refresh">${esc(T('refresh'))}</button>` : ''}${own ? `<button class="full primary" data-act="pr_approve">${esc(T('approve'))}</button>` : ''}${mg ? `<button class="full" data-act="pr_void">${esc(T('voidRun'))}</button>` : ''}`
    : r.status === 'approved' ? `${mg ? `<button class="full primary" data-act="pr_payall">${esc(T('payAll'))}</button>` : ''}${own ? `<button class="full" data-act="pr_void">${esc(T('voidRun'))}</button>` : ''}` : '';
  return `${steps(n)}<div class="pr-row"><b>${esc(locName(P.loc))} · ${esc(P.month)}</b>${stChip(r.status)}</div>${totalsHTML(P.lines)}
    <div class="row">${acts}<button class="full" data-act="pr_csv">${esc(T('csv'))}</button></div><div id="pr_lines">${P.lines.map((l, i) => lineCard(l, i, r.status !== 'draft')).join('')}</div>`;
}
async function summaryHTML() {
  const runs = await loadRun();
  const ids = runs.map((x) => x.id); let lines = [];
  if (ids.length) { const l = await sb.from('payroll_lines').select('*').in('run_id', ids); lines = (l.data || []).filter((x) => x.active !== false); }
  P.sumLines = lines;
  const rows = runs.map((r) => { const ls = lines.filter((l) => l.run_id === r.id); const s = (k) => ls.reduce((a, l) => a + (Number(l[k]) || 0), 0);
    return `<div class="card"><div class="pr-row"><b class="nm">${esc(r.location_id == null ? T('summary') : locName(r.location_id))}</b>${stChip(r.status)}</div>
      <div class="muted pr-num">${ls.length} ${esc(T('people'))} · ${esc(T('gross'))} ${esc(n2(s('gross')))} · ${esc(T('net'))} ${esc(n2(s('net')))} · ${esc(T('paid'))} ${esc(n2(s('paid_amount')))}</div></div>`; }).join('');
  return `${rows || `<p class="muted">${esc(T('noRun'))}</p>`}${lines.length ? totalsHTML(lines) + `<button class="full" data-act="pr_csv">${esc(T('csv'))}</button>` : ''}`;
}
async function loadEmps() {
  const r = await sb.from('employees').select('id,employee_no,full_name_bn,full_name_en,primary_location_id,status,joining_date').in('status', ['active', 'on_leave', 'resigned', 'terminated', 'retired']).order('employee_no');
  P.emps = (r.data || []).filter((e) => e.primary_location_id === P.loc);
}
const empName = (e) => (S.lang === 'en' && e.full_name_en ? e.full_name_en : e.full_name_bn || '');
async function advHTML() {
  if (!(await seeOk(P.loc))) return `<p class="muted">${esc(T('noperm'))}</p>`;
  await loadEmps();
  const ids = P.emps.map((e) => e.id);
  const [a, rc] = await Promise.all([sb.from('employee_advances').select('*').order('adv_date', { ascending: false }), sb.from('employee_advance_recoveries').select('advance_id,amount,status')]);
  const rec = (id) => (rc.data || []).filter((x) => x.advance_id === id && x.status === 'active').reduce((s, x) => s + Number(x.amount), 0);
  P.advs = (a.data || []).filter((x) => ids.includes(x.employee_id));
  const en = (id) => empName(P.emps.find((e) => e.id === id) || {});
  const mg = await can('payroll_manage', P.loc);
  const rows = P.advs.length ? P.advs.map((x) => `<div class="card ${x.status === 'void' ? 'muted' : ''}"><div class="pr-row"><b class="nm">${esc(en(x.employee_id))}</b><b class="pr-num">${esc(T('outst'))} ${esc(n2(Number(x.amount) - rec(x.id)))}</b></div>
      <div class="muted pr-num">${esc(x.adv_date)} · ${esc(n2(x.amount))}${x.instalment ? ' · ' + esc(n2(x.instalment)) + '/' + esc(T('month')) : ''} · ${esc(x.mode === 'none' ? T('modeNone') : T(x.mode))}${x.note ? ' · ' + esc(x.note) : ''}${x.status === 'void' ? ' · ' + esc(T('void')) : ''}</div>
      ${mg && x.status === 'active' && rec(x.id) === 0 ? `<button class="mini" data-act="adv_void" data-v="${x.id}">${esc(T('void'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return `${mg ? `<button class="full primary" data-act="adv_new">${esc(T('addAdv'))}</button>` : ''}<div id="adv_list">${rows}</div>`;
}
async function moreHTML() {
  if (!(await seeOk(P.loc))) return `<p class="muted">${esc(T('noperm'))}</p>`;
  await loadEmps();
  const mg = await can('payroll_manage', P.loc);
  const ev = await sb.from('payroll_bonus_events').select('*').eq('month', m01());
  const evs = (ev.data || []).filter((x) => x.active && (x.location_id == null || x.location_id === P.loc));
  return `<div class="card stack"><b>${esc(T('festival'))} · ${esc(P.month)}</b>${evs.map((x) => `<div class="pr-row"><span>${esc(x.name)}</span>${mg ? `<button class="mini" data-act="fb_off" data-v="${esc(x.name)}" data-loc="${x.location_id == null ? '' : x.location_id}">${esc(T('remove'))}</button>` : ''}</div>`).join('')}
      ${mg ? `<div><label for="fb_n">${esc(T('festName'))}</label><input id="fb_n" autocomplete="off" value="Eid"></div><button class="full" data-act="fb_save">${esc(T('save'))}</button>` : ''}</div>
    <div class="card stack"><b>${esc(T('settle'))}</b><div><label for="st_e">${esc(T('who'))}</label><select id="st_e">${P.emps.map((e) => `<option value="${esc(e.id)}">${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select></div>
      <div><label for="st_d">${esc(T('lastDay'))}</label><input id="st_d" type="date" value="${today()}"></div><button class="full" data-act="st_show">${esc(T('show'))}</button><div id="st_out"></div></div>`;
}
async function draw() {
  const el = $('#pr_body'); if (!el) return;
  el.innerHTML = '<p class="muted">…</p>';
  let h = '';
  try { h = P.loc == null ? await summaryHTML() : P.tab === 'adv' ? await advHTML() : P.tab === 'more' ? await moreHTML() : await runHTML(); } catch (e) { h = `<p class="muted">${esc(eText(e))}</p>`; }
  if ($('#pr_body')) $('#pr_body').innerHTML = h;
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (P.loc === undefined || (P.loc === null && !S.ctx.is_owner) || (P.loc !== null && !locs.find((l) => l.id === P.loc))) P.loc = (locs[0] || {}).id;
  const opts = (S.ctx.is_owner ? `<option value="" ${P.loc == null ? 'selected' : ''}>${esc(T('summary'))}</option>` : '') + locs.map((l) => `<option value="${l.id}" ${l.id === P.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('');
  const tb = [['run', 'tRun'], ['adv', 'tAdv'], ['more', 'tMore']];
  shell(T('title'), `<div class="pr-pick"><div><select id="pr_loc" aria-label="${esc(T('place'))}">${opts}</select></div><div><input id="pr_month" type="month" value="${esc(P.month)}" max="${today().slice(0, 7)}" aria-label="${esc(T('month'))}"></div></div>
    <div class="ptabs" role="tablist">${tb.map(([k, l]) => `<button role="tab" data-act="pr_tab" data-v="${k}" aria-selected="${P.tab === k}">${esc(T(l))}</button>`).join('')}</div><div id="pr_body"></div>`, true);
  try { await draw(); } catch (e) { fail(e); }
}

// ---------------- line sheets: trail, payslip, adjust, pay ----------------
const curLines = () => (P.run ? P.lines : (P.pv && P.pv.lines) || []);
function trailHTML(l) {
  const tr = ((l.calc_detail || {}).trail || []).map((t) => `<tr><td>${esc(X['k_' + t.k] ? lab(X['k_' + t.k]) : t.k)}<div class="muted">${esc(t.f || '')}</div></td><td>${esc(Number(t.v) < 0 ? '− ' + n2(-t.v) : n2(t.v))}</td></tr>`).join('');
  const bon = (l.bonus || []).map((b) => `<tr><td>${esc(T('bonus'))}: ${esc(b.name === 'attendance_bonus' ? 'Attendance' : b.name)}${b.reason ? '<div class="muted">' + esc(b.reason) + '</div>' : ''}</td><td>${esc(n2(b.amount))}</td></tr>`).join('');
  const od = (l.other_deductions || []).map((b) => `<tr><td>${esc(T('other'))}: ${esc(b.name)}<div class="muted">${esc(b.reason || '')}</div></td><td>− ${esc(n2(b.amount))}</td></tr>`).join('');
  const ad = (l.adjustments || []).map((b) => `<tr><td>${esc(T('adj'))}: ${esc(b.name)}<div class="muted">${esc(b.reason || '')}</div></td><td>${Number(b.amount) < 0 ? '− ' + esc(n2(-b.amount)) : esc(n2(b.amount))}</td></tr>`).join('');
  return `<table class="pr-tbl" id="pr_trail">${tr}${bon}${od}${ad}<tr><td><b>${esc(T('gross'))}</b></td><td><b>${esc(n2(l.gross))}</b></td></tr><tr><td>${esc(T('ded'))}</td><td>− ${esc(n2(l.deductions))}</td></tr>
    ${Number(l.round_adj) ? `<tr><td>${esc(T('round'))}</td><td>${esc(Number(l.round_adj).toFixed(2))}</td></tr>` : ''}<tr><td><b>${esc(T('net'))}</b></td><td><b>${esc(n2(l.net))}</b></td></tr></table>`;
}
function slipHTML(l) {
  const row = (k, v, neg) => (Number(v) ? `<tr><td>${esc(k)}</td><td>${neg ? '− ' : ''}${esc(n2(v))}</td></tr>` : '');
  const earn = row(T('basic'), l.basic_amount) + (l.allowances || []).map((a) => row(a.name, a.amount)).join('') + row(T('ot') + ' (' + ((l.ot_minutes || 0) / 60).toFixed(1) + ' h)', l.ot_amount)
    + (l.bonus || []).map((b) => row(T('bonus') + ': ' + (b.name === 'attendance_bonus' ? 'Attendance' : b.name), b.amount)).join('') + (l.adjustments || []).filter((a) => Number(a.amount) > 0).map((a) => row(a.name, a.amount)).join('');
  const ded = row(T('notEmp'), l.not_employed_deduction, 1) + row(T('absent') + ' (' + l.absent_days + ')', l.absent_deduction, 1) + row(T('unpaidD') + ' (' + l.unpaid_leave_days + ')', l.unpaid_deduction, 1)
    + row(T('late') + ' (' + l.late_count + ')', l.late_deduction, 1) + (l.structure_deductions || []).map((a) => row(a.name, a.amount, 1)).join('') + row(T('advance'), l.advance_recovery, 1)
    + (l.other_deductions || []).map((a) => row(a.name, a.amount, 1)).join('') + (l.adjustments || []).filter((a) => Number(a.amount) < 0).map((a) => row(a.name, -a.amount, 1)).join('');
  return `<div class="pr-paper"><h2>${esc(T('payslip'))} · ${esc(P.month)}</h2><p>${esc(locName(l.location_id))}<br><b>${esc(nameOf(l))}</b> ${esc(l.employee_no || '')}</p>
    <p class="pr-num">${esc(T('days'))} ${esc(l.days_in_month)} · ${esc(T('paidDays'))} ${esc(l.paid_days)} · ${esc(T('lateCount'))} ${esc(l.late_count)} · ${esc(T('otH'))} ${esc(((l.ot_minutes || 0) / 60).toFixed(1))}</p>
    <table class="pr-tbl"><tr><td colspan="2"><b>${esc(T('earn'))}</b></td></tr>${earn}<tr><td><b>${esc(T('gross'))}</b></td><td><b>${esc(n2(l.gross))}</b></td></tr>
    <tr><td colspan="2"><b>${esc(T('ded'))}</b></td></tr>${ded}<tr><td><b>${esc(T('ded'))}</b></td><td><b>− ${esc(n2(l.deductions))}</b></td></tr>
    <tr><td><b>${esc(T('net'))}</b></td><td><b>${esc(n2(l.net))}</b></td></tr></table><div class="sig">${esc(T('sign'))}</div></div>`;
}
// bos98: the pay slip through the chosen pay_slip template; false (nothing chosen / no B.tpl / any error) = today's slip. Earnings and deductions the employee sees, no cost.
async function tplSlip(l) {
  try {
    await B.tpl.ensure(sb); const r = (k, v) => (Number(v) ? [{ label: k, amount: Number(v) }] : []);
    const earn = [...r(T('basic'), l.basic_amount), ...(l.allowances || []).flatMap((x) => r(x.name, x.amount)), ...r(T('ot'), l.ot_amount), ...(l.bonus || []).flatMap((x) => r(T('bonus') + ': ' + x.name, x.amount)), ...(l.adjustments || []).filter((x) => Number(x.amount) > 0).flatMap((x) => r(x.name, x.amount))];
    const ded = [...r(T('notEmp'), l.not_employed_deduction), ...r(T('absent'), l.absent_deduction), ...r(T('unpaidD'), l.unpaid_deduction), ...r(T('late'), l.late_deduction), ...(l.structure_deductions || []).flatMap((x) => r(x.name, x.amount)), ...r(T('advance'), l.advance_recovery),
      ...(l.other_deductions || []).flatMap((x) => r(x.name, x.amount)), ...(l.adjustments || []).filter((x) => Number(x.amount) < 0).flatMap((x) => r(x.name, -x.amount))];
    const sum = (a) => a.reduce((t, x) => t + x.amount, 0);
    const data = { employee: nameOf(l), emp_no: l.employee_no || '', month: P.month, days: l.days_in_month, sections: [{ title: T('earn'), rows: earn, total: sum(earn) }, { title: T('ded'), rows: ded, total: sum(ded) }], net: Number(l.net) };
    const o = { lang: S.lang, loc: l.location_id, shop: {} };
    return !!(B.tpl.printHTML('pay_slip', data, undefined, o) && B.tpl.print('pay_slip', data, undefined, o));
  } catch (e) { return false; }
}
function printHTML(html) {
  const old = $('#pr_print'); if (old) old.remove();
  const d = document.createElement('div'); d.id = 'pr_print'; d.innerHTML = html; document.body.appendChild(d);
  try { window.print(); } finally { setTimeout(() => { const x = $('#pr_print'); if (x) x.remove(); }, 800); }
}
function lineSheet(i) {
  const l = curLines()[i]; if (!l) return;
  const draft = P.run && P.run.status === 'draft'; const payable = P.run && ['approved', 'paid'].includes(P.run.status) && Number(l.net) > Number(l.paid_amount);
  const manual = (k) => (l[k] || []).map((b, j) => (b.auto ? '' : `<div class="pr-row"><span>${esc(b.name)} ${esc(n2(b.amount))}</span><button class="mini" data-act="ln_rm" data-i="${i}" data-k="${k}" data-j="${j}">${esc(T('remove'))}</button></div>`)).join('');
  openSheet(`<h3>${esc(nameOf(l))} <span class="muted">${esc(l.employee_no || '')}</span></h3><div class="pr-w">${warnChips(l.warnings)}</div><h4>${esc(T('trail'))}</h4>${trailHTML(l)}
    <div class="stack">${l.skip ? '' : `<button class="full" data-act="ln_slip" data-i="${i}">${esc(T('payslip'))} · ${esc(T('print'))}</button>`}
    ${draft ? `<div class="row"><button class="full" data-act="ln_adj" data-i="${i}" data-k="bonus">${esc(T('addBonus'))}</button><button class="full" data-act="ln_adj" data-i="${i}" data-k="deduction">${esc(T('addDed'))}</button><button class="full" data-act="ln_adj" data-i="${i}" data-k="adjust">${esc(T('adjust'))}</button></div>
      ${manual('bonus')}${manual('other_deductions')}${manual('adjustments')}` : ''}
    ${payable ? `<button class="full primary" data-act="ln_pay" data-i="${i}">${esc(T('pay'))} · ${esc(T('due'))} ${esc(n2(Number(l.net) - Number(l.paid_amount)))}</button>` : ''}</div>`);
}
function paySheet(i) {
  const one = i != null ? P.lines[i] : null;
  openSheet(`<h3>${esc(T('pay'))}${one ? ': ' + esc(nameOf(one)) : ''}</h3><div class="stack"><div><label for="py_m">${esc(T('mode'))}</label><select id="py_m"><option value="cash">${esc(T('cash'))}</option><option value="bank">${esc(T('bank'))}</option><option value="mobile">${esc(T('mobile'))}</option></select></div>
    <div><label for="py_d">${esc(T('date'))}</label><input id="py_d" type="date" value="${today()}" max="${today()}"></div>${one ? `<div><label for="py_a">${esc(T('amount'))}</label><input id="py_a" inputmode="decimal" value="${esc(Number(one.net) - Number(one.paid_amount))}"></div>` : ''}
    <div><label for="py_r">${esc(T('ref'))}</label><input id="py_r" autocomplete="off"></div><div><label for="py_n">${esc(T('note'))}</label><input id="py_n" autocomplete="off"></div>
    <button class="primary full" data-act="py_go" data-i="${i == null ? '' : i}">${esc(T('pay'))}</button></div>`);
  P.payClient = rid();
}
function csvOut(lines) {
  const cols = ['employee_no', 'name', 'location_id', 'days_in_month', 'paid_days', 'absent_days', 'late_count', 'ot_minutes', 'basic_amount', 'allowance_total', 'ot_amount', 'gross', 'absent_deduction', 'late_deduction', 'unpaid_deduction',
    'not_employed_deduction', 'structure_deduction_total', 'advance_recovery', 'deductions', 'net', 'payment_status', 'paid_amount'];
  const q = (v) => { const s = v == null ? '' : String(v); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  const text = '﻿' + cols.join(',') + '\n' + lines.map((l) => cols.map((c) => q(l[c])).join(',')).join('\n') + '\n';
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'text/csv' })); a.download = `payroll_${P.month}_${P.loc == null ? 'all' : P.loc}.csv`;
  document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  P.lastCsv = text;
}

const val = (id) => (($('#' + id) || {}).value || '').trim();
const ask = () => { const n = window.prompt(T('why')); return n && n.trim().length >= 3 ? n.trim() : null; };
async function rpc(fn, args, ok) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } if (ok) toast(T(ok)); return r.data; }
Object.assign(H, {
  pr_tab: (a) => { P.tab = a.dataset.v; document.querySelectorAll('[data-act=pr_tab]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.v === P.tab))); draw(); },
  pr_preview: async () => { const d = await rpc('payroll_preview', { p_month: m01(), p_loc: P.loc }); if (d) { P.pv = d; draw(); } },
  pr_create: async () => { const d = await rpc('payroll_create', { p_month: m01(), p_loc: P.loc, p_client: P.client }, 'saved'); if (d) { P.client = rid(); P.pv = null; draw(); } },
  pr_refresh: async () => { const d = await rpc('payroll_refresh', { p_run: P.run.id }, 'saved'); if (d) draw(); },
  pr_approve: async () => { if (!window.confirm(T('approveQ'))) return; const d = await rpc('payroll_approve', { p_run: P.run.id }, 'saved'); if (d) draw(); },
  pr_void: async () => { const n = ask(); if (!n) return; const d = await rpc('payroll_void', { p_run: P.run.id, p_reason: n }, 'saved'); if (d) draw(); },
  pr_payall: () => paySheet(null),
  pr_csv: () => csvOut(P.loc == null ? (P.sumLines || []) : P.lines),
  pr_line: (a) => lineSheet(Number(a.dataset.i)),
  ln_slip: async (a) => { const l = curLines()[Number(a.dataset.i)]; if (B.tpl && B.tpl.ensure && (await tplSlip(l))) return; printHTML(slipHTML(l)); },   // bos98
  ln_pay: (a) => paySheet(Number(a.dataset.i)),
  ln_adj: (a) => { const k = a.dataset.k; openSheet(`<h3>${esc(T(k === 'bonus' ? 'addBonus' : k === 'deduction' ? 'addDed' : 'adjust'))}</h3><div class="stack"><div><label for="aj_n">${esc(T('name'))}</label><input id="aj_n" autocomplete="off"></div>
      <div><label for="aj_a">${esc(T('amount'))}${k === 'adjust' ? ' (+ / −)' : ''}</label><input id="aj_a" inputmode="decimal" autocomplete="off"></div><div><label for="aj_r">${esc(T('reason'))}</label><input id="aj_r" autocomplete="off"></div>
      <button class="primary full" data-act="aj_save" data-i="${a.dataset.i}" data-k="${k}">${esc(T('save'))}</button></div>`); },
  aj_save: async (a) => { const l = P.lines[Number(a.dataset.i)]; const amt = nnum(val('aj_a')); if (!Number.isFinite(amt) || amt === 0) return toast(lab(ERR.bad_amount)); if (val('aj_r').length < 3) return toast(lab(ERR.reason_required));
    const d = await rpc('payroll_line_adjust', { p_line: l.id, p_kind: a.dataset.k, p_name: val('aj_n'), p_amount: amt, p_reason: val('aj_r'), p_remove: null }, 'saved'); if (d) { closeSheet(); draw(); } },
  ln_rm: async (a) => { const l = P.lines[Number(a.dataset.i)]; const kind = { bonus: 'bonus', other_deductions: 'deduction', adjustments: 'adjust' }[a.dataset.k];
    const d = await rpc('payroll_line_adjust', { p_line: l.id, p_kind: kind, p_name: null, p_amount: null, p_reason: null, p_remove: Number(a.dataset.j) }, 'saved'); if (d) { closeSheet(); draw(); } },
  py_go: async (a) => { const i = a.dataset.i === '' ? null : Number(a.dataset.i); const one = i == null ? null : P.lines[i];
    const amt = one ? nnum(val('py_a')) : null; if (one && !(amt > 0)) return toast(lab(ERR.bad_amount));
    const due = one ? Number(one.net) - Number(one.paid_amount) : null;
    const d = await rpc('payroll_pay', { p_run: P.run.id, p_lines: one ? [one.id] : null, p_mode: val('py_m'), p_date: val('py_d') || today(), p_ref: val('py_r') || null, p_note: val('py_n') || null, p_client: P.payClient, p_amount: one && amt !== due ? amt : null }, 'saved');
    if (d) { closeSheet(); draw(); } },
  adv_new: async () => { if (!P.emps.length) await loadEmps(); openSheet(`<h3>${esc(T('addAdv'))}</h3><div class="stack"><div><label for="av_e">${esc(T('who'))}</label><select id="av_e">${P.emps.filter((e) => ['active', 'on_leave'].includes(e.status)).map((e) => `<option value="${esc(e.id)}">${esc(empName(e))} ${esc(e.employee_no || '')}</option>`).join('')}</select></div>
      <div><label for="av_d">${esc(T('date'))}</label><input id="av_d" type="date" value="${today()}" max="${today()}"></div><div><label for="av_a">${esc(T('amount'))}</label><input id="av_a" inputmode="decimal" autocomplete="off"></div>
      <div><label for="av_i">${esc(T('inst'))}</label><input id="av_i" inputmode="decimal" autocomplete="off"></div><div><label for="av_f">${esc(T('recFrom'))}</label><input id="av_f" type="month" value="${today().slice(0, 7)}"></div>
      <div><label for="av_m">${esc(T('mode'))}</label><select id="av_m"><option value="cash">${esc(T('cash'))}</option><option value="bank">${esc(T('bank'))}</option><option value="mobile">${esc(T('mobile'))}</option><option value="none">${esc(T('modeNone'))}</option></select></div>
      <div><label for="av_n">${esc(T('note'))}</label><input id="av_n" autocomplete="off"></div><button class="primary full" data-act="av_save">${esc(T('save'))}</button></div>`); P.advClient = rid(); },
  av_save: async () => { const amt = nnum(val('av_a')); if (!(amt > 0)) return toast(lab(ERR.bad_amount)); const ins = val('av_i') ? nnum(val('av_i')) : null;
    const d = await rpc('staff_advance_add', { p_emp: val('av_e'), p_date: val('av_d'), p_amount: amt, p_instalment: ins, p_mode: val('av_m'), p_recover_from: (val('av_f') || today().slice(0, 7)) + '-01', p_note: val('av_n') || null, p_client: P.advClient }, 'saved');
    if (d) { closeSheet(); draw(); } },
  adv_void: async (a) => { const n = ask(); if (!n) return; const d = await rpc('staff_advance_void', { p_id: Number(a.dataset.v), p_reason: n }, 'saved'); if (d) draw(); },
  fb_save: async () => { if (!val('fb_n')) return toast(lab(ERR.name_required)); const d = await rpc('payroll_bonus_event_save', { p_month: m01(), p_name: val('fb_n'), p_loc: S.ctx.is_owner ? null : P.loc, p_active: true }, 'saved'); if (d) draw(); },
  fb_off: async (a) => { const d = await rpc('payroll_bonus_event_save', { p_month: m01(), p_name: a.dataset.v, p_loc: a.dataset.loc === '' ? null : Number(a.dataset.loc), p_active: false }, 'saved'); if (d) draw(); },
  st_show: async () => { const d = await rpc('payroll_settlement_preview', { p_emp: val('st_e'), p_last_day: val('st_d') || today() }); const o = $('#st_out'); if (!d || !o) return;
    o.innerHTML = d.line ? `<p class="chip info">${esc(T('trial'))}</p><div class="pr-w">${warnChips(d.line.warnings)}</div>${trailHTML(d.line)}<p class="pr-num">${esc(T('advLeft'))}: ${esc(n2(d.advances_left))}</p>` : `<p class="muted">${esc(T('none'))}</p>`; },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'pr_loc') { P.loc = e.target.value === '' ? null : Number(e.target.value); P.pv = null; draw(); }
  if (e.target.id === 'pr_month') { P.month = e.target.value || prevMonth(); P.pv = null; draw(); }
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { payroll: view });
B.payroll = { eText, slipHTML };
})();
