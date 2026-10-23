/* Islamia BOS · staff & people forms (batch E), taken from the BOS Build Kit v1.39:
   19-1 Monthly Attendance Register, 21-1 Monthly Salary Sheet, 35-1 Staff Advance Register, 01-1 Appointment Letter,
   15-1 Leave Application, 10-1 Exit Clearance, 09-1 Duty & Backup Card, 34-1 Skill Checklist, 33-1 Shift Handover Register.
   Salary figures and rates are the owner's data: entry fields only, nothing is calculated from an invented rate. */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO } = B.f;
B.forms = B.forms || {};

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const QTY = { unit: 'qty' };
function tol(diff, limit) { if (diff === 0) return null; if (limit === null || limit === undefined) return 'red'; return Math.abs(diff) <= limit ? 'yellow' : 'red'; }
const anyRow = (r) => Object.values(r || {}).some(has);
const MONTHS = [['1', L('জানুয়ারি', 'January')], ['2', L('ফেব্রুয়ারি', 'February')], ['3', L('মার্চ', 'March')], ['4', L('এপ্রিল', 'April')], ['5', L('মে', 'May')], ['6', L('জুন', 'June')],
  ['7', L('জুলাই', 'July')], ['8', L('আগস্ট', 'August')], ['9', L('সেপ্টেম্বর', 'September')], ['10', L('অক্টোবর', 'October')], ['11', L('নভেম্বর', 'November')], ['12', L('ডিসেম্বর', 'December')]];
const PAYM = [['bank', L('ব্যাংক', 'Bank')], ['mobile', L('মোবাইল', 'Mobile')], ['cash', L('নগদ', 'Cash')], ['owner', L('মালিকের ব্যক্তিগত', "Owner's personal")], ['other', L('অন্য', 'Other')]];
const monthInit = (x, d) => { const dt = new Date(x.date + 'T12:00:00'); if (!has(d.month)) d.month = String(dt.getMonth() + 1); if (!has(d.year)) d.year = String(dt.getFullYear()); };
const monthDays = (x) => { let m = num(x.d.month), y = num(x.d.year); if (!m || !y) { const dt = new Date(x.date + 'T12:00:00'); m = m || dt.getMonth() + 1; y = y || dt.getFullYear(); } return new Date(y, m, 0).getDate(); };
const monthHead = () => [SEL('month', L('মাস', 'Month'), MONTHS, { req: true }), N('year', L('বছর', 'Year'), { req: true })];
const dayDiff = (a, b) => Math.round((new Date(b + 'T12:00:00') - new Date(a + 'T12:00:00')) / 86400000) + 1;

