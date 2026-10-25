/* Islamia BOS · Money Accounts (#/moneyaccounts). The one settings screen for where money lives and where it comes from:
   cash drawers (per place), mobile wallets (any provider, per number), bank accounts. The owner adds, renames and deactivates accounts (never deletes),
   sets a default source / allow-override / require-source for every payment type, moves money between accounts (with an optional fee), records bank charges
   and interest, reads a statement per account, a period summary, types the real balance (blind), sees the Exceptions list, chooses the approver (any role,
   any named person, or per entry) and reads P&L / balance sheet with a line per account.
   Server: supabase/phase87.sql (money_account_add / update / set_active / money_accounts_list, money_event_setting(s), money_transfer_add / void, money_charge_add / void,
   money_statement(_csv), money_summary, money_check_save / explain / list, money_exceptions_list / exception_grant / resolve, money_statements, money_salary_sources,
   money_recurring_*, owner_approval_mode(_set2), entry_approver_set). The payment screens use the shared picker BOS.moneySrc (web/moneysrc.js).
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const guardCsv = (t) => String(t).replace(/(^|,|\n)("?)([=+\-@\t\r])(?!\d*(\.\d+)?(,|\n|"|$))/g, "$1$2'$3");   // spreadsheet formula guard: a cell starting with = + - @ tab CR gets a leading apostrophe (plain numbers are left alone)
const val = (id) => (($('#' + id) || {}).value || '').trim();
const monthStart = () => today().slice(0, 8) + '01';
const locs = () => {
  const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
  const wide = S.ctx.is_owner || (S.ctx.roles || []).includes('management');
  return (wide ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id))).map((l) => ({ id: l.id, name: A.nm ? A.nm(l) : l.name_en || l.name_bn || l.code || String(l.id) }));
};
const locName = (id) => { const l = locs().find((x) => String(x.id) === String(id)); return l ? l.name : id == null ? 'Company' : '#' + id; };

const TABS = [['accounts', 'Accounts'], ['defaults', 'Payment defaults'], ['move', 'Transfers & charges'], ['statement', 'Statement'], ['summary', 'Summary'], ['check', 'Real balance'],
  ['exceptions', 'Exceptions'], ['approvers', 'Approvers'], ['reports', 'Reports']];
const KIND = { cash: 'Cash drawer', wallet: 'Mobile wallet', bank: 'Bank account' };
const EV_RULE = { negative: 'Negative balance (block)', require_source: 'Source required', override: 'Different source / other place', period_lock: 'Closed period', approver: 'Approver' };
const ERR = {
  not_allowed: 'You do not have permission.', money_negative: 'The account does not hold that much (balance would go below zero). The owner can allow one exception.',
  money_source_required: 'Choose the payment source.', money_source_fixed: 'The owner fixed the source for this payment type.', money_account_place: 'That cash drawer belongs to another place.',
  money_account_inactive: 'That account is switched off.', unknown_money_account: 'Unknown account.', same_account: 'Choose two different accounts.', account_not_empty: 'The account still has a balance or unposted payments.',
  account_is_default: 'The account is the default for a payment type: change that first.', account_in_recurring: 'The account is used by an active repeat transfer.', account_exists: 'This account already exists.',
  reason_required: 'Write a reason.', note_required: 'Write a reason.', bad_amount: 'Amount is not valid.', bad_date: 'Date is not valid.', place_required: 'Choose the place.', fee_exceeds_amount: 'The fee is bigger than the amount.',
  provider_and_number_required: 'Bank/wallet name and number are required.', opening_exists_use_topup: 'The opening balance is already posted: fund this account by an owner top-up or a transfer.',
  period_closed: 'This period is closed.', designated_approver_only: 'Only the approver chosen for this entry can decide it.', named_approver_only: 'Only the named approver can decide this.',
  owner_cannot_be_approver: 'The owner cannot name himself.', unknown_user: 'Unknown or inactive person.', data_needed: 'Accounting start date is not set.', coa_not_usable: 'That chart account cannot be used.',
  coa_already_mapped: 'That chart account is already a money account.', coa_is_legacy_wallet: 'That is a legacy wallet account (use the Mobile wallets screen).', coa_kind_mismatch: 'The chart account does not match the kind.',
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const D = { tab: 'accounts', acc: [], ready: true, legacy: [], settings: [], ex: null, mode: null, people: [], roles: [], st: null, sm: null, rp: null, checks: [], moves: [], from: monthStart(), to: today(), sel: null, last: null, client: { tr: rid(), ch: rid(), ck: rid() } };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const accName = (id) => { const a = D.acc.find((x) => String(x.id) === String(id)); return a ? a.name_en : '#' + id; };
const accOpts = (sel, only) => D.acc.filter((a) => a.active && (!only || only(a))).map((a) => `<option value="${a.id}" ${String(a.id) === String(sel) ? 'selected' : ''}>${esc(a.name_en)} · ${esc(KIND[a.kind])}</option>`).join('');
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;

async function loadAcc() { const r = await call('money_accounts_list', {}); D.acc = r.rows || []; D.ready = r.ready !== false; D.legacy = r.legacy_wallets || []; }

// ---------------- tabs ----------------
function tabsBar() { return `<div class="row wrap" id="ma_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="ma_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`; }

function accountsHTML() {
  const warn = D.ready ? '' : `<div class="notice bad" id="ma_notready">Accounting is not switched on or its start date is empty: payments are recorded, balances and statements show after that.</div>`;
  const rows = D.acc.map((a) => `<div class="card ma-acc ${a.active ? '' : 'muted'}" data-id="${a.id}"><div class="row between"><b>${esc(a.name_en)}</b><b class="mnum">${fm(a.book)}</b></div>
      <div class="muted">${esc(a.code)} · ${esc(KIND[a.kind])}${a.provider ? ' · ' + esc(a.provider) : ''}${a.branch ? ' · ' + esc(a.branch) : ''}${a.account_no ? ' · ' + esc(a.account_no) : ''}${a.location_id ? ' · ' + esc(locName(a.location_id)) : ''} · chart ${esc(a.coa_code)}</div>
      <div class="row wrap">${a.active ? '' : chip('Switched off')}${a.generic ? chip('General account', 'warn') : ''}${Number(a.pending) ? chip('Not posted yet ' + fm(a.pending), 'warn') : ''}${(a.is_default_for || []).length ? chip('Default for ' + (a.is_default_for || []).length + ' payment type(s)') : ''}${chip('Negative: ' + a.neg_policy)}</div>
      <div class="row wrap"><button type="button" class="mini" data-act="ma_stmt" data-v="${a.id}">Statement</button><button type="button" class="mini" data-act="ma_edit" data-v="${a.id}">Edit</button>
        <button type="button" class="mini" data-act="ma_toggle" data-v="${a.id}">⋮ ${a.active ? 'Switch off' : 'Switch on'}</button></div></div>`).join('');
  return warn + `<div class="row between"><h3>Money accounts</h3><button type="button" class="btn primary" data-act="ma_new">Add account</button></div>` + (rows || '<p class="muted">No money account yet. Payments keep using the general cash, bank and mobile accounts until you add one.</p>')
    + `<p class="muted" style="font-size:.85rem">Legacy wallets (bKash, Nagad, Rocket, Upay register, phase 83): ${D.legacy.map((w) => esc(w.name_en)).join(', ') || 'none'}. Their switch "Book each mobile wallet on its own account" only governs that register; a money account of kind wallet never depends on it.</p>`;
}
function newSheet(a) {
  const e = !!a;
  openSheet(`<h3>${e ? 'Edit account' : 'Add a money account'}</h3><div class="stack">
    ${e ? '' : fld('na_kind', 'Kind', `<select id="na_kind">${Object.keys(KIND).map((k) => `<option value="${k}">${esc(KIND[k])}</option>`).join('')}</select>`)}
    ${fld('na_name', 'Name', inp('na_name', e ? a.name_en : '', 'maxlength="100"'))}
    <div id="na_prov">${fld('na_provider', e ? 'Bank or wallet name' : 'Bank or wallet name (bank / wallet)', inp('na_provider', e ? a.provider : '', 'maxlength="80"'))}${fld('na_branch', 'Branch (bank)', inp('na_branch', e ? a.branch : '', 'maxlength="80"'))}${fld('na_no', 'Account or wallet number', inp('na_no', e ? a.account_no : '', 'maxlength="40"'))}</div>
    ${e ? '' : `<div id="na_place">${fld('na_loc', 'Place (cash drawer)', `<select id="na_loc"><option value="">—</option>${locs().map((l) => `<option value="${l.id}">${esc(l.name)}</option>`).join('')}</select>`)}</div>
      ${fld('na_coa', 'Use an existing chart account instead (code, optional)', inp('na_coa', '', 'maxlength="12"'))}
      ${fld('na_open', 'Opening balance (only before the books have an opening entry)', inp('na_open', '', 'inputmode="decimal"'))}`}
    ${fld('na_neg', 'If a payment would make the balance negative', `<select id="na_neg">${[['warn', 'Warn (save it, put it on the Exceptions list)'], ['block', 'Block (the owner can allow one exception)'], ['allow', 'Allow']].map(([k, l]) => `<option value="${k}" ${(e ? a.neg_policy : 'warn') === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`)}
    <button type="button" class="primary full" data-act="${e ? 'ma_update' : 'ma_add'}" ${e ? `data-v="${a.id}"` : ''}>Save</button></div>`);
  syncKind();
}
function syncKind() {
  const k = ($('#na_kind') || {}).value; if (!k) return;
  const p = $('#na_prov'), l = $('#na_place'); if (p) p.hidden = k === 'cash'; if (l) l.hidden = k !== 'cash';
}

function defaultsHTML() {
  const rows = D.settings.map((s) => `<div class="card ma-set" data-ev="${esc(s.event_type)}"><b>${esc(s.label_en)}</b>
      <div><label for="ds_${esc(s.event_type)}">Default source</label><select id="ds_${esc(s.event_type)}"><option value="">None (as before)</option>${accOpts(s.default_account_id, (a) => s.event_type !== 'cash_handover' || a.kind === 'cash')}</select></div>
      <label class="row"><input type="checkbox" id="do_${esc(s.event_type)}" ${s.allow_override ? 'checked' : ''}> Allow the person to choose another source for one payment</label>
      <label class="row"><input type="checkbox" id="dr_${esc(s.event_type)}" ${s.require_source ? 'checked' : ''}> A source must be chosen (the server refuses a payment without one)</label>
      <button type="button" class="mini" data-act="ma_setsave" data-v="${esc(s.event_type)}">Save</button></div>`).join('');
  return `<p class="muted">For every kind of payment: the default source, whether it may be changed for one payment, and whether a source is compulsory. With no default and "required" off, a payment that names no account goes to the general cash / bank / mobile account exactly as before.</p>${rows}`;
}

async function loadMoves() { const r = await sb.from('money_transfers').select('id,from_account,to_account,amount,fee,fee_side,xfer_date,ref,note,status').order('id', { ascending: false }).limit(15); D.moves = r.data || []; }
function moveHTML() {
  const L = locs();
  return `<div class="card stack"><b>Transfer between accounts</b>
    ${fld('tr_from', 'From', `<select id="tr_from">${accOpts()}</select>`)}${fld('tr_to', 'To', `<select id="tr_to">${accOpts()}</select>`)}
    ${fld('tr_amt', 'Amount', inp('tr_amt', '', 'inputmode="decimal"'))}${fld('tr_date', 'Date', inp('tr_date', today(), 'type="date"'))}
    ${fld('tr_fee', 'Fee (optional)', inp('tr_fee', '', 'inputmode="decimal"'))}${fld('tr_side', 'The fee is taken from', `<select id="tr_side"><option value="from">the paying account</option><option value="to">the receiving account</option></select>`)}
    ${fld('tr_loc', 'Place', `<select id="tr_loc">${L.map((l) => `<option value="${l.id}">${esc(l.name)}</option>`).join('')}</select>`)}${fld('tr_ref', 'Reference', inp('tr_ref', '', 'maxlength="60"'))}
    <button type="button" class="primary full" data-act="ma_transfer">Transfer</button></div>
    <div class="card stack"><b>Bank / wallet charge or interest</b>
    ${fld('ch_acc', 'Account', `<select id="ch_acc">${accOpts()}</select>`)}${fld('ch_kind', 'Kind', `<select id="ch_kind"><option value="charge">Charge (expense)</option><option value="interest">Interest (income)</option></select>`)}
    ${fld('ch_amt', 'Amount', inp('ch_amt', '', 'inputmode="decimal"'))}${fld('ch_date', 'Date', inp('ch_date', today(), 'type="date"'))}${fld('ch_ref', 'Reference', inp('ch_ref', '', 'maxlength="60"'))}
    <button type="button" class="primary full" data-act="ma_charge">Save</button></div>
    <h3>Recent transfers</h3>${(D.moves || []).map((t) => `<div class="card ${t.status === 'void' ? 'muted' : ''}"><div class="row between"><span>${esc(String(t.xfer_date))} · ${esc(accName(t.from_account))} → ${esc(accName(t.to_account))}</span><b>${fm(t.amount)}${Number(t.fee) ? ' + fee ' + fm(t.fee) : ''}</b></div>
      ${t.status === 'done' ? `<button type="button" class="mini" data-act="ma_trvoid" data-v="${t.id}">⋮ Void</button>` : chip('Void')}</div>`).join('') || '<p class="muted">None.</p>'}`;
}

function stmtHTML() {
  const s = D.st;
  const head = `<div class="card stack">${fld('st_acc', 'Account', `<select id="st_acc">${accOpts(D.sel)}</select>`)}<div class="row wrap">${fld('st_from', 'From', inp('st_from', D.from, 'type="date"'))}${fld('st_to', 'To', inp('st_to', D.to, 'type="date"'))}</div>
    <div class="row"><button type="button" class="primary" data-act="ma_stshow">Show</button><button type="button" class="btn" data-act="ma_stcsv">Export CSV</button></div></div>`;
  if (!s) return head;
  if (s.data_needed) return head + '<p class="muted">Accounting start date is not set.</p>';
  return head + `<div class="card" id="st_sum"><div class="row between"><span>Opening</span><b>${fm(s.opening)}</b></div><div class="row between"><span>In</span><b>${fm(s.in)}</b></div><div class="row between"><span>Out</span><b>${fm(s.out)}</b></div><div class="row between"><span>Closing</span><b>${fm(s.closing)}</b></div></div>`
    + (s.rows || []).map((r) => `<div class="card st-row"><div class="row between"><span>${esc(String(r.date))} · ${esc(r.memo || '')}</span><b>${Number(r.in) ? '+' + fm(r.in) : '-' + fm(r.out)}</b></div><div class="muted">${esc(r.source_type)} #${esc(String(r.entry_id))}${r.counter ? ' · vs ' + esc(r.counter) : ''} · balance ${fm(r.balance)}</div></div>`).join('')
    + ((s.not_posted_yet || []).length ? `<h3>Not posted yet</h3>${s.not_posted_yet.map((p) => `<div class="card muted"><div class="row between"><span>${esc(String(p.date))} · ${esc(p.memo)}</span><b>${fm(p.amount)}</b></div></div>`).join('')}` : '');
}
function summaryHTML() {
  const s = D.sm;
  const head = `<div class="card stack"><div class="row wrap">${fld('sm_from', 'From', inp('sm_from', D.from, 'type="date"'))}${fld('sm_to', 'To', inp('sm_to', D.to, 'type="date"'))}</div><button type="button" class="primary full" data-act="ma_smshow">Show</button></div>`;
  if (!s || s.data_needed) return head;
  return head + `<div class="card" id="sm_total"><b>All accounts</b><div class="row between"><span>Opening</span><b>${fm(s.total.opening)}</b></div><div class="row between"><span>In</span><b>${fm(s.total.in)}</b></div><div class="row between"><span>Out</span><b>${fm(s.total.out)}</b></div><div class="row between"><span>Closing</span><b>${fm(s.total.closing)}</b></div></div>`
    + (s.accounts || []).map((a) => `<div class="card"><div class="row between"><b>${esc(a.name_en)}</b><b>${fm(a.closing)}</b></div><div class="muted">${esc(KIND[a.kind])} · opening ${fm(a.opening)} · in ${fm(a.in)} · out ${fm(a.out)}</div></div>`).join('')
    + `<h3>By day</h3>${(s.days || []).map((d) => `<div class="row between"><span>${esc(String(d.date))}</span><span>in ${fm(d.in)} · out ${fm(d.out)} · net ${fm(d.net)}</span></div>`).join('')}<p class="muted" style="font-size:.85rem">${esc(s.note || '')}</p>`;
}
function checkHTML() {
  const l = D.last;
  return `<div class="card stack"><b>Real balance (type what you count or see first)</b><p class="muted">The book figure and the difference are shown only after you save.</p>
    ${fld('ck_acc', 'Account', `<select id="ck_acc">${accOpts()}</select>`)}${fld('ck_date', 'Date', inp('ck_date', today(), 'type="date"'))}${fld('ck_real', 'Real balance', inp('ck_real', '', 'inputmode="decimal"'))}
    <button type="button" class="primary full" data-act="ma_ckgo">Save</button>
    ${l ? (l.status === 'matched' ? `<div class="chip ok" id="ck_res">Matches · book ${fm(l.book)}</div>` : `<div id="ck_res"><div class="chip warn">Book ${fm(l.book)} · difference ${fm(l.diff)}</div><p>Write the reason:</p>${inp('ck_why', '', 'maxlength="300"')}<button type="button" class="full" data-act="ma_ckwhy" data-v="${l.id}">Save reason</button></div>`) : ''}</div>
    <h3>Earlier counts</h3>${(D.checks || []).map((c) => `<div class="card"><div class="row between"><span>${esc(String(c.date))} · ${esc(c.account)}</span><b>${chip(c.status, c.status === 'matched' ? 'ok' : 'warn')}</b></div><div class="muted">real ${fm(c.real)} · book ${fm(c.book)} · diff ${fm(c.diff)}${c.reason ? ' · ' + esc(c.reason) : ''}</div></div>`).join('') || '<p class="muted">None.</p>'}`;
}
function exHTML() {
  const x = D.ex || { rows: [], grants: [] }, own = S.ctx && S.ctx.is_owner;
  const grant = own ? `<div class="card stack" id="ex_grant"><b>Allow one exception (owner only)</b><p class="muted">For one payment or one person, once, with a reason. It is written to the Exceptions list and the audit log.</p>
    ${fld('gx_rule', 'Rule', `<select id="gx_rule">${Object.keys(EV_RULE).map((k) => `<option value="${k}">${esc(EV_RULE[k])}</option>`).join('')}</select>`)}
    ${fld('gx_user', 'For this person', `<select id="gx_user"><option value="">—</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id || p.id)}</option>`).join('')}</select>`)}
    ${fld('gx_client', 'or for the payment with this client id (optional)', inp('gx_client', '', 'maxlength="40"'))}${fld('gx_reason', 'Reason', inp('gx_reason', '', 'maxlength="300"'))}
    <button type="button" class="primary full" data-act="ma_gxgo">Allow once</button></div>` : '';
  return grant + `<h3>Exceptions list</h3>` + (x.rows.map((r) => `<div class="card ${r.status === 'resolved' ? 'muted' : ''}"><div class="row between"><b>${esc(r.kind)}</b><span>${esc(String(r.at).slice(0, 16).replace('T', ' '))}</span></div>
      <div>${esc(r.account_name || '')} ${r.amount != null ? fm(r.amount) : ''} ${esc(r.event_type || '')}</div><div class="muted">${esc(r.reason || '')}${r.resolve_note ? ' · resolved: ' + esc(r.resolve_note) : ''}</div>
      ${r.status === 'open' ? `<button type="button" class="mini" data-act="ma_exres" data-v="${r.id}">Resolve</button>` : chip('Resolved')}</div>`).join('') || '<p class="muted">None.</p>');
}
function apprHTML() {
  const m = D.mode || {}, own = S.ctx && S.ctx.is_owner;
  const cur = `<div class="card" id="ap_cur"><b>Current setting</b><div>Mode: <b>${esc(m.mode || '-')}</b> · role: ${esc(m.approver_role || 'none')} · people: ${(m.approver_users || []).map((u) => esc((D.people.find((p) => p.id === u) || {}).full_name || u)).join(', ') || 'none'}</div>
    <p class="muted">self = the owner approves his own entries. named = only the role and/or the people named here can approve the owner's entries (never the maker himself). logged / off keep today's rules.</p></div>`;
  if (!own) return cur;
  return cur + `<div class="card stack" id="ap_set"><b>Change the approver</b>
    ${fld('ap_mode', 'Mode', `<select id="ap_mode">${['self', 'named', 'logged', 'off'].map((k) => `<option value="${k}" ${m.mode === k ? 'selected' : ''}>${k}</option>`).join('')}</select>`)}
    ${fld('ap_role', 'Role (any role; "no role" = people only)', `<select id="ap_role"><option value="">keep as is</option><option value="-">no role</option>${D.roles.filter((r) => r.code !== 'owner').map((r) => `<option value="${esc(r.code)}">${esc(r.code)}</option>`).join('')}</select>`)}
    ${fld('ap_users', 'People (hold Ctrl / long press to pick several)', `<select id="ap_users" multiple size="4">${D.people.map((p) => `<option value="${esc(p.id)}" ${(m.approver_users || []).includes(p.id) ? 'selected' : ''}>${esc(p.full_name || p.staff_id || p.id)}</option>`).join('')}</select>`)}
    ${fld('ap_note', 'Note', inp('ap_note', '', 'maxlength="200"'))}<button type="button" class="primary full" data-act="ma_apgo">Save</button></div>
    <div class="card stack" id="ap_entry"><b>Choose the approver for ONE entry</b>
    ${fld('ae_id', 'Entry id', inp('ae_id', '', 'maxlength="40"'))}${fld('ae_user', 'Person', `<select id="ae_user"><option value="">—</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id || p.id)}</option>`).join('')}</select>`)}
    ${fld('ae_role', 'or role', `<select id="ae_role"><option value="">—</option>${D.roles.map((r) => `<option value="${esc(r.code)}">${esc(r.code)}</option>`).join('')}</select>`)}${fld('ae_why', 'Reason', inp('ae_why', '', 'maxlength="200"'))}
    <button type="button" class="primary full" data-act="ma_aego">Set</button></div>`;
}
function repHTML() {
  const r = D.rp;
  const head = `<div class="card stack"><div class="row wrap">${fld('rp_from', 'From', inp('rp_from', D.from, 'type="date"'))}${fld('rp_to', 'To', inp('rp_to', D.to, 'type="date"'))}</div><button type="button" class="primary full" data-act="ma_rpshow">Show</button></div>`;
  if (!r || r.data_needed) return head;
  const inc = r.income_statement || {}, bs = r.balance_sheet || {};
  return head + `<div class="card" id="rp_pl"><b>Profit and loss</b><div class="row between"><span>Income</span><b>${fm(inc.total_income)}</b></div><div class="row between"><span>Expense</span><b>${fm(inc.total_expense)}</b></div><div class="row between"><span>Net profit</span><b>${fm(inc.net_profit)}</b></div></div>
    <div class="card" id="rp_bs"><b>Cash, bank and wallet — one line per account (balance sheet)</b>${(r.money_lines || []).map((l) => `<div class="row between rp-line"><span>${esc(l.name_en)} <span class="muted">${esc(KIND[l.kind])} · ${esc(l.coa_code)}</span></span><b>${fm(l.closing)}</b></div>`).join('') || '<p class="muted">No money account.</p>'}
    <div class="row between"><span>Total money accounts</span><b>${fm(r.money_total_closing)}</b></div><div class="row between"><span>Total assets</span><b>${fm(bs.total_assets)}</b></div></div>`
    + (D.sal ? `<div class="card" id="rp_sal"><b>Salary paid, by payment source</b>${(D.sal.by_source || []).map((s) => `<div class="row between"><span>${esc(s.source)}</span><b>${fm(s.amount)}</b></div>`).join('') || '<p class="muted">None.</p>'}</div>` : '');
}
function draw() {
  const el = $('#ma_body'); if (!el) return;
  const body = ({ accounts: accountsHTML, defaults: defaultsHTML, move: moveHTML, statement: stmtHTML, summary: summaryHTML, check: checkHTML, exceptions: exHTML, approvers: apprHTML, reports: repHTML })[D.tab]();
  el.innerHTML = tabsBar() + `<div id="ma_pane">${body}</div>`;
}
async function loadTab() {
  await loadAcc();
  if (D.tab === 'defaults') D.settings = await call('money_event_settings_list', {});
  if (D.tab === 'move') await loadMoves();
  if (D.tab === 'check') D.checks = await call('money_checks_list', { p_account: null, p_limit: 30 });
  if (D.tab === 'exceptions' || D.tab === 'approvers') {
    if (!D.people.length) { const p = await sb.from('profiles').select('id,full_name,staff_id,status').eq('status', 'active').order('full_name'); D.people = p.data || []; }
    if (D.tab === 'exceptions') D.ex = await call('money_exceptions_list', { p_status: null, p_limit: 200 });
    if (D.tab === 'approvers') { D.mode = await call('owner_approval_mode', {}); if (!D.roles.length) { const r = await sb.from('roles').select('code').eq('active', true).order('code'); D.roles = r.data || []; } }
  }
}
async function show(tab) { if (tab) D.tab = tab; try { await loadTab(); draw(); } catch (e) { toast(e.message); draw(); } }
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

Object.assign(H, {
  ma_tab: (a) => show(a.dataset.v),
  ma_new: () => newSheet(null),
  ma_edit: (a) => newSheet(D.acc.find((x) => String(x.id) === a.dataset.v)),
  ma_add: act(async () => {
    const k = val('na_kind'), name = val('na_name'); if (!name) return toast('Write the name.');
    const open = val('na_open') === '' ? 0 : nnum(val('na_open')); if (!(open >= 0)) return toast(ERR.bad_amount);
    await call('money_account_add', { p_kind: k, p_name_en: name, p_name_bn: null, p_provider: k === 'cash' ? null : val('na_provider') || null, p_branch: k === 'bank' ? val('na_branch') || null : null,
      p_account_no: k === 'cash' ? null : val('na_no') || null, p_location: k === 'cash' && val('na_loc') ? Number(val('na_loc')) : null, p_coa_code: val('na_coa') || null, p_opening: open, p_opening_date: null, p_neg: val('na_neg') || 'warn', p_note: null });
    closeSheet(); toast('Saved'); if (B.moneySrc) B.moneySrc.reset(); await show('accounts');
  }),
  ma_update: act(async (a) => {
    await call('money_account_update', { p_id: Number(a.dataset.v), p_name_en: val('na_name') || null, p_name_bn: null, p_provider: val('na_provider') || null, p_branch: val('na_branch') || null, p_account_no: val('na_no') || null, p_neg: val('na_neg') || null, p_sort: null, p_note: null });
    closeSheet(); toast('Saved'); if (B.moneySrc) B.moneySrc.reset(); await show('accounts');
  }),
  ma_toggle: act(async (a) => {
    const x = D.acc.find((y) => String(y.id) === a.dataset.v); let why = null;
    if (x.active) { why = window.prompt('Why is this account switched off?'); if (!why || why.trim().length < 3) return; }
    await call('money_account_set_active', { p_id: x.id, p_active: !x.active, p_reason: why }); toast('Saved'); if (B.moneySrc) B.moneySrc.reset(); await show('accounts');
  }),
  ma_stmt: (a) => { D.sel = a.dataset.v; D.st = null; show('statement'); },
  ma_setsave: act(async (a) => {
    const ev = a.dataset.v, d = val('ds_' + ev);
    await call('money_event_setting_set', { p_event: ev, p_default: d ? Number(d) : null, p_allow_override: $('#do_' + ev).checked, p_require: $('#dr_' + ev).checked, p_clear_default: !d });
    if (B.moneySrc) B.moneySrc.reset(); toast('Saved'); await show('defaults');
  }),
  ma_transfer: act(async () => {
    const amt = nnum(val('tr_amt')); if (!(amt > 0)) return toast(ERR.bad_amount); const fee = val('tr_fee') === '' ? 0 : nnum(val('tr_fee')); if (!(fee >= 0)) return toast(ERR.bad_amount);
    await call('money_transfer_add', { p_from: Number(val('tr_from')), p_to: Number(val('tr_to')), p_amount: amt, p_date: val('tr_date'), p_fee: fee, p_fee_side: val('tr_side'), p_ref: val('tr_ref') || null, p_note: null, p_loc: Number(val('tr_loc')), p_client: D.client.tr });
    D.client.tr = rid(); toast('Saved'); await show('move');
  }),
  ma_charge: act(async () => {
    const amt = nnum(val('ch_amt')); if (!(amt > 0)) return toast(ERR.bad_amount);
    await call('money_charge_add', { p_account: Number(val('ch_acc')), p_kind: val('ch_kind'), p_amount: amt, p_date: val('ch_date'), p_ref: val('ch_ref') || null, p_note: null, p_loc: locs()[0] ? Number(locs()[0].id) : null, p_client: D.client.ch });
    D.client.ch = rid(); toast('Saved'); await show('move');
  }),
  ma_trvoid: act(async (a) => { const n = window.prompt('Why is this transfer voided?'); if (!n || n.trim().length < 3) return; await call('money_transfer_void', { p_id: Number(a.dataset.v), p_note: n.trim() }); toast('Voided'); await show('move'); }),
  ma_stshow: act(async () => { D.sel = val('st_acc'); D.from = val('st_from'); D.to = val('st_to'); D.st = await call('money_statement', { p_account: Number(D.sel), p_from: D.from || null, p_to: D.to || null, p_loc: null, p_limit: 2000 }); draw(); }),
  ma_stcsv: act(async () => {
    D.sel = val('st_acc'); const t = await call('money_statement_csv', { p_account: Number(D.sel), p_from: val('st_from') || null, p_to: val('st_to') || null, p_loc: null });
    const blob = new Blob([guardCsv(t)], { type: 'text/csv;charset=utf-8' }), u = URL.createObjectURL(blob), a = document.createElement('a'); a.href = u; a.download = 'statement-' + D.sel + '.csv'; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 1000);
  }),
  ma_smshow: act(async () => { D.from = val('sm_from'); D.to = val('sm_to'); D.sm = await call('money_summary', { p_from: D.from || null, p_to: D.to || null, p_loc: null }); draw(); }),
  ma_ckgo: act(async () => {
    const real = nnum(val('ck_real')); if (!(real >= 0)) return toast(ERR.bad_amount);
    D.last = await call('money_check_save', { p_account: Number(val('ck_acc')), p_date: val('ck_date'), p_real: real, p_client: D.client.ck }); D.client.ck = rid(); await show('check');
  }),
  ma_ckwhy: act(async (a) => { const w = val('ck_why'); if (w.length < 3) return toast(ERR.reason_required); await call('money_check_explain', { p_check: Number(a.dataset.v), p_reason: w }); D.last = null; toast('Saved'); await show('check'); }),
  ma_exres: act(async (a) => { const n = window.prompt('Resolution note'); if (!n || n.trim().length < 3) return; await call('money_exception_resolve', { p_id: Number(a.dataset.v), p_note: n.trim() }); await show('exceptions'); }),
  ma_gxgo: act(async () => {
    if (val('gx_reason').length < 3) return toast(ERR.reason_required);
    await call('money_exception_grant', { p_rule: val('gx_rule'), p_reason: val('gx_reason'), p_for_user: val('gx_user') || null, p_client: val('gx_client') || null, p_event: null, p_account: null, p_max: null, p_date: null, p_hours: 24 });
    toast('Saved'); await show('exceptions');
  }),
  ma_apgo: act(async () => {
    const sel = $('#ap_users'), users = sel ? [...sel.selectedOptions].map((o) => o.value) : [];
    await call('owner_approval_mode_set2', { p_mode: val('ap_mode'), p_role: val('ap_role') || null, p_users: users, p_note: val('ap_note') || null }); toast('Saved'); await show('approvers');
  }),
  ma_aego: act(async () => {
    await call('entry_approver_set', { p_entry: val('ae_id'), p_user: val('ae_user') || null, p_role: val('ae_role') || null, p_reason: val('ae_why') }); toast('Saved');
  }),
  ma_rpshow: act(async () => {
    D.from = val('rp_from'); D.to = val('rp_to'); D.rp = await call('money_statements', { p_from: D.from || null, p_to: D.to || null, p_loc: null });
    try { D.sal = await call('money_salary_sources', { p_from: D.from, p_to: D.to, p_loc: null }); } catch (e) { D.sal = null; }
    draw();
  }),
});
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'na_kind') syncKind(); });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Money Accounts', '<div id="ma_body"><p class="muted">…</p></div>', true);
  try { D.acc = []; await show(D.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { moneyaccounts: view });
})();
