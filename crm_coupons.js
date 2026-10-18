/* Islamia BOS · CRM-F · Coupons and vouchers (#/crmcoupons) and the till helpers (BOS.crmf).
   Tabs: Coupons (list, new, edit, retire), Uses (redemption log), Liability (only used when the owner switched voucher liability on).
   Server: supabase/phase318.sql (crmf_coupon_save / list / check / redeem_after_sale / uses_list, crmf_voucher_liability_*).
   The till helpers at the bottom (BOS.crmf.couponCheck, couponRedeem, burnCheck, redeemPoints, referralCode, referralApply) are what the POS hooks in docs/integration/CRM-F.md call.
   English labels only (owner decision); the L() wrapper keeps the three modes ready for a later translation. UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const E = (s) => L(s, s, s);
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;

const X = {
  title: E('Coupons & vouchers'), t_list: E('Coupons'), t_uses: E('Uses'), t_liab: E('Liability'),
  hint: E('A coupon is a code worth a percent or an amount off a bill. Use it at the till in three steps: check the code, give the discount through the normal discount box, then record it after the sale.'),
  offNote: E('Coupons are switched OFF. You can prepare them here; the till cannot use them until the owner switches them on.'),
  blankMax: E('Set the largest percent and the largest amount in Settings first. A blank number blocks that kind of coupon.'),
  newc: E('New coupon'), code: E('Code'), name: E('Name'), kind: E('Kind'), percent: E('Percent'), amount: E('Amount (taka)'), value: E('Value'), from: E('Valid from'), to: E('Valid to'),
  more: E('More options'), minBill: E('Smallest bill'), maxDisc: E('Largest discount (percent coupons)'), maxUses: E('Total uses (blank = no limit)'), perCust: E('Uses per customer'),
  custMobile: E('For one customer only (mobile)'), outlets: E('Only at these places'), cats: E('Only for these item categories (comma separated)'), items: E('Only for these item codes (comma separated)'),
  campaign: E('Campaign reference'), note: E('Note'), liab: E('Book the unused value as a liability (amount coupons with a total use limit)'), over: E('Reason (needed only to go above the maximum - owner)'),
  save: E('Save'), cancel: E('Cancel'), saved: E('Saved'), edit: E('Edit'), retire: E('Retire'), reopen: E('Switch on again'), none: E('Nothing yet'),
  uses: E('uses'), left: E('left'), active: E('Active'), retired: E('Retired'), expired: E('Expired'), personal: E('One customer'), scope: E('Limited'),
  logTitle: E('Redemption log'), receipt: E('Receipt'), given: E('Discount given'), expected: E('Coupon gives'), mismatch: E('Different from the coupon'), override: E('Accepted with a reason'),
  liabHint: E('Only amount coupons marked "book the unused value" are booked, and only while the owner has switched voucher liability on. Entries have two lines and always balance.'),
  liabOff: E('Voucher liability is OFF. Nothing is booked.'), held: E('Held in the accounts'), should: E('Should hold'), sync: E('Bring the accounts up to date'), wind: E('Wind down to zero'),
  reason: E('Reason'), windGo: E('Release everything'), done: E('Done'), noperm: E('You do not have permission.'), nofn: E('The server does not have this feature yet (phase 316 to 319 not pasted).'),
  code2: E('Code (letters, digits, dash)'), filter: E('Show uses of'), all: E('All coupons'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: 'You do not have permission.', max_percent_not_set: 'Set the largest percent in Settings first.', max_amount_not_set: 'Set the largest amount in Settings first.',
  over_maximum: 'This is above the largest allowed. Only the owner can create it, with a reason.', reason_required: 'Write a reason (at least 3 letters).', bad_code: 'The code may use capital letters, digits and a dash (3 to 20).',
  code_exists: 'That code is already used.', bad_kind: 'Choose percent or amount.', value_required: 'Write the value.', name_required: 'Write a name.', validity_required: 'Choose the dates the coupon is valid.',
  bad_date: 'The end date is before the start date.', bad_number: 'A number is not valid.', locked_after_use: 'This coupon has been used, so its money terms cannot change. Retire it and make a new one.',
  liability_needs_amount_and_max_uses: 'Booking the liability needs an amount coupon with a total number of uses.', bad_location: 'Unknown place.', bad_item: 'Unknown item.', vouchers_off: 'Coupons are switched OFF.',
  period_closed: 'The accounts period is closed.', accounting_off: 'Accounting is switched off.', liability_accounts_needed: 'Set both accounts for voucher liability first.', customer_not_found: 'Customer not found.',
};
const eText = (e) => { const m = String((e && e.message) || ''); if (/could not find|does not exist|PGRST202/i.test(m + ' ' + ((e && e.code) || ''))) return lab(X.nofn); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) { const r = await sb.rpc(fn, args || {}); if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; } return r.data; }
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

const CP = { tab: 'list', list: [], uses: [], filter: '', liab: null, status: null, locs: [], client: rid() };
const locs = () => {
  const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
  return all.map((l) => ({ id: l.id, name: A.nm ? A.nm(l) : l.name_en || l.name_bn || l.code || String(l.id) }));
};
const TABS = [['list', 't_list'], ['uses', 't_uses'], ['liab', 't_liab']];
const tabsBar = () => `<div class="row wrap" id="cpn_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${CP.tab === k ? 'on' : ''}" data-act="cpn_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
const state = (c) => (!c.active ? 'retired' : (c.valid_to < today() ? 'expired' : 'active'));

function listHTML() {
  const off = CP.status && CP.status.voucher && !CP.status.voucher.on ? `<div class="notice" id="cpn_off">${esc(T('offNote'))}</div>` : '';
  const blank = CP.status && CP.status.voucher && (CP.status.voucher.max_percent == null || CP.status.voucher.max_amount == null) ? `<div class="notice" id="cpn_blank">${esc(T('blankMax'))}</div>` : '';
  const rows = CP.list.map((c) => {
    const st = state(c); const val_ = c.kind === 'percent' ? Number(c.value) + '%' : fm(c.value);
    const left = c.max_uses == null ? '' : ` · ${Math.max(Number(c.max_uses) - Number(c.uses), 0)} ${esc(T('left'))}`;
    return `<div class="card cp-row ${st !== 'active' ? 'muted' : ''}" data-code="${esc(c.code)}"><div class="row between"><b>${esc(c.code)}</b><b>${esc(val_)}</b></div>
      <div>${esc(c.name)}</div>
      <div class="muted">${esc(c.valid_from)} → ${esc(c.valid_to)} · ${Number(c.uses)} ${esc(T('uses'))}${left}${c.min_bill != null ? ' · min ' + fm(c.min_bill) : ''}</div>
      <div class="row wrap" style="gap:.3rem">${chip(T(st === 'active' ? 'active' : st), st === 'active' ? 'ok' : '')}${c.customer_id ? chip(T('personal')) : ''}${(c.scope || []).length ? chip(T('scope')) : ''}${c.post_liability ? chip(T('t_liab')) : ''}</div>
      <div class="row"><button type="button" class="mini" data-act="cpn_edit" data-v="${esc(c.code)}">${esc(T('edit'))}</button>
      <button type="button" class="mini" data-act="cpn_active" data-v="${esc(c.code)}">${esc(c.active ? T('retire') : T('reopen'))}</button>
      <button type="button" class="mini" data-act="cpn_log" data-v="${esc(c.code)}">${esc(T('t_uses'))}</button></div></div>`;
  }).join('');
  return `<p class="muted">${esc(T('hint'))}</p>${off}${blank}<div class="row"><button type="button" class="full primary" data-act="cpn_new">+ ${esc(T('newc'))}</button></div>${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function usesHTML() {
  const opts = `<option value="">${esc(T('all'))}</option>` + CP.list.map((c) => `<option value="${esc(c.id)}" ${CP.filter === c.id ? 'selected' : ''}>${esc(c.code)}</option>`).join('');
  const rows = CP.uses.map((u) => `<div class="card ${u.sale_status === 'void' ? 'muted' : ''}"><div class="row between"><b>${esc(u.code)}</b><b>${fm(u.discount_given)}</b></div>
    <div class="muted">${esc(T('receipt'))} ${esc(u.receipt)} · ${esc(String(u.sale_date))}${u.customer_name ? ' · ' + esc(u.customer_name) : ''}${u.sale_status === 'void' ? ' · void' : ''}</div>
    <div class="row wrap" style="gap:.3rem">${u.mismatch ? chip(T('mismatch') + ' (' + T('expected') + ' ' + fm(u.discount_expected) + ')') : ''}${u.override_reason ? chip(T('override')) : ''}</div></div>`).join('');
  return `<h3>${esc(T('logTitle'))}</h3>${fld('cpn_f', T('filter'), `<select id="cpn_f">${opts}</select>`)}${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function liabHTML() {
  const r = CP.liab; if (!r) return `<p class="muted">${esc(T('none'))}</p>`;
  const rows = (r.rows || []).map((x) => `<div class="card"><div class="row between"><b>${esc(x.code)}</b><span>${esc(T('held'))} ${fm(x.held)}</span></div><div class="muted">${esc(T('should'))} ${fm(x.should_hold)}</div></div>`).join('');
  return `<p class="muted">${esc(T('liabHint'))}</p>${r.on ? '' : `<div class="notice" id="lb_off">${esc(T('liabOff'))}</div>`}<div class="card"><b>${esc(T('held'))}: ${fm(r.held_total)}</b></div>
    <div class="row"><button type="button" class="full" data-act="lb_sync">${esc(T('sync'))}</button><button type="button" class="full" data-act="lb_wind">${esc(T('wind'))}</button></div>${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function draw() {
  const el = $('#cpn_body'); if (!el) return;
  el.innerHTML = tabsBar() + (CP.tab === 'list' ? listHTML() : CP.tab === 'uses' ? usesHTML() : liabHTML());
}
async function load(tab) {
  CP.tab = tab || CP.tab;
  try { CP.status = await call('crmf_status', {}); } catch (e) { CP.status = null; }
  if (CP.tab !== 'liab' || !CP.list.length) CP.list = await call('crmf_coupon_list', {});
  if (CP.tab === 'uses') CP.uses = await call('crmf_coupon_uses_list', { p_coupon: CP.filter || null, p_from: null, p_to: null, p_limit: 200 });
  if (CP.tab === 'liab') { try { CP.liab = await call('crmf_voucher_liability_report', {}); } catch (e) { CP.liab = null; toast(e.message); } }
  draw();
}

function formSheet(c) {
  const isNew = !c; const sc = (c && c.scope) || [];
  const chk = (id) => sc.some((s) => s.kind === 'location' && String(s.ref) === String(id)) ? 'checked' : '';
  const cats = sc.filter((s) => s.kind === 'category').map((s) => s.ref).join(', ');
  openSheet(`<h3>${esc(isNew ? T('newc') : c.code)}</h3><div class="stack" id="cpn_form">
    ${isNew ? fld('cf_code', T('code2'), inp('cf_code', '', 'maxlength="20" style="text-transform:uppercase"')) : ''}
    ${fld('cf_name', T('name'), inp('cf_name', c ? c.name : '', 'maxlength="80"'))}
    ${fld('cf_kind', T('kind'), `<select id="cf_kind" ${isNew ? '' : 'disabled'}><option value="percent" ${c && c.kind === 'percent' ? 'selected' : ''}>${esc(T('percent'))}</option><option value="amount" ${c && c.kind === 'amount' ? 'selected' : ''}>${esc(T('amount'))}</option></select>`)}
    ${fld('cf_value', T('value'), inp('cf_value', c ? c.value : '', 'inputmode="decimal"'))}
    ${fld('cf_from', T('from'), inp('cf_from', c ? c.valid_from : today(), 'type="date"'))}${fld('cf_to', T('to'), inp('cf_to', c ? c.valid_to : '', 'type="date"'))}
    <details id="cf_more"><summary>${esc(T('more'))}</summary><div class="stack">
      ${fld('cf_min', T('minBill'), inp('cf_min', c && c.min_bill != null ? c.min_bill : '', 'inputmode="decimal"'))}${fld('cf_cap', T('maxDisc'), inp('cf_cap', c && c.max_discount != null ? c.max_discount : '', 'inputmode="decimal"'))}
      ${fld('cf_max', T('maxUses'), inp('cf_max', c && c.max_uses != null ? c.max_uses : '', 'inputmode="numeric"'))}${fld('cf_per', T('perCust'), inp('cf_per', c ? c.per_customer_uses : 1, 'inputmode="numeric"'))}
      ${isNew ? fld('cf_cust', T('custMobile'), inp('cf_cust', '', 'inputmode="numeric" maxlength="14"')) : ''}
      <div><label>${esc(T('outlets'))}</label>${locs().map((l) => `<label class="row"><input type="checkbox" class="cf_loc" value="${l.id}" ${chk(l.id)} ${isNew ? '' : 'disabled'}> ${esc(l.name)}</label>`).join('')}</div>
      ${fld('cf_cats', T('cats'), inp('cf_cats', cats, isNew ? '' : 'disabled'))}${fld('cf_items', T('items'), inp('cf_items', '', isNew ? '' : 'disabled'))}
      ${fld('cf_camp', T('campaign'), inp('cf_camp', c ? c.campaign_ref || '' : '', 'maxlength="60"'))}${fld('cf_note', T('note'), inp('cf_note', c ? c.note || '' : '', 'maxlength="300"'))}
      <label class="row"><input type="checkbox" id="cf_liab" ${c && c.post_liability ? 'checked' : ''} ${isNew ? '' : 'disabled'}> ${esc(T('liab'))}</label>
      ${S.ctx && S.ctx.is_owner ? fld('cf_over', T('over'), inp('cf_over', '', 'maxlength="300"')) : ''}
    </div></details>
    <div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="cpn_savego" data-v="${esc(c ? c.id : '')}">${esc(T('save'))}</button></div></div>`);
}
async function itemIds(codes) {
  if (!codes.length) return [];
  const r = await sb.from('items').select('id,code').in('code', codes);
  const m = {}; (r.data || []).forEach((x) => { m[x.code] = x.id; });
  const miss = codes.filter((c) => !m[c]); if (miss.length) throw new Error(ERR.bad_item + ' ' + miss.join(', '));
  return codes.map((c) => m[c]);
}
Object.assign(H, {
  cpn_tab: act(async (a) => { await load(a.dataset.v); }),
  cpn_new: () => formSheet(null),
  cpn_edit: (a) => formSheet(CP.list.find((x) => x.code === a.dataset.v)),
  cpn_active: act(async (a) => { const c = CP.list.find((x) => x.code === a.dataset.v); if (!c) return; await call('crmf_coupon_save', { p_id: c.id, p: { active: !c.active }, p_client: null, p_override: null }); toast(T('saved')); CP.list = []; await load('list'); }),
  cpn_log: act(async (a) => { const c = CP.list.find((x) => x.code === a.dataset.v); CP.filter = c ? c.id : ''; await load('uses'); }),
  cpn_savego: act(async (a) => {
    const id = a.dataset.v || null; const p = {};
    const num = (k, s, nm) => { const v = nnum(val(s)); if (Number.isNaN(v)) throw new Error(ERR.bad_number); if (v !== null) p[k] = v; else if (id) p[k] = null; };
    if (!id) { p.code = val('cf_code').toUpperCase(); p.kind = val('cf_kind'); }
    const used = id ? Number((CP.list.find((x) => x.id === id) || {}).uses || 0) : 0;     // after the first use the money terms are locked on the server, so they are not sent
    p.name = val('cf_name'); p.valid_from = val('cf_from'); p.valid_to = val('cf_to');
    if (!used) { num('value', 'cf_value'); num('min_bill', 'cf_min'); num('max_discount', 'cf_cap'); }
    num('max_uses', 'cf_max'); const pc = nnum(val('cf_per')); if (pc !== null && !Number.isNaN(pc)) p.per_customer_uses = pc;
    p.campaign_ref = val('cf_camp'); p.note = val('cf_note');
    if (!id) {
      const cm = norm(val('cf_cust'));
      if (cm) { const r = await sb.from('customers').select('id').eq('mobile', cm).limit(1); if (!r.data || !r.data[0]) throw new Error(ERR.customer_not_found); p.customer_id = r.data[0].id; }
      p.post_liability = !!($('#cf_liab') || {}).checked;
      const L_ = [...document.querySelectorAll('.cf_loc:checked')].map((x) => Number(x.value));
      const cats = val('cf_cats').split(',').map((s) => s.trim()).filter(Boolean); const items = await itemIds(val('cf_items').split(',').map((s) => s.trim()).filter(Boolean));
      if (L_.length || cats.length || items.length) p.scope = { locations: L_, categories: cats, items };
    }
    await call('crmf_coupon_save', { p_id: id, p, p_client: id ? null : CP.client, p_override: val('cf_over') || null });
    if (!id) CP.client = rid();
    closeSheet(); toast(T('saved')); CP.list = []; await load('list');
  }),
  lb_sync: act(async () => { const r = await call('crmf_voucher_liability_sync', {}); toast(r && r.off ? T('liabOff') : T('done')); await load('liab'); }),
  lb_wind: () => openSheet(`<h3>${esc(T('wind'))}</h3><div class="stack">${fld('wd_why', T('reason'), inp('wd_why', '', 'maxlength="300"'))}<div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="lb_windgo">${esc(T('windGo'))}</button></div></div>`),
  lb_windgo: act(async () => { const w = val('wd_why'); if (w.length < 3) return toast(ERR.reason_required); await call('crmf_voucher_liability_wind_down', { p_reason: w }); closeSheet(); toast(T('done')); await load('liab'); }),
});
document.addEventListener('change', (e) => { const t = e.target; if (t && t.id === 'cpn_f') { CP.filter = t.value; load('uses').catch((er) => toast(er.message)); } });

async function viewCoupons() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="cpn_body"><p class="muted">…</p></div>', true);
  try { await load(CP.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmcoupons: viewCoupons });


// ------------------------------------------------------------------ the coupon box in the POS cart sheet (hooks 1 to 3 of docs/integration/CRM-F.md)
// posBox() draws a placeholder; it fills in only when coupons are ON and the person may sell. The cashier types the code, "Check" asks the server and fills the normal discount box with
// the answer (the normal discount rules and approval still apply); after the sale, afterSale() records the use. Nothing here decides a right: the server does.
const CF = { status: null, at: 0, pending: null };
async function cfStatus() {
  if (CF.status && Date.now() - CF.at < 60000) return CF.status;
  try { CF.status = (await call('crmf_status', {})) || { voucher: { on: false } }; } catch (e) { CF.status = { voucher: { on: false } }; }
  CF.at = Date.now(); return CF.status;
}
const REASON = {
  not_found: 'Coupon code not found.', retired: 'This coupon is switched off.', not_started: 'This coupon has not started yet.', expired: 'This coupon has expired.', wrong_outlet: 'This coupon is not for this place.',
  min_bill: 'The bill is smaller than this coupon needs.', wrong_customer: 'This coupon belongs to another customer.', customer_needed: 'Type the customer mobile first: this coupon needs the customer.',
  customer_limit: 'This customer has already used this coupon the allowed number of times.', used_up: 'This coupon has been used up.', nothing_in_scope: 'Nothing in this bill is covered by the coupon.',
  sale_has_coupon: 'This sale already has a coupon.',
};
const XB = { code: E('Coupon code'), check: E('Check'), ok: E('Coupon accepted. Discount filled in:'), mism: E('The discount on the bill is different from the coupon. A yellow line was written for the owner.'), failed: E('The coupon could not be recorded:') };
function posBox() {
  CF.pending = null;
  setTimeout(async () => {
    const el = $('#crmf_box'); if (!el) return;
    const st = await cfStatus(); if (!st.voucher || !st.voucher.on) return;
    el.innerHTML = `<div class="stack" style="margin-top:8px"><label for="crmf_cp">${esc(lab(XB.code))}</label><div class="row"><input id="crmf_cp" autocomplete="off" style="text-transform:uppercase" maxlength="20"><button type="button" class="mini" data-act="crmf_cp_check">${esc(lab(XB.check))}</button></div><div class="muted" id="crmf_cp_out"></div></div>`;
  }, 0);
  return '<div id="crmf_box"></div>';
}
Object.assign(H, {
  crmf_cp_check: act(async () => {
    const ctx = B.pos && B.pos.ctx ? B.pos.ctx() : null; const out = $('#crmf_cp_out'); if (!ctx) return toast(T('nofn'));
    const code = val('crmf_cp').toUpperCase(); if (!code) return;
    const r = await call('crmf_coupon_check', { p_code: code, p_loc: ctx.loc, p_customer: ctx.customerId || null, p_lines: ctx.lines.map((l) => ({ item_id: l.item_id || null, qty: l.qty, price: l.price, amount: l.amount })), p_subtotal: ctx.sub, p_override: null });
    if (r && r.ok) { CF.pending = { code, discount: Number(r.discount) }; ctx.setDiscount(Number(r.discount)); if (out) out.textContent = lab(XB.ok) + ' ' + fm(r.discount); }
    else { CF.pending = null; if (out) out.textContent = REASON[r && r.reason] || String((r && r.reason) || ''); }
  }),
});
async function afterSale(saleId) {
  const pend = CF.pending; CF.pending = null; if (!pend || !saleId) return;
  try {
    const r = await call('crmf_coupon_redeem_after_sale', { p_code: pend.code, p_sale: saleId, p_override: null, p_client: rid() });
    if (!r.ok) toast(lab(XB.failed) + ' ' + (REASON[r.reason] || r.reason)); else if (r.mismatch) toast(lab(XB.mism));
  } catch (e) { toast(lab(XB.failed) + ' ' + (e.message || '')); }
}

// ------------------------------------------------------------------ till helpers (the POS hooks of docs/integration/CRM-F.md call these; each is one server call and never throws on a business refusal)
B.crmf = Object.assign(B.crmf || {}, {
  // lines = [{item_id, qty, price}] or the sale lines; subtotal = bill before discount. Answer: {ok, discount, reason, ...}
  couponCheck: (code, loc, customerId, lines, subtotal, override) => call('crmf_coupon_check', { p_code: code, p_loc: loc, p_customer: customerId || null, p_lines: lines || [], p_subtotal: subtotal, p_override: override || null }),
  couponRedeem: (code, saleId, override, client) => call('crmf_coupon_redeem_after_sale', { p_code: code, p_sale: saleId, p_override: override || null, p_client: client || rid() }),
  burnCheck: (customerId, points, bill) => call('crmf_burn_check', { p_customer: customerId, p_points: points == null ? null : points, p_bill: bill == null ? null : bill }),
  redeemPoints: (customerId, points, bill, note, client, dry, override) => call('crmf_points_redeem', { p_customer: customerId, p_points: points, p_bill: bill == null ? null : bill, p_note: note || null, p_client: client || rid(), p_dry: !!dry, p_override: override || null }),
  referralCode: (customerId) => call('crmf_referral_code', { p_customer: customerId }),
  referralApply: (customerId, code, client) => call('crmf_referral_apply', { p_referred: customerId, p_code: code, p_client: client || rid() }),
  errText: eText, posBox, afterSale,
});
})();
