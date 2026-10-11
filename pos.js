/* Islamia BOS · POS: running sales. Item-wise sale, quick sale for rush, today's list, void with a note.
   Prices and totals are fixed by the server (record_sale). A sale that cannot be sent waits in a local queue and is re-sent. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const money = (n) => '৳ ' + fmt(n);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const hhmm = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' });
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));

const CATS = { sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'),
  cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)') };
const UNITS = { kg: L('কেজি', 'KG', 'KG'), pc: L('পিস', 'Piece', 'Piece'), lb: L('পাউন্ড', 'Pound', 'Pound') };
const MODES = [['cash', L('নগদ', 'Cash', 'Cash')], ['mobile', L('মোবাইল ব্যাংকিং', 'Mobile', 'Mobile')], ['card', L('কার্ড', 'Card', 'Card')], ['due', L('বাকি', 'Due', 'Due (বাকি)')]];
const X = {
  title: L('সেল (POS)', 'Sales (POS)', 'Sale (POS)'), sell: L('বিক্রি', 'Sell', 'Sell'), today: L('আজকের সেল', "Today's sales", 'Today সেল'),
  quick: L('কুইক সেল', 'Quick sale', 'Quick Sale'), cart: L('কার্ট', 'Cart', 'Cart'), pay: L('পেমেন্ট', 'Pay', 'Pay'), total: L('মোট', 'Total', 'Total'),
  discount: L('ডিসকাউন্ট (৳)', 'Discount (৳)', 'Discount (৳)'), given: L('গ্রাহক দিলেন (৳)', 'Customer gave (৳)', 'Customer দিলেন (৳)'), change: L('ফেরত', 'Change', 'Change (ফেরত)'),
  customer: L('গ্রাহকের নাম (বাকির জন্য লাগবে)', 'Customer name (needed for due)', 'Customer নাম (Due হলে লাগবে)'), note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'),
  confirm: L('সেল সম্পন্ন', 'Complete sale', 'Complete Sale'), empty: L('কার্ট খালি — আইটেম ট্যাপ করুন', 'Cart is empty — tap an item', 'Cart খালি — Item ট্যাপ করুন'),
  amount: L('টাকার পরিমাণ', 'Amount', 'Amount'), what: L('কী বিক্রি (ঐচ্ছিক)', 'What was sold (optional)', 'কী বিক্রি (ঐচ্ছিক)'), all: L('সব', 'All', 'All'), freq: L('বেশি বিক্রি', 'Frequent', 'Frequent'),
  search: L('আইটেম খুঁজুন', 'Search item', 'Item খুঁজুন'), qty: L('পরিমাণ', 'Quantity', 'Quantity'), add: L('কার্টে দিন', 'Add to cart', 'Add to Cart'), remove: L('বাদ', 'Remove', 'Remove'),
  priceov: L('দাম বদলান (এটি ব্যতিক্রম তালিকায় যাবে)', 'Change price (goes to exceptions)', 'Price বদলান (Exception এ যাবে)'), receipt: L('রসিদ', 'Receipt', 'Receipt'),
  done: L('সেল হয়েছে', 'Sale done', 'Sale হয়েছে'), queued: L('নেট নেই — সেল জমা আছে, নেট এলে পাঠানো হবে', 'No network — sale saved, will be sent when online', 'Net নেই — Sale জমা আছে, Online হলে যাবে'),
  pending: L('পাঠানো বাকি', 'waiting to send', 'পাঠানো বাকি'), void: L('বাতিল', 'Void', 'Void'), voided: L('বাতিল হয়েছে', 'Voided', 'Voided'), voidwhy: L('বাতিলের কারণ (লিখতেই হবে)', 'Reason for voiding (required)', 'Void এর কারণ (লিখতেই হবে)'),
  day: L('আজকের মোট', "Today's total", 'Today মোট'), count: L('টি সেল', 'sales', 'sales'), loc: L('লোকেশন', 'Location', 'Location'), nodata: L('এখনও কোনো সেল নেই', 'No sales yet', 'এখনও কোনো sale নেই'),
  noprice: L('দাম লেখা নেই', 'No price', 'Price নেই'), back: L('ফিরুন', 'Back', 'Back'), close: L('বন্ধ', 'Close', 'Close'), lines: L('আইটেম', 'Items', 'Items'), by: L('বিক্রেতা', 'Sold by', 'Sold by'),
  dueNeeds: L('বাকির জন্য গ্রাহকের নাম লিখুন', 'Enter a customer name for a due sale', 'Due হলে Customer এর নাম লিখুন'), badDisc: L('ডিসকাউন্ট মোটের বেশি হতে পারে না', 'Discount cannot exceed the total', 'Discount মোটের বেশি হতে পারে না'),
  failedmsg: L('কিছু সেল নিয়মে আটকেছে — আজকের সেল পাতায় দেখুন', 'Some sales were refused — see Today', 'কিছু Sale আটকেছে — Today পাতায় দেখুন'), failed: L('পাঠানো যায়নি (নিয়মে আটকেছে)', 'Could not be recorded (refused)', 'পাঠানো যায়নি (আটকেছে)'), discard: L('বাদ দিন', 'Discard', 'Discard'),
  needNote: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'), noloc: L('কোনো লোকেশন দেওয়া নেই — মালিককে জানান', 'No location assigned — tell the owner', 'কোনো Location দেওয়া নেই — Owner কে জানান'),
};
const T = (k) => lab(X[k]);

// ---------- state ----------
const P = { loc: null, cat: '', q: '', items: [], locs: [], cart: [], mode: 'cash', tab: 'sell', day: [], busy: false };
const uidK = () => (S.ctx && S.ctx.profile ? S.ctx.profile.id : 'anon');
const QK = () => 'bos_pos_queue_' + uidK(), XK = () => 'bos_pos_failed_' + uidK(), FKEY = 'bos_pos_freq';
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const nnum = (v) => { const n = Number(norm(v).trim()); return Number.isFinite(n) ? n : 0; };
const jget = (k, d) => { try { return JSON.parse(store.get(k)) || d; } catch (e) { return d; } };
const queue = () => jget(QK(), []);
const setQueue = (q) => store.set(QK(), JSON.stringify(q));
const failedQ = () => jget(XK(), []);
const setFailed = (q) => store.set(XK(), JSON.stringify(q));
const BUSINESS = /^(no_lines|bad_mode|bad_qty|bad_price|bad_amount|bad_discount|no_price|item_not_found|due_needs_customer|not allowed)/;
const freq = () => jget(FKEY, {});
const bump = (id) => { const f = freq(); f[id] = (f[id] || 0) + 1; store.set(FKEY, JSON.stringify(f)); };
const perms = () => S.ctx.perms.POS || {};
const stepOf = (u) => (u === 'pc' ? 1 : 0.5);
const unitL = (u) => lab(UNITS[u]) || u || '';
const itemById = (id) => P.items.find((i) => i.id === id);
const lineAmt = (l) => Math.round(l.qty * l.price * 100) / 100;
const cartSub = () => P.cart.reduce((s, l) => s + lineAmt(l), 0);
const isNet = (e) => !navigator.onLine || /fetch|network|load failed|timeout/i.test((e && e.message) || '');

async function load() {
  await B.loadStatic();
  const [it, lc] = await Promise.all([sb.from('items').select('id,code,name_bn,name_en,name_mix,category,category_bn,unit,sell_price,is_active').eq('is_active', true).order('code'), Promise.resolve(B.ENV.locs)]);
  if (it.error) throw it.error;
  P.items = it.data.filter((i) => i.sell_price !== null);
  const all = B.ENV.locs;
  P.locs = S.ctx.is_owner || S.ctx.roles.includes('management') ? all : all.filter((l) => S.ctx.locations.includes(l.id));
  if (!P.loc || !P.locs.find((l) => l.id === P.loc)) P.loc = store.get('bos_pos_loc') ? Number(store.get('bos_pos_loc')) : (P.locs[0] || {}).id;
  if (!P.locs.find((l) => l.id === P.loc)) P.loc = (P.locs[0] || {}).id;
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
  $('#pos_body').innerHTML = `
    <div class="row"><input id="pos_q" placeholder="${esc(T('search'))}" value="${esc(P.q)}" style="flex:1"><button class="primary" data-act="pos_quick" ${can ? '' : 'disabled'}>⚡ ${esc(T('quick'))}</button></div>
    <div class="row wrap" style="margin:10px 0" id="pos_cats">${[['', T('all')], ['_f', T('freq')], ...cats.map((c) => [c, cn(c)])].map(([c, l]) =>
      `<button class="tog ${P.cat === c ? 'on' : ''}" data-act="pos_cat" data-v="${esc(c)}">${esc(l)}</button>`).join('')}</div>
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
  const inCart = new Map(P.cart.map((l) => [l.item_id, l.qty]));
  const l = visibleItems();
  $('#pos_items').innerHTML = l.map((i) => `<button class="pos-item ${inCart.has(i.id) ? 'in' : ''}" data-cat="${esc(i.category || '')}" data-act="pos_add" data-v="${i.id}" ${can ? '' : 'disabled'}>
      <span class="pn">${esc(nm(i))}</span><span class="pp"><span class="cur">৳</span>${fmt(i.sell_price)}<small> / ${esc(unitL(i.unit))}</small></span>${inCart.has(i.id) ? `<span class="pq">${fmt(inCart.get(i.id))}</span>` : ''}</button>`).join('')
    || `<p class="muted center">—</p>`;
}
function drawBar(can) {
  const n = P.cart.length, sub = cartSub();
  $('#pos_bar').innerHTML = `<div><div class="muted" style="font-size:.8rem">${n ? n + ' · ' + esc(T('lines')) : esc(T('cart'))}</div><b style="font-size:1.25rem">${money(sub)}</b></div>
    <button class="primary" data-act="pos_cart" ${n && can ? '' : 'disabled'}>${esc(T('pay'))} →</button>`;
}
function addToCart(id, qty) {
  const i = itemById(id); if (!i) return;
  const ex = P.cart.find((l) => l.item_id === id);
  if (ex) ex.qty = Math.round((ex.qty + qty) * 1000) / 1000; else P.cart.push({ item_id: id, qty, price: Number(i.sell_price), ov: false });
  drawItems(true); drawBar(true);
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

// ---------- cart / pay ----------
function cartSheet() {
  const sub = cartSub();
  openSheet(`<h2>${esc(T('cart'))}</h2><div id="cart_lines" class="stack"></div>
    <div class="row between" style="margin:10px 0"><span>${esc(T('total'))}</span><b style="font-size:1.4rem" id="cart_total"></b></div>
    <div class="row wrap" id="cart_modes">${MODES.map(([m, l]) => `<button class="tog ${P.mode === m ? 'on' : ''}" data-act="pos_mode" data-v="${m}">${esc(lab(l))}</button>`).join('')}</div>
    <div id="cart_more" class="stack" style="margin-top:10px"></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('back'))}</button><button class="primary full" id="cart_ok" data-act="pos_confirm">${esc(T('confirm'))}</button></div>`);
  drawCartLines(); drawCartMore();
}
const discVal = () => Math.max(0, nnum(($('#cart_disc') || {}).value || 0));
function drawCartLines() {
  $('#cart_lines').innerHTML = P.cart.map((l, k) => { const i = itemById(l.item_id); return `<div class="cart-line"><div style="flex:1;min-width:0"><div class="nm">${esc(nm(i))}</div>
      <div class="muted" style="font-size:.85rem" data-act="pos_price" data-k="${k}">${money(l.price)} / ${esc(unitL(i.unit))} ✎</div></div>
      <div class="stepper"><button data-act="pos_step" data-k="${k}" data-d="-1">−</button><button data-act="pos_qedit" data-k="${k}" class="qv">${fmt(l.qty)}</button><button data-act="pos_step" data-k="${k}" data-d="1">＋</button></div>
      <b style="min-width:72px;text-align:right">${money(lineAmt(l))}</b></div>`; }).join('') || `<p class="muted">${esc(T('empty'))}</p>`;
  const tt = $('#cart_total'); if (tt) tt.textContent = money(Math.max(0, cartSub() - discVal()));
}
function drawCartMore() {
  const due = P.mode === 'due', cash = P.mode === 'cash';
  const keep = { d: ($('#cart_disc') || {}).value || '', g: ($('#cart_given') || {}).value || '', c: ($('#cart_cust') || {}).value || '', n: ($('#cart_note') || {}).value || '' };
  $('#cart_more').innerHTML = `<div class="row"><div style="flex:1"><label>${esc(T('discount'))}</label><input id="cart_disc" inputmode="decimal" value="${esc(keep.d)}"></div>
      ${cash ? `<div style="flex:1"><label>${esc(T('given'))}</label><input id="cart_given" inputmode="decimal" value="${esc(keep.g)}"></div>` : ''}</div>
    ${cash ? `<div class="notice ok" id="cart_change" style="display:none"></div>` : ''}
    ${due ? `<div><label>${esc(T('customer'))}</label><input id="cart_cust" value="${esc(keep.c)}"></div>` : ''}
    <div><label>${esc(T('note'))}</label><input id="cart_note" value="${esc(keep.n)}"></div>`;
  updTotals();
}
function updTotals() {
  const tot = Math.max(0, cartSub() - discVal()), tt = $('#cart_total'); if (tt) tt.textContent = money(tot);
  const g = $('#cart_given'), c = $('#cart_change');
  if (g && c) { const given = nnum(g.value || 0); if (given > 0) { c.style.display = ''; c.textContent = given >= tot ? T('change') + ': ' + money(given - tot) : '−' + money(tot - given); c.className = 'notice ' + (given >= tot ? 'ok' : 'bad'); } else c.style.display = 'none'; }
}

// ---------- quick sale ----------
function quickSheet() {
  openSheet(`<h2>⚡ ${esc(T('quick'))}</h2>
    <label>${esc(T('amount'))} (৳)</label><input id="qs_amt" inputmode="decimal" style="font-size:1.8rem;font-weight:700" autocomplete="off">
    <label style="margin-top:8px">${esc(T('what'))}</label><input id="qs_what">
    <div class="row wrap" style="margin:12px 0" id="qs_modes">${MODES.map(([m, l]) => `<button class="tog ${P.mode === m ? 'on' : ''}" data-act="pos_qmode" data-v="${m}">${esc(lab(l))}</button>`).join('')}</div>
    <div id="qs_cust" style="display:${P.mode === 'due' ? 'block' : 'none'}"><label>${esc(T('customer'))}</label><input id="qs_c"></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="pos_qs_ok">${esc(T('confirm'))}</button></div>`);
  setTimeout(() => { const e = $('#qs_amt'); if (e) e.focus(); }, 60);
}

// ---------- sending (with offline queue) ----------
function payload(o) { return { p_client: uid(), p_loc: P.loc, p_lines: o.lines, p_discount: o.disc || 0, p_mode: o.mode, p_tendered: o.tendered || null, p_customer: o.cust || null, p_note: o.note || null, p_quick: !!o.quick, p_sold_at: new Date().toISOString(), _t: Date.now(), _total: o.total }; }
const clean = (p) => { const { _t, _total, ...r } = p; return r; };
async function send(p) {
  const { data, error } = await sb.rpc('record_sale', clean(p));
  return { data, error };
}
async function submitSale(p, change) {
  if (P.busy) return; P.busy = true;
  const btn = $('#cart_ok') || $('[data-act="pos_qs_ok"]'); if (btn) btn.disabled = true;
  try {
    const { data, error } = await send(p);
    if (error) {
      if (isNet(error)) { setQueue([...queue(), p]); closeSheet(); P.cart = []; toast(T('queued')); return afterSale(); }
      if (btn) btn.disabled = false;
      return fail(error);
    }
    closeSheet(); P.cart = [];
    toast(`${T('done')} · ${T('receipt')} ${data.receipt} · ${money(data.total)}${change > 0 ? ' · ' + T('change') + ' ' + money(change) : ''}`);
    afterSale();
  } finally { P.busy = false; }
}
function afterSale() { if (location.hash.startsWith('#/pos')) drawPos(); }
let flushing = false;
async function flush() {
  if (flushing || !S.ctx || !navigator.onLine) return;
  const q = queue(); if (!q.length) return;
  flushing = true;
  const done = new Set(), bad = [];
  try {
    for (const p of q) {
      const { error } = await send(p);
      if (!error) { done.add(p.p_client); continue; }
      const m = (error && error.message) || '';
      if (BUSINESS.test(m)) { done.add(p.p_client); bad.push({ ...p, _err: m }); continue; }   // refused by the rules: keep it visible, never lose it
      if (isNet(error) || /jwt|token|401|403|5\d\d|unauthor|permission/i.test(m)) break;       // not the sale's fault: keep and retry later
      break;
    }
  } finally {
    // re-read: a sale queued while we were sending must survive
    setQueue(queue().filter((x) => !done.has(x.p_client)));
    if (bad.length) { setFailed([...failedQ(), ...bad]); toast(T('failedmsg')); }
    flushing = false;
  }
  if (bad.length && location.hash.startsWith('#/pos')) drawPos();
}
window.addEventListener('online', flush);
setInterval(flush, 30000);

// ---------- today ----------
async function drawToday() {
  $('#pos_body').innerHTML = `<p class="muted">${esc(t('loading'))}</p>`;
  const r = await sb.from('sales').select('*').eq('location_id', P.loc).eq('sale_date', today()).order('receipt', { ascending: false });
  if (r.error) return fail(r.error);
  P.day = r.data;
  const ok = P.day.filter((s) => s.status === 'done');
  const by = (m) => ok.filter((s) => s.pay_mode === m).reduce((a, s) => a + Number(s.total), 0);
  const tot = ok.reduce((a, s) => a + Number(s.total), 0);
  const pend = queue().filter((x) => x.p_loc === P.loc);
  $('#pos_body').innerHTML = `<div class="card"><div class="row between"><span>${esc(T('day'))}</span><b style="font-size:1.5rem">${money(tot)}</b></div>
    <div class="muted">${ok.length} ${esc(T('count'))}</div>
    <div class="row wrap" style="margin-top:6px">${MODES.map(([m, l]) => `<span class="chip">${esc(lab(l))} ${money(by(m))}</span>`).join('')}</div></div>
    ${failedQ().filter((x) => x.p_loc === P.loc).map((x, k) => `<div class="notice bad"><b>${esc(T('failed'))}</b> · ${money(x._total || 0)} · ${esc(x._err || '')}<div class="row" style="margin-top:6px"><button class="full" data-act="pos_discard" data-v="${esc(x.p_client)}">${esc(T('discard'))}</button></div></div>`).join('')}
    ${pend.length ? `<div class="notice warn">${pend.length} ${esc(T('pending'))}: ${money(pend.reduce((a, p) => a + (p._total || 0), 0))}</div>` : ''}
    ${P.day.length ? P.day.map((s) => `<div class="card item" data-act="pos_open" data-v="${s.id}" style="${s.status === 'void' ? 'opacity:.55' : ''}"><div><div class="nm">#${s.receipt} · ${hhmm(s.sold_at)} ${s.quick ? '⚡' : ''}</div>
        <div class="muted" style="font-size:.85rem">${esc(lab((MODES.find((m) => m[0] === s.pay_mode) || [])[1]))} · ${esc(s.created_staff || '')}${s.customer ? ' · ' + esc(s.customer) : ''}</div></div>
        <div class="pr"><b>${money(s.total)}</b>${s.status === 'void' ? `<div><span class="chip bad">${esc(T('voided'))}</span></div>` : ''}</div></div>`).join('') : `<p class="muted center">${esc(T('nodata'))}</p>`}`;
}
function saleSheet(id) {
  const s = P.day.find((x) => x.id === id); if (!s) return;
  const canVoid = (perms().approve || S.ctx.is_owner) && s.status === 'done';
  openSheet(`<h2>#${s.receipt} · ${hhmm(s.sold_at)}</h2>
    <div class="stack">${(s.lines || []).map((l) => `<div class="row between"><span>${esc(l.name)}${l.item_id ? ` <span class="muted">${fmt(l.qty)} × ${fmt(l.price)}${l.override ? ' ✎' : ''}</span>` : ''}</span><b>${money(l.amount)}</b></div>`).join('')}
      ${Number(s.discount) ? `<div class="row between"><span>${esc(T('discount'))}</span><b>− ${money(s.discount)}</b></div>` : ''}
      <div class="row between"><b>${esc(T('total'))}</b><b style="font-size:1.3rem">${money(s.total)}</b></div>
      <div class="muted">${esc(lab((MODES.find((m) => m[0] === s.pay_mode) || [])[1]))} · ${esc(T('by'))}: ${esc(s.created_staff || '')}${s.customer ? ' · ' + esc(s.customer) : ''}${s.note ? ' · ' + esc(s.note) : ''}</div>
      ${s.status === 'void' ? `<div class="notice bad">${esc(T('voided'))}: ${esc(s.void_note || '')} (${esc(s.void_staff || '')})</div>` : ''}
      ${canVoid ? `<label>${esc(T('voidwhy'))}</label><input id="void_note"><button class="danger full" data-act="pos_void" data-v="${s.id}">${esc(T('void'))}</button>` : ''}
      <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}

// ---------- handlers ----------
Object.assign(A.H, {
  pos_tab: (a) => { P.tab = a.dataset.v; drawPos(); },
  pos_cat: (a) => { P.cat = a.dataset.v; drawSell(true); },
  pos_add: (a) => { const i = itemById(a.dataset.v); bump(i.id); if (i.unit === 'pc') addToCart(i.id, 1); else qtySheet(i.id); },
  pos_q_set: (a) => { $('#pos_qty').value = a.dataset.n; },
  pos_q_ok: (a) => { const q = nnum($('#pos_qty').value); if (!(q > 0)) return toast(T('qty')); closeSheet(); addToCart(a.dataset.v, q); },
  pos_cart: () => cartSheet(),
  pos_mode: (a) => { P.mode = a.dataset.v; [...document.querySelectorAll('#cart_modes .tog')].forEach((b) => b.classList.toggle('on', b.dataset.v === P.mode)); drawCartMore(); },
  pos_step: (a) => { const l = P.cart[Number(a.dataset.k)], st = stepOf(itemById(l.item_id).unit), n = Math.round((l.qty + Number(a.dataset.d) * st) * 1000) / 1000;
    if (n <= 0) P.cart.splice(Number(a.dataset.k), 1); else l.qty = n; if (!P.cart.length) { closeSheet(); drawSell(true); return; } drawCartLines(); updTotals(); drawBar(true); },
  pos_qedit: (a) => { const l = P.cart[Number(a.dataset.k)]; const v = prompt(T('qty'), l.qty); if (v === null) return; const n = nnum(v); if (n > 0) { l.qty = n; drawCartLines(); updTotals(); drawBar(true); } },
  pos_price: (a) => { const l = P.cart[Number(a.dataset.k)]; const v = prompt(T('priceov'), l.price); if (v === null) return; const n = nnum(v); if (n >= 0 && v.trim() !== '') { l.price = n; l.ov = n !== Number(itemById(l.item_id).sell_price); drawCartLines(); updTotals(); drawBar(true); } },
  pos_confirm: () => {
    const sub = cartSub(), disc = discVal();
    if (disc > sub) return toast(T('badDisc'));
    const cust = ($('#cart_cust') || {}).value || '';
    if (P.mode === 'due' && !cust.trim()) return toast(T('dueNeeds'));
    const given = nnum(($('#cart_given') || {}).value || 0), total = sub - disc;
    const lines = P.cart.map((l) => ({ item_id: l.item_id, qty: l.qty, price: l.price, override: l.ov, name: nm(itemById(l.item_id)) }));
    return submitSale(payload({ lines, disc, mode: P.mode, tendered: P.mode === 'cash' && given > 0 ? given : null, cust, note: ($('#cart_note') || {}).value || '', quick: false, total }), P.mode === 'cash' && given > total ? given - total : 0);
  },
  pos_quick: () => quickSheet(),
  pos_qmode: (a) => { P.mode = a.dataset.v; [...document.querySelectorAll('#qs_modes .tog')].forEach((b) => b.classList.toggle('on', b.dataset.v === P.mode)); $('#qs_cust').style.display = P.mode === 'due' ? 'block' : 'none'; },
  pos_qs_ok: () => {
    const amt = nnum($('#qs_amt').value); if (!(amt > 0)) return toast(T('amount'));
    const cust = ($('#qs_c') || {}).value || ''; if (P.mode === 'due' && !cust.trim()) return toast(T('dueNeeds'));
    return submitSale(payload({ lines: [{ item_id: null, amount: amt, name: ($('#qs_what').value || '').trim() || 'Quick sale' }], disc: 0, mode: P.mode, cust, quick: true, total: amt }), 0);
  },
  pos_open: (a) => saleSheet(a.dataset.v),
  pos_discard: (a) => { setFailed(failedQ().filter((x) => x.p_client !== a.dataset.v)); drawToday(); },
  pos_void: async (a) => { const n = ($('#void_note').value || '').trim(); if (!n) return toast(T('needNote'));
    const { error } = await sb.rpc('void_sale', { p_id: a.dataset.v, p_note: n }); if (error) return fail(error); closeSheet(); toast(T('voided')); drawToday(); },
});
document.addEventListener('input', (e) => {
  if (e.target.id === 'pos_q') { P.q = e.target.value; drawItems(true); }
  if (e.target.id === 'cart_disc' || e.target.id === 'cart_given') updTotals();
});
document.addEventListener('change', (e) => { if (e.target.id === 'pos_loc') { P.loc = Number(e.target.value); store.set('bos_pos_loc', String(P.loc)); P.cart = []; drawPos(); } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { pos: viewPos });
B.pos = { flush };
})();
