/* Islamia BOS · Customer feedback and complaints (#/crmfeedback). Package CRM-H.
   Server (supabase/phase328.sql and phase329.sql, every function starts _crmh_): complaints with outlet, item, severity, owner, status and an SLA clock;
   food-safety routing to the Exceptions list; repeat flags; one star rating per sale or order; a report by outlet, item, category, severity or month.
   A complaint posts NOTHING. A refund is made on the existing sale return screen (B.saleReturn.open); this page only LINKS a finished return to the complaint.
   Three tabs: Complaints, Ratings, Report. Essentials first: the list and one button. Everything else opens in a sheet. English labels only (owner rule 5).
   The server decides who may do what; a hidden button is also a refused request. UNVERIFIED on a real Supabase project and on a real phone. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);                      // English only: the same text in all three modes
const X = {
  title: E('Feedback and complaints'), tabc: E('Complaints'), tabr: E('Ratings'), tabp: E('Report'),
  open: E('Open'), overdue: E('Overdue'), fs: E('Food safety'), calls: E('Calls needed'), unowned: E('No owner'),
  f_active: E('Open'), f_overdue: E('Overdue'), f_fs: E('Food safety'), f_repeat: E('Repeat'), f_mine: E('Mine'), f_all: E('All'),
  all_outlets: E('All outlets'), new_c: E('Log a complaint'), new_r: E('Add a rating'), none_c: E('No complaints to show.'), none_r: E('No ratings to show.'), more: E('More'),
  off: E('Complaints are switched off. The owner can switch them on in the Switchboard (Customer complaints).'),
  rate_off: E('Ratings are switched off. The owner can switch them on in the Switchboard (Customer ratings).'),
  denied: E('You do not have permission to open this page.'), nofn: E('phase328.sql and phase329.sql have not been run on the server yet.'),
  s_open: E('Open'), s_in_progress: E('In progress'), s_resolved: E('Resolved'), s_closed: E('Closed'), s_closed_no_resolution: E('Closed without a result'),
  sev_low: E('Low'), sev_medium: E('Medium'), sev_high: E('High'), sev_critical: E('Critical'),
  sla_overdue: E('Overdue'), sla_running: E('On time'), sla_met: E('Target met'), sla_missed: E('Target missed'), sla_none: E('No clock'),
  left: E('left'), over_by: E('over by'), repeat: E('Repeat'), foodsafety: E('Food safety'),
  outlet: E('Outlet'), category: E('Category'), severity: E('Severity'), desc: E('What happened'), receipt: E('Receipt number (optional)'), item: E('Item (optional)'), find: E('Find'),
  phone: E('Customer phone (optional)'), fsbox: E('This may be a food-safety problem'), save: E('Save'), cancel: E('Cancel'), back: E('Close'), choose: E('Choose'),
  saved: E('Saved.'), found: E('Receipt found.'), notfound: E('That receipt was not found at this outlet.'), needdesc: E('Write what happened (at least 3 letters).'), needcat: E('Choose a category.'), needloc: E('Choose an outlet.'),
  start: E('Start'), resolve: E('Resolve'), close: E('Close'), closenr: E('Close without a result'), reopen: E('Reopen'), note: E('Add a note'), contact: E('Record a call'), assignme: E('Take it'), unassign: E('Clear owner'), sevchg: E('Change severity'),
  result: E('Result'), notefld: E('Note'), reason: E('Reason'), why: E('Why is it being changed?'), trail: E('History'), owner: E('Owner'), noowner: E('nobody yet'), customer: E('Customer'), logged: E('Logged'), due: E('Target time'),
  retblock: E('Refund or return'), retnote: E('This screen never refunds. Make the refund on the sale return screen, then link the finished return here.'), openret: E('Open the sale return screen'), linkret: E('Link this return'),
  noret: E('No finished return on this receipt yet.'), linked: E('Linked returns'), earlier: E('Earlier complaints by this customer'), value: E('value'), norcpt: E('No receipt is linked to this complaint.'),
  stars: E('Stars'), comment: E('Comment (optional)'), channel: E('How was it collected'), ch_counter: E('At the counter'), ch_phone: E('By phone'), ch_message: E('By message'), ch_other: E('Other'),
  avg: E('Average'), calldone: E('Call done'), tocomplaint: E('Make a complaint'), callnote: E('What was said on the call'), needcall: E('needs a call'), cmp_open: E('complaint opened'),
  from: E('From'), to: E('To'), by: E('Group by'), g_outlet: E('Outlet'), g_item: E('Item'), g_category: E('Category'), g_severity: E('Severity'), g_month: E('Month'), run: E('Show report'),
  rep_c: E('Complaints'), rep_r: E('Ratings'), total: E('total'), openn: E('open'), resolvedn: E('resolved'), closednr: E('closed without result'), overdn: E('overdue now'), breached: E('went overdue'),
  met: E('target met'), missed: E('target missed'), fsn: E('food safety'), repn: E('repeats'), avgh: E('average hours to resolve'), refund: E('value of linked returns'), n: E('ratings'),
  scan: E('Check for overdue now'), scanned: E('Marked as overdue'), nothing: E('Nothing new is overdue.'), repeats: E('Repeat customers'), repnone: E('No repeat complaints in this period.'),
  repoff: E('The repeat check is off. The owner sets its look-back days in the Switchboard.'), perr: E('Could not do that.'),
};
const ERR = {
  complaints_off: 'Complaints are switched off.', feedback_off: 'Ratings are switched off.', not_allowed: 'You do not have permission for that.', 'not allowed': 'You do not have permission for that.',
  illegal_status_change: 'That change is not allowed from the current status.', complaint_locked: 'This complaint is closed and cannot be changed.',
  resolution_required: 'Choose a result and write a short note (at least 3 letters).', reason_required: 'Choose a reason and write a short note (at least 3 letters).', note_required: 'Write a short note (at least 3 letters).',
  description_required: 'Write what happened (at least 3 letters).', bad_category: 'Choose a category from the list.', bad_phone: 'The phone number does not look right.',
  item_not_in_sale: 'That item is not on this receipt.', sale_other_outlet: 'That receipt belongs to a different outlet.', location_required: 'Choose an outlet.', owner_other_outlet: 'That person does not work at this outlet.',
  already_rated: 'This sale or order already has a rating.', bad_rating: 'Choose 1 to 5 stars.', sale_void: 'A cancelled sale cannot be rated.', order_cancelled: 'A cancelled order cannot be rated.', too_old: 'This sale is too old to rate.',
  sale_or_order_required: 'Find the receipt first.', return_already_linked: 'That return is already linked to a complaint.', return_other_sale: 'That return belongs to a different receipt.',
  return_other_outlet: 'That return belongs to a different outlet.', return_not_done: 'That return was cancelled.', no_follow_up_needed: 'This rating needs no call.', days_required: 'The repeat check is off.',
  range_too_long: 'Choose a period of one year or less.', bad_range: 'The start date is after the end date.',
};
const T = (k) => lab(X[k]);
const D = { tab: 'c', set: null, fset: null, cnt: null, filt: 'active', loc: '', rows: null, total: 0, rat: null, rep: null, repeats: null, rf: '', rt: '', by: 'outlet', err: null, sale: null, pend: null };

/* ---------- helpers ---------- */
const isMissing = (e) => e && (e.code === 'PGRST202' || /does not exist|could not find/i.test(e.message || ''));
const code = (e) => String((e && e.message) || '').replace(/^.*?(?=[a-z_ ]+$)/, '').trim();
const say = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : T('perr') + (m ? ' · ' + m.slice(0, 80) : ''); };
async function rpc(fn, args) { const r = await sb.rpc(fn, args); if (r.error) throw r.error; return r.data; }
const fail2 = (e) => { toast(say(e)); };
const dt = (ts) => (ts ? new Date(ts).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }) : '');
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const minus = (n) => { const d = new Date(); d.setDate(d.getDate() - n); return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }); };
const locs = () => { const all = (B.ENV && B.ENV.locs) || []; const c = S.ctx || {}; return c.is_owner || (c.roles || []).includes('management') ? all : all.filter((l) => (c.locations || []).includes(l.id)); };
const lname = (l) => l.name_en || l.name_bn || l.code || String(l.id);
const opt = (v, t, sel) => `<option value="${esc(String(v))}" ${String(sel) === String(v) ? 'selected' : ''}>${esc(t)}</option>`;
const hrs = (min) => { const m = Math.abs(Number(min)); return m < 120 ? m + ' min' : m < 2880 ? Math.round(m / 60) + ' h' : Math.round(m / 1440) + ' days'; };
const SEVCHIP = { critical: 'bad', high: 'warn', medium: '', low: '' };
const SLACHIP = { overdue: 'bad', running: 'ok', met: 'ok', missed: 'bad', none: '' };
const stars = (n) => '★'.repeat(n) + '☆'.repeat(5 - n);

