/* Islamia BOS · Category / Sub-category everywhere (phase 100, bos100). One two-level master (table item_categories); items.category / items.sub_category stay the text columns.
   B.catpick  - load / tree / label / name, the chip + select picker (mount), the pair helpers (subSelect, field, read), bulkSheet (set the Category of many items),
                the guarded enhancers that put a Category + Sub-category filter on the item pickers of other screens (purchase lines, stock issue / transfer / count / wastage / production,
                recipes, forms, online orders) and keep the Sub-category list of the item editor in step with its Category.
   B.catfilter(items, sel) - sel = { cat, sub, none }. Works on rows that carry category / sub_category, or on rows that only carry an item id / code.
   Pages:  #/categories (manage the tree: add, rename, merge, reorder, deactivate, move items; the rule category_required_on_item)   #/catreport (sales and stock value by Category / Sub-category, CSV)
   Server: supabase/phase100.sql (category_list, category_save, category_rename, category_merge, category_move, category_reorder, item_set_category, item_set_category_bulk, category_sync100,
   category_rule_state, items_missing_category, biz_items_by_category, stock_valuation_by_category). Without phase100 the tree is built from the items themselves and everything still works (read only).
   Every handler is prefixed cat_. Nothing here edits another screen's text. Loaded last. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const q2 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));

const X = {
  title: L('ক্যাটাগরি ও সাব-ক্যাটাগরি', 'Categories and sub-categories', 'Category ও Sub-category'),
  intro: L('প্রতিটি আইটেমের একটি ক্যাটাগরি ও সাব-ক্যাটাগরি থাকবে। এখান থেকে যোগ, নাম বদল, একত্র (merge), ক্রম ঠিক ও বন্ধ করা যায়।', 'Every item has a Category and a Sub-category. Add, rename, merge, reorder or switch them off here.', 'প্রতিটি Item-এর একটি Category ও Sub-category থাকবে। এখান থেকে add, rename, merge, ক্রম ঠিক ও বন্ধ করা যায়।'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  noFn: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase100 বাকি)', 'The database part for this is not installed yet (phase100 is missing)', 'এই অংশের database এখনও চালু হয়নি (phase100 বাকি)'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), close: L('বন্ধ', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), save: L('সেভ', 'Save', 'Save'), apply: L('অ্যাপ্লাই', 'Apply', 'Apply'),
  cat: L('ক্যাটাগরি', 'Category', 'Category'), sub: L('সাব-ক্যাটাগরি', 'Sub-category', 'Sub-category'), item: L('আইটেম', 'Item', 'Item'), items: L('আইটেম', 'Items', 'Items'),
  all: L('সব', 'All', 'All'), noCat: L('ক্যাটাগরি নেই', 'No category', 'Category নেই'), noSub: L('সাব-ক্যাটাগরি নেই', 'No sub-category', 'Sub-category নেই'),
  pickCat: L('ক্যাটাগরি বাছুন', 'Choose a Category', 'Category বাছুন'), pickSub: L('সাব-ক্যাটাগরি বাছুন', 'Choose a Sub-category', 'Sub-category বাছুন'),
  nItems: L('টি আইটেম', 'items', 'টি Item'), inactive: L('বন্ধ', 'Inactive', 'Inactive'),
  addCat: L('+ ক্যাটাগরি যোগ', '+ Add a Category', '+ Category যোগ'), addSub: L('+ সাব-ক্যাটাগরি যোগ', '+ Add a Sub-category', '+ Sub-category যোগ'),
  nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nameEn: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  rename: L('নাম বদল (মালিক)', 'Rename (owner)', 'Rename (owner)'), merge: L('অন্যটির সাথে একত্র (মালিক)', 'Merge into another (owner)', 'অন্যটির সাথে merge (owner)'),
  mergeInto: L('যেটার মধ্যে একত্র হবে', 'Merge into', 'যেটার মধ্যে merge হবে'),
  mergeHint: L('সব আইটেম ওই ক্যাটাগরি-তে চলে যাবে, এটি বন্ধ হবে। ফেরানো যায় না — শুধু আইটেম আলাদা করে সরানো যায়।', 'Every item moves there and this one is switched off. It cannot be undone; items can only be moved one by one afterwards.', 'সব Item ওই Category-তে চলে যাবে, এটি বন্ধ হবে। ফেরানো যায় না।'),
  mergeDone: L('একত্র হয়েছে', 'Merged', 'Merge হয়েছে'), movedN: L('টি আইটেম সরেছে', 'items moved', 'টি Item সরেছে'),
  moveItems: L('আইটেম সরান', 'Move items', 'Item সরান'), moveSub: L('অন্য ক্যাটাগরি-তে নিন', 'Move under another Category', 'অন্য Category-তে নিন'),
  moveTo: L('যেখানে সরবে', 'Move to', 'যেখানে সরবে'), moveDone: L('সরানো হয়েছে', 'Moved', 'সরানো হয়েছে'),
  off: L('বন্ধ করুন', 'Switch off', 'বন্ধ করুন'), on: L('চালু করুন', 'Switch on', 'চালু করুন'), up: L('ওপরে', 'Move up', 'ওপরে'), down: L('নিচে', 'Move down', 'নিচে'),
  more: L('আরও', 'More', 'আরও'),
  ruleTitle: L('ক্যাটাগরি লাগবে কি?', 'Is a Category needed?', 'Category লাগবে কি?'),
  r_off: L('বন্ধ — আগের মতো', 'Off - as before', 'Off — আগের মতো'), r_warn: L('সতর্কতা — তালিকা দেখায়, আটকায় না (প্রস্তাবিত)', 'Warn - lists the items, never blocks (recommended)', 'Warn — তালিকা দেখায়, আটকায় না (recommended)'),
  r_required: L('জরুরি — নতুন আইটেম ক্যাটাগরি ছাড়া সেভ হবে না', 'Required - a new item cannot be saved without one', 'Required — নতুন Item Category ছাড়া save হবে না'),
  ruleOwner: L('শুধু মালিক বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner বদলাতে পারেন'),
  missing: L('ক্যাটাগরি ছাড়া আইটেম', 'Items without a Category', 'Category ছাড়া Item'), missingNone: L('সব আইটেমের ক্যাটাগরি আছে ✓', 'Every item has a Category ✓', 'সব Item-এর Category আছে ✓'),
  missSub: L('সাব-ক্যাটাগরি ছাড়া আইটেম', 'Items without a Sub-category', 'Sub-category ছাড়া Item'),
  setFor: L('বাছাই করা আইটেমের ক্যাটাগরি ঠিক করুন', 'Set the Category of the selected items', 'বাছাই করা Item-এর Category ঠিক করুন'),
  selAll: L('সব বাছুন', 'Select all', 'সব বাছুন'), nSel: L('টি বাছা', 'selected', 'টি বাছা'), needItems: L('আগে আইটেম বাছুন', 'Choose items first', 'আগে Item বাছুন'),
  needCat: L('ক্যাটাগরি বাছুন', 'Choose a Category', 'Category বাছুন'),
  reqHint: L('ক্যাটাগরি লাগবেই', 'A Category is required', 'Category লাগবেই'), warnHint: L('ক্যাটাগরি দেওয়া ভালো', 'A Category is recommended', 'Category দেওয়া ভালো'),
  rpTitle: L('ক্যাটাগরি অনুযায়ী রিপোর্ট', 'Report by Category', 'Category অনুযায়ী report'), rpSales: L('সেল', 'Sales', 'Sales'), rpStock: L('স্টকের মূল্য', 'Stock value', 'Stock value'),
  rpFrom: L('থেকে', 'From', 'From'), rpTo: L('পর্যন্ত', 'To', 'To'), rpLevel: L('স্তর', 'Level', 'Level'), rpByCat: L('ক্যাটাগরি', 'Category', 'Category'), rpBySub: L('ক্যাটাগরি ও সাব-ক্যাটাগরি', 'Category + Sub-category', 'Category + Sub-category'),
  rpRun: L('দেখান', 'Show', 'Show'), rpRev: L('বিক্রি (৳)', 'Revenue', 'Revenue (৳)'), rpCost: L('কস্ট (৳)', 'Cost', 'Cost (৳)'), rpShare: L('অংশ %', 'Share %', 'Share %'), rpVal: L('মূল্য (৳)', 'Value', 'Value (৳)'),
  rpTotal: L('টোটাল', 'Total', 'Total'), rpUnk: L('কস্ট অজানা আইটেম', 'items with unknown cost', 'cost অজানা Item'), rpNoCost: L('কস্ট দেখার অনুমতি নেই, তাই কস্ট ফাঁকা', 'No cost right, so cost is blank', 'Cost দেখার অধিকার নেই, তাই cost ফাঁকা'),
  rpCsv: L('CSV নামান', 'Download CSV', 'CSV download'), rpNone: L('এই সময়ে কিছু নেই', 'Nothing in this period', 'এই সময়ে কিছু নেই'), rpManage: L('ক্যাটাগরি পাতা', 'Category page', 'Category page'),
  rpUncat: L('(ক্যাটাগরি নেই)', '(no category)', '(Category নেই)'),
};
const T = (k) => lab(X[k]);
const ERR = {
  name_taken: L('এই নামে আগেই আছে', 'That name is already used here', 'এই নামে আগেই আছে'), name_required: L('নাম লিখুন', 'Enter a name', 'নাম লিখুন'),
  same_level_only: L('ক্যাটাগরি-র সাথে ক্যাটাগরি, সাব-ক্যাটাগরি-র সাথে সাব-ক্যাটাগরি একত্র হয়', 'A Category merges with a Category and a Sub-category with a Sub-category', 'Category-র সাথে Category, Sub-category-র সাথে Sub-category merge হয়'),
  bad_parent: L('এই ক্যাটাগরি বাছা যায় না', 'This Category cannot be used', 'এই Category বাছা যায় না'), sub_exists: L('ওই ক্যাটাগরি-তে একই সাব-ক্যাটাগরি আছে', 'That Category already has this Sub-category', 'ওই Category-তে একই Sub-category আছে'),
  category_required: L('ক্যাটাগরি লাগবে (নিয়ম: জরুরি)', 'A Category is required (rule: required)', 'Category লাগবে (rule: required)'),
  sub_category_required: L('এই ক্যাটাগরি-র সাব-ক্যাটাগরি বাছুন (নিয়ম: জরুরি)', 'Choose a Sub-category of this Category (rule: required)', 'এই Category-র Sub-category বাছুন (rule: required)'),
  merged: L('একত্র হয়ে যাওয়াটি আবার চালু হয় না', 'A merged one cannot be switched on again', 'Merge হওয়াটি আবার চালু হয় না'), target_inactive: L('যেটার মধ্যে একত্র হবে সেটি বন্ধ', 'The target is switched off', 'Target বন্ধ'),
  bad_category: L('ক্যাটাগরি ঠিক নয়', 'The Category is not valid', 'Category ঠিক নয়'), bad_sub_category: L('এই সাব-ক্যাটাগরি ওই ক্যাটাগরি-র নয়', 'That Sub-category does not belong to the Category', 'এই Sub-category ওই Category-র নয়'),
  bad_request: L('অনুরোধ ঠিক নয়', 'The request is not valid', 'Request ঠিক নয়'), bad_level: L('স্তর ঠিক নয়', 'The level is not valid', 'Level ঠিক নয়'),
  bad_range: L('ডেটের সীমা ঠিক নয় (সর্বোচ্চ ৪০০ দিন)', 'Date range is not valid (400 days at most)', 'date-এর range ঠিক নয় (সর্বোচ্চ ৪০০ দিন)'),
};
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/function .* does not exist|schema cache|Could not find/i.test(m)) return toast(T('noFn')); return fail(e); };
const call = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };

// ---------- data ----------
// the five names the shop already shows in English (pos.js / items2.js / app.js); nothing else is invented
const LEG = { sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'), cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)') };
const C = { tree: null, byCat: new Map(), byId: new Map(), byCode: new Map(), items: [], master: false, rule: null, loading: null, mgr: null, ver: 0 };
const nameOf = (r) => { const leg = LEG[r.code] && !r.parent_id ? LEG[r.code] : null; return { bn: r.name_bn || r.code, en: r.name_en || (leg && leg.en) || r.name_bn || r.code, mix: r.name_mix || (leg && leg.mix) || r.name_bn || r.code, hasEn: !!(r.name_en || leg) }; };
function buildTree(rows, items) {
  const cats = [], by = new Map();
  if (rows) {
    rows.filter((r) => !r.parent_id).forEach((r) => { const c = { id: r.id, code: r.code, name: nameOf(r), sort: r.sort, active: r.active !== false, n: Number(r.item_count) || 0, subs: [] }; cats.push(c); by.set(r.id, c); });
    rows.filter((r) => r.parent_id).forEach((r) => { const p = by.get(r.parent_id); if (p) p.subs.push({ id: r.id, code: r.code, name: nameOf(r), sort: r.sort, active: r.active !== false, n: Number(r.item_count) || 0, parent: p.id }); });
  } else {      // no phase100: built from the items (read only)
    const seen = new Map();
    items.forEach((i) => { const cc = (i.category || '').trim(); if (!cc) return; let c = seen.get(cc); if (!c) { c = { id: null, code: cc, name: nameOf({ code: cc, name_bn: i.category_bn || cc }), sort: 0, active: true, n: 0, subs: [] }; seen.set(cc, c); cats.push(c); }
      c.n++; const sc = (i.sub_category || '').trim(); if (sc) { let s = c.subs.find((x) => x.code === sc); if (!s) { s = { id: null, code: sc, name: { bn: sc, en: sc, mix: sc }, sort: 0, active: true, n: 0, parent: null }; c.subs.push(s); } s.n++; } });
  }
  return cats;
}
async function load(force) {
  if (C.tree && !force) return C;
  if (!S.ctx) return C;   // not signed in yet: nothing to read, nothing cached
  if (C.loading && !force) return C.loading;
  C.loading = (async () => {
    let rows = null, items = [];
    try { const r = await sb.rpc('category_list', { p_include_inactive: false }); if (r && !r.error && Array.isArray(r.data)) rows = r.data; } catch (e) { rows = null; }
    try { const r = await window.BOS_ALL(sb.from('items').select('id,code,category,category_bn,sub_category').order('code')); items = (r && r.data) || []; } catch (e) { items = []; }
    C.items = items; C.master = !!rows; C.tree = buildTree(rows, items);
    C.byCat = new Map(C.tree.map((c) => [c.code, c])); C.byId = new Map(items.map((i) => [i.id, i])); C.byCode = new Map(items.map((i) => [i.code, i]));
    C.ver++; C.loading = null; return C;
  })();
  return C.loading;
}
async function loadRule() { try { C.rule = await call('category_rule_state'); } catch (e) { C.rule = null; } return C.rule; }
const reload = async () => { await load(true); scan(); };
const catByCode = (code) => (C.byCat && C.byCat.get(code)) || null;
const subByCode = (cat, sub) => { const c = catByCode(cat); return c ? c.subs.find((s) => s.code === sub) || null : null; };
// name of a Category / Sub-category in the current language; null when the tree does not know it (callers keep their own text then)
const name = (code) => { const c = catByCode(code); return c ? lab(c.name) : null; };
const subName = (cat, sub) => { const s = subByCode(cat, sub); return s ? lab(s.name) : null; };
// the master name only when it exists in the current language (so a screen's own old English text is never replaced by a Bangla one)
const nameIfKnown = (code) => { const c = catByCode(code); if (!c) return null; if (S.lang === 'en' && !c.name.hasEn) return null; return lab(c.name); };
function keyOf(i) {
  const m = (i.item_id && C.byId.get(i.item_id)) || (i.id && C.byId.get(i.id)) || (i.code && C.byCode.get(i.code)) || {};
  return { cat: String(i.category !== undefined && i.category !== null ? i.category : (m.category || '')).trim(), sub: String(i.sub_category !== undefined && i.sub_category !== null ? i.sub_category : (m.sub_category || '')).trim() };
}
function label(i) { const k = keyOf(i); if (!k.cat) return ''; return (name(k.cat) || k.cat) + (k.sub ? ' · ' + (subName(k.cat, k.sub) || k.sub) : ''); }
function catfilter(items, sel) {
  sel = sel || {}; if (!sel.cat && !sel.sub && !sel.none) return items;
  return items.filter((i) => { const k = keyOf(i); if (sel.none) return !k.cat; if (sel.cat && k.cat !== sel.cat) return false; if (sel.sub && k.sub !== sel.sub) return false; return true; });
}

// ---------- remembered last choice (per picker, per browser) ----------
const memGet = (id) => { try { const o = JSON.parse(localStorage.getItem('bos.catpick') || '{}'); return o[id] || null; } catch (e) { return null; } };
const memSet = (id, v) => { try { const o = JSON.parse(localStorage.getItem('bos.catpick') || '{}'); o[id] = v; localStorage.setItem('bos.catpick', JSON.stringify(o)); } catch (e) { /* private window: no memory */ } };

