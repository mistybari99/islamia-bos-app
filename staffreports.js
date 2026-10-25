/* Islamia BOS · Staff reports (#/staffreports): #142 attendance summary for a period, #147 overtime and late variance, #148 sales per labour hour (with punch coverage), #149 production output per labour hour,
   #150 cashier-wise cash variance (cashier and shift on form 06-1), and the salary-basis notice for the staff-cost reports. Server: supabase/phase455.sql .. phase457.sql.
   Also BOS.c2prod: the crew-and-hours / for-order fields on the production sheet (recipes.js calls it). Reads only apart from those two captures. Missing = "not captured", never 0. English labels (owner rule). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const C = B.c2ui;
if (!C) { console.warn('staffreports: c2rpt.js is not loaded'); return; }
const { sb, esc, toast, H, openSheet, nm } = A;
const { fmt, tableHTML, tiles, rpc, makePage } = C;
const $ = (s, el = document) => el.querySelector(s);
const mk = (k, h, f, extra) => Object.assign({ k, h, f }, extra || {});
const locArg = (f) => (f.loc === '' || f.loc === undefined ? null : Number(f.loc));
const ename = (x) => x.name_en || x.name_bn;
const SHIFT = { full: 'Full day', s1: 'Shift 1', s2: 'Shift 2', not_written: 'Not written' };
const attRun = (f) => rpc('c2_att_period_summary', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_employee: null });
const personDays = async (x) => { let d; try { d = await rpc('c2_att_person_days', { p_employee: x.employee_id, p_from: C.lastRange.from, p_to: C.lastRange.to }); } catch (e) { return toast(C.errText(e)); }
  openSheet(`<div class="stack"><h3>${esc(ename(x))}</h3>${tableHTML({ name: 'person-days', rows: d.rows, cols: [mk('day', 'Day', 'date'), mk('status', 'Status', 'text'), mk('first_in', 'In', 'ts'), mk('last_out', 'Out', 'ts'), mk('worked_minutes', 'Worked', 'min'), mk('scheduled_minutes', 'Scheduled', 'min'), mk('variance_minutes', 'Variance', 'min'),
    mk('late_minutes', 'Late min', 'int'), mk('ot_minutes', 'OT min', 'int'), mk('ot_approved', 'OT approved', 'bool'), mk('single_punch', 'One punch', 'bool'), mk('source', 'Source', 'text')] })}</div>`); };
C.lastRange = { from: C.monthStart(), to: C.today() };
const TABS = [
  { id: 'attendance', label: 'Attendance', intro: '#142 · Days by status, late, worked and overtime for each person, from the app day records. Calendar days with no record are counted apart.', filters: ['range', 'loc'],
    run: async (f) => { C.lastRange = { from: f.from, to: f.to }; return attRun(f); },
    render: (r) => { const s = r.summary || {}; return tiles([['People', fmt.int(s.people)], ['With no record at all', fmt.int(s.people_with_no_record_at_all)], ['Days with a record', fmt.int(s.days_with_record)], ['Days without a record', fmt.int(s.days_without_record)], ['Late days', fmt.int(s.late_days)], ['Late minutes', fmt.int(s.late_minutes)], ['Absent days', fmt.int(s.absent)], ['Worked', fmt.min(s.worked_minutes)], ['Paper 19-1 sheets (not added)', fmt.int(r.paper_02_1_sheets_in_range)]])
      + tableHTML({ name: 'attendance-summary', rows: r.rows, drill: personDays, cols: [mk('employee_no', 'No', 'text'), mk('name', 'Person', 'text', { get: ename }), mk('present', 'Present', 'int'), mk('late_status', 'Late', 'int'), mk('absent', 'Absent', 'int'), mk('half_day', 'Half day', 'int'), mk('leave', 'Leave', 'int'), mk('unpaid', 'Unpaid', 'int'), mk('off', 'Off', 'int'), mk('holiday', 'Holiday', 'int'),
        mk('days_without_record', 'No record', 'int'), mk('late_days', 'Late days', 'int'), mk('late_minutes', 'Late min', 'int'), mk('worked_minutes', 'Worked', 'min'), mk('single_punch_days', 'One-punch days', 'int'), mk('manual_days', 'Manual days', 'int')] }); } },
  { id: 'variance', label: 'Overtime and variance', intro: '#147 · Worked time against the shift, and overtime waiting for approval. Only days with a shift are compared; days without a shift are counted apart.', filters: ['range', 'loc'],
    run: async (f) => { C.lastRange = { from: f.from, to: f.to }; return attRun(f); },
    render: (r) => { const s = r.summary || {}; return tiles([['Scheduled', fmt.min(s.scheduled_minutes)], ['Worked', fmt.min(s.worked_minutes)], ['Variance (days with a shift)', fmt.min(s.variance_minutes)], ['Overtime', fmt.min(s.ot_minutes)], ['Overtime waiting', fmt.min(s.ot_waiting_minutes)], ['Days without a shift', fmt.int(s.days_without_shift)]])
      + tableHTML({ name: 'ot-variance', rows: r.rows, drill: personDays, cols: [mk('name', 'Person', 'text', { get: ename }), mk('days_with_shift', 'Days with shift', 'int'), mk('days_without_shift', 'Days without shift', 'int'), mk('scheduled_minutes', 'Scheduled', 'min'), mk('worked_minutes', 'Worked', 'min'), mk('variance_minutes', 'Variance', 'min'),
        mk('ot_minutes', 'Overtime', 'min'), mk('ot_approved_minutes', 'OT approved', 'min'), mk('ot_waiting_minutes', 'OT waiting', 'min'), mk('early_leave_minutes', 'Early leave min', 'int')] }); } },
  { id: 'saleshour', label: 'Sales per labour hour', intro: '#148 · Sales against the hours worked at each place. The punch coverage shows how much of the hours is backed by punches.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_sales_per_labour_hour', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; return tiles([['Sales', fmt.money(s.sales)], ['Returns', fmt.money(s.returns)], ['Labour hours', fmt.num(s.labour_hours)], ['Punch coverage', fmt.pct(s.punch_coverage_pct)], ['Sales per hour', fmt.money(s.sales_per_hour)], ['Places with no hours', fmt.int(s.places_without_hours)]])
      + tableHTML({ name: 'sales-per-labour-hour', rows: r.rows, cols: [mk('place', 'Place', 'text', { get: (x) => x.name_en || x.name_bn }), mk('sales', 'Sales', 'money'), mk('returns', 'Returns', 'money'), mk('bills', 'Bills', 'int'), mk('staff_days', 'Staff days', 'int'), mk('labour_hours', 'Labour hours', 'num'), mk('punch_coverage_pct', 'Punch coverage', 'pct'),
        mk('sales_per_hour', 'Sales per hour', 'money'), mk('status', 'Data', 'text', { words: { ok: 'Complete', partial_punches: 'Some days have no punches', no_attendance_records: 'No attendance records', no_hours: 'No hours' } })] }); } },
  { id: 'outhour', label: 'Output per labour hour', intro: '#149 · Finished goods made per crew hour, over the production runs that have a crew written. Runs without a crew are counted apart.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_output_per_labour_hour', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; return tiles([['Runs', fmt.int(s.runs)], ['With a crew', fmt.int(s.runs_with_crew)], ['Without a crew', fmt.int(s.runs_without_crew)], ['Coverage', fmt.pct(s.coverage_pct)], ['Crew hours', fmt.num(s.crew_hours)]])
      + tableHTML({ name: 'output-per-labour-hour', rows: r.rows, cols: [mk('code', 'Item', 'text'), mk('name', 'Name', 'text', { get: ename }), mk('runs', 'Runs', 'int'), mk('runs_with_crew', 'With crew', 'int'), mk('output', 'Output', 'num'), mk('output_with_crew', 'Output (crewed runs)', 'num'), mk('crew_hours', 'Crew hours', 'num'), mk('output_per_labour_hour', 'Output per hour', 'num'), mk('coverage_pct', 'Coverage', 'pct')] }); } },
  { id: 'cashier', label: 'Cashier cash variance', intro: '#150 · Cash short and over from the daily showroom sheet 06-1, by cashier and shift. Sheets with no cashier written are listed apart.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_cashier_variance', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; return tiles([['Sheets', fmt.int(s.sheets)], ['No cashier written', fmt.int(s.sheets_without_cashier)], ['No shift written', fmt.int(s.sheets_without_shift)], ['Short', fmt.money(s.short_amount)], ['Over', fmt.money(s.over_amount)], ['Net', fmt.money(s.net)]])
      + tableHTML({ name: 'cashier-variance', rows: r.rows, cols: [mk('cashier', 'Cashier', 'text', { get: (x) => (x.cashier_written ? (x.cashier_name || x.cashier) : null) }), mk('shift', 'Shift', 'text', { words: SHIFT }), mk('sheets', 'Sheets', 'int'), mk('short_sheets', 'Short', 'int'), mk('over_sheets', 'Over', 'int'), mk('short_amount', 'Short ৳', 'money'), mk('over_amount', 'Over ৳', 'money'),
        mk('net', 'Net', 'money'), mk('worst', 'Worst', 'money'), mk('cases_open', 'Cases open', 'int'), mk('cases_approved', 'Approved', 'int'), mk('cases_rejected', 'Rejected', 'int'), mk('cases_void', 'Void', 'int')] })
      + tableHTML({ name: 'cashier-uncredited', title: 'Sheets with a variance and no cashier written', rows: r.uncredited_sheets_with_a_variance, empty: 'None.', cols: [mk('day', 'Day', 'date'), mk('shift', 'Shift', 'text', { words: SHIFT }), mk('writer', 'Sheet written by', 'text'), mk('variance', 'Variance', 'money'), mk('case_status', 'Case', 'text')] }); } },
  { id: 'salary', label: 'Salary basis', intro: 'Which salary figure the staff-cost and profit reports use, beside the paper 21-1 sheets and the payroll runs. Needs the salary right. Changes nothing.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_salary_basis', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; const BS = { sheets_only: 'Paper 21-1 sheets only', sheets_while_runs_exist: 'Sheets are used although a payroll run exists', runs_first: 'Payroll runs first (sheets only where no run)', none: 'No salary data' };
      return tiles([['Reports use', fmt.money(s.reports_use)], ['Paper 21-1 sheets', fmt.money(s.sheets_02_2)], ['Payroll runs counted', fmt.money(s.runs_counted)], ['Payroll runs paid', fmt.money(s.runs_paid)], ['Months that differ', fmt.int(s.months_with_a_mismatch)], ['Source setting', (r.settings || {}).report_salary_source]])
      + tableHTML({ name: 'salary-basis', rows: r.rows, cols: [mk('month', 'Month', 'date'), mk('reports_use', 'Reports use', 'money'), mk('sheets_02_2', '21-1 sheets', 'money'), mk('runs_counted', 'Runs counted', 'money'), mk('runs_paid', 'Runs paid', 'money'), mk('difference_runs_minus_reports', 'Runs minus reports', 'money'), mk('basis', 'Basis', 'text', { words: BS }), mk('mismatch', 'Differs', 'bool')] }); } },
];
const view = makePage({ route: 'staffreports', prefix: 'sr', title: 'Staff reports', intro: 'Attendance, overtime, sales and output per labour hour, cashier variance and the salary basis. Read only.', tabs: TABS });

/* ----- production sheet fields (called from recipes.js) ----- */
const P = { crew: [], orders: [], pick: [], loc: null, f: null };
async function pf() { if (P.f !== null) return P.f; try { const r = await sb.rpc('c2_orders_features'); P.f = r.error ? false : r.data || false; } catch (e) { P.f = false; } return P.f; }
const crewRow = (i, w) => `<div class="row wrap" data-crew="${i}"><select data-c2crew="emp" data-i="${i}" style="flex:1;min-width:8rem"><option value="">— worker —</option>${P.pick.map((e) => `<option value="${esc(e.employee_id)}" ${e.employee_id === w.emp ? 'selected' : ''}>${esc(e.name_en || e.name_bn)}</option>`).join('')}</select>
  <input data-c2crew="hours" data-i="${i}" inputmode="decimal" placeholder="hours" value="${esc(w.hours)}" style="max-width:4.5rem" aria-label="hours"><button type="button" class="mini" data-act="c2_crew_del" data-i="${i}" aria-label="remove">✕</button></div>`;
