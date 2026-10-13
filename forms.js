/* Islamia BOS · form definitions, taken field by field from the BOS Build Kit v1.39.
   Every limit comes from Location Settings; nothing is invented. A missing setting is reported as "data needed". */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO } = B.f;
B.forms = B.forms || {};
// list choices with the shared list control (+ Add new / Other) when listctl.js is loaded and the list rules are installed; the old fixed array stays as the fallback
B.optsX = B.optsX || ((code, fallback) => () => (B.listctl ? B.listctl.opts(code, fallback) : B.opts(code, fallback))());

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const UNITS = { kg: L('কেজি', 'KG'), pc: L('পিস', 'Piece'), lb: L('পাউন্ড', 'Pound') };
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const itemOf = (x, code) => (x.env.byCode && x.env.byCode.get(code)) || null;
const unitOf = (x, code) => { const it = itemOf(x, code); return it ? (UNITS[it.unit] || L(it.unit || '', it.unit || '')) : ''; };
const tagOf = (x, date) => (date ? (x.s['daytag_' + new Date(date + 'T12:00:00').getDay()] || '') : '');
const NEED = L('তথ্য লাগবে', 'Data needed');
const cfShow = (key) => (x) => !x.cf || has(x.d[key]);
const cfShowC = (key) => (x) => !x.cf || has(x.c[key]);
// tolerance: zero is fine; inside the limit is yellow; outside (or no limit written) is red
function tol(diff, limit) { if (diff === 0) return null; if (limit === null || limit === undefined) return 'red'; return Math.abs(diff) <= limit ? 'yellow' : 'red'; }
const diffText = (d) => (d === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('পার্থক্য ৳ ' + fm(d), 'Difference ৳ ' + fm(d)));

/* ============ 10-2 · Expense voucher ============ */
const HEADS = [['staff_meal', L('স্টাফের খাবার / নাস্তা', 'Staff meals / snacks')], ['transport', L('যাতায়াত / পরিবহন', 'Transport')], ['hospitality', L('কাস্টমার আপ্যায়ন', 'Customer hospitality')],
  ['repair', L('মেরামত / ইউটিলিটি', 'Repairs / utilities')], ['labour', L('অস্থায়ী শ্রমিকের মজুরি', 'Temporary labour wages')], ['sourcing', L('বাইরের সোর্সিংয়ের মালামাল', 'Outside-sourced goods')], ['other', L('অন্যান্য (লিখুন)', 'Other (write it)')]];
