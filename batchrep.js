/* Islamia BOS · Batches and freshness (#/batchrep/<tab>): batch-wise stock with the unbatched line, finished-goods ageing, unsold by production batch, distribution by outlet and batch,
   expired / damaged / unsold, and the trace of one production batch. Server: supabase/phase424.sql and phase425.sql (batch_stock_rows, fg_ageing_rows, unsold_by_batch, fg_distribution,
   expired_damaged_unsold, fg_batch_rows). Read-only. The server answers in the report-viewer shape {columns, rows, notes, sections}; BOS.repkit (web/stockrep.js) draws it and exports CSV.
   A missing expiry, lot or cost is shown as "not captured" with a notice naming the field; no age band or limit is made up here. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab, K = B.repkit;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

const TABS = [['batches', L('ব্যাচ অনুযায়ী স্টক', 'Stock by batch', 'Stock by batch')], ['ageing', L('তৈরি পণ্যের বয়স', 'Finished goods age', 'তৈরি পণ্যের বয়স')], ['unsold', L('ব্যাচ অনুযায়ী অবিক্রীত', 'Unsold by batch', 'ব্যাচ অনুযায়ী unsold')],
  ['distribution', L('আউটলেট ও ব্যাচ বিতরণ', 'Outlet & batch distribution', 'Outlet ও Batch বিতরণ')], ['expired', L('মেয়াদ শেষ / নষ্ট / অবিক্রীত', 'Expired / damaged / unsold', 'মেয়াদ শেষ / নষ্ট / unsold')]];
const X = {
  title: L('ব্যাচ ও তাজা থাকা', 'Batches & freshness', 'Batch ও Freshness'), trace: L('ব্যাচের পথ', 'Batch trace', 'Batch trace'),
  onlyOpen: L('শুধু যেগুলোর মাল আছে', 'Only batches with stock left', 'শুধু যে batch-এ মাল আছে'), item: L('আইটেম (কোড)', 'Item (code)', 'Item (code)'),
  fg: L('শুধু তৈরি পণ্য', 'Finished goods only', 'শুধু তৈরি পণ্য'), allTypes: L('সব ধরন', 'All types', 'সব ধরন'), made: L('তৈরি', 'Made', 'Made'), expires: L('মেয়াদ', 'Expires', 'Expires'),
  family: L('ব্যাচের পরিবার', 'Batch family', 'Batch family'), rows: L('উৎস সারি', 'Source rows', 'Source rows'), sum: L('হিসাব', 'Account', 'Account'), batchNo: L('ব্যাচ নং', 'Batch no', 'Batch no'),
  openTrace: L('ব্যাচের পথ', 'Follow batch', 'Follow batch'), tapRow: L('সারিতে চাপলে ব্যাচের পথ খোলে', 'Tap a row to follow the batch', 'Row-তে চাপলে batch-এর পথ খোলে'),
  noBatch: L('একটি ব্যাচ নম্বর দিন', 'Give a batch number', 'একটি batch number দিন'),
};
const T = (k) => lab(X[k]);
const D = { tab: 'batches', loc: '', from: '', to: '', fgOnly: true, openOnly: false, item: '', itemId: '', items: null, ans: null, batch: '' };

async function loadItems() {
  if (D.items) return D.items;
  try { const r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en').eq('is_active', true).eq('tracked', true).order('code')); D.items = r.data || []; } catch (e) { D.items = []; }
  return D.items;
}
function frame() {
  shell(T('title'), `${K.tabs('batchrep', TABS, D.tab)}<div id="bch_ctl"></div><div id="bch_out" class="stack"><p class="muted">${esc(K.T('loading'))}</p></div>`, true);
  ctl();
}
function ctl() {
  const c = $('#bch_ctl'); if (!c) return;
  const dates = `<label>${esc(K.T('from'))} <input type="date" id="bch_from" value="${esc(D.from)}"></label><label>${esc(K.T('to'))} <input type="date" id="bch_to" value="${esc(D.to)}"></label>`;
  const go = `<button type="button" class="btn primary" data-act="bch_go">${esc(K.T('show'))}</button>`;
  if (D.tab === 'batches') c.innerHTML = `<div class="row wrap">${K.locSel('bch_loc', D.loc)}<label>${esc(T('item'))} <input id="bch_item" list="bch_items" autocomplete="off" value="${esc(D.item)}"></label><datalist id="bch_items">${(D.items || []).map((i) => `<option value="${esc(i.code + ' · ' + (S.lang === 'en' ? i.name_en || i.name_bn : i.name_bn))}"></option>`).join('')}</datalist>${go}</div>`;
  else if (D.tab === 'ageing') c.innerHTML = `<div class="row wrap">${K.locSel('bch_loc', D.loc)}<label class="row"><input type="checkbox" id="bch_fg" ${D.fgOnly ? 'checked' : ''}> ${esc(T('fg'))}</label>${go}</div>`;
  else if (D.tab === 'unsold') c.innerHTML = `<div class="row wrap">${K.locSel('bch_loc', D.loc)}${dates}<label class="row"><input type="checkbox" id="bch_open" ${D.openOnly ? 'checked' : ''}> ${esc(T('onlyOpen'))}</label>${go}</div>`;
  else if (D.tab === 'trace') c.innerHTML = `<div class="row wrap"><label>${esc(T('batchNo'))} <input id="bch_batch" inputmode="numeric" value="${esc(D.batch)}" style="max-width:7rem"></label>${go}</div>`;
  else c.innerHTML = `<div class="row wrap">${K.locSel('bch_loc', D.loc)}${dates}${go}</div>`;
}
function collect() {
  const v = (id) => ($(id) || {}).value;
  if ($('#bch_loc')) D.loc = v('#bch_loc') || '';
  if ($('#bch_from')) D.from = v('#bch_from') || D.from; if ($('#bch_to')) D.to = v('#bch_to') || D.to;
  if ($('#bch_fg')) D.fgOnly = $('#bch_fg').checked; if ($('#bch_open')) D.openOnly = $('#bch_open').checked;
  if ($('#bch_batch')) D.batch = (v('#bch_batch') || '').trim();
  if ($('#bch_item')) { D.item = v('#bch_item') || ''; const code = D.item.split(' · ')[0].trim().toLowerCase(); const it = (D.items || []).find((i) => i.code.toLowerCase() === code); D.itemId = it ? it.id : ''; }
}
const out = (h) => { const el = $('#bch_out'); if (el) el.innerHTML = h; };
const KEYS = { batches: 'batch_stock', ageing: 'fg_ageing', unsold: 'unsold_by_batch', distribution: 'fg_distribution', expired: 'expired_damaged_unsold' };
async function call() {
  const loc = D.loc ? Number(D.loc) : null;
  if (D.tab === 'batches') return sb.rpc('batch_stock_rows', { p_loc: loc, p_item: D.itemId || null, p_types: null });
  if (D.tab === 'ageing') return sb.rpc('fg_ageing_rows', { p_loc: loc, p_types: D.fgOnly ? ['finished_good'] : null });
  if (D.tab === 'unsold') return sb.rpc('unsold_by_batch', { p_from: D.from, p_to: D.to, p_loc: loc, p_types: null, p_open_only: D.openOnly });
  if (D.tab === 'distribution') return sb.rpc('fg_distribution', { p_from: D.from, p_to: D.to, p_loc: loc, p_types: null });
  return sb.rpc('expired_damaged_unsold', { p_from: D.from, p_to: D.to, p_loc: loc });
}
async function run() {
  if (D.tab === 'trace') return runTrace();
  out(`<p class="muted">${esc(K.T('loading'))}</p>`);
  const r = await call(); if (r.error) return K.err(r.error);
  const j = r.data; D.ans = j; const key = KEYS[D.tab], ok = await K.canExport();
  K.last[key] = { cols: j.columns, rows: j.rows, flt: { loc: D.loc, from: D.from, to: D.to } };
  D.rowsNow = j.rows;
  out(`${K.notes(j.notes)}<div class="muted rp-hint">${esc(T('tapRow'))}</div>${K.table(j.columns, j.rows, { tap: 'bch_row' })}${K.sections(j.sections)}<div class="rp-foot">${K.csvBtn(ok, key)}</div>`);
}
async function runTrace() {
  const id = Number(D.batch); if (!(id > 0)) return out(`<p class="muted">${esc(T('noBatch'))}</p>`);
  out(`<p class="muted">${esc(K.T('loading'))}</p>`);
  const r = await sb.rpc('fg_batch_rows', { p_batch: id }); if (r.error) return K.err(r.error);
  const j = r.data, sm = j.summary || {}, ok = await K.canExport();
  const num = (k, bn, en, t = 'num') => ({ key: k, label_bn: bn, label_en: en, type: t });
  const fcols = [num('batch_id', 'ব্যাচ', 'Batch', 'int'), num('location', 'জায়গা', 'Place', 'text'), num('made_on', 'তৈরি', 'Made', 'text'), num('expires_on', 'মেয়াদ', 'Expires', 'text'), num('qty_made', 'তৈরি/পাওয়া', 'Made / received'), num('qty_remaining', 'এখন আছে', 'Left')];
  const rcols = [num('day', 'তারিখ', 'Date', 'text'), num('time', 'সময়', 'Time', 'text'), num('location', 'জায়গা', 'Place', 'text'), num('batch_id', 'ব্যাচ', 'Batch', 'int'), num('reason', 'ধরন', 'Kind', 'text'), num('doc_label', 'উৎস', 'Source', 'text'), num('qty_delta', 'পরিমাণ', 'Qty')]
    .concat(j.cost_shown ? [num('unit_cost', 'একক খরচ', 'Unit cost', 'money')] : []);
  const rows = (j.rows || []).map((x) => Object.assign({}, x, { doc_label: x.doc && x.doc.label }));
  const acc = [['made_qty', 'তৈরি', 'Made'], ['sold_qty', 'বিক্রি (নিট)', 'Sold (net)'], ['wasted_qty', 'নষ্ট', 'Wasted'], ['other_qty', 'অন্যান্য', 'Other'], ['short_qty', 'পথে কম', 'Short'], ['in_transit_qty', 'পথে আছে', 'On the road'], ['remaining_qty', 'আছে', 'In stock'], ['unaccounted_qty', 'হিসাবহীন', 'Not accounted']];
  K.last.batch_trace = { cols: rcols, rows, flt: { batch: id } };
  out(`<div class="card"><b>${esc(j.item.code)} · ${esc(S.lang === 'en' ? j.item.name_en : j.item.name_bn)}</b><div class="muted">#${esc(String(j.batch_id))} · ${esc(T('made'))} ${esc(String(j.made_on))} · ${esc(T('expires'))} ${esc(j.expires_on || K.T('notcap'))} · ${esc(j.item.unit || '')}</div></div>
    <div class="stats" id="bch_acc">${acc.map((a) => `<div class="stat ${a[0] === 'unaccounted_qty' && Number(sm[a[0]]) !== 0 ? 'mk warn' : ''}"><div class="k">${esc(lab(L(a[1], a[2], a[2])))}</div><div class="v">${esc(K.num(sm[a[0]]))}</div></div>`).join('')}</div>
    <div class="hsec">${esc(T('family'))}</div>${K.table(fcols, j.family)}<div class="hsec">${esc(T('rows'))}</div>${K.table(rcols, rows)}<div class="rp-foot">${K.csvBtn(ok, 'batch_trace')}</div>`);
}
Object.assign(H, {
  bch_go: () => { collect(); run().catch(K.err); },
  bch_row: (a) => {
    const r = (D.rowsNow || [])[Number(a.dataset.i)]; if (!r || typeof r.drill !== 'string') return;
    if (r.drill.startsWith('#/batchrep/trace')) { const b = (r.drill.split('batch=')[1] || ''); D.batch = b; location.hash = '#/batchrep/trace?batch=' + b; } else if (r.drill.startsWith('#/')) location.hash = r.drill;
  },
});

async function view() {
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* fall back */ } }
  const parts = K.parts(), q = K.qs();
  D.tab = TABS.some((t) => t[0] === parts[1]) ? parts[1] : parts[1] === 'trace' ? 'trace' : 'batches';
  D.from = q.from || D.from || addDays(today(), -30); D.to = q.to || D.to || today();
  if (q.loc !== undefined) D.loc = q.loc;
  if (q.batch) D.batch = q.batch;
  await loadItems();
  if (q.item) { const it = D.items.find((i) => i.id === q.item); D.itemId = q.item; D.item = it ? it.code + ' · ' + (S.lang === 'en' ? it.name_en || it.name_bn : it.name_bn) : ''; }
  frame();
  if (D.tab === 'trace' && !D.batch) return out(`<p class="muted">${esc(T('noBatch'))}</p>`);
  run().catch(K.err);
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { batchrep: view });
})();