function slaText(c) {
  if (c.sla_state === 'overdue') return `${T('sla_overdue')} · ${T('over_by')} ${hrs(c.minutes_left)}`;
  if (c.sla_state === 'running') return `${T('sla_running')} · ${hrs(c.minutes_left)} ${T('left')}`;
  return T('sla_' + c.sla_state);
}

/* ---------- loading ---------- */
async function loadBase() {
  D.err = null;
  try {
    D.set = await rpc('_crmh_settings');
    try { D.fset = await rpc('_crmh_feedback_settings'); } catch (e) { D.fset = null; }
    D.cnt = await rpc('_crmh_counts');
  } catch (e) { D.err = isMissing(e) ? 'nofn' : /not allowed/i.test(e.message || '') ? 'denied' : 'x'; if (D.err === 'x') throw e; }
}
async function loadList() {
  const f = D.filt, a = { limit: 30 };
  if (f === 'overdue') a.overdue = true; else if (f === 'fs') { a.food_safety = true; a.status = 'active'; } else if (f === 'repeat') { a.repeat = true; a.status = 'active'; }
  else if (f === 'mine') { a.mine = true; a.status = 'active'; } else if (f === 'all') a.status = 'all'; else a.status = 'active';
  if (D.loc) a.location_id = Number(D.loc);
  const r = await rpc('_crmh_complaint_list', a); D.rows = r.rows || []; D.total = r.total || 0;
}
async function loadRatings() {
  const a = { limit: 30 }; if (D.loc) a.location_id = Number(D.loc);
  D.rat = await rpc('_crmh_feedback_list', a);
}
async function loadReport() {
  const a = { from: D.rf || minus(29), to: D.rt || today(), by: D.by }; if (D.loc) a.location_id = Number(D.loc);
  D.rep = await rpc('_crmh_report', a);
  try { D.repeats = await rpc('_crmh_repeat_list', D.loc ? { location_id: Number(D.loc) } : {}); } catch (e) { D.repeats = /days_required/.test(e.message || '') ? { off: true } : null; }
}

