/* Islamia BOS · Customer insight (#/custinsight): #138 credit risk and overdue, #139 lifetime value (no 365-day cap), #140 returns and complaints per customer, #141 special-order (cake) history, the customer card,
   and the "dues not linked to a customer" notice. Credit days per customer are set here (owner or customer_manage). Server: supabase/phase453.sql and phase454.sql. Reads only apart from the credit-days field.
   A missing figure is shown as "not captured", never 0. English labels (owner rule). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const C = B.c2ui;
if (!C) { console.warn('custinsight: c2rpt.js is not loaded'); return; }
const { esc, toast, H, openSheet, closeSheet } = A;
const { fmt, tableHTML, tiles, rpc, makePage } = C;
const $ = (s, el = document) => el.querySelector(s);
const mk = (k, h, f, extra) => Object.assign({ k, h, f }, extra || {});
const RISK = { ok: 'OK', watch: 'Watch', high: 'High risk', rule_not_set: 'Rule not set', no_terms: 'No credit terms' };
const SRC = { app: 'App order', paper_20_1: 'Paper 05-1' };
const NL = { opening_not_counted: 'Opening dues entered but not counted in the dues lists (the opening-dues link is off)', sales_due_no_customer: 'Sales with an amount due but no customer', journal_receivable_no_customer: 'Receivable in the books with no customer' };
const card = (id) => openCard(id);
const locless = () => null;
const TABS = [
  { id: 'credit', label: 'Credit and overdue', intro: '#138 · Customers who owe: balance (same figure as the dues list), credit days, overdue amount, days past due, limit used and risk.', filters: ['asof', 'search'],
    extra: [{ html: (f) => `<label><input type="checkbox" id="c2_ov" ${f.ov ? 'checked' : ''}> Only customers with an overdue amount</label>`, read: (f) => { f.ov = !!($('#c2_ov') && $('#c2_ov').checked); } }],
    run: async (f) => { const r = await rpc('c2_credit_risk', { p_as_of: f.asof || null, p_only_overdue: !!f.ov, p_search: f.search || null }); try { r.notice = await rpc('c2_dues_not_linked_notice', {}); } catch (e) { r.notice = null; } return r; },
    render: (r) => { const s = r.summary || {}; const n = (r.notice && r.notice.items) || [];
      return (n.length ? `<div class="notice warn"><b>Dues not linked to a customer</b>${n.map((i) => `<p style="margin:3px 0">${esc(NL[i.code] || i.code)}: ${esc(fmt.money(i.amount))} (${esc(i.count)}) <a href="#/${esc(i.fix_route)}">open</a></p>`).join('')}</div>` : '')
        + tiles([['Customers owing', fmt.int(s.customers_owing)], ['Balance', fmt.money(s.balance_total)], ['Overdue', fmt.money(s.overdue_total)], ['Customers overdue', fmt.int(s.customers_overdue)], ['Owing, no terms', fmt.int(s.owing_without_terms)], ['Over limit', fmt.int(s.over_limit)], ['Watch', fmt.int(s.watch)], ['High risk', fmt.int(s.high)]])
        + tableHTML({ name: 'credit-risk', rows: r.rows, drill: (x) => card(x.customer_id), cols: [mk('name', 'Customer', 'text'), mk('mobile', 'Mobile', 'text'), mk('balance', 'Balance', 'money'), mk('oldest_open', 'Oldest open', 'date'), mk('terms_days', 'Credit days', 'int'), mk('terms_source', 'Terms from', 'text', { words: { customer: 'Customer', default: 'Default', none: 'None' } }),
          mk('overdue', 'Overdue', 'money'), mk('days_past_due', 'Days past due', 'int'), mk('credit_limit', 'Limit', 'money'), mk('limit_used_pct', 'Limit used', 'pct'), mk('advance_held', 'Advance held', 'money'), mk('advance_applied', 'Advance applied', 'money'), mk('risk', 'Risk', 'text', { words: RISK })] }); } },
  { id: 'ltv', label: 'Lifetime value', intro: '#139 · All time by default (no 365-day cap). Give both dates to look at a window. Margin only where the cost of the sale is known.', filters: ['search'],
    extra: [{ html: (f) => `<div class="row wrap"><label>From <input type="date" id="c2_lf" value="${esc(f.lf || '')}"></label><label>To <input type="date" id="c2_lt" value="${esc(f.lt || '')}"></label></div><p class="muted">Leave both empty for all time.</p>`, read: (f, g) => { f.lf = g('c2_lf') || ''; f.lt = g('c2_lt') || ''; } }],
    run: (f) => rpc('c2_customer_ltv', { p_from: f.lf || null, p_to: f.lt || null, p_search: f.search || null, p_limit: 2000, p_customer: null }),
    render: (r) => { const s = r.summary || {}; return tiles([['Customers', fmt.int(s.customers)], ['Orders', fmt.int(s.orders)], ['Revenue', fmt.money(s.revenue)], ['Returns', fmt.money(s.returns)], ['Net revenue', fmt.money(s.net_revenue)], ['Sales with no customer', fmt.int(s.sales_without_customer)], ['…their revenue', fmt.money(s.revenue_without_customer)]])
      + tableHTML({ name: 'customer-ltv', rows: r.rows, drill: (x) => card(x.customer_id), cols: [mk('name', 'Customer', 'text'), mk('mobile', 'Mobile', 'text'), mk('orders', 'Orders', 'int'), mk('revenue', 'Revenue', 'money'), mk('returns', 'Returns', 'money'), mk('net_revenue', 'Net', 'money'), mk('avg_order', 'Average bill', 'money'),
        mk('first_sale', 'First sale', 'date'), mk('last_sale', 'Last sale', 'date'), mk('days_as_customer', 'Days as customer', 'int'), mk('days_since_last', 'Days since last', 'int'), mk('gross_margin', 'Gross margin', 'money'), mk('sales_with_known_cost', 'Sales with known cost', 'int')] }); } },
  { id: 'returns', label: 'Returns and complaints', intro: '#140 · Sale returns per customer, and complaints written on the paper register 32-1 matched by the phone number on the sheet.', filters: ['range', 'search'],
    run: (f) => rpc('c2_customer_returns', { p_from: f.from, p_to: f.to, p_search: f.search || null, p_customer: null }),
    render: (r) => { const s = r.summary || {}; return tiles([['Customers', fmt.int(s.customers)], ['Returns', fmt.int(s.returns)], ['Return value', fmt.money(s.return_amount)], ['Complaints linked', fmt.int(s.complaints_linked)], ['Complaint sheets', fmt.int(s.complaint_sheets_total)], ['Sheets with no phone', fmt.int(s.complaint_sheets_without_phone)],
        ['Phone not a customer', fmt.int(s.complaint_sheets_phone_not_a_customer)], ['Returns with no customer', fmt.int(s.returns_without_customer)]])
      + tableHTML({ name: 'customer-returns', rows: r.rows, drill: (x) => card(x.customer_id), cols: [mk('name', 'Customer', 'text'), mk('mobile', 'Mobile', 'text'), mk('returns', 'Returns', 'int'), mk('return_amount', 'Return value', 'money'), mk('last_return', 'Last return', 'date'), mk('top_reason', 'Top reason', 'text'), mk('complaints', 'Complaints', 'int'),
        mk('sick_cases', 'Fell ill', 'int'), mk('complaint_refunds', 'Refunds on sheets', 'money'), mk('last_complaint', 'Last complaint', 'date'), mk('causes', 'Causes', 'text', { get: (x) => Object.keys(x.causes || {}).map((k) => k + ' ' + x.causes[k]).join(', ') })] }); } },
  { id: 'special', label: 'Special orders', intro: '#141 · Cake and custom order history per customer: app orders with a specification and paper 05-1 custom sheets, matched by mobile number.', filters: ['range', 'search'],
    run: (f) => rpc('c2_customer_special_orders', { p_from: f.from, p_to: f.to, p_search: f.search || null, p_customer: null }),
    render: (r) => { const s = r.summary || {}; return tiles([['Order rows', fmt.int(s.special_order_rows)], ['Customers', fmt.int(s.customers)], ['Rows with no customer match', fmt.int(s.rows_without_a_customer_match)]])
      + tableHTML({ name: 'special-customers', title: 'By customer', rows: r.customers, drill: (x) => card(x.customer_id), cols: [mk('name', 'Customer', 'text'), mk('mobile', 'Mobile', 'text'), mk('special_orders', 'Special orders', 'int'), mk('last', 'Last', 'date'), mk('flavours', 'Flavours', 'text', { get: (x) => (x.flavours || []).join(', ') }),
        mk('birthday', 'Birthday', 'date'), mk('next_birthday_in_days', 'Birthday in (days)', 'int'), mk('anniversary', 'Anniversary', 'date'), mk('next_anniversary_in_days', 'Anniversary in (days)', 'int')] })
      + tableHTML({ name: 'special-orders', title: 'Every order', rows: r.rows, cols: [mk('name', 'Customer', 'text'), mk('source', 'Source', 'text', { words: SRC }), mk('ref', 'Ref', 'text'), mk('order_date', 'Taken', 'date'), mk('delivery_date', 'Delivery', 'date'), mk('flavour', 'Flavour', 'text'), mk('weight_kg', 'Weight kg', 'num'), mk('message', 'Message', 'text'), mk('design', 'Design', 'text'), mk('total', 'Total', 'money'), mk('status', 'Status', 'text')] }); } },
];
const view = makePage({ route: 'custinsight', prefix: 'ci', title: 'Customer insight', intro: 'Credit, lifetime value, returns, complaints and cake orders per customer. Read only except the credit days.', tabs: TABS });

async function openCard(id) {
  let d; try { d = await rpc('c2_customer_card', { p_customer: id }); } catch (e) { return toast(C.errText(e)); }
  const c = d.customer || {}, cr = d.credit, lt = d.ltv, rt = d.returns_last_365_days, so = d.special_orders_last_365_days || [];
  const r2 = (l, v) => `<div class="row between"><span class="muted">${esc(l)}</span><span>${v === null || v === undefined || v === '' ? '<span class="muted">—</span>' : esc(v)}</span></div>`;
  openSheet(`<div class="stack"><h3>${esc(c.name)}</h3>${c.mobile ? `<div class="muted">${esc(c.mobile)}</div>` : ''}
    <div class="card stack"><b>Credit</b>${r2('Credit days (own)', c.credit_days)}${r2('Default credit days', c.default_credit_days)}${r2('Credit limit', fmt.money(c.credit_limit))}
      ${cr ? r2('Balance', fmt.money(cr.balance)) + r2('Overdue', fmt.money(cr.overdue)) + r2('Days past due', cr.days_past_due) + r2('Risk', RISK[cr.risk] || cr.risk) + r2('Advance held', fmt.money(cr.advance_held)) : '<p class="muted">Nothing owed.</p>'}
      ${d.can_edit_terms ? `<div class="row"><input id="c2_cd" inputmode="numeric" placeholder="days" value="${esc(c.credit_days === null || c.credit_days === undefined ? '' : c.credit_days)}" style="max-width:6rem"><input id="c2_cdr" placeholder="reason (if changing)"><button class="mini primary" data-act="ci_setdays" data-id="${esc(c.id)}">Save days</button></div>` : ''}</div>
    <div class="card stack"><b>Lifetime</b>${lt ? r2('Orders', fmt.int(lt.orders)) + r2('Revenue', fmt.money(lt.revenue)) + r2('Net of returns', fmt.money(lt.net_revenue)) + r2('First sale', lt.first_sale) + r2('Last sale', lt.last_sale) : '<p class="muted">No sales.</p>'}</div>
    <div class="card stack"><b>Returns and complaints (last 365 days)</b>${rt ? r2('Returns', fmt.int(rt.returns)) + r2('Return value', fmt.money(rt.return_amount)) + r2('Complaints', fmt.int(rt.complaints)) : '<p class="muted">None.</p>'}</div>
    <div class="card stack"><b>Special orders (last 365 days)</b>${so.length ? so.map((x) => `<div>${esc([x.order_date, x.source === 'app' ? 'App' : 'Paper', x.flavour, x.weight_kg ? x.weight_kg + ' kg' : '', x.message].filter(Boolean).join(' · '))}</div>`).join('') : '<p class="muted">None.</p>'}${c.birthday ? r2('Birthday', c.birthday) : ''}</div></div>`);
}
Object.assign(H, {
  ci_setdays: async (a) => {
    const raw = ($('#c2_cd') || {}).value.trim(); const days = raw === '' ? null : Number(raw);
    if (days !== null && !(Number.isInteger(days) && days >= 0)) return toast('Enter whole days, 0 or more');
    try { await rpc('c2_customer_credit_days_set', { p_customer: a.dataset.id, p_days: days, p_reason: ($('#c2_cdr') || {}).value || null }); toast('Saved'); closeSheet(); await openCard(a.dataset.id); }
    catch (e) { toast(/reason_required/.test(e.message) ? 'Write a reason to change existing credit days' : C.errText(e)); }
  },
});
B.c2link && B.c2link('c2_cust', 'custinsight', 'Customer insight (credit, lifetime value, returns, cake orders)', 'c2_dues_not_linked_notice', () => ({}));
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { custinsight: view });
})();
