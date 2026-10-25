/* Islamia BOS · Cheques / PDC (#/cheques): register a cheque received from a customer or issued to a supplier, deposit it, clear it, bounce it (reason + bank charge), replace a bounced one,
   and read the four lists: all cheques, due (aging), bounced, post-dated exposure per party. Server: supabase/phase127.sql (cheque_register / cheque_deposit / cheque_clear with a dry run /
   cheque_bounce / cheque_replace / cheque_cancel / cheque_list / cheques_due / cheques_bounced / post_dated_exposure). Only CLEAR moves money in the party ledger (the screen shows the
   balance before and after first). Every row belongs to one location of one business; the server refuses everything outside the user's own business. Switch: dealer_cheque_on. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const { money, nnum, rid, LOCS } = B.s2;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('চেক / PDC খাতা', 'Cheque / PDC register', 'Cheque / PDC খাতা'), loc: L('জায়গা', 'Location', 'Location'),
  tList: L('সব চেক', 'All', 'সব cheque'), tDue: L('পাওনা ডেট', 'Due', 'Due'), tBounced: L('বাউন্স', 'Bounced', 'Bounced'), tExp: L('অগ্রিম ডেটের চেক', 'Post-dated', 'Post-dated'), tNew: L('নতুন চেক', 'New cheque', 'নতুন cheque'),
  dir: L('দিক', 'Direction', 'Direction'), received: L('পাওয়া (গ্রাহক থেকে)', 'Received', 'Received (customer থেকে)'), issued: L('দেওয়া (সাপ্লায়ারকে)', 'Issued', 'Issued (supplier কে)'),
  party: L('পার্টি', 'Party', 'Party'), pCustomer: L('গ্রাহক', 'Customer', 'Customer'), pSupplier: L('সাপ্লায়ার', 'Supplier', 'Supplier'), pOther: L('অন্য', 'Other', 'Other'),
  name: L('নাম', 'Name', 'Name'), bank: L('ব্যাংক', 'Bank', 'Bank'), branch: L('শাখা', 'Branch', 'Branch'), no: L('চেক নম্বর', 'Cheque no.', 'Cheque no.'), amount: L('টাকা', 'Amount', 'Amount'),
  cdate: L('চেকের ডেট', 'Cheque date', 'Cheque date'), ddate: L('জমার ডেট (খালি = চেকের ডেট)', 'Due date (empty = cheque date)', 'Due date (খালি = cheque date)'), note: L('নোট', 'Note', 'Note'),
  save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), pick: L('— বাছুন —', '— choose —', '— বাছুন —'),
  deposit: L('ব্যাংকে জমা', 'Deposit', 'Deposit'), clear: L('ক্লিয়ার', 'Clear', 'Clear'), bounce: L('বাউন্স', 'Bounce', 'Bounce'), cancel: L('বাতিল', 'Cancel', 'Cancel'), replace: L('বদলি চেক', 'Replace', 'Replace'),
  dateAsk: L('ডেট (YYYY-MM-DD)', 'Date (YYYY-MM-DD)', 'Date (YYYY-MM-DD)'), why: L('কারণ', 'Reason', 'Reason'), charge: L('ব্যাংক চার্জ (টাকা)', 'Bank charge', 'Bank charge'),
  newNo: L('নতুন চেক নম্বর', 'New cheque no.', 'নতুন cheque no.'), newAmt: L('নতুন চেকের টাকা', 'New cheque amount', 'নতুন cheque amount'),
  sure: L('ক্লিয়ার করবেন? খাতার ব্যালেন্স', 'Clear it? Ledger balance', 'Clear করবেন? ledger balance'), after: L('পরে', 'after', 'পরে'),
  days: L('দিন', 'days', 'days'), late: L('দেরি', 'late', 'late'), exp: L('মোট', 'Total', 'Total'), cheques: L('চেক', 'cheques', 'cheques'), reason: L('কারণ', 'Reason', 'Reason'),
  st_registered: L('নিবন্ধিত', 'registered', 'registered'), st_deposited: L('জমা', 'deposited', 'deposited'), st_cleared: L('ক্লিয়ার', 'cleared', 'cleared'), st_bounced: L('বাউন্স', 'bounced', 'bounced'),
  st_replaced: L('বদলানো', 'replaced', 'replaced'), st_cancelled: L('বাতিল', 'cancelled', 'cancelled'),
  e_feature_off: L('চেক খাতা বন্ধ আছে (মালিক সুইচবোর্ডে চালু করবেন)', 'The cheque register is switched off (the owner turns it on in the switchboard)', 'Cheque খাতা off আছে (owner switchboard-এ on করবেন)'),
  e_not_allowed: L('এই জায়গায় আপনার অনুমতি নেই', 'You are not allowed here', 'এই জায়গায় permission নেই'), e_overpaid: L('চেকের টাকা খাতার বাকির চেয়ে বেশি', 'The cheque is more than the balance on the ledger', 'Cheque-এর টাকা ledger-এর বাকির চেয়ে বেশি'),
  e_duplicate_cheque: L('এই ব্যাংক ও নম্বরের চেক আগেই আছে', 'A cheque with this bank and number already exists', 'এই bank ও number-এর cheque আগেই আছে'), e_bad_status: L('এই অবস্থায় এটা করা যায় না', 'Not possible in this status', 'এই status-এ করা যায় না'),
  e_bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'The amount is not valid', 'Amount ঠিক নয়'), e_bad_date: L('ডেট ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'), e_bad_due_date: L('জমার ডেট চেকের ডেটের আগে হতে পারে না', 'Due date cannot be before the cheque date', 'Due date cheque date-এর আগে হতে পারে না'),
  e_bad_cheque_date: L('চেকের ডেট ঠিক নয়', 'The cheque date is not valid', 'Cheque date ঠিক নয়'), e_period_closed: L('এই মাসের হিসাব বন্ধ', 'This period is closed', 'এই মাসের হিসাব বন্ধ'),
  e_reason_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'), e_bank_required: L('ব্যাংকের নাম দিন', 'Enter the bank', 'Bank-এর নাম দিন'), e_cheque_no_required: L('চেক নম্বর দিন', 'Enter the cheque number', 'Cheque number দিন'),
  e_customer_not_found: L('গ্রাহক পাওয়া যায়নি', 'Customer not found', 'Customer পাওয়া যায়নি'), e_supplier_not_found: L('সাপ্লায়ার পাওয়া যায়নি', 'Supplier not found', 'Supplier পাওয়া যায়নি'),
  e_party_name_required: L('পার্টির নাম দিন', 'Enter the party name', 'Party-র নাম দিন'),
};
const T = (k) => lab(X[k]);
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? lab(X[k]) : m || 'error'; };
const D = { tab: 'list', loc: null, rows: [], due: [], bounced: [], exp: [], cust: [], supp: [], client: rid() };

async function load() {
  const [a, b, c, d, cu, su] = await Promise.all([sb.rpc('cheque_list', { p_business: null, p_status: null, p_dir: null, p_limit: 200 }), sb.rpc('cheques_due', { p_business: null, p_days: 30, p_dir: null, p_asof: null }),
    sb.rpc('cheques_bounced', { p_business: null, p_from: null, p_to: null }), sb.rpc('post_dated_exposure', { p_business: null, p_dir: null, p_asof: null }),
    sb.from('customers').select('id,name,mobile').order('name').limit(500), sb.from('suppliers').select('id,name').order('name').limit(500)]);
  D.rows = a.data || []; D.due = b.data || []; D.bounced = c.data || []; D.exp = d.data || []; D.cust = cu.data || []; D.supp = su.data || [];
  if (a.error && /feature|not allowed/.test(a.error.message || '')) D.err = a.error;
}
const sc = (s) => `<span class="chip ${s === 'cleared' ? 'ok' : s === 'bounced' ? 'bad' : s === 'cancelled' || s === 'replaced' ? '' : 'warn'}">${esc(T('st_' + s))}</span>`;
const dirT = (d) => (d === 'received' ? T('received') : T('issued'));
function actions(r) {
  const b = (act, k, cls = '') => `<button class="mini ${cls}" data-act="${act}" data-v="${esc(r.id)}">${esc(T(k))}</button>`;
  if (r.status === 'registered') return b('ch_dep', 'deposit') + b('ch_cancel', 'cancel');
  if (r.status === 'deposited') return b('ch_clear', 'clear', 'primary') + b('ch_bounce', 'bounce');
  if (r.status === 'bounced') return b('ch_replace', 'replace') + b('ch_cancel', 'cancel');
  return '';
}
function card(r, acts, extra) {
  return `<div class="card"><div class="row between wrap"><b>${esc(r.party_name || '')}</b><b>${money(r.amount)}</b></div>
    <div class="muted">${esc(dirT(r.direction))} · ${esc(r.bank_name)} · ${esc(r.cheque_no)}</div>
    <div class="row between wrap"><span class="muted">${esc(r.cheque_date)}${r.due_date && r.due_date !== r.cheque_date ? ' → ' + esc(r.due_date) : ''}</span>${sc(r.status)}</div>
    ${r.bounce_reason ? `<div class="muted">${esc(T('reason'))}: ${esc(r.bounce_reason)}${Number(r.bounce_charge) ? ' · ' + esc(T('charge')) + ' ' + money(r.bounce_charge) : ''}</div>` : ''}
    ${extra || ''}${acts ? `<div class="row wrap">${actions(r)}</div>` : ''}</div>`;
}
const empty = () => `<p class="muted">${esc(T('none'))}</p>`;
function formH() {
  const locs = LOCS();
  return `<div class="card stack">
    <div><label for="ch_loc">${esc(T('loc'))}</label><select id="ch_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="ch_dir">${esc(T('dir'))}</label><select id="ch_dir"><option value="received">${esc(T('received'))}</option><option value="issued">${esc(T('issued'))}</option></select></div>
    <div id="ch_pickw"><label for="ch_party">${esc(T('party'))}</label><select id="ch_party"></select></div>
    <div id="ch_namew" hidden><label for="ch_pname">${esc(T('name'))}</label><input id="ch_pname" autocomplete="off"></div>
    <div><label for="ch_bank">${esc(T('bank'))}</label><input id="ch_bank" autocomplete="off"></div>
    <div><label for="ch_branch">${esc(T('branch'))}</label><input id="ch_branch" autocomplete="off"></div>
    <div><label for="ch_no">${esc(T('no'))}</label><input id="ch_no" autocomplete="off"></div>
    <div><label for="ch_amt">${esc(T('amount'))}</label><input id="ch_amt" inputmode="decimal" autocomplete="off"></div>
    <div><label for="ch_cd">${esc(T('cdate'))}</label><input id="ch_cd" type="date" value="${today()}"></div>
    <div><label for="ch_dd">${esc(T('ddate'))}</label><input id="ch_dd" type="date"></div>
    <div><label for="ch_note">${esc(T('note'))}</label><input id="ch_note" autocomplete="off"></div>
    <button class="full primary" data-act="ch_save">${esc(T('save'))}</button></div>`;
}
function fillParty() {
  const dir = ($('#ch_dir') || {}).value, sel = $('#ch_party'); if (!sel) return;
  const list = dir === 'issued' ? D.supp : D.cust, kinds = dir === 'issued' ? [['supplier', T('pSupplier')]] : [['customer', T('pCustomer')]];
  sel.innerHTML = `<option value="">${esc(T('pick'))}</option>` + list.map((p) => `<option value="${esc(p.id)}">${esc(p.name)}${p.mobile ? ' · ' + esc(p.mobile) : ''}</option>`).join('') + `<option value="other">${esc(T('pOther'))}</option>`;
  D.kind = kinds[0][0]; syncName();
}
function syncName() { const v = ($('#ch_party') || {}).value, w = $('#ch_namew'); if (w) w.hidden = v !== 'other'; }
function draw() {
  const el = $('#ch_body'); if (!el) return;
  const tabs = [['list', 'tList'], ['due', 'tDue'], ['bounced', 'tBounced'], ['exp', 'tExp'], ['new', 'tNew']];
  const bar = `<div class="row wrap">${tabs.map(([k, l]) => `<button class="mini ${D.tab === k ? 'primary' : ''}" data-act="ch_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
  let body = '';
  if (D.err) body = `<div class="notice warn">${esc(eText(D.err))}</div>`;
  else if (D.tab === 'list') body = D.rows.length ? D.rows.map((r) => card(r, true)).join('') : empty();
  else if (D.tab === 'due') body = D.due.length ? D.due.map((r) => card(r, true, `<div class="muted">${r.days_to_due < 0 ? esc(String(-r.days_to_due)) + ' ' + esc(T('days')) + ' ' + esc(T('late')) : esc(String(r.days_to_due)) + ' ' + esc(T('days'))}</div>`)).join('') : empty();
  else if (D.tab === 'bounced') body = D.bounced.length ? D.bounced.map((r) => card({ ...r, cheque_date: r.bounced_on, due_date: r.bounced_on }, false)).join('') : empty();
  else if (D.tab === 'exp') body = D.exp.length ? D.exp.map((r) => `<div class="card"><div class="row between wrap"><b>${esc(r.party_name || '')}</b><b>${money(r.total)}</b></div><div class="muted">${esc(dirT(r.direction))} · ${esc(String(r.cheques))} ${esc(T('cheques'))} · ${esc(r.earliest_due)} → ${esc(r.latest_due)}</div></div>`).join('') : empty();
  else body = formH();
  el.innerHTML = bar + body; if (D.tab === 'new') fillParty();
}
async function show() { await load(); draw(); }
const askDate = () => { const d = window.prompt(T('dateAsk'), today()); if (d === null) return null; return /^\d{4}-\d{2}-\d{2}$/.test(d.trim()) ? d.trim() : (toast(lab(X.e_bad_date)), null); };
async function go(fn, args, okMsg) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } if (okMsg) toast(T(okMsg)); await show(); return r.data; }
Object.assign(H, {
  ch_tab: (a) => { D.tab = a.dataset.v; draw(); },
  ch_save: async () => {
    const dir = $('#ch_dir').value, pv = $('#ch_party').value, amt = nnum($('#ch_amt').value);
    if (!(amt > 0)) return toast(lab(X.e_bad_amount));
    const kind = pv === 'other' || !pv ? 'other' : (dir === 'issued' ? 'supplier' : 'customer');
    const r = await sb.rpc('cheque_register', { p_client: D.client, p_loc: Number($('#ch_loc').value), p_dir: dir, p_party_kind: kind, p_party: kind === 'other' ? null : pv, p_party_name: kind === 'other' ? ($('#ch_pname').value.trim() || null) : null,
      p_bank: $('#ch_bank').value.trim(), p_branch: $('#ch_branch').value.trim() || null, p_no: $('#ch_no').value.trim(), p_amount: amt, p_cheque_date: $('#ch_cd').value, p_due_date: $('#ch_dd').value || null, p_note: $('#ch_note').value.trim() || null });
    if (r.error) return toast(eText(r.error));
    D.client = rid(); toast(T('saved')); D.tab = 'list'; await show();
  },
  ch_dep: async (a) => { const d = askDate(); if (!d) return; await go('cheque_deposit', { p_id: a.dataset.v, p_date: d, p_bank_account: null, p_note: null, p_client: rid() }, 'saved'); },
  ch_clear: async (a) => {
    const d = askDate(); if (!d) return;
    const pv = await sb.rpc('cheque_clear', { p_id: a.dataset.v, p_date: d, p_note: null, p_client: null, p_dry: true }); if (pv.error) return toast(eText(pv.error));
    const x = pv.data || {}; const msg = x.balance_before === null || x.balance_before === undefined ? '' : `${T('sure')}: ${money(x.balance_before)} → ${T('after')} ${money(x.balance_after)}`;
    if (msg && !window.confirm(msg)) return;
    await go('cheque_clear', { p_id: a.dataset.v, p_date: d, p_note: null, p_client: rid(), p_dry: false }, 'saved');
  },
  ch_bounce: async (a) => {
    const d = askDate(); if (!d) return; const why = window.prompt(T('why')); if (!why || !why.trim()) return toast(lab(X.e_reason_required));
    const ch = window.prompt(T('charge'), '0'); if (ch === null) return;
    await go('cheque_bounce', { p_id: a.dataset.v, p_date: d, p_reason: why.trim(), p_charge: nnum(ch) || 0, p_note: null, p_client: rid() }, 'saved');
  },
  ch_cancel: async (a) => { const why = window.prompt(T('why')); if (!why || !why.trim()) return; await go('cheque_cancel', { p_id: a.dataset.v, p_reason: why.trim(), p_client: rid() }, 'saved'); },
  ch_replace: async (a) => {
    const old = D.rows.find((r) => r.id === a.dataset.v) || {}; const no = window.prompt(T('newNo')); if (!no || !no.trim()) return;
    const amt = nnum(window.prompt(T('newAmt'), String(old.amount || ''))); if (!(amt > 0)) return toast(lab(X.e_bad_amount));
    await go('cheque_replace', { p_old: a.dataset.v, p_client: rid(), p_bank: old.bank_name, p_branch: null, p_no: no.trim(), p_amount: amt, p_cheque_date: today(), p_due_date: null, p_note: null }, 'saved');
  },
});
document.addEventListener('change', (e) => { if (e.target.id === 'ch_dir') fillParty(); if (e.target.id === 'ch_party') syncName(); });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  shell(T('title'), '<div id="ch_body"><p class="muted">…</p></div>', true);
  try { D.err = null; await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { cheques: view });
})();
