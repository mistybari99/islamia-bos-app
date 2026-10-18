/* Islamia BOS · Return & exit rules (#/returnrules). One owner screen for two controls (package W1-C):
   1. Sale return control: for every item class the owner chooses whether returned goods go back on the shelf or are written off at once, the return window in hours,
      whether the receipt number is needed; global switches (receipt, window, expired batch); the report "returns by reason: restocked or written off" and the overrides.
   2. Staff exit: which statuses switch a login off, what happens (off / alert only / disable), the alert delay, device tokens, the people who left and still can log in,
      keeping one person's access with a reason, and the log.
   Server: supabase/phase90.sql (_w1c_exit_*), supabase/phase91.sql (_w1c_return_*, _w1c_sale_return). The server is the authority: a hidden button is also a refused request.
   The return picker for salereturn.js (BOS.returnRules.pickerHTML / collect / preview / saleReturn) is wired in by the integrator; this file only exports it.
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chk = (id) => !!(($('#' + id) || {}).checked);
const ERR = {
  not_allowed: 'You do not have permission for this.', reason_required: 'Write a reason (at least 3 letters).', bad_mode: 'Choose one of the modes.', bad_statuses: 'Choose at least one status.',
  bad_hours: 'Hours must be a number from 0 to 8760, or empty.', bad_window: 'The window must be a number of hours above zero, or empty.', unknown_class: 'No item has this class.',
  bad_restock: 'Choose put back on the shelf or write off.', bad_class: 'The class is not valid.', no_linked_login: 'This person has no linked login.', not_kept: 'Access is not being kept for this person.',
  not_found: 'Not found.', bad_value: 'The value is not allowed.', too_long: 'The text is too long.',
  return_window_exceeded: 'The return window has passed. A manager with the override right can accept it with a reason.',
  return_receipt_required: 'The receipt number is required and does not match this sale.',
  return_restock_not_allowed: 'This class is never put back on the shelf. A manager with the override right can accept it with a reason.',
  return_expired_restock: 'Goods from an expired batch cannot go back on the shelf. Write them off, or ask a manager to override with a reason.',
  return_override_not_allowed: 'You do not hold the right to override the return rules.', return_bad_restock_qty: 'The quantity to put back is not valid.',
  return_written_off: 'Goods of this return were written off, so it cannot be voided. Fix it with a stock adjustment.',
};
const codeOf = (m) => (m.includes('not allowed') ? 'not_allowed' : Object.keys(ERR).find((x) => m.includes(x)) || '');
const eText = (e) => { const m = String((e && e.message) || ''); const k = codeOf(m); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; e.code = codeOf(String((r.error && r.error.message) || '')); throw e; }
  return r.data;
}
const TABS = [['returns', 'Return rules'], ['exit', 'Staff exit'], ['report', 'Returns report']];
const STATUS_L = { resigned: 'Resigned', terminated: 'Terminated', retired: 'Retired', on_leave: 'On leave (not recommended)', active: 'Active', draft: 'Draft' };
const MODE_L = { off: 'Off: nothing is touched (today)', alert: 'Alert only: a red line in Exceptions', auto: 'Automatic: the login is disabled and the grants end' };
const EXP_L = { allow: 'Allow: back on the shelf (today)', writeoff: 'Write off automatically', block: 'Refuse unless a manager overrides' };
const ACT_L = { revoked: 'Login disabled', alert_only: 'Alert raised', kept: 'Access kept', keep_ended: 'Keep ended', reenabled: 'Login enabled again', skipped_owner: 'Owner login not touched',
  skipped_self: 'Own login not touched', no_linked_login: 'No linked login', already_disabled: 'Already disabled', scan_alert: 'Found by the check' };
const D = { tab: 'returns', st: null, notOwner: false, edit: null, off: null, ex: null, open: [], log: [], keep: null, rep: null, from: '', to: today() };

const optHTML = (pairs, sel) => pairs.map(([v, l]) => `<option value="${esc(String(v))}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const tabsHTML = () => `<div class="ptabs" role="tablist">${TABS.map(([k, l]) => `<button role="tab" data-act="rr_tab" data-v="${k}" aria-selected="${D.tab === k}">${esc(l)}</button>`).join('')}</div>`;
const noOwnerHTML = (what) => `<div class="card muted">${esc(what)}</div>`;

/* ---------- tab 1: return rules ---------- */
function ruleSummary(c) {
  if (!c.configured) return 'No rule: goods go back on the shelf, any age, no receipt (today).';
  const parts = [c.restock === 'no_restock' ? 'Never put back on the shelf: written off at once' : 'Put back on the shelf'];
  parts.push(c.window_hours ? 'window ' + c.window_hours + ' hours' : 'no own window');
  parts.push(c.receipt_required === true ? 'receipt needed' : c.receipt_required === false ? 'receipt not needed' : 'receipt follows the general switch');
  if (c.effective_from && c.effective_from > today()) parts.push('starts ' + c.effective_from);
  return parts.join(' · ');
}
function classEdit(c) {
  const e = D.edit; if (!e || e.cls !== c.class_code) return '';
  return `<div class="stack rr-panel" data-panel="${esc(c.class_code)}">
    <div><label for="rr_restock">When goods come back</label><select id="rr_restock">${optHTML([['restock', 'Put back on the shelf'], ['no_restock', 'Never put back: write off at once']], e.restock)}</select></div>
    <div><label for="rr_cwin">Return window in hours (empty = no own window)</label><input id="rr_cwin" inputmode="decimal" autocomplete="off" value="${esc(e.window)}"></div>
    <div><label for="rr_crec">Receipt number</label><select id="rr_crec">${optHTML([['', 'Follow the general switch'], ['yes', 'Needed'], ['no', 'Not needed']], e.receipt)}</select></div>
    <div><label for="rr_ceff">Applies from</label><input id="rr_ceff" type="date" value="${esc(e.eff)}"></div>
    <div><label for="rr_cnote">Note (optional)</label><input id="rr_cnote" autocomplete="off" value="${esc(e.note)}"></div>
    <div class="row"><button class="full" data-act="rr_cancel">Cancel</button><button class="full primary" data-act="rr_csave">Save</button></div></div>`;
}
function classOff(c) {
  const o = D.off; if (!o || o !== c.class_code) return '';
  return `<div class="stack rr-panel" data-panel-off="${esc(c.class_code)}"><div><label for="rr_offreason">Why is this rule switched off (at least 3 letters)</label><input id="rr_offreason" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="rr_cancel">Cancel</button><button class="full primary" data-act="rr_coffgo">Switch off</button></div></div>`;
}
function returnsHTML() {
  if (D.notOwner) return noOwnerHTML('Only the owner can change the return rules.');
  const s = D.st; if (!s) return '<p class="muted">…</p>';
  const glob = `<div class="card stack" id="rr_global"><b>General rules</b>
    <label class="row"><input type="checkbox" id="rr_receipt" ${s.needs_receipt ? 'checked' : ''}> A return must show the receipt number</label>
    <div><label for="rr_window">Return window in hours (empty = no limit)</label><input id="rr_window" inputmode="decimal" autocomplete="off" value="${esc(s.window_hours ?? '')}"></div>
    <div><label for="rr_exp">Returned goods that come from an expired batch</label><select id="rr_exp">${optHTML(Object.entries(EXP_L), s.expired_mode)}</select></div>
    <div class="muted">With everything off or empty, returns work exactly as before. Past a rule, a manager who holds the override right can still accept a return, with a reason; it is written to the audit log and the Exceptions list.</div>
    <button class="primary" data-act="rr_gsave">Save general rules</button></div>`;
  const cls = (s.classes || []).map((c) => {
    const sug = !c.configured && c.perishable ? `<button class="mini" data-act="rr_suggest" data-c="${esc(c.class_code)}">Looks perishable: suggest never put back</button>` : '';
    return `<div class="card" data-class="${esc(c.class_code)}"><div class="row between"><b>${esc(c.class_code)}</b><span class="muted">${esc(c.items)} items${c.perishable ? ' · perishable' : ''}</span></div>
      <div class="muted">${esc(c.sample_en || c.sample_bn || '')}</div><div data-sum>${esc(ruleSummary(c))}</div>
      <div class="row"><button class="primary" data-act="rr_edit" data-c="${esc(c.class_code)}">${c.configured ? 'Edit' : 'Set a rule'}</button>${c.configured ? `<button data-act="rr_off" data-c="${esc(c.class_code)}">Switch off</button>` : ''}${sug}</div>
      ${classEdit(c)}${classOff(c)}</div>`;
  }).join('');
  return glob + `<h3>Item classes</h3>` + (cls || '<p class="muted">No item classes yet.</p>');
}
async function saveGlobal() {
  const w = val('rr_window'); const win = w === '' ? null : nnum(w);
  if (w !== '' && !(win >= 1)) return toast(ERR.bad_window);
  D.st = await call('_w1c_return_global_set', { p_needs_receipt: chk('rr_receipt'), p_window: win, p_expired: val('rr_exp') });
  toast('Saved'); render();
}
async function saveClass() {
  const e = D.edit; if (!e) return;
  const w = val('rr_cwin'); const win = w === '' ? null : nnum(w);
  if (w !== '' && !(win > 0)) return toast(ERR.bad_window);
  const rec = val('rr_crec');
  await call('_w1c_return_class_set', { p_class: e.cls, p_restock: val('rr_restock'), p_window: win, p_receipt: rec === 'yes' ? true : rec === 'no' ? false : null, p_effective: val('rr_ceff') || null, p_note: val('rr_cnote') || null });
  D.edit = null; await loadReturns(); toast('Saved'); render();
}
async function loadReturns() {
  try { D.st = await call('_w1c_return_settings'); D.notOwner = false; } catch (e) { if (/permission/.test(e.message) || e.code === 'not_allowed') { D.notOwner = true; D.st = null; } else throw e; }
}

