/* Islamia BOS · Recipes / BOM (#/recipes): recipe list with a ⋮ menu (new version, activate / inactivate, duplicate, packaging, cost, produce), the editor,
   packaging rules, the production sheet (also opened from the stock hub's "Production in") and "what can I make now" per location.
   Server: phase19.sql (recipe_save / recipe_copy / recipe_set_active / packaging_set / production_preview / production_can_make / production_post / recipe_cost).
   Nothing is guessed here: an empty waste % says "Data needed"; costs are shown only when the server returns them (owner / ITEM_COST / view_cost). Loaded after salary.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const S2 = () => B.s2 || {};
const q4 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const owner = () => !!(S.ctx && S.ctx.is_owner);
const npMode = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* rules not loaded */ } return m === 'hide' ? 'hide' : 'lock'; };

const X = {
  title: L('রেসিপি', 'Recipes', 'Recipe (রেসিপি)'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), close: L('বন্ধ', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), save: L('সেভ', 'Save', 'Save'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কোনো রেসিপি নেই', 'No recipes yet', 'কোনো recipe নেই'), search: L('পণ্য বা কোড খুঁজুন', 'Search product or code', 'Product বা code খুঁজুন'),
  tRecipes: L('রেসিপি', 'Recipes', 'Recipes'), tMake: L('এখন কী বানানো যায়', 'Can make now', 'এখন কী বানানো যায়'), tPack: L('প্যাকেজিং', 'Packaging', 'Packaging'),
  fActive: L('চালু', 'Active', 'Active'), fOff: L('বন্ধ', 'Inactive', 'Inactive'), fAll: L('সব', 'All', 'All'),
  add: L('নতুন রেসিপি', 'New recipe', 'নতুন recipe'), version: L('ভার্সন', 'Version', 'Version'), yield: L('একবারে তৈরি হয়', 'Yield per batch', 'Yield (প্রতি batch)'),
  used: L('ব্যবহৃত — বদলানো যায় না', 'Used — frozen', 'Used — বদলানো যায় না'), inactive: L('বন্ধ', 'Inactive', 'Inactive'), needData: L('তথ্য দরকার', 'Data needed', 'Data দরকার'),
  nLines: L('উপকরণ', 'ingredients', 'ingredients'), more: L('আরও অপশন', 'More options', 'আরও option'),
  mOpen: L('খুলুন / দেখুন', 'Open / view', 'Open / দেখুন'), mNew: L('নতুন ভার্সন', 'New version', 'নতুন version'), mOn: L('চালু করুন', 'Activate', 'Activate'), mOff: L('বন্ধ করুন', 'Inactivate', 'Inactivate'),
  mDup: L('অন্য পণ্যে কপি', 'Duplicate to another product', 'অন্য product-এ copy'), mPack: L('প্যাকেজিং', 'Packaging', 'Packaging'), mCost: L('কস্ট দেখুন', 'Show cost', 'Cost দেখুন'),
  mMake: L('উৎপাদন করুন', 'Produce', 'Produce করুন'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  product: L('তৈরি পণ্য', 'Finished product', 'Finished product'), productPh: L('কোড বা নাম', 'Code or name', 'Code বা নাম'), unit: L('একক', 'Unit', 'Unit'), baseUnit: L('— বেস একক —', '— base unit —', '— base unit —'),
  qty: L('Qty', 'Quantity', 'Quantity'), waste: L('অপচয় %', 'Waste %', 'Waste %'), note: L('নোট', 'Note', 'Note'), ing: L('উপকরণ', 'Ingredient', 'Ingredient'),
  addLine: L('উপকরণ যোগ', 'Add ingredient', 'Ingredient যোগ'), removeLine: L('সরান', 'Remove', 'Remove'), retireOld: L('আগের ভার্সন বন্ধ করুন', 'Retire the previous version', 'আগের version বন্ধ করুন'),
  usedHint: L('এই ভার্সন উৎপাদনে ব্যবহৃত হয়েছে। সেভ করলে নতুন ভার্সন হবে — পুরনোটি অক্ষত থাকবে।', 'This version has been used in production. Saving makes a NEW version; the old one stays untouched.', 'এই version production-এ use হয়েছে। Save করলে নতুন version হবে — পুরনোটি অক্ষত।'),
  wasteHint: L('অপচয় % ফাঁকা থাকলে ০ ধরা হয় ও মালিককে জানানো হয় — আসল % আপনি বসান।', 'An empty waste % counts as 0 and the owner is told — set the real %.', 'Waste % ফাঁকা থাকলে ০ ধরা হয় — আসল % বসান।'),
  needProduct: L('তৈরি পণ্য বাছুন', 'Choose the finished product', 'Finished product বাছুন'), needIng: L('উপকরণ বাছুন', 'Choose the ingredient', 'Ingredient বাছুন'),
  needQty: L('Qty ঠিক নয়', 'Quantity is not valid', 'Quantity ঠিক নয়'), needWaste: L('অপচয় % ০–১০০ হতে হবে', 'Waste % must be 0–100', 'Waste % ০–১০০ হতে হবে'), needLines: L('অন্তত একটি উপকরণ লাগবে', 'Add at least one ingredient', 'অন্তত একটি ingredient'),
  location: L('জায়গা', 'Location', 'Location'), recipe: L('রেসিপি', 'Recipe', 'Recipe'), batches: L('ব্যাচ সংখ্যা', 'Number of batches', 'Batch সংখ্যা'), madeAt: L('তৈরির সময়', 'Made at', 'Made at'),
  pTitle: L('উৎপাদন (রেসিপি দিয়ে)', 'Production (from a recipe)', 'Production (recipe দিয়ে)'), preview: L('কী কী লাগবে', 'What will be used', 'কী কী লাগবে'), need: L('লাগবে', 'Need', 'Need'), have: L('আছে', 'On hand', 'On hand'),
  short: L('কম', 'Short', 'Short'), willMake: L('তৈরি হবে', 'Will make', 'তৈরি হবে'), post: L('উৎপাদন সেভ', 'Post production', 'Production post'), nothing: L('রেসিপি বাছুন ও ব্যাচ লিখুন', 'Choose a recipe and the batches', 'Recipe বাছুন, batch লিখুন'),
  shortWarn: L('কাঁচামাল কম — সেটিং অনুযায়ী উৎপাদন আটকে যেতে পারে', 'Raw material is short — the setting may refuse this production', 'Raw material কম — setting অনুযায়ী আটকাতে পারে'),
  notTracked: L('স্টক ট্র্যাক বন্ধ / একক অজানা', 'Not tracked / unit unknown', 'Track বন্ধ / unit অজানা'), done: L('উৎপাদন সেভ হয়েছে — কাঁচামাল বাদ গেছে', 'Production saved — raw material taken out', 'Production saved — raw material বাদ'),
  useRecipe: L('রেসিপি দিয়ে উৎপাদন', 'Produce from a recipe', 'Recipe দিয়ে production'),
  makeHead: L('এই জায়গায় এখন যা বানানো যায়', 'What can be made here now', 'এই location-এ এখন যা বানানো যায়'), maxB: L('সর্বোচ্চ ব্যাচ', 'Max batches', 'Max batch'), limit: L('যার জন্য আটকাবে', 'Limited by', 'Limited by'),
  makeEmpty: L('কোনো চালু রেসিপি নেই', 'No active recipes', 'কোনো active recipe নেই'), unknownMake: L('তথ্য দরকার (ট্র্যাক / একক)', 'Data needed (tracking / unit)', 'Data দরকার (track / unit)'),
  cHead: L('এক ব্যাচের কস্ট', 'Cost of one batch', 'এক batch-এর cost'), cBatch: L('ব্যাচ কস্ট', 'Batch cost', 'Batch cost'), cUnit: L('প্রতি একক', 'Per unit', 'Per unit'), cAvg: L('গড় কস্ট', 'avg cost', 'avg cost'),
  cPartial: L('কিছু উপকরণের কস্ট জানা নেই — টোটাল বসানো হয়নি', 'Some ingredients have no known cost — no total is shown', 'কিছু ingredient-এর cost অজানা — total নেই'),
  pkTitle: L('প্যাকেজিং নিয়ম', 'Packaging rules', 'Packaging rule'), pkMode: L('প্যাকেজিং কখন কমবে', 'When packaging leaves the stock', 'Packaging কখন কমবে'), pkOff: L('বন্ধ', 'Off', 'Off'), pkSale: L('বিক্রিতে', 'With a sale', 'Sale-এ'), pkProd: L('উৎপাদনে', 'With production', 'Production-এ'),
  pkPer: L('প্রতি ১ বেস এককে', 'per 1 base unit', 'per 1 base unit'), pkItem: L('প্যাকেজিং আইটেম', 'Packaging item', 'Packaging item'), pkApplies: L('কখন', 'Applies to', 'Applies to'), pkAdd: L('প্যাকেজিং যোগ / বদল', 'Add / change packaging', 'Packaging যোগ / বদল'),
  pkNone: L('কোনো প্যাকেজিং নিয়ম নেই', 'No packaging rules', 'কোনো packaging rule নেই'), pkOffHint: L('এখন বন্ধ — প্যাকেজিং নিজে থেকে কমবে না।', 'Currently off — packaging is not taken out automatically.', 'এখন off — packaging নিজে কমবে না।'),
  pkSaleHint: L('বিক্রিতে কমলে সেল কখনো আটকায় না; কমাতে না পারলে মালিক হলুদ লাইন পান।', 'With a sale it never blocks the sale; if it cannot be taken out the owner gets a yellow line.', 'Sale-এ কমলে sale আটকায় না; না পারলে owner yellow line পান।'),
  pkSale2: L('সেল', 'Sale', 'Sale'), pkProd2: L('উৎপাদন', 'Production', 'Production'), pkProduct: L('যে পণ্যের জন্য', 'For product', 'For product'),
  dupTo: L('কোন পণ্যে কপি করবেন', 'Copy to which product', 'কোন product-এ copy'), copyGo: L('কপি', 'Copy', 'Copy'), copied: L('নতুন ভার্সন তৈরি', 'New version created', 'নতুন version তৈরি'),
  actY: L('প্রকৃত টোটাল উৎপাদন (ঐচ্ছিক)', 'Actual total output (optional)', 'Actual total output (optional)'), actYHint: L('খালি রাখলে রেসিপির হিসাবই ধরা হয়; দিলে সেটাই স্টকে ঢোকে ও পার্থক্য লেখা থাকে।', 'Leave empty to use the recipe figure; if filled, that is what goes into stock and the difference is recorded.', 'খালি রাখলে recipe-র হিসাবই ধরা হয়; দিলে সেটাই stock-এ ঢোকে ও difference লেখা থাকে।'),
  sqlMissing: L('রেসিপির ডেটাবেস অংশ এখনও চালু হয়নি (phase19)', 'The recipe database part is not installed yet (phase19)', 'Recipe-এর database অংশ চালু হয়নি (phase19)'),
};
const T = (k) => lab(X[k]);
const ERRS = {
  cost_missing: L('কোনো উপকরণের কস্ট অজানা — আগে কস্ট বসান, তারপর উৎপাদন করুন', 'An ingredient cost is unknown — set the cost first, then produce', 'কোনো ingredient-এর cost অজানা — আগে cost বসান, তারপর production করুন'),
  recipe_used: L('এই ভার্সন ব্যবহৃত হয়েছে — নতুন ভার্সন বানান', 'This version is already used — make a new version', 'এই version used — নতুন version বানান'),
  recipe_not_found: L('রেসিপি পাওয়া যায়নি', 'Recipe not found', 'Recipe পাওয়া যায়নি'), recipe_inactive: L('রেসিপি বন্ধ আছে', 'The recipe is inactive', 'Recipe inactive'),
  recipe_required: L('উৎপাদন এখন শুধু রেসিপি দিয়ে — "রেসিপি দিয়ে উৎপাদন" ব্যবহার করুন', 'Production now needs a recipe — use "Produce from a recipe"', 'Production এখন শুধু recipe দিয়ে'),
  bad_ingredient_type: L('এই আইটেম উপকরণ হতে পারে না (শুধু উপকরণ / প্যাকেজিং / রিসেল)', 'This item cannot be an ingredient (raw material / packaging / resale only)', 'এই item ingredient হতে পারে না'),
  bad_product_type: L('শুধু তৈরি পণ্যের রেসিপি হয়', 'Only a finished product can have a recipe', 'শুধু finished product-এর recipe'), bad_waste: L('অপচয় % ০–১০০ হতে হবে', 'Waste % must be 0–100', 'Waste % ০–১০০'),
  dup_ingredient: L('একই উপকরণ দুবার', 'The same ingredient twice', 'একই ingredient দুবার'), no_lines: L('অন্তত একটি উপকরণ লাগবে', 'Add at least one ingredient', 'অন্তত একটি ingredient'),
  ingredient_is_product: L('পণ্য নিজেই নিজের উপকরণ হতে পারে না', 'A product cannot be its own ingredient', 'Product নিজের ingredient নয়'), ingredient_not_tracked: L('উপকরণের স্টক ট্র্যাক বন্ধ', 'Stock tracking is off for an ingredient', 'Ingredient-এ stock track বন্ধ'),
  cost_missing: L('কোনো উপকরণের কস্ট অজানা — আগে কস্ট বসান (বা কস্ট সত্যিই শূন্য হলে চিহ্ন দিন)', 'An ingredient cost is unknown - enter the cost first (or mark the item as cost really zero)', 'কোনো ingredient-এর cost অজানা — আগে cost বসান (বা cost সত্যিই শূন্য হলে mark দিন)'),
  waste_needed: L('রেসিপিতে অপচয় % বসানো নেই (সেটিং চালু)', 'A recipe line has no waste % (setting is on)', 'Recipe-এ waste % নেই (setting on)'), too_many_lines: L('১০০-র বেশি উপকরণ হয় না', 'More than 100 ingredients', '১০০-র বেশি ingredient'),
};
const ERRKEYS = Object.keys(ERRS);
function errMsg(e, ctx) {
  const m = String((e && e.message) || '');
  for (const k of ERRKEYS) if (new RegExp('\\b' + k + '\\b').test(m)) return toast(lab(ERRS[k]) + (k === 'cost_missing' && e && e.details ? ' (' + String(e.details).slice(0, 120) + ')' : ''));   // bos107 q4: name the ingredient(s) whose cost is unknown (the server puts them in details)
  if (/could not find the function|schema cache|does not exist/i.test(m)) return toast(T('sqlMissing'));
  if (S2().errToast) return S2().errToast(e, ctx);
  return fail(e);
}

// ---------- state ----------
const D = { tab: 'rec', f: 'active', q: '', recipes: [], lines: [], items: [], conv: [], pack: [], canManage: false, canCost: false, loc: undefined, can: null, ready: false, missing: false };
let E = null;          // editor state
let PS = null;         // production sheet state
const itemById = (id) => D.items.find((i) => i.id === id);
const itemTxt = (i) => (i ? i.code + ' · ' + nm(i) : '');
const baseU = (i) => (i && (i.base_unit || i.unit)) || '';
const unitLabel = (c) => { if (!c) return ''; const r = ((B.ENV && B.ENV.lists && B.ENV.lists.units) || []).find((x) => x.value_code === c); return r ? lab({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined }) : c; };
const LOCS = () => (S2().LOCS ? S2().LOCS() : []);
const locName = (id) => nm(((B.ENV && B.ENV.locs) || []).find((l) => l.id === id) || { name_bn: '#' + id });
const optH = (rows, cur) => rows.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const DOTS = '<svg viewBox="0 0 32 32" aria-hidden="true" width="20" height="20" fill="currentColor"><circle cx="16" cy="7" r="2.6"/><circle cx="16" cy="16" r="2.6"/><circle cx="16" cy="25" r="2.6"/></svg>';
const LOCKI = '<svg viewBox="0 0 32 32" aria-hidden="true" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';
// units an ingredient can be written in: its base unit + every unit with a known conversion to it
function unitsFor(item) {
  if (!item) return [];
  const b = baseU(item), out = [b];
  (D.conv || []).forEach((c) => { if (c.active === false) return; if (c.item_id && c.item_id !== item.id) return; const o = c.to_unit === b ? c.from_unit : c.from_unit === b ? c.to_unit : null; if (o && !out.includes(o)) out.push(o); });
  return out.filter(Boolean);
}

const css = document.createElement('style'); css.id = 'rccss';
css.textContent = `.rc-row .sub{font-size:.85rem;color:var(--muted);overflow-wrap:anywhere}.rc-row .nm{overflow-wrap:anywhere}.rc-dots{min-width:44px;min-height:44px;margin:-8px -8px 0 auto;display:block;background:none;border:0;color:var(--muted);box-shadow:none}
.rc-line{border:1px solid var(--hair);border-radius:12px;padding:10px;margin-top:8px}.rc-line .row{gap:8px}.rc-need{color:var(--sig-bad)}.rc-tbl{width:100%;border-collapse:collapse}.rc-tbl td,.rc-tbl th{padding:6px 4px;border-bottom:1px solid var(--hair);text-align:start;font-size:.9rem;vertical-align:top}
.rc-tbl td.n,.rc-tbl th.n{text-align:end;font-variant-numeric:lining-nums tabular-nums}.rc-bar{position:sticky;bottom:0;z-index:4;display:flex;gap:8px;padding:10px 0 calc(10px + env(safe-area-inset-bottom));background:var(--bg);border-top:1px solid var(--hair);margin-top:14px}.rc-bar button{flex:1}body.has-bnav .rc-bar{bottom:58px}
.rc-act{display:flex;align-items:center;gap:10px;width:100%;justify-content:flex-start;text-align:start}.ptabs.rc-t button{flex:1}.rc-lock{display:flex;align-items:center;gap:10px;min-height:48px;padding:0 12px;border:1px solid var(--hair);border-radius:12px;color:var(--muted);margin-top:8px}`;
document.head.appendChild(css);

// ---------- data ----------
async function load() {
  D.missing = false;
  const S2h = S2();
  const [r, l, it, cv, pk] = await Promise.all([
    sb.from('recipes').select('*').order('created_at', { ascending: false }),
    sb.from('recipe_lines').select('*').order('sort'),
    window.BOS_ALL ? window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,item_type,is_active,tracked').order('code')) : sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,item_type,is_active,tracked').order('code'),
    sb.from('unit_conversions').select('*'), sb.from('product_packaging').select('*')]);
  if (r.error && /could not find|schema cache|does not exist|relation/i.test(r.error.message || '')) D.missing = true;
  D.recipes = r.error ? [] : (r.data || []); D.lines = l.error ? [] : (l.data || []); D.items = it.error ? [] : (it.data || []);
  D.conv = cv.error ? [] : (cv.data || []); D.pack = pk.error ? [] : (pk.data || []);
  D.canManage = owner() || (S2h.grant ? await S2h.grant('recipe_manage', null) : false);
  D.canCost = S2h.costOk ? await S2h.costOk(null) : owner();
  D.ready = true;
}
const linesOf = (id) => D.lines.filter((x) => x.recipe_id === id && x.active !== false);
const latestActive = (itemId) => D.recipes.filter((r) => r.item_id === itemId && r.active).sort((a, b) => b.version - a.version)[0];
const wasteMissing = (r) => linesOf(r.id).some((x) => x.waste_pct === null || x.waste_pct === undefined);

// ---------- page ----------
async function view() {
  const p = location.hash.replace(/^#\/?/, '').split('/');
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  await load();
  if (D.missing) { shell(T('title'), `<div class="notice bad">${esc(T('sqlMissing'))}</div>`, true); return; }
  if (p[1] === 'new') return openEditor(null);
  if (p[1] && p[1] !== 'make' && p[1] !== 'packaging') {
    const r = D.recipes.find((x) => x.id === p[1]);
    if (r) { openEditor(r); if (D.newver === r.id) { D.newver = null; E.used = true; drawEditor(); } return; }
  }
  if (p[1] === 'make') D.tab = 'make'; else if (p[1] === 'packaging') D.tab = 'pack'; else if (!p[1]) D.tab = D.tab || 'rec';
  draw();
}
function draw() {
  const addBtn = D.canManage ? `<button class="primary" data-act="rc_new">${esc(T('add'))}</button>` : '';
  shell(T('title'), `<div class="ptabs rc-t" role="tablist">${[['rec', 'tRecipes'], ['make', 'tMake'], ['pack', 'tPack']].map(([k, l]) => `<button role="tab" data-act="rc_tab" data-v="${k}" aria-selected="${D.tab === k}">${esc(T(l))}</button>`).join('')}</div>
    <div id="rc_main"></div>${D.tab === 'rec' && addBtn ? `<div class="rc-bar">${addBtn}</div>` : ''}`, true);
  if (D.tab === 'rec') drawList(); else if (D.tab === 'make') drawMake(); else drawPack();
}
function drawList() {
  const box = $('#rc_main'); if (!box) return;
  const q = norm(D.q).toLowerCase();
  const list = D.recipes.filter((r) => (D.f === 'all' || (D.f === 'active') === !!r.active) && (!D.cs || !B.catfilter || B.catfilter([itemById(r.item_id) || { id: r.item_id }], D.cs).length) /* bos100 */ && (!q || [itemById(r.item_id)?.code, itemById(r.item_id)?.name_bn, itemById(r.item_id)?.name_en].some((x) => String(x || '').toLowerCase().includes(q))))
    .sort((a, b) => (itemById(a.item_id)?.code || '').localeCompare(itemById(b.item_id)?.code || '') || b.version - a.version);
  box.innerHTML = `<div class="p2-bar"><input id="rc_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(D.q)}" aria-label="${esc(T('search'))}"></div>
    <div class="row wrap" style="margin:8px 0">${[['active', 'fActive'], ['off', 'fOff'], ['all', 'fAll']].map(([k, l]) => `<button class="tog ${D.f === k ? 'on' : ''}" data-act="rc_f" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>
    ${B.catpick ? B.catpick.filterRow('rc_cs', D.cs, 'rc_cat') : ''}<!-- bos100 -->
    <div id="rc_list">${list.map((r) => {
      const it = itemById(r.item_id) || { name_bn: '?', code: '' }, n = linesOf(r.id).length, wm = wasteMissing(r);
      return `<div class="card item rc-row mk ${r.active ? (wm ? 'warn' : '') : ''}" data-act="rc_open" data-id="${r.id}" role="button" tabindex="0"><div><div class="nm">${esc(nm(it))} · ${esc(T('version'))} ${r.version}</div>
        <div class="sub">${esc(it.code)} · ${esc(T('yield'))} ${q4(r.yield_qty)} ${esc(unitLabel(r.yield_unit || baseU(it)))} · ${n} ${esc(T('nLines'))}${B.catpick && B.catpick.label(it) ? ' · ' + esc(B.catpick.label(it)) : ''/* bos100 */}</div>
        <div>${r.used_at ? `<span class="chip">${LOCKI} ${esc(T('used'))}</span>` : ''}${r.active ? '' : `<span class="chip bad">${esc(T('inactive'))}</span>`}${wm ? `<span class="chip warn">${esc(T('waste'))}: ${esc(T('needData'))}</span>` : ''}</div></div>
        <div class="pr"><button type="button" class="rc-dots" data-act="rc_menu" data-id="${r.id}" aria-label="${esc(T('more'))}">${DOTS}</button></div></div>`; }).join('')
      || `<div class="card center"><p class="muted">${esc(T('none'))}</p></div>`}</div>`;
}

// ----- ⋮ menu -----
function menu(r) {
  const it = itemById(r.item_id) || {}, mgr = D.canManage, lock = npMode() === 'lock';
  const btn = (act, label, ok) => (ok ? `<button class="rc-act" data-act="${act}" data-id="${r.id}">${esc(T(label))}</button>` : lock ? `<div class="rc-lock">${LOCKI}<span>${esc(T(label))} · ${esc(T('noperm'))}</span></div>` : '');
  openSheet(`<h2>${esc(nm(it))} · ${esc(T('version'))} ${r.version}</h2><div class="stack" style="margin-top:8px">
    ${btn('rc_open', 'mOpen', true)}${btn('rc_newver', 'mNew', mgr)}${btn('rc_toggle', r.active ? 'mOff' : 'mOn', mgr)}${btn('rc_dup', 'mDup', mgr)}${btn('rc_pack', 'mPack', true)}
    ${D.canCost ? btn('rc_cost', 'mCost', true) : ''}${btn('rc_make', 'mMake', true)}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ----- editor -----
function openEditor(r) {
  const it = r ? itemById(r.item_id) : null;
  E = { id: r ? r.id : null, used: !!(r && r.used_at), item: it, client: rid(), busy: false,
    yq: r ? String(r.yield_qty) : '', yu: r ? (r.yield_unit || '') : '', note: r ? (r.note || '') : '', retire: true,
    lines: r ? linesOf(r.id).map((x) => ({ item: itemById(x.ingredient_item_id), qty: String(x.qty), unit: x.unit || '', waste: x.waste_pct === null || x.waste_pct === undefined ? '' : String(x.waste_pct), note: x.note || '' })) : [{ item: null, qty: '', unit: '', waste: '', note: '' }],
    ver: r ? r.version : null };
  drawEditor();
}
const finished = () => D.items.filter((i) => i.item_type === 'finished_good' && i.is_active !== false);
const ingredients = () => D.items.filter((i) => ['raw_material', 'packaging', 'resale'].includes(i.item_type) && i.is_active !== false);
const findItem = (list, v) => { const s = String(v || '').trim(); if (!s) return null; const c = s.split(' · ')[0].trim().toLowerCase(); return list.find((i) => i.code.toLowerCase() === c) || list.find((i) => nm(i).toLowerCase() === s.toLowerCase()) || null; };
function lineHTML(l, i) {
  const us = unitsFor(l.item);
  return `<div class="rc-line" data-i="${i}"><label for="rl_item_${i}">${esc(T('ing'))}</label><input id="rl_item_${i}" list="rl_dl" autocomplete="off" value="${esc(l.item ? itemTxt(l.item) : '')}" placeholder="${esc(T('productPh'))}" ${E.readonly ? 'disabled' : ''}>
    <div class="row" style="margin-top:6px"><div style="flex:1"><label for="rl_qty_${i}">${esc(T('qty'))}</label><input id="rl_qty_${i}" inputmode="decimal" value="${esc(l.qty)}"></div>
    <div style="flex:1"><label for="rl_unit_${i}">${esc(T('unit'))}</label><select id="rl_unit_${i}"><option value="">${esc(T('baseUnit'))}</option>${optH(us.map((u) => [u, unitLabel(u)]), l.unit)}</select></div>
    <div style="flex:1"><label for="rl_w_${i}">${esc(T('waste'))}</label><input id="rl_w_${i}" inputmode="decimal" value="${esc(l.waste)}" placeholder="—"></div></div>
    ${String(l.waste).trim() === '' ? `<span class="chip warn" id="rl_wc_${i}">${esc(T('waste'))}: ${esc(T('needData'))}</span>` : ''}
    <div class="row" style="margin-top:6px"><input id="rl_note_${i}" autocomplete="off" value="${esc(l.note)}" placeholder="${esc(T('note'))}" style="flex:1"><button type="button" class="mini" data-act="rc_rmline" data-i="${i}" style="width:auto;padding:0 12px">${esc(T('removeLine'))}</button></div></div>`;
}
function drawEditor() {
  const it = E.item, title = E.id ? `${nm(it || {})} · ${T('version')} ${E.ver}` : T('add');
  const yu = it ? unitsFor(it) : [];
  shell(title, `${E.used ? `<div class="notice warn">${esc(T('usedHint'))}</div>` : ''}<div class="stack">
    <div><label for="rc_item">${esc(T('product'))}</label><input id="rc_item" list="rc_idl" autocomplete="off" value="${esc(it ? itemTxt(it) : '')}" placeholder="${esc(T('productPh'))}" ${E.id ? 'disabled' : ''}>
      <datalist id="rc_idl">${finished().map((i) => `<option value="${esc(itemTxt(i))}"></option>`).join('')}</datalist></div>
    <div class="row"><div style="flex:1"><label for="rc_yq">${esc(T('yield'))}</label><input id="rc_yq" inputmode="decimal" value="${esc(E.yq)}"></div>
      <div style="flex:1"><label for="rc_yu">${esc(T('unit'))}</label><select id="rc_yu"><option value="">${esc(T('baseUnit'))}</option>${optH(yu.map((u) => [u, unitLabel(u)]), E.yu)}</select></div></div>
    <div><label for="rc_note">${esc(T('note'))}</label><input id="rc_note" autocomplete="off" value="${esc(E.note)}"></div>
    <div class="hint">${esc(T('wasteHint'))}</div>
    <datalist id="rl_dl">${ingredients().map((i) => `<option value="${esc(itemTxt(i))}"></option>`).join('')}</datalist>
    <div id="rc_lines">${E.lines.map(lineHTML).join('')}</div>
    <button class="full" data-act="rc_addline">${esc(T('addLine'))}</button>
    ${E.used || (E.id === null && it && latestActive(it.id)) ? `<button class="tog ${E.retire ? 'on' : ''}" data-act="rc_retire" style="width:100%;justify-content:flex-start">${esc(T('retireOld'))}</button>` : ''}</div>
    <div class="rc-bar"><button data-act="rc_back">${esc(T('cancel'))}</button>${D.canManage ? `<button class="primary" id="rc_go" data-act="rc_save">${esc(T('save'))}</button>` : ''}</div>`, 'recipes');
}
function readEditor() {
  if (!E.id) { E.item = findItem(finished(), ($('#rc_item') || {}).value); }
  E.yq = ($('#rc_yq') || {}).value || ''; E.yu = ($('#rc_yu') || {}).value || ''; E.note = ($('#rc_note') || {}).value || '';
  E.lines.forEach((l, i) => {
    const el = $('#rl_item_' + i); if (el) l.item = findItem(ingredients(), el.value);
    l.qty = ($('#rl_qty_' + i) || {}).value || ''; l.unit = ($('#rl_unit_' + i) || {}).value || ''; l.waste = ($('#rl_w_' + i) || {}).value || ''; l.note = ($('#rl_note_' + i) || {}).value || '';
  });
}
document.addEventListener('input', (e) => {      // the "Data needed" chip follows the waste field while typing
  const m = e.target && /^rl_w_(\d+)$/.exec(e.target.id || ''); if (!m || !E) return;
  const i = m[1], line = e.target.closest('.rc-line'), chip = $('#rl_wc_' + i), empty = String(e.target.value).trim() === '';
  if (empty && !chip && line) { const c = document.createElement('span'); c.className = 'chip warn'; c.id = 'rl_wc_' + i; c.textContent = T('waste') + ': ' + T('needData'); e.target.closest('.row').insertAdjacentElement('afterend', c); } else if (!empty && chip) chip.remove();
});
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !E || !$('#rc_lines')) return;
  if (id === 'rc_item' || /^rl_item_\d+$/.test(id)) { readEditor(); const i = id === 'rc_item' ? -1 : Number(id.split('_')[2]); if (i >= 0 && E.lines[i].item && !unitsFor(E.lines[i].item).includes(E.lines[i].unit)) E.lines[i].unit = ''; if (i < 0) E.yu = ''; drawEditor(); }
});
async function saveEditor(btn) {
  if (E.busy) return; readEditor();
  if (!E.item) return toast(T('needProduct'));
  const yq = nnum(E.yq); if (!(yq > 0)) return toast(T('needQty'));
  if (!E.lines.length) return toast(T('needLines'));
  const lines = [];
  for (const l of E.lines) {
    if (!l.item) return toast(T('needIng'));
    const q = nnum(l.qty); if (!(q > 0)) return toast(T('needQty'));
    const w = String(l.waste).trim() === '' ? null : nnum(l.waste); if (w !== null && !(w >= 0 && w <= 100)) return toast(T('needWaste'));
    lines.push({ ingredient_item_id: l.item.id, qty: q, unit: l.unit || null, waste_pct: w, note: l.note.trim() || null });
  }
  E.busy = true; if (btn) btn.disabled = true;
  try {
    const r = await sb.rpc('recipe_save', { p_id: E.used ? null : E.id, p_item: E.item.id, p_yield_qty: yq, p_yield_unit: E.yu || null, p_note: E.note.trim() || null, p_lines: lines, p_client: E.client, p_retire_old: !!(E.retire && (E.used || !E.id)) });
    if (r.error) return errMsg(r.error);
    toast(T('saved')); E = null; await load(); location.hash = '#/recipes'; if (location.hash === '#/recipes') { D.tab = 'rec'; draw(); }
  } catch (e) { fail(e); } finally { if (E) { E.busy = false; if (btn) btn.disabled = false; } }
}