// ---------- the picker widget (chips for a few, a select for many) ----------
const W = {};
const MAXCHIPS = 8;
function row(kind, id, opts, cur) {
  if (opts.length > MAXCHIPS) return `<select class="cat-sel" data-catw="${esc(id)}" data-lvl="${kind}" aria-label="${esc(T(kind))}">${opts.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
  return opts.map(([v, l]) => `<button type="button" class="tog cat-chip ${String(v) === String(cur) ? 'on' : ''}" data-act="${kind === 'cat' ? 'cat_c' : 'cat_s'}" data-w="${esc(id)}" data-v="${esc(v)}">${esc(l)}</button>`).join('');
}
function widgetHTML(id) {
  const w = W[id], sel = w.sel, cats = (C.tree || []).filter((c) => c.active !== false);
  const o1 = [['', T('all')]].concat(cats.map((c) => [c.code, lab(c.name)]), w.none ? [['_none', T('noCat')]] : []);
  const cur = sel.none ? '_none' : sel.cat || '';
  const c = sel.cat ? catByCode(sel.cat) : null, subs = c ? c.subs.filter((s) => s.active !== false) : [];
  return `<div class="cat-w" data-w="${esc(id)}"><div class="row wrap cat-r1" role="group" aria-label="${esc(T('cat'))}">${row('cat', id, o1, cur)}</div>${subs.length ? `<div class="row wrap cat-r2" role="group" aria-label="${esc(T('sub'))}">${row('sub', id, [['', T('all')]].concat(subs.map((s) => [s.code, lab(s.name)])), sel.sub || '')}</div>` : ''}</div>`;
}
function paint(id) { const w = W[id]; if (!w || !w.host) return; w.host.innerHTML = widgetHTML(id); }
function setSel(id, patch) {
  const w = W[id]; if (!w) return;
  const n = Object.assign({}, w.sel, patch);
  if (n.none) { n.cat = ''; n.sub = ''; }
  if (patch.cat !== undefined && patch.sub === undefined) n.sub = '';
  w.sel = { cat: n.cat || '', sub: n.sub || '', none: !!n.none };
  if (w.remember) memSet(id, w.sel);
  paint(id);
  if (w.onChange) w.onChange(Object.assign({}, w.sel));
}
// mount the two-level picker into host. o: { id, sel, none, remember, onChange }. The tree is loaded first (once).
async function mount(host, o) {
  o = o || {}; const id = o.id || ('w' + Object.keys(W).length);
  await load();
  const last = o.remember ? memGet(id) : null;
  const sel = Object.assign({ cat: '', sub: '', none: false }, last || {}, o.sel || {});
  if (sel.cat && !catByCode(sel.cat)) { sel.cat = ''; sel.sub = ''; }
  W[id] = { host, sel, none: !!o.none, remember: !!o.remember, onChange: o.onChange };
  paint(id); return { id, get: () => Object.assign({}, W[id].sel), set: (p) => setSel(id, p) };
}
// pair helpers for forms: a Sub-category select that follows a Category select
function subOptions(cat, cur, allLabel) {
  const c = cat ? catByCode(cat) : null, subs = c ? c.subs.filter((s) => s.active !== false || s.code === cur) : [];
  return `<option value="">${esc(allLabel || T('all'))}</option>` + subs.map((s) => `<option value="${esc(s.code)}" ${s.code === cur ? 'selected' : ''}>${esc(lab(s.name))}</option>`).join('');
}
function subSelect(id, cat, cur, forId, allLabel) {
  return `<div><label for="${esc(id)}">${esc(T('sub'))}</label><select id="${esc(id)}" data-cat-for="${esc(forId)}" data-cat-cur="${esc(cur || '')}" data-cat-all="${esc(allLabel || '')}">${C.tree ? subOptions(cat, cur, allLabel) : `<option value="">${esc(allLabel || T('all'))}</option>`}</select></div>`;
}
function catOptions(cur, allLabel, withNone) {
  return `<option value="">${esc(allLabel === undefined ? T('all') : allLabel)}</option>` + ((C.tree || []).filter((c) => c.active !== false || c.code === cur).map((c) => `<option value="${esc(c.code)}" ${c.code === cur ? 'selected' : ''}>${esc(lab(c.name))}</option>`).join('')) + (withNone ? `<option value="_none">${esc(T('noCat'))}</option>` : '');
}
// a Category + Sub-category pair of selects (selectable, never typed): field('x', {cat, sub}) -> read('x')
function field(p, cur, o) {
  cur = cur || {}; o = o || {};
  if (!C.tree) load().then(() => { $$('select[data-catpair]').forEach((c) => { if (c.options.length <= 1) c.innerHTML = catOptions(cur.cat, '—'); }); scan(); }).catch(() => {});
  return `<div class="stack cat-field"><div><label for="${esc(p)}_c">${esc(o.catLabel || T('cat'))}</label><select id="${esc(p)}_c" data-catpair="${esc(p)}">${catOptions(cur.cat, '—')}</select></div>
    <div><label for="${esc(p)}_s">${esc(T('sub'))}</label><select id="${esc(p)}_s" data-cat-for="${esc(p)}_c" data-cat-cur="${esc(cur.sub || '')}" data-cat-all="—">${subOptions(cur.cat, cur.sub, '—')}</select></div></div>`;
}
function read(p) { const c = $('#' + p + '_c'), s = $('#' + p + '_s'); return { cat: c ? c.value : '', sub: s ? s.value : '' }; }
const idOfCat = (code) => { const c = catByCode(code); return c ? c.id : null; };
const idOfSub = (cat, sub) => { const s = subByCode(cat, sub); return s ? s.id : null; };

// ---------- guarded enhancers for the item pickers of other screens ----------
// datalist pickers: the value of an option is "CODE · name"; a bar with a Category and a Sub-category select filters the options and every option shows its Category in the hint
const DL = 'datalist#pu_dl, datalist#rl_dl, datalist#rc_idl, datalist#pk_pl, datalist#pk_il, datalist#dp_dl, datalist#dl_items, datalist[id$="_item_dl"]';
const SELP = 'select[data-sxl="item"]';
const orig = new WeakMap();
function codeOfOpt(v) { return String(v || '').split(' · ')[0].trim(); }
function applyDL(dl, sel) {
  let o = orig.get(dl); if (!o) { o = [...dl.querySelectorAll('option')].map((x) => x.getAttribute('value')); orig.set(dl, o); }
  const keep = o.filter((v) => { const it = C.byCode.get(codeOfOpt(v)); return !it || !!catfilter([it], sel).length; });
  dl.innerHTML = keep.map((v) => { const it = C.byCode.get(codeOfOpt(v)), lb = it ? label(it) : ''; return `<option value="${esc(v)}"${lb ? ` label="${esc(lb)}"` : ''}></option>`; }).join('');
}
function applySEL(sels, sel) {
  sels.forEach((s) => {
    const cur = s.value; if (!s.__catOrig) s.__catOrig = [...s.options].map((x) => ({ v: x.value, t: x.textContent }));
    s.innerHTML = s.__catOrig.filter((x) => x.v === cur || !x.v || !!catfilter([{ id: x.v }], sel).length).map((x) => `<option value="${esc(x.v)}" ${x.v === cur ? 'selected' : ''}>${esc(x.t)}</option>`).join('');
  });
}
function barHTML(key, sel) {
  return `<div class="row cat-bar" data-catbar="${esc(key)}"><select data-catbar-c="${esc(key)}" aria-label="${esc(T('cat'))}">${catOptions(sel.cat, T('cat') + ': ' + T('all'))}</select><select data-catbar-s="${esc(key)}" aria-label="${esc(T('sub'))}">${subOptions(sel.cat, sel.sub, T('sub') + ': ' + T('all'))}</select></div>`;
}
const BARS = {};
function refreshBar(key) {
  const b = BARS[key]; if (!b) return;
  const sel = b.sel; if (b.memKey) memSet(b.memKey, sel);
  if (b.dl && b.dl.isConnected) applyDL(b.dl, sel);
  if (b.sels) applySEL($$(SELP), sel);
}
function attachDL(dl) {
  if (dl.dataset.cat100) return; dl.dataset.cat100 = '1';
  if (!(C.tree || []).length) return;
  const key = 'dl:' + dl.id, last = memGet(key) || {}, sel = { cat: catByCode(last.cat) ? last.cat : '', sub: '' }; if (sel.cat && last.sub && subByCode(sel.cat, last.sub)) sel.sub = last.sub;
  BARS[key] = { sel, dl, memKey: key };
  const bar = document.createElement('div'); bar.innerHTML = barHTML(key, sel); const el = bar.firstChild;
  const inp = document.querySelector('input[list="' + dl.id + '"]'), lb = inp && inp.id ? document.querySelector('label[for="' + inp.id + '"]') : null;
  if (lb && lb.parentElement && lb.parentElement.contains(dl)) lb.parentElement.parentElement.insertBefore(el, lb.parentElement); else dl.insertAdjacentElement('afterend', el);
  applyDL(dl, sel);
}
function attachSEL() {
  const fresh = $$(SELP).filter((s) => !s.dataset.cat100); if (!fresh.length) return;
  fresh.forEach((s) => { s.dataset.cat100 = '1'; });
  if (!(C.tree || []).length) return;
  const key = 'sel:item'; let b = BARS[key];
  if (!b || !document.querySelector('[data-catbar="' + key + '"]')) {   // a new form: a new bar (starts from the remembered choice)
    const last = memGet(key) || {}, sel = { cat: catByCode(last.cat) ? last.cat : '', sub: '' }; if (sel.cat && last.sub && subByCode(sel.cat, last.sub)) sel.sub = last.sub;
    b = BARS[key] = { sel, sels: true, memKey: key };
    const wrap = fresh[0].closest('#sx_lines') || fresh[0].parentElement, bar = document.createElement('div'); bar.innerHTML = barHTML(key, sel);
    wrap.parentElement.insertBefore(bar.firstChild, wrap);
  }
  applySEL(fresh, b.sel);   // lines added later are filtered with the same choice
}
// Sub-category selects that follow a Category select (data-cat-for) and the item editor's own pair (#p_cat / #p_sub)
function fillSub(s) {
  const forId = s.getAttribute('data-cat-for'), cs = forId && document.getElementById(forId); if (!cs) return;
  const cur = s.getAttribute('data-cat-cur') || s.value || '';
  s.innerHTML = subOptions(cs.value === '_none' ? '' : cs.value, cur, s.getAttribute('data-cat-all') || undefined); s.dataset.catFilled = String(C.ver);
}
function followEditor(reset) {
  const cs = document.getElementById('p_cat'), ss = document.getElementById('p_sub'); if (!cs || !ss) return;
  // the app turns every select into a button that lists ALL its options (hidden ones too), so the options are really removed and put back
  const had = ss.__catOrig || []; [...ss.options].forEach((o) => { if (!had.some((x) => x.v === o.value)) had.push({ v: o.value, t: o.textContent }); }); ss.__catOrig = had;
  const c = catByCode(cs.value), allowed = c && c.subs.length ? new Set(c.subs.map((x) => x.code)) : null;
  let cur = ss.value; if (reset && allowed && cur && !allowed.has(cur)) cur = '';
  const keep = had.filter((o) => !o.v || !allowed || allowed.has(o.v) || o.v === cur);
  ss.innerHTML = keep.map((o) => `<option value="${esc(o.v)}" ${o.v === cur ? 'selected' : ''}>${esc(o.t)}</option>`).join('');
  followRule(cs);
}
function followRule(cs) {
  const m = C.rule && C.rule.mode; let h = document.getElementById('cat_reqhint');
  if (!m || m === 'off') { if (h) h.remove(); return; }
  if (!cs.value) { if (!h) { h = document.createElement('div'); h.id = 'cat_reqhint'; h.className = 'hint'; cs.parentElement.appendChild(h); } h.textContent = T(m === 'required' ? 'reqHint' : 'warnHint'); } else if (h) h.remove();
}
let busy = false, again = false;
function scan() {
  if (!C.tree) return;
  if (busy) { again = true; return; } busy = true;
  try {
    $$(DL).forEach(attachDL);
    attachSEL();
    $$('select[data-cat-for]').forEach((s) => { if (s.dataset.catFilled !== String(C.ver)) fillSub(s); });
    $$('select[data-cfr-c]').forEach((cs) => { const k = cs.getAttribute('data-cfr-c'), fr = FR[k], ss = document.querySelector('[data-cfr-s="' + k + '"]'); if (!fr || cs.dataset.cfrFilled === String(C.ver)) return;
      cs.innerHTML = catOptions(fr.sel.cat, T('cat') + ': ' + T('all')); if (ss) ss.innerHTML = subOptions(fr.sel.cat, fr.sel.sub, T('sub') + ': ' + T('all')); cs.dataset.cfrFilled = String(C.ver); });
    if (document.getElementById('p_sub') && !document.getElementById('p_sub').dataset.cat100) { document.getElementById('p_sub').dataset.cat100 = '1'; followEditor(); }
  } finally { busy = false; }
  if (again) { again = false; setTimeout(scan, 0); }
}
document.addEventListener('change', (e) => {
  const t = e.target; if (!t || !t.getAttribute) return;
  if (t.hasAttribute('data-catbar-c')) { const k = t.getAttribute('data-catbar-c'), b = BARS[k]; if (!b) return; b.sel = { cat: t.value, sub: '' }; const sub = document.querySelector('[data-catbar-s="' + k + '"]'); if (sub) sub.innerHTML = subOptions(t.value, '', T('sub') + ': ' + T('all')); refreshBar(k); return; }
  if (t.hasAttribute('data-catbar-s')) { const k = t.getAttribute('data-catbar-s'), b = BARS[k]; if (!b) return; b.sel = { cat: b.sel.cat, sub: t.value }; refreshBar(k); return; }
  if (t.hasAttribute('data-cfr-c') || t.hasAttribute('data-cfr-s')) { filterChanged(t); return; }
  if (t.hasAttribute('data-catw')) { const id = t.getAttribute('data-catw'); if (t.getAttribute('data-lvl') === 'cat') setSel(id, t.value === '_none' ? { none: true } : { cat: t.value, none: false }); else setSel(id, { sub: t.value }); return; }
  if (t.hasAttribute('data-cat-for')) t.setAttribute('data-cat-cur', t.value);
  if (t.id) { $$('select[data-cat-for="' + t.id + '"]').forEach((s) => { s.setAttribute('data-cat-cur', ''); fillSub(s); }); if (t.id === 'p_cat') followEditor(true); }
});
let tmr = null;
try { if (window.MutationObserver && document.body) new MutationObserver((recs) => { if (recs.every((r) => r.target.closest && r.target.closest('#pos_items'))) return; /* bos114: POS cards hold no category list */ if (tmr) return; tmr = setTimeout(() => { tmr = null; scan(); }, 60); }).observe(document.body, { childList: true, subtree: true }); } catch (e) { /* no observer: the filters are simply not added */ }

// a ready-made Category + Sub-category filter row for any list: filterRow(id, sel, act). On change the screen's own handler H[act] gets an element-like { dataset: { cat, sub, w } }.
const FR = {};
function filterRow(id, sel, act) {
  sel = sel || {}; FR[id] = { act, sel: { cat: sel.cat || '', sub: sel.sub || '' } };
  if (!C.tree) load().then(scan).catch(() => {});   // the lists are filled as soon as the tree is there
  return `<div class="row cat-bar" data-cfr="${esc(id)}"><select data-cfr-c="${esc(id)}" aria-label="${esc(T('cat'))}">${catOptions(sel.cat, T('cat') + ': ' + T('all'))}</select><select data-cfr-s="${esc(id)}" aria-label="${esc(T('sub'))}">${subOptions(sel.cat, sel.sub, T('sub') + ': ' + T('all'))}</select></div>`;
}
function filterChanged(t) {
  const k = t.getAttribute('data-cfr-c') || t.getAttribute('data-cfr-s'), fr = FR[k]; if (!fr) return;
  const cs = document.querySelector('[data-cfr-c="' + k + '"]'), ss = document.querySelector('[data-cfr-s="' + k + '"]');
  const isCat = t.hasAttribute('data-cfr-c'); const cat = cs ? cs.value : '', sub = isCat ? '' : (ss ? ss.value : '');
  if (isCat && ss) ss.innerHTML = subOptions(cat, '', T('sub') + ': ' + T('all'));
  fr.sel = { cat, sub };
  if (H[fr.act]) Promise.resolve(H[fr.act]({ dataset: { cat, sub, w: k } })).catch(fail);
}

// ---------- chips for the POS grid and the like ----------
// Sub-category chips for one Category: the screen keeps its own state and handler (act)
function subChips(items, cat, sub, act) {
  const c = cat && cat !== '_f' ? catByCode(cat) : null; if (!c) return '';
  const have = new Set((items || []).filter((i) => (i.category || '') === cat).map((i) => i.sub_category).filter(Boolean));
  const subs = c.subs.filter((s) => s.active !== false && have.has(s.code)); if (!subs.length) return '';
  return `<div class="row wrap" style="margin:-4px 0 10px" role="group" aria-label="${esc(T('sub'))}">${[['', T('all')]].concat(subs.map((s) => [s.code, lab(s.name)])).map(([v, l]) => `<button type="button" class="tog ${sub === v ? 'on' : ''}" data-act="${esc(act)}" data-v="${esc(v)}">${esc(l)}</button>`).join('')}</div>`;
}

// ---------- set the Category of many items ----------
let BULK = null;
async function bulkSheet(ids, done) {
  if (!ids || !ids.length) return toast(T('needItems'));
  await load();
  BULK = { ids: ids.slice(), done };
  openSheet(`<h2>${esc(T('setFor'))}</h2><div class="stack"><div class="muted">${ids.length} ${esc(T('nSel'))}</div>${field('cb')}
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cat_bulk_go">${esc(T('apply'))}</button></div></div>`);
  fillAll();
}
const fillAll = () => $$('select[data-cat-for]').forEach(fillSub);

