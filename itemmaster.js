/* Islamia BOS · Item master (W2): item types and flags, ⋮ menu of the product list, add-by-category with the next code, the dictionary import page
   (preview first, then apply in chunks, resume), the "old items to master codes" decision list, item type defaults, and the asset register.
   Every rule is enforced by the server (phase14.sql); this file only asks. Without phase14 the item_types table is missing and the whole thing stays quiet (B.itemMaster.on() = false).
   Loaded after items2.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, go } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const CHUNK = 200;

const X = {
  more: L('আরও অপশন', 'More options', 'আরও Option'), close: L('বন্ধ', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), save: L('সেভ', 'Save', 'Save'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  yes: L('হ্যাঁ', 'Yes', 'Yes'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), sent: L('অ্যাপ্রুভের জন্য গেছে', 'Sent for approval', 'Approval-এর জন্য গেছে'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  dataNeeded: L('Data needed (প্রাইস নেই)', 'Data needed (no price)', 'Data needed (price নেই)'),
  // menu
  m_edit: L('পণ্য বদলান', 'Edit product', 'Product বদলান'), m_lock: L('লক করুন (শুধু মালিক বদলাতে পারবে)', 'Lock (only the owner can edit)', 'Lock করুন (শুধু Owner বদলাতে পারবে)'), m_unlock: L('আনলক করুন', 'Unlock', 'Unlock করুন'),
  m_hide: L('পিকার থেকে লুকান', 'Hide from pickers', 'Picker থেকে লুকান'), m_show: L('আবার দেখান', 'Show again', 'আবার দেখান'),
  m_inact: L('বন্ধ করুন (কারণসহ)', 'Make inactive (with a reason)', 'Inactive করুন (reason সহ)'), m_act: L('সক্রিয় করুন', 'Make active', 'Active করুন'),
  m_cnt_on: L('ব্যবসার হিসাবে ধরুন (স্টক / COGS / লাভ)', 'Count in business (stock / COGS / profit)', 'Business-এর হিসাবে ধরুন'), m_cnt_off: L('ব্যবসার হিসাবে ধরবেন না', 'Do not count in business', 'Business-এর হিসাবে ধরবেন না'),
  m_sell_on: L('বিক্রির জন্য চালু', 'Allow selling', 'Selling চালু'), m_sell_off: L('বিক্রি বন্ধ', 'Stop selling', 'Selling বন্ধ'),
  m_type: L('ধরন বদলান', 'Change type', 'Type বদলান'), m_dup: L('একই নামের আইটেম আছে কি দেখুন', 'Duplicate check', 'Duplicate check'), m_hist: L('ইতিহাস', 'History', 'History'),
  m_link: L('মাস্টার কোডের সাথে মেলান', 'Link to a master code', 'Master code-এর সাথে মেলান'), m_unlink: L('মাস্টার কোডের সাথে মিল সরান', 'Remove the master link', 'Master link সরান'), m_copy: L('কোড কপি', 'Copy code', 'Code copy'),
  // chips / labels
  c_locked: L('লক', 'Locked', 'Locked'), c_hidden: L('লুকানো', 'Hidden', 'Hidden'), c_nocount: L('ব্যবসার হিসাবে নেই', 'Not counted', 'Not counted'), c_retired: L('অবসরপ্রাপ্ত', 'Retired', 'Retired'), c_nosell: L('সেল নয়', 'Not for sale', 'Not for sale'),
  f_type: L('আইটেমের ধরন', 'Item type', 'Item type'), f_class: L('ডিকশনারি ক্লাস', 'Dictionary class', 'Dictionary class'), f_flags: L('ফ্ল্যাগ', 'Flags', 'Flags'),
  f_lock: L('লক (শুধু মালিক বদলাবে)', 'Locked (only the owner edits)', 'Lock (শুধু Owner বদলাবে)'), f_hide: L('পিকার থেকে লুকানো', 'Hidden from pickers', 'Picker থেকে লুকানো'),
  f_count: L('ব্যবসার হিসাবে ধরা (স্টক / COGS / লাভ)', 'Count in business (stock / COGS / profit)', 'Business-এর হিসাবে ধরা'), f_sell: L('সেলের জন্য', 'For sale', 'Selling-এর জন্য'),
  f_code: L('পরবর্তী কোড', 'Next code', 'Next code'), f_codeold: L('এই ক্যাটাগরিতে নম্বর-কোড নেই: পুরনো I- কোড হবে', 'This category has no code number: an I- code will be used', 'এই Category-তে code number নেই: I- code হবে'),
  f_locked: L('এই আইটেম লক করা — শুধু মালিক বদলাতে পারেন', 'This item is locked — only the owner can change it', 'এই Item locked — শুধু Owner বদলাতে পারেন'),
  f_fixed: L('এই ধরনের আইটেম কখনো স্টক বা বিক্রিতে আসে না', 'This type never goes to stock or sales', 'এই type কখনো stock বা sales-এ আসে না'),
  f_reason: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'), f_master: L('মাস্টার কোড', 'Master code', 'Master code'),
  // add by category
  bycat: L('ক্যাটাগরি ধরে নতুন', 'New by category', 'Category ধরে নতুন'), bycat_h: L('ক্যাটাগরি বেছে নিন — নতুন আইটেমের কোড সেখান থেকে পরের নম্বর পাবে', 'Choose a category — the new item gets the next code of it', 'Category বাছুন — নতুন Item সেখান থেকে next code পাবে'),
  next: L('পরের কোড', 'next', 'next'), search: L('খুঁজুন', 'Search', 'খুঁজুন'),
  // new item sheet (purchase)
  ni_title: L('নতুন আইটেম তালিকায় যোগ', 'Add a new item to the item list', 'নতুন Item list-এ যোগ'), ni_name: L('নাম (বাংলা) *', 'Name (Bangla) *', 'নাম (বাংলা) *'), ni_en: L('ইংরেজি নাম', 'English name', 'English নাম'),
  ni_cat: L('ক্যাটাগরি', 'Category', 'Category'), ni_unit: L('একক', 'Unit', 'Unit'), ni_go: L('যোগ করুন', 'Add', 'Add'), ni_need: L('নাম লিখুন', 'Enter the name', 'নাম লিখুন'),
  ni_done: L('আইটেম যোগ হয়েছে — কোড', 'Item added — code', 'Item যোগ হয়েছে — code'), ni_pend: L('অনুরোধ মালিকের কাছে গেছে', 'Request sent for approval', 'Request approval-এর জন্য গেছে'),
  // dup / history
  dup_none: L('একই নামের আর কোনো আইটেম নেই ✓', 'No other item has the same name ✓', 'একই নামের আর কোনো item নেই ✓'), dup_found: L('একই নামের আইটেম', 'Items with the same name', 'একই নামের Item'),
  h_price: L('প্রাইসের ইতিহাস', 'Price history', 'Price history'), h_log: L('বদলের লগ', 'Change log', 'Change log'), h_none: L('কোনো ইতিহাস নেই', 'No history', 'কোনো history নেই'),
  // link
  l_title: L('মাস্টার কোড বাছুন', 'Choose the master code', 'Master code বাছুন'), l_ph: L('নাম বা কোড লিখুন', 'Type a name or code', 'নাম বা code লিখুন'), l_ok: L('মেলানো হয়েছে', 'Linked', 'Linked'),
  l_stay: L('পুরনো আইটেমের কোড ও প্রাইস বদলায় না', 'The old item keeps its own code and price', 'পুরনো Item-এর code ও price বদলায় না'),
  // import page
  i_title: L('আইটেম মাস্টার ইমপোর্ট', 'Item master import', 'Item master import'), i_load: L('ফাইল লোড', 'Load the file', 'File load'), i_preview: L('প্রিভিউ (কিছু লেখা হয় না)', 'Preview (writes nothing)', 'Preview (কিছু লেখা হয় না)'),
  i_apply: L('ইমপোর্ট করুন', 'Apply the import', 'Import করুন'), i_rows: L('সারি', 'rows', 'rows'), i_total: L('মোট সারি', 'Rows in file', 'File-এ rows'), i_create: L('তৈরি হবে', 'To create', 'তৈরি হবে'),
  i_skip: L('আগেই আছে (বাদ)', 'Already there (skipped)', 'আগেই আছে (skip)'), i_ret: L('অবসরপ্রাপ্ত কোড (বন্ধ অবস্থায়, কোড সংরক্ষিত)', 'Retired codes (inactive, code kept)', 'Retired code (inactive, code reserved)'),
  i_conf: L('সমস্যা (বাদ যাবে)', 'Problems (left out)', 'Problem (বাদ যাবে)'), i_bytype: L('ধরন অনুযায়ী', 'By type', 'Type অনুযায়ী'), i_bycat: L('ক্যাটাগরি অনুযায়ী', 'By category', 'Category অনুযায়ী'),
  i_note: L('কোনো প্রাইস ইমপোর্ট হয় না — প্রতিটি নতুন আইটেমে প্রাইস "Data needed" থাকবে। আগের আইটেম ও প্রাইস অপরিবর্তিত।', 'No price is imported — every new item shows "Data needed" for the price. Existing items and prices stay as they are.', 'কোনো price import হয় না — প্রতিটি নতুন Item-এ price "Data needed"। আগের Item ও price অপরিবর্তিত।'),
  i_confirm: L('ইমপোর্ট শুরু করবেন?', 'Start the import?', 'Import শুরু করবেন?'), i_go: L('হ্যাঁ, ইমপোর্ট', 'Yes, import', 'Yes, import'), i_prog: L('চলছে', 'Working', 'চলছে'),
  i_done: L('ইমপোর্ট শেষ', 'Import finished', 'Import শেষ'), i_resume: L('আবার শুরু করুন (যেখানে থেমেছিল)', 'Resume (where it stopped)', 'Resume (যেখানে থেমেছিল)'), i_stopped: L('থেমে গেছে — আবার চাপলে এগোবে', 'Stopped — press resume to continue', 'থেমে গেছে — resume চাপুন'),
  i_nofile: L('ফাইল পাওয়া যায়নি', 'File not found', 'File পাওয়া যায়নি'), i_map: L('পুরনো আইটেম মেলানো (প্রস্তাব লোড)', 'Load the old-item suggestions', 'পুরনো Item মেলানো (suggestion load)'),
  i_mapok: L('প্রস্তাব লোড হয়েছে', 'Suggestions loaded', 'Suggestion load হয়েছে'), i_decide: L('সিদ্ধান্ত বাকি তালিকা', 'Needs-decision list', 'Decision বাকি list'), i_owner: L('শুধু মালিক', 'Owner only', 'শুধু Owner'),
  i_sql: L('ডেটাবেস আপডেট বাকি (phase14.sql)', 'The database update (phase14.sql) is not installed yet', 'Database update (phase14.sql) বাকি'), i_batch: L('ব্যাচ', 'Batch', 'Batch'),
  // map page
  mp_title: L('পুরনো আইটেম → মাস্টার কোড', 'Old items → master codes', 'পুরনো Item → Master code'), mp_pending: L('সিদ্ধান্ত বাকি', 'Needs decision', 'Decision বাকি'), mp_linked: L('মেলানো', 'Linked', 'Linked'), mp_rejected: L('আলাদা থাকবে', 'Kept apart', 'আলাদা থাকবে'),
  mp_sugg: L('প্রস্তাব', 'Suggestion', 'Suggestion'), mp_conf: L('মিল', 'match', 'match'), mp_use: L('প্রস্তাব মানুন', 'Use the suggestion', 'Suggestion মানুন'), mp_other: L('অন্য কোড বাছুন', 'Choose another code', 'অন্য code বাছুন'),
  mp_rej: L('আলাদা থাকুক', 'Keep it apart', 'আলাদা থাকুক'), mp_undo: L('সিদ্ধান্ত বাতিল', 'Undo the decision', 'Decision বাতিল'), mp_none: L('সিদ্ধান্ত অপেক্ষায় নেই ✓', 'Nothing waiting ✓', 'Decision অপেক্ষায় নেই ✓'),
  mp_empty: L('এখনও প্রস্তাব লোড হয়নি — ইমপোর্ট পাতা থেকে লোড করুন', 'No suggestions loaded yet — load them from the import page', 'এখনও suggestion load হয়নি — import page থেকে load করুন'),
  // types page
  ty_title: L('আইটেমের ধরন ও ডিফল্ট', 'Item types & defaults', 'Item type ও Default'), ty_h: L('প্রতিটি ধরনের নতুন আইটেম এই ফ্ল্যাগ নিয়ে শুরু হয়। আগের আইটেম বদলায় না।', 'New items of each type start with these flags. Existing items do not change.', 'প্রতিটি type-এর নতুন Item এই flag নিয়ে শুরু হয়। আগের Item বদলায় না।'),
  ty_count: L('ব্যবসার হিসাবে ধরা', 'Count in business', 'Business-এ ধরা'), ty_sell: L('সেলের জন্য', 'For sale', 'Selling-এর জন্য'), ty_active: L('সক্রিয়', 'Active', 'Active'), ty_map: L('ডিকশনারি ক্লাস → ধরন', 'Dictionary class → type', 'Dictionary class → type'),
  ty_sw: L('সুইচ', 'Switches', 'Switch'), ty_tools: L('যন্ত্রপাতির (নিয়ন্ত্রিত) আলাদা স্টক গণনা', 'Tools (controlled) stock count', 'Tools (controlled) stock count'), ty_reg: L('সম্পদ কিনলে সম্পদ-খাতায় যোগ', 'Buying an asset adds it to the register', 'Asset কিনলে register-এ যোগ'),
  ty_appr: L('নতুন আইটেমে অ্যাপ্রুভ লাগবে', 'New items need approval', 'নতুন Item-এ approval লাগবে'), ty_fixed: L('স্থায়ী নিয়ম', 'fixed rule', 'fixed rule'), ty_rules: L('সব নিয়ম: নিয়ম ও অপশন', 'All rules: Rules & options', 'সব rule: Rules ও Option'),
  // assets
  as_title: L('সম্পদ-খাতা', 'Asset register', 'Asset register'), as_add: L('সম্পদ যোগ', 'Add asset', 'Asset যোগ'), as_tag: L('ট্যাগ', 'Tag', 'Tag'), as_loc: L('লোকেশন', 'Location', 'Location'), as_cond: L('অবস্থা', 'Condition', 'Condition'),
  as_status: L('স্ট্যাটাস', 'Status', 'Status'), as_bought: L('কেনার তারিখ', 'Bought on', 'Bought on'), as_cost: L('কস্ট ৳', 'Cost ৳', 'Cost ৳'), as_note: L('নোট', 'Note', 'Note'), as_maint: L('মেইনটেন্যান্স রেকর্ড (08-1)', 'Maintenance record (08-1)', 'Maintenance record (08-1)'),
  as_qty: L('কয়টি', 'How many', 'কয়টি'), as_item: L('সম্পদের আইটেম', 'Asset item', 'Asset item'), as_edit: L('বদলান', 'Edit', 'Edit'), as_retire: L('বন্ধ করুন (বিক্রি / হারানো / বাতিল)', 'Retire (sold / lost / scrapped)', 'Retire (sold / lost / scrapped)'),
  as_react: L('আবার চালু', 'Reactivate', 'Reactivate'), as_none: L('কোনো সম্পদ নেই', 'No assets', 'কোনো asset নেই'), as_all: L('সব', 'All', 'All'), as_retired: L('বন্ধগুলোও দেখান', 'Show retired too', 'Retired-ও দেখান'),
  as_noitem: L('আগে "সম্পদ" ধরনের আইটেম যোগ করুন', 'First add an item of type Asset', 'আগে "Asset" type-এর item যোগ করুন'), as_auto: L('ক্রয় বিল থেকে', 'from a purchase bill', 'purchase bill থেকে'),
  as_reason: L('কারণ', 'Reason', 'Reason'), as_total: L('টোটাল', 'Total', 'Total'), as_count: L('টি', 'assets', 'assets'), as_costhid: L('কস্ট শুধু মালিক বা অনুমতি-পাওয়ারা দেখেন', 'Cost is visible to the owner and permitted people only', 'Cost শুধু Owner/permitted দেখেন'),
};
const T = (k) => lab(X[k]);
const STATUS = { in_use: L('ব্যবহারে', 'In use', 'In use'), in_store: L('স্টোরে', 'In store', 'In store'), under_repair: L('মেরামতে', 'Under repair', 'Under repair'), lost: L('হারানো', 'Lost', 'Lost'), sold: L('বিক্রি', 'Sold', 'Sold'), retired: L('বাতিল', 'Retired', 'Retired') };
const TYPE_FALLBACK = { finished_good: L('তৈরি পণ্য', 'Finished good'), resale: L('কিনে বিক্রি', 'Resale'), raw_material: L('কাঁচামাল', 'Raw material'), packaging: L('প্যাকেজিং', 'Packaging'),
  consumable: L('ভোগ্য সামগ্রী', 'Consumable'), asset: L('সম্পদ', 'Asset'), controlled: L('নিয়ন্ত্রিত (যন্ত্রপাতি)', 'Controlled (tools)'), infrastructure: L('অবকাঠামো সামগ্রী', 'Infrastructure') };

// ---------- state ----------
const M = { master: false, types: [], map: [], grant: false, assetGrant: false, ready: false, p: null };
const lists = (c) => ((B.ENV && B.ENV.lists && B.ENV.lists[c]) || []).filter((r) => r.active !== false);
const rl = (r) => ({ bn: r.label_bn || r.label_en || r.value_code, en: r.label_en || undefined, mix: r.label_mix || undefined });
const typeRow = (code) => M.types.find((x) => x.code === code);
const typeLabel = (code) => { const r = typeRow(code); if (r) return lab({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined }); return TYPE_FALLBACK[code] ? lab(TYPE_FALLBACK[code]) : (code || ''); };
const fixedType = (c) => c === 'asset' || c === 'raw_material';

async function init() {
  if (M.p) return M.p;
  M.p = (async () => {
    try {
      const [ty, cm] = await Promise.all([sb.from('item_types').select('*').order('sort'), sb.from('item_class_map').select('*').order('control_class')]);
      M.master = !ty.error && Array.isArray(ty.data) && ty.data.length > 0;
      M.types = M.master ? ty.data : []; M.map = cm.error ? [] : (cm.data || []);
    } catch (e) { M.master = false; }
    if (M.master && S.ctx && !isOwner()) {
      try { const r = await sb.rpc('has_grant', { p_code: 'item_create' }); M.grant = !!(r && !r.error && r.data === true); } catch (e) { M.grant = false; }
      try { const r = await sb.rpc('has_grant', { p_code: 'asset_manage' }); M.assetGrant = !!(r && !r.error && r.data === true); } catch (e) { M.assetGrant = false; }
    } else if (isOwner()) { M.grant = true; M.assetGrant = true; }
    M.ready = true;
  })();
  return M.p;
}
const refresh = () => { M.p = null; return init(); };
const canFlag = () => isOwner() || M.grant;
const canNew = () => M.master && (isOwner() || M.grant);
const ctxPerms = () => (S.ctx && S.ctx.perms) || {};
const canEnterItems = () => isOwner() || !!(ctxPerms().ITEMS && ctxPerms().ITEMS.enter);

// ---------- generic helpers ----------
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));
const catLabel = (code) => { const r = lists('item_categories').find((x) => x.value_code === code); return r ? lab(rl(r)) : code || ''; };
const catNo = (code) => { const r = lists('item_categories').find((x) => x.value_code === code); return r && r.extra && r.extra.cat_no ? String(r.extra.cat_no) : /^\d{2,3}$/.test(code || '') ? code : null; };
const itemsNow = () => (B.items2 && B.items2.items ? B.items2.items() : []);
function nextCodeLocal(cat) {          // display only: the server gives the real code
  const no = catNo(cat); if (!no) return null;
  let mx = 0; itemsNow().forEach((i) => { const m = new RegExp('^' + no + '-(\\d+)$').exec(i.code || ''); if (m) mx = Math.max(mx, Number(m[1])); });
  return no + '-' + String(mx + 1).padStart(3, '0');
}
const unitOpts = () => {
  const r = lists('units'); const base = r.length ? r.map((x) => [x.value_code, rl(x)]) : [['kg', { bn: 'কেজি', en: 'kg' }], ['piece', { bn: 'পিস', en: 'piece' }]];
  return [['kg', { bn: 'কেজি', en: 'KG' }], ['pc', { bn: 'পিস', en: 'Piece' }], ['lb', { bn: 'পাউন্ড', en: 'Pound' }], ...base.filter(([c]) => !['kg', 'piece', 'pound'].includes(c))];
};
const sopt = (v, cur, label) => `<option value="${esc(v)}" ${String(v) === String(cur ?? '') ? 'selected' : ''}>${esc(label)}</option>`;
const menuHTML = (title, rows) => `<h2>${esc(title)}</h2><div class="stack" style="margin-top:10px">${rows.filter(Boolean).map(([act, label, attrs]) => `<button class="im-act" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`;
const css = document.createElement('style'); css.id = 'imcss';
css.textContent = `.im-act{display:flex;align-items:center;gap:10px;width:100%;justify-content:flex-start;text-align:start;min-height:48px}.im-act[disabled]{opacity:.55}
.im-dots{min-width:40px;min-height:40px;font-size:1.25rem;line-height:1;flex:none}.im-card{display:flex;justify-content:space-between;gap:10px;align-items:flex-start}.im-card .nm{font-weight:700;overflow-wrap:anywhere}.im-card .sub{font-size:.85rem;color:var(--muted);overflow-wrap:anywhere}
.im-tbl{width:100%;border-collapse:collapse;font-size:.92rem}.im-tbl td,.im-tbl th{padding:6px 4px;border-bottom:1px solid var(--line,#e3e0d8);text-align:start;vertical-align:top}.im-tbl td.n,.im-tbl th.n{text-align:end;white-space:nowrap}
.im-bar{height:10px;border-radius:5px;background:var(--line,#e3e0d8);overflow:hidden}.im-bar>i{display:block;height:100%;background:var(--sig-ok,#3a7d5c);width:0}.im-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}.im-grid .stat{padding:8px}`;
document.head.appendChild(css);

const ERRT = { bad_price: L('প্রাইস ঠিক নয় (০ থেকে ১০০ কোটির মধ্যে সংখ্যা)', 'The price is not valid (a number from 0 to 1,000,000,000)', 'Price ঠিক নয় (০ থেকে ১০০ কোটি)'), bad_unit: L('এই একক তালিকায় নেই', 'This unit is not in the units list', 'এই unit list-এ নেই'),
  bad_category: L('এই ক্যাটাগরি তালিকায় নেই', 'This category is not in the list', 'এই category list-এ নেই'), category_inactive: L('এই ক্যাটাগরি বন্ধ — নতুন আইটেম যোগ হবে না', 'This category is switched off — no new items', 'এই category বন্ধ — নতুন item হবে না'),
  bad_field: L('এই ঘর এই পথে বদলানো যায় না', 'This field cannot be changed this way', 'এই field এই পথে বদলানো যায় না'), item_not_counted: X.m_cnt_off, bill_voided: L('ভয়েড বিলের সম্পদ আবার চালু করা যায় না', 'An asset of a voided bill cannot be reactivated', 'Voided bill-এর asset আবার চালু হয় না'),
  tag_too_long: L('ট্যাগ ৬০ অক্ষরের বেশি হয় না', 'The tag is at most 60 characters', 'Tag ৬০ অক্ষরের বেশি হয় না'), name_required: L('নাম লিখুন', 'Enter the name', 'নাম লিখুন') };
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERRT)) if (m.includes(k)) return lab(ERRT[k]); return null; };
const failx = (e) => { const m = errMsg(e); if (m) return toast(m); return fail(e); };

// ---------- item changes through the server ----------
async function applyPatch(id, patch, note) {
  const { data, error } = await sb.rpc('item_apply', { p_item: id, p_patch: patch, p_note: note || null });
  if (error) { if (/item_locked/.test(error.message || '')) { toast(lab(X.f_locked)); return null; } if (/item_has_stock/.test(error.message || '')) { toast(lab(L('স্টক আছে — আগে শূন্য করুন', 'There is stock — bring it to zero first', 'Stock আছে — আগে শূন্য করুন'))); return null; } failx(error); return null; }
  toast(data && data.status === 'applied' ? T('saved') : T('sent'));
  if (B.items2 && B.items2.reload) { try { await B.items2.reload(); } catch (e) { /* list reloads on its own */ } if (B.items2.redraw) B.items2.redraw(); }
  return data;
}
const itemById = (id) => itemsNow().find((i) => String(i.id) === String(id));

