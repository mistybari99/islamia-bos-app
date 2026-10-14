/* Islamia BOS · Stock guards page (#/guards, owner). Server side: supabase/phase82.sql.
   Reads guard_recommendations() / unit_unknown_items() / never_opened_negative_items() / grn_pending_report(); writes only through set_rule (the owner taps
   "apply recommended"; nothing is forced). Also exports BOS.guardMsg(code) = the 3-language text of the new error codes. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('স্টক গার্ড ও প্রস্তাবিত সেটিং', 'Stock guards & recommended settings', 'Stock guard ও recommended setting'),
  intro: L('প্রতিটি সুইচের বর্তমান মান ও প্রস্তাবিত মান দেখুন। প্রস্তাব মানা বাধ্যতামূলক নয়; চাপলে তবেই বদলায়।', 'See each switch, its current value and the recommended one. Nothing is forced; it changes only when you tap apply.', 'প্রতিটি switch-এর current ও recommended মান দেখুন। কিছু forced নয়; apply চাপলে তবেই বদলায়।'),
  cur: L('এখন', 'Now', 'Now'), rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'), apply: L('প্রস্তাবিত প্রয়োগ', 'Apply recommended', 'Recommended apply'),
  ok: L('ঠিক আছে ✓', 'Already set ✓', 'Already set ✓'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  unit: L('এককের conversion নেই (tracked পণ্য)', 'Tracked items with no unit conversion', 'Unit conversion নেই (tracked item)'),
  neg: L('opening ছাড়া negative stock', 'Negative stock that was never opened', 'Opening ছাড়া negative stock'),
  nobill: L('বিল-বিহীন রিসিভ (GRN)', 'Receives with no bill (GRN)', 'বিল-বিহীন receive (GRN)'),
  nogrn: L('GRN-বিহীন bill', 'Bills with no GRN', 'GRN-বিহীন bill'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
};
const T = (k) => lab(X[k]);
/* error codes of phase82 -> text in the 3 languages (English text has no Bangla letters) */
const ERR = {
  grn_link_required: L('GRN source চালু: এই bill-এর সাথে GRN জুড়ুন, তারপর post করুন', 'GRN is the stock source: link this bill to its GRN before posting', 'GRN source চালু: bill-এর সাথে GRN জুড়ে তারপর post করুন'),
  void_has_return: L('এই bill-এর বিপরীতে return আছে; আগে return বাতিল করুন', 'A posted return refers to this bill; void the return first', 'এই bill-এর return আছে; আগে return void করুন'),
  void_would_go_negative: L('মাল ব্যবহার/বিক্রি হয়ে গেছে, bill বাতিল করলে stock negative হবে', 'The goods were used or sold; voiding would make stock negative', 'মাল use/sale হয়ে গেছে, void করলে stock negative হবে'),
  void_has_grn_batch: L('এই bill-এর চালু GRN batch আছে', 'Live GRN batches exist for this bill', 'এই bill-এর live GRN batch আছে'),
  unit_unknown: L('এককের conversion জানা নেই; conversion বসান বা base unit-এ বিক্রি করুন', 'The unit conversion is unknown; add it or sell in the base unit', 'Unit conversion জানা নেই; conversion বসান বা base unit-এ sell করুন'),
  production_negative_reason_needed: L('stock-এর বেশি কাঁচামাল নিতে কারণ লিখুন', 'Write a reason to use more ingredient than the stock on hand', 'Stock-এর বেশি ingredient নিতে reason লিখুন'),
};
B.guardMsg = (code) => (ERR[code] ? lab(ERR[code]) : null);
B.guardErrCodes = Object.keys(ERR);
const NAMES = { production_requires_recipe: ['Recipe ছাড়া production', 'Production without a recipe'], production_double_issue_guard: ['উৎপাদন ও issue-তে দুবার কাটা', 'Double deduction (production + issue)'], production_requires_cost: ['Cost অজানা থাকলে production', 'Production with an unknown cost'], purchase_grn_guard: ['GRN উৎস হলে bill-এর stock', 'Bill stock when GRN is the source'], purchase_void_guard: ['Posted bill বাতিলে সুরক্ষা', 'Voiding a posted bill'], purchase_void_payments: ['Bill বাতিলে payment', 'Payments on a voided bill'],
  unit_conv_required: ['Conversion ছাড়া বিক্রি', 'Sale without unit conversion'], neg_grant_log: ['Below-zero permission log', 'Log of the below-zero permission'], production_negative_reason: ['Production negative-এ reason', 'Reason when production goes negative'], stock_negative_mode: ['Stock-এর বেশি বিক্রি', 'Selling above stock'] };
