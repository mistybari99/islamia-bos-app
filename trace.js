/* Islamia BOS · Trace a batch (#/trace) and recall cases (#/recall).
   Server: supabase/phase430.sql (receipt lots, stock_unbatched), phase431.sql (trace_batch, trace_batch_find, recall_* , recall_affected), phase436.sql (rb3_log_export).
   Everything shown is read from records that already exist; nothing here moves stock or money. A recall case only RECORDS what was done (hold, return, write off with the existing screens).
   Missing data is said ("data not captured: ..."), never shown as 0. Paper form code of the recall case: to be given by owner.
   CSV: the same export right as the other reports (owner or export_data); the export is written to the audit log first. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, nm, H, S } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const q4 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const d10 = (v) => (v ? String(v).slice(0, 10) : '');
const X = {
  title: L('ব্যাচ ট্রেস', 'Trace a batch', 'Batch trace'), rtitle: L('রিকল কেস', 'Recall cases', 'Recall case'),
  intro: L('কাঁচামালের লট থেকে তৈরি মাল, কোন শাখা ও কোন ক্রেতার কাছে গেছে — যা খাতায় লেখা আছে শুধু তাই দেখানো হয়। কিছু সরে না।', 'From a raw-material lot to the finished batch, the outlets and the customers it reached — only what is already recorded is shown. Nothing is moved.', 'Raw lot থেকে finished batch, কোন outlet ও customer এর কাছে গেছে — যা record আছে শুধু তাই। কিছু সরে না।'),
  q: L('লট নম্বর বা আইটেম', 'Lot number or item', 'Lot no বা item'), place: L('জায়গা', 'Place', 'Place'), all: L('সব', 'All', 'All'), withEmpty: L('যে ব্যাচে মাল নেই সেটিও', 'Include batches with no stock left', 'যে batch এ মাল নেই সেটাও'),
  find: L('খুঁজুন', 'Find', 'Find'), none: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  lot: L('লট', 'Lot', 'Lot'), batch: L('ব্যাচ', 'Batch', 'Batch'), expiry: L('মেয়াদ', 'Expiry', 'Expiry'), made: L('তৈরি / এসেছে', 'Made / received', 'Made / received'),
  qmade: L('মোট', 'Total', 'Total'), left: L('এখন আছে', 'Left now', 'Left now'), nc: L('তথ্য লেখা হয়নি', 'data not captured', 'data লেখা হয়নি'),
  fSupplier: L('সাপ্লায়ার', 'supplier', 'supplier'), fLot: L('লট নম্বর', 'lot number', 'lot no'), fExpiry: L('মেয়াদ', 'expiry date', 'expiry date'), fOrigin: L('উৎস', 'origin', 'origin'), fCustomer: L('ক্রেতার নাম', 'customer name', 'customer name'),
  oReceipt: L('সাপ্লায়ার থেকে', 'From supplier', 'Supplier থেকে'), oBill: L('বিল', 'bill', 'bill'), oProd: L('কারখানায় তৈরি', 'Made in production', 'Production এ তৈরি'), oTransfer: L('অন্য জায়গা থেকে এসেছে', 'Transferred from another place', 'অন্য place থেকে এসেছে'),
  oGrn: L('মাল গ্রহণ ফর্ম (GRN) থেকে', 'From a goods received form (GRN)', 'GRN form থেকে'), oUnknown: L('উৎস লেখা নেই', 'origin not captured', 'origin লেখা নেই'),
  back: L('কী দিয়ে তৈরি', 'Made from', 'কী দিয়ে তৈরি'), fwd: L('কোথায় গেছে', 'Where it went', 'কোথায় গেছে'), used: L('ব্যবহার', 'used', 'used'),
  unbatchedIn: L('এই উপকরণ কোন লটের তা লেখা নেই (ব্যাচ ছাড়া মাল)', 'Ingredient not tied to a lot (unbatched stock)', 'Ingredient কোন lot এর তা লেখা নেই (unbatched)'),
  byPlace: L('জায়গা অনুযায়ী', 'By place', 'Place অনুযায়ী'), onHand: L('আছে', 'On hand', 'On hand'), sold: L('বিক্রি', 'Sold', 'Sold'), transit: L('পথে', 'In transit', 'Transit'),
  reached: L('যেসব ব্যাচে পৌঁছেছে', 'Batches reached', 'Batch যেখানে পৌঁছেছে'), rel_start: L('শুরু', 'start', 'start'), rel_made_from: L('এর থেকে তৈরি', 'made from it', 'এর থেকে তৈরি'), rel_transferred: L('হস্তান্তরে গেছে', 'transferred', 'transferred'), date: L('তারিখ', 'Date', 'Date'),
  sales: L('বিক্রি', 'Sales', 'Sales'), receipt: L('রসিদ', 'Receipt', 'Receipt'), noCust: L('ক্রেতার নাম লেখা নেই', 'no customer name recorded', 'customer name লেখা নেই'), named: L('নাম লেখা ক্রেতা', 'Named customers', 'Named customers'),
  noName: L('নাম ছাড়া বিক্রি', 'Sales without a name', 'Name ছাড়া sales'), transfers: L('হস্তান্তর', 'Transfers', 'Transfers'), sent: L('পাঠানো', 'Sent', 'Sent'), recv: L('গ্রহণ', 'Received', 'Received'),
  stSent: L('পথে', 'in transit', 'in transit'), stReceived: L('পৌঁছেছে', 'received', 'received'), takenOut: L('অন্যভাবে বেরিয়েছে', 'Taken out otherwise', 'অন্যভাবে বেরিয়েছে'),
  tk_wastage: L('নষ্ট বাবদ', 'wastage', 'wastage'), tk_purchase_return: L('সাপ্লায়ারকে ফেরত', 'returned to supplier', 'supplier কে ফেরত'), tk_count_adjust: L('গণনার সমন্বয়', 'count adjustment', 'count adjustment'),
  manual: L('হাতে ইস্যু (কোন উৎপাদনে গেছে তা লেখা নেই)', 'Issued by hand (where it went is not recorded)', 'হাতে issue (কোথায় গেছে লেখা নেই)'),
  unb: L('একই আইটেমের ব্যাচ-ছাড়া মাল — এই লট থেকে মুক্ত কি না প্রমাণ করা যায় না', 'Same items NOT in any batch — cannot be shown free of this lot', 'একই item এর unbatched মাল — এই lot থেকে মুক্ত কি না প্রমাণ হয় না'),
  unlot: L('একই সাপ্লায়ারের একই আইটেমের যে রসিদে লট লেখা নেই', 'Receipts of the same item and supplier with NO lot recorded', 'একই supplier ও item এর যে receipt এ lot লেখা নেই'),
  hidden: L('আপনার দেখার বাইরের জায়গা আছে — সেগুলো এখানে নেই', 'Some places are outside what you may see — they are not included', 'আপনার দেখার বাইরের place আছে — এখানে নেই'),
  trunc: L('তালিকা ছোট করা হয়েছে', 'The list is cut short', 'List ছোট করা হয়েছে'), csv: L('CSV', 'CSV', 'CSV'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export এর permission নেই'), expDone: L('ফাইল নামানো হয়েছে', 'File downloaded', 'File নামানো হয়েছে'),
  startRecall: L('এই ব্যাচ নিয়ে রিকল কেস খুলুন', 'Open a recall case with this batch', 'এই batch নিয়ে recall case খুলুন'), trace: L('ট্রেস', 'Trace', 'Trace'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  paperCode: L('কাগজের ফর্মের কোড: মালিক দেবেন', 'paper form code: to be given by owner', 'paper form code: owner দেবেন'),
  // recall
  newCase: L('নতুন রিকল কেস', 'New recall case', 'নতুন recall case'), cTitle: L('শিরোনাম', 'Title', 'Title'), cReason: L('কেন (কারণ)', 'Why (reason)', 'কেন (reason)'), cHazard: L('ঝুঁকি (ঐচ্ছিক)', 'Hazard (optional)', 'Hazard (optional)'),
  openCases: L('খোলা কেস', 'Open', 'Open'), closedCases: L('বন্ধ কেস', 'Closed', 'Closed'), caseNo: L('কেস নং', 'Case no.', 'Case no.'), batches: L('রিকলে থাকা ব্যাচ', 'Batches under recall', 'Recall এ batch'),
  addBatch: L('ব্যাচ যোগ করুন', 'Add a batch', 'Batch যোগ করুন'), mark: L('কাজ লিখুন', 'Record action', 'Action লিখুন'), closeCase: L('কেস বন্ধ করুন', 'Close the case', 'Case বন্ধ করুন'), note: L('নোট', 'Note', 'Note'),
  save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('থাক', 'Cancel', 'Cancel'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), affected: L('প্রভাবিত মাল (রিপোর্ট)', 'Affected stock (report)', 'Affected stock (report)'),
  st_to_do: L('করা বাকি', 'to do', 'to do'), st_removed_from_shelf: L('তাক থেকে সরানো', 'removed from shelf', 'shelf থেকে সরানো'), st_returned_to_supplier: L('সাপ্লায়ারকে ফেরত', 'returned to supplier', 'supplier কে ফেরত'),
  st_written_off: L('নষ্ট হিসেবে বাদ', 'written off', 'written off'), st_not_found: L('পাওয়া যায়নি', 'not found', 'not found'), st_nothing_left: L('আর কিছু নেই', 'nothing left', 'nothing left'),
  open: L('খোলা', 'open', 'open'), closed: L('বন্ধ', 'closed', 'closed'), howTo: L('মাল সরানো বা নষ্ট ধরা আগের স্টক স্ক্রিন থেকে করুন (কারণ: ফেরত / নষ্ট); এখানে শুধু কী করা হলো তা লিখে রাখা হয়।', 'Hold, return or write-off is done with the existing stock screens; here you only record what was done.', 'Hold, return বা write-off আগের stock screen থেকে করুন; এখানে শুধু record থাকে।'),
  stillToDo: L('করা বাকি আছে', 'still to do', 'still to do'), pickBatch: L('ব্যাচ বাছুন…', 'Choose a batch…', 'Batch বাছুন…'),
};
const T = (k) => lab(X[k]);
const NC = (k) => `${T('nc')}: ${T(k)}`;
const ERR = {
  not_allowed: X.noperm, batch_not_found: L('ব্যাচ পাওয়া যায়নি', 'Batch not found', 'Batch পাওয়া যায়নি'), bad_title: L('শিরোনাম ৩ থেকে ১২০ অক্ষর', 'Title: 3 to 120 characters', 'Title: 3 থেকে 120 অক্ষর'),
  reason_required: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'), note_required: L('নোট লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a note (at least 3 characters)', 'Note লিখুন (কমপক্ষে ৩ অক্ষর)'),
  case_closed: L('কেস বন্ধ', 'The case is closed', 'Case বন্ধ'), bad_status: L('অবস্থা ঠিক নয়', 'Status is not valid', 'Status ঠিক নয়'), batch_not_in_case: L('এই ব্যাচ কেসে নেই', 'The batch is not in the case', 'Batch case এ নেই'),
  bad_query: L('খোঁজার লেখা ৬০ অক্ষরের মধ্যে', 'Search text: max 60 characters', 'Search text: max 60 অক্ষর'), 'not allowed for this location': L('এই জায়গা আপনার নয়', 'You may not see this place', 'এই place আপনার নয়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const ownTxt = (k) => (X[k] ? T(k) : k);
const D = { q: '', loc: '', all: false, locs: [], canRecall: false, cur: null, fwd: null, back: null, batch: null, cases: null, caseData: null, busy: false };
const itemN = (o) => (o ? nm(o) : '');
const locN = (r) => (S.lang === 'en' ? (r.location_en || r.location) : r.location) || '';
const locOf = (id) => { const l = D.locs.find((x) => String(x.id) === String(id)); return l ? nm(l) : String(id); };
const U = () => B.s2 || {};
const unit = (c) => (U().unitLabel ? U().unitLabel(c) : c || '');

function originText(o) {
  if (!o) return `<span class="muted">${esc(NC('fOrigin'))}</span>`;
  if (o.type === 'receipt') {
    return `${esc(T('oReceipt'))}: <b>${o.supplier ? esc(o.supplier) : esc(NC('fSupplier'))}</b> · ${esc(T('oBill'))} ${esc(o.bill_no || '—')} ${esc(d10(o.bill_date))} · ${esc(T('lot'))} ${o.lot_no ? '<b>' + esc(o.lot_no) + '</b>' : esc(NC('fLot'))} · ${esc(T('expiry'))} ${o.expiry ? esc(d10(o.expiry)) : esc(NC('fExpiry'))}`;
  }
  if (o.type === 'grn_form') return `${esc(T('oGrn'))}: ${o.supplier ? esc(o.supplier) : esc(NC('fSupplier'))} · ${esc(T('lot'))} ${o.lot_no ? esc(o.lot_no) : esc(NC('fLot'))} · ${esc(T('expiry'))} ${o.expiry ? esc(d10(o.expiry)) : esc(NC('fExpiry'))}`;
  if (o.type === 'production') return `${esc(T('oProd'))} · ${esc(d10(o.made_at))}`;
  if (o.type === 'transfer') return `${esc(T('oTransfer'))}${o.from_location_id ? ': ' + esc(locOf(o.from_location_id)) : ''}`;
  return `<span class="muted">${esc(T('oUnknown'))}${o.lot_no ? ' · ' + esc(T('lot')) + ' ' + esc(o.lot_no) : ''}</span>`;
}
function batchCard(b, extra = '') {
  return `<div class="card tap" data-act="tr_open" data-v="${esc(b.batch_id)}" style="cursor:pointer"><div class="row between"><b>${esc(b.code)} · ${esc(itemN(b))}</b><span class="muted">#${esc(b.batch_id)}</span></div>
    <div class="muted">${esc(locN(b))} · ${esc(T('made'))} ${esc(d10(b.made_at))} · ${esc(T('expiry'))} ${b.expires_at ? esc(d10(b.expires_at)) : esc(NC('fExpiry'))}</div>
    <div>${esc(T('qmade'))} ${q4(b.qty_made)} · ${esc(T('left'))} <b>${q4(b.qty_remaining)}</b> ${esc(unit(b.base_unit))}${b.lot_no ? ' · ' + esc(T('lot')) + ' ' + esc(b.lot_no) : ''}${extra}</div>
    <div class="muted">${originText(b.origin)}</div></div>`;
}
const tbl = (head, rows) => (rows.length ? `<div class="scrollx"><table class="tbl" style="font-size:.8rem;width:100%"><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>` : `<p class="muted">${esc(T('none'))}</p>`);

/* ---------- forward part (shared by the trace and the recall report) ---------- */
function fwdHTML(f) {
  if (!f) return '';
  const s = f.summary || {}, out = [];
  if (f.hidden_places > 0) out.push(`<div class="notice warn">${esc(T('hidden'))} (${f.hidden_places})</div>`);
  if (f.sales_truncated || f.batches_truncated) out.push(`<div class="notice warn">${esc(T('trunc'))}</div>`);
  out.push(`<h3>${esc(T('byPlace'))}</h3>` + tbl([T('place'), T('onHand'), T('sold'), T('transit')], (s.by_place || []).map((p) =>
    `<tr><td>${esc(locN(p))}</td><td>${q4(p.on_hand)}</td><td>${q4(p.sold)}${p.sales_n ? ` <span class="muted">(${p.sales_n})</span>` : ''}</td><td>${q4(p.in_transit)}</td></tr>`)));
  out.push(`<h3>${esc(T('reached'))} (${(f.batches || []).length})</h3>` + (f.batches || []).map((b) => batchCard(b, ` · <span class="chip">${esc(ownTxt('rel_' + b.relation))}</span>`)).join(''));
  out.push(`<h3>${esc(T('sales'))} (${f.sales_total || 0})</h3><div class="muted">${esc(T('named'))}: ${s.named_customers ?? 0} · ${esc(T('noName'))}: ${s.sales_without_customer ?? 0}</div>` +
    tbl([T('date'), T('receipt'), T('place'), T('named'), T('sold')], (f.sales || []).map((x, i) =>
      `<tr class="tap" data-act="tr_sale" data-i="${i}" style="cursor:pointer"><td>${esc(d10(x.sale_date))}</td><td>#${esc(x.receipt)}</td><td>${esc(locN(x))}</td><td>${x.customer ? esc(x.customer) : `<span class="muted">${esc(T('noCust'))}</span>`}</td><td>${q4(x.qty)}</td></tr>`)));
  out.push(`<h3>${esc(T('transfers'))}</h3>` + tbl([T('place'), T('sent'), T('recv'), ''], (f.transfers || []).map((t) =>
    `<tr><td>${esc(locOf(t.from_location_id))} → ${esc(locOf(t.to_location_id))}<div class="muted">${esc(d10(t.sent_at))}</div></td><td>${q4(t.qty_sent)}</td><td>${t.status === 'received' ? q4(t.received_qty) : '—'}</td><td>${esc(ownTxt(t.status === 'sent' ? 'stSent' : 'stReceived'))}</td></tr>`)));
  if ((f.taken_out || []).length) out.push(`<h3>${esc(T('takenOut'))}</h3>` + (f.taken_out || []).map((w) =>
    `<div class="row between"><span>#${esc(w.batch_id)} · ${esc(ownTxt('tk_' + w.reason))}</span><b>${q4(w.qty)}</b></div>`).join(''));
  if ((f.issued_without_run || []).length) out.push(`<div class="notice warn">${esc(T('manual'))}: ${(f.issued_without_run || []).map((m) => '#' + m.batch_id + ' ' + q4(m.qty)).join(', ')}</div>`);
  if ((s.unbatched || []).length) out.push(`<div class="notice warn"><b>${esc(T('unb'))}</b>${(s.unbatched || []).map((u) => `<div>${esc(u.code)} · ${esc(itemN(u))} · ${esc(locOf(u.location_id))}: <b>${u.negative ? '−' : ''}${q4(u.unbatched)}</b> ${esc(unit(u.base_unit))}</div>`).join('')}</div>`);
  return out.join('');
}
function fwdRows(f) {   // CSV rows of the forward part
  const r = []; if (!f) return r; const s = f.summary || {};
  r.push([T('byPlace')], [T('place'), T('onHand'), T('sold'), T('transit')]);
  (s.by_place || []).forEach((p) => r.push([locN(p), p.on_hand, p.sold, p.in_transit]));
  r.push([], [T('reached')], ['batch', 'code', 'item', T('place'), T('lot'), T('made'), T('expiry'), T('qmade'), T('left'), T('fOrigin')]);
  (f.batches || []).forEach((b) => r.push([b.batch_id, b.code, itemN(b), locN(b), b.lot_no || NC('fLot'), d10(b.made_at), b.expires_at ? d10(b.expires_at) : NC('fExpiry'), b.qty_made, b.qty_remaining, (b.origin && b.origin.type) || NC('fOrigin')]));
  r.push([], [T('sales')], ['sale', T('receipt'), T('place'), T('named'), T('sold'), 'batch']);
  (f.sales || []).forEach((x) => r.push([d10(x.sale_date), x.receipt, locN(x), x.customer || T('noCust'), x.qty, x.batch_id]));
  r.push([], [T('transfers')], ['transfer', T('sent'), T('recv'), 'status']);
  (f.transfers || []).forEach((t) => r.push([locOf(t.from_location_id) + ' > ' + locOf(t.to_location_id), t.qty_sent, t.status === 'received' ? t.received_qty : '', t.status]));
  r.push([], [T('unb')], ['code', T('place'), 'unbatched']);
  (s.unbatched || []).forEach((u) => r.push([u.code, locOf(u.location_id), u.unbatched]));
  return r;
}
const csvCell = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
function download(name, text) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
async function exportCSV(key, name, rows, filters) {
  const n = rows.length;
  const r = await sb.rpc('rb3_log_export', { p_key: key, p_kind: 'csv', p_filters: filters || {}, p_rows: n });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : eText(r.error)); return false; }
  const p = (S.ctx && S.ctx.profile) || {};
  const all = rows.concat([[], [name, new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)', p.full_name || p.staff_id || '']]);
  download(`${name}.csv`, all.map((r2) => r2.map(csvCell).join(',')).join('\r\n') + '\r\n'); toast(T('expDone')); return true;
}

/* ---------- trace: search ---------- */
async function loadLocs() { try { D.locs = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : []; } catch (e) { D.locs = []; } }
async function canRecall() { try { return !!(U().grant && await U().grant('recall_manage', null)); } catch (e) { return false; } }
function searchView() {
  const locSel = `<select id="tr_loc"><option value="">${esc(T('all'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(D.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;
  shell(T('title'), `<div class="stack"><p class="muted">${esc(T('intro'))}</p>
    <div><label for="tr_q">${esc(T('q'))}</label><input id="tr_q" autocomplete="off" maxlength="60" value="${esc(D.q)}"></div>
    <div><label for="tr_loc">${esc(T('place'))}</label>${locSel}</div>
    <label class="row"><input type="checkbox" id="tr_all" ${D.all ? 'checked' : ''}> ${esc(T('withEmpty'))}</label>
    <button class="primary full" data-act="tr_find">${esc(T('find'))}</button><div id="tr_res" class="stack"></div></div>`, true);
  if (D.q || D.all) find();
}
async function find() {
  D.q = ($('#tr_q') || {}).value || ''; D.loc = ($('#tr_loc') || {}).value || ''; D.all = !!($('#tr_all') || {}).checked;
  const box = $('#tr_res'); if (!box) return; box.innerHTML = B.ui.state('loading');
  const r = await sb.rpc('trace_batch_find', { p_q: D.q || null, p_item: null, p_loc: D.loc ? Number(D.loc) : null, p_all: D.all, p_limit: 100 });
  if (r.error) { box.innerHTML = B.ui.state('error', eText(r.error)); return; }
  const rows = r.data || []; box.innerHTML = rows.length ? rows.map((b) => batchCard(b)).join('') : B.ui.state('empty', T('none'));
}

/* ---------- trace: one batch ---------- */
async function detail(id) {
  shell(T('title'), B.ui.state('loading'), true);
  const r = await sb.rpc('trace_batch', { p_batch: id, p_dir: 'both' });
  if (r.error) { shell(T('title'), `<div class="stack">${B.ui.state('error', eText(r.error))}<button class="full" data-act="go" data-v="trace">←</button></div>`, true); return; }
  const d = r.data || {}; D.cur = d; D.fwd = d.forward; D.back = d.back; D.batch = d.batch; D.canRecall = await canRecall();
  const b = d.batch || {}; const back = d.back || {}; const warn = (d.warnings || []).includes('origin_not_captured');
  const inputs = (back.inputs || []).map((i) => `<div class="card tap" data-act="tr_open" data-v="${esc(i.batch_id)}" style="cursor:pointer"><b>${esc(i.code)} · ${esc(itemN(i))}</b> · ${esc(T('used'))} ${q4(i.qty_used)} ${esc(unit(i.base_unit))}
      <div class="muted">${esc(T('lot'))} ${i.lot_no ? esc(i.lot_no) : esc(NC('fLot'))} · #${esc(i.batch_id)}</div><div class="muted">${originText(i.root_origin)}</div></div>`).join('');
  const unbIn = (back.unbatched_inputs || []).map((i) => `<div class="notice warn">${esc(T('unbatchedIn'))}: ${esc(i.code)} · ${esc(itemN(i))} · ${q4(i.qty)}</div>`).join('');
  shell(T('title'), `<div class="stack" id="tr_detail">
    <div class="card"><div class="row between"><b>${esc(b.code)} · ${esc(itemN(b))}</b><span class="muted">#${esc(b.batch_id)}</span></div>
      <div class="muted">${esc(locN(b))} · ${esc(T('made'))} ${esc(d10(b.made_at))} · ${esc(T('expiry'))} ${b.expires_at ? esc(d10(b.expires_at)) : esc(NC('fExpiry'))}</div>
      <div>${esc(T('qmade'))} ${q4(b.qty_made)} · ${esc(T('left'))} <b>${q4(b.qty_remaining)}</b> ${esc(unit(b.base_unit))}${b.lot_no ? ' · ' + esc(T('lot')) + ' ' + esc(b.lot_no) : ''}</div>
      <div class="muted">${originText(b.origin)}</div>${warn ? `<div class="notice warn">${esc(NC('fOrigin'))}</div>` : ''}</div>
    ${inputs || unbIn ? `<h3>${esc(T('back'))}</h3>${inputs}${unbIn}` : ''}
    <h2>${esc(T('fwd'))}</h2>${fwdHTML(d.forward)}
    <div class="row"><button data-act="tr_csv">${esc(T('csv'))}</button>${D.canRecall ? `<button class="primary" data-act="tr_recall" data-v="${esc(b.batch_id)}">${esc(T('startRecall'))}</button>` : ''}</div>
    <button class="full" data-act="go" data-v="trace">←</button></div>`, true);
}
function traceCSV() {
  const d = D.cur; if (!d) return; const b = d.batch || {};
  const rows = [['Trace', b.batch_id, b.code, itemN(b), locN(b), b.lot_no || NC('fLot')], [T('fOrigin'), (b.origin && b.origin.type) || NC('fOrigin'), b.origin && b.origin.supplier || '', b.origin && b.origin.bill_no || '', b.origin && b.origin.lot_no || '', b.origin && b.origin.expiry || ''], []];
  rows.push([T('back')]);
  ((d.back || {}).inputs || []).forEach((i) => rows.push([i.batch_id, i.code, itemN(i), i.qty_used, i.lot_no || NC('fLot'), i.root_origin && i.root_origin.supplier || NC('fSupplier')]));
  ((d.back || {}).unbatched_inputs || []).forEach((i) => rows.push([T('unbatchedIn'), i.code, itemN(i), i.qty]));
  rows.push([]); rows.push([T('fwd')]);
  exportCSV('trace', `trace-batch-${b.batch_id}`, rows.concat(fwdRows(d.forward)), { batch: b.batch_id });
}
function saleSheet(i) {
  const x = ((D.fwd || D.caseData && D.caseData.forward || {}).sales || [])[i]; if (!x) return;
  openSheet(`<h2>${esc(T('receipt'))} #${esc(x.receipt)}</h2><div class="stack"><div>${esc(d10(x.sale_date))} · ${esc(locN(x))}</div><div>${x.customer ? esc(x.customer) : `<span class="muted">${esc(T('noCust'))}</span>`}</div>
    <div><b>${esc(x.code)}</b> · ${q4(x.qty)}</div><button class="full" data-act="tr_open" data-v="${esc(x.batch_id)}">${esc(T('trace'))} #${esc(x.batch_id)}</button><button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`);
}

/* ---------- recall ---------- */
async function recallList() {
  shell(T('rtitle'), B.ui.state('loading'), true);
  const r = await sb.rpc('recall_list', { p_status: null });
  if (r.error) { shell(T('rtitle'), B.ui.state('error', eText(r.error)), true); return; }
  D.cases = r.data || []; D.canRecall = await canRecall();
  const card = (c) => `<div class="card tap" data-act="trc_open" data-v="${esc(c.id)}" style="cursor:pointer"><div class="row between"><b>${esc(T('caseNo'))} ${esc(c.case_no)} · ${esc(c.title)}</b><span class="chip ${c.status === 'open' ? 'warn' : ''}">${esc(ownTxt(c.status))}</span></div>
    <div class="muted">${esc(d10(c.opened_at))} · ${c.batches_n} ${esc(T('batch'))}${c.to_do_n ? ' · ' + c.to_do_n + ' ' + esc(T('stillToDo')) : ''}</div><div>${esc(c.reason)}</div></div>`;
  const open = D.cases.filter((c) => c.status === 'open'), closed = D.cases.filter((c) => c.status !== 'open');
  shell(T('rtitle'), `<div class="stack">${D.canRecall ? `<button class="primary full" data-act="trc_new">${esc(T('newCase'))}</button>` : ''}
    <h3>${esc(T('openCases'))}</h3>${open.map(card).join('') || B.ui.state('empty', T('none'))}<h3>${esc(T('closedCases'))}</h3>${closed.map(card).join('') || B.ui.state('empty', T('none'))}</div>`, true);
}
function newCaseSheet(batchId) {
  D.sheetBatch = batchId ? Number(batchId) : null; D.client = rid();
  openSheet(`<h2>${esc(T('newCase'))}</h2><div class="stack"><p class="muted">${esc(T('paperCode'))}</p>
    <div><label for="rc_t">${esc(T('cTitle'))}</label><input id="rc_t" maxlength="120" autocomplete="off"></div>
    <div><label for="rc_r">${esc(T('cReason'))}</label><input id="rc_r" maxlength="500" autocomplete="off"></div>
    <div><label for="rc_h">${esc(T('cHazard'))}</label><input id="rc_h" maxlength="300" autocomplete="off"></div>
    ${D.sheetBatch ? `<div class="muted">${esc(T('batch'))} #${esc(D.sheetBatch)}</div>` : `<div class="muted">${esc(T('addBatch'))}: ${esc(T('trace'))} → ${esc(T('startRecall'))}</div>`}
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="rc_create">${esc(T('save'))}</button></div></div>`);
}
async function caseView(id) {
  shell(T('rtitle'), B.ui.state('loading'), true);
  const r = await sb.rpc('recall_affected', { p_case: id });
  if (r.error) { shell(T('rtitle'), `<div class="stack">${B.ui.state('error', eText(r.error))}<button class="full" data-act="go" data-v="recall">←</button></div>`, true); return; }
  const d = r.data || {}; D.caseData = d; D.canRecall = await canRecall(); D.fwd = d.forward;
  const c = d.case || {}, open = c.status === 'open';
  const ent = (d.entered || []).map((b, i) => `<div class="card"><div class="row between"><b>${esc(b.code)} · ${esc(itemN(b))}</b><span class="chip ${b.action_status === 'to_do' ? 'warn' : ''}">${esc(ownTxt('st_' + b.action_status))}</span></div>
    <div class="muted">${esc(locN(b))} · ${esc(T('lot'))} ${b.lot_no ? esc(b.lot_no) : esc(NC('fLot'))} · #${esc(b.batch_id)} · ${esc(T('left'))} ${q4(b.qty_remaining)} ${esc(unit(b.base_unit))}</div>
    <div class="muted">${originText(b.origin)}</div>${b.action_note ? `<div>${esc(b.action_note)}</div>` : ''}
    <div class="row"><button class="mini" data-act="tr_open" data-v="${esc(b.batch_id)}">${esc(T('trace'))}</button>${open && D.canRecall ? `<button class="mini" data-act="rc_mark" data-i="${i}">${esc(T('mark'))}</button>` : ''}</div></div>`).join('');
  const unl = (d.unlotted_receipts || []);
  shell(`${T('caseNo')} ${c.case_no}`, `<div class="stack"><div class="card"><div class="row between"><b>${esc(c.title)}</b><span class="chip ${open ? 'warn' : ''}">${esc(ownTxt(c.status))}</span></div>
      <div>${esc(c.reason)}</div>${c.hazard ? `<div class="muted">${esc(c.hazard)}</div>` : ''}<div class="muted">${esc(d10(c.opened_at))} · ${esc(c.opened_staff || '')}</div>${c.close_note ? `<div class="muted">${esc(c.close_note)}</div>` : ''}</div>
    <p class="muted">${esc(T('howTo'))}</p>
    <h3>${esc(T('batches'))}</h3>${ent}${open && D.canRecall ? `<button class="full" data-act="trc_add">${esc(T('addBatch'))}</button>` : ''}
    <h2>${esc(T('affected'))}</h2>${fwdHTML(d.forward)}
    ${unl.length ? `<div class="notice warn"><b>${esc(T('unlot'))}</b>${unl.map((u) => `<div>${esc(u.supplier)} · ${esc(T('oBill'))} ${esc(u.bill_no || '—')} ${esc(d10(u.bill_date))} · ${esc(u.code)} · ${q4(u.qty)}</div>`).join('')}</div>` : ''}
    <div class="row"><button data-act="rc_csv">${esc(T('csv'))}</button>${open && D.canRecall ? `<button class="danger" data-act="rc_close">${esc(T('closeCase'))}</button>` : ''}</div>
    <button class="full" data-act="go" data-v="recall">←</button></div>`, true);
}
function caseCSV() {
  const d = D.caseData; if (!d) return; const c = d.case || {};
  const rows = [['Recall', c.case_no, c.title, c.status], [T('cReason'), c.reason], [T('cHazard'), c.hazard || ''], [], [T('batches')], ['batch', 'code', 'item', T('place'), T('lot'), T('left'), 'action', 'note']];
  (d.entered || []).forEach((b) => rows.push([b.batch_id, b.code, itemN(b), locN(b), b.lot_no || NC('fLot'), b.qty_remaining, b.action_status, b.action_note || '']));
  rows.push([]);
  fwdRows(d.forward).forEach((r) => rows.push(r));
  rows.push([], [T('unlot')], [T('oBill'), 'date', T('fSupplier'), 'code', 'qty']);
  (d.unlotted_receipts || []).forEach((u) => rows.push([u.bill_no || '', d10(u.bill_date), u.supplier, u.code, u.qty]));
  exportCSV('recall', `recall-case-${c.case_no}`, rows, { case: c.case_no });
}
function markSheet(i) {
  const b = (D.caseData.entered || [])[i]; if (!b) return; D.markBatch = b.batch_id;
  openSheet(`<h2>${esc(T('mark'))} · ${esc(b.code)} #${esc(b.batch_id)}</h2><div class="stack"><div><select id="rc_st">${['to_do', 'removed_from_shelf', 'returned_to_supplier', 'written_off', 'not_found', 'nothing_left'].map((s) => `<option value="${s}" ${b.action_status === s ? 'selected' : ''}>${esc(ownTxt('st_' + s))}</option>`).join('')}</select></div>
    <div><label for="rc_n">${esc(T('note'))}</label><input id="rc_n" maxlength="300" autocomplete="off" value="${esc(b.action_note || '')}"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="rc_markgo">${esc(T('save'))}</button></div></div>`);
}
async function addSheet() {
  const r = await sb.rpc('trace_batch_find', { p_q: null, p_item: null, p_loc: null, p_all: true, p_limit: 100 });
  const rows = (r && !r.error ? r.data : []) || [];
  openSheet(`<h2>${esc(T('addBatch'))}</h2><div class="stack"><select id="rc_pick"><option value="">${esc(T('pickBatch'))}</option>${rows.map((b) => `<option value="${esc(b.batch_id)}">${esc(b.code)} · ${esc(b.lot_no || '#' + b.batch_id)} · ${esc(locN(b))} · ${q4(b.qty_remaining)}</option>`).join('')}</select>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="rc_addgo">${esc(T('save'))}</button></div></div>`);
}
const act = async (p, ok) => { if (D.busy) return; D.busy = true; try { const r = await p; if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); await ok(r.data || {}); } catch (e) { fail(e); } finally { D.busy = false; } };

Object.assign(H, {
  tr_find: () => find().catch(fail),
  tr_open: (a) => { closeSheet(); location.hash = '#/trace/' + a.dataset.v; },
  tr_csv: traceCSV,
  tr_sale: (a) => saleSheet(Number(a.dataset.i)),
  tr_recall: (a) => { location.hash = '#/recall/new/' + a.dataset.v; },
  trc_open: (a) => { location.hash = '#/recall/' + a.dataset.v; },
  trc_new: () => newCaseSheet(null),
  rc_create: () => {
    const t = ($('#rc_t') || {}).value || '', r = ($('#rc_r') || {}).value || '', h = ($('#rc_h') || {}).value || '';
    if (t.trim().length < 3) return toast(lab(ERR.bad_title)); if (r.trim().length < 3) return toast(lab(ERR.reason_required));
    return act(sb.rpc('recall_open', { p_title: t.trim(), p_reason: r.trim(), p_hazard: h.trim() || null, p_batches: D.sheetBatch ? [D.sheetBatch] : [], p_client: D.client }), (d) => { location.hash = '#/recall/' + d.id; });
  },
  rc_mark: (a) => markSheet(Number(a.dataset.i)),
  rc_markgo: () => { const c = D.caseData.case; return act(sb.rpc('recall_batch_mark', { p_case: c.id, p_batch: D.markBatch, p_status: ($('#rc_st') || {}).value, p_note: (($('#rc_n') || {}).value || '').trim() || null }), () => caseView(c.id)); },
  trc_add: () => addSheet().catch(fail),
  rc_addgo: () => { const v = ($('#rc_pick') || {}).value; if (!v) return toast(T('pickBatch')); const c = D.caseData.case; return act(sb.rpc('recall_add_batch', { p_case: c.id, p_batch: Number(v), p_note: null }), () => caseView(c.id)); },
  rc_close: () => openSheet(`<h2>${esc(T('closeCase'))}</h2><div class="stack"><div><label for="rc_cn">${esc(T('note'))}</label><input id="rc_cn" maxlength="500" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="rc_closego">${esc(T('closeCase'))}</button></div></div>`),
  rc_closego: () => { const n = (($('#rc_cn') || {}).value || '').trim(); if (n.length < 3) return toast(lab(ERR.note_required)); const c = D.caseData.case; return act(sb.rpc('recall_close', { p_case: c.id, p_note: n }), () => caseView(c.id)); },
  rc_csv: caseCSV,
});

async function viewTrace() {
  if (B.loadStatic) await B.loadStatic();
  await loadLocs();
  const p = location.hash.replace(/^#\/?/, '').split('/');
  if (/^\d+$/.test(p[1] || '')) return detail(Number(p[1])).catch(fail);
  searchView();
}
async function viewRecall() {
  if (B.loadStatic) await B.loadStatic();
  await loadLocs();
  const p = location.hash.replace(/^#\/?/, '').split('/');
  try {
    if (p[1] === 'new') { await recallList(); D.canRecall = await canRecall(); if (D.canRecall) newCaseSheet(/^\d+$/.test(p[2] || '') ? p[2] : null); return; }
    if (p[1] && /^[0-9a-f-]{36}$/.test(p[1])) return await caseView(p[1]);
    await recallList();
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { trace: viewTrace, recall: viewRecall });
})();
