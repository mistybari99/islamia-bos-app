/* Islamia BOS · Business Memory: the "What happened?" tools (Day replay, Timeline of one thing, Compare, Drill, Record trail).
   Server: supabase/phase471-474.sql (rpt_hub_day, rpt_hub_entity, rpt_hub_find_entity, rpt_hub_metrics, rpt_hub_compare, rpt_hub_drill, rpt_hub_trail). Read only.
   Every result shows when it was made and with which filters; a kind of record the person may not see is named in a notice, never counted. A missing fact is written "not recorded". */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { esc, toast, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const R = B.rhub;
const $ = (s, el = document) => el.querySelector(s);
const { money, qtyf, addDays, monthStart, monthEnd, dhakaToday } = R;
const T = R.T;

const Y = {
  prev_day: L('আগের দিন', 'Previous day', 'Previous day'), next_day: L('পরের দিন', 'Next day', 'Next day'), date: L('তারিখ', 'Date', 'Date'), outlet: L('শাখা / জায়গা', 'Outlet / place', 'Outlet'),
  day_t: L('একটি দিনের গল্প', 'Day replay', 'Day replay'), ent_t: L('একটির ইতিহাস', 'Timeline of one thing', 'Timeline'), cmp_t: L('কী বদলেছে', 'What changed', 'What changed'), drill_t: L('এই সংখ্যার পেছনে', 'Behind this number', 'Behind this number'), trail_t: L('রেকর্ডের ইতিহাস', 'Record trail', 'Record trail'),
  rec_ok: L('দৈনিক সারসংক্ষেপের সাথে মিলেছে', 'Matches the daily summary', 'Daily summary-র সাথে মিলেছে'), rec_bad: L('দৈনিক সারসংক্ষেপের সাথে মিলছে না', 'Does NOT match the daily summary', 'Daily summary-র সাথে মিলছে না'),
  rec_na_no_summary_right: L('মেলানো যায়নি: সারসংক্ষেপ দেখার অনুমতি নেই', 'Not compared: you may not open the daily summary', 'মেলানো যায়নি: summary-র permission নেই'), rec_na_no_sales_right: L('মেলানো যায়নি: বিক্রির অনুমতি নেই', 'Not compared: no sales right', 'মেলানো যায়নি: sales right নেই'),
  rec_na_summary_failed: L('মেলানো যায়নি: সারসংক্ষেপ চালানো গেল না', 'Not compared: the summary could not be run', 'মেলানো যায়নি'), hub: L('এই পাতা', 'This page', 'This page'), summ: L('সারসংক্ষেপ', 'Summary', 'Summary'),
  f_sales_n: L('বিক্রির সংখ্যা', 'Number of sales', 'Number of sales'), f_net_sales: L('নিট বিক্রি', 'Net sales', 'Net sales'), f_sales_discount: L('ডিসকাউন্ট', 'Discounts', 'Discounts'), f_void_n: L('বাতিল সংখ্যা', 'Voids', 'Voids'), f_void_amount: L('বাতিলের টাকা', 'Void value', 'Void value'),
  k_sales_total: L('বিক্রি', 'Sales', 'Sales'), k_net_sales: L('নিট বিক্রি', 'Net sales', 'Net sales'), k_returns_total: L('ফেরত', 'Returns', 'Returns'), k_void_amount: L('বাতিল', 'Voided', 'Voided'), k_collections_total: L('বাকি আদায়', 'Dues collected', 'Dues collected'),
  k_expense_total: L('খরচ', 'Expenses', 'Expenses'), k_purchases_total: L('ক্রয়', 'Purchases', 'Purchases'), k_supplier_paid_total: L('সরবরাহকারীকে', 'Paid to suppliers', 'Paid to suppliers'), k_sales_discount: L('ডিসকাউন্ট', 'Discounts', 'Discounts'),
  events: L('ঘটনা', 'events', 'events'), whom: L('কে', 'Who', 'Who'), record: L('রেকর্ড', 'Record', 'Record'), screen: L('পাতা খুলুন', 'Open screen', 'Open screen'), kinds_f: L('ধরন', 'Kinds', 'Kinds'), all_kinds: L('সব', 'All', 'All'),
  late: L('পরে লেখা', 'entered later', 'entered later'),
  csv_h: ['date', 'time', 'kind', 'outlet', 'who', 'amount', 'qty', 'status', 'title', 'detail', 'record_table', 'record_id'],
  e_kind: L('কী খুঁজছেন?', 'What are you looking for?', 'কী খুঁজছেন?'), k_item: L('আইটেম', 'Item', 'Item'), k_customer: L('গ্রাহক', 'Customer', 'Customer'), k_supplier: L('সরবরাহকারী', 'Supplier', 'Supplier'), k_staff: L('কর্মী', 'Staff', 'Staff'),
  k_employee: L('কর্মী (HR)', 'Employee (HR)', 'Employee (HR)'), k_outlet: L('শাখা', 'Outlet', 'Outlet'), k_batch: L('ব্যাচ', 'Batch', 'Batch'), find_ph: L('নাম, কোড বা মোবাইল লিখুন', 'Type a name, code or mobile', 'নাম, code বা mobile'),
  pick: L('বেছে নিন', 'Pick one', 'Pick one'), none_found: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'), opening: L('শুরুর ব্যালেন্স', 'Opening balance', 'Opening'), closing: L('শেষ ব্যালেন্স', 'Closing balance', 'Closing'), balance: L('ব্যালেন্স', 'Balance', 'Balance'),
  owed: L('(পাওনা/দেনা)', '(amount owed)', '(owed)'), qty_bal: L('(পরিমাণ)', '(quantity)', '(qty)'), change: L('বদল', 'change', 'change'),
  p_this_month: L('এই মাস', 'This month', 'This month'), p_last_30: L('শেষ ৩০ দিন', 'Last 30 days', 'Last 30 days'), p_this_year: L('এই বছর', 'This year', 'This year'), p_last_month: L('গত মাস', 'Last month', 'Last month'), p_custom: L('নিজে বেছে নিন', 'Custom', 'Custom'),
  a: L('সময় ক', 'Period A', 'Period A'), b: L('সময় খ', 'Period B', 'Period B'), pre: L('দ্রুত বেছে নিন', 'Quick choice', 'Quick choice'), mvm: L('এই মাস বনাম গত মাস', 'This month vs last month', 'This month vs last month'),
  wvw: L('এই সপ্তাহ বনাম গত সপ্তাহ', 'This week vs last week', 'This week vs last week'), yvy: L('এই বছর বনাম গত বছর', 'This year vs last year', 'This year vs last year'), dvd: L('গতকাল বনাম আগের সপ্তাহের একই দিন', 'Yesterday vs the same day last week', 'Yesterday vs same day last week'),
  figure: L('সংখ্যা', 'Figure', 'Figure'), chg: L('বদল', 'Change', 'Change'), movers: L('বেশি বদল যেখানে', 'Biggest movers', 'Biggest movers'), why: L('কারণ দেখুন', 'Why?', 'Why?'), diff_len: L('দুই সময়ের দৈর্ঘ্য আলাদা', 'The two periods have different lengths', 'দুই period-এর দৈর্ঘ্য আলাদা'),
  total_is: L('মোট', 'Total', 'Total'), count_is: L('লেনদেন', 'transactions', 'transactions'), group: L('ভাগ', 'Group by', 'Group by'), g_day: L('দিন', 'Day', 'Day'), g_loc: L('শাখা', 'Outlet', 'Outlet'), g_who: L('কে', 'Who', 'Who'), g_kind: L('ধরন', 'Kind', 'Kind'), g_none: L('ভাগ নেই', 'No grouping', 'No grouping'),
  sums_to: L('এই তালিকার যোগফল ওপরের সংখ্যার সমান', 'These rows add up to the figure above', 'যোগফল ওপরের সংখ্যার সমান'), value: L('অবদান', 'Counts as', 'Counts as'),
  tr_for: L('কোন রেকর্ড?', 'Which record?', 'Which record?'), tr_receipt: L('রসিদ নম্বর', 'Receipt number', 'Receipt no.'), tr_find: L('খুঁজুন', 'Find', 'Find'), tr_hint: L('যেকোনো তালিকার "রেকর্ড" বোতাম থেকেও এখানে আসা যায়।', 'You can also get here from the "Record" button on any list.', 'যেকোনো list-এর "Record" button থেকেও আসা যায়।'),
  tr_steps: L('কী কখন হলো', 'What happened to it', 'What happened to it'), tr_rev: L('স্টক উল্টানো', 'Stock reversals', 'Stock reversals'), tr_jrn: L('হিসাবের এন্ট্রি', 'Journal entries', 'Journal entries'), tr_exc: L('ব্যতিক্রম', 'Exceptions', 'Exceptions'),
  tr_cor: L('সংশোধন', 'Corrections', 'Corrections'), tr_chg: L('বদলের অনুরোধ', 'Change requests', 'Change requests'), tr_aud: L('অডিট লগ', 'Audit log', 'Audit log'), tr_nr: L('লেখা নেই', 'Not recorded', 'Not recorded'), tr_fields: L('রেকর্ডের ঘর', 'Record fields', 'Record fields'),
  tr_empty: L('কোনো ধাপ লেখা নেই', 'No step is recorded', 'কোনো step লেখা নেই'), by: L('যিনি', 'by', 'by'),
  ev_created: L('তৈরি', 'Created', 'Created'), ev_requested: L('অনুরোধ', 'Requested', 'Requested'), ev_posted: L('পোস্ট', 'Posted', 'Posted'), ev_received: L('গৃহীত', 'Received', 'Received'), ev_submitted: L('জমা', 'Submitted', 'Submitted'), ev_checked: L('যাচাই', 'Checked', 'Checked'),
  ev_decided: L('সিদ্ধান্ত', 'Decided', 'Decided'), ev_resolved: L('নিষ্পত্তি', 'Resolved', 'Resolved'), ev_voided: L('বাতিল', 'Voided', 'Voided'), ev_cancelled: L('বাতিল', 'Cancelled', 'Cancelled'), ev_closed: L('বন্ধ', 'Closed', 'Closed'), ev_reopened: L('আবার খোলা', 'Reopened', 'Reopened'),
  ev_ended: L('শেষ', 'Ended', 'Ended'), ev_logged: L('লেখা', 'Logged', 'Logged'),
  nr_who_created: L('কে বানিয়েছে', 'who created it', 'who created it'), nr_who_voided: L('কে বাতিল করেছে', 'who voided it', 'who voided it'), nr_void_reason: L('বাতিলের কারণ', 'the reason for the void', 'void reason'),
  nr_audit_log_has_no_line_for_this_record: L('অডিট লগে এই রেকর্ডের কোনো লাইন নেই', 'the audit log has no line for this record', 'audit log-এ line নেই'), nr_who_changed_the_form_after_approval: L('অনুমোদনের পর কে ফর্ম বদলেছে', 'who changed the form after approval', 'who changed the form'),
  n_audit_log_owner_only: L('অডিট লগ শুধু মালিক দেখতে পারেন', 'The audit log can be read by the owner only', 'Audit log শুধু owner দেখেন'), n_only_the_date_is_recorded: L('শুধু তারিখ লেখা আছে, সময় নয়', 'Only the date is recorded, not the time', 'শুধু date, time নয়'),
  owed_c: L('বাকি আছে', 'owed', 'owed'),
};
const TY = (k) => lab(Y[k]);

const num = (v) => (v === null || v === undefined || v === '' ? null : Number(v));
const errBox = (msg, retry) => R.stateHTML('error', msg, retry);
const locChip = (id) => (id === null || id === undefined ? '' : R.locName(id));
const ago = (n) => addDays(dhakaToday(), -n);
const setOut = (html) => { const el = $('#rh_out'); if (el) el.innerHTML = html; };

// ---------- one line per event ----------
function summ(e) {
  const d = e.detail || {}, bits = [];
  const add = (v) => { if (v !== null && v !== undefined && v !== '') bits.push(String(v)); };
  switch (e.kind) {
    case 'sale': add(d.receipt != null ? '#' + d.receipt : null); add(d.pay_mode); add(d.sale_type === 'wholesale' ? 'wholesale' : null); add(d.customer); if (num(d.discount) > 0) add('− ' + money(d.discount)); if (num(d.due) > 0) add('due ' + money(d.due)); if (d.quick) add('quick'); break;
    case 'void': add(d.receipt != null ? '#' + d.receipt : null); add(d.note); break;
    case 'return': add(d.reason); add('refund ' + money(d.refund)); if (num(d.credit) > 0) add('credit ' + money(d.credit)); add(d.note); break;
    case 'collection': case 'sale_payment': add(d.mode); add(d.wallet); add(d.ref); add(d.note); break;
    case 'expense': add(d.head && R.headLabel ? R.headLabel(d.head) : d.head); add(d.paid_to); add(d.note); break;
    case 'voucher': add('#' + d.serial); add(d.lines + ' lines'); break;
    case 'supplier_payment': case 'supplier_refund': add(d.supplier); add(d.mode); add(d.ref); add(d.note); break;
    case 'purchase': case 'purchase_return': add(d.bill_no); add(d.supplier); if (num(d.due) > 0) add('due ' + money(d.due)); add(d.note); break;
    case 'production': add(d.item); add(d.batches + ' batch'); if (d.yield_actual) add('yield ' + d.yield_actual); if (d.cost_hidden) add(T('cost_hidden')); break;
    case 'transfer_sent': add(d.item); add('→ ' + locChip(d.to)); add(d.note); break;
    case 'transfer_received': add(d.item); add('← ' + locChip(d.from)); if (num(d.short) > 0) add('short ' + qtyf(d.short)); add(d.note); break;
    case 'transfer_cancelled': add(d.item); break;
    case 'wastage': add(d.item); add(d.reason); add(d.note); break;
    case 'count_adjust': case 'ledger': add(d.item); add(d.reason || e.title); add(d.note); if (d.ref_type) add(d.ref_type + ' ' + (d.ref_id || '')); break;
    case 'cash_move': add(d.move_kind); add(d.mode); add(d.note); break;
    case 'cash_short': add(d.treatment || e.status); add(d.reason); break;
    case 'other_income': case 'money_transfer': add(d.head); add(d.mode); add(d.note); break;
    case 'handover': case 'day_sheet': case 'count_sheet': case 'factory_sheet': add('#' + d.serial); add(d.checked_by ? 'checked by ' + d.checked_by : null); if (d.entered_later) add(TY('late')); break;
    case 'transit_short': add(d.item); add('from ' + locChip(d.from)); break;
    case 'approval': add(e.title.replace(/_/g, ' ')); add(d.reason); add(d.requested_by ? 'by ' + d.requested_by : null); break;
    case 'exception': case 'exception_resolved': add(e.title); add(d.level); add(d.form); add(d.note); break;
    case 'period': add(e.title.replace(/_/g, ' ')); add(d.month); add(d.reason || d.note); break;
    case 'staff_status': case 'staff_exit': add(d.employee); add((d.from ? d.from + ' → ' : '') + (d.to || '')); add(d.reason); break;
    case 'payroll': case 'advance': add(d.employee); add(d.mode); add(d.note); break;
    case 'price_change': add(d.item); add('price ' + money(d.sell_price)); break;
    default: Object.entries(d).slice(0, 3).forEach(([k, v]) => add(k + ': ' + v));
  }
  return bits.join(' · ');
}
function evHTML(e, showLoc, bal, ov) {
  const void_ = ['void', 'cancelled', 'rejected'].includes(e.status);
  const amt = ov !== undefined ? ov : e.amount !== null && e.amount !== undefined ? money(e.amount) : (e.qty !== null && e.qty !== undefined ? qtyf(e.qty) : '');
  const who = e.who || T('nr');
  const link = e.link && e.kind !== 'ledger' ? `<button data-act="rh_screen" data-v="${esc(e.link)}">${esc(TY('screen'))}</button>` : '';
  const rec = e.ref_table ? `<button data-act="rh_trail" data-t="${esc(e.ref_table)}" data-i="${esc(e.ref_id)}">${esc(TY('record'))}</button>` : '';
  return `<div class="rh-ev ${void_ ? 'void' : ''}" data-k="${esc(e.kind)}"><div class="t">${esc(e.time || '')}${e.day && showLoc === 'day' ? `<br><small>${esc(String(e.day).slice(5))}</small>` : ''}</div>
    <div class="b"><b>${esc(R.evLabel(e.kind))}</b> ${e.status ? `<span class="chip ${R.stCls(e.status)}">${esc(R.stLabel(e.status))}</span>` : ''}<small>${esc(who)}${e.loc != null && showLoc ? ' · ' + esc(locChip(e.loc)) : ''}${summ(e) ? ' · ' + esc(summ(e)) : ''}</small></div>
    <div class="a ${e.dir === 'in' ? 'in' : e.dir === 'out' ? 'out' : ''}">${esc(amt)}${bal !== undefined && bal !== null ? `<br><small class="muted">${esc(qtyf(bal))}</small>` : ''}</div>
    <div class="x">${rec}${link}</div></div>`;
}
const csvRow = (e) => [e.day, e.time, e.kind, locChip(e.loc), e.who || '', e.amount ?? '', e.qty ?? '', e.status || '', e.title || '', summ(e), e.ref_table || '', e.ref_id || ''];

// ---------- Day replay ----------
const DY = { date: null, loc: '', kinds: [], off: 0, last: null };
const PAGE = 50;
async function viewDay(p) {
  DY.date = /^\d{4}-\d{2}-\d{2}$/.test(p.date || '') ? p.date : DY.date || dhakaToday();
  DY.loc = p.loc !== undefined ? p.loc : DY.loc; DY.kinds = p.kinds ? String(p.kinds).split(',').filter(Boolean) : []; DY.off = 0;
  R.currentParams = () => ({ date: DY.date, loc: DY.loc, kinds: DY.kinds.join(',') });
  shell(TY('day_t'), `<div class="card stack"><div class="row rh-date"><button data-act="rh_day_step" data-v="-1" aria-label="${esc(TY('prev_day'))}">‹</button><input id="rh_date" type="date" value="${esc(DY.date)}" aria-label="${esc(TY('date'))}"><button data-act="rh_day_step" data-v="1" aria-label="${esc(TY('next_day'))}">›</button></div>
    ${R.locSelect('rh_dloc', DY.loc)}</div><div id="rh_out">${R.stateHTML('loading')}</div>`, 'reports/hub');
  await dayRun();
}
async function dayRun() {
  const loc = DY.loc === '' ? null : Number(DY.loc);
  const r = await R.rpc('rpt_hub_day', { p_date: DY.date, p_loc: loc, p_kinds: DY.kinds.length ? DY.kinds : null, p_limit: PAGE, p_offset: DY.off });
  if (r.error) return setOut(errBox(r.msg, 'rh_day_retry'));
  const d = r.data; DY.last = d; R.touch('tool:day', { date: DY.date, loc: DY.loc });
  const t = d.totals || {}, rc = d.reconcile || {};
  const cards = [['sales_total', 'k_sales_total', t.sales_total, 'sales_total'], ['net_sales', 'k_net_sales', t.net_sales, 'net_sales'], ['returns_total', 'k_returns_total', t.returns_total, 'returns_total'], ['void_amount', 'k_void_amount', t.void_amount, 'void_total'],
    ['collections_total', 'k_collections_total', t.collections_total, 'collections_total'], ['expense_total', 'k_expense_total', t.expense_total, 'expense_total'], ['purchases_total', 'k_purchases_total', t.purchases_total, 'purchases_total'], ['supplier_paid_total', 'k_supplier_paid_total', t.supplier_paid_total, 'supplier_paid']]
    .filter((c) => c[2] !== undefined);
  const recBox = rc.status === 'match' ? `<div class="notice ok mk ok"><b>${esc(TY('rec_ok'))}</b></div>`
    : rc.status === 'mismatch' ? `<div class="notice bad mk bad"><b>${esc(TY('rec_bad'))}</b><br>${(rc.checks || []).filter((c) => !c.ok).map((c) => esc(TY('f_' + c.field)) + ': ' + esc(String(c.hub)) + ' ≠ ' + esc(String(c.summary))).join('<br>')}</div>`
    : rc.status ? `<p class="muted">${esc(TY('rec_na_' + (rc.why || 'summary_failed')))}</p>` : '';
  const kinds = Object.entries(d.kind_counts || {}).sort((a, b) => b[1].n - a[1].n);
  const events = d.events || [];
  setOut(`${R.stampHTML(d, [DY.date, loc == null ? T('all_places') : R.locName(loc)].concat(DY.kinds.map(R.evLabel)))}
    ${R.maskHTML(d.masked, d.notes)}${recBox}
    ${cards.length ? `<div class="rh-tot">${cards.map((c) => `<button data-act="rh_drill_day" data-m="${c[3]}"><small>${esc(TY(c[1]))}</small><b>${esc(money(c[2]))}</b></button>`).join('')}</div>` : ''}
    <div class="rh-kinds" role="group" aria-label="${esc(TY('kinds_f'))}"><button class="chip" data-act="rh_day_kind" data-v="" aria-pressed="${!DY.kinds.length}">${esc(TY('all_kinds'))} ${d.total_events}</button>${kinds.map(([k, v]) => `<button class="chip" data-act="rh_day_kind" data-v="${esc(k)}" aria-pressed="${DY.kinds.includes(k)}">${esc(R.evLabel(k))} ${v.n}</button>`).join('')}</div>
    ${events.length ? `<div class="card" style="padding:2px 12px">${events.map((e) => evHTML(e, DY.loc === '' ? 'loc' : '')).join('')}</div>` : `<p class="muted center pad">${esc(T('empty_day'))}</p>`}
    ${R.pagerHTML(d.total_events, PAGE, DY.off, 'rh_day_page')}
    ${events.length ? `<div class="row"><button class="full" data-act="rh_day_csv">${esc(T('csv'))}</button></div>` : ''}${R.saveViewHTML('tool:day')}`);
}
async function dayCsv() {
  const loc = DY.loc === '' ? null : Number(DY.loc);
  await R.exportCsv('day_replay_' + DY.date, Y.csv_h, async () => {
    const out = []; for (let off = 0; off < 20000; off += 500) { const r = await R.rpc('rpt_hub_day', { p_date: DY.date, p_loc: loc, p_kinds: DY.kinds.length ? DY.kinds : null, p_limit: 500, p_offset: off }); if (r.error) throw r.error; (r.data.events || []).forEach((e) => out.push(csvRow(e))); if (off + 500 >= r.data.total_events) break; }
    return out;
  }, { date: DY.date, loc });
}
R.views.day = viewDay;

// ---------- Entity timeline ----------
const EN = { kind: 'item', id: '', label: '', from: null, to: null, loc: '', off: 0, found: null, q: '', preset: 'p_last_30' };
const EKINDS = ['item', 'customer', 'supplier', 'staff', 'outlet', 'batch'];
async function viewEntity(p) {
  if (p.kind) EN.kind = EKINDS.concat(['employee']).includes(p.kind) ? p.kind : 'item';
  EN.id = p.id || ''; EN.label = p.label || ''; EN.loc = p.loc || ''; EN.off = 0; EN.found = null; EN.q = '';
  EN.to = /^\d{4}-\d{2}-\d{2}$/.test(p.to || '') ? p.to : dhakaToday(); EN.from = /^\d{4}-\d{2}-\d{2}$/.test(p.from || '') ? p.from : ago(29);
  R.currentParams = () => ({ kind: EN.kind, id: EN.id, label: EN.label, from: EN.from, to: EN.to, loc: EN.loc });
  shell(TY('ent_t'), `<div class="card stack"><b>${esc(TY('e_kind'))}</b>
    <div class="rh-kinds" role="group">${EKINDS.map((k) => `<button class="chip" data-act="rh_ent_kind" data-v="${k}" aria-pressed="${EN.kind === k}">${esc(TY('k_' + k))}</button>`).join('')}</div>
    <div class="row"><input id="rh_eq" type="search" autocomplete="off" placeholder="${esc(TY('find_ph'))}" aria-label="${esc(TY('find_ph'))}"><button data-act="rh_ent_find">${esc(T('ask_go'))}</button></div><div id="rh_efound"></div></div>
    <div id="rh_out"></div>`, 'reports/hub');
  if (EN.id) await entRun(); else if (EN.kind === 'outlet') entFind('');
}
async function entFind(q) {
  const box = $('#rh_efound'); if (!box) return;
  box.innerHTML = R.stateHTML('loading');
  const r = await R.rpc('rpt_hub_find_entity', { p_kind: EN.kind, p_q: q || ' ', p_limit: 20 });
  if (r.error) { box.innerHTML = `<p class="muted">${esc(r.msg)}</p>`; return; }
  EN.found = r.data || [];
  box.innerHTML = EN.found.length ? `<div class="card" style="padding:2px 12px">${EN.found.map((x, i) => `<button class="rp-row" data-act="rh_ent_pick" data-i="${i}"><span class="nm">${esc(x.label)}<small>${esc(x.sub || '')}</small></span><span class="cv">›</span></button>`).join('')}</div>` : `<p class="muted">${esc(TY('none_found'))}</p>`;
}
async function entRun() {
  setOut(R.stateHTML('loading'));
  const kind = EN.kind;
  const r = await R.rpc('rpt_hub_entity', { p_kind: kind, p_id: String(EN.id), p_from: EN.from, p_to: EN.to, p_loc: EN.loc === '' || kind === 'outlet' ? null : Number(EN.loc), p_limit: PAGE, p_offset: EN.off });
  if (r.error) return setOut(errBox(r.msg, 'rh_ent_retry'));
  const d = r.data, en = d.entity || {}; EN.label = en.label || EN.label; R.touch('tool:entity', { kind, id: EN.id, label: EN.label });
  const events = d.events || [];
  const unit = en.unit ? ' ' + en.unit : '';
  const balHead = d.has_balance ? `<div class="rh-tot"><button disabled><small>${esc(TY('opening'))}</small><b>${esc(kind === 'item' || kind === 'batch' ? qtyf(d.opening) + unit : money(d.opening))}</b></button><button disabled><small>${esc(TY('closing'))}</small><b>${esc(kind === 'item' || kind === 'batch' ? qtyf(d.closing) + unit : money(d.closing))}</b></button></div>
    <p class="muted">${esc(TY('balance'))} ${esc(kind === 'item' || kind === 'batch' ? TY('qty_bal') : TY('owed'))}</p>` : '';
  const presets = [['p_this_month', monthStart(dhakaToday()), dhakaToday()], ['p_last_30', ago(29), dhakaToday()], ['p_this_year', dhakaToday().slice(0, 4) + '-01-01', dhakaToday()]];
  setOut(`<div class="card stack"><div class="hsec" style="margin:0">${esc(en.label || '')}<small>${esc(en.sub || '')}</small></div>
      <div class="rh-dates"><label>${esc(T('from'))}<input id="rh_efrom" type="date" value="${esc(EN.from)}"></label><label>${esc(T('to'))}<input id="rh_eto" type="date" value="${esc(EN.to)}"></label></div>
      <div class="rh-kinds">${presets.map(([k, a, b]) => `<button class="chip" data-act="rh_ent_preset" data-a="${a}" data-b="${b}">${esc(TY(k))}</button>`).join('')}</div>
      ${kind === 'outlet' ? '' : R.locSelect('rh_eloc', EN.loc)}</div>
    ${R.stampHTML(d, [EN.from + ' → ' + EN.to, en.label])}${R.maskHTML(d.masked, d.notes)}${balHead}
    ${events.length ? `<div class="card" style="padding:2px 12px">${events.map((e) => evHTML(e, kind === 'outlet' ? 'day' : 'loc', d.has_balance ? e.balance : undefined)).join('')}</div>` : `<p class="muted center pad">${esc(T('empty_day'))}</p>`}
    ${R.pagerHTML(d.total_events, PAGE, EN.off, 'rh_ent_page')}
    ${events.length ? `<div class="row"><button class="full" data-act="rh_ent_csv">${esc(T('csv'))}</button></div>` : ''}${R.saveViewHTML('tool:entity')}`);
}
async function entCsv() {
  const kind = EN.kind, loc = EN.loc === '' || kind === 'outlet' ? null : Number(EN.loc);
  await R.exportCsv('timeline_' + kind + '_' + String(EN.id).slice(0, 8), Y.csv_h.concat(['balance']), async () => {
    const out = []; for (let off = 0; off < 20000; off += 500) { const r = await R.rpc('rpt_hub_entity', { p_kind: kind, p_id: String(EN.id), p_from: EN.from, p_to: EN.to, p_loc: loc, p_limit: 500, p_offset: off }); if (r.error) throw r.error; (r.data.events || []).forEach((e) => out.push(csvRow(e).concat([r.data.has_balance ? e.balance : '']))); if (off + 500 >= r.data.total_events) break; }
    return out;
  }, { kind, id: EN.id, from: EN.from, to: EN.to });
}
R.views.entity = viewEntity;

// ---------- Compare ----------
const CM = { a: null, b: null, loc: '' };
const presetPeriods = (k) => {
  const t = dhakaToday();
  if (k === 'mvm') { const lm = addDays(monthStart(t), -1); return [monthStart(t), t, monthStart(lm), monthEnd(lm)]; }
  if (k === 'wvw') { const d = new Date(t + 'T12:00:00Z'), back = (d.getUTCDay() - 6 + 7) % 7, ws = addDays(t, -back); return [ws, t, addDays(ws, -7), addDays(ws, -1)]; }
  if (k === 'yvy') { const y = parseInt(t.slice(0, 4), 10); return [y + '-01-01', t, (y - 1) + '-01-01', (y - 1) + '-12-31']; }
  return [addDays(t, -1), addDays(t, -1), addDays(t, -8), addDays(t, -8)];
};
async function viewCompare(p) {
  const dflt = presetPeriods('mvm'), ok = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || '');
  CM.a = [ok(p.af) ? p.af : dflt[0], ok(p.at) ? p.at : dflt[1]]; CM.b = [ok(p.bf) ? p.bf : dflt[2], ok(p.bt) ? p.bt : dflt[3]]; CM.loc = p.loc || '';
  R.currentParams = () => ({ af: CM.a[0], at: CM.a[1], bf: CM.b[0], bt: CM.b[1], loc: CM.loc });
  shell(TY('cmp_t'), `<div class="card stack"><b>${esc(TY('pre'))}</b>
    <div class="rh-kinds">${['mvm', 'wvw', 'yvy', 'dvd'].map((k) => `<button class="chip" data-act="rh_cmp_preset" data-v="${k}">${esc(TY(k))}</button>`).join('')}</div>
    <div class="rh-dates"><label>${esc(TY('a'))} ${esc(T('from'))}<input id="rh_caf" type="date" value="${esc(CM.a[0])}"></label><label>${esc(T('to'))}<input id="rh_cat" type="date" value="${esc(CM.a[1])}"></label>
      <label>${esc(TY('b'))} ${esc(T('from'))}<input id="rh_cbf" type="date" value="${esc(CM.b[0])}"></label><label>${esc(T('to'))}<input id="rh_cbt" type="date" value="${esc(CM.b[1])}"></label></div>
    ${R.locSelect('rh_cloc', CM.loc)}<button class="primary full" data-act="rh_cmp_run">${esc(T('ask_go'))}</button></div><div id="rh_out"></div>`, 'reports/hub');
  if (p.run !== '0') await cmpRun();
}
async function cmpRun() {
  const g = (id) => ($('#' + id) || {}).value; CM.a = [g('rh_caf') || CM.a[0], g('rh_cat') || CM.a[1]]; CM.b = [g('rh_cbf') || CM.b[0], g('rh_cbt') || CM.b[1]]; CM.loc = g('rh_cloc') === undefined ? CM.loc : g('rh_cloc');
  setOut(R.stateHTML('loading'));
  const r = await R.rpc('rpt_hub_compare', { p_a_from: CM.a[0], p_a_to: CM.a[1], p_b_from: CM.b[0], p_b_to: CM.b[1], p_loc: CM.loc === '' ? null : Number(CM.loc) });
  if (r.error) return setOut(errBox(r.msg, 'rh_cmp_run'));
  const d = r.data; R.touch('tool:compare', { af: CM.a[0], at: CM.a[1], bf: CM.b[0], bt: CM.b[1], loc: CM.loc });
  const rows = (d.metrics || []);
  const val = (m, v) => (m.money ? money(v) : String(Math.round(Number(v) * 100) / 100));
  setOut(`${R.stampHTML(d, [CM.a[0] + ' → ' + CM.a[1], 'vs ' + CM.b[0] + ' → ' + CM.b[1], CM.loc === '' ? T('all_places') : R.locName(CM.loc)])}${R.maskHTML(d.masked, d.notes)}
    ${(d.notes || []).includes('periods_differ_in_length') ? `<div class="notice warn mk warn">${esc(TY('diff_len'))}: ${d.a.days} / ${d.b.days}</div>` : ''}
    ${rows.length ? `<div class="card" style="padding:6px 8px"><table class="rh-cmp"><thead><tr><th>${esc(TY('figure'))}</th><th>A</th><th>B</th><th>${esc(TY('chg'))}</th></tr></thead><tbody>${rows.map((m) => `<tr data-m="${esc(m.key)}"><td><button class="rh-link" data-act="rh_cmp_why" data-m="${esc(m.key)}">${esc(lab({ bn: m.label_bn, en: m.label_en, mix: m.label_en }))}</button></td>
      <td>${esc(val(m, m.a))}</td><td>${esc(val(m, m.b))}</td><td class="d ${m.delta > 0 ? 'up' : m.delta < 0 ? 'down' : ''}">${m.delta > 0 ? '+' : ''}${esc(val(m, m.delta))}${m.pct !== null && m.pct !== undefined ? '<br><small>' + (m.pct > 0 ? '+' : '') + esc(String(m.pct)) + '%</small>' : ''}</td></tr>
      ${m.movers && m.movers.length && (m.a || m.b) ? `<tr class="mv"><td colspan="4"><small class="muted">${esc(TY('movers'))}: ${m.movers.slice(0, 3).map((x) => esc(locChip(x.loc) || '—') + ' ' + (x.delta > 0 ? '+' : '') + esc(val(m, x.delta))).join(' · ')}</small></td></tr>` : ''}`).join('')}</tbody></table></div>
      <p class="muted">${esc(TY('why'))}: ${esc(lab(L('সংখ্যার নামে চাপুন', 'tap a figure name', 'figure-এর নামে চাপুন')))}</p>` : `<p class="muted center pad">${esc(T('empty_day'))}</p>`}${R.saveViewHTML('tool:compare')}`);
}
R.views.compare = viewCompare;

