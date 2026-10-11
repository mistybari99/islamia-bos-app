/* Islamia BOS · form definitions (batch C: sales & owner papers), taken field by field from the BOS Build Kit v1.39.
   20-1 Customer order form · 20-2 Discount approval slip · 20-3 Return & complaint register · 20-4 Party & wholesale invoice
   08-1 Maintenance request & record · 01-1 Weekly review note · 01-2 Monthly P&L and KPI sheet.
   Every limit comes from Location Settings; nothing is invented. A missing setting is reported as "data needed". */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO } = B.f;
B.forms = B.forms || {};

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const UNITS = { kg: L('কেজি', 'KG'), pc: L('পিস', 'Piece'), lb: L('পাউন্ড', 'Pound') };
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const itemOf = (x, code) => (x.env.byCode && x.env.byCode.get(code)) || null;
const unitOf = (x, code) => { const it = itemOf(x, code); return it ? (UNITS[it.unit] || L(it.unit || '', it.unit || '')) : ''; };
const r2 = (n) => Math.round(n * 100) / 100;
const noItems = (rows) => !rows.some((r) => has(r.item));
const NEED = L('তথ্য লাগবে', 'Data needed');
const sv = (x, k) => (x.s[k] === undefined || x.s[k] === null ? null : x.s[k]);
const money2 = (n) => '৳ ' + fm(n);

