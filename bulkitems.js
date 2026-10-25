/* Islamia BOS · Bulk item editor (#/bulkitems) and the old-item decision page (#/itemmap), phase22.sql.
   Grid of items, 50 per page from the server, many edits then ONE preview -> apply (items_bulk_apply, dry run first), CSV paste, CSV export (no costs),
   bulk hide / inactivate with a reason, Bangla names of the categories. The old-item page: link / use the dictionary item instead / keep apart / later.
   The server decides every rule (phase22.sql); this file only asks. Loaded after itemmaster.js (it replaces the #/itemmap page of that file). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, fmt, go } = A;
const H = A.H, L = B.L, lab = B.lab, t = A.t;
const $ = (s, el = document) => el.querySelector(s);
const normText = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const PAGE = 50, CAP = 200;
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));

const X = {
  title: L('আইটেম একসাথে বদল', 'Bulk item editor', 'Item একসাথে বদল'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), close: L('বন্ধ', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'),
  more: L('আরও অপশন', 'More options', 'আরও Option'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'), all: L('সব', 'All', 'All'), yes: L('হ্যাঁ', 'Yes', 'Yes'), no: L('না', 'No', 'No'),
  tab_grid: L('তালিকা', 'Grid', 'Grid'), tab_csv: L('CSV পেস্ট', 'Paste CSV', 'CSV paste'), tab_bn: L('বাংলা নাম', 'Bangla names', 'বাংলা নাম'),
  search: L('কোড বা নাম খুঁজুন', 'Search code or name', 'Code বা নাম খুঁজুন'), f_cat: L('ক্যাটাগরি', 'Category', 'Category'), f_type: L('ধরন', 'Type', 'Type'), f_batch: L('ইমপোর্ট ব্যাচ', 'Import batch', 'Import batch'),
  f_unpriced: L('দাম নেই', 'Unpriced only', 'দাম নেই'), f_untracked: L('স্টক ট্র্যাক নয়', 'Untracked only', 'Tracked নয়'), f_fg: L('দাম-ছাড়া তৈরি পণ্য / কিনে-বিক্রি', 'Unpriced finished goods / resale', 'দাম-ছাড়া finished / resale'),
  f_active: L('সক্রিয়', 'Active', 'Active'), f_inactive: L('বন্ধ', 'Inactive', 'Inactive'), f_any: L('সক্রিয়/বন্ধ সব', 'Active + inactive', 'Active + inactive'),
  c_code: L('কোড', 'Code', 'Code'), c_bn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), c_en: L('নাম (ইংরেজি)', 'Name (English)', 'Name (English)'), c_unit: L('একক', 'Unit', 'Unit'),
  c_price: L('বিক্রয় ৳', 'Sell ৳', 'Sell ৳'), c_whs: L('পাইকারি ৳', 'Wholesale ৳', 'Wholesale ৳'), c_trk: L('স্টক ট্র্যাক', 'Track stock', 'Track stock'), c_min: L('ন্যূনতম স্টক', 'Min stock', 'Min stock'),
  c_cnt: L('ব্যবসায় গণনা', 'Count in business', 'Count in business'), c_sell: L('বিক্রয়যোগ্য', 'Sellable', 'Sellable'), c_act: L('সক্রিয়', 'Active', 'Active'), c_cost: L('ক্রয় ৳ (মালিক)', 'Cost ৳ (owner)', 'Cost ৳ (owner)'),
  c_state: L('অবস্থা', 'State', 'State'), locked: L('লক', 'Locked', 'Locked'), hidden: L('লুকানো', 'Hidden', 'Hidden'), nodata: L('Data needed', 'Data needed', 'Data needed'),
  cost_show: L('ক্রয়মূল্যের কলাম (মালিক)', 'Cost column (owner)', 'Cost column (owner)'),
  changed: L('বদলানো সারি', 'rows changed', 'rows বদলানো'), preview: L('প্রিভিউ', 'Preview', 'Preview'), apply: L('অ্যাপ্লাই করুন', 'Apply', 'Apply'), discard: L('বদল বাতিল', 'Discard edits', 'Edits বাতিল'),
  sel: L('বাছাই', 'selected', 'selected'), hide_sel: L('বাছাইগুলো পিকার থেকে লুকান', 'Hide selected from pickers', 'Selected Picker থেকে লুকান'), inact_sel: L('বাছাইগুলো বন্ধ করুন (কারণসহ)', 'Mark selected inactive (with reason)', 'Selected Inactive করুন (reason সহ)'),
  reason: L('কারণ', 'Reason', 'Reason'), reason_need: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'), sel_page: L('এই পাতার সব', 'Select this page', 'এই page-এর সব'),
  page: L('পাতা', 'Page', 'Page'), prev: L('আগের', 'Previous', 'Previous'), next: L('পরের', 'Next', 'Next'), of: L('টোটাল', 'total', 'total'),
  pv_title: L('প্রিভিউ — এখনো কিছু লেখা হয়নি', 'Preview — nothing is written yet', 'Preview — এখনো কিছু লেখা হয়নি'), pv_ok: L('বদলাবে', 'will change', 'বদলাবে'), pv_req: L('অনুমোদনের অনুরোধ হবে', 'will become requests', 'approval request হবে'),
  pv_skip: L('বাদ', 'skipped', 'skip'), pv_err: L('ভুল', 'errors', 'errors'), pv_mode_req: L('আপনার সরাসরি বদলের অনুমতি নেই: প্রতিটি সারি মালিকের অ্যাপ্রুভের অনুরোধ হবে', 'You may not change items directly: each row becomes a request for approval', 'আপনার direct change-এর অনুমতি নেই: প্রতিটি row approval request হবে'),
  pv_go: L('এখন অ্যাপ্লাই করুন', 'Apply now', 'এখন Apply করুন'), pv_none: L('অ্যাপ্লাই করার মতো কোনো বদল নেই', 'Nothing to apply', 'Apply করার মতো বদল নেই'), done: L('হয়ে গেছে', 'Done', 'Done'),
  r_nochange: L('কোনো বদল নেই', 'no change', 'no change'), r_locked: L('লক করা আইটেম', 'locked item', 'locked item'),
  working: L('চলছে…', 'Working…', 'চলছে…'), saved_req: L('অনুরোধ গেছে', 'requests sent', 'requests গেছে'),
  csv_h: L('প্রতি লাইনে: কোড, প্রাইস [, একক, ট্র্যাক হ্যাঁ/না, ন্যূনতম স্টক]', 'One line each: code, price [, unit, track yes/no, min stock]', 'প্রতি line: code, price [, unit, track yes/no, min stock]'),
  csv_ph: L('14-001,120\n14-002,95.5,kg,yes,5', '14-001,120\n14-002,95.5,kg,yes,5', '14-001,120\n14-002,95.5,kg,yes,5'), csv_go: L('প্রিভিউ', 'Preview', 'Preview'),
  csv_bad: L('বোঝা যায়নি এমন লাইন', 'lines not understood', 'বোঝা যায়নি এমন line'), csv_empty: L('কিছু লেখা নেই', 'Nothing pasted', 'কিছু লেখা নেই'), csv_max: L('একবারে সর্বোচ্চ ৫০০ লাইন', 'At most 500 lines at once', 'একবারে সর্বোচ্চ ৫০০ line'),
  export: L('CSV নামান (ক্রয়মূল্য ছাড়া)', 'Download CSV (no costs)', 'CSV download (cost ছাড়া)'), exporting: L('তৈরি হচ্ছে…', 'Preparing…', 'তৈরি হচ্ছে…'),
  bn_h: L('এই ক্যাটাগরিগুলোর বাংলা নাম লেখা বাকি', 'These categories still need a Bangla name', 'এই category-গুলোর বাংলা নাম বাকি'), bn_none: L('সব ক্যাটাগরির বাংলা নাম আছে ✓', 'Every category has a Bangla name ✓', 'সব category-র বাংলা নাম আছে ✓'),
  bn_save: L('সেভ', 'Save', 'Save'), bn_ph: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), bn_list: L('তালিকা ব্যবস্থাপনার অনুমতি লাগবে', 'You need the list-manager right', 'List manage-এর অনুমতি লাগবে'),
  nosql: L('ডেটাবেস আপডেট বাকি (phase22.sql)', 'The database update (phase22.sql) is not installed yet', 'Database update (phase22.sql) বাকি'), noright: L('এই পাতা দেখার অনুমতি নেই', 'You do not have access to this page', 'এই page দেখার অনুমতি নেই'),
  link_map: L('পুরনো আইটেম মেলানো', 'Old items to master codes', 'পুরনো Item মেলানো'),
  // mapping page
  mp_title: L('পুরনো আইটেম → মাস্টার কোড', 'Old items → master codes', 'পুরনো Item → Master code'), mp_prog: L('সিদ্ধান্ত হয়েছে', 'decided', 'decided'), mp_todo: L('সিদ্ধান্ত বাকি', 'To decide', 'Decision বাকি'), mp_later: L('পরে', 'Later', 'Later'),
  mp_linked: L('মেলানো', 'Linked', 'Linked'), mp_kept: L('আলাদা', 'Kept apart', 'Kept apart'), mp_repl: L('ডিকশনারি আইটেম ব্যবহার', 'Dictionary used', 'Dictionary used'),
  mp_sugg: L('প্রস্তাব', 'Suggested', 'Suggested'), mp_match: L('মিল', 'match', 'match'), mp_nosugg: L('কোনো প্রস্তাব নেই', 'No suggestion', 'No suggestion'),
  a_link: L('মেলান: পুরনো আইটেমই বিক্রির আইটেম, ডিকশনারি জোড়া লুকানো', 'Link: the old item stays the sellable one, hide the dictionary twin', 'Link: পুরনো item-ই sellable, dictionary twin লুকানো'),
  a_use: L('ডিকশনারি আইটেম ব্যবহার করুন', 'Use the dictionary item instead', 'Dictionary item ব্যবহার করুন'), a_keep: L('আলাদা থাকুক (জোড়া নেই)', 'Keep separate (no twin)', 'আলাদা থাকুক (twin নেই)'),
  a_later: L('পরে ঠিক করব', 'Decide later', 'পরে ঠিক করব'), a_undo: L('সিদ্ধান্ত ফেরত', 'Undo the decision', 'Decision ফেরত'), a_find: L('অন্য ডিকশনারি আইটেম খুঁজুন', 'Find another dictionary item', 'অন্য dictionary item খুঁজুন'),
  a_acc: L('সব নিশ্চিত মিল মানুন', 'Accept all high-confidence', 'সব confident মিল মানুন'), acc_none: L('নিশ্চিত মিল নেই (অথবা সব মানা হয়ে গেছে)', 'No high-confidence match left', 'Confident মিল নেই'),
  acc_q: L('এই পুরনো আইটেমগুলো মেলানো হবে', 'These old items will be linked', 'এই পুরনো item-গুলো link হবে'), acc_rule: L('"নিশ্চিত" মানে: আমদানির সময় auto চিহ্নিত, অথবা নিয়মে দেওয়া সর্বনিম্ন মিল পেরোলে', '"High confidence" = marked auto at import, or above the minimum match set in the rules', '"Confident" = import-এ auto, বা rules-এর minimum match পেরোলে'),
  fnd_title: L('ডিকশনারি আইটেম বাছুন', 'Choose a dictionary item', 'Dictionary item বাছুন'), fnd_ph: L('বাংলা / ইংরেজি নাম বা ক্যাটাগরি', 'Bangla / English name or category', 'বাংলা / English নাম বা category'),
  fnd_none: L('কিছু মেলেনি', 'Nothing matches', 'কিছু মেলেনি'), fnd_link: L('মেলান', 'Link', 'Link'), fnd_use: L('এটি ব্যবহার', 'Use this', 'Use this'),
  cf_title: L('নিশ্চিত করুন', 'Please confirm', 'Confirm করুন'), cf_old: L('পুরনো আইটেম', 'Old item', 'Old item'), cf_dict: L('ডিকশনারি আইটেম', 'Dictionary item', 'Dictionary item'),
  cf_e1: L('ডিকশনারি আইটেম পাবে', 'The dictionary item gets', 'Dictionary item পাবে'), cf_e2: L('পুরনো আইটেম বন্ধ হবে (মোছা হয় না; পুরনো কোড ও প্রাইসের ইতিহাস থাকে)', 'The old item becomes inactive (not deleted; its code and price history stay)', 'পুরনো item inactive হবে (delete নয়; code ও price history থাকে)'),
  cf_e3: L('এটি ফেরত নেওয়া যায় (সিদ্ধান্ত ফেরত)', 'This can be undone (Undo the decision)', 'এটি ফেরত নেওয়া যায় (Undo)'), cf_cur: L('এখন প্রাইস', 'price now', 'price now'), cf_go: L('হ্যাঁ, এটি করুন', 'Yes, do it', 'Yes, do it'),
  dup_rows: L('একই আইটেম একাধিকবার — প্রতিটি একবারই দিন', 'The same item appears twice — give each once', 'একই item একাধিকবার — প্রতিটি একবারই দিন'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
};
const T = (k) => lab(X[k]);
const E = {      // server messages -> short text
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'Not allowed'), too_many_rows: L('একবারে ২০০টির বেশি সারি নয়', 'At most 200 rows at once', 'একবারে ২০০টির বেশি row নয়'),
  item_not_found: L('আইটেম পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি'), duplicate_row: L('একই আইটেম দুবার', 'Same item twice', 'Same item দুবার'), item_locked: L('লক করা আইটেম', 'Locked item', 'Locked item'), locked: L('লক করা আইটেম', 'Locked item', 'Locked item'),
  nochange: L('কোনো বদল নেই', 'No change', 'No change'), bad_unit: L('একক ঠিক নয়', 'Unknown unit', 'Unit ঠিক নয়'), cost_owner_only: L('ক্রয়মূল্য শুধু মালিক বদলাতে পারেন', 'Only the owner can change cost', 'Cost শুধু Owner বদলাতে পারেন'),
  tracked_needs_count: L('স্টক ট্র্যাক করতে আগে "ব্যবসায় গণনা" চালু', 'Turn on "count in business" before tracking stock', 'Track করতে আগে "count in business" চালু'), item_has_stock: L('স্টক আছে — বন্ধ করা যাবে না', 'Stock exists — cannot switch off', 'Stock আছে — বন্ধ করা যাবে না'),
  type_not_sellable: L('এই ধরন বিক্রি হয় না', 'This type is never sold', 'এই type বিক্রি হয় না'), type_not_counted: L('এই ধরন গণনায় আসে না', 'This type is never counted', 'এই type গণনায় আসে না'), unlink_first: L('আগে মিল সরান', 'Remove the link first', 'আগে link সরান'),
  master_code_taken: L('এই ডিকশনারি কোড আগেই ব্যবহৃত', 'That dictionary code is already used', 'এই dictionary code আগেই ব্যবহৃত'), master_type_mismatch: L('এই কোড সেলের পণ্য নয়', 'That code is not a product for sale', 'এই code sale-এর product নয়'),
  legacy_has_stock: L('পুরনো আইটেমে স্টক আছে', 'The old item has stock', 'Old item-এ stock আছে'), legacy_has_no_price: L('পুরনো আইটেমে প্রাইস নেই', 'The old item has no price', 'Old item-এ price নেই'), changed_since: L('এর পর ডিকশনারি আইটেমের প্রাইস বদলেছে — ফেরত নেওয়া যায়নি', 'The dictionary price changed since — cannot undo', 'এর পর dictionary price বদলেছে — undo হয়নি'),
  dict_has_stock: L('ডিকশনারি আইটেমে স্টক আছে', 'The dictionary item has stock', 'Dictionary item-এ stock আছে'), dict_price_differs: L('ডিকশনারি আইটেমের প্রাইস আলাদা — বদলে যাবে', 'The dictionary item has a different price — it will be replaced', 'Dictionary price আলাদা — বদলে যাবে'), dict_unit_differs: L('ডিকশনারি আইটেমের একক আলাদা — বদলে যাবে', 'The dictionary item has a different unit — it will be replaced', 'Dictionary unit আলাদা — বদলে যাবে'),
  dict_unit_has_stock: L('ডিকশনারি আইটেমে স্টক আছে, একক আলাদা — করা যাবে না', 'The dictionary item has stock in another unit — not possible', 'Dictionary item-এ stock আছে, unit আলাদা — করা যাবে না'), item_linked: L('মাস্টার কোডের সাথে মেলানো — আগে মিল সরান', 'Linked to a master code — remove the link first', 'Master code-এর সাথে linked — আগে link সরান'), replaced: L('ডিকশনারি আইটেম ব্যবহার করা — আগে ফেরত নিন', 'Replaced by a dictionary item — undo it first', 'Dictionary item ব্যবহার করা — আগে undo'),
  undo_first: L('আগে সিদ্ধান্ত ফেরত নিন', 'Undo the decision first', 'আগে decision undo করুন'), already_replaced: L('আগেই ডিকশনারি আইটেম ব্যবহার করা হয়েছে', 'Already replaced', 'Already replaced'), dict_retired: L('ডিকশনারি আইটেম বন্ধ', 'The dictionary item is retired', 'Dictionary item retired'),
  master_code_not_found: L('ডিকশনারি কোড পাওয়া যায়নি', 'Dictionary code not found', 'Dictionary code পাওয়া যায়নি'), item_inactive: L('আইটেম আগেই বন্ধ', 'Item is already inactive', 'Item আগেই inactive'),
};
const errText = (m) => { m = String(m || ''); for (const k of Object.keys(E)) if (m.includes(k)) return lab(E[k]); if (/bad_price/.test(m)) return lab(L('প্রাইস ঠিক নয়', 'Price is not valid', 'Price ঠিক নয়')); if (/bad_flag/.test(m)) return lab(L('হ্যাঁ/না ঠিক নয়', 'Yes/No not valid', 'Yes/No ঠিক নয়')); if (/bad_field/.test(m)) return lab(L('এই ঘর বদলানো যায় না', 'This field cannot be changed here', 'এই field বদলানো যায় না')); return m.slice(0, 80); };
const rpcFail = (e) => { const m = (e && e.message) || ''; if (/function .*does not exist|Could not find the function|schema cache/i.test(m)) return toast(T('nosql')); if (Object.keys(E).some((k) => m.includes(k)) || /bad_price|bad_flag|bad_field/.test(m)) return toast(errText(m)); return fail(e); };

// ---------- state ----------
const BK = { tab: 'grid', f: { q: '', cat: '', type: '', batch: '', unpriced: false, untracked: false, fg: false, active: 'yes' }, page: 0, total: 0, rows: [], base: new Map(), edits: new Map(), sel: new Set(), showCost: false, costs: new Map(),
  cats: [], types: [], batches: [], batchId: null, pending: null, pv: null, busy: false, csv: '', csvMsg: '', ready: false, grant: false, direct: false, sqlOk: true, bnDraft: {} };
const lists = (c) => ((B.ENV && B.ENV.lists && B.ENV.lists[c]) || []).filter((r) => r.active !== false);
const catRows = () => lists('item_categories');
const catName = (code) => { const r = catRows().find((x) => x.value_code === code); if (r) return lab({ bn: r.label_bn || r.label_en || r.value_code, en: r.label_en || undefined, mix: r.label_mix || undefined }); return LEGCAT[code] ? lab(LEGCAT[code]) + ' (' + lab(OLD) + ')' : code || ''; };
const OLD = L('পুরনো তালিকা', 'Old list', 'পুরনো list');
const LEGCAT = { sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'), cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)') };
const unitOpts = () => { const base = [['kg', 'kg'], ['pc', 'pc'], ['lb', 'lb']]; lists('units').forEach((r) => { if (!['kg', 'piece', 'pound'].includes(r.value_code) && !base.some((b) => b[0] === r.value_code)) base.push([r.value_code, lab({ bn: r.label_bn || r.value_code, en: r.label_en || undefined, mix: r.label_mix || undefined })]); }); return base; };
const canUse = () => isOwner() || BK.grant || BK.canEnter;
const ctxPerm = () => (S.ctx && S.ctx.perms && S.ctx.perms.ITEMS) || {};

async function initBulk() {
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  try { if (B.itemMaster) await B.itemMaster.init(); } catch (e) { /* item master missing */ }
  BK.types = B.itemMaster && B.itemMaster.on() ? B.itemMaster.types() : [];
  BK.canEnter = isOwner() || !!ctxPerm().enter;
  BK.grant = isOwner();
  if (!isOwner()) { for (const c of ['item_bulk', 'item_create']) { try { const r = await sb.rpc('has_grant', { p_code: c }); if (r && !r.error && r.data === true) BK.grant = true; } catch (e) { /* no grant */ } } }
  BK.direct = BK.grant;
  try { const r = await sb.from('item_import_batches').select('batch').order('batch'); BK.batches = r.error ? [] : [...new Set((r.data || []).map((x) => x.batch).filter(Boolean))]; } catch (e) { BK.batches = []; }
  BK.ready = true;
}