// ----- production sheet -----
function activeRecipes() { return D.recipes.filter((r) => r.active).sort((a, b) => (itemById(a.item_id)?.code || '').localeCompare(itemById(b.item_id)?.code || '') || b.version - a.version); }
async function openProduction(pre) {
  if (!D.ready) await load();
  const locs = LOCS(), loc = (pre && pre.loc) || (D.loc !== undefined && D.loc !== null ? D.loc : (locs[0] || {}).id);
  const recs = activeRecipes();
  PS = { client: rid(), busy: false, loc, recipe: (pre && pre.recipe) || (recs[0] || {}).id || '', batches: (pre && pre.batches) || '', timer: null, pv: null };
  const now = new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Dhaka' }).replace(' ', 'T').slice(0, 16);
  openSheet(`<h2>${esc(T('pTitle'))}</h2><div class="stack">
    ${locs.length > 1 ? `<div><label for="pr_loc">${esc(T('location'))}</label><select id="pr_loc">${optH(locs.map((l) => [l.id, nm(l)]), loc)}</select></div>` : `<input type="hidden" id="pr_loc" value="${loc}">`}
    <div><label for="pr_rec">${esc(T('recipe'))}</label><select id="pr_rec"><option value="">—</option>${optH(recs.map((r) => [r.id, `${nm(itemById(r.item_id) || {})} · ${T('version')} ${r.version}`]), PS.recipe)}</select></div>
    <div><label for="pr_b">${esc(T('batches'))}</label><input id="pr_b" inputmode="decimal" value="${esc(PS.batches)}"></div>
    <div><label for="pr_made">${esc(T('madeAt'))}</label><input id="pr_made" type="datetime-local" value="${now}"></div>
    <div><label for="pr_note">${esc(T('note'))}</label><input id="pr_note" autocomplete="off"></div>
    <div><label for="pr_ay">${esc(lab(L('আসল ফলন (ঐচ্ছিক — না জানলে খালি রাখুন)', 'Actual yield (optional - leave empty if not measured)', 'আসল ফলন (optional — না জানলে খালি)')))}</label><input id="pr_ay" inputmode="decimal" autocomplete="off"><div class="muted" style="font-size:.8rem">${esc(lab(L('খালি রাখলে স্ট্যান্ডার্ড ফলনই স্টকে ওঠে এবং "আসল ফলন লেখা হয়নি" থাকে। কাগজের ফর্মের কোড: মালিক দেবেন।', 'Empty = the standard yield goes into stock and the run says "actual yield not captured". Paper form code: to be given by owner.', 'খালি থাকলে standard yield stock এ যায়, "actual yield লেখা হয়নি" থাকে। Paper form code: owner দেবেন।')))}</div></div>
    <div id="pr_shelf"></div>
    <div id="pr_c2">${B.c2prod ? B.c2prod.fieldsHTML() : ''}</div>
    <div id="pr_pv"><p class="muted">${esc(T('nothing'))}</p></div></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" id="pr_go" data-act="rc_post">${esc(T('post'))}</button></div>`);
  runPreview();
  if (B.c2prod) B.c2prod.prepare(loc).then(() => { const bx = $('#pr_c2'); if (bx) bx.innerHTML = B.c2prod.fieldsHTML(); }, () => {});      /* RPT-C2: crew / order fields, silent without phases 452 / 457 */
}
function schedulePreview() { if (PS) { clearTimeout(PS.timer); PS.timer = setTimeout(runPreview, 250); } }
async function runPreview() {
  const box = $('#pr_pv'); if (!box || !PS) return;
  PS.loc = Number(($('#pr_loc') || {}).value) || PS.loc; PS.recipe = ($('#pr_rec') || {}).value || ''; PS.batches = ($('#pr_b') || {}).value || '';
  const b = nnum(PS.batches);
  if (!PS.recipe || !(b > 0)) { box.innerHTML = `<p class="muted">${esc(T('nothing'))}</p>`; PS.pv = null; return; }
  const r = await sb.rpc('production_preview', { p_loc: PS.loc, p_recipe: PS.recipe, p_batches: b });
  if (!$('#pr_pv')) return;
  try {                                   // RPT-B3: tell the maker when this product has no shelf-life rule (its batch would get no expiry)
    const sm = await sb.rpc('shelf_life_missing', { p_loc: PS.loc }), rec = (D.recipes || []).find((x) => x.id === PS.recipe), its = (sm && !sm.error && sm.data && sm.data.items) || [], sh = $('#pr_shelf');
    if (sh) sh.innerHTML = its.length && (!rec || its.some((x) => x.item_id === rec.item_id)) ? `<div class="notice warn" data-shelf-missing="1">${esc(lab(L('এই পণ্যের মেয়াদের নিয়ম বসানো নেই — ব্যাচে মেয়াদ থাকবে না', 'Shelf life is NOT set for this product - the batch will get no expiry', 'এই product এর shelf life set নেই — batch এ expiry থাকবে না')))} <button type="button" class="mini" data-act="go" data-v="settings2/shelf">${esc(lab(L('নিয়ম বসান', 'Set it', 'Set করুন')))}</button></div>` : '';
  } catch (e) { /* phase 433 not installed */ }
  if (r.error) { box.innerHTML = `<div class="notice bad">${esc(String(r.error.message || '').slice(0, 120))}</div>`; PS.pv = null; return; }
  const pv = PS.pv = r.data || {}, rows = pv.lines || [];
  box.innerHTML = `<h3 style="margin:6px 0">${esc(T('preview'))}</h3><table class="rc-tbl"><tr><th>${esc(T('ing'))}</th><th class="n">${esc(T('need'))}</th><th class="n">${esc(T('have'))}</th></tr>
    ${rows.map((x) => `<tr><td>${esc(nm(x))}${x.kind === 'packaging' ? ' · ' + esc(T('pkTitle')) : ''}${x.waste_missing ? ` <span class="chip warn">${esc(T('waste'))}: ${esc(T('needData'))}</span>` : ''}${!x.tracked || !x.unit_ok ? ` <span class="chip bad">${esc(T('notTracked'))}</span>` : ''}</td>
      <td class="n">${q4(x.need)} ${esc(unitLabel(x.unit))}</td><td class="n ${Number(x.short) > 0 ? 'rc-need' : ''}">${q4(x.on_hand)}${Number(x.short) > 0 ? `<br><span class="chip bad">${esc(T('short'))} ${q4(x.short)}</span>` : ''}</td></tr>`).join('')}</table>
    <div class="row between" style="margin-top:8px"><span>${esc(T('willMake'))}</span><b class="mnum">${q4(pv.yield_base)} ${esc(unitLabel(pv.yield_unit))}</b></div>
    ${pv.can_make ? '' : `<div class="notice warn" id="pr_short">${esc(T('shortWarn'))}</div>`}`;
}
document.addEventListener('input', (e) => { const id = e.target && e.target.id; if (id === 'pr_b') schedulePreview(); });
document.addEventListener('change', (e) => { const id = e.target && e.target.id; if (id === 'pr_loc' || id === 'pr_rec') runPreview(); });
async function postProduction(btn) {
  if (!PS || PS.busy) return; await runPreview();
  const b = nnum(PS.batches); if (!PS.recipe || !(b > 0)) return toast(T('nothing'));
  const m = ($('#pr_made') || {}).value, note = (($('#pr_note') || {}).value || '').trim() || null;
  const c2x = B.c2prod ? B.c2prod.read() : null; if (c2x && B.c2prod.bad(c2x)) return toast(B.c2prod.bad(c2x));
  PS.busy = true; if (btn) btn.disabled = true;
  try {
    const ayRaw = String(($('#pr_ay') || {}).value || '').trim(), ay = ayRaw === '' ? null : nnum(ayRaw);
    if (ay !== null && !(ay > 0)) { PS.busy = false; if (btn) btn.disabled = false; return toast(T('nothing')); }
    const args = { p_loc: PS.loc, p_recipe: PS.recipe, p_batches: b, p_client: PS.client, p_made_at: m ? m + ':00+06:00' : null, p_note: note };
    if (ay !== null) args.p_actual_yield = ay;                          // blank = the 6-argument call exactly as before
    const r = await sb.rpc('production_post', args);
    if (r.error) return errMsg(r.error, { grant: 'stock_production', loc: PS.loc, context: { recipe: PS.recipe } });
    if (c2x && r.data && r.data.run_id && !r.data.dup) await B.c2prod.save(r.data.run_id, c2x);
    closeSheet(); toast(r.data && r.data.dup ? lab(X.saved) : T('done')); PS = null;
    await load(); if ($('#rc_main')) { if (D.tab === 'make') drawMake(); }
    if ($('#s2_main') && S2().sheetStart) { /* the stock hub refreshes on its next load */ }
  } catch (e) { fail(e); } finally { if (PS) { PS.busy = false; if (btn) btn.disabled = false; } }
}

