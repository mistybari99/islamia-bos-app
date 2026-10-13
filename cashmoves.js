/* Islamia BOS · Cash moves (#/cashmoves): bank deposit / withdraw, owner top-up / draw, customer advance (in / refund / used), hub receipt.
   Server: supabase/phase23.sql (cash_move_add with a dry-run, cash_move_void, customer_advances). The day book reads these rows. Nothing is deleted - a wrong row is voided with a reason. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const KINDS = [
  ['bank_deposit', L('ব্যাংকে জমা (ক্যাশ → ব্যাংক)', 'Bank deposit (cash → bank)', 'Bank জমা (cash → bank)'), 0],
  ['bank_withdraw', L('ব্যাংক থেকে তোলা (ব্যাংক → ক্যাশ)', 'Bank withdrawal (bank → cash)', 'Bank থেকে তোলা (bank → cash)'), 0],
  ['owner_topup', L('মালিকের টাকা ব্যবসায় দিলেন', 'Owner put money in', 'Owner-এর টাকা business-এ'), 1],
  ['owner_draw', L('মালিক টাকা নিলেন', 'Owner took money out', 'Owner টাকা নিলেন'), 1],
  ['cust_advance', L('গ্রাহকের অগ্রিম নিলাম', 'Customer advance received', 'Customer advance নিলাম'), 1],
  ['cust_advance_refund', L('গ্রাহকের অগ্রিম ফেরত দিলাম', 'Customer advance refunded', 'Customer advance ফেরত'), 1],
  ['cust_advance_used', L('অগ্রিম বিক্রিতে কাটা হলো (টাকা নড়ে না)', 'Advance used against a sale (no money moves)', 'Advance sale-এ কাটা (টাকা নড়ে না)'), 0],
  ['hub_receipt', L('হাবে ক্যাশ বুঝে পেলাম', 'Hub received cash', 'Hub-এ cash বুঝে পেলাম'), 0],
];
const kl = (k) => { const r = KINDS.find((x) => x[0] === k); return r ? r[1] : k; };
const X = {
  title: L('ক্যাশ ও ব্যাংকের লেনদেন', 'Cash & bank moves', 'Cash ও Bank লেনদেন'), loc: L('জায়গা', 'Location', 'Location'), kind: L('কী ধরনের', 'What kind', 'কী ধরনের'),
  mode: L('কোন মাধ্যমে', 'Through', 'কোন মাধ্যমে'), cash: L('নগদ', 'Cash', 'Cash'), bank: L('ব্যাংক', 'Bank', 'Bank'), mobile: L('মোবাইল', 'Mobile', 'Mobile'),
  amount: L('টাকা', 'Amount', 'Amount'), date: L('তারিখ', 'Date', 'Date'), cust: L('গ্রাহকের মোবাইল', 'Customer mobile', 'Customer mobile'), ref: L('স্লিপ / রেফারেন্স', 'Slip / reference', 'Slip / reference'),
  note: L('নোট', 'Note', 'Note'), check: L('আগে পরীক্ষা করুন', 'Check first', 'আগে check করুন'), save: L('সংরক্ষণ', 'Save', 'Save'), recent: L('সাম্প্রতিক', 'Recent', 'Recent'),
  void: L('বাতিল', 'Void', 'Void'), voidWhy: L('বাতিলের কারণ', 'Why void', 'Void-এর কারণ'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), voided: L('বাতিল হয়েছে', 'Voided', 'Voided'),
  adv: L('গ্রাহকের অগ্রিম বাকি', 'Customer advances held', 'Customer advance বাকি'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  needCust: L('সঠিক মোবাইল দিন (গ্রাহক খুঁজে পাওয়া যায়নি)', 'Enter a known customer mobile', 'Customer mobile দিন'), dry: L('পরীক্ষা: কিছু লেখা হয়নি', 'Check only: nothing was saved', 'Check: কিছু save হয়নি'),
};
const T = (k) => lab(X[k]);
const D = { loc: null, rows: [], adv: [], client: rid() };
const ERR = { bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid'), bad_mode: L('মাধ্যম বাছুন', 'Choose cash / bank / mobile'), bad_date: L('তারিখ ঠিক নয়', 'Date is not valid'),
  customer_required: X.needCust, exceeds_advance: L('অগ্রিমের চেয়ে বেশি', 'More than the advance held'), advance_already_used: L('এই অগ্রিম আগেই ফেরত/ব্যবহার হয়েছে', 'This advance was already refunded or used'),
  note_required: L('কারণ লিখুন', 'Write a reason'), not_allowed: X.noperm, period_locked: L('এই মাস বন্ধ', 'This period is locked') };
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x.replace('_', ' ')) || m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };

async function load() {
  const loc = D.loc;
  const [r, a] = await Promise.all([
    sb.from('cash_moves').select('id,kind,mode,amount,move_date,ref,note,status,customer_id,created_staff,created_at').eq('location_id', loc).order('created_at', { ascending: false }).limit(40),
    sb.rpc('customer_advances'),
  ]);
  D.rows = r.data || []; D.adv = a.data || [];
}
function form() {
  const locs = LOCS();
  return `<div class="card stack">
    <div><label for="cm_loc">${esc(T('loc'))}</label><select id="cm_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="cm_kind">${esc(T('kind'))}</label><select id="cm_kind">${KINDS.map(([k, l]) => `<option value="${k}">${esc(lab(l))}</option>`).join('')}</select></div>
    <div id="cm_modew"><label for="cm_mode">${esc(T('mode'))}</label><select id="cm_mode"><option value="cash">${esc(T('cash'))}</option><option value="bank">${esc(T('bank'))}</option><option value="mobile">${esc(T('mobile'))}</option></select></div>
    <div><label for="cm_amt">${esc(T('amount'))}</label><input id="cm_amt" inputmode="decimal" autocomplete="off"></div>
    <div><label for="cm_date">${esc(T('date'))}</label><input id="cm_date" type="date" value="${today()}"></div>
    <div id="cm_custw" hidden><label for="cm_cust">${esc(T('cust'))}</label><input id="cm_cust" inputmode="tel" autocomplete="off"></div>
    <div><label for="cm_ref">${esc(T('ref'))}</label><input id="cm_ref" autocomplete="off"></div>
    <div><label for="cm_note">${esc(T('note'))}</label><input id="cm_note" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="cm_dry">${esc(T('check'))}</button><button class="full primary" data-act="cm_save">${esc(T('save'))}</button></div>
    <div id="cm_out" class="muted"></div></div>`;
}
function listHTML() {
  const adv = D.adv.length ? `<div class="card"><b>${esc(T('adv'))}</b>${D.adv.map((c) => `<div class="row between"><span>${esc(c.name || '')} ${esc(c.mobile || '')}</span><b>${money(c.balance)}</b></div>`).join('')}</div>` : '';
  const rows = D.rows.length ? D.rows.map((r, i) => `<div class="card ${r.status === 'void' ? 'muted' : ''}"><div class="row between"><b>${esc(lab(kl(r.kind)))}</b><b>${money(r.amount)}</b></div>
      <div class="muted">${esc(r.move_date)} ${r.mode ? '· ' + esc(T(r.mode)) : ''} ${r.ref ? '· ' + esc(r.ref) : ''} ${r.note ? '· ' + esc(r.note) : ''} ${r.status === 'void' ? '· ' + esc(T('voided')) : ''}</div>
      ${r.status === 'done' ? `<div class="row"><button class="mini" data-act="cm_void" data-v="${esc(r.id)}">⋮ ${esc(T('void'))}</button></div>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return adv + `<h3>${esc(T('recent'))}</h3>${rows}`;
}
function sync() {
  const k = ($('#cm_kind') || {}).value, def = KINDS.find((x) => x[0] === k);
  const mw = $('#cm_modew'), cw = $('#cm_custw');
  if (mw) mw.hidden = !(def && def[2]);
  if (cw) cw.hidden = !String(k).startsWith('cust_advance');
}
async function custId() {
  const m = (($('#cm_cust') || {}).value || '').trim(); if (!m) return null;
  const r = await sb.from('customers').select('id').eq('mobile', m).limit(1);
  return r.data && r.data[0] ? r.data[0].id : false;
}
async function call(dry) {
  const kind = $('#cm_kind').value, amt = nnum($('#cm_amt').value);
  if (!(amt > 0)) return toast(lab(ERR.bad_amount));
  let cid = null;
  if (kind.startsWith('cust_advance')) { cid = await custId(); if (!cid) return toast(T('needCust')); }
  const def = KINDS.find((x) => x[0] === kind);
  const r = await sb.rpc('cash_move_add', { p_loc: D.loc, p_kind: kind, p_amount: amt, p_date: $('#cm_date').value || null, p_mode: def[2] ? $('#cm_mode').value : null, p_customer: cid,
    p_ref: $('#cm_ref').value.trim() || null, p_note: $('#cm_note').value.trim() || null, p_client: dry ? null : D.client, p_dry: !!dry });
  if (r.error) return toast(eText(r.error));
  if (dry) { $('#cm_out').textContent = T('dry') + ' → ' + ((r.data && r.data.daybook) || ''); return; }
  D.client = rid(); toast(T('saved')); await show();
}
async function show() {
  const el = $('#cm_body'); if (!el) return;
  await load(); el.innerHTML = form() + listHTML(); sync();
}
Object.assign(H, {
  cm_dry: () => call(true), cm_save: () => call(false),
  cm_void: async (a) => { const n = window.prompt(T('voidWhy')); if (!n || n.trim().length < 3) return;
    const r = await sb.rpc('cash_move_void', { p_id: a.dataset.v, p_note: n.trim() }); if (r.error) return toast(eText(r.error)); toast(T('voided')); await show(); },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'cm_kind') sync();
  if (e.target.id === 'cm_loc') { D.loc = Number(e.target.value); show(); }
});
async function view() {
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  shell(T('title'), '<div id="cm_body"><p class="muted">…</p></div>', true);
  try { await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { cashmoves: view });
})();
