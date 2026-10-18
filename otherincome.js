/* Islamia BOS · Other income, chart and heads, customer bank / cheque receipts.
   Two screens in one file:
   #/otherincome  Other income (scrap, old oil, rent received, supplier discount): enter and void; Chart & heads (seeded accounts, expense heads, other income heads: rename, use another code,
                  turn on / retire, each with a reason where it matters); Coverage (every key the posting needs points to an account); Settings (rule switches, audit-logged).
   #/bankreceipt  Customer receipts with bank transfer or cheque, a payment source (money account) and a reference; recent bank / cheque receipts; owner settings for the channel and the reference rule.
   Server: supabase/phase96.sql (_w1f_other_income_*, _w1f_seed_*, _w1f_expense_head*, _w1f_mapping_coverage) and supabase/phase97.sql (_w1f_collect_payment, _w1f_receipt_settings, _w1f_receipts_list).
   Payment source: the shared picker data of phase87 (BOS.moneySrc / money_pick). English labels only (owner decision); the L() wrapper keeps the three modes ready for a later translation.
   UNVERIFIED on a real phone and on a real Supabase project. */
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
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const locs = () => {
  const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
  const wide = S.ctx.is_owner || (S.ctx.roles || []).includes('management');
  return (wide ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id))).map((l) => ({ id: l.id, name: A.nm ? A.nm(l) : l.name_en || l.name_bn || l.code || String(l.id) }));
};
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;