// ---------- query ----------
function applyFilters(q) {
  const f = BK.f;
  if (f.cat) q = q.eq('category', f.cat);
  if (f.sub) q = q.eq('sub_category', f.sub);   // bos100
  if (f.type) q = q.eq('item_type', f.type);
  if (f.batch) q = q.eq('import_batch', f.batch);
  if (f.fg) { q = q.in('item_type', ['finished_good', 'resale']).is('sell_price', null).eq('is_active', true).eq('hidden', false); }
  else if (f.unpriced) q = q.is('sell_price', null);
  if (f.untracked) q = q.eq('tracked', false);
  if (f.active === 'yes') q = q.eq('is_active', true); else if (f.active === 'no') q = q.eq('is_active', false);
  const s = normText(f.q).replace(/[,()%*\\]/g, ' ').trim();
  if (s) q = q.or(['code', 'name_bn', 'name_en', 'name_mix'].map((c) => c + '.ilike.%' + s + '%').join(','));
  return q;
}
const COLS = 'id,code,name_bn,name_en,unit,sell_price,wholesale_price,tracked,min_stock,count_in_business,sellable,is_active,hidden,locked,item_type,category,sub_category,import_batch';   // bos100: sub_category
async function loadPage() {
  const from = BK.page * PAGE;
  const r = await applyFilters(sb.from('items').select(COLS, { count: 'exact' })).order('code').range(from, from + PAGE - 1);
  if (r.error) throw r.error;
  BK.rows = r.data || []; BK.total = typeof r.count === 'number' ? r.count : BK.rows.length;
  BK.rows.forEach((x) => { if (!BK.base.has(x.id)) BK.base.set(x.id, x); });
  BK.costs = new Map();
  if (isOwner() && BK.showCost && BK.rows.length) { const c = await sb.from('item_costs').select('item_id,cost_price').in('item_id', BK.rows.map((x) => x.id)); (c.data || []).forEach((x) => BK.costs.set(x.item_id, x.cost_price)); }
}

