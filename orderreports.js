/* Islamia BOS · Order and delivery reports (#/orderreports) + the order capture helper (BOS.c2orders) used by the Online orders screen (salesx.js).
   Reports #153 register, #155 cake orders, #156 advance and balances, #159 delayed, #158 on-time, #163 fulfilment, #157 cancellations and refunds, #162 delivery cost, #160 order production cost, #161 order profit.
   Server: supabase/phase445.sql .. phase452.sql. Reads only, except the capture helpers (cake specification, promised slot, delivery cost, advance posting, refund, production link), which call server functions
   that decide every right. A missing figure is shown as "not captured", never 0. The three sources (app order, paper 20-1, paper 20-6) are never added together. English labels (owner rule). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const C = B.c2ui;
if (!C) { console.warn('orderreports: c2rpt.js is not loaded'); return; }
const { sb, esc, toast, fail, H, openSheet, closeSheet, S } = A;
const { E, lab, today, addDays, fmt, tableHTML, tiles, rpc, makePage } = C;
const $ = (s, el = document) => el.querySelector(s);
const SRC = { app: 'App order', paper_20_1: 'Paper 20-1', paper_20_6: 'Paper 20-6 line' };
const ST = { new: 'New', confirmed: 'Confirmed', packed: 'Packed', delivered: 'Delivered', cancelled: 'Cancelled', open: 'Open (paper)', handed: 'Handed over', not_collected: 'Not collected', returned: 'Returned', not_written: 'Not written' };
const ADV = { none: 'No advance', held_in_books: 'Held, in the books', held_not_in_books: 'Held, NOT in the books', paid_into_sale: 'Paid into the sale', applied_to_sale: 'Applied to the sale', held_not_applied: 'Held, not applied yet', refunded: 'Refunded',
  refund_due: 'Refund due', refund_closed: 'Refund closed unpaid', refund_not_recorded: 'Refund NOT recorded', kept_as_customer_advance: 'Kept as customer advance', kept_for_adjustment: 'Kept for adjustment', taken_as_income: 'Taken as income', on_sheet: 'On the sheet', unknown: 'Not decided' };
const BASIS = { total_minus_advance: 'Total - advance', sale_due_after_payments: 'Sale due after payments', sale_due_after_payments_and_applied_advance: 'Sale due after payments and applied advance', cancelled: 'Cancelled', sale_voided: 'Sale voided', sale_missing: 'Sale missing',
  cancelled_on_sheet: 'Not collected', due_payment_not_written: 'Due payment not written', total_minus_advance_minus_due_paid: 'Total - advance - due paid', ledger_line: 'Ledger line' };
const hhmm = (t) => (t ? String(t).slice(0, 5) : '');
const slot = (r) => (r.promised_from ? hhmm(r.promised_from) + (r.promised_to ? '-' + hhmm(r.promised_to) : '') : '');
const promised = (r) => (r.promised_date ? r.promised_date + (slot(r) ? ' ' + slot(r) : '') : null);
const mk = (k, h, f, extra) => Object.assign({ k, h, f }, extra || {});
const idCols = [mk('source', 'Source', 'text', { words: SRC }), mk('ref', 'Ref', 'text')];
const drillOrder = (r) => { if (r.order_id) return B.c2orders.detail(r.order_id); if (r.entry_id) { location.hash = '#/entry/' + r.entry_id; } };
const locArg = (f) => (f.loc === '' || f.loc === undefined ? null : Number(f.loc));
const sel = (id, label, opts, v) => `<label>${esc(label)} <select id="${id}">${opts.map(([k, l]) => `<option value="${k}" ${String(v) === String(k) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></label>`;
const srcExtra = (withPaper6) => ({ html: (f) => sel('c2_src', 'Source', [['', 'All sources'], ['app', SRC.app], ['paper_20_1', SRC.paper_20_1]].concat(withPaper6 ? [['paper_20_6', SRC.paper_20_6]] : []), f.source), read: (f, g) => { f.source = g('c2_src'); } });
const sumTiles = (o) => tiles(Object.keys(o).map((k) => [k, o[k]]));

const TABS = [
  { id: 'register', label: 'Order register', intro: '#153 · Every order in one list with its source: app orders, paper 20-1 sheets and paper 20-6 ledger lines. Sources are never merged.', filters: ['range', 'loc'],
    extra: [srcExtra(true), { html: (f) => sel('c2_by', 'Dates are', [['order', 'the day the order was taken'], ['promised', 'the promised delivery day']], f.by), read: (f, g) => { f.by = g('c2_by'); } },
      { html: (f) => sel('c2_st', 'Status', [['', 'Any']].concat(Object.keys(ST).map((k) => [k, ST[k]])), f.status), read: (f, g) => { f.status = g('c2_st'); } }],
    run: (f) => rpc('c2_order_register', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_source: f.source || null, p_status: f.status || null, p_by: f.by || 'order', p_limit: 2000 }),
    render: (r) => { const tb = r.totals_by_source || {}; return Object.keys(tb).map((s) => `<div class="card stack"><b>${esc(SRC[s] || s)}</b>${tiles([['Rows', fmt.int(tb[s].rows)], ['Total', fmt.money(tb[s].total)], ['Advance', fmt.money(tb[s].advance)], ['Balance', fmt.money(tb[s].balance)],
        tb[s].rows_without_balance ? ['Rows with no balance', fmt.int(tb[s].rows_without_balance)] : null])}</div>`).join('')
      + tableHTML({ name: 'order-register', rows: r.rows, drill: drillOrder, cols: idCols.concat([mk('order_date', 'Taken', 'date'), mk('customer_name', 'Customer', 'text'), mk('customer_mobile', 'Mobile', 'text'), mk('channel', 'Channel', 'text'), mk('order_type', 'Type', 'text'),
        mk('status', 'Status', 'text', { words: ST }), mk('promised', 'Promised', 'text', { get: promised }), mk('total', 'Total', 'money'), mk('advance', 'Advance', 'money'), mk('balance', 'Balance', 'money'), mk('advance_state', 'Advance state', 'text', { words: ADV }),
        mk('delivery_cost', 'Delivery cost', 'money')]) }) + (r.truncated ? `<p class="muted">More rows exist than shown (limit 2000). Narrow the dates.</p>` : ''); } },
  { id: 'cake', label: 'Cake orders', intro: '#155 · Cake and custom orders: the specification written on the app order, beside the paper 20-1 custom sheets.', filters: ['range', 'loc'], extra: [srcExtra(false)],
    run: (f) => rpc('c2_cake_register', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_source: f.source || null }),
    render: (r) => tiles([['Rows', fmt.int((r.rows || []).length)], ['App orders with no cake specification', fmt.int(r.app_orders_without_spec)]])
      + tableHTML({ name: 'cake-orders', rows: r.rows, drill: drillOrder, cols: [mk('source', 'Source', 'text', { words: SRC }), mk('ref', 'Ref', 'text'), mk('order_date', 'Taken', 'date'), mk('customer_name', 'Customer', 'text'), mk('promised', 'Promised', 'text', { get: promised }),
        mk('item_name', 'Item', 'text'), mk('weight_kg', 'Weight kg', 'num'), mk('flavour', 'Flavour', 'text'), mk('description', 'Paper description', 'text'), mk('message', 'Message', 'text'), mk('design', 'Design', 'text'), mk('photo_ref', 'Photo', 'text'), mk('note', 'Note', 'text'), mk('status', 'Status', 'text', { words: ST })] }) },
  { id: 'balances', label: 'Advance and balances', intro: '#156 · Advances held and what is still to collect. A delivered order is not shown as owed unless its sale really has an amount left.', filters: ['range', 'loc'],
    extra: [{ html: (f) => `<label><input type="checkbox" id="c2_open" ${f.open ? 'checked' : ''}> Open orders only</label>`, read: (f, g) => { f.open = !!($('#c2_open') && $('#c2_open').checked); } }],
    run: (f) => rpc('c2_order_balances', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_open_only: !!f.open }),
    render: (r) => { const a = (r.summary || {}).app || {}, p = (r.summary || {}).paper_20_1 || {};
      return `<div class="card stack"><b>App orders</b>${tiles([['Advance held on open orders', fmt.money(a.advance_held_open_orders)], ['…of it NOT in the books', fmt.money(a.advance_not_in_books_open)], ['Balance to collect, open orders', fmt.money(a.balance_to_collect_open_orders)], ['Still owed after delivery', fmt.money(a.still_owed_after_delivery)],
        ['Advance to return, cancelled', fmt.money(a.advance_to_return_cancelled)], ['Posted advance not yet applied', fmt.money(a.advance_posted_not_applied)]])}</div>
        <div class="card stack"><b>Paper 20-1</b>${tiles([['Advance, open sheets', fmt.money(p.advance_open_sheets)], ['Balance, open sheets', fmt.money(p.balance_open_sheets)], ['Open sheets with no total', fmt.int(p.open_sheets_without_total)], ['Handed over, due payment not written', fmt.int(p.handed_without_due_payment_written)]])}</div>`
      + tableHTML({ name: 'order-balances', rows: r.rows, drill: drillOrder, cols: idCols.concat([mk('order_date', 'Taken', 'date'), mk('customer_name', 'Customer', 'text'), mk('status', 'Status', 'text', { words: ST }), mk('total', 'Total', 'money'), mk('advance', 'Advance', 'money'), mk('balance', 'Balance', 'money'),
        mk('balance_basis', 'Basis', 'text', { words: BASIS }), mk('advance_state', 'Advance state', 'text', { words: ADV })]) }); } },
  { id: 'delayed', label: 'Delayed orders', intro: '#159 · Open orders whose promised time has passed. Orders with no promised date cannot be judged and are counted apart.', filters: ['loc'],
    run: (f) => rpc('c2_orders_delayed', { p_loc: locArg(f), p_as_of: null, p_from: null, p_to: null }),
    render: (r) => { const s = r.summary || {}; return tiles([['Delayed', fmt.int(s.delayed)], ['App orders', fmt.int(s.delayed_app)], ['Paper 20-1', fmt.int(s.delayed_paper_20_1)], ['Oldest (days late)', fmt.int(s.oldest_days)], ['Judged by slot', fmt.int(s.judged_by_slot)], ['Judged by date only', fmt.int(s.judged_by_date_only)],
        ['Open, no promised date', fmt.int(s.open_without_promised_date)], ['Open, not yet due', fmt.int(s.open_not_yet_due)]])
      + tableHTML({ name: 'delayed-orders', rows: r.rows, drill: drillOrder, cols: idCols.concat([mk('customer_name', 'Customer', 'text'), mk('status', 'Status', 'text', { words: ST }), mk('promised', 'Promised', 'text', { get: promised }), mk('overdue_hours', 'Hours late', 'num'), mk('overdue_days', 'Days late', 'int'),
        mk('basis', 'Judged by', 'text', { words: { slot: 'Time slot', date_only: 'Date only' } }), mk('advance', 'Advance', 'money'), mk('balance', 'Balance', 'money')]) }); } },
  { id: 'ontime', label: 'On-time delivery', intro: '#158 · App orders delivered by their promised slot (or promised day when no slot was written). Paper sheets have no delivery time and are not part of it.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_orders_ontime', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; return tiles([['Judged', fmt.int(s.judged)], ['On time', fmt.int(s.on_time)], ['Late', fmt.int(s.late)], ['On time %', fmt.pct(s.on_time_pct)], ['On time % (slot only)', fmt.pct(s.on_time_by_slot_pct)], ['Average minutes late', fmt.int(s.avg_late_minutes)],
        ['Delivered, no promised date', fmt.int(s.delivered_without_promised_date_not_judged)], ['Still open and late', fmt.int(r.still_open_overdue)]])
      + tableHTML({ name: 'ontime', rows: r.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('ref', 'Ref', 'text'), mk('customer_name', 'Customer', 'text'), mk('delivery_mode', 'Mode', 'text'), mk('promised', 'Promised', 'text', { get: promised }), mk('delivered_at', 'Delivered', 'ts'),
        mk('on_time', 'On time', 'bool'), mk('late_minutes', 'Minutes late', 'int'), mk('basis', 'Judged by', 'text', { words: { slot: 'Time slot', date_only: 'Date only' } })] }); } },
  { id: 'fulfil', label: 'Fulfilment rate', intro: '#163 · Of the orders taken in the range: delivered, cancelled, still open. Each source has its own rate.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_order_fulfilment', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const sm = r.summary || {}; const rows = Object.keys(sm).map((k) => Object.assign({ source: k }, sm[k])); const br = r.breakdown || {};
      return tableHTML({ name: 'fulfilment', rows, empty: 'No orders in this range.', cols: [mk('source', 'Source', 'text', { words: SRC }), mk('orders', 'Orders', 'int'), mk('delivered', 'Delivered', 'int'), mk('cancelled', 'Cancelled', 'int'), mk('still_open', 'Still open', 'int'), mk('rate_of_closed_pct', 'Rate of closed', 'pct'), mk('rate_of_all_pct', 'Rate of all', 'pct')] })
        + tableHTML({ name: 'fulfilment-breakdown', title: 'App orders by channel and delivery mode', rows: Object.keys(br).map((k) => Object.assign({ group: k.replace('app:channel:', 'Channel: ').replace('app:mode:', 'Delivery: ') }, br[k])), cols: [mk('group', 'Group', 'text'), mk('orders', 'Orders', 'int'), mk('delivered', 'Delivered', 'int'), mk('cancelled', 'Cancelled', 'int')] }); } },
  { id: 'cancel', label: 'Cancellations and refunds', intro: '#157 · Cancelled orders with the reason and where the advance stands. A refund is a real money record only when the refund switch is on.', filters: ['range', 'loc'],
    run: async (f) => { const r = await rpc('c2_order_cancellations', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }); try { r.refunds = await rpc('c2_order_refunds_list', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_state: null }); } catch (e) { r.refunds = null; } return r; },
    render: (r) => { const s = r.summary || {}; const pp = r.paper_20_1 || {};
      return tiles([['Cancelled', fmt.int(s.cancelled)], ['Cancel rate', fmt.pct(s.cancel_rate_pct)], ['Value cancelled', fmt.money(s.cancelled_value)], ['Advance on them', fmt.money(s.advance_total)], ['Refunded', fmt.money(s.refunded)], ['Refund due', fmt.money(s.refund_due)], ['Refund NOT recorded', fmt.money(s.refund_not_recorded)],
        ['Kept as advance', fmt.money(s.kept_as_customer_advance)], ['Taken as income', fmt.money(s.taken_as_income)]])
      + tableHTML({ name: 'cancellations', rows: r.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('ref', 'Ref', 'text'), mk('cancelled_at', 'Cancelled', 'ts'), mk('customer_name', 'Customer', 'text'), mk('reason', 'Reason', 'text'), mk('total', 'Total', 'money'), mk('advance', 'Advance', 'money'),
        mk('advance_state', 'Advance state', 'text', { words: ADV }), mk('refund_mode', 'Refund by', 'text')] })
      + tableHTML({ name: 'cancel-reasons', title: 'By reason', rows: r.by_reason, cols: [mk('reason', 'Reason', 'text'), mk('orders', 'Orders', 'int'), mk('advance', 'Advance', 'money')] })
      + `<div class="card stack"><b>Paper 20-1 not collected</b>${tiles([['Sheets', fmt.int(pp.sheets_not_collected)], ['Advance', fmt.money(pp.advance)]])}</div>`
      + (r.refunds ? tableHTML({ name: 'refunds', title: 'Refund records', rows: r.refunds.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('order_no', 'Order', 'text', { get: (x) => '#' + x.order_no }), mk('customer_name', 'Customer', 'text'), mk('amount', 'Amount', 'money'), mk('refund_mode', 'By', 'text'), mk('state', 'State', 'text', { words: { due: 'Due', paid: 'Paid', void: 'Closed unpaid' } }), mk('paid_at', 'Paid', 'ts'), mk('found_at_refund', 'Advance recorded now', 'bool')] }) : ''); } },
  { id: 'dcost', label: 'Delivery cost', intro: '#162 · What the customer paid for delivery against the actual cost written at delivery. Orders with no cost written are counted apart, never treated as free.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_delivery_cost_report', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; const pp = r.paper_20_6 || {};
      return tiles([['Home / courier orders', fmt.int(s.orders)], ['Delivered', fmt.int(s.delivered)], ['Delivery charge (not cancelled)', fmt.money(s.charge_total)], ['Cost written on', fmt.int(s.with_cost_captured)], ['Delivered, cost NOT written', fmt.int(s.cost_not_captured)], ['Cost total', fmt.money(s.cost_total_captured)],
        ['Margin where cost written', fmt.money(s.margin_where_cost_captured)], ['Average cost per order', fmt.money(s.avg_cost_per_order_captured)]])
      + tableHTML({ name: 'delivery-cost', rows: r.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('ref', 'Ref', 'text'), mk('order_date', 'Taken', 'date'), mk('customer_name', 'Customer', 'text'), mk('delivery_mode', 'Mode', 'text'), mk('delivery_by', 'Delivered by', 'text'), mk('status', 'Status', 'text', { words: ST }), mk('charge', 'Charge', 'money'), mk('cost', 'Cost', 'money'), mk('margin', 'Margin', 'money')] })
      + (r.by_kind ? tableHTML({ name: 'delivery-cost-kinds', title: 'Cost by kind', rows: Object.keys(r.by_kind).map((k) => Object.assign({ kind: k }, r.by_kind[k])), cols: [mk('kind', 'Kind', 'text'), mk('amount', 'Amount', 'money'), mk('rows', 'Entries', 'int')] }) : '')
      + (r.by_delivery_by ? tableHTML({ name: 'delivery-cost-by', title: 'By who delivered', rows: r.by_delivery_by, cols: [mk('delivery_by', 'Delivered by', 'text'), mk('orders', 'Orders', 'int'), mk('orders_with_cost', 'With cost', 'int'), mk('cost', 'Cost', 'money'), mk('charge', 'Charge', 'money')] }) : '')
      + `<div class="card stack"><b>Paper 20-6 ledger</b>${tiles([['Lines', fmt.int(pp.lines)], ['Delivery charge', fmt.money(pp.delivery_charge)], ['Lines with no charge written', fmt.int(pp.lines_without_charge_written)]])}</div>`; } },
  { id: 'prodcost', label: 'Order production cost', intro: '#160 · The cost of the production runs linked to an order. Needs the cost right.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_order_production_cost', { p_from: f.from, p_to: f.to, p_loc: locArg(f), p_order: null }),
    render: (r) => tiles([['Cake orders with no linked run', fmt.int(r.cake_orders_without_a_linked_run)]])
      + tableHTML({ name: 'order-production-cost', title: 'Per order', rows: r.per_order, cols: [mk('order_ref', 'Order', 'text'), mk('runs', 'Runs', 'int'), mk('material_cost', 'Material cost', 'money'), mk('conversion_cost', 'Conversion cost', 'money'), mk('complete', 'Cost complete', 'bool')] })
      + tableHTML({ name: 'order-production-runs', title: 'Per linked run', rows: r.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('order_ref', 'Order', 'text'), mk('made_on', 'Made', 'date'), mk('item_code', 'Item', 'text'), mk('run_output', 'Run output', 'num'), mk('qty_for_order', 'For this order', 'num'), mk('share_pct', 'Share', 'pct'),
        mk('material_cost', 'Material', 'money'), mk('conversion_cost', 'Conversion', 'money'), mk('cost_complete', 'Complete', 'bool')] }) },
  { id: 'profit', label: 'Order profit', intro: '#161 · Delivered app orders: sale value less goods cost less delivery cost. A profit appears only when every cost is known. Needs the cost right.', filters: ['range', 'loc'],
    run: (f) => rpc('c2_order_profit', { p_from: f.from, p_to: f.to, p_loc: locArg(f) }),
    render: (r) => { const s = r.summary || {}; return tiles([['Delivered orders', fmt.int(s.delivered_orders)], ['Revenue', fmt.money(s.revenue_all)], ['Orders with every cost known', fmt.int(s.orders_with_every_cost_known)], ['Orders with something missing', fmt.int(s.orders_with_something_missing)],
        ['Profit (full-cost orders)', fmt.money(s.profit_of_full_cost_orders)], ['Margin (full-cost orders)', fmt.pct(s.margin_pct_of_full_cost_orders)]])
      + tableHTML({ name: 'order-profit', rows: r.rows, drill: (x) => B.c2orders.detail(x.order_id), cols: [mk('ref', 'Ref', 'text'), mk('delivered_on', 'Delivered', 'date'), mk('customer_name', 'Customer', 'text'), mk('delivery_mode', 'Mode', 'text'), mk('revenue', 'Revenue', 'money'), mk('goods_cost', 'Goods cost', 'money'),
        mk('delivery_cost', 'Delivery cost', 'money'), mk('profit', 'Profit', 'money'), mk('linked_production_cost', 'Linked production (info)', 'money'), mk('missing', 'Missing', 'text', { get: (x) => (x.missing && x.missing.length ? x.missing.join(', ') : '') })] }); } },
];
const view = makePage({ route: 'orderreports', prefix: 'or', title: 'Order and delivery reports', intro: 'Orders taken in the app and on paper, delivery, cancellations, refunds, cost and profit. Read only; every figure comes from the server.', tabs: TABS });

/* ---------------- order detail sheet and the capture helper ---------------- */
const O = { f: null, kinds: null };
async function features() {
  if (O.f !== null) return O.f;
  try { const r = await sb.rpc('c2_orders_features'); O.f = r.error ? false : r.data || false; } catch (e) { O.f = false; }
  return O.f;
}
const on = (k) => !!(O.f && O.f[k]);
const num = (v) => { const s = String(v == null ? '' : v).replace(/[০-৯]/g, (c) => '০১২৩৪৫৬৭৮৯'.indexOf(c)).replace(/,/g, '').trim(); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const row2 = (l, v) => `<div class="row between"><span class="muted">${esc(l)}</span><span>${v === null || v === undefined || v === '' ? '<span class="muted">—</span>' : esc(v)}</span></div>`;
async function detail(id) {
  let d; try { d = await rpc('c2_order_detail', { p_order: id }); } catch (e) { return toast(C.errText(e)); }
  const o = d.order || {}, reg = d.register_row || {}, sp = d.specs || [], pr = d.promise, ap = d.advance_post, rf = d.refund, sa = d.sale;
  const btn = (act, label, cls) => `<button type="button" class="mini ${cls || ''}" data-act="${act}" data-id="${esc(id)}">${esc(label)}</button>`;
  const acts = [];
  if (ap && ap.state === 'posted' && o.status === 'delivered') acts.push(btn('c2_ord_apply', 'Apply the advance to the sale'));
  if (ap && ap.state === 'posted' && ['new', 'confirmed', 'packed'].includes(o.status)) acts.push(btn('c2_ord_advvoid', 'Take the advance out of the books'));
  if (!ap && on('advance_post_on') && Number(o.advance) > 0 && ['new', 'confirmed', 'packed'].includes(o.status)) acts.push(btn('c2_ord_advpost', 'Record the advance in the books'));
  if (rf && rf.state === 'due') acts.push(btn('c2_ord_refpay', 'Pay the refund'));
  openSheet(`<div class="stack"><h3>#${esc(o.order_no)} · ${esc(o.customer_name)}</h3>
    ${d.module_on ? '' : `<div class="notice info">${esc(C.noteText('module_off'))}</div>`}
    <div class="card stack">${row2('Status', ST[o.status] || o.status)}${row2('Delivery', o.delivery_mode + (o.delivery_date ? ' · ' + o.delivery_date : '') + (pr ? ' · slot ' + hhmm(pr.slot_from) + (pr.slot_to ? '-' + hhmm(pr.slot_to) : '') : ''))}
      ${row2('Total', fmt.money(reg.total))}${row2('Advance', fmt.money(o.advance))}${row2('Balance still due', fmt.money(reg.balance))}${row2('Advance state', ADV[reg.advance_state] || reg.advance_state)}
      ${sa ? row2('Sale', 'receipt ' + sa.receipt + ' · paid ' + fmt.money(sa.paid) + ' · due ' + fmt.money(sa.due)) : ''}${rf ? row2('Refund', fmt.money(rf.amount) + ' · ' + rf.state + ' · ' + rf.refund_mode) : ''}</div>
    ${acts.length ? `<div class="row wrap">${acts.join('')}</div>` : ''}
    ${sp.length ? `<div class="card stack"><b>Cake specification</b>${sp.map((c) => `<div>${[c.weight_kg ? c.weight_kg + ' kg' : '', c.flavour, c.message ? '"' + c.message + '"' : '', c.design, c.photo_ref ? 'photo: ' + c.photo_ref : '', c.note].filter(Boolean).map(esc).join(' · ')}</div>`).join('')}</div>` : ''}
    <div class="card stack"><b>Delivery cost</b>${d.cost_hidden ? `<p class="muted">${esc(C.noteText('cost_hidden'))}</p>` : (d.costs || []).length ? (d.costs || []).map((c) => `<div class="row between"><span>${esc(c.kind)}${c.paid_to ? ' · ' + esc(c.paid_to) : ''}${c.state === 'void' ? ' (voided)' : ''}</span><span>${esc(fmt.money(c.amount))} ${c.state === 'active' ? btn('c2_ord_costvoid', 'Void', '').replace('data-id="' + esc(id) + '"', 'data-id="' + esc(c.id) + '"') : ''}</span></div>`).join('') : '<p class="muted">not captured</p>'}</div>
    <div class="card stack"><b>Trail</b>${(d.events || []).map((e) => `<div class="muted" style="font-size:.8rem">${esc(String(e.at).slice(0, 16).replace('T', ' '))} · ${esc(e.to)} · ${esc(e.note || '')}</div>`).join('')}</div></div>`);
}
async function actOn(act, id, fn, args, ok) { try { await rpc(fn, args); toast(ok || 'Saved'); closeSheet(); await detail(id); } catch (e) { toast(C.errText(e)); } }
Object.assign(H, {
  c2_ord_apply: (a) => actOn('apply', a.dataset.id, 'c2_order_advance_apply', { p_order: a.dataset.id }),
  c2_ord_advpost: (a) => actOn('post', a.dataset.id, 'c2_order_advance_post', { p_order: a.dataset.id }),
  c2_ord_advvoid: (a) => { const why = window.prompt ? window.prompt('Reason') : ''; if (!why) return; return actOn('void', a.dataset.id, 'c2_order_advance_void', { p_order: a.dataset.id, p_note: why }); },
  c2_ord_refpay: (a) => actOn('pay', a.dataset.id, 'c2_order_refund_pay', { p_order: a.dataset.id, p_mode: null }),
  c2_ord_costvoid: (a) => { const why = window.prompt ? window.prompt('Reason') : ''; if (!why) return; return rpc('c2_order_cost_void', { p_cost: Number(a.dataset.id), p_note: why }).then(() => { toast('Saved'); closeSheet(); }, (e) => toast(C.errText(e))); },
});

// ----- capture helper for salesx.js (online orders) -----
const CK = { spec: { weight: '', flavour: '', message: '', design: '', photo: '' }, slot: { from: '', to: '', reason: '' }, had: { spec: false, slot: false }, kinds: null };
const inp = (id, label, v, extra) => `<label>${esc(label)}<input id="${id}" value="${esc(v)}" ${extra || ''}></label>`;
async function loadKinds() { if (CK.kinds) return CK.kinds; try { const r = await sb.from('option_lists').select('value_code,label_en,sort').eq('list_code', 'order_delivery_cost_kinds').eq('active', true).order('sort'); CK.kinds = (r.data || []).map((x) => [x.value_code, x.label_en || x.value_code]); } catch (e) { CK.kinds = []; } return CK.kinds; }
const c2orders = {
  init: async () => { const f = await features(); if (f && on('cost')) await loadKinds(); return f; },
  on, detail,
  async preload(order) {
    CK.spec = { weight: '', flavour: '', message: '', design: '', photo: '' }; CK.slot = { from: '', to: '', reason: '' }; CK.had = { spec: false, slot: false };
    if (!order || !O.f) return;
    try { const [s, p] = await Promise.all([sb.from('order_cake_specs').select('weight_kg,flavour,message,design,photo_ref').eq('order_id', order.id).eq('state', 'active').order('id').limit(1), sb.from('order_promises').select('slot_from,slot_to').eq('order_id', order.id).eq('state', 'active').order('id', { ascending: false }).limit(1)]);
      const c = (s.data || [])[0]; if (c) { CK.had.spec = true; CK.spec = { weight: c.weight_kg || '', flavour: c.flavour || '', message: c.message || '', design: c.design || '', photo: c.photo_ref || '' }; }
      const q = (p.data || [])[0]; if (q) { CK.had.slot = true; CK.slot = { from: hhmm(q.slot_from), to: hhmm(q.slot_to), reason: '' }; } } catch (e) { /* the fields stay empty */ }
  },
  formHTML() {
    if (!O.f || !(on('spec') || on('promise'))) return '';
    return `<div class="card stack" id="c2_cap">${on('promise') ? `<b>Promised time</b><div class="row wrap"><label>From <input id="c2_pf" type="time" value="${esc(CK.slot.from)}"></label><label>To <input id="c2_pt" type="time" value="${esc(CK.slot.to)}"></label></div>
      ${CK.had.slot ? inp('c2_pr', 'Reason for changing the time', CK.slot.reason, 'maxlength="300"') : ''}<p class="muted">The promised day is the delivery date above.</p>` : ''}
      ${on('spec') ? `<b>Cake specification (leave empty if not a cake)</b><div class="row wrap"><label>Weight kg <input id="c2_cw" inputmode="decimal" value="${esc(CK.spec.weight)}" style="max-width:6rem"></label>${inp('c2_cf', 'Flavour', CK.spec.flavour, 'maxlength="80"')}</div>
      ${inp('c2_cm', 'Message on the cake', CK.spec.message, 'maxlength="200"')}${inp('c2_cd', 'Design', CK.spec.design, 'maxlength="300"')}${inp('c2_cp', 'Photo reference', CK.spec.photo, 'maxlength="300"')}
      <label class="phadd">Take / choose photo <input type="file" accept="image/*" hidden id="c2_cfile"></label>` : ''}</div>`;
  },
  read() {
    const g = (id) => { const el = $('#' + id); return el ? el.value.trim() : ''; };
    const w = g('c2_cw'); const spec = { weight_kg: w === '' ? null : num(w), flavour: g('c2_cf') || null, message: g('c2_cm') || null, design: g('c2_cd') || null, photo_ref: g('c2_cp') || null };
    const hasSpec = !!(spec.weight_kg || spec.flavour || spec.message || spec.design || spec.photo_ref);
    return { spec, hasSpec, badWeight: w !== '' && !(num(w) > 0), from: g('c2_pf') || null, to: g('c2_pt') || null, reason: g('c2_pr') || null };
  },
  async afterSave(orderId, x) {
    if (!O.f || !x) return;
    try {
      if (on('spec') && (x.hasSpec || CK.had.spec)) await rpc('c2_order_spec_save', { p_order: orderId, p_specs: x.hasSpec ? [x.spec] : [], p_note: null });
      if (on('promise') && x.from) await rpc('c2_order_promise_set', { p_order: orderId, p_from: x.from, p_to: x.to, p_reason: x.reason });
    } catch (e) { toast(C.errText(e)); }
  },
  refundModeHTML(o) {
    if (!O.f || !on('cancel') || !(Number(o.advance) > 0)) return '';
    return `<label>Refund paid by<select id="c2_rfm"><option value="">Same as the advance</option><option value="cash">Cash</option><option value="mobile">Mobile money</option><option value="bank">Bank</option></select></label>
      <p class="muted">${esc(O.f.refund_record_on ? 'The refund is written as a real money record (paid now if you may move money, otherwise it waits as due).' : 'The refund switch is off: a refund writes no money record.')}</p>`;
  },
  cancelFn: () => (O.f && on('cancel') ? 'c2_order_cancel' : 'online_order_cancel'),
  cancelArgs(base) { return O.f && on('cancel') ? Object.assign({}, base, { p_refund_mode: ($('#c2_rfm') || {}).value || null }) : base; },
  deliverFn: () => (O.f && on('advance') ? 'c2_order_deliver' : 'online_order_deliver'),
  costFieldsHTML() {
    if (!O.f || !on('cost') || !CK.kinds || !CK.kinds.length) return '';
    return `<div class="card stack"><b>Actual delivery cost (optional)</b><div class="row wrap"><label>Kind <select id="c2_ck">${CK.kinds.map(([k, l]) => `<option value="${esc(k)}">${esc(l)}</option>`).join('')}</select></label><label>Amount <input id="c2_ca" inputmode="decimal" style="max-width:6rem"></label></div>
      ${inp('c2_cn', 'Who was paid / note', '', 'maxlength="60"')}<p class="muted">Information for costing only; it does not post to the books.</p></div>`;
  },
  async afterDeliver(orderId) {
    const a = num(($('#c2_ca') || {}).value); if (!O.f || !on('cost') || !(a > 0)) return;
    try { await rpc('c2_order_cost_add', { p_order: orderId, p_kind: $('#c2_ck').value, p_amount: a, p_paid_to: ($('#c2_cn') || {}).value || null, p_note: ($('#c2_cn') || {}).value || null, p_client: (crypto.randomUUID ? crypto.randomUUID() : null) }); toast('Delivery cost saved'); }
    catch (e) { toast(C.errText(e)); }
  },
  async attach(rows) {
    if (!O.f || !on('detail') || !rows || !rows.length) return;
    try { const d1 = rows.reduce((m, r) => (String(r.created_at).slice(0, 10) < m ? String(r.created_at).slice(0, 10) : m), today()); if ((new Date(today()) - new Date(d1)) / 864e5 > 1000) return;
      const r = await rpc('c2_order_register', { p_from: d1, p_to: today(), p_loc: null, p_source: 'app', p_status: null, p_by: 'order', p_limit: 2000 }); const m = {}; (r.rows || []).forEach((x) => { m[x.order_id] = x; });
      rows.forEach((o) => { o.c2 = m[o.id] || null; }); } catch (e) { /* the old figures stay */ }
  },
};
B.c2orders = c2orders;
B.c2link && B.c2link('c2_orders', 'orderreports', 'Order and delivery reports', 'c2_orders_features', () => ({}));
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { orderreports: view });
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'c2_cfile') { const f = e.target.files && e.target.files[0]; const U = B.s2; if (f && U && U.uploadPhoto) { toast('…'); U.uploadPhoto(f, ['POS', 'STOCK', '20-1'], (S.ctx.locations || [1])[0] || 1).then((p) => { const el = $('#c2_cp'); if (el) el.value = p; }, (er) => toast(String((er && er.message) || er))); } } });
})();
