/* Islamia BOS · Statements (#/statements): the books as statements, from the journal.
   Tab 1  P&L by month and outlet   (stmt_pl_matrix, stmt_pl_drill)       income, cost of goods, other expenses, gross and net, one cell per month and outlet; tap a cell for the accounts and entries behind it.
   Tab 2  Cash flow                  (stmt_cash_flow, stmt_cf_drill)       direct method: operating / investing / financing / unclassified, opening journals apart, moves between cash accounts netted.
   Tab 3  Working capital            (stmt_working_capital)                current assets - current liabilities by the class the owner gave each account, and the plain cash + receivables + inventory - payables formula.
   Tab 4  Classes                    (coa_class_list, coa_class_set, coa_class_apply_suggested)   which cash-flow class and which balance class each chart account has. BLANK = unclassified: nothing is guessed.
   Server: supabase/phase443.sql and phase444.sql (read only for the books; the class table is the only thing written, by the owner or an accounts manager, and every change is in the audit log).
   Without the accounting start date the server answers "accounting module not switched on - no data captured" and this page shows that and no number. English labels only (owner rule for the report screens). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm, openSheet } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: E('Statements'),
  tPl: E('P&L by month'), tCf: E('Cash flow'), tWc: E('Working capital'), tCls: E('Classes'),
  from: E('From (blank = start of the books)'), to: E('To'), asOf: E('As of'), place: E('Place'), allPlaces: E('All places'), show: E('Show'), csv: E('CSV'), loading: E('Loading...'),
  metric: E('Show'), mNet: E('Net profit'), mIncome: E('Income'), mCogs: E('Cost of goods'), mExp: E('Other expenses'), mGross: E('Gross profit'),
  outlet: E('Outlet'), total: E('Total'), unassigned: E('Not assigned to an outlet'), provisional: E('Provisional: some sales have no known cost in the books.'),
  mgmt: E('Compare with the management view'), openPc: E('Profit check'), openL1: E('Profit and loss (management view)'),
  accountsBehind: E('Accounts behind this cell'), entriesBehind: E('Biggest journal entries'), lines: E('lines'), noRows: E('Nothing in this period.'),
  opening: E('Opening cash'), closing: E('Closing cash'), flows: E('Cash flows'), operating: E('Operating'), investing: E('Investing'), financing: E('Financing'), unclassified: E('Unclassified'),
  in: E('In'), out: E('Out'), net: E('Net'), openingJ: E('Opening balances posted in the period (not a flow)'), transfers: E('Moves between cash accounts (netted, not a flow)'),
  agreeTab: E('Closing agrees with the Cash flow tab of Accounts'), differTab: E('Closing differs from the Cash flow tab of Accounts'), bySource: E('By source'),
  openThrough: E('Journals up to this date are opening balances'), openThroughHint: E('If you entered the opening balances as an ordinary manual journal, type its date here (YYYY-MM-DD). Blank: only journals of the kind "opening balances" are left out.'),
  save: E('Save'), saved: E('Saved'), ownerOnly: E('Only the owner can change this.'),
  wcClass: E('By class'), wcFormula: E('Plain formula'), curA: E('Current assets'), curL: E('Current liabilities'), ncA: E('Non-current assets'), ncL: E('Non-current liabilities'),
  unA: E('Assets with no class (not in working capital)'), unL: E('Liabilities with no class (not in working capital)'), wc: E('Working capital'), cash: E('Cash, bank and wallets'), recv: E('Customer receivables'), inv: E('Inventory'), pay: E('Supplier payables'),
  nocap: E('Not captured'),
  clsIntro: E('Give each chart account a cash-flow class (operating / investing / financing) and, for assets and liabilities, a balance class (current / non-current). Blank means unclassified: the statements show it as unclassified and never guess.'),
  code: E('Account'), cf: E('Cash-flow class'), bs: E('Balance class'), suggest: E('Usual practice'), blank: E('(blank)'), cashAcc: E('Cash account'), onlyBlank: E('Only accounts with a blank class'),
  preview: E('Fill the blanks with the usual practice (preview)'), apply: E('Apply'), willFill: E('accounts would get a class. Existing classes are never overwritten.'), reason: E('Reason (at least 5 letters)'),
  noperm: E('Not allowed'), expLock: E('Export not allowed'), readonly: E('Only the owner or an accounts manager can change the classes; the server refuses everybody else.'),
  needStart: E('The accounting module is not switched on - no data captured.'), date: E('Date'), memo: E('Details'), source: E('Source'), amount: E('Amount'), account: E('Account'),
  kind: E('Kind'), cogsMissing: E('Sales without a known cost'),
};
const T = (k) => lab(X[k]);
const ERR = { not_allowed: X.noperm, bad_range: E('The dates are not valid'), reason_required: E('Write a reason of at least 5 letters'), cash_account_has_no_flow_class: E('A cash account has no cash-flow class'),
  balance_class_is_for_assets_and_liabilities: E('A balance class is only for assets and liabilities'), bad_value: E('That value is not allowed'), account_not_found: E('Account not found') };
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x) || m.includes(x.replace(/_/g, ' '))); return k ? lab(ERR[k]) : /could not find|schema cache/i.test(m) ? lab(E('The database part is not installed yet (phases 443 and 444)')) : m || 'error'; };
const num = (n) => (n === null || n === undefined ? '-' : money(n));
const tx = (o, bn, en) => lab({ bn: o[bn] || o[en] || '', en: o[en] || o[bn] || '', mix: o[bn] || o[en] || '' });
const D = { tab: 'pl', from: null, to: null, asof: null, loc: '', metric: 'net', pl: null, cf: null, cfTab: null, wc: null, cls: null, onlyBlank: false, preview: null, err: null, busy: false, openThrough: null };
const locName = (id) => { if (id === null || id === undefined) return T('unassigned'); const l = (LOCS() || []).find((x) => Number(x.id) === Number(id)); return l ? nm(l) : '#' + id; };
const monthLabel = (m) => { const [y, mm] = String(m).split('-'); return ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][Number(mm) - 1] + ' ' + y; };
const locArg = () => (D.loc === '' ? null : Number(D.loc));
const owner = () => !!(S && S.ctx && S.ctx.is_owner);
const needStartHTML = (r) => `<div class="notice warn mk warn">${esc(r && (r.text_en || r.text_bn) ? tx(r, 'text_bn', 'text_en') : T('needStart'))}</div>`;
const notesHTML = (notes) => (notes || []).map((n) => `<div class="rp-note mk ${n.level === 'warn' ? 'warn' : 'info'}">${esc(tx(n, 'text_bn', 'text_en'))}</div>`).join('');
const basisHTML = (b) => (b ? `<p class="muted">${esc(tx(b, 'text_bn', 'text_en'))}</p>` : '');

// ---------- filters ----------
function locSel() {
  const locs = LOCS ? LOCS() : [];
  return `<div><label for="st_loc">${esc(T('place'))}</label><select id="st_loc"><option value="">${esc(T('allPlaces'))}</option>${locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>`;
}
function rangeHTML(withMetric) {
  return `<div class="card stack"><div><label for="st_from">${esc(T('from'))}</label><input id="st_from" type="date" value="${esc(D.from)}"></div>
    <div><label for="st_to">${esc(T('to'))}</label><input id="st_to" type="date" value="${esc(D.to)}"></div>${locSel()}
    ${withMetric ? `<div><label for="st_metric">${esc(T('metric'))}</label><select id="st_metric">${[['net', 'mNet'], ['income', 'mIncome'], ['cogs', 'mCogs'], ['expenses', 'mExp'], ['gross', 'mGross']].map(([v, k]) => `<option value="${v}" ${D.metric === v ? 'selected' : ''}>${esc(T(k))}</option>`).join('')}</select></div>` : ''}
    <button class="full primary" data-act="st_run">${esc(T('show'))}</button></div>`;
}
function readRange() {
  D.from = $('#st_from') ? $('#st_from').value : D.from; D.to = $('#st_to') ? $('#st_to').value : D.to; D.loc = $('#st_loc') ? $('#st_loc').value : D.loc;
  if ($('#st_metric')) D.metric = $('#st_metric').value;
  if ($('#st_asof')) D.asof = $('#st_asof').value;
  return !(D.tab !== 'wc' && D.from && D.to && D.to < D.from);
}

// ---------- tab 1: P&L by month and outlet ----------
const cellOf = (r, m, loc) => (r.cells || []).find((c) => c.month === m && (c.location_id === null || c.location_id === undefined ? loc === null : Number(c.location_id) === Number(loc)));
function plHTML() {
  const r = D.pl; if (!r) return '';
  if (r.data_needed) return needStartHTML(r);
  const months = r.months || [], outs = r.outlets || [], k = D.metric;
  const val = (o) => (o ? num(o[k]) : '-');
  const head = `<tr><th>${esc(T('outlet'))}</th>${months.map((m) => `<th class="n">${esc(monthLabel(m))}</th>`).join('')}<th class="n">${esc(T('total'))}</th></tr>`;
  const body = outs.map((o) => {
    const loc = o.location_id === undefined ? null : o.location_id;
    const tot = (r.by_outlet || []).find((x) => (x.location_id === null || x.location_id === undefined ? loc === null : Number(x.location_id) === Number(loc)));
    return `<tr><th scope="row">${esc(loc === null ? T('unassigned') : tx(o, 'name_bn', 'name_en'))}</th>${months.map((m) => { const c = cellOf(r, m, loc);
      return `<td class="n">${c ? `<button class="linkish" data-act="st_cell" data-m="${esc(m)}" data-l="${loc === null ? '' : loc}" aria-label="${esc(monthLabel(m) + ' ' + (loc === null ? T('unassigned') : tx(o, 'name_bn', 'name_en')) + ' ' + num(c[k]))}">${esc(num(c[k]))}</button>` : '-'}</td>`; }).join('')}<td class="n"><b>${esc(val(tot))}</b></td></tr>`;
  }).join('');
  const foot = `<tr><th>${esc(T('total'))}</th>${months.map((m) => `<td class="n"><b>${esc(val((r.by_month || []).find((x) => x.month === m)))}</b></td>`).join('')}<td class="n"><b>${esc(val(r.grand))}</b></td></tr>`;
  const g = r.grand || {};
  return `${r.provisional ? `<div class="notice warn mk warn">${esc(T('provisional'))} (${esc(String(r.cogs_missing_entries))})</div>` : ''}
    <div class="scrollx"><table class="rp-t" id="st_pl_tbl"><thead>${head}</thead><tbody>${body}</tbody><tfoot>${foot}</tfoot></table></div>
    <div class="stats"><div class="stat"><div class="k">${esc(T('mIncome'))}</div><div class="v">${esc(num(g.income))}</div></div><div class="stat"><div class="k">${esc(T('mCogs'))}</div><div class="v">${esc(num(g.cogs))}</div></div>
      <div class="stat"><div class="k">${esc(T('mExp'))}</div><div class="v">${esc(num(g.expenses))}</div></div><div class="stat"><div class="k">${esc(T('mNet'))}</div><div class="v">${esc(num(g.net))}</div></div></div>
    ${notesHTML(r.notes)}${basisHTML(r.basis)}
    <p class="muted">${esc(T('mgmt'))}: <a href="#/profitcheck">${esc(T('openPc'))}</a> · <a href="#/report/l1_pnl">${esc(T('openL1'))}</a></p>
    <div class="rp-foot"><button data-act="st_csv">${esc(T('csv'))}</button></div>`;
}
async function openCell(m, loc) {
  const r = await sb.rpc('stmt_pl_drill', { p_month: m + '-01', p_loc: loc === '' ? null : Number(loc), p_kind: 'all', p_unassigned: loc === '' });
  if (r.error) return toast(eText(r.error));
  const d = r.data || {}, c = cellOf(D.pl, m, loc === '' ? null : Number(loc)) || {};
  const accs = (d.accounts || []).map((a) => `<div class="row between"><span>${esc(a.code)} · ${esc(tx(a, 'name_bn', 'name_en'))} <small class="muted">${esc(String(a.lines))} ${esc(T('lines'))}</small></span><b>${esc(num(a.amount))}</b></div>`).join('');
  const ents = (d.entries || []).slice(0, 15).map((e) => `<div class="row between"><span>${esc(String(e.entry_date))} · ${esc(e.source_type || '')} <small class="muted">${esc(e.memo || '')}</small></span><b>${esc(num(e.amount))}</b></div>`).join('');
  openSheet(`<div class="stack"><h3>${esc(monthLabel(m))} · ${esc(locName(loc === '' ? null : Number(loc)))}</h3>
    <div class="row between"><span>${esc(T('mIncome'))}</span><b>${esc(num(c.income))}</b></div><div class="row between"><span>${esc(T('mCogs'))}</span><b>${esc(num(c.cogs))}</b></div>
    <div class="row between"><span>${esc(T('mExp'))}</span><b>${esc(num(c.expenses))}</b></div><div class="row between"><span>${esc(T('mNet'))}</span><b>${esc(num(c.net))}</b></div>
    <b>${esc(T('accountsBehind'))}</b>${accs || `<p class="muted">${esc(T('noRows'))}</p>`}<b>${esc(T('entriesBehind'))}</b>${ents || `<p class="muted">${esc(T('noRows'))}</p>`}</div>`);
}
function csvPl() {
  const C = B.c1, r = D.pl, months = r.months || [], out = [];
  const lines = [['outlet'].concat(months, ['total'])];
  ['income', 'cogs', 'gross', 'expenses', 'net'].forEach((k) => {
    lines.push([k]);
    (r.outlets || []).forEach((o) => { const loc = o.location_id === undefined ? null : o.location_id; const tot = (r.by_outlet || []).find((x) => (x.location_id === null || x.location_id === undefined ? loc === null : Number(x.location_id) === Number(loc)));
      lines.push([loc === null ? 'Not assigned to an outlet' : (o.name_en || o.name_bn)].concat(months.map((m) => { const c = cellOf(r, m, loc); return c ? c[k] : ''; }), [tot ? tot[k] : ''])); });
    lines.push(['Total'].concat(months.map((m) => { const x = (r.by_month || []).find((z) => z.month === m); return x ? x[k] : ''; }), [(r.grand || {})[k]]));
  });
  lines.forEach((l) => out.push(C.csvLine(l))); out.push('');
  C.metaLines('P&L by month and outlet (journal)', [['Period', r.from + ' - ' + r.to], ['Place', D.loc === '' ? 'All places' : locName(Number(D.loc))], ['Basis', (r.basis || {}).text_en || ''], ['Provisional', r.provisional ? 'yes' : 'no']]).forEach((m) => out.push(C.csvLine(m)));
  (r.notes || []).forEach((n) => out.push(C.csvLine([n.text_en])));
  return { name: `pl-by-month-${r.from}_${r.to}.csv`, text: C.csvFile(out), rows: (r.cells || []).length, key: 'stmt_pl_matrix' };
}

// ---------- tab 2: cash flow ----------
const CLS = { operating: 'operating', investing: 'investing', financing: 'financing', unclassified: 'unclassified' };
function cfHTML() {
  const r = D.cf; if (!r) return '';
  if (r.data_needed) return needStartHTML(r);
  const cls = (r.classes || []).map((c) => `<div class="card stack"><div class="row between"><button class="linkish" data-act="st_cfclass" data-c="${esc(c.class)}"><b>${esc(T(CLS[c.class] || c.class))}</b></button><b>${esc(num(c.net))}</b></div>
    <div class="row between muted"><span>${esc(T('in'))} ${esc(num(c.in))}</span><span>${esc(T('out'))} ${esc(num(c.out))}</span></div>
    ${(c.accounts || []).length ? `<details><summary>${esc(String(c.accounts.length))} ${esc(T('code'))}</summary>${c.accounts.map((a) => `<div class="row between"><button class="linkish" data-act="st_cfacc" data-c="${esc(c.class)}" data-a="${esc(a.account_id)}">${esc(a.code)} · ${esc(tx(a, 'name_bn', 'name_en'))}</button><span>${esc(num(a.net))}</span></div>`).join('')}</details>` : ''}</div>`).join('');
  const tab = D.cfTab && D.cfTab.closing !== undefined ? `<span class="chip ${Number(D.cfTab.closing) === Number(r.closing) ? 'ok' : 'warn'}">${esc(Number(D.cfTab.closing) === Number(r.closing) ? T('agreeTab') : T('differTab'))}</span>` : '';
  const src = (r.by_source || []).map((s) => `<div class="row between"><span>${esc(s.category)}</span><span>${esc(num(s.in))} / ${esc(num(s.out))} / <b>${esc(num(s.net))}</b></span></div>`).join('');
  const thr = owner() ? `<div class="card stack"><b>${esc(T('openThrough'))}</b><p class="muted">${esc(T('openThroughHint'))}</p><div class="row"><input id="st_thr" type="date" value="${esc(D.openThrough || r.opening_through || '')}" aria-label="${esc(T('openThrough'))}"><button data-act="st_thr_save">${esc(T('save'))}</button></div></div>`
    : (r.opening_through ? `<p class="muted">${esc(T('openThrough'))}: ${esc(String(r.opening_through))}</p>` : '');
  return `<div class="card stack"><div class="row between"><span>${esc(T('opening'))}</span><b>${esc(num(r.opening))}</b></div>
    <div class="row between"><span>${esc(T('flows'))}</span><b>${esc(num(r.flows))}</b></div>
    <div class="row between"><span>${esc(T('openingJ'))}</span><b>${esc(num(r.opening_in_period))}</b></div>
    <div class="row between"><span>${esc(T('closing'))}</span><b>${esc(num(r.closing))}</b></div>${tab}</div>
    ${cls}
    <div class="card stack"><div class="row between"><button class="linkish" data-act="st_cfclass" data-c="opening">${esc(T('openingJ'))}</button><b>${esc(num(r.opening_in_period))}</b></div>
      <div class="row between"><button class="linkish" data-act="st_cfclass" data-c="transfer">${esc(T('transfers'))}</button><b>${esc(num(r.transfers_netted))}</b></div></div>
    ${src ? `<details class="card stack"><summary><b>${esc(T('bySource'))}</b></summary>${src}</details>` : ''}
    ${notesHTML(r.notes)}${basisHTML(r.basis)}${thr}<div class="rp-foot"><button data-act="st_csv">${esc(T('csv'))}</button></div>`;
}
async function openCf(cls, acc) {
  const r = await sb.rpc('stmt_cf_drill', { p_from: D.cf.from, p_to: D.cf.to, p_loc: locArg(), p_class: cls, p_account: acc ? Number(acc) : null });
  if (r.error) return toast(eText(r.error));
  const rows = (r.data && r.data.rows) || [];
  openSheet(`<div class="stack"><h3>${esc(CLS[cls] ? T(CLS[cls]) : cls === 'opening' ? T('openingJ') : cls === 'transfer' ? T('transfers') : cls)}</h3>${rows.length ? rows.map((x) => `<div class="row between"><span>${esc(String(x.entry_date))} · ${esc(x.source_type || '')}${x.account_code ? ' · ' + esc(x.account_code) : ''}<small class="muted" style="display:block">${esc(x.memo || '')}</small></span><b>${esc(num(x.amount))}</b></div>`).join('') : `<p class="muted">${esc(T('noRows'))}</p>`}</div>`);
}
function csvCf() {
  const C = B.c1, r = D.cf, out = [C.csvLine(['class', 'account_code', 'account', 'in', 'out', 'net'])];
  (r.classes || []).forEach((c) => { out.push(C.csvLine([c.class, '', '', c.in, c.out, c.net])); (c.accounts || []).forEach((a) => out.push(C.csvLine([c.class, a.code, a.name_en || a.name_bn, a.in, a.out, a.net]))); });
  out.push(C.csvLine(['opening_journals_in_period', '', '', '', '', r.opening_in_period])); out.push(C.csvLine(['transfers_netted', '', '', '', '', r.transfers_netted]));
  out.push(C.csvLine(['source', '', 'category', 'in', 'out', 'net'])); (r.by_source || []).forEach((s) => out.push(C.csvLine(['source', '', s.category, s.in, s.out, s.net])));
  out.push('');
  C.metaLines('Cash-flow statement (journal, direct method)', [['Period', r.from + ' - ' + r.to], ['Place', D.loc === '' ? 'All places' : locName(Number(D.loc))], ['Opening', r.opening], ['Flows', r.flows], ['Opening journals in the period', r.opening_in_period],
    ['Closing', r.closing], ['Opening-balance date setting', r.opening_through || ''], ['Basis', (r.basis || {}).text_en || '']]).forEach((m) => out.push(C.csvLine(m)));
  (r.notes || []).forEach((n) => out.push(C.csvLine([n.text_en])));
  return { name: `cash-flow-${r.from}_${r.to}.csv`, text: C.csvFile(out), rows: (r.classes || []).length, key: 'stmt_cash_flow' };
}

// ---------- tab 3: working capital ----------
function accList(list) { return (list || []).map((a) => `<div class="row between"><span>${esc(a.code)} · ${esc(tx(a, 'name_bn', 'name_en'))}</span><span>${esc(num(a.amount))}</span></div>`).join(''); }
function wcHTML() {
  const r = D.wc; if (!r) return '';
  if (r.data_needed) return needStartHTML(r);
  const c = r.by_class || {}, t = c.totals || {}, f = r.formula || {};
  const wc = c.working_capital === null || c.working_capital === undefined ? `<span class="chip warn">${esc(T('nocap'))}</span>` : `<b>${esc(num(c.working_capital))}</b>`;
  const block = (label, list, total) => ((list || []).length ? `<div class="card stack"><div class="row between"><b>${esc(T(label))}</b><b>${esc(num(total))}</b></div>${accList(list)}</div>` : '');
  return `<div class="card stack"><div class="row between"><b>${esc(T('wcClass'))}</b></div>
      <div class="row between"><span>${esc(T('wc'))}</span>${wc}</div></div>
    ${block('curA', c.current_assets, t.current_assets)}${block('curL', c.current_liabilities, t.current_liabilities)}${block('ncA', c.non_current_assets, t.non_current_assets)}${block('ncL', c.non_current_liabilities, t.non_current_liabilities)}
    ${block('unA', c.unclassified_assets, t.unclassified_assets)}${block('unL', c.unclassified_liabilities, t.unclassified_liabilities)}
    <div class="card stack"><b>${esc(T('wcFormula'))}</b><div class="row between"><span>${esc(T('cash'))}</span><span>${esc(num(f.cash))}</span></div><div class="row between"><span>${esc(T('recv'))}</span><span>${esc(num(f.receivables))}</span></div>
      <div class="row between"><span>${esc(T('inv'))}</span><span>${esc(num(f.inventory))}</span></div><div class="row between"><span>${esc(T('pay'))}</span><span>- ${esc(num(f.payables))}</span></div>
      <div class="row between"><b>${esc(T('wc'))}</b><b>${esc(num(f.working_capital))}</b></div></div>
    ${notesHTML(r.notes)}${basisHTML(r.basis)}<div class="rp-foot"><button data-act="st_csv">${esc(T('csv'))}</button></div>`;
}
function csvWc() {
  const C = B.c1, r = D.wc, c = r.by_class || {}, f = r.formula || {}, out = [C.csvLine(['group', 'account_code', 'account', 'amount'])];
  [['current_assets', c.current_assets], ['current_liabilities', c.current_liabilities], ['non_current_assets', c.non_current_assets], ['non_current_liabilities', c.non_current_liabilities], ['unclassified_assets', c.unclassified_assets], ['unclassified_liabilities', c.unclassified_liabilities]]
    .forEach(([g, list]) => (list || []).forEach((a) => out.push(C.csvLine([g, a.code, a.name_en || a.name_bn, a.amount]))));
  out.push(''); out.push(C.csvLine(['working_capital_by_class', '', '', c.working_capital === null || c.working_capital === undefined ? 'not captured' : c.working_capital]));
  out.push(C.csvLine(['formula_cash', '', '', f.cash])); out.push(C.csvLine(['formula_receivables', '', '', f.receivables])); out.push(C.csvLine(['formula_inventory', '', '', f.inventory])); out.push(C.csvLine(['formula_payables', '', '', f.payables])); out.push(C.csvLine(['formula_working_capital', '', '', f.working_capital]));
  out.push(''); C.metaLines('Working capital (journal)', [['As of', r.as_of], ['Place', D.loc === '' ? 'All places' : locName(Number(D.loc))], ['Basis', (r.basis || {}).text_en || '']]).forEach((m) => out.push(C.csvLine(m)));
  (r.notes || []).forEach((n) => out.push(C.csvLine([n.text_en])));
  return { name: `working-capital-${r.as_of}.csv`, text: C.csvFile(out), rows: 1, key: 'stmt_working_capital' };
}

// ---------- tab 4: classes ----------
const optSel = (vals, cur, dis) => `<select ${dis ? 'disabled' : ''}><option value="">${esc(T('blank'))}</option>${vals.map((v) => `<option value="${v}" ${cur === v ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select>`;
function clsHTML() {
  const list = D.cls; if (!list) return '';
  const rows = list.filter((a) => a.active !== false && (!D.onlyBlank || (!a.cf_class && !a.bs_class))).map((a) => {
    const noBs = !(a.type === 'asset' || a.type === 'liability');
    return `<div class="card stack" data-id="${esc(a.id)}"><div class="row between"><b>${esc(a.code)} · ${esc(tx(a, 'name_bn', 'name_en'))}</b><small class="muted">${esc(a.type)}${a.is_cash ? ' · ' + esc(T('cashAcc')) : ''}</small></div>
      <div class="row wrap"><label>${esc(T('cf'))} ${optSel(['operating', 'investing', 'financing'], a.cf_class, a.is_cash)}</label><label>${esc(T('bs'))} ${optSel(['current', 'non_current'], a.bs_class, noBs)}</label>
        <button data-act="st_clsave" data-id="${esc(a.id)}">${esc(T('save'))}</button></div>
      <small class="muted">${esc(T('suggest'))}: ${esc(a.suggest_cf || '-')} / ${esc(a.suggest_bs || '-')}</small></div>`; }).join('');
  const pv = D.preview ? `<div class="card stack"><p>${esc(String(D.preview.accounts))} ${esc(T('willFill'))}</p><input id="st_clwhy" autocomplete="off" aria-label="${esc(T('reason'))}" placeholder="${esc(T('reason'))}"><button class="primary" data-act="st_clapply">${esc(T('apply'))}</button></div>` : '';
  return `<p class="muted">${esc(T('clsIntro'))}</p><p class="muted">${esc(T('readonly'))}</p>
    <div class="row wrap"><button type="button" class="chip ${D.onlyBlank ? 'ok' : ''}" data-act="st_clblank" aria-pressed="${D.onlyBlank}">${esc(T('onlyBlank'))}</button>
      <button data-act="st_clprev">${esc(T('preview'))}</button><button data-act="st_csv">${esc(T('csv'))}</button></div>${pv}${rows}`;
}
function csvCls() {
  const C = B.c1, out = [C.csvLine(['code', 'name', 'type', 'cash_account', 'cash_flow_class', 'balance_class', 'suggested_cash_flow', 'suggested_balance'])];
  (D.cls || []).forEach((a) => out.push(C.csvLine([a.code, a.name_en || a.name_bn, a.type, a.is_cash ? 'yes' : 'no', a.cf_class || '', a.bs_class || '', a.suggest_cf || '', a.suggest_bs || ''])));
  out.push(''); C.metaLines('Account classes (blank = unclassified)', []).forEach((m) => out.push(C.csvLine(m)));
  return { name: 'account-classes.csv', text: C.csvFile(out), rows: (D.cls || []).length, key: 'coa_classes' };
}

// ---------- page ----------
function body() {
  const tabs = [['pl', 'tPl'], ['cf', 'tCf'], ['wc', 'tWc'], ['cls', 'tCls']];
  const head = `<div class="tabs" role="tablist" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${tabs.map(([k, l]) => `<button type="button" role="tab" aria-selected="${D.tab === k}" data-act="st_tab" data-v="${k}" class="${D.tab === k ? 'on' : ''}" style="min-width:0;flex:1 1 22%">${esc(T(l))}</button>`).join('')}</div>`;
  const filt = D.tab === 'pl' ? rangeHTML(true) : D.tab === 'cf' ? rangeHTML(false)
    : D.tab === 'wc' ? `<div class="card stack"><div><label for="st_asof">${esc(T('asOf'))}</label><input id="st_asof" type="date" value="${esc(D.asof)}"></div>${locSel()}<button class="full primary" data-act="st_run">${esc(T('show'))}</button></div>` : '';
  const res = D.busy ? `<p class="muted">${esc(T('loading'))}</p>` : D.err ? `<div class="notice bad mk bad">${esc(D.err)}</div>` : D.tab === 'pl' ? plHTML() : D.tab === 'cf' ? cfHTML() : D.tab === 'wc' ? wcHTML() : clsHTML();
  return head + filt + `<div id="st_res">${res}</div>`;
}
function draw() { const el = $('#st_body'); if (el) el.innerHTML = body(); }
async function load() {
  D.err = null; D.busy = true; draw();
  try {
    let r;
    if (D.tab === 'pl') { r = await sb.rpc('stmt_pl_matrix', { p_from: D.from || null, p_to: D.to || null, p_loc: locArg() }); if (r.error) throw r.error; D.pl = r.data; }
    else if (D.tab === 'cf') {
      r = await sb.rpc('stmt_cash_flow', { p_from: D.from || null, p_to: D.to || null, p_loc: locArg() }); if (r.error) throw r.error; D.cf = r.data; D.cfTab = null;
      if (D.cf && !D.cf.data_needed) { try { const t = await sb.rpc('acct_cash_flow', { p_from: D.cf.from, p_to: D.cf.to, p_loc: locArg() }); if (t && !t.error && t.data) D.cfTab = t.data; } catch (e) { /* the accounts right is separate: the comparison line is simply not shown */ } }
    } else if (D.tab === 'wc') { r = await sb.rpc('stmt_working_capital', { p_as_of: D.asof || null, p_loc: locArg() }); if (r.error) throw r.error; D.wc = r.data; }
    else { r = await sb.rpc('coa_class_list'); if (r.error) throw r.error; D.cls = r.data || []; D.preview = null; }
  } catch (e) { D.err = eText(e); }
  D.busy = false; draw();
}
async function exportCSV() {
  const C = B.c1, f = D.tab === 'pl' ? D.pl && !D.pl.data_needed && csvPl : D.tab === 'cf' ? D.cf && !D.cf.data_needed && csvCf : D.tab === 'wc' ? D.wc && !D.wc.data_needed && csvWc : D.cls && csvCls;
  if (!f) return;
  const file = f();
  if (!(await C.exportOk(file.key, 'csv', { tab: D.tab, from: D.from, to: D.to, asof: D.asof, loc: D.loc || null }, file.rows))) return;
  C.download(file.name, file.text); C.expDone();
}
async function saveRule(k, v) {
  const r = await sb.rpc('set_rule', { p_key: k, p_value: v }); if (r.error) return toast(eText(r.error));
  try { if (B.reloadRules) await B.reloadRules(); } catch (e) { /* ignore */ }
  toast(T('saved'));
}
Object.assign(H, {
  st_tab: async (a) => { D.tab = a.dataset.v; D.err = null; if (D.tab === 'cls' && !D.cls) return load(); draw(); },
  st_run: () => { if (!readRange()) return toast(lab(ERR.bad_range)); return load(); },
  st_cell: (a) => openCell(a.dataset.m, a.dataset.l),
  st_cfclass: (a) => openCf(a.dataset.c, null),
  st_cfacc: (a) => openCf(a.dataset.c, a.dataset.a),
  st_thr_save: async () => { const v = ($('#st_thr').value || '').trim(); D.openThrough = v; await saveRule('report_cf_opening_through', v === '' ? null : v); return load(); },
  st_csv: exportCSV,
  st_clblank: () => { D.onlyBlank = !D.onlyBlank; draw(); },
  st_clsave: async (a) => {
    const card = a.closest('.card'), sels = card.querySelectorAll('select');
    const r = await sb.rpc('coa_class_set', { p_account: Number(a.dataset.id), p_cf: sels[0].value || null, p_bs: sels[1].value || null, p_reason: 'set on the Statements screen' });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); return load();
  },
  st_clprev: async () => { const r = await sb.rpc('coa_class_apply_suggested', { p_reason: null, p_dry: true }); if (r.error) return toast(eText(r.error)); D.preview = r.data; draw(); },
  st_clapply: async () => {
    const why = ($('#st_clwhy').value || '').trim(); if (why.length < 5) return toast(lab(ERR.reason_required));
    const r = await sb.rpc('coa_class_apply_suggested', { p_reason: why, p_dry: false }); if (r.error) return toast(eText(r.error)); toast(T('saved')); D.preview = null; return load();
  },
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const t = today(); D.to = t; D.from = ''; D.asof = t; D.loc = ''; D.pl = D.cf = D.wc = D.cls = null; D.err = null; D.preview = null;
  shell(T('title'), '<div id="st_body"></div>', true);
  draw();
  try { await load(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { statements: view });
})();