// ---------- page ----------
async function viewBulk() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  try { await initBulk(); } catch (e) { return fail(e); }
  if (!canUse()) return shell(T('title'), `<div class="notice bad">${esc(T('noright'))}</div>`, 'items');
  if (B.bulkPreset) { Object.assign(BK.f, { fg: B.bulkPreset === 'fg', active: 'yes' }); B.bulkPreset = null; BK.page = 0; }
  drawBulk(true);
}
async function reloadGrid() { try { await loadPage(); } catch (e) { return fail(e); } drawGrid(); }
function drawBulk(fresh) {
  const tab = (k) => `<button class="tog ${BK.tab === k ? 'on' : ''}" data-act="bk_tab" data-v="${k}">${esc(T('tab_' + k))}</button>`;
  shell(T('title'), `<div class="row wrap" style="margin-bottom:8px">${tab('grid')}${tab('csv')}${tab('bn')}<a href="#/itemmap" class="mini" style="margin-inline-start:auto;align-self:center">${esc(T('link_map'))} ›</a></div><div id="bk_body"></div>`, 'items');
  if (BK.tab === 'grid') { drawGridShell(); if (fresh || !BK.rows.length) reloadGrid(); else drawGrid(); } else if (BK.tab === 'csv') drawCsv(); else drawBn();
}
const sel = (id, opts, cur, allLabel) => `<select id="${id}"><option value="">${esc(allLabel || T('all'))}</option>${opts.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
function catChoices() {
  const out = []; const seen = new Set();
  catRows().forEach((r) => { seen.add(r.value_code); out.push([r.value_code, catName(r.value_code)]); });            // dictionary categories first
  BK.rows.concat([...BK.base.values()]).forEach((r) => { if (r.category && !seen.has(r.category) && LEGCAT[r.category]) { seen.add(r.category); out.push([r.category, catName(r.category)]); } });
  Object.keys(LEGCAT).forEach((c) => { if (!seen.has(c)) { seen.add(c); out.push([c, catName(c)]); } });
  return out;
}
function drawGridShell() {
  const f = BK.f, chk = (id, on, l) => `<label class="row" style="gap:6px;align-items:center"><input type="checkbox" id="${id}" ${on ? 'checked' : ''}> <span>${esc(l)}</span></label>`;
  $('#bk_body').innerHTML = `<div class="card stack"><input id="bk_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(f.q)}" aria-label="${esc(T('search'))}">
    <div class="row wrap" style="gap:8px">${sel('bk_cat', catChoices(), f.cat, T('f_cat'))}${/* bos100 */ B.catpick ? B.catpick.subSelect('bk_sub', f.cat, f.sub, 'bk_cat') : ''}${BK.types.length ? sel('bk_type', BK.types.map((x) => [x.code, B.itemMaster.typeLabel(x.code)]), f.type, T('f_type')) : ''}
      <select id="bk_active"><option value="yes" ${f.active === 'yes' ? 'selected' : ''}>${esc(T('f_active'))}</option><option value="no" ${f.active === 'no' ? 'selected' : ''}>${esc(T('f_inactive'))}</option><option value="" ${f.active === '' ? 'selected' : ''}>${esc(T('f_any'))}</option></select>
      ${BK.batches.length ? sel('bk_batch', BK.batches.map((b) => [b, b]), f.batch, T('f_batch')) : ''}</div>
    <div class="row wrap" style="gap:12px">${chk('bk_unpriced', f.unpriced, T('f_unpriced'))}${chk('bk_untracked', f.untracked, T('f_untracked'))}${chk('bk_fg', f.fg, T('f_fg'))}${isOwner() ? chk('bk_cost', BK.showCost, T('cost_show')) : ''}</div></div>
    <div class="row between" style="margin:6px 0"><span class="muted" id="bk_count"></span><span class="row" style="gap:6px">${isOwner() ? `<button class="mini" data-act="bk_export">${esc(T('export'))}</button>` : ''}</span></div>
    <div id="bk_bar"></div><div id="bk_grid"></div><div class="row between" id="bk_pager" style="margin-top:8px"></div>`;
}
const cellVal = (r, f) => { const e = BK.edits.get(r.id); return e && f in e ? e[f] : r[f]; };
const edited = (r, f) => { const e = BK.edits.get(r.id); return !!(e && f in e); };
function drawGrid() {
  const el = $('#bk_grid'); if (!el) return;
  const showCost = isOwner() && BK.showCost;
  const inp = (r, f, cls) => { const v = cellVal(r, f); return `<input class="bk-cell ${cls || ''} ${edited(r, f) ? 'ed' : ''}" data-id="${esc(r.id)}" data-f="${f}" inputmode="decimal" autocomplete="off" value="${esc(v === null || v === undefined ? '' : v)}" ${r.locked ? 'disabled' : ''} aria-label="${esc(r.code)} ${f}">`; };
  const txt = (r, f) => { const v = cellVal(r, f); return `<input class="bk-cell bk-name ${edited(r, f) ? 'ed' : ''}" data-id="${esc(r.id)}" data-f="${f}" autocomplete="off" value="${esc(v ?? '')}" ${r.locked ? 'disabled' : ''} aria-label="${esc(r.code)} ${f}">`; };
  const ck = (r, f) => `<input type="checkbox" class="bk-cell ${edited(r, f) ? 'ed' : ''}" data-id="${esc(r.id)}" data-f="${f}" ${cellVal(r, f) ? 'checked' : ''} ${r.locked ? 'disabled' : ''} aria-label="${esc(r.code)} ${f}">`;
  const un = (r) => { const v = cellVal(r, 'unit') || ''; const o = unitOpts(); if (v && !o.some((x) => x[0] === v)) o.push([v, v]); return `<select class="bk-cell ${edited(r, 'unit') ? 'ed' : ''}" data-id="${esc(r.id)}" data-f="unit" ${r.locked ? 'disabled' : ''} aria-label="${esc(r.code)} unit"><option value=""></option>${o.map(([c, l]) => `<option value="${esc(c)}" ${c === v ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`; };
  const head = ['', 'c_code', 'c_bn', 'c_en', 'c_unit', 'c_price', 'c_whs', 'c_trk', 'c_min', 'c_cnt', 'c_sell', 'c_act'].concat(showCost ? ['c_cost'] : []);
  el.innerHTML = BK.rows.length ? `<div class="bk-wrap"><table class="bk-tbl"><thead><tr>${head.map((h) => `<th>${h ? esc(T(h)) : `<label class="bk-hit"><input type="checkbox" id="bk_selall" aria-label="${esc(T('sel_page'))}"></label>`}</th>`).join('')}</tr></thead><tbody>${BK.rows.map((r) => `<tr class="${BK.edits.has(r.id) ? 'chg' : ''}" data-row="${esc(r.id)}">
    <td><label class="bk-hit"><input type="checkbox" class="bk-sel" data-id="${esc(r.id)}" ${BK.sel.has(r.id) ? 'checked' : ''} aria-label="select ${esc(r.code)}"></label></td>
    <td class="bk-code"><b>${esc(r.code)}</b>${/* bos100 */ B.catpick && B.catpick.label(r) ? `<div class="muted" style="font-size:.75rem">${esc(B.catpick.label(r))}</div>` : ''}${r.locked ? ` <span class="chip warn">${esc(T('locked'))}</span>` : ''}${r.hidden ? ` <span class="chip">${esc(T('hidden'))}</span>` : ''}</td>
    <td>${txt(r, 'name_bn')}</td><td>${txt(r, 'name_en')}</td><td>${un(r)}</td><td>${inp(r, 'sell_price', 'n')}</td><td>${inp(r, 'wholesale_price', 'n')}</td><td class="c">${ck(r, 'tracked')}</td><td>${inp(r, 'min_stock', 'n')}</td>
    <td class="c">${ck(r, 'count_in_business')}</td><td class="c">${ck(r, 'sellable')}</td><td class="c">${ck(r, 'is_active')}</td>${showCost ? `<td>${inp({ id: r.id, locked: r.locked, code: r.code, cost_price: BK.costs.get(r.id) }, 'cost_price', 'n')}</td>` : ''}</tr>`).join('')}</tbody></table></div>`
    : `<p class="muted center">${esc(T('none'))}</p>`;
  const pages = Math.max(1, Math.ceil(BK.total / PAGE));
  const c = $('#bk_count'); if (c) c.textContent = BK.total + ' ' + T('of');
  const pg = $('#bk_pager'); if (pg) pg.innerHTML = `<button class="mini" data-act="bk_prev" ${BK.page <= 0 ? 'disabled' : ''}>← ${esc(T('prev'))}</button><span class="muted">${esc(T('page'))} ${BK.page + 1} / ${pages}</span><button class="mini" data-act="bk_next" ${BK.page + 1 >= pages ? 'disabled' : ''}>${esc(T('next'))} →</button>`;
  drawBar();
}
function drawBar() {
  const el = $('#bk_bar'); if (!el) return;
  const n = BK.edits.size, s = BK.sel.size;
  el.innerHTML = (n || s) ? `<div class="card stack bk-bar"><div class="row between"><b id="bk_n">${n} ${esc(T('changed'))}</b><span class="muted">${s} ${esc(T('sel'))}</span></div>
    <div class="row wrap" style="gap:8px">${n ? `<button class="primary" data-act="bk_preview">${esc(T('preview'))}</button><button data-act="bk_discard">${esc(T('discard'))}</button>` : ''}
    ${/* bos100 */ s && BK.direct && B.catpick ? `<button data-act="bk_cat_sel">${esc(B.catpick.T('setFor'))}</button>` : ''}${s && BK.direct ? `<button data-act="bk_hide_sel">${esc(T('hide_sel'))}</button><button data-act="bk_inact_sel">${esc(T('inact_sel'))}</button>` : ''}</div></div>` : '';
}
const css = document.createElement('style'); css.id = 'bkcss';
css.textContent = `.bk-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch;max-width:100%}.bk-tbl{border-collapse:collapse;font-size:.9rem;min-width:880px}.bk-tbl th,.bk-tbl td{padding:4px;border-bottom:1px solid var(--line,#e3e0d8);text-align:start;vertical-align:middle;white-space:nowrap}
.bk-tbl th{font-size:.78rem;color:var(--muted)}.bk-tbl td.c{text-align:center}.bk-tbl input.bk-cell:not([type=checkbox]),.bk-tbl select.bk-cell{width:92px;min-height:36px;padding:4px 6px}.bk-tbl input.bk-name{width:150px}.bk-tbl input[type=checkbox]{width:22px;height:22px}.bk-hit{display:inline-flex;align-items:center;justify-content:center;min-width:40px;min-height:40px}
.bk-cell.ed{outline:2px solid var(--sig-info,#2f6f9f);background:var(--surface-2,#eef5fa)}.bk-tbl tr.chg td.bk-code{border-inline-start:3px solid var(--sig-info,#2f6f9f)}.bk-bar{position:sticky;bottom:6px;z-index:5}
.bk-pv td,.bk-pv th{padding:4px 6px;border-bottom:1px solid var(--line,#e3e0d8);text-align:start;font-size:.88rem;vertical-align:top}.bk-pv .bad{color:var(--sig-bad,#b3261e)}.bk-pv .ok{color:var(--sig-ok,#3a7d5c)}
.bk-ta{width:100%;min-height:150px;font-family:monospace}.mp2 .acts{display:flex;flex-wrap:wrap;gap:6px;margin-top:8px}.mp2 .acts button{min-height:40px;text-align:start}`;
document.head.appendChild(css);