B.forms['10-2'] = {
  title: L('ব্যয় ভাউচার', 'Expense voucher'),
  head: [TM('time', L('সময়', 'Time')), T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.'))],
  sections: [
    { title: L('খরচের তালিকা (ইমপ্রেস্ট থেকে)', 'Expenses (from the imprest)'), fields: [
      TABLE('lines', null, [SEL('head', L('খরচের খাত', 'Expense head'), B.optsX('expense_heads', HEADS), { req: true, wide: true, list: 'expense_heads' }), T('to', L('কার কাছে / কী বাবদ', 'Paid to / for'), { wide: true }),
        CH('receipt', L('রসিদ সংযুক্ত', 'Receipt attached'), YN, { req: true }), M('amount', L('টাকা', 'Amount'), { req: true })], { min: 3 }),
      CALC('total', L('মোট', 'Total'), 'money', { big: true })] },
    { title: L('সীমা ও রসিদ', 'Limit & receipts'), fields: [
      PHOTO('receipt_photos', L('রসিদ / ভাউচারের ছবি', 'Receipt / voucher photos')),
      CALC('limit_text', L('সীমা যাচাই', 'Limit check'), 'text'),
      ST('approved_by', L('সীমার উপরে হলে অনুমোদনকারী', 'Approved by (when over the limit)'), { show: (x) => x.v.over_limit, req: (x) => x.v.over_limit }),
      TA('no_receipt_reason', L('রসিদ না থাকলে কারণ', 'Reason if a receipt is missing'), { show: (x) => x.v.no_receipt, req: (x) => x.v.no_receipt }),
      CK('drawer_untouched', L('বিক্রয় ড্রয়ার থেকে কিছু নেওয়া হয়নি', 'Nothing was taken from the sales drawer'), { req: true })] },
    { title: L('ইমপ্রেস্টের হিসাব', 'Imprest (petty cash) check'), fields: [
      NOTE(L('নগদ ও রসিদের যোগফল সবসময় নির্ধারিত টাকার সমান থাকবে। পুনঃপূরণ হবে শুধু রসিদের বিপরীতে।', 'Cash plus receipts must always equal the fixed amount. Replenishment only against receipts.'), 'ok'),
      M('cash_morning', L('সকালে নগদ', 'Cash in the morning')),
      M('cash_now', L('এখন নগদ (গুনে লিখুন)', 'Cash now (count, then enter)'), { req: true }),
      M('receipts_total', L('রসিদের মোট', 'Receipts total'), { req: true }),
      CALC('sum_cr', L('নগদ + রসিদ', 'Cash + receipts'), 'money', { show: cfShow('cash_now') }),
      CALC('imprest_text', L('নির্ধারিত টাকার সাথে মিল', 'Match with the fixed amount'), 'text', { show: cfShow('cash_now') })] },
  ],
  calc(x) {
    const lines = x.rows('lines'), amt = lines.map((r) => num(r.amount)), total = sum(amt);
    const lim = x.s.expense_max, over = lim !== undefined && lim !== null && amt.some((a) => a > lim), maxA = Math.max(0, ...amt);
    const noRec = lines.filter((r) => r.receipt === 'no' && num(r.amount) > 0), noRecAmt = sum(noRec.map((r) => r.amount));
    const imp = x.s.imprest, sumcr = num(x.d.cash_now) + num(x.d.receipts_total);
    const flags = [], needs = [];
    if (lim === undefined || lim === null) needs.push('expense_max');
    if (over) { flags.push(flag('over_limit', 'yellow', 'খরচ সীমার উপরে', 'Expense above the limit', maxA)); if (!has(x.d.approved_by)) flags.push(flag('approval_missing', 'red', 'সীমার উপরের খরচে অনুমোদনকারীর নাম নেই', 'No approver named for an over-limit expense', maxA)); }
    if (noRec.length) { flags.push(flag('no_receipt', 'yellow', 'রসিদ ছাড়া খরচ', 'Expense without a receipt', noRecAmt)); if (!has(x.d.no_receipt_reason)) flags.push(flag('receipt_reason_missing', 'red', 'রসিদ না থাকার কারণ লেখা নেই', 'Reason for the missing receipt is not written', noRecAmt)); }
    let itext = NEED;
    if (imp === undefined || imp === null) needs.push('imprest');
    else if (has(x.d.cash_now)) { const diff = sumcr - imp; itext = diffText(diff); if (diff !== 0) flags.push(flag('imprest_mismatch', 'red', 'নগদ + রসিদ নির্ধারিত ইমপ্রেস্টের সমান নয়', 'Cash + receipts differ from the fixed imprest', diff)); }
    return { v: { total, over_limit: over, no_receipt: noRec.length > 0, sum_cr: sumcr, imprest_text: itext,
      limit_text: lim === undefined || lim === null ? NEED : over ? L('সীমার উপরে', 'Over the limit') : L('সীমার ভেতরে', 'Within the limit') }, flags, needs };
  },
};

/* ============ 10-1 · Cash handover slip ============ */
B.forms['10-1'] = {
  title: L('ক্যাশ হ্যান্ডওভার স্লিপ', 'Cash handover slip'),
  head: [T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.')), T('carrier', L('বহনকারী', 'Carrier'), { req: true }), T('seal_no', L('সিল / ব্যাগ নং', 'Seal / bag no.')), TM('send_time', L('পাঠানোর সময়', 'Time sent'))],
  sections: [
    { title: L('হ্যান্ডওভার (শোরুম পূরণ করবে)', 'Handover (showroom fills)'), fields: [
      DEN('count', L('নোট ধরে গণনা', 'Count by notes'), { req: true }),
      CALC('counted_total', L('গণনায় প্রাপ্ত মোট', 'Counted total'), 'money'),
      M('leave_float', L('রেখে যাওয়া খুচরা', 'Float left behind'), { req: true }),
      CALC('handover', L('হ্যান্ডওভারের টাকা', 'Handover amount'), 'money', { big: true }),
      T('words', L('কথায়', 'In words')),
      CK('with_sheet', L('দৈনিক শোরুম শিট (মূল কপি) সাথে', 'Daily showroom sheet (original) enclosed'), { req: true }),
      N('vouchers_count', L('সাথে ব্যয় ভাউচার (টি)', 'Expense vouchers enclosed (no.)')), T('other_docs', L('অন্য কাগজ', 'Other papers'))] },
    { who: 'checker', title: L('গ্রহণ (হাব পূরণ করবে)', 'Receipt (hub fills)'), fields: [
      NOTE(L('আগে গুনুন, তারপর পার্থক্য দেখুন।', 'Count first, then see the difference.'), 'warn', { who: 'checker' }),
      DEN('rcount', L('হাবে নোট ধরে গণনা', 'Hub count by notes'), { who: 'checker', req: true }),
      CALC('received_total', L('হাবে গণনায় প্রাপ্ত', 'Counted at the hub'), 'money', { who: 'checker' }),
      CALC('diff', L('পার্থক্য', 'Difference'), 'money', { who: 'checker', big: true, show: (x) => B.num(x.denC('rcount')) > 0 }),
      TA('diff_reason', L('পার্থক্যের কারণ', 'Reason for the difference'), { who: 'checker', show: (x) => x.v.diff_nonzero, req: (x) => x.v.diff_nonzero }),
      D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date'), { who: 'checker' }), T('ledger_line', L('লেজারের লাইন নং', 'Ledger line no.'), { who: 'checker' }),
      CK('seal_ok', L('সিল ঠিক অবস্থায় পাওয়া', 'Seal found intact'), { who: 'checker' }), CK('copy_returned', L('ফেরত কপি শোরুমে পাঠানো', 'Return copy sent to the showroom'), { who: 'checker' })] },
  ],
  calc(x) {
    const counted = x.den('count'), leave = num(x.d.leave_float), handover = counted - leave, flags = [], needs = [];
    const fl = x.s.drawer_float;
    if (has(x.d.leave_float) && fl !== undefined && fl !== null && leave !== fl) flags.push(flag('float_mismatch', 'yellow', 'রেখে যাওয়া খুচরা নির্ধারিত খুচরার সমান নয়', 'Float left differs from the fixed float', leave - fl));
    if (fl === undefined || fl === null) needs.push('drawer_float');
    const rec = x.denC('rcount'), diff = rec - handover;
    if (rec > 0 && diff !== 0) flags.push(flag('hub_diff', 'red', 'হাবে গণনা হ্যান্ডওভারের সমান নয়', 'Hub count differs from the handover', diff, { src: 'check' }));
    return { v: { counted_total: counted, handover, received_total: rec, diff, diff_nonzero: rec > 0 && diff !== 0 }, flags, needs };
  },
};

/* ============ 03-1 · Transfer challan (IBT) ============ */
const TTYPES = [['f2s', L('কারখানা → শোরুম', 'Factory → showroom')], ['s2f', L('শোরুম → কারখানা (ফেরত)', 'Showroom → factory (return)')], ['cust', L('কাস্টমার / পার্টি', 'Customer / party')], ['s2s', L('শোরুম → শোরুম', 'Showroom → showroom')],
  ['g2l', L('গোডাউন → লোকেশন', 'Godown → location')], ['p2l', L('পার্টির ফেরত → লোকেশন', 'Party return → location')], ['other', L('অন্য', 'Other')]];
const GRADES = [['g1', L('১ম', '1st')], ['g2', L('২য়', '2nd')]];
B.forms['03-1'] = {
  title: L('ট্রান্সফার চালান (IBT)', 'Transfer challan (IBT)'),
  head: [SEL('ttype', L('ধরন', 'Type'), TTYPES, { req: true }), LOC('from_loc', L('প্রেরক লোকেশন (From)', 'Sender location (From)'), { req: true }), LOC('to_loc', L('প্রাপক লোকেশন (To)', 'Receiver location (To)'), { req: true }),
    CH('shift', L('শিফট', 'Shift'), [['m', L('সকাল', 'Morning')], ['a', L('বিকাল', 'Afternoon')], ['n', L('রাত', 'Night')]]), T('vehicle', L('গাড়ি / ভ্যান', 'Vehicle')), T('driver', L('ডেলিভারি ম্যান', 'Delivery man')),
    TM('out_time', L('আউট টাইম (প্রেরক)', 'Out time (sender)')), T('handover_point', L('হ্যান্ডওভার পয়েন্ট', 'Handover point'))],
  sections: [
    { title: L('পাঠানোর আগে যাচাই', 'Before dispatch'), fields: [
      CK('as_demand', L('দৈনিক শোরুম শিটের চাহিদা মতো পাঠানো', 'Sent as per the daily showroom sheet demand')), T('demand_sheet_no', L('শোরুম শিট নং', 'Showroom sheet no.')),
      CH('outside', L('চাহিদার বাইরের পণ্য?', 'Goods outside the demand?'), YN), T('outside_reason', L('কারণ', 'Reason'), { show: (x) => x.d.outside === 'yes', req: (x) => x.d.outside === 'yes' }),
      CH('cust_order', L('কাস্টমার অর্ডারের পণ্য?', 'Goods for a customer order?'), YN), T('order_no', L('অর্ডার নং', 'Order no.'), { show: (x) => x.d.cust_order === 'yes' }),
      CK('prod_dates', L('প্রতিটি লাইনে উৎপাদন তারিখ লেখা', 'Production date written on every line'), { req: true }), CK('grades', L('গ্রেড (১ম / ২য়) লেখা', 'Grade (1st / 2nd) written'), { req: true })] },
    { title: L('পণ্যের বিবরণ', 'Product description'), fields: [
      TABLE('items', null, [ITEM('item', L('আইটেম', 'Item'), { req: true, wide: true }), CALC('unit', L('একক', 'Unit'), 'text'), CH('grade', L('গ্রেড', 'Grade'), GRADES, { req: true }),
        D('prod_date', L('উৎপাদন তারিখ', 'Production date'), { req: true }), CALC('tag', L('ট্যাগ রং (সেটিংস থেকে)', 'Tag colour (from settings)'), 'text'),
        N('demand', L('চাহিদা', 'Demand')), N('sent', L('প্রেরিত পরিমাণ', 'Sent quantity'), { req: true }),
        N('received', L('গৃহীত পরিমাণ (প্রাপক)', 'Received quantity (receiver)'), { who: 'checker', req: true }), CALC('diff', L('পার্থক্য (প্রেরিত − গৃহীত)', 'Difference (sent − received)'), 'num'),
        T('remark', L('মন্তব্য / ড্যামেজ', 'Remark / damage'), { who: 'checker', wide: true })], { min: 3 })] },
    { who: 'checker', title: L('হ্যান্ডওভার পয়েন্টে গণনা ও যাচাই (প্রাপক)', 'Handover count & receiving check (receiver)'), fields: [
      NOTE(L('প্রেরক ও প্রাপক দুজনে একসাথে গণনা করে স্বাক্ষর করবেন। প্রাপক নিজে গণনা করবেন।', 'Sender and receiver count together and sign. The receiver counts personally.'), 'warn', { who: 'checker' }),
      TM('count_time', L('গণনার সময়', 'Count time'), { who: 'checker' }), TM('in_time', L('ইন টাইম (প্রাপক)', 'In time (receiver)'), { who: 'checker' }),
      CK('sender_counted', L('প্রেরক গণনা করেছেন', 'Sender counted'), { who: 'checker', req: true }), CK('receiver_counted', L('প্রাপক গণনা করেছেন', 'Receiver counted'), { who: 'checker', req: true }),
      CK('dates_ok', L('সব লাইনে উৎপাদন তারিখ আছে', 'Production dates on every line'), { who: 'checker' }), CK('tag_ok', L('ট্যাগ রং চালানের তারিখের সাথে মিল', 'Tag colour matches the challan date'), { who: 'checker' }),
      TA('damage_note', L('ড্যামেজ — পণ্য, পরিমাণ, মূল্য', 'Damage — item, quantity, value'), { who: 'checker' }),
      CH('liability', L('দায়', 'Liability'), [['factory', L('কারখানা', 'Factory')], ['transport', L('পরিবহন', 'Transport')], ['ok', L('ঠিক আছে', 'All fine')]], { who: 'checker' })] },
    { collapsed: true, title: L('কারখানায় ফেরত (দরকার হলে)', 'Return to factory (if needed)'), fields: [
      TABLE('returns', null, [ITEM('item', L('আইটেম', 'Item'), { wide: true }), N('qty', L('পরিমাণ', 'Quantity')),
        SEL('reason', L('কারণ', 'Reason'), [['g2', L('২য় গ্রেড', '2nd grade')], ['unsold', L('অবিক্রিত', 'Unsold')], ['broken', L('ভাঙা', 'Broken')], ['expired', L('মেয়াদ শেষ', 'Expired')]]), T('paper_no', L('সংশ্লিষ্ট কাগজের নং', 'Related paper no.'))], { min: 1 })] },
    { collapsed: true, title: L('ক্যারেট ও ট্রে', 'Crates & trays'), fields: [
      N('crates_sent', L('ক্যারেট — প্রেরিত', 'Crates sent')), N('crates_back', L('ক্যারেট — ফেরত', 'Crates returned')), N('crates_due', L('ক্যারেট — বকেয়া', 'Crates outstanding')),
      N('trays_sent', L('ট্রে — প্রেরিত', 'Trays sent')), N('trays_back', L('ট্রে — ফেরত', 'Trays returned')), N('trays_due', L('ট্রে — বকেয়া', 'Trays outstanding')),
      CK('crates_match', L('ক্যারেট/ট্রের হিসাব মিলেছে', 'Crate/tray count matches'))] },
    { collapsed: true, title: L('এন্ট্রি (পোস্টিং)', 'Posting'), fields: [
      CK('in_factory_sheet', L('কারখানা দৈনিক শিটে লেখা', 'Written in the factory daily sheet')), T('factory_sheet_no', L('কারখানা শিট নং', 'Factory sheet no.')),
      CK('in_stock_ledger', L('স্টক লেজারে লেখা', 'Written in the stock ledger')), CK('both_papers', L('চালান নং দুই কাগজেই লেখা', 'Challan no. written on both papers'))] },
    { collapsed: true, title: L('কাস্টমার / পার্টি ডেলিভারি (দরকার হলে)', 'Customer / party delivery (if needed)'), fields: [
      T('order_invoice_no', L('অর্ডার ফরম / ইনভয়েস নং', 'Order form / invoice no.')), T('recv_name', L('প্রাপকের নাম', 'Receiver name')), T('recv_phone', L('ফোন', 'Phone')),
      CH('pay', L('পেমেন্ট', 'Payment'), [['adv', L('অ্যাডভান্স', 'Advance')], ['cash', L('ক্যাশ', 'Cash')], ['credit', L('বাকি', 'Credit')]]), M('cash_amount', L('ক্যাশ টাকা', 'Cash amount'), { show: (x) => x.d.pay === 'cash' })] },
  ],
  calc(x) {
    const rows = x.rows('items'), rowsC = x.rowsC('items'), flags = [], needs = [];
    const out = rows.map((r, i) => { const c = rowsC[i] || {}; const diff = has(c.received) ? num(r.sent) - num(c.received) : undefined;
      return { unit: unitOf(x, r.item), tag: tagOf(x, r.prod_date), diff }; });
    const short = sum(rows.map((r, i) => { const c = rowsC[i] || {}; return has(c.received) ? Math.max(0, num(r.sent) - num(c.received)) : 0; }));
    const excess = sum(rows.map((r, i) => { const c = rowsC[i] || {}; return has(c.received) ? Math.max(0, num(c.received) - num(r.sent)) : 0; }));
    if (short > 0) flags.push(flag('shortage', 'red', 'প্রাপক কম পেয়েছে', 'Receiver got less than sent', short, { src: 'check', unit: 'qty' }));
    if (excess > 0) flags.push(flag('excess', 'yellow', 'প্রাপক বেশি পেয়েছে', 'Receiver got more than sent', excess, { src: 'check', unit: 'qty' }));
    if (x.d.outside === 'yes') flags.push(flag('outside_demand', 'yellow', 'চাহিদার বাইরের পণ্য পাঠানো হয়েছে', 'Goods outside the demand were sent', undefined));
    const over = sum(rows.map((r) => (has(r.demand) ? Math.max(0, num(r.sent) - num(r.demand)) : 0)));
    if (over > 0) flags.push(flag('over_demand', 'yellow', 'চাহিদার চেয়ে বেশি পাঠানো', 'Sent more than the demand', over, { unit: 'qty' }));
    if (has(x.d.from_loc) && x.d.from_loc === x.d.to_loc && x.d.from_loc !== 'other') flags.push(flag('same_location', 'red', 'প্রেরক ও প্রাপক একই লোকেশন', 'Sender and receiver are the same location'));
    return { v: {}, rows: { items: out }, flags, needs };
  },
};

/* ============ 04-3 · Stock count sheet ============ */
B.forms['04-3'] = {
  title: L('স্টক কাউন্ট শিট', 'Stock count sheet'),
  head: [TM('start_time', L('শুরুর সময়', 'Start time')), TM('end_time', L('শেষ সময়', 'End time')),
    ST('counted_by', L('গণনাকারী (Counted by)', 'Counted by'), { req: true }), ST('storekeeper', L('স্টোরকিপার', 'Storekeeper'), { req: true }),
    CH('kind', L('ধরন', 'Kind'), [['regular', L('নিয়মিত কাউন্ট', 'Regular count')], ['surprise', L('হঠাৎ কাউন্ট (Surprise)', 'Surprise count')]])],
  sections: [
    { title: L('গণনা', 'Count'), fields: [
      NOTE(L('স্টোরকিপার নিজে গণনা করবেন না, অন্য কেউ করবেন। গণনার সময় কোনো মালামাল প্রাপ্তি বা ইস্যু হবে না।', 'The storekeeper must not count; someone else does. No goods are received or issued while counting.'), 'warn'),
      CH('movement', L('গণনার সময় মালামাল প্রাপ্তি বা ইস্যু হয়েছে?', 'Were goods received or issued during the count?'), YN, { req: true }),
      T('movement_detail', L('বিবরণ', 'Details'), { show: (x) => x.d.movement === 'yes', req: (x) => x.d.movement === 'yes' }),
      TABLE('rows', null, [ITEM('item', L('আইটেম', 'Item'), { req: true, wide: true }), CALC('unit', L('একক', 'Unit'), 'text'),
        N('count', L('গণনায় প্রাপ্ত', 'Counted'), { req: true }),
        N('book', L('লেজারে বাকি (Book)', 'Book balance (ledger)'), { req: true, show: (x) => (!x.cf || has(x.row.count)) && !x.sbBook }),
        CALC('var', L('পার্থক্য (গণনা − লেজার)', 'Variance (count − book)'), 'num', { show: (x) => has(x.row.count) && has(x.row.book) }),
        T('reason', L('কারণ', 'Reason'), { wide: true, req: (x) => has(x.row.count) && has(x.row.book) && num(x.row.count) !== num(x.row.book) })], { min: 5 }),
      ST('witness', L('সাক্ষী / দ্বিতীয় জন', 'Witness / second person'), { req: (x) => !x.pin, show: (x) => !x.pin })] },
  ],
  calc(x) {
    const rows = x.rows('rows'), flags = [], needs = [];
    let outside = 0, small = 0, valueOut = 0;
    const pct = x.s.count_tol_pct, max = x.s.count_tol_max;
    const out = rows.map((r) => {
      if (!has(r.count) || !has(r.book)) return { unit: unitOf(x, r.item) };
      const v = num(r.count) - num(r.book); const it = itemOf(x, r.item); const price = it ? num(it.sell_price) : 0;
      if (v !== 0) { const p = num(r.book) > 0 ? Math.abs(v) / num(r.book) * 100 : 100;
        const okPct = pct !== undefined && pct !== null && p <= pct, okMax = max !== undefined && max !== null && Math.abs(v) * price <= max;
        if (okPct || okMax) small++; else { outside++; valueOut += Math.abs(v) * price; } }
      return { unit: unitOf(x, r.item), var: v };
    });
    if ((pct === undefined || pct === null) && (max === undefined || max === null)) needs.push('count_tol_pct', 'count_tol_max');
    if (outside) flags.push(flag('count_variance', 'red', 'গণনার পার্থক্য সীমার বাইরে (আনুমানিক মূল্য)', 'Count variance outside the limit (approx. value)', Math.round(valueOut)));
    else if (small) flags.push(flag('count_variance_small', 'yellow', 'গণনায় ছোট পার্থক্য আছে (সীমার ভেতরে)', 'Small count variance (within the limit)'));
    if (has(x.d.counted_by) && x.d.counted_by === x.d.storekeeper) flags.push(flag('counter_is_storekeeper', 'red', 'স্টোরকিপার নিজেই গণনা করেছেন', 'The storekeeper counted personally'));
    if (has(x.d.witness) && x.d.witness === x.d.counted_by) flags.push(flag('same_witness', 'red', 'গণনাকারী ও সাক্ষী একই জন', 'Counter and witness are the same person'));
    return { v: {}, rows: { rows: out }, flags, needs };
  },
};

/* ============ 14-1 · Daily showroom sheet ============ */
const CATS = [['sweet', L('মিষ্টি', 'Sweets')], ['cake', L('কেক', 'Cake')], ['jalebi', L('জিলাপি', 'Jalebi')], ['doi', L('দই', 'Curd')], ['bakery', L('বেকারি', 'Bakery')], ['ice', L('আইসক্রিম', 'Ice cream')], ['drink', L('পানীয়', 'Drinks')], ['other', L('অন্যান্য', 'Other')]];
const FRIDGES = [1, 2, 3];
const CLOSE_STEPS = [
  ['c1', L('স্টক লেজারে রাতের গণনা — আগে মালামাল, তারপর ক্যাশ', 'Night count in the stock ledger: goods first, then cash')],
  ['c2', L('অর্ডার বোর্ড ও কাস্টমার অর্ডার ফরমের বইয়ের রিকনসিলিয়েশন', 'Order board reconciled with the customer order form book')],
  ['c3', L('ক্যাটাগরি যোগফল = মোট বিক্রয়', 'Category total = total sales')], ['c4', L('প্রত্যাশিত ব্যালেন্স হিসাব', 'Expected balance worked out')],
  ['c5', L('ক্যাশ নোট ধরে গণনা', 'Cash counted by notes')], ['c6', L('সাক্ষীর দ্বিতীয়বার গণনা', "Witness's second count")], ['c7', L('কম/বেশি ও কারণ লেখা', 'Short/over and its reason written')],
  ['c8', L('ক্যাশ হ্যান্ডওভার স্লিপ তৈরি, নং এই শিটে', 'Cash handover slip made, number written here')], ['c9', L('রাখা / সরানো / অপচয় লেখা', 'Kept / removed / wastage written')],
  ['c10', L('মেয়াদ শেষ পণ্য আলাদা রাখা', 'Expired goods set apart')], ['c11', L('অপচয়ে অন্য একজনের অনুমোদন', 'Wastage approved by another person')], ['c12', L('পরদিনের চাহিদা পাঠানো', "Next day's demand sent")],
  ['c13', L('ফ্রিজ / চিলার চালু, বাকি যন্ত্র বন্ধ', 'Fridges / chillers on, other machines off')], ['c14', L('বন্ধের আগে পরিষ্কার, যাচাই অন্য একজনের', 'Cleaned before closing, checked by another person')],
  ['c15', L('গ্যাস, বিদ্যুৎ, আগুন — বন্ধ / নিরাপদ', 'Gas, power, fire — off / safe')], ['c16', L('ক্যাশ কখনো একা অরক্ষিত রাখা হয়নি', 'Cash was never left alone and unprotected')],
];
const moneyFlds = (list) => list.map(([id, l, o]) => M(id, l, o || {}));
B.forms['14-1'] = {
  title: L('দৈনিক শোরুম শিট', 'Daily showroom sheet'),
  head: [CH('day_type', L('দিনের ধরন', 'Day type'), [['normal', L('সাধারণ দিন', 'Normal day')], ['busy', L('ব্যস্ত দিন (Peak)', 'Busy day (Peak)')]], { req: true }),
    CH('shift', L('শিফট', 'Shift'), [['full', L('পুরো দিন', 'Full day')], ['s1', L('শিফট ১', 'Shift 1')], ['s2', L('শিফট ২', 'Shift 2')]]), ST('duty_manager', L('ডিউটি ম্যানেজার', 'Duty manager'), { req: true })],
  sections: [
    { title: L('ক · শোরুম খোলা (Opening)', 'A · Opening'), fields: [
      TM('open_time', L('শাটার খোলার সময়', 'Shutter opening time'), { req: true }),
      CH('safety', L('গ্যাস, বিদ্যুৎ ও আগুনের নিরাপত্তা চেক ঠিক আছে?', 'Gas, power and fire safety check OK?'), YN, { req: true }), T('safety_defect', L('ত্রুটির বিবরণ', 'Defect'), { show: (x) => x.d.safety === 'no', req: (x) => x.d.safety === 'no' }),
      CALC('float_set', L('নির্ধারিত খুচরা (সেটিংস থেকে)', 'Fixed float (from settings)'), 'money'),
      M('open_counted', L('ড্রয়ারে গণনায় প্রাপ্ত খুচরা (গুনে লিখুন)', 'Float counted in the drawer (count, then enter)'), { req: true }),
      CALC('open_diff', L('পার্থক্য', 'Difference'), 'money', { show: cfShow('open_counted') }),
      M('imp_cash', L('ইমপ্রেস্ট — নগদ', 'Imprest — cash')), M('imp_receipts', L('ইমপ্রেস্ট — রসিদ', 'Imprest — receipts')), CALC('imp_text', L('নগদ + রসিদ = নির্ধারিত?', 'Cash + receipts = fixed amount?'), 'text', { show: (x) => !x.cf || has(x.d.imp_cash) }),
      TABLE('fridges', L('ফ্রিজ / চিলার চেক', 'Fridge / chiller check'), [CALC('name', L('ইউনিট', 'Unit'), 'text'), CK('noise', L('শব্দ ঠিক', 'Sound OK')), CK('leak', L('লিকেজ নেই', 'No leak')), CK('cold', L('ঠান্ডা ঠিক', 'Cooling OK')), CK('seal', L('দরজার সিল ঠিক', 'Door seal OK')),
        N('temp', L('তাপমাত্রা °C', 'Temperature °C'), { req: true }), CALC('temp_ok', L('সীমার মধ্যে?', 'Within range?'), 'text')], { rows: FRIDGES.map((i) => L('ইউনিট ' + i, 'Unit ' + i)) }),
      T('fridge_defect', L('ত্রুটির বিবরণ', 'Defect details')),
      T('product_cond', L('পণ্যের অবস্থা — ত্রুটি থাকলে লিখুন', 'Product condition — write any defect')), CK('product_ok', L('ত্রুটি নেই', 'No defect')),
      CH('expired_shown', L('ডিসপ্লেতে মেয়াদ শেষ পণ্য?', 'Expired goods on display?'), [['no', L('না', 'No')], ['yes', L('হ্যাঁ', 'Yes')]], { req: true }),
      CK('expired_removed', L('সরানো হয়েছে', 'Removed'), { show: (x) => x.d.expired_shown === 'yes' }), CK('expired_informed', L('ব্যবস্থাপনাকে জানানো হয়েছে', 'Management informed'), { show: (x) => x.d.expired_shown === 'yes' }),
      ST('key_shutter', L('চাবির দায়িত্বে — শাটার', 'Keys — shutter')), ST('key_drawer', L('চাবির দায়িত্বে — ড্রয়ার', 'Keys — drawer')), ST('key_stock', L('চাবির দায়িত্বে — স্টক-রুম', 'Keys — stock room')),
      T('duties', L('আজকের দায়িত্ব ভাগ (পরিষ্কার, ডিসপ্লে, অর্ডার বোর্ড, ক্যাশ)', "Today's duty split (cleaning, display, order board, cash)")),
      CK('r_pack', L('প্যাকেজিং স্টক', 'Packaging stock')), CK('r_pest', L('পোকামাকড় নিয়ন্ত্রণ', 'Pest control')), CK('r_cobweb', L('মাকড়সার জাল', 'Cobwebs')), CK('r_trays', L('ট্রে ঘোরানো ও সাজানো', 'Trays rotated and arranged')), CK('r_light', L('আলো ও ব্র্যান্ডিং', 'Lights and branding')),
      CK('open_all_ok', L('সব বাধ্যতামূলক ঘর পূরণ ও ঠিক', 'All required boxes filled and correct'), { req: true })] },
    { collapsed: true, title: L('খ · মালামাল গ্রহণ (Goods receipt)', 'B · Goods receipt'), fields: [
      NOTE(L('সাপ্লায়ার বা বাইরের সোর্সিংয়ের মালামালে দাম ও তাঁদের স্বাক্ষর লাগবে; দাম মৌখিক নয়।', 'Goods from suppliers or outside sourcing need the price and their signature; prices are never verbal.'), 'warn'),
      TABLE('receipts', null, [T('challan_no', L('চালান নং', 'Challan no.')), TM('time', L('সময়', 'Time')), SEL('from', L('কোথা থেকে', 'From'), [['factory', L('কারখানা', 'Factory')], ['godown', L('গোডাউন', 'Godown')], ['branch', L('অন্য শাখা', 'Other branch')], ['supplier', L('সাপ্লায়ার', 'Supplier')], ['outside', L('বাইরের সোর্সিং', 'Outside sourcing')]]),
        N('written', L('চালানে লেখা', 'Written on challan')), N('counted', L('গণনায় প্রাপ্ত', 'Counted')), CALC('short', L('ঘাটতি / ড্যামেজ', 'Shortage / damage'), 'num'), D('prod_date', L('উৎপাদন তারিখ', 'Production date')), T('tag', L('ট্যাগ রং', 'Tag colour')), CK('signed', L('দুজনের স্বাক্ষর', 'Both signed'))], { min: 1 })] },
    { collapsed: true, title: L('গ · দিনের মাঝের কাজ (Mid-day)', 'C · Mid-day'), fields: [
      TABLE('clean', L('পরিষ্কার — সম্পাদনকারী ও যাচাইকারী আলাদা জন', 'Cleaning — doer and checker are different people'), [ST('doer', L('সম্পাদনকারী', 'Done by')), ST('verifier', L('যাচাইকারী', 'Checked by')), CK('done', L('সম্পন্ন', 'Done'))], { rows: [L('সকাল', 'Morning'), L('দুপুর', 'Noon'), L('রাত', 'Night')] }),
      CK('disp_open', L('ডিসপ্লে সাজানো (আগের মালামাল সামনে — FIFO): খোলার সময়', 'Display arranged (older stock in front — FIFO): at opening')), CK('disp_peak', L('বড় বিক্রির পর', 'After a big sale')),
      T('sun_move', L('রোদ / গরম থেকে পণ্য সরানো — সময় ও কারণ', 'Goods moved from sun / heat — time and reason')),
      N('t2_1', L('দ্বিতীয়বার তাপমাত্রা ১ °C (ব্যস্ত দিনে)', 'Second temperature 1 °C (busy day)'), { show: (x) => x.d.day_type === 'busy' }), N('t2_2', L('দ্বিতীয়বার তাপমাত্রা ২ °C', 'Second temperature 2 °C'), { show: (x) => x.d.day_type === 'busy' }),
      CK('parcel_check', L('পার্সেল প্যাকিংয়ের আগে মান যাচাই', 'Quality checked before packing parcels')), T('parcel_defect', L('ত্রুটি থাকলে লিখুন', 'Write any defect')),
      TABLE('vouchers', L('দৈনিক খরচ (শুধু ইমপ্রেস্ট থেকে)', 'Daily expenses (from the imprest only)'), [T('v_no', L('ব্যয় ভাউচার নং', 'Expense voucher no.')), T('v_head', L('খাত', 'Head')), M('v_amt', L('টাকা', 'Amount')), CH('v_rec', L('রসিদ', 'Receipt'), YN)], { min: 1 }),
      CALC('v_total', L('মোট খরচ', 'Total expenses'), 'money'), CK('drawer_none', L('ড্রয়ার থেকে কোনো খরচ হয়নি', 'Nothing was spent from the drawer')),
      N('ho_count', L('আজ হ্যান্ডওভার কতবার', 'Handovers today (times)')), T('ho_range', L('শিফট হ্যান্ডওভার রেজিস্টারের ক্র.নং', 'Shift handover register serials')), CK('ho_written', L('প্রতিটি হ্যান্ডওভার ওই রেজিস্টারে লেখা', 'Every handover written in that register')),
      CK('stock_locked', L('স্টক-রুম তালা দেওয়া', 'Stock room locked'))] },
    { collapsed: true, title: L('ঘ · পেন্ডিং অর্ডার বোর্ড', 'D · Pending orders board'), fields: [
      N('orders_taken', L('আজ নেওয়া অর্ডার (টি)', 'Orders taken today')), T('order_range', L('ফরম নং (থেকে — পর্যন্ত)', 'Form no. (from — to)')), N('delivered_n', L('আজ ডেলিভারি (টি)', 'Delivered today')), N('pending_next', L('পরদিনের জন্য বাকি (টি)', 'Pending for tomorrow')),
      M('advance_taken', L('আজ নেওয়া অ্যাডভান্স', 'Advance taken today')), CK('board_recon', L('বোর্ড ও অর্ডার ফরমের বইয়ের রিকনসিলিয়েশন', 'Board and order book reconciled')), CK('board_cleared', L('আজকের সব অর্ডার বোর্ড থেকে মোছা', "Today's orders wiped from the board")),
      T('delivery_orders', L('আজ ডেলিভারি — অর্ডার নং', 'Delivered today — order nos.')), CK('prior_adv_ok', L('(−) আগে নেওয়া অ্যাডভান্স সমন্বয় = ওই অর্ডারগুলোর অ্যাডভান্সের যোগ', 'Prior advance adjusted = sum of those orders\' advances'))] },
    { title: L('ঙ · বিক্রয় ও ক্যাশ ক্লোজিং', 'E · Sales & cash closing'), fields: [
      ...CATS.map(([id, l]) => M('cat_' + id, L(l.bn + ' — বিক্রয়', l.en + ' — sales'))),
      M('total_entered', L('মোট বিক্রয় (বই / মেশিনের মোট)', 'Total sales (book / machine total)'), { req: true }),
      CALC('cat_sum', L('ক্যাটাগরির যোগফল', 'Category total'), 'money'), CALC('cat_match', L('যোগফল = মোট বিক্রয়?', 'Category total = total sales?'), 'text'),
      M('online_sales', L('এর মধ্যে অনলাইন', 'of which online')), M('party_cash', L('পার্টি ও পাইকারি ক্যাশ', 'Party & wholesale cash')), T('party_invoice', L('ইনভয়েস নং', 'Invoice no.')),
      M('goods_based', L('মালামাল থেকে হিসাবের খুচরা বিক্রি (স্টক লেজারের আজকের বিক্রি × মূল্য তালিকা, পার্টি বাদ)', 'Retail sales worked out from goods (stock ledger × price list, minus party)')),
      CALC('retail', L('খুচরা বিক্রয় (মোট − পার্টি ও পাইকারি)', 'Retail sales (total − party & wholesale)'), 'money'), CALC('gm_text', L('মালামাল বনাম টাকা', 'Goods vs money'), 'text', { show: (x) => has(x.d.goods_based) }),
      M('d_bkash', L('ডিজিটাল — বিকাশ', 'Digital — bKash')), M('d_nagad', L('ডিজিটাল — নগদ (Nagad)', 'Digital — Nagad')), M('d_card', L('ডিজিটাল — কার্ড', 'Digital — card')), M('d_bank', L('ডিজিটাল — ব্যাংক', 'Digital — bank')), M('d_other', L('ডিজিটাল — অন্য', 'Digital — other')),
      CALC('d_total', L('মোট ডিজিটাল', 'Total digital'), 'money'), CK('d_phone', L('ব্যবসার ফোন / মেশিনে দেখা হয়েছে', 'Checked on the business phone / machine'), { req: true }), CK('d_nopersonal', L('ব্যক্তিগত নম্বরে কোনো লেনদেন হয়নি', 'No transaction on a personal number'), { req: true }),
      M('dues', L('পূর্বের বকেয়া আদায়', 'Earlier dues collected')), M('new_adv', L('নতুন অর্ডারের অ্যাডভান্স', 'Advance on new orders')), M('prior_adv', L('(−) পূর্বের অ্যাডভান্স সমন্বয়', '(−) Earlier advance adjusted')),
      N('disc_n', L('ডিসকাউন্ট (টি)', 'Discounts (no.)')), M('disc_amt', L('ডিসকাউন্ট ৳ (তথ্য)', 'Discount ৳ (info)')), N('cancel_n', L('বাতিল বিক্রয় (টি)', 'Cancelled sales (no.)')),
      M('refund', L('(−) রিফান্ড', '(−) Refund')), T('refund_ref', L('রিটার্ন ও অভিযোগ রেজিস্টার নং', 'Return & complaint register no.'), { show: (x) => num(x.d.refund) > 0 }),
      M('credit_sales', L('(−) আজ বাকিতে বিক্রি', '(−) Sold on credit today')), T('credit_memo', L('মেমো নং', 'Memo no.'), { show: (x) => num(x.d.credit_sales) > 0 }),
      M('midday_hub', L('(−) দিনের মাঝে হাবে পাঠানো', '(−) Sent to the hub during the day')), T('midday_slip', L('ক্যাশ হ্যান্ডওভার স্লিপ নং', 'Cash handover slip no.'), { show: (x) => num(x.d.midday_hub) > 0 }),
      M('rounding', L('± রাউন্ডিং', '± Rounding'), { hint: L('কম হলে মাইনাস চিহ্ন দিন', 'Use a minus sign for less') }),
      DEN('cash_count', L('ক্যাশ নোট ধরে গণনা — আগে গুনুন', 'Cash counted by notes — count first'), { req: true }),
      CALC('counted_total', L('গণনায় প্রাপ্ত মোট', 'Counted total'), 'money'),
      CALC('expected', L('প্রত্যাশিত ড্রয়ার ব্যালেন্স', 'Expected drawer balance'), 'money', { show: (x) => !x.cf || x.den('cash_count') > 0 }),
      CALC('short_over', L('কম / বেশি (গণনা − প্রত্যাশিত)', 'Short / over (count − expected)'), 'money', { big: true, show: (x) => !x.cf || x.den('cash_count') > 0 }),
      TA('so_reason', L('কম/বেশির কারণ (শূন্য হলেও যাচাই)', 'Reason for short/over'), { show: (x) => x.v.so_nonzero, req: (x) => x.v.so_nonzero }),
      ST('witness', L('দ্বিতীয়বার গণনা — সাক্ষী', 'Second count — witness'), { req: (x) => !x.pin, show: (x) => !x.pin }), M('second_count', L('সাক্ষীর গণনায় প্রাপ্ত', "Witness's counted total"), { req: true }),
      M('leave_float', L('পরদিনের জন্য রেখে যাওয়া খুচরা', 'Float left for tomorrow'), { req: true }),
      CALC('hub_deposit', L('হাবে জমা = গণনায় প্রাপ্ত − রেখে যাওয়া', 'Hub deposit = counted − float left'), 'money', { big: true }),
      T('slip_no', L('ক্যাশ হ্যান্ডওভার স্লিপ নং', 'Cash handover slip no.')), CK('counterfoil', L('কাউন্টারফয়েল বইয়ে আছে', 'Counterfoil is in the book')), T('carrier', L('বহনকারী', 'Carrier')), TM('carry_time', L('সময়', 'Time'))] },
    { collapsed: true, title: L('চ · সমাপনী স্টক', 'F · Closing stock'), fields: [
      TABLE('stock', null, [T('kept', L('পরদিনের জন্য রাখা (পরিমাণ · রং)', 'Kept for tomorrow (qty · colour)')), N('exp_qty', L('মেয়াদ শেষ / প্রায় শেষ — পরিমাণ', 'Expired / near expiry — qty')), M('exp_amt', L('— মূল্য', '— value')),
        N('waste_qty', L('অপচয় — পরিমাণ', 'Wastage — qty')), T('waste_reason', L('অপচয়ের কারণ', 'Wastage reason')), ST('waste_by', L('অপচয়ের অনুমোদনকারী', 'Wastage approved by'), { req: (x) => num(x.row.waste_qty) > 0, show: (x) => num(x.row.waste_qty) > 0 }),
        T('ret_challan', L('কারখানায় ফেরত (চালান নং)', 'Returned to factory (challan no.)'))], { rows: [L('মিষ্টি', 'Sweets'), L('কেক', 'Cake'), L('জিলাপি / দই', 'Jalebi / curd'), L('বেকারি / অন্য', 'Bakery / other')] }),
      CK('exp_apart', L('মেয়াদ শেষ পণ্য আলাদা রাখা', 'Expired goods set apart')),
      T('own_use', L('বিক্রি ছাড়া ইস্যু — নিজস্ব ব্যবহার ও উপহার: পণ্য · পরিমাণ · মূল্য', 'Non-sale issue — own use & gifts: item · qty · value')), ST('own_use_by', L('গ্রহণকারী', 'Received by')),
      T('staff_credit', L('স্টাফ বাকি', 'Staff credit')), T('staff_adv_page', L('স্টাফ অ্যাডভান্স রেজিস্টারের পাতা নং', 'Staff advance register page')), T('sample', L('ব্যবসার উপহার বা স্যাম্পল', 'Business gift or sample')), ST('sample_by', L('অনুমোদনকারী', 'Approved by'))] },
    { collapsed: true, title: L('ছ · পরদিনের চাহিদা', 'G · Demand for tomorrow'), fields: [
      TABLE('demand', null, [ITEM('item', L('আইটেম', 'Item'), { wide: true }), N('qty', L('চাহিদা (আজ রাতে)', 'Demand (tonight)')), T('note', L('মন্তব্য', 'Remark'))], { min: 5 }),
      N('box_bag', L('বক্স / ব্যাগ / প্যাকেট', 'Boxes / bags / packets')), T('direct_buy', L('সরাসরি ক্রয় — পানীয়, পানি, আইসক্রিম, অন্য', 'Direct purchase — drinks, water, ice cream, other')), T('pr_no', L('পারচেজ রিকুইজিশন (PR) নং', 'Purchase Requisition (PR) no.'))] },
    { title: L('জ · ক্লোজিং চেকলিস্ট (১৬ ধাপ, সবগুলো বাধ্যতামূলক)', 'H · Closing checklist (16 steps, all required)'), fields: [
      ...CLOSE_STEPS.map(([id, l]) => CK(id, l, { req: true })),
      N('end_temp', L('শেষ তাপমাত্রা °C', 'Closing temperature °C')), ST('key_to', L('চাবি দেওয়া হলো', 'Keys handed to')), TM('shutter_time', L('শাটার বন্ধ', 'Shutter closed'))] },
    { collapsed: true, title: L('ঝ · গরমিল, ঘটনা ও মেরামত', 'I · Exceptions, incidents & repairs'), fields: [
      TABLE('incidents', null, [T('what', L('ঘটনা বা মেরামতের অনুরোধ', 'Incident or repair request'), { wide: true }), CH('urgency', L('ধরন', 'Type'), [['urgent', L('জরুরি', 'Urgent')], ['routine', L('রুটিন', 'Routine')]]), T('why', L('কারণ', 'Reason')), T('owner', L('দায়িত্বে', 'Responsible')), T('action', L('গৃহীত ব্যবস্থা', 'Action taken'), { wide: true }), CK('solved', L('সমাধান', 'Solved'))], { min: 1 }),
      CK('no_incident', L('কোনো ঘটনা না ঘটলে এখানে টিক', 'Tick if nothing happened'))] },
    { title: L('স্বাক্ষর', 'Signatures'), fields: [ST('second_sig', L('দ্বিতীয় স্বাক্ষর — ব্যাকআপ ম্যানেজার / সাক্ষী', 'Second signature — backup manager / witness'), { req: (x) => !x.pin, show: (x) => !x.pin })] },
    { who: 'checker', title: L('হাবে গ্রহণ (হাব পূরণ করবে)', 'Received at the hub (hub fills)'), fields: [
      T('hub_ledger', L('ক্যাশ ও ব্যাংক লেজারের তারিখ ও লাইন নং', 'Cash & bank ledger date and line no.'), { who: 'checker', req: true }), TM('hub_time', L('সময়', 'Time'), { who: 'checker' }), CK('hub_received', L('হাবে ক্যাশ ও শিট গ্রহণ করা হয়েছে', 'Cash and sheet received at the hub'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const sv = (k) => (x.s[k] === undefined || x.s[k] === null ? null : x.s[k]);
    // opening float and imprest
    const fl = sv('drawer_float'); v.float_set = fl === null ? NEED : fl;
    if (fl === null) needs.push('drawer_float');
    if (has(d.open_counted) && fl !== null) { v.open_diff = num(d.open_counted) - fl; if (v.open_diff !== 0) flags.push(flag('open_float_diff', 'red', 'খোলার সময় ড্রয়ারের খুচরা নির্ধারিতের সমান নয়', 'Opening drawer float differs from the fixed float', v.open_diff)); }
    const imp = sv('imprest'); if (imp === null) { needs.push('imprest'); v.imp_text = NEED; }
    else if (has(d.imp_cash)) { const df = num(d.imp_cash) + num(d.imp_receipts) - imp; v.imp_text = diffText(df); if (df !== 0) flags.push(flag('open_imprest_diff', 'red', 'ইমপ্রেস্টের নগদ + রসিদ নির্ধারিতের সমান নয়', 'Imprest cash + receipts differ from the fixed amount', df)); }
    // fridges
    const fr = x.rows('fridges'), frOut = FRIDGES.map((i, k) => { const r = fr[k] || {}, min = sv('fridge' + i + '_min'), max = sv('fridge' + i + '_max'), name = x.s['fridge' + i + '_name'];
      let ok = NEED; if (has(r.temp)) { if (min === null || max === null) { needs.push('fridge' + i + '_min', 'fridge' + i + '_max'); } else { const tt = num(r.temp), good = tt >= min && tt <= max; ok = good ? L('সীমার মধ্যে ✓', 'In range ✓') : L('সীমার বাইরে', 'Outside the limit'); if (!good) flags.push(flag('temp_out_' + i, 'red', 'ফ্রিজ ' + i + ' এর তাপমাত্রা সীমার বাইরে', 'Fridge ' + i + ' temperature out of range', tt, { unit: 'qty' })); } }
      return { name: name || L('ইউনিট ' + i, 'Unit ' + i), temp_ok: ok }; });
    // goods receipt
    const rc = x.rows('receipts'), rcOut = rc.map((r) => ({ short: has(r.counted) && has(r.written) ? num(r.written) - num(r.counted) : undefined }));
    const rshort = sum(rcOut.map((r) => Math.max(0, r.short || 0))); if (rshort > 0) flags.push(flag('receipt_short', 'yellow', 'মালামাল গ্রহণে ঘাটতি / ড্যামেজ', 'Shortage / damage on goods received', rshort, { unit: 'qty' }));
    // cleaning
    if (x.rows('clean').some((r) => has(r.doer) && r.doer === r.verifier)) flags.push(flag('same_person_cleaning', 'yellow', 'পরিষ্কারে সম্পাদনকারী ও যাচাইকারী একই জন', 'Cleaning doer and checker are the same person'));
    v.v_total = sum(x.rows('vouchers').map((r) => r.v_amt));
    // sales
    const catSum = sum(CATS.map(([id]) => d['cat_' + id])); v.cat_sum = catSum;
    if (has(d.total_entered)) { const df = catSum - num(d.total_entered); v.cat_match = df === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('অমিল ৳ ' + fm(df), 'Mismatch ৳ ' + fm(df)); if (df !== 0) flags.push(flag('cat_total_mismatch', 'red', 'ক্যাটাগরির যোগফল মোট বিক্রয়ের সমান নয়', 'Category total differs from total sales', df)); } else v.cat_match = '';
    const total = num(d.total_entered), retail = total - num(d.party_cash); v.retail = retail;
    if (has(d.goods_based)) { const gd = num(d.goods_based) - retail, pct = sv('goods_money_tol_pct'), mx = sv('goods_money_tol_max'); let lvl = null;
      if (gd !== 0) { const okP = pct !== null && retail > 0 && Math.abs(gd) / retail * 100 <= pct, okM = mx !== null && Math.abs(gd) <= mx; lvl = okP || okM ? 'yellow' : 'red'; if (pct === null && mx === null) needs.push('goods_money_tol_pct', 'goods_money_tol_max'); }
      v.gm_text = gd === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('পার্থক্য ৳ ' + fm(gd), 'Difference ৳ ' + fm(gd)); if (lvl) flags.push(flag('goods_money_gap', lvl, 'মালামাল বনাম টাকায় পার্থক্য', 'Goods vs money gap', gd)); }
    v.d_total = sum(['d_bkash', 'd_nagad', 'd_card', 'd_bank', 'd_other'].map((k) => d[k]));
    // expected drawer balance (Guidebook G.6, equation 1)
    const openF = has(d.open_counted) ? num(d.open_counted) : (fl === null ? 0 : fl);
    const expected = openF + total - v.d_total + num(d.dues) + num(d.new_adv) - num(d.prior_adv) - num(d.refund) - num(d.credit_sales) - num(d.midday_hub) + num(d.rounding);
    const counted = x.den('cash_count'); v.counted_total = counted; v.expected = expected;
    if (counted > 0) { const so = counted - expected; v.short_over = so; v.so_nonzero = so !== 0; const lvl = tol(so, sv('cash_tol')); if (sv('cash_tol') === null) needs.push('cash_tol'); if (lvl) flags.push(flag('cash_short_over', lvl, so < 0 ? 'ক্যাশ কম' : 'ক্যাশ বেশি', so < 0 ? 'Cash short' : 'Cash over', so)); }
    if (has(d.second_count) && counted > 0 && num(d.second_count) !== counted) flags.push(flag('second_count_mismatch', 'red', 'সাক্ষীর গণনা প্রথম গণনার সমান নয়', "Witness count differs from the first count", num(d.second_count) - counted));
    if (has(d.witness) && d.witness === x.me) flags.push(flag('witness_is_maker', 'red', 'সাক্ষী ও লেখক একই জন', 'Witness and sheet writer are the same person'));
    v.hub_deposit = counted - num(d.leave_float);
    if (has(d.leave_float) && fl !== null && num(d.leave_float) !== fl) flags.push(flag('float_left_diff', 'yellow', 'রেখে যাওয়া খুচরা নির্ধারিত খুচরার সমান নয়', 'Float left differs from the fixed float', num(d.leave_float) - fl));
    // stock: wastage approval and expiry loss
    const st = x.rows('stock'); if (st.some((r) => num(r.waste_qty) > 0 && has(r.waste_by) && r.waste_by === x.me)) flags.push(flag('self_waste_approval', 'red', 'অপচয় নিজে অনুমোদন করা হয়েছে', 'Wastage approved by the writer', undefined));
    const expv = sum(st.map((r) => r.exp_amt)); if (expv > 0) flags.push(flag('expired_loss', 'yellow', 'মেয়াদ শেষ পণ্যের ক্ষতি', 'Loss on expired goods', expv));
    if (d.second_sig && d.second_sig === x.me) flags.push(flag('second_sig_is_maker', 'red', 'দ্বিতীয় স্বাক্ষর ও লেখক একই জন', 'Second signature and writer are the same person'));
    return { v, rows: { fridges: frOut, receipts: rcOut }, flags, needs: [...new Set(needs)] };
  },
};
})();
