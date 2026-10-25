/* Islamia BOS · Profit check (#/profitcheck): ONE profit number.
   - the settings of phases 92 and 93 (owner changes them any time; every change is written to audit_log by the server),
   - management profit against the journal profit, the difference by named cause (profit_recon),
   - the exception path: leave ONE named loss out of the profit with a written reason (profit_exclude / profit_exclusion_revoke),
   - the same expense and salary totals in the day book, the profit report, the expense report and the journal (report_parity),
   - the dated brand map (brand_map_hist_list / brand_map_set; a change from a past date needs a reason).
   Server: supabase/phase92.sql and supabase/phase93.sql. The page only shows and sends; the server decides every right and every number. English labels only (owner rule). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm, S } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);                         // one text in the three language slots: the owner asked for English labels only
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: E('Profit check'),
  intro: E('One profit number: the profit shown for branches, the owner sheet, break-even and partner shares. Nothing here changes a figure until you switch it on.'),
  settings: E('Settings'), readonly: E('Only the owner can change these.'), on: E('On'), off: E('Off'), save: E('Save'), saved: E('Saved'), blank: E('Blank'), notInstalled: E('The settings of this screen are not installed on the server yet.'),
  compare: E('Compare management profit with the journal'), from: E('From'), to: E('To'), place: E('Place'), allPlaces: E('All places'), run: E('Compare'),
  mgmt: E('Management profit'), ledger: E('Journal profit'), diff: E('Difference'), explained: E('Explained'), unexplained: E('Not explained'), unposted: E('Documents not posted yet'),
  line: E('Line'), jr: E('Journal'), none: E('Nothing'), ifOn: E('If you count it, profit changes by'), noJournal: E('The journal has no figures for this period.'),
  parity: E('Same totals everywhere?'), expenses: E('Expenses'), salary: E('Salary'), dayBook: E('Day book'), pl: E('Profit report'), expRep: E('Expense report'), journal: E('Journal'), agree: E('Agree'), differs: E('Differ'), paid: E('Paid out'),
  excl: E('Leave one loss out of the profit'), exclHint: E('An exception. It needs a written reason, it is written to the audit log and to the Exceptions list. You can count the loss again at any time.'),
  cause: E('Kind of loss'), srcId: E('Record id'), reason: E('Reason (at least 5 letters)'), leave: E('Leave it out'), revoke: E('Count it again'), active: E('Left out'), revoked: E('Counted again'),
  brand: E('Brand of each place'), brandHint: E('A change counts from the date you choose. A date in the past rewrites history, so it needs a reason and is shown in the Exceptions list.'),
  code: E('Brand code'), nameBn: E('Name (first language)'), nameEn: E('Name (English)'), setBrand: E('Change the brand'), validFrom: E('From'), validTo: E('To'), open: E('open'), retired: E('replaced'),
  noperm: E('Not allowed'),
};
const T = (k) => lab(X[k]);
const CAUSES = [['wastage', E('Wasted stock')], ['count_shrink', E('Stock count shortage')], ['transit_loss', E('Goods lost in transit')], ['cash_short', E('Cash short and over')], ['bill_opex', E('Running cost paid by supplier bill')], ['overhead_absorbed', E('Factory overhead absorbed into products')]];
const REASONS = {
  count_adjustment_not_in_journal_yet: E('A stock count shortage is not written to the books yet.'), cash_short_not_posted_to_journal: E('Cash short is not posted to the books (its posting switch is off).'),
  not_counted_in_management_profit_switch_off: E('Not counted in the profit because the master switch is off.'), this_cause_is_switched_off: E('Not counted because this kind of loss is switched off.'),
  before_the_start_date: E('Part of it is before the start date.'), left_out_by_owner_exception: E('Left out by an owner exception.'), fixed_cost_is_management_only: E('Fixed cost exists only in the management profit.'),
  salary_basis_differs_forms_runs_or_payments: E('Salary: forms, payroll runs and payments are counted on different bases.'), voucher_status_basis_differs: E('Vouchers: a different status is counted in each report.'),
  journal_only_entries_manual_depreciation_charges_opening: E('Journal-only entries: manual journals, depreciation, charges.'), documents_not_posted_to_journal_yet: E('Some documents are not posted to the journal yet.'),
  period_starts_before_accounting_start: E('The period starts before the accounting start date.'), journal_not_started: E('The journal has not started.'),
};
const ERR = {
  not_allowed: X.noperm, reason_required: E('Write a reason of at least 5 letters'), bad_cause: E('Choose a kind of loss'), row_not_found: E('That record was not found'), already_excluded: E('That loss is already left out'),
  not_active: E('That exception is no longer active'), bad_range: E('The dates are not valid'), future_date_not_allowed: E('A future date is not allowed'), location_not_found: E('Place not found'), bad_brand: E('Fill the brand code and both names'),
  bad_value: E('That value is not allowed'), too_long: E('The text is too long'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const KEYS = ['profit_one_number_on', 'profit_losses_from', 'profit_loss_wastage', 'profit_loss_count', 'profit_loss_transit', 'profit_loss_cashshort', 'profit_loss_billopex', 'profit_overhead_once', 'profit_source',
  'report_salary_source', 'report_expense_parity_on', 'expense_count_on', 'brand_map_dated_on'];
const D = { rules: [], excl: [], hist: [], from: null, to: null, loc: '', recon: null, parity: null };
const owner = () => !!(S && S.ctx && S.ctx.is_owner);
const val = (r) => (r.value !== null && r.value !== undefined ? r.value : r.default_value);

async function load() {
  const [r, x, h] = await Promise.all([sb.from('rules').select('key,kind,value,default_value,choices,label_en,hint_en,sort').in('key', KEYS).order('sort'), sb.rpc('profit_exclusions_list', { p_status: null }), sb.rpc('brand_map_hist_list', { p_loc: null })]);
  D.rules = ((r && r.data) || []).sort((a, b) => (a.sort || 0) - (b.sort || 0));
  D.excl = x && !x.error ? x.data || [] : []; D.hist = h && !h.error ? h.data || [] : [];
}
function ruleHTML(r) {
  const v = val(r), id = 'pc_r_' + r.key;
  let ctl = '';
  if (r.kind === 'switch') ctl = `<button class="chip ${v === true ? 'ok' : ''}" data-act="pc_sw" data-k="${esc(r.key)}" data-on="${v === true ? '1' : '0'}" ${owner() ? '' : 'disabled'} aria-pressed="${v === true}">${esc(v === true ? T('on') : T('off'))}</button>`;
  else if (r.kind === 'choice') ctl = `<select id="${id}" class="pc_sel" data-k="${esc(r.key)}" ${owner() ? '' : 'disabled'}>${(r.choices || []).map((c) => `<option value="${esc(c)}" ${c === v ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>`;
  else ctl = `<span class="row"><input id="${id}" type="date" value="${esc(v || '')}" ${owner() ? '' : 'disabled'} aria-label="${esc(r.label_en)}"><button data-act="pc_text" data-k="${esc(r.key)}" ${owner() ? '' : 'disabled'}>${esc(T('save'))}</button></span>`;
  return `<div class="card stack" data-key="${esc(r.key)}"><div class="row between"><b>${esc(r.label_en)}</b>${ctl}</div><p class="muted">${esc(r.hint_en || '')}</p></div>`;
}
function settingsHTML() {
  if (!D.rules.length) return `<p class="muted">${esc(T('notInstalled'))}</p>`;
  return (owner() ? '' : `<p class="muted">${esc(T('readonly'))}</p>`) + D.rules.map(ruleHTML).join('');
}
function compareHTML() {
  const locs = LOCS ? LOCS() : [];
  return `<div class="card stack"><b>${esc(T('compare'))}</b>
    <div><label for="pc_from">${esc(T('from'))}</label><input id="pc_from" type="date" value="${esc(D.from)}"></div>
    <div><label for="pc_to">${esc(T('to'))}</label><input id="pc_to" type="date" value="${esc(D.to)}"></div>
    <div><label for="pc_loc">${esc(T('place'))}</label><select id="pc_loc"><option value="">${esc(T('allPlaces'))}</option>${locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <button class="full primary" data-act="pc_cmp">${esc(T('run'))}</button><div id="pc_out"></div></div>`;
}
const num = (n) => (n === null || n === undefined ? '-' : money(n));
function reconHTML(r) {
  if (!r) return '';
  const rows = (r.rows || []).filter((x) => Number(x.management) !== 0 || Number(x.ledger || 0) !== 0 || Number(x.difference || 0) !== 0).map((x) => {
    const why = x.reason ? (REASONS[x.reason] ? lab(REASONS[x.reason]) : x.reason) : (Number(x.difference || 0) !== 0 ? lab(E('Not explained - check this line.')) : '');
    return `<div class="card stack"><div class="row between"><b>${esc(x.label_en)}</b><span class="chip ${Number(x.difference || 0) === 0 ? 'ok' : (x.reason ? '' : 'warn')}">${esc(T('diff'))} ${esc(num(x.difference))}</span></div>
      <div class="row between"><span>${esc(T('mgmt'))} ${esc(num(x.management))}</span><span>${esc(T('jr'))} ${esc(num(x.ledger))}</span></div>${why ? `<p class="muted">${esc(why)}</p>` : ''}</div>`;
  }).join('');
  const would = Object.keys(r.would_add_if_counted || {}).map((k) => { const c = CAUSES.find((z) => z[0] === k); return `<div class="row between"><span>${esc(c ? lab(c[1]) : k)}</span><b>${esc(money(r.would_add_if_counted[k].amount))}</b></div>`; }).join('');
  return `<div class="card stack"><div class="row between"><span>${esc(T('mgmt'))}</span><b>${esc(num(r.management_profit))}</b></div>
    <div class="row between"><span>${esc(T('ledger'))}</span><b>${esc(num(r.ledger_profit))}</b></div>
    <div class="row between"><span>${esc(T('diff'))}</span><b>${esc(num(r.difference))}</b></div>
    <div class="row between"><span>${esc(T('explained'))}</span><span>${esc(num(r.explained))}</span></div>
    <div class="row between"><span>${esc(T('unexplained'))}</span><span class="chip ${Number(r.unexplained) === 0 ? 'ok' : 'warn'}">${esc(num(r.unexplained))}</span></div>
    ${r.ledger_note ? `<p class="muted">${esc(r.ledger_note)}</p>` : ''}</div>${rows}${would ? `<div class="card stack"><b>${esc(T('ifOn'))}</b>${would}</div>` : ''}`;
}
function parityHTML(p) {
  if (!p) return '';
  const e = p.expenses || {}, s = p.salary || {};
  const chip = (ok) => `<span class="chip ${ok ? 'ok' : 'warn'}">${esc(ok ? T('agree') : T('differs'))}</span>`;
  return `<div class="card stack"><div class="row between"><b>${esc(T('expenses'))}</b>${chip(!!e.agree)}</div>
    <div class="row between"><span>${esc(T('dayBook'))}</span><span>${esc(num(e.daybook))}</span></div><div class="row between"><span>${esc(T('pl'))}</span><span>${esc(num(e.pl))}</span></div>
    <div class="row between"><span>${esc(T('expRep'))}</span><span>${esc(num(e.expense_report))}</span></div><div class="row between"><span>${esc(T('journal'))}</span><span>${esc(num(e.journal))}</span></div></div>
    <div class="card stack"><div class="row between"><b>${esc(T('salary'))}</b>${chip(!!s.pl_agrees_journal)}</div>
    <div class="row between"><span>${esc(T('pl'))}</span><span>${esc(num(s.pl))}</span></div><div class="row between"><span>${esc(T('journal'))}</span><span>${esc(num(s.journal))}</span></div>
    <div class="row between"><span>${esc(T('dayBook'))} (${esc(T('paid'))})</span><span>${esc(num(s.daybook_paid))}</span></div><p class="muted">${esc(s.note || '')}</p></div>`;
}
function exclHTML() {
  const cl = (c) => { const z = CAUSES.find((q) => q[0] === c); return z ? lab(z[1]) : c; };
  const list = D.excl.map((x) => `<div class="card stack"><div class="row between"><b>${esc(cl(x.cause))}</b><span class="chip ${x.status === 'active' ? 'warn' : ''}">${esc(x.status === 'active' ? T('active') : T('revoked'))}</span></div>
    <div class="row between"><span>${esc(String(x.row_date || ''))}</span><b>${esc(num(x.amount))}</b></div><p class="muted">${esc(x.reason || '')}${x.revoke_reason ? ' / ' + esc(x.revoke_reason) : ''}</p>
    ${x.status === 'active' ? `<div class="row"><input id="pc_rv_${esc(x.id)}" autocomplete="off" aria-label="${esc(T('reason'))}" placeholder="${esc(T('reason'))}"><button data-act="pc_unexcl" data-v="${esc(x.id)}">${esc(T('revoke'))}</button></div>` : ''}</div>`).join('');
  return `<div class="card stack"><b>${esc(T('excl'))}</b><p class="muted">${esc(T('exclHint'))}</p>
    <div><label for="pc_xc">${esc(T('cause'))}</label><select id="pc_xc">${CAUSES.map(([k, l]) => `<option value="${k}">${esc(lab(l))}</option>`).join('')}</select></div>
    <div><label for="pc_xs">${esc(T('srcId'))}</label><input id="pc_xs" autocomplete="off"></div>
    <div><label for="pc_xr">${esc(T('reason'))}</label><input id="pc_xr" autocomplete="off"></div>
    <button class="full" data-act="pc_excl">${esc(T('leave'))}</button></div>${list}`;
}
function brandHTML() {
  const locs = LOCS ? LOCS() : [];
  const rows = D.hist.map((h) => `<div class="card stack"><div class="row between"><b>${esc(h.brand_en)}</b><span class="chip ${h.active ? (h.valid_to ? '' : 'ok') : ''}">${esc(h.active ? (h.valid_to ? '' : T('open')) : T('retired'))}</span></div>
    <div class="row between"><span>#${esc(h.location_id)}</span><span>${esc(h.valid_from || '...')} - ${esc(h.valid_to || '')}</span></div>${h.reason ? `<p class="muted">${esc(h.reason)}</p>` : ''}</div>`).join('');
  return `<div class="card stack"><b>${esc(T('brand'))}</b><p class="muted">${esc(T('brandHint'))}</p>
    <div><label for="pc_bl">${esc(T('place'))}</label><select id="pc_bl">${locs.map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="pc_bc">${esc(T('code'))}</label><input id="pc_bc" autocomplete="off"></div>
    <div><label for="pc_bb">${esc(T('nameBn'))}</label><input id="pc_bb" autocomplete="off"></div>
    <div><label for="pc_be">${esc(T('nameEn'))}</label><input id="pc_be" autocomplete="off"></div>
    <div><label for="pc_bf">${esc(T('validFrom'))}</label><input id="pc_bf" type="date" value="${esc(today())}"></div>
    <div><label for="pc_br">${esc(T('reason'))}</label><input id="pc_br" autocomplete="off"></div>
    <button class="full primary" data-act="pc_brand" ${owner() ? '' : 'disabled'}>${esc(T('setBrand'))}</button></div>${rows}`;
}
function page() {
  return `<p class="muted">${esc(T('intro'))}</p><h3>${esc(T('settings'))}</h3>${settingsHTML()}${compareHTML()}${exclHTML()}<h3>${esc(T('parity'))}</h3><div id="pc_par"></div>${brandHTML()}`;
}
async function show() { const el = $('#pc_body'); if (!el) return; await load(); el.innerHTML = page(); if (D.recon) { const o = $('#pc_out'); if (o) o.innerHTML = reconHTML(D.recon); } if (D.parity) { const p = $('#pc_par'); if (p) p.innerHTML = parityHTML(D.parity); } }
const setRule = async (k, v) => {
  const r = await sb.rpc('set_rule', { p_key: k, p_value: v });
  if (r.error) return toast(eText(r.error));
  try { if (B.reloadRules) await B.reloadRules(); } catch (e) { /* ignore */ }
  toast(T('saved')); await show();
};
Object.assign(H, {
  pc_sw: (a) => setRule(a.dataset.k, a.dataset.on !== '1'),
  pc_choice: (a) => setRule(a.dataset.k, a.value),      // called by the change listener below, not by a click
  pc_text: (a) => { const el = $('#pc_r_' + a.dataset.k); const v = el ? el.value.trim() : ''; return setRule(a.dataset.k, v === '' ? null : v); },
  pc_cmp: async () => {
    D.from = $('#pc_from').value; D.to = $('#pc_to').value; D.loc = $('#pc_loc').value;
    if (!D.from || !D.to || D.to < D.from) return toast(lab(ERR.bad_range));
    const loc = D.loc === '' ? null : Number(D.loc);
    const [r, p] = await Promise.all([sb.rpc('profit_recon', { p_from: D.from, p_to: D.to, p_loc: loc }), sb.rpc('report_parity', { p_from: D.from, p_to: D.to, p_loc: loc })]);
    if (r.error) return toast(eText(r.error));
    D.recon = r.data; D.parity = p.error ? null : p.data;
    $('#pc_out').innerHTML = reconHTML(D.recon); $('#pc_par').innerHTML = parityHTML(D.parity);
  },
  pc_excl: async () => {
    const why = ($('#pc_xr').value || '').trim(); const src = ($('#pc_xs').value || '').trim();
    if (why.length < 5) return toast(lab(ERR.reason_required)); if (!src) return toast(lab(ERR.row_not_found));
    const r = await sb.rpc('profit_exclude', { p_cause: $('#pc_xc').value, p_source_id: src, p_reason: why });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); await show();
  },
  pc_unexcl: async (a) => {
    const el = $('#pc_rv_' + a.dataset.v); const why = el ? el.value.trim() : '';
    if (why.length < 5) return toast(lab(ERR.reason_required));
    const r = await sb.rpc('profit_exclusion_revoke', { p_id: Number(a.dataset.v), p_reason: why });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); await show();
  },
  pc_brand: async () => {
    const code = ($('#pc_bc').value || '').trim(), bn = ($('#pc_bb').value || '').trim(), en = ($('#pc_be').value || '').trim(), from = $('#pc_bf').value || null, why = ($('#pc_br').value || '').trim();
    if (!code || !bn || !en) return toast(lab(ERR.bad_brand));
    if (from && from < today() && why.length < 5) return toast(lab(ERR.reason_required));      // the server asks for it too
    const r = await sb.rpc('brand_map_set', { p_loc: Number($('#pc_bl').value), p_code: code, p_bn: bn, p_en: en, p_from: from, p_reason: why || null });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); await show();
  },
});
document.addEventListener('change', (e) => { if (e.target && e.target.classList && e.target.classList.contains('pc_sel')) H.pc_choice(e.target); });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const t = today(); D.to = t; D.from = t.slice(0, 8) + '01'; D.recon = null; D.parity = null;
  shell(T('title'), '<div id="pc_body"><p class="muted">…</p></div>', true);
  try { await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { profitcheck: view });
})();
