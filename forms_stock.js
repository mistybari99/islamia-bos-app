/* Islamia BOS · stock and purchase forms (batch A), taken field by field from the BOS Build Kit v1.39.
   13-1 Goods received note · 18-1 Material issue slip · 37-1 Store ledger · 28-1 Purchase requisition · 29-1 Quotation comparison
   27-1 Purchase order · 02-1 Bill check & payment request · 38-1 Supplier ledger.
   Every limit comes from Location Settings; nothing is invented. A missing setting is reported as "data needed". */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO, SUP } = B.f;
B.forms = B.forms || {};

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const UNITS = { kg: L('কেজি', 'KG'), pc: L('পিস', 'Piece'), lb: L('পাউন্ড', 'Pound') };
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const itemOf = (x, code) => (x.env.byCode && x.env.byCode.get(code)) || null;
const unitOf = (x, code) => { const it = itemOf(x, code); return it ? (UNITS[it.unit] || L(it.unit || '', it.unit || '')) : ''; };
const NEED = L('তথ্য লাগবে', 'Data needed');
const sv = (x, k) => (x.s[k] === undefined || x.s[k] === null ? null : x.s[k]);
const hasN = (v) => has(v) && v !== '0' && num(v) !== 0;
// tolerance: zero is fine; inside the limit is yellow; outside (or no limit written) is red
function tol(diff, limit) { if (diff === 0) return null; if (limit === null || limit === undefined) return 'red'; return Math.abs(diff) <= limit ? 'yellow' : 'red'; }
const diffText = (d) => (d === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('পার্থক্য ৳ ' + fm(d), 'Difference ৳ ' + fm(d)));

// payment ways (kit: cash · credit · bank · mobile · owner's personal money · other)
const PAYS = [['cash', L('নগদ', 'Cash')], ['credit', L('বাকি', 'On credit')], ['bank', L('ব্যাংক', 'Bank')], ['mobile', L('মোবাইল', 'Mobile')], ['owner', L('মালিকের ব্যক্তিগত', "Owner's personal money")], ['other', L('অন্য', 'Other')]];
const SHIFTS = [['m', L('সকাল', 'Morning')], ['a', L('বিকাল', 'Afternoon')], ['n', L('রাত', 'Night')]];
const OWNER_NOTE = L('মালিকের ব্যক্তিগত টাকায় দিলে ক্যাশ ও ব্যাংক লেজারে একই দিনে দুই দিকে এন্ট্রি হবে।', "If paid from the owner's personal money, the cash & bank ledger gets both sides written on the same day.");

