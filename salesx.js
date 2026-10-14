/* Islamia BOS · Sales extras (P3 slice b): online orders (#/onlineorders), forms 20-x <-> sales (#/saleforms, owner), benefit grants report (#/benefitsx), BI export (#/biexport).
   Server: supabase/phase61.sql. Reads: online_orders_list / online_order_get, unlinked_sale_forms, sale_form_links, benefits_report, bi_export_log_list.
   Writes (only through server functions): online_order_save / _status / _cancel / _deliver / _link_sale, sale_form_link / _unlink, benefit_type_save, employee_benefit_grant / _end, bi_export.
   Delivering an order makes ONE sale through the existing record_sale2; linking a form makes it a locked shadow copy of the sale; benefits are report only. Nothing is deleted. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
// only the columns the app role may read (phase61 column grant: sale_client stays server side) - select('*') would be refused
const OO_COLS = 'id,client_id,order_no,location_id,channel,customer_name,customer_mobile,address,lines,subtotal,discount,delivery_mode,delivery_by,delivery_date,delivery_charge,advance,advance_mode,advance_wallet,note,status,sale_id,cancel_reason,advance_fate,created_by,created_staff,created_at,updated_at';
const num = (v) => { const s = String(v == null ? '' : v).replace(/[০-৯]/g, (c) => '০১২৩৪৫৬৭৮৯'.indexOf(c)).replace(/,/g, '').trim(); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const money = (n) => '৳ ' + (Math.round(Number(n || 0) * 100) / 100).toLocaleString('en-US');
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const locs = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); return S.ctx.is_owner || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const locSel = (id, val) => `<select id="${id}">${locs().map((l) => `<option value="${l.id}" ${String(l.id) === String(val) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;

const X = {
  oTitle: L('অনলাইন অর্ডার', 'Online orders', 'Online অর্ডার'), fTitle: L('ফর্ম 20-১/২/৪ ↔ সেল', 'Forms 20-1 / 2 / 4 ↔ sales', 'Form 20-1/2/4 ↔ sale'),
  bTitle: L('কর্মচারীর সুবিধা (রিপোর্ট)', 'Employee benefits (report)', 'Employee সুবিধা (report)'), eTitle: L('BI এক্সপোর্ট', 'BI export', 'BI export'),
  place: L('জায়গা', 'Place', 'Place'), status: L('অবস্থা', 'Status', 'Status'), all: L('সব', 'All', 'All'), new_: L('নতুন অর্ডার', 'New order', 'নতুন Order'),
  confirm: L('নিশ্চিত', 'Confirm', 'Confirm'), pack: L('প্যাক হয়েছে', 'Packed', 'Packed'), deliver: L('ডেলিভারি দিন', 'Deliver', 'Deliver'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'),
  link: L('আগের সেলের সাথে জুড়ুন', 'Link an existing sale', 'আগের sale-এর সাথে জুড়ুন'), edit: L('বদলান', 'Edit', 'Edit'),
  s_new: L('নতুন', 'New', 'New'), s_confirmed: L('নিশ্চিত', 'Confirmed', 'Confirmed'), s_packed: L('প্যাক', 'Packed', 'Packed'), s_delivered: L('ডেলিভারি হয়েছে', 'Delivered', 'Delivered'), s_cancelled: L('ক্যান্সেল', 'Cancelled', 'Cancelled'),
  name: L('কাস্টমারের নাম', 'Customer name', 'Customer নাম'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), addr: L('ঠিকানা', 'Address', 'Address'), channel: L('মাধ্যম', 'Channel', 'Channel'),
  dmode: L('ডেলিভারি', 'Delivery', 'Delivery'), pickup: L('দোকান থেকে নেবে', 'Pick up', 'Pickup'), home: L('হোম ডেলিভারি', 'Home delivery', 'Home delivery'), courier: L('কুরিয়ার', 'Courier', 'Courier'),
  ddate: L('ডেলিভারির ডেট', 'Delivery date', 'Delivery date'), charge: L('ডেলিভারি চার্জ', 'Delivery charge', 'Delivery charge'), disc: L('ডিসকাউন্ট', 'Discount', 'Discount'),
  adv: L('অ্যাডভান্স', 'Advance', 'Advance'), advm: L('অ্যাডভান্স কীভাবে', 'Advance paid by', 'Advance কীভাবে'), note: L('নোট', 'Note', 'Note'), cash: L('ক্যাশ', 'Cash', 'Cash'), mobileP: L('মোবাইল ব্যাংকিং', 'Mobile money', 'Mobile money'), card: L('কার্ড', 'Card', 'Card'),
  items: L('আইটেম', 'Items', 'Items'), addLine: L('+ আইটেম যোগ', '+ Add item', '+ Item যোগ'), qty: L('Qty', 'Qty', 'Qty'), save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  total: L('টোটাল', 'Total', 'Total'), balance: L('বাকি', 'Balance', 'Balance'), collect: L('এখন কত টাকা নিলেন', 'Collected now', 'এখন কত নিলেন'), payBy: L('কীভাবে', 'By', 'By'),
  none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'), reason: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), fate: L('অ্যাডভান্সের কী হবে', 'What happens to the advance', 'Advance-এর কী হবে'),
  refund: L('ফেরত', 'Refund', 'Refund'), adjust: L('সমন্বয়', 'Adjust', 'Adjust'), income: L('ব্যবসার আয়ে', 'To income', 'Income-এ'), receipt: L('রসিদ', 'Receipt', 'Receipt'),
  pickSale: L('কোন সেল', 'Which sale', 'কোন sale'), done: L('হয়ে গেছে', 'Done', 'Done'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখুন', 'Show', 'Show'),
  unl: L('সেলের সাথে জোড়া হয়নি', 'Not linked to a sale', 'Sale-এর সাথে জোড়া হয়নি'), lnk: L('জোড়া আছে', 'Linked', 'Linked'), cand: L('সম্ভাব্য সেল', 'Candidate sales', 'Candidate sales'),
  doLink: L('জুড়ুন', 'Link', 'Link'), unlink: L('জোড়া খুলুন', 'Unlink', 'Unlink'), diff: L('অঙ্কের তফাত', 'Amount difference', 'Amount তফাত'), customer: L('কাস্টমার', 'Customer', 'Customer'),
  asof: L('যে তারিখের হিসাবে', 'As of', 'As of'), ben: L('সুবিধার তালিকা', 'Grants', 'Grants'), miss: L('পাওনা কিন্তু দেওয়া হয়নি', 'Eligible but not granted', 'Eligible, grant নেই'),
  endIt: L('সুবিধা শেষ করুন', 'End this grant', 'Grant শেষ করুন'), notyet: L('এখনো প্রাপ্য নয়', 'Not yet eligible', 'Not yet'), eligible: L('প্রাপ্য', 'Eligible', 'Eligible'), ended: L('শেষ', 'Ended', 'Ended'),
  paid: L('বেতনের সাথে', 'Paid in payroll', 'Payroll-এ'), val: L('মাসিক মূল্য', 'Value / month', 'Value / month'), reportOnly: L('শুধু রিপোর্ট — বেতনের হিসাব বদলায় না।', 'Report only - payroll maths is not changed.', 'শুধু report - payroll হিসাব বদলায় না।'),
  addGrant: L('সুবিধা দিন', 'Grant a benefit', 'Benefit দিন'), emp: L('কর্মচারী', 'Employee', 'Employee'), type: L('ধরন', 'Type', 'Type'), fromD: L('শুরুর ডেট', 'From date', 'From date'),
  dataset: L('কী এক্সপোর্ট', 'What to export', 'কী export'), format: L('ফরম্যাট', 'Format', 'Format'), limit: L('সর্বোচ্চ সারি', 'Max rows', 'Max rows'), run: L('এক্সপোর্ট', 'Export', 'Export'),
  dl: L('ফাইল নামান', 'Download file', 'File নামান'), rows: L('সারি', 'rows', 'rows'), cut: L('সীমায় কাটা হয়েছে — ডেট ছোট করুন বা সীমা বাড়ান', 'Cut at the row cap - narrow the dates', 'Row cap-এ কাটা - dates ছোট করুন'),
  costNote: L('কস্টের প্রাইস শুধু কস্ট-অনুমতি থাকলে আসে।', 'Cost prices appear only with the cost right.', 'Cost price শুধু cost-right থাকলে আসে।'), log: L('এক্সপোর্ট লগ', 'Export log', 'Export log'),
  d_sales: L('সেল', 'Sales', 'Sales'), d_sale_lines: L('সেলের লাইন', 'Sale lines', 'Sale lines'), d_purchases: L('ক্রয়', 'Purchases', 'Purchases'), d_stock_ledger: L('স্টক খাতা', 'Stock ledger', 'Stock ledger'), d_journal: L('জার্নাল', 'Journal', 'Journal'),
  noperm: L('এই কাজের অনুমতি নেই', 'You are not allowed to do this', 'এই কাজের permission নেই'),
};
const T = (k) => lab(X[k]);
const ERR = {
  module_off: L('এই সুবিধা এখনো চালু করা হয়নি (সুইচবোর্ডে চালু করুন)', 'This feature is switched off (owner: turn it on in the switch board)'),
  not_allowed: X.noperm, bad_status: L('এই অবস্থা থেকে এটা করা যায় না', 'Not possible from the current status'), order_closed: L('অর্ডার বন্ধ হয়ে গেছে', 'The order is already closed'),
  advance_fate_required: L('অ্যাডভান্সের কী হবে বাছুন', 'Choose what happens to the advance'), reason_required: X.reason, address_required: L('ঠিকানা দিন', 'Enter the address'),
  advance_over_total: L('অ্যাডভান্স মোটের চেয়ে বেশি', 'Advance is more than the total'), bad_mobile: L('মোবাইল নম্বর ঠিক নয়', 'Mobile number is not valid'), customer_name_required: L('নাম দিন', 'Enter the name'),
  no_lines: L('অন্তত একটি পণ্য দিন', 'Add at least one item'), bad_qty: L('পরিমাণ ঠিক নয়', 'Quantity is not valid'), overpaid: L('টাকা মোটের চেয়ে বেশি', 'Payment is more than the total'),
  sale_already_linked: L('এই বিক্রি আরেক অর্ডারে জোড়া', 'This sale is already linked'), sale_other_location: L('বিক্রিটি অন্য জায়গার', 'The sale belongs to another place'),
  entry_already_linked: L('ফর্মটি আগেই জোড়া', 'This form is already linked'), sale_already_has_form: L('এই বিক্রিতে এই ফর্ম আগেই আছে', 'This sale already has that form'), other_location: L('ফর্ম ও বিক্রি আলাদা জায়গার', 'Form and sale are at different places'),
  form_not_final: L('ফর্ম আগে জমা দিন', 'Submit the form first'), path_locked: L('মালিক এই পথ লক করেছেন', 'The owner has locked this path'), shadow_locked: L('জোড়া ফর্ম বদলানো যায় না', 'A linked form cannot be changed'),
  bad_date: L('তারিখ ঠিক নয় (সর্বোচ্চ ৩৬৬ দিন)', 'Dates are not valid (max 366 days)'), cost_not_allowed: L('ক্রয়ের ডেটায় খরচের দাম আছে — খরচ-অনুমতি লাগবে', 'Purchase data carries cost prices - the cost right is needed'),
  overlap: L('এই কর্মীর এই সুবিধা এই সময়ে আগেই আছে', 'The employee already holds this benefit in those dates'), grant_ended: L('এই সুবিধা শেষ হয়ে গেছে', 'This grant has ended'), note_needed: X.reason,
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).filter((x) => m.includes(x)).sort((a, b) => b.length - a.length)[0]; return k ? lab(ERR[k]) : m; };
const bad = (e) => { console.error(e); toast(eText(e) || 'error'); };
const rpc = async (fn, a) => { const r = await sb.rpc(fn, a); if (r.error) { bad(r.error); return null; } return r.data === null ? {} : r.data; };
const chips = (s) => `<span class="chip ${s === 'delivered' ? 'ok' : s === 'cancelled' ? 'warn' : ''}">${esc(T('s_' + s))}</span>`;

/* ============ #/onlineorders ============ */
const O = { loc: null, status: '', rows: [], items: [], lines: [], client: rid(), edit: null };
const CH = [['facebook', 'Facebook'], ['instagram', 'Instagram'], ['whatsapp', 'WhatsApp'], ['phone', L('ফোন', 'Phone')], ['website', 'Website'], ['foodapp', L('ফুড অ্যাপ', 'Food app')], ['other', L('অন্য', 'Other')]];
const nameOf = (x) => (typeof x === 'string' ? x : lab(x));
async function loadOrders() {
  if (B.loadStatic) await B.loadStatic();
  if (!O.loc) O.loc = (locs()[0] || {}).id;
  const r = await sb.rpc('online_orders_list', { p_loc: O.loc, p_status: O.status || null, p_from: null, p_to: null, p_limit: 100 });
  if (r.error) throw r.error; O.rows = r.data || [];
}
function drawOrders() {
  const el = $('#sx_body'); if (!el) return;
  const st = ['', 'new', 'confirmed', 'packed', 'delivered', 'cancelled'];
  el.innerHTML = `<div class="card stack"><div class="row wrap"><label>${esc(T('place'))} ${locSel('sx_loc', O.loc)}</label>
      <label>${esc(T('status'))} <select id="sx_st">${st.map((s) => `<option value="${s}" ${O.status === s ? 'selected' : ''}>${esc(s ? T('s_' + s) : T('all'))}</option>`).join('')}</select></label>
      <button type="button" class="btn primary" data-act="sx_new">${esc(T('new_'))}</button></div></div>
    ${O.rows.length ? O.rows.map(orderCard).join('') : `<p class="muted">${esc(T('none'))}</p>`}`;
}
function orderCard(o) {
  const a = (act, k, cls = '') => `<button type="button" class="mini ${cls}" data-act="${act}" data-id="${esc(o.id)}">${esc(T(k))}</button>`;
  const acts = o.status === 'new' ? a('sx_edit', 'edit') + a('sx_st_confirmed', 'confirm') + a('sx_cancel', 'cancel') + a('sx_linksale', 'link')
    : o.status === 'confirmed' ? a('sx_edit', 'edit') + a('sx_st_packed', 'pack') + a('sx_cancel', 'cancel') + a('sx_linksale', 'link')
    : o.status === 'packed' ? a('sx_deliver', 'deliver', 'primary') + a('sx_cancel', 'cancel') + a('sx_linksale', 'link') : '';
  return `<div class="card stack" data-order="${esc(o.id)}"><div class="row between"><b>#${esc(o.order_no)} · ${esc(o.customer_name)}</b>${chips(o.status)}</div>
    <div class="muted" style="font-size:.85rem">${esc(o.channel)} · ${esc(o.customer_mobile)} · ${esc(o.delivery_mode)}${o.delivery_date ? ' · ' + esc(o.delivery_date) : ''}</div>
    <div class="row between"><span>${esc(T('total'))} ${esc(money(Number(o.subtotal) - Number(o.discount) + Number(o.delivery_charge)))}${Number(o.advance) ? ' · ' + esc(T('adv')) + ' ' + esc(money(o.advance)) : ''}</span><b>${esc(T('balance'))} ${esc(money(o.balance))}</b></div>
    ${acts ? `<div class="row wrap">${acts}</div>` : ''}</div>`;
}
async function ensureItems() {
  if (O.items.length) return;
  const r = await sb.from('items').select('id,code,name_bn,name_en,sell_price').eq('is_active', true).order('code').limit(800);
  O.items = (r.data || []).filter((i) => Number(i.sell_price) > 0);
}
const itemLabel = (i) => `${i.code} · ${lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn })} · ${money(i.sell_price)}`;
function lineRow(l, i) {
  return `<div class="row wrap" data-line="${i}"><select data-sxl="item" data-i="${i}" style="flex:1;min-width:10rem">${O.items.map((it) => `<option value="${esc(it.id)}" ${it.id === l.item_id ? 'selected' : ''}>${esc(itemLabel(it))}</option>`).join('')}</select>
    <input data-sxl="qty" data-i="${i}" inputmode="decimal" value="${esc(l.qty)}" style="max-width:5rem" aria-label="${esc(T('qty'))}"><button type="button" class="mini" data-act="sx_delline" data-i="${i}" aria-label="x">✕</button></div>`;
}
function orderForm(o) {
  const v = o || {};
  return `<div class="stack" id="sx_form"><h3>${esc(o ? '#' + o.order_no : T('new_'))}</h3>
    <label>${esc(T('name'))}<input id="sx_n" maxlength="80" value="${esc(v.customer_name || '')}"></label>
    <label>${esc(T('mobile'))}<input id="sx_m" inputmode="tel" maxlength="20" value="${esc(v.customer_mobile || '')}"></label>
    <label>${esc(T('channel'))}<select id="sx_ch">${CH.map((c) => `<option value="${c[0]}" ${v.channel === c[0] ? 'selected' : ''}>${esc(nameOf(c[1]))}</option>`).join('')}</select></label>
    <label>${esc(T('dmode'))}<select id="sx_dm">${[['pickup', 'pickup'], ['home', 'home'], ['courier', 'courier']].map((c) => `<option value="${c[0]}" ${v.delivery_mode === c[0] ? 'selected' : ''}>${esc(T(c[1]))}</option>`).join('')}</select></label>
    <label>${esc(T('addr'))}<input id="sx_a" maxlength="300" value="${esc(v.address || '')}"></label>
    <label>${esc(T('ddate'))}<input id="sx_dd" type="date" value="${esc(v.delivery_date || '')}"></label>
    <b>${esc(T('items'))}</b><div id="sx_lines">${O.lines.map(lineRow).join('')}</div><button type="button" class="mini" data-act="sx_addline">${esc(T('addLine'))}</button>
    <div class="row wrap"><label>${esc(T('charge'))}<input id="sx_c" inputmode="decimal" value="${esc(v.delivery_charge || 0)}" style="max-width:6rem"></label>
      <label>${esc(T('disc'))}<input id="sx_d" inputmode="decimal" value="${esc(v.discount || 0)}" style="max-width:6rem"></label>
      <label>${esc(T('adv'))}<input id="sx_ad" inputmode="decimal" value="${esc(v.advance || 0)}" style="max-width:6rem"></label>
      <label>${esc(T('advm'))}<select id="sx_am">${[['cash', 'cash'], ['mobile', 'mobileP'], ['card', 'card']].map((c) => `<option value="${c[0]}" ${v.advance_mode === c[0] ? 'selected' : ''}>${esc(T(c[1]))}</option>`).join('')}</select></label></div>
    <label>${esc(T('note'))}<input id="sx_nt" maxlength="300" value="${esc(v.note || '')}"></label>
    <button type="button" class="btn primary" data-act="sx_save">${esc(T('save'))}</button></div>`;
}
async function openForm(id) {
  await ensureItems();
  O.edit = null; O.lines = [];
  if (id) { const r = await sb.from('online_orders').select(OO_COLS).eq('id', id).maybeSingle(); O.edit = r.data; O.lines = ((O.edit && O.edit.lines) || []).map((l) => ({ item_id: l.item_id, qty: l.qty })); }
  if (!O.lines.length && O.items[0]) O.lines = [{ item_id: O.items[0].id, qty: 1 }];
  O.client = rid(); openSheet(orderForm(O.edit));
}
const refreshLines = () => { const el = $('#sx_lines'); if (el) el.innerHTML = O.lines.map(lineRow).join(''); };
const refreshOrders = async () => { await loadOrders(); drawOrders(); };
Object.assign(H, {
  sx_new: () => openForm(null).catch(fail),
  sx_edit: (a) => openForm(a.dataset.id).catch(fail),
  sx_addline: () => { O.lines.push({ item_id: (O.items[0] || {}).id, qty: 1 }); refreshLines(); },
  sx_delline: (a) => { if (O.lines.length > 1) { O.lines.splice(Number(a.dataset.i), 1); refreshLines(); } },
  sx_save: async () => {
    const lines = O.lines.map((l) => ({ item_id: l.item_id, qty: num(l.qty) })); if (lines.some((l) => !(l.qty > 0))) return toast(lab(ERR.bad_qty));
    const adv = num($('#sx_ad').value) || 0;
    const r = await rpc('online_order_save', { p_id: O.edit ? O.edit.id : null, p_client: O.edit ? null : O.client, p_loc: O.edit ? O.edit.location_id : O.loc, p_channel: $('#sx_ch').value, p_name: $('#sx_n').value, p_mobile: $('#sx_m').value,
      p_address: $('#sx_a').value || null, p_lines: lines, p_delivery_mode: $('#sx_dm').value, p_delivery_by: null, p_delivery_date: $('#sx_dd').value || null, p_charge: num($('#sx_c').value) || 0, p_discount: num($('#sx_d').value) || 0,
      p_advance: adv, p_adv_mode: adv > 0 ? $('#sx_am').value : null, p_adv_wallet: null, p_note: $('#sx_nt').value || null });
    if (!r) return; closeSheet(); toast(T('saved')); await refreshOrders();
  },
  sx_st_confirmed: async (a) => { if (await rpc('online_order_status', { p_id: a.dataset.id, p_to: 'confirmed', p_note: null })) await refreshOrders(); },
  sx_st_packed: async (a) => { if (await rpc('online_order_status', { p_id: a.dataset.id, p_to: 'packed', p_note: null })) await refreshOrders(); },
  sx_cancel: (a) => {
    const o = O.rows.find((x) => x.id === a.dataset.id);
    openSheet(`<div class="stack"><h3>${esc(T('cancel'))} #${esc(o.order_no)}</h3><label>${esc(T('reason'))}<input id="sx_cr" maxlength="300"></label>
      ${Number(o.advance) > 0 ? `<label>${esc(T('fate'))} (${esc(money(o.advance))})<select id="sx_cf"><option value="refund">${esc(T('refund'))}</option><option value="adjust">${esc(T('adjust'))}</option><option value="income">${esc(T('income'))}</option></select></label>` : ''}
      <button type="button" class="btn primary" data-act="sx_cancel_go" data-id="${esc(o.id)}">${esc(T('cancel'))}</button></div>`);
  },
  sx_cancel_go: async (a) => {
    const r = await rpc('online_order_cancel', { p_id: a.dataset.id, p_reason: $('#sx_cr').value, p_advance_fate: $('#sx_cf') ? $('#sx_cf').value : 'none' });
    if (r) { closeSheet(); await refreshOrders(); }
  },
  sx_deliver: (a) => {
    const o = O.rows.find((x) => x.id === a.dataset.id);
    openSheet(`<div class="stack"><h3>${esc(T('deliver'))} #${esc(o.order_no)}</h3><b>${esc(T('balance'))} ${esc(money(o.balance))}</b>
      <label>${esc(T('collect'))}<input id="sx_pa" inputmode="decimal" value="${esc(o.balance)}"></label>
      <label>${esc(T('payBy'))}<select id="sx_pm"><option value="cash">${esc(T('cash'))}</option><option value="mobile">${esc(T('mobileP'))}</option><option value="card">${esc(T('card'))}</option></select></label>
      <button type="button" class="btn primary" data-act="sx_deliver_go" data-id="${esc(o.id)}">${esc(T('deliver'))}</button></div>`);
  },
  sx_deliver_go: async (a) => {
    const amt = num($('#sx_pa').value) || 0;
    const r = await rpc('online_order_deliver', { p_id: a.dataset.id, p_payments: amt > 0 ? [{ mode: $('#sx_pm').value, amount: amt }] : [] });
    if (r) { closeSheet(); toast(T('done') + (r.receipt ? ' · ' + T('receipt') + ' ' + r.receipt : '')); await refreshOrders(); }
  },
  sx_linksale: async (a) => {
    const o = O.rows.find((x) => x.id === a.dataset.id);
    const r = await sb.from('sales').select('id,receipt,total,sale_date').eq('location_id', o.location_id).eq('status', 'done').order('sold_at', { ascending: false }).limit(40);
    openSheet(`<div class="stack"><h3>${esc(T('link'))} #${esc(o.order_no)}</h3><label>${esc(T('pickSale'))}<select id="sx_ls">${(r.data || []).map((s) => `<option value="${esc(s.id)}">#${esc(s.receipt)} · ${esc(s.sale_date)} · ${esc(money(s.total))}</option>`).join('')}</select></label>
      <button type="button" class="btn primary" data-act="sx_link_go" data-id="${esc(o.id)}">${esc(T('link'))}</button></div>`);
  },
  sx_link_go: async (a) => { const r = await rpc('online_order_link_sale', { p_id: a.dataset.id, p_sale: $('#sx_ls').value, p_note: null }); if (r) { closeSheet(); await refreshOrders(); } },
});
document.addEventListener('change', (e) => {
  const t = e.target;
  if (t.id === 'sx_loc') { O.loc = Number(t.value); refreshOrders().catch(fail); }
  if (t.id === 'sx_st') { O.status = t.value; refreshOrders().catch(fail); }
  if (t.dataset && t.dataset.sxl) { const l = O.lines[Number(t.dataset.i)]; if (l) { if (t.dataset.sxl === 'item') l.item_id = t.value; else l.qty = t.value; } }
});
document.addEventListener('input', (e) => { const t = e.target; if (t.dataset && t.dataset.sxl === 'qty') { const l = O.lines[Number(t.dataset.i)]; if (l) l.qty = t.value; } });
async function viewOrders() {
  shell(T('oTitle'), '<div id="sx_body"><p class="muted">…</p></div>', true);
  try { await loadOrders(); drawOrders(); } catch (e) { bad(e); }
}

/* ============ #/saleforms (owner) ============ */
const F = { from: null, to: null, loc: null, rep: [], linked: [], sales: {} };
async function loadForms() {
  if (B.loadStatic) await B.loadStatic();
  F.to = F.to || today(); F.from = F.from || addDays(F.to, -7); if (!F.loc) F.loc = (locs()[0] || {}).id;
  const r = await sb.rpc('unlinked_sale_forms', { p_from: F.from, p_to: F.to, p_loc: F.loc, p_limit: 200 }); if (r.error) throw r.error; F.rep = r.data || [];
  const l = await sb.from('sale_form_links').select('id,sale_id,entry_id,form_code,amount_diff,linked_at').eq('location_id', F.loc).eq('state', 'active').order('id', { ascending: false }).limit(40); F.linked = l.data || [];
  const ids = [...new Set(F.rep.flatMap((x) => x.candidate_sales || []).concat(F.linked.map((x) => x.sale_id)))];
  F.sales = {};
  if (ids.length) { const s = await sb.from('sales').select('id,receipt,total,sale_date').in('id', ids); (s.data || []).forEach((x) => { F.sales[x.id] = x; }); }
}
const saleTxt = (id) => { const s = F.sales[id]; return s ? `#${s.receipt} · ${s.sale_date} · ${money(s.total)}` : String(id).slice(0, 8); };
function drawForms() {
  const el = $('#sf_body'); if (!el) return;
  el.innerHTML = `<div class="card stack"><div class="row wrap"><label>${esc(T('place'))} ${locSel('sf_loc', F.loc)}</label><label>${esc(T('from'))} <input type="date" id="sf_from" value="${esc(F.from)}"></label>
      <label>${esc(T('to'))} <input type="date" id="sf_to" value="${esc(F.to)}"></label><button type="button" class="btn" data-act="sf_run">${esc(T('show'))}</button></div></div>
    <h3>${esc(T('unl'))} (${F.rep.length})</h3>
    ${F.rep.length ? F.rep.map((x) => `<div class="card stack" data-entry="${esc(x.entry_id)}"><div class="row between"><b>${esc(x.form_code)} #${esc(x.serial)}</b><span class="muted">${esc(x.entry_date)}</span></div>
      <div class="muted">${esc(T('customer'))}: ${esc(x.customer || '-')}${x.form_total != null ? ' · ' + esc(T('total')) + ' ' + esc(money(x.form_total)) : ''}</div>
      ${(x.candidate_sales || []).length ? `<div class="muted">${esc(T('cand'))}</div>` + x.candidate_sales.map((sid) => `<div class="row between"><span>${esc(saleTxt(sid))}</span><button type="button" class="mini" data-act="sf_link" data-e="${esc(x.entry_id)}" data-s="${esc(sid)}">${esc(T('doLink'))}</button></div>`).join('') : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    <h3>${esc(T('lnk'))} (${F.linked.length})</h3>
    ${F.linked.map((l) => `<div class="card row between"><span>${esc(l.form_code)} ↔ ${esc(saleTxt(l.sale_id))}${l.amount_diff != null && Number(l.amount_diff) !== 0 ? ` · <b>${esc(T('diff'))} ${esc(money(l.amount_diff))}</b>` : ''}</span>
      <button type="button" class="mini" data-act="sf_unlink" data-id="${esc(l.id)}">${esc(T('unlink'))}</button></div>`).join('')}`;
}
const refreshForms = async () => { await loadForms(); drawForms(); };
Object.assign(H, {
  sf_run: async () => { F.from = $('#sf_from').value; F.to = $('#sf_to').value; F.loc = Number($('#sf_loc').value); try { await refreshForms(); } catch (e) { bad(e); } },
  sf_link: async (a) => { const r = await rpc('sale_form_link', { p_entry: a.dataset.e, p_sale: a.dataset.s, p_note: null }); if (r) { toast(T('saved') + (r.amount_diff ? ' · ' + T('diff') + ' ' + money(r.amount_diff) : '')); await refreshForms().catch(bad); } },
  sf_unlink: async (a) => { const why = window.prompt(T('reason')); if (!why) return; const r = await rpc('sale_form_unlink', { p_link: Number(a.dataset.id), p_note: why }); if (r) await refreshForms().catch(bad); },
});
async function viewForms() {
  shell(T('fTitle'), '<div id="sf_body"><p class="muted">…</p></div>', true);
  try { await loadForms(); drawForms(); } catch (e) { bad(e); }
}

/* ============ #/benefitsx ============ */
const BN = { asof: null, loc: null, rep: null, emps: [], types: [] };
async function loadBen() {
  if (B.loadStatic) await B.loadStatic();
  BN.asof = BN.asof || today();
  const r = await sb.rpc('benefits_report', { p_as_of: BN.asof, p_loc: BN.loc || null }); if (r.error) throw r.error; BN.rep = r.data;
  const t = await sb.from('benefit_types').select('code,name_bn,name_en,paid_in_payroll,eligible_after_days,default_for_all,active').eq('active', true).order('sort'); BN.types = t.data || [];
}
function drawBen() {
  const el = $('#bx_body'); if (!el) return; const r = BN.rep || { grants: [], missing: [] };
  const tn = (c) => { const t = BN.types.find((x) => x.code === c); return t ? lab({ bn: t.name_bn, mix: t.name_bn, en: t.name_en || t.name_bn }) : c; };
  el.innerHTML = `<p class="muted">${esc(T('reportOnly'))}</p>
    <div class="card stack"><div class="row wrap"><label>${esc(T('place'))} <select id="bx_loc"><option value="">${esc(T('all'))}</option>${locs().map((l) => `<option value="${l.id}" ${String(BN.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>
      <label>${esc(T('asof'))} <input type="date" id="bx_asof" value="${esc(BN.asof)}"></label><button type="button" class="btn" data-act="bx_run">${esc(T('show'))}</button>
      <button type="button" class="btn primary" data-act="bx_add">${esc(T('addGrant'))}</button></div></div>
    <h3>${esc(T('ben'))} (${r.grants.length})</h3>
    ${r.grants.length ? r.grants.map((g) => `<div class="card stack"><div class="row between"><b>${esc(g.employee_name)} · ${esc(tn(g.type_code))}</b><span class="chip ${g.state === 'eligible' ? 'ok' : g.state === 'ended' ? '' : 'warn'}">${esc(T(g.state === 'not_yet' ? 'notyet' : g.state))}</span></div>
      <div class="muted" style="font-size:.85rem">${esc(g.from_date)} → ${esc(g.to_date || '…')} · ${esc(T('eligible'))} ${esc(g.eligible_from)}${g.paid_in_payroll ? ' · ' + esc(T('paid')) : ''}${g.value_per_month != null ? ' · ' + esc(T('val')) + ' ' + esc(money(g.value_per_month)) : ''}</div>
      ${g.state !== 'ended' ? `<button type="button" class="mini" data-act="bx_end" data-id="${esc(g.id)}">${esc(T('endIt'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    <h3>${esc(T('miss'))} (${r.missing.length})</h3>
    ${r.missing.length ? r.missing.map((m) => `<div class="card row between"><span>${esc(m.employee_name)} · ${esc(tn(m.type_code))}</span><span class="muted">${esc(m.eligible_from)}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}`;
}
Object.assign(H, {
  bx_run: async () => { BN.asof = $('#bx_asof').value || today(); BN.loc = $('#bx_loc').value ? Number($('#bx_loc').value) : null; try { await loadBen(); drawBen(); } catch (e) { bad(e); } },
  bx_add: async () => {
    const e = await sb.from('employees').select('id,full_name_bn,employee_no').eq('status', 'active').order('full_name_bn').limit(500); BN.emps = e.data || [];
    openSheet(`<div class="stack"><h3>${esc(T('addGrant'))}</h3><label>${esc(T('emp'))}<select id="bx_e">${BN.emps.map((x) => `<option value="${esc(x.id)}">${esc(x.full_name_bn)}${x.employee_no ? ' · ' + esc(x.employee_no) : ''}</option>`).join('')}</select></label>
      <label>${esc(T('type'))}<select id="bx_t">${BN.types.map((t) => `<option value="${esc(t.code)}">${esc(lab({ bn: t.name_bn, mix: t.name_bn, en: t.name_en || t.name_bn }))}</option>`).join('')}</select></label>
      <label>${esc(T('fromD'))}<input type="date" id="bx_f" value="${esc(today())}"></label><label>${esc(T('val'))}<input id="bx_v" inputmode="decimal" placeholder="-"></label>
      <label>${esc(T('note'))}<input id="bx_n" maxlength="300"></label><button type="button" class="btn primary" data-act="bx_go">${esc(T('save'))}</button></div>`);
  },
  bx_go: async () => {
    const v = num($('#bx_v').value);
    const r = await rpc('employee_benefit_grant', { p_id: null, p_client: rid(), p_emp: $('#bx_e').value, p_type: $('#bx_t').value, p_from: $('#bx_f').value, p_to: null, p_value: Number.isNaN(v) ? null : v, p_paid: null, p_note: $('#bx_n').value || null });
    if (r) { closeSheet(); toast(T('saved')); await loadBen(); drawBen(); }
  },
  bx_end: async (a) => { const r = await rpc('employee_benefit_grant_end', { p_id: Number(a.dataset.id), p_to: today(), p_note: null }); if (r) { await loadBen(); drawBen(); } },
});
async function viewBen() {
  shell(T('bTitle'), '<div id="bx_body"><p class="muted">…</p></div>', true);
  try { await loadBen(); drawBen(); } catch (e) { bad(e); }
}

/* ============ #/biexport ============ */
const EX = { ds: 'sales', from: null, to: null, loc: null, fmt: 'csv', limit: '', res: null, log: [] };
const DS = ['sales', 'sale_lines', 'purchases', 'stock_ledger', 'journal'];
function drawExport() {
  const el = $('#ex_body'); if (!el) return; const r = EX.res;
  el.innerHTML = `<div class="card stack"><label>${esc(T('dataset'))}<select id="ex_ds">${DS.map((d) => `<option value="${d}" ${EX.ds === d ? 'selected' : ''}>${esc(T('d_' + d))}</option>`).join('')}</select></label>
    <div class="row wrap"><label>${esc(T('from'))} <input type="date" id="ex_from" value="${esc(EX.from)}"></label><label>${esc(T('to'))} <input type="date" id="ex_to" value="${esc(EX.to)}"></label></div>
    <div class="row wrap"><label>${esc(T('place'))} <select id="ex_loc"><option value="">${esc(T('all'))}</option>${locs().map((l) => `<option value="${l.id}" ${String(EX.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>
      <label>${esc(T('format'))} <select id="ex_fmt"><option value="csv" ${EX.fmt === 'csv' ? 'selected' : ''}>CSV</option><option value="json" ${EX.fmt === 'json' ? 'selected' : ''}>JSON</option></select></label>
      <label>${esc(T('limit'))} <input id="ex_lim" inputmode="numeric" value="${esc(EX.limit)}" style="max-width:6rem"></label></div>
    <div class="muted" style="font-size:.85rem">${esc(T('costNote'))}</div><button type="button" class="btn primary" data-act="ex_run">${esc(T('run'))}</button></div>
    ${r ? `<div class="card stack"><b>${esc(T('d_' + r.dataset))}: ${esc(r.row_count)} ${esc(T('rows'))}</b>${r.truncated ? `<div class="chip warn">${esc(T('cut'))}</div>` : ''}
      <button type="button" class="btn" data-act="ex_dl">${esc(T('dl'))}</button></div>` : ''}
    ${EX.log.length ? `<h3>${esc(T('log'))}</h3>${EX.log.slice(0, 15).map((l) => `<div class="muted" style="font-size:.8rem">${esc(String(l.at).slice(0, 16).replace('T', ' '))} · ${esc(l.dataset)} · ${esc(l.row_count)}${l.truncated ? ' ✂' : ''} · ${esc(l.format)}</div>`).join('')}` : ''}`;
}
Object.assign(H, {
  ex_run: async () => {
    EX.ds = $('#ex_ds').value; EX.from = $('#ex_from').value; EX.to = $('#ex_to').value; EX.loc = $('#ex_loc').value ? Number($('#ex_loc').value) : null; EX.fmt = $('#ex_fmt').value; EX.limit = $('#ex_lim').value;
    const lim = num(EX.limit);
    const r = await rpc('bi_export', { p_dataset: EX.ds, p_from: EX.from, p_to: EX.to, p_loc: EX.loc, p_format: EX.fmt, p_limit: lim > 0 ? Math.floor(lim) : null });
    if (!r) return; EX.res = r;
    if (S.ctx.is_owner) { const l = await sb.rpc('bi_export_log_list', { p_limit: 15 }); if (!l.error) EX.log = l.data || []; }
    drawExport();
  },
  ex_dl: () => {
    const r = EX.res; if (!r) return;
    const body = r.format === 'csv' ? '﻿' + r.csv : JSON.stringify(r.rows, null, 1);
    const url = URL.createObjectURL(new Blob([body], { type: r.format === 'csv' ? 'text/csv;charset=utf-8' : 'application/json' }));
    const a = document.createElement('a'); a.href = url; a.download = `${r.dataset}_${EX.from}_${EX.to}.${r.format}`; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000);
  },
});
async function viewExport() {
  if (B.loadStatic) await B.loadStatic();
  EX.to = EX.to || today(); EX.from = EX.from || addDays(EX.to, -30); EX.res = null;
  shell(T('eTitle'), '<div id="ex_body"></div>', true); drawExport();
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { onlineorders: viewOrders, saleforms: viewForms, benefitsx: viewBen, biexport: viewExport });
})();