const c2prod = {
  async prepare(loc) { P.loc = loc; P.crew = []; P.orders = []; P.pick = []; await pf(); if (!P.f) return; try { const [a, b] = await Promise.all([sb.rpc('c2_crew_pick', { p_loc: loc }), sb.rpc('c2_orders_for_production', { p_loc: null })]); P.pick = a.error ? [] : a.data || []; P.orders = b.error ? [] : (b.data || {}).rows || []; } catch (e) { /* fields stay hidden */ } },
  fieldsHTML() {
    if (!P.f || (!P.pick.length && !P.orders.length)) return '';
    return `<div class="card stack" id="c2_prodbox">${P.pick.length ? `<b>Crew and hours (optional)</b><div id="c2_crew">${P.crew.map((w, i) => crewRow(i, w)).join('')}</div><button type="button" class="mini" data-act="c2_crew_add">+ Worker</button>` : ''}
      ${P.orders.length && P.f.online_orders_on ? `<label>For app order (optional)<select id="c2_pord"><option value="">— none —</option>${P.orders.map((o) => `<option value="${esc(o.order_id)}">#${esc(o.order_no)} · ${esc(o.customer_name)}${o.delivery_date ? ' · ' + esc(o.delivery_date) : ''}</option>`).join('')}</select></label><label>Quantity for that order<input id="c2_pq" inputmode="decimal" placeholder="blank = the whole run"></label>` : ''}</div>`;
  },
  read() {
    const crew = P.crew.map((w, i) => { const e = $('[data-c2crew=emp][data-i="' + i + '"]'), h = $('[data-c2crew=hours][data-i="' + i + '"]'); return { employee_id: e ? e.value : '', hours: h ? Number(String(h.value).replace(/,/g, '')) : NaN }; }).filter((w) => w.employee_id);
    const ord = ($('#c2_pord') || {}).value || ''; const q = ($('#c2_pq') || {}).value || '';
    return { crew, order: ord || null, qty: q === '' ? null : Number(q) };
  },
  bad(x) { return x.crew.some((w) => !(w.hours > 0)) ? 'Write the hours for every worker you pick' : null; },
  async save(runId, x) {
    if (!P.f || !x) return;
    try {
      if (x.crew.length) await rpc('c2_production_crew_set', { p_run: runId, p_crew: x.crew.map((w) => ({ employee_id: w.employee_id, hours: w.hours })), p_note: null });
      if (x.order) await rpc('c2_production_link_order', { p_run: runId, p_order: x.order, p_qty: x.qty && x.qty > 0 ? x.qty : null, p_note: null });
    } catch (e) { toast('Production saved, but the crew / order link was not: ' + C.errText(e)); }
  },
};
B.c2prod = c2prod;
Object.assign(H, {
  c2_crew_add: () => { P.crew = c2prod.read().crew.map((w) => ({ emp: w.employee_id, hours: w.hours || '' })); P.crew.push({ emp: '', hours: '' }); const el = $('#c2_crew'); if (el) el.innerHTML = P.crew.map((w, i) => crewRow(i, w)).join(''); },
  c2_crew_del: (a) => { P.crew = c2prod.read().crew.map((w) => ({ emp: w.employee_id, hours: w.hours || '' })); P.crew.splice(Number(a.dataset.i), 1); const el = $('#c2_crew'); if (el) el.innerHTML = P.crew.map((w, i) => crewRow(i, w)).join(''); },
});
B.c2link && B.c2link('c2_staff', 'staffreports', 'Staff reports (attendance, labour hours, cashier variance)', 'c2_orders_features', () => ({}));
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { staffreports: view });
})();