// ---------- edits ----------
function setEdit(id, f, v) {
  const base = BK.base.get(id) || {}; let cur = BK.edits.get(id) || {};
  const b = f === 'cost_price' ? BK.costs.get(id) : base[f];
  const same = typeof v === 'boolean' ? !!b === v : String(v ?? '').trim() === String(b ?? '').trim() || (v !== '' && b !== null && b !== undefined && !Number.isNaN(Number(normText(v))) && ['sell_price', 'wholesale_price', 'min_stock', 'cost_price'].includes(f) && Number(normText(v)) === Number(b));
  cur = { ...cur }; if (same) delete cur[f]; else cur[f] = v;
  if (Object.keys(cur).length) BK.edits.set(id, cur); else BK.edits.delete(id);
}
function collectChanges() {
  const out = [];
  BK.edits.forEach((e, id) => {
    const base = BK.base.get(id); if (!base) return; const row = { item_id: id };
    Object.keys(e).forEach((f) => {
      const v = e[f];
      if (['sell_price', 'wholesale_price', 'min_stock', 'cost_price'].includes(f)) { const n = normText(v); if (n !== '') row[f] = n; }
      else if (f === 'name_bn') { if (normText(v) !== '') row[f] = String(v).trim(); } else row[f] = v;
    });
    if (Object.keys(row).length > 1) out.push(row);
  });
  return out;
}