// ----- what can I make now -----
async function drawMake() {
  const box = $('#rc_main'); if (!box) return; const locs = LOCS();
  if (D.loc === undefined || D.loc === null) D.loc = (locs[0] || {}).id;
  box.innerHTML = `<h3 style="margin:8px 0">${esc(T('makeHead'))}</h3>${locs.length > 1 ? `<div style="margin-bottom:8px"><select id="mk_loc" aria-label="${esc(T('location'))}">${optH(locs.map((l) => [l.id, nm(l)]), D.loc)}</select></div>` : ''}<div id="mk_list"><p class="muted">${esc(T('loading'))}</p></div>`;
  D.canVoid = !!(S.ctx.is_owner || (await sb.rpc('has_grant', { p_code: 'production_void', p_loc: D.loc })).data === true);
  const r = await sb.rpc('production_can_make', { p_loc: D.loc });
  const lst = $('#mk_list'); if (!lst) return;
  if (r.error) { lst.innerHTML = `<div class="notice bad">${esc(String(r.error.message || '').slice(0, 120))}</div>`; return; }
  D.can = (r.data || []).slice().sort((a, b) => (b.max_batches === null ? -1 : Number(b.max_batches)) - (a.max_batches === null ? -1 : Number(a.max_batches)));
  lst.innerHTML = D.can.length ? D.can.map((x, i) => {
    const lim = x.limiting_item_id ? itemById(x.limiting_item_id) : null, mb = x.max_batches, zero = mb !== null && Number(mb) <= 0;
    return `<div class="card item rc-row mk ${zero ? 'bad' : x.unknown ? 'warn' : ''}" data-act="rc_makerow" data-i="${i}" role="button" tabindex="0"><div><div class="nm">${esc(nm(x))}</div>
      <div class="sub">${esc(x.code)} · ${esc(T('yield'))} ${q4(x.yield_per_batch)} ${esc(unitLabel(x.yield_unit))}</div>
      ${lim ? `<div class="sub">${esc(T('limit'))}: ${esc(nm(lim))}</div>` : ''}${x.unknown ? `<span class="chip warn">${esc(T('unknownMake'))}</span>` : ''}</div>
      <div class="pr"><b class="mnum">${mb === null ? '—' : q4(mb)}</b><small>${esc(T('maxB'))}</small></div></div>`; }).join('')
    : `<div class="card center"><p class="muted">${esc(T('makeEmpty'))}</p></div>`;
  if (!$('#mk_runs')) lst.insertAdjacentHTML('afterend', '<div id="mk_runs"></div>');
  drawRuns();
}