/* ---------- drawing ---------- */
function stripHTML() {
  const c = D.cnt || {}, f = D.rat ? D.rat.needs_call : null;
  const chip = (n, k, cls) => `<span class="chip ${Number(n) > 0 ? cls : ''}" data-k="${k}">${esc(String(n || 0))} ${esc(T(k))}</span>`;
  return `<div class="row wrap cf-strip" id="cf_strip" style="gap:6px">${chip(c.open, 'open', '')}${chip(c.overdue, 'overdue', 'bad')}${chip(c.food_safety, 'fs', 'warn')}${f !== null ? chip(f, 'calls', 'warn') : ''}</div>`;
}
function outletSel() {
  const ls = locs(); if (ls.length < 2) return '';
  return `<select id="cf_loc" aria-label="${esc(T('outlet'))}">${opt('', T('all_outlets'), D.loc)}${ls.map((l) => opt(l.id, lname(l), D.loc)).join('')}</select>`;
}
function rowHTML(c) {
  const chips = [`<span class="chip ${SEVCHIP[c.severity] || ''}">${esc(T('sev_' + c.severity))}</span>`,
    `<span class="chip ${SLACHIP[c.sla_state] || ''}" data-sla="${esc(c.sla_state)}">${esc(slaText(c))}</span>`];
  if (c.food_safety) chips.push(`<span class="chip warn">${esc(T('foodsafety'))}</span>`);
  if (c.repeat_flag) chips.push(`<span class="chip warn">${esc(T('repeat'))}</span>`);
  const sub = [c.location, c.item_name, c.customer_name].filter(Boolean).join(' · ');
  return `<button type="button" class="card stack cf-row" data-act="cf_open" data-id="${esc(c.id)}" style="text-align:start;width:100%">
    <div class="row between"><b>#${esc(String(c.ticket_no))} · ${esc(c.category_label || c.category)}</b><span class="muted">${esc(T('s_' + c.status))}</span></div>
    <div class="muted">${esc(sub)}</div><div class="row wrap" style="gap:6px">${chips.join('')}</div></button>`;
}
function complaintsHTML() {
  const on = D.set && D.set.on;
  if (!on) return `<div class="card" id="cf_off"><p>${esc(T('off'))}</p></div>`;
  const filt = ['active', 'overdue', 'fs', 'repeat', 'mine', 'all'].map((k) => `<button type="button" class="chip ${D.filt === k ? 'ok' : ''}" data-act="cf_filt" data-k="${k}" aria-pressed="${D.filt === k}">${esc(T('f_' + k))}</button>`).join('');
  const rows = D.rows === null ? '<p class="muted">…</p>' : D.rows.length ? D.rows.map(rowHTML).join('') : `<p class="muted">${esc(T('none_c'))}</p>`;
  const scan = D.set.may_manage ? `<button type="button" class="btn" data-act="cf_scan" id="cf_scan">${esc(T('scan'))}</button>` : '';
  return `<div class="row wrap" style="gap:6px">${filt}</div>${outletSel()}<div class="stack" id="cf_list">${rows}</div>
    <div class="row wrap p2-bar2">${D.set.may_log ? `<button type="button" class="btn primary" data-act="cf_new" id="cf_new">${esc(T('new_c'))}</button>` : ''}${scan}</div>`;
}
function ratingRow(r) {
  const call = r.follow_up === 'needed' ? `<span class="chip warn">${esc(T('needcall'))}</span>` : r.complaint_id ? `<span class="chip">${esc(T('cmp_open'))}</span>` : '';
  const act = r.follow_up === 'needed' && D.set && D.set.may_manage
    ? `<div class="row wrap" style="gap:6px"><button type="button" class="btn" data-act="cf_calldone" data-id="${esc(r.id)}">${esc(T('calldone'))}</button><button type="button" class="btn" data-act="cf_tocomplaint" data-id="${esc(r.id)}">${esc(T('tocomplaint'))}</button></div>` : '';
  return `<div class="card stack cf-rate" data-id="${esc(r.id)}"><div class="row between"><b class="cf-stars" aria-label="${r.rating}">${stars(r.rating)}</b><span class="muted">${esc(dt(r.at))}</span></div>
    <div class="muted">${esc([r.location, r.receipt ? '#' + r.receipt : r.order_no ? 'Order ' + r.order_no : '', r.customer_name].filter(Boolean).join(' · '))}</div>
    ${r.comment ? `<div>${esc(r.comment)}</div>` : ''}${call}${act}</div>`;
}
function ratingsHTML() {
  const fs = D.fset;
  if (!fs || !fs.on) return `<div class="card" id="cf_roff"><p>${esc(T('rate_off'))}</p></div>`;
  const r = D.rat; const rows = !r ? '<p class="muted">…</p>' : r.rows.length ? r.rows.map(ratingRow).join('') : `<p class="muted">${esc(T('none_r'))}</p>`;
  const sum = r ? `<div class="card row between" id="cf_rsum"><span><b>${esc(T('avg'))}:</b> ${r.average === null || r.average === undefined ? '-' : esc(String(r.average))} / 5</span><span class="muted">${esc(String(r.total))} ${esc(T('n'))}</span></div>` : '';
  return `${outletSel()}${sum}<div class="stack" id="cf_rlist">${rows}</div>
    <div class="row wrap p2-bar2">${fs.may_log ? `<button type="button" class="btn primary" data-act="cf_newr" id="cf_newr">${esc(T('new_r'))}</button>` : ''}</div>`;
}
function repHTML() {
  const p = D.rep;
  const form = `<div class="card stack"><div class="row wrap" style="gap:8px"><label>${esc(T('from'))}<input type="date" id="cf_from" value="${esc(D.rf || minus(29))}"></label><label>${esc(T('to'))}<input type="date" id="cf_to" value="${esc(D.rt || today())}"></label></div>
    <label>${esc(T('by'))}<select id="cf_by">${['outlet', 'item', 'category', 'severity', 'month'].map((k) => opt(k, T('g_' + k), D.by)).join('')}</select></label>${outletSel()}
    <button type="button" class="btn primary" data-act="cf_run" id="cf_run">${esc(T('run'))}</button></div>`;
  if (!p) return form;
  const crow = (x) => `<div class="card stack cf-rep" data-k="${esc(x.key)}"><div class="row between"><b>${esc(x.label)}</b><span>${esc(String(x.total))} ${esc(T('total'))}</span></div>
    <div class="muted">${x.open} ${esc(T('openn'))} · ${x.resolved} ${esc(T('resolvedn'))} · ${x.closed_no_result} ${esc(T('closednr'))}</div>
    <div class="muted">${x.overdue_now} ${esc(T('overdn'))} · ${x.breached} ${esc(T('breached'))} · ${x.sla_met} ${esc(T('met'))} · ${x.sla_missed} ${esc(T('missed'))}</div>
    <div class="muted">${x.food_safety} ${esc(T('fsn'))} · ${x.repeat} ${esc(T('repn'))}${x.avg_resolve_hours !== null && x.avg_resolve_hours !== undefined ? ` · ${esc(String(x.avg_resolve_hours))} ${esc(T('avgh'))}` : ''}${Number(x.refund_total) ? ` · ${esc(T('refund'))} ${esc(String(x.refund_total))}` : ''}</div></div>`;
  const rrow = (x) => `<div class="card row between cf-repr" data-k="${esc(x.key)}"><span><b>${esc(x.label)}</b> <span class="muted">${esc(String(x.n))} ${esc(T('n'))}</span></span><span>${x.average === null ? '-' : esc(String(x.average))} / 5${x.needs_call ? ` · ${x.needs_call} ${esc(T('needcall'))}` : ''}</span></div>`;
  const rp = D.repeats;
  const reps = rp && rp.off ? `<p class="muted">${esc(T('repoff'))}</p>` : rp && rp.rows ? (rp.rows.length ? rp.rows.map((x) => `<div class="card row between cf-rpt"><span><b>${esc(x.customer_name || '-')}</b> <span class="muted">${esc(x.item_name || '')}</span></span><span>${x.complaints}${x.open ? ` (${x.open} ${esc(T('openn'))})` : ''}</span></div>`).join('') : `<p class="muted">${esc(T('repnone'))}</p>`) : '';
  return `${form}<h3>${esc(T('rep_c'))} · ${esc(String(p.totals.complaints))}</h3>${p.complaints.map(crow).join('') || `<p class="muted">${esc(T('none_c'))}</p>`}
    <h3>${esc(T('rep_r'))} · ${esc(String(p.totals.ratings))}${p.totals.average_rating !== null ? ' · ' + esc(String(p.totals.average_rating)) + ' / 5' : ''}</h3>${p.note ? `<p class="muted">${esc(p.note)}</p>` : ''}${p.ratings.map(rrow).join('')}
    ${rp ? `<h3>${esc(T('repeats'))}</h3>${reps}` : ''}`;
}
function draw() {
  const el = $('#cf_body'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p>${esc(T(D.err))}</p></div>`; return; }
  const tabs = [['c', 'tabc'], ['r', 'tabr'], ['p', 'tabp']].map(([k, l]) => `<button type="button" class="${D.tab === k ? 'on' : ''}" role="tab" aria-selected="${D.tab === k}" data-act="cf_tab" data-t="${k}">${esc(T(l))}</button>`).join('');
  el.innerHTML = `${stripHTML()}<div class="tabs" role="tablist">${tabs}</div>${D.tab === 'c' ? complaintsHTML() : D.tab === 'r' ? ratingsHTML() : repHTML()}`;
}
async function refresh(all) {
  try {
    if (all !== false) { D.cnt = await rpc('_crmh_counts'); }
    if (D.tab === 'c' && D.set && D.set.on) await loadList();
    if (D.tab === 'r' && D.fset && D.fset.on) await loadRatings();
    if (D.tab !== 'r' && D.fset && D.fset.on && !D.rat) { try { await loadRatings(); } catch (e) { /* no right to see ratings */ } }
  } catch (e) { fail2(e); }
  draw();
}

/* ---------- a small form sheet: fields -> values -> a callback ---------- */
function ask(title, fields, onGo, goLabel) {
  D.pend = { fields, onGo };
  const f = fields.map((x) => {
    const lab_ = `<label for="cfa_${x.id}">${esc(x.label)}</label>`;
    if (x.type === 'select') return `<div>${lab_}<select id="cfa_${x.id}">${(x.options || []).map((o) => opt(o[0], o[1], x.value)).join('')}</select></div>`;
    if (x.type === 'area') return `<div>${lab_}<textarea id="cfa_${x.id}" rows="3" maxlength="${x.max || 1000}">${esc(x.value || '')}</textarea></div>`;
    if (x.type === 'check') return `<label class="row"><input type="checkbox" id="cfa_${x.id}" ${x.value ? 'checked' : ''}> ${esc(x.label)}</label>`;
    if (x.type === 'html') return x.html;
    return `<div>${lab_}<input id="cfa_${x.id}" autocomplete="off" value="${esc(x.value || '')}" ${x.mode ? `inputmode="${x.mode}"` : ''}></div>`;
  }).join('');
  openSheet(`<h2>${esc(title)}</h2><div class="stack" id="cf_ask">${f}<div class="row"><button type="button" class="btn" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="btn primary" id="cf_ask_go" data-act="cf_ask_go">${esc(goLabel || T('save'))}</button></div></div>`);
}
const val = (id) => { const e = $('#cfa_' + id); return e ? (e.type === 'checkbox' ? e.checked : e.value.trim()) : ''; };
const OPT = (arr) => (arr || []).map((x) => [x.code, x.label]);

/* ---------- complaint detail ---------- */
async function openDetail(id) {
  let g; try { g = await rpc('_crmh_complaint_get', { p_id: id }); } catch (e) { return fail2(e); }
  const c = g.complaint, m = g.can_manage, fin = c.status === 'closed' || c.status === 'closed_no_resolution';
  const b = (act, label, extra = '') => `<button type="button" class="btn" data-act="${act}" data-id="${esc(c.id)}" ${extra}>${esc(label)}</button>`;
  const acts = [];
  if (!fin) {
    if (m || c.owner_user === (S.ctx && S.ctx.profile && S.ctx.profile.id)) {
      if (c.status === 'open') acts.push(b('cf_start', T('start')));
      if (c.status === 'open' || c.status === 'in_progress') acts.push(b('cf_resolve', T('resolve')));
    }
    if (m) {
      if (c.status === 'resolved') acts.push(b('cf_close', T('close')), b('cf_reopen', T('reopen')));
      if (c.status === 'open' || c.status === 'in_progress') acts.push(b('cf_closenr', T('closenr')));
      acts.push(b('cf_contact', T('contact')), b('cf_note', T('note')), b('cf_sev', T('sevchg')));
      acts.push(c.owner_user ? b('cf_unassign', T('unassign')) : b('cf_assign', T('assignme')));
    }
  }
  const trail = (g.events || []).slice(-8).reverse().map((e) => `<div class="muted cf-ev">${esc(dt(e.at))} · ${esc(e.kind)}${e.to ? ' → ' + esc(e.to) : ''}${e.note ? ' · ' + esc(e.note) : ''}</div>`).join('');
  const rets = (g.returns || []).map((r) => `<div class="row between cf-ret"><span>${esc(T('value'))} ${esc(String(r.amount))}</span><span class="muted">${esc(dt(r.at))}</span></div>`).join('');
  const prev = (g.earlier_by_same_customer || []).map((p) => `<div class="muted">#${esc(String(p.ticket_no))} · ${esc(dt(p.at))} · ${esc(T('s_' + p.status))}</div>`).join('');
  const hint = g.return_hint
    ? `<div class="card stack" id="cf_retbox"><b>${esc(T('retblock'))}</b><p class="muted">${esc(T('retnote'))}</p>
       <div class="row wrap" style="gap:6px">${B.saleReturn ? `<button type="button" class="btn" data-act="cf_openret" data-sale="${esc(g.return_hint.sale_id)}">${esc(T('openret'))}</button>` : ''}${m && !fin ? b('cf_linkret', T('linkret')) : ''}</div>${rets ? `<b>${esc(T('linked'))}</b>${rets}` : ''}</div>`
    : `<p class="muted">${esc(T('norcpt'))}</p>`;
  openSheet(`<h2>#${esc(String(c.ticket_no))} · ${esc(c.category_label || c.category)}</h2><div class="stack" id="cf_detail" data-id="${esc(c.id)}" data-status="${esc(c.status)}">
    <div class="row wrap" style="gap:6px"><span class="chip ${SEVCHIP[c.severity] || ''}">${esc(T('sev_' + c.severity))}</span><span class="chip ${SLACHIP[c.sla_state] || ''}">${esc(slaText(c))}</span><span class="chip">${esc(T('s_' + c.status))}</span>${c.food_safety ? `<span class="chip warn">${esc(T('foodsafety'))}</span>` : ''}${c.repeat_flag ? `<span class="chip warn">${esc(T('repeat'))}</span>` : ''}</div>
    <p>${esc(c.description)}</p>
    <div class="muted">${esc([c.location, c.item_name].filter(Boolean).join(' · '))}</div>
    <div class="muted">${esc(T('customer'))}: ${esc([c.customer_name, c.customer_phone].filter(Boolean).join(' · ') || '-')}</div>
    <div class="muted">${esc(T('owner'))}: ${esc(c.owner_name || T('noowner'))} · ${esc(T('logged'))} ${esc(dt(c.created_at))}${c.due_at ? ` · ${esc(T('due'))} ${esc(dt(c.due_at))}` : ''}</div>
    ${c.resolution_note ? `<div>${esc(c.resolution_type)}: ${esc(c.resolution_note)}</div>` : ''}
    ${acts.length ? `<div class="row wrap" id="cf_acts" style="gap:6px">${acts.join('')}</div>` : ''}${hint}
    ${prev ? `<b>${esc(T('earlier'))}</b>${prev}` : ''}<b>${esc(T('trail'))}</b>${trail}</div>`);
}
async function doMove(id, to, args) {
  try { await rpc('_crmh_complaint_move', { p_id: id, p_to: to, p_note: args.note || null, p_resolution: args.res || null, p_close_reason: args.reason || null }); closeSheet(); toast(T('saved')); await refresh(); }
  catch (e) { fail2(e); }
}
async function findSale() {
  const loc = Number(val('loc') || (locs()[0] || {}).id), n = val('rcpt'); D.sale = null;
  if (!n || !loc) return;
  const r = await sb.from('sales').select('id,receipt,location_id,lines').eq('location_id', loc).eq('receipt', Number(n)).limit(1);
  const s = r.data && r.data[0]; if (!s) return toast(T('notfound'));
  D.sale = s; toast(T('found'));
  const items = (Array.isArray(s.lines) ? s.lines : []).filter((l) => l.item_id).map((l) => [l.item_id, l.name || l.item_id]);
  const el = $('#cfa_item'); if (el) el.innerHTML = opt('', T('choose'), '') + items.map((o) => opt(o[0], o[1], '')).join('');
}

Object.assign(H, {
  cf_tab: async (a) => { D.tab = a.dataset.t; if (D.tab === 'p' && !D.rep) { try { await loadReport(); } catch (e) { fail2(e); } } draw(); if (D.tab !== 'p') await refresh(false); },
  cf_filt: async (a) => { D.filt = a.dataset.k; D.rows = null; draw(); await refresh(false); },
  cf_open: (a) => openDetail(a.dataset.id),
  cf_new: () => {
    const ls = locs(), set = D.set;
    ask(T('new_c'), [
      ls.length > 1 ? { id: 'loc', label: T('outlet'), type: 'select', options: ls.map((l) => [l.id, lname(l)]), value: ls[0].id } : { id: 'loc', label: T('outlet'), type: 'html', html: `<input type="hidden" id="cfa_loc" value="${esc(String((ls[0] || {}).id || ''))}">` },
      { id: 'cat', label: T('category'), type: 'select', options: [['', T('choose')]].concat(OPT(set.categories)) },
      { id: 'desc', label: T('desc'), type: 'area' },
      { id: 'more', label: T('more'), type: 'html', html: `<details id="cf_more"><summary>${esc(T('more'))}</summary><div class="stack" style="margin-top:8px">
        <div><label for="cfa_sev">${esc(T('severity'))}</label><select id="cfa_sev">${['low', 'medium', 'high', 'critical'].map((k) => opt(k, T('sev_' + k), 'medium')).join('')}</select></div>
        <label class="row"><input type="checkbox" id="cfa_fs"> ${esc(T('fsbox'))}</label>
        <div><label for="cfa_rcpt">${esc(T('receipt'))}</label><div class="row"><input id="cfa_rcpt" inputmode="numeric" autocomplete="off"><button type="button" class="btn" data-act="cf_find">${esc(T('find'))}</button></div></div>
        <div><label for="cfa_item">${esc(T('item'))}</label><select id="cfa_item">${opt('', T('choose'), '')}</select></div>
        <div><label for="cfa_phone">${esc(T('phone'))}</label><input id="cfa_phone" inputmode="tel" autocomplete="off"></div></div></details>` },
    ], async () => {
      const loc = Number(val('loc')), cat = val('cat'), desc = val('desc');
      if (!loc) return toast(T('needloc')); if (!cat) return toast(T('needcat')); if (desc.length < 3) return toast(T('needdesc'));
      const p = { location_id: loc, category: cat, severity: val('sev') || 'medium', food_safety: !!val('fs'), description: desc };
      if (D.sale && String(D.sale.receipt) === val('rcpt') && D.sale.location_id === loc) p.sale_id = D.sale.id;
      if (val('item') && p.sale_id) p.item_id = val('item'); if (val('phone')) p.customer_phone = val('phone');
      try { const r = await rpc('_crmh_complaint_save', { p_client: crypto.randomUUID ? crypto.randomUUID() : null, p }); closeSheet(); toast(T('saved') + ' #' + r.ticket_no); D.filt = 'active'; await refresh(); } catch (e) { fail2(e); }
    });
    D.sale = null;
  },
  cf_find: () => findSale().catch(fail2),
  cf_ask_go: async () => { const p = D.pend; if (p && p.onGo) await p.onGo(); },
  cf_start: (a) => doMove(a.dataset.id, 'in_progress', { note: null }),
  cf_resolve: (a) => ask(T('resolve'), [{ id: 'res', label: T('result'), type: 'select', options: [['', T('choose')]].concat(OPT(D.set.resolutions)) }, { id: 'note', label: T('notefld'), type: 'area' }],
    () => { if (!val('res') || val('note').length < 3) return toast(ERR.resolution_required); return doMove(a.dataset.id, 'resolved', { note: val('note'), res: val('res') }); }),
  cf_close: (a) => doMove(a.dataset.id, 'closed', { note: null }),
  cf_closenr: (a) => ask(T('closenr'), [{ id: 'reason', label: T('reason'), type: 'select', options: [['', T('choose')]].concat(OPT(D.set.close_reasons)) }, { id: 'note', label: T('notefld'), type: 'area' }],
    () => { if (!val('reason') || val('note').length < 3) return toast(ERR.reason_required); return doMove(a.dataset.id, 'closed_no_resolution', { note: val('note'), reason: val('reason') }); }),
  cf_reopen: (a) => ask(T('reopen'), [{ id: 'note', label: T('why'), type: 'area' }], () => { if (val('note').length < 3) return toast(ERR.note_required); return doMove(a.dataset.id, 'in_progress', { note: val('note') }); }),
  cf_note: (a) => ask(T('note'), [{ id: 'note', label: T('notefld'), type: 'area' }], async () => { try { await rpc('_crmh_complaint_note', { p_id: a.dataset.id, p_kind: 'note', p_body: val('note') }); closeSheet(); toast(T('saved')); } catch (e) { fail2(e); } }),
  cf_contact: (a) => ask(T('contact'), [{ id: 'note', label: T('callnote'), type: 'area' }], async () => { try { await rpc('_crmh_complaint_note', { p_id: a.dataset.id, p_kind: 'contact', p_body: val('note') }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } }),
  cf_sev: (a) => ask(T('sevchg'), [{ id: 'sev', label: T('severity'), type: 'select', options: ['low', 'medium', 'high', 'critical'].map((k) => [k, T('sev_' + k)]), value: 'medium' }, { id: 'note', label: T('why'), type: 'area' }],
    async () => { try { await rpc('_crmh_complaint_severity_set', { p_id: a.dataset.id, p_severity: val('sev'), p_note: val('note') }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } }),
  cf_assign: async (a) => { try { await rpc('_crmh_complaint_assign', { p_id: a.dataset.id, p_user: S.ctx.profile.id, p_note: null }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } },
  cf_unassign: async (a) => { try { await rpc('_crmh_complaint_assign', { p_id: a.dataset.id, p_user: null, p_note: null }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } },
  cf_openret: (a) => { closeSheet(); if (B.saleReturn) B.saleReturn.open(a.dataset.sale); },
  cf_linkret: async (a) => {
    const id = a.dataset.id; let g; try { g = await rpc('_crmh_complaint_get', { p_id: id }); const sr = await rpc('sale_returns_for', { p_sale: g.return_hint.sale_id }); D.rets = (sr.returns || []).filter((r) => r.status === 'done'); } catch (e) { return fail2(e); }
    const linked = new Set((g.returns || []).map((r) => r.return_id));
    const rows = D.rets.filter((r) => !linked.has(r.id)).map((r) => `<div class="row between"><span>${esc(T('value'))} ${esc(String(r.amount))} <span class="muted">${esc(dt(r.at))}</span></span><button type="button" class="btn" data-act="cf_linkgo" data-id="${esc(id)}" data-ret="${esc(r.id)}">${esc(T('linkret'))}</button></div>`).join('');
    openSheet(`<h2>${esc(T('linkret'))}</h2><div class="stack" id="cf_rets">${rows || `<p class="muted">${esc(T('noret'))}</p>`}</div>`);
  },
  cf_linkgo: async (a) => { try { await rpc('_crmh_complaint_link_return', { p_id: a.dataset.id, p_return: a.dataset.ret }); closeSheet(); toast(T('saved')); await openDetail(a.dataset.id); } catch (e) { fail2(e); } },
  cf_scan: async () => { try { const r = await rpc('_crmh_sla_scan', { p_dry: false }); toast(r.marked ? `${T('scanned')}: ${r.marked}` : T('nothing')); await refresh(); } catch (e) { fail2(e); } },
  cf_newr: () => {
    const ls = locs();
    ask(T('new_r'), [
      ls.length > 1 ? { id: 'loc', label: T('outlet'), type: 'select', options: ls.map((l) => [l.id, lname(l)]), value: ls[0].id } : { id: 'loc', label: T('outlet'), type: 'html', html: `<input type="hidden" id="cfa_loc" value="${esc(String((ls[0] || {}).id || ''))}">` },
      { id: 'rcpt', label: E('Receipt number'), type: 'text', mode: 'numeric' },
      { id: 'st', label: T('stars'), type: 'select', options: [5, 4, 3, 2, 1].map((n) => [n, n + ' ' + stars(n)]), value: 5 },
      { id: 'cm', label: T('comment'), type: 'area', max: 500 },
      { id: 'ch', label: T('channel'), type: 'select', options: ['counter', 'phone', 'message', 'other'].map((k) => [k, T('ch_' + k)]) },
    ], async () => {
      const loc = Number(val('loc')), n = val('rcpt'); if (!n) return toast(ERR.sale_or_order_required);
      try {
        const r = await sb.from('sales').select('id').eq('location_id', loc).eq('receipt', Number(n)).limit(1); const s = r.data && r.data[0]; if (!s) return toast(T('notfound'));
        await rpc('_crmh_feedback_add', { p_client: crypto.randomUUID ? crypto.randomUUID() : null, p: { sale_id: s.id, rating: Number(val('st')), comment: val('cm') || null, channel: val('ch') } });
        closeSheet(); toast(T('saved')); await refresh();
      } catch (e) { fail2(e); }
    });
  },
  cf_calldone: (a) => ask(T('calldone'), [{ id: 'note', label: T('callnote'), type: 'area', max: 500 }], async () => { try { await rpc('_crmh_feedback_followup', { p_id: a.dataset.id, p_note: val('note') }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } }),
  cf_tocomplaint: (a) => ask(T('tocomplaint'), [{ id: 'cat', label: T('category'), type: 'select', options: [['', T('choose')]].concat(OPT(D.set.categories)) }, { id: 'sev', label: T('severity'), type: 'select', options: ['low', 'medium', 'high', 'critical'].map((k) => [k, T('sev_' + k)]), value: 'medium' }],
    async () => { if (!val('cat')) return toast(T('needcat')); try { await rpc('_crmh_feedback_to_complaint', { p_id: a.dataset.id, p: { category: val('cat'), severity: val('sev') } }); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { fail2(e); } }),
  cf_run: async () => { D.rf = val0('cf_from'); D.rt = val0('cf_to'); D.by = val0('cf_by') || 'outlet'; try { await loadReport(); } catch (e) { fail2(e); } draw(); },
});
const val0 = (id) => { const e = $('#' + id); return e ? e.value : ''; };
document.addEventListener('change', async (e) => {
  if (e.target && e.target.id === 'cf_loc') { D.loc = e.target.value; D.rows = null; D.rat = null; if (D.tab === 'p') { try { await loadReport(); } catch (x) { fail2(x); } draw(); } else { draw(); await refresh(false); } }
});

async function view() {
  shell(T('title'), '<div id="cf_body"><p class="muted">…</p></div>', true);
  try { await loadBase(); } catch (e) { return fail2(e); }
  draw();
  if (!D.err) { D.rows = null; D.rat = null; D.rep = null; await refresh(false); }
}
window.BOS = window.BOS || B;
window.BOS.crmFeedback = { open: () => { location.hash = '#/crmfeedback'; }, version: 1 };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmfeedback: view });
})();
