/* Islamia BOS · Step W: online order review board (#/packflags) for step E9 (supabase/phase77.sql, phase76.sql):
   - packed orders with a stock check (online_order_stock_check: warning only, packing is never blocked)
   - flags "the sale of a delivered order was voided" (online_order_flags_list / online_order_flag_review - needs POS approve, a reason is required)
   - possible duplicate orders (order_dup_flags_list / order_dup_flag_review)
   - the three E9 switches, each next to the system's advice (online_pack_warn_on, online_pack_reserve_on, online_keep_order_price) - owner only
   Handlers are prefixed wpf_. English mode has no Bangla letters. Loaded after stepw_common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.w) return;
const { sb, esc, toast, shell, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab, W = B.w;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('অনলাইন অর্ডার যাচাই', 'Online order review', 'Online order যাচাই'),
  intro: L('প্যাক হওয়া অর্ডারে stock কম কি না, বাতিল হওয়া বিক্রির অর্ডার, আর সম্ভাব্য দুবার আসা অর্ডার। এখানে কিছুই আটকায় না — শুধু দেখায়।', 'Packed orders with short stock, orders whose sale was voided, and possible double orders. Nothing here blocks anything - it only shows.', 'Packed order-এ stock কম কি না, void হওয়া sale-এর order, আর সম্ভাব্য double order। এখানে কিছুই আটকায় না — শুধু দেখায়।'),
  tPack: L('প্যাক হওয়া অর্ডার — stock', 'Packed orders - stock', 'Packed order — stock'), tFlag: L('বিক্রি বাতিল হয়েছে', 'Sale voided', 'Sale void হয়েছে'), tDup: L('সম্ভাব্য দুবার', 'Possible doubles', 'সম্ভাব্য double'), tSw: L('সুইচ', 'Switches', 'Switch'),
  check: L('stock দেখুন', 'Check stock', 'Stock দেখুন'), off: L('প্যাক-সতর্কতা বন্ধ আছে — নিচের সুইচ চালু করলে এখানে দেখা যাবে', 'The pack warning is off - switch it on below to see results here', 'Pack warning বন্ধ আছে — নিচের switch চালু করলে এখানে দেখা যাবে'),
  ok: L('stock যথেষ্ট ✓', 'Stock is enough ✓', 'Stock যথেষ্ট ✓'), need: L('লাগবে', 'need', 'need'), have: L('আছে', 'have', 'have'), res: L('অন্য প্যাক হওয়া অর্ডারের জন্য ধরা', 'held by other packed orders', 'অন্য packed order-এর জন্য ধরা'), shortBy: L('কম', 'short by', 'short by'),
  order: L('অর্ডার', 'Order', 'Order'), noPacked: L('প্যাক হওয়া কোনো অর্ডার নেই', 'No packed orders', 'Packed order নেই'),
  review: L('যাচাই হয়েছে', 'Mark reviewed', 'Mark reviewed'), why: L('কী দেখলেন / কী করলেন (বাধ্যতামূলক)', 'What you checked / did (required)', 'কী দেখলেন / কী করলেন (required)'), send: L('সংরক্ষণ', 'Save', 'Save'), close: L('বন্ধ', 'Close', 'Close'),
  reviewed: L('যাচাই হয়েছে', 'Reviewed', 'Reviewed'), orderA: L('অর্ডার', 'Orders', 'Orders'), day: L('দিন', 'Day', 'Day'),
  flagHint: L('অর্ডার এখনও "ডেলিভারি হয়েছে" দেখাচ্ছে অথচ বিক্রিটা বাতিল। দেখে নোট লিখে যাচাই করুন।', 'The order still says delivered but its sale was voided. Look, write a note, mark reviewed.', 'Order এখনও "delivered" দেখাচ্ছে অথচ sale void। দেখে note লিখে review করুন।'),
  needApprove: L('যাচাই করতে POS অনুমোদনের অধিকার লাগবে', 'Marking reviewed needs the POS approve right', 'Review করতে POS approve-এর অধিকার লাগবে'),
  loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing here ✓', 'কিছু নেই ✓'), noperm: L('অর্ডার দেখার অনুমতি নেই', 'You are not allowed to see orders', 'Order দেখার permission নেই'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  k_warn: L('প্যাক করার সময় stock কম হলে সতর্কতা', 'Warn at pack time when stock is short', 'Pack করার সময় stock কম হলে warning'),
  k_reserve: L('প্যাক হওয়া অর্ডারের stock ধরে রাখা (নরম)', 'Soft-reserve stock of packed orders', 'Packed order-এর stock ধরে রাখা (soft)'),
  k_price: L('ডেলিভারিতে অর্ডারের দাম ধরে রাখা', 'Keep the order price at delivery', 'Delivery-তে order-এর দাম ধরে রাখা'),
  r_warn: L('চালু রাখাই ভালো: এটা শুধু সতর্কতা, প্যাক কখনও আটকায় না, আর কম stock-এর অর্ডার আগেই ধরা পড়ে।', 'Better on: it is a warning only, packing is never blocked, and short-stock orders are seen early.', 'On রাখাই ভালো: এটা শুধু warning, pack কখনও আটকায় না, আর কম stock-এর order আগেই ধরা পড়ে।'),
  r_reserve: L('একই মাল একাধিক প্যাক অর্ডারে দেওয়ার কথা থাকলে চালু করুন; কাউন্টারের বিক্রি এতে আটকায় না। সতর্কতা চালু না থাকলে এর কোনো কাজ নেই।', 'Turn on if the same goods are promised to several packed orders; the counter is not blocked. It does nothing while the pack warning is off.', 'একই মাল একাধিক packed order-এ দেওয়ার কথা থাকলে On করুন; counter-এর sale আটকায় না। Pack warning off থাকলে এর কাজ নেই।'),
  r_price: L('গ্রাহককে দাম কথা দিলে চালু করুন (অর্ডারের দামই বসবে)। নইলে বন্ধ — আজকের তালিকা দাম। দাম বদলালে সাধারণ ওভাররাইড-অনুমতি লাগে।', 'Turn on if you promise prices to customers (the order price is used). Otherwise off - today\'s list price. A different price needs the normal override approval.', 'Customer-কে দাম কথা দিলে On করুন (order-এর দামই বসবে)। নইলে Off — আজকের list price। দাম বদলালে normal override approval লাগে।'),
};
const T = (k) => lab(X[k]);
const WARN = (m) => `<div class="notice warn">${esc(m)}</div>`;
const SW = [['online_pack_warn_on', 'k_warn', 'r_warn', true], ['online_pack_reserve_on', 'k_reserve', 'r_reserve', false], ['online_keep_order_price', 'k_price', 'r_price', false]];
// advice per switch: warn = on; the other two only advice text (their recommended value is the "off" default unless the owner promises prices / shares stock)
const swCard = (k, lk, rk, rec) => W.recCard({ key: k, kind: 'switch', label: T(lk), current: B.rule ? B.rule(k, false) === true : false, recommended: rec, reason: T(rk) });
const D = { tab: 'pack' };

async function view() {
  await W.locs();
  shell(T('title'), `<p class="muted">${esc(T('intro'))}</p><div class="row wrap">${[['pack', 'tPack'], ['flag', 'tFlag'], ['dup', 'tDup'], ['sw', 'tSw']].map(([k, l]) => `<button class="tog ${D.tab === k ? 'on' : ''}" data-act="wpf_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div><div id="wpf_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  W.setRedraw(draw); return draw();
}
async function draw() {
  const el = $('#wpf_body'); if (!el) return;
  if (D.tab === 'sw') { el.innerHTML = SW.map((s) => swCard(...s)).join(''); return; }
  if (D.tab === 'pack') {
    const { data, error } = await sb.rpc('online_orders_list', { p_loc: null, p_status: 'packed', p_from: null, p_to: null, p_limit: 60 });
    if (error) { el.innerHTML = WARN(W.errText(error) || error.message); return; }
    el.innerHTML = (data || []).length ? data.map((o) => `<div class="card"><div><b>${esc(T('order'))} #${esc(String(o.order_no))}</b> · ${esc(W.locName(o.location_id))}</div>
      <button class="full" data-act="wpf_check" data-v="${esc(o.id)}">${esc(T('check'))}</button><div id="wpf_c_${esc(o.id)}"></div></div>`).join('') : `<p class="muted center pad">${esc(T('noPacked'))}</p>`;
    return;
  }
  const dup = D.tab === 'dup';
  const { data, error } = await sb.rpc(dup ? 'order_dup_flags_list' : 'online_order_flags_list', { p_loc: null, p_state: 'open' });
  if (error) { el.innerHTML = WARN(W.errText(error) || error.message); return; }
  const rows = data || [];
  el.innerHTML = (dup ? '' : `<p class="muted">${esc(T('flagHint'))}</p>`) + (rows.length ? rows.map((f) => `<div class="card"><div><b>${dup ? esc(T('orderA')) + ' #' + esc(String(f.order_no_a)) + ' / #' + esc(String(f.order_no_b)) : esc(T('order')) + ' #' + esc(String(f.order_no))}</b> · ${esc(W.locName(f.location_id))}</div>
    <div class="muted">${dup ? esc(T('day')) + ': ' + esc(W.day(f.day)) + ' · ' + esc(f.channel_a || '') + ' / ' + esc(f.channel_b || '') : esc(f.note || '') + ' · ' + esc(W.day(f.at))}</div>
    <button class="primary full" data-act="wpf_review" data-v="${esc(f.id)}">${esc(T('review'))}</button></div>`).join('') : `<p class="muted center pad">${esc(T('none'))}</p>`);
}
async function check(id) {
  const box = $('#wpf_c_' + id); if (!box) return;
  const { data, error } = await sb.rpc('online_order_stock_check', { p_id: id });
  if (error) { box.innerHTML = WARN(W.errText(error) || error.message); return; }
  if (!data.on) { box.innerHTML = `<div class="notice info">${esc(T('off'))}</div>`; return; }
  const sh = data.short || [];
  box.innerHTML = sh.length ? sh.map((s) => `<div class="notice warn"><b>${esc(s.name)}</b>: ${esc(T('need'))} ${esc(W.q(s.need))} · ${esc(T('have'))} ${esc(W.q(s.have))}${Number(s.reserved) > 0 ? ' · ' + esc(T('res')) + ' ' + esc(W.q(s.reserved)) : ''} · <b>${esc(T('shortBy'))} ${esc(W.q(s.short_by))}</b></div>`).join('') : `<div class="notice info">${esc(T('ok'))}</div>`;
}
function review(id) {
  openSheet(`<h2>${esc(T('review'))}</h2><label>${esc(T('why'))}</label><textarea id="wpf_why" rows="3"></textarea>
    <div class="row" style="margin-top:10px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="wpf_go" data-v="${esc(id)}">${esc(T('send'))}</button></div>`);
}
async function go(id) {
  const note = (($('#wpf_why') || {}).value || '').trim();
  if (note.length < 3) return toast(W.errText({ message: 'reason_required' }));
  const { error } = await sb.rpc(D.tab === 'dup' ? 'order_dup_flag_review' : 'online_order_flag_review', { p_id: Number(id), p_note: note });
  if (error) return W.err(error);
  closeSheet(); toast(T('saved')); return draw();
}
A.H = A.H || {};
Object.assign(A.H, {
  wpf_tab: (a) => { D.tab = a.dataset.v; return view(); },
  wpf_check: (a) => check(a.dataset.v), wpf_review: (a) => review(a.dataset.v), wpf_go: (a) => go(a.dataset.v),
});
B.packflags = { X, T, SW, D };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { packflags: view });
})();
