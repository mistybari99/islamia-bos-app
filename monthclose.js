/* Islamia BOS · Monthly Close (#/monthclose). Salary is a MONTHLY cost, not a daily one: this screen shows the month's salary (accrued from the approved payroll runs),
   the advances recovered, the month profit from the books, the partner profit split, and closes the month once nothing is pending.
   Server side: supabase/phase82.sql - c_month_close_preview / c_month_close / c_month_reopen / c_month_closes, c_post_pending, c_partner_month_split, set_rule.
   Reads and writes only through those functions. Nothing is deleted: a close and a reopen are two lines of an append-only trail.
   Who: the owner and holders of the accounts_manage grant (the server decides; the partner split and the settings are owner only). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const t3 = (bn, en, mix) => lab(L(bn, en, mix || bn));
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const mny = (n) => (n === null || n === undefined || n === '' ? '-' : '৳ ' + num(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const todayD = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const mFirst = (d) => d.slice(0, 7) + '-01';
const addM = (d, k) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCMonth(x.getUTCMonth() + k); return x.toISOString().slice(0, 10); };

const X = {
  title: L('মাস শেষের হিসাব (Monthly Close)', 'Monthly Close', 'Monthly Close (মাস শেষ)'),
  intro: L('বেতন দৈনিক খরচ নয়, মাসের খরচ। এখানে মাসের বেতন, অগ্রিম কাটা, মাসের লাভ ও অংশীদারের ভাগ একসাথে দেখে মাস "দেখা হয়েছে" চিহ্ন দেওয়া যায়। এটি হিসাবের তালা নয়: পরে হিসাব বদলাতে পারে।',
    'Salary is a monthly cost, not a daily one. See the month salary, advances recovered, the month profit and the partner split together, then mark the month as reviewed. This is a note in the log, not a lock: the books of that month can still change.',
    'Salary দৈনিক খরচ নয়, মাসের খরচ। মাসের salary, advance কাটা, profit ও partner share একসাথে দেখে মাস "reviewed" mark করুন। এটি log-এর note, lock নয়: হিসাব পরে বদলাতে পারে।'),
  month: L('মাস', 'Month', 'Month'), state_open: L('খোলা', 'Open', 'Open'), state_closed: L('দেখা হয়েছে (তালা নয়)', 'Reviewed (not locked)', 'Reviewed (lock নয়)'),
  blockers: L('আটকে আছে', 'Blocking the review', 'Review আটকে আছে'), warns: L('সতর্কতা', 'Warnings', 'Warnings'), ready: L('দেখা হয়েছে বলে চিহ্ন দেওয়া যাবে', 'Ready to mark as reviewed', 'Reviewed mark করা যাবে'),
  pay: L('বেতন (মাসের খরচ)', 'Salary (the month cost)', 'Salary (month cost)'), exp: L('মাসের বেতন খরচ', 'Salary cost of the month', 'Month salary cost'),
  netpay: L('হাতে দেওয়ার বেতন', 'Net pay', 'Net pay'), paid: L('দেওয়া হয়েছে', 'Paid', 'Paid'), unpaid: L('বাকি', 'Still to pay', 'বাকি'),
  rec: L('অগ্রিম কাটা', 'Advance recovered', 'Advance কাটা'), accr: L('জমা (accrual)', 'Accrued', 'Accrued'), posted: L('খতিয়ানে উঠেছে', 'In the books', 'Books-এ উঠেছে'),
  notposted: L('এখনও ওঠেনি', 'Not posted yet', 'এখনও ওঠেনি'), run: L('শিট', 'Run', 'Run'), basis_accrual: L('মাসের জমা', 'Monthly accrual', 'Monthly accrual'),
  basis_cash: L('টাকা দেওয়ার দিনে', 'On the pay day', 'Pay day-তে'), basis_form: L('কাগজের ফর্মই রেকর্ড', 'The paper form is the record', 'Paper form-ই record'),
  adv: L('স্টাফের অগ্রিম বাকি (সবাই)', 'Staff advances still owed (all)', 'Staff advance বাকি (সবাই)'),
  profit: L('মাসের লাভ (খতিয়ান থেকে)', 'Month profit (from the books)', 'Month profit (books থেকে)'), inc: L('আয়', 'Income', 'Income'), expn: L('খরচ', 'Expenses', 'Expenses'),
  net: L('নিট লাভ', 'Net profit', 'Net profit'), before: L('বেতনের আগের লাভ', 'Profit before salary', 'Salary-র আগের profit'), salj: L('খতিয়ানে বেতন', 'Salary in the books', 'Books-এ salary'),
  split: L('অংশীদারের ভাগ (প্রিভিউ)', 'Partner split (preview)', 'Partner share (preview)'), splitnote: L('চুক্তির শতাংশ ধরে। আসল হিসাব সেটেলমেন্টে হয়।', 'By the percent in each deed. The real calculation is the settlement.', 'Deed-এর percent ধরে। আসল হিসাব settlement-এ।'),
  post: L('বাকি এন্ট্রি খতিয়ানে তুলুন', 'Post the pending entries', 'বাকি entry post করুন'), close: L('মাস দেখা হয়েছে চিহ্ন দিন', 'Mark the month reviewed', 'মাস reviewed mark করুন'),
  reopen: L('চিহ্ন তুলে নিন', 'Undo the mark', 'Mark তুলে নিন'), why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), note: L('নোট (ইচ্ছামতো)', 'Note (optional)', 'Note (optional)'),
  hist: L('আগের মাস', 'Earlier months', 'আগের মাস'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), done: L('হয়েছে', 'Done', 'হয়েছে'),
  set: L('সেটিং (শুধু মালিক)', 'Settings (owner only)', 'Settings (owner only)'), s_acc: L('বেতন মাসের জমা (accrual) চালু', 'Book salary as a monthly accrual', 'Salary monthly accrual চালু'),
  s_from: L('জমা শুরুর মাস (YYYY-MM-01)', 'First accrual month (YYYY-MM-01)', 'Accrual শুরুর মাস'), s_src: L('বেতন কোথা থেকে দেওয়া হয়', 'Salary is paid from', 'Salary কোথা থেকে দেওয়া হয়'),
  s_day: L('দৈনিক লাভে বেতন ধরা হবে না', 'Keep salary out of the daily profit', 'Daily profit-এ salary ধরা হবে না'),
  s_pp: L('অংশীদারের ভাগ খতিয়ানে উঠবে', 'Post partner profit shares to the books', 'Partner share books-এ উঠবে'),
  s_pa: L('অংশীদারের মুনাফা কখন ওঠে', 'Book the partner profit at', 'Partner profit কখন book হবে'),
  o_by_payment: L('যে মাধ্যমে দেওয়া হলো', 'The mode used when paying', 'Payment mode অনুযায়ী'), o_cash: L('নগদ', 'Cash', 'Cash'), o_mobile: L('বিকাশ / মোবাইল ওয়ালেট', 'bKash / mobile wallet', 'bKash / wallet'),
  o_bank: L('ব্যাংক', 'Bank', 'Bank'), o_approval: L('অনুমোদনের দিন (দেনা)', 'When approved (a debt)', 'Approval-এর দিন'), o_payment: L('টাকা দেওয়ার দিন', 'When paid', 'Payment-এর দিন'),
  hookwarn: L('খতিয়ানের সাথে সংযোগ বাকি (ইন্টিগ্রেটর)', 'The link to the books is not installed yet (integrator)', 'Books-এর link বাকি'),
  saved: L('সংরক্ষিত', 'Saved', 'Saved'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
};
const T = (k) => lab(X[k]);
const CODE = {
  accounting_start_missing: L('হিসাবের শুরুর তারিখ দেওয়া নেই', 'The accounts start date is not set'),
  month_not_finished: L('মাস এখনও শেষ হয়নি', 'The month is not over yet'),
  payroll_run_not_approved: L('একটি বেতন শিট এখনও অনুমোদিত নয়', 'A payroll run is still a draft'),
  payroll_not_posted: L('বেতনের এন্ট্রি খতিয়ানে ওঠা বাকি - "বাকি এন্ট্রি তুলুন" চাপুন', 'Payroll entries are not posted yet - press "Post the pending entries"'),
  advance_recovery_exceeds_balance: L('অগ্রিম কাটা বাকি অগ্রিমের চেয়ে বেশি - শিটটি ঠিক করুন', 'An advance recovery is above the advance still owed - fix the run'),
  unbalanced_entries: L('খতিয়ানে অমিল এন্ট্রি আছে', 'There are unbalanced journal entries'),
  already_closed: L('মাস ইতিমধ্যে দেখা হয়েছে বলে চিহ্নিত', 'The month is already marked as reviewed'),
  no_payroll_run: L('এই মাসে কোনো বেতন শিট নেই', 'There is no payroll run for this month'),
  accrual_hook_missing: L('accrual চালু কিন্তু খতিয়ানের সাথে সংযোগ বসেনি, তাই আগের নিয়মেই চলছে', 'Accrual is on but the link to the books is not installed, so the old way is still used'),
  accrual_from_missing: L('accrual চালু কিন্তু শুরুর মাস ফাঁকা', 'Accrual is on but the first month is blank'),
  salary_journal_differs_from_runs: L('খতিয়ানের বেতন শিটের মোটের সাথে মেলে না (অন্য মাসে উল্টানো এন্ট্রি বা হাতে লেখা এন্ট্রি)', 'The salary in the books differs from the run total (a reversal in another month, or a manual entry)'),
  'not allowed': L('এই কাজের অনুমতি নেই', 'You are not allowed to do this'), reason_required: L('কারণ লিখতে হবে', 'A reason is required'), not_closed: L('মাস চিহ্নিত নয়', 'The month is not marked as reviewed'),
  bad_value: L('মান ঠিক নয়', 'That value is not allowed'), accounting_off: L('হিসাব চালু নেই', 'Accounting is off'),
};
const eText = (e) => { const m = String((e && e.message) || e || ''); const ks = Object.keys(CODE).filter((k) => m.includes(k)); return ks.length ? ks.map((k) => lab(CODE[k])).join(' · ') : m; };
const D = { month: null, pv: null, hist: [], split: null, rules: {}, owner: false };
const RULES = ['payroll_accrual_on', 'payroll_accrual_from', 'salary_pay_source', 'salary_in_daily_off', 'partner_settlement_post_on', 'partner_accrue_at'];

async function load() {
  D.owner = !!(S.ctx && S.ctx.is_owner);
  const a = await sb.rpc('c_month_close_preview', { p_month: D.month }); if (a.error) throw a.error; D.pv = a.data;
  const h = await sb.rpc('c_month_closes', { p_months: 12 }); D.hist = h.error ? [] : (h.data || []);
  D.split = null; D.rules = {};
  if (D.owner) {
    const s = await sb.rpc('c_partner_month_split', { p_month: D.month }); D.split = s.error ? null : s.data;
    const r = await sb.from('rules').select('key,value,default_value').in('key', RULES);
    (r.data || []).forEach((x) => { D.rules[x.key] = x.value !== null && x.value !== undefined ? x.value : x.default_value; });
  }
}
const chips = (arr, cls) => (arr || []).map((c) => `<div class="chip ${cls}" data-code="${esc(c)}">${esc(CODE[c] ? lab(CODE[c]) : c)}</div>`).join('');
function runRows(runs) {
  if (!runs || !runs.length) return `<p class="muted">${esc(T('none'))}</p>`;
  return runs.map((r) => `<div class="card stack" data-run="${esc(r.run_id)}"><div class="row between"><b>${esc(T('run'))} #${esc(r.run_id)}</b><span class="chip">${esc(T('basis_' + (r.basis === 'accrual' ? 'accrual' : r.basis === 'form' ? 'form' : 'cash')))}</span></div>
    <div class="row between"><span>${esc(T('exp'))}</span><b>${esc(mny(r.salary_expense))}</b></div>
    <div class="row between muted"><span>${esc(T('netpay'))} / ${esc(T('rec'))}</span><span>${esc(mny(r.net))} / ${esc(mny(r.advance_recovery))}</span></div>
    <div class="row between muted"><span>${esc(T('paid'))} / ${esc(T('unpaid'))}</span><span>${esc(mny(r.paid))} / ${esc(mny(r.unpaid))}</span></div>
    ${r.basis === 'accrual' ? `<div class="muted">${esc(T('accr'))}: ${esc(r.accrual_posted ? T('posted') : T('notposted'))}</div>` : ''}</div>`).join('');
}
function splitHTML(sp) {
  if (!sp || !sp.agreements || !sp.agreements.length) return '';
  return `<div class="card stack" id="mc_split"><b>${esc(T('split'))}</b><div class="muted">${esc(T('splitnote'))}</div>${sp.agreements.map((g) => `<div class="stack" data-agr="${esc(g.agreement_id)}"><div class="row between"><span>${esc(g.title)}</span><span class="chip ${g.status === 'ok' ? '' : 'warn'}">${esc(g.status)}</span></div>
    ${(g.parties || []).map((p) => `<div class="row between"><span>${esc(p.name)} (${esc(p.role)}, ${esc(p.share_percent === null ? '?' : p.share_percent)}%)</span><b>${esc(p.amount === null ? '-' : mny(p.amount))}</b></div>`).join('')}
    <div class="row between muted"><span>${esc(T('net'))}</span><span>${esc(mny(g.base_profit))}</span></div></div>`).join('')}</div>`;
}
function rulesHTML() {
  const R = D.rules, on = (k) => R[k] === true;
  const tog = (k, label) => `<div class="row between"><span>${esc(label)}</span><button type="button" class="tog ${on(k) ? 'on' : ''}" role="switch" aria-checked="${on(k)}" data-act="mc_tog" data-k="${k}">${esc(on(k) ? T('on') : T('off'))}</button></div>`;
  const sel = (k, label, opts) => `<label class="stack"><span>${esc(label)}</span><select data-mc-rule="${k}">${opts.map((o) => `<option value="${o}" ${(R[k] || opts[0]) === o ? 'selected' : ''}>${esc(T('o_' + o))}</option>`).join('')}</select></label>`;
  return `<div class="card stack" id="mc_rules"><b>${esc(T('set'))}</b>${tog('payroll_accrual_on', T('s_acc'))}
    <label class="stack"><span>${esc(T('s_from'))}</span><input id="mc_from" type="text" inputmode="numeric" placeholder="YYYY-MM-01" value="${esc(R.payroll_accrual_from || '')}" data-mc-from="1"></label>
    ${sel('salary_pay_source', T('s_src'), ['by_payment', 'cash', 'mobile', 'bank'])}${tog('salary_in_daily_off', T('s_day'))}${tog('partner_settlement_post_on', T('s_pp'))}${sel('partner_accrue_at', T('s_pa'), ['approval', 'payment'])}</div>`;
}
function paint() {
  const el = $('#mc_body'); if (!el) return; const pv = D.pv, p = pv.payroll || {}, pr = pv.profit;
  const months = []; for (let i = 1; i <= 12; i++) months.push(addM(mFirst(todayD()), -i));
  if (!months.includes(D.month)) months.unshift(D.month);
  const closed = pv.state === 'closed';
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>
    <div class="card stack"><div class="row between wrap"><label>${esc(T('month'))} <select id="mc_month">${months.map((m) => `<option value="${m}" ${m === D.month ? 'selected' : ''}>${esc(m.slice(0, 7))}</option>`).join('')}</select></label>
      <span class="chip ${closed ? 'ok' : ''}" id="mc_state">${esc(closed ? T('state_closed') : T('state_open'))}</span></div>
      ${(pv.blockers || []).length ? `<div class="stack"><b>${esc(T('blockers'))}</b>${chips(pv.blockers, 'bad')}</div>` : (closed ? '' : `<div class="chip ok">${esc(T('ready'))}</div>`)}
      ${(pv.warnings || []).length ? `<div class="stack"><b>${esc(T('warns'))}</b>${chips(pv.warnings, 'warn')}</div>` : ''}
      <div class="row wrap"><button type="button" class="btn" data-act="mc_post">${esc(T('post'))}</button>
        ${closed ? (D.owner ? `<button type="button" class="btn" data-act="mc_reopen">${esc(T('reopen'))}</button>` : '') : `<button type="button" class="btn primary" data-act="mc_close" ${pv.can_close ? '' : 'disabled'}>${esc(T('close'))}</button>`}</div></div>
    <div class="card stack" id="mc_pay"><b>${esc(T('pay'))}</b>
      <div class="row between"><span>${esc(T('exp'))}</span><b id="mc_exp">${esc(mny(p.salary_expense))}</b></div>
      <div class="row between"><span>${esc(T('netpay'))}</span><span>${esc(mny(p.net_pay))}</span></div>
      <div class="row between"><span>${esc(T('paid'))}</span><span>${esc(mny(p.paid))}</span></div>
      <div class="row between"><span>${esc(T('unpaid'))}</span><span>${esc(mny(p.unpaid))}</span></div>
      <div class="row between"><span>${esc(T('salj'))}</span><span>${esc(mny(p.salary_in_journal))}</span></div>
      <div class="row between muted"><span>${esc(T('adv'))}</span><span>${esc(mny((pv.advances || {}).outstanding_all_staff))}</span></div></div>
    ${runRows(p.runs)}
    ${pr ? `<div class="card stack" id="mc_profit"><b>${esc(T('profit'))}</b><div class="row between"><span>${esc(T('inc'))}</span><span>${esc(mny(pr.income))}</span></div>
      <div class="row between"><span>${esc(T('expn'))}</span><span>${esc(mny(pr.expense))}</span></div>
      <div class="row between"><b>${esc(T('net'))}</b><b id="mc_net">${esc(mny(pr.net_profit))}</b></div>
      <div class="row between muted"><span>${esc(T('before'))}</span><span>${esc(mny(pr.profit_before_salary))}</span></div></div>` : ''}
    ${splitHTML(D.split)}
    <div class="card stack"><b>${esc(T('hist'))}</b>${(D.hist || []).length ? D.hist.map((h) => `<div class="row between"><span>${esc(String(h.month).slice(0, 7))}</span><span class="chip ${h.state === 'closed' ? 'ok' : ''}">${esc(h.state === 'closed' ? T('state_closed') : T('state_open'))}</span><span>${esc(mny(h.net_profit))}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>
    ${D.owner ? rulesHTML() : ''}`;
}
async function refresh() { await load(); paint(); }
async function call(fn, args, okMsg) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } if (okMsg) toast(okMsg); return r.data === null || r.data === undefined ? {} : r.data; }
async function setRule(key, value) { const r = await call('set_rule', { p_key: key, p_value: value }, T('saved')); if (r !== null) await refresh(); }
Object.assign(H, {
  mc_post: async () => { const r = await call('c_post_pending', { p_dry: false, p_limit: 500 }, T('done')); if (r !== null) await refresh(); },
  mc_close: async () => { const note = window.prompt(T('note')); if (note === null) return; const r = await call('c_month_close', { p_month: D.month, p_note: note || null }, T('done')); if (r !== null) await refresh(); },
  mc_reopen: async () => { const why = window.prompt(T('why')); if (!why) return; const r = await call('c_month_reopen', { p_month: D.month, p_reason: why }, T('done')); if (r !== null) await refresh(); },
  mc_tog: (a) => setRule(a.dataset.k, !(D.rules[a.dataset.k] === true)),
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t) return;
  if (t.id === 'mc_month') { D.month = t.value; refresh().catch(fail); }
  if (t.dataset && t.dataset.mcRule) setRule(t.dataset.mcRule, t.value);
  if (t.dataset && t.dataset.mcFrom) { const v = t.value.trim(); setRule('payroll_accrual_from', v === '' ? null : v); }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), `<div id="mc_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  if (!D.month) D.month = addM(mFirst(todayD()), -1);
  try { await load(); paint(); } catch (e) { const el = $('#mc_body'); if (el) el.innerHTML = `<p class="muted">${esc(eText(e))}</p>`; }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { monthclose: view });
})();
