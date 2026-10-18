/* Islamia BOS · Expense register (#/expenseregister): ONE list of every expense line, voucher by voucher, with the three totals side by side.
   The same period had three different expense totals (the expense report, the P&L and day book, the journal) and no screen listed the vouchers behind them. This one does:
   expense vouchers 10-2 (every status), quick expenses, bank charges, mobile wallet fees, and the marketing register 18-1 (shown as "not in the books").
   Every line says which of the three totals counts it. A basis selector (all lines / expense report / P&L and day book / journal) shows the lines behind one total. The reconciliation says why the totals differ.
   Server: supabase/phase442.sql (expense_register, read only), phase444.sql (c1_export_log for the CSV). The page only shows and sends; the server decides every right and every number.
   Nothing depends on a capture switch: the register is open to the people who may read the expense report (or the accounts). English labels only (owner rule for the report screens). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const E = (s) => L(s, s, s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: E('Expense register'),
  intro: E('Every expense line in one list. The expense report, the P&L and the journal count expenses in three different ways, so their totals differ. Each line below shows which total counts it.'),
  from: E('From'), to: E('To'), place: E('Place'), allPlaces: E('All places'), basis: E('Show the lines that'), status: E('Status'), anyStatus: E('Any status'), show: E('Show'),
  bAll: E('Every line'), bReport: E('The expense report counts'), bPl: E('The P&L and day book count'), bJournal: E('The journal counts'),
  kinds: E('Kinds'), kVoucher: E('Vouchers 10-2'), kQuick: E('Quick expenses'), kBank: E('Bank charges'), kWallet: E('Wallet fees'), kMkt: E('Marketing 18-1'),
  tReport: E('Expense report'), tPl: E('P&L'), tDay: E('Day book'), tJournal: E('Journal'), tNot: E('Not in the books'), tapTotal: E('Tap a total to list the lines it counts.'),
  agree: E('The totals agree'), differ: E('The totals differ'), recon: E('Why the totals differ'), line: E('Line'), diffPl: E('P&L - report'), diffJr: E('Journal - P&L'), why: E('Why'),
  waiting: E('Approved, not posted to the journal yet'), shown: E('Shown'), lines: E('lines'), more: E('Show more'), none: E('No expense line in this period and these places.'),
  inRep: E('Expense report'), inPl: E('P&L'), inJr: E('Journal'), posted: E('Posted'), notPosted: E('Not posted yet'), noReceipt: E('No receipt'), unreadable: E('Unreadable amount'),
  paidTo: E('Paid to'), ref: E('Reference'), mode: E('Paid by'), staff: E('Entered by'), heads: E('Heads'), openSrc: E('Open the record'), csv: E('CSV'), loading: E('Loading...'),
  setting: E('Settings used'), expLock: E('Export not allowed'), noperm: E('Not allowed'), flags: E('Notes on this line'), amt: E('Amount'), date: E('Date'), kind: E('Kind'),
  fNotInBooks: E('Not in the books'), fMaybeVoucher: E('The same spend may also be typed as a voucher'), fShadow: E('A copy of another record'), fUnreadable: E('Has an amount that cannot be read'), fNoReceipt: E('No receipt'),
  yes: E('yes'), no: E('no'),
};
const T = (k) => lab(X[k]);
const ERR = { not_allowed: X.noperm, bad_range: E('The dates are not valid (at most one year)'), bad_basis: E('Choose a basis from the list') };
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x) || m.includes(x.replace(/_/g, ' '))); return k ? lab(ERR[k]) : /could not find|schema cache/i.test(m) ? lab(E('The database part is not installed yet (phase 442)')) : m || 'error'; };
const KINDS = [['voucher', 'kVoucher'], ['quick', 'kQuick'], ['bank_charge', 'kBank'], ['wallet_fee', 'kWallet'], ['marketing', 'kMkt']];
const FLAGS = { not_in_books: 'fNotInBooks', maybe_in_voucher: 'fMaybeVoucher', shadow: 'fShadow', unreadable_lines: 'fUnreadable', no_receipt: 'fNoReceipt' };
const PAGE = 100;
const D = { from: null, to: null, loc: '', basis: 'all', kinds: [], status: '', data: null, rows: [], loading: false, err: null, tok: 0 };
const num = (n) => (n === null || n === undefined ? '-' : money(n));
const locName = (id) => { const l = (LOCS() || []).find((x) => Number(x.id) === Number(id)); return l ? nm(l) : (id === null || id === undefined ? '-' : '#' + id); };
const tx = (o, bn, en) => lab({ bn: o[bn] || o[en] || '', en: o[en] || o[bn] || '', mix: o[bn] || o[en] || '' });

function args(offset, limit) {
  return { p_from: D.from, p_to: D.to, p_loc: D.loc === '' ? null : Number(D.loc), p_basis: D.basis, p_kinds: D.kinds.length ? D.kinds : null, p_status: D.status || null, p_limit: limit || PAGE, p_offset: offset || 0 };
}
async function run(append) {
  const tok = ++D.tok; D.loading = true; D.err = null;
  if (!append) { D.rows = []; D.data = null; }
  draw();
  let r; try { r = await sb.rpc('expense_register', args(append ? D.rows.length : 0)); } catch (e) { r = { error: e }; }
  if (tok !== D.tok) return; D.loading = false;
  if (r.error || !r.data) { D.err = eText(r.error || { message: 'empty' }); draw(); return; }
  D.data = r.data; D.rows = append ? D.rows.concat(r.data.rows || []) : (r.data.rows || []);
  draw();
}

function filterHTML() {
  const locs = LOCS ? LOCS() : [];
  const opt = (v, k) => `<option value="${v}" ${D.basis === v ? 'selected' : ''}>${esc(T(k))}</option>`;
  return `<div class="card stack">
    <div><label for="er_from">${esc(T('from'))}</label><input id="er_from" type="date" value="${esc(D.from)}"></div>
    <div><label for="er_to">${esc(T('to'))}</label><input id="er_to" type="date" value="${esc(D.to)}"></div>
    <div><label for="er_loc">${esc(T('place'))}</label><select id="er_loc"><option value="">${esc(T('allPlaces'))}</option>${locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="er_basis">${esc(T('basis'))}</label><select id="er_basis">${opt('all', 'bAll')}${opt('report', 'bReport')}${opt('pl', 'bPl')}${opt('journal', 'bJournal')}</select></div>
    <div><label for="er_status">${esc(T('status'))}</label><select id="er_status"><option value="">${esc(T('anyStatus'))}</option>${['draft', 'submitted', 'approved', 'done', 'rejected', 'void'].map((s) => `<option value="${s}" ${D.status === s ? 'selected' : ''}>${esc(s)}</option>`).join('')}</select></div>
    <div class="row wrap" role="group" aria-label="${esc(T('kinds'))}">${KINDS.map(([k, l]) => `<button type="button" class="chip ${D.kinds.includes(k) ? 'ok' : ''}" data-act="er_kind" data-k="${k}" aria-pressed="${D.kinds.includes(k)}">${esc(T(l))}</button>`).join('')}</div>
    <button class="full primary" data-act="er_run">${esc(T('show'))}</button></div>`;
}
function totalsHTML(d) {
  const t = d.totals || {}, rec = d.recon || {};
  const card = (b, label, v, extra) => `<button type="button" class="card stack er-tot ${D.basis === b ? 'on' : ''}" data-act="er_basis" data-b="${b}" aria-label="${esc(label + ' ' + num(v))}"><small class="muted">${esc(label)}</small><b>${esc(num(v))}</b>${extra || ''}</button>`;
  return `<div class="er-tots" style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${card('report', T('tReport'), t.report)}${card('pl', T('tPl'), t.pl, `<small class="muted">${esc(T('tDay'))} ${esc(num(t.daybook))}</small>`)}
    ${card('journal', T('tJournal'), t.journal, Number(t.journal_posted) !== Number(t.journal) ? `<small class="muted">${esc(T('posted'))} ${esc(num(t.journal_posted))}</small>` : '')}
    <div class="card stack"><small class="muted">${esc(T('tNot'))}</small><b>${esc(num(t.not_in_books))}</b><small class="muted">18-1</small></div></div>
    <p class="muted">${esc(T('tapTotal'))} <span class="chip ${rec.agree ? 'ok' : 'warn'}">${esc(rec.agree ? T('agree') : T('differ'))}</span></p>`;
}
function reconHTML(d) {
  const rec = d.recon || {}, lines = rec.lines || [];
  const unp = rec.unposted && Number(rec.unposted.n) > 0 ? `<p class="notice warn mk warn">${esc(T('waiting'))}: ${esc(String(rec.unposted.n))} / ${esc(num(rec.unposted.amount))}</p>` : '';
  const rows = lines.map((l) => `<tr><th scope="row">${esc(tx(l, 'label_bn', 'label_en'))}<small class="muted"> ${esc(String(l.n))}</small></th><td class="n">${esc(num(l.report))}</td><td class="n">${esc(num(l.pl))}</td><td class="n">${esc(num(l.journal))}</td>
    <td>${l.why_en || l.why_bn ? esc(tx(l, 'why_bn', 'why_en')) : ''}</td></tr>`).join('');
  return `<details class="card stack er-recon" ${rec.agree ? '' : 'open'}><summary><b>${esc(T('recon'))}</b></summary><p>${esc(tx(rec, 'summary_bn', 'summary_en'))}</p>${unp}
    <div class="scrollx"><table class="rp-t"><thead><tr><th>${esc(T('line'))}</th><th class="n">${esc(T('tReport'))}</th><th class="n">${esc(T('tPl'))}</th><th class="n">${esc(T('tJournal'))}</th><th>${esc(T('why'))}</th></tr></thead><tbody>${rows}</tbody></table></div></details>`;
}
function rowHTML(r, i) {
  const kk = KINDS.find((k) => k[0] === r.kind), kindTxt = kk ? T(kk[1]) : r.kind;
  const tick = (ok, k) => `<span class="chip ${ok ? 'ok' : ''}">${esc(T(k))} ${esc(ok ? '✓' : '–')}</span>`;
  const st = r.status && !['done'].includes(r.status) ? `<span class="chip ${r.status === 'void' || r.status === 'rejected' ? 'bad' : ''}">${esc(r.status)}</span>` : '';
  return `<div class="card stack tap" role="button" tabindex="0" data-act="er_open" data-i="${i}">
    <div class="row between"><b>${esc(String(r.entry_date || ''))}</b><b>${esc(num(r.amount))}</b></div>
    <div class="row between wrap"><span>${esc(kindTxt)} ${st}</span><span class="muted">${esc(locName(r.location_id))}</span></div>
    <div class="muted">${esc([r.paid_to, r.ref].filter(Boolean).join(' · '))}</div>
    <div class="row wrap">${tick(r.in_report, 'inRep')}${tick(r.in_pl, 'inPl')}${tick(r.in_journal, 'inJr')}${r.in_journal && !r.posted ? `<span class="chip warn">${esc(T('notPosted'))}</span>` : ''}</div></div>`;
}
function draw() {
  const el = $('#er_res'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="notice bad mk bad">${esc(D.err)}</div>`; return; }
  if (D.loading && !D.data) { el.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`; return; }
  const d = D.data; if (!d) { el.innerHTML = ''; return; }
  const more = d.has_more ? `<button class="full" data-act="er_more" ${D.loading ? 'disabled' : ''}>${esc(T('more'))} · ${D.rows.length} / ${esc(String(d.count))}</button>` : '';
  const st = d.settings || {};
  el.innerHTML = `${totalsHTML(d)}${reconHTML(d)}
    <div class="row between"><b>${esc(T('shown'))}: ${esc(String(d.count))} ${esc(T('lines'))}</b><b>${esc(num(d.shown_amount))}</b></div>
    ${D.rows.length ? D.rows.map(rowHTML).join('') : `<p class="notice warn mk warn">${esc(T('none'))}</p>`}${more}
    <div class="rp-foot"><button data-act="er_csv" ${D.rows.length ? '' : 'disabled'}>${esc(T('csv'))}</button></div>
    <p class="muted">${esc(T('setting'))}: expense_count_on = ${esc(String(st.expense_count_on))}; report_expense_parity_on = ${esc(String(st.report_expense_parity_on))}; d_wallet_fee_treatment = ${esc(String(st.d_wallet_fee_treatment))}</p>`;
}
function srcRoute(r) {
  if (r.kind === 'voucher' && r.source_id) return '#/entry/' + r.source_id;
  if (r.kind === 'marketing' && r.source_id) return '#/entry/' + String(r.source_id).split(':')[0];
  if (r.kind === 'quick') return '#/quickexp';
  if (r.kind === 'bank_charge') return '#/moneyaccounts';
  if (r.kind === 'wallet_fee') return '#/wallets';
  return null;
}
function openRow(i) {
  const r = D.rows[i]; if (!r) return;
  const route = srcRoute(r);
  const heads = Array.isArray(r.heads) && r.heads.length ? `<div class="stack"><b>${esc(T('heads'))}</b>${r.heads.map((h) => `<div class="row between"><span>${esc(((((D.data.labels || {}).expense_heads || {})[h.head]) ? tx(D.data.labels.expense_heads[h.head], 'bn', 'en') : (h.head || '-')))}</span><b>${esc(num(h.amount))}</b></div>`).join('')}</div>` : '';
  const flags = (r.flags || []).map((f) => `<li>${esc(FLAGS[f] ? T(FLAGS[f]) : f)}</li>`).join('');
  openSheet(`<div class="stack"><h3>${esc(String(r.entry_date || ''))} · ${esc(num(r.amount))}</h3>
    <div class="row between"><span>${esc(T('kind'))}</span><span>${esc(r.kind)} / ${esc(r.class || '')}</span></div>
    <div class="row between"><span>${esc(T('status'))}</span><span>${esc(r.status || '')}</span></div>
    <div class="row between"><span>${esc(T('place'))}</span><span>${esc(locName(r.location_id))}</span></div>
    <div class="row between"><span>${esc(T('paidTo'))}</span><span>${esc(r.paid_to || '-')}</span></div>
    <div class="row between"><span>${esc(T('ref'))}</span><span>${esc(r.ref || '-')}</span></div>
    <div class="row between"><span>${esc(T('mode'))}</span><span>${esc(r.mode || '-')}</span></div>
    <div class="row between"><span>${esc(T('staff'))}</span><span>${esc(r.staff || '-')}</span></div>
    ${heads}
    <div class="row wrap"><span class="chip ${r.in_report ? 'ok' : ''}">${esc(T('inRep'))}: ${esc(r.in_report ? T('yes') : T('no'))}</span><span class="chip ${r.in_pl ? 'ok' : ''}">${esc(T('inPl'))}: ${esc(r.in_pl ? T('yes') : T('no'))}</span>
      <span class="chip ${r.in_journal ? 'ok' : ''}">${esc(T('inJr'))}: ${esc(r.in_journal ? (r.posted ? T('posted') : T('notPosted')) : T('no'))}</span></div>
    ${Number(r.no_receipt_amount) > 0 ? `<div class="row between"><span>${esc(T('noReceipt'))}</span><b>${esc(num(r.no_receipt_amount))}</b></div>` : ''}
    ${Number(r.unreadable) > 0 ? `<p class="notice warn mk warn">${esc(T('unreadable'))}: ${esc(String(r.unreadable))}</p>` : ''}
    ${flags ? `<div><b>${esc(T('flags'))}</b><ul>${flags}</ul></div>` : ''}
    ${route ? `<a class="btn full" href="${esc(route)}" data-act="closesheet">${esc(T('openSrc'))}</a>` : ''}</div>`);
}
async function fetchAll() {
  let rows = D.rows.slice(), more = D.data && D.data.has_more, guard = 0;
  while (more && guard < 80) { guard += 1; const r = await sb.rpc('expense_register', args(rows.length, 500)); if (r.error || !r.data) throw r.error || new Error('page'); rows = rows.concat(r.data.rows || []); more = r.data.has_more; }
  return rows;
}
async function exportCSV() {
  if (!D.data) return; const C = B.c1; toast(T('loading'));
  let rows; try { rows = await fetchAll(); } catch (e) { return toast(eText(e)); }
  if (!(await C.exportOk('expense_register', 'csv', { from: D.from, to: D.to, loc: D.loc || null, basis: D.basis, kinds: D.kinds, status: D.status || null }, rows.length))) return;
  const d = D.data, t = d.totals || {}, rec = d.recon || {};
  const out = [C.csvLine(['date', 'place', 'kind', 'class', 'status', 'paid_to', 'reference', 'heads', 'paid_by', 'amount', 'in_expense_report', 'in_pl_and_daybook', 'in_journal', 'journal_posted', 'no_receipt_amount', 'unreadable_lines', 'notes', 'entered_by', 'record_id'])];
  rows.forEach((r) => out.push(C.csvLine([r.entry_date, locName(r.location_id), r.kind, r.class, r.status, r.paid_to, r.ref, (r.heads || []).map((h) => h.head + ':' + h.amount).join('; '), r.mode, r.amount,
    r.in_report ? 'yes' : 'no', r.in_pl ? 'yes' : 'no', r.in_journal ? 'yes' : 'no', r.in_journal ? (r.posted ? 'yes' : 'no') : '', r.no_receipt_amount, r.unreadable, (r.flags || []).join('; '), r.staff, r.source_id])));
  out.push('');
  C.metaLines(lab(X.title), [['Period', D.from + ' - ' + D.to], ['Place', D.loc === '' ? 'All places' : locName(D.loc)], ['Basis', D.basis], ['Total expense report', t.report], ['Total P&L', t.pl], ['Total day book', t.daybook], ['Total journal', t.journal],
    ['Journal posted', t.journal_posted], ['Not in the books (18-1)', t.not_in_books], ['Totals agree', rec.agree ? 'yes' : 'no']]).forEach((m) => out.push(C.csvLine(m)));
  out.push(''); out.push(C.csvLine(['Why the totals differ', 'expense report', 'P&L', 'journal', 'why']));
  (rec.lines || []).forEach((l) => out.push(C.csvLine([l.label_en, l.report, l.pl, l.journal, l.why_en])));
  C.download(`expense-register-${D.from}_${D.to}.csv`, C.csvFile(out)); C.expDone();
}
Object.assign(H, {
  er_kind: (a) => { const k = a.dataset.k; D.kinds = D.kinds.includes(k) ? D.kinds.filter((x) => x !== k) : D.kinds.concat(k); const el = $('#er_filters'); if (el) el.innerHTML = filterHTML(); },
  er_basis: (a) => { D.basis = a.dataset.b === D.basis ? 'all' : a.dataset.b; const el = $('#er_filters'); if (el) el.innerHTML = filterHTML(); return run(false); },
  er_run: () => {
    D.from = $('#er_from').value; D.to = $('#er_to').value; D.loc = $('#er_loc').value; D.basis = $('#er_basis').value; D.status = $('#er_status').value;
    if (!D.from || !D.to || D.to < D.from) return toast(lab(ERR.bad_range));
    return run(false);
  },
  er_more: () => run(true),
  er_open: (a) => openRow(Number(a.dataset.i)),
  er_csv: exportCSV,
});
document.addEventListener('keydown', (e) => { const t = e.target; if (t && t.dataset && t.dataset.act === 'er_open' && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); openRow(Number(t.dataset.i)); } });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const t = today(); D.to = t; D.from = t.slice(0, 8) + '01'; D.basis = 'all'; D.kinds = []; D.status = ''; D.loc = ''; D.data = null; D.rows = []; D.err = null;
  shell(T('title'), `<p class="muted">${esc(T('intro'))}</p><div id="er_filters">${filterHTML()}</div><div id="er_res"></div>`, true);
  try { await run(false); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { expenseregister: view });
})();
