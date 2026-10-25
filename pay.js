/* Islamia BOS · payment rows: cash / mobile / card, split and partial payment (the rest stays due).
   One shared component for the sale screen and for collecting dues. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, fmt } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const nnum = (v) => { const n = Number(norm(v).trim()); return Number.isFinite(n) ? n : 0; };
const r2 = (n) => Math.round(n * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(n));

const MODES = [['cash', L('নগদ', 'Cash', 'Cash')], ['mobile', L('মোবাইল ব্যাংকিং', 'Mobile', 'Mobile')], ['card', L('কার্ড', 'Card', 'Card')]];
// W1-F (phase97): customer receipts by bank transfer and by cheque. Offered ONLY on a payment state flagged st.receipt (POS, dues) and ONLY when the owner has switched receipt_bank_on ON
// (read once from _w1f_receipt_settings; a database without phase 97 answers nothing and the old three modes stay). A cheque is mode 'bank' with cheque_no / cheque_date.
const BANK_MODES = [['bank', L('ব্যাংক ট্রান্সফার', 'Bank transfer', 'Bank transfer')], ['cheque', L('চেক', 'Cheque', 'Cheque')]];
const RC = { bank_on: false, ref_required: 'off', loaded: false };
B.receiptCfg = RC;
async function loadReceiptCfg() {
  if (RC.loaded) return RC; RC.loaded = true;
  try { const r = await sb.rpc('_w1f_receipt_settings', {}); if (!r.error && r.data) { RC.bank_on = r.data.bank_on === true; RC.ref_required = r.data.ref_required || 'off'; } } catch (e) { /* no phase 97: the old modes only */ }
  return RC;
}
const X = {
  chq: L('চেক নম্বর', 'Cheque no.', 'Cheque no.'), chqd: L('চেকের ডেট', 'Cheque date', 'Cheque date'), refb: L('ট্রানজেকশন / স্লিপ নং', 'Transaction / slip no.', 'Transaction / slip no.'),
  why: L('নম্বর না থাকলে কারণ (ঐচ্ছিক)', 'Reason if the number is missing (optional)', 'Number না থাকলে reason (ঐচ্ছিক)'),
  paid: L('পরিশোধ', 'Paid', 'Paid'), due: L('বাকি', 'Due', 'Due (বাকি)'), amount: L('টাকা', 'Amount', 'Amount'), wallet: L('কোন মাধ্যম', 'Which service', 'Which service'),
  ref: L('ট্রানজেকশন নং (ঐচ্ছিক)', 'Transaction no. (optional)', 'Transaction no. (ঐচ্ছিক)'), given: L('গ্রাহক দিলেন', 'Customer gave', 'Customer দিলেন'), change: L('ফেরত', 'Change', 'Change (ফেরত)'),
  add: L('পেমেন্ট যোগ', 'Add payment', 'Payment যোগ'), onCredit: L('সব বাকি', 'All on credit', 'সব Due'), pickWallet: L('— বাছুন —', '— choose —', '— বাছুন —'), short: L('কম', 'short', 'কম'),
};
const T = (k) => lab(X[k]);

// wallets (bKash / Nagad ...) come from the editable list "wallets"; the built-in names are the fallback
const WALLET_FALLBACK = [['bkash', L('বিকাশ', 'bKash')], ['nagad', L('Nagad (নগদ)', 'Nagad')], ['rocket', L('রকেট', 'Rocket')], ['upay', L('উপায়', 'Upay')]];
let wallets = null;
async function loadWallets() {
  if (wallets) return wallets;
  const r = await sb.from('option_lists').select('value_code,label_bn,label_mix,label_en,sort,active').eq('list_code', 'wallets').order('sort');
  const act = !r.error && r.data ? r.data.filter((x) => x.active) : [];
  wallets = act.length ? act.map((x) => [x.value_code, { bn: x.label_bn, mix: x.label_mix, en: x.label_en }]) : WALLET_FALLBACK;
  return wallets;
}