// ---------- #/categories ----------
const P = { can: false, owner: false, rows: [], open: null, missing: null, sel: new Set() };
async function probeCan() {
  P.owner = !!(S.ctx && S.ctx.is_owner); P.can = P.owner;
  if (!P.owner) { for (const c of ['item_create', 'item_bulk']) { try { const r = await sb.rpc('has_grant', { p_code: c }); if (r && !r.error && r.data === true) P.can = true; } catch (e) { /* no grant */ } } }
}
const catNum = (n) => `${T('items')}: ${n}`;
function findNode(id) { for (const c of C.tree || []) { if (String(c.id) === String(id)) return { c, s: null, node: c }; for (const s of c.subs) if (String(s.id) === String(id)) return { c, s, node: s }; } return null; }
function treeHTML() {
  return (C.tree || []).map((c) => `<div class="card cat-card"><div class="row between"><div><b>${esc(lab(c.name))}</b> <span class="chip">${esc(catNum(c.n))}</span></div>${P.can && c.id ? `<button type="button" class="mini" data-act="cat_menu" data-id="${c.id}" aria-label="${esc(T('more'))}">⋮</button>` : ''}</div>
    ${c.subs.map((s) => `<div class="row between cat-sub"><span>${esc(lab(s.name))} <span class="muted">· ${esc(catNum(s.n))}</span></span>${P.can && s.id ? `<button type="button" class="mini" data-act="cat_menu" data-id="${s.id}" aria-label="${esc(T('more'))}">⋮</button>` : ''}</div>`).join('')}</div>`).join('') || `<p class="muted center">${esc(T('none'))}</p>`;
}
function ruleHTML() {
  const r = C.rule; if (!r) return '';
  const modes = ['off', 'warn', 'required'];
  return `<div class="card stack"><b>${esc(T('ruleTitle'))}</b>
    ${P.owner ? `<select id="cat_mode" data-catrule="1" aria-label="${esc(T('ruleTitle'))}">${modes.map((m) => `<option value="${m}" ${r.mode === m ? 'selected' : ''}>${esc(T('r_' + m))}</option>`).join('')}</select>` : `<div class="chip">${esc(T('r_' + r.mode))}</div><div class="muted">${esc(T('ruleOwner'))}</div>`}
    <div class="row between wrap"><span>${esc(T('missing'))}: <b>${Number(r.missing) || 0}</b>${Number(r.missing_sub) ? ` · ${esc(T('missSub'))}: <b>${Number(r.missing_sub)}</b>` : ''}</span>${P.can && (Number(r.missing) || Number(r.missing_sub)) ? `<button type="button" class="mini" data-act="cat_missing">${esc(T('setFor'))}</button>` : ''}</div></div>`;
}
async function catView() {
  shell(T('title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, 'home');
  await probeCan(); await load(true); await loadRule();
  drawCat();
}
function drawCat() {
  shell(T('title'), `<div class="card stack"><div class="muted">${esc(T('intro'))}</div>${P.can ? `<div class="row wrap"><button type="button" class="primary" data-act="cat_add">${esc(T('addCat'))}</button></div>` : ''}${!C.master ? `<div class="notice warn">${esc(T('noFn'))}</div>` : ''}</div>
    ${ruleHTML()}<a class="mini" href="#/catreport">${esc(T('rpManage'))} ›</a><div id="cat_tree">${treeHTML()}</div>`, 'home');
}
const redraw = async () => { await load(true); await loadRule(); if (/^#\/categories/.test(location.hash)) drawCat(); scan(); };
function nameSheet(title, nb, ne, go, id) {
  openSheet(`<h2>${esc(title)}</h2><div class="stack"><div><label for="cat_nbn">${esc(T('nameBn'))}</label><input id="cat_nbn" autocomplete="off" maxlength="120" value="${esc(nb || '')}"></div>
    <div><label for="cat_nen">${esc(T('nameEn'))}</label><input id="cat_nen" autocomplete="off" maxlength="120" value="${esc(ne || '')}"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="${go}" data-id="${esc(id || '')}">${esc(T('save'))}</button></div></div>`);
}
function menuSheet(id) {
  const f = findNode(id); if (!f) return;
  const top = !f.s, nd = f.node;
  const b = (act, l, extra) => `<button type="button" class="s2-act" data-act="${act}" data-id="${esc(id)}" ${extra || ''}>${esc(l)}</button>`;
  openSheet(`<h2>${esc(lab(nd.name))}</h2><div class="stack" style="margin-top:10px">
    ${top ? b('cat_addsub', T('addSub')) : ''}${P.owner ? b('cat_rename', T('rename')) + b('cat_merge', T('merge')) : ''}${b('cat_up', T('up'))}${b('cat_down', T('down'))}
    ${b('cat_toggle', nd.active === false ? T('on') : T('off'))}${b('cat_moveitems', T('moveItems'))}${top ? '' : b('cat_movesub', T('moveSub'))}
    <button type="button" class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}
async function reorder(id, dir) {
  const f = findNode(id); if (!f) return;
  const sibs = (f.s ? f.c.subs : C.tree).slice().sort((a, z) => (a.sort - z.sort) || String(lab(a.name)).localeCompare(String(lab(z.name))));
  const i = sibs.findIndex((x) => String(x.id) === String(id)), j = i + dir; if (i < 0 || j < 0 || j >= sibs.length) return;
  [sibs[i], sibs[j]] = [sibs[j], sibs[i]];
  await call('category_reorder', { p_ids: sibs.map((x) => x.id) });
}
function targetOptions(f) {   // merge targets: same level, active, not itself
  if (!f.s) return (C.tree || []).filter((c) => c.id && c.id !== f.c.id && c.active !== false).map((c) => [c.id, lab(c.name)]);
  const out = []; (C.tree || []).forEach((c) => c.subs.forEach((s) => { if (s.id && s.id !== f.s.id && s.active !== false) out.push([s.id, lab(c.name) + ' › ' + lab(s.name)]); })); return out;
}
function itemsOf(f) { return (C.items || []).filter((i) => (i.category || '') === f.c.code && (!f.s || (i.sub_category || '') === f.s.code)); }
function moveSheet(f) {
  const list = itemsOf(f).slice(0, 300); P.sel = new Set(); P.open = f;
  openSheet(`<h2>${esc(T('moveItems'))}</h2><div class="stack"><div class="cat-items" style="max-height:40vh;overflow:auto">${list.map((i) => `<label class="row" style="gap:8px;min-height:44px;align-items:center"><input type="checkbox" class="cat-pick" value="${esc(i.id)}"> <span>${esc(i.code)} · ${esc(i.name_en || i.name_bn || '')}</span></label>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>
    <div class="muted">${esc(T('moveTo'))}</div>${field('cm')}<div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cat_move_go">${esc(T('apply'))}</button></div></div>`);
  fillAll();
}
async function missingSheet() {
  let rows = []; try { rows = await call('items_missing_category', { p_limit: 300 }); } catch (e) { return errMsg(e); }
  openSheet(`<h2>${esc(T('missing'))}</h2><div class="stack">${rows.length ? `<label class="row" style="gap:8px;align-items:center"><input type="checkbox" id="cat_selall"> <span>${esc(T('selAll'))}</span></label>` : ''}
    <div class="cat-items" style="max-height:38vh;overflow:auto">${rows.map((i) => `<label class="row" style="gap:8px;min-height:44px;align-items:center"><input type="checkbox" class="cat-pick" value="${esc(i.item_id)}"> <span>${esc(i.code)} · ${esc(i.name_en || i.name_bn || '')}${i.reason === 'no_sub_category' ? ` <span class="chip warn">${esc(T('noSub'))}</span>` : ''}</span></label>`).join('') || `<p class="muted">${esc(T('missingNone'))}</p>`}</div>
    ${rows.length ? `${field('cm')}<div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cat_move_go">${esc(T('apply'))}</button></div>` : `<button class="full" data-act="closesheet">${esc(T('close'))}</button>`}</div>`);
  P.open = null; fillAll();
}
async function moveGo() {
  const ids = $$('.cat-pick').filter((x) => x.checked).map((x) => x.value); if (!ids.length) return toast(T('needItems'));
  const v = read('cm'), cid = v.cat ? idOfCat(v.cat) : null; if (!cid) return toast(T('needCat'));
  try { await call('item_set_category_bulk', { p_items: ids, p_cat: cid, p_sub: v.sub ? idOfSub(v.cat, v.sub) : null, p_client: rid() }); } catch (e) { return errMsg(e); }
  closeSheet(); toast(T('moveDone')); await redraw();
}

Object.assign(H, {
  cat_c: (a) => { const id = a.dataset.w; setSel(id, a.dataset.v === '_none' ? { none: true } : { cat: a.dataset.v, none: false }); },
  cat_s: (a) => setSel(a.dataset.w, { sub: a.dataset.v }),
  cat_add: () => nameSheet(T('addCat'), '', '', 'cat_add_go', ''),
  cat_addsub: (a) => nameSheet(T('addSub'), '', '', 'cat_add_go', a.dataset.id),
  cat_add_go: async (a) => {
    const bn = ($('#cat_nbn') || {}).value || '', en = ($('#cat_nen') || {}).value || ''; if (!bn.trim() && !en.trim()) return toast(lab(ERR.name_required));
    try { await call('category_save', { p_id: null, p_parent: a.dataset.id ? Number(a.dataset.id) : null, p_name_bn: bn, p_name_en: en || null, p_sort: null, p_active: null, p_client: rid() }); } catch (e) { return errMsg(e); }
    closeSheet(); toast(T('saved')); await redraw();
  },
  cat_menu: (a) => menuSheet(a.dataset.id),
  cat_rename: (a) => { const f = findNode(a.dataset.id); if (f) nameSheet(T('rename'), f.node.name.bn, (f.node.name.en && f.node.name.en !== f.node.name.bn) ? f.node.name.en : '', 'cat_rename_go', a.dataset.id); },
  cat_rename_go: async (a) => {
    const bn = ($('#cat_nbn') || {}).value || ''; if (!bn.trim()) return toast(lab(ERR.name_required));
    try { await call('category_rename', { p_id: Number(a.dataset.id), p_name_bn: bn, p_name_en: ($('#cat_nen') || {}).value || null }); } catch (e) { return errMsg(e); }
    closeSheet(); toast(T('saved')); await redraw();
  },
  cat_merge: (a) => {
    const f = findNode(a.dataset.id); if (!f) return; const opts = targetOptions(f);
    openSheet(`<h2>${esc(T('merge'))}</h2><div class="stack"><div class="notice warn">${esc(T('mergeHint'))}</div><div><label for="cat_mt">${esc(T('mergeInto'))}</label><select id="cat_mt"><option value="">—</option>${opts.map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join('')}</select></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cat_merge_go" data-id="${esc(a.dataset.id)}">${esc(T('merge'))}</button></div></div>`);
  },
  cat_merge_go: async (a) => {
    const to = ($('#cat_mt') || {}).value; if (!to) return toast(T('pickCat'));
    let r; try { r = await call('category_merge', { p_from: Number(a.dataset.id), p_into: Number(to), p_client: rid() }); } catch (e) { return errMsg(e); }
    closeSheet(); toast(T('mergeDone') + ': ' + ((r && r.items_moved) || 0) + ' ' + T('movedN')); await redraw();
  },
  cat_up: async (a) => { try { await reorder(a.dataset.id, -1); } catch (e) { return errMsg(e); } closeSheet(); await redraw(); },
  cat_down: async (a) => { try { await reorder(a.dataset.id, 1); } catch (e) { return errMsg(e); } closeSheet(); await redraw(); },
  cat_toggle: async (a) => { const f = findNode(a.dataset.id); if (!f) return; try { await call('category_save', { p_id: Number(a.dataset.id), p_active: f.node.active === false }); } catch (e) { return errMsg(e); } closeSheet(); toast(T('saved')); await redraw(); },
  cat_moveitems: (a) => { const f = findNode(a.dataset.id); if (f) moveSheet(f); },
  cat_move_go: moveGo,
  cat_movesub: (a) => {
    const f = findNode(a.dataset.id); if (!f) return;
    openSheet(`<h2>${esc(T('moveSub'))}</h2><div class="stack"><div><label for="cat_mp">${esc(T('moveTo'))}</label><select id="cat_mp"><option value="">—</option>${(C.tree || []).filter((c) => c.id && c.id !== f.c.id && c.active !== false).map((c) => `<option value="${c.id}">${esc(lab(c.name))}</option>`).join('')}</select></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cat_movesub_go" data-id="${esc(a.dataset.id)}">${esc(T('apply'))}</button></div></div>`);
  },
  cat_movesub_go: async (a) => { const to = ($('#cat_mp') || {}).value; if (!to) return toast(T('pickCat')); let r; try { r = await call('category_move', { p_id: Number(a.dataset.id), p_new_parent: Number(to) }); } catch (e) { return errMsg(e); } closeSheet(); toast(T('moveDone') + ': ' + ((r && r.items_moved) || 0) + ' ' + T('movedN')); await redraw(); },
  cat_missing: missingSheet,
  cat_bulk_go: async () => {
    const v = read('cb'), cid = v.cat ? idOfCat(v.cat) : null; if (!cid) return toast(T('needCat')); if (!BULK) return;
    try { await call('item_set_category_bulk', { p_items: BULK.ids, p_cat: cid, p_sub: v.sub ? idOfSub(v.cat, v.sub) : null, p_client: rid() }); } catch (e) { return errMsg(e); }
    const done = BULK.done; BULK = null; closeSheet(); toast(T('moveDone')); await reload(); if (done) done();
  },
  cat_rpt_go: () => reportGo(), cat_rpt_csv: () => reportCsv(),
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t) return;
  if (t.id === 'cat_selall') { $$('.cat-pick').forEach((x) => { x.checked = t.checked; }); return; }
  if (t.id === 'cat_mode') { call('set_rule', { p_key: 'category_required_on_item', p_value: t.value }).then(() => { toast(T('saved')); return loadRule(); }).then(() => { if (/^#\/categories/.test(location.hash)) drawCat(); }).catch(errMsg); }
});

// ---------- #/catreport ----------
const R = { kind: 'sales', level: 'category', from: null, to: null, rows: null, cost: false };
async function reportView() {
  if (!R.from) { R.to = today(); R.from = addDays(R.to, -29); }
  await load();
  drawReport();
}
function drawReport() {
  const sales = R.kind === 'sales';
  shell(T('rpTitle'), `<div class="card stack"><div class="row wrap"><button type="button" class="tog ${sales ? 'on' : ''}" data-act="cat_rpt_k" data-v="sales">${esc(T('rpSales'))}</button><button type="button" class="tog ${sales ? '' : 'on'}" data-act="cat_rpt_k" data-v="stock">${esc(T('rpStock'))}</button></div>
    ${sales ? `<div class="row"><div style="flex:1"><label for="cat_rf">${esc(T('rpFrom'))}</label><input id="cat_rf" type="date" value="${esc(R.from)}"></div><div style="flex:1"><label for="cat_rt">${esc(T('rpTo'))}</label><input id="cat_rt" type="date" value="${esc(R.to)}"></div></div>` : ''}
    <div><label for="cat_rl">${esc(T('rpLevel'))}</label><select id="cat_rl"><option value="category" ${R.level === 'category' ? 'selected' : ''}>${esc(T('rpByCat'))}</option><option value="sub" ${R.level === 'sub' ? 'selected' : ''}>${esc(T('rpBySub'))}</option></select></div>
    <div class="row"><button type="button" class="primary full" data-act="cat_rpt_go">${esc(T('rpRun'))}</button><button type="button" class="full" data-act="cat_rpt_csv">${esc(T('rpCsv'))}</button></div></div><div id="cat_rep"></div>`, 'reports');
  if (R.rows) paintReport();
}
const rowName = (r) => {
  const c = r.category ? lab({ bn: r.cat_name_bn || r.category, en: r.cat_name_en || (LEG[r.category] && LEG[r.category].en) || r.cat_name_bn || r.category, mix: r.cat_name_bn || r.category }) : T('rpUncat');
  const s = r.sub_category ? lab({ bn: r.sub_name_bn || r.sub_category, en: r.sub_name_en || r.sub_name_bn || r.sub_category, mix: r.sub_name_bn || r.sub_category }) : '';
  return { c, s };
};
async function reportGo() {
  const rf = $('#cat_rf'), rt = $('#cat_rt'), rl = $('#cat_rl'); if (rf) R.from = rf.value || R.from; if (rt) R.to = rt.value || R.to; if (rl) R.level = rl.value;
  const box = $('#cat_rep'); if (box) box.innerHTML = `<p class="muted center pad">${esc(T('loading'))}</p>`;
  try { R.rows = R.kind === 'sales' ? await call('biz_items_by_category', { p_from: R.from, p_to: R.to, p_loc: null, p_level: R.level }) : await call('stock_valuation_by_category', { p_loc: null, p_level: R.level }); } catch (e) { R.rows = null; if (box) box.innerHTML = ''; return errMsg(e); }
  paintReport();
}
function totals() {
  const rows = R.rows || [], sales = R.kind === 'sales';
  const rev = rows.reduce((s, r) => s + (Number(sales ? r.revenue : r.value) || 0), 0);
  const known = rows.filter((r) => r.cogs !== null && r.cogs !== undefined), cost = known.reduce((s, r) => s + Number(r.cogs), 0), unk = rows.reduce((s, r) => s + (Number(r.cogs_unknown_items) || 0), 0);
  return { rev, cost: known.length ? cost : null, unk, items: rows.reduce((s, r) => s + (Number(r.items) || 0), 0) };
}
function paintReport() {
  const box = $('#cat_rep'); if (!box) return; const rows = R.rows || [], sales = R.kind === 'sales', sub = R.level === 'sub', t = totals();
  if (!rows.length) { box.innerHTML = `<p class="muted center pad">${esc(T('rpNone'))}</p>`; return; }
  const th = [T('cat')].concat(sub ? [T('sub')] : [], [T('items')], sales ? [T('rpRev'), T('rpCost'), T('rpShare')] : [T('rpVal')]);
  box.innerHTML = `<div class="card" style="overflow-x:auto"><table class="cat-tbl"><thead><tr>${th.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.map((r) => { const n = rowName(r); return `<tr><td>${esc(n.c)}</td>${sub ? `<td>${esc(n.s)}</td>` : ''}<td class="n">${esc(q2(r.items))}</td>${sales ? `<td class="n">${esc(q2(r.revenue))}</td><td class="n">${r.cogs === null || r.cogs === undefined ? '—' : esc(q2(r.cogs))}${Number(r.cogs_unknown_items) ? ` <span class="chip warn">${Number(r.cogs_unknown_items)}</span>` : ''}</td><td class="n">${esc(q2(r.share_pct))}</td>` : `<td class="n">${esc(q2(r.value))}</td>`}</tr>`; }).join('')}
    <tr class="cat-tot"><td><b>${esc(T('rpTotal'))}</b></td>${sub ? '<td></td>' : ''}<td class="n">${esc(q2(t.items))}</td>${sales ? `<td class="n"><b>${esc(q2(t.rev))}</b></td><td class="n">${t.cost === null ? '—' : esc(q2(t.cost))}</td><td></td>` : `<td class="n"><b>${esc(q2(t.rev))}</b></td>`}</tr></tbody></table></div>
    ${sales && t.cost === null ? `<div class="notice info">${esc(T('rpNoCost'))}</div>` : ''}${sales && t.unk ? `<div class="muted">${esc(T('rpUnk'))}: ${t.unk}</div>` : ''}`;
}
const csvCell = (v) => { let s = String(v ?? ''); if (/^[=+\-@\t\r]/.test(s) && isNaN(Number(s))) s = "'" + s; return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };   // bos111 (L1): a name that starts with = + - @ is text in Excel, never a formula
function csvText() {
  const rows = R.rows || [], sales = R.kind === 'sales', sub = R.level === 'sub';
  const head = ['category'].concat(sub ? ['sub_category'] : [], ['items'], sales ? ['revenue', 'cost', 'share_pct'] : ['value']);
  const out = [head.join(',')];
  rows.forEach((r) => { const n = rowName(r); out.push([n.c].concat(sub ? [n.s] : [], [r.items], sales ? [r.revenue, r.cogs === null || r.cogs === undefined ? '' : r.cogs, r.share_pct] : [r.value]).map(csvCell).join(',')); });
  return out.join('\n');
}
function reportCsv() {
  if (!R.rows || !R.rows.length) return toast(T('rpNone'));
  try { const blob = new Blob(['﻿' + csvText()], { type: 'text/csv;charset=utf-8' }), a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'by-category-' + R.kind + '-' + (R.kind === 'sales' ? R.from + '_' + R.to : today()) + '.csv'; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500); } catch (e) { fail(e); }
}
H.cat_rpt_k = (a) => { R.kind = a.dataset.v; R.rows = null; drawReport(); };

// ---------- registration ----------
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { categories: catView, catreport: reportView });
B.catfilter = catfilter;
B.catpick = { X, T, ERR, load, reload, mount, label, name, subName, nameIfKnown, catfilter, subSelect, subOptions, catOptions, filterRow, field, read, subChips, bulkSheet, keyOf, scan, csvText, buildTree, idOfCat, idOfSub, loadRule, _state: () => C, _widgets: () => W, _bars: () => BARS };

// preload once the session is known; a failed load only means no filters appear
let probes = 0; const probeTimer = setInterval(() => { if (++probes > 120) return clearInterval(probeTimer); if (S.ctx) { clearInterval(probeTimer); load().then(() => { loadRule(); scan(); }).catch(() => {}); } }, 500);

const css = document.createElement('style'); css.id = 'catcss';
css.textContent = `.cat-bar{gap:6px;margin:4px 0 8px;flex-wrap:wrap;max-width:100%}.cat-bar .ctl-trg{flex:1 1 140px;width:auto;min-width:0;max-width:100%}.cat-bar select{flex:1;min-width:0;min-height:44px}.cat-w{margin-bottom:8px}.cat-chip{min-height:44px}.cat-sel{width:100%;min-height:44px;margin-bottom:6px}
.cat-sub{padding:6px 0 6px 12px;border-top:1px solid var(--line,#e3e0d8);min-height:44px;align-items:center}.cat-card{overflow-wrap:anywhere}.cat-tbl{border-collapse:collapse;font-size:.9rem;width:100%}.cat-tbl th,.cat-tbl td{padding:6px 4px;border-bottom:1px solid var(--line,#e3e0d8);text-align:start}
.cat-tbl td.n{text-align:end;white-space:nowrap}.cat-tot td{border-top:2px solid var(--line,#e3e0d8)}`;
document.head.appendChild(css);
})();