/* ---------- tab 2: staff exit ---------- */
const nm = (x) => (x.employee_no ? x.employee_no + ' · ' : '') + (x.name_en || x.name_bn || '');
function exitHTML() {
  const s = D.ex; if (!s) return noOwnerHTML('You do not have permission to see the staff exit rules.');
  const sts = new Set(s.statuses || []);
  const own = s.is_owner;
  const form = `<div class="card stack" id="ex_form"><b>When a person leaves</b>
    <div><label for="ex_mode">What happens to the login</label><select id="ex_mode" ${own ? '' : 'disabled'}>${optHTML(Object.entries(MODE_L), s.mode)}</select></div>
    <div><b>Statuses that count as leaving</b>${(s.allowed_statuses || []).map((k) => `<label class="row"><input type="checkbox" class="ex_st" value="${esc(k)}" ${sts.has(k) ? 'checked' : ''} ${own ? '' : 'disabled'}> ${esc(STATUS_L[k] || k)}</label>`).join('')}</div>
    <div><label for="ex_hours">Flag a login that is still active after this many hours (empty = off)</label><input id="ex_hours" inputmode="decimal" autocomplete="off" value="${esc(s.alert_hours ?? '')}" ${own ? '' : 'disabled'}></div>
    <label class="row"><input type="checkbox" id="ex_dev" ${s.devices ? 'checked' : ''} ${own ? '' : 'disabled'}> Also switch off attendance device tokens that this person registered</label>
    <div class="muted">A re-hire enables the login again; grants and device tokens are not restored. A login with the owner role is never switched off by this rule.</div>
    ${own ? '<button class="primary" data-act="ex_save">Save</button>' : '<div class="muted">Only the owner can change these settings.</div>'}</div>`;
  const rows = (D.open || []).map((x) => `<div class="card" data-emp="${esc(x.employee_id)}"><div class="row between"><b>${esc(nm(x))}</b><span class="muted">${esc(STATUS_L[x.status] || x.status)} ${esc(x.status_date || '')}</span></div>
    <div class="muted">${esc(x.staff_id || '')} · login ${esc(x.login_status)}${x.kept ? ' · access kept: ' + esc(x.kept_reason || '') : ''}</div>
    ${s.can_keep ? (x.kept ? `<button data-act="ex_keepopen" data-id="${esc(x.employee_id)}" data-k="end">End the keep</button>` : `<button data-act="ex_keepopen" data-id="${esc(x.employee_id)}" data-k="keep">Keep access (reason needed)</button>`) : ''}
    ${D.keep && D.keep.id === x.employee_id ? `<div class="stack rr-panel"><div><label for="ex_reason">Reason (at least 3 letters)</label><input id="ex_reason" autocomplete="off"></div>
      <div class="row"><button class="full" data-act="rr_cancel">Cancel</button><button class="full primary" data-act="ex_keepgo">${D.keep.k === 'end' ? 'End the keep' : 'Keep access'}</button></div></div>` : ''}</div>`).join('');
  const open = `<h3>Left but can still log in</h3>${rows || '<p class="muted">Nobody.</p>'}<button data-act="ex_scan">Check now and raise the red lines</button>`;
  const log = `<h3>Log</h3>` + ((D.log || []).map((l) => `<div class="card"><div class="row between"><b>${esc(ACT_L[l.action] || l.action)}</b><span class="muted">${esc(String(l.at || '').slice(0, 16).replace('T', ' '))}</span></div>
    <div class="muted">${esc(nm(l))} · ${esc(l.from || '')} → ${esc(l.to || '')}${l.grants_ended ? ' · grants ended ' + esc(l.grants_ended) : ''}${l.devices_off ? ' · tokens off ' + esc(l.devices_off) : ''}${l.reason ? ' · ' + esc(l.reason) : ''}</div></div>`).join('') || '<p class="muted">Nothing yet.</p>');
  return form + open + log;
}
async function loadExit() {
  try { D.ex = await call('_w1c_exit_settings'); D.open = await call('_w1c_exit_open_list'); D.log = await call('_w1c_exit_log_list', { p_limit: 60 }); }
  catch (e) { if (/permission/.test(e.message) || e.code === 'not_allowed') { D.ex = null; D.open = []; D.log = []; } else throw e; }
}
async function saveExit() {
  const h = val('ex_hours'); const hrs = h === '' ? null : nnum(h);
  if (h !== '' && !(hrs >= 0 && hrs <= 8760)) return toast(ERR.bad_hours);
  const sts = Array.from(document.querySelectorAll('.ex_st')).filter((x) => x.checked).map((x) => x.value);
  if (!sts.length) return toast(ERR.bad_statuses);
  D.ex = await call('_w1c_exit_settings_set', { p_mode: val('ex_mode'), p_statuses: sts.join(','), p_alert_hours: hrs, p_devices: chk('ex_dev'), p_note: null });
  toast('Saved'); await loadExit(); render();
}

