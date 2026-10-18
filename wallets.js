/* Islamia BOS · Mobile wallets (#/wallets): a balance for every wallet (bKash, Nagad, Rocket and others), the wallet fee as its own expense,
   money moved between a wallet and cash / bank / another wallet, and the 10-3 reconcile (phone total typed FIRST, the book figure and the difference are shown after saving).
   Server: supabase/phase83.sql (d_wallet_balances, d_wallet_fee_add, d_wallet_move_add, d_wallet_check_save, d_wallet_check_explain, d_wallet_recon_report). Nothing is deleted:
   a wrong fee or move is voided with a reason (the server keeps it). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('মোবাইল ওয়ালেট', 'Mobile wallets', 'Mobile ওয়ালেট'),
  loc: L('জায়গা', 'Location', 'Location'), wallet: L('ওয়ালেট', 'Wallet', 'Wallet'), amount: L('টাকা', 'Amount', 'Amount'), date: L('তারিখ', 'Date', 'Date'),
  ref: L('ট্রানজেকশন নম্বর', 'Transaction ID', 'Transaction ID'), note: L('নোট', 'Note', 'Note'), save: L('সংরক্ষণ', 'Save', 'Save'),
  bal: L('ওয়ালেটের জের', 'Wallet balances', 'Wallet জের'), book: L('খাতায় জের', 'Book balance', 'খাতায় জের'), jr: L('খতিয়ানে', 'In the ledger', 'Ledger-এ'),
  hidden: L('গোনার পর দেখা যাবে', 'Shown after you count', 'গোনার পর দেখা যাবে'), counted: L('গোনা হয়েছে', 'Counted', 'গোনা হয়েছে'),
  count: L('ফোনের জের মেলান (১০-৩)', 'Reconcile the phone balance (10-3)', 'Phone-এর জের মেলান (10-3)'),
  countHint: L('আগে ফোনে যে টাকা দেখাচ্ছে সেটা লিখুন। খাতার অঙ্ক সংরক্ষণের পরে দেখা যাবে।', 'Type the balance shown on the phone first. The book figure is shown after you save.', 'আগে phone-এর balance লিখুন। Book figure save-এর পরে দেখা যাবে।'),
  phone: L('ফোনে দেখাচ্ছে', 'Balance on the phone', 'Phone-এ দেখাচ্ছে'), diff: L('পার্থক্য', 'Difference', 'পার্থক্য'), matched: L('মিলেছে', 'Matched', 'মিলেছে'),
  mismatch: L('মেলেনি — কারণ লিখুন', 'Does not match - write the reason', 'মেলেনি — কারণ লিখুন'), reason: L('কারণ', 'Reason', 'কারণ'), explained: L('কারণ লেখা হয়েছে', 'Reason written', 'কারণ লেখা হয়েছে'),
  fee: L('ওয়ালেট ফি (আলাদা খরচ)', 'Wallet fee (its own expense)', 'Wallet fee (আলাদা expense)'), kind: L('ধরন', 'Kind', 'Kind'),
  move: L('ওয়ালেটে টাকা আনা / নেওয়া', 'Move money in or out of a wallet', 'Wallet-এ টাকা আনা / নেওয়া'), dir: L('দিক', 'Direction', 'Direction'),
  din: L('ওয়ালেটে ঢুকল', 'Into the wallet', 'Wallet-এ ঢুকল'), dout: L('ওয়ালেট থেকে বের হলো', 'Out of the wallet', 'Wallet থেকে বের'),
  counter: L('অপর পাশ', 'Other side', 'অপর পাশ'), cash: L('নগদ', 'Cash', 'Cash'), bank: L('ব্যাংক', 'Bank', 'Bank'), other: L('অন্য ওয়ালেট', 'Another wallet', 'অন্য wallet'),
  cwallet: L('অন্য ওয়ালেট কোনটি', 'Which other wallet', 'কোন wallet'),
  unas: L('ওয়ালেটের নাম চেনা যায়নি এমন মোবাইল টাকা', 'Mobile money whose wallet name is not recognised', 'Wallet চেনা যায়নি এমন mobile টাকা'),
  saved: L('সংরক্ষিত', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), noperm: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'),
  warn: L('সতর্কতা: ওয়ালেটের জের শূন্যের নিচে যাবে', 'Warning: the wallet balance goes below zero', 'Warning: wallet জের শূন্যের নিচে'),
};
const KINDS = [['cash_out', L('ক্যাশ আউট', 'Cash out')], ['send_money', L('সেন্ড মানি', 'Send money')], ['merchant', L('মার্চেন্ট পেমেন্ট', 'Merchant payment')], ['payment', L('পেমেন্ট', 'Payment')], ['other', L('অন্য', 'Other')]];
const T = (k) => lab(X[k]);
const ERR = {
  wallet_negative: L('ওয়ালেটে এত টাকা নেই (জের শূন্যের নিচে যেত)', 'The wallet does not hold that much (balance would go below zero)'),
  wallet_mismatch: L('অপর ওয়ালেট ঠিক নয়', 'The other wallet does not fit the choice'),
  bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid'), bad_date: L('তারিখ ঠিক নয়', 'Date is not valid'), period_locked: L('এই মাস বন্ধ', 'This period is locked'),
  reason_required: L('কারণ লিখুন', 'Write a reason'), not_allowed: X.noperm, wallet_not_found: L('ওয়ালেট পাওয়া যায়নি', 'Wallet not found'),
  nothing_to_explain: L('এখানে কারণ লেখার কিছু নেই', 'Nothing to explain here'), client_id_taken: L('এটি আগেই সংরক্ষিত', 'Already saved'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x) || m.includes(x.replace('_', ' '))); return k ? lab(ERR[k]) : m || 'error'; };
const D = { loc: null, date: today(), wallets: [], recon: null, last: null, client: { fee: rid(), move: rid(), check: rid() } };

async function load() {
  const [b, r] = await Promise.all([sb.rpc('d_wallet_balances', { p_asof: D.date }), sb.rpc('d_wallet_recon_report', { p_date: D.date, p_loc: D.loc })]);
  if (b.error) throw b.error;
  D.wallets = b.data || []; D.recon = r.error ? null : r.data;
}
const wopts = (exclude) => D.wallets.filter((w) => w.active !== false && w.wallet_id !== exclude).map((w) => `<option value="${w.wallet_id}">${esc(lab(L(w.name_bn, w.name_en, w.name_en)))}</option>`).join('');
function balHTML() {
  if (!D.wallets.length) return `<p class="muted">${esc(T('none'))}</p>`;
  const rc = D.recon && D.recon.wallets ? D.recon.wallets : [];
  const rows = D.wallets.map((w) => {
    const r = rc.find((x) => x.wallet_id === w.wallet_id) || {};
    const book = w.book === null || w.book === undefined ? `<span class="muted">${esc(T('hidden'))}</span>` : `<b>${money(w.book)}</b>`;
    const jr = w.journal === null || w.journal === undefined ? '' : `<div class="muted">${esc(T('jr'))}: ${money(w.journal)}${Number(w.journal_gap) ? ` · <span class="chip warn">${money(w.journal_gap)}</span>` : ''}</div>`;
    const st = r.status === 'matched' ? `<span class="chip ok">${esc(T('matched'))}</span>` : r.status === 'difference' ? `<span class="chip warn">${esc(T('diff'))} ${money(r.diff)}</span>` : r.status === 'explained' ? `<span class="chip">${esc(T('explained'))} · ${money(r.diff)}</span>` : '';
    return `<div class="card"><div class="row between"><b>${esc(lab(L(w.name_bn, w.name_en, w.name_en)))}</b>${book}</div>${jr}${st ? `<div>${st}</div>` : ''}</div>`;
  }).join('');
  const un = D.recon && Number(D.recon.unassigned_mobile) ? `<p class="muted">${esc(T('unas'))}: <b>${money(D.recon.unassigned_mobile)}</b></p>` : '';
  return rows + un;
}
function countHTML() {
  return `<div class="card stack"><b>${esc(T('count'))}</b><p class="muted">${esc(T('countHint'))}</p>
    <div><label for="wl_cw">${esc(T('wallet'))}</label><select id="wl_cw">${wopts()}</select></div>
    <div><label for="wl_cp">${esc(T('phone'))}</label><input id="wl_cp" inputmode="decimal" autocomplete="off"></div>
    <button class="full primary" data-act="wl_count">${esc(T('save'))}</button><div id="wl_cout"></div></div>`;
}
function countResult(r) {
  const el = $('#wl_cout'); if (!el) return;
  D.last = r;
  if (r.status === 'matched') { el.innerHTML = `<div class="chip ok">${esc(T('matched'))} · ${esc(T('book'))} ${money(r.book)}</div>`; return; }
  el.innerHTML = `<div class="chip warn">${esc(T('book'))} ${money(r.book)} · ${esc(T('diff'))} ${money(r.diff)}</div><p>${esc(T('mismatch'))}</p>
    <input id="wl_rs" autocomplete="off" aria-label="${esc(T('reason'))}"><button class="full" data-act="wl_explain" data-v="${esc(r.id)}">${esc(T('save'))}</button>`;
}
function feeHTML() {
  return `<div class="card stack"><b>${esc(T('fee'))}</b>
    <div><label for="wl_fw">${esc(T('wallet'))}</label><select id="wl_fw">${wopts()}</select></div>
    <div><label for="wl_fa">${esc(T('amount'))}</label><input id="wl_fa" inputmode="decimal" autocomplete="off"></div>
    <div><label for="wl_fk">${esc(T('kind'))}</label><select id="wl_fk">${KINDS.map(([k, l]) => `<option value="${k}">${esc(lab(l))}</option>`).join('')}</select></div>
    <div><label for="wl_fr">${esc(T('ref'))}</label><input id="wl_fr" autocomplete="off"></div>
    <button class="full primary" data-act="wl_fee">${esc(T('save'))}</button></div>`;
}
function moveHTML() {
  return `<div class="card stack"><b>${esc(T('move'))}</b>
    <div><label for="wl_mw">${esc(T('wallet'))}</label><select id="wl_mw">${wopts()}</select></div>
    <div><label for="wl_md">${esc(T('dir'))}</label><select id="wl_md"><option value="in">${esc(T('din'))}</option><option value="out">${esc(T('dout'))}</option></select></div>
    <div><label for="wl_mc">${esc(T('counter'))}</label><select id="wl_mc"><option value="cash">${esc(T('cash'))}</option><option value="bank">${esc(T('bank'))}</option><option value="wallet">${esc(T('other'))}</option></select></div>
    <div id="wl_mow" hidden><label for="wl_mo">${esc(T('cwallet'))}</label><select id="wl_mo">${wopts()}</select></div>
    <div><label for="wl_ma">${esc(T('amount'))}</label><input id="wl_ma" inputmode="decimal" autocomplete="off"></div>
    <div><label for="wl_mr">${esc(T('ref'))}</label><input id="wl_mr" autocomplete="off"></div>
    <button class="full primary" data-act="wl_move">${esc(T('save'))}</button></div>`;
}
function page() {
  const locs = LOCS();
  return `<div class="card stack">
    <div><label for="wl_loc">${esc(T('loc'))}</label><select id="wl_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="wl_date">${esc(T('date'))}</label><input id="wl_date" type="date" value="${esc(D.date)}"></div></div>
  <h3>${esc(T('bal'))}</h3>${balHTML()}${countHTML()}${feeHTML()}${moveHTML()}`;
}
async function show() {
  const el = $('#wl_body'); if (!el) return;
  await load(); el.innerHTML = page(); syncMove();
}
function syncMove() { const c = $('#wl_mc'), w = $('#wl_mow'); if (w && c) w.hidden = c.value !== 'wallet'; }
const done = async (r, key) => {
  if (r.error) return toast(eText(r.error));
  D.client[key] = rid(); toast(r.data && r.data.warning ? T('warn') : T('saved')); await show();
};
Object.assign(H, {
  wl_count: async () => {
    const amt = nnum($('#wl_cp').value); if (!(amt >= 0) || $('#wl_cp').value.trim() === '') return toast(lab(ERR.bad_amount));
    const r = await sb.rpc('d_wallet_check_save', { p_wallet: Number($('#wl_cw').value), p_date: D.date, p_phone: amt, p_loc: D.loc, p_client: D.client.check });
    if (r.error) return toast(eText(r.error));
    D.client.check = rid(); await load(); const keep = r.data; $('#wl_body').innerHTML = page(); syncMove(); countResult(keep);
  },
  wl_explain: async (a) => {
    const why = ($('#wl_rs') || {}).value || ''; if (why.trim().length < 3) return toast(lab(ERR.reason_required));
    const r = await sb.rpc('d_wallet_check_explain', { p_check: Number(a.dataset.v), p_reason: why.trim() });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); await show();
  },
  wl_fee: async () => {
    const amt = nnum($('#wl_fa').value); if (!(amt > 0)) return toast(lab(ERR.bad_amount));
    await done(await sb.rpc('d_wallet_fee_add', { p_wallet: Number($('#wl_fw').value), p_loc: D.loc, p_date: D.date, p_amount: amt, p_kind: $('#wl_fk').value, p_ref: $('#wl_fr').value.trim() || null, p_note: null, p_client: D.client.fee }), 'fee');
  },
  wl_move: async () => {
    const amt = nnum($('#wl_ma').value); if (!(amt > 0)) return toast(lab(ERR.bad_amount));
    const counter = $('#wl_mc').value;
    await done(await sb.rpc('d_wallet_move_add', { p_wallet: Number($('#wl_mw').value), p_loc: D.loc, p_date: D.date, p_direction: $('#wl_md').value, p_counter: counter,
      p_counter_wallet: counter === 'wallet' ? Number($('#wl_mo').value) : null, p_amount: amt, p_ref: $('#wl_mr').value.trim() || null, p_note: null, p_client: D.client.move }), 'move');
  },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'wl_mc') syncMove();
  if (e.target.id === 'wl_loc') { D.loc = Number(e.target.value); show(); }
  if (e.target.id === 'wl_date' && e.target.value) { D.date = e.target.value; show(); }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  D.date = today();
  shell(T('title'), '<div id="wl_body"><p class="muted">…</p></div>', true);
  try { await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { wallets: view });
})();
