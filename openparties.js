/* Islamia BOS · Opening dues and payables (#/openparties). One place for what customers owed us and what we owed suppliers BEFORE go-live (plan item U-01).
   The job: type each old due once, import a paper list in one paste, see for every party the books figure, the customer/supplier sub-ledger figure and the DIFFERENCE,
   change a figure after the opening only with a reason, and run the gate "sub-ledger equals general ledger for every party".
   Server: supabase/phase88.sql (w1a_open_state / list / set / import / json / precheck / from_journal / adjust / adjust_decide / adjust_list, w1a_party_gate).
   Three settings (Rules hub, module books; the owner edits them here too, every change is a change-log line): open_parties_link (OFF), open_parties_freeze (off), open_parties_adjust_mode (direct).
   The hooks that make the typed due count in the customer balance are in docs/integration/W1-A.md (integrator). Until they are pasted the screen still works; the balance is simply not changed.
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { if (n === null || n === undefined || n === '') return '-'; const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;

const TABS = [['customers', 'Customers'], ['suppliers', 'Suppliers'], ['import', 'Paste import'], ['changes', 'Changes'], ['gate', 'Check'], ['settings', 'Settings']];
const ERR = {
  not_allowed: 'You do not have permission.', bad_kind: 'Unknown kind.', negative_not_allowed: 'A customer opening cannot be negative.', bad_amount: 'Amount is not valid.', unknown_party: 'Unknown customer or supplier.',
  opening_posted_use_adjust: 'The opening is already posted. Use "Change with reason".', opening_frozen: 'The opening is locked. Use "Change with reason".', reason_required: 'Write a reason (at least 3 characters).',
  no_change: 'That is the same figure.', adjust_pending_exists: 'A change for this party is already waiting for a decision.', maker_cannot_decide: 'The person who asked cannot decide the same request.',
  named_approver_only: 'Only the approver named by the owner can decide this.', not_pending: 'This request was already decided.', note_required: 'Write a note.', import_has_errors: 'The file has rows that are not valid: nothing was imported.',
  too_many_rows: 'More than 2000 rows: split the file.', no_rows: 'The file is empty.', bad_value: 'Value is not valid.', data_needed: 'Accounting start date is not set.', no_opening_posted: 'No opening entry has been posted yet.',
  period_closed: 'That period is closed.', bad_payload: 'The opening data is not valid.',
};
const eText = (e) => { const m = String((e && e.message) || '').replace(/\bnot allowed\b/, 'not_allowed'); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const CAUSE = {
  opening_in_books_not_in_subledger: 'The opening is in the books but not in the sub-ledger. Fill it from the opening journal.',
  opening_in_subledger_not_in_books: 'The opening is typed in the sub-ledger but the books do not have it. Post it in the opening batch or change it with a reason.',
  opening_amounts_differ: 'The opening in the books and in the sub-ledger are different amounts.',
  transactions_differ: 'The openings agree; the difference comes from sales, payments or journals. Look at the party ledger.',
};
const STAT = { ok: 'will change', same: 'no change', will_create: 'new customer', unknown_party: 'not found', duplicate_row: 'repeated', bad_amount: 'amount not valid', bad_mobile: 'mobile not valid',
  negative_not_allowed: 'negative not allowed', party_missing: 'no mobile or name', bad_date: 'date not valid', ambiguous_party: 'more than one match', bad_row: 'row not valid' };
const D = { tab: 'customers', st: null, err: null, lists: { customer: null, supplier: null }, q: '', only: 'all', limit: 100, imp: { kind: 'customer', text: '', create: false, dry: null, hash: '' }, ch: null, gate: null, fill: null, rules: null, json: null, pre: null, adj: { client: rid() } };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; e.code = r.error.code; throw e; }
  return r.data;
}
const missing = (e) => e && e.raw && (e.raw.code === 'PGRST202' || /does not exist|could not find/i.test(String(e.raw.message || '')));

// ---------------- header ----------------
function headHTML() {
  const s = D.st; if (!s) return '';
  return `<div class="card stack" id="op_head">
    <div class="row wrap">${chip(s.link ? 'Typed dues count in customer balances: ON' : 'Typed dues count in customer balances: OFF', s.link ? 'ok' : 'warn')}${chip('Lock after opening: ' + (s.freeze === 'after_opening' ? 'on' : 'off'))}
      ${chip(s.batch_exists ? 'Opening batch posted' : 'Opening batch not posted yet', s.batch_exists ? 'ok' : 'info')}${s.pending_adjustments > 0 ? chip(s.pending_adjustments + ' change(s) waiting', 'warn') : ''}</div>
    <div class="muted">Customers with an opening: ${esc(String(s.customers_typed))} · ${fm(s.customers_typed_total)} &nbsp;|&nbsp; Suppliers with an opening: ${esc(String(s.suppliers_typed))} · ${fm(s.suppliers_typed_total)}${s.accounting_start ? ' · Accounting starts ' + esc(String(s.accounting_start)) : ''}</div>
    ${s.batch_exists ? '<div class="muted">The opening is posted. A figure can now only be changed with a written reason; it makes a balanced journal entry, a change-log line and a row in the Exceptions list.</div>'
      : '<div class="muted">Type each old due once. The opening screen takes the customer and supplier sections from this list, so nothing is typed twice.</div>'}
    ${!s.link && Number(s.customers_typed) > 0 ? '<div class="notice warn" id="op_linkoff">Customer dues are saved here but NOT counted yet: the switch is OFF, so these customers still cannot pay the old due. The owner turns it on in Settings.</div>' : ''}
  </div>`;
}
function tabsBar() { return `<div class="row wrap" id="op_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="op_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`; }

// ---------------- the two lists ----------------
function listHTML(kind) {
  const L = D.lists[kind]; const s = D.st || {};
  const bar = `<div class="card stack"><div class="row wrap">${fld('op_q', 'Search name or mobile', inp('op_q', D.q, 'maxlength="60"'))}
      ${fld('op_only', 'Show', `<select id="op_only">${[['all', 'Everyone'], ['opening', 'Only parties with an opening'], ['diff', 'Only differences']].map(([k, l]) => `<option value="${k}" ${D.only === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`)}</div>
      <button type="button" class="primary full" data-act="op_show">Show</button></div>`;
  if (!L) return bar;
  const rows = (L.rows || []).map((r) => {
    const df = Number(r.difference), has = Math.abs(df) > 0.005;
    return `<div class="card op-row" data-id="${esc(r.id)}"><div class="row between"><b>${esc(r.name)}</b><b class="mnum">${r.opening === null || r.opening === undefined ? '-' : fm(r.opening)}</b></div>
      <div class="muted">${r.mobile ? esc(r.mobile) + ' · ' : ''}${r.opening_date ? 'opening date ' + esc(String(r.opening_date)) + ' · ' : ''}opening in the books ${fm(r.journal_opening)}${r.active === false ? ' · inactive' : ''}</div>
      <div class="row between"><span>Books</span><span class="mnum">${fm(r.journal_balance)}</span></div>
      <div class="row between"><span>Sub-ledger</span><span class="mnum">${fm(r.subledger_balance)}</span></div>
      <div class="row between op-diff ${has ? 'bad' : ''}"><span>Difference (books minus sub-ledger)</span><b class="mnum">${has ? fm(df) : '0.00'}</b></div>
      ${s.can_manage ? `<div class="row wrap"><button type="button" class="mini" data-act="${s.batch_exists ? 'op_change' : 'op_type'}" data-v="${esc(r.id)}" data-k="${kind}">${s.batch_exists ? 'Change with reason' : 'Type opening'}</button></div>` : ''}</div>`;
  }).join('');
  return bar + (rows || '<p class="muted" id="op_none">Nobody matches.</p>') + (L.has_more ? '<button type="button" class="full" data-act="op_more">Show more</button>' : '');
}
function partyOf(kind, id) { const L = D.lists[kind]; return L && (L.rows || []).find((r) => String(r.id) === String(id)); }
function typeSheet(kind, id) {
  const p = partyOf(kind, id); if (!p) return;
  openSheet(`<h3>Opening ${kind === 'customer' ? 'due' : 'payable'}: ${esc(p.name)}</h3><div class="stack">
    <p class="muted">${kind === 'customer' ? 'What this customer owed us before go-live.' : 'What we owed this supplier before go-live (a negative figure means the supplier owes us).'} Leave empty to clear.</p>
    ${fld('ty_amt', 'Amount', inp('ty_amt', p.opening ?? '', 'inputmode="decimal"'))}${fld('ty_date', 'Date of the figure (optional)', inp('ty_date', p.opening_date || '', 'type="date"'))}
    ${fld('ty_note', 'Where it comes from (paper page, statement)', inp('ty_note', '', 'maxlength="200"'))}
    <button type="button" class="primary full" data-act="op_typego" data-v="${esc(id)}" data-k="${kind}">Save</button></div>`);
}
function changeSheet(kind, id) {
  const p = partyOf(kind, id); if (!p) return;
  const mode = D.st && D.st.adjust_mode === 'approval';
  openSheet(`<h3>Change the opening: ${esc(p.name)}</h3><div class="stack">
    <p class="muted">Now ${p.opening === null || p.opening === undefined ? 'empty' : fm(p.opening)}. ${mode ? 'A second person must approve this change.' : 'The change is made at once.'} It makes a balanced journal entry, a change-log line and a row in the Exceptions list.</p>
    ${fld('ch_amt', 'New amount', inp('ch_amt', p.opening ?? '', 'inputmode="decimal"'))}
    ${fld('ch_why', 'Reason (required)', inp('ch_why', '', 'maxlength="300"'))}
    <button type="button" class="primary full" data-act="op_changego" data-v="${esc(id)}" data-k="${kind}">${mode ? 'Ask for approval' : 'Change'}</button></div>`);
}

// ---------------- paste import ----------------
function parseRows(text, kind) {
  const out = []; let first = true;
  for (const raw of String(text || '').split(/\r?\n/)) {
    const line = raw.trim(); if (!line) continue;
    const cells = (line.includes('\t') ? line.split('\t') : line.split(/[;,]/)).map((c) => c.trim());
    if (first) { first = false; if (cells.length > 1 && !/^-?[0-9০-৯][0-9০-৯.,]*$/.test(cells[1])) continue; }     // a header line
    const key = cells[0] || '', digits = norm(key).replace(/[^0-9]/g, '');
    const row = {};
    if (digits.length >= 10 && !/[A-Za-z]/.test(key)) row.mobile = key; else if (key) row.name = key;
    row.amount = norm(cells[1] || '');
    if (cells[2] && /^\d{4}-\d{2}-\d{2}$/.test(cells[2])) row.date = cells[2];
    if (cells[3] && kind === 'customer') row.name = cells[3];
    out.push(row);
  }
  return out;
}
const impHash = () => D.imp.kind + '|' + D.imp.create + '|' + D.imp.text;
function importHTML() {
  const I = D.imp, r = I.dry; const fresh = r && I.hash === impHash();
  const head = `<div class="card stack"><b>Paste a list of old dues</b>
    <p class="muted">One party per line: <b>mobile or name</b>, <b>amount</b>, date (optional, YYYY-MM-DD), name of a new customer (optional). Separate with a comma, a semicolon or a tab (write amounts without a thousands comma). Check first: nothing is written until you press Import, and one bad row refuses the whole file.</p>
    ${fld('im_kind', 'Who', `<select id="im_kind"><option value="customer" ${I.kind === 'customer' ? 'selected' : ''}>Customers (they owe us)</option><option value="supplier" ${I.kind === 'supplier' ? 'selected' : ''}>Suppliers (we owe them)</option></select>`)}
    <label for="im_text">The list</label><textarea id="im_text" rows="7" autocomplete="off" spellcheck="false">${esc(I.text)}</textarea>
    ${I.kind === 'customer' ? `<label class="row"><input type="checkbox" id="im_create" ${I.create ? 'checked' : ''}> Add customers that are not in the system yet (needs mobile and name)</label>` : ''}
    <div class="row"><button type="button" class="primary" data-act="op_imcheck">Check</button>${fresh && Number(r.errors) === 0 && (Number(r.ok) + Number(r.create)) > 0 ? `<button type="button" class="btn" id="op_imgo" data-act="op_imgo">Import ${esc(String(Number(r.ok) + Number(r.create)))} row(s)</button>` : ''}</div></div>`;
  if (!r) return head + jsonCardHTML();
  const bad = Number(r.errors) > 0;
  return head + `<div class="card stack" id="op_imres"><div class="row wrap">${chip(r.ok + ' will change', 'ok')}${Number(r.create) ? chip(r.create + ' new customer(s)', 'info') : ''}${chip(r.same + ' no change')}${bad ? chip(r.errors + ' not valid', 'bad') : ''}${chip('total ' + fm(r.total_new))}</div>
    ${fresh ? '' : '<div class="notice warn">The list changed after the check. Check again.</div>'}
    ${(r.rows || []).filter((x) => x.status !== 'same').map((x) => `<div class="row between op-imrow"><span>#${esc(String(x.i))} ${esc(x.name || '')}</span><span>${chip(STAT[x.status] || x.status, x.status === 'ok' || x.status === 'will_create' ? 'ok' : 'bad')} ${x.new === null || x.new === undefined ? '' : fm(x.new)}</span></div>`).join('')}
    ${bad ? '<p class="muted">Fix the rows marked in red and check again. Nothing was written.</p>' : ''}</div>` + jsonCardHTML();
}
function jsonCardHTML() {
  const s = D.st || {};
  if (!s.can_manage) return '';
  const j = D.json;
  return `<div class="card stack" id="op_jsoncard"><b>For the opening screen</b>
    <p class="muted">The customer and supplier sections of the opening entry, made from the figures typed here (nothing is typed twice). Paste them into the opening data, or compare a full opening JSON with this list before you post it.</p>
    <button type="button" class="btn" data-act="op_json">Make the sections</button>
    ${j ? (j.batch_exists ? '<p class="muted">The opening is already posted.</p>' : `<div class="row wrap">${chip(j.customer_dues.length + ' customer line(s)')}${chip(j.supplier_dues.length + ' supplier line(s)')}${(j.not_postable || []).length ? chip((j.not_postable || []).length + ' cannot be posted here', 'warn') : ''}</div>
      <textarea id="op_jsonout" rows="5" readonly>${esc(JSON.stringify({ customer_dues: j.customer_dues, supplier_dues: j.supplier_dues }))}</textarea>
      ${(j.not_postable || []).map((x) => `<div class="muted">${esc(x.name)} ${fm(x.amount)}: ${esc(x.why)}</div>`).join('')}`) : ''}
    <label for="pc_text">Compare an opening JSON with the list</label><textarea id="pc_text" rows="4" autocomplete="off" spellcheck="false" placeholder="{...}"></textarea>
    <button type="button" class="btn" data-act="op_precheck">Compare</button>
    ${D.pre ? `<div id="op_pre"><div class="row wrap">${chip(D.pre.differing ? D.pre.differing + ' differ' : 'All agree', D.pre.differing ? 'warn' : 'ok')}</div>${(D.pre.rows || []).filter((x) => x.status !== 'same').map((x) => `<div class="row between"><span>${esc(x.name || x.party_id)} (${esc(x.kind)})</span><span>${esc(x.status.replace(/_/g, ' '))} · file ${fm(x.json_amount)} · typed ${fm(x.typed)}</span></div>`).join('')}</div>` : ''}</div>`;
}

// ---------------- changes ----------------
function changesHTML() {
  const c = D.ch; if (!c) return '';
  const rows = (c.rows || []).map((a) => `<div class="card op-adj" data-id="${a.id}"><div class="row between"><b>${esc(a.party_name || '')}</b>${chip(a.status, a.status === 'approved' ? 'ok' : a.status === 'pending' ? 'warn' : 'bad')}</div>
      <div class="row between"><span>${esc(a.kind)}: ${fm(a.old_amount)} → ${fm(a.new_amount)}</span><b class="mnum">${Number(a.delta) > 0 ? '+' : ''}${fm(a.delta)}</b></div>
      <div class="muted">Reason: ${esc(a.reason)}${a.decision_note ? ' · Decision: ' + esc(a.decision_note) : ''}${a.journal_entry_id ? ' · journal #' + esc(String(a.journal_entry_id)) : ''}</div>
      ${a.status === 'pending' ? (a.can_decide ? `<div class="row wrap"><button type="button" class="mini" data-act="op_decide" data-v="${a.id}" data-ok="1">Approve</button><button type="button" class="mini" data-act="op_decide" data-v="${a.id}" data-ok="0">Reject</button></div>` : '<div class="muted">Waiting for a second person.</div>') : ''}</div>`).join('');
  return `<p class="muted">Every change after the opening: who asked, the reason, the journal entry. The same lines are in the Exceptions list.</p>` + (rows || '<p class="muted" id="op_nochg">No changes yet.</p>');
}
function decideSheet(id, ok) {
  openSheet(`<h3>${ok ? 'Approve' : 'Reject'} the change</h3><div class="stack">${fld('dc_note', ok ? 'Note (optional)' : 'Reason (required)', inp('dc_note', '', 'maxlength="300"'))}
    <button type="button" class="primary full" data-act="op_decidego" data-v="${id}" data-ok="${ok ? 1 : 0}">${ok ? 'Approve' : 'Reject'}</button></div>`);
}

// ---------------- gate ----------------
function gateHTML() {
  const g = D.gate;
  const run = '<div class="card stack"><p class="muted">For every customer and supplier the sub-ledger figure must equal the general ledger (the journal). A party that differs is listed with the cause.</p><button type="button" class="primary full" data-act="op_gate">Check now</button></div>';
  if (!g) return run;
  if (g.status === 'data_needed') return run + '<div class="notice warn">Accounting start date is not set.</div>';
  const rowsOf = (list, label) => (list || []).map((x) => `<div class="card op-gate" data-id="${esc(x.party_id)}"><div class="row between"><b>${esc(x.name)}</b><b class="mnum bad">${fm(x.difference)}</b></div>
      <div class="muted">${label} · books ${fm(x.journal)} · sub-ledger ${fm(x.existing)} · opening typed ${fm(x.typed_opening)} · opening in the books ${fm(x.journal_opening)}</div>
      <div>${esc(CAUSE[x.cause] || '')}</div></div>`).join('');
  const f = D.fill;
  return run + `<div class="card" id="op_gatebanner" data-status="${esc(g.status)}" style="border-left:6px solid ${g.status === 'green' ? '#2e7d32' : '#c62828'}"><b>${g.status === 'green' ? 'All parties agree with the books.' : 'RED: ' + (Number(g.customers_off) + Number(g.suppliers_off)) + ' party(ies) do not agree.'}</b>
      ${g.link ? '' : '<div class="muted">The switch for customer openings is OFF, so a customer opening that is typed but not counted shows as a difference.</div>'}</div>`
    + rowsOf(g.customers, 'Customer') + rowsOf(g.suppliers, 'Supplier')
    + (Number(g.unattributed_receivable) ? `<div class="notice warn">Receivable lines with no customer in the books: ${fm(g.unattributed_receivable)}.</div>` : '')
    + (g.status === 'red' && D.st && D.st.can_manage && D.st.batch_exists ? `<div class="card stack"><b>Fill from the opening journal</b><p class="muted">If the opening was posted before this screen existed, copy each party's opening figure from the posted entry. Parties that already have a different figure are listed and never overwritten.</p>
        <button type="button" class="btn" data-act="op_fillcheck">Check</button>
        ${f ? `<div id="op_fill"><div class="row wrap">${chip(f.filled + ' would be filled', 'ok')}${chip(f.same + ' already right')}${Number(f.conflicts) ? chip(f.conflicts + ' differ (not changed)', 'warn') : ''}</div>${f.dry && Number(f.filled) > 0 ? '<button type="button" class="primary full" data-act="op_fillgo">Fill now</button>' : ''}</div>` : ''}</div>` : '');
}

// ---------------- settings ----------------
const RULE_KEYS = ['open_parties_link', 'open_parties_freeze', 'open_parties_adjust_mode'];
const CHOICE_LABEL = { off: 'Off (changes allowed as today)', after_opening: 'Locked after the opening batch', direct: 'Direct (made at once, with a reason)', approval: 'Needs a second person' };
function settingsHTML() {
  const rs = D.rules || [];
  const owner = !!(S && S.ctx && S.ctx.is_owner);
  return `<p class="muted">The owner can change these at any time. Every change is written to the change log. The defaults keep today's behaviour.</p>` + rs.map((r) => {
    const cur = r.value === null || r.value === undefined ? r.default_value : r.value;
    const ctl = r.kind === 'switch'
      ? (owner ? `<label class="row"><input type="checkbox" id="rl_${esc(r.key)}" ${cur === true ? 'checked' : ''}> On</label>` : chip(cur === true ? 'On' : 'Off'))
      : (owner ? `<select id="rl_${esc(r.key)}">${(r.choices || []).map((c) => `<option value="${esc(c)}" ${c === cur ? 'selected' : ''}>${esc(CHOICE_LABEL[c] || c)}</option>`).join('')}</select>` : chip(CHOICE_LABEL[cur] || String(cur)));
    return `<div class="card stack op-rule" data-key="${esc(r.key)}"><b>${esc(r.label_en)}</b><div class="muted">${esc(r.hint_en)}</div>${ctl}${owner ? `<button type="button" class="mini" data-act="op_rulesave" data-v="${esc(r.key)}">Save</button>` : '<div class="muted">Only the owner changes this.</div>'}</div>`;
  }).join('') || '<p class="muted">Settings are not available.</p>';
}

// ---------------- draw and load ----------------
function draw() {
  const el = $('#op_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(D.err === 'nofn' ? 'phase88.sql has not been run on the server yet.' : D.err === 'denied' ? 'You do not have permission to open this page.' : D.err)}</p></div>`; return; }
  const body = ({ customers: () => listHTML('customer'), suppliers: () => listHTML('supplier'), import: importHTML, changes: changesHTML, gate: gateHTML, settings: settingsHTML })[D.tab]();
  el.innerHTML = headHTML() + tabsBar() + `<div id="op_pane">${body}</div>`;
}
async function loadList(kind, more) {
  const off = more ? ((D.lists[kind] && D.lists[kind].rows) || []).length : 0;
  const r = await call('w1a_open_list', { p_kind: kind, p_search: D.q || null, p_only: D.only, p_limit: D.limit, p_offset: off });
  if (more && D.lists[kind]) { D.lists[kind] = { ...r, rows: [...D.lists[kind].rows, ...(r.rows || [])] }; } else D.lists[kind] = r;
}
async function loadTab() {
  D.st = await call('w1a_open_state', {});
  if (D.tab === 'customers') await loadList('customer');
  if (D.tab === 'suppliers') await loadList('supplier');
  if (D.tab === 'changes') D.ch = await call('w1a_open_adjust_list', { p_status: null, p_limit: 100 });
  if (D.tab === 'settings') { const r = await sb.from('rules').select('key,kind,value,default_value,choices,label_en,hint_en').in('key', RULE_KEYS); D.rules = ((r && r.data) || []).sort((a, b) => RULE_KEYS.indexOf(a.key) - RULE_KEYS.indexOf(b.key)); }
}
async function show(tab) {
  if (tab) D.tab = tab;
  try { D.err = null; await loadTab(); } catch (e) { D.err = missing(e) ? 'nofn' : /permission/i.test(e.message) ? 'denied' : e.message; }
  draw();
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

Object.assign(H, {
  op_tab: (a) => show(a.dataset.v),
  op_show: act(async () => { D.q = val('op_q'); D.only = val('op_only') || 'all'; await show(); }),
  op_more: act(async () => { await loadList(D.tab === 'suppliers' ? 'supplier' : 'customer', true); draw(); }),
  op_type: (a) => typeSheet(a.dataset.k, a.dataset.v),
  op_typego: act(async (a) => {
    const raw = val('ty_amt'); let amt = null;
    if (raw !== '') { amt = nnum(raw); if (!Number.isFinite(amt)) return toast(ERR.bad_amount); }
    await call('w1a_open_set', { p_kind: a.dataset.k, p_party: a.dataset.v, p_amount: amt, p_date: val('ty_date') || null, p_note: val('ty_note') || null });
    closeSheet(); toast('Saved'); await show();
  }),
  op_change: (a) => changeSheet(a.dataset.k, a.dataset.v),
  op_changego: act(async (a) => {
    const amt = nnum(val('ch_amt')); if (!Number.isFinite(amt)) return toast(ERR.bad_amount);
    if (val('ch_why').length < 3) return toast(ERR.reason_required);
    const r = await call('w1a_open_adjust', { p_kind: a.dataset.k, p_party: a.dataset.v, p_new: amt, p_reason: val('ch_why'), p_client: D.adj.client });
    D.adj.client = rid(); closeSheet(); toast(r && r.status === 'pending' ? 'Sent for approval' : 'Changed'); await show();
  }),
  op_imcheck: act(async () => {
    D.imp.kind = val('im_kind') || 'customer'; D.imp.text = ($('#im_text') || {}).value || ''; D.imp.create = !!($('#im_create') && $('#im_create').checked);
    const rows = parseRows(D.imp.text, D.imp.kind); if (!rows.length) return toast('Paste at least one line.');
    D.imp.dry = await call('w1a_open_import', { p_kind: D.imp.kind, p_rows: rows, p_dry: true, p_create: D.imp.create }); D.imp.hash = impHash(); draw();
  }),
  op_imgo: act(async () => {
    const I = D.imp; if (I.hash !== impHash()) return toast('Check again first.');
    const rows = parseRows(I.text, I.kind);
    const r = await call('w1a_open_import', { p_kind: I.kind, p_rows: rows, p_dry: false, p_create: I.create });
    toast('Imported ' + (Number(r.changed) + Number(r.created)) + ' row(s)'); D.imp.dry = null; D.imp.text = ''; D.imp.hash = ''; await show('import');
  }),
  op_json: act(async () => { D.json = await call('w1a_open_json', {}); draw(); }),
  op_precheck: act(async () => {
    let j; try { j = JSON.parse(val('pc_text')); } catch (e) { return toast('That is not valid JSON.'); }
    D.pre = await call('w1a_open_precheck', { p_json: j }); draw();
  }),
  op_decide: (a) => decideSheet(a.dataset.v, a.dataset.ok === '1'),
  op_decidego: act(async (a) => {
    const ok = a.dataset.ok === '1', note = val('dc_note'); if (!ok && note.length < 3) return toast(ERR.note_required);
    await call('w1a_open_adjust_decide', { p_id: Number(a.dataset.v), p_approve: ok, p_note: note || null }); closeSheet(); toast(ok ? 'Approved' : 'Rejected'); await show('changes');
  }),
  op_gate: act(async () => { D.gate = await call('w1a_party_gate', { p_kind: 'all' }); D.fill = null; draw(); }),
  op_fillcheck: act(async () => { D.fill = await call('w1a_open_from_journal', { p_dry: true }); draw(); }),
  op_fillgo: act(async () => { const r = await call('w1a_open_from_journal', { p_dry: false }); toast('Filled ' + r.filled + ' part(ies)'); D.fill = null; D.gate = await call('w1a_party_gate', { p_kind: 'all' }); D.st = await call('w1a_open_state', {}); draw(); }),
  op_rulesave: act(async (a) => {
    const key = a.dataset.v, r = (D.rules || []).find((x) => x.key === key); if (!r) return;
    const v = r.kind === 'switch' ? !!$('#rl_' + key).checked : val('rl_' + key);
    const res = await sb.rpc('set_rule', { p_key: key, p_value: v }); if (res.error) throw new Error(eText(res.error));
    toast('Saved'); await show('settings');
  }),
});
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'im_text') D.imp.text = e.target.value; });
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'im_kind') { D.imp.kind = e.target.value; D.imp.dry = null; D.imp.text = ($('#im_text') || {}).value || D.imp.text; draw(); } });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Opening dues and payables', '<div id="op_body"><p class="muted">…</p></div>', true);
  try { await show(D.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { openparties: view });
})();