// ----- recent runs + void (phase 23) -----
const XR = { head: L('সাম্প্রতিক উৎপাদন', 'Recent production', 'সাম্প্রতিক Production'), void: L('ভয়েড করুন', 'Void', 'Void'), why: L('ভয়েডের কারণ (অন্তত ৩ অক্ষর)', 'Why void (3+ letters)', 'Void-এর কারণ (৩+ অক্ষর)'),
  done: L('উৎপাদন ভয়েড, মাল ফিরেছে', 'Run voided, stock put back', 'Production void, stock ফিরেছে'), voided: L('ভয়েড', 'Voided', 'Voided'), used: L('এই ব্যাচের কিছু বিক্রি হয়ে গেছে — ভয়েড হবে না (অপচয়/কাউন্ট ব্যবহার করুন)', 'Part of this batch is already sold - cannot void (use wastage / count)', 'এই batch-এর কিছু sold - void হবে না (wastage/count ব্যবহার করুন)') };
async function drawRuns() {
  const box = $('#mk_runs'); if (!box) return;
  const r = await sb.from('production_runs').select('id,item_id,batches,made_at,yield_base,status,note').eq('location_id', D.loc).order('made_at', { ascending: false }).limit(15);
  const rows = r.data || []; if (!rows.length) { box.innerHTML = ''; return; }
  box.innerHTML = `<h3 style="margin:14px 0 6px">${esc(lab(XR.head))}</h3>` + rows.map((x) => { const it = itemById(x.item_id);
    return `<div class="card item ${x.status === 'void' ? 'muted' : ''}"><div><div class="nm">${esc(it ? nm(it) : '')}</div><div class="sub">${esc(String(x.made_at).slice(0, 16).replace('T', ' '))} · ${q4(x.batches)} × · ${q4(x.yield_base)} ${x.status === 'void' ? '· ' + esc(lab(XR.voided)) : ''}</div></div>
      ${x.status === 'done' && D.canVoid ? `<button class="mini" data-act="rc_runvoid" data-v="${esc(x.id)}">⋮ ${esc(lab(XR.void))}</button>` : ''}</div>`; }).join('');
}
// ----- packaging -----
function drawPack() {
  const box = $('#rc_main'); if (!box) return;
  const mode = B.rule('packaging_consume_on', 'off');
  const rows = D.pack.slice().sort((a, b) => (itemById(a.product_item_id)?.code || '').localeCompare(itemById(b.product_item_id)?.code || ''));
  box.innerHTML = `<h3 style="margin:8px 0">${esc(T('pkMode'))}</h3>
    <div class="row wrap">${[['off', 'pkOff'], ['sale', 'pkSale'], ['production', 'pkProd']].map(([k, l]) => `<button class="tog ${mode === k ? 'on' : ''}" ${owner() ? `data-act="rc_pkmode" data-v="${k}"` : 'disabled'}>${esc(T(l))}</button>`).join('')}</div>
    <p class="hint">${esc(mode === 'off' ? T('pkOffHint') : mode === 'sale' ? T('pkSaleHint') : T('pkProd'))}</p>
    <h3 style="margin:10px 0 4px">${esc(T('pkTitle'))}</h3>
    ${rows.map((x, i) => { const pr = itemById(x.product_item_id) || {}, pk = itemById(x.packaging_item_id) || {};
      return `<div class="card item rc-row mk ${x.active ? '' : 'bad'}"><div><div class="nm">${esc(nm(pr))}</div><div class="sub">${esc(nm(pk))} × ${q4(x.qty_per_unit)} ${esc(T('pkPer'))} · ${esc(x.applies_to === 'sale' ? T('pkSale2') : T('pkProd2'))}</div>${x.active ? '' : `<span class="chip bad">${esc(T('inactive'))}</span>`}</div>
        <div class="pr"><button type="button" class="rc-dots" data-act="rc_pkmenu" data-i="${i}" aria-label="${esc(T('more'))}">${DOTS}</button></div></div>`; }).join('') || `<div class="card center"><p class="muted">${esc(T('pkNone'))}</p></div>`}
    ${D.canManage ? `<button class="full" style="margin-top:10px" data-act="rc_pkedit">${esc(T('pkAdd'))}</button>` : ''}`;
}
function packSheet(row, productId) {
  const prod = productId || (row && row.product_item_id) || '';
  const prods = D.items.filter((i) => ['finished_good', 'resale'].includes(i.item_type) && i.is_active !== false), packs = D.items.filter((i) => i.item_type === 'packaging' && i.is_active !== false);
  PS_PK = { row, client: rid() };
  openSheet(`<h2>${esc(T('pkAdd'))}</h2><div class="stack">
    <div><label for="pk_prod">${esc(T('pkProduct'))}</label><input id="pk_prod" list="pk_pl" autocomplete="off" value="${esc(prod ? itemTxt(itemById(prod)) : '')}" ${row ? 'disabled' : ''}><datalist id="pk_pl">${prods.map((i) => `<option value="${esc(itemTxt(i))}"></option>`).join('')}</datalist></div>
    <div><label for="pk_item">${esc(T('pkItem'))}</label><input id="pk_item" list="pk_il" autocomplete="off" value="${esc(row ? itemTxt(itemById(row.packaging_item_id)) : '')}" ${row ? 'disabled' : ''}><datalist id="pk_il">${packs.map((i) => `<option value="${esc(itemTxt(i))}"></option>`).join('')}</datalist></div>
    <div class="row"><div style="flex:1"><label for="pk_q">${esc(T('qty'))} (${esc(T('pkPer'))})</label><input id="pk_q" inputmode="decimal" value="${row ? esc(String(row.qty_per_unit)) : ''}"></div>
      <div style="flex:1"><label for="pk_ap">${esc(T('pkApplies'))}</label><select id="pk_ap" ${row ? 'disabled' : ''}>${optH([['sale', T('pkSale2')], ['production', T('pkProd2')]], row ? row.applies_to : 'sale')}</select></div></div>
    <button class="tog ${!row || row.active ? 'on' : ''}" id="pk_act" data-act="sheettog" style="width:100%;justify-content:flex-start">${esc(T('fActive'))}</button></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="rc_pksave">${esc(T('save'))}</button></div>`);
}
let PS_PK = null;

