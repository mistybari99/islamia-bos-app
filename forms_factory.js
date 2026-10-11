/* Islamia BOS · factory forms 05-1 to 05-5, taken field by field from the BOS Build Kit v1.39.
   Recipes, quantities, yields and standard weights are the owner's data: they are entry fields only, nothing is pre-filled.
   Every limit comes from Location Settings; a missing setting is reported as "data needed". */
(() => {
'use strict';
const B = window.BOS, L = B.L, YN = B.YN, num = B.num, has = B.has, sum = B.sum;
const { T, TA, N, M, TM, D, CK, ST, ITEM, LOC, DEN, CH, SEL, CALC, NOTE, TABLE, PHOTO } = B.f;
B.forms = B.forms || {};

const flag = (code, level, bn, en, amount, o = {}) => ({ code, level, text: L(bn, en), amount, ...o });
const NEED = L('তথ্য লাগবে', 'Data needed');
const fm = (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const sv = (x, k) => (x.s[k] === undefined || x.s[k] === null || x.s[k] === '' ? null : x.s[k]);
const addSetting = (def) => { if (!B.SETTING_DEFS.some((d) => d.key === def.key)) B.SETTING_DEFS.push(def); };
addSetting({ key: 'scale_test', group: 'C', label: L('পাল্লা যাচাইয়ের জানা ওজনের বস্তু ও সীমা', 'Scale check: known-weight object and limit'), kind: 'text', unit: '' });
addSetting({ key: 'newprod_review_days', group: 'C', label: L('নতুন প্রোডাক্ট চালুর কত দিন পর পর্যালোচনা', 'Days after launch to review a new product'), kind: 'number', unit: 'দিন' });

/* ============ 05-1 · Factory daily sheet ============ */
const FR = [1, 2];
const fridgeRows = FR.map((i) => L('ফ্রিজ / চিলার ' + i, 'Fridge / chiller ' + i));
const fridgeCalc = (x, tid, flagPrefix, flags, needs) => {
  const rs = x.rows(tid);
  return FR.map((i, k) => {
    const r = rs[k] || {}, min = sv(x, 'fridge' + i + '_min'), max = sv(x, 'fridge' + i + '_max'), name = x.s['fridge' + i + '_name'];
    let ok = NEED;
    if (has(r.temp)) {
      if (min === null || max === null) needs.push('fridge' + i + '_min', 'fridge' + i + '_max');
      else { const tt = num(r.temp), good = tt >= min && tt <= max; ok = good ? L('সীমার মধ্যে ✓', 'In range ✓') : L('সীমার বাইরে', 'Out of range');
        if (!good) flags.push(flag(flagPrefix + i, 'red', 'ফ্রিজ / চিলার ' + i + ' এর তাপমাত্রা সীমার বাইরে', 'Fridge / chiller ' + i + ' temperature out of range', tt, { unit: 'qty' })); }
    }
    return { name: name || L('ফ্রিজ / চিলার ' + i, 'Fridge / chiller ' + i), temp_ok: ok };
  });
};
const tempCols = (n) => [CALC('name', L('ইউনিট', 'Unit'), 'text'), N('temp', n === 1 ? L('প্রথম পাঠ — তাপমাত্রা °C', 'First reading: temperature °C') : L('দ্বিতীয় পাঠ — তাপমাত্রা °C', 'Second reading: temperature °C'), { req: true }), CALC('temp_ok', L('নির্ধারিত সীমায়?', 'Within the set range?'), 'text')];

B.forms['05-1'] = {
  title: L('কারখানা দৈনিক শিট', 'Factory daily sheet'),
  head: [CH('shift', L('শিফট', 'Shift'), [['m', L('সকাল', 'Morning')], ['a', L('বিকাল', 'Afternoon')], ['n', L('রাত', 'Night')]], { req: true }),
    ST('in_charge', L('দায়িত্বে (নাম)', 'In charge (name)'), { req: true }), T('handover_line', L('শিফট হ্যান্ডওভার রেজিস্টারের লাইন নং', 'Shift handover register line no.'))],
  sections: [
    { title: L('Section A · শিফট শুরুর আগে (Before Shift)', 'Section A · Before shift'), fields: [
      CH('safety', L('গ্যাস, বিদ্যুৎ ও আগুনের নিরাপত্তা চেক (Safety Check)', 'Gas, power and fire safety check'), [['ok', L('নিরাপদ', 'Safe')], ['defect', L('ত্রুটি', 'Defect')]], { req: true }),
      T('safety_defect', L('ত্রুটির বিবরণ', 'Defect details'), { show: (x) => x.d.safety === 'defect', req: (x) => x.d.safety === 'defect' }),
      TABLE('machines', L('যন্ত্রপাতি চেক (মিক্সার · চুলা · ওভেন · ফ্রিজ)', 'Equipment check (mixer · stove · oven · fridge)'),
        [T('name', L('যন্ত্র', 'Equipment'), { req: true, wide: true }), CH('state', L('অবস্থা', 'State'), [['ok', L('ঠিক', 'OK')], ['defect', L('ত্রুটি', 'Defect')]], { req: true })], { min: 3 }),
      CK('machines_done', L('যন্ত্রপাতি চেক সম্পন্ন', 'Equipment check done')),
      CALC('scale_info', L('পাল্লা যাচাইয়ের বস্তু ও সীমা (লোকেশন সেটিংস থেকে)', 'Scale check object and limit (from settings)'), 'text'),
      CH('scale', L('পাল্লা — জানা ওজনের বস্তু দিয়ে চেক', 'Scale: checked with a known-weight object'), [['ok', L('ঠিক', 'OK')], ['off', L('গরমিল', 'Off')]], { req: true }),
      NOTE(L('গরমিল হলে পাল্লা ব্যবহার বন্ধ, আর কাজের তালিকায় যোগ করতে হবে।', 'If the scale is off, stop using it and add it to the work list.'), 'warn', { show: (x) => x.d.scale === 'off' }),
      CK('scale_listed', L('কাজের তালিকায় যোগ করা হয়েছে', 'Added to the work list'), { show: (x) => x.d.scale === 'off', req: (x) => x.d.scale === 'off' }),
      TABLE('fridges', L('ফ্রিজ / চিলারের তাপমাত্রা (Temperature)', 'Fridge / chiller temperature'), tempCols(1), { rows: fridgeRows }),
      CK('pots_done', L('পাত্র ও মালশা — ধোয়া, উল্টে শুকানো, ফাটল চেক সম্পন্ন', 'Pots and trays: washed, dried upside down, checked for cracks'), { req: true }),
      ST('pots_by', L('সম্পাদনকারী (Performed by)', 'Performed by'), { req: true }), ST('pots_verify', L('যাচাইকারী', 'Checked by'), { req: true }),
      CK('hygiene_done', L('কর্মীর ব্যক্তিগত পরিষ্কার ও পোশাক (Hygiene) সম্পন্ন', 'Staff personal hygiene and uniform done')), ST('hygiene_verify', L('যাচাইকারী', 'Checked by')),
      T('issue_slip', L('কাঁচামাল ইস্যু — মালামাল ইস্যু স্লিপ নং', 'Raw material issued: material issue slip no.'), { req: true })] },
    { title: L('Section B · শিফট চলাকালীন (During Shift)', 'Section B · During shift'), fields: [
      NOTE(L('প্রতি ব্যাচের পর কর্মক্ষেত্র পরিষ্কার করতে হবে।', 'Clean the work area after every batch.'), 'ok'),
      CK('batch1', L('ব্যাচ 1 পরিষ্কার', 'Batch 1 cleaned')), CK('batch2', L('ব্যাচ 2 পরিষ্কার', 'Batch 2 cleaned')), CK('batch3', L('ব্যাচ 3 পরিষ্কার', 'Batch 3 cleaned')), ST('batch_verify', L('যাচাইকারী', 'Checked by')),
      TM('t2_time', L('তাপমাত্রা — দ্বিতীয় পাঠের সময়', 'Temperature, second reading: time'), { req: true }),
      TABLE('fridges2', L('তাপমাত্রা (Temperature) — দ্বিতীয় পাঠ', 'Temperature, second reading'), tempCols(2), { rows: fridgeRows }),
      CH('unplanned', L('পরিকল্পনার বাইরে উৎপাদন (Unplanned Production)', 'Unplanned production'), [['no', L('না', 'No')], ['yes', L('হ্যাঁ', 'Yes')]], { req: true }),
      T('unplanned_what', L('কী ও কেন', 'What and why'), { show: (x) => x.d.unplanned === 'yes', req: (x) => x.d.unplanned === 'yes' }),
      CH('breakdown', L('যন্ত্র বিকল (Breakdown)', 'Equipment breakdown'), [['no', L('না', 'No')], ['yes', L('হ্যাঁ', 'Yes')]], { req: true }),
      T('bd_machine', L('কোন যন্ত্র', 'Which equipment'), { show: (x) => x.d.breakdown === 'yes', req: (x) => x.d.breakdown === 'yes' }),
      TM('bd_time', L('সময়', 'Time'), { show: (x) => x.d.breakdown === 'yes' }),
      T('bd_request', L('মেইনটেন্যান্স অনুরোধ ও রেকর্ড নং', 'Maintenance request & record no.'), { show: (x) => x.d.breakdown === 'yes', req: (x) => x.d.breakdown === 'yes' }),
      CH('bd_product', L('বিকল অবস্থায় রাখা পণ্যের অবস্থা যাচাই', 'Condition of product held during the breakdown checked'), [['na', L('প্রযোজ্য নয়', 'Not applicable')], ['checked', L('যাচাই করা হয়েছে', 'Checked')]], { req: true }),
      T('bd_result', L('ফল', 'Result'), { show: (x) => x.d.bd_product === 'checked', req: (x) => x.d.bd_product === 'checked' })] },
    { title: L('Section C · শিফট শেষে (End of Shift)', 'Section C · End of shift'), fields: [
      N('batches', L('ব্যাচ সংখ্যা', 'Number of batches'), { req: true }),
      CK('yield_report', L('উৎপাদন রিপোর্ট পূরণ ও ফলন (Yield) হিসাব সম্পন্ন', 'Production report filled and yield worked out'), { req: true }),
      NOTE(L('ফলনের পার্থক্য অনুমোদন করবেন উৎপাদনকারী নন, অন্য কেউ।', 'The yield difference is approved by someone other than the producer.'), 'warn'),
      ST('yield_approver', L('ফলনের পার্থক্য অনুমোদনকারী (Approved by)', 'Yield difference approved by'), { req: true }),
      CH('raw_return', L('অব্যবহৃত কাঁচামাল গোডাউনে ফেরত', 'Unused raw material returned to the godown'), [['done', L('সম্পন্ন', 'Done')], ['na', L('প্রযোজ্য নয়', 'Not applicable')]], { req: true }),
      ST('raw_return_by', L('ফেরত গ্রহণকারী (Return received by)', 'Return received by'), { show: (x) => x.d.raw_return === 'done', req: (x) => x.d.raw_return === 'done' }),
      T('challan_from', L('সব চালান লেখা ও পাঠানো — চালান নং (থেকে)', 'All challans written and sent: challan no. (from)'), { req: true }), T('challan_to', L('চালান নং (পর্যন্ত)', 'Challan no. (to)'), { req: true }),
      CK('clean_done', L('পরিষ্কার ও বর্জ্য সরানো সম্পন্ন', 'Cleaning and waste removal done')), ST('clean_by', L('সম্পাদনকারী (Performed by)', 'Performed by')), ST('clean_verify', L('যাচাইকারী', 'Checked by')),
      N('end_temp', L('ফ্রিজ / চিলার চালু, বাকি যন্ত্র বন্ধ — শেষ তাপমাত্রা °C', 'Fridge / chiller on, other machines off: closing temperature °C'), { req: true }),
      CK('machines_off', L('ফ্রিজ / চিলার চালু, বাকি যন্ত্র বন্ধ — সম্পন্ন', 'Fridge / chiller on, other machines off: done'), { req: true }),
      CK('gas_off', L('গ্যাস বন্ধ / নিরাপদ', 'Gas off / safe'), { req: true }), CK('power_off', L('বিদ্যুৎ বন্ধ / নিরাপদ', 'Power off / safe'), { req: true }), CK('fire_safe', L('আগুন — নিরাপদ', 'Fire: safe'), { req: true }),
      TM('shutter_time', L('শাটার বন্ধের সময়', 'Shutter closed at'), { req: true }), ST('key_to', L('চাবি গ্রহণকারী (Key received by)', 'Key received by'), { req: true })] },
    { title: L('Section D · গরমিল ও ঘটনা (Exceptions)', 'Section D · Exceptions & incidents'), fields: [
      NOTE(L('কোনো ঘটনা না থাকলে নিচের ঘরে টিক দিন।', 'If nothing happened, tick the box below.'), 'ok'),
      TABLE('incidents', null, [T('what', L('আজকের ঘটনা (Incident)', "Today's incident"), { wide: true }), T('cause', L('কারণ (Cause)', 'Cause')), T('owner', L('ইনচার্জ (In charge)', 'In charge')),
        T('action', L('গৃহীত ব্যবস্থা (Action Taken)', 'Action taken'), { wide: true }), CK('solved', L('সমাধান (Resolved)', 'Resolved'))], { min: 3 }),
      CK('no_incident', L('কোনো ঘটনা নেই', 'Nothing happened'))] },
    { who: 'checker', title: L('যাচাই ও স্বাক্ষর', 'Checks & signatures'), fields: [
      ST('factory_incharge', L('কারখানা ইনচার্জ (Factory In charge)', 'Factory in charge'), { who: 'checker', req: true }),
      ST('mgmt_checker', L('যাচাইকারী (Checked by) — ব্যবস্থাপনা', 'Checked by: management'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, flags = [], needs = [], v = {};
    const st = sv(x, 'scale_test'); v.scale_info = st === null ? NEED : st; if (st === null) needs.push('scale_test');
    const f1 = fridgeCalc(x, 'fridges', 'temp_out_', flags, needs), f2 = fridgeCalc(x, 'fridges2', 'temp2_out_', flags, needs);
    if (d.safety === 'defect') flags.push(flag('safety_defect', 'yellow', 'গ্যাস/বিদ্যুৎ/আগুনের নিরাপত্তায় ত্রুটি', 'Gas / power / fire safety defect'));
    if (!x.rows('machines').some((r) => has(r.name))) flags.push(flag('machines_not_recorded', 'yellow', 'যন্ত্রপাতি চেকে কোনো যন্ত্র লেখা হয়নি', 'No equipment recorded in the equipment check'));
    const mdef = x.rows('machines').filter((r) => r.state === 'defect').length;
    if (mdef) flags.push(flag('machine_defect', 'yellow', 'যন্ত্রপাতিতে ত্রুটি', 'Equipment defect', mdef, { unit: 'qty' }));
    if (d.scale === 'off') flags.push(flag('scale_off', 'yellow', 'পাল্লায় গরমিল — ব্যবহার বন্ধ', 'Scale is off: stop using it'));
    if (d.unplanned === 'yes') flags.push(flag('unplanned_production', 'yellow', 'পরিকল্পনার বাইরে উৎপাদন', 'Unplanned production'));
    if (d.breakdown === 'yes') flags.push(flag('breakdown', 'yellow', 'যন্ত্র বিকল', 'Equipment breakdown'));
    if (has(d.yield_approver) && d.yield_approver === d.in_charge) flags.push(flag('self_yield_approval', 'red', 'ফলনের পার্থক্য উৎপাদনকারী নিজে অনুমোদন করেছেন', 'Yield difference approved by the producer'));
    if ([['pots_by', 'pots_verify'], ['clean_by', 'clean_verify']].some(([a, b]) => has(d[a]) && d[a] === d[b])) flags.push(flag('same_person_check', 'yellow', 'সম্পাদনকারী ও যাচাইকারী একই জন', 'Doer and checker are the same person'));
    const open = x.rows('incidents').filter((r) => has(r.what) && !r.solved).length;
    if (open) flags.push(flag('incident_open', 'yellow', 'অমীমাংসিত ঘটনা আছে', 'Unresolved incident', open, { unit: 'qty' }));
    return { v, rows: { fridges: f1, fridges2: f2 }, flags, needs: [...new Set(needs)] };
  },
};

/* ============ 05-2 · Product spec card ============ */
const WD_NAMES = [L('রবি', 'Sun'), L('সোম', 'Mon'), L('মঙ্গল', 'Tue'), L('বুধ', 'Wed'), L('বৃহঃ', 'Thu'), L('শুক্র', 'Fri'), L('শনি', 'Sat')];
const SHELF_KEY = { sweet: 'shelf_sweet', cake: 'shelf_cake', bakery: 'shelf_bakery' };
const HD = [['hour', L('ঘণ্টা', 'hours')], ['day', L('দিন', 'days')]];
B.forms['05-2'] = {
  title: L('প্রোডাক্ট স্পেক কার্ড', 'Product spec card'),
  head: [ITEM('item', L('আইটেম কোড ও পণ্যের নাম', 'Item code & product name'), { req: true }), D('card_date', L('কার্ড তৈরির তারিখ', 'Card date'), { req: true }), T('version', L('সংস্করণ (Version) নং', 'Version no.'), { req: true }),
    CH('cat', L('ধরন', 'Category'), [['sweet', L('মিষ্টি', 'Sweets')], ['cake', L('কেক', 'Cake')], ['bakery', L('বেকারি', 'Bakery')], ['other', L('অন্য', 'Other')]]),
    T('cat_other', L('অন্য (লিখুন)', 'Other (write it)'), { show: (x) => x.d.cat === 'other' })],
  sections: [
    { title: L('১ম গ্রেড — সঠিক পণ্য ●', '1st grade: the correct product ●'), fields: [
      PHOTO('photo_g1', L('১ম গ্রেডের ছবি', '1st grade photo'), { req: true }),
      NOTE(L('১ম গ্রেড — এর সবগুলো মিলতে হবে। কারিগরের নিজের ভাষায় লিখুন।', '1st grade: all of these must match. Write in the craftsman\'s own words.'), 'ok'),
      T('g1_look', L('চেহারা ও রং', 'Appearance and colour'), { req: true }), T('g1_size', L('আকার / মাপ', 'Size'), { req: true }),
      N('g1_weight', L('ওজন প্রতি পিস (গ্রাম)', 'Weight per piece (grams)'), { req: true }), N('g1_pcs_kg', L('প্রতি কেজিতে পিস', 'Pieces per kg'), { req: true }),
      CALC('pcs_calc', L('ওজন থেকে হিসাব: প্রতি কেজিতে পিস (দেখার জন্য)', 'Worked out from the weight: pieces per kg (for reference)'), 'num', { show: (x) => num(x.d.g1_weight) > 0 }),
      T('g1_texture', L('গঠন (নরম / শক্ত / রসালো)', 'Texture (soft / firm / juicy)')), T('g1_syrup', L('রস / সিরা / আবরণ', 'Syrup / coating')), T('g1_broken', L('ভাঙা / ফাটা', 'Broken / cracked')),
      T('g1_taste', L('স্বাদ', 'Taste'), { req: true }), T('g1_smell', L('গন্ধ', 'Smell'), { req: true })] },
    { title: L('২য় গ্রেড (বাতিল নয়)', '2nd grade (not rejected)'), fields: [
      PHOTO('photo_g2', L('২য় গ্রেডের ছবি', '2nd grade photo'), { req: true }),
      NOTE(L('এর একটিও হলে ২য় গ্রেড (বাতিল নয়)।', 'If any one of these applies, it is 2nd grade (not rejected).'), 'ok'),
      CK('g2_color', L('রং বদলে গেছে', 'Colour changed')), CK('g2_cracked', L('ফেটে গেছে / ভেঙেছে', 'Cracked / broken')), CK('g2_uneven', L('আকার অসমান', 'Uneven size')),
      CK('g2_dry', L('রস শুকিয়ে গেছে', 'Syrup dried up')), CK('g2_flat', L('চাপা পড়ে চ্যাপ্টা', 'Pressed flat')),
      T('g2_more1', L('এই পণ্যে আরও — ১', 'More for this product: 1')), T('g2_more2', L('এই পণ্যে আরও — ২', 'More for this product: 2'))] },
    { title: L('বাতিল — বিক্রি নয় ●', 'Rejected: not for sale ●'), fields: [
      PHOTO('photo_rej', L('বাতিল মালামালের ছবি', 'Rejected goods photo'), { req: true }),
      NOTE(L('এর একটিও হলে বিক্রি নয়।', 'If any one of these applies, it must not be sold.'), 'warn'),
      CK('rj_sour', L('টক গন্ধ', 'Sour smell')), CK('rj_mold', L('ছাতা / আঠালো', 'Mould / sticky')), CK('rj_raw', L('ভেতরে কাঁচা', 'Raw inside')), CK('rj_foreign', L('বাইরের কিছু মিশেছে', 'Foreign matter mixed in')), CK('rj_expired', L('মেয়াদ শেষ', 'Expired')),
      T('rj_more1', L('এই পণ্যে আরও — ১', 'More for this product: 1')), T('rj_more2', L('এই পণ্যে আরও — ২', 'More for this product: 2'))] },
    { title: L('বিক্রয়যোগ্য সময়সীমা ও সংরক্ষণ', 'Shelf life & storage'), fields: [
      N('shelf_normal', L('বিক্রয়যোগ্য সময়সীমা — সাধারণ তাপে', 'Shelf life at normal temperature'), { req: true }), CH('shelf_normal_u', L('একক', 'Unit'), HD, { req: true }),
      N('shelf_cold', L('বিক্রয়যোগ্য সময়সীমা — ফ্রিজে বা চিলারে', 'Shelf life in fridge or chiller')), CH('shelf_cold_u', L('একক', 'Unit'), HD),
      CALC('shelf_ref', L('লোকেশন সেটিংসে এই ধরনের বিক্রয়যোগ্য দিন (দেখার জন্য)', 'Shelf days in location settings for this category (for reference)'), 'text', { show: (x) => !!SHELF_KEY[x.d.cat] }),
      SEL('storage', L('সংরক্ষণের নিয়ম', 'Storage rule'), [['fridge', L('ফ্রিজে', 'Fridge')], ['chiller', L('চিলারে', 'Chiller')], ['normal', L('সাধারণ', 'Normal')], ['other', L('অন্য', 'Other')]]),
      T('storage_other', L('অন্য (লিখুন)', 'Other (write it)'), { show: (x) => x.d.storage === 'other' }),
      N('store_temp', L('রাখার তাপমাত্রা °C', 'Storage temperature °C')), CK('covered', L('ঢেকে রাখা', 'Keep covered')), CK('separate', L('আলাদা রাখা', 'Keep separate')),
      CK('daytag', L('তৈরির দিনের রং লাগবে', 'Make-day colour tag needed')),
      CALC('daytag_list', L('দিন-ট্যাগের রং (লোকেশন সেটিংস থেকে)', 'Day-tag colours (from settings)'), 'text', { show: (x) => !!x.d.daytag })] },
    { title: L('নোট', 'Note'), fields: [
      NOTE(L('এই কার্ড ছাড়া গ্রেড দেওয়া বা অভিযোগের বিচার করা যাবে না। কার্ডের ভাষা কারিগরের নিজের ভাষায় লেখা হবে। মান বদলালে নতুন সংস্করণ (Version) নম্বরে নতুন কার্ড; পুরোনো কার্ড কারখানার ফাইলে থাকবে।',
        'Without this card no grade can be given and no complaint can be judged. Write the card in the craftsman\'s own words. If the standard changes, make a new card with a new Version no.; the old card stays in the factory file.'), 'warn'),
      NOTE(L('দাম এই কার্ডে নয় — দাম মূল্য তালিকায়।', 'No price on this card; prices live in the price list.'), 'ok'),
      ST('craft_incharge', L('কারিগর ইনচার্জ', 'Craftsman in charge'), { req: true }), ST('factory_incharge', L('কারখানা ইনচার্জ', 'Factory in charge'), { req: true })] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      ST('approver', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by: management'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, v = {}, flags = [];
    v.pcs_calc = num(d.g1_weight) > 0 ? Math.round(1000 / num(d.g1_weight) * 100) / 100 : undefined;
    const key = SHELF_KEY[d.cat]; if (key) { const s = sv(x, key); v.shelf_ref = s === null ? NEED : L(fm(s) + ' দিন', fm(s) + ' days'); }
    v.daytag_list = WD_NAMES.map((n, i) => { const t = x.s['daytag_' + i]; return (x.lab ? x.lab(n) : '') + ': ' + (t || '—'); }).join(' · ');
    if (has(d.craft_incharge) && d.craft_incharge === d.factory_incharge) flags.push(flag('same_incharge', 'yellow', 'কারিগর ইনচার্জ ও কারখানা ইনচার্জ একই জন', 'Craftsman in charge and factory in charge are the same person'));
    return { v, flags, needs: [] };
  },
};

/* ============ 05-3 · Recipe card ============ */
const FAMILIES = [['chana', L('ছানার মিষ্টি', 'Chhana sweets')], ['fried', L('ভাজা মিষ্টি ও জিলাপি', 'Fried sweets & jalebi')], ['doi', L('দই ও দুগ্ধ', 'Curd & dairy')], ['khoa', L('খোয়া / মাওয়া', 'Khoa / mawa')], ['cake', L('কেক ও বেকারি', 'Cake & bakery')], ['other', L('অন্য', 'Other')]];
const RUNITS = [['kg', L('কেজি', 'kg')], ['l', L('লিটার', 'litre')], ['pc', L('পিস', 'pc')], ['lb', L('পাউন্ড', 'lb')], ['g', L('গ্রাম', 'gram')]];
const ingCols = () => [ITEM('item', L('কাঁচামালের নাম ও আইটেম কোড', 'Raw material name & item code'), { wide: true, req: (x) => !has(x.row.name) }),
  T('name', L('নাম (তালিকায় না থাকলে)', 'Name (if not in the list)'), { req: (x) => !has(x.row.item) }), N('qty', L('পরিমাণ', 'Quantity'), { req: true }), SEL('unit', L('একক', 'Unit'), RUNITS, { req: true })];
B.forms['05-3'] = {
  title: L('রেসিপি কার্ড', 'Recipe card'),
  head: [ITEM('item', L('আইটেম কোড ও পণ্যের নাম', 'Item code & product name'), { req: true }), D('card_date', L('তারিখ', 'Date'), { req: true }), T('version', L('সংস্করণ (Version) নং', 'Version no.'), { req: true })],
  sections: [
    { title: L('পরিবার ও ব্যাচ', 'Family & batch'), fields: [
      NOTE(L('কারিগর বলবেন, ব্যবস্থাপনার একজন লিখবেন — পণ্য বানানোর সময় পাশে দাঁড়িয়ে। প্রতিটি পরিমাণ মেপে লিখতে হবে, অনুমানে নয়। অনুমোদনের আগে এই রেসিপি দিয়ে খরচের হিসাব হবে না। রেসিপি বদলালে নতুন সংস্করণ (Version) নম্বরে নতুন কার্ড; পুরোনো কার্ড ফাইলে থাকবে।',
        'The craftsman tells, one person from management writes, standing beside while the product is made. Every quantity must be measured, not guessed. No costing is done with this recipe before it is approved. If the recipe changes, make a new card with a new Version no.; the old card stays on file.'), 'warn'),
      SEL('family', L('পরিবার', 'Family'), FAMILIES), T('family_other', L('অন্য (লিখুন)', 'Other (write it)'), { show: (x) => x.d.family === 'other' }),
      N('batch_qty', L('এক ব্যাচে তৈরি হয়', 'Made in one batch'), { req: true }), SEL('batch_unit', L('একক', 'Unit'), [...RUNITS, ['other', L('অন্য', 'Other')]], { req: true }),
      T('batch_unit_other', L('অন্য একক (লিখুন)', 'Other unit (write it)'), { show: (x) => x.d.batch_unit === 'other' })] },
    { title: L('Section A · ধাপ (Step) 1 — বেস তৈরি (ছানা / খোয়া / খামির / ব্যাটার / দুধ জ্বাল)', 'Section A · Step 1: making the base (chhana / khoa / dough / batter / boiled milk)'), fields: [
      TABLE('a', null, ingCols(), { min: 4 }),
      N('base_qty', L('ধাপ (Step) 1 থেকে প্রাপ্ত বেস', 'Base obtained from Step 1'), { req: true }), CH('base_unit', L('একক', 'Unit'), [['kg', L('কেজি', 'kg')], ['l', L('লিটার', 'litre')]], { req: true })] },
    { title: L('Section B · ধাপ (Step) 2 — পণ্য তৈরি', 'Section B · Step 2: making the product'), fields: [TABLE('b', null, ingCols(), { min: 5 })] },
    { title: L('Section C · প্যাকেজিং — পণ্যের উপকরণের সাথে নয়, আলাদা', 'Section C · Packaging: kept apart from the product ingredients'), fields: [TABLE('c', null, ingCols(), { min: 2 })] },
    { title: L('Section D · বানানোর ধাপ (Step)', 'Section D · Method steps'), fields: [
      TABLE('steps', null, [TA('text', L('বানানোর ধাপ (Step) — কারিগরের বর্ণনা, সময় ও মাপসহ', "Method step: in the craftsman's words, with time and measure"), { wide: true })], { min: 6 })] },
    { title: L('সময়, জনবল ও যন্ত্র', 'Time, people & equipment'), fields: [
      N('cook_min', L('জ্বাল / বেক — সময় (মিনিট)', 'Cooking / baking time (minutes)')), T('cook_heat', L('জ্বাল / বেক — তাপ', 'Cooking / baking heat')),
      N('rest_min', L('বিশ্রাম (মিনিট)', 'Resting time (minutes)')), N('total_min', L('মোট সময় (মিনিট)', 'Total time (minutes)')),
      N('headcount', L('প্রয়োজনীয় কর্মী সংখ্যা (Headcount)', 'Staff needed (headcount)')), T('machines', L('যন্ত্র', 'Equipment'))] },
    { title: L('সংযোগ ও স্বাক্ষর', 'Links & signatures'), fields: [
      T('yield_no', L('ফলন টেস্ট শিট নং', 'Yield test sheet no.')), T('spec_version', L('প্রোডাক্ট স্পেক কার্ডের সংস্করণ (Version)', 'Product spec card version')),
      T('informant', L('তথ্যদাতা (Information given by) — কারিগরের নাম / পদ', 'Information given by: craftsman name / post'), { req: true })] },
    { who: 'checker', title: L('অনুমোদন (ব্যবস্থাপনা)', 'Approval (management)'), fields: [
      ST('approver', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by: management'), { who: 'checker', req: true })] },
  ],
  calc(x) { return { v: {}, flags: [], needs: [] }; },
};

/* ============ 05-4 · Yield test sheet ============ */
const BATCH_ROWS = [1, 2, 3].map((i) => L('ব্যাচ ' + i, 'Batch ' + i));
const pct = (a, b) => (num(b) > 0 && has(a) ? Math.round(num(a) / num(b) * 10000) / 100 : undefined);
const div = (a, b) => (num(b) > 0 && has(a) ? Math.round(num(a) / num(b) * 10000) / 10000 : undefined);
const AVG_KEYS = [['input', L('গড় — মূল উপকরণ', 'Average: main input'), 'num'], ['base', L('গড় — প্রাপ্ত বেস', 'Average: base obtained'), 'num'], ['base_pct', L('গড় — বেস রূপান্তর %', 'Average: base conversion %'), 'num'],
  ['base_use', L('গড় — বেস ব্যবহার', 'Average: base used'), 'num'], ['sugar', L('গড় — চিনি / সিরা / অন্য', 'Average: sugar / syrup / other'), 'num'], ['mid', L('গড় — মাঝের ওজন', 'Average: mid weight'), 'num'],
  ['good', L('গড় — ভালো পণ্য', 'Average: good product'), 'num'], ['second', L('গড় — ২য় গ্রেড', 'Average: 2nd grade'), 'num'], ['waste', L('গড় — নষ্ট', 'Average: wastage'), 'num'], ['total', L('গড় — মোট উৎপাদন', 'Average: total output'), 'num'],
  ['per_unit', L('গড় — মূল উপকরণের প্রতি ১ একক থেকে ভালো পণ্য', 'Average: good product per 1 unit of main input'), 'num'], ['second_pct', L('গড় — ২য় গ্রেড %', 'Average: 2nd grade %'), 'num'], ['waste_pct', L('গড় — নষ্ট %', 'Average: wastage %'), 'num'],
  ['headcount', L('গড় — কর্মী সংখ্যা', 'Average: headcount'), 'num'], ['minutes', L('গড় — মোট সময় (মিনিট)', 'Average: total time (minutes)'), 'num']];
B.forms['05-4'] = {
  title: L('ফলন টেস্ট শিট', 'Yield test sheet'),
  head: [ITEM('item', L('আইটেম কোড ও পণ্যের নাম', 'Item code & product name'), { req: true }), SEL('family', L('পরিবার', 'Family'), FAMILIES), T('family_other', L('অন্য (লিখুন)', 'Other (write it)'), { show: (x) => x.d.family === 'other' }), T('recipe_no', L('রেসিপি কার্ড নং', 'Recipe card no.'), { req: true }), T('recipe_ver', L('রেসিপির সংস্করণ (Version)', 'Recipe version'), { req: true })],
  sections: [
    { title: L('তিন ব্যাচের মাপ', 'Three-batch measurements'), fields: [
      NOTE(L('তিনটি আলাদা দিনের তিনটি ব্যাচ মাপতে হবে। প্রতিটি সংখ্যা পাল্লায় মেপে বা গণনা করে, অনুমানে নয়। যিনি মাপবেন, তিনি ওই ব্যাচের কারিগর নন। যে ঘর পণ্যের সাথে খাটে না, সেখানে খালি রাখুন।',
        'Measure three batches on three different days. Every number is weighed or counted, never guessed. The person who measures is not the craftsman of that batch. Leave a box empty if it does not apply to this product.'), 'warn'),
      CH('in_unit', L('মূল উপকরণের একক', 'Main input unit'), [['kg', L('কেজি', 'kg')], ['l', L('লিটার', 'litre')]], { req: true }),
      CH('out_unit', L('পণ্যের একক', 'Product unit'), [['kg', L('কেজি', 'kg')], ['pc', L('পিস', 'pc')]], { req: true }),
      TABLE('b', null, [D('date', L('1 · তারিখ', '1 · Date'), { req: true }),
        N('input', L('2 · ব্যবহৃত মূল উপকরণ (Input) — দুধ / ময়দা / অন্য', '2 · Main input used: milk / flour / other'), { req: true }),
        N('base', L('3 · প্রাপ্ত বেস (ছানা / খোয়া / খামির / ব্যাটার)', '3 · Base obtained (chhana / khoa / dough / batter)'), { req: (x) => !x.row.dash }),
        CALC('base_pct', L('4 · বেস রূপান্তর % = (3) ÷ (2) × 100', '4 · Base conversion % = (3) ÷ (2) × 100'), 'num'),
        N('base_use', L('5 · বেস ব্যবহার', '5 · Base used'), { req: (x) => !x.row.dash }), N('sugar', L('6 · চিনি / সিরা / অন্য উপকরণ', '6 · Sugar / syrup / other'), { req: (x) => !x.row.dash }), N('mid', L('7 · মাঝের ওজন — ভাজা বা বেকের পর', '7 · Mid weight after frying or baking'), { req: (x) => !x.row.dash }),
        N('good', L('8 · ভালো পণ্য (১ম গ্রেড)', '8 · Good product (1st grade)'), { req: true }), N('second', L('9 · ২য় গ্রেড', '9 · 2nd grade'), { req: (x) => !x.row.dash }), N('waste', L('10 · নষ্ট / জমাট না বাঁধা', '10 · Wasted / failed to set'), { req: (x) => !x.row.dash }),
        CALC('total', L('11 · মোট উৎপাদন = (8) + (9) + (10)', '11 · Total output = (8) + (9) + (10)'), 'num'),
        CALC('per_unit', L('12 · মূল উপকরণের প্রতি ১ একক থেকে ভালো পণ্য = (8) ÷ (2)', '12 · Good product per 1 unit of input = (8) ÷ (2)'), 'num'),
        CALC('second_pct', L('13 · ২য় গ্রেড % = (9) ÷ (11) × 100', '13 · 2nd grade % = (9) ÷ (11) × 100'), 'num'),
        CALC('waste_pct', L('14 · নষ্ট % = (10) ÷ (11) × 100', '14 · Wastage % = (10) ÷ (11) × 100'), 'num'),
        N('headcount', L('15 · কর্মী সংখ্যা (Headcount)', '15 · Headcount'), { req: (x) => !x.row.dash }), N('minutes', L('16 · মোট সময় (মিনিট)', '16 · Total time (minutes)'), { req: (x) => !x.row.dash }),
        CK('dash', L('খালি ঘরগুলো এই পণ্যে খাটে না (দাগ দেওয়া)', 'Empty boxes do not apply to this product (dashed)')),
        ST('craftsman', L('ওই ব্যাচের কারিগর', 'Craftsman of this batch'), { req: true }), ST('measurer', L('17 · পরিমাপকারী (Measured by)', '17 · Measured by'), { req: true })], { rows: BATCH_ROWS })] },
    { title: L('তিন ব্যাচের গড়', 'Three-batch average'), fields: [
      NOTE(L('অনুমোদিত গড় — (12), (13), (14) — উৎপাদন রিপোর্টে টার্গেট ফলন হিসেবে বসবে।', 'Approved averages (12), (13), (14) become the target yield in the production report.'), 'ok'),
      ...AVG_KEYS.map(([k, l, f]) => CALC('avg_' + k, l, f, k === 'per_unit' || k === 'second_pct' || k === 'waste_pct' ? { big: true } : {}))] },
    { title: L('স্বাক্ষর', 'Signatures'), fields: [ST('factory_incharge', L('কারখানা ইনচার্জ', 'Factory in charge'), { req: true })] },
    { who: 'checker', title: L('যাচাই ও অনুমোদন', 'Check & approval'), fields: [
      ST('verifier', L('যাচাইকারী (Checked by)', 'Checked by'), { who: 'checker', req: true }),
      ST('approver', L('অনুমোদনকারী (Approved by) — ব্যবস্থাপনা', 'Approved by: management'), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const rs = x.rows('b'), flags = [], v = {};
    const out = rs.map((r) => {
      const total = (has(r.good) || has(r.second) || has(r.waste)) ? num(r.good) + num(r.second) + num(r.waste) : undefined;
      return { base_pct: pct(r.base, r.input), total, per_unit: div(r.good, r.input), second_pct: pct(r.second, total), waste_pct: pct(r.waste, total) };
    });
    const avgOf = (k) => { const a = rs.map((r, i) => (k in (out[i] || {}) ? out[i][k] : (has(r[k]) ? num(r[k]) : undefined))).filter((n) => n !== undefined && Number.isFinite(n)); return a.length ? Math.round(sum(a) / a.length * 10000) / 10000 : undefined; };
    AVG_KEYS.forEach(([k]) => { v['avg_' + k] = avgOf(k); });
    const dates = rs.map((r) => r.date).filter(has);
    if (new Set(dates).size < dates.length) flags.push(flag('same_day_batches', 'yellow', 'দুটি ব্যাচ একই দিনের — তিনটি আলাদা দিন লাগবে', 'Two batches fall on the same day: three different days are needed'));
    if (rs.some((r) => has(r.measurer) && (r.measurer === r.craftsman))) flags.push(flag('measurer_is_craftsman', 'red', 'পরিমাপকারী ও ওই ব্যাচের কারিগর একই জন', 'The person who measured also made the batch'));
    return { v, rows: { b: out }, flags, needs: [] };
  },
};

/* ============ 05-5 · New product decision sheet ============ */
const BRANDS = [['islamia', L('ইসলামিয়া মিষ্টি ঘর', 'Islamia Misti Ghor')], ['bari', L('মিষ্টি বাড়ি', 'Misti Bari')], ['alcakes', L('আল-কেকিজ', 'Al-Cakes')], ['other', L('অন্য', 'Other')]];
const TRIAL_ROWS = [L('মালামাল ইস্যু স্লিপ — ট্রায়াল', 'Material issue slip: trial'), L('মালামাল ইস্যু স্লিপ — ট্রায়াল', 'Material issue slip: trial'), L('মার্কেটিং ব্যয় রেজিস্টার — স্যাম্পল', 'Marketing expense register: sample'), L('মার্কেটিং ব্যয় রেজিস্টার — স্যাম্পল', 'Marketing expense register: sample')];
const isoAdd = (iso, n) => { const d = new Date(iso + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toLocaleDateString('en-CA'); };
B.forms['05-5'] = {
  title: L('নতুন প্রোডাক্ট সিদ্ধান্ত শিট', 'New product decision sheet'),
  head: [SEL('brand', L('ব্র্যান্ড', 'Brand'), BRANDS, { req: true }), T('brand_other', L('অন্য ব্র্যান্ড (লিখুন)', 'Other brand (write it)'), { show: (x) => x.d.brand === 'other' }),
    T('product', L('পণ্যের নাম', 'Product name'), { req: true }), T('new_code', L('নতুন আইটেম কোড', 'New item code'), { req: true }),
    D('start_date', L('শুরুর তারিখ', 'Start date'), { req: true }), D('review_date', L('পর্যালোচনার তারিখ', 'Review date'), { req: true }),
    CALC('review_hint', L('সেটিংস অনুযায়ী পর্যালোচনার তারিখ', 'Review date according to settings'), 'text')],
  sections: [
    { title: L('Section A · ধারণা', 'Section A · Idea'), fields: [
      T('target', L('লক্ষ্য কাস্টমার', 'Target customer')), M('est_price', L('আনুমানিক বিক্রয়মূল্য', 'Estimated selling price')), T('reason', L('পণ্যের কারণ', 'Why this product'))] },
    { title: L('Section B · রেসিপি, ফলন, মান ও খরচ', 'Section B · Recipe, yield, quality & cost'), fields: [
      T('recipe_no', L('রেসিপি কার্ড নং', 'Recipe card no.')), T('yield_no', L('ফলন টেস্ট শিট নং', 'Yield test sheet no.')), T('spec_no', L('প্রোডাক্ট স্পেক কার্ড নং', 'Product spec card no.')), M('unit_cost', L('একক খরচ ৳', 'Unit cost ৳'))] },
    { title: L('Section C · ট্রায়াল ও স্যাম্পলের খরচ', 'Section C · Trial & sample cost'), fields: [
      TABLE('trial', null, [T('ref', L('কাগজ ও লাইন নং', 'Paper & line no.')), M('amount', L('টাকা ৳', 'Amount ৳'))], { rows: TRIAL_ROWS }),
      CALC('trial_total', L('মোট ট্রায়াল খরচ', 'Total trial cost'), 'money', { big: true })] },
    { title: L('Section D · মতামত', 'Section D · Opinions'), fields: [
      N('tasters', L('স্যাম্পল — স্বাদ পরীক্ষকের সংখ্যা (Taster Count)', 'Sample: number of tasters'), {}),
      N('op_good', L('ভালো', 'Good')), N('op_mid', L('মাঝারি', 'Average')), N('op_bad', L('খারাপ', 'Poor')), CALC('op_text', L('ভালো + মাঝারি + খারাপ = পরীক্ষক?', 'Good + average + poor = tasters?'), 'text', { show: (x) => has(x.d.tasters) }),
      TA('key_point', L('মূল কথা', 'Key point'))] },
    { title: L('Section E · বিক্রি — পর্যালোচনার দিনে', 'Section E · Sales on the review day'), fields: [
      CALC('day_tag', L('পর্যালোচনার দিনের ট্যাগ (লোকেশন সেটিংস থেকে)', 'Review-day tag (from location settings)'), 'text', { show: (x) => has(x.d.review_date) }),
      NOTE(L('মোট বিক্রি দৈনিক শোরুম শিট থেকে নিন।', 'Take total sales from the daily showroom sheet.'), 'ok'),
      N('sold_qty', L('মোট বিক্রি — পরিমাণ', 'Total sold: quantity')), M('sold_amt', L('মোট বিক্রি — টাকা', 'Total sold: amount')),
      N('returns', L('ফেরত বা অভিযোগ (টি)', 'Returns or complaints (no.)')),
      CALC('price_used', L('দাম (মূল্য তালিকা, না পেলে আনুমানিক)', 'Price (price list, else estimated)'), 'money'),
      CALC('margin', L('দাম − একক খরচ = প্রতি এককে মার্জিন ৳', 'Price − unit cost = margin per unit ৳'), 'money', { big: true }),
      N('repeat', L('পুনরায় ক্রয়কারী কাস্টমার', 'Repeat customers'))] },
    { title: L('প্রস্তুতকারী ও যাচাইকারী', 'Prepared & checked by'), fields: [
      NOTE(L('যাচাইকারী হবেন যিনি পণ্যটি তৈরি করেননি, প্রস্তুতকারীও নন।', 'The checker is someone who did not make the product and is not the preparer.'), 'warn'),
      ST('preparer', L('প্রস্তুতকারী (Prepared by)', 'Prepared by'), { req: true }),
      ST('verifier', L('যাচাইকারী (Checked by) (প্রস্তুতকারী নন)', 'Checked by (not the preparer)'), { req: true })] },
    { who: 'checker', title: L('সিদ্ধান্ত ও স্বাক্ষর (মালিক ও প্রধান ব্যবস্থাপনা)', 'Decision & signatures (owner and chief management)'), fields: [
      ST('chief_mgmt', L('প্রধান ব্যবস্থাপনা', 'Chief management'), { who: 'checker', req: true }),
      CH('decision', L('সিদ্ধান্ত', 'Decision'), [['keep', L('রাখা', 'Keep')], ['change', L('বদলানো', 'Change')], ['drop', L('বাদ', 'Drop')]], { who: 'checker', req: true }),
      T('change_what', L('বদলানো — কী', 'Change: what'), { who: 'checker', show: (x) => x.c.decision === 'change', req: (x) => x.c.decision === 'change' }),
      ST('owner', L('মালিকের স্বাক্ষর', "Owner's signature"), { who: 'checker', req: true })] },
  ],
  calc(x) {
    const d = x.d, v = {}, flags = [], needs = [];
    const days = sv(x, 'newprod_review_days');
    if (days === null) { v.review_hint = NEED; needs.push('newprod_review_days'); } else if (has(d.start_date)) v.review_hint = isoAdd(d.start_date, num(days)); else v.review_hint = '—';
    const tr = x.rows('trial'); v.trial_total = sum(tr.map((r) => r.amount));
    const out = tr.map(() => ({}));
    if (has(d.tasters)) { const s = num(d.op_good) + num(d.op_mid) + num(d.op_bad), df = s - num(d.tasters); v.op_text = df === 0 ? L('মিল আছে ✓', 'Matches ✓') : L('অমিল: ' + fm(df), 'Mismatch: ' + fm(df)); if (df !== 0) flags.push(flag('opinion_mismatch', 'yellow', 'মতামতের যোগফল পরীক্ষকের সংখ্যার সমান নয়', 'Opinion counts do not add up to the number of tasters', df, { unit: 'qty' })); }
    if (has(d.review_date)) { const t = x.s['daytag_' + new Date(d.review_date + 'T12:00:00').getDay()]; v.day_tag = t || NEED; }
    const it = (x.env.byCode && x.env.byCode.get(d.new_code)) || null; const price = it && num(it.sell_price) > 0 ? num(it.sell_price) : (has(d.est_price) ? num(d.est_price) : undefined);
    v.price_used = price; v.margin = price !== undefined && has(d.unit_cost) ? price - num(d.unit_cost) : undefined;
    if (v.margin !== undefined && v.margin < 0) flags.push(flag('negative_margin', 'yellow', 'প্রতি এককে মার্জিন ঋণাত্মক', 'Margin per unit is negative', v.margin));
    if (has(d.verifier) && d.verifier === d.preparer) flags.push(flag('verifier_is_preparer', 'red', 'যাচাইকারী ও প্রস্তুতকারী একই জন', 'Checker and preparer are the same person'));
    return { v, rows: { trial: out }, flags, needs };
  },
};
})();