const pay = {
  cur: null, loadWallets, resetWallets() { wallets = null; }, loadReceiptCfg,
  // flag a state as a customer receipt (POS: 'pos_split_payment', dues: 'customer_collection'): bank and cheque rows and the payment source appear when receipt_bank_on is ON
  receipt(st, event) { st.receipt = true; st.receiptEvent = event; loadReceiptCfg().then((c) => { if (c.bank_on) { if (B.moneySrc) B.moneySrc.prefetch(event, null); if (pay.cur === st && $('#pay_box')) pay.redraw(); } }); return st; },
  modes(st) { return st && st.receipt && RC.bank_on ? MODES.concat(BANK_MODES) : MODES; },
  // st = { rows, getTotal(), onChange() }
  create(getTotal, onChange) {
    const st = { rows: [{ mode: 'cash', amount: '', wallet: '', ref: '', given: '', auto: true }], getTotal, onChange: onChange || (() => {}) };
    pay.syncAuto(st); return st;
  },
  paid: (st) => r2(st.rows.reduce((s, r) => s + r2(nnum(r.amount)), 0)),
  due: (st) => r2(st.getTotal() - pay.paid(st)),
  syncAuto(st) { if (st.rows.length === 1 && st.rows[0].auto) st.rows[0].amount = String(r2(st.getTotal())); },
  list(st) { return st.rows.filter((r) => r2(nnum(r.amount)) > 0).map((r) => ({ mode: r.mode, amount: r2(nnum(r.amount)), wallet: (B.moneySrc ? B.moneySrc.taggedWallet(r.macc, r.mode === 'mobile' ? r.wallet : '') : (r.mode === 'mobile' ? r.wallet : '')) || undefined, ref: (r.mode === 'mobile' || (r.mode === 'bank' && r.ch !== 'cheque')) && r.ref ? r.ref : undefined,
    tendered: r.mode === 'cash' && nnum(r.given) > 0 ? r2(nnum(r.given)) : undefined,
    cheque_no: r.mode === 'bank' && r.ch === 'cheque' && String(r.cheque_no || '').trim() ? String(r.cheque_no).trim() : undefined, cheque_date: r.mode === 'bank' && r.ch === 'cheque' && r.cheque_date ? r.cheque_date : undefined,
    exception_reason: r.mode === 'bank' && String(r.exception_reason || '').trim() ? String(r.exception_reason).trim() : undefined })); },
  // returns an error key (string) or null
  check(st) {
    const tot = st.getTotal();
    if (pay.paid(st) > tot + 0.001) return 'overpaid';
    for (const r of st.rows) { if (nnum(r.amount) > 0 && r.mode === 'mobile' && !r.wallet && !r.macc) return 'wallet_needed'; }
    return null;
  },
  html(st) {
    pay.cur = st;
    const w = wallets || WALLET_FALLBACK, tot = st.getTotal(), paid = pay.paid(st), due = r2(tot - paid), mset = pay.modes(st), mev = st.moneyEvent || (st.receipt && RC.bank_on ? st.receiptEvent : null);
    const rowName = (r) => lab(r.mode === 'bank' && r.ch === 'cheque' ? BANK_MODES[1][1] : ((mset.find((m) => m[0] === r.mode) || [])[1]));
    const single = st.rows.length === 1 && st.rows[0].mode === 'cash';
    const rows = st.rows.map((r, i) => `<div class="payrow"><div class="row between"><b>${esc(rowName(r))}</b>
        <button type="button" class="mini" data-act="pay_del" data-i="${i}" aria-label="x">✕</button></div>
      <div class="row"><div style="flex:1"><label>${esc(T('amount'))} (৳)</label><input data-pay="${i}.amount" inputmode="decimal" value="${esc(r.amount)}"></div>
        ${r.mode === 'cash' && single ? `<div style="flex:1"><label>${esc(T('given'))} (৳)</label><input data-pay="${i}.given" inputmode="decimal" value="${esc(r.given)}"></div>` : ''}</div>
      ${mev && B.moneySrc ? B.moneySrc.rowSelect(mev, i, r.macc, r) : ''}
      ${st.receipt && r.mode === 'bank' ? (r.ch === 'cheque'
        ? `<div class="row"><div style="flex:1"><label>${esc(T('chq'))}</label><input data-pay="${i}.cheque_no" value="${esc(r.cheque_no || '')}"></div><div style="flex:1"><label>${esc(T('chqd'))}</label><input type="date" data-pay="${i}.cheque_date" value="${esc(r.cheque_date || '')}"></div></div>`
        : `<div><label>${esc(T('refb'))}</label><input data-pay="${i}.ref" value="${esc(r.ref || '')}"></div>`) + `<div><label>${esc(T('why'))}</label><input data-pay="${i}.exception_reason" value="${esc(r.exception_reason || '')}"></div>` : ''}
      ${r.mode === 'mobile' && !r.macc ? `<div class="row"><div style="flex:1"><label>${esc(T('wallet'))}</label><select data-pay="${i}.wallet"><option value="">${esc(T('pickWallet'))}</option>${w.map(([c, l]) => `<option value="${esc(c)}" ${r.wallet === c ? 'selected' : ''}>${esc(lab(l))}</option>`).join('')}</select></div>
        <div style="flex:1"><label>${esc(T('ref'))}</label><input data-pay="${i}.ref" value="${esc(r.ref)}"></div></div>` : ''}</div>`).join('');
    return `<div id="pay_box">${rows}<div class="row wrap" style="margin:8px 0">${mset.map(([m, l]) => `<button type="button" class="tog" data-act="pay_add" data-m="${m}">＋ ${esc(lab(l))}</button>`).join('')}
        <button type="button" class="tog ${st.rows.length === 0 ? 'on' : ''}" data-act="pay_credit">${esc(T('onCredit'))}</button></div>
      <div id="pay_sum">${pay.sumHTML(st)}</div></div>`;
  },
  sumHTML(st) {
    const tot = st.getTotal(), paid = pay.paid(st), due = r2(tot - paid);
    const single = st.rows.length === 1 && st.rows[0].mode === 'cash', given = single ? nnum(st.rows[0].given) : 0, cashAmt = single ? r2(nnum(st.rows[0].amount)) : 0;
    return `<div class="row between"><span>${esc(T('paid'))}</span><b>${money(paid)}</b></div>
      <div class="row between"><span>${esc(T('due'))}</span><b style="${due > 0 ? 'color:var(--ruby)' : due < 0 ? 'color:#b3121f' : ''}">${money(Math.max(due, 0))}${due < 0 ? ' ✖' : ''}</b></div>
      ${given > 0 && given >= cashAmt ? `<div class="notice ok">${esc(T('change'))}: ${money(given - cashAmt)}</div>` : given > 0 ? `<div class="notice bad">− ${money(cashAmt - given)}</div>` : ''}`;
  },
  redraw() { const st = pay.cur; const el = $('#pay_box'); if (!st || !el) return; el.outerHTML = pay.html(st); st.onChange(); },
  refreshSum() { const st = pay.cur; const el = $('#pay_sum'); if (st && el) el.innerHTML = pay.sumHTML(st); if (st) st.onChange(); },
};
B.pay = pay;