const D = { rec: [], unit: null, neg: null, pend: null };
const val = (v) => (v === null || v === undefined ? '-' : String(v));
function list(arr, f) { return arr.length ? arr.map(f).join('') : `<div class="muted">${esc(T('none'))}</div>`; }
function draw() {
  const el = $('#gd_body'); if (!el) return;
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>` + D.rec.map((r) => {
    const same = JSON.stringify(r.current) === JSON.stringify(r.recommended), n = NAMES[r.key] || [lab(L('নিয়ম', 'Rule', 'Rule')) + ' #' + (D.rec.indexOf(r) + 1), lab(L('নিয়ম', 'Rule', 'Rule')) + ' #' + (D.rec.indexOf(r) + 1)]; /* bos108: no raw key as a title */
    return `<div class="card stack"><b>${esc(lab({ bn: n[0], mix: n[0], en: n[1] }))}</b><div class="row wrap"><span class="chip">${esc(T('cur'))}: ${esc(val(r.current))}</span><span class="chip ${same ? '' : 'warn'}">${esc(T('rec'))}: ${esc(val(r.recommended))}</span></div>
      <div class="muted" style="font-size:.85rem">${esc(lab({ bn: r.reason_bn, mix: r.reason_mix, en: r.reason_en }))}</div>
      ${same ? `<span class="chip">${esc(T('ok'))}</span>` : `<button type="button" class="btn primary" data-act="gd_apply" data-k="${esc(r.key)}">${esc(T('apply'))}</button>`}</div>`;
  }).join('') + `<div class="card stack"><b>${esc(T('unit'))} (${D.unit.count})</b>${list(D.unit.items, (i) => `<div>${esc(i.code)} · ${esc(i.unit)} → ${esc(i.base_unit)}</div>`)}</div>
    <div class="card stack"><b>${esc(T('neg'))} (${D.neg.count})</b>${list(D.neg.items, (i) => `<div>${esc(i.code)} · ${esc(String(i.qty))}</div>`)}</div>
    <div class="card stack"><b>${esc(T('nobill'))} (${D.pend.receipts_without_bill.length})</b>${list(D.pend.receipts_without_bill, (i) => `<div>${esc(i.date)} · ${esc(i.supplier || '')}</div>`)}</div>
    <div class="card stack"><b>${esc(T('nogrn'))} (${D.pend.bills_without_receipt.length})</b>${list(D.pend.bills_without_receipt, (i) => `<div>${esc(i.date)} · ${esc(i.bill_no || '')}</div>`)}</div>`;
}
async function load() {
  const [a, b, c, d] = await Promise.all([sb.rpc('guard_recommendations'), sb.rpc('unit_unknown_items'), sb.rpc('never_opened_negative_items'), sb.rpc('grn_pending_report', { p_days: 60 })]);
  for (const r of [a, b, c, d]) if (r.error) throw r.error;
  D.rec = a.data || []; D.unit = b.data; D.neg = c.data; D.pend = d.data;
  try { const p = await sb.rpc('production_recommendations'); if (!p.error && Array.isArray(p.data)) D.rec = D.rec.concat(p.data); } catch (e) { /* phase87 not pasted yet: the page works without the production rows */ }
}
Object.assign(H, {
  gd_apply: async (a) => {
    const r = D.rec.find((x) => x.key === a.dataset.k); if (!r) return;
    const s = await sb.rpc('set_rule', { p_key: r.key, p_value: r.recommended }); if (s.error) return fail(s.error);
    toast(T('saved')); try { await load(); draw(); } catch (e) { fail(e); }
  },
});
async function viewGuards() {
  shell(T('title'), '<div id="gd_body"><p class="muted">…</p></div>', true);
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { guards: viewGuards });
})();