// ---------- Drill: the transactions behind one figure ----------
const DR = { metric: '', from: '', to: '', loc: '', group: 'day', off: 0 };
async function viewDrill(p) {
  DR.metric = p.metric || DR.metric; DR.from = p.from || DR.from; DR.to = p.to || DR.from; DR.loc = p.loc || ''; DR.group = p.group || 'day'; DR.off = 0;
  R.currentParams = () => ({ metric: DR.metric, from: DR.from, to: DR.to, loc: DR.loc, group: DR.group });
  shell(TY('drill_t'), `<div id="rh_out">${R.stateHTML('loading')}</div>`, 'reports/hub');
  await drillRun();
}
async function drillRun() {
  const r = await R.rpc('rpt_hub_drill', { p_metric: DR.metric, p_from: DR.from, p_to: DR.to, p_loc: DR.loc === '' ? null : Number(DR.loc), p_group: DR.group === 'none' ? null : DR.group, p_limit: PAGE, p_offset: DR.off });
  if (r.error) return setOut(errBox(r.msg, 'rh_drill_retry'));
  const d = r.data, rows = d.rows || [], isMoney = !['sales_count', 'void_count', 'exceptions_count', 'production_runs', 'count_adjustments'].includes(DR.metric);
  const gv = (v) => (isMoney ? money(v) : String(v));
  R.touch('tool:drill', { metric: DR.metric, from: DR.from, to: DR.to, loc: DR.loc });
  setOut(`<div class="hsec" style="margin:0">${esc(lab({ bn: d.label_bn, en: d.label_en, mix: d.label_en }))}</div>
    ${R.stampHTML(d, [DR.from + (DR.to !== DR.from ? ' → ' + DR.to : ''), DR.loc === '' ? T('all_places') : R.locName(DR.loc)])}
    <div class="rh-tot"><button disabled><small>${esc(TY('total_is'))}</small><b>${esc(gv(d.total))}</b></button><button disabled><small>${esc(TY('count_is'))}</small><b>${d.count}</b></button></div>
    <p class="muted">${esc(TY('sums_to'))}</p>
    <div class="rh-kinds" role="group" aria-label="${esc(TY('group'))}">${['day', 'loc', 'who', 'kind', 'none'].map((g) => `<button class="chip" data-act="rh_drill_group" data-v="${g}" aria-pressed="${DR.group === g}">${esc(TY('g_' + g))}</button>`).join('')}</div>
    ${(d.groups || []).length ? `<div class="card" style="padding:4px 12px">${d.groups.map((g) => `<div class="row between" style="min-height:40px"><span>${esc(DR.group === 'loc' ? (g.key === '-' ? '—' : R.locName(g.key)) : DR.group === 'kind' ? R.evLabel(g.key) : g.key === 'not recorded' ? T('nr') : g.key)}</span><span><small class="muted">${g.n}</small> <b>${esc(gv(g.value))}</b></span></div>`).join('')}</div>` : ''}
    ${R.maskHTML(d.masked, [])}
    ${rows.length ? `<div class="card" style="padding:2px 12px">${rows.map((x) => evHTML(Object.assign({}, x, { dir: null }), 'day', undefined, isMoney ? money(x.value) : String(x.value))).join('')}</div>` : `<p class="muted center pad">${esc(T('empty_day'))}</p>`}
    ${R.pagerHTML(d.count, PAGE, DR.off, 'rh_drill_page')}${rows.length ? `<div class="row"><button class="full" data-act="rh_drill_csv">${esc(T('csv'))}</button></div>` : ''}${R.saveViewHTML('tool:drill')}`);
}
async function drillCsv() {
  await R.exportCsv('drill_' + DR.metric, Y.csv_h.concat(['counts_as']), async () => {
    const out = []; for (let off = 0; off < 20000; off += 500) { const r = await R.rpc('rpt_hub_drill', { p_metric: DR.metric, p_from: DR.from, p_to: DR.to, p_loc: DR.loc === '' ? null : Number(DR.loc), p_group: null, p_limit: 500, p_offset: off }); if (r.error) throw r.error; (r.data.rows || []).forEach((e) => out.push(csvRow(e).concat([e.value]))); if (off + 500 >= r.data.count) break; }
    return out;
  }, { metric: DR.metric, from: DR.from, to: DR.to });
}
R.views.drill = viewDrill;

