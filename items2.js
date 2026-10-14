/* Islamia BOS · Products (items) v2: list with search + filter sheet, and the Add / Edit product page with Advance Options.
   Replaces the items screen at #/items (and #/items/new, #/items/edit/<id>); the old item-change workflow is unchanged:
   saves go through submit_item_change -> apply_item_patch (owner applies at once, everyone else waits for approval).
   Cost price is shown only to people who may see ITEM_COST. Loaded after app.js / entry.js / barcode.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, go } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const money = (n) => '৳ ' + fmt(n);
const MAXIMG = 5, PAGE = 50;

// ---------- labels (3 modes; Bng-Eng is hyphen-free Bangla + English words) ----------
const X = {
  title: L('পণ্য ও দাম', 'Products & prices', 'Product ও Price'), search: L('নাম, কোড বা বারকোড খুঁজুন', 'Search name, code or barcode', 'নাম, code বা barcode খুঁজুন'),
  filter: L('ফিল্টার', 'Filter', 'Filter'), add: L('নতুন পণ্য', 'Add product', 'নতুন Product'), edit: L('পণ্য বদলান', 'Edit product', 'Product বদলান'),
  count: L('টি পণ্য', 'products', 'products'), more: L('আরও দেখুন', 'Show more', 'আরও দেখুন'), none: L('কোনো পণ্য নেই', 'No products', 'কোনো product নেই'),
  all: L('সব', 'All', 'All'), cat: L('ক্যাটাগরি', 'Category', 'Category'), sub: L('সাব-ক্যাটাগরি', 'Sub-category', 'Sub-category'), src: L('উৎস', 'Source', 'Source'),
  made: L('নিজে তৈরি', 'Made here', 'নিজে made'), bought: L('কিনে বিক্রি', 'Bought in', 'Bought in'), tracked: L('স্টক ট্র্যাক', 'Stock tracked', 'Stock tracked'),
  untracked: L('স্টক ট্র্যাক নয়', 'Not tracked', 'Tracked নয়'), low: L('কম-স্টক সতর্কতা দেওয়া আছে', 'Low-stock alert is set', 'Low-stock alert দেওয়া আছে'),
  lowchip: L('সতর্কতা ≤ ', 'Alert ≤ ', 'Alert ≤ '), active: L('সক্রিয়', 'Active', 'Active'), inactive: L('বন্ধ', 'Inactive', 'Inactive'), apply: L('প্রয়োগ', 'Apply', 'Apply'), reset: L('মুছে দিন', 'Reset', 'Reset'),
  wholesale: L('পাইকারি', 'Wholesale', 'Wholesale'), cost: L('ক্রয়', 'Cost', 'Cost'), pending: L('অনুমোদনের অপেক্ষায় থাকা বদল', 'Changes waiting for approval', 'Approval-এর অপেক্ষায় বদল'),
  conv: L('একক রূপান্তর', 'Unit conversions', 'Unit conversion'), yes: L('হ্যাঁ', 'Yes', 'Yes'), no: L('না', 'No', 'No'), unset: L('ঠিক হয়নি', 'Not decided', 'Not decided'),
  // form
  name: L('পণ্যের নাম (বাংলা) *', 'Product name (Bangla) *', 'Product নাম (বাংলা) *'), name_en: L('ইংরেজি নাম', 'English name', 'English নাম'), name_mix: L('Bng-Eng নাম', 'Bng-Eng name', 'Bng-Eng নাম'),
  sell: L('বিক্রয়মূল্য ৳ *', 'Selling price ৳ *', 'Selling Price ৳ *'), whs: L('পাইকারি দাম ৳', 'Wholesale price ৳', 'Wholesale Price ৳'), cost_l: L('ক্রয়মূল্য ৳', 'Buying price ৳', 'Buying Price ৳'),
  adv: L('অ্যাডভান্স অপশন', 'Advance options', 'Advance Option'), unit: L('একক', 'Unit', 'Unit'), base: L('বেস একক', 'Base unit', 'Base unit'), sellu: L('বিক্রির একক (একাধিক)', 'Selling units (many)', 'Selling unit (একাধিক)'),
  whon: L('পাইকারি দাম চালু', 'Wholesale price on', 'Wholesale price চালু'), lowon: L('কম-স্টক সতর্কতা', 'Low-stock alert', 'Low-stock alert'), minst: L('ন্যূনতম স্টক', 'Minimum stock', 'Minimum stock'),
  vat: L('ভ্যাট প্রযোজ্য', 'VAT applicable', 'VAT applicable'), source: L('পণ্যের উৎস', 'Product source', 'Product source'), trk: L('স্টক ট্র্যাক করুন', 'Track stock', 'Stock track করুন'),
  actv: L('সক্রিয়', 'Active', 'Active'), images: L('ছবি (সর্বোচ্চ ৫)', 'Images (max 5)', 'Image (max ৫)'), addimg: L('ছবি যোগ', 'Add image', 'Image যোগ'), barcode: L('বারকোড', 'Barcode', 'Barcode'), scan: L('স্ক্যান', 'Scan', 'Scan'),
  newcat: L('নতুন ক্যাটাগরির নাম', 'New category name', 'নতুন Category নাম'), newsub: L('নতুন সাব-ক্যাটাগরির নাম', 'New sub-category name', 'নতুন Sub-category নাম'), plus: L('নতুন', 'New', 'New'),
  note: L('বদলের কারণ (ঐচ্ছিক)', 'Reason (optional)', 'বদলের reason (ঐচ্ছিক)'), save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'),
  needname: L('পণ্যের নাম লিখুন', 'Enter the product name', 'Product নাম লিখুন'), badprice: L('দাম ঠিক নয়', 'Price is not valid', 'Price ঠিক নয়'), needsell: L('বিক্রয়মূল্য লিখুন', 'Enter the selling price', 'Selling price লিখুন'),
  needwh: L('পাইকারি দাম লিখুন', 'Enter the wholesale price', 'Wholesale price লিখুন'), needmin: L('ন্যূনতম স্টক লিখুন', 'Enter the minimum stock', 'Minimum stock লিখুন'),
  dupbc: L('এই বারকোড অন্য পণ্যে আছে', 'This barcode is already used by another product', 'এই barcode অন্য product-এ আছে'),
  convh: L('এই পণ্যের একক রূপান্তর', 'Conversions for this product', 'এই product-এর unit conversion'), convnone: L('কোনো রূপান্তর লেখা নেই', 'No conversion written', 'কোনো conversion লেখা নেই'),
  convedit: L('রূপান্তর বদলান', 'Edit conversions', 'Conversion বদলান'), convall: L('সব পণ্যের জন্য', 'for all products', 'সব product-এর জন্য'),
  upl: L('ছবি আপলোড হচ্ছে…', 'Uploading image…', 'Image upload হচ্ছে…'), maximg: L('সর্বোচ্চ ৫টি ছবি', 'At most 5 images', 'সর্বোচ্চ ৫টি image'),
  appr: L('আপনার বদল অনুমোদনের জন্য গেছে।', 'Your change was sent for approval.', 'আপনার বদল approval-এর জন্য গেছে।'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  nochange: L('কোনো বদল নেই', 'Nothing changed', 'কোনো বদল নেই'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  vatoff: L('ভ্যাট সেটিংসে বন্ধ আছে', 'VAT is off in Settings', 'VAT Settings-এ বন্ধ'),
  details: L('বিবরণ', 'Details', 'Details'), detailsph: L('উপাদান, ওজন, নোট…', 'Ingredients, weight, notes…', 'Ingredients, weight, notes…'),
  lowNow: L('এখন স্টক কম', 'Low stock now', 'এখন stock কম'), lowNowH: L('শুধু ন্যূনতম স্টকের নিচে থাকা পণ্য (স্টকের হিসাব থেকে)', 'Only products below their minimum stock (from the stock ledger)', 'শুধু minimum stock-এর নিচে থাকা product (stock ledger থেকে)'),
  type: L('ধরন', 'Type', 'Type'), flagf: L('ফ্ল্যাগ', 'Flag', 'Flag'), fl_locked: L('লক করা', 'Locked', 'Locked'), fl_hidden: L('লুকানো', 'Hidden', 'Hidden'), fl_nocount: L('ব্যবসার হিসাবে নেই', 'Not counted in business', 'Business-এর হিসাবে নেই'),
  fl_notype: L('টাইপ নেই', 'No type', 'Type নেই'), fl_unpriced_fg: L('দাম-ছাড়া তৈরি পণ্য / কিনে-বিক্রি (দাম দিন বা লুকান)', 'Unpriced finished goods / resale (to price or hide)', 'দাম-ছাড়া finished / resale (দাম দিন বা লুকান)'), oldlist: L('পুরনো তালিকা', 'Old list', 'পুরনো list'), openbulk: L('একসাথে বদলের পাতায় খুলুন', 'Open in the bulk editor', 'Bulk editor-এ খুলুন'), pbulk: L('আইটেম একসাথে বদল', 'Bulk item editor', 'Item একসাথে বদল'),
  fl_noprice: L('দাম নেই (Data needed)', 'No price (Data needed)', 'দাম নেই (Data needed)'), fl_retired: L('অবসরপ্রাপ্ত', 'Retired', 'Retired'), fl_master: L('মাস্টার কোডে মেলানো', 'Linked to a master code', 'Master code-এ linked'),
  dneeded: L('Data needed', 'Data needed', 'Data needed'), more2: L('আরও অপশন', 'More options', 'আরও Option'), pimp: L('আইটেম মাস্টার ইমপোর্ট', 'Item master import', 'Item master import'), pmap: L('পুরনো আইটেম মেলানো', 'Old items to master codes', 'পুরনো Item মেলানো'),
  ptypes: L('আইটেমের ধরন ও ডিফল্ট', 'Item types & defaults', 'Item type ও Default'), passets: L('সম্পদ-খাতা', 'Asset register', 'Asset register'), bycat: L('ক্যাটাগরি ধরে', 'By category', 'Category ধরে'),
  lowNoMin: L('ন্যূনতম স্টক না থাকলে কম-স্টক চিহ্ন হয় না', 'A product without a minimum stock is never flagged', 'Minimum stock না থাকলে low-stock চিহ্ন হয় না'), onHand: L('আছে', 'on hand', 'on hand'),
};
const T = (k) => lab(X[k]);
const LEG = { kg: L('কেজি', 'KG', 'KG'), pc: L('পিস', 'Piece', 'Piece'), lb: L('পাউন্ড', 'Pound', 'Pound') };
const ALIAS = { pc: 'piece', lb: 'pound' };                     // old item codes vs the editable units list
const CATLEG = {
  sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'),
  cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)'),
};
const rl = (r) => ({ bn: r.label_bn || r.label_en || r.value_code, en: r.label_en || undefined, mix: r.label_mix || undefined });

// ---------- state ----------
const D = { items: [], cost: new Map(), canCost: false, conv: [], ready: false, low: new Map(), lowOk: false, master: false };
const Fl = { q: '', cat: '', sub: '', source: '', tracked: '', low: false, lowNow: false, active: '', type: '', cls: '', flag: '' };
let shown = PAGE;
let F = null;                          // the open form: { id, cur, images, vat, ... }

const perms = () => (S.ctx && S.ctx.perms) || {};
const canEnter = () => !!(S.ctx.is_owner || (perms().ITEMS && perms().ITEMS.enter));
const canCostEnter = () => !!(S.ctx.is_owner || (perms().ITEM_COST && perms().ITEM_COST.enter));
const lists = (c) => ((B.ENV && B.ENV.lists && B.ENV.lists[c]) || []).filter((r) => r.active !== false);
const unitRow = (code) => lists('units').find((r) => r.value_code === code);

async function load() {
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  try { if (B.itemMaster) await B.itemMaster.init(); } catch (e) { /* item master not installed */ }
  const wantCost = !!(S.ctx.is_owner || (perms().ITEM_COST && perms().ITEM_COST.view));
  const [it, co, cv, lv] = await Promise.all([window.BOS_ALL(sb.from('items').select('*').order('code')), wantCost ? sb.from('item_costs').select('*') : Promise.resolve({ data: [] }),
    sb.from('unit_conversions').select('*').order('id'), lowLevels()]);
  if (it.error) throw it.error;
  D.canCost = wantCost && !co.error;
  D.cost = new Map((co.data || []).map((c) => [c.item_id, c.cost_price]));
  // only the grant view_cost (no ITEM_COST right): the costs come through a small server function instead of the table (phase12)
  if (!D.canCost) {
    try {
      const g = await sb.rpc('has_grant', { p_code: 'view_cost' });
      if (g && !g.error && g.data === true) { const r = await sb.rpc('items_with_cost'); if (r && !r.error && Array.isArray(r.data)) { D.canCost = true; D.cost = new Map(r.data.map((c) => [c.item_id, c.cost_price])); } }
    } catch (e) { /* no costs */ }
  }
  D.low = lv;
  D.items = it.data || [];
  D.master = !!(B.itemMaster && B.itemMaster.on() && D.items.length && D.items.some((i) => i.item_type !== undefined));
  D.conv = cv.error ? [] : (cv.data || []).filter((c) => c.active !== false);
  D.ready = true;
}