// ----- cost -----
async function costSheet(r) {
  openSheet(`<h2>${esc(T('cHead'))}</h2><p class="muted">${esc(T('loading'))}</p>`);
  const c = await sb.rpc('recipe_cost', { p_recipe: r.id, p_loc: null });
  if (c.error) { closeSheet(); return errMsg(c.error); }
  const d = c.data || {}, it = itemById(r.item_id) || {};
  openSheet(`<h2>${esc(nm(it))} · ${esc(T('version'))} ${r.version}</h2><table class="rc-tbl"><tr><th>${esc(T('ing'))}</th><th class="n">${esc(T('cAvg'))}</th><th class="n">${esc(T('cHead'))}</th></tr>
    ${(d.lines || []).map((x) => `<tr><td>${esc(nm(itemById(x.ingredient_item_id) || { name_bn: x.code }))}${x.waste_missing ? ` <span class="chip warn">${esc(T('waste'))}: ${esc(T('needData'))}</span>` : ''}</td>
      <td class="n">${x.unit_cost === null || x.unit_cost === undefined ? `<span class="chip warn">${esc(T('needData'))}</span>` : esc(money(x.unit_cost))}</td><td class="n">${x.line_cost === null || x.line_cost === undefined ? '—' : esc(money(x.line_cost))}</td></tr>`).join('')}</table>
    ${d.complete ? `<div class="row between" style="margin-top:8px"><span>${esc(T('cBatch'))}</span><b class="mnum">${esc(money(d.batch_cost))}</b></div><div class="row between"><span class="muted">${esc(T('cUnit'))}</span><span>${esc(money(d.unit_cost))}</span></div>` : `<div class="notice warn">${esc(T('cPartial'))}</div>`}
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ---------- handlers ----------
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'rc_q') { D.q = e.target.value; drawList(); const q = $('#rc_q'); if (q) { q.focus(); q.setSelectionRange(q.value.length, q.value.length); } } });
const rec = (a) => D.recipes.find((r) => r.id === a.dataset.id);
Object.assign(H, {
  rc_runvoid: async (a) => { const n = window.prompt(lab(XR.why)); if (!n || n.trim().length < 3) return;
    const r = await sb.rpc('production_void', { p_run: a.dataset.v, p_note: n.trim() });
    if (r.error) return toast(/batch_partly_used/.test(r.error.message || '') ? lab(XR.used) : errMsg(r.error)); toast(lab(XR.done)); drawMake(); },
  rc_tab: (a) => { D.tab = a.dataset.v; draw(); },
  rc_f: (a) => { D.f = a.dataset.v; drawList(); },
  rc_cat: (a) => { D.cs = a.dataset.cat || a.dataset.sub ? { cat: a.dataset.cat, sub: a.dataset.sub } : null; drawList(); },   // bos100
  rc_new: () => { location.hash = '#/recipes/new'; },
  rc_open: (a) => { closeSheet(); const r = rec(a); if (r) location.hash = '#/recipes/' + r.id; },
  rc_menu: (a) => { const r = rec(a); if (r) menu(r); },
  rc_newver: (a) => { closeSheet(); const r = rec(a); if (r) { D.newver = r.id; location.hash = '#/recipes/' + r.id; } },
  rc_toggle: async (a) => { const r = rec(a); if (!r) return; closeSheet(); const x = await sb.rpc('recipe_set_active', { p_id: r.id, p_active: !r.active }); if (x.error) return errMsg(x.error); toast(T('saved')); await load(); draw(); },
  rc_dup: (a) => { const r = rec(a); if (!r) return; const prods = finished();
    openSheet(`<h2>${esc(T('mDup'))}</h2><div><label for="dp_item">${esc(T('dupTo'))}</label><input id="dp_item" list="dp_dl" autocomplete="off" placeholder="${esc(T('productPh'))}"><datalist id="dp_dl">${prods.map((i) => `<option value="${esc(itemTxt(i))}"></option>`).join('')}</datalist></div>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="rc_dupgo" data-id="${r.id}">${esc(T('copyGo'))}</button></div>`); },
  rc_dupgo: async (a) => { const it = findItem(finished(), ($('#dp_item') || {}).value); if (!it) return toast(T('needProduct'));
    const x = await sb.rpc('recipe_copy', { p_from: a.dataset.id, p_item: it.id, p_retire_old: false, p_client: rid() }); if (x.error) return errMsg(x.error); closeSheet(); toast(T('copied')); await load(); draw(); },
  rc_pack: (a) => { closeSheet(); const r = rec(a); D.tab = 'pack'; draw(); if (r) setTimeout(() => packSheet(null, r.item_id), 0); },
  rc_cost: (a) => { closeSheet(); const r = rec(a); if (r) costSheet(r); },
  rc_make: (a) => { closeSheet(); const r = rec(a); openProduction({ recipe: r && r.id }); },
  rc_makerow: (a) => { const x = (D.can || [])[Number(a.dataset.i)]; if (x) openProduction({ recipe: x.recipe_id, loc: D.loc, batches: x.max_batches && Number(x.max_batches) >= 1 ? '1' : '' }); },
  rc_post: postProduction,
  rc_addline: () => { readEditor(); E.lines.push({ item: null, qty: '', unit: '', waste: '', note: '' }); drawEditor(); },
  rc_rmline: (a) => { readEditor(); E.lines.splice(Number(a.dataset.i), 1); drawEditor(); },
  rc_retire: () => { readEditor(); E.retire = !E.retire; drawEditor(); },
  rc_back: () => { E = null; location.hash = '#/recipes'; },
  rc_save: saveEditor,
  rc_pkmode: async (a) => { const x = await sb.rpc('set_rule', { p_key: 'packaging_consume_on', p_value: a.dataset.v }); if (x.error) return errMsg(x.error); try { await B.reloadRules(); } catch (e) { /* keep going */ } toast(T('saved')); drawPack(); },
  rc_pkedit: () => packSheet(null, null),
  rc_pkmenu: (a) => { const row = D.pack.slice().sort((p, q) => (itemById(p.product_item_id)?.code || '').localeCompare(itemById(q.product_item_id)?.code || ''))[Number(a.dataset.i)]; if (row && D.canManage) packSheet(row); },
  rc_pksave: async () => {
    const row = PS_PK && PS_PK.row, prod = row ? itemById(row.product_item_id) : findItem(D.items.filter((i) => ['finished_good', 'resale'].includes(i.item_type)), ($('#pk_prod') || {}).value);
    const pkg = row ? itemById(row.packaging_item_id) : findItem(D.items.filter((i) => i.item_type === 'packaging'), ($('#pk_item') || {}).value);
    if (!prod) return toast(T('needProduct')); if (!pkg) return toast(T('needIng')); const q = nnum(($('#pk_q') || {}).value); if (!(q > 0)) return toast(T('needQty'));
    const x = await sb.rpc('packaging_set', { p_product: prod.id, p_packaging: pkg.id, p_qty: q, p_applies: ($('#pk_ap') || {}).value || 'sale', p_active: $('#pk_act').classList.contains('on'), p_note: null });
    if (x.error) return errMsg(x.error); closeSheet(); toast(T('saved')); await load(); drawPack(); },
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'mk_loc') { D.loc = Number(e.target.value); drawMake(); } });

// ---------- shared API: the stock hub's "Production in" sheet offers a recipe button ----------
B.recipes = {
  prodButton: () => `<button class="full" data-act="rc_prodopen" style="margin-bottom:8px">${esc(T('useRecipe'))}</button>`,
  openProduction: (loc) => { closeSheet(); openProduction({ loc }); },
};
H.rc_prodopen = () => { const l = $('#a_loc'); closeSheet(); openProduction({ loc: l ? Number(l.value) || undefined : undefined }); };
// friendly texts for the new server codes everywhere the stock errors are shown
if (S2().ERR) Object.assign(S2().ERR, ERRS);

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { recipes: view });
})();
