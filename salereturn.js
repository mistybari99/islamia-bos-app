/* Islamia BOS · Sale returns (#/salereturn, #/salereturn/<sale id>).
   A list of a day's receipts at one location, every row with a ⋮ menu (Return goods / Returns of this receipt), and the return sheet:
   lines to take back (never more than is left), a reason from the editable list return_reasons, how the value is settled
   (first against what the customer owes — rule sale_return_due_first — the rest handed back in cash / mobile / card).
   The server (phase12.sql: sale_return, void_sale_return, sale_returns_for) restocks, batch aware, and checks everything again.
   Other screens can open the sheet with B.saleReturn.open(saleId). Needs stock2.js (B.s2). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const U = B.s2;
const { errToast, rid, grant, nnum, money, dt, optHTML, lists, rowL, LOCS, allLocs, LOCK, npMode } = U;
const r2 = (n) => Math.round(Number(n) * 100) / 100;
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });

const X = {
  title: L('সেল ফেরত', 'Sale returns', 'Sale return'), date: L('ডেট', 'Date', 'Date'), location: L('জায়গা', 'Location', 'Location'), receipt: L('রসিদ', 'Receipt', 'Receipt'),
  none: L('এই দিনে কোনো সেল নেই', 'No sales on this day', 'এই দিনে কোনো sale নেই'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), voided: L('ভয়েড', 'Voided', 'Void'),
  more: L('আরও অপশন', 'More options', 'আরও option'), doReturn: L('মাল ফেরত নিন', 'Take goods back', 'মাল return নিন'), history: L('এই রসিদের ফেরত', 'Returns of this receipt', 'এই receipt-এর return'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), close: L('বন্ধ', 'Close', 'Close'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'),
  sold: L('বিক্রি', 'Sold', 'Sold'), returned: L('ফেরত হয়েছে', 'Returned', 'Returned'), left: L('বাকি', 'Left', 'Left'), qty: L('ফেরত Qty', 'Return quantity', 'Return quantity'),
  reason: L('ফেরতের কারণ', 'Return reason', 'Return reason'), note: L('নোট', 'Note', 'Note'), value: L('ফেরত মূল্য', 'Value of the return', 'Return value'),
  fromDue: L('কাস্টমারের বাকি থেকে কাটা', 'Taken off what the customer owes', 'Customer-এর due থেকে কাটা'), handBack: L('ফেরত দিতে হবে', 'To hand back', 'ফেরত দিতে হবে'),
  mode: L('কীভাবে ফেরত দিলেন', 'How it was handed back', 'কীভাবে ফেরত দিলেন'), cash: L('ক্যাশ', 'Cash', 'Cash'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), card: L('কার্ড', 'Card', 'Card'),
  wallet: L('ওয়ালেট (বিকাশ/নগদ…)', 'Wallet (bKash / Nagad…)', 'Wallet (bKash/Nagad…)'), ref: L('রেফারেন্স', 'Reference', 'Reference'),
  go: L('ফেরত নিন', 'Confirm return', 'Return confirm'), done: L('ফেরত নেওয়া হয়েছে', 'Return recorded', 'Return recorded'), dup: L('আগেই সেভ হয়েছে — আবার হয়নি', 'Already saved — nothing was added twice', 'আগেই saved — আবার হয়নি'),
  needQty: L('অন্তত একটি আইটেমের ফেরত Qty লিখুন', 'Enter a quantity for at least one item', 'অন্তত একটি item-এর quantity লিখুন'), badQty: L('Qty বাকির চেয়ে বেশি বা ঠিক নয়', 'Quantity is wrong or more than what is left', 'Quantity ঠিক নয় বা বাকির বেশি'),
  needReason: L('কারণ বাছুন', 'Choose a reason', 'Reason বাছুন'), needMode: L('ফেরতের ধরন বাছুন', 'Choose how it was handed back', 'Refund-এর ধরন বাছুন'), needWallet: L('ওয়ালেট লিখুন', 'Enter the wallet', 'Wallet লিখুন'),
  voidRet: L('ফেরত ভয়েড', 'Void this return', 'Return void'), voidWhy: L('ভয়েডের কারণ (লাগবেই)', 'Reason for voiding (required)', 'Void-এর reason (লাগবেই)'), voidDone: L('ফেরত ভয়েড হয়েছে', 'Return voided', 'Return voided'),
  noReturns: L('এই রসিদে কোনো ফেরত নেই', 'No returns on this receipt', 'এই receipt-এ কোনো return নেই'), cust: L('কাস্টমার', 'Customer', 'Customer'), owes: L('কাস্টমারের বাকি', 'Customer owes', 'Customer-এর due'),
  nothingLeft: L('ফেরত নেওয়ার মতো কিছু বাকি নেই', 'Nothing is left to return', 'Return নেওয়ার মতো কিছু বাকি নেই'), sqlMissing: L('সেল ফেরতের ডেটাবেস অংশ এখনও চালু হয়নি (phase12)', 'The sale-return database part is not installed yet (phase12)', 'Sale return-এর database অংশ চালু হয়নি (phase12)'),
  dueFirstOff: L('সেটিং অনুযায়ী পুরো টাকা ফেরত যাবে', 'By the setting the whole value is handed back', 'Setting অনুযায়ী পুরো টাকা ফেরত'), items: L('আইটেম', 'items', 'items'),
};
const T = (k) => lab(X[k]);
const D = { loc: undefined, date: today(), rows: [], err: null };
const C = { d: null, client: null, busy: false };      // the open return sheet
const missingFn = (e) => e && /could not find the function|does not exist|schema cache|404/i.test(e.message || '');

async function listView() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const locs = LOCS(); if (D.loc === undefined) D.loc = (locs[0] || {}).id;
  const r = await sb.from('sales').select('id,receipt,sold_at,total,status,customer,location_id,pay_mode').eq('location_id', D.loc).eq('sale_date', D.date).order('receipt', { ascending: false }).limit(200);
  D.err = r.error; D.rows = r.error ? [] : (r.data || []);
  shell(T('title'), `<div class="p2-bar">${locs.length > 1 || allLocs() ? `<select id="sr_loc" aria-label="${esc(T('location'))}">${optHTML(locs.map((l) => [l.id, nm(l)]), D.loc)}</select>` : ''}<input id="sr_date" type="date" value="${esc(D.date)}" aria-label="${esc(T('date'))}"></div>
    <div id="sr_list">${D.rows.map((s, i) => `<div class="card item mk ${s.status === 'void' ? 'bad' : ''}" data-act="sr_open" data-v="${esc(s.id)}" role="button" tabindex="0"><div><div class="nm">${esc(T('receipt'))} #${esc(String(s.receipt))}</div>
      <div class="muted" style="font-size:.85rem">${esc(dt(s.sold_at))}${s.customer ? ' · ' + esc(s.customer) : ''}</div>${s.status === 'void' ? `<span class="chip bad">${esc(T('voided'))}</span>` : ''}</div>
      <div class="pr"><button type="button" class="mini s2-dots" data-act="sr_menu" data-i="${i}" aria-label="${esc(T('more'))}">⋮</button><b>${esc(money(s.total))}</b></div></div>`).join('') || `<p class="muted center">${esc(T('none'))}</p>`}</div>`, true);
}

// ---- the return sheet ----
async function open(saleId) {
  openSheet(`<p class="muted">${esc(T('loading'))}</p>`);
  const r = await sb.rpc('sale_returns_for', { p_sale: saleId });
  if (r.error) { closeSheet(); if (missingFn(r.error)) return toast(T('sqlMissing')); return errToast(r.error); }
  const d = r.data; C.d = d; C.client = rid(); C.busy = false;
  const lines = d.lines || [], reasons = lists('return_reasons').map((x) => [x.value_code, lab(rowL(x))]);
  const lock = npMode() === 'lock';
  openSheet(`<h2>${esc(T('receipt'))} #${esc(String(d.receipt))}</h2>${d.customer ? `<div class="muted">${esc(T('cust'))}: ${esc(d.customer)}${d.balance !== null && d.balance !== undefined ? ' · ' + esc(T('owes')) + ' ' + esc(money(d.balance)) : ''}</div>` : ''}
    ${d.can_return && d.status === 'done' ? `<div class="stack" style="margin-top:8px" id="sr_form">
      ${lines.map((l, i) => `<div class="card stack" data-sl="${i}"><b>${esc(l.name || '')}</b><div class="muted" style="font-size:.85rem">${esc(T('sold'))} ${U.q4(l.sold)} · ${esc(T('returned'))} ${U.q4(l.returned)} · ${esc(T('left'))} ${U.q4(l.left)} ${esc(l.unit ? U.unitLabel(l.unit) : '')}</div>
        ${Number(l.left) > 0 ? `<div><label>${esc(T('qty'))}</label><input data-rq="${i}" inputmode="decimal" autocomplete="off"></div>` : ''}</div>`).join('') || `<p class="muted">${esc(T('nothingLeft'))}</p>`}
      <div><label for="sr_reason">${esc(T('reason'))}</label><select id="sr_reason"><option value="">—</option>${optHTML(reasons, '')}</select></div>
      <div><label for="sr_note">${esc(T('note'))}</label><input id="sr_note" autocomplete="off"></div>
      <div class="card stack" id="sr_sum"></div>
      <div id="sr_mw" hidden><label for="sr_mode">${esc(T('mode'))}</label><select id="sr_mode"><option value="">—</option>${['cash', 'mobile', 'card'].map((m) => `<option value="${m}">${esc(T(m))}</option>`).join('')}</select>
        <div id="sr_ww" hidden style="margin-top:6px"><label for="sr_wallet">${esc(T('wallet'))}</label><input id="sr_wallet" autocomplete="off"></div><div style="margin-top:6px"><label for="sr_ref">${esc(T('ref'))}</label><input id="sr_ref" autocomplete="off"></div></div></div>`
    : lock && d.status === 'done' ? `<div class="s2-lockrow">${LOCK}<span>${esc(T('doReturn'))} · ${esc(T('noperm'))}</span></div>` : ''}
    <h3 style="margin-top:14px">${esc(T('history'))}</h3><div>${(d.returns || []).map((x) => `<div class="s2-led"><div>${esc(money(x.amount))} ${x.status === 'void' ? `<span class="chip bad">${esc(T('voided'))}</span>` : ''}<div class="sub">${esc(dt(x.at))}${x.staff ? ' · ' + esc(x.staff) : ''} · ${esc(rLabel(x.reason))}${x.note ? ' · ' + esc(x.note) : ''}</div>
      <div class="sub">${Number(x.credit) ? esc(T('fromDue')) + ' ' + esc(money(x.credit)) : ''}${Number(x.refund) ? ' ' + esc(T('handBack')) + ' ' + esc(money(x.refund)) + (x.refund_mode ? ' (' + esc(T(x.refund_mode)) + ')' : '') : ''}</div></div>
      ${x.status === 'done' && d.can_return ? `<button class="mini s2-dots" data-act="sr_void" data-v="${esc(x.id)}" aria-label="${esc(T('voidRet'))}">⋮</button>` : ''}</div>`).join('') || `<p class="muted center">${esc(T('noReturns'))}</p>`}</div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button>${d.can_return && d.status === 'done' && lines.some((l) => Number(l.left) > 0) ? `<button class="primary full" id="sr_go" data-act="sr_go">${esc(T('go'))}</button>` : ''}</div>`);
  recalc();
  { const lc = B.listctl, oth = lists('return_reasons').some((r) => r.value_code === 'other' && r.active);
    if (lc && $('#sr_reason')) lc.enhance('#sr_reason', 'return_reasons', oth ? { otherValue: 'other', form: 'SALE_RETURN', ctx: { field: 'return_reason', sale: String(d.sale_id || '').slice(0, 40) } } : { noOther: true, form: 'SALE_RETURN' }); }
}
const rLabel = (code) => { const r = lists('return_reasons').find((x) => x.value_code === code); return r ? lab(rowL(r)) : code || ''; };
// value / due / hand-back as the server will compute them (all from the sale's own numbers: price per unit, the discount factor, the customer's balance)
function calc() {
  const d = C.d; if (!d) return null; let gross = 0, bad = false, any = false;
  (d.lines || []).forEach((l, i) => { const el = $(`[data-rq="${i}"]`); if (!el || !el.value.trim()) return; const q = nnum(el.value); if (!(q > 0) || q > Number(l.left) + 0.00005) { bad = true; return; } any = true; gross += r2(q * Number(l.price)); });
  const amt = r2(gross * Number(d.factor || 1)), bal = d.balance === null || d.balance === undefined ? 0 : Number(d.balance);
  const credit = d.customer_id && d.due_first ? Math.min(amt, Math.max(bal, 0)) : 0;
  return { amt, credit: r2(credit), refund: r2(amt - credit), bad, any };
}
function recalc() {
  const c = calc(); const box = $('#sr_sum'); if (!c || !box) return;
  box.innerHTML = `<div class="row between"><span>${esc(T('value'))}</span><b>${esc(money(c.amt))}</b></div>${c.credit > 0 ? `<div class="row between"><span>${esc(T('fromDue'))}</span><b>${esc(money(c.credit))}</b></div>` : ''}
    <div class="row between"><span>${esc(T('handBack'))}</span><b class="mnum">${esc(money(c.refund))}</b></div>${C.d.customer_id && !C.d.due_first ? `<div class="hint">${esc(T('dueFirstOff'))}</div>` : ''}`;
  const mw = $('#sr_mw'); if (mw) mw.hidden = !(c.refund > 0);
}
async function goReturn(btn) {
  if (C.busy || !C.d) return; const c = calc();
  if (!c || c.bad) return toast(T('badQty')); if (!c.any) return toast(T('needQty'));
  const reason = ($('#sr_reason') || {}).value; if (!reason) return toast(T('needReason'));
  const mode = ($('#sr_mode') || {}).value || null; if (c.refund > 0 && !mode) return toast(T('needMode'));
  const wallet = (($('#sr_wallet') || {}).value || '').trim(); if (mode === 'mobile' && !wallet) return toast(T('needWallet'));
  const lines = []; (C.d.lines || []).forEach((l, i) => { const el = $(`[data-rq="${i}"]`); if (el && el.value.trim()) lines.push({ item_id: l.item_id, qty: nnum(el.value) }); });
  const d = C.d, slip = B.tpl ? slipData(d, lines, c, reason) : null;   // bos98
  await U.submit(btn, () => sb.rpc('sale_return', { p_client: C.client, p_sale: d.sale_id, p_lines: lines, p_reason: reason, p_note: (($('#sr_note') || {}).value || '').trim() || null,
    p_refund_mode: c.refund > 0 ? mode : null, p_wallet: wallet || null, p_ref: (($('#sr_ref') || {}).value || '').trim() || null }),
    () => { toast(T('done')); if ($('#sr_list')) listView(); if (slip) tplSlip(slip, d.location_id); }, { grant: 'sale_return', loc: d.location_id, context: { sale: d.sale_id } });
}
// bos98: the return slip, only when the owner chose a sale_return template (B.tpl absent or nothing chosen: nothing printed, as before). Customer-facing numbers only, no cost.
function slipData(d, lines, c, reasonCode) {
  try {
    const items = lines.map((x) => { const l = (d.lines || []).find((z) => z.item_id === x.item_id) || {}; const f = Number(d.factor || 1); return { name: l.name || '', qty: x.qty, price: Number(l.price), amount: r2(x.qty * Number(l.price) * f) }; });
    return { no: '', date: today(), orig_no: String(d.receipt), reason: rLabel(reasonCode), customer: d.customer ? { name: d.customer } : null, items, subtotal: c.amt, vat: 0, refund: c.refund };
  } catch (e) { return null; }
}
async function tplSlip(data, loc) {
  try { if (!B.tpl || !B.tpl.ensure) return; await B.tpl.ensure(sb); const o = { lang: S.lang, loc, shop: {} }; if (B.tpl.printHTML('sale_return', data, undefined, o)) B.tpl.print('sale_return', data, undefined, o); } catch (e) { /* keep today's behaviour: nothing printed */ }
}