// items below their minimum stock now: the server's stock_levels (min_stock flag); no minimum = never flagged, nothing is guessed
async function lowLevels() {
  const m = new Map(); D.lowOk = false;
  try {
    const r = await sb.rpc('stock_levels', { p_loc: null, p_filters: { below_min: true } });
    if (r && !r.error && Array.isArray(r.data)) { D.lowOk = true; r.data.forEach((x) => { if (x.below_min && (!m.has(x.item_id) || Number(x.qty) < m.get(x.item_id).qty)) m.set(x.item_id, { qty: Number(x.qty), min: x.min_stock, unit: x.base_unit }); }); }
  } catch (e) { /* stock part not installed: no low-stock marks */ }
  return m;
}
// ---------- option lists (category / sub-category / units) ----------
function catMap() {
  const m = new Map();
  lists('item_categories').forEach((r) => m.set(r.value_code, rl(r)));
  D.items.forEach((i) => { if (i.category && !m.has(i.category)) m.set(i.category, CATLEG[i.category] || { bn: i.category_bn || i.category }); });
  return m;
}
const catLabel = (code) => { if (!code) return ''; const r = lists('item_categories').find((x) => x.value_code === code); if (r) return lab(rl(r)); if (CATLEG[code]) return lab(CATLEG[code]) + ' (' + T('oldlist') + ')'; const i = D.items.find((x) => x.category === code); return (i && i.category_bn) || code; };
function subMap() {
  const m = new Map();
  lists('item_subcategories').forEach((r) => m.set(r.value_code, rl(r)));
  D.items.forEach((i) => { if (i.sub_category && !m.has(i.sub_category)) m.set(i.sub_category, { bn: i.sub_category, en: i.sub_category }); });
  return m;
}
const subLabel = (code) => { if (!code) return ''; const r = lists('item_subcategories').find((x) => x.value_code === code); return r ? lab(rl(r)) : code; };
function itemUnitOpts(cur) {            // the unit of an item: old POS codes first, labels follow the editable units list
  const out = Object.keys(LEG).map((k) => { const r = unitRow(k) || unitRow(ALIAS[k]); return [k, r ? rl(r) : LEG[k]]; });
  lists('units').forEach((r) => { if (!LEG[r.value_code] && !Object.values(ALIAS).includes(r.value_code)) out.push([r.value_code, rl(r)]); });
  if (cur && !out.some((o) => o[0] === cur)) out.push([cur, { bn: cur, en: cur }]);
  return out;
}
function listUnitOpts() {              // base unit and selling units use the same codes as unit conversions
  const rows = lists('units');
  const out = rows.length ? rows.map((r) => [r.value_code, rl(r)]) : ['kg', 'piece', 'box', 'pack', 'pound', 'gram'].map((c) => [c, { bn: c, en: c }]);
  return out;
}
const unitName = (code) => { const r = unitRow(code) || unitRow(ALIAS[code]); return r ? lab(rl(r)) : LEG[code] ? lab(LEG[code]) : (code || ''); };

