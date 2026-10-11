/* Islamia BOS · POS: running sales. Item-wise sale, items that are not in the list, quick sale for rush, retail / wholesale,
   split and partial payment, customer (mobile) rules, today's list, void with a note, receipt share.
   Prices and totals are fixed by the server (record_sale2). A sale that cannot be sent waits in a local queue and is re-sent. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const r2 = (n) => Math.round(n * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(n));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const hhmm = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' });
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const nnum = (v) => { const n = Number(norm(v).trim()); return Number.isFinite(n) ? n : 0; };
// Bangladesh mobile: 01XXXXXXXXX (also +880 / 880 / spaces / dashes)
const normMobile = (v) => { let d = norm(v).replace(/[^0-9+]/g, ''); if (d.startsWith('+880')) d = '0' + d.slice(4); else if (d.startsWith('880') && d.length === 13) d = '0' + d.slice(3); return /^01[3-9][0-9]{8}$/.test(d) ? d : null; };

const CATS = { sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'),
  cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)') };
const UNITS = { kg: L('কেজি', 'KG', 'KG'), pc: L('পিস', 'Piece', 'Piece'), lb: L('পাউন্ড', 'Pound', 'Pound') };
const X = {
  title: L('সেল (POS)', 'Sales (POS)', 'Sale (POS)'), sell: L('বিক্রি', 'Sell', 'Sell'), today: L('আজকের সেল', "Today's sales", 'Today সেল'),
  quick: L('কুইক সেল', 'Quick sale', 'Quick Sale'), cart: L('কার্ট', 'Cart', 'Cart'), pay: L('পেমেন্ট', 'Pay', 'Pay'), total: L('মোট', 'Total', 'Total'),
  discount: L('ডিসকাউন্ট (৳)', 'Discount (৳)', 'Discount (৳)'), note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'),
  confirm: L('সেল সম্পন্ন', 'Complete sale', 'Complete Sale'), empty: L('কার্ট খালি — আইটেম ট্যাপ করুন', 'Cart is empty — tap an item', 'Cart খালি — Item ট্যাপ করুন'),
  amount: L('টাকার পরিমাণ', 'Amount', 'Amount'), what: L('কী বিক্রি (ঐচ্ছিক)', 'What was sold (optional)', 'কী বিক্রি (ঐচ্ছিক)'), all: L('সব', 'All', 'All'), freq: L('বেশি বিক্রি', 'Frequent', 'Frequent'),
  search: L('আইটেম খুঁজুন', 'Search item', 'Item খুঁজুন'), qty: L('পরিমাণ', 'Quantity', 'Quantity'), add: L('কার্টে দিন', 'Add to cart', 'Add to Cart'),
  receipt: L('রসিদ', 'Receipt', 'Receipt'), done: L('সেল হয়েছে', 'Sale done', 'Sale হয়েছে'), queued: L('নেট নেই — সেল জমা আছে, নেট এলে পাঠানো হবে', 'No network — sale saved, will be sent when online', 'Net নেই — Sale জমা আছে, Online হলে যাবে'),
  pending: L('পাঠানো বাকি', 'waiting to send', 'পাঠানো বাকি'), void: L('বাতিল', 'Void', 'Void'), voided: L('বাতিল হয়েছে', 'Voided', 'Voided'), voidwhy: L('বাতিলের কারণ (লিখতেই হবে)', 'Reason for voiding (required)', 'Void এর কারণ (লিখতেই হবে)'),
  day: L('আজকের মোট', "Today's total", 'Today মোট'), count: L('টি সেল', 'sales', 'sales'), nodata: L('এখনও কোনো সেল নেই', 'No sales yet', 'এখনও কোনো sale নেই'),
  back: L('ফিরুন', 'Back', 'Back'), close: L('বন্ধ', 'Close', 'Close'), lines: L('আইটেম', 'Items', 'Items'), by: L('বিক্রেতা', 'Sold by', 'Sold by'),
  needNote: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'), noloc: L('কোনো লোকেশন দেওয়া নেই — মালিককে জানান', 'No location assigned — tell the owner', 'কোনো Location দেওয়া নেই — Owner কে জানান'),
  priceov: L('দাম বদলান (ব্যতিক্রম তালিকায় যাবে)', 'Change price (goes to exceptions)', 'Price বদলান (Exception এ যাবে)'),
  retail: L('খুচরা', 'Retail', 'Retail'), wholesale: L('পাইকারি', 'Wholesale', 'Wholesale (পাইকারি)'),
  cust: L('গ্রাহক', 'Customer', 'Customer'), custAdd: L('গ্রাহক যোগ করুন', 'Add customer', 'Customer যোগ করুন'), mobile: L('মোবাইল নম্বর', 'Mobile number', 'Mobile number'), cname: L('গ্রাহকের নাম', 'Customer name', 'Customer এর নাম'),
  custReq: L('বাকি বা পাইকারি সেলে গ্রাহকের মোবাইল নম্বর আর নাম লাগবেই', 'A customer mobile number and name are required for a due or wholesale sale', 'Due বা Wholesale sale এ Customer এর mobile number আর নাম লাগবেই'),
  known: L('পুরনো গ্রাহক', 'Existing customer', 'পুরনো Customer'), newc: L('নতুন গ্রাহক — নাম লিখুন', 'New customer — enter the name', 'নতুন Customer — নাম লিখুন'),
  owes: L('এখন বাকি', 'Owes now', 'এখন Due'), limit: L('বাকির সীমা', 'Credit limit', 'Credit limit'),
  other: L('অন্য আইটেম (তালিকায় নেই)', 'Other item (not in the list)', 'অন্য Item (list এ নেই)'), oname: L('আইটেমের নাম', 'Item name', 'Item এর নাম'), ounit: L('একক (কেজি, পিস…)', 'Unit (kg, piece…)', 'Unit (kg, piece…)'), oprice: L('একক দাম (৳)', 'Unit price (৳)', 'Unit price (৳)'),
  ohint: L('এটা মালিকের কাছে "তালিকায় নেই" হিসেবে যাবে, যাতে তালিকায় যোগ হয়।', 'The owner is told it is not in the list so it can be added.', 'Owner কে "list এ নেই" হিসেবে জানানো হবে, যাতে list এ যোগ হয়।'),
  newitem: L('＋ নতুন আইটেম', '＋ New item', '＋ নতুন Item'), full: L('নগদে সম্পন্ন', 'Done — cash', 'Cash এ Done'), more: L('মোবাইল / বাকি / ভাগ…', 'Mobile / due / split…', 'Mobile / Due / ভাগ…'),
  paidword: L('পরিশোধ', 'Paid', 'Paid'), dueword: L('বাকি', 'Due', 'Due'), share: L('রসিদ শেয়ার', 'Share receipt', 'Receipt Share'), collect: L('বাকি আদায়', 'Collect due', 'Due আদায়'),
  failed: L('পাঠানো যায়নি (নিয়মে আটকেছে)', 'Could not be recorded (refused)', 'পাঠানো যায়নি (আটকেছে)'), discard: L('বাদ দিন', 'Discard', 'Discard'),
  failedmsg: L('কিছু সেল নিয়মে আটকেছে — আজকের সেল পাতায় দেখুন', 'Some sales were refused — see Today', 'কিছু Sale আটকেছে — Today পাতায় দেখুন'),
  needupd: L('ডেটাবেস আপডেট বাকি (নতুন SQL চালাতে হবে) — এখন শুধু পুরো নগদ সেল চলবে', 'Database update pending (new SQL) — only full-cash sales work for now', 'Database update বাকি (নতুন SQL) — এখন শুধু full-cash sale চলবে'),
};
const T = (k) => lab(X[k]);
const ERRS = {
  customer_required: X.custReq, customer_name_required: L('নতুন গ্রাহকের নাম লিখুন', 'Enter the new customer’s name', 'নতুন Customer এর নাম লিখুন'), bad_mobile: L('মোবাইল নম্বর সঠিক নয় (01XXXXXXXXX)', 'The mobile number is not valid (01XXXXXXXXX)', 'Mobile number ঠিক নয় (01XXXXXXXXX)'),
  overpaid: L('পরিশোধ মোটের বেশি হতে পারে না', 'Paid cannot be more than the total', 'Paid মোটের বেশি হতে পারে না'), over_credit_limit: L('এই গ্রাহকের বাকির সীমা পার হচ্ছে — ম্যানেজার লাগবে', 'This customer’s credit limit would be exceeded — a manager is needed', 'এই Customer এর Credit limit পার হচ্ছে — Manager লাগবে'),
  override_needs_approval: L('দাম বদলাতে ম্যানেজার লাগবে', 'Only a manager can change a price', 'Price বদলাতে Manager লাগবে'), discount_needs_approval: L('ডিসকাউন্ট সীমার উপরে — ম্যানেজার লাগবে', 'The discount is above the limit — a manager is needed', 'Discount limit এর উপরে — Manager লাগবে'),
  customer_inactive: L('এই গ্রাহক বন্ধ করা আছে', 'This customer is switched off', 'এই Customer বন্ধ করা আছে'), bad_discount: L('ডিসকাউন্ট মোটের বেশি হতে পারে না', 'Discount cannot exceed the total', 'Discount মোটের বেশি হতে পারে না'),
  period_closed: L('এই তারিখের হিসাব বন্ধ — শুধু মালিক বদলাতে পারবেন', 'This date is closed — only the owner can change it', 'এই date এর হিসাব বন্ধ — শুধু Owner বদলাতে পারবেন'),
  wallet_needed: L('মোবাইল পেমেন্টে বিকাশ/নগদ ইত্যাদি বাছুন', 'Choose bKash / Nagad etc. for a mobile payment', 'Mobile payment এ bKash/Nagad বাছুন'), name_required: L('আইটেমের নাম লিখুন', 'Enter the item name', 'Item এর নাম লিখুন'),
};
const T2 = (e) => { const m = (e && e.message) || String(e || ''); for (const k of Object.keys(ERRS)) if (m.includes(k)) return lab(ERRS[k]); return null; };

// ---------- state ----------
const P = { loc: null, cat: '', q: '', items: [], locs: [], cart: [], type: 'retail', tab: 'sell', day: [], busy: false, st: null, cust: { mobile: '', name: '', found: null, show: false } };
const uidK = () => (S.ctx && S.ctx.profile ? S.ctx.profile.id : 'anon');
const QK = () => 'bos_pos_queue_' + uidK(), XK = () => 'bos_pos_failed_' + uidK(), FKEY = 'bos_pos_freq';
const jget = (k, d) => { try { return JSON.parse(store.get(k)) || d; } catch (e) { return d; } };
const queue = () => jget(QK(), []);
const setQueue = (q) => store.set(QK(), JSON.stringify(q));
const failedQ = () => jget(XK(), []);
const setFailed = (q) => store.set(XK(), JSON.stringify(q));
const BUSINESS = /^(no_lines|bad_mode|bad_qty|bad_price|bad_amount|bad_discount|no_price|item_not_found|due_needs_customer|not allowed|customer_required|customer_name_required|bad_mobile|overpaid|over_credit_limit|override_needs_approval|discount_needs_approval|customer_inactive|bad_sale_type|bad_payments|name_required|period_closed)/;
const freq = () => jget(FKEY, {});
const bump = (id) => { const f = freq(); f[id] = (f[id] || 0) + 1; store.set(FKEY, JSON.stringify(f)); };
const perms = () => S.ctx.perms.POS || {};
const stepOf = (u) => (u === 'pc' ? 1 : 0.5);
const unitL = (u) => lab(UNITS[u]) || u || '';
const itemById = (id) => P.items.find((i) => i.id === id);
const lineAmt = (l) => (l.kind === 'quick' ? r2(l.amount) : r2(l.qty * l.price));
const cartSub = () => r2(P.cart.reduce((s, l) => s + lineAmt(l), 0));
const isNet = (e) => !navigator.onLine || /fetch|network|load failed|timeout/i.test((e && e.message) || '');
const discVal = () => Math.max(0, nnum(($('#cart_disc') || {}).value || 0));
const netTotal = () => Math.max(0, r2(cartSub() - discVal()));

async function load() {
  await B.loadStatic();
  const it = await sb.from('items').select('id,code,name_bn,name_en,name_mix,category,category_bn,unit,sell_price,is_active').eq('is_active', true).order('code');
  if (it.error) throw it.error;
  P.items = it.data.filter((i) => i.sell_price !== null);
  const all = B.ENV.locs;
  P.locs = S.ctx.is_owner || S.ctx.roles.includes('management') ? all : all.filter((l) => S.ctx.locations.includes(l.id));
  if (!P.loc || !P.locs.find((l) => l.id === P.loc)) P.loc = store.get('bos_pos_loc') ? Number(store.get('bos_pos_loc')) : (P.locs[0] || {}).id;
  if (!P.locs.find((l) => l.id === P.loc)) P.loc = (P.locs[0] || {}).id;
  B.pay.loadWallets();
}

// ---------- page ----------
async function viewPos() {
  if (!perms().view && !S.ctx.is_owner) return (location.hash = '#/home');
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  try { await load(); } catch (e) { return fail(e); }
  if (!P.loc) return shell(T('title'), `<div class="notice bad">${esc(T('noloc'))}</div>`, true);
  drawPos();
  flush();
}
function drawPos() {
  const can = perms().enter || S.ctx.is_owner;
  const q = queue().filter((x) => x.p_loc === P.loc).length;
  shell(T('title'), `
    <div class="row" style="margin-bottom:8px">${P.locs.length > 1 ? `<select id="pos_loc" style="flex:1">${P.locs.map((l) => `<option value="${l.id}" ${l.id === P.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>` : `<b style="flex:1">${esc(nm(P.locs[0]))}</b>`}
      ${q ? `<span class="chip warn" id="pos_qchip">${q} ${esc(T('pending'))}</span>` : ''}</div>
    <div class="row" style="margin-bottom:10px"><button class="tog ${P.tab === 'sell' ? 'on' : ''}" data-act="pos_tab" data-v="sell" style="flex:1">${esc(T('sell'))}</button>
      <button class="tog ${P.tab === 'today' ? 'on' : ''}" data-act="pos_tab" data-v="today" style="flex:1">${esc(T('today'))}</button></div>
    <div id="pos_body"></div>`, true);
  if (P.tab === 'sell') drawSell(can); else drawToday();
}

// ---------- sell ----------
function drawSell(can) {
  const cats = [...new Set(P.items.map((i) => i.category).filter(Boolean))];
  const cn = (c) => lab(CATS[c]) || (P.items.find((i) => i.category === c) || {}).category_bn || c;
  const canNew = S.ctx.is_owner || (S.ctx.perms.ITEMS && S.ctx.perms.ITEMS.enter);
  $('#pos_body').innerHTML = `
    <div class="row"><input id="pos_q" placeholder="${esc(T('search'))}" value="${esc(P.q)}" style="flex:1"><button class="primary" data-act="pos_quick" ${can ? '' : 'disabled'}>⚡ ${esc(T('quick'))}</button></div>
    <div class="row wrap" style="margin:10px 0" id="pos_cats">${[['', T('all')], ['_f', T('freq')], ...cats.map((c) => [c, cn(c)])].map(([c, l]) =>
      `<button class="tog ${P.cat === c ? 'on' : ''}" data-act="pos_cat" data-v="${esc(c)}">${esc(l)}</button>`).join('')}</div>
    <div class="row wrap" style="margin-bottom:10px"><button class="tog" data-act="pos_other" ${can ? '' : 'disabled'}>${esc(T('other'))}</button>${canNew ? `<button class="tog" data-act="pos_newitem">${esc(T('newitem'))}</button>` : ''}</div>
    <div class="pos-grid" id="pos_items"></div><div style="height:96px"></div>
    <div class="pos-bar" id="pos_bar"></div>`;
  drawItems(can); drawBar(can);
}
function visibleItems() {
  const q = P.q.trim().toLowerCase(), f = freq();
  let l = P.items.filter((i) => (!P.cat || P.cat === '_f' || i.category === P.cat) && (!q || [i.name_bn, i.name_en, i.name_mix, i.code].some((x) => (x || '').toLowerCase().includes(q))));
  if (P.cat === '_f') l = l.filter((i) => f[i.id]).sort((a, z) => f[z.id] - f[a.id]).slice(0, 24);
  return l;
}
function drawItems(can) {
  const inCart = new Map(P.cart.filter((l) => l.kind === 'item').map((l) => [l.item_id, l.qty]));
  $('#pos_items').innerHTML = visibleItems().map((i) => `<button class="pos-item ${inCart.has(i.id) ? 'in' : ''}" data-cat="${esc(i.category || '')}" data-act="pos_add" data-v="${i.id}" ${can ? '' : 'disabled'}>
      <span class="pn">${esc(nm(i))}</span><span class="pp"><span class="cur">৳</span>${fmt(i.sell_price)}<small> / ${esc(unitL(i.unit))}</small></span>${inCart.has(i.id) ? `<span class="pq">${fmt(inCart.get(i.id))}</span>` : ''}</button>`).join('') || `<p class="muted center">—</p>`;
}
function drawBar(can) {
  const n = P.cart.length, sub = cartSub();
  const b = $('#pos_bar'); if (!b) return;
  b.innerHTML = `<div><div class="muted" style="font-size:.8rem">${n ? n + ' · ' + esc(T('lines')) : esc(T('cart'))}</div><b style="font-size:1.25rem">${money(sub)}</b></div>
    <button class="primary" data-act="pos_cart" ${n && can ? '' : 'disabled'}>${esc(T('pay'))} →</button>`;
}
function refreshSell() { if (P.tab !== 'sell' || !$('#pos_items')) return; drawItems(true); drawBar(true); }
function addItem(id, qty) {
  const i = itemById(id); if (!i) return;
  const ex = P.cart.find((l) => l.kind === 'item' && l.item_id === id);
  if (ex) ex.qty = Math.round((ex.qty + qty) * 1000) / 1000; else P.cart.push({ kind: 'item', item_id: id, qty, price: Number(i.sell_price), ov: false });
  refreshSell();
}
function qtySheet(id) {
  const i = itemById(id);
  const presets = i.unit === 'pc' ? [1, 2, 3, 5, 10] : [0.25, 0.5, 1, 2, 5];
  openSheet(`<h2>${esc(nm(i))}</h2><p class="muted">${money(i.sell_price)} / ${esc(unitL(i.unit))}</p>
    <div class="row wrap" style="margin-bottom:10px">${presets.map((p) => `<button class="tog" data-act="pos_q_set" data-v="${id}" data-n="${p}" style="min-width:64px;font-size:1.15rem">${p}</button>`).join('')}</div>
    <label>${esc(T('qty'))} (${esc(unitL(i.unit))})</label><input id="pos_qty" inputmode="decimal" value="1" style="font-size:1.4rem">
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="pos_q_ok" data-v="${id}">${esc(T('add'))}</button></div>`);
  setTimeout(() => { const e = $('#pos_qty'); if (e) { e.focus(); e.select(); } }, 60);
}
function otherSheet() {
  openSheet(`<h2>${esc(T('other'))}</h2><div class="notice ok">${esc(T('ohint'))}</div><div class="stack">
    <div><label>${esc(T('oname'))}</label><input id="ot_name"></div>
    <div class="row"><div style="flex:1"><label>${esc(T('qty'))}</label><input id="ot_qty" inputmode="decimal" value="1"></div><div style="flex:1"><label>${esc(T('ounit'))}</label><input id="ot_unit"></div></div>
    <div><label>${esc(T('oprice'))}</label><input id="ot_price" inputmode="decimal"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="pos_ot_ok">${esc(T('add'))}</button></div></div>`);
  setTimeout(() => { const e = $('#ot_name'); if (e) e.focus(); }, 60);
}

// ---------- cart / pay ----------
function cartSheet() {
  P.st = B.pay.create(netTotal, updDue);
  openSheet(`<h2>${esc(T('cart'))}</h2><div id="cart_lines" class="stack"></div>
    <div class="row wrap" style="margin:8px 0"><button class="tog ${P.type === 'retail' ? 'on' : ''}" data-act="pos_type" data-v="retail">${esc(T('retail'))}</button><button class="tog ${P.type === 'wholesale' ? 'on' : ''}" data-act="pos_type" data-v="wholesale">${esc(T('wholesale'))}</button></div>
    <div class="row"><div style="flex:1"><label>${esc(T('discount'))}</label><input id="cart_disc" inputmode="decimal"></div></div>
    <div class="row between" style="margin:10px 0"><span>${esc(T('total'))}</span><b style="font-size:1.4rem" id="cart_total"></b></div>
    <div id="cart_pay"></div><div id="cart_cust"></div>
    <div style="margin-top:8px"><label>${esc(T('note'))}</label><input id="cart_note"></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('back'))}</button><button class="primary full" id="cart_ok" data-act="pos_confirm">${esc(T('confirm'))}</button></div>`);
  drawCartLines(); drawPay(); drawCust();
}
function drawPay() { const el = $('#cart_pay'); if (el) el.innerHTML = B.pay.html(P.st); }
function updDue() { const tt = $('#cart_total'); if (tt) tt.textContent = money(netTotal()); drawCust(); }
function needCust() { return P.type === 'wholesale' || (P.st && B.pay.due(P.st) > 0); }
function drawCust() {
  const el = $('#cart_cust'); if (!el) return;
  const need = needCust(), c = P.cust;
  const keepFocus = document.activeElement && document.activeElement.id;
  if (!need && !c.show) { el.innerHTML = `<button type="button" class="tog" data-act="pos_cust_show">${esc(T('custAdd'))}</button>`; return; }
  const m = normMobile(c.mobile), f = c.found;
  el.innerHTML = `<div class="card" style="margin:8px 0"><b>${esc(T('cust'))}${need ? ' *' : ''}</b>${need ? `<div class="muted" style="font-size:.85rem">${esc(T('custReq'))}</div>` : ''}
    <label>${esc(T('mobile'))}</label><input id="cu_mobile" inputmode="tel" value="${esc(c.mobile)}" placeholder="01XXXXXXXXX">
    ${m && f && f.found ? `<div class="notice ok"><b>${esc(f.name)}</b> · ${esc(T('known'))}${Number(f.balance) > 0 ? ` · ${esc(T('owes'))}: ${money(f.balance)}` : ''}${f.credit_limit !== null && f.credit_limit !== undefined ? ` · ${esc(T('limit'))}: ${money(f.credit_limit)}` : ''}</div>`
      : m ? `<label>${esc(T('cname'))} — ${esc(T('newc'))}</label><input id="cu_name" value="${esc(c.name)}">` : ''}</div>`;
  if (keepFocus === 'cu_mobile') { const i = $('#cu_mobile'); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }
}
let lookTimer = null;
function lookup() {
  clearTimeout(lookTimer);
  const m = normMobile(P.cust.mobile); if (!m) { P.cust.found = null; return; }
  lookTimer = setTimeout(async () => {
    const r = await sb.rpc('find_customer', { p_mobile: m }); if (r.error) return;
    if (normMobile(P.cust.mobile) !== m) return;
    P.cust.found = r.data; if (r.data && r.data.found) P.cust.name = r.data.name; drawCust();
  }, 250);
}
function drawCartLines() {
  const el = $('#cart_lines'); if (!el) return;
  el.innerHTML = P.cart.map((l, k) => {
    const i = l.kind === 'item' ? itemById(l.item_id) : null;
    const name = l.kind === 'item' ? nm(i) : l.name, unit = l.kind === 'item' ? unitL(i.unit) : l.unit || '';
    return `<div class="cart-line"><div style="flex:1;min-width:0"><div class="nm">${esc(name)}${l.kind === 'quick' ? ' ⚡' : ''}${l.kind === 'custom' ? ' ◇' : ''}</div>
      ${l.kind === 'quick' ? '' : `<div class="muted" style="font-size:.85rem" ${l.kind === 'item' ? `data-act="pos_price" data-k="${k}"` : ''}>${money(l.price)} / ${esc(unit)}${l.kind === 'item' ? ' ✎' : ''}${l.ov ? ' ✎' : ''}</div>`}</div>
      ${l.kind === 'quick' ? `<button class="mini" data-act="pos_rm" data-k="${k}" aria-label="x">✕</button>` : `<div class="stepper"><button data-act="pos_step" data-k="${k}" data-d="-1">−</button><button data-act="pos_qedit" data-k="${k}" class="qv">${fmt(l.qty)}</button><button data-act="pos_step" data-k="${k}" data-d="1">＋</button></div>`}
      <b style="min-width:72px;text-align:right">${money(lineAmt(l))}</b></div>`; }).join('') || `<p class="muted">${esc(T('empty'))}</p>`;
  const tt = $('#cart_total'); if (tt) tt.textContent = money(netTotal());
}
function afterCartChange() {
  if (!P.cart.length) { closeSheet(); refreshSell(); return; }
  drawCartLines(); B.pay.syncAuto(P.st); drawPay(); drawCust(); drawBar(true);
}

// ---------- quick sale ----------
function quickSheet() {
  openSheet(`<h2>⚡ ${esc(T('quick'))}</h2>
    <label>${esc(T('amount'))} (৳)</label><input id="qs_amt" inputmode="decimal" style="font-size:1.8rem;font-weight:700" autocomplete="off">
    <label style="margin-top:8px">${esc(T('what'))}</label><input id="qs_what">
    <div class="stack" style="margin-top:12px"><button class="primary full" data-act="pos_qs_cash" style="min-height:56px">${esc(T('full'))}</button>
      <button class="full" data-act="pos_qs_more">${esc(T('more'))}</button><button class="full" data-act="closesheet">${esc(t('cancel'))}</button></div>`);
  setTimeout(() => { const e = $('#qs_amt'); if (e) e.focus(); }, 60);
}
function readQuick() { const amt = nnum($('#qs_amt').value); if (!(amt > 0)) { toast(T('amount')); return null; } return { kind: 'quick', amount: amt, name: ($('#qs_what').value || '').trim() || 'Quick sale' }; }

// ---------- sending (with offline queue) ----------
function linesOf() {
  return P.cart.map((l) => l.kind === 'item' ? { item_id: l.item_id, qty: l.qty, price: l.price, override: l.ov, name: nm(itemById(l.item_id)) }
    : l.kind === 'custom' ? { item_id: null, name: l.name, unit: l.unit, qty: l.qty, price: l.price } : { item_id: null, name: l.name, amount: l.amount });
}
function build(o) {
  return { p_client: uid(), p_loc: P.loc, p_lines: o.lines, p_discount: o.disc || 0, p_payments: o.payments, p_customer_mobile: o.mobile || null, p_customer_name: o.cname || null,
    p_sale_type: o.type || 'retail', p_note: o.note || null, p_quick: !!o.quick, p_sold_at: new Date().toISOString(), _t: Date.now(), _total: o.total, _paid: o.paid };
}
const clean = (p) => { const { _t, _total, _paid, ...r } = p; return r; };
const NOFN = /record_sale2|Could not find the function|PGRST202|schema cache/i;
async function send(p) {
  let r = await sb.rpc('record_sale2', clean(p));
  if (r.error && NOFN.test(r.error.message || '')) {
    // database not updated yet: only a full single-mode payment can still be recorded the old way
    const pays = p.p_payments || [];
    if (pays.length === 1 && Number(pays[0].amount) >= Number(p._total) - 0.001 && p.p_sale_type === 'retail' && !p.p_customer_mobile && p.p_lines.every((l) => l.item_id || l.amount !== undefined)) {
      r = await sb.rpc('record_sale', { p_client: p.p_client, p_loc: p.p_loc, p_lines: p.p_lines.filter((l) => l.item_id || l.amount), p_discount: p.p_discount, p_mode: pays[0].mode, p_tendered: pays[0].tendered || null,
        p_customer: p.p_customer_name, p_note: p.p_note, p_quick: p.p_quick, p_sold_at: p.p_sold_at });
    } else r = { data: null, error: { message: 'LEGACY: ' + lab(X.needupd) } };
  }
  return r;
}
async function submitSale(p, change) {
  if (P.busy) return; P.busy = true;
  const btn = $('#cart_ok') || $('[data-act="pos_qs_cash"]'); if (btn) btn.disabled = true;
  try {
    const { data, error } = await send(p);
    if (error) {
      if (isNet(error)) { setQueue([...queue(), p]); closeSheet(); resetCart(); toast(T('queued')); return afterSale(); }
      if (btn) btn.disabled = false;
      const m = T2(error); if (m) return toast(m);
      if (/^LEGACY: /.test(error.message || '')) return toast(error.message.slice(8));
      return fail(error);
    }
    closeSheet(); resetCart();
    toast(`${T('done')} · ${T('receipt')} ${data.receipt} · ${money(data.total)}${change > 0 ? ' · ' + lab(L('ফেরত', 'Change', 'Change')) + ' ' + money(change) : ''}${data.due > 0 ? ' · ' + T('dueword') + ' ' + money(data.due) : ''}`);
    afterSale();
  } finally { P.busy = false; }
}
function resetCart() { P.cart = []; P.type = 'retail'; P.cust = { mobile: '', name: '', found: null, show: false }; P.st = null; }
function afterSale() { if (location.hash.startsWith('#/pos')) drawPos(); }
let flushing = false;
async function flush() {
  if (flushing || !S.ctx || !navigator.onLine) return;
  const q = queue(); if (!q.length) return;
  flushing = true;
  const done = new Set(), bad = [], tried = new Map();
  try {
    for (const p of q) {
      const { error } = await send(p);
      if (!error) { done.add(p.p_client); continue; }
      const m = (error && error.message) || '';
      if (BUSINESS.test(m)) { done.add(p.p_client); bad.push({ ...p, _err: T2(error) || m }); continue; }   // refused by the rules: kept visible, never lost
      if (isNet(error) || /jwt|token|401|403|permission denied|not authenticated|unauthor/i.test(m)) break;   // network or session trouble: keep and retry later
      p._tries = (p._tries || 0) + 1;                                                                        // an odd error on one sale must not block the others
      if (p._tries >= 3) { done.add(p.p_client); bad.push({ ...p, _err: m }); } else tried.set(p.p_client, p);
    }
  } finally {
    setQueue(queue().filter((x) => !done.has(x.p_client)).map((x) => tried.get(x.p_client) || x));
    if (bad.length) { setFailed([...failedQ(), ...bad]); toast(T('failedmsg')); }
    flushing = false;
  }
  if (bad.length && location.hash.startsWith('#/pos')) drawPos();
}
window.addEventListener('online', flush);
setInterval(flush, 30000);

// ---------- today ----------
const MODEL = { cash: L('নগদ', 'Cash', 'Cash'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), card: L('কার্ড', 'Card', 'Card'), due: L('বাকি', 'Due', 'Due'), split: L('ভাগ করা', 'Split', 'Split') };
async function drawToday() {
  $('#pos_body').innerHTML = `<p class="muted">${esc(t('loading'))}</p>`;
  const [r, pr] = await Promise.all([sb.from('sales').select('*').eq('location_id', P.loc).eq('sale_date', today()).order('receipt', { ascending: false }),
    sb.from('sale_payments').select('mode,kind,amount').eq('location_id', P.loc).eq('voided', false).gte('paid_at', today() + 'T00:00:00+06:00')]);
  if (r.error) return fail(r.error);
  P.day = r.data;
  const ok = P.day.filter((s) => s.status === 'done');
  const tot = ok.reduce((a, s) => a + Number(s.total), 0), dueT = ok.reduce((a, s) => a + Number(s.due_amount || 0), 0);
  const by = (m) => (pr.error ? ok.filter((x) => x.pay_mode === m).reduce((a, x) => a + Number(x.total), 0) : (pr.data || []).filter((x) => x.mode === m).reduce((a, x) => a + Number(x.amount), 0));
  const coll = (pr.data || []).filter((x) => x.kind === 'collection').reduce((a, x) => a + Number(x.amount), 0);
  const pend = queue().filter((x) => x.p_loc === P.loc);
  $('#pos_body').innerHTML = `<div class="card"><div class="row between"><span>${esc(T('day'))}</span><b style="font-size:1.5rem">${money(tot)}</b></div>
    <div class="muted">${ok.length} ${esc(T('count'))}</div>
    <div class="row wrap" style="margin-top:6px">${['cash', 'mobile', 'card'].map((m) => `<span class="chip">${esc(lab(MODEL[m]))} ${money(by(m))}</span>`).join('')}<span class="chip warn">${esc(T('dueword'))} ${money(dueT)}</span>${coll ? `<span class="chip ok">${esc(T('collect'))} ${money(coll)}</span>` : ''}</div></div>
    ${failedQ().filter((x) => x.p_loc === P.loc).map((x) => `<div class="notice bad"><b>${esc(T('failed'))}</b> · ${money(x._total || 0)} · ${esc(x._err || '')}<div class="row" style="margin-top:6px"><button class="full" data-act="pos_discard" data-v="${esc(x.p_client)}">${esc(T('discard'))}</button></div></div>`).join('')}
    ${pend.length ? `<div class="notice warn">${pend.length} ${esc(T('pending'))}: ${money(pend.reduce((a, p) => a + (p._total || 0), 0))}</div>` : ''}
    ${P.day.length ? P.day.map((s) => `<div class="card item" data-act="pos_open" data-v="${s.id}" style="${s.status === 'void' ? 'opacity:.55' : ''}"><div><div class="nm">#${s.receipt} · ${hhmm(s.sold_at)} ${s.quick ? '⚡' : ''}${s.sale_type === 'wholesale' ? ' ◆' : ''}</div>
        <div class="muted" style="font-size:.85rem">${esc(lab(MODEL[s.pay_mode]))} · ${esc(s.created_staff || '')}${s.customer ? ' · ' + esc(s.customer) : ''}</div></div>
        <div class="pr"><b>${money(s.total)}</b>${s.status === 'void' ? `<div><span class="chip bad">${esc(T('voided'))}</span></div>` : Number(s.due_amount) > 0 ? `<div><span class="chip warn">${esc(T('dueword'))} ${money(s.due_amount)}</span></div>` : ''}</div></div>`).join('') : `<p class="muted center">${esc(T('nodata'))}</p>`}`;
}
function receiptText(s, pays, cust) {
  const loc = B.ENV.locs.find((l) => l.id === s.location_id) || {}, lines = (s.lines || []).map((l) => `${l.name}${l.item_id || l.custom ? ` ${fmt(l.qty)} × ${fmt(l.price)}` : ''} = ${fmt(l.amount)}`);
  return [`${A.BRAND_TEXT || 'ইসলামিয়া মিষ্টি ঘর'}`, `ISLAMIYA MISTY GHAR`, `${nm(loc)}`, `${T('receipt')} ${loc.code || ''}-${s.receipt} · ${s.sale_date} ${hhmm(s.sold_at)}`, '—', ...lines,
    Number(s.discount) ? `${lab(L('ডিসকাউন্ট', 'Discount', 'Discount'))}: -${fmt(s.discount)}` : null, `${T('total')}: ${fmt(s.total)}`,
    ...(pays || []).map((p) => `${lab(MODEL[p.mode])}${p.wallet ? ' (' + p.wallet + ')' : ''}: ${fmt(p.amount)}`), Number(s.due_amount) > 0 ? `${T('dueword')}: ${fmt(s.due_amount)}` : null,
    cust ? `${T('cust')}: ${cust.name} ${cust.mobile}` : null, lab(L('ধন্যবাদ', 'Thank you', 'ধন্যবাদ'))].filter(Boolean).join('\n');
}
async function saleSheet(id) {
  const s = P.day.find((x) => x.id === id); if (!s) return;
  const canVoid = (perms().approve || S.ctx.is_owner) && s.status === 'done';
  const [pr, cu] = await Promise.all([sb.from('sale_payments').select('mode,wallet,ref,amount,voided').eq('sale_id', id), s.customer_id ? sb.from('customers').select('name,mobile').eq('id', s.customer_id).maybeSingle() : { data: null }]);
  const pays = (pr.data || []).filter((p) => !p.voided);
  P.shareText = receiptText(s, pays, cu.data);
  openSheet(`<h2>#${s.receipt} · ${hhmm(s.sold_at)}</h2>
    <div class="stack">${(s.lines || []).map((l) => `<div class="row between"><span>${esc(l.name)}${l.item_id || l.custom ? ` <span class="muted">${fmt(l.qty)} × ${fmt(l.price)}${l.override ? ' ✎' : ''}</span>` : ''}</span><b>${money(l.amount)}</b></div>`).join('')}
      ${Number(s.discount) ? `<div class="row between"><span>${esc(T('discount'))}</span><b>− ${money(s.discount)}</b></div>` : ''}
      <div class="row between"><b>${esc(T('total'))}</b><b style="font-size:1.3rem">${money(s.total)}</b></div>
      ${pays.map((p) => `<div class="row between muted"><span>${esc(lab(MODEL[p.mode]))}${p.wallet ? ' · ' + esc(p.wallet) : ''}${p.ref ? ' · ' + esc(p.ref) : ''}</span><span>${money(p.amount)}</span></div>`).join('')}
      ${Number(s.due_amount) > 0 && s.status === 'done' ? `<div class="notice warn">${esc(T('dueword'))}: <b>${money(s.due_amount)}</b></div>` : ''}
      <div class="muted">${esc(T('by'))}: ${esc(s.created_staff || '')}${cu.data ? ' · ' + esc(cu.data.name) + ' ' + esc(cu.data.mobile) : s.customer ? ' · ' + esc(s.customer) : ''}${s.note ? ' · ' + esc(s.note) : ''}</div>
      ${s.status === 'void' ? `<div class="notice bad">${esc(T('voided'))}: ${esc(s.void_note || '')} (${esc(s.void_staff || '')})</div>` : ''}
      <button class="full" data-act="pos_share">${esc(T('share'))}</button>
      ${canVoid ? `<label>${esc(T('voidwhy'))}</label><input id="void_note"><button class="danger full" data-act="pos_void" data-v="${s.id}">${esc(T('void'))}</button>` : ''}
      <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}

// ---------- handlers ----------
Object.assign(A.H, {
  pos_tab: (a) => { P.tab = a.dataset.v; drawPos(); },
  pos_cat: (a) => { P.cat = a.dataset.v; drawSell(true); },
  pos_add: (a) => { const i = itemById(a.dataset.v); bump(i.id); if (i.unit === 'pc') addItem(i.id, 1); else qtySheet(i.id); },
  pos_q_set: (a) => { $('#pos_qty').value = a.dataset.n; },
  pos_q_ok: (a) => { const q = nnum($('#pos_qty').value); if (!(q > 0)) return toast(T('qty')); closeSheet(); addItem(a.dataset.v, q); },
  pos_other: () => otherSheet(),
  pos_ot_ok: () => { const name = ($('#ot_name').value || '').trim(), qty = nnum($('#ot_qty').value), price = nnum($('#ot_price').value);
    if (!name) return toast(lab(ERRS.name_required)); if (!(qty > 0) || !(price > 0)) return toast(T('oprice'));
    P.cart.push({ kind: 'custom', name, unit: ($('#ot_unit').value || '').trim(), qty, price }); closeSheet(); refreshSell(); },
  pos_newitem: () => { location.hash = '#/items'; setTimeout(() => { if (A.H.itemnew) A.H.itemnew(); }, 700); },
  pos_cart: () => cartSheet(),
  pos_type: (a) => { P.type = a.dataset.v; [...document.querySelectorAll('[data-act=pos_type]')].forEach((b) => b.classList.toggle('on', b.dataset.v === P.type)); drawCust(); },
  pos_cust_show: () => { P.cust.show = true; drawCust(); },
  pos_step: (a) => { const l = P.cart[Number(a.dataset.k)], st = stepOf(l.kind === 'item' ? itemById(l.item_id).unit : 'pc'), n = Math.round((l.qty + Number(a.dataset.d) * st) * 1000) / 1000;
    if (n <= 0) P.cart.splice(Number(a.dataset.k), 1); else l.qty = n; afterCartChange(); },
  pos_rm: (a) => { P.cart.splice(Number(a.dataset.k), 1); afterCartChange(); },
  pos_qedit: (a) => { const l = P.cart[Number(a.dataset.k)]; const v = prompt(T('qty'), l.qty); if (v === null) return; const n = nnum(v); if (n > 0) { l.qty = n; afterCartChange(); } },
  pos_price: (a) => { const l = P.cart[Number(a.dataset.k)]; const v = prompt(T('priceov'), l.price); if (v === null) return; const n = nnum(v); if (n >= 0 && v.trim() !== '') { l.price = n; l.ov = n !== Number(itemById(l.item_id).sell_price); afterCartChange(); } },
  pos_confirm: () => {
    const disc = discVal(), sub = cartSub();
    if (disc > sub) return toast(lab(ERRS.bad_discount));
    const pe = B.pay.check(P.st); if (pe) return toast(lab(ERRS[pe]));
    let mobile = null, cname = null;
    if (needCust() || P.cust.mobile) {
      mobile = normMobile(P.cust.mobile);
      if (!mobile) return toast(P.cust.mobile ? lab(ERRS.bad_mobile) : lab(ERRS.customer_required));
      cname = (P.cust.found && P.cust.found.found ? P.cust.found.name : ($('#cu_name') || {}).value || P.cust.name || '').trim();
      if (!cname) return toast(lab(ERRS.customer_name_required));
    }
    const total = netTotal(), paid = B.pay.paid(P.st), single = P.st.rows.length === 1 && P.st.rows[0].mode === 'cash', given = single ? nnum(P.st.rows[0].given) : 0, cashAmt = single ? r2(nnum(P.st.rows[0].amount)) : 0;
    const quickOnly = P.cart.length > 0 && P.cart.every((l) => l.kind === 'quick');
    return submitSale(build({ lines: linesOf(), disc, payments: B.pay.list(P.st), mobile, cname, type: P.type, note: ($('#cart_note') || {}).value || '', quick: quickOnly, total, paid }), given > cashAmt ? r2(given - cashAmt) : 0);
  },
  pos_quick: () => quickSheet(),
  pos_qs_cash: () => { const q = readQuick(); if (!q) return;      // a one-tap cash sale of just this amount; the cart is left alone
    return submitSale(build({ lines: [{ item_id: null, name: q.name, amount: q.amount }], disc: 0, payments: [{ mode: 'cash', amount: q.amount }], type: 'retail', quick: true, total: q.amount, paid: q.amount }), 0); },
  pos_qs_more: () => { const q = readQuick(); if (!q) return; P.cart.push(q); closeSheet(); refreshSell(); cartSheet(); },
  pos_open: (a) => saleSheet(a.dataset.v),
  pos_share: async () => { const txt = P.shareText || ''; try { if (navigator.share) await navigator.share({ text: txt }); else { await navigator.clipboard.writeText(txt); toast('✓'); } } catch (e) { /* cancelled */ } },
  pos_discard: (a) => { setFailed(failedQ().filter((x) => x.p_client !== a.dataset.v)); drawToday(); },
  pos_void: async (a) => { const n = ($('#void_note').value || '').trim(); if (!n) return toast(T('needNote'));
    const { error } = await sb.rpc('void_sale', { p_id: a.dataset.v, p_note: n }); if (error) return fail(error); closeSheet(); toast(T('voided')); drawToday(); },
});
document.addEventListener('input', (e) => {
  const id = e.target.id;
  if (id === 'pos_q') { P.q = e.target.value; drawItems(true); }
  if (id === 'cart_disc') { B.pay.syncAuto(P.st); const box = $('#cart_pay'); if (box) { const f = document.activeElement; box.innerHTML = B.pay.html(P.st); if (f && f.id === 'cart_disc') f.focus(); } updDue(); }
  if (id === 'cu_mobile') { P.cust.mobile = e.target.value; P.cust.found = null; P.cust.name = ''; lookup(); const el = $('#cart_cust'); const m = normMobile(P.cust.mobile); if (m) drawCust(); }
  if (id === 'cu_name') P.cust.name = e.target.value;
});
document.addEventListener('change', (e) => { if (e.target.id === 'pos_loc') { P.loc = Number(e.target.value); store.set('bos_pos_loc', String(P.loc)); resetCart(); drawPos(); } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { pos: viewPos });
B.pos = { flush, normMobile };
})();