// ---------- preview / apply (one pipeline for grid edits, CSV and bulk actions) ----------
async function runChunks(changes, dry, note) {
  const sum = { ok: 0, requested: 0, skipped: 0, error: 0, results: [], mode: null };
  for (let i = 0; i < changes.length; i += CAP) {
    const part = changes.slice(i, i + CAP);
    const { data, error } = await sb.rpc('items_bulk_apply', { p_changes: part, p_dry: dry, p_batch: dry ? null : BK.batchId + '-' + (i / CAP), p_note: note || null });
    if (error) return { error };
    ['ok', 'requested', 'skipped', 'error'].forEach((k) => { sum[k] += Number(data[k] || 0); });
    sum.mode = data.mode; sum.results = sum.results.concat((data.results || []).map((r) => ({ ...r, i: i + r.i })));
  }
  return { sum };
}
async function startPreview(changes, label, note) {
  if (!changes.length) return toast(T('pv_none'));
  const keys = changes.map((c) => c.item_id || String(c.code || '').toLowerCase()), dup = keys.find((k, i) => keys.indexOf(k) !== i);
  if (dup) return toast(T('dup_rows') + ': ' + dup);
  BK.pending = { changes, label, note }; BK.batchId = rid(); BK.pv = null;
  openSheet(`<h2>${esc(T('pv_title'))}</h2><p class="muted">${esc(T('working'))}</p>`);
  const r = await runChunks(changes, true, note); if (r.error) { closeSheet(); return rpcFail(r.error); }
  BK.pv = r.sum; drawPreview();
}
const codeOf = (r) => r.code || (BK.base.get(r.item_id) || {}).code || '';
function chgText(c) { return Object.keys(c || {}).map((k) => k + ': ' + (Array.isArray(c[k]) ? (c[k][0] === null || c[k][0] === undefined ? '—' : c[k][0]) + ' → ' + (c[k][1] === null || c[k][1] === undefined ? '—' : c[k][1]) : c[k])).join('; '); }
function drawPreview(done) {
  const s = BK.pv; if (!s) return;
  const go_ = s.ok + s.requested;
  openSheet(`<h2>${esc(done ? T('done') : T('pv_title'))}</h2>
    <div class="row wrap" style="gap:10px;margin:6px 0"><b class="ok">${s.ok} ${esc(T('pv_ok'))}</b><b>${s.requested} ${esc(T('pv_req'))}</b><span>${s.skipped} ${esc(T('pv_skip'))}</span><b class="${s.error ? 'bad' : ''}">${s.error} ${esc(T('pv_err'))}</b></div>
    ${s.mode === 'requests' ? `<div class="notice">${esc(T('pv_mode_req'))}</div>` : ''}
    <div style="max-height:46vh;overflow:auto"><table class="bk-pv" style="width:100%"><tbody>${s.results.map((r) => `<tr><td><b>${esc(codeOf(r))}</b></td><td class="${r.status === 'error' ? 'bad' : r.status === 'ok' || r.status === 'requested' ? 'ok' : ''}">${esc(r.status === 'error' || r.status === 'skipped' ? errText(r.reason) : chgText(r.changes))}</td></tr>`).join('')}</tbody></table></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button>${!done && go_ > 0 ? `<button class="primary full" data-act="bk_apply" ${BK.busy ? 'disabled' : ''}>${esc(T('pv_go'))}</button>` : ''}</div>`);
}
async function applyPending() {
  if (!BK.pending || BK.busy) return; BK.busy = true;
  const r = await runChunks(BK.pending.changes, false, BK.pending.note); BK.busy = false;
  if (r.error) return rpcFail(r.error);
  BK.pv = r.sum;
  const okIds = new Set(r.sum.results.filter((x) => x.status === 'ok' || x.status === 'requested' || x.status === 'skipped').map((x) => x.item_id));
  okIds.forEach((id) => { BK.edits.delete(id); BK.sel.delete(id); BK.base.delete(id); });
  BK.pending = null; drawPreview(true);
  if (BK.tab === 'grid') await reloadGrid(); else drawBar();
}