// ---------- list ----------
function matches(i) {
  const q = Fl.q.trim().toLowerCase();
  if (q && ![i.name_bn, i.name_en, i.name_mix, i.code, i.barcode].some((x) => (x || '').toLowerCase().includes(q))) return false;
  if (Fl.cat && i.category !== Fl.cat) return false;
  if (Fl.sub && i.sub_category !== Fl.sub) return false;
  if (Fl.source && i.source !== Fl.source) return false;
  if (Fl.tracked === 'yes' && !i.tracked) return false;
  if (Fl.tracked === 'no' && i.tracked) return false;
  if (Fl.low && !(i.min_stock !== null && i.min_stock !== undefined)) return false;
  if (Fl.lowNow && !D.low.has(i.id)) return false;
  if (Fl.active === 'yes' && !i.is_active) return false;
  if (Fl.active === 'no' && i.is_active) return false;
  if (Fl.type && i.item_type !== Fl.type) return false;
  if (Fl.cls && i.control_class !== Fl.cls) return false;
  if (Fl.flag === 'locked' && !i.locked) return false; if (Fl.flag === 'hidden' && !i.hidden) return false; if (Fl.flag === 'nocount' && i.count_in_business !== false) return false;
  if (Fl.flag === 'unpriced_fg' && !(i.sell_price === null || i.sell_price === undefined) ) return false; if (Fl.flag === 'unpriced_fg' && !(['finished_good', 'resale'].includes(i.item_type) && i.is_active && !i.hidden)) return false; if (Fl.flag === 'noprice' && !(i.sell_price === null || i.sell_price === undefined)) return false; if (Fl.flag === 'retired' && !i.retired_at) return false; if (Fl.flag === 'master' && !i.master_code) return false;
  return true;
}
const nFilters = () => ['cat', 'sub', 'source', 'tracked', 'active', 'type', 'flag'].filter((k) => Fl[k]).length + (Fl.low ? 1 : 0) + (Fl.lowNow ? 1 : 0);
function chipsHTML() {
  const c = [];
  if (Fl.cat) c.push(['cat', catLabel(Fl.cat)]); if (Fl.sub) c.push(['sub', subLabel(Fl.sub)]);
  if (Fl.source) c.push(['source', T(Fl.source)]); if (Fl.tracked) c.push(['tracked', Fl.tracked === 'yes' ? T('tracked') : T('untracked')]);
  if (Fl.low) c.push(['low', T('low')]); if (Fl.lowNow) c.push(['lowNow', T('lowNow')]); if (Fl.active) c.push(['active', Fl.active === 'yes' ? T('active') : T('inactive')]);
  if (Fl.cls) c.push(['cls', Fl.cls]);
  if (Fl.type) c.push(['type', B.itemMaster ? B.itemMaster.typeLabel(Fl.type) : Fl.type]); if (Fl.flag) c.push(['flag', T('fl_' + Fl.flag)]);
  return c.map(([k, l]) => `<button type="button" class="chip" data-act="p2_chip_x" data-k="${k}" aria-label="${esc(l)} ✕">${esc(l)} ✕</button>`).join('');
}
function rowHTML(i) {
  const cost = D.canCost ? D.cost.get(i.id) : undefined;
  const loss = cost !== undefined && cost !== null && i.sell_price !== null && Number(cost) >= Number(i.sell_price);
  const sub = [i.code, catLabel(i.category) + (i.sub_category ? ' · ' + subLabel(i.sub_category) : ''), unitName(i.unit)].filter(Boolean).join(' · ');
  const lw = D.low.get(i.id);
  const mt = D.master ? [i.item_type ? `<span class="chip info">${esc(B.itemMaster.typeLabel(i.item_type))}</span>` : '', i.locked ? `<span class="chip warn">${esc(T('fl_locked'))}</span>` : '', i.hidden ? `<span class="chip">${esc(T('fl_hidden'))}</span>` : '',
    i.count_in_business === false ? `<span class="chip">${esc(T('fl_nocount'))}</span>` : '', i.retired_at ? `<span class="chip bad">${esc(T('fl_retired'))}</span>` : ''].join('') : '';
  const tags = [mt, lw ? `<span class="chip warn">${esc(T('lowNow'))} · ${fmt(lw.qty)} ${esc(unitName(lw.unit))}</span>` : '', i.tracked ? `<span class="chip info">${esc(T('tracked'))}</span>` : '', i.is_active ? '' : `<span class="chip bad">${esc(T('inactive'))}</span>`,
    i.min_stock !== null && i.min_stock !== undefined ? `<span class="chip warn">${esc(T('lowchip'))}${fmt(i.min_stock)}</span>` : '', loss ? `<span class="chip warn">${esc(t('loss_warn'))}</span>` : ''].join('');
  const act = canEnter() ? `data-act="itemedit" data-v="${esc(i.id)}" role="button" tabindex="0"` : '';
  return `<div class="card p2-row mk ${lw ? 'warn' : ''}" ${act} data-cat="${esc(i.category || '')}"><div><div class="nm">${esc(nm(i))}</div><div class="sub">${esc(sub)}</div>${tags ? `<div class="tags">${tags}</div>` : ''}</div>
    <div class="pr">${D.master ? `<button type="button" class="mini im-dots" data-act="im_menu" data-v="${esc(i.id)}" aria-label="${esc(T('more2'))}">⋮</button>` : ''}<b>${i.sell_price === null || i.sell_price === undefined ? (D.master ? `<span class="muted" style="font-size:.85rem">${esc(T('dneeded'))}</span>` : '—') : money(i.sell_price)}</b>
      ${i.wholesale_price !== null && i.wholesale_price !== undefined ? `<small>${esc(T('wholesale'))} ${money(i.wholesale_price)}</small>` : ''}
      ${cost !== undefined ? `<small>${esc(T('cost'))} ${cost === null ? '—' : money(cost)}</small>` : ''}</div></div>`;
}
function drawList() {
  const el = $('#p2_list'); if (!el) return;
  const rows = D.items.filter(matches);
  el.innerHTML = rows.slice(0, shown).map(rowHTML).join('') || `<p class="muted center">${esc(T('none'))}</p>`;
  const more = $('#p2_more'); if (more) more.hidden = rows.length <= shown;
  const c = $('#p2_count'); if (c) c.textContent = rows.length + ' ' + T('count');
  const ch = $('#p2_chips'); if (ch) ch.innerHTML = chipsHTML();
  const fb = $('#p2_fb .cnt'); if (fb) { fb.textContent = nFilters(); fb.hidden = !nFilters(); }
}
async function viewList() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'home');
  try { await load(); } catch (e) { return fail(e); }
  shown = PAGE;
  const canNew = canEnter();
  shell(T('title'), `<div class="p2-bar"><input id="p2_q" type="search" placeholder="${esc(T('search'))}" value="${esc(Fl.q)}" aria-label="${esc(T('search'))}" autocomplete="off">
      <button id="p2_fb" class="p2-fb" data-act="p2_filter" aria-label="${esc(T('filter'))}">${esc(T('filter'))}<span class="cnt" ${nFilters() ? '' : 'hidden'}>${nFilters()}</span></button>
      ${canNew ? `<button class="primary" data-act="itemnew" aria-label="${esc(T('add'))}">＋</button>` : ''}${canNew && D.master ? `<button data-act="im_bycat" aria-label="${esc(T('bycat'))}">${esc(T('bycat'))}</button>` : ''}${D.master ? `<button class="mini im-dots" data-act="p2_pagemenu" aria-label="${esc(T('more2'))}">⋮</button>` : ''}</div>
    ${D.master ? `<div class="row wrap" style="gap:6px;margin:4px 0"><button type="button" class="chip ${Fl.flag === 'unpriced_fg' ? 'warn' : ''}" id="p2_fg" data-act="p2_fg">${esc(T('fl_unpriced_fg'))} · <span id="p2_fgn">${D.items.filter((i) => ['finished_good', 'resale'].includes(i.item_type) && i.is_active && !i.hidden && (i.sell_price === null || i.sell_price === undefined)).length}</span></button>${Fl.flag === 'unpriced_fg' && canEnter() ? `<button type="button" class="chip info" data-act="p2_fg_bulk">${esc(T('openbulk'))} ›</button>` : ''}</div>` : ''}
    ${D.master ? `<div id="p2_badges">${badgesHTML()}</div>` : ''}
    <div class="p2-chips" id="p2_chips"></div>
    <div class="row between muted" style="font-size:.88rem"><span id="p2_count"></span><span class="row">${canNew || S.ctx.is_owner ? `<a href="#/itemreq">${esc(T('pending'))}</a>` : ''}</span></div>
    <div id="p2_list"></div><button class="full" id="p2_more" data-act="p2_more" hidden>${esc(T('more'))}</button>`, 'home');
  drawList();
}
// count badges: how many products of each type / dictionary class (active, not retired); a tap filters the list by it, a second tap clears
function badgesHTML() {
  const live = D.items.filter((i) => i.is_active && !i.retired_at), cnt = (k) => live.reduce((m, i) => { const v = i[k]; if (v) m[v] = (m[v] || 0) + 1; return m; }, {});
  const t = cnt('item_type'), c = cnt('control_class'), none = live.filter((i) => !i.item_type).length;
  const chip = (act, v, label, n, on) => `<button type="button" class="chip ${on ? 'info' : ''}" data-act="${act}" data-v="${esc(v)}" aria-pressed="${on}">${esc(label)} <b>${n}</b></button>`;
  const types = Object.keys(t).sort((a, b) => t[b] - t[a]).map((k) => chip('p2_btype', k, B.itemMaster ? B.itemMaster.typeLabel(k) : k, t[k], Fl.type === k)).join('');
  const classes = Object.keys(c).sort((a, b) => c[b] - c[a]).map((k) => chip('p2_bcls', k, k, c[k], Fl.cls === k)).join('');
  return `<div class="row wrap" style="gap:6px;margin:4px 0">${types}${none ? `<span class="chip warn">${esc(T('fl_notype'))} <b>${none}</b></span>` : ''}</div>${classes ? `<div class="row wrap" style="gap:6px;margin:4px 0">${classes}</div>` : ''}`;
}
function filterSheet() {
  const sel = (id, opts, cur) => `<select id="${id}"><option value="">${esc(T('all'))}</option>${opts.map(([v, l]) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
  openSheet(`<h2>${esc(T('filter'))}</h2><div class="stack">
    <div><label>${esc(T('cat'))}</label>${sel('ff_cat', [...catMap().keys()].map((c) => [c, catLabel(c)]), Fl.cat)}</div>
    <div><label>${esc(T('sub'))}</label>${sel('ff_sub', [...subMap().keys()].map((c) => [c, subLabel(c)]), Fl.sub)}</div>
    <div><label>${esc(T('src'))}</label>${sel('ff_src', [['made', T('made')], ['bought', T('bought')]], Fl.source)}</div>
    <div><label>${esc(T('tracked'))}</label>${sel('ff_trk', [['yes', T('yes')], ['no', T('no')]], Fl.tracked)}</div>
    <div><label>${esc(T('active'))}</label>${sel('ff_act', [['yes', T('active')], ['no', T('inactive')]], Fl.active)}</div>
    ${D.master ? `<div><label>${esc(T('type'))}</label>${sel('ff_type', B.itemMaster.types().map((x) => [x.code, B.itemMaster.typeLabel(x.code)]), Fl.type)}</div>
    <div><label>${esc(T('flagf'))}</label>${sel('ff_flag', ['locked', 'hidden', 'nocount', 'noprice', 'unpriced_fg', 'retired', 'master'].map((k) => [k, T('fl_' + k)]), Fl.flag)}</div>` : ''}
    <div class="row between"><span>${esc(T('low'))}</span><button class="tog ${Fl.low ? 'on' : ''}" id="ff_low" data-act="sheettog">${esc(Fl.low ? t('on') : t('off'))}</button></div>
    ${D.lowOk ? `<div><div class="row between"><span>${esc(T('lowNow'))}</span><button class="tog ${Fl.lowNow ? 'on' : ''}" id="ff_lownow" data-act="sheettog">${esc(Fl.lowNow ? t('on') : t('off'))}</button></div><div class="hint">${esc(T('lowNowH'))}. ${esc(T('lowNoMin'))}</div></div>` : ''}
    <div class="row"><button class="full" data-act="p2_reset">${esc(T('reset'))}</button><button class="primary full" data-act="p2_apply">${esc(T('apply'))}</button></div></div>`);
}

// ---------- form ----------
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));
function shrink(file, max = 1024, q = 0.72) {
  return new Promise((res, rej) => { const img = new Image(), u = URL.createObjectURL(file);
    img.onload = () => { const k = Math.min(1, max / Math.max(img.width, img.height)), c = document.createElement('canvas'); c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(u); c.toBlob((b) => (b ? res(b) : rej(new Error('image'))), 'image/jpeg', q); };
    img.onerror = () => rej(new Error('image')); img.src = u; });
}
const locId = () => { const l = (S.ctx.locations || [])[0]; if (l !== undefined) return l; const e = (B.ENV && B.ENV.locs) || []; return e[0] ? e[0].id : 1; };
const opt = (v, cur, label) => `<option value="${esc(v)}" ${String(v) === String(cur ?? '') ? 'selected' : ''}>${esc(label)}</option>`;
const tg = (on, id, extra = '') => `<button type="button" class="tog ${on ? 'on' : ''}" id="${id}" data-act="p2_tg" ${extra} aria-pressed="${on ? 'true' : 'false'}">${esc(on ? t('on') : t('off'))}</button>`;
const seg = (grp, opts, cur) => `<div class="p2-seg" data-grp="${grp}">${opts.map(([v, l]) => `<button type="button" class="tog ${cur === v ? 'on' : ''}" data-act="p2_pick" data-g="${grp}" data-v="${v}" aria-pressed="${cur === v ? 'true' : 'false'}">${esc(l)}</button>`).join('')}</div>`;
const isOn = (id) => { const e = $('#' + id); return !!(e && e.classList.contains('on')); };
const grpVal = (g) => { const e = $(`[data-grp="${g}"] .tog.on`); return e ? e.dataset.v : null; };

function convHTML(it) {
  const rows = D.conv.filter((c) => c.item_id === it.id || !c.item_id);
  return `<div class="card stack"><b>${esc(T('convh'))}</b>${rows.length ? rows.map((c) => `<div class="p2-conv">1 ${esc(c.from_unit)} = ${esc(String(c.factor))} ${esc(c.to_unit)}${c.item_id ? '' : ` <span class="muted">· ${esc(T('convall'))}</span>`}</div>`).join('') : `<div class="muted">${esc(T('convnone'))}</div>`}
    ${S.ctx.is_owner ? `<a class="tog" href="#/settings2/units/${esc(it.id)}" style="text-decoration:none">${esc(T('convedit'))} →</a>` : ''}</div>`;
}
async function viewForm(id, presetCat) {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'items');
  if (!canEnter()) return go('items');
  try { await load(); } catch (e) { return fail(e); }
  const cur = id ? D.items.find((i) => String(i.id) === String(id)) : null;
  if (id && !cur) return go('items');
  const guessType = (cat) => { const n = {}; D.items.filter((x) => x.category === cat && x.item_type).forEach((x) => { n[x.item_type] = (n[x.item_type] || 0) + 1; }); const k = Object.keys(n).sort((a, z) => n[z] - n[a])[0]; return k || 'finished_good'; };
  const f = cur ? { ...cur, cost_price: D.canCost ? D.cost.get(cur.id) : undefined } : { name_bn: '', name_en: '', name_mix: '', category: presetCat || '', unit: 'kg', sell_price: '', is_active: true, sell_units: [], images: [], item_type: D.master ? guessType(presetCat) : undefined };
  if (!cur && D.master && f.item_type) { const d = B.itemMaster.types().find((x) => x.code === f.item_type); if (d) { f.count_in_business = d.count_in_business; f.sellable = d.sellable; } }
  F = { id: id || null, cur, images: [...(f.images || [])], vat: B.rule('vat_on', false) === true, up: 0 };
  const cats = [...catMap().keys()], subs = [...subMap().keys()], lu = listUnitOpts(), owner = !!S.ctx.is_owner;
  const hasWh = f.wholesale_price !== null && f.wholesale_price !== undefined, hasLow = f.min_stock !== null && f.min_stock !== undefined;
  const val = (v) => (v === null || v === undefined ? '' : v);
  const su = new Set(f.sell_units || []);
  shell(cur ? T('edit') : T('add'), `<div class="card stack">
      <div><label for="p_bn">${esc(T('name'))}</label><input id="p_bn" value="${esc(f.name_bn)}" autocomplete="off"></div>
      <div><label for="p_en">${esc(T('name_en'))}</label><input id="p_en" value="${esc(val(f.name_en))}" autocomplete="off"></div>
      <div class="row"><div style="flex:1"><label for="p_sell">${esc(T('sell'))}</label><input id="p_sell" inputmode="decimal" value="${esc(val(f.sell_price))}"></div>
        <div style="flex:1" id="p_wh_w" ${hasWh ? '' : 'hidden'}><label for="p_whs">${esc(T('whs'))}</label><input id="p_whs" inputmode="decimal" value="${esc(val(f.wholesale_price))}"></div></div>
      ${D.canCost ? `<div><label for="p_cost">${esc(T('cost_l'))}</label><input id="p_cost" inputmode="decimal" value="${esc(val(f.cost_price))}" ${canCostEnter() ? '' : 'readonly'}></div>` : ''}
    </div>
    <details class="acc" id="p_adv"><summary>${esc(T('adv'))}</summary><div class="accb stack">
      <div><label for="p_cat">${esc(T('cat'))}</label><div class="p2-inl"><select id="p_cat"><option value=""></option>${cats.map((c) => opt(c, f.category, catLabel(c))).join('')}</select>${owner ? `<button type="button" class="mini" data-act="p2_newbox" data-t="cat" aria-label="${esc(T('plus'))}">＋</button>` : ''}</div>
        <input id="p_cat_new" placeholder="${esc(T('newcat'))}" hidden style="margin-top:6px"></div>
      <div><label for="p_sub">${esc(T('sub'))}</label><div class="p2-inl"><select id="p_sub"><option value=""></option>${subs.map((c) => opt(c, f.sub_category, subLabel(c))).join('')}</select>${owner ? `<button type="button" class="mini" data-act="p2_newbox" data-t="sub" aria-label="${esc(T('plus'))}">＋</button>` : ''}</div>
        <input id="p_sub_new" placeholder="${esc(T('newsub'))}" hidden style="margin-top:6px"></div>
      <div class="row"><div style="flex:1"><label for="p_unit">${esc(T('unit'))}</label><select id="p_unit">${itemUnitOpts(f.unit).map(([v, l]) => opt(v, f.unit, lab(l))).join('')}</select></div>
        <div style="flex:1"><label for="p_base">${esc(T('base'))}</label><select id="p_base"><option value=""></option>${lu.map(([v, l]) => opt(v, f.base_unit, lab(l))).join('')}${f.base_unit && !lu.some((o) => o[0] === f.base_unit) ? opt(f.base_unit, f.base_unit, f.base_unit) : ''}</select></div></div>
      <div><label>${esc(T('sellu'))}</label><div class="p2-seg" id="p_su">${lu.map(([v, l]) => `<button type="button" class="tog ${su.has(v) ? 'on' : ''}" data-act="sheettog" data-su="${esc(v)}">${esc(lab(l))}</button>`).join('')}</div></div>
      <div class="row between"><span>${esc(T('whon'))}</span>${tg(hasWh, 'p_wh_on')}</div>
      <div class="row between"><span>${esc(T('lowon'))}</span>${tg(hasLow, 'p_low_on')}</div>
      <div id="p_min_w" ${hasLow ? '' : 'hidden'}><label for="p_min">${esc(T('minst'))}</label><input id="p_min" inputmode="decimal" value="${esc(val(f.min_stock))}"></div>
      ${F.vat ? `<div><label>${esc(T('vat'))}</label>${seg('vat', [['yes', T('yes')], ['no', T('no')]], f.vat_applicable === true ? 'yes' : f.vat_applicable === false ? 'no' : null)}</div>` : ''}
      <div><label>${esc(T('source'))}</label>${seg('src', [['made', T('made')], ['bought', T('bought')]], f.source || null)}</div>
      <div class="row between"><span>${esc(T('trk'))}</span>${tg(!!f.tracked, 'p_trk')}</div>
      <div class="row between"><span>${esc(T('actv'))}</span>${tg(f.is_active !== false, 'p_act')}</div>
      <div><label>${esc(T('images'))}</label><div class="photos" id="p_imgs"></div></div>
      <div><label for="p_bc">${esc(T('barcode'))}</label><div class="p2-inl"><input id="p_bc" value="${esc(val(f.barcode))}" autocomplete="off" inputmode="text"><button type="button" data-act="p2_scan">▮▮ ${esc(T('scan'))}</button></div><div class="hint" id="p_bc_h"></div></div>
      <div><label for="p_mix">${esc(T('name_mix'))}</label><input id="p_mix" value="${esc(val(f.name_mix))}" autocomplete="off"></div>
      <div><label for="p_details">${esc(T('details'))}</label><textarea id="p_details" rows="3" maxlength="2000" placeholder="${esc(T('detailsph'))}">${esc(val(f.details))}</textarea></div>
    </div></details>
    ${D.master ? B.itemMaster.formHTML(f, !cur) : ''}
    ${cur ? convHTML(cur) : ''}
    ${S.ctx.is_owner ? '' : `<div class="notice warn">${esc(t('needs_approval'))}</div>`}
    <div class="card"><label for="p_note">${esc(T('note'))}</label><input id="p_note" autocomplete="off"></div>
    <div class="p2-bar2"><button data-act="go" data-v="items">${esc(T('cancel'))}</button><button class="primary" data-act="p2_save">${esc(T('save'))}</button></div>`, 'items');
  drawImgs();
  if (D.master && !cur && f.category) B.itemMaster.showNext('p_cat', 'im_code_h');
  wireLists();
}
async function drawImgs() {
  const box = $('#p_imgs'); if (!box || !F) return;
  box.innerHTML = F.images.map((p, i) => `<span class="ph"><img data-path="${esc(p)}" alt="" width="84" height="84"><button type="button" class="mini" data-act="p2_img_del" data-i="${i}" aria-label="✕">✕</button></span>`).join('')
    + (F.images.length < MAXIMG ? `<label class="phadd">📷 ${esc(T('addimg'))}<input type="file" accept="image/*" hidden id="p_file"></label>` : '');
  const imgs = [...box.querySelectorAll('img[data-path]')]; if (!imgs.length) return;
  try {
    const r = await sb.storage.from('photos').createSignedUrls([...new Set(imgs.map((i) => i.dataset.path))], 3600);
    if (r.error || !r.data) return; const m = new Map(r.data.map((x) => [x.path, x.signedUrl]));
    imgs.forEach((i) => { const u = m.get(i.dataset.path); if (u) i.src = u; });
  } catch (e) { /* thumbnails are optional */ }
}
async function addImage(file) {
  if (!F || !file) return;
  if (F.images.length >= MAXIMG) return toast(T('maximg'));
  toast(T('upl'));
  try {
    const blob = await shrink(file), path = `ITEMS/${locId()}/${rid()}.jpg`;
    const up = await sb.storage.from('photos').upload(path, blob, { contentType: 'image/jpeg' }); if (up.error) throw up.error;
    try { await sb.storage.from('photos').upload(path + '.t.jpg', await shrink(file, 160, 0.7), { contentType: 'image/jpeg' }); } catch (e2) { /* bos103: the small copy is optional */ }
    F.images.push(path); drawImgs();
  } catch (e) { fail(e); }
}
function syncBarcodeHint() {
  const h = $('#p_bc_h'), v = ($('#p_bc') || {}).value ? $('#p_bc').value.trim() : ''; if (!h) return;
  const dup = v && D.items.find((i) => i.barcode && i.barcode.trim() === v && i.id !== (F && F.id));
  h.textContent = dup ? T('dupbc') + ' · ' + nm(dup) : ''; h.style.color = dup ? 'var(--bad)' : '';
  return !!dup;
}
const same = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null) || ((typeof a === 'number' || typeof b === 'number') && Number(a) === Number(b));
// shared list control: + Add new (follows the list's add rule) and Other on the category / sub-category / unit pickers; the old owner-only boxes stay when the list rules are not installed
function wireLists() {
  const lc = B.listctl; if (!lc) return;
  const on = () => { ['p_cat', 'p_sub', 'p_unit'].forEach((id) => { const code = id === 'p_cat' ? 'item_categories' : id === 'p_sub' ? 'item_subcategories' : 'units'; lc.enhance('#' + id, code, { keepPrev: true, form: 'ITEMS', ctx: () => ({ field: code, item_id: String((F && F.id) || '') }) }); });
    if (lc.available()) document.querySelectorAll('[data-act=p2_newbox]').forEach((b) => b.remove()); };
  on(); lc.load().then(() => { if (document.getElementById('p_cat')) on(); }).catch(() => {});
}
async function addToList(code, label) {                  // owner adds a category / sub-category to the editable list
  const rows = lists(code), max = ((B.ENV.lists && B.ENV.lists[code]) || []).reduce((m, r) => Math.max(m, r.sort || 0), 0);
  const slug = (label.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '') || 'x') + '_' + Date.now().toString(36).slice(-4);
  const row = { list_code: code, value_code: slug, label_bn: label, label_en: null, label_mix: null, sort: max + 1, active: true, extra: {} };
  const { error } = await sb.from('option_lists').upsert(row, { onConflict: 'list_code,value_code' }); if (error) throw error;
  await B.reloadLists(); void rows; return slug;
}
async function save() {
  if (!F) return;
  const cur = F.cur, num = (v) => (norm(v) === '' ? null : Number(norm(v)));
  const bad = (n) => n !== null && (!Number.isFinite(n) || n < 0);
  const name = $('#p_bn').value.trim(); if (!name) return toast(T('needname'));
  const sell = num($('#p_sell').value); if (sell === null && !cur && (!D.master || isOn('im_sell_f'))) return toast(T('needsell')); if (bad(sell)) return toast(T('badprice'));
  const whOn = isOn('p_wh_on'), wh = whOn ? num($('#p_whs').value) : null; if (whOn && wh === null) return toast(T('needwh')); if (bad(wh)) return toast(T('badprice'));
  const lowOn = isOn('p_low_on'), mn = lowOn ? num($('#p_min').value) : null; if (lowOn && mn === null) return toast(T('needmin')); if (bad(mn)) return toast(T('badprice'));
  const cost = $('#p_cost') && canCostEnter() ? num($('#p_cost').value) : undefined; if (bad(cost ?? null)) return toast(T('badprice'));
  if (syncBarcodeHint()) return toast(T('dupbc'));
  let cat = $('#p_cat').value, sub = $('#p_sub').value;
  { // "Other" on category / sub-category / unit: the old value stays; the typed words go into Details (and the owner's Other queue, with this item's id)
    const labels = { p_cat: 'Category', p_sub: 'Sub-category', p_unit: 'Unit' }, oth = Object.keys(labels).map((id) => [id, $('#' + id) && $('#' + id).dataset.lpOther]).filter((x) => x[1]);
    if (!cur && oth.some(([id]) => (id === 'p_cat' || id === 'p_unit') && !$('#' + id).value)) return toast(lab(L('"অন্যান্য" দিলে এখন একটি তালিকা-মান বেছে নিন; লেখা মালিকের কাছে গেছে', 'You used "Other": pick a listed value for now - your words went to the owner', '"Other" দিলে এখন একটি list-মান বেছে নিন; লেখা Owner এর কাছে গেছে')));
    if (oth.length && $('#p_details')) { const add = oth.map(([id, w]) => 'Other ' + labels[id].toLowerCase() + ': ' + w).join('\n'); $('#p_details').value = (($('#p_details').value || '').trim() + '\n' + add).trim(); oth.forEach(([id]) => { $('#' + id).dataset.lpOther = ''; }); }
  }
  try {
    const nc = ($('#p_cat_new') && !$('#p_cat_new').hidden ? $('#p_cat_new').value.trim() : ''), ns = ($('#p_sub_new') && !$('#p_sub_new').hidden ? $('#p_sub_new').value.trim() : '');
    if (nc) cat = await addToList('item_categories', nc); if (ns) sub = await addToList('item_subcategories', ns);
  } catch (e) { return fail(e); }
  const catRow = D.items.find((i) => i.category === cat), catL = lists('item_categories').find((r) => r.value_code === cat);
  const next = { name_bn: name, name_en: $('#p_en').value.trim() || null, name_mix: $('#p_mix').value.trim() || null, category: cat || null, unit: $('#p_unit').value || null,
    sell_price: sell, is_active: isOn('p_act'), sub_category: sub || null, base_unit: $('#p_base').value || null,
    sell_units: [...document.querySelectorAll('#p_su .tog.on')].map((b) => b.dataset.su), wholesale_price: wh, tracked: isOn('p_trk'), min_stock: mn,
    barcode: $('#p_bc').value.trim() || null, source: grpVal('src'), images: F.images.slice(), details: ($('#p_details') ? $('#p_details').value.trim() : '') || null };
  if (cat) next.category_bn = catL ? catL.label_bn : catRow ? catRow.category_bn : undefined; if (next.category_bn === undefined) delete next.category_bn;
  if (F.vat) { const v = grpVal('vat'); next.vat_applicable = v === 'yes' ? true : v === 'no' ? false : null; }
  if (cost !== undefined) next.cost_price = cost;
  const patch = {};
  const empty = (k, v) => v === null || v === undefined || (Array.isArray(v) && !v.length) || (v === false && k !== 'is_active');
  for (const k of Object.keys(next)) {
    const was = cur ? (k === 'cost_price' ? D.cost.get(cur.id) : cur[k]) : undefined;
    if (cur ? !same(was, next[k]) : !empty(k, next[k])) patch[k] = next[k];
  }
  if (D.master) Object.assign(patch, B.itemMaster.formPatch(cur));
  if (cur && !Object.keys(patch).length) { toast(T('nochange')); return go('items'); }
  const btn = $('[data-act=p2_save]'); if (btn) btn.disabled = true;
  const note = ($('#p_note').value || '').trim() || null;
  // item master installed: new items get their code from the category (item_new), changes go through item_apply (the owner or an item_create holder at once, others as a request)
  const { data, error } = D.master ? (F.id ? await sb.rpc('item_apply', { p_item: F.id, p_patch: patch, p_note: note }) : await sb.rpc('item_new', { p_patch: patch, p_note: note }))
    : await sb.rpc('submit_item_change', { p_item: F.id || null, p_patch: patch, p_note: note });
  if (btn) btn.disabled = false;
  if (error) { if (/duplicate|unique/i.test(error.message || '')) return toast(T('dupbc')); if (/item_locked/.test(error.message || '')) return toast(lab(L('এই আইটেম লক করা — শুধু মালিক বদলাতে পারেন', 'This item is locked — only the owner can change it', 'এই Item locked — শুধু Owner বদলাতে পারেন'))); if (/item_has_stock/.test(error.message || '')) return toast(lab(L('স্টক আছে — আগে শূন্য করুন', 'There is stock — bring it to zero first', 'Stock আছে — আগে শূন্য করুন'))); return (B.itemMaster && B.itemMaster.errMsg(error) ? toast(B.itemMaster.errMsg(error)) : fail(error)); }
  toast(data && (data.status === 'applied' || data.status === 'created') ? T('saved') + (data.code ? ' · ' + data.code : '') : T('appr'));
  F = null; go('items');
}

// ---------- events ----------
Object.assign(H, {
  itemnew: () => go('items/new'),
  itemedit: (a) => go('items/edit/' + a.dataset.v),
  p2_filter: () => filterSheet(),
  p2_btype: (a) => { Fl.type = Fl.type === a.dataset.v ? '' : a.dataset.v; shown = PAGE; const b = $('#p2_badges'); if (b) b.innerHTML = badgesHTML(); drawList(); },
  p2_bcls: (a) => { Fl.cls = Fl.cls === a.dataset.v ? '' : a.dataset.v; shown = PAGE; const b = $('#p2_badges'); if (b) b.innerHTML = badgesHTML(); drawList(); },
  p2_fg: () => { Fl.flag = Fl.flag === 'unpriced_fg' ? '' : 'unpriced_fg'; shown = PAGE; viewList(); },
  p2_fg_bulk: () => { B.bulkPreset = 'fg'; go('bulkitems'); },
  p2_apply: () => { Fl.cat = $('#ff_cat').value; Fl.sub = $('#ff_sub').value; Fl.source = $('#ff_src').value; Fl.tracked = $('#ff_trk').value; Fl.active = $('#ff_act').value; Fl.type = $('#ff_type') ? $('#ff_type').value : ''; Fl.flag = $('#ff_flag') ? $('#ff_flag').value : ''; Fl.low = isOn('ff_low'); Fl.lowNow = isOn('ff_lownow'); shown = PAGE; closeSheet(); drawList(); },
  p2_reset: () => { Object.assign(Fl, { cat: '', sub: '', source: '', tracked: '', low: false, lowNow: false, active: '', type: '', cls: '', flag: '' }); shown = PAGE; closeSheet(); const bd = $('#p2_badges'); if (bd) bd.innerHTML = badgesHTML(); drawList(); },
  p2_chip_x: (a) => { const k = a.dataset.k; Fl[k] = k === 'low' || k === 'lowNow' ? false : ''; shown = PAGE; const bd = $('#p2_badges'); if (bd) bd.innerHTML = badgesHTML(); drawList(); },
  p2_more: () => { shown += PAGE; drawList(); },
  p2_tg: (a) => {
    const on = !a.classList.contains('on'); a.classList.toggle('on', on); a.setAttribute('aria-pressed', on ? 'true' : 'false'); a.textContent = on ? t('on') : t('off');
    if (a.id === 'p_wh_on') { const w = $('#p_wh_w'); if (w) w.hidden = !on; if (on && $('#p_whs')) $('#p_whs').focus(); }
    if (a.id === 'p_low_on') { const w = $('#p_min_w'); if (w) w.hidden = !on; if (on && $('#p_min')) $('#p_min').focus(); }
  },
  p2_pick: (a) => { const was = a.classList.contains('on'); document.querySelectorAll(`[data-grp="${a.dataset.g}"] .tog`).forEach((b) => { b.classList.remove('on'); b.setAttribute('aria-pressed', 'false'); }); if (!was) { a.classList.add('on'); a.setAttribute('aria-pressed', 'true'); } },
  p2_newbox: (a) => { const el = $('#p_' + a.dataset.t + '_new'); if (!el) return; el.hidden = !el.hidden; if (!el.hidden) el.focus(); },
  p2_scan: async () => { if (!B.barcode) return; const code = await B.barcode.scan(); if (code && $('#p_bc')) { $('#p_bc').value = code; syncBarcodeHint(); } },
  p2_img_del: (a) => { if (!F) return; F.images.splice(Number(a.dataset.i), 1); drawImgs(); },
  p2_save: save,
  p2_pagemenu: () => {
    const o = !!S.ctx.is_owner, ok = (route, label, show) => (show ? `<button class="im-act" data-act="go" data-v="${route}">${esc(T(label))}</button>` : '');
    openSheet(`<h2>${esc(T('more2'))}</h2><div class="stack" style="margin-top:10px">${ok('assets', 'passets', true)}${ok('itemimport', 'pimp', o)}${ok('itemmap', 'pmap', o || (B.itemMaster && B.itemMaster.canFlag()))}${ok('itemtypes', 'ptypes', o)}${ok('bulkitems', 'pbulk', o || canEnter())}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('cancel'))}</button>`);
  },
});
let qTimer = null;
document.addEventListener('input', (e) => {
  if (e.target.id === 'p2_q') { Fl.q = e.target.value; shown = PAGE; clearTimeout(qTimer); qTimer = setTimeout(drawList, 150); }
  if (e.target.id === 'p_bc') syncBarcodeHint();
});
document.addEventListener('change', (e) => { if (e.target.id === 'p_file') { const f = e.target.files && e.target.files[0]; e.target.value = ''; addImage(f); } });
document.addEventListener('keydown', (e) => { if ((e.key === 'Enter' || e.key === ' ') && e.target.classList && e.target.classList.contains('p2-row')) { e.preventDefault(); e.target.click(); } });

async function view() {
  const seg = location.hash.replace(/^#\/?/, '').split('/');
  if (seg[1] === 'new') return viewForm(null, seg[2] || '');
  if (seg[1] === 'edit' && seg[2]) return viewForm(seg[2]);
  return viewList();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { items: view, products: view });
// labels for the approval screen (#/itemreq): the new item fields
window.BOS_ITEM_LABELS = () => ({ item_type: T('type'), control_class: lab(L('ডিকশনারি ক্লাস', 'Dictionary class', 'Dictionary class')), count_in_business: lab(L('ব্যবসার হিসাবে ধরা', 'Count in business', 'Business-এ ধরা')), sellable: lab(L('বিক্রির জন্য', 'For sale', 'Selling-এর জন্য')),
  locked: T('fl_locked'), hidden: T('fl_hidden'), retired_reason: lab(L('কারণ', 'Reason', 'Reason')), master_code: lab(L('মাস্টার কোড', 'Master code', 'Master code')), sub_category: T('sub'), base_unit: T('base'), sell_units: T('sellu'), wholesale_price: T('whs'), tracked: T('trk'), min_stock: T('minst'),
  barcode: T('barcode'), source: T('source'), vat_applicable: T('vat'), images: T('images'), details: T('details') });
B.items2 = { reload: load, items: () => D.items, redraw: () => { try { drawList(); } catch (e) { /* not on the list */ } } };
})();
