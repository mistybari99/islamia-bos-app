/* Islamia BOS · RPT-C2 shared report helper (BOS.c2ui): date / place filters, summary tiles, notes, tables with drill-down and CSV, one page factory.
   Used by orderreports.js (orders and delivery), custinsight.js (customers) and staffreports.js (staff). Reads only: every figure comes from a server function (phases 445-457); the page never computes money.
   A missing figure (null) is shown as "not captured" - never as 0. Labels are English (owner rule for new screens). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm, S, openSheet } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const monthStart = () => today().slice(0, 8) + '01';
const NOTES = {
  module_off: 'Module not switched on: the Online orders switch is off, so new app orders are not being captured. Paper sheets and anything already recorded are still shown.',
  sources_not_merged: 'App orders and paper sheets (05-1, 23-1) are listed apart and never added together. An order written on paper and also typed in the app shows once in each.',
  cost_hidden: 'Cost figures need the cost right, so they are empty for your access.', mobile_hidden: 'Mobile numbers are hidden for your access.',
  old_list_balance_differs: 'The Online orders list still shows total minus advance for every order, so a delivered or cancelled order can look owed there. This report shows what is really still due.',
  open_without_date_not_judged: 'Open orders with no promised date cannot be judged late or on time; they are counted apart.', paper_delivery_time_not_captured: 'The paper sheet has no delivery time, so paper orders are not part of the on-time percentage.',
  rate_formulas: 'Rate of closed = delivered / (delivered + cancelled). Rate of all = delivered / all orders taken. Open orders are not counted as failures.', refund_switch_off: 'The refund switch is off: a refund chosen on a cancelled order writes no money record (as before).',
  cost_is_information_not_posted: 'A delivery cost is information for costing. It does not post to the books; the payment is entered as an expense as usual.', paper_20_6_no_cost_side: 'Paper ledger 23-1 shows the delivery charge only; it has no cost side.',
  run_cost_split_by_quantity: 'A production run cost is split by the quantity given to each order. A run with several orders and no quantity written cannot be split, so it shows "not captured".', profit_only_when_every_cost_known: 'A profit appears only when the goods cost and (for home or courier orders) the delivery cost are both known.',
  linked_production_not_subtracted: 'The linked production cost is shown for comparison only; the goods cost is already in the cost of the sale.', risk_rule_not_set: 'The risk rule is not set (Settings: watch days and high-risk days). Ages and amounts are shown; the risk column says "rule not set".',
  no_default_terms: 'No default credit days are set, so a customer without days of their own has no terms and is not called overdue.', same_oldest_first_rule_as_dues_list: 'Payments and return credits settle the oldest amount first, the same rule as the dues list; the balance is the dues list figure.',
  margin_only_where_cost_known: 'Margin counts only the sales whose cost is fully known; the number of such sales is shown.', complaints_matched_by_phone: 'Complaints are matched to a customer by the phone number written on the 32-1 sheet.',
  paper_20_3_phone_optional: 'The phone box on form 32-1 is optional; sheets without a phone, or with a phone that is not a customer, are counted apart.', matched_by_mobile: 'Orders are matched to customers by mobile number.',
  app_days_only: 'This report reads the app day records (punches). Paper sheets 19-1 are not added.', calendar_days_without_record_counted_apart: 'Calendar days with no attendance record at all are counted apart; they are not assumed present or absent.',
  variance_only_days_with_a_shift: 'Scheduled time and variance count only days that have a shift; days without a shift are counted apart.', paper_02_1_not_included: 'Paper attendance sheets 19-1 exist for this period; their data is not included here.',
  reports_t3_t4_l1_use_this_figure: 'The staff-cost and profit reports (T3, T4, L1) use the "Reports use" column.', nothing_here_changes_a_report: 'Looking at this changes no report. The salary source is chosen on the Profit check screen.', switch_in_profit_check: '',
  same_flag_as_hub_cash_short_over: 'Short / over is the flag each 06-1 sheet carries, the same figure as the Reports hub.', case_status_shown: 'The decision on each shortage case (open, approved, rejected, void) is shown beside the sheet.',
  cashier_box_new_on_14_1: 'The Cashier box is new on form 06-1; older sheets have none.', cashier_not_written_on_some_sheets: 'Some sheets have no cashier written. They are listed apart and not given to anyone.',
  hours_from_app_day_records: 'Labour hours are the worked minutes of present, late and half-day records in the app.', returns_shown_apart: 'Sales are shown with returns apart; sales per hour uses sales minus returns.',
  per_hour_only_where_hours_exist: 'Sales per hour is shown only where labour hours exist; punch coverage is always beside it.', per_hour_only_runs_with_a_crew: 'Output per hour counts only runs that have a crew; runs without a crew are counted apart.',
  units_are_the_run_output_units: 'Output is in the unit of each finished product.', runs_without_crew_counted_apart: '', all_time: '',
};
const noteText = (c) => (c in NOTES ? NOTES[c] : String(c).replace(/_/g, ' '));
const noteHTML = (notes) => { const n = (notes || []).map(noteText).filter(Boolean); return n.length ? `<div class="notice info c2-notes">${n.map((t) => `<p style="margin:2px 0">${esc(t)}</p>`).join('')}</div>` : ''; };
const NC = 'not captured';
const fmt = {
  money: (v) => (v === null || v === undefined ? null : '৳ ' + (Math.round(Number(v) * 100) / 100).toLocaleString('en-US')), int: (v) => (v === null || v === undefined ? null : String(Math.round(Number(v)))),
  num: (v) => (v === null || v === undefined ? null : String(Math.round(Number(v) * 100) / 100)), pct: (v) => (v === null || v === undefined ? null : Number(v) + '%'), text: (v) => (v === null || v === undefined || v === '' ? null : String(v)),
  date: (v) => (v ? String(v).slice(0, 10) : null), bool: (v) => (v === null || v === undefined ? null : v ? 'Yes' : 'No'), min: (v) => (v === null || v === undefined ? null : (Number(v) < 0 ? '-' : '') + Math.floor(Math.abs(Number(v)) / 60) + 'h ' + (Math.abs(Number(v)) % 60) + 'm'),
  time: (v) => (v ? String(v).slice(0, 5) : null), ts: (v) => (v ? String(v).replace('T', ' ').slice(0, 16) : null),
};
const cell = (c, r) => { const raw = c.get ? c.get(r) : r[c.k]; const f = (fmt[c.f || 'text'] || fmt.text)(raw); const w = c.words && f !== null ? (c.words[raw] || f) : f; return w === null ? `<span class="muted" title="${esc(NC)}">—</span>` : esc(w); };
const rawCell = (c, r) => { const raw = c.get ? c.get(r) : r[c.k]; if (raw === null || raw === undefined) return ''; return c.words && c.words[raw] ? c.words[raw] : (fmt[c.f || 'text'] || fmt.text)(raw) || ''; };
const REG = {};   // table id -> {cols, rows, drill}
let seq = 0;
function tableHTML(t) {
  const id = 'c2t' + (++seq); REG[id] = t;
  if (!t.rows || !t.rows.length) return `<div class="card stack">${t.title ? `<b>${esc(t.title)}</b>` : ''}<p class="muted">${esc(t.empty || 'Nothing in this range.')}</p></div>`;
  const rows = t.rows.slice(0, t.max || 300);
  return `<div class="card stack" data-c2t="${id}">${t.title ? `<div class="row between"><b>${esc(t.title)}</b><button class="mini" data-act="c2_csv" data-t="${id}">CSV</button></div>` : `<div class="row" style="justify-content:flex-end"><button class="mini" data-act="c2_csv" data-t="${id}">CSV</button></div>`}
    <div class="c2-wrap"><table class="c2-tbl"><thead><tr>${t.cols.map((c) => `<th class="${/money|int|num|pct|min/.test(c.f || '') ? 'n' : ''}">${esc(c.h)}</th>`).join('')}</tr></thead>
    <tbody>${rows.map((r, i) => `<tr ${t.drill ? `class="c2-row" data-act="c2_drill" data-t="${id}" data-i="${i}"` : ''}>${t.cols.map((c) => `<td class="${/money|int|num|pct|min/.test(c.f || '') ? 'n' : ''}">${cell(c, r)}</td>`).join('')}</tr>`).join('')}</tbody>
    ${t.total ? `<tfoot><tr>${t.cols.map((c, i) => `<td class="${/money|int|num|pct|min/.test(c.f || '') ? 'n' : ''}"><b>${i === 0 ? esc(t.total.label || 'Total') : t.total.vals && t.total.vals[c.k] !== undefined ? cell(c, { [c.k]: t.total.vals[c.k] }) : ''}</b></td>`).join('')}</tr></tfoot>` : ''}</table></div>
    ${t.rows.length > rows.length ? `<p class="muted">${esc('Showing the first ' + rows.length + ' of ' + t.rows.length + ' rows; the CSV has all of them.')}</p>` : ''}</div>`;
}
const csvEsc = (v) => { let s = String(v === null || v === undefined ? '' : v); if (/^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; /* spreadsheet formula guard */ return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
function csvText(t) { return [t.cols.map((c) => csvEsc(c.h)).join(',')].concat(t.rows.map((r) => t.cols.map((c) => csvEsc(rawCell(c, r))).join(','))).join('\r\n'); }
function csvDownload(name, text) {
  try { const blob = new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' }); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name + '.csv'; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500); window.__c2csv = { name, text }; }
  catch (e) { window.__c2csv = { name, text }; }
}
const tiles = (arr) => `<div class="c2-tiles">${arr.filter((x) => x).map(([l, v, cls]) => `<div class="card c2-tile ${cls || ''}"><div class="muted">${esc(l)}</div><b>${v === null || v === undefined || v === '' ? `<span class="muted" title="${esc(NC)}">—</span>` : esc(v)}</b></div>`).join('')}</div>`;
const locOpts = (sel) => { const all = (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : (B.ENV && B.ENV.locs) || []); const mine = S.ctx.is_owner || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id));
  return `<option value="">All my places</option>` + mine.map((l) => `<option value="${l.id}" ${String(sel) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join(''); };
function filterHTML(def, f, prefix) {
  const k = def.filters || [];
  return `<div class="card stack c2-filters">${k.includes('range') ? `<div class="row wrap"><label>From <input type="date" id="c2_from" value="${esc(f.from)}"></label><label>To <input type="date" id="c2_to" value="${esc(f.to)}"></label></div>` : ''}
    ${k.includes('asof') ? `<label>As of <input type="date" id="c2_asof" value="${esc(f.asof || '')}" max="${esc(today())}"></label>` : ''}
    ${k.includes('loc') ? `<label>Place <select id="c2_loc">${locOpts(f.loc)}</select></label>` : ''}
    ${(def.extra || []).map((x) => x.html(f)).join('')}
    ${k.includes('search') ? `<label>Search <input id="c2_search" autocomplete="off" value="${esc(f.search || '')}" placeholder="name or mobile"></label>` : ''}
    <button class="btn primary full" data-act="${prefix || 'c2'}_run">Show</button></div>`;
}
function readFilters(def, f) {
  const g = (id) => { const el = $('#' + id); return el ? el.value : undefined; };
  if (g('c2_from')) f.from = g('c2_from'); if (g('c2_to')) f.to = g('c2_to'); if ($('#c2_asof')) f.asof = g('c2_asof') || ''; if ($('#c2_loc')) f.loc = g('c2_loc'); if ($('#c2_search')) f.search = g('c2_search');
  (def.extra || []).forEach((x) => x.read && x.read(f, g));
}
const ERRW = { 'not allowed': 'You do not have access to this report.', bad_date: 'The dates are not valid.', bad_filter: 'That filter is not valid.', module_off: 'Module not switched on.' };
const errText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERRW).find((x) => m.includes(x)); return k ? ERRW[k] : m || 'error'; };
const rpc = async (fn, a) => { const r = await sb.rpc(fn, a); if (r.error) { const e = new Error(r.error.message); e.rpc = fn; throw e; } return r.data; };
const STYLE = '.c2-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}.c2-tbl{border-collapse:collapse;font-size:.82rem;min-width:100%}.c2-tbl th,.c2-tbl td{padding:4px 6px;border-bottom:1px solid rgba(128,128,128,.25);text-align:left;vertical-align:top}.c2-tbl th.n,.c2-tbl td.n{text-align:right;white-space:nowrap}'
  + '.c2-row{cursor:pointer}.c2-tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px}.c2-tile{padding:8px}.c2-tabs{display:flex;gap:6px;overflow-x:auto;padding-bottom:4px}.c2-tabs button{white-space:nowrap}.c2-filters label{display:block}';
function ensureStyle() { if (!document.getElementById('c2-style')) { const s = document.createElement('style'); s.id = 'c2-style'; s.textContent = STYLE; document.head.appendChild(s); } }

/* page factory: cfg = { route, title, intro, tabs: [ { id, label, filters, extra, run(f) -> result, render(res, f) -> html, init(f) } ] , prefix } */
function makePage(cfg) {
  const ST = { tab: cfg.tabs[0].id, f: {}, res: {} };
  const def = () => cfg.tabs.find((t) => t.id === ST.tab);
  const fOf = () => { if (!ST.f[ST.tab]) { const d = def(); ST.f[ST.tab] = Object.assign({ from: monthStart(), to: today(), loc: '', search: '', asof: '' }, d.init ? d.init() : {}); } return ST.f[ST.tab]; };
  async function draw() {
    const d = def(), f = fOf(); ensureStyle();
    const el = $('#c2_body'); if (!el) return;
    el.innerHTML = `<div class="c2-tabs" role="tablist">${cfg.tabs.map((t) => `<button role="tab" class="tog ${t.id === ST.tab ? 'on' : ''}" aria-selected="${t.id === ST.tab}" data-act="${cfg.prefix}_tab" data-v="${t.id}">${esc(t.label)}</button>`).join('')}</div>
      ${d.intro ? `<p class="muted">${esc(d.intro)}</p>` : ''}${filterHTML(d, f, cfg.prefix)}<div id="c2_out"><p class="muted">Press Show.</p></div>`;
    if (ST.res[ST.tab]) $('#c2_out').innerHTML = ST.res[ST.tab];
  }
  async function run() {
    const d = def(), f = fOf(); readFilters(d, f);
    const out = $('#c2_out'); if (!out) return; out.innerHTML = '<p class="muted">…</p>';
    try { const res = await d.run(f); window.__c2last = res; const html = (res.notes ? noteHTML(res.notes) : '') + d.render(res, f); ST.res[ST.tab] = html; if ($('#c2_out')) $('#c2_out').innerHTML = html; }
    catch (e) { out.innerHTML = `<div class="notice bad">${esc(errText(e))}</div>`; }
  }
  Object.assign(H, {
    [cfg.prefix + '_tab']: (a) => { ST.tab = a.dataset.v; draw(); }, [cfg.prefix + '_run']: () => run(),
  });
  cfg._ST = ST;
  return async function view() {
    if (B.loadStatic) await B.loadStatic();
    shell(cfg.title, `<p class="muted">${esc(cfg.intro || '')}</p><div id="c2_body"></div>`, true);
    ensureStyle(); await draw();
    const hash = (location.hash.split('?')[1] || ''); const m = /tab=([a-z_]+)/.exec(hash); if (m && cfg.tabs.some((t) => t.id === m[1])) { ST.tab = m[1]; await draw(); }
  };
}
Object.assign(H, {
  c2_csv: (a) => { const t = REG[a.dataset.t]; if (t) csvDownload((t.name || 'report') + '-' + today(), csvText(t)); },
  c2_drill: (a) => { const t = REG[a.dataset.t]; if (t && t.drill) t.drill(t.rows[Number(a.dataset.i)]); },
  c2_x: () => {},
});
B.c2ui = { E, L, lab, today, addDays, monthStart, NOTES, noteText, noteHTML, fmt, tableHTML, csvText, csvDownload, tiles, filterHTML, readFilters, makePage, rpc, errText, ensureStyle, esc, locOpts, REG };
// the Reports hub lists one link per screen (the same B.reportLinks list the other report pages use)
B.c2link = (key, route, label, probeFn, probeArgs) => {
  B.reportLinks = B.reportLinks || [];
  B.reportLinks.push({ key, route, label: () => label, allowed: null, check: async () => { const l = B.reportLinks.find((x) => x.key === key); try { const r = await sb.rpc(probeFn, probeArgs()); l.allowed = !(r && r.error && /not allowed/.test(r.error.message || '')); } catch (e) { l.allowed = false; } } });
};
})();
