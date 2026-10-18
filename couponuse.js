/* Islamia BOS · Coupon and offer usage (#/couponuse, report #168).
   Reads supabase/phase460.sql mkt_coupon_usage. Validated coupon uses come from the coupon module (CRM-F) when it is installed - this page creates no coupon and no coupon table;
   codes typed on the bill (phase458 tags) are shown in a second block, labelled "typed, not validated". Built on rptkit.js. */
(() => {
'use strict';
const B = window.BOS, L = B.L, K = B.rptkit;
const c = (k, bn, en, fmt) => ({ k, label: L(bn, en, en), fmt });
const view = K.make({ id: 'cu', route: 'couponuse', title: L('কুপন ও অফারের ব্যবহার', 'Coupon and offer usage', 'Coupon ও offer usage'), tabs: [
  { k: 'use', label: L('কুপন ও অফারের ব্যবহার', 'Coupon and offer usage', 'Coupon ও offer usage'), rpc: 'mkt_coupon_usage', exportKey: 'mkt_coupons', dates: true, loc: true,
    info: { what: L('কোন কুপন বা অফার-কোড কতবার, কত ছাড়ে ব্যবহার হয়েছে।', 'Which coupon or offer code was used, how often and for how much discount.', 'Coupon / offer usage.'), why: L('যাচাই-করা ব্যবহার আর বিলে শুধু লেখা কোড আলাদা — একটি বিল দুবার গোনা হয় না।', 'Validated uses and codes merely typed on a bill are kept apart; a bill is never counted twice.', 'Validated and typed are kept apart.') },
    stats: [{ label: L('যাচাই-করা ব্যবহার', 'Validated uses', 'Validated uses'), path: 'totals.validated_uses', fmt: 'num' }, { label: L('লেখা কোডের বিল', 'Bills with a typed code', 'Typed-code bills'), path: 'totals.typed_bills', fmt: 'num' }],
    tables: [
      { title: L('যাচাই-করা কুপন (কুপন মডিউল)', 'Validated coupons (coupon module)', 'Validated coupons'), path: 'validated', empty: L('কোনো যাচাই-করা ব্যবহার নেই', 'No validated use', 'কোনো validated use নেই'),
        cols: [c('code', 'কোড', 'Code'), c('name', 'নাম', 'Name'), c('uses', 'ব্যবহার', 'Uses', 'num'), c('customers', 'গ্রাহক', 'Customers', 'num'), c('discount_given', 'ছাড়', 'Discount', 'money'), c('bill_total', 'বিলের মোট', 'Bill totals', 'money'), c('mismatches', 'ছাড় মেলেনি', 'Mismatches', 'num'), c('campaign_ref', 'ক্যাম্পেইন', 'Campaign'), c('first_use', 'প্রথম', 'First', 'date'), c('last_use', 'শেষ', 'Last', 'date')] },
      { title: L('বিলে লেখা কোড (যাচাই নয়)', 'Typed on the bill (not validated)', 'Typed codes'), path: 'typed', empty: L('বিলে লেখা কোড নেই', 'No typed code', 'No typed code'),
        cols: [c('offer_code', 'কোড', 'Code'), c('bills', 'বিল', 'Bills', 'num'), c('discount_given', 'ছাড়', 'Discount', 'money'), c('net', 'নিট', 'Net', 'money'), c('campaign_code', 'ক্যাম্পেইন', 'Campaign')] }] },
] });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { couponuse: view });
})();