/* ============ 20-1 · Customer order form ============ */
const CHANNELS = [['counter', L('কাউন্টার', 'Counter')], ['phone', L('ফোন', 'Phone')], ['message', L('মেসেজ', 'Message')], ['party', L('পার্টি', 'Party')], ['other', L('অন্য', 'Other')]];
const ONLINE = [['fb', L('ফেসবুক', 'Facebook')], ['ig', L('ইনস্টাগ্রাম', 'Instagram')], ['tt', L('টিকটক', 'TikTok')], ['wa', L('হোয়াটসঅ্যাপ', 'WhatsApp')], ['foodapp', L('ফুড অ্যাপ', 'Food app')], ['other', L('অন্য', 'Other')]];
const DELIV = [['pickup', L('দোকান থেকে সংগ্রহ', 'Pick up from the shop')], ['own', L('নিজস্ব', 'Own delivery')], ['courier', L('কুরিয়ার', 'Courier')], ['foodapp', L('ফুড অ্যাপ', 'Food app')], ['other', L('অন্য', 'Other')]];
const PAYMODES = [['cash', L('নগদ', 'Cash')], ['bkash', L('বিকাশ', 'bKash')], ['nagad', L('Nagad (নগদ)', 'Nagad', 'Nagad (নগদ)')], ['card', L('কার্ড', 'Card')], ['other', L('অন্য', 'Other')]];
const notCol = (x) => x.d.not_collected;
const handover = (x) => !x.d.not_collected;
B.forms['20-1'] = {
  title: L('কাস্টমার অর্ডার ফরম', 'Customer order form'),
  head: [ST('taker', L('অর্ডার গ্রহণকারী (Order Taker)', 'Order taker'), { req: true }),
    CH('order_type', L('ধরন', 'Type'), [['normal', L('সাধারণ পণ্য', 'Normal goods')], ['custom', L('কাস্টম-মেইড', 'Custom-made')]], { req: true }),
    CH('channel', L('মাধ্যম (Channel)', 'Channel'), CHANNELS, { req: true }), T('channel_other', L('অন্য মাধ্যম', 'Other channel'), { show: (x) => x.d.channel === 'other' }),
    CH('online', L('অনলাইন', 'Online'), ONLINE), T('online_other', L('অন্য অনলাইন', 'Other online'), { show: (x) => x.d.online === 'other' })],
  sections: [
    { title: L('কাস্টমারের রসিদ — কাস্টমার', 'Customer receipt — customer'), fields: [
      T('cust_name', L('নাম', 'Name'), { req: true }), T('cust_phone', L('ফোন', 'Phone'), { req: true }),
      CH('deliv_mode', L('ডেলিভারি', 'Delivery'), [['pickup', L('শোরুম থেকে সংগ্রহ', 'Pick up from the showroom')], ['home', L('হোম ডেলিভারি', 'Home delivery')]], { req: true }),
      T('address', L('ঠিকানা (ডেলিভারি হলে)', 'Address (if delivered)'), { wide: true, show: (x) => x.d.deliv_mode === 'home', req: (x) => x.d.deliv_mode === 'home' }),
      CH('deliv_by', L('ডেলিভারি মাধ্যম', 'Delivery by'), DELIV), T('deliv_other', L('অন্য ডেলিভারি মাধ্যম', 'Other delivery mode'), { show: (x) => x.d.deliv_by === 'other' }),
      D('deliv_date', L('ডেলিভারির তারিখ', 'Delivery date'), { req: true }), TM('deliv_time', L('সময়', 'Time'), { req: true })] },
    { title: L('অর্ডারের পণ্য', 'Order items'), fields: [
      TABLE('items', null, [ITEM('item', L('আইটেম কোড', 'Item code'), { req: true, wide: true }), T('desc', L('পণ্যের বিবরণ · আকার · ফ্লেভার', 'Description · size · flavour'), { wide: true }),
        N('qty', L('পরিমাণ', 'Quantity'), { req: true }),
        T('msg', L('কেকে লিখিত বার্তা (বানানসহ)', 'Message on the cake (with spelling)'), { wide: true }), T('design', L('ডিজাইন · রং', 'Design · colour')), T('special', L('বিশেষ নির্দেশ', 'Special instruction'), { wide: true })], { min: 1 })] },
    { title: L('টাকা', 'Money'), fields: [
      M('total', L('মোট', 'Total'), { req: true }),
      M('discount', L('ডিসকাউন্ট', 'Discount')), T('disc_slip', L('ডিসকাউন্ট স্লিপ নং', 'Discount slip no.'), { show: (x) => num(x.d.discount) > 0 }),
      M('advance', L('অ্যাডভান্স', 'Advance')), SEL('adv_mode', L('অ্যাডভান্স কীভাবে', 'Advance paid by'), PAYMODES, { show: (x) => num(x.d.advance) > 0 }), T('adv_other', L('অন্য মাধ্যম', 'Other mode'), { show: (x) => num(x.d.advance) > 0 && x.d.adv_mode === 'other' }),
      CALC('balance', L('বাকি', 'Balance due'), 'money', { big: true }),
      NOTE(L('পণ্য নেওয়ার সময় এই রসিদ দেখান। বাকি টাকা তখনই পেমেন্ট করুন। কাস্টম-মেইড পণ্যের অ্যাডভান্স ফেরতযোগ্য নয়। অর্ডার বদলাতে চাইলে ডেলিভারির কমপক্ষে একদিন আগে জানাবেন।', 'Show this receipt when collecting. Pay the balance then. The advance on custom-made goods is not refundable. Tell us at least one day before delivery to change an order.'), 'ok')] },
    { title: L('অর্ডার গ্রহণের সাথে সাথে · কারখানা (Order Intake & Factory)', 'At order intake · Factory'), fields: [
      CK('on_board', L('পেন্ডিং বোর্ডে লেখা হয়েছে', 'Written on the pending board'), { req: true }), TM('board_time', L('সময়', 'Time')),
      CK('board_no', L('বোর্ডের নং = এই ফরমের ছাপা নং', 'Board number = printed number of this form'), { req: true }), ST('board_checker', L('যাচাইকারী (Checked by)', 'Checked by')),
      CK('sent_factory', L('কারখানার কপি প্রেরিত (Sent)', 'Factory copy sent')), TM('sent_time', L('সময়', 'Time')),
      CK('factory_deadline', L('কারখানা সময়সীমা নিশ্চিত করেছে', 'Factory confirmed the deadline'), { req: true }),
      CK('factory_done', L('কারখানা: উৎপাদন সম্পন্ন', 'Factory: production done')), ST('factory_sign', L('কারখানার স্বাক্ষর', 'Factory signature')), T('xfer_no', L('ট্রান্সফার চালান নং', 'Transfer challan no.'))] },
    { title: L('পণ্য হ্যান্ডওভার (Handover) — নির্ধারিত ক্রমে', 'Handover of goods — in this order'), fields: [
      NOTE(L('ক্রম মানতে হবে: ১) আগে বকেয়া পেমেন্ট, ২) কাস্টমারের সামনে অর্ডার যাচাই, ৩) কাস্টমারের স্বাক্ষর, ৪) বোর্ড থেকে সরানো।', 'Keep this order: 1) due payment first, 2) check the order with the customer, 3) customer signs, 4) remove from the board.'), 'warn'),
      M('due_paid', L('১ · প্রথমে বকেয়া পেমেন্ট — নেওয়া হলো', '1 · Due payment collected first'), { req: handover }),
      CH('due_mode', L('কীভাবে', 'How'), [['cash', L('নগদ', 'Cash')], ['digital', L('ডিজিটাল', 'Digital')]]), TM('due_time', L('সময়', 'Time')),
      CK('chk_item', L('২ · কাস্টমারের উপস্থিতিতে যাচাই — পণ্য', '2 · Checked with the customer — goods'), { req: handover }), CK('chk_qty', L('পরিমাণ', 'Quantity'), { req: handover }),
      CK('chk_msg', L('লিখিত বার্তা / বানান', 'Written message / spelling'), { req: handover }), CK('chk_design', L('ডিজাইন', 'Design'), { req: handover }),
      CK('cust_signed', L('৩ · কাস্টমারের স্বাক্ষর নেওয়া হয়েছে', '3 · Customer signed'), { req: handover }), TM('sign_time', L('সময়', 'Time')),
      CH('received_by', L('গ্রহণকারী (Received by)', 'Received by'), [['self', L('কাস্টমার নিজে', 'Customer himself')], ['rep', L('প্রতিনিধি', 'Representative')]], { req: handover }),
      T('rep_name', L('প্রতিনিধির নাম', 'Representative name'), { show: (x) => x.d.received_by === 'rep', req: (x) => x.d.received_by === 'rep' && handover(x) }),
      CK('off_board', L('৪ · বোর্ড থেকে সরানো হয়েছে', '4 · Removed from the board')), CK('book_crossed', L('বইয়ের কপিতে দুই দাগের ক্রস, সময় ও স্বাক্ষর', 'Book copy crossed with two lines, time and signature')),
      T('complaint_no', L('অভিযোগ থাকলে রিটার্ন ও অভিযোগ রেজিস্টার নং', 'Complaint register no. (if any)'))] },
    { collapsed: true, title: L('৫ · ডেলিভারি নেওয়া হয়নি / বাতিল অর্ডার', '5 · Not collected / cancelled order'), fields: [
      CK('not_collected', L('ডেলিভারি নেওয়া হয়নি (Not Collected) / বাতিল', 'Not collected / cancelled')),
      TM('call1', L('ফোন করা হয়েছে — সময়', 'First call — time'), { show: notCol }), TM('call2', L('দ্বিতীয়বার — সময়', 'Second call — time'), { show: notCol }),
      CALC('hold_text', L('পণ্য রাখা হবে (লোকেশন সেটিংস থেকে)', 'Goods held for (from location settings)'), 'text', { show: notCol }),
      CH('adv_fate', L('অ্যাডভান্স (Advance)', 'Advance'), [['refund', L('ফেরত', 'Refund')], ['adjust', L('সমন্বয়', 'Adjust')], ['income', L('ব্যবসার আয়ে', 'To business income')]], { show: notCol, req: (x) => x.d.not_collected && num(x.d.advance) > 0 }),
      CH('goods_fate', L('পণ্য', 'Goods'), [['display', L('ডিসপ্লেতে', 'To display')], ['g2', L('২য় গ্রেড', '2nd grade')], ['waste', L('অপচয়', 'Wastage')]], { show: notCol, req: (x) => x.d.not_collected }),
      T('fate_reason', L('কারণ', 'Reason'), { show: notCol, req: (x) => x.d.not_collected }), ST('decided_by', L('সিদ্ধান্তগ্রহণকারী (Decided by)', 'Decided by'), { show: notCol, req: (x) => x.d.not_collected })] },
    { title: L('স্বাক্ষর', 'Signatures'), fields: [
      NOTE(L('উপরের অংশ বইয়ে থাকে; ১ম কপি কাস্টমারের, ২য় কপি শোরুমের, ৩য় কপি কারখানার। কাস্টমারের স্লিপে প্রতিষ্ঠানের স্বাক্ষর ও সিল লাগবে।', 'The office part stays in the book; copy 1 is the customer, copy 2 the showroom, copy 3 the factory. The customer slip needs the authorised signature and stamp.'), 'ok'),
      ST('manager', L('শোরুম ম্যানেজার', 'Showroom manager'))] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const bal = r2(num(d.total) - num(d.discount) - num(d.advance)); v.balance = bal;
    if (has(d.total) && bal < 0) flags.push(flag('adv_over_total', 'red', 'অ্যাডভান্স ও ডিসকাউন্ট মোটের চেয়ে বেশি', 'Advance and discount exceed the total', bal));
    if (has(d.deliv_date) && d.deliv_date < x.date) flags.push(flag('delivery_past', 'red', 'ডেলিভারির তারিখ অর্ডারের তারিখের আগে', 'Delivery date is before the order date'));
    const dl = sv(x, 'discount_limit');
    if (num(d.discount) > 0) {
      if (dl === null) needs.push('discount_limit');
      if (dl === null || r2(num(d.discount)) > dl) flags.push(flag('discount_over', has(d.disc_slip) ? 'yellow' : 'red', has(d.disc_slip) ? 'ডিসকাউন্ট সীমার উপরে — স্লিপ আছে' : 'ডিসকাউন্ট সীমার উপরে — অনুমোদন স্লিপ (২০-২) লাগবে', has(d.disc_slip) ? 'Discount above the limit — slip given' : 'Discount above the limit — approval slip (20-2) needed', num(d.discount)));
    }
    if (d.order_type === 'custom' && d.adv_fate === 'refund') flags.push(flag('custom_refund', 'yellow', 'কাস্টম-মেইড অর্ডারের অ্যাডভান্স সাধারণত ফেরত নয়', 'Advance on a custom-made order is normally not refunded', num(d.advance)));
    const hd = sv(x, 'order_hold_days'); v.hold_text = hd === null ? NEED : L(fm(hd) + ' দিন', fm(hd) + ' days');
    if (d.not_collected && hd === null) needs.push('order_hold_days');
    if (d.not_collected) flags.push(flag('order_not_collected', 'yellow', 'অর্ডার নেওয়া হয়নি / বাতিল', 'Order not collected / cancelled', num(d.advance) > 0 ? num(d.advance) : undefined));
    if (has(d.board_checker) && d.board_checker === d.taker) flags.push(flag('board_checker_is_maker', 'yellow', 'বোর্ড যাচাইকারী ও অর্ডার গ্রহণকারী একই জন', 'Board checker and order taker are the same person'));
    if (noItems(x.rows('items'))) flags.push(flag('no_items', 'red', 'অর্ডারে কোনো পণ্য লেখা নেই', 'No item lines on the order'));
    return { v, flags, needs };
  },
};

/* ============ 20-2 · Discount approval slip ============ */
B.forms['20-2'] = {
  title: L('ডিসকাউন্ট অনুমোদন স্লিপ', 'Discount approval slip'),
  head: [TM('time', L('সময়', 'Time')), T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.')), T('memo_no', L('অর্ডার / মেমো নং (থাকলে)', 'Order / memo no. (if any)'))],
  sections: [
    { title: L('ডিসকাউন্টের পণ্য', 'Discounted items'), fields: [
      NOTE(L('ডিসকাউন্টের পরের বিক্রয় মূল্যই দিনের মোট বিক্রিতে যাবে। ডিসকাউন্টের মোট অঙ্ক ক্লোজিং রিপোর্টের নোটে লিখুন।', 'The sale price after discount is what goes into the day’s total sales. Write the total discount in the closing report note.'), 'ok'),
      TABLE('lines', null, [ITEM('item', L('আইটেম কোড', 'Item code'), { req: true, wide: true }), T('desc', L('পণ্যের বিবরণ', 'Product description'), { wide: true }), N('qty', L('পরিমাণ', 'Quantity'), { req: true }),
        M('list_price', L('তালিকা মূল্য ৳ (প্রতি একক)', 'List price ৳ (per unit)'), { req: true }), M('disc', L('ডিসকাউন্ট ৳', 'Discount ৳'), { req: true }), CALC('sale', L('বিক্রয় মূল্য ৳', 'Sale price ৳'), 'money')], { min: 3 }),
      CALC('tot_list', L('মোট তালিকা মূল্য', 'Total list price'), 'money'), CALC('tot_disc', L('মোট ডিসকাউন্ট', 'Total discount'), 'money', { big: true }), CALC('tot_sale', L('মোট বিক্রয় মূল্য', 'Total sale price'), 'money')] },
    { title: L('কারণ ও অনুমোদন', 'Reason & approval'), fields: [
      CH('reason', L('ডিসকাউন্টের কারণ', 'Reason for the discount'), [['old', L('পুরোনো কাস্টমার', 'Regular customer')], ['bulk', L('পরিমাণে বেশি', 'Large quantity')], ['cond', L('পণ্যের অবস্থা', 'Condition of goods')], ['offer', L('অনুমোদিত অফার', 'Approved offer')], ['other', L('অন্য', 'Other')]], { req: true }),
      T('reason_other', L('অন্য কারণ', 'Other reason'), { show: (x) => x.d.reason === 'other', req: (x) => x.d.reason === 'other' }),
      T('mkt_line', L('মার্কেটিং ব্যয় রেজিস্টারের লাইন নং', 'Marketing expense register line no.'), { show: (x) => x.d.reason === 'offer', req: (x) => x.d.reason === 'offer' }),
      CALC('limit_text', L('সীমা যাচাই (সীমা: লোকেশন সেটিংস)', 'Limit check (limit: location settings)'), 'text'),
      ST('approved_by', L('অনুমোদনকারী (Approved by)', 'Approved by'), { show: (x) => x.v.over_limit, req: (x) => x.v.over_limit }),
      TM('approved_time', L('অনুমোদনের সময়', 'Approval time'), { show: (x) => x.v.over_limit, req: (x) => x.v.over_limit }),
      CK('phone_approval', L('ফোনে অনুমোদন (পরে স্বাক্ষর)', 'Approved by phone (signature later)'), { show: (x) => x.v.over_limit }),
      ST('seller', L('বিক্রয়কারী (Seller)', 'Seller'), { req: true }), ST('manager', L('শোরুম ম্যানেজার', 'Showroom manager'))] },
  ],
  calc(x) {
    const rows = x.rows('lines'), flags = [], needs = [], v = {};
    const out = rows.map((r) => ({ sale: r2(num(r.qty) * num(r.list_price) - num(r.disc)) }));
    if (noItems(rows)) flags.push(flag('no_items', 'red', 'কোনো পণ্যের লাইন নেই', 'No item lines'));
    v.tot_list = r2(sum(rows.map((r) => num(r.qty) * num(r.list_price)))); v.tot_disc = r2(sum(rows.map((r) => r.disc))); v.tot_sale = r2(v.tot_list - v.tot_disc);
    const lim = sv(x, 'discount_limit'), disc = v.tot_disc;
    if (lim === null) needs.push('discount_limit');
    const over = disc > 0 && (lim === null || disc > lim); v.over_limit = over;
    v.limit_text = disc <= 0 ? '' : lim === null ? NEED : over ? L('সীমার উপরে — অনুমোদন নেওয়া হয়েছে কি?', 'Over the limit — approval needed') : L('নির্ধারিত সীমার ভেতরে — অনুমোদন লাগবে না', 'Within the fixed limit — no approval needed');
    if (over) flags.push(flag('discount_over_limit', has(x.d.approved_by) ? 'yellow' : 'red', has(x.d.approved_by) ? 'ডিসকাউন্ট সীমার উপরে (অনুমোদিত)' : 'ডিসকাউন্ট সীমার উপরে — অনুমোদনকারী নেই', has(x.d.approved_by) ? 'Discount above the limit (approved)' : 'Discount above the limit — no approver', disc));
    if (has(x.d.approved_by) && x.d.approved_by === x.d.seller) flags.push(flag('approver_is_maker', 'red', 'অনুমোদনকারী ও বিক্রয়কারী একই জন', 'Approver and seller are the same person'));
    if (rows.some((r) => r2(num(r.disc)) > r2(num(r.qty) * num(r.list_price)) && has(r.list_price))) flags.push(flag('disc_over_price', 'red', 'কোনো লাইনে ডিসকাউন্ট তালিকা মূল্যের চেয়ে বেশি', 'A line has a discount above its list price'));
    rows.forEach((r) => { const it = itemOf(x, r.item); if (it && has(r.list_price) && num(it.sell_price) > 0 && num(it.sell_price) !== num(r.list_price) && !flags.some((f) => f.code === 'list_price_diff')) flags.push(flag('list_price_diff', 'yellow', 'তালিকা মূল্য মূল্য-তালিকার সাথে মেলেনি', 'List price differs from the price list')); });
    return { v, rows: { lines: out }, flags, needs };
  },
};

/* ============ 20-3 · Return & complaint register ============ */
const COMPLAINTS = [['taste', L('স্বাদ', 'Taste')], ['smell', L('গন্ধ / নষ্ট', 'Smell / spoiled')], ['broken', L('ভাঙা / চেহারা', 'Broken / appearance')], ['short', L('পরিমাণে কম', 'Short quantity')], ['wrong', L('ভুল পণ্য', 'Wrong goods')], ['late', L('দেরি', 'Late')], ['staff', L('কর্মীর আচরণ', 'Staff behaviour')]];
B.forms['20-3'] = {
  title: L('রিটার্ন ও অভিযোগ রেজিস্টার', 'Return & complaint register'),
  head: [TM('time', L('সময়', 'Time')), T('cust_name', L('কাস্টমারের নাম', "Customer's name"), { req: true }), T('cust_phone', L('ফোন', 'Phone')), T('sheet_no', L('দৈনিক শোরুম শিট নং', 'Daily showroom sheet no.'))],
  sections: [
    { title: L('পণ্য', 'Item'), fields: [
      ITEM('item', L('আইটেম কোড ও নাম', 'Item code and name'), { req: true, wide: true }), N('qty', L('পরিমাণ', 'Quantity'), { req: true }),
      D('buy_date', L('ক্রয়ের তারিখ', 'Date of purchase')), T('memo_no', L('মেমো / অর্ডার নং', 'Memo / order no.')), T('tag_prod', L('ট্যাগ রং / উৎপাদন তারিখ', 'Tag colour / production date'))] },
    { title: L('অভিযোগের বিবরণ (Complaint)', 'Complaint'), fields: [
      ...COMPLAINTS.map(([id, l]) => CK('c_' + id, l)), CK('c_sick', L('খেয়ে অসুস্থ', 'Fell ill after eating')),
      TM('sick_informed', L('ব্যবস্থাপনাকে জানানোর সময় (সেদিনই)', 'Time management was informed (same day)'), { show: (x) => x.d.c_sick, req: (x) => x.d.c_sick }),
      CK('c_other', L('অন্য', 'Other')), T('c_other_text', L('অন্য — কী', 'Other — what'), { show: (x) => x.d.c_other }),
      TA('detail', L('বিবরণ', 'Details'), { req: true }),
      NOTE(L('প্রতিটি অভিযোগ লেখা হবে — স্টাফের কাছে অযৌক্তিক মনে হলেও।', 'Every complaint is written down, even if it seems unreasonable to the staff.'), 'warn'),
      CK('taken_back', L('পণ্যটি জমা নেওয়া হয়েছে', 'The product has been taken in'), { req: true }), T('store_place', L('সংরক্ষণের স্থান', 'Storage place'), { show: (x) => x.d.taken_back }),
      NOTE(L('তদন্তের আগে নষ্ট করা যাবে না।', 'Do not destroy it before the investigation.'), 'warn')] },
    { title: L('সিদ্ধান্ত ১ · কাস্টমারের জন্য', 'Decision 1 · For the customer'), fields: [
      CK('d_replace', L('বদলে দেওয়া হলো', 'Replaced')), CK('d_refund', L('টাকা ফেরত', 'Money refunded')),
      M('refund_amt', L('ফেরতের টাকা', 'Refund amount'), { show: (x) => x.d.d_refund, req: (x) => x.d.d_refund }),
      CALC('limit_text', L('সীমা যাচাই (লোকেশন সেটিংস)', 'Limit check (location settings)'), 'text', { show: (x) => x.d.d_refund }),
      ST('approved_by', L('বাইরে হলে অনুমোদনকারী (Approved by)', 'Approver (if over the limit)'), { show: (x) => x.v.over_limit, req: (x) => x.v.over_limit }),
      TM('approved_time', L('অনুমোদনের সময়', 'Approval time'), { show: (x) => x.v.over_limit, req: (x) => x.v.over_limit }), CK('phone_approval', L('ফোনে অনুমোদন (পরে স্বাক্ষর)', 'Approved by phone (signature later)'), { show: (x) => x.v.over_limit }),
      CK('d_adjust', L('পরের বার সমন্বয়', 'Adjust next time')), CK('d_sorry', L('দুঃখপ্রকাশ, কিছু দেওয়া হয়নি', 'Apology only, nothing given')),
      TM('handed_time', L('প্রদানের সময়', 'Time given')), ST('handed_by', L('প্রদানকারী (Handed over by)', 'Handed over by'))] },
    { title: L('সিদ্ধান্ত ২ · পণ্যের জন্য', 'Decision 2 · For the product'), fields: [
      CH('p_fate', L('পণ্যের ব্যবস্থা', 'What happens to the product'), [['nodisplay', L('ডিসপ্লেতে ফেরত যাবে না', 'Not back to display')], ['g2', L('২য় গ্রেড', '2nd grade')], ['waste', L('অপচয় হিসেবে বাদ', 'Written off as wastage')], ['factory', L('কারখানায় ফেরত', 'Returned to the factory')]], { req: true }),
      T('challan_no', L('চালান নং', 'Challan no.'), { show: (x) => x.d.p_fate === 'factory', req: (x) => x.d.p_fate === 'factory' }),
      CK('posted', L('স্টক লেজারে এন্ট্রি (Posting) করা হয়েছে', 'Entered (posted) in the stock ledger'), { req: true })] },
    { who: 'checker', title: L('তদন্ত (Investigation) — হাব পূরণ করবে', 'Investigation — hub fills'), fields: [
      T('batch', L('কোন ব্যাচ / উৎপাদন তারিখ', 'Batch / production date'), { who: 'checker' }), T('producer', L('উৎপাদনকারী (Produced by) ও প্রেরক', 'Produced by and sender'), { who: 'checker' }),
      N('prev_count', L('এ মাসে এই পণ্যে আগের অভিযোগ (টি)', 'Earlier complaints on this product this month'), { who: 'checker' }), T('prev_reg', L('রিটার্ন ও অভিযোগ রেজিস্টার নং', 'Return & complaint register no.'), { who: 'checker' }),
      TA('root_cause', L('মূল কারণ', 'Root cause'), { who: 'checker', req: true }),
      NOTE(L('মূল কারণ না লিখে ফাইল বন্ধ করা যাবে না।', 'The file cannot be closed without writing the root cause.'), 'warn', { who: 'checker' }),
      TA('action', L('গৃহীত ব্যবস্থা (Action Taken)', 'Action taken'), { who: 'checker' }), ST('investigated_by', L('তদন্তকারী (Investigated by) — হাব', 'Investigated by — hub'), { who: 'checker' }), ST('responsible', L('দায়িত্ব', 'Responsible'), { who: 'checker' }), D('deadline', L('সময়সীমা', 'Deadline'), { who: 'checker' }),
      CK('in_worklist', L('কাজের তালিকায় যোগ হয়েছে', 'Added to the work list'), { who: 'checker', req: true }),
      TM('call_time', L('কাস্টমারকে ফোন — সময়', 'Call to the customer — time'), { who: 'checker' }),
      CH('feedback', L('মতামত', 'Feedback'), [['happy', L('সন্তুষ্ট', 'Satisfied')], ['unhappy', L('অসন্তুষ্ট', 'Not satisfied')]], { who: 'checker' }), T('unhappy_why', L('অসন্তুষ্ট হলে কারণ', 'Reason if not satisfied'), { who: 'checker', show: (x) => x.c.feedback === 'unhappy' }),
      CK('resolved', L('সমাধান — হ্যাঁ', 'Resolved'), { who: 'checker', req: true }), D('resolved_date', L('সমাধানের তারিখ', 'Resolved on'), { who: 'checker', show: (x) => x.c.resolved }), ST('resolved_by', L('সমাধানকারী (Resolved by)', 'Resolved by'), { who: 'checker', show: (x) => x.c.resolved })] },
    { title: L('গ্রহণ', 'Received'), fields: [ST('received_by', L('গ্রহণকারী (Received by)', 'Received by'), { req: true }), ST('manager', L('শোরুম ম্যানেজার', 'Showroom manager'))] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const lim = sv(x, 'refund_limit'), amt = num(d.refund_amt);
    if (d.d_refund) { if (lim === null) needs.push('refund_limit'); }
    const over = !!d.d_refund && amt > 0 && (lim === null || amt > lim); v.over_limit = over;
    v.limit_text = !d.d_refund ? '' : lim === null ? NEED : over ? L('সীমার বাইরে — অনুমোদন লাগবে', 'Over the limit — approval needed') : L('সীমার ভেতরে', 'Within the limit');
    if (over) flags.push(flag('refund_over_limit', has(d.approved_by) ? 'yellow' : 'red', has(d.approved_by) ? 'টাকা ফেরত সীমার বাইরে (অনুমোদিত)' : 'টাকা ফেরত সীমার বাইরে — অনুমোদনকারী নেই', has(d.approved_by) ? 'Refund over the limit (approved)' : 'Refund over the limit — no approver', amt));
    if (has(d.approved_by) && (d.approved_by === d.received_by || d.approved_by === d.handed_by)) flags.push(flag('approver_is_maker', 'red', 'অনুমোদনকারী ও গ্রহণকারী/প্রদানকারী একই জন', 'Approver is the receiver / giver'));
    if (d.c_sick) flags.push(flag('illness_complaint', 'yellow', 'খেয়ে অসুস্থ হওয়ার অভিযোগ — সেদিনই ব্যবস্থাপনাকে জানাতে হবে', 'Complaint of illness after eating — management must be told the same day'));
    if (has(d.item) && !d.d_replace && !d.d_refund && !d.d_adjust && !d.d_sorry) flags.push(flag('no_customer_decision', 'yellow', 'কাস্টমারের জন্য কোনো সিদ্ধান্ত টিক দেওয়া হয়নি', 'No decision ticked for the customer'));
    if (has(d.item) && !d.taken_back) flags.push(flag('product_not_taken', 'red', 'পণ্যটি জমা নেওয়া হয়নি', 'The product was not taken in'));
    if (x.c.resolved === undefined || !x.c.resolved) { if (Object.values(x.c).some(has)) flags.push(flag('complaint_open', 'yellow', 'অভিযোগ এখনো সমাধান হয়নি', 'Complaint is not resolved yet', undefined, { src: 'check' })); }
    return { v, rows: {}, flags, needs };
  },
};

/* ============ 20-4 · Party & wholesale invoice ============ */
const isInv = (x) => x.d.doc === 'invoice';
const isQuote = (x) => x.d.doc === 'quote';
B.forms['20-4'] = {
  title: L('পার্টি ও পাইকারি ইনভয়েস', 'Party & wholesale invoice'),
  head: [CH('doc', L('কোটেশন না ইনভয়েস', 'Quotation or invoice'), [['quote', L('কোটেশন (Quotation)', 'Quotation')], ['invoice', L('ইনভয়েস (Invoice) — মালামাল যাচ্ছে', 'Invoice — goods are going')]], { req: true }),
    T('party', L('পার্টির নাম', 'Party name'), { req: true }), T('phone', L('ফোন', 'Phone')), T('order_no', L('অর্ডার নং (থাকলে)', 'Order no. (if any)'))],
  sections: [
    { title: L('কোটেশন', 'Quotation'), show: isQuote, fields: [
      NOTE(L('কোটেশন মানে শুধু দাম জানানো; মালামাল ও টাকা নয়।', 'A quotation only tells the price; no goods and no money.'), 'ok'),
      D('valid_until', L('মেয়াদ (এই তারিখ পর্যন্ত)', 'Valid until')), T('agreed_invoice', L('পার্টি সম্মত হলে ইনভয়েস নং', 'Invoice no. if the party agreed')), CK('not_agreed', L('সম্মত হননি — পাতা বইয়ে থাকবে', 'Not agreed — page stays in the book'))] },
    { title: L('পেমেন্টের শর্ত', 'Payment terms'), fields: [
      CH('pay', L('পেমেন্ট (Payment)', 'Payment'), [['cash', L('নগদ', 'Cash')], ['credit', L('বাকি', 'Credit')], ['part', L('আংশিক', 'Part')]]),
      N('credit_days', L('বাকির সময় (দিন)', 'Credit period (days)'), { show: (x) => x.d.pay === 'credit' || x.d.pay === 'part' }), D('due_date', L('পেমেন্টের শেষ তারিখ', 'Last date of payment'), { show: (x) => x.d.pay === 'credit' || x.d.pay === 'part' }),
      M('prev_dues', L('আগের বকেয়া', 'Earlier dues'))] },
    { title: L('মালামাল', 'Goods'), fields: [
      NOTE(L('পার্টির দর প্রতিষ্ঠানের অনুমোদিত দরেই হবে — মৌখিক নির্দেশে নয়। ক্রেডিট সীমার বাইরে গেলে নতুন বাকিতে মালামাল যাবে না।', 'The party’s rate must be the rate approved by the business, never on verbal instruction. If over the credit limit, no new goods on credit.'), 'warn'),
      TABLE('lines', null, [ITEM('item', L('আইটেম কোড', 'Item code'), { req: true, wide: true }), T('desc', L('পণ্যের বিবরণ', 'Product description'), { wide: true }), T('unit', L('একক', 'Unit')), N('qty', L('পরিমাণ', 'Quantity'), { req: true }), M('rate', L('দর ৳', 'Rate ৳'), { req: true }), CALC('line_total', L('মোট ৳', 'Total ৳'), 'money')], { min: 3 }),
      CALC('grand', L('সর্বমোট (Grand Total)', 'Grand total'), 'money', { big: true })] },
    { title: L('টাকা', 'Money'), show: isInv, fields: [
      M('discount', L('(−) ডিসকাউন্ট', '(−) Discount')), T('disc_slip', L('ডিসকাউন্ট স্লিপ নং', 'Discount slip no.'), { show: (x) => num(x.d.discount) > 0 }),
      CALC('inv_total', L('এই ইনভয়েসের মোট', 'Total of this invoice'), 'money'),
      M('cash_today', L('আজ নগদ পাওয়া গেল', 'Cash received today')), SEL('cash_mode', L('কীভাবে', 'How'), [['cash', L('নগদ', 'Cash')], ['bkash', L('বিকাশ', 'bKash')], ['bank', L('ব্যাংক', 'Bank')], ['other', L('অন্য', 'Other')]], { show: (x) => num(x.d.cash_today) > 0 }),
      T('cash_other', L('অন্য মাধ্যম', 'Other mode'), { show: (x) => num(x.d.cash_today) > 0 && x.d.cash_mode === 'other' }),
      CALC('inv_due', L('এই ইনভয়েসের বাকি', 'Balance of this invoice'), 'money', { big: true }), CALC('all_due', L('মোট বকেয়া (আগের + আজকের)', 'Total outstanding (earlier + today)'), 'money', { big: true })] },
    { title: L('যাচাই ও এন্ট্রি', 'Checks & posting'), show: isInv, fields: [
      M('party_limit', L('পার্টির ক্রেডিট সীমা (পার্টি ও পাইকারি লেজার থেকে)', 'Party credit limit (from the party & wholesale ledger)'), { req: (x) => isInv(x) && x.d.credit_ok === 'inside' }),
      CH('credit_ok', L('ক্রেডিট সীমা', 'Credit limit'), [['inside', L('সীমার ভেতরে', 'Within the limit')], ['outside', L('সীমার বাইরে — অনুমোদন', 'Outside — approved')]], { req: isInv }),
      ST('approved_by', L('সীমার বাইরে হলে অনুমোদনকারী (Approved by)', 'Approver (if outside the limit)'), { show: (x) => x.d.credit_ok === 'outside', req: (x) => x.d.credit_ok === 'outside' }),
      CK('posted_ledger', L('পার্টি ও পাইকারি লেজারে এন্ট্রি (Posting)', 'Posted in the party & wholesale ledger'), { req: isInv }), T('ledger_line', L('পাতা / লাইন নং', 'Page / line no.')),
      CK('posted_sheet', L('দৈনিক শোরুম শিটে এন্ট্রি (নগদ অংশ)', 'Posted in the daily showroom sheet (cash part)')), T('sheet_no', L('শিট নং', 'Sheet no.'))] },
    { title: L('স্বাক্ষর', 'Signatures'), show: isInv, fields: [
      ST('prepared_by', L('প্রস্তুতকারী (Prepared by)', 'Prepared by'), { req: true }), T('delivered_by', L('বহনকারী / ডেলিভারি (Delivered by)', 'Delivered by')),
      CK('party_signed', L('পার্টির স্বাক্ষর নেওয়া হয়েছে', 'Party signed'), { req: isInv }), T('received_by', L('গ্রহণকারী (Received by) — পার্টির প্রতিনিধি', 'Received by — party representative'), { req: isInv })] },
  ],
  calc(x) {
    const d = x.d, rows = x.rows('lines'), flags = [], needs = [], v = {};
    const out = rows.map((r) => ({ line_total: r2(num(r.qty) * num(r.rate)) }));
    if (noItems(rows)) flags.push(flag('no_items', 'red', 'কোনো পণ্যের লাইন নেই', 'No item lines'));
    v.grand = r2(sum(rows.map((r) => num(r.qty) * num(r.rate))));
    v.inv_total = r2(v.grand - num(d.discount)); v.inv_due = r2(v.inv_total - num(d.cash_today)); v.all_due = r2(num(d.prev_dues) + v.inv_due);
    if (isInv(x)) {
      if (num(d.cash_today) > v.inv_total) flags.push(flag('cash_over_total', 'red', 'আজকের নগদ ইনভয়েসের মোটের চেয়ে বেশি', "Today's cash is more than the invoice total", r2(num(d.cash_today) - v.inv_total)));
      if (d.pay === 'cash' && v.inv_due > 0) flags.push(flag('cash_but_due', 'yellow', 'পেমেন্ট "নগদ" কিন্তু বাকি আছে', 'Payment is "cash" but a balance remains', v.inv_due));
      if (d.pay === 'credit' && v.inv_due > 0 && !has(d.credit_days)) flags.push(flag('credit_days_missing', 'yellow', 'বাকির সময় লেখা নেই', 'Credit period is not written', v.inv_due));
      if (d.credit_ok === 'outside') flags.push(flag('credit_outside', has(d.approved_by) ? 'yellow' : 'red', has(d.approved_by) ? 'ক্রেডিট সীমার বাইরে (অনুমোদিত)' : 'ক্রেডিট সীমার বাইরে — অনুমোদনকারী নেই', has(d.approved_by) ? 'Over the credit limit (approved)' : 'Over the credit limit — no approver', v.all_due));
      if (d.credit_ok === 'inside' && !has(d.party_limit)) flags.push(flag('credit_limit_missing', 'red', 'ক্রেডিট সীমা লেখা নেই — "সীমার ভেতরে" যাচাই করা যায়নি', 'Credit limit not entered — cannot confirm "inside the limit"'));
      if (d.credit_ok === 'inside' && has(d.party_limit) && v.all_due > num(d.party_limit)) flags.push(flag('credit_over_limit', 'red', 'মোট বকেয়া পার্টির ক্রেডিট সীমার উপরে, অথচ "সীমার ভেতরে" টিক', 'Total outstanding is over the party credit limit but "inside the limit" is ticked', r2(v.all_due - num(d.party_limit))));
      const dl = sv(x, 'discount_limit');
      if (num(d.discount) > 0) { if (dl === null) needs.push('discount_limit');
        if (dl === null || r2(num(d.discount)) > dl) flags.push(flag('discount_over', has(d.disc_slip) ? 'yellow' : 'red', has(d.disc_slip) ? 'ডিসকাউন্ট সীমার উপরে — স্লিপ আছে' : 'ডিসকাউন্ট সীমার উপরে — অনুমোদন স্লিপ (২০-২) লাগবে', has(d.disc_slip) ? 'Discount above the limit — slip given' : 'Discount above the limit — approval slip (20-2) needed', num(d.discount))); }
      if (has(d.approved_by) && d.approved_by === d.prepared_by) flags.push(flag('approver_is_maker', 'red', 'অনুমোদনকারী ও প্রস্তুতকারী একই জন', 'Approver and preparer are the same person'));
    }
    return { v, rows: { lines: out }, flags, needs };
  },
};

/* ============ 08-1 · Maintenance request & record ============ */
const PROBLEMS = [['p_stop', L('চলছে না', 'Not running')], ['p_cool', L('ঠান্ডা হচ্ছে না', 'Not cooling')], ['p_noise', L('শব্দ', 'Noise')], ['p_leak', L('লিক', 'Leak')], ['p_power', L('বিদ্যুৎ', 'Electrical')], ['p_other', L('অন্য', 'Other')]];
B.forms['08-1'] = {
  title: L('মেইনটেন্যান্স অনুরোধ ও রেকর্ড', 'Maintenance request & record'),
  head: [T('machine', L('যন্ত্রের নাম', 'Machine name'), { req: true }), T('machine_id', L('যন্ত্রের নং / পরিচয়', 'Machine no. / ID'), { req: true }),
    D('found_date', L('সমস্যা শনাক্তের তারিখ', 'Date problem found'), { req: true }), TM('found_time', L('সময়', 'Time'), { req: true }), ST('reported_by', L('রিপোর্টকারী (Reported by)', 'Reported by'), { req: true }), ST('requested_by', L('অনুরোধকারী (Requested by)', 'Requested by'))],
  sections: [
    { title: L('সমস্যা', 'Problem'), fields: [
      NOTE(L('যন্ত্র বিকল হলে শুধু মেরামত নয় — ভেতরে রাখা পণ্যের অবস্থাও যাচাই করতে হবে। বিকল অবস্থায় কত সময় ছিল, তা লিখতে হবে।', 'When a machine fails it is not only a repair: check the condition of the goods inside. Write how long it stayed out of order.'), 'warn'),
      ...PROBLEMS.map(([id, l]) => CK(id, l)), T('p_other_text', L('অন্য — কী', 'Other — what'), { show: (x) => x.d.p_other }),
      CH('work_stopped', L('কাজ বন্ধ আছে?', 'Is work stopped?'), YN), T('work_which', L('কোন কাজ', 'Which work'), { show: (x) => x.d.work_stopped === 'yes' }), T('work_alt', L('বিকল্প ব্যবস্থা', 'Alternative arrangement')),
      CH('goods_state', L('ভেতরের পণ্যের অবস্থা', 'Condition of the goods inside'), [['na', L('প্রযোজ্য নয়', 'Not applicable')], ['checked', L('যাচাই করা হয়েছে', 'Checked')]], { req: true }),
      T('goods_result', L('ফল', 'Result'), { show: (x) => x.d.goods_state === 'checked', req: (x) => x.d.goods_state === 'checked' }), CK('goods_moved', L('পণ্য সরানো হয়েছে', 'Goods moved'), { show: (x) => x.d.goods_state === 'checked' }),
      PHOTO('photos', L('যন্ত্র / সমস্যার ছবি', 'Photos of the machine / problem'))] },
    { title: L('দায়িত্ব ও অনুমোদন', 'Assignment & approval'), fields: [
      CH('assigned', L('দায়িত্বধারী (Assigned to)', 'Assigned to'), [['own', L('নিজেরা', 'Our own people')], ['tech', L('বাইরের টেকনিশিয়ান (Technician)', 'Outside technician')]]),
      T('tech_name', L('নাম / ফোন', 'Name / phone')),
      M('est_cost', L('আনুমানিক খরচ', 'Estimated cost'), { req: true }), ST('approved_by', L('অনুমোদনকারী (Approved by)', 'Approved by'), { req: true })] },
    { title: L('মেরামত শেষ', 'Repair finished'), fields: [
      D('done_date', L('মেরামত শেষের তারিখ', 'Repair finished — date')), TM('done_time', L('সময়', 'Time')),
      CALC('downtime', L('মোট বন্ধের সময় (ঘণ্টা)', 'Total hours out of order'), 'num', { big: true }),
      M('actual_cost', L('প্রকৃত খরচ', 'Actual cost')), CH('cost_type', L('খরচের ধরন', 'Cost type'), [['parts', L('যন্ত্রাংশ', 'Parts')], ['labour', L('মজুরি', 'Labour')], ['both', L('দুটোই', 'Both')]]),
      CK('receipt', L('রসিদ সংযুক্ত', 'Receipt attached')),
      CH('pay', L('পেমেন্ট', 'Payment'), [['imprest', L('ইমপ্রেস্ট (খরচের বাক্স)', 'Imprest (petty cash box)')], ['hub', L('হাবের নগদ', 'Hub cash')], ['bank', L('ব্যাংক', 'Bank')], ['mobile', L('মোবাইল', 'Mobile')], ['owner', L('মালিকের ব্যক্তিগত', "Owner's personal")], ['other', L('অন্য', 'Other')]]),
      T('pay_other', L('অন্য', 'Other'), { show: (x) => x.d.pay === 'other' }), T('voucher_no', L('ব্যয় ভাউচার নং', 'Expense voucher no.'), { show: (x) => x.d.pay === 'imprest' }), T('ledger_line', L('ক্যাশ ও ব্যাংক লেজারের লাইন নং', 'Cash & bank ledger line no.')),
      N('times_year', L('একই যন্ত্রে এ বছরে (বার)', 'Times on this machine this year')), CK('replace_proposal', L('বারবার হলে বদলানোর প্রস্তাব', 'Proposal to replace if it keeps happening')),
      ST('received_by', L('মেরামত শেষ — গ্রহণকারী (Received by)', 'Repair finished — received by')), PHOTO('photos_done', L('মেরামতের পরের ছবি / রসিদ', 'Photos after repair / receipt'))] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    if (has(d.found_date) && has(d.found_time) && has(d.done_date) && has(d.done_time)) {
      const a = new Date(d.found_date + 'T' + d.found_time), b = new Date(d.done_date + 'T' + d.done_time), h = (b - a) / 36e5;
      v.downtime = Number.isFinite(h) ? Math.round(h * 10) / 10 : undefined;
      if (Number.isFinite(h) && h < 0) flags.push(flag('done_before_found', 'red', 'মেরামত শেষের সময় শনাক্তের সময়ের আগে', 'Repair finish time is before the time found'));
    }
    if (has(d.actual_cost) && has(d.est_cost) && num(d.actual_cost) > num(d.est_cost)) flags.push(flag('cost_over_estimate', 'yellow', 'প্রকৃত খরচ অনুমোদিত আনুমানিক খরচের চেয়ে বেশি', 'Actual cost is above the approved estimate', r2(num(d.actual_cost) - num(d.est_cost))));
    const em = sv(x, 'expense_max');
    if (d.pay === 'imprest' && num(d.actual_cost) > 0) { if (em === null) needs.push('expense_max'); else if (num(d.actual_cost) > em) flags.push(flag('imprest_over_limit', 'yellow', 'ইমপ্রেস্ট থেকে খরচ এককালীন সীমার উপরে', 'Imprest payment above the single-expense limit', num(d.actual_cost))); }
    if (num(d.actual_cost) > 0 && !d.receipt) flags.push(flag('no_receipt', 'yellow', 'রসিদ সংযুক্ত নেই', 'No receipt attached', num(d.actual_cost)));
    if (d.pay === 'owner') flags.push(flag('owner_personal', 'yellow', 'মালিকের ব্যক্তিগত টাকায় পেমেন্ট', "Paid from the owner's personal money", num(d.actual_cost) || undefined));
    if (has(d.approved_by) && (d.approved_by === d.reported_by || d.approved_by === d.requested_by)) flags.push(flag('approver_same', 'red', 'অনুমোদনকারী ও রিপোর্টকারী/অনুরোধকারী একই জন', 'Approver is the reporter / requester'));
    return { v, flags, needs };
  },
};

/* ============ 01-1 · Weekly review note ============ */
const SHOWROOMS = [L('ইসলামিয়া মিষ্টি ঘর — মেইন', 'ISLAMIYA MISTY GHAR — Main'), L('ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', 'ISLAMIYA MISTY GHAR — 2nd Branch'), L('মিষ্টি বাড়ি', 'MISTY BARI'), L('AL-CAKIZ', 'AL-CAKIZ'), L('অন্য', 'Other')];
B.forms['01-1'] = {
  title: L('সাপ্তাহিক রিভিউ নোট', 'Weekly review note'),
  head: [D('week_from', L('সপ্তাহ — থেকে', 'Week — from'), { req: true }), D('week_to', L('সপ্তাহ — পর্যন্ত', 'Week — to'), { req: true })],
  sections: [
    { title: L('A · সব শোরুম পাশাপাশি', 'A · All showrooms side by side'), fields: [
      NOTE(L('সব শোরুম পাশাপাশি রেখে দেখা হবে। প্রতিটি সিদ্ধান্তের পাশে নাম ও সময়সীমা থাকবে।', 'All showrooms are looked at side by side. Every decision has a name and a deadline.'), 'ok'),
      T('other_name', L('"অন্য" সারির শোরুমের নাম', 'Name of the showroom in the "Other" row')),
      TABLE('show', null, [M('sales', L('মোট বিক্রি ৳', 'Total sales ৳')), M('cash_so', L('ক্যাশ কম/বেশি — সপ্তাহের যোগ ৳ (কম হলে −)', 'Cash short/over — week total ৳ (minus if short)')),
        M('gm_gap', L('মালামাল বনাম টাকার পার্থক্য — সপ্তাহের যোগ ৳ (কম হলে −)', 'Goods vs money gap — week total ৳ (minus if short)')),
        N('days_cash', L('কত দিন কম — ক্যাশ', 'Days short — cash')), N('days_gm', L('কত দিন কম — মালামাল বনাম টাকা', 'Days short — goods vs money')),
        M('wastage', L('অপচয় (Wastage) ৳', 'Wastage ৳')), N('complaints', L('ফেরত ও অভিযোগ (সংখ্যা)', 'Returns & complaints (number)')), M('discount', L('ডিসকাউন্ট ৳', 'Discount ৳')),
        N('orders_taken', L('অর্ডার — নেওয়া', 'Orders — taken')), N('orders_given', L('অর্ডার — দেওয়া', 'Orders — delivered')), M('online', L('এর মধ্যে অনলাইন ৳', 'of which online ৳')),
        CK('outside_ok', L('বাইরের সোর্সিংয়ের বাকি — তাদের লেজারের সাথে মিল আছে', 'Outside-sourcing balance matches their ledger')),
        N('jal_diff', L('জিলাপি: পার্থক্য (কেজি)', 'Jalebi: difference (kg)')), N('jal_oil', L('জিলাপি: তেল প্রতি কেজি', 'Jalebi: oil per kg')), N('jal_juice', L('জিলাপি: রস প্রতি কেজি', 'Jalebi: syrup per kg'))], { rows: SHOWROOMS })] },
    { title: L('B · কারখানা ও হাব', 'B · Factory & hub'), fields: [
      T('f_other_name', L('"অন্য" সারির নাম', 'Name of the "Other" row')),
      TABLE('fac', null, [N('yield_diff', L('ফলনের পার্থক্য', 'Yield difference')), N('chhana_short', L('ছানার ঘাটতি', 'Chhana shortage')), M('supplier_due', L('সাপ্লায়ারের বকেয়া ৳', 'Supplier dues ৳')), M('receivable', L('প্রাপ্য ৳', 'Receivable ৳')), M('open_adv', L('খোলা অ্যাডভান্স ৳', 'Open advance ৳'))],
        { rows: [L('মিষ্টি কারখানা', 'Sweets factory'), L('কেক কারখানা', 'Cake factory'), L('অন্য', 'Other'), L('হাব', 'Hub')] }),
      M('owner_liab', L('হাব: মালিকের কাছে ব্যবসার দায় (Liability) ৳', 'Hub: business liability to the owner ৳')), M('outside_debt', L('হাব: বাইরের ঋণ ৳', 'Hub: outside debt ৳')),
      CK('split_seen', L('দেখা হয়েছে (সপ্তাহের সব ব্যয় ভাউচার)', 'Checked (all expense vouchers of the week)'), { req: true }),
      CH('split', L('সীমার নিচে ভাগ করা খরচ বা পেমেন্ট — সপ্তাহের সব ব্যয় ভাউচার দেখে: একই খাতে বা একই জনকে সীমার নিচে একাধিক?', 'Split expenses or payments below the limit — after checking all expense vouchers of the week: several below the limit on the same head or to the same person?'),
        [['no', L('না', 'No')], ['yes', L('হ্যাঁ', 'Yes')]], { req: true }),
      CK('split_in_decisions', L('হ্যাঁ হলে সিদ্ধান্তে যোগ করা হয়েছে', 'If yes, added to the decisions'), { show: (x) => x.d.split === 'yes', req: (x) => x.d.split === 'yes' })] },
    { title: L('C · অনলাইন ও মার্কেটিং', 'C · Online & marketing'), fields: [
      NOTE(L('মার্কেটিং ব্যয় রেজিস্টার ও অনলাইন ও ডেলিভারি লেজার থেকে লিখুন।', 'Copy from the marketing expense register and the online & delivery ledger.'), 'ok'),
      N('on_msgs', L('মেসেজ / খোঁজ', 'Messages / enquiries')), N('on_orders', L('অর্ডার', 'Orders')), M('on_sales', L('অনলাইন বিক্রি ৳', 'Online sales ৳')), M('on_ads', L('বিজ্ঞাপন-খরচ ৳', 'Advertising cost ৳')), M('on_cpo', L('প্রতি অর্ডারে খরচ ৳', 'Cost per order ৳')),
      N('on_complaints', L('ফেরত / অভিযোগ', 'Returns / complaints')), N('rev_good', L('রিভিউ: ভালো', 'Reviews: good')), N('rev_bad', L('রিভিউ: খারাপ', 'Reviews: bad')),
      CH('level', L('স্তর', 'Level'), [['0', '0'], ['1', '1'], ['2', '2'], ['3', '3'], ['4', '4']].map(([a, b]) => [a, L(b, b)])),
      CH('level_cond', L('পরের স্তরে যাওয়ার শর্ত পূরণ (লোকেশন সেটিংস শিট)', 'Condition for the next level met (location settings sheet)'), [['yes', L('হ্যাঁ', 'Yes')], ['no', L('না', 'No')]])] },
    { title: L('গত সপ্তাহের সিদ্ধান্ত', "Last week's decisions"), fields: [
      N('prev_total', L('মোট (টি)', 'Total')), N('prev_done', L('সম্পন্ন (টি)', 'Done')), N('prev_open', L('বাকি (টি)', 'Open')),
      T('prev_reason', L('বাকি থাকার কারণ', 'Why still open'), { show: (x) => num(x.d.prev_open) > 0, req: (x) => num(x.d.prev_open) > 0 })] },
    { title: L('D · এই সপ্তাহের সিদ্ধান্ত', "D · This week's decisions"), fields: [
      TABLE('dec', null, [T('what', L('সিদ্ধান্ত / করণীয়', 'Decision / action'), { wide: true }), ST('who', L('দায়িত্বধারী (Assigned to)', 'Assigned to'), { req: (x) => has(x.row.what) }),
        D('deadline', L('সময়সীমা', 'Deadline'), { req: (x) => has(x.row.what) }), CK('worklist', L('কাজের তালিকায় যোগ', 'Added to the work list'))], { min: 5 })] },
    { title: L('উপস্থিত ও স্বাক্ষর', 'Present & signatures'), fields: [ST('present1', L('উপস্থিত (Present) — ১', 'Present — 1')), ST('present2', L('উপস্থিত (Present) — ২', 'Present — 2')), ST('chair', L('সভাপতি (Chair)', 'Chair'))] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [];
    if (has(d.week_from) && has(d.week_to) && d.week_to < d.week_from) flags.push(flag('week_range', 'red', 'সপ্তাহের শেষ তারিখ শুরুর আগে', 'Week end is before its start'));
    if (d.split === 'yes') flags.push(flag('split_expenses', 'yellow', 'সীমার নিচে ভাগ করা খরচ ধরা পড়েছে', 'Split expenses below the limit found'));
    if (has(d.prev_total) && has(d.prev_done) && has(d.prev_open) && r2(num(d.prev_done) + num(d.prev_open)) !== r2(num(d.prev_total))) flags.push(flag('prev_mismatch', 'yellow', 'গত সপ্তাহের সিদ্ধান্ত: সম্পন্ন + বাকি ≠ মোট', "Last week's decisions: done + open ≠ total", r2(num(d.prev_done) + num(d.prev_open) - num(d.prev_total)), { unit: 'qty' }));
    return { v: {}, flags, needs };
  },
};

/* ============ 01-2 · Monthly P&L and KPI sheet ============ */
const XHEADS = [['staff_meal', L('স্টাফের খাবার / নাস্তা', 'Staff meals / snacks')], ['transport', L('যাতায়াত / পরিবহন', 'Transport')], ['hospitality', L('কাস্টমার আপ্যায়ন', 'Customer hospitality')],
  ['repair', L('মেরামত / ইউটিলিটি', 'Repairs / utilities')], ['labour', L('অস্থায়ী শ্রমিকের মজুরি', 'Temporary labour wages')], ['sourcing', L('বাইরের সোর্সিংয়ের মালামাল', 'Outside-sourced goods')], ['other', L('অন্যান্য', 'Other')]];
const KPIS = [
  L('বিক্রি — লোকেশন ও ব্র্যান্ড ধরে', 'Sales — by location and brand'), L('মোট লাভ % = মোট লাভ ÷ বিক্রি', 'Gross profit % = gross profit ÷ sales'), L('নিট লাভ % = নিট লাভ ÷ বিক্রি', 'Net profit % = net profit ÷ sales'),
  L('বেতন % = বেতন ÷ বিক্রি', 'Salary % = salary ÷ sales'), L('প্রতি কর্মীর বিক্রি = বিক্রি ÷ কর্মী-সংখ্যা', 'Sales per employee = sales ÷ headcount'), L('অপচয় (Wastage) % = অপচয় ÷ বিক্রি', 'Wastage % = wastage ÷ sales'),
  L('ডিসকাউন্ট % = ডিসকাউন্ট ÷ বিক্রি', 'Discount % = discount ÷ sales'), L('লিক ৳ = ক্যাশ কম + মালামাল বনাম টাকার অব্যাখ্যাত + স্টক কাউন্টের ঘাটতি', 'Leak ৳ = cash short + unexplained goods-vs-money + stock count shortfall'),
  L('মজুদের দিন = শেষের মজুদ ÷ (বিক্রি হওয়া মালামালের খরচ ÷ মাসের দিন)', 'Stock days = closing stock ÷ (cost of goods sold ÷ days in month)'), L('সাপ্লায়ার বকেয়ার দিন = বকেয়া ÷ (মাসের ক্রয় ÷ মাসের দিন)', 'Days payable = payables ÷ (purchases ÷ days in month)'),
  L('প্রাপ্য ও পাইকারির বাকি ৳', 'Receivables & wholesale credit ৳'), L('প্রধান ৫ কাঁচামালের দাম বদল', 'Price change of the top 5 raw materials'), L('নতুন পণ্যের বিক্রি', 'Sales of new products'),
  L('অনলাইন — অর্ডার · বিক্রি · প্রতি অর্ডারে খরচ', 'Online — orders · sales · cost per order'), L('জরুরি ক্রয়ের ভাগ % = জরুরি ক্রয় ÷ মোট ক্রয়', 'Emergency purchase share % = emergency purchases ÷ total purchases')];
const daysInMonth = (m) => { const mm = /^(\d{4})-(\d{1,2})$/.exec(String(m || '').trim()); if (!mm) return null; return new Date(Number(mm[1]), Number(mm[2]), 0).getDate(); };
B.forms['01-2'] = {
  title: L('মাসিক লাভ-ক্ষতি (P&L) ও KPI শিট', 'Monthly P&L and KPI sheet'),
  head: [T('month', L('মাস (বছর-মাস, যেমন 2026-10)', 'Month (year-month, e.g. 2026-10)'), { req: true }),
    CH('scope', L('পরিধি', 'Scope'), [['all', L('সব লোকেশন', 'All locations')], ['loc', L('একটি লোকেশন', 'One location')], ['other', L('অন্য', 'Other')]]), T('scope_name', L('লোকেশন / অন্য — নাম', 'Location / other — name'), { show: (x) => x.d.scope === 'loc' || x.d.scope === 'other' })],
  sections: [
    { title: L('A · লাভ-ক্ষতি (P&L)', 'A · Profit & loss (P&L)'), fields: [
      NOTE(L('এক পাতা, মাসে একটি। পাশের সংখ্যা এ মাসের কাগজ থেকে — মৌখিক নয়।', 'One page, one per month. The numbers come from this month’s papers, never from memory.'), 'warn'),
      M('sales', L('১ · মোট বিক্রি (শোরুমের মাসের যোগ + পার্টি ও পাইকারির বাকি)', '1 · Total sales (showroom month total + party & wholesale credit)'), { req: true }),
      M('open_stock', L('২ক · শুরুর মজুদ (স্টোর লেজার)', '2a · Opening stock (store ledger)'), { req: true }), M('purchases', L('২খ · মাসের ক্রয়', '2b · Purchases of the month'), { req: true }), M('close_stock', L('২গ · শেষের মজুদ', '2c · Closing stock'), { req: true }),
      CALC('cogs', L('২ · বিক্রি হওয়া মালামালের খরচ = শুরুর মজুদ + ক্রয় − শেষের মজুদ', '2 · Cost of goods sold = opening + purchases − closing'), 'money'),
      CALC('gross', L('৩ · মোট লাভ = ১ − ২', '3 · Gross profit = 1 − 2'), 'money', { big: true }),
      ...XHEADS.map(([id, l]) => M('x_' + id, L('৪ · খরচ — ' + l.bn, '4 · Expenses — ' + l.en))),
      CALC('expenses', L('৪ · খরচ (ব্যয় ভাউচারের যোগ)', '4 · Expenses (sum of expense vouchers)'), 'money'),
      M('salary', L('৫ · বেতন (মাসিক বেতন শিটের মোট)', '5 · Salary (month total of the salary sheet)'), { req: true }),
      M('bank_charges', L('৬ · ব্যাংক ও মোবাইলের চার্জ', '6 · Bank & mobile charges')),
      CALC('net', L('৭ · নিট লাভ = ৩ − ৪ − ৫ − ৬', '7 · Net profit = 3 − 4 − 5 − 6'), 'money', { big: true }),
      N('reinvest_pct', L('মালিকের ঠিক করা ভাগ (%) — পুনর্বিনিয়োগ', "Owner's chosen share (%) — reinvestment"), { req: true }),
      CALC('reinvest', L('৮ · পুনর্বিনিয়োগ ফান্ডে = নিট লাভ × ভাগ', '8 · To the reinvestment fund = net profit × share'), 'money')] },
    { title: L('KPI-এর উৎস সংখ্যা (কাগজ থেকে)', 'Source numbers for the KPIs (from the papers)'), fields: [
      TABLE('sales_by', L('বিক্রি — লোকেশন ও ব্র্যান্ড ধরে', 'Sales — by location and brand'), [T('name', L('লোকেশন · ব্র্যান্ড', 'Location · brand'), { wide: true }), M('amt', L('বিক্রি ৳', 'Sales ৳'))], { min: 2 }),
      N('headcount', L('কর্মী-সংখ্যা (মাসিক হাজিরা রেজিস্টার)', 'Headcount (monthly attendance register)')), M('wastage', L('অপচয় (Wastage) ৳', 'Wastage ৳')), M('discount', L('ডিসকাউন্ট ৳', 'Discount ৳')),
      M('cash_short', L('ক্যাশ কম ৳ (পজিটিভ সংখ্যা)', 'Cash short ৳ (positive number)')), M('gm_unexplained', L('মালামাল বনাম টাকার অব্যাখ্যাত ৳', 'Unexplained goods-vs-money ৳')), M('count_short', L('স্টক কাউন্টের ঘাটতি ৳', 'Stock count shortfall ৳')),
      M('payables', L('সাপ্লায়ারের বকেয়া ৳', 'Supplier payables ৳')), M('receivables', L('প্রাপ্য ও পাইকারির বাকি ৳', 'Receivables & wholesale credit ৳')),
      TABLE('raw', L('প্রধান ৫ কাঁচামালের দাম (স্টোর লেজার — মাসের শুরু বনাম শেষ)', 'Top 5 raw materials price (store ledger — start vs end of month)'), [T('name', L('কাঁচামাল', 'Raw material'), { wide: true }), M('p_start', L('মাসের শুরুর দাম', 'Price at start')), M('p_end', L('মাসের শেষের দাম', 'Price at end')), CALC('chg', L('বদল ৳', 'Change ৳'), 'text')], { min: 5, max: 5 }),
      M('new_prod', L('নতুন পণ্যের বিক্রি (নতুন প্রোডাক্ট সিদ্ধান্ত শিট)', 'Sales of new products (new product decision sheet)')),
      N('on_orders', L('অনলাইন — অর্ডার', 'Online — orders')), M('on_sales', L('অনলাইন — বিক্রি ৳', 'Online — sales ৳')), M('on_cpo', L('অনলাইন — প্রতি অর্ডারে খরচ ৳', 'Online — cost per order ৳')),
      M('emerg', L('জরুরি ক্রয় ৳', 'Emergency purchases ৳'))] },
    { title: L('B · ১৫টি KPI (কাজের মাপকাঠি)', 'B · The 15 KPIs'), fields: [
      CALC('days_text', L('মাসের দিন', 'Days in the month'), 'text'),
      TABLE('kpi', null, [CALC('cur', L('এ মাস', 'This month'), 'text'), T('prev', L('গত মাস', 'Last month')), T('ly', L('গত বছর এই মাস', 'Same month last year')),
        CH('dir', L('দিক', 'Direction'), [['good', L('ভালো', 'Good')], ['bad', L('খারাপ', 'Bad')]])], { rows: KPIS.map((k, i) => L((i + 1) + ' · ' + k.bn, (i + 1) + ' · ' + k.en)) }),
      CALC('leak', L('লিক ৳', 'Leak ৳'), 'money', { big: true })] },
    { title: L('C · সিদ্ধান্ত (Decisions)', 'C · Decisions'), fields: [
      TABLE('dec', null, [T('what', L('এ মাসের সিদ্ধান্ত', "This month's decision"), { wide: true }), ST('who', L('দায়িত্বধারী', 'Responsible'), { req: (x) => has(x.row.what) }), D('deadline', L('সময়সীমা', 'Deadline'), { req: (x) => has(x.row.what) })], { min: 3 })] },
    { title: L('হিসাব রিকনসিলিয়েশন ও স্বাক্ষর', 'Reconciliation & signatures'), fields: [
      CK('rec_sales', L('লাইন ১ = মাসের সব দৈনিক শোরুম শিটের যোগ', 'Line 1 = total of all daily showroom sheets of the month'), { req: true }),
      CK('rec_salary', L('লাইন ৫ = মাসিক বেতন শিট', 'Line 5 = monthly salary sheet'), { req: true }),
      CK('rec_leak', L('লিক ৳ শূন্য না হলে কারণ কাজের তালিকায়', 'If leak ৳ is not zero, the reason is in the work list'), { show: (x) => x.v.leak_nonzero, req: (x) => x.v.leak_nonzero }),
      ST('prepared_by', L('প্রস্তুতকারী (Prepared by) — ব্যবস্থাপনা', 'Prepared by — management'), { req: true }),
      ST('owner', L('মালিক', 'Owner'))] },
    { who: 'checker', title: L('যাচাই (অন্য কেউ, প্রস্তুতকারী নন)', 'Check (someone else, not the preparer)'), fields: [
      ST('checked_by', L('যাচাইকারী (Checked by) — অন্য কেউ, প্রস্তুতকারী নন', 'Checked by — someone else, not the preparer'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const sales = num(d.sales), cogs = r2(num(d.open_stock) + num(d.purchases) - num(d.close_stock)); v.cogs = cogs;
    const gross = r2(sales - cogs); v.gross = gross;
    const exp = r2(sum(XHEADS.map(([id]) => d['x_' + id]))); v.expenses = exp;
    const net = r2(gross - exp - num(d.salary) - num(d.bank_charges)); v.net = net;
    v.reinvest = r2(net * num(d.reinvest_pct) / 100);
    const dim = daysInMonth(d.month); v.days_text = dim === null ? L('মাস লিখুন (যেমন 2026-10)', 'Enter the month (e.g. 2026-10)') : String(dim);
    const leak = r2(num(d.cash_short) + num(d.gm_unexplained) + num(d.count_short)); v.leak = leak; v.leak_nonzero = leak !== 0;
    const pc = (a, b) => (b > 0 ? (a / b * 100).toFixed(1) + ' %' : '—');
    const stockDays = dim && cogs > 0 ? (num(d.close_stock) / (cogs / dim)).toFixed(1) : '—';
    const payDays = dim && num(d.purchases) > 0 ? (num(d.payables) / (num(d.purchases) / dim)).toFixed(1) : '—';
    const salesBy = r2(sum(x.rows('sales_by').map((r) => r.amt)));
    const cur = [has(d.sales) || salesBy ? money2(salesBy || sales) : '—', pc(gross, sales), pc(net, sales), pc(num(d.salary), sales), num(d.headcount) > 0 ? money2(sales / num(d.headcount)) : '—', pc(num(d.wastage), sales), pc(num(d.discount), sales),
      money2(leak), stockDays, payDays, money2(num(d.receivables)), '', money2(num(d.new_prod)),
      (num(d.on_orders) + ' · ' + money2(num(d.on_sales)) + ' · ' + money2(num(d.on_cpo))), pc(num(d.emerg), num(d.purchases))];
    cur[11] = x.rows('raw').some((r) => has(r.p_start) || has(r.p_end)) ? x.rows('raw').filter((r) => has(r.name)).map((r) => r.name + ' ' + (num(r.p_end) - num(r.p_start) >= 0 ? '+' : '') + fm(num(r.p_end) - num(r.p_start))).join(', ') || '—' : '—';
    const raw = x.rows('raw').map((r) => ({ chg: has(r.p_start) && has(r.p_end) ? (num(r.p_end) - num(r.p_start) >= 0 ? '+' : '') + fm(num(r.p_end) - num(r.p_start)) : '' }));
    if (has(x.c.checked_by) && has(d.prepared_by) && x.c.checked_by === d.prepared_by) flags.push(flag('checker_is_preparer', 'red', 'যাচাইকারী ও প্রস্তুতকারী একই জন', 'Checker and preparer are the same person', undefined, { src: 'check' }));
    if (leak !== 0) flags.push(flag('leak_nonzero', 'yellow', 'লিক ৳ শূন্য নয়', 'Leak ৳ is not zero', leak));
    if (has(d.month) && dim === null) flags.push(flag('month_format', 'red', 'মাসের ফরম্যাট ভুল — বছর-মাস লিখুন (যেমন 2026-10)', 'Month format is wrong — write year-month (e.g. 2026-10)'));
    if (net < 0 && num(d.reinvest_pct) > 0) flags.push(flag('reinvest_on_loss', 'yellow', 'নিট ক্ষতি — পুনর্বিনিয়োগের অঙ্ক ঋণাত্মক দেখাচ্ছে', 'Net is a loss — the reinvestment figure is negative', v.reinvest));
    if (has(d.sales) && net < 0) flags.push(flag('net_loss', 'yellow', 'এ মাসে নিট ক্ষতি', 'Net loss this month', net));
    if (cogs < 0 && has(d.close_stock)) flags.push(flag('cogs_negative', 'red', 'বিক্রি হওয়া মালামালের খরচ ঋণাত্মক — মজুদ/ক্রয় যাচাই করুন', 'Cost of goods sold is negative — check stock/purchases', cogs));
    if (salesBy > 0 && has(d.sales) && salesBy !== sales) flags.push(flag('sales_by_gap', 'yellow', 'লোকেশন-ব্র্যান্ড বিক্রির যোগ লাইন ১-এর সমান নয়', 'Sales by location/brand do not add up to line 1', r2(salesBy - sales)));
    return { v, rows: { kpi: cur.map((c) => ({ cur: c })), raw }, flags, needs };
  },
};
})();
