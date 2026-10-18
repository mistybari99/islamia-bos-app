/* Islamia BOS · Money controls (#/moneycontrols). One screen for the cash, payment, journal and mapping controls of phases 94 and 95:
   Settings (every policy choice is a setting the owner can change at any time; each change is written to the change log by the server),
   Requests (owner money, supplier payments over the limit and journals on control accounts that wait for the approver chosen under Money Accounts > Approvers),
   Exceptions (what the controls flagged, and the one-off exceptions the owner may allow with a reason), Checks (shared supplier identity or pay account) and Mapping types.
   Server: supabase/phase94.sql and phase95.sql (w1e_state, w1e_requests_list, w1e_request_decide / cancel / approver_set, w1e_exceptions_list, w1e_checks, w1e_mapping_types_list / set,
   money_exception_grant / resolve from phase 87, set_rule). Nothing is decided in the browser: a hidden button is also a refused request on the server.
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const dt = (s) => String(s || '').slice(0, 10);

const TABS = [['settings', 'Settings'], ['requests', 'Requests'], ['exceptions', 'Exceptions'], ['checks', 'Checks'], ['types', 'Mapping types']];
const GROUPS = [
  ['Owner money', ['owner_money_entry_mode']],
  ['Bank deposits and withdrawals', ['bank_slip_required', 'bank_move_large_over', 'bank_move_backdate_days']],
  ['Supplier payments', ['supplier_pay_dup_mode', 'supplier_pay_dup_hours', 'supplier_pay_over']],
  ['Suppliers and employees', ['supplier_dup_mode', 'employee_pay_dup_mode', 'employee_pay_change_flag']],
  ['Journals', ['journal_loc_check', 'journal_attach_over', 'journal_control_acct_mode', 'journal_control_prefixes']],
  ['Chart mapping', ['mapping_type_guard']],
  ['Purchases (existing setting)', ['purchase_separate_poster']],
];
const KEYS = GROUPS.reduce((a, g) => a.concat(g[1]), []);
const KIND = { owner_money: 'Owner money', supplier_pay: 'Supplier payment', journal_control: 'Journal on a control account' };
const EVENTS = [
  ['w1e_owner_money', 'Owner draw or top-up by someone who is not the owner'], ['w1e_bank_slip', 'Bank move without a slip number'], ['w1e_dup_payment', 'Repeat supplier payment'],
  ['w1e_pay_over', 'Supplier payment above the limit'], ['w1e_vendor_dup', 'Second supplier with the same name, mobile or TIN'], ['w1e_pay_account', 'Employee pay account used by another employee'],
  ['w1e_journal_loc', 'Journal line in a place the person may not use'], ['w1e_journal_attach', 'Journal above the total without an attachment'], ['w1e_journal_control', 'Journal on a control account (block mode)'],
  ['w1e_mapping', 'Mapping to an account type that is not listed'],
];
const KIND_LABEL = { w1e_bank_move_flag: 'Bank move flagged', w1e_duplicate_payment: 'Repeat supplier payment', w1e_pay_over_request: 'Supplier payment waits', w1e_vendor_duplicate: 'Duplicate supplier',
  w1e_pay_account_duplicate: 'Pay account shared', w1e_pay_account_changed: 'Pay account changed', w1e_owner_money_request: 'Owner money waits', w1e_journal_request: 'Journal waits',
  override_exception: 'One-off exception used', approver_exception: 'Approver exception used' };
const ERR = {
  not_allowed: 'You do not have permission.', owner_money_owner_only: 'Only the owner may record an owner draw or top-up. The owner can allow one exception.', bank_slip_required: 'Write the slip number in the reference.',
  duplicate_payment: 'This supplier was paid the same total just now. The owner can allow one exception.', vendor_duplicate: 'A supplier with the same name, mobile or TIN exists.', pay_account_duplicate: 'Another employee uses this pay account.',
  journal_place_not_allowed: 'A line is in a place you may not use.', attachment_required: 'Add the attachment: the total is above the limit.', control_account_blocked: 'A journal on a cash, bank, receivable, payable or inventory account is blocked.',
  mapping_type_mismatch: 'That account type does not fit this mapping.', self_approval: 'You made this request, so you cannot decide it.', approver_only: 'Only the approver chosen by the owner can decide this.',
  request_not_pending: 'This request was already decided.', note_required: 'Write a reason.', reason_required: 'Write a reason.', approver_is_maker: 'The maker cannot be the approver.', unknown_user: 'Unknown or inactive person.',
  bad_bad: 'Not valid.', overpaid: 'The payment is more than the supplier balance now.', period_closed: 'This period is closed.', bad_value: 'That value is not allowed for this setting.', bad_key: 'Not valid.',
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const D = { tab: 'settings', st: null, rules: [], rq: null, rqAll: false, ex: null, ck: null, ty: null, people: [], roles: [] };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const who = (id) => { const p = D.people.find((x) => x.id === id); return p ? (p.full_name || p.staff_id) : String(id || '').slice(0, 8); };
const cur = (r) => (r.value !== null && r.value !== undefined ? r.value : r.default_value);

// ---------------- tabs ----------------
function tabsBar() { return `<div class="row wrap" id="mc_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="mc_tab" data-v="${k}">${esc(l)}${k === 'requests' && D.st && D.st.pending ? ' (' + D.st.pending + ')' : ''}</button>`).join('')}</div>`; }

function ruleCtl(r) {
  const v = cur(r), id = 'mc_r_' + r.key, ro = isOwner() ? '' : 'disabled';
  let ctl;
  if (r.kind === 'switch') ctl = `<select id="${id}" ${ro}><option value="false" ${v === true ? '' : 'selected'}>Off</option><option value="true" ${v === true ? 'selected' : ''}>On</option></select>`;
  else if (r.kind === 'choice') ctl = `<select id="${id}" ${ro}>${(r.choices || []).map((c) => `<option value="${esc(c)}" ${c === v ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>`;
  else if (r.kind === 'number') ctl = `<div class="row" style="gap:.4rem">${inp(id, r.value === null || r.value === undefined ? '' : r.value, `inputmode="decimal" placeholder="blank = off" ${ro}`)}${r.unit ? `<span class="muted">${esc(r.unit)}</span>` : ''}</div>`;
  else ctl = inp(id, v === null || v === undefined ? '' : v, `maxlength="120" ${ro}`);
  const d = r.default_value === null || r.default_value === undefined ? 'blank (off)' : String(r.default_value);
  return `<div class="card stack mc-rule" data-key="${esc(r.key)}"><b>${esc(r.label_en)}</b><div class="muted" style="font-size:.85rem">${esc(r.hint_en || '')}</div>
    <div class="row between wrap">${ctl}${isOwner() ? `<button type="button" class="mini" data-act="mc_save" data-v="${esc(r.key)}">Save</button>` : ''}</div>
    <div class="muted" style="font-size:.8rem">Default (today): ${esc(d)}</div></div>`;
}
function settingsHTML() {
  const st = D.st || {}, h = st.hooks || {}, ap = st.approver || {};
  const hook = (ok, name) => (ok ? chip(name + ': ready', 'ok') : chip(name + ': waiting for the hook of docs/integration/W1-E.md', 'warn'));
  const head = `<div class="card stack" id="mc_head"><b>Approver</b><div>Owner's own entries and the requests below are decided by: mode <b>${esc(ap.mode || 'self')}</b>${ap.role ? ' · role <b>' + esc(ap.role) + '</b>' : ''}${(ap.users || []).length ? ' · ' + ap.users.map((u) => esc(who(u))).join(', ') : ''}.
      <a href="#/moneyaccounts" data-act="mc_goapprovers">Change under Money Accounts &gt; Approvers</a>.</div>
    <div class="row wrap">${hook(h.pay_supplier, 'Supplier payment guard')}${hook(h.cash_move_add, 'Cash move answer')}${hook(h.acct_journal_post, 'Journal gate')}</div>
    ${isOwner() ? '' : '<div class="muted">Only the owner can change a setting.</div>'}</div>`;
  const body = GROUPS.map(([title, keys]) => {
    const rows = keys.map((k) => D.rules.find((r) => r.key === k)).filter(Boolean);
    return rows.length ? `<h3>${esc(title)}</h3>${rows.map(ruleCtl).join('')}` : '';
  }).join('');
  return head + body;
}

function requestsHTML() {
  const rows = ((D.rq || {}).rows || []);
  const filt = `<div class="row wrap"><button type="button" class="tog ${D.rqAll ? '' : 'on'}" data-act="mc_rqf" data-v="pending">Waiting</button><button type="button" class="tog ${D.rqAll ? 'on' : ''}" data-act="mc_rqf" data-v="all">All</button></div>`;
  const cards = rows.map((q) => `<div class="card stack mc-req" data-id="${q.id}" data-status="${esc(q.status)}"><div class="row between"><b>${esc(KIND[q.kind] || q.kind)}</b><b>${fm(q.amount)}</b></div>
      <div>${esc(q.summary)}</div><div class="muted">${esc(dt(q.ref_date))} · asked by ${esc(q.requested_staff || who(q.requested_by))} · ${esc(dt(q.requested_at))}${q.approver_user || q.approver_role ? ' · approver: ' + esc(q.approver_role || who(q.approver_user)) : ''}</div>
      <div class="row wrap">${chip(q.status, q.status === 'pending' ? 'warn' : q.status === 'approved' ? 'ok' : '')}${q.decision_note ? `<span class="muted">${esc(q.decision_note)}</span>` : ''}</div>
      ${q.can_decide ? `<div class="row wrap"><button type="button" class="btn primary" data-act="mc_approve" data-v="${q.id}">Approve</button><button type="button" class="btn" data-act="mc_reject" data-v="${q.id}">Reject</button></div>` : ''}
      ${q.status === 'pending' && !q.can_decide && q.mine ? '<div class="muted">You asked for this. The approver decides it; you cannot decide your own request.</div>' : ''}
      ${q.status === 'pending' && (q.can_cancel || isOwner()) ? `<div class="row wrap"><button type="button" class="mini" data-act="mc_cancel" data-v="${q.id}">⋮ Cancel</button>${isOwner() ? `<button type="button" class="mini" data-act="mc_setap" data-v="${q.id}">⋮ Set approver for this one</button>` : ''}</div>` : ''}</div>`).join('');
  return filt + (cards || '<p class="muted">Nothing here.</p>');
}

function exceptionsHTML() {
  const ex = D.ex || { rows: [], grants: [] };
  const rows = ex.rows.map((x) => `<div class="card stack mc-ex" data-level="${esc(x.level)}"><div class="row between"><b>${esc(KIND_LABEL[x.kind] || x.kind)}</b>${chip(x.level === 'red' ? 'Red' : 'Yellow', x.level === 'red' ? 'bad' : 'warn')}</div>
      <div>${esc(x.reason || '')}</div><div class="muted">${esc(dt(x.at))}${x.amount !== null && x.amount !== undefined ? ' · ' + fm(x.amount) : ''} · ${esc(x.event_type || '')}</div>
      ${x.status === 'open' ? `<div class="row"><button type="button" class="mini" data-act="mc_exres" data-v="${x.id}">Mark as looked at</button></div>` : `<div class="muted">Looked at: ${esc(x.resolve_note || '')}</div>`}</div>`).join('');
  const grant = isOwner() ? `<div class="card stack" id="mc_grant"><b>Allow one exception</b><div class="muted">For one person (24 hours, used once). A reason is required. It is written to the change log and shown in this list. A journal that does not balance is never excepted.</div>
      ${fld('gx_ev', 'What', `<select id="gx_ev">${EVENTS.map(([k, l]) => `<option value="${k}">${esc(l)}</option>`).join('')}</select>`)}
      ${fld('gx_rule', 'Kind', '<select id="gx_rule"><option value="override">Let the entry through</option><option value="approver">Let me decide a request (approver exception)</option></select>')}
      ${fld('gx_user', 'For this person', `<select id="gx_user"><option value="">—</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id || p.id)}</option>`).join('')}</select>`)}
      ${fld('gx_reason', 'Reason', inp('gx_reason', '', 'maxlength="200"'))}<button type="button" class="btn primary" data-act="mc_grant">Allow once</button></div>` : '';
  const used = (ex.grants || []).length ? `<h3>Exceptions allowed</h3>${ex.grants.map((g) => `<div class="card"><b>${esc(g.event_type || 'any')}</b> · ${esc(g.rule)} · ${esc(who(g.for_user))}<div class="muted">${esc(g.reason)} · ${g.used_at ? 'used' : g.revoked ? 'revoked' : 'open until ' + esc(dt(g.expires_at))}</div></div>`).join('')}` : '';
  return grant + `<h3>Flags and exceptions</h3>` + (rows || '<p class="muted">Nothing flagged.</p>') + used;
}

function checksHTML() {
  const c = D.ck || { vendors: [], pay_accounts: [] };
  const v = c.vendors.map((x) => `<div class="card mc-vd"><b>${esc(x.a_name)}</b> and <b>${esc(x.b_name)}</b><div class="muted">same ${esc(x.by)}</div></div>`).join('');
  const p = c.pay_accounts.map((x) => `<div class="card mc-pa"><b>${esc(x.a_no)}</b> and <b>${esc(x.b_no)}</b><div class="muted">same ${esc(x.by)} · ${esc(x.account)}</div></div>`).join('');
  return `<h3>Suppliers that look the same</h3>${v || '<p class="muted">None.</p>'}<h3>Employees on one pay account</h3>${p || '<p class="muted">None. Account numbers are shown with the last 4 characters only.</p>'}`;
}

function typesHTML() {
  const rows = (D.ty || []).map((t, i) => `<div class="card stack mc-ty ${t.active ? '' : 'muted'}" data-k="${esc(t.key_like)}"><div class="row between"><b>${esc(t.key_like.replace(/\\/g, ''))}</b>${t.active ? '' : chip('Switched off')}</div>
      <div class="muted">${esc(t.note || '')}</div>
      <div class="row wrap">${inp('mt_' + i, (t.allowed || []).join(', '), `${isOwner() ? '' : 'disabled'} aria-label="allowed account types"`)}${isOwner() ? `<button type="button" class="mini" data-act="mc_tysave" data-v="${i}">Save</button><button type="button" class="mini" data-act="mc_tytog" data-v="${i}">⋮ ${t.active ? 'Switch off' : 'Switch on'}</button>` : ''}</div></div>`).join('');
  return `<div class="muted">A mapping key (for example sales) may only point to the account types listed here, when the setting "Check the account type when a mapping is changed" is on. Types: asset, liability, equity, income, expense. Rows are switched off, never deleted.</div>${rows}`;
}

function draw() {
  const el = $('#mc_body'); if (!el) return;
  el.innerHTML = tabsBar() + ({ settings: settingsHTML, requests: requestsHTML, exceptions: exceptionsHTML, checks: checksHTML, types: typesHTML }[D.tab] || settingsHTML)();
}
async function loadTab() {
  if (!D.people.length) { try { const p = await sb.from('profiles').select('id,full_name,staff_id,status').eq('status', 'active').order('full_name'); D.people = p.data || []; } catch (e) { D.people = []; } }
  D.st = await call('w1e_state', {});
  if (D.tab === 'settings') { const r = await sb.from('rules').select('key,kind,value,default_value,choices,unit,label_en,hint_en,min_value,max_value').in('key', KEYS); D.rules = r.data || []; }
  if (D.tab === 'requests') D.rq = await call('w1e_requests_list', { p_status: D.rqAll ? null : 'pending', p_limit: 200 });
  if (D.tab === 'exceptions') D.ex = await call('w1e_exceptions_list', { p_status: null, p_limit: 200 });
  if (D.tab === 'checks') D.ck = await call('w1e_checks', {});
  if (D.tab === 'types') D.ty = await call('w1e_mapping_types_list', {});
}
async function show(tab) { if (tab) D.tab = tab; try { await loadTab(); draw(); } catch (e) { toast(e.message); draw(); } }
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const ask = (q) => { const n = window.prompt(q); return n && n.trim().length >= 3 ? n.trim() : null; };

Object.assign(H, {
  mc_tab: (a) => show(a.dataset.v),
  mc_goapprovers: () => {},
  mc_save: act(async (a) => {
    const k = a.dataset.v, r = D.rules.find((x) => x.key === k); if (!r) return;
    const raw = val('mc_r_' + k); let v;
    if (r.kind === 'switch') v = raw === 'true';
    else if (r.kind === 'number') { if (norm(raw) === '') v = null; else { v = Number(norm(raw)); if (!Number.isFinite(v)) return toast(ERR.bad_value); } }
    else v = raw === '' ? null : raw;
    await call('set_rule', { p_key: k, p_value: v });
    toast('Saved'); await show('settings');
  }),
  mc_rqf: (a) => { D.rqAll = a.dataset.v === 'all'; return show('requests'); },
  mc_approve: act(async (a) => { await call('w1e_request_decide', { p_id: Number(a.dataset.v), p_approve: true, p_note: null }); toast('Approved'); await show('requests'); }),
  mc_reject: act(async (a) => { const n = ask('Why is this rejected?'); if (!n) return; await call('w1e_request_decide', { p_id: Number(a.dataset.v), p_approve: false, p_note: n }); toast('Rejected'); await show('requests'); }),
  mc_cancel: act(async (a) => { const n = ask('Why is this cancelled?'); if (!n) return; await call('w1e_request_cancel', { p_id: Number(a.dataset.v), p_note: n }); toast('Cancelled'); await show('requests'); }),
  mc_setap: (a) => {
    const id = a.dataset.v;
    openSheet(`<h3>Approver for this request</h3><div class="stack">${fld('sa_user', 'Person', `<select id="sa_user"><option value="">—</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id || p.id)}</option>`).join('')}</select>`)}
      ${fld('sa_role', 'or role', `<input id="sa_role" autocomplete="off" maxlength="40" placeholder="role code">`)}${fld('sa_why', 'Reason', inp('sa_why', '', 'maxlength="200"'))}
      <button type="button" class="btn primary" data-act="mc_setapgo" data-v="${esc(id)}">Save</button></div>`);
  },
  mc_setapgo: act(async (a) => {
    if (val('sa_why').length < 3) return toast(ERR.reason_required);
    await call('w1e_request_approver_set', { p_id: Number(a.dataset.v), p_user: val('sa_user') || null, p_role: val('sa_role') || null, p_reason: val('sa_why') });
    closeSheet(); toast('Saved'); await show('requests');
  }),
  mc_exres: act(async (a) => { const n = ask('Note: what did you check?'); if (!n) return; await call('money_exception_resolve', { p_id: Number(a.dataset.v), p_note: n }); await show('exceptions'); }),
  mc_grant: act(async () => {
    if (val('gx_reason').length < 3) return toast(ERR.reason_required);
    if (!val('gx_user')) return toast('Choose the person.');
    const ev = val('gx_ev');
    await call('money_exception_grant', { p_rule: val('gx_rule'), p_reason: val('gx_reason'), p_for_user: val('gx_user'), p_client: null, p_event: ev, p_account: null, p_max: null, p_date: null, p_hours: 24 });
    toast('Saved'); await show('exceptions');
  }),
  mc_tysave: act(async (a) => {
    const i = Number(a.dataset.v), t = (D.ty || [])[i]; if (!t) return; const k = t.key_like;
    const list = val('mt_' + i).split(',').map((s) => s.trim().toLowerCase()).filter(Boolean); if (!list.length) return toast(ERR.bad_value);
    const n = ask('Why is this list changed?'); if (!n) return;
    await call('w1e_mapping_type_set', { p_key_like: k, p_allowed: list, p_active: t.active, p_reason: n }); toast('Saved'); await show('types');
  }),
  mc_tytog: act(async (a) => {
    const t = (D.ty || [])[Number(a.dataset.v)]; if (!t) return; const k = t.key_like;
    const n = ask(t.active ? 'Why is this row switched off?' : 'Why is this row switched on?'); if (!n) return;
    await call('w1e_mapping_type_set', { p_key_like: k, p_allowed: t.allowed, p_active: !t.active, p_reason: n }); toast('Saved'); await show('types');
  }),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Money controls', '<div id="mc_body"><p class="muted">…</p></div>', true);
  try { D.st = null; await show(D.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { moneycontrols: view });
})();