/* ============ 19-1 · Monthly attendance register ============ */
B.forms['19-1'] = {
  title: L('মাসিক হাজিরা', 'Monthly Attendance', 'মাসিক হাজিরা'),
  head: monthHead(),
  init: monthInit,
  sections: [
    { title: L('নিয়ম', 'Rules'), fields: [
      NOTE(L('হাজিরা প্রতিদিন লেখা হবে — মাস শেষে মনে করে নয়। বেতন ও অনুপস্থিতির হিসাব এই রেজিস্টার থেকেই আসবে; অন্য কোনো উৎস থেকে নয়।', 'Attendance is written every day — not from memory at month end. Salary and absence figures come from this register and nowhere else.'), 'warn'),
      NOTE(L('চিহ্ন: উ = উপস্থিত · অ = অনুপস্থিত · ছ = ছুটি (বিনা বেতনের) · স = সবেতন ছুটি · দ = দেরিতে উপস্থিত · শ 1 / শ 2 = কোন শিফট · ও = ওভারটাইম (ঘণ্টা) · ল = অন্য লোকেশনে কাজ। ছুটির চিহ্ন আসে ছুটির আবেদন ফরম (15-1) থেকে। নিচে প্রতিটি চিহ্নের দিন-সংখ্যা লিখুন।',
        'Marks: P = present · A = absent · U = unpaid leave · PL = paid leave · Late = present but late · S1 / S2 = shift · OT = overtime (hours) · OL = worked at another location. Leave marks come from the Leave Application (15-1). Enter the number of days for each mark below.', 'চিহ্ন: উ = উপস্থিত · অ = অনুপস্থিত · ছ = ছুটি (বিনা বেতনের) · স = সবেতন ছুটি · দ = দেরিতে উপস্থিত · শ 1 / শ 2 = কোন Shift · ও = ওভারটাইম (ঘণ্টা) · ল = অন্য Location-এ কাজ। ছুটির চিহ্ন আসে ছুটির আবেদন Form (15-1) থেকে। নিচে প্রতিটি চিহ্নের দিন-সংখ্যা লিখুন।'), 'ok'),
      NOTE(L('অনুপস্থিতি, ওভারটাইম বা অন্য লোকেশনে কাজ থাকলে কোন কোন তারিখে — তা অবশ্যই লিখুন; দিন-সংখ্যা একা প্রমাণ নয়। অনুপস্থিতি বা ছুটি থাকলে দায়িত্বধারী (Delegate) লিখতে হবে।', 'If there is absence, overtime or other-location work, the dates must be written — day counts alone are not evidence. If there is absence or leave, a delegate must be named.'), 'warn'),
      NOTE(L('উপস্থিত + অনুপস্থিত + ছুটি = মোট দিন = মাসের দিন সংখ্যা', 'Present + Absent + Leave = Total days = number of days in the month'), 'warn')] },
    { title: L('কর্মীদের হাজিরা (প্রতি কর্মীর জন্য একটি কার্ড)', 'Staff attendance (one card per person)'), fields: [
      TABLE('staff', null, [T('name', L('নাম ও পদ', 'Name & post'), { req: true, wide: true }),
        N('present', L('উপস্থিত (উ)', 'Present'), { req: true }), N('late', L('এর মধ্যে দেরিতে (দ)', 'of which late'), {}),
        N('absent', L('অনুপস্থিত (অ)', 'Absent'), { req: true }), N('leave_unpaid', L('ছুটি — বিনা বেতনের (ছ)', 'Leave — unpaid'), {}), N('leave_paid', L('ছুটি — সবেতন (স)', 'Leave — paid'), {}),
        CALC('total', L('মোট দিন', 'Total days'), 'num'), CALC('sum_ok', L('মাসের দিনের সাথে মিল', 'Match with days in month'), 'text'),
        N('shift1', L('শিফট 1 (শ 1) — দিন', 'Shift 1 — days'), {}), N('shift2', L('শিফট 2 (শ 2) — দিন', 'Shift 2 — days'), {}),
        N('ot_hours', L('ওভারটাইম (ও) — মোট ঘণ্টা', 'Overtime — total hours'), {}), N('other_loc', L('অন্য লোকেশনে কাজ (ল) — দিন', 'Other-location work — days'), {}),
        T('dates_note', L('অনুপস্থিতি / ওভারটাইম / ল-এর তারিখ ও মন্তব্য', 'Dates & remarks for absence / overtime / other-location'), { wide: true, req: (x) => num(x.row.absent) > 0 || num(x.row.ot_hours) > 0 || num(x.row.other_loc) > 0 })], { min: 3 })] },
    { title: L('অনুপস্থিতি ও দায়িত্ব', 'Absence & cover'), fields: [
      TABLE('delegates', L('অনুপস্থিতিতে দায়িত্বধারী (Delegate) — অনুপস্থিতি বা ছুটি থাকলে বাধ্যতামূলক', 'Delegate during absence — required when there is absence or leave'), [D('date', L('তারিখ', 'Date'), { req: true }), T('person', L('কর্মী (দায়িত্বধারী)', 'Staff (delegate)'), { req: true, wide: true })], { min: 1 }),
      CH('leave_informed', L('ছুটি আগে জানানো হয়েছিল?', 'Was leave informed in advance?'), YN),
      N('not_informed_n', L('না হলে — কতবার', 'If not — how many times'), { show: (x) => x.d.leave_informed === 'no' }),
      TABLE('other_loc', L('অন্য লোকেশনে কাজ (ল)', 'Work at another location (OL)'), [D('date', L('তারিখ', 'Date')), T('person', L('কর্মী', 'Staff')), T('place', L('স্থান', 'Place'))], { min: 1 }),
      N('sudden_n', L('এ মাসে হঠাৎ অনুপস্থিতি (বার)', 'Sudden absences this month (times)')),
      CK('work_list', L('বারবার হলে কাজের তালিকায় তোলা হয়েছে', 'If repeated, put on the work list'))] },
    { title: L('অস্থায়ী শ্রমিক (Temporary Worker) — দিনের মজুরিতে', 'Temporary workers — daily wage'), fields: [
      TABLE('temps', null, [T('name', L('অস্থায়ী শ্রমিকের নাম', 'Worker name'), { req: true, wide: true }), T('id_no', L('পরিচয়পত্র নং', 'ID no.')), D('date', L('তারিখ', 'Date'), { req: true }),
        T('work', L('কাজের বিবরণ', 'Work description'), { wide: true }), M('wage', L('মজুরি ৳', 'Wage ৳'), { req: true }),
        T('ref', L('ব্যয় ভাউচার বা লেজারের লাইন নং', 'Expense voucher or ledger line no.'), { req: (x) => num(x.row.wage) > 0 }), CK('signed', L('শ্রমিকের স্বাক্ষর নেওয়া হয়েছে', 'Worker signed'))], { min: 1 }),
      CALC('temp_total', L('অস্থায়ী মজুরির মোট', 'Temporary wages total'), 'money')] },
    { title: L('স্বাক্ষর ও জমা', 'Sign-off & submission'), fields: [
      CK('hub_submitted', L('মাস শেষে হাবে জমা', 'Submitted to the hub at month end')), D('hub_date', L('জমার তারিখ', 'Submission date'))] },
    { who: 'checker', title: L('যাচাই (ব্যবস্থাপনা)', 'Check (management)'), fields: [
      CK('mgmt_checked', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা: রেজিস্টার যাচাই করা হয়েছে', 'Checked by management: register verified'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const days = monthDays(x), rows = x.rows('staff'), flags = [], needs = [];
    let bad = 0, lateBad = 0;
    const out = rows.map((r) => {
      const total = num(r.present) + num(r.absent) + num(r.leave_unpaid) + num(r.leave_paid);
      let ok = '';
      if (anyRow(r)) { const df = total - days; ok = df === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('অমিল: ' + fm(df) + ' দিন', 'Mismatch: ' + fm(df) + ' days'); if (df !== 0) bad++; if (num(r.late) > num(r.present)) lateBad++; }
      return { total, sum_ok: ok };
    });
    if (bad) flags.push(flag('att_total_mismatch', 'red', 'উপস্থিত + অনুপস্থিত + ছুটি মাসের দিন সংখ্যার সমান নয় (কর্মীর সংখ্যা)', 'Present + absent + leave differs from the days in the month (staff count)', bad, QTY));
    if (lateBad) flags.push(flag('late_over_present', 'red', 'দেরিতে উপস্থিতের দিন উপস্থিতের চেয়ে বেশি', 'Late days are more than present days', lateBad, QTY));
    if (rows.some((r) => num(r.absent) + num(r.leave_unpaid) + num(r.leave_paid) > 0) && !x.rows('delegates').some((r) => has(r.person))) flags.push(flag('delegate_missing', 'red', 'অনুপস্থিতি / ছুটি আছে কিন্তু দায়িত্বধারী (Delegate) লেখা নেই', 'Absence / leave recorded but no delegate named'));
    if (num(x.d.sudden_n) > 0) flags.push(flag('sudden_absence', 'yellow', 'এ মাসে হঠাৎ অনুপস্থিতি আছে (বার)', 'Sudden absences this month (times)', num(x.d.sudden_n), QTY));
    const temps = x.rows('temps'), tt = sum(temps.map((r) => r.wage));
    if (temps.some((r) => num(r.wage) > 0 && !r.signed)) flags.push(flag('temp_unsigned', 'yellow', 'অস্থায়ী শ্রমিকের স্বাক্ষর নেই', 'A temporary worker has not signed'));
    return { v: { temp_total: tt }, rows: { staff: out }, flags, needs };
  },
};

/* ============ 21-1 · Monthly salary sheet ============ */
B.forms['21-1'] = {
  title: L('মাসিক বেতন', 'Monthly Salary', 'মাসিক বেতন'),
  head: [...monthHead(), T('attendance_no', L('মাসিক হাজিরা রেজিস্টার নং', 'Monthly attendance register no.'))],
  init: monthInit,
  sections: [
    { title: L('নিয়ম', 'Rules'), fields: [
      NOTE(L('মাসিক হাজিরা রেজিস্টার ছাড়া বেতন শিট তৈরি হবে না। অ্যাডভান্স কর্তনের পর বাকি টাকা দেওয়া হবে। প্রত্যেকের স্বাক্ষর ছাড়া কোনো টাকা প্রদান করা যাবে না। "অন্যান্য" বা "অন্য কর্তন" ঘরে কোনো অঙ্ক লেখা হলে কারণ লিখতেই হবে।',
        'No salary sheet without the Monthly Attendance Register. The balance is paid after the advance deduction. No payment without each person\'s signature. If any amount is written in "Other" or "Other deduction", the reason must be written.'), 'warn'),
      NOTE(L('বেতন ও হারের অঙ্ক মালিকের তথ্য — এখানে নিজে থেকে কোনো অঙ্ক হিসাব করা হয় না; যা লিখবেন তাই ধরা হবে।', 'Salary and rate figures are the owner\'s data — nothing is worked out from a rate here; the figures you enter are used as written.'), 'ok')] },
    { title: L('বেতনের তালিকা', 'Salary list'), fields: [
      TABLE('pay', null, [T('name', L('নাম ও পদ', 'Name & post'), { req: true, wide: true }), M('salary', L('মাসিক বেতন ৳', 'Monthly salary ৳'), { req: true }),
        N('work_days', L('কাজের দিন', 'Working days')), N('absent', L('অনুপস্থিত', 'Absent days')), N('leave', L('ছুটি', 'Leave days')),
        M('due', L('পাওনা বেতন ৳', 'Salary due ৳'), { req: true }), M('overtime', L('ওভারটাইম ৳', 'Overtime ৳')), M('other', L('অন্যান্য ৳', 'Other ৳')),
        CALC('gross', L('মোট পাওনা ৳', 'Total due ৳'), 'money'), M('adv_ded', L('অ্যাডভান্স কর্তন ৳', 'Advance deduction ৳'), { req: true }), M('other_ded', L('অন্য কর্তন ৳', 'Other deduction ৳')),
        CALC('net', L('নিট ৳', 'Net ৳'), 'money'), T('remark', L('কারণ / মন্তব্য', 'Reason / remark'), { req: true, wide: true })], { min: 3 }),
      CALC('t_salary', L('সর্বমোট — মাসিক বেতন', 'Grand total — monthly salary'), 'money'), CALC('t_due', L('সর্বমোট — পাওনা বেতন', 'Grand total — salary due'), 'money'),
      CALC('t_ot', L('সর্বমোট — ওভারটাইম', 'Grand total — overtime'), 'money'), CALC('t_other', L('সর্বমোট — অন্যান্য', 'Grand total — other'), 'money'),
      CALC('t_gross', L('সর্বমোট — মোট পাওনা', 'Grand total — total due'), 'money'), CALC('t_adv', L('সর্বমোট — অ্যাডভান্স কর্তন', 'Grand total — advance deduction'), 'money'),
      CALC('t_other_ded', L('সর্বমোট — অন্য কর্তন', 'Grand total — other deduction'), 'money'), CALC('t_net', L('সর্বমোট — নিট', 'Grand total — net'), 'money', { big: true })] },
    { title: L('পেমেন্ট', 'Payment'), fields: [
      SEL('pay_method', L('পেমেন্টের মাধ্যম (Payment Method)', 'Payment method'), PAYM, { req: true }),
      T('pay_other', L('অন্য মাধ্যম — লিখুন', 'Other method — write it'), { show: (x) => x.d.pay_method === 'other', req: (x) => x.d.pay_method === 'other' }),
      D('pay_date', L('পেমেন্টের তারিখ', 'Payment date')), D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date')), T('ledger_line', L('লাইন নং', 'Line no.')),
      CK('all_signed', L('প্রত্যেকের স্বাক্ষর নেওয়া হয়েছে — স্বাক্ষর ছাড়া টাকা দেওয়া যাবে না', 'Everyone has signed — no money without a signature'), { req: true })] },
    { title: L('প্রাপ্তি স্বীকার (Receipt Acknowledgement)', 'Receipt acknowledgement'), fields: [
      TABLE('receipts', null, [T('name', L('নাম', 'Name'), { req: true, wide: true }), M('net', L('নিট ৳', 'Net ৳'), { req: true }), D('date', L('তারিখ', 'Date')), SEL('method', L('মাধ্যম', 'Method'), PAYM),
        CK('signed', L('প্রাপকের স্বাক্ষর', "Recipient's signature"))], { min: 3 }),
      CALC('t_receipts', L('প্রাপ্তির মোট', 'Receipts total'), 'money')] },
    { who: 'checker', title: L('যাচাই ও অনুমোদন', 'Check & approval'), fields: [
      NOTE(L('যাচাইকারী প্রস্তুতকারী থেকে ভিন্ন ব্যক্তি হবেন।', 'The checker must be a different person from the preparer.'), 'warn', { who: 'checker' }),
      CK('checked', L('যাচাইকারী (Checked by) — হিসাব যাচাই করা হয়েছে', 'Checked by: figures verified'), { who: 'checker', req: true }),
      ST('approved_by', L('অনুমোদনকারী (Approved by)', 'Approved by'), { who: 'checker', req: true }), D('approved_date', L('অনুমোদনের তারিখ', 'Approval date'), { who: 'checker' })] },
  ],
  calc(x) {
    const rows = x.rows('pay'), flags = [], needs = [];
    let neg = 0, noReason = 0;
    const out = rows.map((r) => {
      const gross = num(r.due) + num(r.overtime) + num(r.other), net = gross - num(r.adv_ded) - num(r.other_ded);
      if (anyRow(r)) { if (net < 0) neg++; if ((num(r.other) > 0 || num(r.other_ded) > 0) && !has(r.remark)) noReason++; }
      return { gross, net };
    });
    const t = (k) => sum(rows.map((r) => r[k]));
    const tg = t('due') + t('overtime') + t('other'), tn = tg - t('adv_ded') - t('other_ded');
    if (neg) flags.push(flag('net_negative', 'red', 'নিট বেতন ঋণাত্মক (কর্মীর সংখ্যা)', 'Net pay is negative (staff count)', neg, QTY));
    if (noReason) flags.push(flag('other_no_reason', 'red', '"অন্যান্য" / "অন্য কর্তন"-এ অঙ্ক আছে কিন্তু কারণ লেখা নেই (কর্মীর সংখ্যা)', 'An "Other" / "Other deduction" amount has no reason written (staff count)', noReason, QTY));
    const rc = x.rows('receipts');
    if (rc.some((r) => num(r.net) > 0 && !r.signed)) flags.push(flag('paid_unsigned', 'red', 'স্বাক্ষর ছাড়া টাকা প্রদান — প্রাপ্তি স্বীকারে স্বাক্ষর নেই', 'Money paid without a signature on the receipt acknowledgement'));
    return { v: { t_salary: t('salary'), t_due: t('due'), t_ot: t('overtime'), t_other: t('other'), t_gross: tg, t_adv: t('adv_ded'), t_other_ded: t('other_ded'), t_net: tn, t_receipts: sum(rc.map((r) => r.net)) }, rows: { pay: out }, flags, needs };
  },
};

/* ============ 35-1 · Staff advance register ============ */
B.forms['35-1'] = {
  title: L('স্টাফ অ্যাডভান্স', 'Staff Advance', 'Staff Advance'),
  head: [T('page_no', L('পাতা নং', 'Page no.')), ST('staff', L('কর্মীর নাম', 'Employee'), { req: true }), T('post', L('পদ', 'Post'), { req: true }), LOC('staff_loc', L('লোকেশন', 'Location')), M('salary', L('মাসিক বেতন ৳', 'Monthly salary ৳'), { req: true })],
  sections: [
    { title: L('নিয়ম', 'Rules'), fields: [
      NOTE(L('অ্যাডভান্স দেওয়ার সময়েই লিখতে হবে — লিখিত ছাড়া কোনো অ্যাডভান্স নয়। মুখের কথায় কোনো অ্যাডভান্স নয়।', 'Write it at the moment the advance is given — no advance without writing. No verbal advances.'), 'warn'),
      NOTE(L('মাধ্যম: নগদ · ব্যাংক · মোবাইল · মালিকের ব্যক্তিগত। শোরুম থেকে বাকিতে মালামাল নিলে: কারণ ঘরে "মালামাল — কী, কত" লিখুন, দৈনিক শোরুম শিট নং দিন, মাধ্যম "মালামাল" বাছুন।',
        'Method: cash · bank · mobile · owner\'s personal. If goods are taken on credit from the showroom: write "Goods — what, how much" in the reason, give the daily showroom sheet no., and choose "Goods" as the method.'), 'ok')] },
    { title: L('অ্যাডভান্সের লাইন', 'Advance lines'), fields: [
      TABLE('adv', null, [D('date', L('তারিখ', 'Date'), { req: true }), T('reason', L('কারণ', 'Reason'), { req: true, wide: true }),
        M('amount', L('অ্যাডভান্স ৳', 'Advance ৳'), { req: true }),
        SEL('method', L('মাধ্যম', 'Method'), [['cash', L('নগদ', 'Cash')], ['bank', L('ব্যাংক', 'Bank')], ['mobile', L('মোবাইল', 'Mobile')], ['owner', L('মালিকের ব্যক্তিগত', "Owner's personal")], ['goods', L('মালামাল', 'Goods')]], { req: true }),
        T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.'), { show: (x) => x.row.method === 'goods', req: (x) => x.row.method === 'goods' }),
        D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date'), { show: (x) => x.row.method !== 'goods' }), T('ledger_line', L('লেজারের লাইন', 'Ledger line'), { show: (x) => x.row.method !== 'goods' }),
        ST('approver', L('অনুমোদনকারী', 'Approved by'), { req: true }), N('months', L('কর্তনের মেয়াদ (মাস)', 'Deduction period (months)')),
        M('ded_now', L('এ মাসে কর্তন ৳', 'Deduction this month ৳')), M('balance', L('বাকি ৳', 'Balance ৳'), { req: true }), CK('emp_signed', L('কর্মীর স্বাক্ষর', "Employee's signature"))], { min: 3 }),
      CALC('outstanding', L('মোট বকেয়া অ্যাডভান্স (Total Outstanding)', 'Total outstanding advance'), 'money', { big: true })] },
    { title: L('মিল ও সমাপ্তি', 'Matching & exit'), fields: [
      CK('match_payroll', L('এই পাতার বাকি অ্যাডভান্স মাসিক বেতন শিটের কর্তনের সাথে মিল আছে', 'The balance on this page matches the deduction on the Monthly Salary Sheet'), { req: true }),
      NOTE(L('পদত্যাগ / চাকরির অবসানের সময় বাকি অ্যাডভান্স ছাড়পত্রে (10-1) লিখতে হবে ও শেষ বেতন থেকে কাটতে হবে। অ্যাডভান্স বাকি থাকলে ছাড়পত্র দেওয়া যাবে না।', 'On resignation / termination the outstanding advance must be written on the Exit Clearance (10-1) and deducted from the final pay. No clearance while an advance is outstanding.', 'পদত্যাগ / চাকরির অবসানের Time বাকি Advance ছাড়পত্রে (10-1) লিখতে হবে ও শেষ বেতন থেকে কাটতে হবে। Advance বাকি থাকলে ছাড়পত্র দেওয়া যাবে না।'), 'warn'),
      M('exit_balance', L('পদত্যাগ / অবসানের সময় বাকি অ্যাডভান্স ৳', 'Outstanding advance at resignation / termination ৳')),
      CK('exit_deducted', L('শেষ বেতন থেকে কর্তন করা হয়েছে', 'Deducted from the final pay'), { show: (x) => num(x.d.exit_balance) > 0 }),
      CK('exit_clearance', L('ছাড়পত্রে (এক্সিট ক্লিয়ারেন্স) লেখা হয়েছে', 'Written on the Exit Clearance'), { show: (x) => num(x.d.exit_balance) > 0, req: (x) => num(x.d.exit_balance) > 0 })] },
    { who: 'checker', title: L('যাচাই (ব্যবস্থাপনা)', 'Check (management)'), fields: [
      CK('checked', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা: পাতা যাচাই করা হয়েছে', 'Checked by management: page verified'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('adv'), flags = [], needs = [];
    const outstanding = sum(rows.map((r) => r.balance));
    if (rows.some((r) => num(r.balance) > num(r.amount))) flags.push(flag('balance_over_advance', 'red', 'বাকি অ্যাডভান্স দেওয়া অ্যাডভান্সের চেয়ে বেশি', 'Balance is more than the advance given'));
    if (rows.some((r) => has(r.amount) && !r.emp_signed)) flags.push(flag('adv_unsigned', 'yellow', 'কর্মীর স্বাক্ষর নেওয়া হয়নি', 'Employee has not signed an advance line'));
    if (rows.some((r) => has(r.approver) && r.approver === x.d.staff)) flags.push(flag('self_approved_adv', 'red', 'কর্মী নিজেই নিজের অ্যাডভান্স অনুমোদন করেছেন', 'The employee approved their own advance'));
    if (num(x.d.exit_balance) > 0 && !x.d.exit_deducted) flags.push(flag('exit_adv_pending', 'yellow', 'চাকরি ছাড়ার সময়ের বাকি অ্যাডভান্স এখনো শেষ বেতন থেকে কাটা হয়নি', 'Outstanding advance at exit is not yet deducted from the final pay', num(x.d.exit_balance)));
    return { v: { outstanding }, flags, needs };
  },
};

/* ============ 01-1 · Appointment letter — terms & duties ============ */
B.forms['01-1'] = {
  title: L('নিয়োগপত্র', 'Appointment Letter', 'নিয়োগপত্র'),
  head: [T('reg_no', L('কর্মী রেজিস্ট্রেশন ফরম নং', 'Employee registration form no.')), ST('staff', L('কর্মীর নাম', 'Employee'), { req: true }), T('post', L('পদ', 'Post'), { req: true }),
    LOC('staff_loc', L('লোকেশন', 'Location'), { req: true }), D('join_date', L('যোগদানের তারিখ', 'Joining date'), { req: true })],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [
      NOTE(L('এই পত্র ছাড়া নিয়োগ সম্পূর্ণ নয়। শর্তগুলো একজনই ব্যাখ্যা করবেন। কর্মী ও প্রতিষ্ঠান দুজনেই এক কপি রাখবেন।', 'Appointment is not complete without this letter. One person alone explains the terms. Both the employee and the business keep a copy.'), 'warn'),
      NOTE(L('বেতন, পেমেন্টের মাধ্যম ও আইনি ঘোষণা কর্মী রেজিস্ট্রেশন ফরমে (Employee Registration Form) আছে। এখানে আবার লেখা হবে না।', 'Salary, payment method and legal declaration are on the Employee Registration Form. They are not written again here.'), 'ok')] },
    { title: L('Section A · নিয়োগের শর্ত (Terms of Appointment)', 'Section A · Terms of appointment'), fields: [
      N('probation_months', L('শিক্ষানবিশকাল (Probation) — মাস', 'Probation — months')), N('probation_notice', L('শিক্ষানবিশকালে নোটিশ — দিন', 'Notice during probation — days')),
      CK('ack_probation', L('কর্মী অবগত — শিক্ষানবিশকাল', 'Employee acknowledged — probation')),
      TA('confirm_terms', L('স্থায়ী হওয়ার শর্ত', 'Conditions for confirmation')), CK('ack_confirm', L('কর্মী অবগত — স্থায়ী হওয়ার শর্ত', 'Employee acknowledged — confirmation')),
      CK('off_friday', L('সাপ্তাহিক ছুটি — শুক্রবার', 'Weekly off — Friday')), T('off_other', L('সাপ্তাহিক ছুটি — অন্য দিন', 'Weekly off — other day')), N('off_per_month', L('মাসে ছুটির দিন', 'Off days per month')),
      CK('ack_weekly', L('কর্মী অবগত — সাপ্তাহিক ছুটি', 'Employee acknowledged — weekly off')),
      N('festival_days', L('উৎসব ছুটি — বছরে কত দিন', 'Festival holidays — days per year')), T('festival_dates', L('উৎসব ছুটির তারিখ', 'Festival holiday dates')), CK('ack_festival', L('কর্মী অবগত — উৎসব ছুটি', 'Employee acknowledged — festival holidays')),
      N('annual_days', L('বার্ষিক ছুটি (সবেতন) — বছরে কত দিন', 'Annual leave (paid) — days per year')), CK('ack_annual', L('কর্মী অবগত — বার্ষিক ছুটি', 'Employee acknowledged — annual leave')),
      N('notice_emp', L('নোটিশ (Notice Period) — কর্মীর পক্ষে দিন', 'Notice period — by the employee (days)')), N('notice_org', L('নোটিশ — প্রতিষ্ঠানের পক্ষে দিন', 'Notice period — by the business (days)')),
      CK('ack_notice', L('কর্মী অবগত — চাকরির অবসানের নোটিশ', 'Employee acknowledged — notice period')),
      TA('bonus', L('উৎসব বোনাস (Festival Bonus)', 'Festival bonus')), CK('ack_bonus', L('কর্মী অবগত — উৎসব বোনাস', 'Employee acknowledged — festival bonus')),
      CH('lodging', L('থাকা / খাওয়া', 'Lodging / meals'), [['na', L('প্রযোজ্য নয়', 'Not applicable')], ['yes', L('আছে', 'Provided')]]),
      T('lodging_detail', L('থাকা / খাওয়ার বিবরণ', 'Lodging / meals details'), { show: (x) => x.d.lodging === 'yes', req: (x) => x.d.lodging === 'yes' }), CK('ack_lodging', L('কর্মী অবগত — থাকা / খাওয়া', 'Employee acknowledged — lodging / meals'))] },
    { title: L('Section B · এই পদের দায়িত্ব (Duties)', 'Section B · Duties of this post'), fields: [
      TABLE('duties', null, [T('duty', L('এই পদের দায়িত্ব', 'Duty of this post'), { req: true, wide: true }), T('forms', L('ব্যবহারের ফর্ম (Forms Handled)', 'Forms handled'), { wide: true })], { min: 4 }),
      T('delegate', L('অনুপস্থিতিতে দায়িত্বধারী (Delegate) — পদ / নাম', 'Delegate when absent — post / name'), { req: true }), T('reports_to', L('রিপোর্টিং পদ (Reports to) — পদ / নাম', 'Reports to — post / name')),
      CH('keys', L('চাবির দায়িত্ব', 'Key responsibility'), [['na', L('প্রযোজ্য নয়', 'Not applicable')], ['yes', L('আছে', 'Yes')]]), T('keys_detail', L('কোন চাবি', 'Which keys'), { show: (x) => x.d.keys === 'yes' })] },
    { title: L('স্বাক্ষর', 'Signatures'), fields: [
      CK('emp_signed', L('কর্মীর স্বাক্ষর (Employee) নেওয়া হয়েছে', 'Employee signed'), { req: true }), D('emp_date', L('কর্মীর স্বাক্ষরের তারিখ', 'Employee signature date')),
      ST('explained_by', L('ব্যাখ্যাকারী (Explained by) — যিনি শর্ত বুঝিয়েছেন', 'Explained by — who explained the terms'), { req: true }), D('explained_date', L('ব্যাখ্যার তারিখ', 'Explained on'))] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      CK('approved', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by — management'), { who: 'checker', req: true }), D('approved_date', L('অনুমোদনের তারিখ', 'Approval date'), { who: 'checker' })] },
  ],
  calc(x) {
    const flags = [];
    const d = x.d, acks = [];
    if (has(d.probation_months) || has(d.probation_notice)) acks.push('ack_probation');
    if (has(d.confirm_terms)) acks.push('ack_confirm');
    if (d.off_friday || has(d.off_other) || has(d.off_per_month)) acks.push('ack_weekly');
    if (has(d.festival_days) || has(d.festival_dates)) acks.push('ack_festival');
    if (has(d.annual_days)) acks.push('ack_annual');
    if (has(d.notice_emp) || has(d.notice_org)) acks.push('ack_notice');
    if (has(d.bonus)) acks.push('ack_bonus');
    if (d.lodging === 'yes') acks.push('ack_lodging');
    if (x.d.emp_signed && acks.some((k) => !x.d[k])) flags.push(flag('terms_not_acknowledged', 'yellow', 'কর্মী সব শর্তে "অবগত" টিক পাননি', 'Some terms are not ticked as acknowledged by the employee'));
    if (has(x.d.explained_by) && x.d.explained_by === x.d.staff) flags.push(flag('explained_by_self', 'red', 'ব্যাখ্যাকারী ও কর্মী একই জন', 'The person who explained and the employee are the same'));
    return { v: {}, flags, needs: [] };
  },
};

/* ============ 15-1 · Leave application ============ */
B.forms['15-1'] = {
  title: L('ছুটির আবেদন', 'Leave Application', 'ছুটির আবেদন'),
  head: [ST('applicant', L('কর্মীর নাম (আবেদনকারী)', 'Employee (applicant)'), { req: true }), T('post', L('পদ', 'Post'), { req: true }), D('apply_date', L('আবেদনের তারিখ', 'Application date'), { req: true }), N('taken_year', L('এ বছরে নেওয়া ছুটি (দিন)', 'Leave taken this year (days)'))],
  init(x, d) { if (!has(d.apply_date)) d.apply_date = x.date; },
  sections: [
    { title: L('আবেদন', 'Application'), fields: [
      NOTE(L('ছুটি আগে জানাতে হবে — হঠাৎ অনুপস্থিতি ছুটি নয়। অনুমোদন ছাড়া ছুটি অনুপস্থিতি হিসেবে গণ্য হবে। জরুরি অবস্থায় ফোনে জানিয়ে কাজে ফিরে এই ফরম পূরণ করতে হবে।',
        'Leave must be asked for in advance — sudden absence is not leave. Leave without approval counts as absence. In an emergency, inform by phone and fill this form on returning to work.'), 'warn'),
      CH('type', L('ছুটির ধরন (Leave Type)', 'Leave type'), [['swap', L('সাপ্তাহিক বদল', 'Weekly-off swap')], ['annual', L('বার্ষিক (সবেতন)', 'Annual (paid)')], ['unpaid', L('বিনা বেতনের', 'Unpaid')], ['sick', L('অসুস্থতা', 'Sick')], ['emergency', L('জরুরি', 'Emergency')]], { req: true }),
      D('from', L('শুরুর তারিখ', 'Start date'), { req: true }), D('to', L('শেষের তারিখ', 'End date'), { req: true }), CALC('days', L('মোট দিন', 'Total days'), 'num'),
      TA('reason', L('কারণ', 'Reason'), { req: true }),
      CK('phoned', L('জরুরি অবস্থায় ফোনে জানানো হয়েছিল', 'Informed by phone in the emergency'), { show: (x) => x.d.type === 'emergency' })] },
    { title: L('অনুপস্থিতিতে দায়িত্ব', 'Cover during leave'), fields: [
      T('delegate', L('অনুপস্থিতিতে দায়িত্বধারী (Delegate) — নাম / পদ', 'Delegate — name / post'), { req: true }), CK('delegate_agreed', L('তিনি সম্মত', 'The delegate agrees')), CK('delegate_signed', L('তাঁর স্বাক্ষর (দায়িত্বধারী)', "Delegate's signature")),
      TA('handover_items', L('অসম্পন্ন কাজ / হ্যান্ডওভারের বিষয়', 'Pending work / handover items')),
      CK('applicant_signed', L('আবেদনকারীর স্বাক্ষর (Applicant)', "Applicant's signature"), { req: true })] },
    { who: 'checker', title: L('সিদ্ধান্ত (ম্যানেজার)', 'Decision (manager)'), fields: [
      CH('decision', L('সিদ্ধান্ত', 'Decision'), [['yes', L('অনুমোদিত', 'Approved')], ['no', L('অনুমোদিত নয়', 'Not approved')], ['part', L('আংশিক', 'Partly approved')]], { who: 'checker', req: true }),
      N('part_days', L('আংশিক — অনুমোদিত দিন', 'Partly approved — days'), { who: 'checker', show: (x) => x.c.decision === 'part', req: (x) => x.c.decision === 'part' }),
      ST('approver', L('অনুমোদনকারী (Approved by)', 'Approved by'), { who: 'checker', req: true }), D('decision_date', L('তারিখ', 'Date'), { who: 'checker' }),
      CK('posted', L('মাসিক হাজিরা রেজিস্টারে এন্ট্রি (Posting) করা হয়েছে', 'Posted in the Monthly Attendance Register'), { who: 'checker', req: true }),
      CK('manager_signed', L('ম্যানেজার ইনচার্জের স্বাক্ষর', "Manager in charge's signature"), { who: 'checker' })] },
  ],
  calc(x) {
    const flags = [], d = x.d;
    let days;
    if (has(d.from) && has(d.to)) { days = dayDiff(d.from, d.to); if (days < 1) { flags.push(flag('leave_dates', 'red', 'শেষের তারিখ শুরুর তারিখের আগে', 'The end date is before the start date')); days = undefined; } }
    if (has(d.apply_date) && has(d.from) && d.apply_date > d.from && d.type !== 'emergency') flags.push(flag('leave_late', 'yellow', 'ছুটি শুরুর পরে আবেদন — আগে না জানালে ছুটি নয়, অনুপস্থিতি', 'Applied after the leave started — leave not asked in advance counts as absence'));
    if (d.type === 'emergency' && !d.phoned) flags.push(flag('emergency_not_phoned', 'yellow', 'জরুরি ছুটি — ফোনে জানানোর টিক নেই', 'Emergency leave — no tick that it was phoned in'));
    if (has(d.delegate) && !d.delegate_agreed) flags.push(flag('delegate_not_agreed', 'yellow', 'দায়িত্বধারীর সম্মতি টিক নেই', "The delegate's agreement is not ticked"));
    if (x.c.decision === 'no') flags.push(flag('leave_declined', 'yellow', 'ছুটি অনুমোদিত নয় — অনুপস্থিতি হিসেবে গণ্য হবে', 'Leave not approved — counts as absence', undefined, { src: 'check' }));
    if (x.c.decision === 'part' && days && num(x.c.part_days) > days) flags.push(flag('part_over', 'red', 'আংশিক অনুমোদিত দিন আবেদনের দিনের চেয়ে বেশি', 'Partly approved days exceed the days applied for', num(x.c.part_days), { ...QTY, src: 'check' }));
    if (has(x.c.approver) && x.c.approver === d.applicant) flags.push(flag('leave_self_approved', 'red', 'আবেদনকারী নিজেই অনুমোদনকারী', 'The applicant is also the approver', undefined, { src: 'check' }));
    return { v: { days }, flags, needs: [] };
  },
};

/* ============ 10-1 · Exit clearance ============ */
const HAND = [
  ['adv', L('বাকি অ্যাডভান্স (স্টাফ অ্যাডভান্স রেজিস্টার দেখে)', 'Outstanding advance (from the Staff Advance Register)'), L('পরিমাণ ৳', 'Amount ৳')],
  ['keys', L('চাবি (শাটার · ড্রয়ার · স্টক-কক্ষ)', 'Keys (shutter · drawer · stock room)'), L('কয়টি', 'How many')],
  ['cash', L('ক্যাশ বাক্স / ইমপ্রেস্ট (খরচের বাক্স)', 'Cash box / imprest (petty cash)'), L('পরিমাণ ৳', 'Amount ৳')],
  ['orders', L('অসম্পূর্ণ অর্ডার ও পেন্ডিং কাজ', 'Incomplete orders and pending work'), L('কয়টি', 'How many')],
  ['papers', L('কাগজ ও রেজিস্টার (শেষ ক্রমিক নং)', 'Papers and registers (last serial no.)'), L('নং', 'No.')],
  ['assets', L('প্রতিষ্ঠানের সম্পদ (ইউনিফর্ম · যন্ত্র · ফোন · ল্যাপটপ)', 'Business assets (uniform · tools · phone · laptop)'), L('বিবরণ', 'Details')],
  ['online', L('অনলাইন অ্যাকাউন্ট ও পাসওয়ার্ড — অধিকার বন্ধ', 'Online accounts and passwords — access closed'), L('কোনগুলো', 'Which ones')],
];
B.forms['10-1'] = {
  title: L('এক্সিট ক্লিয়ারেন্স', 'Exit Clearance', 'এক্সিট ক্লিয়ারেন্স'),
  head: [T('reg_no', L('কর্মী রেজিস্ট্রেশন ফরম নং', 'Employee registration form no.')), ST('staff', L('কর্মীর নাম', 'Employee'), { req: true }), T('post', L('পদ', 'Post'), { req: true }), D('join_date', L('যোগদান', 'Joined')), D('last_day', L('শেষ কর্মদিবস', 'Last working day'), { req: true })],
  sections: [
    { title: L('চাকরির সমাপ্তি', 'End of employment'), fields: [
      CH('how', L('পদত্যাগ / চাকরির অবসানের ধরন', 'Type of resignation / termination'), [['resign', L('পদত্যাগ — কর্মী কর্তৃক', 'Resignation — by the employee')], ['terminate', L('চাকরির অবসান — প্রতিষ্ঠান কর্তৃক', 'Termination — by the business')], ['contract', L('চুক্তি শেষ', 'Contract ended')], ['other', L('অন্য', 'Other')]], { req: true }),
      T('how_other', L('অন্য — লিখুন', 'Other — write it'), { show: (x) => x.d.how === 'other', req: (x) => x.d.how === 'other' }),
      CH('notice', L('নোটিশ দেওয়া হয়েছিল?', 'Was notice given?'), YN, { req: true }), N('notice_days', L('নোটিশ — কত দিন', 'Notice — days'), { show: (x) => x.d.notice === 'yes' }),
      M('notice_ded', L('না হলে কর্তন ৳', 'If not — deduction ৳'), { show: (x) => x.d.notice === 'no' }), T('reason', L('কারণ (সংক্ষেপে)', 'Reason (brief)'))] },
    { title: L('নিয়ম', 'Rule'), fields: [
      NOTE(L('সব ঘর শেষ না হওয়া পর্যন্ত শেষ বেতনের পেমেন্ট হবে না। ক্লিয়ারেন্স সম্পূর্ণ না হলে এক্সিট (Exit) সম্পন্ন হবে না। অ্যাডভান্স বাকি থাকলে ছাড়পত্র দেওয়া যাবে না।', 'No final pay until every line is done. The exit is not complete until clearance is complete. No clearance while an advance is outstanding.'), 'warn')] },
    { title: L('হ্যান্ডওভার তালিকা (Handover List)', 'Handover list'), fields: [
      TABLE('handover', null, [CH('status', L('অবস্থা', 'Status'), [['done', L('হয়েছে', 'Done')], ['pending', L('বাকি', 'Pending')]], { req: true }),
        N('qty', L('পরিমাণ / নং', 'Amount / no.')), T('detail', L('বিবরণ', 'Details'), { wide: true }), ST('received', L('গ্রহণকারী (Received by)', 'Received by'))], { rows: HAND.map((h) => L(h[1].bn + ' — ' + h[2].bn, h[1].en + ' — ' + h[2].en)) })] },
    { title: L('না জানিয়ে চলে গেলে (Absconded)', 'Left without notice (Absconded)'), collapsed: true, fields: [
      CK('absconded', L('বিনা নোটিশে অনুপস্থিত (Absconded)', 'Absent without notice (Absconded)')),
      D('last_seen', L('শেষ দেখা', 'Last seen'), { show: (x) => x.d.absconded, req: (x) => x.d.absconded }), M('abs_adv', L('বাকি অ্যাডভান্স ৳', 'Outstanding advance ৳'), { show: (x) => x.d.absconded, req: (x) => x.d.absconded }),
      CK('key_not_returned', L('চাবি ফেরত হয়নি', 'Keys not returned'), { show: (x) => x.d.absconded }), CK('asset_not_returned', L('প্রতিষ্ঠানের সম্পদ ফেরত হয়নি', 'Business assets not returned'), { show: (x) => x.d.absconded }),
      CK('access_closed', L('অ্যাক্সেস বন্ধ করা হয়েছে', 'Access closed'), { show: (x) => x.d.absconded, req: (x) => x.d.absconded }),
      CK('slot_empty', L('ডিউটি স্লট "খালি" করা হয়েছে', 'Duty slot marked "vacant"'), { show: (x) => x.d.absconded, req: (x) => x.d.absconded }),
      CK('on_worklist', L('কাজের তালিকায় তোলা হয়েছে', 'Put on the work list'), { show: (x) => x.d.absconded, req: (x) => x.d.absconded })] },
    { title: L('শেষ হিসাব', 'Final settlement'), fields: [
      M('final_due', L('পাওনা বেতন ৳', 'Salary due ৳'), { req: true }), M('final_adv', L('(−) অ্যাডভান্স ৳', '(−) Advance ৳'), { req: true }), M('final_other', L('(−) অন্য ৳', '(−) Other ৳')),
      CALC('net', L('নিট প্রদেয় (Net Payable) ৳', 'Net payable ৳'), 'money', { big: true }),
      D('pay_date', L('পেমেন্টের তারিখ', 'Payment date')), SEL('pay_method', L('পেমেন্টের মাধ্যম', 'Payment method'), PAYM),
      T('pay_other', L('অন্য মাধ্যম — লিখুন', 'Other method — write it'), { show: (x) => x.d.pay_method === 'other', req: (x) => x.d.pay_method === 'other' }),
      D('ledger_date', L('ক্যাশ ও ব্যাংক লেজারের তারিখ', 'Cash & bank ledger date')), T('ledger_line', L('লেজারের লাইন', 'Ledger line')),
      CK('emp_received', L('গ্রহণকারী (Received by) — কর্মী বুঝে পেয়েছেন, স্বাক্ষর', 'Employee received the money — signature'), { req: true }), CK('emp_signed', L('কর্মীর স্বাক্ষর (Employee)', "Employee's signature"), { req: true }),
      D('emp_date', L('কর্মীর স্বাক্ষরের তারিখ', 'Employee signature date')), CK('mgr_signed', L('ম্যানেজার ইনচার্জের স্বাক্ষর', "Manager in charge's signature"))] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      CK('approved', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by — management'), { who: 'checker', req: true }), D('approved_date', L('অনুমোদনের তারিখ', 'Approval date'), { who: 'checker' }),
      CK('duty_card', L('ডিউটি ও ব্যাকআপ কার্ড হালনাগাদ করা হয়েছে', 'Duty & Backup Card updated'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, rows = x.rows('handover'), flags = [];
    const net = num(d.final_due) - num(d.final_adv) - num(d.final_other);
    const pending = HAND.length - rows.slice(0, HAND.length).filter((r) => r && r.status === 'done').length;
    if ((has(d.pay_date) || d.emp_received) && pending > 0) flags.push(flag('clearance_incomplete', 'red', 'হ্যান্ডওভার তালিকার সব ঘর শেষ হয়নি — শেষ বেতন দেওয়া যাবে না (বাকি ঘর)', 'Handover list is not complete — final pay cannot be given (lines pending)', pending, QTY));
    const advRow = rows[0] || {};
    if (num(advRow.qty) > 0 && num(d.final_adv) < num(advRow.qty)) flags.push(flag('exit_adv_not_cleared', 'red', 'বাকি অ্যাডভান্স শেষ বেতন থেকে পুরো কাটা হয়নি — ছাড়পত্র দেওয়া যাবে না', 'Outstanding advance is not fully deducted from the final pay — clearance cannot be given', num(advRow.qty) - num(d.final_adv)));
    if (rows.some((r) => r.status === 'done' && has(r.received) && r.received === d.staff)) flags.push(flag('self_received', 'red', 'কর্মী নিজেই নিজের হ্যান্ডওভার গ্রহণ করেছেন', 'The employee received their own handover'));
    if (has(d.pay_date) || has(d.final_due)) { if (net < 0) flags.push(flag('net_negative', 'red', 'নিট প্রদেয় ঋণাত্মক', 'Net payable is negative', net)); }
    if (d.notice === 'no' && !has(d.notice_ded)) flags.push(flag('notice_ded_missing', 'yellow', 'নোটিশ দেওয়া হয়নি কিন্তু কর্তনের অঙ্ক লেখা নেই', 'No notice was given but the deduction amount is not written'));
    if (d.absconded) flags.push(flag('absconded', 'yellow', 'কর্মী বিনা নোটিশে চলে গেছেন', 'Employee left without notice', has(d.abs_adv) ? num(d.abs_adv) : undefined));
    return { v: { net }, flags, needs: [] };
  },
};

/* ============ 09-1 · Duty & backup card ============ */
// sections A and B follow the live showrooms of the locations table (the old fixed names are only a fallback)
const SLOT_A_FALLBACK = [L('ইসলামিয়া মিষ্টি ঘর — মেইন — ম্যানেজার', 'ISLAMIYA MISTY GHAR — Main — manager'), L('ইসলামিয়া মিষ্টি ঘর — ২য় শাখা — ম্যানেজার', 'ISLAMIYA MISTY GHAR — 2nd Branch — manager'), L('মিষ্টি বাড়ি — ম্যানেজার', 'MISTY BARI — manager'), L('AL-CAKIZ — ম্যানেজার', 'AL-CAKIZ — manager')];
const SLOT_B_FALLBACK = [L('ইসলামিয়া মিষ্টি ঘর — ২য় শাখা — ব্যাকআপ', 'ISLAMIYA MISTY GHAR — 2nd Branch — backup'), L('মিষ্টি বাড়ি — ব্যাকআপ', 'MISTY BARI — backup'), L('AL-CAKIZ — ব্যাকআপ', 'AL-CAKIZ — backup')];
const liveShowrooms = () => ((B.ENV && B.ENV.locs) || []).filter((l) => l.kind === 'showroom' && l.is_active !== false && ['live', 'setting_up', null, undefined].includes(l.status));
const SLOT_A = () => { const ls = liveShowrooms(); return ls.length ? ls.map((l) => ({ bn: l.name_bn + ' — ম্যানেজার', en: (l.name_en || l.name_bn) + ' — manager', mix: (l.name_mix || l.name_bn) + ' — manager' })) : SLOT_A_FALLBACK; };
const SLOT_B = () => { const ls = liveShowrooms(); return [...(ls.length ? ls.slice(1).map((l) => ({ bn: l.name_bn + ' — ব্যাকআপ', en: (l.name_en || l.name_bn) + ' — backup', mix: (l.name_mix || l.name_bn) + ' — backup' })) : SLOT_B_FALLBACK), L('রিজার্ভ — দুই শাখা একসাথে খালি হলে', 'Reserve — when two branches are empty together')]; };
const SLOT_C = [L('খামির ব্যাকআপ 1', 'Yeast backup 1'), L('খামির ব্যাকআপ 2', 'Yeast backup 2'), L('খামির ব্যাকআপ 3', 'Yeast backup 3')];
const SLOT_E = [L('গোডাউন — স্টোরকিপার', 'Godown — storekeeper'), L('গোডাউন — ব্যাকআপ', 'Godown — backup'), L('মিষ্টি কারখানার স্টোর — স্টোরকিপার', 'Sweet factory store — storekeeper'), L('মিষ্টি কারখানার স্টোর — ব্যাকআপ', 'Sweet factory store — backup'),
  L('কেক কারখানার স্টোর — স্টোরকিপার', 'Cake factory store — storekeeper'), L('কেক কারখানার স্টোর — ব্যাকআপ', 'Cake factory store — backup')];
const SLOT_F = [L('মিষ্টি কারখানা — ইনচার্জ', 'Sweet factory — in charge'), L('মিষ্টি কারখানা — ইনচার্জের ব্যাকআপ', 'Sweet factory — in-charge backup'), L('মিষ্টি কারখানা — প্রধান কারিগর', 'Sweet factory — head artisan'), L('মিষ্টি কারখানা — প্রধান কারিগরের ব্যাকআপ', 'Sweet factory — head-artisan backup'),
  L('কেক কারখানা — ইনচার্জ', 'Cake factory — in charge'), L('কেক কারখানা — ইনচার্জের ব্যাকআপ', 'Cake factory — in-charge backup'), L('কেক কারখানা — প্রধান কারিগর', 'Cake factory — head artisan'), L('কেক কারখানা — প্রধান কারিগরের ব্যাকআপ', 'Cake factory — head-artisan backup')];
const SLOT_G = [L('দৈনিক হিসাব রিকনসিলিয়েশন', 'Daily accounts reconciliation'), L('দৈনিক হিসাব রিকনসিলিয়েশন — ব্যাকআপ', 'Daily accounts reconciliation — backup'), L('রাতের ক্যাশ গ্রহণকারী 1', 'Night cash receiver 1'), L('রাতের ক্যাশ গ্রহণকারী 2', 'Night cash receiver 2'),
  L('রাতের ক্যাশ গ্রহণকারী 3', 'Night cash receiver 3'), L('ব্যাংকে জমা — গণনাকারী (Counted by)', 'Bank deposit — counted by'), L('ব্যাংকে জমা — জমাদানকারী (Deposited by)', 'Bank deposit — deposited by')];
const SLOT_H = [L('ইনডিপেনডেন্ট চেক — রোটেশন 1', 'Independent check — rotation 1'), L('ইনডিপেনডেন্ট চেক — রোটেশন 2', 'Independent check — rotation 2'), L('ইনডিপেনডেন্ট চেক — রোটেশন 3', 'Independent check — rotation 3'),
  L('অনলাইন অ্যাকাউন্ট — সর্বোচ্চ অধিকার', 'Online account — full rights'), L('অনলাইন অ্যাকাউন্ট — সীমিত অধিকার 1', 'Online account — limited rights 1'), L('অনলাইন অ্যাকাউন্ট — সীমিত অধিকার 2', 'Online account — limited rights 2')];
const SLOT_I = [L('কোটেশন সংগ্রহ ও পারচেজ অর্ডার তৈরি', 'Collecting quotations and making Purchase Orders'), L('কোটেশন সংগ্রহ ও পারচেজ অর্ডার — ব্যাকআপ', 'Quotations and Purchase Orders — backup'), L('বাজারে ক্রয় (জরুরি ক্রয়)', 'Market purchase (urgent buying)'),
  L('নকল চাবির দায়িত্বে', 'Duplicate-key holder')];
const slotCols = () => [
  ST('name', L('দায়িত্বধারীর নাম', 'Holder name'), { req: (x) => !x.row.vacant, wide: true }), CK('vacant', L('স্লট খালি', 'Slot is vacant')),
  D('start', L('শুরুর তারিখ (জানা থাকলে)', 'Start date (if known)'), { show: (x) => !x.row.vacant }),
  CH('skill', L('স্কিল চেকলিস্ট', 'Skill checklist'), [['full', L('সম্পূর্ণ', 'Complete')], ['part', L('আংশিক', 'Partial')]], { req: (x) => !x.row.vacant, show: (x) => !x.row.vacant }),
  N('part_n', L('আংশিক — বাকি কাজ (টি)', 'Partial — tasks left'), { show: (x) => !x.row.vacant && x.row.skill === 'part' }),
  CK('holder_sig', L('দায়িত্বধারীর স্বাক্ষর', "Holder's signature"), { show: (x) => !x.row.vacant }), CK('appr', L('অনুমোদনকারীর স্বাক্ষর', "Approver's signature"), { who: 'checker', show: (x) => !x.row.vacant })];
const slotTable = (id, labels) => TABLE(id, null, slotCols(), { rows: labels });
const SLOT_TABLES = [['slotA', SLOT_A], ['slotB', SLOT_B], ['slotC', SLOT_C], ['slotE', SLOT_E], ['slotF', SLOT_F], ['slotG', SLOT_G], ['slotH', SLOT_H], ['slotI', SLOT_I]];
B.forms['09-1'] = {
  title: L('ডিউটি ও ব্যাকআপ কার্ড', 'Duty and Backup Card', 'Duty ও ব্যাকআপ Card'),
  head: [D('last_update', L('সর্বশেষ হালনাগাদ', 'Last updated'), { req: true })],
  init(x, d) { if (!has(d.last_update)) d.last_update = x.date; },
  sections: [
    { title: L('নিয়ম', 'Rules'), fields: [
      NOTE(L('প্রতিটি ডিউটি স্লটে একজনের নাম। স্লট খালি থাকলে "স্লট খালি" টিক দিন। দায়িত্বধারী বদলালে পুরোনো লাইন বদলে নতুন নাম দিন এবং Section D-র ইতিহাসে পুরোনো নাম যোগ করুন — মুছে ফেলবেন না। স্কিল চেকলিস্টের সব কাজ শেষ না হওয়া পর্যন্ত স্লট "আংশিক"। এই কার্ডে নাম না থাকলে কেউ ব্যাকআপ হিসেবে গণ্য নয়।',
        'Each duty slot has one name. If a slot is empty, tick "Slot is vacant". When a holder changes, put the new name and add the old name to the Section D history — never delete it. A slot is "Partial" until every Skill Checklist task is done. Nobody counts as a backup unless named on this card.'), 'warn'),
      NOTE(L('একই ব্যক্তি দুই ডিউটি স্লটে নয়: স্টোরকিপার ও তাঁর ব্যাকআপ · দৈনিক হিসাব রিকনসিলিয়েশন ও রাতের ক্যাশ গ্রহণকারী · ব্যাংকে জমার দুজন · ব্যাংকে জমার দুজনের কেউ ও দৈনিক হিসাব রিকনসিলিয়েশন বা রাতের ক্যাশ গ্রহণকারী · ইনডিপেনডেন্ট চেকের লোক ও যে লোকেশন তিনি যাচাই করেন তার কাজ · গোডাউন বা স্টোরের স্টোরকিপার ও কোটেশন সংগ্রহ, পারচেজ অর্ডার বা বাজারে ক্রয় · নকল চাবির দায়িত্বে যিনি ও ওই চাবির নিয়মিত দায়িত্বধারী। ব্যাকআপ স্লটেও একই নিষেধ।',
        'The same person may not hold two duty slots: storekeeper and own backup · daily reconciliation and night cash receiver · the two bank-deposit people · either bank-deposit person and daily reconciliation or night cash receiver · the independent checker and the work of the location they check · godown/store storekeeper and quotation collection, Purchase Orders or market purchase · the duplicate-key holder and the regular holder of that key. The same ban applies to backup slots.'), 'warn'),
      NOTE(L('এই কার্ডে সিস্টেম নিজে থেকে যাচাই করে: স্টোরকিপার ↔ ব্যাকআপ, রিকনসিলিয়েশন ↔ রাতের ক্যাশ, ব্যাংকে জমার দুজন, ব্যাংকে জমা ↔ রিকনসিলিয়েশন / রাতের ক্যাশ, স্টোরকিপার ↔ ক্রয়। ইনডিপেনডেন্ট চেক ও নকল চাবির নিষেধ নিজে মিলিয়ে দেখুন (তাঁর লোকেশন বা চাবির নিয়মিত দায়িত্বধারীর নাম এই কার্ডে নেই)।',
        'The system checks these pairs on this card: storekeeper ↔ backup, reconciliation ↔ night cash, the two bank-deposit people, bank deposit ↔ reconciliation / night cash, storekeeper ↔ purchasing. Check the independent-check and duplicate-key bans yourself (the checked location and the regular key holder are not named on this card).'), 'ok')] },
    { title: L('Section A · শোরুম ম্যানেজার', 'Section A · Showroom managers'), fields: [slotTable('slotA', SLOT_A)] },
    { title: L('Section B · শাখার ব্যাকআপ ম্যানেজার', 'Section B · Branch backup managers'), fields: [slotTable('slotB', SLOT_B)] },
    { title: L('Section C · জিলাপির খামির — প্রশিক্ষিত ব্যাকআপ', 'Section C · Jalebi batter — trained backups'), fields: [slotTable('slotC', SLOT_C)] },
    { title: L('ফাঁকা স্লট (অন্য নাম / নতুন শাখা)', 'Extra slots (other name / new branch)'), collapsed: true, fields: [
      NOTE(L('কার্ডের "________ — ম্যানেজার / ব্যাকআপ / স্টোরকিপার" ফাঁকা ঘরগুলোর জন্য।', 'For the blank "________ — manager / backup / storekeeper" lines on the card.'), 'ok'),
      TABLE('extra', null, [T('slot', L('স্লটের নাম (যেমন: ________ — ম্যানেজার)', 'Slot name (e.g. ________ — manager)'), { req: true, wide: true }), ...slotCols()], { min: 1 })] },
    { title: L('Section D · পরিবর্তনের ইতিহাস (Change History)', 'Section D · Change history'), fields: [
      TABLE('history', null, [T('slot', L('ডিউটি স্লট', 'Duty slot'), { req: true, wide: true }), T('old', L('পুরোনো দায়িত্বধারী', 'Previous holder'), { req: true }), D('end', L('শেষের তারিখ', 'End date')), T('why', L('কারণ', 'Reason')),
        ST('by', L('পরিবর্তনকারী (Changed by)', 'Changed by'), { req: true })], { min: 1 })] },
    { title: L('Section E · গোডাউন ও স্টোর — স্টোরকিপার ও ব্যাকআপ', 'Section E · Godown & stores — storekeepers and backups'), collapsed: true, fields: [slotTable('slotE', SLOT_E)] },
    { title: L('Section F · কারখানা', 'Section F · Factories'), collapsed: true, fields: [slotTable('slotF', SLOT_F)] },
    { title: L('Section G · হিসাব ও ক্যাশ', 'Section G · Accounts & cash'), collapsed: true, fields: [slotTable('slotG', SLOT_G)] },
    { title: L('Section H · ইনডিপেনডেন্ট চেক ও অনলাইন অ্যাকাউন্ট', 'Section H · Independent check & online accounts'), collapsed: true, fields: [slotTable('slotH', SLOT_H)] },
    { title: L('Section I · ক্রয় ও নকল চাবি', 'Section I · Purchasing & duplicate keys'), collapsed: true, fields: [
      slotTable('slotI', SLOT_I), T('key_where', L('নকল চাবি — চাবি ও রাখার জায়গা', 'Duplicate keys — which keys and where kept'))] },
    { who: 'checker', title: L('অনুমোদন (মালিক / প্রধান ব্যবস্থাপনা)', 'Approval (owner / head management)'), fields: [
      CK('owner_approved', L('মালিক / প্রধান ব্যবস্থাপনা (Approved by)', 'Owner / head management approved'), { who: 'checker', req: true }), D('owner_date', L('তারিখ', 'Date'), { who: 'checker' })] },
  ],
  calc(x) {
    const flags = [];
    const slot = (tid, labels) => x.rows(tid).slice(0, labels.length);
    const nm = (r) => (r && !r.vacant && has(r.name) ? r.name : null);
    const lst = (tid, labels, idx) => idx.map((i) => ({ n: nm(slot(tid, labels)[i]), l: labels[i] })).filter((o) => o.n);
    const E = (idx) => lst('slotE', SLOT_E, idx), G = (idx) => lst('slotG', SLOT_G, idx), I = (idx) => lst('slotI', SLOT_I, idx);
    const dup = (code, bn, en, a, b) => { const seen = new Map(); a.forEach((o) => seen.set(o.n, o)); const hit = new Set();
      b.forEach((o) => { if (seen.has(o.n) && seen.get(o.n) !== o) hit.add(o.n); });
      if (hit.size) flags.push(flag(code, 'red', bn, en, hit.size, QTY)); };
    // storekeeper vs own backup (godown, sweet store, cake store)
    [[0, 1], [2, 3], [4, 5]].forEach(([a, b], k) => dup('dup_store_' + k, 'একই ব্যক্তি স্টোরকিপার ও তাঁর ব্যাকআপ (জন)', 'Same person is storekeeper and own backup (people)', E([a]), E([b])));
    // reconciliation (+backup) vs night cash receivers
    dup('dup_recon_night', 'একই ব্যক্তি দৈনিক হিসাব রিকনসিলিয়েশন ও রাতের ক্যাশ গ্রহণকারী (জন)', 'Same person in daily reconciliation and night cash receiver (people)', G([0, 1]), G([2, 3, 4]));
    // the two bank-deposit people
    dup('dup_bank_two', 'ব্যাংকে জমার দুজন একই ব্যক্তি (জন)', 'The two bank-deposit people are the same (people)', G([5]), G([6]));
    // bank-deposit people vs reconciliation / night cash
    dup('dup_bank_recon', 'ব্যাংকে জমার ব্যক্তি রিকনসিলিয়েশন / রাতের ক্যাশে আছেন (জন)', 'A bank-deposit person is also in reconciliation / night cash (people)', G([5, 6]), G([0, 1, 2, 3, 4]));
    // storekeepers vs purchasing
    dup('dup_store_purchase', 'স্টোরকিপার ও কোটেশন / পারচেজ অর্ডার / বাজারে ক্রয় একই ব্যক্তি (জন)', 'Storekeeper also in quotations / Purchase Orders / market purchase (people)', E([0, 1, 2, 3, 4, 5]), I([0, 1, 2]));
    // incomplete skill on a named slot is "partial": information only
    let partial = 0;
    SLOT_TABLES.forEach(([id, labels]) => x.rows(id).slice(0, (typeof labels === 'function' ? labels() : labels).length).forEach((r) => { if (nm(r) && r.skill === 'part') partial++; }));
    if (partial) flags.push(flag('skill_partial', 'yellow', 'স্কিল চেকলিস্ট আংশিক এমন স্লট আছে', 'Slots whose skill checklist is only partial', partial, QTY));
    let vacant = 0;
    SLOT_TABLES.forEach(([id, labels]) => x.rows(id).slice(0, (typeof labels === 'function' ? labels() : labels).length).forEach((r) => { if (r.vacant) vacant++; }));
    if (vacant) flags.push(flag('slot_vacant', 'yellow', 'খালি ডিউটি স্লট আছে', 'Vacant duty slots', vacant, QTY));
    return { v: {}, flags, needs: [] };
  },
};

/* ============ 34-1 · Skill checklist ============ */
const SK = {
  A: [
    [L('দিনের ক্যাশ বন্ধ — নোট গণনা করে লেখা; আসল ঘরে প্রত্যাশিত সংখ্যা নয়; ঘাটতি বা বাড়তি শূন্য হলেও লেখা', 'Day cash close — notes counted and written; never the expected figure in the real box; short/over written even when zero')],
    [L('শোরুম বন্ধ — পেন্ডিং অর্ডার বোর্ড যাচাই, দিন-ট্যাগ দেখা, যন্ত্র বন্ধ করে স্বাক্ষর', 'Showroom close — pending orders board checked, day-tag looked at, machines off, signed')],
    [L('পেন্ডিং অর্ডার বোর্ড — অর্ডার নেওয়ার সাথে সাথে বোর্ডে যোগ করা', 'Pending orders board — add the order the moment it is taken')],
    [L('অর্ডার ডেলিভারি — আগে বাকি টাকা, তারপর কাস্টমারের সামনে মালামাল মিলিয়ে দেখা, তারপর স্বাক্ষর', 'Order delivery — balance money first, then check the goods in front of the customer, then sign')],
    [L('অভিযোগ নেওয়া — যেকোনো অসন্তোষ ক্রমিক নম্বরে লেখা; পণ্যটি তদন্ত পর্যন্ত রেখে দেওয়া', 'Taking a complaint — every dissatisfaction written under a serial number; keep the product until investigated')],
    [L('খোলার সময় পণ্যের অবস্থা দেখা — চেহারা, রস, জমাট, গন্ধ, ঘাম — প্রোডাক্ট স্পেক কার্ডের সাথে মিলিয়ে', 'Checking product condition at opening — look, syrup, setting, smell, sweating — against the Product Spec Card')],
    [L('মেয়াদ শেষ বা কাছাকাছি পণ্য — সরিয়ে আলাদা রাখা; পরিমাণ ও মূল্যসহ লেখা', 'Expired or near-expiry goods — set apart; written with quantity and value')],
    [L('শোরুমে মালামাল প্রাপ্তি — নিজে গণনা করে স্বাক্ষর', 'Receiving goods at the showroom — count personally and sign')],
    [L('দিন-ট্যাগ দেখে আগে তৈরি মালামাল আগে বিক্রি', 'Sell earlier-made goods first by the day-tag')],
    [L('চালানের মালামাল বুঝে নেওয়া — যিনি দিচ্ছেন তাঁর সামনে গণনা করে', 'Taking over challan goods — counted in front of the person handing over')],
    [L('শিফট বা ফ্লোর ত্যাগের হ্যান্ডওভার — পেন্ডিং অর্ডার, ড্রয়ারের টাকা গণনা করে, চাবি, খোলা সমস্যা — শিফট হ্যান্ডওভার রেজিস্টারে স্বাক্ষর', 'Shift or floor handover — pending orders, drawer money counted, keys, open issues — signed in the Shift Handover Register')],
    [L('জিলাপি কাউন্টার খোলা ও বন্ধের মাপ — খামির, তেল ও রস; যিনি ভাজেন তিনি মাপবেন না (শুধু যেখানে জিলাপি কাউন্টার আছে)', 'Jalebi counter open and close measures — batter, oil and syrup; the fryer must not measure (only where there is a jalebi counter)')],
  ],
  B: [
    [L('খামিরের উপকরণ মালামাল ইস্যু স্লিপে নিয়ে ওজন করে নেওয়া', 'Taking batter ingredients on a goods issue slip and weighing them')],
    [L('কারিগরের সামনে পুরো এক ব্যাচ খামির নিজে বানানো — কারিগর মেনে নিলে টিক', 'Making one full batch of batter yourself in front of the artisan — tick if the artisan accepts it')],
  ],
  C: [
    [L('মালামাল গ্রহণ — সাপ্লায়ারের সামনে নিজে গণনা করে বা ওজন করে মালামাল গ্রহণ রসিদে লেখা', 'Receiving goods — count or weigh in front of the supplier and write it on the goods receipt')],
    [L('মান যাচাই গ্রহণের সময়েই — গ্রহণ / আটক / ফেরত; আটক মালামাল আলাদা রাখা', 'Quality check at the time of receiving — accept / hold / return; held goods kept apart')],
    [L('স্টোর লেজারে প্রতিটি প্রাপ্তি ও ইস্যু রসিদ বা মালামাল ইস্যু স্লিপের নম্বরে; প্রতি লাইনের পর বাকি', 'Every receipt and issue in the store ledger under the receipt / issue slip number; balance after every line')],
    [L('ইস্যু ওজন করে; একই দিনে না-লাগা মালামাল ওজন করে ফেরত নেওয়া; দুই স্বাক্ষর', 'Issue by weighing; unused goods weighed and taken back the same day; two signatures')],
    [L('মাসের কাউন্টে নিজে গণনা না করা; পার্থক্য অনুমোদন ছাড়া সমন্বয় নয়', 'Not counting personally in the month-end count; no variance adjusted without approval')],
  ],
  D: [
    [L('মালামাল ইস্যু স্লিপের নিট ব্যবহার উৎপাদন রিপোর্টের ইনপুটে হুবহু লেখা', 'Net use from the goods issue slip written exactly in the production report input')],
    [L('রেসিপি কার্ড ধরে ব্যাচ; বাড়তি মালামাল নিলে কারণ মালামাল ইস্যু স্লিপে', 'Batch by the recipe card; extra goods taken — reason on the goods issue slip')],
    [L('প্রোডাক্ট স্পেক কার্ড ধরে গ্রেড দেওয়া', 'Grading by the Product Spec Card')],
    [L('পরিকল্পনার বাইরে কিছু তৈরি হলে কারখানা দৈনিক শিটে লেখা', 'Anything made outside the plan is written in the factory daily sheet')],
    [L('পাত্র ও মালসা ধুয়ে, উল্টে, পুরো শুকিয়ে — সম্পাদনকারী (Performed by) ও যাচাইকারী (Checked by) — দুজন', 'Pots and bowls washed, turned over, fully dried — performer and checker are two people')],
    [L('যন্ত্র বিকল হলে ভেতরের পণ্যের অবস্থা যাচাই ও মেইনটেন্যান্স অনুরোধ ও রেকর্ডে লেখা', 'When a machine fails, check the goods inside and write it in the Maintenance Request & Record')],
    [L('কারখানা দৈনিক শিটে তিন নম্বর — মালামাল ইস্যু স্লিপ, চালান, শিফট হ্যান্ডওভার রেজিস্টারের লাইন', 'Three numbers in the factory daily sheet — goods issue slip, challan, shift handover register line')],
    [L('ট্রান্সফার চালানের প্রতিটি লাইনে উৎপাদন তারিখ ও গ্রেড; হ্যান্ডওভার পয়েন্টে প্রাপকের সাথে গণনা করে স্বাক্ষর', 'Production date and grade on every transfer challan line; count with the receiver at the handover point and sign')],
  ],
  E: [
    [L('ক্লোজিং রিপোর্ট, ক্যাশ হ্যান্ডওভার স্লিপ আর ক্যাশ ও ব্যাংক লেজার — তিন জায়গায় একই অঙ্কের রিকনসিলিয়েশন', 'Closing report, cash handover slip and cash & bank ledger — the same figure reconciled in three places')],
    [L('লেজারের ডিজিটাল বিক্রির লাইন = সব শোরুমের মোট ডিজিটালের যোগ', 'Ledger digital-sales line = sum of all showrooms\' digital totals')],
    [L('লেজারে থাকার কথা, গণনায় প্রাপ্ত আর কম/বেশি — শূন্য হলেও লেখা', 'Should be in the ledger, counted, and short/over — written even when zero')],
    [L('দুধ ও ছানা লেজারের নগদ প্রদান = লেজারের দুধ ক্রয়ের লাইন', 'Cash paid in the milk & chhana ledger = milk-purchase line in the ledger')],
    [L('ডিজিটাল পেমেন্ট রিকনসিলিয়েশন রেজিস্টারে — কাগজ = স্টেটমেন্ট = ব্যাংকে জমা; স্টেটমেন্ট না পেলে আটক', 'In the Digital Payment Reconciliation Register — paper = statement = bank deposit; hold if no statement')],
    [L('মালিকের ব্যক্তিগত টাকায় পেমেন্ট হলে লেজারে দুই দিকে একই অঙ্ক — জমায় আর খরচে', 'When paid from the owner\'s personal money, the same figure on both sides of the ledger — in receipts and in expenses')],
  ],
  F: [
    [L('বহনকারীর সামনে নোট ধরে গণনা; স্লিপের "হাবে গণনায় প্রাপ্ত" ঘরে লিখে স্বাক্ষর', 'Count by notes in front of the carrier; write in the slip\'s "counted at the hub" box and sign')],
    [L('পার্থক্য থাকলে স্লিপেই লেখা, তারপর কাজের তালিকায়', 'If there is a difference, write it on the slip, then on the work list')],
    [L('স্বাক্ষরিত ২য় কপি পরদিন শোরুমে ফেরত পাঠানো', 'Send the signed 2nd copy back to the showroom next day')],
  ],
  G: [
    [L('প্রতিটি অনলাইন অর্ডার আগে কাস্টমার অর্ডার ফরমে (প্ল্যাটফর্মের টিক), তারপর অনলাইন ও ডেলিভারি লেজারে', 'Every online order first on the Customer Order Form (platform tick), then in the Online & Delivery Ledger')],
    [L('অ্যাডভান্স শুধু ব্যবসার মার্চেন্ট নম্বরে — কর্মীর নম্বরে কখনো নয়', 'Advance only on the business merchant number — never on a staff number')],
    [L('প্রতিটি বুস্ট বা মার্কেটিং খরচ আগে মার্কেটিং ব্যয় রেজিস্টারে, অনুমোদনসহ; পরে ফল লেখা', 'Every boost or marketing spend first in the Marketing Expense Register with approval; result written afterwards')],
    [L('দাম শুধু মূল্য তালিকা থেকে; অফার বা ডিসকাউন্ট মালিকের অনুমোদনে', 'Prices only from the price list; offers or discounts with the owner\'s approval')],
    [L('অভিযোগ বা খারাপ রিভিউ রিটার্ন ও অভিযোগ রেজিস্টারে; রিভিউ মোছা নয়', 'Complaints or bad reviews go in the Returns & Complaints Register; never delete a review')],
    [L('সপ্তাহের শেষে অনলাইন বিক্রি তিন জায়গায় রিকনসিলিয়েশন — অনলাইন ও ডেলিভারি লেজার, কাস্টমার অর্ডার ফরম, দৈনিক শোরুম শিট', 'Weekly online-sales reconciliation in three places — online & delivery ledger, customer order form, daily showroom sheet')],
  ],
};
const SK_TITLES = {
  A: L('Section A · শোরুম ম্যানেজার ও ব্যাকআপ ম্যানেজার — যাচাইকারী: ওই শোরুমের ম্যানেজার বা প্রধান ব্যবস্থাপনা', 'Section A · Showroom manager & backup manager — checker: that showroom\'s manager or head management'),
  B: L('Section B · জিলাপির খামির ব্যাকআপ — যাচাইকারী: জিলাপির কারিগর', 'Section B · Jalebi batter backup — checker: the jalebi artisan'),
  C: L('Section C · গোডাউন ও স্টোরের স্টোরকিপার ও ব্যাকআপ — যাচাইকারী: কারখানা ইনচার্জ বা প্রধান ব্যবস্থাপনা', 'Section C · Godown & store storekeepers and backups — checker: factory in charge or head management'),
  D: L('Section D · কারখানা ইনচার্জ ও প্রধান কারিগর, ব্যাকআপসহ — যাচাইকারী: প্রধান ব্যবস্থাপনা', 'Section D · Factory in charge & head artisan, with backups — checker: head management'),
  E: L('Section E · দৈনিক হিসাব রিকনসিলিয়েশন ও ব্যাকআপ — যাচাইকারী: মালিক বা প্রধান ব্যবস্থাপনা', 'Section E · Daily accounts reconciliation & backup — checker: owner or head management'),
  F: L('Section F · রাতের ক্যাশ গ্রহণকারী — যাচাইকারী: দৈনিক হিসাব রিকনসিলিয়েশনের কর্মী', 'Section F · Night cash receiver — checker: the daily-reconciliation staff'),
  G: L('Section G · অনলাইন ও মার্কেটিং — যাচাইকারী: মালিক', 'Section G · Online & marketing — checker: the owner'),
};
const skTable = (k) => TABLE('sk' + k, null, [...(k === 'A' ? [CK('na', L('প্রযোজ্য নয় (শুধু ১২ নম্বর — যেখানে জিলাপি কাউন্টার নেই)', 'Not applicable (task 12 only — where there is no jalebi counter)'))] : []), CK('done', L('নিজে সম্পাদিত', 'Done by the holder personally'), { show: (x) => !x.row.na }), D('date', L('তারিখ', 'Date'), { req: (x) => !!x.row.done, show: (x) => !x.row.na }),
  ST('verifier', L('যাচাইকারীর স্বাক্ষর', "Checker's signature"), { req: (x) => !!x.row.done, show: (x) => !x.row.na })], { rows: SK[k].map((r) => r[0]) });
B.forms['34-1'] = {
  title: L('স্কিল চেকলিস্ট', 'Skill Checklist', 'স্কিল চেকলিস্ট'),
  head: [T('slot', L('ডিউটি স্লট', 'Duty slot'), { req: true }), T('initials', L('ব্যক্তির নামের আদ্যক্ষর (Initials)', "Person's initials"), { req: true }), ST('holder', L('স্লটের দায়িত্বধারী', 'Slot holder'), { req: true }),
    LOC('place', L('লোকেশন', 'Location')), D('start', L('শুরুর তারিখ', 'Start date')), D('end', L('শেষের তারিখ', 'End date'))],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [
      NOTE(L('কাজটি নিজে করেছেন এবং যাচাইকারী পাশে দাঁড়িয়ে দেখেছেন — তবেই টিক। ডিউটি স্লট অনুযায়ী শুধু সেই অংশ পূরণ হবে। স্লটের দায়িত্বধারী নিজে কখনো যাচাইকারী নন।',
        'Tick only if the holder did the task personally and the checker stood beside and watched. Only the sections for the duty slot are filled. The slot holder is never their own checker.'), 'warn'),
      NOTE(L('যাচাইকারী: Section A-তে ওই শোরুমের ম্যানেজার বা প্রধান ব্যবস্থাপনা; B-তে জিলাপির কারিগর; C-তে কারখানা ইনচার্জ বা প্রধান ব্যবস্থাপনা; D-তে প্রধান ব্যবস্থাপনা; E-তে মালিক বা প্রধান ব্যবস্থাপনা; F-তে দৈনিক হিসাব রিকনসিলিয়েশনের কর্মী; G-তে মালিক।',
        'Checkers: Section A — that showroom\'s manager or head management; B — the jalebi artisan; C — factory in charge or head management; D — head management; E — owner or head management; F — the daily-reconciliation staff; G — the owner.'), 'ok')] },
    ...['A', 'B', 'C', 'D', 'E', 'F', 'G'].map((k, i) => ({ title: SK_TITLES[k], collapsed: i > 0, fields: [skTable(k)] })),
    { title: L('ফলাফল', 'Result'), fields: [
      CALC('verified_n', L('মোট যাচাই (সংখ্যা) — কাজ', 'Total verified (number of tasks)'), 'num', { big: true }),
      CK('all_done', L('সব কাজ সম্পূর্ণ', 'All tasks complete')), CK('posted', L('ডিউটি ও ব্যাকআপ কার্ডে এন্ট্রি (Posting) করা হয়েছে', 'Posted on the Duty & Backup Card'), { show: (x) => x.d.all_done, req: (x) => x.d.all_done }),
      D('rest_date', L('বাকি কাজ সম্পন্নের তারিখ', 'Date the remaining tasks will be done')),
      CK('holder_signed', L('স্লটের দায়িত্বধারীর স্বাক্ষর', "Slot holder's signature"))] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      CK('approved', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by — management'), { who: 'checker', req: true }), D('approved_date', L('তারিখ', 'Date'), { who: 'checker' })] },
  ],
  calc(x) {
    const flags = []; let n = 0, incomplete = 0, selfV = 0;
    Object.keys(SK).forEach((k) => { const rows = x.rows('sk' + k).slice(0, SK[k].length); const done = rows.filter((r) => r.done).length; n += rows.filter((r) => r.done && has(r.verifier)).length;
      const na = rows.filter((r) => r.na).length; if (done > 0) incomplete += SK[k].length - done - na; selfV += rows.filter((r) => r.done && has(r.verifier) && r.verifier === x.d.holder).length; });
    if (selfV) flags.push(flag('verifier_is_holder', 'red', 'স্লটের দায়িত্বধারী নিজেই যাচাইকারী (কাজের সংখ্যা)', 'The slot holder is their own checker (tasks)', selfV, QTY));
    if (x.d.all_done && incomplete > 0) flags.push(flag('not_all_done', 'red', '"সব কাজ সম্পূর্ণ" টিক দেওয়া, কিন্তু শুরু করা অংশে কাজ বাকি (কাজের সংখ্যা)', '"All tasks complete" is ticked but started sections still have tasks left (tasks)', incomplete, QTY));
    if (has(x.d.start) && has(x.d.end) && x.d.end < x.d.start) flags.push(flag('skill_dates', 'red', 'শেষের তারিখ শুরুর তারিখের আগে', 'End date is before start date'));
    return { v: { verified_n: n }, flags, needs: [] };
  },
};

/* ============ 33-1 · Shift handover register ============ */
B.forms['33-1'] = {
  title: L('শিফট হ্যান্ডওভার', 'Shift Handover', 'Shift Handover'),
  head: [T('page_no', L('পৃষ্ঠা নং', 'Page no.'))],
  sections: [
    { title: L('নিয়ম', 'Rule'), fields: [
      NOTE(L('যে কেউ ফ্লোর ছাড়লে এক লাইন: ড্রয়ারে গণনাকৃত নগদ · অসম্পন্ন অর্ডার · চাবি · ডিসপ্লের মালামাল দুজনে গণনা করে · অমীমাংসিত বিষয় · দুই সই। প্রদানকারী গণনা করেন, গ্রহণকারী যাচাই করেন, দুজনে সই — পার্থক্য আগের শিফটের লাইনেই লিখতে হবে।',
        'Whoever leaves the floor writes one line: drawer cash counted · pending orders · keys · display goods counted by both · open issues · two signatures. The giver counts, the receiver checks, both sign — any difference is written on the earlier shift\'s line.'), 'warn')] },
    { title: L('হ্যান্ডওভারের লাইন', 'Handover lines'), fields: [
      TABLE('lines', null, [TM('time', L('সময়', 'Time'), { req: true }), ST('from', L('প্রদানকারী (Handed over by)', 'Handed over by'), { req: true }), ST('to', L('গ্রহণকারী (Received by)', 'Received by'), { req: true }),
        M('cash', L('ড্রয়ারে গণনায় প্রাপ্ত নগদ ৳', 'Cash counted in the drawer ৳'), { req: true }), N('pending', L('পেন্ডিং অর্ডার (সংখ্যা)', 'Pending orders (number)')),
        CK('keys', L('চাবি হ্যান্ডওভার', 'Keys handed over')), CK('from_signed', L('প্রদানকারী — স্বাক্ষর', "Giver's signature")), CK('to_signed', L('গ্রহণকারী — স্বাক্ষর', "Receiver's signature")), CH('display', L('ডিসপ্লের মালামাল — দুজনের গণনা', 'Display goods — counted by both'), [['match', L('মিল আছে', 'Matches')], ['short', L('ঘাটতি', 'Short')]], { req: true }),
        N('short_qty', L('ঘাটতি (পরিমাণ)', 'Shortage (quantity)'), { show: (x) => x.row.display === 'short', req: (x) => x.row.display === 'short' }),
        T('open_issues', L('অমীমাংসিত বিষয় / বিশেষ নির্দেশ', 'Open issues / special instructions'), { wide: true })], { min: 2 }),
      CALC('lines_n', L('মোট লাইন', 'Lines on this register'), 'num')] },
    { title: L('দিন শেষে', 'End of day'), fields: [
      CH('place', L('লোকেশনের ধরন', 'Location type'), [['shop', L('শোরুম', 'Showroom')], ['factory', L('কারখানা', 'Factory')]], { req: true }),
      N('shop_last', L('শেষ লাইনের ক্রম নং', 'Last line serial no.'), { show: (x) => x.d.place === 'shop', req: (x) => x.d.place === 'shop' }),
      M('shop_cash', L('ওই লাইনের গণনায় প্রাপ্ত নগদ ৳', 'Cash counted on that line ৳'), { show: (x) => x.d.place === 'shop', req: (x) => x.d.place === 'shop' }),
      CK('shop_closing', L('ক্লোজিং রিপোর্টে এই ক্রম নং লেখা হয়েছে', 'This serial no. is written in the Closing Report'), { show: (x) => x.d.place === 'shop', req: (x) => x.d.place === 'shop' }),
      N('fac_last', L('শেষ লাইনের ক্রম নং', 'Last line serial no.'), { show: (x) => x.d.place === 'factory', req: (x) => x.d.place === 'factory' }),
      T('fac_batch', L('চলমান ব্যাচ / অসম্পন্ন কাজ', 'Running batch / unfinished work'), { show: (x) => x.d.place === 'factory' }),
      CK('fac_sheet', L('কারখানা দৈনিক শিটে এই ক্রম নং লেখা হয়েছে', 'This serial no. is written in the Factory Daily Sheet'), { show: (x) => x.d.place === 'factory', req: (x) => x.d.place === 'factory' }),
      ST('in_charge', L('ম্যানেজার ইনচার্জ (In charge)', 'Manager in charge'), { req: true })] },
    { who: 'checker', title: L('যাচাই (ব্যবস্থাপনা)', 'Check (management)'), fields: [
      CK('checked', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা: রেজিস্টার যাচাই করা হয়েছে', 'Checked by management: register verified'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], d = x.d;
    const filled = rows.filter(anyRow);
    if (filled.some((r) => has(r.from) && r.from === r.to)) flags.push(flag('same_person_handover', 'red', 'প্রদানকারী ও গ্রহণকারী একই জন', 'Giver and receiver are the same person'));
    const sh = sum(filled.filter((r) => r.display === 'short').map((r) => r.short_qty));
    if (filled.some((r) => r.display === 'short')) flags.push(flag('display_short', 'red', 'ডিসপ্লের মালামালে ঘাটতি', 'Shortage in the display goods', sh, QTY));
    if (filled.some((r) => (r.from || r.to) && (!r.from_signed || !r.to_signed))) flags.push(flag('handover_unsigned', 'yellow', 'হ্যান্ডওভার লাইনে দুই স্বাক্ষর নেই', 'A handover line is missing one of the two signatures'));
    if (filled.some((r) => has(r.cash) && !has(r.to))) flags.push(flag('no_receiver', 'red', 'গ্রহণকারীর নাম ছাড়া নগদ হ্যান্ডওভার', 'Cash handed over without a named receiver'));
    const last = filled.length ? filled[filled.length - 1] : null;
    const lastCash = d.place === 'shop' ? d.shop_cash : null;
    const needs = [];
    if (last && has(lastCash)) { const df = num(lastCash) - num(last.cash), lv = tol(df, x.s.cash_tol); if (lv) flags.push(flag('last_cash_mismatch', lv, 'দিন শেষের নগদ শেষ লাইনের নগদের সমান নয়', 'End-of-day cash differs from the last line\'s cash', df)); if (df !== 0 && (x.s.cash_tol === undefined || x.s.cash_tol === null)) needs.push('cash_tol'); }
    const ls = d.place === 'shop' ? d.shop_last : d.place === 'factory' ? d.fac_last : null;
    if (has(ls) && num(ls) !== filled.length) flags.push(flag('last_serial_mismatch', 'yellow', 'শেষ লাইনের ক্রম নং লাইন-সংখ্যার সাথে মেলে না (পৃষ্ঠা আলাদা হলে ঠিক আছে)', 'Last serial no. differs from the number of lines (fine if the register runs over several pages)', undefined));
    return { v: { lines_n: filled.length }, flags, needs };
  },
};
})();
