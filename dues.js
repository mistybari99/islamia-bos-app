/* Islamia BOS · customers and dues (baki): who owes what and since when, the customer ledger, collecting a payment
   (full or part), and the owner's credit limit per customer. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const r2 = (n) => Math.round(n * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(Number(n)));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const nnum = (v) => { const n = Number(norm(v).trim()); return Number.isFinite(n) ? n : 0; };
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const days = (iso) => (iso ? Math.max(0, Math.round((new Date(today() + 'T12:00:00Z') - new Date(iso + 'T12:00:00Z')) / 86400000)) : 0);
const hhmm = (iso) => new Date(iso).toLocaleString('en-GB', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Asia/Dhaka' });
const X = {
  title: L('বাকি ও গ্রাহক', 'Dues & customers', 'Due ও Customer'), search: L('নাম বা মোবাইল দিয়ে খুঁজুন', 'Search by name or mobile', 'নাম বা mobile দিয়ে খুঁজুন'), total: L('মোট বাকি', 'Total due', 'মোট Due'),
  none: L('কারও বাকি নেই ✓', 'Nobody owes anything ✓', 'কারও Due নেই ✓'), since: L('দিন আগে থেকে', 'days since', 'দিন আগে থেকে'), wholesale: L('পাইকারি', 'Wholesale', 'Wholesale'),
  ledger: L('হিসাব খাতা', 'Ledger', 'Ledger'), collect: L('বাকি আদায়', 'Collect payment', 'Due আদায়'), balance: L('এখন বাকি', 'Balance now', 'এখন Due'), limit: L('বাকির সীমা (৳)', 'Credit limit (৳)', 'Credit limit (৳)'),
  save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), collected: L('আদায় হয়েছে', 'Collected', 'আদায় হয়েছে'), noteph: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'),
  sale: L('বিক্রি', 'Sale', 'Sale'), paid: L('পরিশোধ', 'Paid', 'Paid'), coll: L('আদায়', 'Collection', 'আদায়'), back: L('ফিরুন', 'Back', 'Back'), close: L('বন্ধ', 'Close', 'Close'),
  confirm: L('আদায় নিশ্চিত', 'Confirm collection', 'আদায় Confirm'), nolimit: L('(লেখা নেই)', '(not set)', '(লেখা নেই)'), noloc: L('কোনো লোকেশন নেই', 'No location', 'কোনো Location নেই'),
};
const T = (k) => lab(X[k]);
const ERR = { overpaid: L('আদায় বাকির বেশি হতে পারে না', 'Collection cannot be more than the balance', 'আদায় Due এর বেশি হতে পারে না'), wallet_needed: L('মোবাইল পেমেন্টে বিকাশ/নগদ ইত্যাদি বাছুন', 'Choose bKash / Nagad etc.', 'bKash/Nagad বাছুন') };
const D = { rows: [], q: '', cur: null, st: null, loc: null };

async function viewDues() {
  if (!(S.ctx.is_owner || (S.ctx.perms.POS && S.ctx.perms.POS.view))) return (location.hash = '#/home');
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic();
  const r = await sb.rpc('customer_dues'); if (r.error) return fail(r.error);
  D.rows = r.data || [];
  const locs = S.ctx.is_owner || S.ctx.roles.includes('management') ? B.ENV.locs : B.ENV.locs.filter((l) => S.ctx.locations.includes(l.id));
  D.loc = D.loc && locs.find((l) => l.id === D.loc) ? D.loc : (locs[0] || {}).id;
  B.pay.loadWallets();
  draw();
}
function draw() {
  const q = D.q.trim().toLowerCase(), list = D.rows.filter((c) => !q || c.name.toLowerCase().includes(q) || c.mobile.includes(norm(q)));
  const tot = D.rows.reduce((a, c) => a + Number(c.balance), 0);
  shell(T('title'), `<div class="plate"><div class="pl-k">${esc(T('total'))}</div><div class="pl-v"><span class="cur">৳</span>${fmt(r2(tot))}</div><div class="pl-s">${D.rows.length}</div></div>
    <input id="du_q" placeholder="${esc(T('search'))}" value="${esc(D.q)}" style="margin-bottom:8px">
    <div id="du_list"></div>`, true);
  drawList(list);
}
function drawList(list) {
  $('#du_list').innerHTML = list.map((c) => `<div class="card item" data-act="du_open" data-v="${c.id}"><div><div class="nm">${esc(c.name)} ${c.type === 'wholesale' ? '◆' : ''}</div>
      <div class="muted" style="font-size:.85rem">${esc(c.mobile)}${c.oldest ? ` · ${days(c.oldest)} ${esc(T('since'))}` : ''}</div></div>
      <div class="pr"><b>${money(c.balance)}</b>${c.credit_limit !== null && Number(c.balance) > Number(c.credit_limit) ? '<div><span class="chip bad">!</span></div>' : ''}</div></div>`).join('') || `<p class="muted center">${esc(T('none'))}</p>`;
}
async function openCustomer(id) {
  const c = D.rows.find((x) => x.id === id); if (!c) return;
  D.cur = c;
  const r = await sb.rpc('customer_ledger', { p_customer: id }); if (r.error) return fail(r.error);
  const canPay = S.ctx.is_owner || (S.ctx.perms.POS && S.ctx.perms.POS.enter);
  D.st = B.pay.create(() => Number(c.balance));
  openSheet(`<h2>${esc(c.name)} ${c.type === 'wholesale' ? '◆' : ''}</h2><div class="muted">${esc(c.mobile)}</div>
    <div class="row between" style="margin:8px 0"><span>${esc(T('balance'))}</span><b class="mnum">${money(c.balance)}</b></div>
    ${S.ctx.is_owner ? `<div class="row"><div style="flex:1"><label>${esc(T('limit'))}</label><input id="du_lim" inputmode="decimal" value="${c.credit_limit === null ? '' : esc(String(c.credit_limit))}" placeholder="${esc(T('nolimit'))}"></div><button class="primary" data-act="du_limit" style="align-self:flex-end">${esc(T('save'))}</button></div>` : ''}
    ${canPay && Number(c.balance) > 0 ? `<h3 style="margin-top:12px">${esc(T('collect'))}</h3><div id="du_pay">${B.pay.html(D.st)}</div><div><label>${esc(T('noteph'))}</label><input id="du_note"></div>
      <button class="primary full" style="margin-top:10px" data-act="du_collect">${esc(T('confirm'))}</button>` : ''}
    <h3 style="margin-top:14px">${esc(T('ledger'))}</h3>
    <div class="stack">${(r.data || []).slice().reverse().map((e) => `<div class="row between perm"><span>${esc(hhmm(e.at))}<br><span class="muted" style="font-size:.8rem">${esc(e.kind === 'sale' ? T('sale') + ' ' + e.ref : e.kind === 'collection' ? T('coll') : T('paid'))}${e.kind !== 'sale' && e.ref ? ' · ' + esc(e.ref) : ''}</span></span>
      <span style="text-align:right">${Number(e.debit) ? `<b>+${money(e.debit)}</b>` : `<b style="color:var(--ok)">−${money(e.credit)}</b>`}<br><span class="muted" style="font-size:.8rem">${money(e.balance)}</span></span></div>`).join('')}</div>
    <button class="full" style="margin-top:10px" data-act="closesheet">${esc(T('close'))}</button>`);
}
Object.assign(A.H, {
  du_open: (a) => openCustomer(a.dataset.v),
  du_limit: async () => { const v = $('#du_lim').value.trim(); const { error } = await sb.from('customers').update({ credit_limit: v === '' ? null : nnum(v) }).eq('id', D.cur.id); if (error) return fail(error); D.cur.credit_limit = v === '' ? null : nnum(v); toast(T('saved')); },
  du_collect: async () => {
    const pe = B.pay.check(D.st); if (pe) return toast(lab(ERR[pe]));
    const list = B.pay.list(D.st); if (!list.length) return toast(T('collect'));
    const { data, error } = await sb.rpc('collect_payment', { p_client: crypto.randomUUID ? crypto.randomUUID() : null, p_loc: D.loc, p_customer: D.cur.id, p_payments: list, p_note: ($('#du_note') || {}).value || null });
    if (error) { const m = /overpaid/.test(error.message || '') ? lab(ERR.overpaid) : null; return m ? toast(m) : fail(error); }
    closeSheet(); toast(`${T('collected')} · ${money(data.collected)} · ${T('balance')} ${money(data.balance)}`); viewDues();
  },
});
document.addEventListener('input', (e) => { if (e.target.id === 'du_q') { D.q = e.target.value; const q = D.q.trim().toLowerCase(); drawList(D.rows.filter((c) => !q || c.name.toLowerCase().includes(q) || c.mobile.includes(norm(q)))); } });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { dues: viewDues });
})();