const X = {
  title: E('Other income'), t_enter: E('Enter'), t_chart: E('Chart & heads'), t_cov: E('Coverage'), t_set: E('Settings'),
  off: E('Other income entry is switched OFF. The owner can switch it on under Settings.'),
  loc: E('Place'), date: E('Date'), head: E('What the money is for'), amount: E('Amount'), mode: E('How it was received'), cash: E('Cash'), mobile: E('Mobile wallet'), bank: E('Bank'),
  from: E('Received from'), ref: E('Reference'), note: E('Note'), photo: E('Photo (optional)'), check: E('Check first'), save: E('Save'), recent: E('Recent entries'), none: E('Nothing yet'),
  void: E('Void'), voidWhy: E('Why is this voided?'), voided: E('Voided'), saved: E('Saved'), dry: E('Check passed - nothing was saved'), reason: E('Reason'), cancel: E('Cancel'),
  seeds: E('Seeded accounts'), seedsHint: E('Accounts and mapping keys added for you. Nothing existing was changed. You can rename them, use another code or switch them off.'),
  eheads: E('Expense heads (the 10-2 form)'), eheadsHint: E('A new head is offered on the expense form only after you turn it on. Documents already posted never move.'),
  oheads: E('Other income heads'), rename: E('Rename'), newcode: E('Use another code'), choose: E('Choose account'), on: E('Switch on'), offb: E('Switch off'), retire: E('Retire'), turnon: E('Turn on'),
  addhead: E('Add a head'), editacc: E('Change account'), label: E('Name'), code: E('Code'), acc: E('Account'), effective: E('Effective from'), unposted: E('older documents not posted yet'),
  covOk: E('Every key points to an active account.'), covBad: E('These keys need an account:'),
  setOi: E('Other income entry'), setOiFrom: E('Other income counts from (YYYY-MM-DD, blank = any date)'), setBank: E('Accept bank transfer and cheque from customers'),
  setRef: E('Reference number needed on customer bank receipts'), setRefFrom: E('The reference rule counts from (YYYY-MM-DD, blank = at once)'), ownerOnly: E('Only the owner can change settings.'),
  refOff: E('Never'), refBank: E('Bank and cheque receipts'), refBankMobile: E('Bank, cheque and mobile receipts'),
  r_title: E('Bank & cheque receipts'), r_find: E('Find customer'), r_mobile: E('Customer mobile'), r_due: E('Due'), r_none: E('Customer not found'), r_add: E('Add a payment row'), r_collect: E('Collect'),
  r_channel: E('Channel'), r_cash: E('Cash'), r_mobile2: E('Mobile wallet'), r_card: E('Card'), r_bank: E('Bank transfer'), r_cheque: E('Cheque'), r_amount: E('Amount'), r_src: E('Payment source'), r_srcNone: E('Not named (as before)'),
  r_ref: E('Transaction / reference no.'), r_chq: E('Cheque no.'), r_chqd: E('Cheque date'), r_why: E('If there is no reference, write why'), r_recent: E('Recent bank and cheque receipts'),
  r_bankOff: E('Bank transfer and cheque are switched OFF (only cash, mobile and card). The owner can switch them on below.'), r_note: E('Note'), r_done: E('Collected'), r_del: E('Remove'),
  r_over: E('More than the customer owes'), r_needChq: E('Write the cheque number'), r_needRef: E('Write the reference number, or why there is none'), r_waived: E('no reference, reason on record'),
  r_defaults: E('Which account is the default for these payments is set under Money Accounts > Payment defaults (Customer payment of a due, Customer payment taken with a sale).'),
  r_chqHint: E('A cheque is a bank receipt with its cheque number.'),
  noperm: E('You do not have permission.'), nofn: E('The server does not have this feature yet (phase 96 / 97 not pasted).'),
};
const T = (k) => lab(X[k]);
const ERR = {
  other_income_off: 'Other income entry is switched OFF.', bad_head: 'Choose a head from the list.', bad_amount: 'Amount is not valid.', bad_mode: 'This way of paying is not accepted (bank / cheque are switched OFF or unknown).',
  bad_date: 'Date is not valid.', before_start_date: 'This date is before the start date the owner set.', period_closed: 'This period is closed.', client_id_taken: 'This entry number belongs to another person.',
  not_allowed: 'You do not have permission.', bad_location: 'Unknown place.', bad_photo: 'The photo path is not valid.', money_source_required: 'Choose the payment source.', money_source_fixed: 'The owner fixed the source for this payment.',
  money_account_place: 'That cash drawer belongs to another place.', money_account_inactive: 'That account is switched off.', unknown_money_account: 'Unknown account.', receipt_reference_required: 'A reference number is required: write it, or write why there is none.',
  receipt_bank_off: 'Bank receipts are switched OFF.', cheque_needs_bank: 'A cheque number belongs to a bank receipt.', overpaid: 'More than the customer owes.', customer_not_found: 'Customer not found.', no_payments: 'Add a payment.',
  older_documents_unposted: 'Older documents with this head are not posted yet. Post them first, or write a reason to go ahead.', reason_required: 'Write a reason.', code_taken: 'That code is already used.', bad_code: 'The code is not valid.',
  account_has_balance: 'The account still has a balance.', wrong_account_type: 'The account is of another type.', bad_account: 'Choose an active account of the right type.', account_required: 'Choose the account.',
  name_required: 'Write the name.', unknown_key: 'Unknown item.', not_mapped: 'This item has no account yet. Use "Choose account".', bad_head_code: 'The code may use small letters, digits and underscore.', parent_inactive: 'The parent account is switched off.',
};
const eText = (e) => { const m = String((e && e.message) || ''); if (/could not find|does not exist|PGRST202/i.test(m + ' ' + ((e && e.code) || ''))) return lab(X.nofn); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

const OI = { tab: 'enter', loc: null, heads: [], list: null, seeds: [], eheads: [], oheads: [], cov: null, coa: [], rules: {}, client: rid(), photo: '', isOwner: false };

// ------------------------------------------------------------------ settings card (rules, audit-logged by the server)
const RULEKEYS = ['other_income_on', 'other_income_from', 'receipt_bank_on', 'receipt_ref_required', 'receipt_ref_from'];
async function loadRules() {
  const r = await sb.from('rules').select('key,value,default_value').in('key', RULEKEYS);
  const o = {}; (r.data || []).forEach((x) => { const v = x.value === null || x.value === undefined ? x.default_value : x.value; o[x.key] = v; });
  OI.rules = o;
}
const rv = (k) => (OI.rules[k] === undefined || OI.rules[k] === null ? '' : OI.rules[k]);
function settingsCard(keys) {
  const owner = !!(S.ctx && S.ctx.is_owner);
  const row = (k) => {
    if (k === 'other_income_on') return `<label class="row"><input type="checkbox" id="rs_${k}" ${rv(k) === true ? 'checked' : ''} ${owner ? '' : 'disabled'}> ${esc(T('setOi'))}</label>`;
    if (k === 'receipt_bank_on') return `<label class="row"><input type="checkbox" id="rs_${k}" ${rv(k) === true ? 'checked' : ''} ${owner ? '' : 'disabled'}> ${esc(T('setBank'))}</label>`;
    if (k === 'receipt_ref_required') return fld('rs_' + k, T('setRef'), `<select id="rs_${k}" ${owner ? '' : 'disabled'}>${[['off', T('refOff')], ['bank', T('refBank')], ['bank_mobile', T('refBankMobile')]].map(([v, l]) => `<option value="${v}" ${(rv(k) || 'off') === v ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`);
    return fld('rs_' + k, k === 'other_income_from' ? T('setOiFrom') : T('setRefFrom'), inp('rs_' + k, rv(k), `maxlength="10" placeholder="YYYY-MM-DD" ${owner ? '' : 'disabled'}`));
  };
  return `<div class="card stack" id="w1_settings">${keys.map(row).join('')}${owner ? `<button type="button" class="primary full" data-act="w1_setsave" data-v="${esc(keys.join(','))}">${esc(T('save'))}</button>` : `<p class="muted">${esc(T('ownerOnly'))}</p>`}</div>`;
}
const setRule = async (key, value) => call('set_rule', { p_key: key, p_value: value });

// ------------------------------------------------------------------ Other income
async function loadHeads() { OI.heads = await call('_w1f_other_income_heads', {}); }
async function loadCoa() {
  if (OI.coa.length) return;
  const r = await sb.from('coa_accounts').select('code,name_en,type,active,is_group').eq('active', true).order('code');
  OI.coa = (r.data || []).filter((a) => !a.is_group);
}
const accOpts = (type, sel, none) => (none ? `<option value="">${esc(none)}</option>` : '') + OI.coa.filter((a) => a.type === type).map((a) => `<option value="${esc(a.code)}" ${String(sel) === String(a.code) ? 'selected' : ''}>${esc(a.code)} · ${esc(a.name_en)}</option>`).join('');
const headLabel = (code) => { const h = OI.heads.find((x) => x.code === code); return h ? h.label_en : code; };

function enterHTML() {
  const l = OI.list || { on: false, rows: [] };
  const off = l.on ? '' : `<div class="notice bad" id="oi_off">${esc(T('off'))}</div>`;
  const L_ = locs();
  const form = `<div class="card stack" id="oi_form">
    ${fld('oi_loc', T('loc'), `<select id="oi_loc">${L_.map((x) => `<option value="${x.id}" ${String(x.id) === String(OI.loc) ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select>`)}
    ${fld('oi_date', T('date'), inp('oi_date', today(), 'type="date"'))}
    ${fld('oi_head', T('head'), `<select id="oi_head">${OI.heads.filter((h) => h.active).map((h) => `<option value="${esc(h.code)}">${esc(h.label_en)}</option>`).join('')}</select>`)}
    ${fld('oi_amt', T('amount'), inp('oi_amt', '', 'inputmode="decimal"'))}
    ${fld('oi_mode', T('mode'), `<select id="oi_mode"><option value="cash">${esc(T('cash'))}</option><option value="mobile">${esc(T('mobile'))}</option><option value="bank">${esc(T('bank'))}</option></select>`)}
    ${B.moneySrc ? B.moneySrc.slot('oi', 'other_income', { locSel: '#oi_loc' }) : ''}
    ${fld('oi_from', T('from'), inp('oi_from', '', 'maxlength="120"'))}${fld('oi_ref', T('ref'), inp('oi_ref', '', 'maxlength="80"'))}${fld('oi_note', T('note'), inp('oi_note', '', 'maxlength="300"'))}
    <div><label>${esc(T('photo'))}</label><div class="s2-ph" id="oi_ph">${OI.photo ? '📎 ' + esc(OI.photo) : ''}</div><label class="phadd">📷 ${esc(T('photo'))}<input type="file" accept="image/*" hidden id="oi_file"></label></div>
    <div class="row"><button type="button" class="full" data-act="oi_dry">${esc(T('check'))}</button><button type="button" class="full primary" data-act="oi_save">${esc(T('save'))}</button></div></div>`;
  const rows = (l.rows || []).map((r) => `<div class="card oi-row ${r.status === 'void' ? 'muted' : ''}" data-id="${esc(r.id)}"><div class="row between"><b>${esc(r.head_label || headLabel(r.head))}</b><b>${fm(r.amount)}</b></div>
      <div class="muted">${esc(String(r.income_date))} · ${esc(T(r.mode))}${r.account_name ? ' · ' + esc(r.account_name) : ''}${r.received_from ? ' · ' + esc(r.received_from) : ''}${r.ref ? ' · ' + esc(r.ref) : ''}${r.note ? ' · ' + esc(r.note) : ''}</div>
      ${r.status === 'done' ? `<div class="row"><button type="button" class="mini" data-act="oi_void" data-v="${esc(r.id)}">⋮ ${esc(T('void'))}</button></div>` : `<div>${chip(T('voided'))} <span class="muted">${esc(r.void_note || '')}</span></div>`}</div>`).join('');
  return off + form + `<h3>${esc(T('recent'))}</h3>${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
const oiArgs = (dry) => ({ p_loc: Number(val('oi_loc')), p_date: val('oi_date') || null, p_head: val('oi_head'), p_amount: nnum(val('oi_amt')), p_mode: val('oi_mode'),
  p_money_account: B.moneySrc ? B.moneySrc.get('oi') : null, p_received_from: val('oi_from') || null, p_ref: val('oi_ref') || null, p_note: val('oi_note') || null, p_photo: OI.photo || null,
  p_client: dry ? null : OI.client, p_dry: !!dry });

// ------------------------------------------------------------------ Chart & heads
const STATUS = { created: 'Added for you', mapped_existing: 'Linked to the standard account', owner_mapping_kept: 'Your own mapping kept', code_taken: 'Code already used: choose an account', type_mismatch: 'Code used by another type: choose an account', history_exists: 'Waiting: older documents use this head', pending: 'Pending' };
function chartHTML() {
  const seeds = OI.seeds.map((s) => `<div class="card w1-seed" data-k="${esc(s.key)}"><div class="row between"><b>${esc(s.name_en || s.proposed_code)}</b><span class="muted">${esc(s.code || '-')}</span></div>
      <div class="muted">${esc(s.purpose)}</div>
      <div class="row wrap">${chip(STATUS[s.status] || s.status, ['code_taken', 'type_mismatch', 'history_exists'].includes(s.status) ? 'warn' : '')}${s.placeholder ? chip('Placeholder') : ''}${s.has_account ? '' : chip('No account yet', 'bad')}${s.has_account && !s.active ? chip('Switched off') : ''}${s.has_lines ? chip('Has postings') : ''}</div>
      <div class="row wrap">${s.has_account ? `<button type="button" class="mini" data-act="w1_rename" data-v="${esc(s.key)}">${esc(T('rename'))}</button>` : ''}<button type="button" class="mini" data-act="w1_newcode" data-v="${esc(s.key)}">${esc(T('newcode'))}</button>
        <button type="button" class="mini" data-act="w1_map" data-v="${esc(s.key)}">${esc(T('choose'))}</button>
        ${s.has_account ? `<button type="button" class="mini" data-act="w1_active" data-v="${esc(s.key)}">⋮ ${esc(s.active ? T('offb') : T('on'))}</button>` : ''}</div></div>`).join('');
  const eh = OI.eheads.map((h) => `<div class="card w1-ehead" data-c="${esc(h.code)}"><div class="row between"><b>${esc(h.label_en)}</b>${chip(h.active ? 'On' : 'Retired', h.active ? 'ok' : '')}</div>
      <div class="muted">${esc(h.code)} · ${h.mapped ? esc(h.account_code) + ' ' + esc(h.account_name || '') : 'no account'}${Number(h.unposted) ? ' · ' + Number(h.unposted) + ' ' + esc(T('unposted')) : ''}${h.effective_from ? ' · from ' + esc(h.effective_from) : ''}</div>
      <div class="row wrap"><button type="button" class="mini" data-act="w1_ehead" data-v="${esc(h.code)}">${esc(h.active ? T('editacc') : T('turnon'))}</button>${h.active ? `<button type="button" class="mini" data-act="w1_eretire" data-v="${esc(h.code)}">⋮ ${esc(T('retire'))}</button>` : ''}</div></div>`).join('');
  const oh = OI.oheads.map((h) => `<div class="card w1-ohead" data-c="${esc(h.code)}"><div class="row between"><b>${esc(h.label_en)}</b>${chip(h.active ? 'On' : 'Retired', h.active ? 'ok' : '')}</div>
      <div class="muted">${esc(h.code)} · ${esc(h.account_code || '-')} ${esc(h.account_name || '')}${h.own_account ? '' : ' (Other income)'}</div>
      <div class="row wrap"><button type="button" class="mini" data-act="w1_ohead" data-v="${esc(h.code)}">${esc(T('editacc'))}</button>${h.active ? `<button type="button" class="mini" data-act="w1_oretire" data-v="${esc(h.code)}">⋮ ${esc(T('retire'))}</button>` : ''}</div></div>`).join('');
  return `<h3>${esc(T('seeds'))}</h3><p class="muted">${esc(T('seedsHint'))}</p>${seeds}
    <div class="row between"><h3>${esc(T('eheads'))}</h3><button type="button" class="mini" data-act="w1_ehead" data-v="">${esc(T('addhead'))}</button></div><p class="muted">${esc(T('eheadsHint'))}</p>${eh}
    <div class="row between"><h3>${esc(T('oheads'))}</h3><button type="button" class="mini" data-act="w1_ohead" data-v="">${esc(T('addhead'))}</button></div>${oh}`;
}
const reasonField = (id, hint) => fld(id, hint || T('reason'), inp(id, '', 'maxlength="300"'));
const sheetBtns = (act_, v) => `<div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="${act_}" data-v="${esc(v ?? '')}">${esc(T('save'))}</button></div>`;

function covHTML() {
  const c = OI.cov;
  if (!c) return '';
  if (c.ok) return `<div class="card" id="cov_ok" style="border-left:6px solid #2e7d32"><b>${esc(T('covOk'))}</b></div>`;
  return `<div class="card stack" id="cov_bad" style="border-left:6px solid #c62828"><b>${esc(T('covBad'))}</b>${(c.rows || []).map((r) => `<div class="row between cov-row"><span>${esc(r.key)}</span><span class="muted">${esc(r.problem)}</span></div>`).join('')}</div>`;
}

const TABS = [['enter', 't_enter'], ['chart', 't_chart'], ['cov', 't_cov'], ['set', 't_set']];
const tabsBar = () => `<div class="row wrap" id="oi_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${OI.tab === k ? 'on' : ''}" data-act="oi_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;

async function loadTab() {
  if (OI.tab === 'enter') {
    await loadHeads();
    OI.list = await call('_w1f_other_income_list', { p_loc: OI.loc ? Number(OI.loc) : null, p_from: null, p_to: null, p_limit: 100 });
  }
  if (OI.tab === 'chart') {
    await loadCoa();
    const [s, e, o] = await Promise.all([call('_w1f_seed_report', {}), call('_w1f_expense_heads', {}), call('_w1f_other_income_heads', {})]);
    OI.seeds = s || []; OI.eheads = e || []; OI.oheads = o || [];
  }
  if (OI.tab === 'cov') OI.cov = await call('_w1f_mapping_coverage', {});
  if (OI.tab === 'set') await loadRules();
}
function draw() {
  const el = $('#oi_body'); if (!el) return;
  const body = OI.tab === 'enter' ? enterHTML() : OI.tab === 'chart' ? chartHTML() : OI.tab === 'cov' ? covHTML() : settingsCard(['other_income_on', 'other_income_from']);
  el.innerHTML = tabsBar() + body;
  if (B.moneySrc && B.moneySrc.fillAll) B.moneySrc.fillAll(el);
}
async function showTab(tab) { if (tab) OI.tab = tab; try { await loadTab(); draw(); } catch (e) { toast(e.message || 'error'); draw(); } }

// ------------------------------------------------------------------ Customer bank / cheque receipts
const RC = { loc: null, cust: null, bal: null, rows: [], set: null, list: null, client: rid(), note: '', mobile: '' };
const CH = { cash: ['cash', 'cash'], mobile: ['mobile', 'wallet'], card: ['card', 'bank'], bank: ['bank', 'bank'], cheque: ['bank', 'bank'] };
const newRow = (ch) => ({ ch: ch || 'cash', amt: '', macc: '', ref: '', chq: '', chqd: '', why: '' });
const channelsOn = () => ['cash', 'mobile', 'card'].concat(RC.set && RC.set.bank_on ? ['bank', 'cheque'] : []);
const chLabel = (c) => T({ cash: 'r_cash', mobile: 'r_mobile2', card: 'r_card', bank: 'r_bank', cheque: 'r_cheque' }[c]);
const refNeeded = (r) => { const q = RC.set && RC.set.ref_required; if (!q || q === 'off') return false; return r.ch === 'bank' || r.ch === 'cheque' || (q === 'bank_mobile' && r.ch === 'mobile'); };
function srcSelect(i, r) {
  const d = B.moneySrc && B.moneySrc.cached ? B.moneySrc.cached('customer_collection', RC.loc || '') : null;
  if (!d || !(d.rows || []).length) return '';
  const kind = CH[r.ch][1];
  const rows = d.rows.filter((a) => a.kind === kind || (r.ch === 'card' && a.kind === 'bank'));
  const def = rows.find((a) => a.is_default);
  const first = d.require_source ? '' : `<option value="">${esc(def ? 'Default: ' + def.name_en : T('r_srcNone'))}</option>`;
  const fixed = !d.allow_override && d.default_id;
  return `<div><label>${esc(T('r_src'))}</label><select data-w1r="${i}.macc"${fixed ? ' disabled' : ''}>${first}${rows.map((a) => `<option value="${esc(String(a.id))}" ${String(r.macc) === String(a.id) ? 'selected' : ''}>${esc(a.name_en)}${a.provider && a.kind !== 'cash' ? ' · ' + esc(a.provider) : ''}${a.account_no ? ' · …' + esc(String(a.account_no).slice(-4)) : ''}</option>`).join('')}</select></div>`;
}
function rowHTML(r, i) {
  const showRef = r.ch !== 'cash' && r.ch !== 'cheque';
  return `<div class="card stack w1-prow" data-i="${i}"><div class="row between"><b>${esc(chLabel(r.ch))}</b>${RC.rows.length > 1 ? `<button type="button" class="mini" data-act="rc_del" data-v="${i}" aria-label="${esc(T('r_del'))}">✕</button>` : ''}</div>
    ${fld('rc_ch' + i, T('r_channel'), `<select id="rc_ch${i}" data-w1r="${i}.ch">${channelsOn().map((c) => `<option value="${c}" ${r.ch === c ? 'selected' : ''}>${esc(chLabel(c))}</option>`).join('')}</select>`)}
    ${fld('rc_amt' + i, T('r_amount'), `<input id="rc_amt${i}" data-w1r="${i}.amt" inputmode="decimal" autocomplete="off" value="${esc(r.amt)}">`)}
    ${srcSelect(i, r)}
    ${showRef ? fld('rc_ref' + i, T('r_ref'), `<input id="rc_ref${i}" data-w1r="${i}.ref" autocomplete="off" maxlength="60" value="${esc(r.ref)}">`) : ''}
    ${r.ch === 'cheque' ? `${fld('rc_chq' + i, T('r_chq'), `<input id="rc_chq${i}" data-w1r="${i}.chq" autocomplete="off" maxlength="40" value="${esc(r.chq)}">`)}${fld('rc_chqd' + i, T('r_chqd'), `<input id="rc_chqd${i}" data-w1r="${i}.chqd" type="date" value="${esc(r.chqd)}">`)}<p class="muted">${esc(T('r_chqHint'))}</p>` : ''}
    ${refNeeded(r) ? fld('rc_why' + i, T('r_why'), `<input id="rc_why${i}" data-w1r="${i}.why" autocomplete="off" maxlength="200" value="${esc(r.why)}">`) : ''}</div>`;
}
function receiptHTML() {
  const L_ = locs(), set = RC.set || {};
  const owner = !!(S.ctx && S.ctx.is_owner);
  const off = set.bank_on ? '' : `<div class="notice bad" id="rc_bankoff">${esc(T('r_bankOff'))}</div>`;
  const cust = RC.cust ? `<div class="card" id="rc_cust"><div class="row between"><b>${esc(RC.cust.name)}</b><span>${esc(RC.cust.mobile)}</span></div><div class="row between"><span>${esc(T('r_due'))}</span><b id="rc_due">${fm(RC.bal)}</b></div></div>` : '';
  const sum = RC.rows.reduce((s, r) => s + (nnum(r.amt) > 0 ? nnum(r.amt) : 0), 0);
  const form = `<div class="card stack">${fld('rc_loc', T('loc'), `<select id="rc_loc">${L_.map((x) => `<option value="${x.id}" ${String(x.id) === String(RC.loc) ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select>`)}
    <div class="row">${fld('rc_mobile', T('r_mobile'), inp('rc_mobile', RC.mobile, 'inputmode="tel"'))}<button type="button" class="btn" data-act="rc_find" style="align-self:end">${esc(T('r_find'))}</button></div></div>${cust}`;
  const pay = RC.cust ? `${RC.rows.map(rowHTML).join('')}<div class="row wrap"><button type="button" class="tog" data-act="rc_add">＋ ${esc(T('r_add'))}</button></div>
    ${fld('rc_note', T('r_note'), inp('rc_note', RC.note, 'maxlength="200"'))}
    <div class="row between"><span>${esc(T('r_amount'))}</span><b id="rc_sum">${fm(sum)}</b></div>
    <button type="button" class="primary full" data-act="rc_collect">${esc(T('r_collect'))}</button>` : '';
  const list = ((RC.list && RC.list.rows) || []).map((r) => `<div class="card rc-row ${r.voided ? 'muted' : ''}"><div class="row between"><b>${esc(r.customer_name || (r.receipt ? '#' + r.receipt : '-'))}</b><b>${fm(r.amount)}</b></div>
      <div class="muted">${esc(String(r.paid_at).slice(0, 10))} · ${esc(r.kind === 'collection' ? 'Due collection' : 'Sale')} · ${esc(r.mode)}${r.account_name ? ' · ' + esc(r.account_name) : ''}${r.ref ? ' · ' + esc(r.ref) : ''}${r.cheque_no ? ' · cheque ' + esc(r.cheque_no) : ''}${r.ref_waiver ? ' · ' + esc(T('r_waived')) + ': ' + esc(r.ref_waiver) : ''}${r.voided ? ' · voided' : ''}</div></div>`).join('');
  return off + form + pay + `<h3>${esc(T('r_recent'))}</h3>${list || `<p class="muted">${esc(T('none'))}</p>`}<p class="muted" style="font-size:.85rem">${esc(T('r_defaults'))}</p>`
    + (owner ? `<h3>${esc(T('t_set'))}</h3>${settingsCard(['receipt_bank_on', 'receipt_ref_required', 'receipt_ref_from'])}` : '');
}
async function loadReceipts() {
  RC.set = await call('_w1f_receipt_settings', {});
  RC.list = await call('_w1f_receipts_list', { p_loc: RC.loc ? Number(RC.loc) : null, p_from: null, p_to: null, p_limit: 40 });
  if (B.moneySrc && B.moneySrc.prefetch) await B.moneySrc.prefetch('customer_collection', RC.loc || null);
  if (S.ctx && S.ctx.is_owner) await loadRules();
}
function drawReceipts() {
  const el = $('#rc_body'); if (!el) return;
  if (!RC.rows.length) RC.rows = [newRow('cash')];
  el.innerHTML = receiptHTML();
}
async function showReceipts() { try { await loadReceipts(); drawReceipts(); } catch (e) { toast(e.message || 'error'); drawReceipts(); } }

// ------------------------------------------------------------------ handlers
Object.assign(H, {
  oi_tab: (a) => showTab(a.dataset.v),
  oi_dry: act(async () => { const a = oiArgs(true); if (!(a.p_amount > 0)) return toast(ERR.bad_amount); await call('_w1f_other_income_add', a); toast(T('dry')); }),
  oi_save: act(async () => {
    const a = oiArgs(false); if (!(a.p_amount > 0)) return toast(ERR.bad_amount);
    await call('_w1f_other_income_add', a); OI.client = rid(); OI.photo = ''; toast(T('saved')); await showTab('enter');
  }),
  oi_void: (a) => {
    openSheet(`<h3>${esc(T('voidWhy'))}</h3><div class="stack">${reasonField('vd_why')}${sheetBtns('oi_voidgo', a.dataset.v)}</div>`);
  },
  oi_voidgo: act(async (a) => {
    const why = val('vd_why'); if (why.length < 3) return toast(ERR.reason_required);
    await call('_w1f_other_income_void', { p_id: a.dataset.v, p_note: why }); closeSheet(); toast(T('voided')); await showTab('enter');
  }),
  w1_setsave: act(async (a) => {
    const todo = [];
    for (const k of a.dataset.v.split(',')) {
      const el = $('#rs_' + k); if (!el) continue;
      let v;
      if (el.type === 'checkbox') v = el.checked; else if (k.endsWith('_from')) v = el.value.trim() === '' ? null : el.value.trim(); else v = el.value;
      if (typeof v === 'string' && k.endsWith('_from') && !/^\d{4}-\d{2}-\d{2}$/.test(v)) return toast(ERR.bad_date);       // check everything first: nothing is half saved
      const cur = rv(k);
      if (cur === v || (k.endsWith('_from') && (cur || null) === v)) continue;
      todo.push([k, v]);
    }
    for (const [k, v] of todo) await setRule(k, v);
    toast(T('saved')); await loadRules(); if (OI.tab === 'set') draw(); else await showReceipts();
  }),
  // chart & heads
  w1_rename: (a) => { const s = OI.seeds.find((x) => x.key === a.dataset.v); if (!s) return;
    openSheet(`<h3>${esc(T('rename'))}</h3><div class="stack">${fld('rn_en', T('label'), inp('rn_en', s.name_en, 'maxlength="120"'))}${sheetBtns('w1_renamego', s.key)}</div>`); },
  w1_renamego: act(async (a) => { const n = val('rn_en'); if (!n) return toast(ERR.name_required); await call('_w1f_seed_edit', { p_key: a.dataset.v, p_name_en: n, p_name_bn: n, p_active: null, p_reason: null }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  w1_newcode: (a) => { const s = OI.seeds.find((x) => x.key === a.dataset.v); if (!s) return;
    openSheet(`<h3>${esc(T('newcode'))}</h3><p class="muted">A new account with this code takes over from now on. The old account is switched off when it has no postings; its history is never moved.</p><div class="stack">
      ${fld('nc_code', T('code'), inp('nc_code', '', 'maxlength="12"'))}${fld('nc_name', T('label'), inp('nc_name', s.name_en || '', 'maxlength="120"'))}${reasonField('nc_why')}${sheetBtns('w1_newcodego', s.key)}</div>`); },
  w1_newcodego: act(async (a) => { const c = val('nc_code'); if (!c) return toast(ERR.bad_code); await call('_w1f_seed_new_code', { p_key: a.dataset.v, p_code: c, p_name_en: val('nc_name') || null, p_name_bn: null, p_reason: val('nc_why') || null }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  w1_map: async (a) => { try { await loadCoa(); } catch (e) { return toast(e.message); } const s = OI.seeds.find((x) => x.key === a.dataset.v); if (!s) return;
    openSheet(`<h3>${esc(T('choose'))}</h3><div class="stack">${fld('mp_acc', T('acc'), `<select id="mp_acc">${accOpts(s.type, s.code)}</select>`)}${reasonField('mp_why')}${sheetBtns('w1_mapgo', s.key)}</div>`); },
  w1_mapgo: act(async (a) => { await call('_w1f_seed_map', { p_key: a.dataset.v, p_account_code: val('mp_acc'), p_reason: val('mp_why') || null }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  w1_active: (a) => { const s = OI.seeds.find((x) => x.key === a.dataset.v); if (!s) return;
    if (!s.active) { call('_w1f_seed_edit', { p_key: s.key, p_name_en: null, p_name_bn: null, p_active: true, p_reason: null }).then(() => { toast(T('saved')); return showTab('chart'); }).catch((e) => toast(e.message)); return; }
    openSheet(`<h3>${esc(T('offb'))}</h3><div class="stack">${reasonField('ac_why')}${sheetBtns('w1_activego', s.key)}</div>`); },
  w1_activego: act(async (a) => { const w = val('ac_why'); if (w.length < 3) return toast(ERR.reason_required); await call('_w1f_seed_edit', { p_key: a.dataset.v, p_name_en: null, p_name_bn: null, p_active: false, p_reason: w }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  w1_ehead: (a) => { const h = OI.eheads.find((x) => x.code === a.dataset.v); const isNew = !h;
    openSheet(`<h3>${esc(isNew ? T('addhead') : h.label_en)}</h3><div class="stack">
      ${isNew ? fld('eh_code', T('code'), inp('eh_code', '', 'maxlength="31" placeholder="insurance"')) : ''}${fld('eh_label', T('label'), inp('eh_label', h ? h.label_en : '', 'maxlength="120"'))}
      ${fld('eh_acc', T('acc'), `<select id="eh_acc">${accOpts('expense', h ? h.account_code : '', isNew ? '—' : '')}</select>`)}${fld('eh_eff', T('effective'), inp('eh_eff', today(), 'type="date"'))}
      ${reasonField('eh_why', T('reason') + (h && Number(h.unposted) ? ' (needed: ' + Number(h.unposted) + ' ' + T('unposted') + ')' : ''))}${sheetBtns('w1_eheadgo', h ? h.code : '')}</div>`); },
  w1_eheadgo: act(async (a) => {
    const code = a.dataset.v || val('eh_code'); if (!/^[a-z][a-z0-9_]{1,30}$/.test(code)) return toast(ERR.bad_head_code);
    await call('_w1f_expense_head_set', { p_code: code, p_label_en: val('eh_label') || null, p_label_bn: null, p_account_code: val('eh_acc') || null, p_active: true, p_effective_from: val('eh_eff') || null, p_reason: val('eh_why') || null });
    closeSheet(); toast(T('saved')); await showTab('chart');
  }),
  w1_eretire: (a) => { openSheet(`<h3>${esc(T('retire'))}</h3><div class="stack">${reasonField('er_why')}${sheetBtns('w1_eretirego', a.dataset.v)}</div>`); },
  w1_eretirego: act(async (a) => { const w = val('er_why'); if (w.length < 3) return toast(ERR.reason_required); await call('_w1f_expense_head_set', { p_code: a.dataset.v, p_label_en: null, p_label_bn: null, p_account_code: null, p_active: false, p_effective_from: null, p_reason: w }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  w1_ohead: (a) => { const h = OI.oheads.find((x) => x.code === a.dataset.v); const isNew = !h;
    openSheet(`<h3>${esc(isNew ? T('addhead') : h.label_en)}</h3><div class="stack">
      ${isNew ? fld('oh_code', T('code'), inp('oh_code', '', 'maxlength="31" placeholder="commission"')) : ''}${fld('oh_label', T('label'), inp('oh_label', h ? h.label_en : '', 'maxlength="120"'))}
      ${fld('oh_acc', T('acc') + ' (blank = Other income)', `<select id="oh_acc">${accOpts('income', h && h.own_account ? h.account_code : '', '—')}</select>`)}${sheetBtns('w1_oheadgo', h ? h.code : '')}</div>`); },
  w1_oheadgo: act(async (a) => {
    const code = a.dataset.v || val('oh_code'); if (!/^[a-z][a-z0-9_]{1,30}$/.test(code)) return toast(ERR.bad_head_code);
    await call('_w1f_other_income_head_set', { p_code: code, p_label_en: val('oh_label') || null, p_label_bn: null, p_account_code: val('oh_acc') || null, p_active: true, p_reason: null });
    closeSheet(); toast(T('saved')); await showTab('chart');
  }),
  w1_oretire: (a) => { openSheet(`<h3>${esc(T('retire'))}</h3><div class="stack">${reasonField('or_why')}${sheetBtns('w1_oretirego', a.dataset.v)}</div>`); },
  w1_oretirego: act(async (a) => { const w = val('or_why'); if (w.length < 3) return toast(ERR.reason_required); await call('_w1f_other_income_head_set', { p_code: a.dataset.v, p_label_en: null, p_label_bn: null, p_account_code: null, p_active: false, p_reason: w }); closeSheet(); toast(T('saved')); await showTab('chart'); }),
  // customer receipts
  rc_find: act(async () => {
    const m = val('rc_mobile'); RC.mobile = m; if (!m) return;
    const r = await sb.from('customers').select('id,name,mobile').eq('mobile', m).limit(1);
    const c = r.data && r.data[0];
    if (!c) { RC.cust = null; RC.bal = null; drawReceipts(); return toast(T('r_none')); }
    RC.cust = c; const b = await sb.rpc('customer_balance', { p_customer: c.id }); RC.bal = b.error ? null : Number(b.data); RC.client = rid(); drawReceipts();
  }),
  rc_add: () => { RC.rows.push(newRow(channelsOn()[0])); drawReceipts(); },
  rc_del: (a) => { RC.rows.splice(Number(a.dataset.v), 1); drawReceipts(); },
  rc_collect: act(async () => {
    RC.note = val('rc_note');
    const pays = [];
    for (const r of RC.rows) {
      const amt = nnum(r.amt); if (!(amt > 0)) continue;
      if (r.ch === 'cheque' && !r.chq.trim()) return toast(T('r_needChq'));
      if (refNeeded(r) && !r.ref.trim() && !r.chq.trim() && r.why.trim().length < 3) return toast(T('r_needRef'));
      const p = { mode: CH[r.ch][0], amount: amt };
      if (r.macc) p.money_account_id = Number(r.macc);
      if (r.ref.trim()) p.ref = r.ref.trim();
      if (r.ch === 'cheque') { p.cheque_no = r.chq.trim(); if (r.chqd) p.cheque_date = r.chqd; }
      if (r.why.trim()) p.exception_reason = r.why.trim();
      pays.push(p);
    }
    if (!pays.length) return toast(ERR.no_payments);
    const sum = pays.reduce((s, p) => s + p.amount, 0);
    if (RC.bal != null && sum > RC.bal + 0.001) return toast(T('r_over'));
    const r = await call('_w1f_collect_payment', { p_client: RC.client, p_loc: Number(RC.loc), p_customer: RC.cust.id, p_payments: pays, p_note: RC.note || null });
    RC.client = rid(); RC.rows = [newRow('cash')]; RC.note = ''; toast(T('r_done') + ' ' + fm(r && r.collected != null ? r.collected : sum));
    const b = await sb.rpc('customer_balance', { p_customer: RC.cust.id }); RC.bal = b.error ? RC.bal : Number(b.data);
    RC.list = await call('_w1f_receipts_list', { p_loc: Number(RC.loc), p_from: null, p_to: null, p_limit: 40 }); drawReceipts();
  }),
});
document.addEventListener('input', (e) => {
  const k = e.target && e.target.dataset && e.target.dataset.w1r; if (!k) return;
  const [i, f] = k.split('.'); const r = RC.rows[Number(i)]; if (!r) return; r[f] = e.target.value;
  const s = $('#rc_sum'); if (s) s.textContent = fm(RC.rows.reduce((t, x) => t + (nnum(x.amt) > 0 ? nnum(x.amt) : 0), 0));
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t) return;
  const k = t.dataset && t.dataset.w1r;
  if (k) { const [i, f] = k.split('.'); const r = RC.rows[Number(i)]; if (!r) return; r[f] = t.value; if (f === 'ch') { r.macc = ''; drawReceipts(); } return; }
  if (t.id === 'oi_loc') { OI.loc = Number(t.value); showTab('enter'); }
  if (t.id === 'rc_loc') { RC.loc = Number(t.value); showReceipts(); }
  if (t.id === 'oi_file' && t.files && t.files[0]) {
    const f = t.files[0]; const up = B.s2 && B.s2.uploadPhoto;
    if (!up) return toast('Photo upload is not available.');
    toast('…'); up(f, ['ACCOUNTS', 'STOCK', '10-2'], Number(val('oi_loc')) || (locs()[0] || {}).id).then((p) => { OI.photo = p; const el = $('#oi_ph'); if (el) el.textContent = '📎 ' + p; }).catch((er) => toast(er.message || 'error'));
  }
});

async function viewOtherIncome() {
  if (B.loadStatic) await B.loadStatic();
  const L_ = locs(); if (!OI.loc || !L_.find((x) => String(x.id) === String(OI.loc))) OI.loc = (L_[0] || {}).id;
  shell(T('title'), '<div id="oi_body"><p class="muted">…</p></div>', true);
  try { await showTab(OI.tab); } catch (e) { fail(e); }
}
async function viewReceipts() {
  if (B.loadStatic) await B.loadStatic();
  const L_ = locs(); if (!RC.loc || !L_.find((x) => String(x.id) === String(RC.loc))) RC.loc = (L_[0] || {}).id;
  shell(T('r_title'), '<div id="rc_body"><p class="muted">…</p></div>', true);
  try { await showReceipts(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { otherincome: viewOtherIncome, bankreceipt: viewReceipts });
})();