Object.assign(H, {
  sr_open: (a) => open(a.dataset.v),
  sr_menu: async (a) => { const s = D.rows[Number(a.dataset.i)]; if (!s) return; const ok = await grant('sale_return', s.location_id);
    openSheet(`<h2>${esc(T('receipt'))} #${esc(String(s.receipt))}</h2><div class="stack" style="margin-top:10px">${s.status === 'done' ? (ok ? `<button class="s2-act" data-act="sr_open2" data-v="${esc(s.id)}">${esc(T('doReturn'))}</button>` : npMode() === 'lock' ? `<div class="s2-lockrow">${LOCK}<span>${esc(T('doReturn'))} · ${esc(T('noperm'))}</span></div>` : '') : ''}
      <button class="s2-act" data-act="sr_open2" data-v="${esc(s.id)}">${esc(T('history'))}</button></div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`); },
  sr_open2: (a) => open(a.dataset.v),
  sr_go: goReturn,
  sr_void: (a) => { U.sheetStart('srvoid'); const id = a.dataset.v;
    openSheet(`<h2>${esc(T('voidRet'))}</h2><div><label for="vn_note">${esc(T('voidWhy'))}</label><input id="vn_note" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="sr_voidgo" data-v="${esc(id)}">${esc(T('voidRet'))}</button></div>`); },
  sr_voidgo: async (a) => { const n = (($('#vn_note') || {}).value || '').trim(); if (!n) return toast(T('voidWhy')); const d = C.d;
    await U.submit(a, () => sb.rpc('void_sale_return', { p_id: a.dataset.v, p_note: n }), () => { toast(T('voidDone')); if ($('#sr_list')) listView(); }, { grant: 'sale_return', loc: d ? d.location_id : null, context: { return: a.dataset.v } }); },
});
document.addEventListener('input', (e) => { if (e.target.dataset && e.target.dataset.rq !== undefined) recalc(); });
document.addEventListener('change', (e) => {
  const el = e.target;
  if (el.id === 'sr_loc') { D.loc = Number(el.value); listView(); }
  if (el.id === 'sr_date' && el.value) { D.date = el.value; listView(); }
  if (el.id === 'sr_mode') { const w = $('#sr_ww'); if (w) w.hidden = el.value !== 'mobile'; }
});
async function view() {
  const p = location.hash.replace(/^#\/?/, '').split('/');
  await listView(); if (p[1]) open(p[1]);
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { salereturn: view });
B.saleReturn = { open };
})();