/* ============ 13-1 · Goods received note (GRN) ============ */
const QUALITY = [['accept', L('গ্রহণ', 'Accept')], ['reduced', L('দর কমিয়ে গ্রহণ', 'Accept at a lower rate')], ['hold', L('আটক', 'Hold')], ['return', L('ফেরত', 'Return')]];
B.forms['13-1'] = {
  title: L('মালামাল গ্রহণ (GRN)', 'Goods Received (GRN)'),
  head: [TM('time', L('সময়', 'Time')), SUP('supplier', L('সাপ্লায়ার', 'Supplier'), { req: true }), T('memo_no', L('তাদের মেমো / চালান নং', 'Their memo / challan no.')),
    CH('paper', L('যে কাগজে ক্রয়', 'Purchase made on'), [['po', L('পারচেজ অর্ডার (PO)', 'Purchase order (PO)')], ['pr', L('জরুরি ক্রয় — পারচেজ রিকুইজিশন (PR)', 'Urgent purchase — purchase requisition (PR)')], ['direct', L('শোরুমে সরাসরি ক্রয়', 'Direct purchase at the showroom')]], { req: true }),
    T('po_no', L('পারচেজ অর্ডার (PO) নং', 'Purchase order (PO) no.'), { show: (x) => x.d.paper === 'po', req: (x) => x.d.paper === 'po' }),
    T('pr_no', L('পারচেজ রিকুইজিশন (PR) নং', 'Purchase Requisition (PR) no.'), { show: (x) => x.d.paper === 'pr', req: (x) => x.d.paper === 'pr' })],
  sections: [
    { title: L('পারচেজ অর্ডারের অগ্রগতি', 'Purchase order progress'), show: (x) => x.d.paper === 'po', fields: [
      N('po_prev', L('এই পারচেজ অর্ডারে আগে প্রাপ্ত', 'Received earlier on this PO')), N('po_today', L('আজ প্রাপ্ত', 'Received today')), N('po_rest', L('বাকি', 'Remaining')),
      CK('po_last', L('শেষ ডেলিভারি', 'Last delivery'))] },
    { title: L('মালামাল (গণনা / ওজন)', 'Goods (count / weight)'), fields: [
      NOTE(L('গণনা বা ওজন হবে গ্রহণকারীর নিজের হাতে, সাপ্লায়ারের উপস্থিতিতে। মেমোর সংখ্যা “গণনা / পরিমাপে প্রাপ্ত” ঘরে লেখা যাবে না। দর সাপ্লায়ারের বিল থেকে নিতে হবে — মৌখিক তথ্য থেকে নয়।',
        'Counting or weighing is done by the receiver personally, in front of the supplier. The memo figure must not be written in the “Counted / measured” box. The rate comes from the supplier bill, never from a verbal figure.'), 'warn'),
      CK('scale_checked', L('পাল্লা আজ পরীক্ষিত', 'Scale checked today'), { req: true }),
      TABLE('lines', null, [ITEM('item', L('আইটেম', 'Item'), { req: true, wide: true }), CALC('unit', L('একক', 'Unit'), 'text'),
        N('memo', L('মেমোতে লেখা', 'Written on the memo'), { show: (x) => !x.sbMemo }), N('counted', L('গণনা / পরিমাপে প্রাপ্ত', 'Counted / measured'), { req: true }),
        CALC('var', L('পার্থক্য (প্রাপ্ত − মেমো)', 'Variance (received − memo)'), 'num', { show: (x) => has(x.row.counted) && has(x.row.memo) }),
        M('rate', L('দর ৳ (বিল অনুযায়ী)', 'Rate ৳ (as per the bill)')), CALC('amt', L('মোট ৳', 'Total ৳'), 'money', { show: (x) => has(x.row.counted) && has(x.row.rate) }),
        SEL('quality', L('মান যাচাই', 'Quality check'), QUALITY, { req: true }), T('remark', L('মন্তব্য', 'Remark'), { wide: true })], { min: 3 }),
      CALC('t_memo', L('মোট — মেমোতে লেখা', 'Total — on the memo'), 'num'), CALC('t_count', L('মোট — গণনায় প্রাপ্ত', 'Total — counted'), 'num'),
      CALC('t_var', L('মোট পার্থক্য', 'Total variance'), 'num'), CALC('t_amt', L('সর্বমোট ৳', 'Grand total ৳'), 'money', { big: true })] },
    { title: L('মান যাচাই ও স্টোর লেজার', 'Quality check & store ledger'), fields: [
      CK('qc_all', L('সব লাইনে মান যাচাই হয়েছে', 'Quality checked on every line'), { req: true }),
      NOTE(L('দর কমিয়ে গ্রহণ হলে নতুন দর ও অনুমোদনকারীর নাম লিখতে হবে; অনুমোদনকারী গ্রহণকারী হতে পারবেন না।', 'For “accept at a lower rate”, write the new rate and the approver; the approver cannot be the receiver.'), 'ok', { show: (x) => x.v.has_reduced }),
      M('new_rate', L('নতুন দর ৳', 'New rate ৳'), { show: (x) => x.v.has_reduced, req: (x) => x.v.has_reduced }),
      ST('rate_approver', L('অনুমোদনকারী (Approved by) (গ্রহণকারী নন)', 'Approved by (not the receiver)'), { show: (x) => x.v.has_reduced, req: (x) => x.v.has_reduced }),
      CK('rate_phone', L('ফোনে অনুমোদন', 'Approved by phone'), { show: (x) => x.v.has_reduced }),
      CK('held_apart', L('আটক মালামাল আলাদা রাখা হয়েছে', 'Held goods are kept apart'), { show: (x) => x.v.has_hold, req: (x) => x.v.has_hold }),
      NOTE(L('আটক মালামাল উৎপাদনে যাবে না।', 'Held goods must not go into production.'), 'warn', { show: (x) => x.v.has_hold }),
      CK('posted', L('স্টোর লেজারে এন্ট্রি (Posting) করা হয়েছে', 'Posted in the store ledger')), T('ledger_ref', L('পাতা / লাইন নং', 'Page / line no.'))] },
    { title: L('পেমেন্ট', 'Payment'), fields: [
      CH('pay', L('পেমেন্ট', 'Payment'), PAYS, { req: true }), T('pay_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.pay === 'other', req: (x) => x.d.pay === 'other' }),
      M('cash_amount', L('নগদ হলে ৳', 'Cash amount ৳'), { show: (x) => x.d.pay === 'cash', req: (x) => x.d.pay === 'cash' }),
      NOTE(OWNER_NOTE, 'warn', { show: (x) => x.d.pay === 'owner' }),
      D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date'), { show: (x) => has(x.d.pay) && x.d.pay !== 'credit' }),
      T('ledger_line', L('লেজারের লাইন নং', 'Ledger line no.'), { show: (x) => has(x.d.pay) && x.d.pay !== 'credit' })] },
    { title: L('ছবি ও সই', 'Photos & signatures'), fields: [
      PHOTO('photos', L('মালামাল / মেমো / বিলের ছবি', 'Photos of goods / memo / bill')),
      T('carrier', L('সাপ্লায়ার / বহনকারী (Supplier / Carrier) — নাম', 'Supplier / carrier — name')),
      ST('receiver', L('গ্রহণকারী (Received by)', 'Received by'))] },
    { who: 'checker', title: L('যাচাই (ব্যবস্থাপনা পূরণ করবে)', 'Check (management fills)'), fields: [
      CK('mgmt_checked', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা: রসিদ যাচাই করেছি', 'Checked by management: receipt checked'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    const out = rows.map((r) => { const hasC = has(r.counted);
      return { unit: unitOf(x, r.item), var: hasC && has(r.memo) ? num(r.counted) - num(r.memo) : undefined, amt: hasC && has(r.rate) ? num(r.counted) * num(r.rate) : undefined }; });
    v.t_memo = sum(rows.map((r) => r.memo)); v.t_count = sum(rows.map((r) => r.counted));
    v.t_var = sum(out.map((o) => o.var)); v.t_amt = sum(out.map((o) => o.amt));
    v.has_reduced = rows.some((r) => r.quality === 'reduced'); v.has_hold = rows.some((r) => r.quality === 'hold');
    const short = sum(rows.map((r) => (has(r.counted) && has(r.memo) ? Math.max(0, num(r.memo) - num(r.counted)) : 0)));
    const excess = sum(rows.map((r) => (has(r.counted) && has(r.memo) ? Math.max(0, num(r.counted) - num(r.memo)) : 0)));
    if (short > 0) flags.push(flag('grn_short', 'yellow', 'মেমোর চেয়ে কম পাওয়া গেছে — সেদিনই সাপ্লায়ারের ডেবিট নোট ও বহনকারীর সই', 'Received less than the memo: debit note and carrier signature the same day', short, { unit: 'qty' }));
    if (excess > 0) flags.push(flag('grn_excess', 'yellow', 'মেমোর চেয়ে বেশি পাওয়া গেছে', 'Received more than the memo', excess, { unit: 'qty' }));
    const val = (q) => sum(rows.map((r) => (r.quality === q && has(r.counted) && has(r.rate) ? num(r.counted) * num(r.rate) : 0)));
    if (v.has_hold) { flags.push(flag('grn_hold', 'yellow', 'মালামাল আটক রাখা হয়েছে', 'Goods held back', val('hold') || undefined)); if (!x.d.held_apart) flags.push(flag('hold_not_apart', 'red', 'আটক মালামাল আলাদা রাখা হয়নি', 'Held goods are not kept apart', undefined)); }
    if (rows.some((r) => r.quality === 'return')) flags.push(flag('grn_return', 'yellow', 'মালামাল ফেরত যাচ্ছে', 'Goods going back to the supplier', val('return') || undefined));
    if (v.has_reduced) { flags.push(flag('grn_reduced', 'yellow', 'দর কমিয়ে গ্রহণ', 'Accepted at a lower rate', val('reduced') || undefined));
      if (has(x.d.rate_approver) && has(x.d.receiver) && x.d.rate_approver === x.d.receiver) flags.push(flag('rate_approver_is_receiver', 'red', 'দর কমানোর অনুমোদনকারী ও গ্রহণকারী একই জন', 'The rate approver and the receiver are the same person', undefined)); }
    if (rows.some((r) => has(r.counted) && !has(r.rate))) flags.push(flag('grn_rate_missing', 'yellow', 'কিছু লাইনে বিল অনুযায়ী দর লেখা নেই — বিল যাচাই করা যাবে না', 'Some lines have no bill rate, so the bill check is impossible', undefined));
    return { v, rows: { lines: out }, flags, needs };
  },
};

/* ============ 18-1 · Material issue slip ============ */
const PURPOSE = [['prod', L('উৎপাদনের জন্য', 'For production')], ['staff', L('স্টাফ / ব্যক্তিগত ব্যবহারে', 'Staff / personal use')], ['sample', L('স্যাম্পল', 'Sample')], ['trial', L('ট্রায়াল (নতুন পণ্য)', 'Trial (new product)')]];
B.forms['18-1'] = {
  title: L('মালামাল ইস্যু', 'Material Issue'),
  head: [CH('shift', L('শিফট', 'Shift'), SHIFTS), T('batch_no', L('ব্যাচ / ক্রম নং', 'Batch / serial no.')), T('product', L('তৈরির পণ্য', 'Product being made')),
    CH('purpose', L('ইস্যুর উদ্দেশ্য', 'Purpose of the issue'), PURPOSE, { req: true })],
  sections: [
    { title: L('ইস্যু', 'Issue'), fields: [
      NOTE(L('প্রতিটি কাঁচামাল ওজন করে ইস্যু হবে — অনুমানে নয়। উৎপাদন ছাড়া অন্য কোনো কারণে মালামাল ইস্যু হলেও এই স্লিপে লিখতে হবে। স্টাফ বা ব্যক্তিগত ব্যবহারে গেলে মূল্য ধরে বেতন থেকে কর্তন হবে।',
        'Every raw material is issued by weight, never by guess. Issues for any reason other than production must also be written on this slip. If it goes to staff or personal use, its value is deducted from salary.'), 'warn'),
      TABLE('lines', null, [ITEM('item', L('আইটেম', 'Item'), { req: true, wide: true }), CALC('unit', L('একক', 'Unit'), 'text'),
        N('issued', L('ইস্যু — ওজন', 'Issued — weight'), { req: true }), N('ret', L('একই দিনে ফেরত', 'Returned the same day')),
        CALC('net', L('নিট ব্যবহার', 'Net use'), 'num', { show: (x) => has(x.row.issued) }), T('reason', L('কারণ / মন্তব্য', 'Reason / remark'), { wide: true })], { min: 3 }),
      CALC('t_issued', L('সর্বমোট ইস্যু', 'Total issued'), 'num'), CALC('t_ret', L('সর্বমোট ফেরত', 'Total returned'), 'num'), CALC('t_net', L('সর্বমোট নিট ব্যবহার', 'Total net use'), 'num', { big: true })] },
    { title: L('একই দিনে ফেরত', 'Same-day return'), fields: [
      CK('ret_same_day', L('অব্যবহৃত মালামাল একই দিনে ফেরত', 'Unused goods returned the same day'), { req: (x) => x.v.has_return }),
      TM('ret_time', L('ফেরতের সময়', 'Time of return'), { show: (x) => x.v.has_return }),
      ST('ret_weigher', L('ফেরত ওজনকারী (Return weighed by) — গোডাউন ইনচার্জ', 'Return weighed by — godown in-charge'), { show: (x) => x.v.has_return, req: (x) => x.v.has_return }),
      CK('not_overnight', L('রাতে কারখানায় রাখা হয়নি', 'Not kept in the factory overnight')),
      NOTE(L('রাখা হলে পুরোটাই ব্যবহৃত ধরা হবে। (টিক না দিলে ফেরত গণ্য হবে না; নিট ব্যবহার = ইস্যু।)', 'If kept overnight, the whole quantity counts as used. (Without the tick, returns do not count: net use = issued.)'), 'warn'),
      M('staff_value', L('স্টাফ / ব্যক্তিগত হলে — মূল্য ৳', 'Staff / personal — value ৳'), { show: (x) => x.d.purpose === 'staff' }),
      CK('deducted', L('বেতন থেকে কর্তন', 'Deducted from salary'), { show: (x) => x.d.purpose === 'staff', req: (x) => x.d.purpose === 'staff' })] },
    { title: L('উৎপাদন ও লেজারের সাথে যোগ', 'Link to production & ledger'), fields: [
      CK('net_to_report', L('এই স্লিপের নিট ব্যবহারের সংখ্যা উৎপাদন রিপোর্টের ইনপুট ঘরে হুবহু লিখতে হবে', "This slip's net use must be written exactly in the production report input box"), { req: true }),
      T('report_batch', L('উৎপাদন রিপোর্টের ব্যাচ / ক্রম নং', 'Production report batch / serial no.')), T('ledger_ref', L('স্টোর লেজারের পাতা / লাইন নং', 'Store ledger page / line no.'))] },
    { who: 'checker', title: L('গ্রহণ (উৎপাদন পূরণ করবে)', 'Receipt (production fills)'), fields: [
      ST('received_by', L('গ্রহণকারী (Received by) — কারিগর / উৎপাদন', 'Received by — artisan / production'), { who: 'checker', req: true }),
      ST('ret_received_by', L('ফেরত গ্রহণকারী (Return received by)', 'Return received by'), { who: 'checker', show: (x) => x.v.has_return }),
      CK('received_ok', L('ওজন করা মালামাল বুঝে পেয়েছি', 'Received the weighed goods'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], v = {};
    const kept = !x.d.not_overnight; // paper: if kept overnight, the whole quantity counts as used
    const out = rows.map((r) => ({ unit: unitOf(x, r.item), net: has(r.issued) ? num(r.issued) - (kept ? 0 : num(r.ret)) : undefined }));
    v.t_issued = sum(rows.map((r) => r.issued)); v.t_ret = sum(rows.map((r) => r.ret)); v.t_net = kept ? v.t_issued : v.t_issued - v.t_ret; v.has_return = v.t_ret > 0;
    if (v.has_return && kept) flags.push(flag('kept_overnight', 'yellow', 'ফেরত লেখা আছে কিন্তু “রাতে রাখা হয়নি” টিক নেই — পুরোটাই ব্যবহৃত ধরা হলো', 'A return is written but “not kept overnight” is not ticked: the whole quantity counts as used', v.t_ret, { unit: 'qty' }));
    if (rows.some((r) => num(r.ret) > num(r.issued))) flags.push(flag('return_exceeds', 'red', 'ফেরত ইস্যুর চেয়ে বেশি', 'Returned more than was issued', undefined));
    if (x.d.purpose === 'staff') { flags.push(flag('issue_staff', 'yellow', 'স্টাফ / ব্যক্তিগত ব্যবহারে ইস্যু — বেতন থেকে কর্তন', 'Issued for staff / personal use: salary deduction', has(x.d.staff_value) ? num(x.d.staff_value) : undefined));
      if (!has(x.d.staff_value)) flags.push(flag('staff_value_missing', 'yellow', 'স্টাফ / ব্যক্তিগত ইস্যুর মূল্য লেখা নেই', 'Value of the staff / personal issue is not written', undefined)); }
    else if (x.d.purpose === 'sample' || x.d.purpose === 'trial') flags.push(flag('issue_non_production', 'yellow', 'উৎপাদন ছাড়া অন্য কারণে ইস্যু', 'Issued for a reason other than production', undefined));
    return { v, rows: { lines: out }, flags, needs: [] };
  },
};

/* ============ 37-1 · Store ledger (one page per item) ============ */
const OTHER_PAPERS = [['return', L('ফেরত', 'Return')], ['count_adj', L('কাউন্টের সমন্বয়', 'Count adjustment')], ['other', L('অন্য', 'Other')]];
B.forms['37-1'] = {
  title: L('স্টোর লেজার', 'Store Ledger'),
  head: [ITEM('item', L('আইটেম কোড / নাম', 'Item code / name'), { req: true, wide: true }), CALC('unit', L('একক (Unit)', 'Unit'), 'text'),
    T('bin', L('বিন লোকেশন (Bin Location — তাক / জায়গা)', 'Bin location (shelf / place)')), ST('storekeeper', L('স্টোরকিপার (ডিউটি স্লট)', 'Storekeeper (duty slot)'), { req: true }),
    N('opening', L('আগের পাতার বাকি (Opening)', 'Balance from the previous page (opening)'))],
  sections: [
    { title: L('লেনদেন', 'Entries'), fields: [
      NOTE(L('প্রতিটি প্রাপ্তি ও ইস্যু এই লেজারে লিখুন, কাগজের নম্বরসহ। কাগজ ছাড়া কোনো মালামাল প্রাপ্তি বা ইস্যু হবে না। প্রতিটি লাইনের পর বাকি লিখুন। গণনার পার্থক্য ঠিক করা যাবে শুধু স্টক কাউন্ট শিটের নম্বর ও অনুমোদনসহ।',
        'Write every receipt and issue in this ledger with its paper number. No goods come in or go out without a paper. Write the balance after every line. A count difference can be corrected only with a stock count sheet number and approval.'), 'warn'),
      TABLE('lines', null, [D('date', L('তারিখ', 'Date')), T('grn_no', L('মালামাল গ্রহণ রসিদ (GRN) নং', 'Goods received note (GRN) no.')), T('issue_no', L('মালামাল ইস্যু স্লিপ নং', 'Material issue slip no.')),
        SEL('other_type', L('অন্য কাগজ (ফেরত · কাউন্টের সমন্বয়)', 'Other paper (return · count adjustment)'), OTHER_PAPERS), T('other_no', L('অন্য কাগজের নং', 'Other paper no.')),
        N('in', L('প্রাপ্তি (In)', 'In')), N('out', L('ইস্যু (Out)', 'Out')), CALC('bal', L('বাকি (Balance)', 'Balance'), 'num', { show: (x) => has(x.row.in) || has(x.row.out) }),
        M('rate', L('দর ৳ (GRN অনুযায়ী)', 'Rate ৳ (as per the GRN)'))], { min: 5 }),
      CALC('closing', L('পাতার শেষে বাকি (Closing)', 'Balance at the end of the page (closing)'), 'num', { big: true }),
      CK('carried', L('পরের পাতায় নেওয়া', 'Carried to the next page'))] },
    { collapsed: true, title: L('মাসের শেষে', 'Month end'), fields: [
      CALC('book', L('লেজারে বাকি', 'Balance in the ledger'), 'num'), N('counted', L('গণনায় প্রাপ্ত', 'Counted')), CALC('diff', L('পার্থক্য (গণনা − লেজার)', 'Difference (count − ledger)'), 'num', { show: (x) => has(x.d.counted) }),
      T('count_sheet', L('স্টক কাউন্ট শিট নং', 'Stock count sheet no.'), { req: (x) => x.v.diff_nonzero }),
      CALC('value', L('মজুদের মূল্য (Stock Value) = বাকি × শেষ দর', 'Stock value = balance × last rate'), 'text')] },
    { who: 'checker', title: L('মাসিক যাচাই ও অনুমোদন (ব্যবস্থাপনা)', 'Monthly check & approval (management)'), fields: [
      ST('monthly_checker', L('মাসিক যাচাই (Checked by — স্টোরকিপার নন)', 'Monthly check (Checked by — not the storekeeper)'), { who: 'checker', req: true }),
      CK('mgmt_approved', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by — management'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {}; let bal = num(x.d.opening), lastRate = null;
    const out = rows.map((r) => { if (!(has(r.in) || has(r.out))) return {}; bal += num(r.in) - num(r.out); if (has(r.rate)) lastRate = num(r.rate); return { bal }; });
    v.closing = bal; v.book = bal;
    const noPaper = rows.filter((r) => (num(r.in) > 0 && !has(r.grn_no) && !has(r.other_no)) || (num(r.out) > 0 && !has(r.issue_no) && !has(r.other_no)));
    if (noPaper.length) flags.push(flag('no_paper', 'red', 'কাগজের নম্বর ছাড়া প্রাপ্তি বা ইস্যু লেখা হয়েছে', 'A receipt or issue is written without a paper number', noPaper.length, { unit: 'qty' }));
    if (rows.some((r) => has(r.other_type) && !has(r.other_no))) flags.push(flag('other_paper_no', 'red', 'অন্য কাগজের ধরন আছে কিন্তু নম্বর নেই', 'Other paper type chosen but its number is missing', undefined));
    if (out.some((o) => o.bal !== undefined && o.bal < 0)) flags.push(flag('negative_balance', 'red', 'বাকি ঋণাত্মক হয়েছে', 'The balance went below zero', Math.min(...out.filter((o) => o.bal !== undefined).map((o) => o.bal)), { unit: 'qty' }));
    v.value = lastRate === null ? NEED : '৳ ' + fm(bal * lastRate);
    if (has(x.d.counted)) { const d = num(x.d.counted) - bal; v.diff = d; v.diff_nonzero = d !== 0;
      if (d !== 0) { const pct = sv(x, 'count_tol_pct'), max = sv(x, 'count_tol_max'), price = lastRate === null ? 0 : lastRate;
        const p = bal > 0 ? Math.abs(d) / bal * 100 : 100, okP = pct !== null && p <= pct, okM = max !== null && lastRate !== null && Math.abs(d) * price <= max;
        if (pct === null && max === null) needs.push('count_tol_pct', 'count_tol_max');
        flags.push(flag('ledger_count_diff', okP || okM ? 'yellow' : 'red', 'গণনা ও লেজারের বাকিতে পার্থক্য', 'Count differs from the ledger balance', Math.abs(d), { unit: 'qty' }));
        if (!has(x.d.count_sheet)) flags.push(flag('adj_no_sheet', 'red', 'পার্থক্যের জন্য স্টক কাউন্ট শিটের নম্বর নেই', 'No stock count sheet number for the difference', undefined)); } }
    const mc = x.c.monthly_checker; if (has(mc) && mc === x.d.storekeeper) flags.push(flag('checker_is_keeper', 'red', 'মাসিক যাচাইকারী ও স্টোরকিপার একই জন', 'The monthly checker is the storekeeper', undefined, { src: 'check' }));
    return { v, rows: { lines: out }, flags, needs };
  },
};
// the unit of the item chosen in the header is a plain calc outside a table: keep it in v
{ const base = B.forms['37-1'].calc; B.forms['37-1'].calc = (x) => { const r = base(x); r.v.unit = unitOf(x, x.d.item); return r; }; }

/* ============ 28-1 · Purchase requisition (PR) ============ */
B.forms['28-1'] = {
  title: L('পারচেজ রিকুইজিশন', 'Purchase Requisition'),
  head: [ST('requester', L('অনুরোধকারী (নাম)', 'Requested by (name)'), { req: true }), D('required_date', L('প্রয়োজনের তারিখ (Required Date)', 'Required date'), { req: true }),
    CH('urgency', L('ধরন', 'Type'), [['normal', L('স্বাভাবিক', 'Normal')], ['urgent', L('জরুরি', 'Urgent')]], { req: true })],
  sections: [
    { title: L('কী প্রয়োজন', 'What is needed'), fields: [
      NOTE(L('স্টক শেষ হওয়ার আগে অনুরোধ করতে হবে, শেষ হওয়ার পরে নয়। অনুরোধকারী নিজে অনুমোদন দিতে পারবেন না।', 'Request before the stock runs out, not after. The requester cannot approve their own request.'), 'warn'),
      TABLE('lines', null, [ITEM('item', L('আইটেম', 'Item'), { req: true, wide: true }), CALC('unit', L('একক', 'Unit'), 'text'), N('stock', L('গোডাউনে মজুদ (Stock)', 'Stock in the godown')),
        N('need', L('প্রয়োজন (Required)', 'Required'), { req: true }), M('last_rate', L('শেষ ক্রয়ের দর', 'Last purchase rate')),
        CALC('est', L('আনুমানিক মূল্য ৳', 'Estimated value ৳'), 'money', { show: (x) => has(x.row.need) && has(x.row.last_rate) }), T('why', L('প্রয়োজনের কারণ', 'Reason for the need'), { wide: true })], { min: 3 }),
      CALC('est_total', L('আনুমানিক মোট ৳', 'Estimated total ৳'), 'money', { big: true, show: (x) => !x.v.est_incomplete })] },
    { title: L('কোটেশন তুলনা', 'Quotation comparison'), fields: [
      CALC('cmp_text', L('সীমা (লোকেশন সেটিংস)', 'Limit (location settings)'), 'text'),
      CH('cmp', L('কোটেশন তুলনা', 'Quotation comparison'), [['within', L('সীমার ভেতরে — প্রয়োজন নেই', 'Within the limit — not needed')], ['outside', L('বাইরে → কোটেশন তুলনা (CS) নং', 'Outside → quotation comparison (CS) no.')]], { req: true }),
      T('cs_no', L('কোটেশন তুলনা ও সাপ্লায়ার নির্বাচন (CS) নং', 'Quotation comparison (CS) no.'), { show: (x) => x.d.cmp === 'outside', req: (x) => x.d.cmp === 'outside' })] },
    { title: L('জরুরি হলে — ক্রয়ের আগেই পূরণ', 'If urgent — fill before buying'), show: (x) => x.d.urgency === 'urgent', fields: [
      TA('urgent_reason', L('কারণ', 'Reason'), { req: true }), M('normal_rate', L('স্বাভাবিক দর ৳', 'Normal rate ৳')), M('now_rate', L('এখনকার দর ৳', 'Current rate ৳')),
      CALC('rate_diff', L('দরের পার্থক্য ৳', 'Rate difference ৳'), 'money', { show: (x) => has(x.d.normal_rate) && has(x.d.now_rate) }),
      N('urgent_count', L('এ মাসে এই আইটেমে জরুরি ক্রয় (বার)', 'Urgent purchases of this item this month (times)'))] },
    { title: L('বাজারের নগদ অ্যাডভান্স (জরুরি ক্রয়ে)', 'Cash advance for the market (urgent purchase)'), show: (x) => x.d.urgency === 'urgent', fields: [
      M('adv_given', L('দেওয়া হলো ৳', 'Given ৳')), ST('adv_to', L('কাকে', 'Given to'), { show: (x) => hasN(x.d.adv_given), req: (x) => hasN(x.d.adv_given) }),
      T('adv_ledger', L('ক্যাশ ও ব্যাংক লেজারের লাইন নং', 'Cash & bank ledger line no.'), { show: (x) => hasN(x.d.adv_given) }),
      M('adv_change', L('ফেরত খুচরা ৳', 'Change returned ৳')), M('adv_receipts', L('রসিদের মোট ৳', 'Receipts total ৳')), D('adv_return_date', L('ফেরতের তারিখ', 'Return date')),
      CALC('adv_text', L('অ্যাডভান্স = ফেরত + রসিদ', 'Advance = change + receipts'), 'text', { show: (x) => hasN(x.d.adv_given) }),
      CK('adv_equal', L('অ্যাডভান্স = ফেরত + রসিদ', 'Advance = change + receipts'), { req: (x) => x.v.adv_started }),
      ST('adv_checker', L('যাচাইকারী (Checked by) (যিনি ক্রয় করেছেন তিনি নন)', 'Checked by (not the person who bought)'), { req: (x) => x.v.adv_started }),
      NOTE(L('মালামাল গ্রহণ রসিদের নম্বর ছাড়া অ্যাডভান্স রিকনসিলিয়েশন হবে না।', 'No advance reconciliation without a goods received note number.'), 'warn'),
      T('grn_no', L('মালামাল গ্রহণ রসিদ (GRN) নং', 'Goods received note (GRN) no.'), { req: (x) => x.v.adv_started }),
      CK('counted_by_other', L('মালামাল গণনা করে নিয়েছেন যিনি ক্রয় করেছেন তিনি নন', 'The goods were counted by someone other than the buyer'), { req: (x) => x.v.adv_started })] },
    { who: 'checker', title: L('অনুমোদন (ভিন্ন ব্যক্তি)', 'Approval (a different person)'), fields: [
      CH('decision', L('সিদ্ধান্ত', 'Decision'), [['yes', L('অনুমোদিত', 'Approved')], ['no', L('অনুমোদিত নয়', 'Not approved')]], { who: 'checker', req: true }),
      CK('phone_approval', L('ফোনে অনুমোদন (পরে স্বাক্ষর)', 'Approved by phone (to sign later)'), { who: 'checker' }), TM('phone_time', L('সময়', 'Time'), { who: 'checker', show: (x) => !!x.c.phone_approval }),
      T('approver_note', L('মন্তব্য', 'Remark'), { who: 'checker' })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    const out = rows.map((r) => ({ unit: unitOf(x, r.item), est: has(r.need) && has(r.last_rate) ? num(r.need) * num(r.last_rate) : undefined }));
    const est = sum(out.map((o) => o.est)); v.est_total = est;
    const noRate = rows.some((r) => hasN(r.need) && !has(r.last_rate)); v.est_incomplete = noRate;
    const lim = sv(x, 'quote_over');
    if (noRate) flags.push(flag('est_incomplete', 'yellow', 'কিছু লাইনে শেষ ক্রয়ের দর নেই — আনুমানিক মূল্য অসম্পূর্ণ, সীমা যাচাই করা যায়নি', 'Some lines have no last rate: the estimate is incomplete and the limit cannot be checked', undefined));
    if (lim === null) { needs.push('quote_over'); v.cmp_text = NEED; }
    else if (noRate) v.cmp_text = L('সীমা ৳ ' + fm(lim) + ' — দর অসম্পূর্ণ: ' + NEED.bn, 'Limit ৳ ' + fm(lim) + ' — rates incomplete: ' + NEED.en);
    else { const over = est > lim; v.cmp_text = L('সীমা ৳ ' + fm(lim) + ' — ' + (over ? 'আনুমানিক মূল্য সীমার বাইরে: কোটেশন তুলনা লাগবে' : 'সীমার ভেতরে'), 'Limit ৳ ' + fm(lim) + ' — ' + (over ? 'estimate is above it: a quotation comparison is needed' : 'within it'));
      if (over && !(x.d.cmp === 'outside' && has(x.d.cs_no))) flags.push(flag('cs_missing', 'red', 'মূল্য কোটেশন তুলনার সীমার উপরে কিন্তু কোটেশন তুলনা (CS) নং নেই', 'Value is above the quotation limit but there is no CS number', est)); }
    if (x.d.urgency === 'urgent') { flags.push(flag('urgent_purchase', 'yellow', 'জরুরি ক্রয়', 'Urgent purchase', undefined));
      if (has(x.d.normal_rate) && has(x.d.now_rate)) { const d = num(x.d.now_rate) - num(x.d.normal_rate); v.rate_diff = d; if (d > 0) flags.push(flag('urgent_rate_premium', 'yellow', 'জরুরি ক্রয়ে স্বাভাবিকের চেয়ে বেশি দর', 'Urgent purchase at a higher rate than normal', d)); } }
    v.adv_started = x.d.urgency === 'urgent' && hasN(x.d.adv_given) && (has(x.d.adv_change) || has(x.d.adv_receipts));
    if (x.d.urgency === 'urgent' && hasN(x.d.adv_given)) {
      v.adv_text = NEED;
      if (v.adv_started) { const df = num(x.d.adv_given) - num(x.d.adv_change) - num(x.d.adv_receipts); v.adv_text = diffText(df);
        if (df !== 0) flags.push(flag('advance_mismatch', 'red', 'অ্যাডভান্স ≠ ফেরত + রসিদ', 'Advance differs from change + receipts', df));
        if (!has(x.d.grn_no)) flags.push(flag('advance_no_grn', 'red', 'মালামাল গ্রহণ রসিদের নম্বর ছাড়া অ্যাডভান্স রিকনসিলিয়েশন', 'Advance reconciliation without a goods received note number', undefined));
        if (has(x.d.adv_checker) && x.d.adv_checker === x.d.adv_to) flags.push(flag('adv_checker_is_buyer', 'red', 'যাচাইকারী ও যিনি ক্রয় করেছেন একই জন', 'The checker is the person who bought', undefined)); } }
    if (x.c.decision === 'no') flags.push(flag('pr_not_approved', 'red', 'সিদ্ধান্ত “অনুমোদিত নয়” — অনুমোদন করা যাবে না', 'Decision is “Not approved”: it cannot be approved', undefined, { src: 'check' }));
    return { v, rows: { lines: out }, flags, needs };
  },
};

/* ============ 29-1 · Quotation comparison & supplier choice (CS) ============ */
B.forms['29-1'] = {
  title: L('কোটেশন তুলনা', 'Quotation Comparison'),
  head: [T('pr_no', L('সংশ্লিষ্ট পারচেজ রিকুইজিশন (PR) নং', 'Related purchase requisition (PR) no.')), T('what', L('প্রয়োজনীয় আইটেম', 'Item needed'), { req: true }),
    N('qty', L('পরিমাণ', 'Quantity'), { req: true }), ST('collector', L('দর সংগ্রহকারী (Rates Collected by)', 'Rates collected by'), { req: true })],
  sections: [
    { title: L('দর পাশাপাশি', 'Quotes side by side'), fields: [
      NOTE(L('দর নেওয়া হবে ক্রয়ের আগে — পরে নয়। একটিমাত্র দর নিয়ে ক্রয় হলে লিখিত কারণ লাগবে।', 'Take quotes before buying, not after. Buying on a single quote needs a written reason.'), 'warn'),
      CALC('limit_text', L('কোটেশন তুলনার সীমা (লোকেশন সেটিংস)', 'Quotation comparison limit (location settings)'), 'text'),
      TABLE('quotes', null, [SUP('supplier', L('সাপ্লায়ারের নাম (Supplier)', 'Supplier name'), { req: true, wide: true }), M('rate', L('দর ৳ (প্রতি একক)', 'Rate ৳ (per unit)'), { req: true }),
        CALC('total', L('মোট ৳', 'Total ৳'), 'money', { show: (x) => has(x.row.rate) && num(x.d.qty) > 0 }), T('delivery', L('সরবরাহের সময়', 'Delivery time')), N('credit', L('বাকির সময় (দিন)', 'Credit period (days)')),
        T('quality', L('মান / আগের অভিজ্ঞতা', 'Quality / earlier experience'), { wide: true })], { min: 3 }),
      CALC('lowest', L('সবচেয়ে কম দর ৳', 'Lowest rate ৳'), 'text')] },
    { title: L('নির্বাচিত সাপ্লায়ার', 'Selected supplier'), fields: [
      SUP('sel_supplier', L('নির্বাচিত সাপ্লায়ার (Selected)', 'Selected supplier'), { req: true }), M('sel_rate', L('দর ৳', 'Rate ৳'), { req: true }),
      NOTE(L('বেশি দরের সাপ্লায়ার নির্বাচন করলে কারণ লিখতেই হবে।', 'If you pick a supplier with a higher rate, a reason is a must.'), 'warn', { show: (x) => x.v.not_lowest }),
      TA('reason', L('কারণ', 'Reason'), { show: (x) => x.v.not_lowest, req: (x) => x.v.not_lowest }),
      CH('single', L('একটিমাত্র দর নেওয়া হয়েছে?', 'Only one quote taken?'), [['no', L('না', 'No')], ['yes', L('হ্যাঁ', 'Yes')]], { req: true }),
      TA('single_reason', L('কারণ', 'Reason'), { show: (x) => x.d.single === 'yes', req: (x) => x.d.single === 'yes' })] },
    { title: L('পারচেজ অর্ডার', 'Purchase order'), fields: [T('po_no', L('পারচেজ অর্ডার (PO) নং', 'Purchase order (PO) no.')), D('po_date', L('তারিখ', 'Date'))] },
    { who: 'checker', title: L('নির্বাচনের অনুমোদন (ব্যবস্থাপনা)', 'Approval of the choice (management)'), fields: [
      CK('sel_approved', L('নির্বাচনের অনুমোদনকারী (Approved by) — নির্বাচন অনুমোদিত', 'Approved by — the choice is approved'), { who: 'checker', req: true }),
      ST('single_approver', L('একটিমাত্র দরে — অনুমোদনকারী (Approved by)', 'Single quote — approved by'), { who: 'checker', show: (x) => x.d.single === 'yes', req: (x) => x.d.single === 'yes' })] },
  ],
  calc(x) {
    const rows = x.rows('quotes'), flags = [], needs = [], v = {}, q = num(x.d.qty);
    const out = rows.map((r) => ({ total: has(r.rate) && q > 0 ? num(r.rate) * q : undefined }));
    const filled = rows.filter((r) => has(r.supplier) || has(r.rate)), rates = rows.filter((r) => hasN(r.rate)).map((r) => num(r.rate));
    const low = rates.length ? Math.min(...rates) : null; v.lowest = low === null ? NEED : '৳ ' + fm(low);
    const lim = sv(x, 'quote_over'); v.limit_text = lim === null ? NEED : L('৳ ' + fm(lim) + ' এর উপরে তুলনা বাধ্যতামূলক', 'Comparison is compulsory above ৳ ' + fm(lim));
    if (has(x.d.sel_rate) && low !== null && num(x.d.sel_rate) > low) { v.not_lowest = true; flags.push(flag('not_lowest', 'yellow', 'সবচেয়ে কম দরের সাপ্লায়ার নির্বাচিত হয়নি', 'Not the lowest-rate supplier', q > 0 ? (num(x.d.sel_rate) - low) * q : num(x.d.sel_rate) - low)); }
    const amount = has(x.d.sel_rate) ? num(x.d.sel_rate) * q : 0;
    if (filled.length === 1 && x.d.single !== 'yes') flags.push(flag('single_unmarked', 'red', 'একটিমাত্র দর আছে কিন্তু “একটিমাত্র দর” চিহ্নিত নয়', 'Only one quote but not marked as a single quote', undefined));
    if (x.d.single === 'yes' || filled.length === 1) {
      if (lim === null) { needs.push('quote_over'); flags.push(flag('single_quote', 'red', 'একটিমাত্র দরে ক্রয় (সীমা লেখা নেই)', 'Buying on a single quote (limit not set)', amount || undefined)); }
      else flags.push(flag('single_quote', amount > lim ? 'red' : 'yellow', amount > lim ? 'সীমার উপরের ক্রয় একটিমাত্র দরে' : 'একটিমাত্র দরে ক্রয়', amount > lim ? 'Above-limit purchase on a single quote' : 'Buying on a single quote', amount || undefined));
    } else if (lim === null) needs.push('quote_over');
    if (has(x.c.single_approver) && x.c.single_approver === x.d.collector) flags.push(flag('single_approver_is_collector', 'red', 'একটিমাত্র দরের অনুমোদনকারী ও দর সংগ্রহকারী একই জন', 'The approver of the single quote collected the rates', undefined, { src: 'check' }));
    return { v, rows: { quotes: out }, flags, needs: [...new Set(needs)] };
  },
};

/* ============ 27-1 · Purchase order (PO) ============ */
B.forms['27-1'] = {
  title: L('পারচেজ অর্ডার', 'Purchase Order'),
  head: [T('cs_no', L('সংশ্লিষ্ট কোটেশন তুলনা (CS) নং', 'Related quotation comparison (CS) no.')), T('pr_no', L('পারচেজ রিকুইজিশন (PR) নং', 'Purchase Requisition (PR) no.')),
    SUP('supplier', L('সাপ্লায়ার', 'Supplier'), { req: (x) => !x.d.cancel }), T('phone', L('ফোন', 'Phone')), D('delivery_date', L('ডেলিভারির তারিখ (Delivery Date)', 'Delivery date'), { req: (x) => !x.d.cancel }),
    T('place', L('ডেলিভারির স্থান', 'Delivery place')),
    CH('pay', L('পেমেন্ট', 'Payment'), PAYS, { req: (x) => !x.d.cancel }), T('pay_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.pay === 'other', req: (x) => x.d.pay === 'other' && !x.d.cancel }),
    N('credit_days', L('বাকির সময় (দিন)', 'Credit period (days)'), { show: (x) => x.d.pay === 'credit', req: (x) => x.d.pay === 'credit' && !x.d.cancel })],
  sections: [
    { title: L('বাতিল', 'Cancellation'), collapsed: true, fields: [
      CK('cancel', L('বাতিল', 'Cancelled')),
      TA('cancel_reason', L('বাতিলের কারণ', 'Reason for cancelling'), { show: (x) => !!x.d.cancel, req: (x) => !!x.d.cancel }),
      ST('cancel_approver', L('অনুমোদনকারী (বাতিলের)', 'Cancellation approved by'), { show: (x) => !!x.d.cancel, req: (x) => !!x.d.cancel }),
      D('cancel_date', L('বাতিলের তারিখ', 'Date of cancellation'), { show: (x) => !!x.d.cancel }), CK('cancel_told', L('সাপ্লায়ারকে জানানো', 'Supplier informed'), { show: (x) => !!x.d.cancel }),
      NOTE(L('বাতিল পাতা বইয়েই রাখা হবে।', 'The cancelled page stays in the book.'), 'ok', { show: (x) => !!x.d.cancel })] },
    { title: L('অর্ডারের আইটেম', 'Order lines'), fields: [
      NOTE(L('পারচেজ অর্ডার ছাড়া মালামাল গ্রহণ করা যাবে না — মালামাল নামানো বন্ধ থাকবে।', 'Goods cannot be accepted without a purchase order: unloading stays stopped.'), 'warn'),
      TABLE('lines', null, [ITEM('item', L('আইটেম', 'Item'), { req: (x) => !x.d.cancel, wide: true }), T('desc', L('বিবরণ', 'Description'), { wide: true }), CALC('unit', L('একক', 'Unit'), 'text'),
        N('qty', L('পরিমাণ (Qty)', 'Quantity (Qty)'), { req: (x) => !x.d.cancel }), M('rate', L('দর ৳', 'Rate ৳'), { req: (x) => !x.d.cancel }), CALC('total', L('মোট ৳', 'Total ৳'), 'money', { show: (x) => has(x.row.qty) && has(x.row.rate) })], { min: 3 }),
      CALC('grand', L('সর্বমোট (Total)', 'Grand total'), 'money', { big: true }), CALC('cs_text', L('কোটেশন তুলনার সীমা', 'Quotation comparison limit'), 'text')] },
    { title: L('শর্ত', 'Terms'), fields: [
      CK('t_short', L('পরিমাণে কম হলে বিল সেই অনুযায়ী', 'If the quantity is short, the bill follows it')), CK('t_return', L('নিম্নমানের হলে ফেরতযোগ্য', 'Returnable if of poor quality')),
      CK('t_rate', L('দর এই পারচেজ অর্ডারে লেখা দরেই থাকবে', 'The rate stays as written on this PO')), CK('t_late', L('সময়ের পরে দিলে আগে জানাতে হবে', 'If delivering late, inform beforehand')),
      TA('t_special', L('বিশেষ শর্ত', 'Special terms'))] },
    { title: L('সম্মতি', 'Acceptance'), fields: [
      CK('accepted', L('সম্মতিদাতা (Accepted by) — সাপ্লায়ার সম্মতি জানিয়েছেন', 'Accepted by the supplier')), T('accepted_name', L('সাপ্লায়ারের পক্ষে নাম', 'Name for the supplier'), { show: (x) => !!x.d.accepted })] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      CK('po_approved', L('অনুমোদনকারী (Approved by) — অর্ডার অনুমোদিত', 'Approved by — the order is approved'), { who: 'checker', req: (x) => !x.d.cancel })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    const out = rows.map((r) => ({ unit: unitOf(x, r.item), total: has(r.qty) && has(r.rate) ? num(r.qty) * num(r.rate) : undefined }));
    v.grand = sum(out.map((o) => o.total));
    const lim = sv(x, 'quote_over');
    if (lim === null) { needs.push('quote_over'); v.cs_text = NEED; }
    else { const over = v.grand > lim; v.cs_text = L('৳ ' + fm(lim) + ' এর উপরে তুলনা বাধ্যতামূলক — ' + (over ? 'এই অর্ডার সীমার উপরে' : 'সীমার ভেতরে'), 'Comparison compulsory above ৳ ' + fm(lim) + (over ? ' — this order is above it' : ' — within it'));
      if (over && !has(x.d.cs_no)) flags.push(flag('po_no_cs', 'red', 'অর্ডার কোটেশন তুলনার সীমার উপরে কিন্তু কোটেশন তুলনা (CS) নং নেই', 'Order is above the quotation limit but there is no CS number', v.grand)); }
    if (x.d.cancel) flags.push(flag('po_cancelled', 'yellow', 'পারচেজ অর্ডার বাতিল', 'Purchase order cancelled', v.grand || undefined));
    if (x.d.pay === 'owner') flags.push(flag('pay_owner', 'yellow', 'মালিকের ব্যক্তিগত টাকায় পেমেন্ট', "Payment from the owner's personal money", undefined));
    return { v, rows: { lines: out }, flags, needs };
  },
};

/* ============ 02-1 · Bill check & payment request ============ */
const BILLPAYS = [['cash', L('নগদ', 'Cash')], ['bank', L('ব্যাংক', 'Bank')], ['cheque', L('চেক', 'Cheque')], ['mobile', L('মোবাইল', 'Mobile')], ['owner', L('মালিকের ব্যক্তিগত', "Owner's personal money")], ['other', L('অন্য', 'Other')]];
B.forms['02-1'] = {
  title: L('বিল যাচাই ও পেমেন্ট', 'Bill Check and Payment'),
  head: [SUP('supplier', L('সাপ্লায়ার', 'Supplier'), { req: true }), T('bill_no', L('সাপ্লায়ারের বিল নং', "Supplier's bill no."), { req: true }), D('bill_date', L('বিলের তারিখ', 'Bill date'), { req: true }), M('bill_amount', L('বিলের অঙ্ক ৳', 'Bill amount ৳'), { req: true })],
  sections: [
    { title: L('তিন কাগজ মিলিয়ে দেখা', 'Three papers matched'), fields: [
      NOTE(L('তিন কাগজ মিলতেই হবে — পারচেজ অর্ডার · মালামাল গ্রহণ রসিদ · সাপ্লায়ারের বিল। একটিতেও গরমিল থাকলে পেমেন্ট আটকে থাকবে।', 'The three papers must match: purchase order, goods received note, supplier bill. If any one differs, payment stays held.'), 'warn'),
      TABLE('tri', null, [T('po', L('পারচেজ অর্ডারে (PO)', 'On the PO')), T('grn', L('গ্রহণ রসিদে (GRN)', 'On the GRN')), T('bill', L('বিলে (Bill)', 'On the bill')),
        CALC('ok', L('মিল', 'Match'), 'text')], { rows: [L('কাগজের নম্বর (PO নং, তিন কাগজে যেভাবে লেখা)', 'Paper number (PO no. as written on each paper)'), L('পরিমাণ', 'Quantity'), L('দর ৳', 'Rate ৳'), L('মোট ৳', 'Total ৳')] }),
      NOTE(L('PO নং, GRN নং ও বিল নং যথাক্রমে PO, GRN ও বিলের ঘরে লিখুন; সংখ্যার সারিতে শুধু সংখ্যা।', 'Write the PO, GRN and bill numbers in the PO, GRN and bill boxes of the first row; plain numbers in the other rows.'), 'ok'),
      T('grn_no', L('মালামাল গ্রহণ রসিদ (GRN) নং', 'Goods received note (GRN) no.')),
      CALC('diff', L('পার্থক্য ৳ (বিল − GRN মোট)', 'Difference ৳ (bill − GRN total)'), 'money', { show: (x) => x.v.mismatch && x.v.diff !== undefined })] },
    { title: L('গরমিল থাকলে', 'If something differs'), show: (x) => x.v.mismatch, fields: [
      CH('mism_what', L('কোন বিষয়ে গরমিল', 'What differs'), [['qty', L('পরিমাণ', 'Quantity')], ['rate', L('দর', 'Rate')], ['both', L('দুটোই', 'Both')]], { req: true }),
      CK('held', L('পেমেন্ট আটকে রাখা হলো', 'Payment held'), { req: true }), CK('todo', L('কাজের তালিকায় যোগ', 'Added to the to-do list')),
      CK('told', L('সাপ্লায়ারকে জানানো হয়েছে', 'Supplier informed')), D('told_date', L('জানানোর তারিখ', 'Date informed')), ST('told_by', L('জানানোর দায়িত্বধারী', 'Person responsible for informing'))] },
    { title: L('ঘাটতি / ফেরতের দাবি', 'Shortage / return claim'), fields: [
      CH('short', L('ঘাটতি ছিল?', 'Was there a shortage?'), YN), N('short_qty', L('ঘাটতির পরিমাণ', 'Shortage quantity'), { show: (x) => x.d.short === 'yes', req: (x) => x.d.short === 'yes' }),
      CK('carrier_signed', L('বহনকারী স্বাক্ষর করেছিলেন', 'The carrier signed'), { show: (x) => x.d.short === 'yes' }),
      CH('returned', L('ফেরত গেছে?', 'Did goods go back?'), YN), N('ret_qty', L('ফেরতের পরিমাণ', 'Returned quantity'), { show: (x) => x.d.returned === 'yes', req: (x) => x.d.returned === 'yes' }),
      T('debit_no', L('ডেবিট নোট (Debit Note) নং', 'Debit note no.'), { show: (x) => x.d.short === 'yes' || x.d.returned === 'yes', req: (x) => x.d.short === 'yes' || x.d.returned === 'yes' }),
      CH('debit_reason', L('কারণ', 'Reason'), [['short', L('ঘাটতি', 'Shortage')], ['return', L('ফেরত', 'Return')], ['quality', L('মান — দর কমিয়ে গ্রহণ (মালামাল গ্রহণ রসিদ অনুযায়ী)', 'Quality: accepted at a lower rate (as per the GRN)')]], { show: (x) => x.d.short === 'yes' || x.d.returned === 'yes' }),
      CK('ledger_deducted', L('সাপ্লায়ার লেজারে বাদ দেওয়া হয়েছে', 'Deducted in the supplier ledger'))] },
    { title: L('পেমেন্টের অনুরোধ', 'Payment request'), fields: [
      M('pay_amount', L('পেমেন্ট দিতে হবে ৳', 'Amount to pay ৳')),
      CH('pay_way', L('মাধ্যম', 'Way of payment'), BILLPAYS), T('pay_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.pay_way === 'other', req: (x) => x.d.pay_way === 'other' }),
      NOTE(OWNER_NOTE, 'warn', { show: (x) => x.d.pay_way === 'owner' }),
      D('due_date', L('পেমেন্টের নির্ধারিত তারিখ (Due Date)', 'Payment due date')), M('prev_dues', L('সাপ্লায়ার লেজারে আগের বকেয়া ৳', 'Earlier dues in the supplier ledger ৳')),
      CK('only_matched', L('শুধু মিলে যাওয়া বিলই পেমেন্টে যাবে', 'Only a matching bill goes to payment'), { req: true }),
      D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date')), T('ledger_line', L('লাইন নং', 'Line no.'))] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      CK('pay_approved', L('অনুমোদনকারী (Approved by) — পেমেন্ট অনুমোদিত', 'Approved by — payment approved'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const r = x.rows('tri'), flags = [], v = {}; let mism = false;
    const norm = (s) => String(s).trim().toLowerCase();
    const out = [0, 1, 2, 3].map((i) => { const a = r[i] || {}; if (!(has(a.po) && has(a.grn) && has(a.bill))) return { ok: '' };
      const eq = i === 0 ? norm(a.po) === norm(a.grn) && norm(a.grn) === norm(a.bill) : num(a.po) === num(a.grn) && num(a.grn) === num(a.bill);
      if (!eq) mism = true; return { ok: eq ? L('মিল আছে ✓', 'Matches ✓') : L('অমিল ✗', 'Differs ✗') }; });
    const tot = r[3] || {}; v.diff = has(tot.bill) && has(tot.grn) ? num(tot.bill) - num(tot.grn) : undefined;
    if (has(x.d.bill_amount) && has(tot.grn) && num(x.d.bill_amount) !== num(tot.grn)) { mism = true; if (v.diff === undefined) v.diff = num(x.d.bill_amount) - num(tot.grn); }
    v.mismatch = mism;
    if (mism) { const held = !!x.d.held;
      flags.push(flag('bill_mismatch', held ? 'yellow' : 'red', held ? 'তিন কাগজে গরমিল — পেমেন্ট আটকে রাখা হয়েছে' : 'তিন কাগজে গরমিল — পেমেন্ট আটকানো হয়নি', held ? 'Three papers differ: payment is held' : 'Three papers differ: payment is not held', v.diff !== undefined ? Math.abs(v.diff) : undefined));
      if (hasN(x.d.pay_amount)) flags.push(flag('pay_on_mismatch', 'red', 'গরমিল থাকা সত্ত্বেও পেমেন্টের অঙ্ক লেখা হয়েছে', 'A payment amount is written although the papers differ', num(x.d.pay_amount))); }
    if (has(x.d.bill_amount) && has(tot.bill) && num(x.d.bill_amount) !== num(tot.bill)) flags.push(flag('bill_amount_differs', 'red', 'বিলের অঙ্ক ও “বিলে মোট” আলাদা', 'Bill amount differs from the “total on the bill”', num(x.d.bill_amount) - num(tot.bill)));
    if (x.d.short === 'yes' && !x.d.carrier_signed) flags.push(flag('short_no_carrier', 'yellow', 'ঘাটতি আছে কিন্তু বহনকারীর স্বাক্ষর নেই', 'Shortage but no carrier signature', undefined));
    if (x.d.pay_way === 'owner') flags.push(flag('pay_owner', 'yellow', 'মালিকের ব্যক্তিগত টাকায় পেমেন্ট', "Payment from the owner's personal money", has(x.d.pay_amount) ? num(x.d.pay_amount) : undefined));
    return { v, rows: { tri: out }, flags, needs: [] };
  },
};

/* ============ 38-1 · Supplier ledger (one page per supplier) ============ */
B.forms['38-1'] = {
  title: L('সাপ্লায়ার লেজার', 'Supplier Ledger'),
  head: [T('page_no', L('পাতা নং', 'Page no.')), ST('keeper', L('হিসাবরক্ষক (Ledger Keeper)', 'Ledger keeper')), SUP('supplier', L('সাপ্লায়ারের নাম', 'Supplier name'), { req: true }), T('items', L('সরবরাহের আইটেম (Items Supplied)', 'Items supplied')),
    CH('kind', L('ধরন', 'Type'), [['supplier', L('সাপ্লায়ার', 'Supplier')], ['outside', L('বাইরের সোর্সিং', 'Outside sourcing')], ['other', L('অন্য', 'Other')]]),
    T('kind_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.kind === 'other' }),
    T('phone', L('ফোন', 'Phone')), T('address', L('ঠিকানা', 'Address')), N('credit_days', L('বাকির সময় (দিন)', 'Credit period (days)')),
    T('account_no', L('হিসাব নং (থাকলে)', 'Account no. (if any)')), D('first_date', L('প্রথম কাজের তারিখ', 'First work date'))],
  sections: [
    { title: L('পেমেন্টের মাধ্যম', 'Ways of payment'), fields: [
      CK('m_cash', L('নগদ', 'Cash')), CK('m_bank', L('ব্যাংক', 'Bank')), CK('m_mobile', L('মোবাইল', 'Mobile')), CK('m_owner', L("মালিকের ব্যক্তিগত", "Owner's personal money")),
      CK('m_goods', L('মালামালে সমন্বয়', 'Settled with goods')), CK('m_other', L('অন্য', 'Other')), T('m_other_text', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => !!x.d.m_other })] },
    { title: L('হিসাবের তথ্য যাচাই — প্রথম পেমেন্টের আগে', 'Account details check — before the first payment'), fields: [
      NOTE(L('হিসাবের তথ্য প্রথম পেমেন্টের আগে যাচাই হবে। যাচাইকারী হিসাবরক্ষক হতে পারবেন না।', 'Account details are checked before the first payment. The checker cannot be the ledger keeper.'), 'warn'),
      ST('verifier', L('যাচাইকারী (Checked by) (হিসাবরক্ষক নন)', 'Checked by (not the ledger keeper)')), D('verify_date', L('যাচাইয়ের তারিখ', 'Date checked')),
      CH('verify_how', L('কীভাবে', 'How'), [['call', L('এই পাতার ফোন নম্বরে ফোন করে', 'By calling the phone number on this page')], ['paper', L('হিসাবের কাগজ দেখে', 'By seeing the account paper')], ['other', L('অন্য', 'Other')]]),
      T('verify_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.verify_how === 'other' })] },
    { collapsed: true, title: L('হিসাবের তথ্য বদল হলে', 'If account details change'), fields: [
      T('chg_new', L('নতুন তথ্য', 'New details')), D('chg_date', L('তারিখ', 'Date')), ST('chg_approver', L('বদলের অনুমোদনকারী (Approved by) (হিসাবরক্ষক নন)', 'Change approved by (not the ledger keeper)'), { show: (x) => has(x.d.chg_new), req: (x) => has(x.d.chg_new) }),
      CK('chg_struck', L('পুরোনো তথ্য কেটে দেওয়া', 'Old details struck out'), { show: (x) => has(x.d.chg_new), req: (x) => has(x.d.chg_new) })] },
    { title: L('লেনদেন', 'Entries'), fields: [
      NOTE(L('মাসের শেষে মোট বকেয়া কত — এই লেজার দেখে বলা যাবে। কারও মনে রাখার উপর নির্ভর করা যাবে না।', "The month-end total due must be readable from this ledger. Nobody's memory may be relied on."), 'ok'),
      M('opening', L('আগের পাতার বকেয়া ৳ (নতুন হলে ফাঁকা)', 'Dues from the previous page ৳ (blank if new)')),
      TABLE('lines', null, [D('date', L('তারিখ', 'Date')), T('paper_no', L('কাগজ নং', 'Paper no.')), T('desc', L('বিবরণ', 'Description'), { wide: true }), M('bill', L('বিল ৳', 'Bill ৳')),
        M('debit', L('ডেবিট নোট ৳ (−)', 'Debit note ৳ (−)')), M('pay', L('পেমেন্ট ৳ (−)', 'Payment ৳ (−)')), CALC('bal', L('বকেয়া ৳', 'Balance due ৳'), 'money', { show: (x) => has(x.row.bill) || has(x.row.debit) || has(x.row.pay) })], { min: 5 }),
      CALC('due', L('এখন মোট বকেয়া ৳', 'Total due now ৳'), 'money', { big: true })] },
    { title: L('এ মাসের কাজ', "This month's performance"), fields: [
      N('p_total', L('মোট সরবরাহ (বার)', 'Deliveries in total (times)')), N('p_late', L('দেরিতে ডেলিভারি (বার)', 'Late deliveries (times)')),
      N('p_short', L('কম পরিমাণে ডেলিভারি (বার)', 'Short deliveries (times)')), N('p_poor', L('নিম্নমানের ডেলিভারি (বার)', 'Poor-quality deliveries (times)')), T('p_note', L('মন্তব্য', 'Remark'))] },
    { collapsed: true, title: L('মূল তালিকা — মাসের শেষে বকেয়া', 'Master list: dues at month end'), fields: [
      T('m_month', L('মাস', 'Month')),
      NOTE(L('নতুন সাপ্লায়ার এলে: আগে এখানে এক লাইন, তারপর তাঁর নিজের পাতা।', "For a new supplier: first one line here, then the supplier's own page."), 'ok'),
      TABLE('master', null, [SUP('name', L('সাপ্লায়ারের নাম', 'Supplier name'), { wide: true }), T('m_items', L('সরবরাহের আইটেম', 'Items supplied')), T('m_phone', L('ফোন', 'Phone')), T('m_page', L('পাতা নং', 'Page no.')), M('m_due', L('মাসের শেষে বকেয়া ৳', 'Dues at month end ৳'))], { min: 3 }),
      CALC('master_total', L('সব সাপ্লায়ারের মোট বকেয়া', 'Total dues of all suppliers'), 'money'), CK('master_posted', L('মাসের শেষে প্রতিটি পাতার বকেয়া এখানে এন্ট্রি (Posting) করা', "Each page's month-end dues posted here"))] },
    { who: 'checker', title: L('যাচাই (ব্যবস্থাপনা)', 'Check (management)'), fields: [
      CK('mgmt_checked', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা: লেজার যাচাই করেছি', 'Checked by management: ledger checked'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], v = {}; let bal = num(x.d.opening);
    const out = rows.map((r) => { if (!(has(r.bill) || has(r.debit) || has(r.pay))) return {}; bal += num(r.bill) - num(r.debit) - num(r.pay); return { bal }; });
    v.due = bal; v.master_total = sum(x.rows('master').map((r) => r.m_due));
    if (out.some((o) => o.bal !== undefined && o.bal < 0)) flags.push(flag('overpaid', 'yellow', 'সাপ্লায়ারকে পাওনার চেয়ে বেশি দেওয়া হয়েছে (বকেয়া ঋণাত্মক)', 'The supplier was paid more than is due (balance below zero)', Math.min(...out.filter((o) => o.bal !== undefined).map((o) => o.bal))));
    if (has(x.d.verifier) && has(x.d.keeper) && x.d.verifier === x.d.keeper) flags.push(flag('verifier_is_keeper', 'red', 'হিসাবের তথ্যের যাচাইকারী ও হিসাবরক্ষক একই জন', 'The account details checker is the ledger keeper', undefined));
    if (has(x.d.chg_approver) && has(x.d.keeper) && x.d.chg_approver === x.d.keeper) flags.push(flag('change_approver_is_keeper', 'red', 'তথ্য বদলের অনুমোদনকারী ও হিসাবরক্ষক একই জন', 'The change approver is the ledger keeper', undefined));
    if (rows.some((r) => num(r.pay) > 0) && !has(x.d.verifier)) flags.push(flag('pay_before_verify', 'red', 'হিসাবের তথ্য যাচাই ছাড়াই পেমেন্ট লেখা হয়েছে', 'A payment is written before the account details were checked', undefined));
    return { v, rows: { lines: out }, flags, needs: [] };
  },
};

/* ============ Forms <-> stock ledger links (phase20) ============
   Switch `forms_post_to_ledger` (default OFF) + one switch per form (forms_ledger_cfg). When it is on, an approved 13-1 / 18-1 / 36-1 / 39-1 / 12-1 posts to the stock ledger on the server
   (entry_post_ledger, a trigger on entries): nothing is typed twice.  Then 37-1 (store ledger) and 38-1 (supplier ledger) open as READ views over stock_ledger_rows / supplier_ledger;
   the old paper-form entry stays one tap away ("paper entries") and is the only screen while the switch is off. Page #/ledgerlinks: the switches and the "could not post" retry list. */
{
const A = window.BOS_APP, { sb, S, esc, toast, fail, shell, fmt } = A, lab = B.lab;
const $ = (q, el = document) => el.querySelector(q);
const X = {
  title: L('ফর্ম ও স্টক লেজারের যোগ', 'Forms and the stock ledger', 'Form ও Stock ledger যোগ'), master: L('অ্যাপ্রুভের সময় স্টক লেজারে নিজে পোস্ট', 'Post to the stock ledger when a form is approved', 'Approve হলে stock ledger-এ নিজে পোস্ট'),
  masterHint: L('বন্ধ থাকলে কিছুই বদলায় না। চালু করার আগে পুরোনো অ্যাপ্রুভড ফর্ম নিজে থেকে পোস্ট হয় না।', 'Off = nothing changes. Forms approved before you switch it on are not posted by themselves.', 'Off = কিছুই বদলায় না।'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), forms: L('ফর্ম অনুযায়ী', 'Per form', 'Per form'), problems: L('পোস্ট হয়নি / বাদ গেছে', 'Not posted / skipped', 'Not posted / skipped'),
  none: L('কোনো সমস্যা নেই ✓', 'No problems ✓', 'কোনো সমস্যা নেই ✓'), retry: L('আবার চেষ্টা', 'Retry', 'Retry'), failed: L('ব্যর্থ', 'failed', 'failed'), skipped: L('বাদ', 'skipped', 'skipped'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), retried: L('আবার চেষ্টা হয়েছে', 'Retried', 'Retried'), nonowner: L('শুধু মালিক বদলাতে পারেন', 'Only the owner can change these', 'Only the owner can change these'),
  f04_1: L('GRN — মালামাল গ্রহণ', 'GRN — goods received', 'GRN'), f04_2: L('ইস্যু স্লিপ', 'Issue slip', 'Issue slip'), f04_3: L('স্টক কাউন্ট শিট', 'Stock count sheet', 'Count sheet'), f03_1: L('ট্রান্সফার চালান', 'Transfer challan', 'Transfer challan'), f05_1: L('কারখানা দৈনিক শিট', 'Factory daily sheet', 'Factory sheet'),
  sl_title: L('স্টোর লেজার (শুধু দেখা)', 'Store ledger (read only)', 'Store ledger (শুধু দেখা)'), sup_title: L('সাপ্লায়ার লেজার (শুধু দেখা)', 'Supplier ledger (read only)', 'Supplier ledger (শুধু দেখা)'),
  fromforms: L('অ্যাপ্রুভড ফর্ম ও স্টক পেজ থেকে নিজে আসে — এখানে টাইপ করতে হয় না।', 'Filled by itself from approved forms and the stock page: nothing to type here.', 'Approved form ও stock page থেকে নিজে আসে।'),
  paper: L('কাগজের ফর্মের এন্ট্রি', 'Paper-form entries', 'Paper form entries'), place: L('লোকেশন', 'Place', 'Place'), search: L('আইটেম খুঁজুন…', 'Search item…', 'Item খুঁজুন…'), noitems: L('কোনো আইটেম নেই', 'No items', 'No items'),
  qty: L('Qty', 'Quantity', 'Quantity'), bal: L('বাকি', 'Balance', 'Balance'), noledg: L('এই আইটেমে এখনও লেনদেন নেই', 'No movements yet for this item', 'No movements yet'), back: L('← তালিকা', '← List', '← List'),
  stockpage: L('স্টক পেজ', 'Stock page', 'Stock page'), allp: L('সব লোকেশন', 'All places', 'All places'), sup: L('সাপ্লায়ার', 'Supplier', 'Supplier'), due: L('এখন বকেয়া', 'Due now', 'Due now'),
  nosup: L('কোনো সাপ্লায়ার নেই', 'No suppliers', 'No suppliers'), debit: L('বিল / বকেয়া বাড়ে', 'Bill (adds)', 'Bill (adds)'), credit: L('পেমেন্ট (কমে)', 'Payment (reduces)', 'Payment (reduces)'), purpage: L('ক্রয় ও বকেয়া পেজ', 'Purchase and payables page', 'Purchase page'),
  r_opening: L('শুরুর জের', 'Opening', 'Opening'), r_purchase_in: L('ক্রয়ে এল', 'Purchase in', 'Purchase in'), r_purchase_return: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), r_sale_out: L('সেল', 'Sale', 'Sale'), r_sale_void_in: L('সেল ভয়েড', 'Sale voided', 'Sale voided'),
  r_sale_return: L('সেল ফেরত', 'Sale return', 'Sale return'), r_issue_out: L('উৎপাদনে ইস্যু', 'Issued', 'Issued'), r_production_in: L('উৎপাদিত', 'Produced', 'Produced'), r_transfer_out: L('ট্রান্সফার আউট', 'Transfer out', 'Transfer out'),
  r_transfer_in: L('ট্রান্সফার ইন', 'Transfer in', 'Transfer in'), r_wastage: L('অপচয়', 'Wastage', 'Wastage'), r_count_adjust: L('কাউন্টের সমন্বয়', 'Count adjustment', 'Count adjustment'), r_reversal: L('ফেরানো', 'Reversal', 'Reversal'),
  k_bill: L('বিল', 'Bill', 'Bill'), k_paid: L('পরিশোধ', 'Paid', 'Paid'), k_payment: L('পেমেন্ট', 'Payment', 'Payment'), k_return: L('ফেরত', 'Return', 'Return'), k_refund: L('সাপ্লায়ারের ফেরত টাকা', 'Supplier refund', 'Supplier refund'), k_opening: L('শুরুর জের', 'Opening', 'Opening'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), pick: L('একটি সাপ্লায়ার বাছুন', 'Pick a supplier', 'Pick a supplier'), more: L('সর্বশেষ ১০০টি', 'Latest 100', 'Latest 100'),
};
const T = (k) => lab(X[k]);
const money = (n) => (n === null || n === undefined ? '—' : '৳ ' + fmt(Math.round(Number(n) * 100) / 100));
const FORMS5 = [['13-1', 'f04_1'], ['18-1', 'f04_2'], ['36-1', 'f04_3'], ['39-1', 'f03_1'], ['12-1', 'f05_1']];
const LS = { master: false, cfg: {}, loaded: false };
async function loadSwitches() {
  const [r, c] = await Promise.all([sb.from('rules').select('key,value,default_value').eq('key', 'forms_post_to_ledger'), sb.from('forms_ledger_cfg').select('form_code,is_on')]);
  const row = !r.error && r.data && r.data[0]; const v = row ? (row.value !== null && row.value !== undefined ? row.value : row.default_value) : false;
  LS.master = v === true || v === 'true'; LS.cfg = {}; (!c.error && c.data ? c.data : []).forEach((x) => { LS.cfg[x.form_code] = x.is_on !== false; }); LS.loaded = true;
}
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const LOCS = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); return isOwner() || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const allPlaces = () => isOwner() || (S.ctx.roles || []).includes('management');
const RS = { loc: null, q: '', item: null, sup: null, paper: null };

/* ----- styles (own prefix) ----- */
if (!document.getElementById('lk_css')) { const st = document.createElement('style'); st.id = 'lk_css'; st.textContent = `
.lk-row{display:flex;justify-content:space-between;align-items:center;gap:10px;min-height:52px;padding:8px 0;border-bottom:1px solid var(--line,#0001);text-align:start}
.lk-row:last-child{border-bottom:0} .lk-row .nm{font-weight:700} .lk-row .sub{font-size:.8rem;color:var(--muted)}
.lk-num{font-variant-numeric:tabular-nums;font-weight:700;white-space:nowrap} .lk-pos{color:var(--sig-ok)} .lk-neg{color:var(--sig-bad)}
.lk-sw{display:flex;gap:6px} .lk-sw button{min-height:44px;padding:0 14px}
.lk-note{font-size:.85rem;margin:6px 0 10px}`; document.head.appendChild(st); }

/* ----- the read views for 37-1 and 38-1 ----- */
async function viewStoreLedger() {
  shell(T('sl_title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, true);
  const locs = LOCS(); if (!RS.loc || !locs.find((l) => l.id === RS.loc)) RS.loc = (locs[0] || {}).id;
  const nm = A.nm;
  const head = `<div class="notice ok lk-note">${esc(T('fromforms'))}</div>
    <div class="row wrap" style="margin-bottom:8px"><select id="lk_loc" aria-label="${esc(T('place'))}" style="flex:1">${locs.map((l) => `<option value="${l.id}" ${l.id === RS.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
    <button data-act="lk_stock">${esc(T('stockpage'))}</button><button data-act="lk_paper" data-v="37-1">${esc(T('paper'))}</button></div>`;
  if (RS.item) {
    const lv = await sb.rpc('stock_levels', { p_loc: RS.loc, p_filters: { item_ids: [RS.item.item_id], include_zero: true } });
    const lr = await sb.rpc('stock_ledger_rows', { p_loc: RS.loc, p_item: RS.item.item_id, p_from: null, p_to: null, p_limit: 100 });
    if (lr.error) return fail(lr.error);
    const cur = lv.data && lv.data[0] ? Number(lv.data[0].qty) : null; let bal = cur;
    const rows = (lr.data || []).map((r) => { const o = { r, after: bal }; if (bal !== null) bal = Math.round((bal - Number(r.qty_delta)) * 10000) / 10000; return o; });
    shell(T('sl_title'), head + `<div class="row between" style="margin:6px 0"><button data-act="lk_back">${esc(T('back'))}</button><b>${esc(nm(RS.item))} · ${cur === null ? '—' : esc(fmt(cur))} ${esc(RS.item.base_unit || '')}</b></div>
      <div class="card" style="padding:4px 12px">${rows.length ? rows.map(({ r, after }) => `<div class="lk-row"><div><div class="nm">${esc(lab(X['r_' + r.reason] || L(r.reason, r.reason)))}</div><div class="sub">${esc(String(r.made_at || '').slice(0, 16).replace('T', ' '))}${r.note ? ' · ' + esc(String(r.note).slice(0, 60)) : ''}</div></div>
        <div style="text-align:end"><div class="lk-num ${Number(r.qty_delta) >= 0 ? 'lk-pos' : 'lk-neg'}">${Number(r.qty_delta) >= 0 ? '+' : '−'}${esc(fmt(Math.abs(Number(r.qty_delta))))}</div><div class="sub">${esc(T('bal'))} ${after === null ? '—' : esc(fmt(after))}</div></div></div>`).join('') : `<p class="muted center pad">${esc(T('noledg'))}</p>`}</div>
      <p class="muted lk-note">${esc(T('more'))}</p>`, true);
  } else {
    const r = await sb.rpc('stock_levels', { p_loc: RS.loc, p_filters: { q: RS.q || undefined, include_zero: true } });
    if (r.error) return fail(r.error);
    shell(T('sl_title'), head + `<input id="lk_q" type="search" placeholder="${esc(T('search'))}" value="${esc(RS.q)}" style="width:100%;margin-bottom:8px">
      <div class="card" style="padding:4px 12px">${(r.data || []).length ? r.data.map((x) => `<button class="lk-row" style="width:100%;background:transparent;border:0;border-bottom:1px solid var(--line,#0001);box-shadow:none;color:inherit" data-act="lk_item" data-v="${esc(x.item_id)}"><span><span class="nm">${esc(nm(x))}</span><span class="sub"> ${esc(x.code || '')}</span></span><span class="lk-num">${esc(fmt(x.qty))} ${esc(x.base_unit || '')}</span></button>`).join('') : `<p class="muted center pad">${esc(T('noitems'))}</p>`}</div>`, true);
    RS.levels = r.data || [];
  }
}
async function viewSupplierLedger() {
  shell(T('sup_title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, true);
  const locs = LOCS(), all = allPlaces();
  if (RS.loc === undefined || (RS.loc !== null && !locs.find((l) => l.id === RS.loc))) RS.loc = all ? null : (locs[0] || {}).id;
  const nm = A.nm;
  const head = `<div class="notice ok lk-note">${esc(T('fromforms'))}</div>
    <div class="row wrap" style="margin-bottom:8px"><select id="lk_loc" aria-label="${esc(T('place'))}" style="flex:1">${all ? `<option value="" ${RS.loc === null ? 'selected' : ''}>${esc(T('allp'))}</option>` : ''}${locs.map((l) => `<option value="${l.id}" ${l.id === RS.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
    <button data-act="lk_purpage">${esc(T('purpage'))}</button><button data-act="lk_paper" data-v="38-1">${esc(T('paper'))}</button></div>`;
  if (RS.sup) {
    const r = await sb.rpc('supplier_ledger', { p_supplier: RS.sup.supplier_id, p_loc: RS.loc });
    if (r.error) return fail(r.error);
    const rows = r.data || [], last = rows.length ? rows[rows.length - 1] : null;
    shell(T('sup_title'), head + `<div class="row between" style="margin:6px 0"><button data-act="lk_back">${esc(T('back'))}</button><b>${esc(RS.sup.name)}${last ? ' · ' + esc(T('due')) + ' ' + money(last.balance) : ''}</b></div>
      <div class="card" style="padding:4px 12px">${rows.length ? rows.map((x) => `<div class="lk-row"><div><div class="nm">${esc(lab(X['k_' + x.kind] || L(x.kind, x.kind)))}${x.ref ? ' · ' + esc(x.ref) : ''}</div><div class="sub">${x.kind === 'opening' ? '' : esc(String(x.at || '').slice(0, 10))}${x.note ? ' · ' + esc(String(x.note).slice(0, 60)) : ''}</div></div>
        <div style="text-align:end"><div class="lk-num ${Number(x.debit) > 0 ? 'lk-neg' : 'lk-pos'}">${Number(x.debit) > 0 ? '+' + money(x.debit) : '−' + money(x.credit)}</div><div class="sub">${esc(T('bal'))} ${money(x.balance)}</div></div></div>`).join('') : `<p class="muted center pad">${esc(T('noledg'))}</p>`}</div>`, true);
  } else {
    const r = await sb.rpc('supplier_dues', { p_loc: RS.loc });
    if (r.error) return fail(r.error);
    shell(T('sup_title'), head + `<div class="card" style="padding:4px 12px">${(r.data || []).length ? r.data.map((x) => `<button class="lk-row" style="width:100%;background:transparent;border:0;border-bottom:1px solid var(--line,#0001);box-shadow:none;color:inherit" data-act="lk_sup" data-v="${esc(x.supplier_id)}"><span class="nm">${esc(x.name)}</span><span class="lk-num">${money(x.balance)}</span></button>`).join('') : `<p class="muted center pad">${esc(T('nosup'))}</p>`}</div>`, true);
    RS.dues = r.data || [];
  }
}

/* ----- take over #/form/37-1 and #/form/38-1 only while the master switch is on ----- */
{
  const orig = (window.BOS_PAGES || {}).form;
  const leaveWatch = () => { if (RS.paper && !new RegExp('^#/?form/' + RS.paper + '(/|$)').test(location.hash)) RS.paper = null; };
  window.addEventListener('hashchange', leaveWatch);
  if (orig) window.BOS_PAGES.form = async function () {
    const code = location.hash.replace(/^#\/?/, '').split('/')[1];
    if ((code === '37-1' || code === '38-1') && RS.paper !== code) {
      try { await loadSwitches(); } catch (e) { LS.master = false; }
      if (LS.master) { RS.item = null; RS.sup = null; return code === '37-1' ? viewStoreLedger() : viewSupplierLedger(); }
    }
    return orig.apply(this, arguments);
  };
}

/* ----- #/ledgerlinks: switches + retry list ----- */
async function viewLinks() {
  shell(T('title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, true);
  await loadSwitches();
  const pr = await sb.rpc('ledger_post_problems', { p_loc: null });
  const rows = pr.error ? [] : (pr.data || []);
  const sw = (on, act, v) => `<div class="lk-sw"><button class="tog ${on ? 'on' : ''}" ${isOwner() ? '' : 'disabled'} data-act="${act}" data-v="${v}:1">${esc(T('on'))}</button><button class="tog ${!on ? 'on' : ''}" ${isOwner() ? '' : 'disabled'} data-act="${act}" data-v="${v}:0">${esc(T('off'))}</button></div>`;
  shell(T('title'), `<div class="card panel"><div class="lk-row"><span><span class="nm">${esc(T('master'))}</span><div class="sub">${esc(T('masterHint'))}</div></span>${sw(LS.master, 'lk_set', 'master')}</div>
      ${isOwner() ? '' : `<div class="muted lk-note">${esc(T('nonowner'))}</div>`}</div>
    <div class="hsec">${esc(T('forms'))}</div><div class="card" style="padding:4px 12px">${FORMS5.map(([c, k]) => `<div class="lk-row"><span><span class="nm">${esc(c)}</span> <span class="sub">${esc(T(k))}</span></span>${sw(LS.cfg[c] !== false, 'lk_set', c)}</div>`).join('')}</div>
    <div class="hsec">${esc(T('problems'))}</div><div class="card" style="padding:4px 12px">${rows.length ? rows.map((x) => `<div class="lk-row"><span><span class="nm">${esc(x.form_code)}-${esc(x.serial)}</span> <span class="sub">${esc(x.entry_date)} · ${Number(x.failed) ? esc(x.failed + ' ' + T('failed')) : ''}${Number(x.failed) && Number(x.skipped) ? ' · ' : ''}${Number(x.skipped) ? esc(x.skipped + ' ' + T('skipped')) : ''}${x.first_reason ? ' · ' + esc(String(x.first_reason).slice(0, 60)) : ''}</span></span>
      ${Number(x.failed) ? `<button data-act="lk_retry" data-v="${esc(x.entry_id)}">${esc(T('retry'))}</button>` : ''}</div>`).join('') : `<p class="muted center pad">${esc(T('none'))}</p>`}</div>`, true);
}

Object.assign(A.H, {
  lk_stock: () => { location.hash = '#/stock'; }, lk_purpage: () => { location.hash = '#/payables'; },
  lk_paper: (a) => { RS.paper = a.dataset.v; const r = (window.BOS_PAGES || {}).form; if (r) r(); },
  lk_back: () => { RS.item = null; RS.sup = null; return location.hash.indexOf('38-1') >= 0 ? viewSupplierLedger() : viewStoreLedger(); },
  lk_item: (a) => { RS.item = (RS.levels || []).find((x) => x.item_id === a.dataset.v) || null; return viewStoreLedger(); },
  lk_sup: (a) => { RS.sup = (RS.dues || []).find((x) => x.supplier_id === a.dataset.v) || null; return viewSupplierLedger(); },
  lk_set: async (a) => {
    if (!isOwner()) return;
    const [k, v] = a.dataset.v.split(':'), on = v === '1';
    if (k === 'master' && on && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true))) return;   // bos98 (W1-G): say what the switch will lock, before it is saved
    const r = k === 'master' ? await sb.rpc('set_rule', { p_key: 'forms_post_to_ledger', p_value: on }) : await sb.rpc('forms_ledger_cfg_set', { p_form: k, p_on: on });
    if (r.error) return fail(r.error); toast(T('saved')); return viewLinks();
  },
  lk_retry: async (a) => { const r = await sb.rpc('entry_post_ledger_retry', { p_entry: a.dataset.v }); if (r.error) return fail(r.error); toast(T('retried')); return viewLinks(); },
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'lk_loc') { RS.loc = e.target.value === '' ? null : Number(e.target.value); RS.item = null; RS.sup = null;
  if (/form\/38-1/.test(location.hash)) viewSupplierLedger(); else if (/form\/37-1/.test(location.hash)) viewStoreLedger(); } });
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'lk_q') { RS.q = e.target.value; clearTimeout(RS.tm); RS.tm = setTimeout(viewStoreLedger, 300); } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { ledgerlinks: viewLinks });
B.reportLinks = B.reportLinks || [];
B.reportLinks.push({ key: 'ledgerlinks', route: 'ledgerlinks', label: () => T('title'), allowed: null,
  check: async () => { const l = B.reportLinks.find((x) => x.key === 'ledgerlinks'); if (isOwner()) { l.allowed = true; return; }
    try { const r = await sb.rpc('ledger_post_problems', { p_loc: null }); l.allowed = !!(r && !r.error && (r.data || []).length > 0); } catch (e) { l.allowed = false; } } });
}
})();