// ---------- the ⋮ menu of a product row ----------
function rowMenu(id) {
  const it = itemById(id); if (!it) return;
  const o = isOwner(), fl = canFlag(), enter = canEnterItems();
  const link = it.import_batch ? null : it.master_code ? ['im_unlink', T('m_unlink') + ' · ' + it.master_code, `data-v="${esc(id)}"`] : ['im_link', T('m_link'), `data-v="${esc(id)}"`];
  openSheet(menuHTML(nm(it) + ' · ' + it.code, [
    enter ? ['im_edit', T('m_edit'), `data-v="${esc(id)}"`] : null,
    o ? ['im_lock', it.locked ? T('m_unlock') : T('m_lock'), `data-v="${esc(id)}"`] : null,
    enter || fl ? ['im_hide', it.hidden ? T('m_show') : T('m_hide'), `data-v="${esc(id)}"`] : null,
    enter || fl ? ['im_active', it.is_active ? T('m_inact') : T('m_act'), `data-v="${esc(id)}"`] : null,
    (enter || fl) && it.item_type !== 'asset' ? ['im_count', it.count_in_business ? T('m_cnt_off') : T('m_cnt_on'), `data-v="${esc(id)}"`] : null,
    (enter || fl) && !fixedType(it.item_type) ? ['im_sell', it.sellable ? T('m_sell_off') : T('m_sell_on'), `data-v="${esc(id)}"`] : null,
    enter || fl ? ['im_type', T('m_type') + ' · ' + typeLabel(it.item_type), `data-v="${esc(id)}"`] : null,
    ['im_dup', T('m_dup'), `data-v="${esc(id)}"`], ['im_hist', T('m_hist'), `data-v="${esc(id)}"`],
    (enter || fl) && link ? link : null,
    ['im_copy', T('m_copy') + ' · ' + it.code, `data-v="${esc(it.code)}"`],
  ]));
}
async function askReason(title, okAct, id) {
  openSheet(`<h2>${esc(title)}</h2><div><label for="im_reason">${esc(T('f_reason'))}</label><input id="im_reason" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="${okAct}" data-v="${esc(id)}">${esc(T('save'))}</button></div>`);
}
function typeSheet(id) {
  const it = itemById(id); if (!it) return;
  const rows = M.types.filter((x) => x.active || x.code === it.item_type);
  openSheet(`<h2>${esc(T('m_type'))} · ${esc(nm(it))}</h2><div class="stack" style="margin-top:10px">${rows.map((x) => `<button class="im-act ${x.code === it.item_type ? 'on' : ''}" data-act="im_type_do" data-v="${esc(id)}" data-t="${esc(x.code)}" ${x.code === it.item_type ? 'disabled' : ''}>${esc(typeLabel(x.code))}</button>`).join('')}</div>
    <div class="hint" style="margin-top:8px">${esc(lab(L('ধরন বদলালে নতুন ধরনের ডিফল্ট ফ্ল্যাগ বসে', 'Changing the type applies the default flags of the new type', 'Type বদলালে নতুন type-এর default flag বসে')))}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
async function dupSheet(id) {
  const it = itemById(id); if (!it) return;
  const { data, error } = await sb.rpc('item_dup_check', { p_name_bn: it.name_bn, p_name_en: it.name_en, p_exclude: it.id });
  if (error) return fail(error);
  openSheet(`<h2>${esc(T('m_dup'))} · ${esc(nm(it))}</h2>${(data || []).length ? `<div class="notice warn">${esc(T('dup_found'))}</div>${data.map((d) => `<div class="card"><b>${esc(d.code)}</b> · ${esc(d.name_bn)}${d.name_en ? ' · ' + esc(d.name_en) : ''}</div>`).join('')}` : `<div class="notice ok">${esc(T('dup_none'))}</div>`}<button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
async function histSheet(id) {
  const it = itemById(id); if (!it) return;
  const ph = await sb.from('item_price_history').select('*').eq('item_id', id).order('id', { ascending: false }).limit(15);
  let lg = { data: [] }; if (isOwner()) lg = await sb.from('audit_log').select('*').eq('table_name', 'items').eq('record_id', String(id)).order('id', { ascending: false }).limit(15);
  const when = (x) => new Date(x).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Asia/Dhaka' });
  const ps = (ph.data || []).map((p) => `<div class="row between"><span class="muted">${esc(when(p.changed_at || p.at || p.created_at))}</span><span>${esc(String(p.old_price ?? '—'))} → <b>${esc(String(p.new_price ?? p.sell_price ?? '—'))}</b></span></div>`).join('');
  const ls = (lg.data || []).map((l) => `<div class="card"><div class="muted" style="font-size:.8rem">${esc(when(l.at))} · ${esc(l.staff_id || '')} · ${esc(l.action)}</div><div style="font-size:.85rem;overflow-wrap:anywhere">${esc(Object.keys((l.detail && l.detail.new) || {}).filter((k) => !['updated_at', 'updated_by'].includes(k)).join(', '))}</div></div>`).join('');
  openSheet(`<h2>${esc(T('m_hist'))} · ${esc(nm(it))}</h2><h3>${esc(T('h_price'))}</h3>${ps || `<p class="muted">${esc(T('h_none'))}</p>`}${isOwner() ? `<h3>${esc(T('h_log'))}</h3>${ls || `<p class="muted">${esc(T('h_none'))}</p>`}` : ''}<button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
// choose a dictionary item for an old item (also used by the needs-decision list)
function pickMaster(oldId, after) {
  const old = itemById(oldId) || { id: oldId, name_bn: '' };
  M.pick = { oldId, after };
  openSheet(`<h2>${esc(T('l_title'))}</h2><div class="muted" style="margin-bottom:6px">${esc(nm(old))} · ${esc(T('l_stay'))}</div><input id="im_pk_q" type="search" autocomplete="off" placeholder="${esc(T('l_ph'))}"><div id="im_pk_l" style="margin-top:8px"></div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  drawPick('');
}
function drawPick(q) {
  const el = $('#im_pk_l'); if (!el) return; const s = q.trim().toLowerCase();
  const rows = itemsNow().filter((i) => i.import_batch && i.is_active && (!s || [i.code, i.name_bn, i.name_en].some((x) => (x || '').toLowerCase().includes(s)))).sort((a, b) => (a.control_class === 'Finished Good' ? 0 : 1) - (b.control_class === 'Finished Good' ? 0 : 1) || a.code.localeCompare(b.code)).slice(0, 30);
  el.innerHTML = rows.map((i) => `<button class="im-act" data-act="im_pick_do" data-c="${esc(i.code)}"><span><b>${esc(i.code)}</b> · ${esc(nm(i))}<br><small class="muted">${esc(i.control_class || '')}${i.unit ? ' · ' + esc(i.unit) : ''}${i.hidden ? ' · ' + esc(T('c_hidden')) : ''}</small></span></button>`).join('') || `<p class="muted">${esc(T('none'))}</p>`;
}
async function linkTo(oldId, code, note, force) {
  const { error } = await sb.rpc('item_mapping_decide', { p_item: oldId, p_dict: code, p_status: 'linked', p_note: note || null, p_force: !!force });
  if (error && /master_type_mismatch/.test(error.message || '') && isOwner() && !force && window.confirm(lab(L('এই মাস্টার কোডটি সেলের পণ্য নয় (কাঁচামাল / সম্পদ / যন্ত্রপাতি …)। তবুও মেলাবেন?', 'That master code is not a product for sale (material / asset / tool …). Link anyway?', 'এই master code sale-এর product নয়। তবুও link করবেন?')))) return linkTo(oldId, code, note, true);
  if (error && /master_type_mismatch/.test(error.message || '')) return toast(lab(L('এই মাস্টার কোডটি সেলের পণ্য নয় — শুধু মালিক জোর করে মেলাতে পারেন', 'That master code is not a product for sale — only the owner can force the link', 'এই master code sale-এর product নয় — শুধু Owner force করতে পারেন')));
  if (error) { if (/master_code_taken/.test(error.message || '')) return toast(lab(L('এই মাস্টার কোড আরেক আইটেমের সাথে মেলানো', 'That master code is already linked to another item', 'এই master code অন্য item-এর সাথে linked'))); return fail(error); }
  toast(T('l_ok'));
}

// ---------- new item sheet (also from the purchase bill editor) ----------
function newItemSheet(o = {}) {
  M.ni = o;
  const cats = lists('item_categories').filter((r) => r.extra && r.extra.cat_no);
  const types = M.types.filter((x) => x.active);
  const ty = o.type || 'finished_good';
  openSheet(`<h2>${esc(T('ni_title'))}</h2><div class="stack">
    <div><label for="ni_bn">${esc(T('ni_name'))}</label><input id="ni_bn" autocomplete="off"></div>
    <div><label for="ni_en">${esc(T('ni_en'))}</label><input id="ni_en" autocomplete="off"></div>
    <div><label for="ni_type">${esc(T('f_type'))}</label><select id="ni_type">${types.map((x) => sopt(x.code, ty, typeLabel(x.code))).join('')}</select></div>
    <div><label for="ni_cat">${esc(T('ni_cat'))}</label><select id="ni_cat"><option value=""></option>${cats.map((r) => sopt(r.value_code, o.category || '', r.extra.cat_no + ' · ' + lab(rl(r)))).join('')}</select><div class="hint" id="ni_code"></div></div>
    ${B.catpick ? B.catpick.subSelect('ni_sub', o.category || '', '', 'ni_cat') : ''}<!-- bos100 -->
    <div><label for="ni_unit">${esc(T('ni_unit'))}</label><select id="ni_unit">${unitOpts().map(([v, l]) => sopt(v, o.unit || 'pc', lab(l))).join('')}</select></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" id="ni_go" data-act="im_ni_go">${esc(T('ni_go'))}</button></div></div>`);
  showNext('ni_cat', 'ni_code');
  if (B.listctl) B.listctl.enhance('#ni_unit', 'units', { keepPrev: true, form: 'ITEMS', ctx: { field: 'units', via: 'new_item' } });
}
async function showNext(selId, hintId) {
  const s = $('#' + selId), h = $('#' + hintId); if (!s || !h) return;
  const c = s.value; if (!c) { h.textContent = ''; return; }
  const local = nextCodeLocal(c);
  h.textContent = local ? T('f_code') + ': ' + local : T('f_codeold');
  try { const r = await sb.rpc('item_next_code', { p_category: c }); if (r && !r.error && r.data && $('#' + hintId) && $('#' + selId).value === c) $('#' + hintId).textContent = T('f_code') + ': ' + r.data; } catch (e) { /* the local guess stays */ }
}
async function niGo() {
  const bn = ($('#ni_bn').value || '').trim(); if (!bn) return toast(T('ni_need'));
  const patch = { name_bn: bn, item_type: $('#ni_type').value, unit: $('#ni_unit').value || null };
  const en = ($('#ni_en').value || '').trim(); if (en) patch.name_en = en; const cat = $('#ni_cat').value; if (cat) patch.category = cat;
  { const sc = $('#ni_sub'); if (cat && sc && sc.value) patch.sub_category = sc.value; }   // bos100
  const btn = $('#ni_go'); if (btn) btn.disabled = true;
  const { data, error } = await sb.rpc('item_new', { p_patch: patch, p_note: null });
  if (btn) btn.disabled = false;
  if (error) return failx(error);
  closeSheet();
  if (data && data.status === 'created') { toast(T('ni_done') + ' ' + data.code); }
  else toast(T('ni_pend'));
  const cb = M.ni && M.ni.onCreated; M.ni = null;
  if (B.items2 && B.items2.reload) { try { await B.items2.reload(); } catch (e) { /* ignore */ } }
  if (cb && data && data.status === 'created') await cb({ item_id: data.item_id, code: data.code });
}
// the "by category" chooser of the product list: every category with its next code
function byCategory() {
  const cats = lists('item_categories').filter((r) => r.extra && r.extra.cat_no).sort((a, b) => String(a.extra.cat_no).localeCompare(String(b.extra.cat_no)));
  openSheet(`<h2>${esc(T('bycat'))}</h2><div class="muted" style="margin-bottom:6px">${esc(T('bycat_h'))}</div><input id="im_bc_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}"><div id="im_bc_l" style="margin-top:8px"></div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  M.bc = cats; drawByCat('');
}
function drawByCat(q) {
  const el = $('#im_bc_l'); if (!el) return; const s = q.trim().toLowerCase();
  el.innerHTML = (M.bc || []).filter((r) => !s || (r.extra.cat_no + ' ' + (r.label_en || '') + ' ' + (r.label_bn || '')).toLowerCase().includes(s)).map((r) => `<button class="im-act" data-act="im_bc_do" data-c="${esc(r.value_code)}"><span><b>${esc(r.extra.cat_no)}</b> · ${esc(lab(rl(r)))}<br><small class="muted">${esc(T('next'))}: ${esc(nextCodeLocal(r.value_code) || '')}</small></span></button>`).join('') || `<p class="muted">${esc(T('none'))}</p>`;
}

// ---------- fields of the product form (items2.js asks for them) ----------
function formHTML(f, isNew) {
  if (!M.master) return '';
  const it = f || {}; const o = isOwner(), types = M.types.filter((x) => x.active || x.code === it.item_type), cur = it.item_type || 'finished_good';
  const tg = (on, id, dis) => `<button type="button" class="tog ${on ? 'on' : ''}" id="${id}" data-act="im_tg" ${dis ? 'disabled' : ''} aria-pressed="${on ? 'true' : 'false'}">${esc(on ? t('on') : t('off'))}</button>`;
  const fixed = fixedType(cur);
  return `<div class="card stack" id="im_form">
    ${it.locked && !o ? `<div class="notice warn">${esc(T('f_locked'))}</div>` : ''}
    <div><label for="im_type">${esc(T('f_type'))}</label><select id="im_type">${types.map((x) => sopt(x.code, cur, typeLabel(x.code))).join('')}</select></div>
    <div><label for="im_class">${esc(T('f_class'))}</label><input id="im_class" value="${esc(it.control_class || '')}" autocomplete="off"></div>
    ${isNew ? `<div class="hint" id="im_code_h"></div>` : `<div class="hint">${esc(T('f_code'))}: <b>${esc(it.code || '')}</b>${it.master_code ? ' · ' + esc(T('f_master')) + ': ' + esc(it.master_code) : ''}</div>`}
    <div class="row between"><span>${esc(T('f_count'))}</span>${tg(it.count_in_business !== false, 'im_count_f', cur === 'asset')}</div>
    <div class="row between"><span>${esc(T('f_sell'))}</span>${tg(it.sellable !== false, 'im_sell_f', fixed)}</div>
    <div class="row between"><span>${esc(T('f_hide'))}</span>${tg(!!it.hidden, 'im_hide_f')}</div>
    ${o ? `<div class="row between"><span>${esc(T('f_lock'))}</span>${tg(!!it.locked, 'im_lock_f')}</div>` : ''}
    ${fixed ? `<div class="hint" id="im_fixed">${esc(T('f_fixed'))}</div>` : '<div class="hint" id="im_fixed" hidden></div>'}</div>`;
}
const flagOn = (id) => { const e = $('#' + id); return !!(e && e.classList.contains('on')); };
function formPatch(cur) {
  if (!M.master || !$('#im_type')) return {};
  const p = {}, ty = $('#im_type').value, cls = ($('#im_class').value || '').trim() || null;
  const set = (k, v) => { if (!cur || cur[k] !== v && !(cur[k] === undefined && v === null)) p[k] = v; };
  set('item_type', ty); if (cls !== null || (cur && cur.control_class)) set('control_class', cls);
  const typeChanged = cur && cur.item_type !== ty;
  const cnt = flagOn('im_count_f'), sell = flagOn('im_sell_f'), hid = flagOn('im_hide_f');
  if (!typeChanged || cnt !== (cur.count_in_business !== false)) set('count_in_business', cnt);
  if (!typeChanged || sell !== (cur.sellable !== false)) set('sellable', sell);
  set('hidden', hid);
  if ($('#im_lock_f')) set('locked', flagOn('im_lock_f'));
  if (!cur) { ['count_in_business', 'sellable'].forEach((k) => { const d = M.types.find((x) => x.code === ty); if (d && p[k] === d[k]) delete p[k]; }); if (p.hidden === false) delete p.hidden; if (p.locked === false) delete p.locked; if (p.control_class === null) delete p.control_class; }
  return p;
}

// ---------- import page ----------
const IMP = { rows: null, pv: null, batch: null, busy: false, done: null, err: null, map: null };
const lsGet = (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } };
const lsSet = (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private window */ } };
async function viewImport() {
  if (!isOwner()) return go('home');
  shell(T('i_title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  await init();
  if (!M.master) return shell(T('i_title'), `<div class="notice bad">${esc(T('i_sql'))}</div>`, 'items');
  IMP.batch = lsGet('bos_im_batch') || ('dict-' + new Date().toISOString().slice(0, 10).replace(/-/g, '') + '-' + Math.random().toString(36).slice(2, 6));
  lsSet('bos_im_batch', IMP.batch);
  drawImport();
}
function nextIdx() { return Number(lsGet('bos_im_next_' + IMP.batch) || 0); }
function drawImport() {
  const pv = IMP.pv, n = IMP.rows ? IMP.rows.length : 0, next = nextIdx();
  const prog = IMP.rows ? Math.min(100, Math.round(100 * next / Math.max(1, n))) : 0;
  const tbl = (rows, head) => `<table class="im-tbl"><thead><tr>${head.map((h, i) => `<th class="${i ? 'n' : ''}">${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table>`;
  const sum = pv ? `<div class="im-grid">
      <div class="stat"><div class="k">${esc(T('i_total'))}</div><div class="v">${pv.total}</div></div><div class="stat"><div class="k">${esc(T('i_create'))}</div><div class="v">${pv.to_create}</div></div>
      <div class="stat"><div class="k">${esc(T('i_skip'))}</div><div class="v">${pv.skip_existing}</div></div><div class="stat"><div class="k">${esc(T('i_ret'))}</div><div class="v">${pv.to_create_retired}</div></div>
      <div class="stat ${pv.conflicts ? 'mk warn' : ''}"><div class="k">${esc(T('i_conf'))}</div><div class="v">${pv.conflicts}</div></div></div>
    <div class="card stack"><b>${esc(T('i_bytype'))}</b>${tbl(Object.entries(pv.by_type || {}).map(([k, v]) => `<tr><td>${esc(typeLabel(k))}</td><td class="n">${v}</td></tr>`), [T('f_type'), '#'])}</div>
    <div class="card stack"><b>${esc(T('i_bycat'))}</b>${tbl((pv.by_category || []).map((c) => `<tr><td>${esc(c.cat_no)} · ${esc(c.category)}</td><td class="n">${c.to_create}${c.skip_existing ? ' <span class="muted">(+' + c.skip_existing + ')</span>' : ''}${c.retired ? ' <span class="chip">' + c.retired + ' ' + esc(T('c_retired')) + '</span>' : ''}</td></tr>`), [T('ni_cat'), '#'])}</div>
    ${(pv.conflict_list || []).length ? `<div class="card stack"><b>${esc(T('i_conf'))}</b>${pv.conflict_list.map((c) => `<div class="row between"><span>${esc(c.code)} · ${esc(c.name || '')}</span><span class="chip bad">${esc(c.reason)}</span></div>`).join('')}</div>` : ''}
    <div class="notice ok">${esc(T('i_note'))}</div>` : '';
  shell(T('i_title'), `<div class="stack">
      <div class="card stack"><div class="row between"><span>${esc(T('i_batch'))}</span><b>${esc(IMP.batch)}</b></div>
        <div class="row"><button class="full" data-act="im_load" ${IMP.busy ? 'disabled' : ''}>${esc(T('i_load'))}${IMP.rows ? ' · ' + n + ' ' + esc(T('i_rows')) : ''}</button>
        <button class="primary full" data-act="im_preview" ${IMP.rows && !IMP.busy ? '' : 'disabled'}>${esc(T('i_preview'))}</button></div>
        ${IMP.err ? `<div class="notice bad">${esc(IMP.err)}</div>` : ''}</div>
      ${sum}
      ${pv ? `<div class="card stack"><div class="im-bar"><i style="width:${prog}%"></i></div><div class="muted" id="im_prog">${next} / ${n}</div>
        <button class="primary" data-act="im_apply" ${IMP.busy || pv.to_create + pv.skip_existing === 0 ? 'disabled' : ''}>${esc(next > 0 && next < n ? T('i_resume') : T('i_apply'))}</button></div>` : ''}
      ${IMP.done ? `<div class="notice ok"><b>${esc(T('i_done'))}</b> · ${IMP.done.created} / ${IMP.done.skipped_existing} / ${IMP.done.conflicts}</div>
        <div class="card stack"><button data-act="im_map">${esc(T('i_map'))}</button>${IMP.map ? `<div class="notice ok">${esc(T('i_mapok'))}: ${IMP.map.loaded}${IMP.map.linked ? ' · ' + esc(T('mp_linked')) + ' ' + IMP.map.linked : ''}</div>` : ''}<a class="tog" href="#/itemmap" style="text-decoration:none">${esc(T('i_decide'))} ›</a></div>` : ''}
    </div>`, 'items');
}
async function loadDict() {
  IMP.err = null; IMP.busy = true; drawImport();
  try { const r = await fetch('data/item_dictionary.json', { cache: 'no-store' }); if (!r.ok) throw new Error(T('i_nofile')); IMP.rows = await r.json(); }
  catch (e) { IMP.err = (e && e.message) || T('i_nofile'); IMP.rows = null; }
  IMP.busy = false; IMP.pv = null; drawImport();
}
async function doPreview() {
  if (!IMP.rows) return; IMP.busy = true; IMP.err = null; drawImport();
  const { data, error } = await sb.rpc('item_master_import_preview', { p_rows: IMP.rows });
  IMP.busy = false; if (error) { IMP.err = (error.message || '').slice(0, 120); drawImport(); return; }
  IMP.pv = data; drawImport();
}
function confirmApply() {
  const pv = IMP.pv; if (!pv) return;
  openSheet(`<h2>${esc(T('i_confirm'))}</h2><div class="stack"><div class="row between"><span>${esc(T('i_create'))}</span><b>${pv.to_create}</b></div><div class="row between"><span>${esc(T('i_skip'))}</span><b>${pv.skip_existing}</b></div>
    <div class="row between"><span>${esc(T('i_ret'))}</span><b>${pv.to_create_retired}</b></div><div class="notice ok">${esc(T('i_note'))}</div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="im_apply_go">${esc(T('i_go'))}</button></div></div>`);
}
async function runApply() {
  closeSheet(); if (!IMP.rows || IMP.busy) return; IMP.busy = true; IMP.err = null; IMP.done = null; drawImport();
  const tot = { created: 0, skipped_existing: 0, conflicts: 0, retired_created: 0 };
  let i = nextIdx();
  while (i < IMP.rows.length) {
    const chunk = IMP.rows.slice(i, i + CHUNK);
    const { data, error } = await sb.rpc('item_master_import_apply', { p_rows: chunk, p_batch: IMP.batch, p_expected: IMP.rows.length });
    if (error) { IMP.err = T('i_stopped') + ' · ' + (error.message || '').slice(0, 100); IMP.busy = false; drawImport(); return; }
    ['created', 'skipped_existing', 'conflicts', 'retired_created'].forEach((k) => { tot[k] += Number(data[k] || 0); });
    i += chunk.length; lsSet('bos_im_next_' + IMP.batch, String(i));
    const pg = $('#im_prog'); if (pg) pg.textContent = i + ' / ' + IMP.rows.length;
    const bar = $('.im-bar > i'); if (bar) bar.style.width = Math.round(100 * i / IMP.rows.length) + '%';
  }
  IMP.busy = false; IMP.done = tot; lsSet('bos_im_batch', ''); IMP.pv = null;
  try { await B.reloadLists(); if (B.items2 && B.items2.reload) await B.items2.reload(); } catch (e) { /* lists refresh next load */ }
  drawImport();
}
async function loadMapping() {
  let rows; try { const r = await fetch('data/seed_item_mapping.json', { cache: 'no-store' }); if (!r.ok) throw new Error('x'); rows = await r.json(); } catch (e) { IMP.err = T('i_nofile'); return drawImport(); }
  const out = { loaded: 0, linked: 0 };
  for (let i = 0; i < rows.length; i += 100) {
    const { data, error } = await sb.rpc('item_mapping_load', { p_rows: rows.slice(i, i + 100) }); if (error) return fail(error);
    out.loaded += Number(data.loaded || 0);
  }
  const al = await sb.rpc('item_mapping_autolink'); if (al && !al.error) out.linked = Number(al.data || 0);
  IMP.map = out; try { if (B.items2 && B.items2.reload) await B.items2.reload(); } catch (e) { /* ignore */ } drawImport();
}

// ---------- needs-decision list ----------
const MP = { tab: 'pending', rows: [], items: [] };
async function viewMap() {
  shell(T('mp_title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  await init(); if (!M.master) return shell(T('mp_title'), `<div class="notice bad">${esc(T('i_sql'))}</div>`, 'items');
  if (!(isOwner() || M.grant)) return go('home');
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const [r, it] = await Promise.all([sb.from('item_mapping_review').select('*').order('id'), window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,sell_price,item_type,control_class,import_batch,is_active,hidden,master_code,category'))]);
  if (r.error) return fail(r.error);
  MP.rows = r.data || []; MP.items = it.data || []; B.__mpItems = MP.items; drawMap();
}
function drawMap() {
  const byId = new Map(MP.items.map((i) => [i.id, i])), byCode = new Map(MP.items.map((i) => [i.code, i]));
  const cnt = (s) => MP.rows.filter((x) => x.status === s).length;
  const rows = MP.rows.filter((x) => x.status === MP.tab);
  const tab = (k, l) => `<button class="tog ${MP.tab === k ? 'on' : ''}" data-act="im_mp_tab" data-v="${k}">${esc(T(l))} (${cnt(k)})</button>`;
  const card = (x) => { const o = byId.get(x.item_id) || {}, s = x.suggested_code ? byCode.get(x.suggested_code) : null, lk = o.master_code ? byCode.get(o.master_code) : null;
    const pct = x.confidence !== null && x.confidence !== undefined ? Math.round(Number(x.confidence) * 100) + '%' : '';
    return `<div class="card mk ${x.status === 'pending' ? 'warn' : ''}"><div class="im-card"><div><div class="nm">${esc(o.name_bn || '')} <span class="muted">· ${esc(o.code || '')}</span></div>
      <div class="sub">${esc(o.unit || '')}${o.sell_price !== null && o.sell_price !== undefined ? ' · ৳ ' + esc(fmt(o.sell_price)) : ''}</div>
      ${x.status === 'linked' && lk ? `<div class="sub">→ <b>${esc(lk.code)}</b> ${esc(lk.name_bn)}</div>` : s ? `<div class="sub">${esc(T('mp_sugg'))}: <b>${esc(s.code)}</b> ${esc(s.name_bn)} · ${esc(s.unit || '')}${pct ? ' · ' + esc(pct) + ' ' + esc(T('mp_conf')) : ''}</div>` : ''}</div>
      <button class="mini im-dots" data-act="im_mp_menu" data-v="${esc(x.item_id)}" aria-label="${esc(T('more'))}">⋮</button></div></div>`; };
  shell(T('mp_title'), `<div class="row wrap" style="margin-bottom:10px">${tab('pending', 'mp_pending')}${tab('linked', 'mp_linked')}${tab('rejected', 'mp_rejected')}</div>
    <div class="muted" style="margin-bottom:8px">${esc(T('l_stay'))}</div>${rows.map(card).join('') || `<p class="muted center">${esc(MP.rows.length ? T('mp_none') : T('mp_empty'))}</p>`}`, 'items');
}
function mpMenu(itemId) {
  const x = MP.rows.find((r) => r.item_id === itemId); if (!x) return;
  const o = MP.items.find((i) => i.id === itemId) || {};
  openSheet(menuHTML((o.name_bn || '') + ' · ' + (o.code || ''), [
    x.status !== 'linked' && x.suggested_code ? ['im_mp_use', T('mp_use') + ' · ' + x.suggested_code, `data-v="${esc(itemId)}"`] : null,
    x.status !== 'linked' ? ['im_mp_other', T('mp_other'), `data-v="${esc(itemId)}"`] : null,
    x.status === 'pending' ? ['im_mp_rej', T('mp_rej'), `data-v="${esc(itemId)}"`] : null,
    x.status !== 'pending' ? ['im_mp_undo', T('mp_undo'), `data-v="${esc(itemId)}"`] : null,
  ]));
}
async function mpDecide(itemId, code, status, force) {
  const { error } = await sb.rpc('item_mapping_decide', { p_item: itemId, p_dict: code, p_status: status, p_note: null, p_force: !!force });
  if (error && /master_type_mismatch/.test(error.message || '') && isOwner() && !force && window.confirm(lab(L('এই মাস্টার কোডটি সেলের পণ্য নয়। তবুও মেলাবেন?', 'That master code is not a product for sale. Link anyway?', 'এই master code sale-এর product নয়। তবুও link করবেন?')))) return mpDecide(itemId, code, status, true);
  if (error && /master_type_mismatch/.test(error.message || '')) return toast(lab(L('এই মাস্টার কোডটি সেলের পণ্য নয়', 'That master code is not a product for sale', 'এই master code sale-এর product নয়')));
  if (error) { if (/master_code_taken/.test(error.message || '')) return toast(lab(L('এই মাস্টার কোড আরেক আইটেমের সাথে মেলানো', 'That master code is already linked to another item', 'এই master code অন্য item-এর সাথে linked'))); return fail(error); }
  closeSheet(); toast(T('saved')); await viewMap();
}

// ---------- item types page ----------
async function viewTypes() {
  if (!isOwner()) return go('home');
  shell(T('ty_title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  await refresh(); if (!M.master) return shell(T('ty_title'), `<div class="notice bad">${esc(T('i_sql'))}</div>`, 'items');
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  drawTypes();
}
function drawTypes() {
  const sw = (key, l) => { const v = B.rule(key, key === 'tools_stock_on' ? false : true) === true; return `<div class="row between"><span>${esc(T(l))}</span><button class="tog ${v ? 'on' : ''}" data-act="im_rule" data-k="${key}">${esc(v ? t('on') : t('off'))}</button></div>`; };
  const tg = (on, act, c, k, dis) => `<button class="tog ${on ? 'on' : ''}" data-act="${act}" data-c="${esc(c)}" data-k="${k}" ${dis ? 'disabled' : ''}>${esc(on ? t('on') : t('off'))}</button>`;
  shell(T('ty_title'), `<div class="notice ok">${esc(T('ty_h'))}</div>
    <div class="card stack"><b>${esc(T('ty_sw'))}</b>${sw('tools_stock_on', 'ty_tools')}${sw('asset_register_on', 'ty_reg')}${sw('item_create_needs_approval', 'ty_appr')}<a href="#/rulehub" style="text-decoration:none">${esc(T('ty_rules'))} ›</a></div>
    ${M.types.map((x) => `<div class="card stack"><div class="row between"><b>${esc(typeLabel(x.code))}</b><span class="muted">${esc(x.code)}</span></div>
      <div class="row between"><span>${esc(T('ty_count'))}</span>${tg(x.count_in_business, 'im_ty_tg', x.code, 'count_in_business', x.code === 'asset')}</div>
      <div class="row between"><span>${esc(T('ty_sell'))}</span>${tg(x.sellable, 'im_ty_tg', x.code, 'sellable', fixedType(x.code))}</div>
      <div class="row between"><span>${esc(T('ty_active'))}</span>${tg(x.active, 'im_ty_tg', x.code, 'active', false)}</div>
      ${fixedType(x.code) ? `<div class="hint">${esc(T('ty_fixed'))}: ${esc(T('f_fixed'))}</div>` : ''}</div>`).join('')}
    <div class="card stack"><b>${esc(T('ty_map'))}</b>${M.map.map((m) => `<div class="row between"><span>${esc(m.control_class)}</span><select data-imcm="${esc(m.control_class)}">${M.types.filter((x) => x.active || x.code === m.item_type).map((x) => sopt(x.code, m.item_type, typeLabel(x.code))).join('')}</select></div>`).join('')}</div>`, 'items');
}

// ---------- asset register ----------
const AS = { rows: [], items: [], costs: new Map(), maint: [], f: { q: '', loc: '', status: '', retired: false }, shown: 60, canCost: false };
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? nm(l) : String(id); };
const condLabel = (c) => { const r = lists('asset_conditions').find((x) => x.value_code === c); return r ? lab(rl(r)) : c || ''; };
async function viewAssets() {
  shell(T('as_title'), `<p class="muted">${esc(T('loading'))}</p>`, 'home');
  await init(); try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const [a, it, co] = await Promise.all([sb.from('assets').select('*').order('tag'), window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,item_type').eq('item_type', 'asset')), sb.from('asset_costs').select('*')]);
  if (a.error) return shell(T('as_title'), `<div class="notice bad">${esc(T('i_sql'))}</div>`, 'home');
  AS.rows = a.data || []; AS.items = it.data || []; AS.costs = new Map((co.data || []).map((c) => [c.asset_id, c.cost])); AS.canCost = !co.error && (isOwner() || AS.costs.size > 0 || ctxPerms().ITEM_COST);
  drawAssets();
}
const canManage = () => isOwner() || M.assetGrant;
function assetsFiltered() {
  const q = AS.f.q.trim().toLowerCase(), byI = new Map(AS.items.map((i) => [i.id, i]));
  return AS.rows.filter((r) => (AS.f.retired || r.active) && (!AS.f.loc || String(r.location_id) === AS.f.loc) && (!AS.f.status || r.status === AS.f.status)
    && (!q || [r.tag, r.note, (byI.get(r.item_id) || {}).name_bn, (byI.get(r.item_id) || {}).name_en, (byI.get(r.item_id) || {}).code].some((x) => (x || '').toLowerCase().includes(q))));
}
function drawAssets() {
  const byI = new Map(AS.items.map((i) => [i.id, i])), list = assetsFiltered(), locs = (B.ENV && B.ENV.locs) || [];
  const total = AS.canCost ? list.reduce((s, r) => s + (AS.costs.has(r.id) && AS.costs.get(r.id) !== null ? Number(AS.costs.get(r.id)) : 0), 0) : null;
  const row = (r) => { const it = byI.get(r.item_id) || {}, c = AS.costs.get(r.id);
    return `<div class="card p2-row mk ${r.active ? '' : 'bad'}"><div><div class="nm">${esc(nm(it) || it.code || '')}</div><div class="sub">${esc(r.tag)} · ${esc(it.code || '')} · ${esc(locName(r.location_id))}${r.bought_on ? ' · ' + esc(r.bought_on) : ''}</div>
      <div class="tags"><span class="chip ${r.status === 'in_use' ? 'ok' : r.active ? 'info' : 'bad'}">${esc(lab(STATUS[r.status] || L(r.status, r.status)))}</span>${r.condition ? `<span class="chip">${esc(condLabel(r.condition))}</span>` : ''}${r.purchase_bill_id ? `<span class="chip">${esc(T('as_auto'))}</span>` : ''}${r.maintenance_ref ? '<span class="chip">08-1</span>' : ''}</div></div>
      <div class="pr">${AS.canCost ? `<b>${c === undefined || c === null ? '—' : '৳ ' + esc(fmt(c))}</b>` : ''}<button class="mini im-dots" data-act="as_menu" data-v="${esc(r.id)}" aria-label="${esc(T('more'))}">⋮</button></div></div>`; };
  shell(T('as_title'), `<div class="p2-bar"><input id="as_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(AS.f.q)}">${canManage() ? `<button class="primary" data-act="as_add" aria-label="${esc(T('as_add'))}">＋</button>` : ''}</div>
    <div class="row wrap" style="margin:6px 0">${locs.length > 1 ? `<select id="as_loc"><option value="">${esc(T('as_all'))} · ${esc(T('as_loc'))}</option>${locs.map((l) => sopt(String(l.id), AS.f.loc, nm(l))).join('')}</select>` : ''}
      <select id="as_st"><option value="">${esc(T('as_all'))} · ${esc(T('as_status'))}</option>${Object.keys(STATUS).map((k) => sopt(k, AS.f.status, lab(STATUS[k]))).join('')}</select>
      <button class="tog ${AS.f.retired ? 'on' : ''}" data-act="as_ret">${esc(T('as_retired'))}</button></div>
    <div class="row between muted" style="font-size:.88rem"><span>${list.length} ${esc(T('as_count'))}</span>${total !== null ? `<span>${esc(T('as_total'))} ৳ ${esc(fmt(total))}</span>` : `<span>${esc(T('as_costhid'))}</span>`}</div>
    <div id="as_list">${list.slice(0, AS.shown).map(row).join('') || `<p class="muted center">${esc(T('as_none'))}</p>`}</div>${list.length > AS.shown ? `<button class="full" data-act="as_more">${esc(lab(L('আরও দেখুন', 'Show more', 'আরও দেখুন')))}</button>` : ''}`, 'home');
}
function assetMenu(id) {
  const r = AS.rows.find((x) => x.id === id); if (!r) return; const it = AS.items.find((i) => i.id === r.item_id) || {};
  const m = canManage();
  openSheet(menuHTML((nm(it) || '') + ' · ' + r.tag, [
    m && r.active ? ['as_edit', T('as_edit'), `data-v="${esc(id)}"`] : null,
    m && r.active && r.status !== 'under_repair' ? ['as_stat', lab(STATUS.under_repair), `data-v="${esc(id)}" data-s="under_repair"`] : null,
    m && r.active && r.status !== 'in_store' ? ['as_stat', lab(STATUS.in_store), `data-v="${esc(id)}" data-s="in_store"`] : null,
    m && r.active && r.status !== 'in_use' ? ['as_stat', lab(STATUS.in_use), `data-v="${esc(id)}" data-s="in_use"`] : null,
    m && r.active ? ['as_retire', T('as_retire'), `data-v="${esc(id)}"`] : null,
    m && !r.active ? ['as_react', T('as_react'), `data-v="${esc(id)}"`] : null,
    ['im_copy', T('m_copy') + ' · ' + r.tag, `data-v="${esc(r.tag)}"`],
  ]));
}
async function assetForm(id) {
  const r = id ? AS.rows.find((x) => x.id === id) : null; const locs = (B.ENV && B.ENV.locs) || [];
  const conds = lists('asset_conditions');
  let maint = [];
  if (r) { const q = await sb.from('entries').select('id,serial,entry_date').eq('form_code', '08-1').eq('location_id', r.location_id).order('entry_date', { ascending: false }).limit(40); maint = q.data || []; }
  AS.edit = id;
  if (!r && !AS.items.length) return toast(T('as_noitem'));
  const cost = r ? AS.costs.get(r.id) : '';
  openSheet(`<h2>${esc(r ? T('as_edit') + ' · ' + r.tag : T('as_add'))}</h2><div class="stack">
    ${r ? '' : `<div><label for="af_item">${esc(T('as_item'))}</label><select id="af_item">${AS.items.map((i) => sopt(i.id, '', i.code + ' · ' + nm(i))).join('')}</select></div>`}
    <div><label for="af_loc">${esc(T('as_loc'))}</label><select id="af_loc">${locs.map((l) => sopt(String(l.id), r ? String(r.location_id) : String((S.ctx.locations || [])[0] || (locs[0] || {}).id || ''), nm(l))).join('')}</select></div>
    ${r ? '' : `<div><label for="af_qty">${esc(T('as_qty'))}</label><input id="af_qty" inputmode="numeric" value="1"></div>`}
    <div><label for="af_cond">${esc(T('as_cond'))}</label><select id="af_cond"><option value=""></option>${conds.map((c) => sopt(c.value_code, r ? r.condition : '', lab(rl(c)))).join('')}</select></div>
    ${r ? `<div><label for="af_st">${esc(T('as_status'))}</label><select id="af_st">${Object.keys(STATUS).filter((k) => !['lost', 'sold', 'retired'].includes(k) || r.status === k).map((k) => sopt(k, r.status, lab(STATUS[k]))).join('')}</select></div>` : ''}
    <div><label for="af_date">${esc(T('as_bought'))}</label><input id="af_date" type="date" value="${esc(r ? r.bought_on || '' : '')}"></div>
    ${isOwner() || ctxPerms().ITEM_COST ? `<div><label for="af_cost">${esc(T('as_cost'))}</label><input id="af_cost" inputmode="decimal" value="${esc(cost === undefined || cost === null ? '' : cost)}"></div>` : ''}
    ${r ? `<div><label for="af_maint">${esc(T('as_maint'))}</label><select id="af_maint"><option value=""></option>${maint.map((m) => sopt(m.id, r.maintenance_ref, '#' + m.serial + ' · ' + m.entry_date)).join('')}${r.maintenance_ref && !maint.some((m) => m.id === r.maintenance_ref) ? sopt(r.maintenance_ref, r.maintenance_ref, '08-1') : ''}</select></div>` : ''}
    <div><label for="af_note">${esc(T('as_note'))}</label><input id="af_note" value="${esc(r ? r.note || '' : '')}" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="as_save">${esc(T('save'))}</button></div></div>`);
  if (B.listctl) B.listctl.enhance('#af_cond', 'asset_conditions', { otherBlank: true, form: 'ASSET', ctx: () => ({ field: 'asset_condition', asset_id: String((r && r.id) || '') }) });
}
async function assetSave() {
  const id = AS.edit, num = (v) => (norm(v) === '' ? null : Number(norm(v)));
  const cost = $('#af_cost') ? num($('#af_cost').value) : undefined; if (cost !== undefined && cost !== null && (!Number.isFinite(cost) || cost < 0)) return toast(lab(L('কস্ট ঠিক নয়', 'Cost is not valid', 'Cost ঠিক নয়')));
  if (id) {
    const r = AS.rows.find((x) => x.id === id), p = { location_id: Number($('#af_loc').value), condition: $('#af_cond').value || null, status: $('#af_st').value, bought_on: $('#af_date').value || null, note: $('#af_note').value.trim() || null, maintenance_ref: $('#af_maint') ? $('#af_maint').value || null : r.maintenance_ref };
    if (cost !== undefined && cost !== (AS.costs.get(id) === undefined ? null : Number(AS.costs.get(id)))) p.cost = cost;
    const { error } = await sb.rpc('asset_update', { p_id: id, p: p }); if (error) return fail(error);
  } else {
    const q = Math.max(1, Math.min(200, Math.round(num($('#af_qty').value) || 1)));
    const p = { item_id: $('#af_item').value, location_id: Number($('#af_loc').value), qty: q, condition: $('#af_cond').value || null, bought_on: $('#af_date').value || null, note: $('#af_note').value.trim() || null };
    if (cost !== undefined && cost !== null) p.cost = cost;
    const { error } = await sb.rpc('asset_add', { p: p }); if (error) return fail(error);
  }
  closeSheet(); toast(T('saved')); await viewAssets();
}

// ---------- events ----------
Object.assign(H, {
  im_menu: (a) => rowMenu(a.dataset.v),
  im_edit: (a) => { closeSheet(); go('items/edit/' + a.dataset.v); },
  im_lock: async (a) => { const it = itemById(a.dataset.v); closeSheet(); await applyPatch(a.dataset.v, { locked: !it.locked }); },
  im_hide: async (a) => { const it = itemById(a.dataset.v); closeSheet(); await applyPatch(a.dataset.v, { hidden: !it.hidden }); },
  im_active: async (a) => { const it = itemById(a.dataset.v); if (it.is_active) return askReason(T('m_inact'), 'im_inact_do', a.dataset.v); closeSheet(); await applyPatch(a.dataset.v, { is_active: true }); },
  im_inact_do: async (a) => { const r = ($('#im_reason').value || '').trim(); closeSheet(); await applyPatch(a.dataset.v, { is_active: false, retired_reason: r || undefined }); },
  im_count: async (a) => { const it = itemById(a.dataset.v); closeSheet(); await applyPatch(a.dataset.v, { count_in_business: !it.count_in_business }); },
  im_sell: async (a) => { const it = itemById(a.dataset.v); closeSheet(); await applyPatch(a.dataset.v, { sellable: !it.sellable }); },
  im_type: (a) => typeSheet(a.dataset.v),
  im_type_do: async (a) => { closeSheet(); await applyPatch(a.dataset.v, { item_type: a.dataset.t }); },
  im_dup: (a) => dupSheet(a.dataset.v), im_hist: (a) => histSheet(a.dataset.v),
  im_link: (a) => pickMaster(a.dataset.v, null),
  im_unlink: async (a) => { closeSheet(); const { error } = await sb.rpc('item_mapping_decide', { p_item: a.dataset.v, p_dict: null, p_status: 'pending', p_note: null }); if (error) return fail(error); toast(T('saved')); if (B.items2 && B.items2.reload) { await B.items2.reload(); if (B.items2.redraw) B.items2.redraw(); } },
  im_pick_do: async (a) => { const p = M.pick; if (!p) return; closeSheet(); await linkTo(p.oldId, a.dataset.c, 'chosen'); if (p.after) await p.after(); else if (B.items2 && B.items2.reload) { await B.items2.reload(); if (B.items2.redraw) B.items2.redraw(); } },
  im_copy: async (a) => { try { await navigator.clipboard.writeText(a.dataset.v); toast(a.dataset.v); } catch (e) { toast(a.dataset.v); } closeSheet(); },
  im_bycat: () => byCategory(),
  im_bc_do: (a) => { closeSheet(); go('items/new/' + a.dataset.c); },
  im_ni_go: niGo,
  im_tg: (a) => {
    if (a.disabled) return; const on = !a.classList.contains('on'); a.classList.toggle('on', on); a.setAttribute('aria-pressed', on ? 'true' : 'false'); a.textContent = on ? t('on') : t('off');
  },
  im_load: loadDict, im_preview: doPreview, im_apply: confirmApply, im_apply_go: runApply, im_map: loadMapping,
  im_mp_tab: (a) => { MP.tab = a.dataset.v; drawMap(); }, im_mp_menu: (a) => mpMenu(a.dataset.v),
  im_mp_use: (a) => { const x = MP.rows.find((r) => r.item_id === a.dataset.v); return mpDecide(a.dataset.v, x.suggested_code, 'linked'); },
  im_mp_other: (a) => { closeSheet(); pickMaster(a.dataset.v, async () => { await viewMap(); }); },
  im_mp_rej: (a) => mpDecide(a.dataset.v, null, 'rejected'), im_mp_undo: (a) => mpDecide(a.dataset.v, null, 'pending'),
  im_rule: async (a) => { const k = a.dataset.k, v = B.rule(k, k === 'tools_stock_on' ? false : true) === true; const { error } = await sb.rpc('set_rule', { p_key: k, p_value: !v });
    if (error) { if (/tools_stock_has_stock/.test(error.message || '')) return toast(lab(L('যন্ত্রপাতির স্টক শূন্য না হলে বন্ধ করা যায় না', 'Tools stock must be zero before switching off', 'Tools stock শূন্য না হলে off করা যায় না'))); return fail(error); }
    await B.reloadRules(); toast(T('saved')); drawTypes(); },
  im_ty_tg: async (a) => { const x = typeRow(a.dataset.c), k = a.dataset.k; if (!x) return; const { error } = await sb.rpc('item_type_set', { p_code: x.code, p_patch: { [k]: !x[k] } }); if (error) return fail(error); await refresh(); drawTypes(); },
  as_menu: (a) => assetMenu(a.dataset.v), as_add: () => assetForm(null), as_edit: (a) => assetForm(a.dataset.v), as_save: assetSave,
  as_stat: async (a) => { closeSheet(); const { error } = await sb.rpc('asset_update', { p_id: a.dataset.v, p: { status: a.dataset.s } }); if (error) return fail(error); toast(T('saved')); await viewAssets(); },
  as_retire: (a) => { openSheet(`<h2>${esc(T('as_retire'))}</h2><div class="stack"><div><label for="ar_st">${esc(T('as_status'))}</label><select id="ar_st">${['retired', 'sold', 'lost'].map((k) => sopt(k, 'retired', lab(STATUS[k]))).join('')}</select></div>
      <div><label for="ar_reason">${esc(T('as_reason'))} *</label><input id="ar_reason" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="as_retire_do" data-v="${esc(a.dataset.v)}">${esc(T('save'))}</button></div></div>`); },
  as_retire_do: async (a) => { const r = ($('#ar_reason').value || '').trim(); if (!r) return toast(T('f_reason')); const { error } = await sb.rpc('asset_retire', { p_id: a.dataset.v, p_reason: r, p_status: $('#ar_st').value }); if (error) return fail(error); closeSheet(); toast(T('saved')); await viewAssets(); },
  as_react: async (a) => { closeSheet(); const { error } = await sb.rpc('asset_reactivate', { p_id: a.dataset.v }); if (error) return fail(error); toast(T('saved')); await viewAssets(); },
  as_ret: () => { AS.f.retired = !AS.f.retired; drawAssets(); }, as_more: () => { AS.shown += 60; drawAssets(); },
});
let qT = null;
document.addEventListener('input', (e) => {
  const id = e.target.id;
  if (id === 'im_pk_q') drawPick(e.target.value);
  if (id === 'im_bc_q') drawByCat(e.target.value);
  if (id === 'as_q') { AS.f.q = e.target.value; AS.shown = 60; clearTimeout(qT); qT = setTimeout(() => { const keep = $('#as_q'); drawAssets(); const n = $('#as_q'); if (n && keep) { n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }, 200); }
});
document.addEventListener('change', async (e) => {
  const t_ = e.target, id = t_.id;
  if (id === 'ni_cat') showNext('ni_cat', 'ni_code');
  if (id === 'p_cat' && $('#im_code_h')) showNext('p_cat', 'im_code_h');
  if (id === 'as_loc') { AS.f.loc = t_.value; drawAssets(); }
  if (id === 'as_st') { AS.f.status = t_.value; drawAssets(); }
  if (id === 'im_type') {           // the form follows the type defaults (the person can still change each flag)
    const d = typeRow(t_.value), fixed = fixedType(t_.value), set = (i, on, dis) => { const b = $('#' + i); if (b) { b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); b.textContent = on ? t('on') : t('off'); b.disabled = !!dis; } };
    if (d) { set('im_count_f', t_.value === 'asset' ? false : d.count_in_business, t_.value === 'asset'); set('im_sell_f', fixed ? false : d.sellable, fixed); const f = $('#im_fixed'); if (f) { f.hidden = !fixed; f.textContent = T('f_fixed'); } }
  }
  if (t_.dataset && t_.dataset.imcm) { const { error } = await sb.rpc('item_class_map_set', { p_class: t_.dataset.imcm, p_type: t_.value, p_active: true }); if (error) return fail(error); await refresh(); toast(T('saved')); }
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { itemimport: viewImport, itemmap: viewMap, itemtypes: viewTypes, assets: viewAssets });
B.itemMaster = { errMsg, init, on: () => M.master, canNew, canFlag, types: () => M.types, typeLabel, formHTML, formPatch, rowMenu, newItemSheet, byCategory, nextCodeLocal, showNext, catNo, fixedType };
// start loading the settings tables once the user is signed in (the pages above call init() themselves)
window.addEventListener('hashchange', () => { if (S.ctx && !M.p) init(); });
})();