Object.assign(A.H, {
  pay_add: (a) => { const st = pay.cur; const rest = Math.max(0, r2(st.getTotal() - pay.paid(st)));
    if (st.rows.length === 1 && st.rows[0].auto) { st.rows[0].auto = false; if (!(nnum(st.rows[0].amount) > 0)) st.rows[0].amount = ''; }
    st.rows.push({ mode: a.dataset.m === 'cheque' ? 'bank' : a.dataset.m, ...(a.dataset.m === 'cheque' ? { ch: 'cheque' } : {}), amount: rest ? String(rest) : '', wallet: '', ref: '', given: '', auto: false });
    if (st.rows.length === 2 && st.rows[0].auto === false && nnum(st.rows[0].amount) === r2(st.getTotal())) { st.rows[0].amount = ''; st.rows[1].amount = String(r2(st.getTotal())); }
    pay.redraw(); },
  pay_del: (a) => { const st = pay.cur; st.rows.splice(Number(a.dataset.i), 1); if (st.rows.length === 1) st.rows[0].auto = false; pay.redraw(); },
  pay_credit: () => { const st = pay.cur; st.rows = []; pay.redraw(); },
});
document.addEventListener('input', (e) => {
  const k = e.target.dataset && e.target.dataset.pay; if (!k || !pay.cur) return;
  const [i, f] = k.split('.'); const r = pay.cur.rows[Number(i)]; if (!r) return;
  r[f] = e.target.value; if (f === 'amount') r.auto = false;
  pay.refreshSum();
});
document.addEventListener('change', (e) => {
  const k = e.target.dataset && e.target.dataset.pay; if (!k || !pay.cur) return;
  const [i, f] = k.split('.'); const r = pay.cur.rows[Number(i)]; if (r) { r[f] = e.target.value; pay.refreshSum(); }
});
// shared list control on every wallet picker this file draws (POS, dues, purchase payments): + Add new follows the list's rule, "Other" keeps the old value and the words go to the Other queue
const wireWallets = (root) => {
  const lc = B.listctl; if (!lc || !root || !root.querySelectorAll) return;
  root.querySelectorAll('select[data-pay$=".wallet"]').forEach((sel) => { if (!sel.dataset.lpid) lc.enhance(sel, 'wallets', { keepPrev: true, form: 'PAYMENT', ctx: { field: 'wallet' } }); });
};
pay.wire = wireWallets;
try {
  new MutationObserver((ms) => { for (const m of ms) m.addedNodes.forEach((n) => { if (n.nodeType === 1) wireWallets(n.matches && n.matches('select[data-pay]') ? n.parentNode : n); }); }).observe(document.documentElement, { childList: true, subtree: true });
} catch (e) { /* no observer: the plain wallet select stays */ }
})();
