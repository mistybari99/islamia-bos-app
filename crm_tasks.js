/* Islamia BOS · My tasks (#/crmtasks). Package CRM-G. Follow-up tasks for staff: due time, done, snooze, skip with a reason, overdue first.
   Server: supabase/phase326.sql (_crmg_task_*, _crmg_my_tasks, _crmg_task_counts) and phase327.sql (_crmg_status). The server decides every call: a hidden button is also a refused request.
   Tasks are OFF until the owner switches on "Use follow-up tasks and the My tasks list". A task posts nothing to the books and never messages a customer.
   Exports for the integrator (docs/integration/CRM-G.md): BOS.crmTasks.stripHTML() / counts() for the Home strip.
   English labels only for now. UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const ERR = {
  not_allowed: 'You do not have permission for this.', module_off: 'Tasks are switched off. The owner can switch them on in Settings.', not_found: 'This task was not found.',
  title_required: 'Write what has to be done.', due_required: 'Choose the date and time the task is due.', bad_due: 'The date and time are not valid.', bad_kind: 'Choose a kind.',
  task_closed: 'This task is already done or skipped.', reason_required: 'Write a reason (at least 3 letters).', bad_snooze: 'Choose a time in the future.',
  snooze_too_long: 'That is longer than the owner allows for a snooze.', snooze_until_required: 'Choose until when.', assignee_not_active: 'This person cannot get tasks (the login is not active).',
  assignee_not_at_outlet: 'This person does not work at the outlet of this task.', customer_not_found: 'The customer was not found.', bad_scope: 'Choose Mine or Team.',
};
const codeOf = (m) => (/not allowed/.test(m) ? 'not_allowed' : Object.keys(ERR).find((x) => m.includes(x)) || '');
const eText = (e) => { const m = String((e && e.message) || ''); const k = codeOf(m); return k ? ERR[k] : m || 'Something went wrong'; };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const guard = (fn) => (a) => { fn(a).catch((e) => { if (e && e.raw !== undefined) toast(e.message); else fail(e); }); };
const KIND = { call: 'Call', message: 'Message', visit: 'Visit', follow_up: 'Follow up', other: 'Task' };
const D = { st: null, scope: 'mine', data: null, form: null, more: null };

const when = (iso) => { try { return new Date(iso).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true }); } catch (e) { return ''; } };
const late = (h) => { const n = Number(h); if (!Number.isFinite(n)) return ''; return n >= 48 ? Math.floor(n / 24) + ' days late' : n >= 1 ? Math.floor(n) + ' h late' : 'just now'; };
const localToISO = (v) => (v ? v + ':00+06:00' : null);
const hoursToTomorrow9 = () => { const now = new Date(); const d = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Dhaka' })); const t = new Date(d); t.setDate(t.getDate() + 1); t.setHours(9, 0, 0, 0); return Math.max(1, Math.round((t - d) / 36e5)); };

function css() {
  if (document.getElementById('crmg_css')) return;
  const s = document.createElement('style'); s.id = 'crmg_css';
  s.textContent = '.crmg-pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;background:var(--line,#e5e5e5);margin-right:6px}.crmg-late{background:#f8d7da;color:#842029}.crmg-tag{background:#e7f1ff}'
    + '.crmg-acts{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}.crmg-acts button{min-height:44px}.crmg-sum{font-weight:600;margin:8px 0}.crmg-task-acts{display:grid;grid-template-columns:auto 1fr auto;align-items:center}.crmg-task-acts select{width:100%;min-width:0}.crmg-bar{position:sticky;bottom:0;padding:8px 0;background:var(--bg,#fff)}'
    + '.crmg-board-stage{margin:10px 0}.crmg-card{padding:10px;margin:6px 0}.crmg-grid{display:grid;gap:8px}';
  document.head.appendChild(s);
}

function taskCard(t, bucket) {
  const open = D.more === t.id;
  const link = t.lead_id ? `<a href="#/crmleads/${esc(t.lead_id)}">Enquiry ${esc(t.lead_no)} · ${esc(t.lead_name || '')}</a>` : t.order_no ? `Order ${esc(t.order_no)}` : '';
  const who = D.scope !== 'mine' && t.assigned_staff ? `<span class="crmg-pill">${esc(t.assigned_staff)}</span>` : '';
  const tag = bucket === 'overdue' ? `<span class="crmg-pill crmg-late">${esc(late(t.overdue_hours))}</span>` : bucket === 'snoozed' ? `<span class="crmg-pill crmg-tag">Back ${esc(when(t.snooze_until))}</span>` : '';
  const sn = [['1', 'In 1 hour'], ['3', 'In 3 hours'], [String(hoursToTomorrow9()), 'Tomorrow morning'], ['72', 'In 3 days'], ['168', 'In a week']];
  return `<div class="card crmg-card" data-task="${esc(t.id)}"><div><b>${esc(t.title)}</b></div>
    <div class="muted">${who}<span class="crmg-pill">${esc(KIND[t.kind] || 'Task')}</span>${tag}${bucket === 'snoozed' ? '' : esc(when(t.due_at))}</div>${link ? `<div class="muted">${link}</div>` : ''}
    <div class="crmg-acts crmg-task-acts"><button class="primary" data-act="ct_done" data-id="${esc(t.id)}">Done</button>
      <select data-snooze="${esc(t.id)}" aria-label="Snooze"><option value="">Snooze…</option>${sn.map(([h, l]) => `<option value="${esc(h)}">${esc(l)}</option>`).join('')}</select>
      <button data-act="ct_more" data-id="${esc(t.id)}">${open ? 'Less' : 'More'}</button></div>
    ${open ? `<div class="stack" data-more="${esc(t.id)}"><label for="ct_skip_${esc(t.id)}">Skip this task: why (at least 3 letters)</label><input id="ct_skip_${esc(t.id)}" autocomplete="off"><button data-act="ct_skip" data-id="${esc(t.id)}">Skip the task</button></div>` : ''}</div>`;
}
function section(title, rows, bucket, fold) {
  if (!rows || !rows.length) return '';
  const inner = rows.map((t) => taskCard(t, bucket)).join('');
  return fold ? `<details data-sec="${bucket}"><summary><b>${esc(title)} (${rows.length})</b></summary>${inner}</details>` : `<h3 data-sec="${bucket}">${esc(title)} (${rows.length})</h3>${inner}`;
}
function formHTML() {
  const f = D.form; if (!f) return '';
  const st = D.st || {};
  const staff = (st.staff_here || []);
  return `<div class="card stack" id="ct_form"><b>New task</b>
    <div><label for="ct_title">What has to be done</label><input id="ct_title" autocomplete="off" maxlength="120" value="${esc(f.title || '')}"></div>
    <div><label for="ct_due">Due${st.task_default_due_hours ? ' (empty = in ' + esc(st.task_default_due_hours) + ' hours)' : ''}</label><input id="ct_due" type="datetime-local" value="${esc(f.due || '')}"></div>
    <details><summary>More</summary><div class="stack"><div><label for="ct_kind">Kind</label><select id="ct_kind">${Object.entries(KIND).map(([k, l]) => `<option value="${k}" ${f.kind === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>
      ${st.can_assign_tasks ? `<div><label for="ct_who">Give to</label><select id="ct_who"><option value="">Me</option>${staff.map((p) => `<option value="${esc(p.id)}">${esc(p.staff_id)}${p.name ? ' · ' + esc(p.name) : ''}</option>`).join('')}</select></div>` : ''}</div></details>
    <div class="row"><button class="full" data-act="ct_cancel">Cancel</button><button class="full primary" data-act="ct_save">Save task</button></div></div>`;
}
function body() {
  const st = D.st;
  if (!st) return '<p class="muted">…</p>';
  if (!st.signed_in) return '<div class="card muted">Sign in to see your tasks.</div>';
  if (!st.task_on) return '<div class="card muted">Tasks are switched off. The owner can switch on "Use follow-up tasks and the My tasks list" in Settings. Nothing is lost: the list appears here as soon as it is on.</div>';
  const d = D.data; if (!d) return '<p class="muted">…</p>';
  const c = d.counts || {};
  const teamOk = st.sees_all_tasks || st.can_manage_leads || st.can_assign_tasks;
  const tabs = teamOk ? `<div class="ptabs" role="tablist"><button role="tab" data-act="ct_scope" data-v="mine" aria-selected="${D.scope === 'mine'}">Mine</button><button role="tab" data-act="ct_scope" data-v="team" aria-selected="${D.scope === 'team'}">Team</button></div>` : '';
  const empty = !(c.overdue || c.today || c.upcoming || c.snoozed);
  return tabs + `<div class="crmg-sum" id="ct_sum">${esc(c.overdue || 0)} overdue · ${esc(c.today || 0)} due today · ${esc(c.upcoming || 0)} later${c.snoozed ? ' · ' + esc(c.snoozed) + ' snoozed' : ''}</div>`
    + formHTML()
    + (empty ? '<div class="card muted" id="ct_empty">Nothing to do. Add a task with the button below.</div>' : '')
    + section('Overdue', d.overdue, 'overdue') + section('Due today', d.today, 'today') + section('Later', d.upcoming, 'upcoming') + section('Snoozed', d.snoozed, 'snoozed', true)
    + `<div class="crmg-bar"><button class="primary full" data-act="ct_new">New task</button></div>`;
}
function render() { const el = $('#ct_body'); if (el) el.innerHTML = body(); }
async function load() {
  D.st = await call('_crmg_status');
  if (D.st && D.st.task_on) D.data = await call('_crmg_my_tasks', { p_scope: D.scope });
  render();
}
Object.assign(H, {
  ct_scope: guard(async (a) => { D.scope = a.dataset.v; D.more = null; await load(); }),
  ct_new: () => { D.form = { title: '', due: '', kind: 'other' }; render(); const t = $('#ct_title'); if (t) t.focus(); },
  ct_cancel: () => { D.form = null; render(); },
  ct_save: guard(async () => {
    const title = val('ct_title'); if (!title) return toast(ERR.title_required);
    const data = { title, kind: val('ct_kind') || 'other' };
    const due = localToISO(val('ct_due')); if (due) data.due_at = due;
    const who = val('ct_who'); if (who) data.assigned_to = who;
    await call('_crmg_task_save', { p_id: null, p_client: crypto.randomUUID ? crypto.randomUUID() : null, p_data: data });
    D.form = null; toast('Saved'); await load();
  }),
  ct_done: guard(async (a) => { await call('_crmg_task_done', { p_id: a.dataset.id, p_note: null }); toast('Done'); await load(); }),
  ct_more: (a) => { D.more = D.more === a.dataset.id ? null : a.dataset.id; render(); },
  ct_skip: guard(async (a) => {
    const r = val('ct_skip_' + a.dataset.id); if (r.length < 3) return toast(ERR.reason_required);
    await call('_crmg_task_skip', { p_id: a.dataset.id, p_reason: r }); D.more = null; toast('Skipped'); await load();
  }),
});
document.addEventListener('change', (e) => {
  const s = e.target && e.target.closest ? e.target.closest('[data-snooze]') : null; if (!s || !s.value) return;
  const id = s.dataset.snooze, h = Number(s.value); s.value = '';
  call('_crmg_task_snooze', { p_id: id, p_until: null, p_hours: h, p_note: null }).then(() => { toast('Snoozed'); return load(); }).catch((er) => toast(er.message || 'error'));
});

/* ---------- for the Home strip (the integrator wires it in) ---------- */
const CT = {
  counts: () => call('_crmg_task_counts'),
  /* a one-line card; empty string when tasks are off or nothing is due */
  async stripHTML() {
    let c; try { c = await call('_crmg_task_counts'); } catch (e) { return ''; }
    if (!c || !c.on) return '';
    const o = c.overdue || 0, t = c.today || 0, l = c.leads_overdue || 0;
    if (!o && !t && !l) return '';
    return `<a class="card crmg-strip" href="#/crmtasks" style="display:block;text-decoration:none">${o ? '<span class="crmg-pill crmg-late">' + esc(o) + ' overdue</span>' : ''}<b>My tasks</b> · ${esc(t)} due today${l ? ' · ' + esc(l) + ' enquiries to follow up' : ''}</a>`;
  },
};
B.crmTasks = CT;

async function view() {
  if (B.loadStatic) await B.loadStatic();
  css(); D.st = null; D.data = null; D.form = null; D.more = null; D.scope = 'mine';
  shell('My tasks', '<div id="ct_body"><p class="muted">…</p></div>', true);
  try { await load(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmtasks: view });
})();
