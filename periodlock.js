/* Islamia BOS · Period lock (#/periodlock). One place for period integrity (U-02): the lock (manual date, automatic month lock, or off), what the owner may do in a closed period
   (silent, logged, or only with a written reason), override windows (reason, dates, minutes), the back-date limit per document type, the policy for an offline sale that arrives
   too late (re-date, re-date and list, or hold for the owner), the start-date and accounting-ON guards, and the log of every exception.
   Server: supabase/phase89.sql - period_lock_state, period_lock_set, period_lock_policy_set, period_override_start / end / log, period_lateness_report, late_sales_held_list,
   late_sale_release, accounting_on_preview, accounting_on_set. The screen only asks; the server decides (a hidden button is also a refused request).
   Register the route only through web/ia.js and add the script tag in index.html (integrator, see docs/integration/W1-B.md).
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;
const sel = (id, opts, cur) => `<select id="${id}">${opts.map(([k, l]) => `<option value="${esc(k)}" ${String(cur) === String(k) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;

const TABS_OWNER = [['lock', 'Lock'], ['override', 'Override'], ['backdate', 'Back-dating'], ['late', 'Late sales'], ['books', 'Accounting'], ['log', 'Log']];
const MODE = [['manual', 'Manual: the date I type'], ['auto', 'Automatic month lock (the date I type still counts)'], ['off', 'Off: nothing is locked']];
const OWNER_MODE = [['off', 'Silent, as before'], ['log', 'Allowed, and every use is logged'], ['reason', 'Only with a written reason (override window)']];
const BACKWARD = [['allow', 'Any time'], ['reason_after_year_close', 'A reason is needed to reopen a closed year'], ['reason_always', 'A reason is needed for any move back']];
const LATE = [['redate', 'Re-date to the time it arrives (as before)'], ['redate_flag', 'Re-date, and list it in Exceptions'], ['park', 'Hold it for the owner to decide']];
const SCOPE = [['lock', 'Closed period'], ['backdate', 'Back-dating limit'], ['both', 'Both']];
const DOCS = [['', 'Every document type'], ['purchase', 'Purchase bill'], ['cash_move', 'Cash move'], ['expense', 'Quick expense'], ['production', 'Production']];
const HOOK_NAMES = { lock_check: 'the closed-period test', acct_locked: 'the posting date test', record_sale2: 'the sale (late offline sale)', cash_move_add: 'cash moves (back-date limit)',
  quick_expense_add: 'quick expenses (back-date limit)', save_purchase: 'purchase bills (back-date limit)', production_post: 'production (back-date limit)' };
const ERR = {
  not_allowed: 'You do not have permission.', reason_required: 'Write a reason (at least 3 characters).', bad_date: 'The date is not valid.', bad_minutes: 'Minutes must be between 1 and 1440.',
  bad_scope: 'Choose what the window is for.', bad_doc: 'Unknown document type.', unknown_user: 'Unknown or inactive person.', unknown_setting: 'Unknown setting.', bad_value: 'That value is not allowed.',
  auto_lock_day_missing: 'Set the automatic lock day first (the automatic mode needs it).', lock_backward_needs_reason: 'Moving the lock date back needs a written reason: use "Set the lock date".',
  start_date_locked_by_opening: 'An opening balance exists: reverse it before moving the accounting start date.', accounting_on_needs_reason: 'Use the Accounting tab: a reason is needed to switch accounting on.',
  period_closed_reason_required: 'The books are closed for that date. Open an override window with a reason first.', period_closed: 'That period is closed.', maker_cannot_decide: 'The person who made the sale cannot decide it.',
  already_decided: 'Already decided.', bad_action: 'Unknown action.', 'not found': 'Not found.',
};
const eText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const D = { tab: 'lock', st: null, log: null, held: null, late: null, prev: null, people: [], owner: false, lastErr: '' };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const askReason = (q) => { const r = window.prompt(q); return r === null ? null : r.trim(); };
const optLabel = (arr, k) => { const f = arr.find((x) => String(x[0]) === String(k)); return f ? f[1] : String(k ?? ''); };
const dt = (v) => (v ? String(v).replace('T', ' ').slice(0, 16) : '-');

function hooksNotice() {
  const h = (D.st && D.st.hooks) || {}; const miss = Object.keys(HOOK_NAMES).filter((k) => h[k] !== true);
  if (!miss.length) return '';
  return `<div class="notice bad" id="pl_hooks">These links to existing screens are not installed yet (the integrator installs them; the settings below are saved but have no effect there until then): ${miss.map((k) => esc(HOOK_NAMES[k])).join(', ')}.</div>`;
}
function tabsBar() {
  const tabs = D.owner ? TABS_OWNER : [['lock', 'Lock']];
  return `<div class="row wrap" id="pl_tabs" style="gap:.3rem">${tabs.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="pl_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
}

// ---------------- Lock ----------------
function lockHTML() {
  const s = D.st; if (!s) return '';
  const eff = s.effective_lock_date;
  const head = `<div class="card stack" id="pl_state"><div class="row between"><b>Books are closed up to</b><b id="pl_eff">${esc(eff || 'nothing is closed')}</b></div>
    <div class="row wrap">${chip('Lock: ' + optLabel(MODE, s.mode).split(':')[0].split(' (')[0])}${s.manual_date ? chip('Typed date ' + s.manual_date) : chip('No typed date')}${s.mode === 'auto' ? chip('Automatic: after day ' + (s.auto_day ?? '?')) : ''}
      ${chip('Owner: ' + optLabel(OWNER_MODE, s.owner_mode).split(',')[0].split(' (')[0], s.owner_mode === 'off' ? 'warn' : 'ok')}</div>
    <div class="muted">Today is ${esc(s.today)}. ${s.owner_mode === 'off' ? 'The owner can still change closed dates without a trace: choose "Only with a written reason" below once the books are really closed.' : ''}</div></div>`;
  const wins = (s.my_windows || []).length ? `<div class="card" id="pl_mine"><b>Your open override windows</b>${s.my_windows.map((w) => `<div class="muted">#${esc(w.id)} · ${esc(w.from)} to ${esc(w.to)} · until ${esc(dt(w.expires_at))} · ${esc(w.reason)}</div>`).join('')}</div>` : '';
  if (!D.owner) return hooksNotice() + head + wins;
  return hooksNotice() + head + wins + `<div class="card stack" id="pl_setdate"><b>Set the lock date</b>
      <p class="muted">Everything dated up to and including this day is closed. Moving it forward needs no reason. Moving it back may need one (see below). Empty = clear it.</p>
      ${fld('pl_ld', 'Lock date', inp('pl_ld', s.manual_date || '', 'type="date"'))}${fld('pl_lr', 'Reason (needed when moving back, kept in the log)', inp('pl_lr', '', 'maxlength="300"'))}
      <button type="button" class="primary full" data-act="pl_setdate">Save the lock date</button></div>
    <div class="card stack" id="pl_policy"><b>Lock rules</b>
      ${fld('pl_mode', 'How the books are closed', sel('pl_mode', MODE, s.mode))}
      ${fld('pl_day', 'Automatic lock: lock last month after this day of the month (1 to 28, empty = not set)', inp('pl_day', s.auto_day ?? '', 'inputmode="numeric"'))}
      ${fld('pl_om', 'The owner in a closed period', sel('pl_om', OWNER_MODE, s.owner_mode))}
      ${fld('pl_bw', 'Moving the lock date back', sel('pl_bw', BACKWARD, s.backward_policy))}
      ${fld('pl_min', 'Override window: default length in minutes', inp('pl_min', s.override_minutes ?? 60, 'inputmode="numeric"'))}
      <button type="button" class="primary full" data-act="pl_savepolicy">Save the lock rules</button>
      <p class="muted">Every change is written to the audit log with the old and the new value.</p></div>`;
}

// ---------------- Override ----------------
function overrideHTML() {
  const s = D.st;
  const people = `<option value="">Me</option>` + D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id || p.id)}</option>`).join('');
  return `<div class="card stack" id="pl_ov"><b>Open an override window</b>
      <p class="muted">For a short time one person may enter or change something dated in a closed period (or beyond a back-date limit). A written reason is compulsory. Every use is one audit line and one line in the Exceptions list.</p>
      ${fld('ov_reason', 'Reason', inp('ov_reason', '', 'maxlength="300"'))}
      <div class="row wrap">${fld('ov_from', 'Dates from', inp('ov_from', '', 'type="date"'))}${fld('ov_to', 'to', inp('ov_to', '', 'type="date"'))}</div>
      ${fld('ov_min', 'Minutes the window stays open', inp('ov_min', s.override_minutes ?? 60, 'inputmode="numeric"'))}
      ${fld('ov_scope', 'The window is for', sel('ov_scope', SCOPE, 'lock'))}${fld('ov_doc', 'Document type (back-dating)', sel('ov_doc', DOCS, ''))}
      ${fld('ov_user', 'For', `<select id="ov_user">${people}</select>`)}
      <button type="button" class="primary full" data-act="pl_ovstart">Open the window</button></div>
    <h3>Open windows</h3>${(s.open_windows || []).map((w) => `<div class="card pl-win" data-id="${esc(w.id)}"><div class="row between"><b>#${esc(w.id)} · ${esc(w.staff || w.user_id)}</b><span>${esc(optLabel(SCOPE, w.scope))}</span></div>
        <div class="muted">${esc(w.from)} to ${esc(w.to)}${w.doc ? ' · ' + esc(optLabel(DOCS, w.doc)) : ''} · until ${esc(dt(w.expires_at))} · used ${esc(w.uses)} time(s)</div><div>${esc(w.reason)}</div>
        <button type="button" class="mini" data-act="pl_ovend" data-v="${esc(w.id)}">End now</button></div>`).join('') || '<p class="muted">None open.</p>'}`;
}

// ---------------- Back-dating ----------------
function backdateHTML() {
  const b = (D.st && D.st.backdate) || {}; const L = D.late;
  const row = (k, label) => `<div class="card stack pl-bd" data-k="${k}"><b>${esc(label)}</b>${fld('bd_' + k, 'Most days back (empty = no limit)', inp('bd_' + k, b[k] ?? '', 'inputmode="numeric"'))}<button type="button" class="mini" data-act="pl_bdsave" data-v="${k}">Save</button></div>`;
  const rep = L ? Object.keys(L.by_document || {}).map((k) => { const r = L.by_document[k]; return `<div class="card pl-late-row"><div class="row between"><b>${esc(optLabel(DOCS, k))}</b><span>${esc(r.records)} records, latest ${esc(r.max_days_late)} days late</span></div>
      <div class="muted">same day ${esc(r.same_day)} · 1-2 days ${esc(r.days_1_2)} · 3-7 days ${esc(r.days_3_7)} · 8-30 days ${esc(r.days_8_30)} · over 30 days ${esc(r.over_30)}</div></div>`; }).join('') || '<p class="muted">No records in this period.</p>' : '';
  return `<p class="muted">How far back a NEW record may be dated. Empty = no limit (as before). Over the limit the server refuses unless an override window, a one-off owner grant or a trusted role allows it. Read the lateness report first and choose a number from what really happens.</p>
    ${row('purchase', 'Purchase bill date')}${row('cash_move', 'Cash move date')}${row('expense', 'Quick expense date')}${row('production', 'Production date')}
    <div class="card stack"><b>Lateness report</b>${fld('lr_days', 'Last how many days', inp('lr_days', 30, 'inputmode="numeric"'))}<button type="button" class="btn" data-act="pl_lateshow">Show the report</button>${rep}
    <p class="muted">${esc((L && L.note) || '')}</p></div>`;
}

// ---------------- Late sales ----------------
function lateHTML() {
  const s = D.st; const held = D.held || [];
  const rows = held.map((h) => `<div class="card pl-held" data-id="${esc(h.id)}"><div class="row between"><b>#${esc(h.id)} · ${esc(h.staff || h.user_id)}</b><span>${esc(h.status)}</span></div>
      <div class="muted">made ${esc(dt(h.sold_at))} · arrived ${esc(dt(h.received_at))} · ${esc(h.hours_late)} hours late · ${esc(h.n_lines)} line(s) · paid ${esc(h.paid)}</div>
      ${h.status === 'held' ? `<div class="row wrap"><button type="button" class="mini" data-act="pl_rel" data-v="${esc(h.id)}" data-a="accept">Accept with its own time</button><button type="button" class="mini" data-act="pl_rel" data-v="${esc(h.id)}" data-a="redate">Re-date to now</button>
        <button type="button" class="mini" data-act="pl_rel" data-v="${esc(h.id)}" data-a="reject">⋮ Reject</button></div>` : `<div>${esc(h.decide_reason || '')}</div>`}</div>`).join('');
  return `<div class="card stack" id="pl_latepol"><b>A sale that arrives later than the offline limit</b>
      <p class="muted">The limit is ${esc(s.offline_hours)} hours (the setting "How many hours an offline sale keeps its own time"). What should happen to a sale that arrives after it?</p>
      ${fld('pl_lp', 'Policy', sel('pl_lp', LATE, s.late_sale_policy))}<button type="button" class="primary full" data-act="pl_savelate">Save</button></div>
    <h3>Held sales</h3>${rows || '<p class="muted">None held.</p>'}`;
}

// ---------------- Accounting ----------------
function booksHTML() {
  const s = D.st; const p = D.prev;
  const prev = p ? (p.ran === false ? `<div class="chip warn">${esc(p.why || 'The preview could not run')}</div>` : `<div class="card" id="pl_prev"><b>If accounting is switched on now</b>
      <div class="row between"><span>Documents that would be posted</span><b>${esc(p.would_post)}</b></div><div class="row between"><span>Reversals</span><b>${esc(p.would_reverse)}</b></div>
      <div class="row between"><span>Skipped because their date is closed</span><b>${esc(p.skipped_locked)}</b></div>${p.oldest_in_sample ? `<div class="muted">Oldest in the sample: ${esc(p.oldest_in_sample)}</div>` : ''}
      ${p.data_needed ? '<div class="chip warn">The accounting start date is not set.</div>' : ''}</div>`) : '';
  return `<div class="card stack" id="pl_books"><b>Accounting is ${s.accounting_on ? 'ON' : 'OFF'}</b>
      <div class="row wrap"><button type="button" class="btn" data-act="pl_prevgo">Preview the backlog</button>
        <button type="button" class="${s.accounting_on ? 'btn' : 'primary'}" data-act="pl_accset" data-v="${s.accounting_on ? 'off' : 'on'}">${s.accounting_on ? 'Switch accounting OFF' : 'Switch accounting ON'}</button></div>${prev}</div>
    <div class="card stack"><b>Guards</b>
      <label class="row"><input type="checkbox" id="pl_g1" ${s.start_date_lock_after_opening ? 'checked' : ''}> Do not move the accounting start date once the opening balance is posted</label>
      <label class="row"><input type="checkbox" id="pl_g2" ${s.accounting_on_needs_reason ? 'checked' : ''}> Switching accounting ON again needs a written reason</label>
      <button type="button" class="primary full" data-act="pl_saveguards">Save the guards</button><p class="muted">Both are off by default (as before).</p></div>`;
}

// ---------------- Log ----------------
function logHTML() {
  const g = D.log; if (!g) return '<p class="muted">…</p>';
  return `<h3>Windows</h3>${(g.windows || []).map((w) => `<div class="card pl-logwin"><div class="row between"><b>#${esc(w.id)} · ${esc(w.staff || w.user_id)}</b><span>${esc(w.ended_at ? 'ended' : 'opened')} · used ${esc(w.uses)}</span></div>
      <div class="muted">${esc(optLabel(SCOPE, w.scope))} · ${esc(w.from_date)} to ${esc(w.to_date)} · ${esc(dt(w.started_at))} until ${esc(dt(w.expires_at))}</div><div>${esc(w.reason)}</div></div>`).join('') || '<p class="muted">None.</p>'}
    <h3>Exceptions</h3>${(g.exceptions || []).map((x) => `<div class="card pl-logex"><div class="row between"><b>${esc(x.kind)}</b><span>${esc(dt(x.at))} · ${esc(x.status)}</span></div><div>${esc(x.reason || '')}</div></div>`).join('') || '<p class="muted">None.</p>'}
    <h3>Audit lines</h3>${(g.audit || []).map((x) => `<div class="muted pl-logau">${esc(dt(x.at))} · ${esc(x.staff_id || '')} · ${esc(x.action)} ${esc(x.record_id || '')}</div>`).join('') || '<p class="muted">None.</p>'}`;
}

function draw() {
  const el = $('#pl_body'); if (!el) return;
  const body = ({ lock: lockHTML, override: overrideHTML, backdate: backdateHTML, late: lateHTML, books: booksHTML, log: logHTML })[D.tab]();
  el.innerHTML = tabsBar() + `<div id="pl_pane">${D.tab === 'lock' ? '' : hooksNotice()}${body}</div>`;
}
async function loadTab() {
  D.st = await call('period_lock_state', {}); D.owner = !!D.st.owner;
  if (!D.owner) { D.tab = 'lock'; return; }
  if (D.tab === 'override' && !D.people.length) { const p = await sb.from('profiles').select('id,full_name,staff_id,status').eq('status', 'active').order('full_name'); D.people = p.data || []; }
  if (D.tab === 'backdate' && !D.late) D.late = await call('period_lateness_report', { p_days: 30 });
  if (D.tab === 'late') D.held = await call('late_sales_held_list', { p_status: null });
  if (D.tab === 'log') D.log = await call('period_override_log', { p_limit: 100 });
}
async function show(tab) { if (tab) D.tab = tab; try { await loadTab(); draw(); } catch (e) { toast(eText(e)); draw(); } }
const intOrNull = (t) => { const v = norm(t); if (v === '') return null; const n = Number(v); return Number.isFinite(n) ? n : NaN; };
async function policy(key, value, note) { await call('period_lock_policy_set', { p_key: key, p_value: value === undefined ? null : value, p_note: note || null }); }

Object.assign(H, {
  pl_tab: (a) => show(a.dataset.v),
  pl_setdate: act(async () => {
    const d = val('pl_ld') || null; const why = val('pl_lr');
    await call('period_lock_set', { p_date: d, p_reason: why || null }); toast('Saved'); await show('lock');
  }),
  pl_savepolicy: act(async () => {
    const day = intOrNull(val('pl_day')); const mins = intOrNull(val('pl_min'));
    if (Number.isNaN(day) || Number.isNaN(mins)) return toast(ERR.bad_value);
    if (val('pl_mode') === 'auto' && day === null) return toast(ERR.auto_lock_day_missing);
    // order matters: the day first when switching to auto, the mode first when switching away from it
    const s = D.st; const dayChanged = day !== (s.auto_day === undefined || s.auto_day === null ? null : Number(s.auto_day)); const modeChanged = val('pl_mode') !== s.mode;
    if (val('pl_mode') === 'auto') { if (dayChanged) await policy('auto_lock_day', day, 'Period lock screen'); if (modeChanged) await policy('period_lock_mode', val('pl_mode'), 'Period lock screen'); }
    else { if (modeChanged) await policy('period_lock_mode', val('pl_mode'), 'Period lock screen'); if (dayChanged) await policy('auto_lock_day', day, 'Period lock screen'); }
    if (val('pl_om') !== s.owner_mode) await policy('owner_closed_period_mode', val('pl_om'), 'Period lock screen');
    if (val('pl_bw') !== s.backward_policy) await policy('lock_backward_policy', val('pl_bw'), 'Period lock screen');
    if (mins !== null && mins !== s.override_minutes) await policy('period_override_default_minutes', mins, 'Period lock screen');
    toast('Saved'); await show('lock');
  }),
  pl_ovstart: act(async () => {
    const why = val('ov_reason'); if (why.length < 3) return toast(ERR.reason_required);
    const f = val('ov_from'), t = val('ov_to'); if (!f || !t) return toast(ERR.bad_date);
    const mins = intOrNull(val('ov_min')); if (Number.isNaN(mins)) return toast(ERR.bad_minutes);
    await call('period_override_start', { p_reason: why, p_from: f, p_to: t, p_minutes: mins, p_scope: val('ov_scope'), p_for_user: val('ov_user') || null, p_doc: val('ov_doc') || null });
    toast('The window is open'); await show('override');
  }),
  pl_ovend: act(async (a) => { const n = askReason('Why is the window ended?'); if (n === null) return; await call('period_override_end', { p_id: Number(a.dataset.v), p_note: n || null }); toast('Ended'); await show('override'); }),
  pl_bdsave: act(async (a) => {
    const k = a.dataset.v; const n = intOrNull(val('bd_' + k)); if (Number.isNaN(n) || (n !== null && (n < 0 || n > 3650))) return toast(ERR.bad_value);
    await policy('backdate_max_days_' + k, n, 'Period lock screen'); toast('Saved'); await show('backdate');
  }),
  pl_lateshow: act(async () => { const n = intOrNull(val('lr_days')); D.late = await call('period_lateness_report', { p_days: n || 30 }); draw(); }),
  pl_savelate: act(async () => { await policy('late_sale_policy', val('pl_lp'), 'Period lock screen'); toast('Saved'); await show('late'); }),
  pl_rel: act(async (a) => {
    const why = askReason('Write the reason for this decision'); if (why === null) return; if (why.length < 3) return toast(ERR.reason_required);
    await call('late_sale_release', { p_id: Number(a.dataset.v), p_action: a.dataset.a, p_reason: why }); toast('Done'); await show('late');
  }),
  pl_prevgo: act(async () => { D.prev = await call('accounting_on_preview', {}); draw(); }),
  pl_accset: act(async (a) => {
    const on = a.dataset.v === 'on'; const why = askReason(on ? 'Why is accounting switched on? (kept in the audit log)' : 'Why is accounting switched off? (optional)'); if (why === null) return;
    if (on && D.st.accounting_on_needs_reason && why.length < 3) return toast(ERR.reason_required);
    await call('accounting_on_set', { p_on: on, p_reason: why || null }); toast('Saved'); D.prev = null; await show('books');
  }),
  pl_saveguards: act(async () => {
    await policy('start_date_lock_after_opening', !!($('#pl_g1') || {}).checked, 'Period lock screen'); await policy('accounting_on_needs_reason', !!($('#pl_g2') || {}).checked, 'Period lock screen');
    toast('Saved'); await show('books');
  }),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell('Period lock', '<div id="pl_body"><p class="muted">…</p></div>', true);
  try { await show(D.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { periodlock: view });
})();