// ---------- Record trail ----------
const TR = { table: '', id: '' };
const SKIP = new Set(['lines', 'data', 'detail', 'patch', 'payload', 'photo', 'images', 'details', 'snapshot', 'conversion_detail', 'text']);
async function viewTrail(p) {
  TR.table = p.table || ''; TR.id = p.id || '';
  R.currentParams = () => ({ table: TR.table, id: TR.id });
  if (!TR.id) {
    shell(TY('trail_t'), `<div class="card stack"><b>${esc(TY('tr_for'))}</b><p class="muted">${esc(TY('tr_hint'))}</p>
      <div class="row"><input id="rh_rc" inputmode="numeric" autocomplete="off" placeholder="${esc(TY('tr_receipt'))}" aria-label="${esc(TY('tr_receipt'))}">${R.locSelect('rh_rloc', '', T('place'))}<button data-act="rh_trail_find">${esc(TY('tr_find'))}</button></div></div><div id="rh_out"></div>`, 'reports/hub');
    return;
  }
  shell(TY('trail_t'), `<div id="rh_out">${R.stateHTML('loading')}</div>`, 'reports/hub');
  await trailRun();
}
const diffLine = (a) => {
  const d = a.detail || {}, o = d.old, n = d.new; if (o && n && typeof o === 'object') { const ch = Object.keys(n).filter((k) => JSON.stringify(n[k]) !== JSON.stringify(o[k])).slice(0, 6); return ch.map((k) => k + ': ' + JSON.stringify(o[k]) + ' → ' + JSON.stringify(n[k])).join('; '); }
  return n ? 'new record' : '';
};
async function trailRun() {
  const r = await R.rpc('rpt_hub_trail', { p_table: TR.table, p_id: TR.id });
  if (r.error) return setOut(errBox(r.msg, 'rh_trail_retry'));
  const d = r.data, rec = d.record || {};
  R.touch('tool:trail', { table: TR.table, id: TR.id });
  const sec = (title, inner) => (inner ? `<div class="rh-sub">${esc(title)}</div>${inner}` : '');
  const step = (s) => `<div class="e"><b>${esc(Y['ev_' + s.event] ? lab(Y['ev_' + s.event]) : s.event)}</b> <span class="muted">${esc(s.at ? R.stamp(s.at) : T('nr'))}</span><br><small>${esc(TY('by'))} ${esc(s.who || T('nr'))}${s.note ? ' · ' + esc(s.note) : ''}</small></div>`;
  const fields = Object.entries(rec).filter(([k, v]) => !SKIP.has(k) && v !== null && typeof v !== 'object').slice(0, 40);
  setOut(`${R.stampHTML(d, [d.table, String(d.id).slice(0, 8)])}
    <div class="hsec" style="margin:0">${esc(R.evLabel(({ sales: 'sale', sale_returns: 'return', quick_expenses: 'expense', purchase_bills: 'purchase', production_runs: 'production', stock_wastage: 'wastage', stock_transfers: 'transfer_sent', cash_moves: 'cash_move' })[d.table] || '') || d.table)}</div>
    <div class="card rh-tl">${(d.trail || []).length ? d.trail.map(step).join('') : `<p class="muted">${esc(TY('tr_empty'))}</p>`}</div>
    ${sec(TY('tr_rev'), (d.reversals || []).length ? `<div class="card">${d.reversals.map((x) => `<div class="rh-ev"><div class="t">${esc(R.hm(x.at))}</div><div class="b">${esc(x.reason || x.relation || '')}<small>${esc(x.item || '')} ${esc(qtyf(x.qty))} · ${esc(x.who || T('nr'))}</small></div><div class="a"></div></div>`).join('')}</div>` : '')}
    ${sec(TY('tr_jrn'), (d.journal || []).length ? `<div class="card">${d.journal.map((x) => `<div class="row between"><span>#${esc(x.journal_id)} ${esc(x.source_type)}${x.reverses_id ? ' ↺ #' + esc(x.reverses_id) : ''}</span><span class="chip ${R.stCls(x.status)}">${esc(R.stLabel(x.status))}</span></div>`).join('')}</div>` : '')}
    ${sec(TY('tr_exc'), (d.exceptions || []).length ? `<div class="card">${d.exceptions.map((x) => `<div class="row between"><span>${esc(x.flag)} <small class="muted">${esc(x.level)}</small></span><span class="chip ${R.stCls(x.status)}">${esc(R.stLabel(x.status))}</span></div>${x.resolved_by ? `<small class="muted">${esc(x.resolved_by)}${x.note ? ' · ' + esc(x.note) : ''}</small>` : ''}`).join('')}</div>` : '')}
    ${sec(TY('tr_cor'), (d.corrections || []).length ? `<div class="card">${d.corrections.map((x) => `<div><b>${esc(R.stamp(x.at))}</b> ${esc(x.who || T('nr'))}<br><small>${esc(x.note || '')}</small></div>`).join('')}</div>` : '')}
    ${sec(TY('tr_chg'), (d.change_requests || []).length ? `<div class="card">${d.change_requests.map((x) => `<div><b>${esc(x.requested_by || T('nr'))}</b> → ${esc(x.decided_by || '…')} <span class="chip ${R.stCls(x.status)}">${esc(R.stLabel(x.status))}</span><br><small>${esc(x.reason || '')}</small></div>`).join('')}</div>` : '')}
    ${sec(TY('tr_aud'), (d.audit_log || []).length ? `<div class="card">${d.audit_log.map((x) => `<div><b>${esc(R.stamp(x.at))}</b> ${esc(x.who || T('nr'))} · ${esc(x.action)}<br><small>${esc(diffLine(x))}</small></div>`).join('')}</div>` : '')}
    ${(d.not_recorded || []).length ? `<div class="notice warn mk warn"><b>${esc(TY('tr_nr'))}:</b> ${d.not_recorded.map((k) => esc(Y['nr_' + k] ? lab(Y['nr_' + k]) : k)).join('; ')}</div>` : ''}
    ${(d.notes || []).filter((n) => Y['n_' + String(n).split(':')[0]]).map((n) => `<p class="muted">${esc(lab(Y['n_' + String(n).split(':')[0]]))}</p>`).join('')}
    <details><summary>${esc(TY('tr_fields'))}</summary><dl class="rh-kv">${fields.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(String(v))}</dd>`).join('')}</dl></details>${R.saveViewHTML('tool:trail')}`);
}
R.views.trail = viewTrail;

// ---------- actions ----------
const toDay = (iso) => iso;
Object.assign(H, {
  rh_screen: (a) => { location.hash = '#/' + a.dataset.v; },
  rh_trail: (a) => R.go('trail', { table: a.dataset.t, id: a.dataset.i }),
  rh_day_retry: () => dayRun(),
  rh_day_step: (a) => { DY.date = addDays(DY.date, Number(a.dataset.v)); const el = $('#rh_date'); if (el) el.value = DY.date; DY.off = 0; return dayRun(); },
  rh_day_kind: (a) => { const k = a.dataset.v; if (!k) DY.kinds = []; else DY.kinds = DY.kinds.includes(k) ? DY.kinds.filter((x) => x !== k) : DY.kinds.concat([k]); DY.off = 0; return dayRun(); },
  rh_day_page: (a) => { DY.off = Number(a.dataset.o); return dayRun(); },
  rh_day_csv: () => dayCsv(),
  rh_drill_day: (a) => R.go('drill', { metric: a.dataset.m, from: DY.date, to: DY.date, loc: DY.loc }),
  rh_ent_kind: (a) => { EN.kind = a.dataset.v; EN.id = ''; EN.found = null; document.querySelectorAll('[data-act=rh_ent_kind]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.v === EN.kind))); setOut(''); const b = $('#rh_efound'); if (b) b.innerHTML = ''; if (EN.kind === 'outlet') entFind(''); },
  rh_ent_find: () => entFind(($('#rh_eq') || {}).value || ''),
  rh_ent_pick: (a) => { const x = (EN.found || [])[Number(a.dataset.i)]; if (!x) return; EN.kind = x.kind === 'employee' ? 'employee' : EN.kind; EN.id = x.id; EN.label = x.label; EN.off = 0; const b = $('#rh_efound'); if (b) b.innerHTML = ''; return entRun(); },
  rh_ent_retry: () => entRun(),
  rh_ent_preset: (a) => { EN.from = a.dataset.a; EN.to = a.dataset.b; EN.off = 0; return entRun(); },
  rh_ent_page: (a) => { EN.off = Number(a.dataset.o); return entRun(); },
  rh_ent_csv: () => entCsv(),
  rh_cmp_preset: (a) => { const p = presetPeriods(a.dataset.v); CM.a = [p[0], p[1]]; CM.b = [p[2], p[3]]; ['rh_caf', 'rh_cat', 'rh_cbf', 'rh_cbt'].forEach((id, i) => { const el = $('#' + id); if (el) el.value = p[i]; }); return cmpRun(); },
  rh_cmp_run: () => cmpRun(),
  rh_cmp_why: (a) => R.go('drill', { metric: a.dataset.m, from: CM.b[0], to: CM.b[1], loc: CM.loc, group: 'day' }),
  rh_drill_group: (a) => { DR.group = a.dataset.v; DR.off = 0; return drillRun(); },
  rh_drill_page: (a) => { DR.off = Number(a.dataset.o); return drillRun(); },
  rh_drill_retry: () => drillRun(),
  rh_drill_csv: () => drillCsv(),
  rh_trail_retry: () => trailRun(),
  rh_trail_find: async () => {
    const n = Number((($('#rh_rc') || {}).value || '').replace(/\D/g, '')), loc = ($('#rh_rloc') || {}).value;
    if (!n) return toast(TY('tr_receipt'));
    let q = A.sb.from('sales').select('id,location_id,receipt').eq('receipt', n); if (loc) q = q.eq('location_id', Number(loc));
    const r = await q.limit(5); if (r.error) return toast(R.errText(r.error));
    if (!r.data || !r.data.length) return toast(TY('none_found'));
    if (r.data.length > 1) return toast(T('place'));
    R.go('trail', { table: 'sales', id: r.data[0].id });
  },
});
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id) return;
  if (id === 'rh_date' && /^\d{4}-\d{2}-\d{2}$/.test(e.target.value)) { DY.date = e.target.value; DY.off = 0; dayRun(); }
  else if (id === 'rh_dloc') { DY.loc = e.target.value; DY.off = 0; dayRun(); }
  else if (id === 'rh_efrom' || id === 'rh_eto') { const f = $('#rh_efrom').value, t = $('#rh_eto').value; if (f && t && t >= f) { EN.from = f; EN.to = t; EN.off = 0; entRun(); } }
  else if (id === 'rh_eloc') { EN.loc = e.target.value; EN.off = 0; entRun(); }
});
document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target && e.target.id === 'rh_eq') { e.preventDefault(); H.rh_ent_find(); } });
})();
