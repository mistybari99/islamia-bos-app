/* Islamia BOS · Purchasing reports (#/purchrep): supplier returns and adjustments (#100), agreed prices and the price variance (#101), supplier rejection rate (#103),
   preferred / alternative suppliers with the dependency and risk report (#104), supplier delivery performance (#102). The price trend with a value column (#92) is the existing report (#/report/p2_rate_trend).
   Server: supabase/phase434.sql (supplier_price_*, item_supplier_*), phase435.sql (the five reports), phase436.sql (rb3_log_export for the CSV).
   All reports are read only. Money is shown only to who may see costs (the server sends null otherwise and says so). A missing figure is "data not captured: <field>", never 0.
   Every row opens its source (bill, quality check, purchase-order entry). Paper form code of the two maintenance lists: to be given by owner. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, nm, H, S } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q4 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const d10 = (v) => (v ? String(v).slice(0, 10) : '');
const X = {
  title: L('ক্রয় রিপোর্ট ও সাপ্লায়ার', 'Purchasing reports & suppliers', 'Purchase report ও supplier'),
  tRet: L('ফেরত ও সমন্বয়', 'Returns & adjustments', 'Return ও adjustment'), tPrice: L('নির্ধারিত দাম', 'Agreed prices', 'Agreed price'), tRej: L('বাতিলের হার', 'Rejection rate', 'Rejection rate'),
  tSup: L('সাপ্লায়ার নির্ভরতা', 'Supplier dependency', 'Supplier dependency'), tDel: L('ডেলিভারি', 'Delivery', 'Delivery'),
  trend: L('দামের ধারা (মূল্যসহ)', 'Price trend (with value)', 'দামের trend (value সহ)'), openTrend: L('রিপোর্ট খুলুন', 'Open the report', 'Report খুলুন'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), place: L('জায়গা', 'Place', 'Place'), supplier: L('সাপ্লায়ার', 'Supplier', 'Supplier'), all: L('সব', 'All', 'All'), show: L('দেখুন', 'Show', 'Show'),
  none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'), nc: L('তথ্য লেখা হয়নি', 'data not captured', 'data লেখা হয়নি'), costHidden: L('টাকার অঙ্ক দেখার অনুমতি আপনার নেই — শুধু পরিমাণ দেখানো হচ্ছে।', 'You may not see money figures — quantities only.', 'টাকার অঙ্ক দেখার permission নেই — শুধু quantity।'),
  csv: L('CSV', 'CSV', 'CSV'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export এর permission নেই'), expDone: L('ফাইল নামানো হয়েছে', 'File downloaded', 'File নামানো হয়েছে'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  trunc: L('তালিকা ছোট করা হয়েছে', 'The list is cut short', 'List ছোট করা হয়েছে'),
  paperCode: L('কাগজের ফর্মের কোড: মালিক দেবেন', 'paper form code: to be given by owner', 'paper form code: owner দেবেন'),
  // returns
  returns: L('ক্রয় ফেরত', 'Purchase returns', 'Purchase return'), discounts: L('বিলের ছাড়', 'Bill discounts', 'Bill discount'), voided: L('বাতিল বিল', 'Voided bills', 'Voided bill'), refunds: L('সাপ্লায়ারের ফেরত টাকা', 'Supplier refunds', 'Supplier refund'),
  summary: L('সাপ্লায়ার অনুযায়ী', 'By supplier', 'Supplier অনুযায়ী'), against: L('মূল বিল', 'Against bill', 'Against bill'), reason: L('কারণ', 'Reason', 'Reason'), credit: L('ক্রেডিট', 'Credit', 'Credit'), variance: L('বইয়ের পার্থক্য', 'Book difference', 'Book difference'),
  purchases: L('কেনা', 'Purchases', 'Purchases'), retShare: L('ফেরতের হার', 'Return share', 'Return share'), disc: L('ছাড়', 'Discount', 'Discount'), amount: L('টাকা', 'Amount', 'Amount'), items: L('আইটেম', 'Items', 'Items'),
  // prices
  priceList: L('নির্ধারিত দামের তালিকা', 'Agreed price list', 'Agreed price list'), addPrice: L('নতুন নির্ধারিত দাম', 'New agreed price', 'নতুন agreed price'), item: L('আইটেম', 'Item', 'Item'), itemph: L('কোড বা নাম লিখুন', 'Type code or name', 'Code বা নাম লিখুন'),
  price: L('দাম', 'Price', 'Price'), perUnit: L('প্রতি একক', 'per unit', 'per unit'), unit: L('একক', 'Unit', 'Unit'), baseUnit: L('— বেস একক —', '— base unit —', '— base unit —'), validFrom: L('কবে থেকে', 'Valid from', 'Valid from'), note: L('নোট', 'Note', 'Note'),
  save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('থাক', 'Cancel', 'Cancel'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), retire: L('বন্ধ করুন', 'Retire', 'Retire'), why: L('কারণ (কমপক্ষে ৩ অক্ষর)', 'Reason (at least 3 characters)', 'Reason (কমপক্ষে ৩ অক্ষর)'),
  current: L('চলতি', 'current', 'current'), ended: L('শেষ', 'ended', 'ended'), retired: L('বন্ধ', 'retired', 'retired'), until: L('পর্যন্ত', 'until', 'until'),
  variancePrice: L('নির্ধারিত দামের সাথে তুলনা', 'Against the agreed price', 'Agreed price এর সাথে তুলনা'), actual: L('আসল দাম', 'Actual', 'Actual'), agreed: L('নির্ধারিত', 'Agreed', 'Agreed'), diff: L('পার্থক্য', 'Diff', 'Diff'), extra: L('বাড়তি খরচ', 'Extra cost', 'Extra cost'),
  withAgreed: L('নির্ধারিত দাম আছে', 'with an agreed price', 'agreed price আছে'), withoutAgreed: L('নির্ধারিত দাম লেখা নেই', 'without an agreed price', 'agreed price লেখা নেই'), lines: L('লাইন', 'lines', 'lines'), fAgreed: L('নির্ধারিত দাম', 'agreed price', 'agreed price'),
  basis: L('বিলের লাইনের দাম (বিলের ছাড়ের আগে) বিলের তারিখে চালু নির্ধারিত দামের সাথে মেলানো হয়।', 'Bill line price (before the bill discount) against the agreed price valid on the bill date.', 'Bill line price (bill discount এর আগে) bill date এ চালু agreed price এর সাথে মেলানো।'),
  // rejection
  checks: L('পরীক্ষা', 'Checks', 'Checks'), pass: L('পাস', 'Pass', 'Pass'), hold: L('আটক', 'Hold', 'Hold'), reject: L('বাতিল', 'Reject', 'Reject'), rate: L('বাতিলের হার', 'Reject rate', 'Reject rate'), qtyRate: L('পরিমাণে হার', 'by quantity', 'by quantity'),
  qtyChecked: L('পরীক্ষিত পরিমাণ', 'Qty checked', 'Qty checked'), qtyRej: L('বাতিল পরিমাণ', 'Qty rejected', 'Qty rejected'), qtyNc: L('টি পরীক্ষায় পরিমাণ লেখা নেই', 'checks without a quantity', 'check এ quantity লেখা নেই'), fQty: L('পরিমাণ', 'quantity', 'quantity'),
  noSupplier: L('সাপ্লায়ার লেখা নেই', 'supplier not captured', 'supplier লেখা নেই'), fSupplier: L('সাপ্লায়ার', 'supplier', 'supplier'), checked: L('মোট রসিদের মধ্যে পরীক্ষিত', 'of receipts that were checked', 'receipt এর মধ্যে checked'), receipts: L('রসিদ', 'receipts', 'receipts'),
  latest: L('প্রতিটি মালের শেষ পরীক্ষাটি ধরা হয়।', 'The latest check of each received lot counts.', 'প্রতিটি lot এর শেষ check ধরা হয়।'), checkRows: L('পরীক্ষার তালিকা', 'Checks', 'Checks'),
  // dependency
  declared: L('ঘোষিত সাপ্লায়ার', 'Declared suppliers', 'Declared suppliers'), preferred: L('পছন্দের', 'preferred', 'preferred'), alternative: L('বিকল্প', 'alternative', 'alternative'), manageLinks: L('পছন্দের / বিকল্প সাপ্লায়ার ঠিক করুন', 'Set preferred / alternative suppliers', 'Preferred / alternative supplier ঠিক করুন'),
  rank: L('ধরন', 'Rank', 'Rank'), main: L('প্রধান সাপ্লায়ার', 'Main supplier', 'Main supplier'), share: L('অংশ', 'share', 'share'), used: L('ব্যবহৃত সাপ্লায়ার', 'Suppliers used', 'Suppliers used'), qty: L('পরিমাণ', 'Quantity', 'Quantity'),
  fl_single_supplier_used: L('একটি মাত্র সাপ্লায়ার', 'single supplier', 'single supplier'), fl_declared_suppliers_not_captured: L('ঘোষিত সাপ্লায়ার লেখা নেই', 'declared suppliers: data not captured', 'declared supplier লেখা নেই'),
  fl_no_alternative_declared: L('বিকল্প ঠিক করা নেই', 'no alternative declared', 'alternative ঠিক নেই'), fl_preferred_not_the_main_supplier: L('পছন্দের সাপ্লায়ার প্রধান নয়', 'preferred is not the main supplier', 'preferred main নয়'),
  fl_used_supplier_not_declared: L('ব্যবহৃত সাপ্লায়ার ঘোষিত নয়', 'a used supplier is not declared', 'used supplier declared নয়'), addLink: L('সাপ্লায়ার যোগ', 'Add a supplier', 'Supplier যোগ'),
  sFlags: L('ঝুঁকি গণনা', 'Risk count', 'Risk count'),
  // delivery
  po: L('পিও', 'PO', 'PO'), promised: L('কথা দেওয়া তারিখ', 'Promised', 'Promised'), firstGrn: L('প্রথম গ্রহণ', 'First GRN', 'First GRN'), lastGrn: L('শেষ গ্রহণ', 'Last GRN', 'Last GRN'), late: L('দেরি (দিন)', 'Days late', 'Days late'),
  onTime: L('সময়ে', 'On time', 'On time'), lateN: L('দেরিতে', 'Late', 'Late'), onTimePct: L('সময়ে পাওয়ার হার', 'On-time rate', 'On-time rate'), avgLate: L('গড় দেরি (দিন)', 'Avg days late', 'Avg days late'), lead: L('গড় আসতে সময় (দিন)', 'Avg lead days', 'Avg lead days'),
  overdue: L('সময় পেরিয়েও আসেনি', 'Overdue, not received', 'Overdue'), partial: L('আংশিক', 'Partial', 'Partial'), fPromised: L('কথা দেওয়া তারিখ', 'promised date', 'promised date'),
  st_on_time: L('সময়ে এসেছে', 'on time', 'on time'), st_late: L('দেরিতে এসেছে', 'late', 'late'), st_received_no_promised_date: L('এসেছে, কথা দেওয়া তারিখ নেই', 'received, no promised date', 'received, promised date নেই'),
  st_partial: L('আংশিক এসেছে', 'partly received', 'partly received'), st_partial_overdue: L('আংশিক, সময় পেরিয়েছে', 'partly received, overdue', 'partial, overdue'), st_partial_no_promised_date: L('আংশিক, কথা দেওয়া তারিখ নেই', 'partly received, no promised date', 'partial, promised date নেই'),
  st_open: L('খোলা', 'open', 'open'), st_overdue_open: L('সময় পেরিয়েছে', 'overdue', 'overdue'), st_open_no_promised_date: L('খোলা, কথা দেওয়া তারিখ নেই', 'open, no promised date', 'open, promised date নেই'),
  delBasis: L('কাগজের পিও (06-3) ও মাল গ্রহণ (04-1) মিলিয়ে। ক্রয় বিলে পিওর লিংক নেই, তাই সেগুলো এতে নেই।', 'From the paper purchase orders (06-3) and goods received notes (04-1). Purchase bills carry no PO link, so they are not in it.', 'Paper PO (06-3) ও GRN (04-1) থেকে। Purchase bill এ PO link নেই, তাই সেগুলো নেই।'),
};
const T = (k) => lab(X[k]);
const NC = (k) => `${T('nc')}: ${T(k)}`;
const ERR = {
  not_allowed: X.noperm, 'not allowed for this location': L('এই জায়গা আপনার নয়', 'You may not see this place', 'এই place আপনার নয়'), bad_range: L('তারিখের সীমা ঠিক নয়', 'The date range is not valid', 'Date range ঠিক নয়'),
  bad_price: L('দাম ঠিক নয়', 'The price is not valid', 'Price ঠিক নয়'), unit_unknown: L('এককের রূপান্তর জানা নেই', 'Unit conversion unknown', 'Unit conversion জানা নেই'), overlaps_existing: L('এর আগের তারিখে চালু দাম আছে — আগে সেটি বন্ধ করুন', 'An open price starts on or after that date — retire it first', 'আগের date এ চালু price আছে — আগে retire করুন'),
  item_not_found: L('আইটেম পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি'), supplier_not_found: L('সাপ্লায়ার পাওয়া যায়নি', 'Supplier not found', 'Supplier পাওয়া যায়নি'), note_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'Reason লিখুন (কমপক্ষে ৩ অক্ষর)'),
  bad_rank: L('ধরন ঠিক নয়', 'Rank is not valid', 'Rank ঠিক নয়'), bad_date: L('তারিখ ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const D = { tab: 'ret', from: null, to: null, loc: '', sup: '', locs: [], sups: [], items: [], data: {}, canTerms: false, busy: false, sheet: null };
const itemText = (i) => i.code + ' · ' + nm(i);
const itemFrom = (v) => { const s = String(v || '').trim(); if (!s) return null; const c = s.split(' · ')[0].trim().toLowerCase(); return D.items.find((i) => i.code.toLowerCase() === c) || D.items.find((i) => nm(i).toLowerCase() === s.toLowerCase()) || null; };
const unit = (c) => (B.s2 && B.s2.unitLabel ? B.s2.unitLabel(c) : c || '');
const unitOpts = () => ((B.ENV && B.ENV.lists && B.ENV.lists.units) || []).filter((r) => r.active !== false);
const go = (hash, label) => `<button class="mini" data-act="pr_go" data-v="${esc(hash)}">${esc(label)}</button>`;
const csvCell = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
function download(name, text) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }
async function exportCSV(key, name, rows) {
  const r = await sb.rpc('rb3_log_export', { p_key: key, p_kind: 'csv', p_filters: { from: D.from, to: D.to, loc: D.loc || null, supplier: D.sup || null }, p_rows: rows.length });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : eText(r.error)); return; }
  const p = (S.ctx && S.ctx.profile) || {};
  download(name + '.csv', rows.concat([[], [name, new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)', p.full_name || p.staff_id || '']]).map((r2) => r2.map(csvCell).join(',')).join('\r\n') + '\r\n'); toast(T('expDone'));
}
const mv = (v, cost) => (cost === false ? '—' : v === null || v === undefined ? '—' : money(v));
const tbl = (head, rows) => (rows.length ? `<div class="scrollx"><table class="tbl" style="font-size:.8rem;width:100%"><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>` : `<p class="muted">${esc(T('none'))}</p>`);
const costNote = (d) => (d && d.cost_hidden ? `<div class="notice warn">${esc(T('costHidden'))}</div>` : '');
const truncNote = (d) => (d && d.truncated ? `<div class="notice warn">${esc(T('trunc'))}</div>` : '');

/* ---------- tabs ---------- */
const TABS = [['ret', 'tRet'], ['price', 'tPrice'], ['rej', 'tRej'], ['sup', 'tSup'], ['del', 'tDel']];
function frame() {
  const locOpts = D.locs.map((l) => `<option value="${l.id}" ${String(D.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('');
  const supOpts = D.sups.map((s) => `<option value="${esc(s.id)}" ${D.sup === s.id ? 'selected' : ''}>${esc(s.name)}</option>`).join('');
  shell(T('title'), `<div class="stack"><div class="card"><b>${esc(T('trend'))}</b> <button class="mini" data-act="pr_go" data-v="#/report/p2_rate_trend">${esc(T('openTrend'))}</button></div>
    <div class="row wrap">${TABS.map((t) => `<button type="button" class="btn ${D.tab === t[0] ? 'primary' : ''}" data-act="pur_tab" data-v="${t[0]}">${esc(T(t[1]))}</button>`).join('')}</div>
    <div class="row"><div style="flex:1"><label for="pr_from">${esc(T('from'))}</label><input id="pr_from" type="date" value="${esc(D.from)}"></div><div style="flex:1"><label for="pr_to">${esc(T('to'))}</label><input id="pr_to" type="date" value="${esc(D.to)}"></div></div>
    <div class="row"><div style="flex:1"><label for="pr_loc">${esc(T('place'))}</label><select id="pr_loc"><option value="">${esc(T('all'))}</option>${locOpts}</select></div>
      <div style="flex:1"><label for="pr_sup">${esc(T('supplier'))}</label><select id="pr_sup"><option value="">${esc(T('all'))}</option>${supOpts}</select></div></div>
    <button class="full" data-act="pr_show">${esc(T('show'))}</button><div id="pr_out" class="stack">${B.ui.state('loading')}</div></div>`, true);
  run();
}
const filt = () => ({ p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null });
const out = (h) => { const el = $('#pr_out'); if (el) el.innerHTML = h; };
const footer = (key, label) => `<div class="row"><button data-act="pur_csv" data-k="${key}" data-n="${label}">${esc(T('csv'))}</button></div>`;
const supN = (id) => { const s = D.sups.find((x) => x.id === id); return s ? s.name : id; };

async function run() {
  out(B.ui.state('loading'));
  try {
    if (D.tab === 'ret') await tabRet();
    else if (D.tab === 'price') await tabPrice();
    else if (D.tab === 'rej') await tabRej();
    else if (D.tab === 'sup') await tabSup();
    else await tabDel();
  } catch (e) { out(B.ui.state('error', eText(e))); }
}
async function call(fn, extra) {
  const r = await sb.rpc(fn, Object.assign(filt(), extra || {}));
  if (r.error) throw r.error; return r.data;
}

/* ----- #100 ----- */
async function tabRet() {
  const d = D.data.ret = await call('supplier_returns_report', { p_supplier: D.sup || null }), c = !d.cost_hidden;
  out(costNote(d) + truncNote(d) + `<h3>${esc(T('summary'))}</h3>` + tbl([T('supplier'), T('purchases'), T('returns'), T('retShare'), T('disc'), T('voided'), T('refunds')], (d.summary || []).map((s) =>
      `<tr><td>${esc(s.supplier)}</td><td>${s.purchases_n} · ${mv(s.purchases_total, c)}</td><td>${s.returns_n} · ${mv(s.returns_total, c)}</td><td>${s.return_pct !== null && s.return_pct !== undefined ? s.return_pct + '%' : '—'}</td><td>${mv(s.discounts_total, c)}</td><td>${s.voided_n} · ${mv(s.voided_total, c)}</td><td>${s.refunds_n} · ${mv(s.refunds_total, c)}</td></tr>`))
    + `<h3>${esc(T('returns'))}</h3>` + ((d.returns || []).map((r) => `<div class="card"><div class="row between"><b>${esc(r.supplier)} · ${esc(r.bill_no || '—')}</b><span>${mv(r.total, c)}</span></div>
        <div class="muted">${esc(d10(r.bill_date))} · ${esc(r.location)} · ${esc(T('reason'))}: ${esc(S.lang === 'bn' ? (r.reason_label_bn || r.reason_label) : (r.reason_label || r.reason_code || ''))}${r.variance !== null && r.variance !== undefined ? ' · ' + esc(T('variance')) + ' ' + money(r.variance) : ''}</div>
        <div class="muted">${esc(T('items'))}: ${(r.items || []).map((i) => esc((i.code || '') + ' ' + q4(i.qty) + (i.unit ? ' ' + unit(i.unit) : ''))).join(', ')}</div>
        <div class="row">${go('#/purchase/' + r.bill_id, r.bill_no || 'bill')}${r.ref_bill_id ? go('#/purchase/' + r.ref_bill_id, T('against') + ' ' + (r.ref_bill_no || '')) : ''}</div></div>`).join('') || B.ui.state('empty', T('none')))
    + `<h3>${esc(T('discounts'))}</h3>` + tbl([T('supplier'), 'Bill', T('disc'), ''], (d.discounts || []).map((r) => `<tr><td>${esc(r.supplier)}</td><td>${esc(r.bill_no || '—')} ${esc(d10(r.bill_date))}</td><td>${mv(r.discount, c)}</td><td>${go('#/purchase/' + r.bill_id, '→')}</td></tr>`))
    + `<h3>${esc(T('voided'))}</h3>` + tbl([T('supplier'), 'Bill', T('amount'), ''], (d.voided || []).map((r) => `<tr><td>${esc(r.supplier)}</td><td>${esc(r.bill_no || '—')} ${esc(d10(r.bill_date))}<div class="muted">${esc(r.void_note || '')}</div></td><td>${mv(r.total, c)}</td><td>${go('#/purchase/' + r.bill_id, '→')}</td></tr>`))
    + `<h3>${esc(T('refunds'))}</h3>` + tbl([T('supplier'), T('amount'), ''], (d.refunds || []).map((r) => `<tr><td>${esc(r.supplier)}<div class="muted">${esc(d10(r.day))} · ${esc(r.mode)}</div></td><td>${mv(r.amount, c)}</td><td>${esc(r.note || '')}</td></tr>`))
    + footer('supplier_returns', 'supplier-returns'));
}
/* ----- #101 ----- */
async function tabPrice() {
  const parts = [];
  try {
    const pl = await sb.rpc('supplier_price_list', { p_item: null, p_supplier: D.sup || null, p_all: true });
    if (pl.error) throw pl.error;
    D.data.prices = pl.data || [];
    parts.push(`<h3>${esc(T('priceList'))}</h3>${D.canTerms ? `<p class="muted">${esc(T('paperCode'))}</p><button class="primary full" data-act="pr_pnew">${esc(T('addPrice'))}</button>` : ''}`
      + (D.data.prices.length ? D.data.prices.map((p) => `<div class="card" style="${p.active ? '' : 'opacity:.6'}"><div class="row between"><b>${esc(p.code)} · ${esc(nm(p))}</b><span class="chip ${p.current ? '' : 'warn'}">${esc(p.active ? (p.current ? T('current') : T('ended')) : T('retired'))}</span></div>
          <div>${esc(p.supplier)} · <b>${money(p.price)}</b> ${esc(T('perUnit'))} ${esc(unit(p.unit || p.base_unit))}</div><div class="muted">${esc(T('validFrom'))} ${esc(d10(p.effective_from))}${p.effective_to ? ' ' + esc(T('until')) + ' ' + esc(d10(p.effective_to)) : ''}${p.note ? ' · ' + esc(p.note) : ''}${p.retired_note ? ' · ' + esc(p.retired_note) : ''}</div>
          ${p.active && p.can_edit ? `<div class="row"><button class="mini" data-act="pr_pret" data-v="${p.id}">⋮ ${esc(T('retire'))}</button></div>` : ''}</div>`).join('') : B.ui.state('empty', T('none'))));
  } catch (e) { parts.push(`<div class="notice warn">${esc(eText(e))}</div>`); }
  try {
    const d = D.data.pv = await call('purch_price_variance', { p_supplier: D.sup || null, p_item: null });
    parts.push(`<h3>${esc(T('variancePrice'))}</h3><p class="muted">${esc(T('basis'))}</p>${truncNote(d)}<div class="card">${esc(T('withAgreed'))}: <b>${d.lines_with_agreed}</b> / ${d.lines} ${esc(T('lines'))} · ${esc(T('withoutAgreed'))}: <b>${d.lines_without_agreed}</b>${d.lines_without_agreed ? ` <span class="muted">(${esc(NC('fAgreed'))})</span>` : ''}<div>${esc(T('extra'))}: <b>${money(d.extra_cost_total)}</b></div></div>`
      + tbl([T('supplier'), T('lines'), T('extra')], (d.summary || []).map((s) => `<tr><td>${esc(s.supplier)}</td><td>${s.lines_with_agreed}/${s.lines}</td><td>${money(s.extra_cost)}</td></tr>`))
      + (d.rows || []).map((r) => `<div class="card"><div class="row between"><b>${esc(r.code)} · ${esc(nm(r))}</b>${r.agreed_price === null || r.agreed_price === undefined ? `<span class="chip warn">${esc(NC('fAgreed'))}</span>` : `<span class="chip ${Number(r.extra_cost) > 0 ? 'warn' : ''}">${r.diff_pct > 0 ? '+' : ''}${r.diff_pct}%</span>`}</div>
          <div class="muted">${esc(r.supplier)} · ${esc(r.bill_no || '—')} ${esc(d10(r.bill_date))} · ${q4(r.qty)} ${esc(unit(r.base_unit))}</div>
          <div>${esc(T('actual'))} ${money(r.actual_price)}${r.agreed_price !== null && r.agreed_price !== undefined ? ` · ${esc(T('agreed'))} ${money(r.agreed_price)} · ${esc(T('extra'))} <b>${money(r.extra_cost)}</b>` : ''}</div><div class="row">${go('#/purchase/' + r.bill_id, r.bill_no || 'bill')}</div></div>`).join('')
      + footer('price_variance', 'price-variance'));
  } catch (e) { parts.push(`<div class="notice warn">${esc(eText(e))}</div>`); }
  out(parts.join(''));
}
/* ----- #103 ----- */
async function tabRej() {
  const d = D.data.rej = await call('supplier_rejection_rate', { p_supplier: D.sup || null });
  out(`<p class="muted">${esc(T('latest'))}</p>` + ((d.rows || []).map((r) => `<div class="card"><div class="row between"><b>${r.supplier_not_captured ? esc(NC('fSupplier')) : esc(r.supplier)}</b><span class="chip ${Number(r.reject) > 0 ? 'warn' : ''}">${r.reject_rate_pct !== null && r.reject_rate_pct !== undefined ? r.reject_rate_pct + '%' : '—'}</span></div>
      <div class="muted">${esc(T('checks'))} ${r.checks} · ${esc(T('pass'))} ${r.pass} · ${esc(T('hold'))} ${r.hold} · ${esc(T('reject'))} ${r.reject}${r.receipts_n !== null && r.receipts_n !== undefined ? ` · ${esc(T('checked'))}: ${r.share_checked_pct ?? '—'}% (${r.receipts_n} ${esc(T('receipts'))})` : ''}</div>
      <div>${r.qty_captured_n > 0 ? `${esc(T('qtyChecked'))} ${q4(r.qty_checked)} · ${esc(T('qtyRej'))} ${q4(r.qty_rejected)} · ${esc(T('qtyRate'))} <b>${r.reject_rate_qty_pct !== null && r.reject_rate_qty_pct !== undefined ? r.reject_rate_qty_pct + '%' : '—'}</b>` : `<span class="muted">${esc(NC('fQty'))}</span>`}${r.qty_not_captured_n > 0 && r.qty_captured_n > 0 ? ` <span class="muted">(${r.qty_not_captured_n} ${esc(T('qtyNc'))})</span>` : ''}</div></div>`).join('') || B.ui.state('empty', T('none')))
    + `<h3>${esc(T('checkRows'))}</h3>` + ((d.checks || []).map((c) => `<div class="card"><div class="row between"><b>${c.supplier ? esc(c.supplier) : esc(NC('fSupplier'))}</b><span class="chip ${c.status === 'pass' ? '' : 'warn'}">${esc(T(c.status))}</span></div>
        <div class="muted">${esc(d10(c.day))} · ${c.code ? esc(c.code) + ' · ' + esc(nm(c)) : esc(NC('fQty') === '' ? '' : T('item'))}${c.qty !== null && c.qty !== undefined ? ' · ' + q4(c.qty) + ' ' + esc(unit(c.base_unit)) : ''}</div>${c.note ? `<div>${esc(c.note)}</div>` : ''}
        <div class="row">${go(c.is_bill ? '#/purchase/' + c.source_id : '#/entry/' + c.source_id, '→')}</div></div>`).join('') || B.ui.state('empty', T('none'))) + footer('rejection', 'rejection-rate'));
}
/* ----- #104 ----- */
async function tabSup() {
  const parts = [];
  const d = D.data.dep = await call('supplier_dependency', {});
  const s = d.summary || {};
  parts.push(costNote(d) + `<div class="card"><b>${esc(T('sFlags'))}</b>: ${esc(T('fl_single_supplier_used'))} ${s.single_supplier ?? 0} · ${esc(T('fl_declared_suppliers_not_captured'))} ${s.declared_not_captured ?? 0} · ${esc(T('fl_no_alternative_declared'))} ${s.no_alternative ?? 0} · ${esc(T('fl_preferred_not_the_main_supplier'))} ${s.preferred_not_main ?? 0} · ${esc(T('fl_used_supplier_not_declared'))} ${s.used_not_declared ?? 0}</div>`
    + (D.canTerms ? `<p class="muted">${esc(T('paperCode'))}</p><button class="primary full" data-act="pr_lnew">${esc(T('manageLinks'))}</button>` : ''));
  parts.push((d.rows || []).map((r, i) => `<div class="card tap" data-act="pr_dep" data-i="${i}" style="cursor:pointer"><div class="row between"><b>${esc(r.code)} · ${esc(nm(r))}</b><span class="chip ${r.flags.length ? 'warn' : ''}">${r.suppliers_used}</span></div>
      <div class="muted">${esc(T('main'))}: ${esc(r.top_supplier)} (${r.top_share_pct}%) · ${esc(T('qty'))} ${q4(r.qty_total)} ${esc(unit(r.base_unit))}${r.value_total !== null && r.value_total !== undefined ? ' · ' + money(r.value_total) : ''}</div>
      <div class="muted">${esc(T('preferred'))}: ${(r.preferred || []).map((p) => esc(p.supplier)).join(', ') || esc(NC('fSupplier'))} · ${esc(T('alternative'))}: ${(r.alternatives || []).map((p) => esc(p.supplier)).join(', ') || '—'}</div>
      <div>${r.flags.map((f) => `<span class="chip warn">${esc(T('fl_' + f))}</span>`).join(' ')}</div></div>`).join('') || B.ui.state('empty', T('none')));
  parts.push(footer('dependency', 'supplier-dependency'));
  out(parts.join(''));
}
/* ----- #102 ----- */
async function tabDel() {
  const d = D.data.del = await call('supplier_delivery_perf', { p_supplier: D.sup || null });
  out(`<p class="muted">${esc(T('delBasis'))}</p>${truncNote(d)}` + ((d.summary || []).map((s) => `<div class="card"><div class="row between"><b>${esc(s.supplier)}</b><span class="chip ${s.on_time_pct !== null && s.on_time_pct !== undefined && s.on_time_pct < 100 ? 'warn' : ''}">${s.on_time_pct !== null && s.on_time_pct !== undefined ? s.on_time_pct + '%' : '—'}</span></div>
      <div class="muted">PO ${s.pos} · ${esc(T('onTime'))} ${s.on_time} · ${esc(T('lateN'))} ${s.late} · ${esc(T('overdue'))} ${s.overdue_open} · ${esc(T('partial'))} ${s.partial}</div>
      <div class="muted">${esc(T('avgLate'))}: ${s.avg_days_late ?? '—'} · ${esc(T('lead'))}: ${s.avg_lead_days ?? '—'}</div>${s.promised_date_not_captured ? `<div class="muted">${s.promised_date_not_captured} PO — ${esc(NC('fPromised'))}</div>` : ''}</div>`).join('') || B.ui.state('empty', T('none')))
    + (d.rows || []).map((r) => `<div class="card"><div class="row between"><b>${esc(r.supplier)} · ${esc(r.po_no)}</b><span class="chip ${/late|overdue/.test(r.status) ? 'warn' : ''}">${esc(T('st_' + r.status))}</span></div>
        <div class="muted">${esc(d10(r.po_date))} · ${esc(r.location)} · ${esc(T('promised'))} ${r.promised_date ? esc(d10(r.promised_date)) : esc(NC('fPromised'))}</div>
        <div class="muted">${esc(T('firstGrn'))} ${r.first_grn ? esc(d10(r.first_grn)) : '—'} · ${esc(T('lastGrn'))} ${r.last_grn ? esc(d10(r.last_grn)) : '—'} · ${esc(T('late'))} ${r.days_late === null || r.days_late === undefined ? '—' : r.days_late}</div>
        <div class="row">${go('#/entry/' + r.entry_id, r.po_no)}</div></div>`).join('') + footer('delivery', 'delivery-performance'));
}

/* ---------- CSV rows per tab ---------- */
function csvRows(k) {
  const head = [T('title'), D.from, D.to];
  if (k === 'supplier_returns') {
    const d = D.data.ret || {}; const r = [head, [T('summary')], [T('supplier'), 'purchases n', 'purchases total', 'returns n', 'returns total', 'return %', 'discounts', 'voided n', 'voided total', 'refunds n', 'refunds total']];
    (d.summary || []).forEach((s) => r.push([s.supplier, s.purchases_n, s.purchases_total ?? '', s.returns_n, s.returns_total ?? '', s.return_pct ?? '', s.discounts_total ?? '', s.voided_n, s.voided_total ?? '', s.refunds_n, s.refunds_total ?? '']));
    r.push([], [T('returns')], ['date', T('supplier'), 'bill', T('against'), T('reason'), 'credit', 'items']);
    (d.returns || []).forEach((x) => r.push([d10(x.bill_date), x.supplier, x.bill_no, x.ref_bill_no || '', x.reason_label || x.reason_code || '', x.total ?? '', (x.items || []).map((i) => i.code + ' ' + i.qty).join('; ')]));
    r.push([], [T('discounts')], ['date', T('supplier'), 'bill', T('disc')]); (d.discounts || []).forEach((x) => r.push([d10(x.bill_date), x.supplier, x.bill_no, x.discount ?? '']));
    r.push([], [T('voided')], ['date', T('supplier'), 'bill', T('amount'), T('note')]); (d.voided || []).forEach((x) => r.push([d10(x.bill_date), x.supplier, x.bill_no, x.total ?? '', x.void_note || '']));
    r.push([], [T('refunds')], ['date', T('supplier'), T('amount'), 'mode']); (d.refunds || []).forEach((x) => r.push([d10(x.day), x.supplier, x.amount ?? '', x.mode]));
    return r;
  }
  if (k === 'price_variance') {
    const d = D.data.pv || {}; const r = [head, [T('withAgreed'), d.lines_with_agreed, T('withoutAgreed'), d.lines_without_agreed, T('extra'), d.extra_cost_total ?? ''], [], ['date', T('supplier'), 'bill', 'code', T('item'), 'qty', T('actual'), T('agreed'), T('diff'), 'diff %', T('extra')]];
    (d.rows || []).forEach((x) => r.push([d10(x.bill_date), x.supplier, x.bill_no, x.code, nm(x), x.qty, x.actual_price, x.agreed_price ?? NC('fAgreed'), x.diff ?? '', x.diff_pct ?? '', x.extra_cost ?? '']));
    return r;
  }
  if (k === 'rejection') {
    const d = D.data.rej || {}; const r = [head, [T('supplier'), T('checks'), T('pass'), T('hold'), T('reject'), T('rate'), T('qtyChecked'), T('qtyRej'), T('qtyRate'), 'qty not captured']];
    (d.rows || []).forEach((x) => r.push([x.supplier_not_captured ? NC('fSupplier') : x.supplier, x.checks, x.pass, x.hold, x.reject, x.reject_rate_pct ?? '', x.qty_captured_n > 0 ? x.qty_checked : NC('fQty'), x.qty_captured_n > 0 ? x.qty_rejected : '', x.reject_rate_qty_pct ?? '', x.qty_not_captured_n]));
    r.push([], [T('checkRows')], ['date', T('supplier'), 'status', 'code', 'qty', T('note')]); (d.checks || []).forEach((x) => r.push([d10(x.day), x.supplier || NC('fSupplier'), x.status, x.code || '', x.qty ?? NC('fQty'), x.note || '']));
    return r;
  }
  if (k === 'dependency') {
    const d = D.data.dep || {}; const r = [head, ['code', T('item'), T('used'), T('main'), 'share %', T('qty'), 'value', T('preferred'), T('alternative'), 'flags']];
    (d.rows || []).forEach((x) => r.push([x.code, nm(x), x.suppliers_used, x.top_supplier, x.top_share_pct, x.qty_total, x.value_total ?? '', (x.preferred || []).map((p) => p.supplier).join('; ') || NC('fSupplier'), (x.alternatives || []).map((p) => p.supplier).join('; '), x.flags.join('; ')]));
    return r;
  }
  const d = D.data.del || {}; const r = [head, [T('supplier'), 'PO', T('onTime'), T('lateN'), T('onTimePct'), T('avgLate'), T('lead'), T('overdue'), T('partial'), NC('fPromised')]];
  (d.summary || []).forEach((s) => r.push([s.supplier, s.pos, s.on_time, s.late, s.on_time_pct ?? '', s.avg_days_late ?? '', s.avg_lead_days ?? '', s.overdue_open, s.partial, s.promised_date_not_captured]));
  r.push([], ['PO', T('supplier'), 'PO date', T('promised'), T('firstGrn'), T('lastGrn'), T('late'), 'status']);
  (d.rows || []).forEach((x) => r.push([x.po_no, x.supplier, d10(x.po_date), x.promised_date ? d10(x.promised_date) : NC('fPromised'), x.first_grn ? d10(x.first_grn) : '', x.last_grn ? d10(x.last_grn) : '', x.days_late ?? '', x.status]));
  return r;
}

/* ---------- maintenance sheets ---------- */
function itemFld(id) { return `<div><label for="${id}">${esc(T('item'))}</label><input id="${id}" list="${id}_dl" autocomplete="off" placeholder="${esc(T('itemph'))}"><datalist id="${id}_dl">${D.items.map((i) => `<option value="${esc(itemText(i))}"></option>`).join('')}</datalist></div>`; }
const supSel = (id) => `<div><label for="${id}">${esc(T('supplier'))}</label><select id="${id}"><option value="">—</option>${D.sups.map((s) => `<option value="${esc(s.id)}">${esc(s.name)}</option>`).join('')}</select></div>`;
function priceSheet() {
  openSheet(`<h2>${esc(T('addPrice'))}</h2><div class="stack"><p class="muted">${esc(T('paperCode'))}</p>${itemFld('pp_item')}${supSel('pp_sup')}
    <div class="row"><div style="flex:1"><label for="pp_price">${esc(T('price'))}</label><input id="pp_price" inputmode="decimal" autocomplete="off"></div>
      <div style="flex:1"><label for="pp_unit">${esc(T('unit'))}</label><select id="pp_unit"><option value="">${esc(T('baseUnit'))}</option>${unitOpts().map((r) => `<option value="${esc(r.value_code)}">${esc(lab({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined }))}</option>`).join('')}</select></div></div>
    <div><label for="pp_from">${esc(T('validFrom'))}</label><input id="pp_from" type="date" value="${esc(today())}"></div><div><label for="pp_note">${esc(T('note'))}</label><input id="pp_note" maxlength="300" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="pr_pgo">${esc(T('save'))}</button></div></div>`);
}
function linkSheet(preItem) {
  openSheet(`<h2>${esc(T('manageLinks'))}</h2><div class="stack"><p class="muted">${esc(T('paperCode'))}</p>${itemFld('lk_item')}<div id="lk_cur" class="stack"></div>${supSel('lk_sup')}
    <div><label for="lk_rank">${esc(T('rank'))}</label><select id="lk_rank"><option value="preferred">${esc(T('preferred'))}</option><option value="alternative">${esc(T('alternative'))}</option></select></div>
    <div><label for="lk_note">${esc(T('note'))}</label><input id="lk_note" maxlength="300" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="pr_lgo">${esc(T('addLink'))}</button></div></div>`);
  if (preItem) { const i = D.items.find((x) => x.id === preItem); const e = $('#lk_item'); if (e && i) { e.value = itemText(i); showLinks(); } }
}
async function showLinks() {
  const it = itemFrom(($('#lk_item') || {}).value), box = $('#lk_cur'); if (!box) return; if (!it) { box.innerHTML = ''; return; }
  const r = await sb.rpc('item_supplier_list', { p_item: it.id, p_supplier: null, p_all: false });
  box.innerHTML = r.error ? '' : (r.data || []).map((x) => `<div class="row between"><span>${esc(x.supplier)} · <span class="chip">${esc(T(x.rank))}</span></span>${x.can_edit ? `<button class="mini" data-act="pr_lret" data-v="${x.id}">${esc(T('retire'))}</button>` : ''}</div>`).join('');
}
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'lk_item') showLinks().catch(() => {}); });
async function reasonSheet(kind, id) {
  D.sheet = { kind, id };
  openSheet(`<h2>${esc(T('retire'))}</h2><div class="stack"><div><label for="rs_n">${esc(T('why'))}</label><input id="rs_n" maxlength="300" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="pr_rgo">${esc(T('retire'))}</button></div></div>`);
}
const act = async (p, ok) => { if (D.busy) return; D.busy = true; try { const r = await p; if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); await ok(r.data || {}); } catch (e) { fail(e); } finally { D.busy = false; } };

Object.assign(H, {
  pur_tab: (a) => { D.tab = a.dataset.v; frame(); },
  pr_show: () => { D.from = ($('#pr_from') || {}).value || D.from; D.to = ($('#pr_to') || {}).value || D.to; D.loc = ($('#pr_loc') || {}).value || ''; D.sup = ($('#pr_sup') || {}).value || ''; run(); },
  pr_go: (a) => { location.hash = a.dataset.v; },
  pur_csv: (a) => exportCSV(a.dataset.k, a.dataset.n + `-${D.from}_${D.to}`, csvRows(a.dataset.k)),
  pr_pnew: priceSheet,
  pr_pgo: () => {
    const it = itemFrom(($('#pp_item') || {}).value), sup = ($('#pp_sup') || {}).value, price = nnum(($('#pp_price') || {}).value);
    if (!it) return toast(T('item') + '?'); if (!sup) return toast(T('supplier') + '?'); if (!(price > 0)) return toast(lab(ERR.bad_price));
    return act(sb.rpc('supplier_price_set', { p_item: it.id, p_supplier: sup, p_price: price, p_unit: ($('#pp_unit') || {}).value || null, p_from: ($('#pp_from') || {}).value || null, p_note: (($('#pp_note') || {}).value || '').trim() || null }), () => run());
  },
  pr_pret: (a) => reasonSheet('price', a.dataset.v),
  pr_lnew: () => linkSheet(null),
  pr_dep: (a) => { const r = ((D.data.dep || {}).rows || [])[Number(a.dataset.i)]; if (!r) return;
    openSheet(`<h2>${esc(r.code)} · ${esc(nm(r))}</h2><div class="stack"><b>${esc(T('used'))}</b>${(r.used || []).map((u) => `<div class="row between"><span>${esc(u.supplier)}${u.declared ? '' : ` <span class="chip warn">${esc(T('fl_used_supplier_not_declared'))}</span>`}</span><span>${u.share_pct}% · ${q4(u.qty)}${u.value !== null && u.value !== undefined ? ' · ' + money(u.value) : ''}</span></div>`).join('')}
      ${D.canTerms ? `<button class="full" data-act="pr_lnew_i" data-v="${esc(r.item_id)}">${esc(T('manageLinks'))}</button>` : ''}<button class="full" data-act="closesheet">${esc(T('cancel'))}</button></div>`); },
  pr_lnew_i: (a) => { closeSheet(); linkSheet(a.dataset.v); },
  pr_lgo: () => {
    const it = itemFrom(($('#lk_item') || {}).value), sup = ($('#lk_sup') || {}).value; if (!it) return toast(T('item') + '?'); if (!sup) return toast(T('supplier') + '?');
    return act(sb.rpc('item_supplier_set', { p_item: it.id, p_supplier: sup, p_rank: ($('#lk_rank') || {}).value, p_note: (($('#lk_note') || {}).value || '').trim() || null }), () => run());
  },
  pr_lret: (a) => reasonSheet('link', a.dataset.v),
  pr_rgo: () => {
    const n = (($('#rs_n') || {}).value || '').trim(); if (n.length < 3) return toast(lab(ERR.note_required)); const s = D.sheet;
    return act(sb.rpc(s.kind === 'price' ? 'supplier_price_retire' : 'item_supplier_retire', { p_id: Number(s.id), p_note: n }), () => run());
  },
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  try { D.locs = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : []; } catch (e) { D.locs = []; }
  if (!(S.ctx.is_owner || (S.ctx.roles || []).includes('management'))) D.locs = D.locs.filter((l) => (S.ctx.locations || []).includes(l.id));
  const [s, i] = await Promise.all([sb.from('suppliers').select('id,name,active').order('name'), window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,is_active,hidden').order('code'))]);
  D.sups = (s.data || []).filter((x) => x.active !== false); D.items = i.error ? [] : (i.data || []).filter((x) => x.is_active !== false && !x.hidden);
  D.canTerms = !!(B.s2 && B.s2.grant && await B.s2.grant('supplier_terms_manage', null));
  D.from = D.from || new Date(Date.now() + 6 * 3600e3 - 30 * 864e5).toISOString().slice(0, 10); D.to = D.to || today();
  frame();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { purchrep: view });
})();
