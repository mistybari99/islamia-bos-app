/* Islamia BOS · Stock movement and reconciliation (#/stockrep): the movement LEDGER of one item at one place (opening, every row with its running balance, closing, source document)
   and the PERIOD RECONCILIATION (opening + in - out = closing per item and place, in-transit and short transfer lines, check against the cached balance).
   Server: supabase/phase422.sql (stock_movement_ledger) and phase423.sql (stock_recon_period). Read-only; costs only when the server returns them.
   This file also defines BOS.repkit, the small table / CSV / drill helper that web/batchrep.js and web/stockx.js use, so every report page of this package exports CSV the same way.
   A value the server could not give is shown as "not captured" (row field _nc), never as 0. Nothing here is a business number. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

/* ---------- shared kit ---------- */
const K = {};
K.X = {
  notcap: L('লেখা হয়নি', 'not captured', 'not captured'), csv: L('CSV', 'CSV', 'CSV'), show: L('দেখুন', 'Show', 'Show'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'),
  place: L('লোকেশন', 'Place', 'Place'), all: L('সব', 'All', 'All'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  nocsv: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export-এর permission নেই'), type: L('ধরন', 'Type', 'Type'), close: L('বন্ধ', 'Close', 'Close'),
  denied: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), tapRow: L('সারিতে চাপলে উৎস খোলে', 'Tap a row to open its source', 'Row-তে চাপলে source খোলে'),
};
K.T = (k) => lab(K.X[k]);
K.col = (c) => lab({ bn: c.label_bn, en: c.label_en || c.label_bn, mix: c.label_bn });
K.num = (v) => fmt(Math.round(Number(v) * 10000) / 10000);
K.val = (c, row) => {
  let v = row[c.key];
  if (v === null || v === undefined || v === '') return Array.isArray(row._nc) && row._nc.includes(c.key) ? K.T('notcap') : '—';
  if (c.type === 'money') return fmt(Math.round(Number(v) * 100) / 100);
  if (c.type === 'pct') return Number(v).toFixed(1) + '%';
  if (c.type === 'int') return c.key === 'batch_id' ? String(v) : fmt(v);
  if (c.type === 'num') return K.num(v);
  if (typeof v === 'boolean') return v ? '✓' : '—';
  return String(v);
};
K.vis = (cols) => {            // hide the "(EN)" twins and id columns, remember the twin for English mode
  const twin = new Set(); (cols || []).forEach((c) => { if (/_en$/.test(c.key) && /\(EN\)/.test(c.label_en || '')) { const base = cols.find((x) => x.key === c.key.slice(0, -3) || x.key === c.key.slice(0, -3) + '_bn'); if (base) { twin.add(c.key); base.en = c.key; } } });
  return (cols || []).filter((c) => c.type !== 'id' && !twin.has(c.key));
};
K.cell = (c, row) => { const v = c.en && S.lang === 'en' && row[c.en] ? row[c.en] : row[c.key]; return K.val(c, Object.assign({}, row, { [c.key]: v })); };
K.notes = (notes) => (notes || []).filter((n) => n.code !== 'no_data').map((n) => `<div class="rp-note mk ${/^(data_needed|truncated)$/.test(n.code) ? 'warn' : 'info'}">${esc(n.code === 'cost_hidden' ? lab(L('আপনার ভূমিকার জন্য খরচের কলাম বন্ধ', 'Cost columns are hidden for your role', 'Cost column আপনার role-এর জন্য বন্ধ')) : lab({ bn: n.text_bn || n.text_en, en: n.text_en || n.text_bn, mix: n.text_bn || n.text_en }) + (n.code === 'data_needed' && n.what ? ' [' + n.what + ']' : ''))}</div>`).join('');
K.table = (cols, rows, o = {}) => {
  const vc = K.vis(cols);
  if (!rows || !rows.length) return `<p class="muted">${esc(K.T('none'))}</p>`;
  return `<div class="scrollx rp-tw"><table class="rp-t"><thead><tr>${vc.map((c) => `<th class="${['money', 'int', 'num', 'pct'].includes(c.type) ? 'n' : ''}">${esc(K.col(c))}</th>`).join('')}</tr></thead><tbody>${rows.map((r, i) => `<tr ${o.tap ? `class="tap" data-act="${o.tap}" data-i="${i}" ${o.tapAttr || ''}` : ''}>${vc.map((c, ci) => `<${ci === 0 ? 'th scope="row"' : 'td'} class="${['money', 'int', 'num', 'pct'].includes(c.type) ? 'n' : ''}">${esc(K.cell(c, r))}</${ci === 0 ? 'th' : 'td'}>`).join('')}</tr>`).join('')}</tbody></table></div>`;
};
K.sections = (secs) => (secs || []).map((sc) => `<div class="hsec">${esc(lab({ bn: sc.title_bn, en: sc.title_en || sc.title_bn, mix: sc.title_bn }))}</div>${K.table(sc.columns, sc.rows)}`).join('');
K.csvText = (cols, rows) => {
  const vc = K.vis(cols), q = (v) => '"' + String(v === null || v === undefined ? '' : v).replace(/"/g, '""') + '"';
  return '﻿' + [vc.map((c) => q(K.col(c))).join(',')].concat(rows.map((r) => vc.map((c) => { const v = r[c.key]; return q(v === null || v === undefined || v === '' ? (Array.isArray(r._nc) && r._nc.includes(c.key) ? 'not captured' : '') : v); }).join(','))).join('\n');
};
let EXP = null;
K.canExport = async () => {
  if (S.ctx && S.ctx.is_owner) return true; if (EXP !== null) return EXP;
  try { const r = await sb.rpc('has_grant', { p_code: 'export_data' }); EXP = !r.error && r.data === true; } catch (e) { EXP = false; }
  return EXP;
};
K.csvBtn = (ok, key) => (ok ? `<button type="button" data-act="rk_csv" data-key="${esc(key)}">${esc(K.T('csv'))}</button>` : `<button type="button" disabled aria-label="${esc(K.T('csv') + ' · ' + K.T('nocsv'))}">${esc(K.T('csv'))} 🔒</button>`);
K.last = {};           // key -> { cols, rows, flt }
K.download = (name, text) => {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' }), url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000);
};
K.exportNow = async (key) => {
  const d = K.last[key]; if (!d) return;
  K.download(`${key}_${today()}.csv`, K.csvText(d.cols, d.rows));
  try { await sb.rpc('log_report_export4', { p_key: key, p_kind: 'csv', p_filters: d.flt || {}, p_rows: d.rows.length }); } catch (e) { /* the file is made; the log line is best effort */ }
  toast(lab(L('ফাইল তৈরি', 'File ready', 'File তৈরি')));
};
K.qs = () => { const q = (location.hash.split('?')[1] || ''); const o = {}; q.split('&').filter(Boolean).forEach((p) => { const [k, v] = p.split('='); o[decodeURIComponent(k)] = decodeURIComponent(v || ''); }); return o; };
K.parts = () => location.hash.replace(/^#\/?/, '').split('?')[0].split('/');
K.locs = () => { const all = (B.ENV && B.ENV.locs) || []; return B.liveLocs ? B.liveLocs(all) : all; };
K.locSel = (id, cur) => `<label>${esc(K.T('place'))} <select id="${id}"><option value="">${esc(K.T('all'))}</option>${K.locs().map((l) => `<option value="${l.id}" ${String(cur) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>`;
K.err = (e) => { const m = String((e && e.message) || ''); if (/not allowed/.test(m)) return toast(K.T('denied')); if (/bad_range/.test(m)) return toast(lab(L('তারিখের সীমা ঠিক নেই', 'The date range is wrong', 'Date range ঠিক নেই'))); return fail(e); };
K.tabs = (route, tabs, cur) => `<div class="ptabs" role="tablist">${tabs.map((t) => `<button role="tab" data-act="rk_tab" data-r="${route}" data-v="${t[0]}" aria-selected="${cur === t[0]}">${esc(lab(t[1]))}</button>`).join('')}</div>`;
B.repkit = K;
H.rk_csv = (a) => K.exportNow(a.dataset.key);
H.rk_tab = (a) => { location.hash = '#/' + a.dataset.r + '/' + a.dataset.v; };

/* ---------- labels ---------- */
const X = {
  title: L('স্টক নড়াচড়া ও মিলান', 'Stock movement & reconciliation', 'Stock নড়াচড়া ও মিলান'),
  tLed: L('নড়াচড়ার খাতা', 'Movement ledger', 'নড়াচড়ার খাতা'), tRec: L('সময়ের মিলান', 'Period reconciliation', 'সময়ের মিলান'),
  item: L('আইটেম (কোড)', 'Item (code)', 'Item (code)'), pickItem: L('আইটেম বেছে নিন', 'Choose an item', 'Item বেছে নিন'), pickPlace: L('একটি লোকেশন বেছে নিন', 'Choose a place', 'একটি Location বেছে নিন'),
  opening: L('শুরু', 'Opening', 'Opening'), closing: L('শেষ', 'Closing', 'Closing'), running: L('চলতি ব্যালান্স', 'Running balance', 'Running balance'), qty: L('পরিমাণ', 'Qty', 'Qty'),
  reason: L('ধরন', 'Kind', 'Kind'), doc: L('উৎস', 'Source', 'Source'), who: L('কে', 'Who', 'Who'), when: L('কখন', 'When', 'When'), note: L('নোট', 'Note', 'Note'),
  unitCost: L('একক খরচ', 'Unit cost', 'Unit cost'), value: L('মূল্য', 'Value', 'Value'), batch: L('ব্যাচ', 'Batch', 'Batch'),
  checkOk: L('ক্যাশ ব্যালান্স খাতার সাথে মেলে', 'Cached balance equals the ledger', 'Cached balance খাতার সাথে মেলে'), checkBad: L('ক্যাশ ব্যালান্স খাতার সাথে মেলে না', 'Cached balance differs from the ledger', 'Cached balance খাতার সাথে মেলে না'),
  later: L('এই সময়ের পরেও নড়াচড়া আছে', 'There are movements after this period', 'এই সময়ের পরেও নড়াচড়া আছে'), byReason: L('ধরন অনুযায়ী', 'By kind', 'Kind অনুযায়ী'),
  detail: L('উৎসের তথ্য', 'Source details', 'Source-এর তথ্য'), openBatch: L('ব্যাচের পথ দেখুন', 'Follow the batch', 'Batch-এর পথ দেখুন'), openLedger: L('এই আইটেমের খাতা', 'Ledger of this item', 'এই item-এর খাতা'),
  ledgerTap: L('সারিতে চাপলে উৎসের তথ্য খোলে', 'Tap a row to see its source', 'Row-তে চাপলে source খোলে'),
  rOpen: L('শুরু', 'Opening', 'Opening'), rIn: L('পাওয়া', 'Received', 'Received'), rBack: L('বিক্রি ফেরত', 'Sales back', 'Sales back'), rSale: L('বিক্রি', 'Sold', 'Sold'), rIss: L('ইস্যু', 'Issued', 'Issued'),
  rWas: L('নষ্ট', 'Wastage', 'Wastage'), rTo: L('ট্রান্সফার আউট', 'Transfer out', 'Transfer out'), rPr: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), rCnt: L('গণনা সংশোধন', 'Count', 'Count'),
  rRev: L('বাতিল', 'Reversal', 'Reversal'), rClose: L('শেষ', 'Closing', 'Closing'), rTr: L('পথে', 'On the road', 'On the road'), rState: L('অবস্থা', 'State', 'State'), rCache: L('ক্যাশ − খাতা', 'Cache − ledger', 'Cache − ledger'),
  summary: L('সারসংক্ষেপ', 'Summary', 'Summary'), identity: L('শুরু + নড়াচড়া = শেষ সব সারিতে মিলেছে', 'Opening + movements = closing on every row', 'Opening + movement = closing সব row-তে মিলেছে'),
  identityBad: L('কিছু সারিতে হিসাব মেলেনি', 'Some rows do not balance', 'কিছু row-তে হিসাব মেলেনি'), transit: L('পথে থাকা ট্রান্সফার', 'Transfers on the road', 'পথে থাকা Transfer'),
  short: L('কম পৌঁছানো ট্রান্সফার', 'Transfers received short', 'কম পৌঁছানো Transfer'), types: L('ধরন বাছুন', 'Item types', 'Item types'),
  rsFrom: L('কোথা থেকে', 'From', 'From'), rsTo: L('কোথায়', 'To', 'To'), rsSent: L('পাঠানো', 'Sent', 'Sent'), rsRecv: L('পৌঁছেছে', 'Received', 'Received'), rsShort: L('কম', 'Short', 'Short'), rsClaim: L('দাবি', 'Claim', 'Claim'), days: L('দিন', 'Days', 'Days'),
};
const T = (k) => lab(X[k]);
const REASON = { opening: L('শুরুর স্টক', 'Opening stock', 'Opening stock'), purchase_in: L('ক্রয়', 'Purchase', 'Purchase'), purchase_return: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), sale_out: L('বিক্রি', 'Sale', 'Sale'),
  sale_void_in: L('বিক্রি বাতিল', 'Sale voided', 'Sale voided'), sale_return: L('বিক্রি ফেরত', 'Refund', 'Refund'), issue_out: L('উৎপাদনে ইস্যু', 'Issued to production', 'Issued to production'), production_in: L('উৎপাদন', 'Production', 'Production'),
  transfer_out: L('ট্রান্সফার আউট', 'Transfer out', 'Transfer out'), transfer_in: L('ট্রান্সফার ইন', 'Transfer in', 'Transfer in'), wastage: L('নষ্ট', 'Wastage', 'Wastage'), count_adjust: L('গণনা সংশোধন', 'Count adjustment', 'Count adjustment'), reversal: L('বাতিল (রিভার্সাল)', 'Reversal', 'Reversal') };
const rsn = (r) => (REASON[r] ? lab(REASON[r]) : r);
const D = { tab: 'ledger', loc: '', item: '', itemId: '', from: '', to: '', types: [], items: null, ans: null, rec: null };

async function loadItems() {
  if (D.items) return D.items;
  try { const r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,item_type,tracked').eq('is_active', true).order('code')); D.items = (r.data || []).filter((i) => i.tracked !== false); } catch (e) { D.items = []; }
  return D.items;
}
const itemLabel = (i) => `${i.code} · ${nm(i)}`;
function frame() {
  shell(T('title'), `${K.tabs('stockrep', [['ledger', X.tLed], ['recon', X.tRec]], D.tab)}<div id="stk_ctl"></div><div id="stk_out" class="stack"><p class="muted">${esc(K.T('loading'))}</p></div>`, true);
  ctl();
}
function ctl() {
  const c = $('#stk_ctl'); if (!c) return;
  const dates = `<label>${esc(K.T('from'))} <input type="date" id="stk_from" value="${esc(D.from)}"></label><label>${esc(K.T('to'))} <input type="date" id="stk_to" value="${esc(D.to)}"></label>`;
  if (D.tab === 'ledger') {
    c.innerHTML = `<div class="row wrap">${K.locSel('stk_loc', D.loc)}<label>${esc(T('item'))} <input id="stk_item" list="stk_items" autocomplete="off" value="${esc(D.item)}" placeholder="${esc(T('pickItem'))}"></label>
      <datalist id="stk_items">${(D.items || []).map((i) => `<option value="${esc(itemLabel(i))}"></option>`).join('')}</datalist>${dates}<button type="button" class="btn primary" data-act="stk_go">${esc(K.T('show'))}</button></div>`;
  } else {
    const ts = (D.typeList || []).map((t) => `<label class="row"><input type="checkbox" class="stk_ty" value="${esc(t.code)}" ${D.types.includes(t.code) ? 'checked' : ''}> ${esc(S.lang === 'en' ? (t.label_en || t.label_bn) : t.label_bn)}</label>`).join('');
    c.innerHTML = `<div class="row wrap">${K.locSel('stk_loc', D.loc)}${dates}<button type="button" class="btn primary" data-act="stk_go">${esc(K.T('show'))}</button></div><details><summary>${esc(T('types'))}</summary><div class="row wrap">${ts}</div></details>`;
  }
}
function collect() {
  const v = (id) => ($(id) || {}).value;
  D.loc = v('#stk_loc') || ''; D.from = v('#stk_from') || D.from; D.to = v('#stk_to') || D.to;
  if (D.tab === 'ledger') {
    D.item = v('#stk_item') || ''; const code = D.item.split(' · ')[0].trim().toLowerCase();
    const it = (D.items || []).find((i) => i.code.toLowerCase() === code); D.itemId = it ? it.id : '';
  } else D.types = [...document.querySelectorAll('.stk_ty:checked')].map((x) => x.value);
}
const out = (h) => { const el = $('#stk_out'); if (el) el.innerHTML = h; };
async function run() {
  if (D.tab === 'ledger') return runLedger();
  return runRecon();
}
async function runLedger() {
  if (!D.itemId) return out(`<p class="muted">${esc(T('pickItem'))}</p>`);
  if (!D.loc) return out(`<p class="muted">${esc(T('pickPlace'))}</p>`);
  out(`<p class="muted">${esc(K.T('loading'))}</p>`);
  const r = await sb.rpc('stock_movement_ledger', { p_item: D.itemId, p_loc: Number(D.loc), p_from: D.from, p_to: D.to }); if (r.error) return K.err(r.error);
  const j = r.data; D.ans = j;
  const cost = !!j.cost_shown, chk = j.check || {};
  const cols = [{ key: 'day', label_bn: 'তারিখ', label_en: 'Date', type: 'text' }, { key: 'time', label_bn: 'সময়', label_en: 'Time', type: 'text' }, { key: 'reason', label_bn: 'ধরন', label_en: 'Kind', type: 'text' }, { key: 'doc_label', label_bn: 'উৎস', label_en: 'Source', type: 'text' },
    { key: 'qty_delta', label_bn: 'পরিমাণ', label_en: 'Qty', type: 'num' }, { key: 'running', label_bn: 'চলতি ব্যালান্স', label_en: 'Running balance', type: 'num' }, { key: 'who', label_bn: 'কে', label_en: 'Who', type: 'text' }, { key: 'batch_no', label_bn: 'ব্যাচ', label_en: 'Batch', type: 'text' }, { key: 'note', label_bn: 'নোট', label_en: 'Note', type: 'text' }]
    .concat(cost ? [{ key: 'unit_cost', label_bn: 'একক খরচ', label_en: 'Unit cost', type: 'money' }, { key: 'value', label_bn: 'মূল্য', label_en: 'Value', type: 'money' }] : []);
  const rows = (j.rows || []).map((x) => Object.assign({}, x, { doc_label: x.doc && x.doc.label, reason_raw: x.reason, reason: rsn(x.reason), batch_no: x.batch_no || (x.batch_id ? '#' + x.batch_id : null) }));
  D.rowsRaw = j.rows || [];
  K.last.stock_ledger = { cols: cols.map((c) => Object.assign({}, c, { type: c.type })), rows: rows.map((x) => Object.assign({}, x, { reason: x.reason_raw })), flt: { item: D.itemId, loc: D.loc, from: D.from, to: D.to } };
  const ok = await K.canExport();
  out(`<div class="card"><b>${esc(j.item.code)} · ${esc(S.lang === 'en' ? j.item.name_en : j.item.name_bn)}</b><div class="muted">${esc(S.lang === 'en' ? j.location.name_en : j.location.name_bn)} · ${esc(j.from)} → ${esc(j.to)} · ${esc(j.item.unit || '')}</div></div>
    <div class="stats"><div class="stat"><div class="k">${esc(T('opening'))}</div><div class="v" id="stk_open">${esc(K.num(j.opening))}</div></div><div class="stat"><div class="k">${esc(T('closing'))}</div><div class="v" id="stk_close">${esc(K.num(j.closing))}</div></div></div>
    <div class="notice ${chk.ok ? 'ok' : 'bad'}" id="stk_check">${esc(chk.ok ? T('checkOk') : T('checkBad'))} (${esc(K.num(chk.ledger_total_all))} / ${esc(K.num(chk.cached))})${chk.later_rows > 0 ? ' · ' + esc(T('later')) : ''}</div>
    ${K.notes(j.notes)}<div class="muted rp-hint">${esc(T('ledgerTap'))}</div>${K.table(cols, rows, { tap: 'stk_row' })}
    <div class="hsec">${esc(T('byReason'))}</div>${K.table([{ key: 'reason', label_bn: 'ধরন', label_en: 'Kind', type: 'text' }, { key: 'rows', label_bn: 'সারি', label_en: 'Rows', type: 'int' }, { key: 'in_qty', label_bn: 'ঢুকেছে', label_en: 'In', type: 'num' }, { key: 'out_qty', label_bn: 'বেরিয়েছে', label_en: 'Out', type: 'num' }, { key: 'net', label_bn: 'নিট', label_en: 'Net', type: 'num' }], (j.summary || []).map((s) => Object.assign({}, s, { reason: rsn(s.reason) })))}
    <div class="rp-foot">${K.csvBtn(ok, 'stock_ledger')}</div>`);
  D.shownRows = rows;
}
function rowSheet(i) {
  const r = (D.rowsRaw || [])[i]; if (!r) return;
  const d = (r.doc && r.doc.detail) || {}, lines = Object.keys(d).filter((k) => d[k] !== null && d[k] !== undefined).map((k) => `<div class="row"><span class="muted">${esc(k)}</span> <b>${esc(String(d[k]))}</b></div>`).join('');
  openSheet(`<h3>${esc(rsn(r.reason))} · ${esc(K.num(r.qty_delta))}</h3><p>${esc((r.doc && r.doc.label) || '')}</p><div class="stack"><div class="muted">${esc(T('detail'))}</div>${lines || `<p class="muted">${esc(K.T('none'))}</p>`}
    ${r.note ? `<div><span class="muted">${esc(T('note'))}</span> ${esc(r.note)}</div>` : ''}${r.who ? `<div><span class="muted">${esc(T('who'))}</span> ${esc(r.who)}</div>` : ''}</div>
    ${r.batch_id ? `<button type="button" class="full" data-act="stk_batch" data-b="${esc(String(r.batch_id))}">${esc(T('openBatch'))}</button>` : ''}<button type="button" class="full" data-act="closesheet">${esc(K.T('close'))}</button>`);
}
async function runRecon() {
  out(`<p class="muted">${esc(K.T('loading'))}</p>`);
  await loadTypes();
  const r = await sb.rpc('stock_recon_period', { p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null, p_types: D.types.length ? D.types : null }); if (r.error) return K.err(r.error);
  const j = r.data; D.rec = j;
  const num = (k, bn, en, t = 'num') => ({ key: k, label_bn: bn, label_en: en, type: t });
  const cols = [num('item_code', 'কোড', 'Code', 'text'), num('item_name', 'আইটেম', 'Item', 'text'), Object.assign(num('item_name_en', 'Item (EN)', 'Item (EN)', 'text')), num('location_bn', 'লোকেশন', 'Place', 'text'), Object.assign(num('location_en', 'Place (EN)', 'Place (EN)', 'text')), num('unit', 'একক', 'Unit', 'text'),
    num('opening', 'শুরু', 'Opening'), num('received', 'পাওয়া', 'Received'), num('sales_back', 'বিক্রি ফেরত', 'Sales back'), num('sale_out', 'বিক্রি', 'Sold'), num('issue_out', 'ইস্যু', 'Issued'), num('wastage', 'নষ্ট', 'Wastage'), num('transfer_out', 'ট্রান্সফার আউট', 'Transfer out'),
    num('purchase_return', 'ক্রয় ফেরত', 'Purchase return'), num('count_adjust', 'গণনা সংশোধন', 'Count'), num('reversal', 'বাতিল', 'Reversal'), num('closing', 'শেষ', 'Closing'), num('in_transit_out', 'পথে', 'On the road'), num('cache_diff', 'ক্যাশ − খাতা', 'Cache − ledger'), num('state', 'অবস্থা', 'State', 'text')];
  const rows = (j.rows || []).map((x) => Object.assign({}, x, { received: Number(x.opening_entry) + Number(x.purchase_in) + Number(x.production_in) + Number(x.transfer_in) }));
  const tcols = [num('sent_day', 'পাঠানো', 'Sent', 'text'), num('from_name', 'কোথা থেকে', 'From', 'text'), num('to_name', 'কোথায়', 'To', 'text'), num('item_name', 'আইটেম', 'Item', 'text'), num('qty', 'পরিমাণ', 'Qty'), num('days', 'দিন', 'Days', 'int')];
  const scols = [num('sent_day', 'পাঠানো', 'Sent', 'text'), num('received_day', 'গ্রহণ', 'Received on', 'text'), num('from_name', 'কোথা থেকে', 'From', 'text'), num('to_name', 'কোথায়', 'To', 'text'), num('item_name', 'আইটেম', 'Item', 'text'), num('sent_qty', 'পাঠানো', 'Sent qty'), num('received_qty', 'পৌঁছেছে', 'Received qty'), num('short_qty', 'কম', 'Short'), num('claim', 'দাবি', 'Claim', 'text')]
    .concat(j.cost_shown ? [num('short_value', 'কমের মূল্য', 'Short value', 'money')] : []);
  const srows = (j.short || []).map((x) => Object.assign({}, x, { _nc: x.value_missing ? ['short_value'] : [] }));
  K.last.stock_recon = { cols, rows, flt: { from: D.from, to: D.to, loc: D.loc, types: D.types } };
  const sm = j.summary || {}, ok = await K.canExport();
  D.recRows = rows;
  out(`<div class="notice ${sm.identity_holds ? 'ok' : 'bad'}" id="stk_ident">${esc(sm.identity_holds ? T('identity') : T('identityBad'))}</div>
    <div class="stats"><div class="stat"><div class="k">OK</div><div class="v">${sm.ok || 0}</div></div><div class="stat ${sm.cache_differs ? 'mk warn' : ''}"><div class="k">${esc(T('rCache'))}</div><div class="v">${sm.cache_differs || 0}</div></div>
      <div class="stat"><div class="k">${esc(T('transit'))}</div><div class="v">${sm.in_transit_lines || 0}</div></div><div class="stat"><div class="k">${esc(T('short'))}</div><div class="v">${sm.short_lines || 0}</div></div></div>
    ${K.notes(j.notes)}<div class="muted rp-hint">${esc(K.T('tapRow'))}</div>${K.table(cols, rows, { tap: 'stk_recrow' })}
    <div class="hsec">${esc(T('transit'))}</div>${K.table(tcols, j.transit || [])}<div class="hsec">${esc(T('short'))}</div>${K.table(scols, srows)}
    <div class="rp-foot">${K.csvBtn(ok, 'stock_recon')}</div>`);
}
async function loadTypes() { if (D.typeList) return; try { const r = await sb.from('item_types').select('code,label_bn,label_en,sort').eq('active', true).order('sort'); D.typeList = r.data || []; } catch (e) { D.typeList = []; } }

Object.assign(H, {
  stk_go: () => { collect(); run().catch(K.err); },
  stk_row: (a) => rowSheet(Number(a.dataset.i)),
  stk_batch: (a) => { closeSheet(); location.hash = '#/batchrep/trace?batch=' + a.dataset.b; },
  stk_recrow: (a) => { const r = (D.recRows || [])[Number(a.dataset.i)]; if (!r) return; location.hash = `#/stockrep/ledger?item=${r.item_id}&loc=${r.location_id}&from=${D.from}&to=${D.to}`; },
});

async function view() {
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* fall back */ } }
  const parts = K.parts(), q = K.qs();
  D.tab = parts[1] === 'recon' ? 'recon' : 'ledger';
  D.from = q.from || D.from || addDays(today(), -30); D.to = q.to || D.to || today();
  if (q.loc !== undefined) D.loc = q.loc;
  await loadItems();
  if (q.item) { const it = D.items.find((i) => i.id === q.item); D.itemId = q.item; D.item = it ? itemLabel(it) : ''; }
  frame();
  if ((D.tab === 'ledger' && D.itemId && D.loc) || D.tab === 'recon') run().catch(K.err); else out(`<p class="muted">${esc(T('pickItem'))}</p>`);
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stockrep: view });
})();