/* ---------- tab 3: report ---------- */
function reportHTML() {
  const r = D.rep;
  const f = `<div class="card stack"><div class="row"><div><label for="rp_from">From</label><input id="rp_from" type="date" value="${esc(D.from)}"></div><div><label for="rp_to">To</label><input id="rp_to" type="date" value="${esc(D.to)}"></div></div>
    <button class="primary" data-act="rp_go">Show</button></div>`;
  if (!r) return f;
  const rows = (r.by_reason || []).map((x) => `<tr><td>${esc(x.reason)}</td><td>${esc(x.class || '-')}</td><td>${esc(x.returns)}</td><td>${esc(x.restocked_qty)}</td><td>${esc(x.written_off_qty)}</td><td>${esc(x.written_off_value)}</td></tr>`).join('');
  const ov = (r.overrides || []).map((x) => `<div class="card"><b>${esc((x.kinds || []).join(', '))}</b><div class="muted">${esc(String(x.at || '').slice(0, 16).replace('T', ' '))} · ${esc(x.reason || '')}</div></div>`).join('');
  return f + `<h3>Returns by reason: restocked or written off</h3>
    ${rows ? `<div class="tablewrap"><table class="tbl"><thead><tr><th>Reason</th><th>Class</th><th>Returns</th><th>Put back</th><th>Written off</th><th>Value</th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p class="muted">No returns in this period.</p>'}
    ${r.not_covered ? `<div class="card muted">${esc(r.not_covered)} returns in this period were saved without the return rules (before they were switched on, or by an old screen). They are not in the table.</div>` : ''}
    <h3>Overrides</h3>${ov || '<p class="muted">None.</p>'}`;
}
async function loadReport() {
  if (!D.from) { const d = new Date(Date.now() + 6 * 3600e3 - 30 * 864e5); D.from = d.toISOString().slice(0, 10); }
  D.rep = await call('_w1c_return_report', { p_from: D.from, p_to: D.to, p_loc: null });
}

/* ---------- shell ---------- */
function body() { return tabsHTML() + (D.tab === 'returns' ? returnsHTML() : D.tab === 'exit' ? exitHTML() : reportHTML()); }
function render() { const el = $('#rr_body'); if (el) el.innerHTML = body(); }
async function loadTab() {
  if (D.tab === 'returns') await loadReturns(); else if (D.tab === 'exit') await loadExit(); else if (D.rep === null) { try { await loadReport(); } catch (e) { D.rep = null; throw e; } }
  render();
}
const guard = (fn) => (a) => { fn(a).catch((e) => { if (e && e.raw !== undefined) toast(e.message); else fail(e); }); };
Object.assign(H, {
  rr_tab: guard(async (a) => { D.tab = a.dataset.v; D.edit = null; D.off = null; D.keep = null; await loadTab(); }),
  rr_gsave: guard(async () => { await saveGlobal(); }),
  rr_edit: (a) => {
    const c = (D.st.classes || []).find((x) => x.class_code === a.dataset.c) || {};
    D.off = null; D.edit = { cls: c.class_code, restock: c.configured ? c.restock : 'restock', window: c.window_hours ?? '', receipt: c.receipt_required === true ? 'yes' : c.receipt_required === false ? 'no' : '', eff: c.effective_from && c.configured ? c.effective_from : today(), note: c.note || '' };
    render();
  },
  rr_suggest: (a) => { H.rr_edit(a); D.edit.restock = 'no_restock'; D.edit.note = 'perishable: never put back on the shelf'; render(); },
  rr_cancel: () => { D.edit = null; D.off = null; D.keep = null; render(); },
  rr_csave: guard(async () => { await saveClass(); }),
  rr_off: (a) => { D.edit = null; D.off = a.dataset.c; render(); },
  rr_coffgo: guard(async () => {
    const r = val('rr_offreason'); if (r.length < 3) return toast(ERR.reason_required);
    await call('_w1c_return_class_off', { p_class: D.off, p_reason: r }); D.off = null; await loadReturns(); toast('Switched off'); render();
  }),
  ex_save: guard(async () => { await saveExit(); }),
  ex_scan: guard(async () => { const r = await call('_w1c_exit_scan'); toast(r && r.skipped ? 'Set the hours first (the check is off)' : (r.raised || 0) + ' new red lines'); await loadExit(); render(); }),
  ex_keepopen: (a) => { D.keep = { id: a.dataset.id, k: a.dataset.k }; render(); },
  ex_keepgo: guard(async () => {
    const r = val('ex_reason'); if (r.length < 3) return toast(ERR.reason_required);
    const k = D.keep; await call(k.k === 'end' ? '_w1c_exit_keep_end' : '_w1c_exit_keep', { p_employee: k.id, p_reason: r });
    D.keep = null; await loadExit(); toast('Saved'); render();
  }),
  rp_go: guard(async () => { D.from = val('rp_from') || D.from; D.to = val('rp_to') || D.to; await loadReport(); render(); }),
});

/* ---------- the picker for salereturn.js (the integrator wires it in) ---------- */
const RR = {
  preview: (sale, lines, restock, receipt) => call('_w1c_return_preview', { p_sale: sale, p_lines: lines, p_restock: restock || null, p_receipt: receipt || null }),
  saleReturn: (a) => call('_w1c_sale_return', a),
  /* pv = result of preview(); names = {item_id: label}. One row per item: put back / write off, the receipt field and the override reason when the rules say so. */
  pickerHTML(pv, names) {
    const rows = (pv.lines || []).map((l) => `<div class="card" data-rr-item="${esc(l.item_id)}"><b>${esc((names && names[l.item_id]) || l.item_id)}</b> <span class="muted">${esc(l.qty)} · class ${esc(l.class)}</span>
      <label for="rrp_${esc(l.item_id)}">Goods to put back on the shelf (rest is written off)</label><input id="rrp_${esc(l.item_id)}" data-rr-qty inputmode="decimal" autocomplete="off" value="${esc(l.restock_qty)}">
      ${l.restock_rule === 'no_restock' ? '<div class="muted">This class is not put back on the shelf.</div>' : ''}</div>`).join('');
    const need = (pv.lines || []).some((l) => l.receipt_needed);
    const viol = (pv.violations || []);
    return rows + (need ? `<div><label for="rrp_receipt">Receipt number</label><input id="rrp_receipt" autocomplete="off"></div>` : '')
      + (viol.length ? `<div class="notice">${viol.map((v) => `<div>${esc(ERR[v] || v)}</div>`).join('')}${pv.can_override ? '<label for="rrp_override">Override reason (manager)</label><input id="rrp_override" autocomplete="off">' : '<div class="muted">Ask a manager who holds the override right.</div>'}</div>` : '');
  },
  collect(root) {
    const r = root || document;
    const restock = Array.from(r.querySelectorAll('[data-rr-item]')).map((el) => ({ item_id: el.getAttribute('data-rr-item'), restock_qty: nnum(($('[data-rr-qty]', el) || {}).value) })).filter((x) => Number.isFinite(x.restock_qty));
    return { p_restock_lines: restock.length ? restock : null, p_receipt_no: (($('#rrp_receipt', r) || {}).value || '').trim() || null, p_override_reason: (($('#rrp_override', r) || {}).value || '').trim() || null };
  },
  errorText: eText,
};
B.returnRules = RR;

async function view() {
  if (B.loadStatic) await B.loadStatic();
  D.tab = 'returns'; D.edit = null; D.off = null; D.keep = null; D.rep = null;
  shell('Return & exit rules', '<div id="rr_body"><p class="muted">…</p></div>', true);
  try { await loadTab(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { returnrules: view });
})();
