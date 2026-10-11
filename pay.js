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
const X = {
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
  cur: null, loadWallets, resetWallets() { wallets = null; },
  // st = { rows, getTotal(), onChange() }
  create(getTotal, onChange) {
    const st = { rows: [{ mode: 'cash', amount: '', wallet: '', ref: '', given: '', auto: true }], getTotal, onChange: onChange || (() => {}) };
    pay.syncAuto(st); return st;
  },
  paid: (st) => r2(st.rows.reduce((s, r) => s + r2(nnum(r.amount)), 0)),
  due: (st) => r2(st.getTotal() - pay.paid(st)),
  syncAuto(st) { if (st.rows.length === 1 && st.rows[0].auto) st.rows[0].amount = String(r2(st.getTotal())); },
  list(st) { return st.rows.filter((r) => r2(nnum(r.amount)) > 0).map((r) => ({ mode: r.mode, amount: r2(nnum(r.amount)), wallet: r.mode === 'mobile' ? r.wallet : undefined, ref: r.mode === 'mobile' && r.ref ? r.ref : undefined,
    tendered: r.mode === 'cash' && nnum(r.given) > 0 ? r2(nnum(r.given)) : undefined })); },
  // returns an error key (string) or null
  check(st) {
    const tot = st.getTotal();
    if (pay.paid(st) > tot + 0.001) return 'overpaid';
    for (const r of st.rows) { if (nnum(r.amount) > 0 && r.mode === 'mobile' && !r.wallet) return 'wallet_needed'; }
    return null;
  },
  html(st) {
    pay.cur = st;
    const w = wallets || WALLET_FALLBACK, tot = st.getTotal(), paid = pay.paid(st), due = r2(tot - paid);
    const single = st.rows.length === 1 && st.rows[0].mode === 'cash';
    const rows = st.rows.map((r, i) => `<div class="payrow"><div class="row between"><b>${esc(lab((MODES.find((m) => m[0] === r.mode) || [])[1]))}</b>
        <button type="button" class="mini" data-act="pay_del" data-i="${i}" aria-label="x">✕</button></div>
      <div class="row"><div style="flex:1"><label>${esc(T('amount'))} (৳)</label><input data-pay="${i}.amount" inputmode="decimal" value="${esc(r.amount)}"></div>
        ${r.mode === 'cash' && single ? `<div style="flex:1"><label>${esc(T('given'))} (৳)</label><input data-pay="${i}.given" inputmode="decimal" value="${esc(r.given)}"></div>` : ''}</div>
      ${r.mode === 'mobile' ? `<div class="row"><div style="flex:1"><label>${esc(T('wallet'))}</label><select data-pay="${i}.wallet"><option value="">${esc(T('pickWallet'))}</option>${w.map(([c, l]) => `<option value="${esc(c)}" ${r.wallet === c ? 'selected' : ''}>${esc(lab(l))}</option>`).join('')}</select></div>
        <div style="flex:1"><label>${esc(T('ref'))}</label><input data-pay="${i}.ref" value="${esc(r.ref)}"></div></div>` : ''}</div>`).join('');
    return `<div id="pay_box">${rows}<div class="row wrap" style="margin:8px 0">${MODES.map(([m, l]) => `<button type="button" class="tog" data-act="pay_add" data-m="${m}">＋ ${esc(lab(l))}</button>`).join('')}
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
    st.rows.push({ mode: a.dataset.m, amount: rest ? String(rest) : '', wallet: '', ref: '', given: '', auto: false });
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
})();
