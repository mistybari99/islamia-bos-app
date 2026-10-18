/* Islamia BOS · Balance check (#/balancecheck). Red / green status page for the books.
   The job: one look tells whether the books and the stock agree. Red = a book rule is broken (assets <> liabilities + equity + earnings, trial balance
   debit <> credit, a journal entry where Dr <> Cr, a stock identity break: opening + in - out <> closing). Amber = day book / journal / stock valuation / unposted
   documents disagree (usually timing) and never turns the page red.
   Server (supabase/phase84.sql): _e_balance_check(p_date, p_loc, p_days) READ ONLY; _e_test_reset_state() and _e_test_reset(p_phrase) (TEST PROJECTS ONLY).
   The reset card is shown ONLY to the owner AND only while the server rule allow_test_reset is ON (default OFF), and it still needs the typed phrase.
   UNVERIFIED on a real Supabase project and on a real phone. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const PHRASE = 'DELETE ALL TEST DATA';
const X = {
  title: L('হিসাব মেলানো (ব্যালান্স চেক)', 'Balance check', 'Balance check (হিসাব মেলানো)'),
  intro: L('শুধু দেখার পাতা: কিছু বদলায় না। লাল মানে হিসাবের নিয়ম ভেঙেছে; হলুদ মানে দুটি রিপোর্ট মিলছে না, দেখে নিন।',
    'A read-only page: it changes nothing. Red means a book rule is broken; amber means two reports disagree and need a look.',
    'শুধু দেখার page: কিছু বদলায় না। Red মানে হিসাবের নিয়ম ভেঙেছে; amber মানে দুটি report মিলছে না।'),
  asof: L('তারিখ পর্যন্ত', 'As of', 'As of'), place: L('লোকেশন', 'Place', 'Place'), all: L('সব', 'All', 'All'), show: L('দেখুন', 'Check', 'Check'),
  green: L('সব ঠিক আছে - হিসাব মিলেছে', 'All good - the books agree', 'সব ঠিক - হিসাব মিলেছে'),
  red: L('লাল - হিসাব মেলেনি', 'RED - the books do not agree', 'RED - হিসাব মেলেনি'),
  need: L('হিসাব শুরুর তারিখ দেওয়া নেই', 'Accounting start date is not set', 'হিসাব শুরুর তারিখ দেওয়া নেই'),
  eq: L('সমীকরণ: সম্পদ = দায় + মালিকের পুঁজি + মুনাফা', 'Equation: assets = liabilities + equity + earnings', 'Equation: assets = liabilities + equity + earnings'),
  assets: L('সম্পদ', 'Assets', 'Assets'), liab: L('দায়', 'Liabilities', 'Liabilities'), equity: L('পুঁজি', 'Equity', 'Equity'), earn: L('মুনাফা', 'Earnings', 'Earnings'),
  diff: L('পার্থক্য', 'Difference', 'Difference'),
  tb: L('ট্রায়াল ব্যালান্স: ডেবিট = ক্রেডিট', 'Trial balance: debit = credit', 'Trial balance: debit = credit'), dr: L('ডেবিট', 'Debit', 'Debit'), cr: L('ক্রেডিট', 'Credit', 'Credit'),
  je: L('জার্নাল এন্ট্রি যেখানে ডেবিট ≠ ক্রেডিট', 'Journal entries where debit differs from credit', 'Journal entry যেখানে Dr ≠ Cr'),
  stk: L('স্টক: শুরু + আসা - গেছে = শেষ', 'Stock: opening + in - out = closing', 'Stock: opening + in - out = closing'),
  none: L('কোনো ভুল নেই', 'None found', 'কোনো ভুল নেই'), more: L('আরও আছে (প্রথম ২০০টি দেখানো)', 'More exist (first 200 shown)', 'আরও আছে (first 200)'),
  entry: L('এন্ট্রি', 'Entry', 'Entry'), src: L('উৎস', 'Source', 'Source'), lines: L('লাইন', 'Lines', 'Lines'),
  item: L('আইটেম', 'Item', 'Item'), op: L('শুরু', 'Opening', 'Opening'), inn: L('আসা', 'In', 'In'), out: L('গেছে', 'Out', 'Out'), exp: L('হওয়ার কথা', 'Expected', 'Expected'), bal: L('স্টক ব্যালান্স', 'Stock balance', 'Stock balance'),
  xc: L('মিলিয়ে দেখা (হলুদ হলে দেখে নিন)', 'Cross-checks (amber = take a look)', 'Cross-check (amber হলে দেখুন)'),
  dvj: L('ডে-বুক বনাম জার্নাল', 'Day book vs journal', 'Day book vs journal'), ivg: L('স্টকের মূল্য বনাম জার্নাল', 'Stock value vs journal', 'Stock value vs journal'),
  unp: L('জার্নালে ওঠেনি এমন কাগজ ও ভুল', 'Documents not yet posted, and posting errors', 'Journal-এ ওঠেনি এমন document ও error'),
  kinds: L('ভিন্ন ধরন', 'Kinds that differ', 'Kinds that differ'), pend: L('বাকি', 'Pending', 'Pending'), errs: L('ভুল', 'Errors', 'Errors'),
  skipped: L('এই অনুমতিতে চালানো যায়নি', 'Not run with this permission', 'এই permission-এ চালানো যায়নি'),
  okc: L('ঠিক', 'OK', 'OK'), check: L('দেখুন', 'Look', 'Look'),
  note: L('স্টকের মিল এখনকার অবস্থা ধরে দেখা হয়। আসল Supabase-এ এখনো যাচাই করা হয়নি।', 'The stock identity is checked as of now. UNVERIFIED on a real Supabase project.', 'Stock identity এখনকার অবস্থায় দেখা হয়। আসল Supabase-এ এখনো যাচাই হয়নি।'),
  nofn: L('সার্ভারে phase84.sql চালানো হয়নি।', 'phase84.sql has not been run on the server yet.', 'Server-এ phase84.sql চালানো হয়নি।'),
  denied: L('এই পাতা দেখার অনুমতি নেই।', 'You do not have permission to open this page.', 'এই page দেখার permission নেই।'),
  rt: L('টেস্ট প্রজেক্ট রিসেট - শুধু টেস্টের জন্য', 'Test project reset - TEST PROJECTS ONLY', 'Test project reset - শুধু test-এর জন্য'),
  rwarn: L('এটি সব লেনদেন মুছে দেয় (আইটেম, নিয়ম, ভূমিকা, লোকেশন থাকে)। আসল প্রজেক্টে কখনও চালাবেন না।',
    'This clears ALL transactions (items, rules, roles and places stay). Never run it on the live project.',
    'এটি সব লেনদেন মুছে দেয় (item, rule, role, place থাকে)। Live project-এ কখনও চালাবেন না।'),
  rphrase: L('নিশ্চিত করতে লিখুন: ', 'To confirm, type: ', 'Confirm করতে লিখুন: '), rgo: L('সব লেনদেন মুছুন', 'Clear all transactions', 'সব লেনদেন মুছুন'),
  rdone: L('মোছা হয়েছে; সুইচ আবার বন্ধ', 'Cleared; the switch is OFF again', 'মোছা হয়েছে; switch আবার OFF'), rbad: L('বাক্যটি ঠিক নয়', 'The phrase does not match', 'Phrase ঠিক নয়'),
};
const T = (k) => lab(X[k]);
const D = { r: null, err: null, st: null, date: '', loc: '', locs: [] };
const num = (v) => (v == null || v === '' ? '-' : Number(v).toLocaleString('en-US', { maximumFractionDigits: 2 }));
const dateStr = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);

async function load() {
  D.err = null;
  const args = { p_date: D.date || null, p_loc: D.loc ? Number(D.loc) : null, p_days: 31 };
  const [r, s] = await Promise.all([sb.rpc('_e_balance_check', args), sb.rpc('_e_test_reset_state')]);
  if (r.error) {
    const m = r.error.message || '';
    if (r.error.code === 'PGRST202' || /does not exist|could not find/i.test(m)) { D.err = 'nofn'; return; }
    if (/not allowed/i.test(m)) { D.err = 'denied'; return; }
    throw r.error;
  }
  D.r = r.data; D.st = s && !s.error ? s.data : null;
}
const chip = (ok, txt) => `<span class="chip ${ok ? 'ok' : 'bad'}">${esc(txt)}</span>`;
const kv = (k, v) => `<div class="row between"><span>${esc(k)}</span><span>${esc(v)}</span></div>`;

function banner(r) {
  if (r.status === 'data_needed') return `<div class="card" id="bc_banner" data-status="data_needed"><b>${esc(T('need'))}</b></div>`;
  const red = r.status === 'red';
  const warn = (r.warnings || []).length;
  return `<div class="card stack" id="bc_banner" data-status="${esc(r.status)}" style="border-left:6px solid ${red ? '#c62828' : '#2e7d32'}">
    <div class="row between"><b style="font-size:1.1rem">${esc(red ? T('red') : T('green'))}</b>${chip(!red, red ? 'RED' : 'GREEN')}</div>
    ${warn ? `<span class="chip warn" id="bc_warn">${esc(String(warn))} ${esc(T('check'))}</span>` : ''}</div>`;
}
function eqHTML(r) {
  const e = r.equation, t = r.trial_balance;
  return `<div class="card stack" id="bc_eq"><div class="row between"><b>${esc(T('eq'))}</b>${chip(e.ok, e.ok ? T('okc') : 'RED')}</div>
    ${kv(T('assets'), num(e.assets))}${kv(T('liab'), num(e.liabilities))}${kv(T('equity'), num(e.equity))}${kv(T('earn'), num(e.earnings))}${kv(T('diff'), num(e.difference))}</div>
   <div class="card stack" id="bc_tb"><div class="row between"><b>${esc(T('tb'))}</b>${chip(t.ok, t.ok ? T('okc') : 'RED')}</div>
    ${kv(T('dr'), num(t.total_debit))}${kv(T('cr'), num(t.total_credit))}${kv(T('diff'), num(t.difference))}</div>`;
}
function jeHTML(r) {
  const j = r.journal;
  const rows = j.rows.map((x) => `<div class="row between bc-je" style="gap:.5rem"><span>#${esc(String(x.entry_id))} · ${esc(String(x.date))} · ${esc(x.source_type)} ${esc(x.source_id)}</span><span>${esc(T('dr'))} ${esc(num(x.debit))} / ${esc(T('cr'))} ${esc(num(x.credit))} (${esc(num(x.diff))}) · ${esc(String(x.lines))}</span></div>`).join('');
  return `<div class="card stack" id="bc_je"><div class="row between"><b>${esc(T('je'))}</b>${chip(j.ok, j.ok ? T('okc') : String(j.broken))}</div>
    ${j.ok ? `<p class="muted">${esc(T('none'))}</p>` : rows}${j.truncated ? `<p class="muted">${esc(T('more'))}</p>` : ''}</div>`;
}
function stkHTML(r) {
  const s = r.stock_identity;
  const rows = s.rows.map((x) => `<div class="row between bc-st" style="gap:.5rem"><span>${esc(T('item'))} ${esc(String(x.item_id).slice(0, 8))} · #${esc(String(x.location_id))}</span><span>${esc(T('op'))} ${esc(num(x.opening))} + ${esc(T('inn'))} ${esc(num(x.in))} - ${esc(T('out'))} ${esc(num(x.out))} = ${esc(num(x.expected_closing))} ≠ ${esc(num(x.stock_balance))}</span></div>`).join('');
  return `<div class="card stack" id="bc_stk"><div class="row between"><b>${esc(T('stk'))}</b>${chip(s.ok, s.ok ? T('okc') : String(s.broken))}</div>
    ${s.ok ? `<p class="muted">${esc(T('none'))}</p>` : rows}${s.truncated ? `<p class="muted">${esc(T('more'))}</p>` : ''}</div>`;
}
function xcHTML(r) {
  const c = r.cross_checks || {};
  const line = (key, title, body) => {
    const x = c[key];
    if (!x) return '';
    if (x.ran === false) return `<div class="row between"><span>${esc(title)}</span><span class="muted">${esc(T('skipped'))}</span></div>`;
    return `<div class="row between bc-xc" data-k="${esc(key)}"><span>${esc(title)}${body(x)}</span>${chip(x.ok, x.ok ? T('okc') : T('check'))}</div>`;
  };
  return `<div class="card stack" id="bc_xc"><b>${esc(T('xc'))}</b>
    ${line('daybook_vs_journal', T('dvj'), (x) => ` · ${T('kinds')}: ${x.kinds_differing}`)}
    ${line('inventory_vs_gl', T('ivg'), (x) => ` · ${T('diff')}: ${num(x.diff)}`)}
    ${line('unposted_sources', T('unp'), (x) => ` · ${T('pend')}: ${x.pending} · ${T('errs')}: ${x.errors}`)}
    ${line('money_accounts', 'Money accounts total = mapped ledger accounts', (x) => ` · ${num(x.money_accounts_total)} / ${num(x.ledger_total)} · ${T('diff')}: ${num(x.difference)}${x.red ? ' · RED' : ''}`)}</div>`;
}
function resetHTML() {
  const s = D.st; if (!s || !s.owner || !s.flag) return '';
  return `<div class="card stack" id="bc_reset" style="border:2px solid #c62828"><b style="color:#c62828">${esc(T('rt'))}</b><p>${esc(T('rwarn'))}</p>
    <p>${esc(T('rphrase'))}<code>${esc(PHRASE)}</code></p><input id="bc_phrase" autocomplete="off" maxlength="40">
    <button type="button" class="btn" data-act="bc_reset">${esc(T('rgo'))}</button></div>`;
}
function draw() {
  const el = $('#bc_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(T(D.err))}</p></div>`; return; }
  const r = D.r;
  const top = `<p class="muted">${esc(T('intro'))}</p>
    <div class="card row" style="gap:.5rem;align-items:end"><label>${esc(T('asof'))} <input type="date" id="bc_date" value="${esc(D.date || dateStr())}"></label>
    <label>${esc(T('place'))} <select id="bc_loc"><option value="">${esc(T('all'))}</option>${D.locs.map((l) => `<option value="${esc(String(l.id))}"${String(l.id) === String(D.loc) ? ' selected' : ''}>${esc(String(l.name || l.code || l.id))}</option>`).join('')}</select></label>
    <button type="button" class="btn primary" data-act="bc_go">${esc(T('show'))}</button></div>`;
  if (r.status === 'data_needed') { el.innerHTML = top + banner(r); return; }
  el.innerHTML = top + banner(r) + eqHTML(r) + jeHTML(r) + stkHTML(r) + xcHTML(r) + `<p class="muted" style="font-size:.85rem">${esc(T('note'))}</p>` + resetHTML();
}
Object.assign(H, {
  bc_go: async () => {
    D.date = $('#bc_date').value; D.loc = $('#bc_loc').value;
    try { await load(); draw(); } catch (e) { fail(e); }
  },
  bc_reset: async () => {
    const v = $('#bc_phrase').value;
    if (v !== PHRASE) return toast(T('rbad'));
    const r = await sb.rpc('_e_test_reset', { p_phrase: v });
    if (r.error) return fail(r.error);
    toast(T('rdone'));
    try { await load(); draw(); } catch (e) { fail(e); }
  },
});
async function viewBalanceCheck() {
  shell(T('title'), '<div id="bc_body"><p class="muted">…</p></div>', true);
  try {
    D.locs = ((S && S.ctx && S.ctx.locations) || []).map((l) => ({ id: l.id, name: l.name_en || l.name_bn || l.code, code: l.code }));
    await load(); draw();
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { balancecheck: viewBalanceCheck });
})();