// ---------- CSV paste ----------
function drawCsv() {
  $('#bk_body').innerHTML = `<div class="card stack"><div class="hint">${esc(T('csv_h'))}</div><textarea id="bk_ta" class="bk-ta" placeholder="${esc(T('csv_ph'))}" autocomplete="off" spellcheck="false">${esc(BK.csv)}</textarea>
    <div id="bk_csvmsg" class="${BK.csvMsg ? 'notice bad' : ''}">${esc(BK.csvMsg)}</div><button class="primary full" data-act="bk_csv_go">${esc(T('csv_go'))}</button></div>`;
}
function parseCsv(text) {
  const rows = [], bad = []; const lines = String(text || '').split(/\r?\n/).map((x) => x.trim()).filter(Boolean);
  lines.forEach((ln, i) => {
    const c = ln.split(/[,\t;]/).map((x) => normText(x));
    if (i === 0 && /^(code|কোড)$/i.test(c[0])) return;
    const row = { code: c[0] }; let okLine = !!c[0];
    if (c[1] !== undefined && c[1] !== '') { if (/^[0-9]{1,10}(\.[0-9]{1,6})?$/.test(c[1]) && Number(c[1]) > 0) row.sell_price = c[1]; else okLine = false; }
    if (c[2]) row.unit = c[2];
    if (c[3]) { const v = c[3].toLowerCase(); if (['yes', 'y', 'true', '1', 'হ্যাঁ'].includes(v)) row.tracked = true; else if (['no', 'n', 'false', '0', 'না'].includes(v)) row.tracked = false; else okLine = false; }
    if (c[4] !== undefined && c[4] !== '') { if (/^[0-9]{1,10}(\.[0-9]{1,6})?$/.test(c[4])) row.min_stock = c[4]; else okLine = false; }
    if (okLine) rows.push(row); else bad.push(i + 1);
  });
  return { rows, bad };
}

