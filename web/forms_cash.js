/* Islamia BOS · forms batch B (cash, receivables, marketing, ledgers), taken field by field from the BOS Build Kit v1.39.
   07-1 · 04-1 · 30-1 · 14-1 · 17-1 · 25-1 · 23-1. Every limit comes from Location Settings; nothing is invented. */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO } = B.f;
B.forms = B.forms || {};

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const NEED = L('তথ্য লাগবে', 'Data needed');
const sv = (x, k) => (x.s[k] === undefined || x.s[k] === null ? null : x.s[k]);
const diffText = (d) => (d === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('পার্থক্য ৳ ' + fm(d), 'Difference ৳ ' + fm(d)));
const anyRow = (r) => Object.values(r || {}).some(has);
const r2 = (n) => Math.round(n * 100) / 100;
const uniq = (a) => [...new Set(a)];

// ---------- new settings keys (added only when not already in the catalogue) ----------
const addDefs = (list) => list.forEach(([key, group, bn, en, kind, unit]) => {
  if (!B.SETTING_DEFS.some((d) => d.key === key)) B.SETTING_DEFS.push({ key, group, label: L(bn, en), kind: kind || 'number', unit: unit === undefined ? '' : unit });
});
addDefs([
  ['jalebi_base_pct', 'C', 'জিলাপি — খামির থেকে ময়দার বেস রূপান্তর % (ফলন টেস্ট শিটের অনুমোদিত গড়)', 'Jalebi: dough-to-flour base conversion % (approved average of the yield test)', 'number', '%'],
  ['jalebi_per_kg_flour', 'C', 'জিলাপি — প্রতি কেজি ময়দায় জিলাপি (কেজি, ফলন টেস্ট শিটের অনুমোদিত গড়)', 'Jalebi: kg of jalebi per kg of flour (approved average of the yield test)', 'number', 'কেজি'],
  ['jalebi_tol_pct', 'C', 'জিলাপি কাউন্টার — প্রত্যাশিত বনাম প্রকৃতের গ্রহণযোগ্য পার্থক্য (%)', 'Jalebi counter: acceptable expected-vs-actual gap (%)', 'number', '%'],
  ['jalebi_tol_kg', 'C', 'জিলাপি কাউন্টার — প্রত্যাশিত বনাম প্রকৃতের সর্বোচ্চ পার্থক্য (কেজি)', 'Jalebi counter: acceptable expected-vs-actual gap (max kg)', 'number', 'কেজি'],
  ['oil_change_rule', 'C', 'জিলাপির তেল কখন বদলানো হবে', 'When the jalebi frying oil is changed', 'text', ''],
  ...[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((i) => ['mkt_limit_' + i, 'A', 'মার্কেটিং খাত ' + i + ' — মাসের সীমা', 'Marketing head ' + i + ' — monthly limit', 'number', '৳']),
  ['online_order_limit', 'A', 'অনলাইন অর্ডার — দিনে সর্বোচ্চ সংখ্যা (এর উপরে অনুমোদন)', 'Online orders — maximum per day (approval needed above)', 'number', 'টি'],
]);

/* ============ 07-1 · Digital payment reconciliation register ============ */
// showrooms come from the locations table (paused / closed places are not offered); the old fixed list is only a fallback when the table could not be read
const SHOWROOMS_FALLBACK = [['s1', L('ইসলামিয়া মিষ্টি ঘর — মেইন', 'ISLAMIYA MISTY GHAR — Main')], ['s2', L('ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', 'ISLAMIYA MISTY GHAR — 2nd Branch')], ['s3', L('মিষ্টি বাড়ি', 'MISTY BARI')], ['s4', L('AL-CAKIZ', 'AL-CAKIZ')]];
const showroomLocs = () => ((B.ENV && B.ENV.locs) || []).filter((l) => l.kind === 'showroom' && l.is_active !== false && ['live', 'setting_up', null, undefined].includes(l.status));
const SHOWROOMS = () => { const ls = showroomLocs(); return [...(ls.length ? ls.map((l) => [l.code, { bn: l.name_bn, en: l.name_en || l.name_bn, mix: l.name_mix || l.name_bn }]) : SHOWROOMS_FALLBACK), ['other', L('অন্য', 'Other')]]; };
const recCols = (nameCol, aLabel, cLabel, chgLabel, pre) => [nameCol,
  M('a', aLabel), M('b', L('স্টেটমেন্টে (B)', 'On the statement (B)')), M('chg', chgLabel), M('c', cLabel),
  CALC('d1', L('পার্থক্য: A − B', 'Difference: A − B'), 'money', { show: (x) => has(x.row.a) && has(x.row.b) }),
  CALC('d2', L('পার্থক্য: (B − চার্জ) − C', 'Difference: (B − charge) − C'), 'money', { show: (x) => has(x.row.b) && has(x.row.c) }),
  T('reason', L('কারণ / ব্যবস্থা', 'Reason / action'), { wide: true })];
function recCalc(rows, pre, v) {
  const out = rows.map((r) => ({ d1: has(r.a) && has(r.b) ? r2(num(r.a) - num(r.b)) : undefined, d2: has(r.b) && has(r.c) ? r2(num(r.b) - num(r.chg) - num(r.c)) : undefined }));
  v[pre + 'a'] = sum(rows.map((r) => r.a)); v[pre + 'b'] = sum(rows.map((r) => r.b)); v[pre + 'chg'] = sum(rows.map((r) => r.chg)); v[pre + 'c'] = sum(rows.map((r) => r.c));
  v[pre + 'd1'] = r2(v[pre + 'a'] - v[pre + 'b']); v[pre + 'd2'] = r2(v[pre + 'b'] - v[pre + 'chg'] - v[pre + 'c']);
  return { out, abs1: r2(sum(out.map((o) => Math.abs(o.d1 || 0)))), abs2: r2(sum(out.map((o) => Math.abs(o.d2 || 0)))), noB: rows.filter((r) => has(r.a) && !has(r.b)).length };
}
B.forms['07-1'] = {
  title: L('ডিজিটাল পেমেন্ট রিকনসিলিয়েশন', 'Digital Payment Reconciliation', 'Digital Payment Reconciliation'),
  head: [D('week_from', L('সপ্তাহ — থেকে', 'Week from'), { req: true }), D('week_to', L('সপ্তাহ — পর্যন্ত', 'Week to'), { req: true })],
  init(x, data) { if (!data.showroom) data.showroom = (showroomLocs().length ? showroomLocs().slice(0, 4).map((l) => l.code) : ['s1', 's2', 's3', 's4']).map((c) => ({ who: c })); },
  sections: [
    { title: L('নিয়ম ও স্টেটমেন্ট সংগ্রহ', 'Rule & statement collection'), fields: [
      NOTE(L('স্টেটমেন্ট হাতে না পেলে রিকনসিলিয়েশন আটকে থাকবে; অনুমান করে লেখা যাবে না।', 'Without the statement in hand the reconciliation stays on hold; nothing may be written by guessing.'), 'warn'),
      CK('st_bkash', L('বিকাশ', 'bKash')), CK('st_nagad', L('Nagad (নগদ)', 'Nagad')), CK('st_card', L('কার্ড/POS', 'Card / POS')), CK('st_bank', L('ব্যাংক', 'Bank')),
      CK('st_courier', L('কুরিয়ার', 'Courier')), CK('st_foodapp', L('ফুড অ্যাপ', 'Food app')), CK('st_other', L('অন্য', 'Other')), T('st_other_name', L('অন্য — কোনটি', 'Other — which'), { show: (x) => !!x.d.st_other }),
      D('st_date', L('সংগ্রহের তারিখ', 'Collection date')), ST('st_by', L('সংগ্রহকারী (Collected by)', 'Collected by')),
      CK('no_statement', L('কোনো স্টেটমেন্ট পাওয়া যায়নি → রিকনসিলিয়েশন আটক', 'No statement could be obtained → reconciliation on hold'), { req: false })] },
    { title: L('শোরুম', 'Showroom'), fields: [
      TABLE('showroom', null, recCols(SEL('who', L('শোরুম', 'Showroom'), SHOWROOMS, { wide: true }), L('শোরুমের কাগজে (A)', 'On the showroom paper (A)'), L('ব্যাংকে জমা (C)', 'Deposited in the bank (C)'), L('কেটে রাখা চার্জ', 'Charge deducted')), { min: 4 }),
      CALC('sh_a', L('মোট — শোরুমের কাগজে (A)', 'Total — showroom paper (A)'), 'money'), CALC('sh_b', L('মোট — স্টেটমেন্টে (B)', 'Total — statement (B)'), 'money'),
      CALC('sh_chg', L('মোট — কেটে রাখা চার্জ', 'Total — charge deducted'), 'money'), CALC('sh_c', L('মোট — ব্যাংকে জমা (C)', 'Total — deposited (C)'), 'money'),
      CALC('sh_d1', L('মোট পার্থক্য A − B', 'Total difference A − B'), 'money'), CALC('sh_d2', L('মোট পার্থক্য (B − চার্জ) − C', 'Total difference (B − charge) − C'), 'money')] },
    { title: L('কুরিয়ারের ক্যাশ অন ডেলিভারি ও ফুড অ্যাপের টাকা (Courier & Food App)', 'Courier cash on delivery & food-app money (Courier & Food App)'), fields: [
      TABLE('online', null, recCols(T('who', L('কুরিয়ার বা ফুড অ্যাপ', 'Courier or food app'), { wide: true }), L('অনলাইন ও ডেলিভারি লেজারে প্রাপ্য (A)', 'Due per the online & delivery ledger (A)'), L('হাতে বা ব্যাংকে প্রাপ্ত (C)', 'Received in hand or bank (C)'), L('কেটে রাখা চার্জ বা কমিশন', 'Charge or commission deducted')), { min: 3 }),
      CALC('on_a', L('মোট — লেজারে প্রাপ্য (A)', 'Total — ledger due (A)'), 'money'), CALC('on_b', L('মোট — স্টেটমেন্টে (B)', 'Total — statement (B)'), 'money'),
      CALC('on_chg', L('মোট — কেটে রাখা চার্জ', 'Total — charge deducted'), 'money'), CALC('on_c', L('মোট — প্রাপ্ত (C)', 'Total — received (C)'), 'money'),
      CALC('on_d1', L('মোট পার্থক্য A − B', 'Total difference A − B'), 'money'), CALC('on_d2', L('মোট পার্থক্য (B − চার্জ) − C', 'Total difference (B − charge) − C'), 'money')] },
    { title: L('গরমিল ও যাচাই', 'Exceptions & check'), fields: [
      NOTE(L('কাগজের ডিজিটাল = স্টেটমেন্ট; স্টেটমেন্ট − চার্জ = ব্যাংকে জমা। যাচাইকারী অবশ্যই ভিন্ন ব্যক্তি।', 'Paper digital = statement; statement − charge = bank deposit. The checker must be a different person.'), 'ok'),
      M('only_st_amt', L('স্টেটমেন্টে আছে, আমাদের কাগজে নেই — অঙ্ক', 'On the statement but not on our paper — amount'), { req: true }), N('only_st_n', L('— কতটি', '— how many')), T('only_st_note', L('— বিবরণ', '— details')),
      M('only_us_amt', L('আমাদের কাগজে আছে, স্টেটমেন্টে নেই — অঙ্ক', 'On our paper but not on the statement — amount'), { req: true }), N('only_us_n', L('— কতটি', '— how many')), T('only_us_note', L('— বিবরণ', '— details')),
      CH('personal', L('ব্যক্তিগত নম্বরে কোনো টাকা এসেছে?', 'Did any money arrive on a personal number?'), YN, { req: true }),
      M('personal_amt', L('— অঙ্ক', '— amount'), { show: (x) => x.d.personal === 'yes', req: (x) => x.d.personal === 'yes' }),
      NOTE(L('হ্যাঁ হলে সঙ্গে সঙ্গে ব্যবস্থাপনাকে জানাতে হবে।', 'If yes, inform management at once.'), 'warn', { show: (x) => x.d.personal === 'yes' }),
      CK('worklist', L('কাজের তালিকায় যোগ (পার্থক্যের সমাধান না হলে)', 'Added to the work list (if the difference is unresolved)')),
      ST('performed_by', L('সম্পাদনকারী (Performed by)', 'Performed by'))] },
    { who: 'checker', title: L('যাচাই', 'Check'), fields: [
      ST('checked_by', L('যাচাইকারী (Checked by) — ভিন্ন ব্যক্তি', 'Checked by — a different person'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const flags = [], v = {};
    const sh = recCalc(x.rows('showroom'), 'sh_', v), on = recCalc(x.rows('online'), 'on_', v);
    if (sh.abs1 > 0) flags.push(flag('dig_showroom_paper_diff', 'red', 'শোরুমের কাগজ ও স্টেটমেন্ট মেলেনি', 'Showroom paper differs from the statement', sh.abs1));
    if (sh.abs2 > 0) flags.push(flag('dig_bank_diff', 'red', 'স্টেটমেন্ট − চার্জ ব্যাংকে জমার সমান নয়', 'Statement − charge differs from the bank deposit', sh.abs2));
    if (on.abs1 > 0) flags.push(flag('app_ledger_diff', 'red', 'কুরিয়ার/ফুড অ্যাপ: লেজারের প্রাপ্য ও স্টেটমেন্ট মেলেনি', 'Courier / food app: ledger due differs from the statement', on.abs1));
    if (on.abs2 > 0) flags.push(flag('app_bank_diff', 'red', 'কুরিয়ার/ফুড অ্যাপ: স্টেটমেন্ট − চার্জ প্রাপ্তির সমান নয়', 'Courier / food app: statement − charge differs from the money received', on.abs2));
    if (sh.noB + on.noB > 0) flags.push(flag('dig_line_no_statement', 'yellow', 'কিছু লাইনে কাগজের অঙ্ক আছে কিন্তু স্টেটমেন্টের অঙ্ক নেই', 'Some lines have a paper amount but no statement amount'));
    if (x.d.no_statement) flags.push(flag('no_statement', 'red', 'স্টেটমেন্ট পাওয়া যায়নি — রিকনসিলিয়েশন আটক', 'No statement obtained — reconciliation on hold'));
    if (x.d.personal === 'yes') flags.push(flag('personal_number', 'red', 'ব্যক্তিগত নম্বরে টাকা এসেছে — ব্যবস্থাপনাকে জানান', 'Money arrived on a personal number — inform management', has(x.d.personal_amt) ? num(x.d.personal_amt) : undefined));
    if (num(x.d.only_st_amt) > 0) flags.push(flag('only_on_statement', 'yellow', 'স্টেটমেন্টে আছে কিন্তু আমাদের কাগজে নেই', 'On the statement but not on our paper', num(x.d.only_st_amt)));
    if (num(x.d.only_us_amt) > 0) flags.push(flag('only_on_paper', 'yellow', 'আমাদের কাগজে আছে কিন্তু স্টেটমেন্টে নেই', 'On our paper but not on the statement', num(x.d.only_us_amt)));
    return { v, rows: { showroom: sh.out, online: on.out }, flags, needs: [] };
  },
};

/* ============ 04-1 · Cash position & purchase budget ============ */
B.forms['04-1'] = {
  title: L('ক্যাশ পজিশন ও বাজেট', 'Cash Position and Budget', 'Cash পজিশন ও Budget'),
  head: [],
  sections: [
    { title: L('হাতে যা আছে', 'Cash in hand'), fields: [
      NOTE(L('এখন ব্যবসার হাতে মোট কত টাকা আছে — যেকোনো মুহূর্তে বলা যেতে হবে। ক্রয় এই সংখ্যার ভেতরে থাকবে।', 'How much money the business holds right now must be answerable at any moment. Purchases stay inside this number.'), 'ok'),
      M('hub_cash', L('হাবের ক্যাশ বাক্সে', 'In the hub cash box'), { req: true }),
      CALC('hub_state', L('সর্বোচ্চ নগদের সীমা (লোকেশন সেটিংস)', 'Maximum-cash limit (location settings)'), 'text'),
      CK('hub_informed', L('সীমার বাইরে — ব্যবস্থাপনাকে জানানো হয়েছে', 'Outside the limit — management informed'), { show: (x) => x.v.hub_over }),
      M('sr_float', L('শোরুমগুলোর ড্রয়ারে রাখা খুচরা', 'Float kept in the showroom drawers')), M('bank', L('ব্যাংকে', 'In the bank')), M('mobile', L('মোবাইল অ্যাকাউন্টে', 'In mobile accounts')),
      CALC('A', L('A · মোট হাতে (Total Cash)', 'A · Total cash in hand'), 'money', { big: true })] },
    { title: L('প্রাপ্য (পরবর্তী 7 দিনে)', 'Receivable (next 7 days)'), fields: [
      TABLE('recv', null, [M('amt', L('অঙ্ক ৳', 'Amount ৳')), D('date', L('তারিখ', 'Date'))], { rows: [L('পার্টি ও বাকির আদায়', 'Party & credit collections'), L('অর্ডারের বাকি টাকা', 'Order balances'), L('অন্যান্য', 'Other')] }),
      CALC('Bt', L('B · মোট প্রাপ্য (Receivable)', 'B · Total receivable'), 'money', { big: true })] },
    { title: L('দিতে হবে (7 দিনে)', 'Payable (in 7 days)'), fields: [
      TABLE('pay', null, [M('amt', L('অঙ্ক ৳', 'Amount ৳')), D('date', L('তারিখ', 'Date'))], { rows: [L('সাপ্লায়ারের বকেয়া', 'Supplier dues'), L('বেতন ও ভাতা', 'Salary & allowances'), L('ভাড়া · বিদ্যুৎ · গ্যাস', 'Rent · electricity · gas'), L('ঋণ পরিশোধ', 'Loan repayment'), L('অন্যান্য', 'Other')] }),
      CALC('Ct', L('C · মোট দিতে হবে (Payable)', 'C · Total payable'), 'money', { big: true })] },
    { title: L('পারচেজ বাজেট (Purchase Budget)', 'Purchase budget'), fields: [
      NOTE(L('পারচেজ বাজেট = A + B − C − সুরক্ষিত ন্যূনতম নগদ। এর বাইরে কোনো পারচেজ অর্ডার দেওয়া যাবে না।', 'Purchase budget = A + B − C − protected minimum cash. No purchase order may be placed beyond it.'), 'warn'),
      CALC('protect', L('সুরক্ষিত ন্যূনতম নগদ (লোকেশন সেটিংস)', 'Protected minimum cash (location settings)'), 'text'),
      CALC('budget', L('পারচেজ বাজেট', 'Purchase budget'), 'text')] },
    { title: L('ঘাটতির আশঙ্কা', 'Shortage risk'), fields: [
      CH('shortage', L('ঘাটতির আশঙ্কা আছে?', 'Is a shortage likely?'), YN, { req: true }),
      D('shortage_date', L('কবে', 'When'), { show: (x) => x.d.shortage === 'yes', req: (x) => x.d.shortage === 'yes' }),
      M('shortage_amt', L('ঘাটতির অঙ্ক ৳', 'Shortage amount ৳'), { show: (x) => x.d.shortage === 'yes' }),
      T('shortage_action', L('ব্যবস্থা (Action)', 'Action'), { show: (x) => x.d.shortage === 'yes', wide: true }),
      CK('mgmt_informed', L('ব্যবস্থাপনাকে জানানো', 'Management informed'), { show: (x) => x.d.shortage === 'yes', req: (x) => x.d.shortage === 'yes' })] },
    { title: L('টাকা কম হলে — আজ কাকে আগে', 'If money is short — who is paid first today'), fields: [
      TABLE('prio', null, [T('who', L('কাকে · কী বাবদ', 'To whom · for what'), { wide: true }), M('amt', L('অঙ্ক ৳', 'Amount ৳')), D('date', L('তারিখ', 'Date'))], { rows: ['1', '2', '3'].map((n) => L(n, n)) })] },
    { who: 'checker', title: L('সিদ্ধান্ত ও অনুমোদন (Approval) — প্রস্তুতকারী নন', 'Decision & approval — not the preparer'), fields: [
      NOTE(L('অনুমোদনকারী প্রস্তুতকারী হতে পারবেন না। ব্যবস্থাপনা যাচাই করবেন।', 'The approver cannot be the preparer. Management checks.'), 'warn', { who: 'checker' }),
      ST('approver', L('অনুমোদনকারী', 'Approved by'), { who: 'checker', req: true }), TM('approve_time', L('সময়', 'Time'), { who: 'checker' }),
      CK('phone_approval', L('ফোনে অনুমোদন (পরে স্বাক্ষর)', 'Approved by phone (signature later)'), { who: 'checker' })] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const mx = sv(x, 'hub_cash_max'), mn = sv(x, 'hub_min_cash');
    v.A = sum([d.hub_cash, d.sr_float, d.bank, d.mobile]); v.Bt = sum(x.rows('recv').map((r) => r.amt)); v.Ct = sum(x.rows('pay').map((r) => r.amt));
    if (mx === null) { needs.push('hub_cash_max'); v.hub_state = NEED; v.hub_over = false; if (has(d.hub_cash)) flags.push(flag('hub_max_missing', 'red', 'হাবের সর্বোচ্চ নগদের সীমা সেটিংসে নেই', 'Hub maximum-cash limit is missing in settings')); }
    else if (has(d.hub_cash)) { v.hub_over = num(d.hub_cash) > mx; v.hub_state = v.hub_over ? L('বাইরে (সীমা ৳ ' + fm(mx) + ')', 'Outside (limit ৳ ' + fm(mx) + ')') : L('ভেতরে ✓ (সীমা ৳ ' + fm(mx) + ')', 'Inside ✓ (limit ৳ ' + fm(mx) + ')');
      if (v.hub_over) flags.push(flag('hub_cash_over', 'yellow', 'হাবের নগদ সর্বোচ্চ সীমার বাইরে', 'Hub cash above the maximum', r2(num(d.hub_cash) - mx))); }
    else { v.hub_over = false; v.hub_state = '—'; }
    if (mn === null) { needs.push('hub_min_cash'); v.protect = NEED; v.budget = NEED; }
    else { v.protect = L('৳ ' + fm(mn), '৳ ' + fm(mn)); const bud = r2(v.A + v.Bt - v.Ct - mn); v.budget = L('৳ ' + fm(bud), '৳ ' + fm(bud)); v.budget_n = bud;
      if (bud < 0) flags.push(flag('budget_negative', 'yellow', 'পারচেজ বাজেট নেই — কোনো পারচেজ অর্ডার দেওয়া যাবে না', 'No purchase budget — no purchase order may be placed', bud)); }
    if (d.shortage === 'yes') flags.push(flag('shortage_risk', 'yellow', 'ঘাটতির আশঙ্কা', 'Shortage likely', has(d.shortage_amt) ? num(d.shortage_amt) : undefined));
    return { v, flags, needs };
  },
};

/* ============ 30-1 · Receivable & advance reconciliation ============ */
const ADV_STATUS = [['pending', L('বাকি', 'Pending')], ['given', L('দেওয়া হয়েছে', 'Delivered')], ['refunded', L('ফেরত দেওয়া', 'Refunded')]];
B.forms['30-1'] = {
  title: L('প্রাপ্য ও অ্যাডভান্স', 'Receivable and Advance', 'প্রাপ্য ও Advance'),
  head: [D('week_from', L('সপ্তাহ — থেকে', 'Week from'), { req: true }), D('week_to', L('সপ্তাহ — পর্যন্ত', 'Week to'), { req: true })],
  sections: [
    { title: L('Section A · কার কাছে কত প্রাপ্য (Receivable)', 'Section A · Who owes how much (Receivable)'), fields: [
      NOTE(L('কার কাছে কত প্রাপ্য, আর কত টাকার মালামাল দেওয়া বাকি। দুটোই লেজার দেখে বলা যেতে হবে।', 'Who owes how much, and how much goods are still to be delivered. Both must be answerable from the ledger.'), 'ok'),
      TABLE('recv', null, [T('party', L('পার্টি / কাস্টমারের নাম', 'Party / customer name'), { wide: true }), T('page', L('লেজারের পাতা নং', 'Ledger page no.')), M('total', L('মোট প্রাপ্য ৳', 'Total due ৳')),
        M('a30', L('30 দিনের কম', 'Under 30 days')), M('a60', L('31–60 দিন', '31–60 days')), M('a60p', L('60+ দিন', '60+ days')), T('action', L('গৃহীত ব্যবস্থা (Action Taken)', 'Action taken'), { wide: true })], { min: 6 }),
      CALC('t_total', L('মোট প্রাপ্য', 'Total due'), 'money', { big: true }), CALC('t_a30', L('মোট — 30 দিনের কম', 'Total — under 30 days'), 'money'), CALC('t_a60', L('মোট — 31–60 দিন', 'Total — 31–60 days'), 'money'), CALC('t_a60p', L('মোট — 60+ দিন', 'Total — 60+ days'), 'money')] },
    { title: L('Section B · খোলা অ্যাডভান্স (Open Advance) — যেসব অর্ডারের মালামাল এখনো যায়নি', 'Section B · Open advances — orders whose goods have not yet gone'), fields: [
      TABLE('adv', null, [T('order_no', L('অর্ডার নং', 'Order no.')), D('adv_date', L('অ্যাডভান্স নেওয়ার তারিখ', 'Advance taken on')), M('amt', L('অ্যাডভান্স ৳', 'Advance ৳')), D('due_date', L('ডেলিভারির নির্ধারিত তারিখ', 'Scheduled delivery date')),
        CH('status', L('অবস্থা', 'Status'), ADV_STATUS), T('note', L('মন্তব্য', 'Remark'), { wide: true })], { min: 6 }),
      CALC('adv_open', L('মোট খোলা অ্যাডভান্স', 'Total open advance'), 'money', { big: true })] },
    { title: L('যাচাই', 'Checks'), fields: [
      CH('over_credit', L('ক্রেডিট সীমার বাইরে কেউ আছে?', 'Is anyone beyond the credit limit?'), YN, { req: true }),
      T('over_party', L('পার্টি', 'Party'), { show: (x) => x.d.over_credit === 'yes', req: (x) => x.d.over_credit === 'yes' }),
      CK('credit_stopped', L('নতুন বাকি বন্ধ', 'New credit stopped'), { show: (x) => x.d.over_credit === 'yes' }),
      CH('adv_match', L('অ্যাডভান্সের মোট লেজারের সাথে মিল আছে?', 'Does the advance total match the ledger?'), YN, { req: true }),
      M('adv_diff', L('পার্থক্য ৳', 'Difference ৳'), { show: (x) => x.d.adv_match === 'no', req: (x) => x.d.adv_match === 'no' }),
      CALC('a60p_show', L('60+ দিনের প্রাপ্য', '60+ days receivable'), 'money'), CK('worklist', L('কাজের তালিকায় যোগ (60+ দিনের প্রাপ্য)', 'Added to the work list (60+ days receivable)')),
      ST('prepared_by', L('প্রস্তুতকারী (Prepared by)', 'Prepared by'))] },
    { who: 'checker', title: L('যাচাই', 'Check'), fields: [
      ST('checked_by', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা', 'Checked by — management'), { who: 'checker' })] },
  ],
  calc(x) {
    const rows = x.rows('recv'), adv = x.rows('adv'), flags = [], v = {};
    v.t_total = sum(rows.map((r) => r.total)); v.t_a30 = sum(rows.map((r) => r.a30)); v.t_a60 = sum(rows.map((r) => r.a60)); v.t_a60p = sum(rows.map((r) => r.a60p)); v.a60p_show = v.t_a60p;
    v.adv_open = sum(adv.filter((r) => r.status !== 'given' && r.status !== 'refunded').map((r) => r.amt));
    const bad = rows.filter((r) => has(r.total) && (has(r.a30) || has(r.a60) || has(r.a60p)) && r2(num(r.total) - num(r.a30) - num(r.a60) - num(r.a60p)) !== 0);
    if (bad.length) flags.push(flag('recv_aging_mismatch', 'yellow', 'প্রাপ্যের মোট ও বয়সের ভাগের যোগ মেলেনি', 'Total due differs from the sum of its age buckets', r2(sum(bad.map((r) => Math.abs(num(r.total) - num(r.a30) - num(r.a60) - num(r.a60p)))))));
    if (v.t_a60p > 0) flags.push(flag('recv_60plus', 'yellow', '60+ দিনের প্রাপ্য আছে', '60+ days receivable exists', v.t_a60p));
    if (x.d.over_credit === 'yes') flags.push(flag('over_credit', 'yellow', 'ক্রেডিট সীমার বাইরে পার্টি আছে', 'A party is beyond the credit limit'));
    if (x.d.over_credit === 'yes' && !x.d.credit_stopped) flags.push(flag('credit_not_stopped', 'red', 'ক্রেডিট সীমার বাইরের পার্টির নতুন বাকি বন্ধ হয়নি', 'New credit not stopped for a party beyond the limit'));
    if (x.d.adv_match === 'no' && num(x.d.adv_diff) !== 0) flags.push(flag('adv_ledger_mismatch', 'red', 'অ্যাডভান্সের মোট লেজারের সাথে মেলেনি', 'Advance total does not match the ledger', num(x.d.adv_diff)));
    return { v, flags, needs: [] };
  },
};

/* ============ 14-1 · Jalebi counter daily record ============ */
const kgT = (n) => L(fm(n) + ' কেজি', fm(n) + ' kg');
B.forms['14-1'] = {
  title: L('জিলাপি কাউন্টার দৈনিক', 'Jalebi Counter Daily', 'জিলাপি Counter দৈনিক'),
  head: [T('produced_slot', L('উৎপাদনকারী (Produced by) — পদ / ডিউটি স্লট', 'Produced by — role / duty slot')),
    T('prepared_slot', L('প্রস্তুতকারী (Prepared by) — খামির (পদ / ডিউটি স্লট)', 'Prepared by (dough) — role / duty slot')), CH('roster', L('রোস্টার অনুযায়ী', 'As per the roster'), YN),
    T('measured_slot', L('পরিমাপকারী (Measured by) — পদ / ডিউটি স্লট', 'Measured by — role / duty slot'), { req: true })],
  sections: [
    { title: L('Section A · খোলা ও বন্ধের মাপ', 'Section A · Opening & closing measures'), fields: [
      NOTE(L('যিনি ভাজেন তিনি মাপবেন না। খামির, তেল ও রস মাপা হবে দাগ-কাটা ডিপস্টিক বা পাল্লায়, তালিকা দেখে কেজি বা লিটারে। মালামাল ইস্যু স্লিপ ছাড়া কাউন্টারে কোনো মালামাল প্রাপ্ত হবে না — মিষ্টি কারখানার রসও নয়। অবিক্রিত (Unsold) জিলাপি বন্ধের সময় একবার ওজন করে সিদ্ধান্ত লিখতে হবে।',
        'Whoever fries does not measure. Dough, oil and syrup are measured with a marked dipstick or scale, from the list, in kg or litres. No goods are received at the counter without an issue slip, syrup from the sweet factory included. Unsold jalebi is weighed once at closing and a decision written.'), 'warn'),
      TABLE('meas', null, [TM('t_open', L('খোলায় — সময়', 'Opening — time')), N('open', L('খোলায় — পরিমাপ', 'Opening — amount'), { req: true }), TM('t_close', L('বন্ধে — সময়', 'Closing — time')), N('close', L('বন্ধে — পরিমাপ', 'Closing — amount'), { req: true }),
        CH('unit', L('একক', 'Unit'), [['kg', L('কেজি', 'KG')], ['l', L('লিটার', 'Litre')]])],
        { rows: [L('খামির', 'Dough'), L('তেল', 'Oil'), L('রস', 'Syrup')] }),
      ST('measured_by', L('পরিমাপকারী (Measured by) — স্বাক্ষর', 'Measured by — signature'), { req: true }),
      CH('scale', L('পাল্লা — জানা ওজনের বস্তু দিয়ে পরীক্ষা (খোলায়)', 'Scale — tested with a known weight (at opening)'), [['ok', L('ঠিক', 'OK')], ['bad', L('গরমিল', 'Off')]], { req: true }),
      NOTE(L('গরমিল হলে পাল্লা ব্যবহার বন্ধ, কাজের তালিকায় যোগ করুন।', 'If it is off, stop using the scale and add it to the work list.'), 'warn', { show: (x) => x.d.scale === 'bad' }),
      CK('scale_worklist', L('কাজের তালিকায় যোগ', 'Added to the work list'), { show: (x) => x.d.scale === 'bad' }),
      CH('oil_changed', L('তেল বদল', 'Oil change'), YN),
      CALC('oil_rule', L('তেল কখন বদল (লোকেশন সেটিংস)', 'When oil is changed (location settings)'), 'text', { show: (x) => x.d.oil_changed === 'yes' }),
      N('old_oil', L('পুরোনো তেল (লিটার)', 'Old oil (litres)'), { show: (x) => x.d.oil_changed === 'yes' }),
      CH('old_oil_fate', L('পুরোনো তেল', 'Old oil'), [['destroyed', L('নষ্ট করা', 'Discarded')], ['sold', L('বিক্রি', 'Sold')]], { show: (x) => x.d.oil_changed === 'yes' }),
      M('old_oil_amt', L('বিক্রি ৳', 'Sold for ৳'), { show: (x) => x.d.oil_changed === 'yes' && x.d.old_oil_fate === 'sold' }),
      T('old_oil_line', L('ক্যাশ ও ব্যাংক লেজারের লাইন নং', 'Cash & bank ledger line no.'), { show: (x) => x.d.oil_changed === 'yes' && x.d.old_oil_fate === 'sold' })] },
    { title: L('Section B · আজকের প্রাপ্তি — মালামাল ইস্যু স্লিপ অনুযায়ী', 'Section B · Receipts today — per goods issue slips'), fields: [
      TABLE('slips', null, [T('slip_no', L('মালামাল ইস্যু স্লিপ নং', 'Goods issue slip no.')), CK('i_flour', L('ময়দা', 'Flour')), CK('i_sugar', L('চিনি', 'Sugar')), CK('i_oil', L('তেল', 'Oil')), CK('i_syrup', L('রস', 'Syrup')), CK('i_other', L('অন্য', 'Other')),
        CH('source', L('উৎস', 'Source'), [['godown', L('গোডাউন', 'Godown')], ['factory', L('মিষ্টি কারখানা', 'Sweet factory')]])], { min: 5 }),
      N('tot_flour', L('দিনের মোট (স্লিপ অনুযায়ী) — ময়দা (কেজি)', 'Day total per slips — flour (kg)'), { req: true }), N('tot_sugar', L('— চিনি (কেজি)', '— sugar (kg)')),
      N('tot_oil', L('— তেল (লিটার)', '— oil (litres)')), N('tot_syrup', L('— রস (লিটার)', '— syrup (litres)'))] },
    { title: L('Section C · দিনের হিসাব', 'Section C · The day\'s working'), fields: [
      NOTE(L('বেস রূপান্তর % ও প্রতি কেজি ময়দায় জিলাপি: ফলন টেস্ট শিটের (জিলাপি) অনুমোদিত গড় · প্রতি কেজির দাম: মূল্য তালিকা · সীমা: লোকেশন সেটিংস শিট', 'Base conversion % and jalebi per kg of flour: approved average of the yield test sheet (jalebi) · price per kg: price list · limit: location settings'), 'ok'),
      ITEM('jalebi_item', L('জিলাপি (মূল্য তালিকা থেকে দাম নিতে)', 'Jalebi item (price taken from the price list)'), { req: true }),
      M('jalebi_sales', L('দৈনিক শোরুম শিটের জিলাপি বিক্রি ৳ (06-1 থেকে)', 'Jalebi sales (in taka) from the daily showroom sheet (06-1)', 'দৈনিক Showroom Sheet-এর জিলাপি বিক্রি ৳ (06-1 থেকে)'), { req: true }),
      CALC('c1', L('1 · ইস্যু হওয়া ময়দা (Section B-র মোট)', '1 · Flour issued (Section B total)'), 'text'),
      CALC('c2', L('2 · খোলার খামির − বন্ধের খামির', '2 · Opening dough − closing dough'), 'text'),
      CALC('c3', L('3 · খামির থেকে ময়দার হিসাব = (2) × 100 ÷ বেস রূপান্তর %', '3 · Flour worked out from dough = (2) × 100 ÷ base conversion %'), 'text'),
      CALC('c4', L('4 · আজ খরচ হওয়া ময়দা = (1) + (3)', '4 · Flour used today = (1) + (3)'), 'text'),
      CALC('c5', L('5 · প্রত্যাশিত জিলাপি = (4) × প্রতি কেজি ময়দায় জিলাপি', '5 · Expected jalebi = (4) × jalebi per kg of flour'), 'text', { big: true }),
      CALC('c6', L('6 · বিক্রি = জিলাপি বিক্রি ৳ ÷ প্রতি কেজির দাম', '6 · Sold = jalebi sales ৳ ÷ price per kg'), 'text'),
      N('unsold', L('7 · অবিক্রিত জিলাপি — বন্ধে একবার ওজন (কেজি)', '7 · Unsold jalebi — weighed once at closing (kg)'), { req: true }),
      N('samples', L('8 · নমুনা ও ভাঙা (কেজি)', '8 · Samples & broken (kg)')),
      CALC('c9', L('9 · প্রকৃত মোট = (6) + (7) + (8)', '9 · Actual total = (6) + (7) + (8)'), 'text'),
      CALC('c10', L('10 · পার্থক্য = (9) − (5)', '10 · Difference = (9) − (5)'), 'text', { big: true }),
      CALC('c10_state', L('সীমার ভেতরে / বাইরে (লোকেশন সেটিংস)', 'Inside / outside the limit (location settings)'), 'text'),
      CALC('c11', L('11 · তেল খরচ = তেল ইস্যু + খোলার তেল − বন্ধের তেল', '11 · Oil used = oil issued + opening oil − closing oil'), 'text'),
      CALC('c11k', L('— প্রতি কেজি জিলাপিতে তেল = (11) ÷ (9)', '— oil per kg of jalebi = (11) ÷ (9)'), 'text'),
      CALC('c12', L('12 · রস খরচ = প্রাপ্ত রস + খোলার রস − বন্ধের রস', '12 · Syrup used = syrup received + opening syrup − closing syrup'), 'text'),
      CALC('c12k', L('— প্রতি কেজি জিলাপিতে রস = (12) ÷ (9)', '— syrup per kg of jalebi = (12) ÷ (9)'), 'text')] },
    { title: L('Section D · অবিক্রিত (Unsold) জিলাপির সিদ্ধান্ত', 'Section D · Decision on unsold jalebi'), fields: [
      CALC('unsold_show', L('অবিক্রিত জিলাপির ওজন (উপরের 7)', 'Unsold weight (line 7 above)'), 'text'),
      CH('decision', L('সিদ্ধান্ত', 'Decision'), [['keep', L('রাতে রাখা হলো', 'Kept overnight')], ['drop', L('রাখা হলো না', 'Not kept')]], { req: (x) => num(x.d.unsold) > 0 }),
      CK('daytag', L('দিন-ট্যাগ লাগানো', 'Day tag attached'), { show: (x) => x.d.decision === 'keep', req: (x) => x.d.decision === 'keep' }),
      CK('wasted', L('স্টক লেজারে অপচয় হিসেবে লেখা', 'Written as wastage in the stock ledger'), { show: (x) => x.d.decision === 'drop', req: (x) => x.d.decision === 'drop' }),
      T('decider_role', L('সিদ্ধান্তগ্রহণকারী (Decided by) — পদ', 'Decided by — role')), ST('decided_by', L('সিদ্ধান্তগ্রহণকারী — স্বাক্ষর', 'Decided by — signature'))] },
    { title: L('Section E · গরমিল (Exception) — যেকোনো টিক পড়লে কাজের তালিকায় যোগ করতে হবে', 'Section E · Exceptions — any tick must be added to the work list'), fields: [
      NOTE(L('যেকোনো টিক পড়লে কাজের তালিকায় যোগ করতে হবে।', 'Any tick must be added to the work list.'), 'warn'),
      CK('e_noslip', L('স্লিপ ছাড়া মালামাল প্রাপ্ত হয়েছে', 'Goods received without a slip')), CK('e_nomeasure', L('মাপ নেওয়া হয়নি', 'Measure not taken')),
      CK('e_same', L('উৎপাদনকারী (Produced by) ও পরিমাপকারী (Measured by) একই ব্যক্তি', 'Producer and measurer are the same person')), CK('e_roster', L('রোস্টার মানা হয়নি', 'Roster not followed')),
      CK('e_syrup', L('রস কম পড়ায় আলাদা চিনির রস বানানো হয়েছে', 'Separate sugar syrup made because syrup ran short')), CK('e_diff', L('পার্থক্য সীমার বাইরে', 'Difference outside the limit')),
      N('e_days', L('পরপর কত দিন', 'Consecutive days'), { show: (x) => !!x.d.e_diff || x.v.diff_out, req: (x) => x.v.diff_out })] },
    { title: L('স্বাক্ষর', 'Signatures'), fields: [ST('produced_by', L('উৎপাদনকারী (Produced by)', 'Produced by'))] },
    { who: 'checker', title: L('যাচাই', 'Check'), fields: [ST('checked_by', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা', 'Checked by — management'), { who: 'checker' })] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const meas = x.rows('meas'), dough = meas[0] || {}, oil = meas[1] || {}, syr = meas[2] || {};
    const base = sv(x, 'jalebi_base_pct'), perkg = sv(x, 'jalebi_per_kg_flour'), pct = sv(x, 'jalebi_tol_pct'), mxk = sv(x, 'jalebi_tol_kg');
    v.oil_rule = sv(x, 'oil_change_rule') || NEED; if (d.oil_changed === 'yes' && !sv(x, 'oil_change_rule')) needs.push('oil_change_rule');
    const c1 = num(d.tot_flour); v.c1 = has(d.tot_flour) ? kgT(c1) : '—';
    const c2 = has(dough.open) && has(dough.close) ? num(dough.open) - num(dough.close) : null; v.c2 = c2 === null ? '—' : kgT(c2);
    let c3 = null; if (c2 !== null) { if (base === null || base === 0) { needs.push('jalebi_base_pct'); v.c3 = NEED; } else { c3 = c2 * 100 / base; v.c3 = kgT(c3); } } else v.c3 = '—';
    const c4 = c3 === null || !has(d.tot_flour) ? null : c1 + c3; v.c4 = c4 === null ? '—' : kgT(c4);
    let c5 = null; if (c4 !== null) { if (perkg === null) { needs.push('jalebi_per_kg_flour'); v.c5 = NEED; } else { c5 = c4 * perkg; v.c5 = kgT(c5); } } else v.c5 = '—';
    const it = d.jalebi_item && x.env.byCode ? x.env.byCode.get(d.jalebi_item) : null, price = it ? num(it.sell_price) : 0;
    const c6 = has(d.jalebi_sales) && price > 0 ? num(d.jalebi_sales) / price : null; v.c6 = c6 === null ? (has(d.jalebi_sales) ? NEED : '—') : kgT(c6);
    const c9 = c6 === null || !has(d.unsold) ? null : c6 + num(d.unsold) + num(d.samples); v.c9 = c9 === null ? '—' : kgT(c9);
    v.unsold_show = has(d.unsold) ? kgT(num(d.unsold)) : '—';
    v.c10 = '—'; v.c10_state = '—'; v.diff_out = false;
    if (c9 !== null && c5 !== null) {
      const df = r2(c9 - c5); v.c10 = L((df > 0 ? '+' : '') + fm(df) + ' কেজি', (df > 0 ? '+' : '') + fm(df) + ' kg');
      if (df === 0) v.c10_state = L('মিল আছে ✓', 'Matches ✓');
      else { const okP = pct !== null && c5 > 0 && Math.abs(df) / c5 * 100 <= pct, okK = mxk !== null && Math.abs(df) <= mxk;
        if (pct === null && mxk === null) needs.push('jalebi_tol_pct', 'jalebi_tol_kg');
        if (okP || okK) { v.c10_state = L('সীমার ভেতরে', 'Within the limit'); flags.push(flag('jalebi_diff_small', 'yellow', 'জিলাপির প্রত্যাশিত ও প্রকৃতে ছোট পার্থক্য (সীমার ভেতরে)', 'Small expected-vs-actual jalebi gap (inside the limit)', Math.abs(df), { unit: 'qty' })); }
        else { v.c10_state = pct === null && mxk === null ? NEED : L('সীমার বাইরে', 'Outside the limit'); v.diff_out = true; flags.push(flag('jalebi_diff', 'red', 'জিলাপির প্রত্যাশিত ও প্রকৃতের পার্থক্য সীমার বাইরে', 'Expected-vs-actual jalebi gap outside the limit', Math.abs(df), { unit: 'qty' })); } }
    }
    const un = (o) => (o.unit === 'l' ? L('লিটার', 'Litre') : L('কেজি', 'KG')); const qt = (n, o) => L(fm(n) + ' ' + un(o).bn, fm(n) + ' ' + un(o).en);
    const c11 = has(oil.open) && has(oil.close) ? num(d.tot_oil) + num(oil.open) - num(oil.close) : null; v.c11 = c11 === null ? '—' : qt(c11, oil);
    v.c11k = c11 !== null && c9 !== null && c9 > 0 ? L(fm(c11 / c9), fm(c11 / c9)) : '—';
    const c12 = has(syr.open) && has(syr.close) ? num(d.tot_syrup) + num(syr.open) - num(syr.close) : null; v.c12 = c12 === null ? '—' : qt(c12, syr);
    v.c12k = c12 !== null && c9 !== null && c9 > 0 ? L(fm(c12 / c9), fm(c12 / c9)) : '—';
    if (d.scale === 'bad') flags.push(flag('scale_off', 'red', 'পাল্লায় গরমিল — ব্যবহার বন্ধ', 'Scale is off — stop using it'));
    const sameP = has(d.produced_by) && d.produced_by === d.measured_by;
    if (sameP) flags.push(flag('producer_is_measurer', 'red', 'উৎপাদনকারী ও পরিমাপকারী একই জন', 'Producer and measurer are the same person'));
    else if (d.e_same) flags.push(flag('exc_same_person', 'yellow', 'গরমিল: উৎপাদনকারী ও পরিমাপকারী একই ব্যক্তি', 'Exception: producer and measurer are the same person'));
    if (d.e_noslip) flags.push(flag('exc_noslip', 'yellow', 'গরমিল: স্লিপ ছাড়া মালামাল প্রাপ্ত', 'Exception: goods received without a slip'));
    if (d.e_nomeasure) flags.push(flag('exc_nomeasure', 'yellow', 'গরমিল: মাপ নেওয়া হয়নি', 'Exception: measure not taken'));
    if (d.e_roster || d.roster === 'no') flags.push(flag('exc_roster', 'yellow', 'গরমিল: রোস্টার মানা হয়নি', 'Exception: roster not followed'));
    if (d.e_syrup) flags.push(flag('exc_syrup', 'yellow', 'গরমিল: রস কম পড়ায় আলাদা চিনির রস', 'Exception: separate sugar syrup because syrup ran short'));
    return { v, flags, needs: uniq(needs) };
  },
};

/* ============ 17-1 · Marketing expense register ============ */
const MKT_HEADS = [['1', L('1 · অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)', '1 · Online ads & boost (with VAT)')], ['2', L('2 · কনটেন্ট তৈরি', '2 · Content creation')], ['3', L('3 · ছাপা', '3 · Printing')], ['4', L('4 · স্যাম্পল ও ট্রায়াল', '4 · Samples & trials')],
  ['5', L('5 · অফার ও ছাড়ের ক্যাম্পেইন', '5 · Offer & discount campaigns')], ['6', L('6 · ডেলিভারি ভর্তুকি', '6 · Delivery subsidy')], ['7', L('7 · প্ল্যাটফর্ম কমিশন', '7 · Platform commission')], ['8', L('8 · উৎসব ও ইভেন্ট', '8 · Festivals & events')],
  ['9', L('9 · পার্টনার', '9 · Partners')], ['10', L('10 · অন্যান্য (লিখুন)', '10 · Other (write it)')]];
const MKT_SRC = [['imprest', L('ইমপ্রেস্ট (খরচের বাক্স)', 'Imprest (petty cash)')], ['bank', L('ব্যাংক', 'Bank')], ['card', L('কার্ড', 'Card')], ['mobile', L('মোবাইল', 'Mobile')], ['owner', L('মালিকের ব্যক্তিগত (লেজারে দুই দিকে)', 'Owner personal (both sides in the ledger)')]];
const MONTHS = ['জানুয়ারি:January', 'ফেব্রুয়ারি:February', 'মার্চ:March', 'এপ্রিল:April', 'মে:May', 'জুন:June', 'জুলাই:July', 'আগস্ট:August', 'সেপ্টেম্বর:September', 'অক্টোবর:October', 'নভেম্বর:November', 'ডিসেম্বর:December'].map((m, i) => [String(i + 1), L(m.split(':')[0], m.split(':')[1])]);
const MKT_BRANDS = [['imh', L('ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR')], ['mb', L('মিষ্টি বাড়ি', 'MISTY BARI')], ['ak', L('AL-CAKIZ', 'AL-CAKIZ')], ['other', L('অন্য', 'Other')], ['all', L('সব', 'All')]];
B.forms['17-1'] = {
  title: L('মার্কেটিং ব্যয়', 'Marketing Expense', 'মার্কেটিং Expense'),
  head: [SEL('month', L('মাস', 'Month'), MONTHS),
    CH('brand', L('ব্র্যান্ড', 'Brand'), () => (B.biz ? B.biz.brandOpts(MKT_BRANDS, ['other', 'all']) : MKT_BRANDS)),   // report_brand_map of the chosen business; MKT_BRANDS is the fallback

    T('brand_other', L('অন্য ব্র্যান্ড', 'Other brand'), { show: (x) => x.d.brand === 'other' })],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [
      NOTE(L('প্রতিটি মার্কেটিং খরচ কাজের আগেই এই রেজিস্টারে, অনুমোদনসহ। বিক্রির ড্রয়ার থেকে টাকা নয়। কর্মী নিজের টাকায় বুস্ট করে পরে ফেরত চাইলে — আগে অনুমোদন না থাকলে ফেরত নয়।', 'Every marketing expense goes into this register before the work, with approval. No money from the sales drawer. If a staff member boosts with their own money and asks for a refund later, there is no refund without prior approval.'), 'warn'),
      NOTE(L('স্যাম্পলের মালামাল ইস্যু হয় মালামাল ইস্যু স্লিপে।', 'Sample goods are issued on the goods issue slip.'), 'ok')] },
    { title: L('খরচের লাইন', 'Expense lines'), fields: [
      TABLE('lines', null, [D('date', L('তারিখ', 'Date')), SEL('head', L('খাত', 'Head'), B.optsX('marketing_heads', MKT_HEADS), { req: true, wide: true, list: 'marketing_heads' }), T('campaign', L('পণ্য বা ক্যাম্পেইন', 'Product or campaign'), { wide: true }), SEL('campaign_id', L('ক্যাম্পেইন (তালিকা থেকে)', 'Campaign (from the list)'), B.optsX('marketing_campaigns', []), { wide: true, list: 'marketing_campaigns' }), T('period', L('মেয়াদ · স্থান', 'Period · place')),
        SEL('source', L('টাকার উৎস', 'Source of money'), MKT_SRC), M('amt', L('টাকা ৳', 'Amount ৳'), { req: (x) => !has(x.row.nonpay) }), M('nonpay', L('টাকা প্রদান ছাড়া — মূল্য ৳', 'Without payment — value ৳')),
        T('receipt', L('রসিদ / ইনভয়েস নং', 'Receipt / invoice no.')), T('ledger', L('লেজারের লাইন নং', 'Ledger line no.')), T('result', L('ফল: মেসেজ · অর্ডার', 'Result: messages · orders'), { wide: true }),
        ST('approved_by', L('অনুমোদনকারী', 'Approved by')), TM('approve_time', L('মেসেজে অনুমোদন হলে সময়', 'Time, if approved by message'), { show: (x) => has(x.row.approved_by) }),
        CALC('state', L('খাতের সীমা (মাসের মোট)', 'Head limit (month total)'), 'text')], { min: 3 }),
      CALC('tot_amt', L('মোট টাকা', 'Total money'), 'money', { big: true }), CALC('tot_nonpay', L('মোট — টাকা প্রদান ছাড়া মূল্য', 'Total — value without payment'), 'money')] },
    { title: L('মাসের শেষে মিল', 'Month-end reconciliation'), fields: [
      CALC('reg_total', L('রেজিস্টারের টাকার মোট', 'Register money total'), 'money'),
      M('ledger_total', L('= ক্যাশ ও ব্যাংক লেজারের মার্কেটিং খরচ', '= marketing expense in the cash & bank ledger'), { req: true }),
      M('stmt_total', L('= কার্ড / মোবাইল স্টেটমেন্ট ও বিজ্ঞাপনের ইনভয়েস', '= card / mobile statements and ad invoices'), { req: true }),
      CALC('rec_text', L('মিল', 'Match'), 'text'),
      CALC('limit_text', L('লোকেশন সেটিংস শিটের খাত-সীমার ভেতরে', 'Within the head limits in location settings'), 'text'),
      ST('over_approver', L('সীমার বাইরে হলে অনুমোদনকারী (Approved by)', 'Approver if outside the limit'), { show: (x) => x.v.any_over, req: (x) => x.v.any_over }),
      ST('entered_by', L('এন্ট্রিকারী (Entered by) — অনলাইন দায়িত্ব', 'Entered by — online duty'))] },
    { who: 'checker', title: L('যাচাই ও অনুমোদন', 'Check & approval'), fields: [
      ST('checked_by', L('যাচাইকারী (Checked by) — দৈনিক হিসাব রিকনসিলিয়েশনের কর্মী', 'Checked by — daily reconciliation staff'), { who: 'checker', req: true }),
      ST('owner_by', L('অনুমোদনকারী (Approved by) — মালিক', 'Approved by — owner'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    const cum = {}, over = new Set(); let anyOver = false, excess = 0, noAppr = 0, noLim = 0;
    const out = rows.map((r) => {
      if (!has(r.head) || !has(r.amt) || num(r.amt) <= 0) return { state: '—' };
      const hk = String(r.head).startsWith('other:') ? 'other' : r.head;   // every write-in 'other:<text>' is one Other bucket (no list entry, so no limit of its own)
      const ex = B.optExtra('marketing_heads', hk), exl = ex && ex.limit_month !== undefined && ex.limit_month !== null && ex.limit_month !== '' ? Number(ex.limit_month) : null, lim = exl !== null && Number.isFinite(exl) ? exl : sv(x, 'mkt_limit_' + hk); cum[hk] = (cum[hk] || 0) + num(r.amt);
      if (lim === null) { needs.push('mkt_limit_' + hk); noLim += num(r.amt); return { state: NEED }; }
      if (cum[hk] > lim) { anyOver = true; over.add(hk); excess += Math.min(num(r.amt), cum[hk] - lim); if (!has(r.approved_by)) noAppr++; return { state: L('সীমার বাইরে', 'Outside the limit') }; }
      return { state: L('সীমার ভেতরে ✓', 'Within the limit ✓') };
    });
    v.tot_amt = sum(rows.map((r) => r.amt)); v.tot_nonpay = sum(rows.map((r) => r.nonpay)); v.reg_total = v.tot_amt; v.any_over = anyOver;
    v.limit_text = needs.length ? NEED : anyOver ? L('বাইরে', 'Outside') : rows.some((r) => has(r.amt)) ? L('ভেতরে ✓', 'Inside ✓') : '—';
    if (noLim > 0) flags.push(flag('mkt_limit_missing', 'red', 'মার্কেটিং খাতের মাসিক সীমা তালিকায় নেই', 'Marketing head monthly limit is not set in the list', noLim));
    if (anyOver) flags.push(flag('mkt_over_limit', 'yellow', 'মার্কেটিং খরচ খাতের সীমার বাইরে', 'Marketing spend over the head limit', excess));
    if (noAppr) flags.push(flag('mkt_approval_missing', 'red', 'সীমার বাইরের মার্কেটিং খরচে অনুমোদনকারী নেই', 'No approver on over-limit marketing spend', excess));
    const dl = has(x.d.ledger_total) ? r2(v.reg_total - num(x.d.ledger_total)) : null, ds = has(x.d.stmt_total) ? r2(v.reg_total - num(x.d.stmt_total)) : null;
    v.rec_text = dl === null && ds === null ? '—' : (dl || 0) === 0 && (ds || 0) === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('মিল নেই — লেজারের সাথে ৳ ' + fm(dl || 0) + ', স্টেটমেন্টের সাথে ৳ ' + fm(ds || 0), 'No match — ledger ৳ ' + fm(dl || 0) + ', statements ৳ ' + fm(ds || 0));
    if (dl) flags.push(flag('mkt_ledger_diff', 'red', 'রেজিস্টারের মোট ক্যাশ ও ব্যাংক লেজারের সাথে মেলেনি', 'Register total differs from the cash & bank ledger', dl));
    if (ds) flags.push(flag('mkt_statement_diff', 'red', 'রেজিস্টারের মোট স্টেটমেন্ট ও ইনভয়েসের সাথে মেলেনি', 'Register total differs from statements and invoices', ds));
    return { v, rows: { lines: out }, flags, needs: uniq(needs) };
  },
};

/* ============ 25-1 · Party & wholesale ledger ============ */
B.forms['25-1'] = {
  title: L('পার্টি ও পাইকারি লেজার', 'Party and Wholesale Ledger', 'Party ও পাইকারি Ledger'),
  head: [T('page_no', L('পাতা নং', 'Page no.')), T('party', L('পার্টির নাম', 'Party name'), { req: true }), T('firm', L('প্রতিষ্ঠান / দোকান', 'Firm / shop')), T('phone', L('ফোন', 'Phone')), T('address', L('ঠিকানা', 'Address')),
    CH('rate_basis', L('দরের ভিত্তি', 'Rate basis'), [['list', L('পাইকারি তালিকা', 'Wholesale list')], ['special', L('বিশেষ', 'Special')]]),
    M('credit_limit', L('ক্রেডিট সীমা (Credit Limit) ৳', 'Credit limit ৳'), { req: true }), N('credit_days', L('বাকির সময় (দিন)', 'Credit period (days)')), ST('approved_by', L('অনুমোদনকারী (Approved by)', 'Approved by'))],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [NOTE(L('ক্রেডিট সীমা ও বাকির সময় ব্যবস্থাপনার অনুমোদনে ঠিক হবে — বিক্রয়কারীর সিদ্ধান্তে নয়। সীমা অতিক্রম করলে নতুন বাকিতে মালামাল যাবে না।', 'The credit limit and credit period are fixed by management approval, not by the seller. Beyond the limit no new goods go on credit.'), 'warn')] },
    { title: L('লেজার', 'Ledger'), fields: [
      NOTE(L('"আগের পাতা থেকে জের" ঘরটি কাগজে নেই — চলতি পাতায় আগের জের আনার জন্য অ্যাপের যোগ। ফাঁকা থাকলে শূন্য ধরা হবে।', 'The "brought forward" box is not on the paper — an app addition for continuing pages. Blank counts as zero.'), 'ok'),
      M('opening', L('আগের পাতা থেকে জের ৳ (নতুন পাতায় থাকলে)', 'Brought forward from the previous page ৳ (if any)')),
      TABLE('lines', null, [D('date', L('তারিখ', 'Date'), { req: true }), T('inv_no', L('পার্টি ও পাইকারি ইনভয়েস নং', 'Party & wholesale invoice no.')), T('desc', L('বিবরণ', 'Description'), { wide: true }),
        M('inv', L('ইনভয়েস ৳', 'Invoice ৳')), M('ret', L('রিটার্ন / ডিসকাউন্ট ৳ (−)', 'Return / discount ৳ (−)')), M('coll', L('আদায় ৳ (−)', 'Collected ৳ (−)')),
        CALC('bal', L('বকেয়া ৳', 'Balance due ৳'), 'money', { show: (x) => anyRow(x.row) }), ST('sign', L('স্বাক্ষর', 'Signature'))], { min: 14 }),
      CALC('total_due', L('মোট বকেয়া (Total Due)', 'Total due'), 'money', { big: true })] },
    { title: L('বকেয়ার বয়স (Aging)', 'Age of dues (Aging)'), fields: [
      M('ag30', L('30 দিনের কম ৳', 'Under 30 days ৳')), M('ag60', L('31–60 দিন ৳', '31–60 days ৳')), M('ag60p', L('60+ দিন ৳', '60+ days ৳')),
      CALC('ag_text', L('বয়সের যোগ = মোট বকেয়া?', 'Age total = total due?'), 'text'),
      CALC('limit_state', L('ক্রেডিট সীমার ভেতরে / বাইরে', 'Inside / outside the credit limit'), 'text'),
      CK('credit_stop', L('নতুন বাকি বন্ধ', 'New credit stopped')), D('stop_date', L('শুরুর তারিখ', 'Start date'), { show: (x) => !!x.d.credit_stop }), ST('decided_by', L('সিদ্ধান্তগ্রহণকারী (Decided by)', 'Decided by'), { show: (x) => !!x.d.credit_stop })] },
    { title: L('এ মাসের লেনদেন', 'This month\'s dealings'), fields: [
      N('m_inv_n', L('ইনভয়েস (টি)', 'Invoices (no.)')), M('m_inv_amt', L('মোট ৳', 'Total ৳')), N('on_time', L('সময়মতো পেমেন্ট (বার)', 'On-time payments (times)')), N('late', L('দেরিতে পেমেন্ট (বার)', 'Late payments (times)')), T('remark', L('মন্তব্য', 'Remark'), { wide: true }), ST('keeper', L('হিসাবরক্ষক (Ledger Keeper)', 'Ledger keeper'))] },
    { who: 'checker', title: L('যাচাই', 'Check'), fields: [ST('checked_by', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা', 'Checked by — management'), { who: 'checker' })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], v = {}; let bal = num(x.d.opening);
    const out = rows.map((r) => { bal = r2(bal + num(r.inv) - num(r.ret) - num(r.coll)); return { bal }; });
    v.total_due = bal;
    const ag = r2(num(x.d.ag30) + num(x.d.ag60) + num(x.d.ag60p)), hasAg = has(x.d.ag30) || has(x.d.ag60) || has(x.d.ag60p);
    v.ag_text = !hasAg ? '—' : ag === bal ? L('মিল আছে ✓', 'Matches ✓') : L('অমিল ৳ ' + fm(r2(ag - bal)), 'Mismatch ৳ ' + fm(r2(ag - bal)));
    if (hasAg && ag !== bal) flags.push(flag('aging_mismatch', 'yellow', 'বকেয়ার বয়সের যোগ মোট বকেয়ার সমান নয়', 'Age total differs from the total due', r2(ag - bal)));
    const lim = has(x.d.credit_limit) ? num(x.d.credit_limit) : null; const over = lim !== null && r2(bal - lim) > 0;
    v.limit_state = lim === null ? '—' : over ? L('বাইরে', 'Outside') : L('ভেতরে ✓', 'Inside ✓');
    if (over) { flags.push(flag('over_credit_limit', 'yellow', 'বকেয়া ক্রেডিট সীমার বাইরে', 'Dues are beyond the credit limit', r2(bal - lim))); if (!x.d.credit_stop) flags.push(flag('credit_not_stopped', 'red', 'সীমা পেরিয়েছে কিন্তু নতুন বাকি বন্ধ হয়নি', 'Limit crossed but new credit not stopped', r2(bal - lim))); }
    if (lim !== null && !has(x.d.approved_by)) flags.push(flag('credit_no_approver', 'yellow', 'ক্রেডিট সীমার অনুমোদনকারীর নাম নেই', 'No approver named for the credit limit'));
    if (num(x.d.ag60p) > 0) flags.push(flag('party_60plus', 'yellow', '60+ দিনের বকেয়া আছে', '60+ days dues exist', num(x.d.ag60p)));
    return { v, rows: { lines: out }, flags, needs: [] };
  },
};

/* ============ 23-1 · Online & delivery ledger ============ */
B.forms['23-1'] = {
  title: L('অনলাইন ও ডেলিভারি লেজার', 'Online and Delivery Ledger', 'Online ও Delivery Ledger'),
  head: [D('week_from', L('সপ্তাহ — থেকে', 'Week from'), { req: true }), D('week_to', L('সপ্তাহ — পর্যন্ত', 'Week to'), { req: true })],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [NOTE(L('প্রতিটি অনলাইন অর্ডার আগে কাস্টমার অর্ডার ফরমে, তারপর এই লেজারে এক লাইন। অ্যাডভান্স শুধু ব্যবসার মার্চেন্ট নম্বরে — কর্মীর নম্বরে কখনো নয়।', 'Every online order goes first on the customer order form, then one line in this ledger. Advance only on the business merchant number, never on a staff number.'), 'warn')] },
    { title: L('অর্ডারের লাইন', 'Order lines'), fields: [
      TABLE('lines', null, [D('date', L('তারিখ', 'Date'), { req: true }), T('platform', L('প্ল্যাটফর্ম', 'Platform')), T('order_no', L('কাস্টমার অর্ডার ফরম নং', 'Customer order form no.'), { req: true }), M('amt', L('অঙ্ক ৳', 'Amount ৳'), { req: true }),
        SEL('path', L('টাকার পথ', 'Money path'), [['merchant', L('মার্চেন্ট', 'Merchant')], ['cod', L('ক্যাশ অন ডেলিভারি', 'Cash on delivery')], ['foodapp', L('ফুড অ্যাপ', 'Food app')]]), LOC('showroom', L('শোরুম', 'Showroom')),
        SEL('delivery', L('ডেলিভারি', 'Delivery'), [['shop', L('দোকান থেকে', 'From the shop')], ['own', L('নিজস্ব', 'Own')], ['courier', L('কুরিয়ার', 'Courier')], ['foodapp', L('ফুড অ্যাপ', 'Food app')]]), M('dcharge', L('ডেলিভারি চার্জ ৳', 'Delivery charge ৳')),
        CH('outcome', L('ফলাফল', 'Outcome'), [['handed', L('হাতে দেওয়া', 'Handed over')], ['returned', L('ফেরত', 'Returned')]]), T('return_ref', L('রিটার্ন ও অভিযোগ রেজিস্টার নং', 'Return & complaint register no.'), { show: (x) => x.row.outcome === 'returned' }),
        CK('money_in', L('টাকা এসেছে', 'Money received')), T('match_src', L('মিলের উৎস', 'Source of the match'))], { min: 3 }),
      CALC('tot_amt', L('মোট অঙ্ক', 'Total amount'), 'money', { big: true }), CALC('tot_dch', L('মোট ডেলিভারি চার্জ', 'Total delivery charge'), 'money')] },
    { title: L('সপ্তাহের শেষে মিল', 'End-of-week reconciliation'), fields: [
      CALC('led_total', L('এই লেজারের মোট', 'This ledger\'s total'), 'money'),
      M('forms_total', L('= কাস্টমার অর্ডার ফরমের অনলাইন-টিকের মোট', '= total of the online-ticked customer order forms'), { req: true }),
      M('sheet_total', L('= দৈনিক শোরুম শিটের "এর মধ্যে অনলাইন"-র যোগ', '= sum of "of which online" on the daily showroom sheets'), { req: true }),
      CALC('rec_text', L('মিল', 'Match'), 'text'),
      CK('to_10_3', L('কুরিয়ার ও ফুড অ্যাপের প্রাপ্য → ডিজিটাল পেমেন্ট রিকনসিলিয়েশন রেজিস্টারে', 'Courier & food-app dues → digital payment reconciliation register')),
      CALC('limit_text', L('অর্ডার-সীমা (লোকেশন সেটিংস শিট) পার হয়েছে?', 'Order limit (location settings) exceeded?'), 'text'),
      CALC('over_days', L('যে দিন পার হয়েছে', 'Day(s) exceeded'), 'text', { show: (x) => x.v.over_n > 0 }),
      ST('over_approver', L('অনুমোদনকারী (Approved by)', 'Approved by'), { show: (x) => x.v.over_n > 0, req: (x) => x.v.over_n > 0 })] },
    { title: L('এ সপ্তাহে', 'This week'), fields: [
      N('c_msgs', L('মেসেজ / খোঁজ', 'Messages / enquiries')), N('c_orders', L('অর্ডার', 'Orders')), N('c_returns', L('ফেরত বা অভিযোগ', 'Returns or complaints')), N('c_good', L('রিভিউ: ভালো', 'Reviews: good')), N('c_bad', L('রিভিউ: খারাপ', 'Reviews: bad')),
      CK('to_weekly', L('সাপ্তাহিক রিভিউ নোটে', 'Carried to the weekly review note'))] },
    { who: 'checker', title: L('যাচাই ও রিভিউ', 'Check & review'), fields: [
      ST('checked_by', L('যাচাইকারী (Checked by) — দৈনিক হিসাব রিকনসিলিয়েশনের কর্মী', 'Checked by — daily reconciliation staff'), { who: 'checker', req: true }),
      ST('reviewed_by', L('রিভিউকারী (Reviewed by) — মালিক', 'Reviewed by — owner'), { who: 'checker' })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    v.tot_amt = sum(rows.map((r) => r.amt)); v.tot_dch = sum(rows.map((r) => r.dcharge)); v.led_total = v.tot_amt;
    const df = has(x.d.forms_total) ? r2(v.led_total - num(x.d.forms_total)) : null, ds = has(x.d.sheet_total) ? r2(v.led_total - num(x.d.sheet_total)) : null;
    v.rec_text = df === null && ds === null ? '—' : (df || 0) === 0 && (ds || 0) === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('মিল নেই — অর্ডার ফরমের সাথে ৳ ' + fm(df || 0) + ', শোরুম শিটের সাথে ৳ ' + fm(ds || 0), 'No match — order forms ৳ ' + fm(df || 0) + ', showroom sheets ৳ ' + fm(ds || 0));
    if (df) flags.push(flag('online_forms_diff', 'red', 'লেজারের মোট কাস্টমার অর্ডার ফরমের সাথে মেলেনি', 'Ledger total differs from the customer order forms', df));
    if (ds) flags.push(flag('online_sheet_diff', 'red', 'লেজারের মোট দৈনিক শোরুম শিটের অনলাইন যোগের সাথে মেলেনি', 'Ledger total differs from the online total on the daily sheets', ds));
    const lim = sv(x, 'online_order_limit'), perDay = {}; rows.filter((r) => has(r.amt)).forEach((r) => { const k = has(r.date) ? r.date : 'undated'; perDay[k] = (perDay[k] || 0) + 1; });
    const days = Object.keys(perDay).filter((k) => lim !== null && perDay[k] > lim).sort(); v.over_n = days.length; v.over_days = days.join(', ');
    if (lim === null) { needs.push('online_order_limit'); v.limit_text = NEED; if (rows.some((r) => has(r.amt))) flags.push(flag('online_limit_missing', 'red', 'অনলাইন অর্ডারের দৈনিক সীমা সেটিংসে নেই', 'Daily online order limit missing in settings')); } else { v.limit_text = days.length ? L('হ্যাঁ — পার হয়েছে', 'Yes — exceeded') : L('না ✓', 'No ✓'); }
    if (days.length) { flags.push(flag('online_order_limit', 'yellow', 'দিনে অনলাইন অর্ডারের সীমা পার হয়েছে', 'Daily online order limit exceeded', Math.max(...days.map((k) => perDay[k])), { unit: 'qty' }));
      if (!has(x.d.over_approver)) flags.push(flag('online_limit_no_approver', 'red', 'অর্ডার-সীমা পারের অনুমোদনকারী নেই', 'No approver for the exceeded order limit', undefined)); }
    return { v, flags, needs };
  },
};
B.SETTING_DEFS.forEach((d) => { if (/^mkt_limit_/.test(d.key)) { d.hidden = true; d.label = L('মার্কেটিং খাতের মাসিক সীমা (তালিকা পাতায় দিন)', 'Marketing head monthly limit (set it on the Lists page)'); } });
// RPT-C2 (#150): a Cashier box in the head of the daily showroom sheet 06-1 (the shift box is already there). Added once; older sheets simply have no cashier. Paper form code: unchanged (the box is a digital entry).
if (B.forms['06-1'] && B.forms['06-1'].head && !B.forms['06-1'].head.some((f) => f.id === 'cashier')) B.forms['06-1'].head.push(ST('cashier', L('ক্যাশিয়ার (Cashier)', 'Cashier')));
})();