// ---------- export ----------
async function exportCsv() {
  if (!isOwner()) return; toast(T('exporting'));
  const cols = ['code', 'name_bn', 'name_en', 'category', 'item_type', 'unit', 'sell_price', 'wholesale_price', 'tracked', 'min_stock', 'count_in_business', 'sellable', 'is_active'];   // never a cost column
  const all = []; for (let from = 0; from < 100000; from += 1000) { const r = await applyFilters(sb.from('items').select(cols.join(','))).order('code').range(from, from + 999); if (r.error) return fail(r.error); all.push(...(r.data || [])); if ((r.data || []).length < 1000) break; }
  const q = (v) => { v = v === null || v === undefined ? '' : String(v); if (/^[=+\-@\t\r]/.test(v)) v = "'" + v; return /[",\n]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
  const csv = '﻿' + [cols.join(','), ...all.map((r) => cols.map((c) => q(r[c])).join(','))].join('\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = 'items-' + new Date().toISOString().slice(0, 10) + '.csv'; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  window.__LASTCSV = csv; toast(T('done'));
}

// ---------- Bangla category names ----------
function drawBn() {
  const need = catRows().filter((r) => !String(r.label_bn || '').trim());
  $('#bk_body').innerHTML = need.length ? `<div class="notice">${esc(T('bn_h'))} (${need.length})</div>${need.map((r) => `<div class="card"><div class="muted">${esc(r.extra && r.extra.cat_no ? r.extra.cat_no + ' · ' : '')}${esc(r.label_en || r.value_code)}</div>
    <div class="row" style="gap:8px;margin-top:6px"><input class="bk-bn" data-c="${esc(r.value_code)}" placeholder="${esc(T('bn_ph'))}" autocomplete="off" value="${esc(BK.bnDraft[r.value_code] || '')}"><button class="primary" data-act="bk_bn_save" data-c="${esc(r.value_code)}">${esc(T('bn_save'))}</button></div></div>`).join('')}`
    : `<div class="notice ok">${esc(T('bn_none'))}</div>`;
}
async function saveBn(code) {
  const v = (BK.bnDraft[code] || '').trim(); if (!v) return toast(T('bn_ph'));
  const r = catRows().find((x) => x.value_code === code); if (!r) return;
  const { error } = await sb.rpc('option_update', { p_list: 'item_categories', p_value: code, p_bn: v, p_en: r.label_en || null, p_mix: r.label_mix || null });
  if (error) { if (/not allowed/.test(error.message || '')) return toast(T('bn_list')); return fail(error); }
  delete BK.bnDraft[code]; try { await B.reloadLists(); } catch (e) { /* next load */ } toast(T('saved')); drawBn();
}

// ---------- actions ----------
Object.assign(H, {
  bk_tab: (a) => { BK.tab = a.dataset.v; BK.sel.clear(); drawBulk(false); },
  bk_prev: () => { if (BK.page > 0) { BK.page--; reloadGrid(); } }, bk_next: () => { BK.page++; reloadGrid(); },
  bk_preview: () => startPreview(collectChanges(), 'grid', null), bk_apply: applyPending,
  bk_discard: () => { BK.edits.clear(); drawGrid(); },
  bk_export: exportCsv,
  bk_cat_sel: () => B.catpick.bulkSheet([...BK.sel], () => { BK.sel.clear(); reloadGrid(); }),   // bos100
  bk_hide_sel: () => startPreview([...BK.sel].map((id) => ({ item_id: id, hidden: true })), 'hide', null),
  bk_inact_sel: () => openSheet(`<h2>${esc(T('inact_sel'))}</h2><div class="stack"><div><label for="bk_reason">${esc(T('reason'))} *</label><input id="bk_reason" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="bk_inact_go">${esc(T('preview'))}</button></div></div>`),
  bk_inact_go: () => { const r = ($('#bk_reason').value || '').trim(); if (!r) return toast(T('reason_need')); startPreview([...BK.sel].map((id) => ({ item_id: id, is_active: false, reason: r })), 'inactive', r); },
  bk_csv_go: () => {
    const ta = $('#bk_ta'); BK.csv = ta ? ta.value : BK.csv; BK.csvMsg = '';
    const { rows, bad } = parseCsv(BK.csv);
    if (!BK.csv.trim()) { BK.csvMsg = T('csv_empty'); return drawCsv(); }
    if (rows.length > 500) { BK.csvMsg = T('csv_max'); return drawCsv(); }
    if (bad.length) BK.csvMsg = T('csv_bad') + ': ' + bad.slice(0, 10).join(', ');
    drawCsv(); if (rows.length) startPreview(rows, 'csv', null);
  },
  bk_bn_save: (a) => saveBn(a.dataset.c),
});
document.addEventListener('input', (e) => {
  const el = e.target;
  if (el.id === 'bk_q') { BK.f.q = el.value; BK.sel.clear(); BK.page = 0; clearTimeout(BK.qt); BK.qt = setTimeout(reloadGrid, 300); return; }
  if (el.classList && el.classList.contains('bk-bn')) { BK.bnDraft[el.dataset.c] = el.value; return; }
  if (el.classList && el.classList.contains('bk-cell') && el.type !== 'checkbox' && el.tagName !== 'SELECT') { setEdit(el.dataset.id, el.dataset.f, el.value); el.classList.toggle('ed', BK.edits.has(el.dataset.id) && el.dataset.f in (BK.edits.get(el.dataset.id) || {})); const tr = el.closest('tr'); if (tr) tr.classList.toggle('chg', BK.edits.has(el.dataset.id)); drawBarSoft(); }
});
function drawBarSoft() { const n = $('#bk_n'); if (n && (BK.edits.size || BK.sel.size)) n.textContent = BK.edits.size + ' ' + T('changed'); else drawBar(); }
document.addEventListener('change', (e) => {
  const el = e.target, id = el.id;
  if (el.classList && el.classList.contains('bk-cell') && (el.type === 'checkbox' || el.tagName === 'SELECT')) { setEdit(el.dataset.id, el.dataset.f, el.type === 'checkbox' ? el.checked : el.value); el.classList.toggle('ed', el.dataset.f in (BK.edits.get(el.dataset.id) || {})); const tr = el.closest('tr'); if (tr) tr.classList.toggle('chg', BK.edits.has(el.dataset.id)); drawBar(); return; }
  if (el.classList && el.classList.contains('bk-sel')) { if (el.checked) BK.sel.add(el.dataset.id); else BK.sel.delete(el.dataset.id); drawBar(); return; }
  if (id === 'bk_selall') { BK.rows.forEach((r) => { if (el.checked) BK.sel.add(r.id); else BK.sel.delete(r.id); }); drawGrid(); return; }
  if (['bk_cat', 'bk_sub', 'bk_type', 'bk_active', 'bk_batch'].includes(id)) { BK.sel.clear(); if (id === 'bk_cat') BK.f.sub = ''; /* bos100 */ BK.f[{ bk_cat: 'cat', bk_sub: 'sub', bk_type: 'type', bk_active: 'active', bk_batch: 'batch' }[id]] = el.value; BK.page = 0; reloadGrid(); return; }
  if (['bk_unpriced', 'bk_untracked', 'bk_fg'].includes(id)) { BK.sel.clear(); BK.f[{ bk_unpriced: 'unpriced', bk_untracked: 'untracked', bk_fg: 'fg' }[id]] = el.checked; BK.page = 0; reloadGrid(); return; }
  if (id === 'bk_cost') { BK.showCost = el.checked; reloadGrid(); }
});

// ============================================================ old item decisions (#/itemmap)
const MP = { rows: [], items: [], tab: 'todo', ready: false, find: null, sqlOk: true };
const nameOf = (i) => (i ? (i.name_bn || i.name_en || i.code) : '');
async function viewMap() {
  shell(T('mp_title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  try { await B.loadStatic(); if (B.itemMaster) await B.itemMaster.init(); } catch (e) { /* defaults */ }
  let ok = isOwner(); if (!ok) { try { const r = await sb.rpc('has_grant', { p_code: 'item_create' }); ok = !!(r && !r.error && r.data === true); } catch (e) { ok = false; } }
  if (!ok) return shell(T('mp_title'), `<div class="notice bad">${esc(T('noright'))}</div>`, 'items');
  MP.owner = isOwner();
  const [r, it] = await Promise.all([sb.from('item_mapping_review').select('*').order('id'), window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,sell_price,wholesale_price,item_type,control_class,category,import_batch,is_active,hidden,master_code,retired_at').order('code'))]);
  if (r.error) return fail(r.error); if (it.error) return fail(it.error);
  MP.rows = r.data || []; MP.items = it.data || []; MP.ready = true; drawMap();
}
const stOf = (x) => (x.status === 'pending' || x.status === 'later' ? (x.status === 'later' ? 'later' : 'todo') : x.status === 'linked' ? 'linked' : x.status === 'rejected' ? 'kept' : 'repl');
function drawMap() {
  const byId = new Map(MP.items.map((i) => [i.id, i])), byCode = new Map(MP.items.map((i) => [i.code, i]));
  const cnt = (k) => MP.rows.filter((x) => stOf(x) === k).length, total = MP.rows.length, decided = cnt('linked') + cnt('kept') + cnt('repl');
  const tabs = [['todo', 'mp_todo'], ['later', 'mp_later'], ['linked', 'mp_linked'], ['kept', 'mp_kept'], ['repl', 'mp_repl']];
  const rows = MP.rows.filter((x) => stOf(x) === MP.tab);
  const pct = total ? Math.round(100 * decided / total) : 0;
  const card = (x) => {
    const o = byId.get(x.item_id) || {}, s = x.suggested_code ? byCode.get(x.suggested_code) : null, lk = o.master_code ? byCode.get(o.master_code) : null, st = stOf(x);
    const conf = x.confidence !== null && x.confidence !== undefined ? Math.round(Number(x.confidence) * 100) + '% ' + T('mp_match') : '';
    return `<div class="card mk mp2 ${st === 'todo' ? 'warn' : ''}"><div class="row between" style="align-items:flex-start;gap:8px"><div><div class="nm"><b>${esc(nameOf(o))}</b> <span class="muted">· ${esc(o.code || '')}</span></div>
      <div class="muted">${esc(o.unit || '')}${o.sell_price !== null && o.sell_price !== undefined ? ' · ৳ ' + esc(fmt(o.sell_price)) : ''}</div>
      ${st === 'linked' && lk ? `<div>→ <b>${esc(lk.code)}</b> ${esc(nameOf(lk))}</div>` : st === 'repl' ? `<div>→ <b>${esc(x.suggested_code || '')}</b> ${esc(nameOf(byCode.get(x.suggested_code)))}</div>` : s ? `<div>${esc(T('mp_sugg'))}: <b>${esc(s.code)}</b> ${esc(nameOf(s))} <span class="muted">· ${esc(s.unit || '')}${conf ? ' · ' + esc(conf) : ''}</span></div>` : `<div class="muted">${esc(T('mp_nosugg'))}</div>`}</div>
      <button class="mini im-dots" data-act="mp_menu" data-v="${esc(x.item_id)}" aria-label="${esc(T('more'))}">⋮</button></div>
      ${st === 'todo' || st === 'later' ? `<div class="acts">${s ? `<button class="primary" data-act="mp_link" data-v="${esc(x.item_id)}" data-c="${esc(s.code)}">${esc(T('a_link'))}</button>` : ''}
        <button data-act="mp_find" data-v="${esc(x.item_id)}">${esc(T('a_find'))}</button>${MP.owner && s ? `<button data-act="mp_use" data-v="${esc(x.item_id)}" data-c="${esc(s.code)}">${esc(T('a_use'))}</button>` : ''}
        <button data-act="mp_keep" data-v="${esc(x.item_id)}">${esc(T('a_keep'))}</button>${st === 'todo' ? `<button data-act="mp_later" data-v="${esc(x.item_id)}">${esc(T('a_later'))}</button>` : ''}</div>`
        : (st === 'repl' && !MP.owner ? '' : `<div class="acts"><button data-act="mp_undo" data-v="${esc(x.item_id)}">${esc(T('a_undo'))}</button></div>`)}</div>`;
  };
  shell(T('mp_title'), `<div class="card stack"><div class="row between"><b id="mp_prog">${decided} / ${total} ${esc(T('mp_prog'))}</b><span class="muted">${pct}%</span></div><div class="im-bar"><i style="width:${pct}%"></i></div>
    <button data-act="mp_accept">${esc(T('a_acc'))}</button></div>
    <div class="row wrap" style="margin:8px 0">${tabs.map(([k, l]) => `<button class="tog ${MP.tab === k ? 'on' : ''}" data-act="mp_tab" data-v="${k}">${esc(T(l))} (${cnt(k)})</button>`).join('')}</div>
    ${rows.map(card).join('') || `<p class="muted center">${esc(T('none'))}</p>`}`, 'items');
}
const stx = (id) => MP.rows.find((r) => r.item_id === id);
async function decide(item, action, dict, force) {
  const { error } = await sb.rpc('item_map_decide2', { p_item: item, p_action: action, p_dict: dict || null, p_note: null, p_force: !!force });
  if (error) {
    const fm = /(master_type_mismatch|dict_has_stock|dict_price_differs|dict_unit_differs)/.exec(error.message || '');
    if (fm && isOwner() && !force && window.confirm(fm[1] === 'master_type_mismatch' ? lab(L('এই কোডটি সেলের পণ্য নয়। তবুও করবেন?', 'That code is not a product for sale. Do it anyway?', 'এই code sale-এর product নয়। তবুও করবেন?')) : errText(fm[1]) + ' — ' + lab(L('তবুও করবেন?', 'Do it anyway?', 'তবুও করবেন?')))) return decide(item, action, dict, true);
    return rpcFail(error);
  }
  closeSheet(); toast(T('saved')); await viewMap(); try { if (B.items2 && B.items2.reload) await B.items2.reload(); } catch (e) { /* list reloads later */ }
}
function menuSheet(id) {
  const x = stx(id); if (!x) return; const o = MP.items.find((i) => i.id === id) || {}, st = stOf(x);
  const b = (act, label, extra) => `<button class="im-act" data-act="${act}" data-v="${esc(id)}" ${extra || ''}>${esc(label)}</button>`;
  openSheet(`<h2>${esc(nameOf(o))} · ${esc(o.code || '')}</h2><div class="stack" style="margin-top:10px">
    ${st === 'todo' || st === 'later' ? (x.suggested_code ? b('mp_link', T('a_link') + ' · ' + x.suggested_code, `data-c="${esc(x.suggested_code)}"`) : '') + b('mp_find', T('a_find')) + (MP.owner && x.suggested_code ? b('mp_use', T('a_use') + ' · ' + x.suggested_code, `data-c="${esc(x.suggested_code)}"`) : '') + b('mp_keep', T('a_keep')) + (st === 'todo' ? b('mp_later', T('a_later')) : '') : (st === 'repl' && !MP.owner ? '' : b('mp_undo', T('a_undo')))}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
// dictionary search: suggestions first, then by how many words of the query match name / category
function candidates(item, q) {
  const o = MP.items.find((i) => i.id === item) || {}, x = stx(item) || {};
  const linked = new Set(MP.items.map((i) => i.master_code).filter(Boolean)); const used = new Set(MP.rows.filter((r) => r.status === 'replaced').map((r) => r.suggested_code));
  const words = normText(q || '').toLowerCase().split(/\s+/).filter(Boolean);
  const catOf = (i) => catName(i.category) + ' ' + (i.control_class || '');
  const out = [];
  MP.items.forEach((d) => {
    if (!d.import_batch || !d.is_active || linked.has(d.code) || used.has(d.code)) return;
    const hay = [d.code, d.name_bn, d.name_en, d.name_mix, catOf(d)].join(' ').toLowerCase();
    let sc = 0; if (words.length) { words.forEach((w) => { if (hay.includes(w)) sc += 1; }); if (!sc && d.code !== x.suggested_code) return; } else if (d.code !== x.suggested_code) { if (!['finished_good', 'resale'].includes(d.item_type)) return; if (!(d.category && d.category === (MP.items.find((i) => i.code === x.suggested_code) || {}).category)) return; }
    if (d.code === x.suggested_code) sc += 100; if (['finished_good', 'resale'].includes(d.item_type)) sc += 0.5;
    out.push([sc, d]);
  });
  return out.sort((a, b) => b[0] - a[0] || String(a[1].code).localeCompare(b[1].code)).slice(0, 25).map((p) => p[1]);
}
function findSheet(item) {
  MP.find = item; const o = MP.items.find((i) => i.id === item) || {};
  openSheet(`<h2>${esc(T('fnd_title'))}</h2><div class="muted">${esc(nameOf(o))} · ${esc(o.code || '')}</div><input id="mp_fq" type="search" autocomplete="off" placeholder="${esc(T('fnd_ph'))}" value="${esc(o.name_bn || '')}" style="margin-top:8px"><div id="mp_fl" style="margin-top:8px;max-height:52vh;overflow:auto"></div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  drawFind('');
}
function drawFind(q) {
  const el = $('#mp_fl'); if (!el) return; const o = MP.items.find((i) => i.id === MP.find) || {};
  const list = candidates(MP.find, q === '' ? (o.name_en || o.name_bn || '') : q);
  const x = stx(MP.find) || {};
  el.innerHTML = list.map((d) => `<div class="card"><div class="nm"><b>${esc(d.code)}</b> ${esc(nameOf(d))}${d.code === x.suggested_code ? ` <span class="chip ok">${esc(T('mp_sugg'))}</span>` : ''}</div><div class="muted">${esc(d.name_en || '')} · ${esc(catName(d.category))} · ${esc(d.unit || '')}${d.sell_price !== null && d.sell_price !== undefined ? ' · ৳ ' + esc(fmt(d.sell_price)) : ''}</div>
    <div class="acts"><button data-act="mp_link" data-v="${esc(MP.find)}" data-c="${esc(d.code)}">${esc(T('fnd_link'))}</button>${MP.owner ? `<button data-act="mp_use" data-v="${esc(MP.find)}" data-c="${esc(d.code)}">${esc(T('fnd_use'))}</button>` : ''}</div></div>`).join('') || `<p class="muted center">${esc(T('fnd_none'))}</p>`;
}
function useSheet(item, code) {
  const o = MP.items.find((i) => i.id === item) || {}, d = MP.items.find((i) => i.code === code) || {};
  const pr = (v) => (v === null || v === undefined ? T('nodata') : '৳ ' + fmt(v));
  openSheet(`<h2>${esc(T('cf_title'))}</h2><div class="stack"><div class="card"><div class="muted">${esc(T('cf_old'))}</div><b>${esc(o.code)}</b> ${esc(nameOf(o))}<div>${esc(o.unit || '')} · ${esc(pr(o.sell_price))}</div></div>
    <div class="card"><div class="muted">${esc(T('cf_dict'))}</div><b>${esc(d.code)}</b> ${esc(nameOf(d))}<div class="muted">${esc(T('cf_cur'))}: ${esc(pr(d.sell_price))} · ${esc(d.unit || '')}</div></div>
    <ul><li>${esc(T('cf_e1'))}: ${esc(pr(o.sell_price))} · ${esc(o.unit || '')}${o.wholesale_price !== null && o.wholesale_price !== undefined ? ' · ' + esc(lab(L('পাইকারি', 'wholesale', 'wholesale'))) + ' ৳ ' + esc(fmt(o.wholesale_price)) : ''}</li><li>${esc(T('cf_e2'))}</li><li>${esc(T('cf_e3'))}</li></ul>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="mp_use_do" data-v="${esc(item)}" data-c="${esc(code)}">${esc(T('cf_go'))}</button></div></div>`);
}
async function acceptAll() {
  const { data, error } = await sb.rpc('item_map_accept_confident', { p_dry: true }); if (error) return rpcFail(error);
  if (!data || !Number(data.accepted)) return toast(T('acc_none'));
  openSheet(`<h2>${esc(T('a_acc'))}</h2><p>${esc(T('acc_q'))}: <b>${data.accepted}</b></p><p class="muted" style="overflow-wrap:anywhere">${esc((data.codes || []).join(', '))}</p><div class="hint">${esc(T('acc_rule'))}</div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="mp_accept_do">${esc(T('cf_go'))}</button></div>`);
}
Object.assign(H, {
  mp_tab: (a) => { MP.tab = a.dataset.v; drawMap(); }, mp_menu: (a) => menuSheet(a.dataset.v),
  mp_link: (a) => decide(a.dataset.v, 'link', a.dataset.c), mp_keep: (a) => decide(a.dataset.v, 'keep'), mp_later: (a) => decide(a.dataset.v, 'later'), mp_undo: (a) => decide(a.dataset.v, 'undo'),
  mp_find: (a) => findSheet(a.dataset.v), mp_use: (a) => useSheet(a.dataset.v, a.dataset.c), mp_use_do: (a) => decide(a.dataset.v, 'use_dict', a.dataset.c),
  mp_accept: acceptAll, mp_accept_do: async () => { const { error } = await sb.rpc('item_map_accept_confident', { p_dry: false }); if (error) return rpcFail(error); closeSheet(); toast(T('saved')); await viewMap(); },
});
document.addEventListener('input', (e) => { if (e.target.id === 'mp_fq') drawFind(e.target.value || ' '); });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { bulkitems: viewBulk, itemmap: viewMap });
B.bulkItems = { state: BK, parseCsv, openUnpriced: () => { B.bulkPreset = 'fg'; go('bulkitems'); } };
})();
