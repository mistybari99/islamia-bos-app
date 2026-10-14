/* Islamia BOS · Stock extras (#/stockx): reorder suggestion, near-expiry + batch capture + FEFO hint, wastage by reason, quality checks.
   Server: supabase/phase60.sql — reorder_report, near_expiry_report, fefo_hint, grn_batch_add, wastage_by_reason, qc_record / qc_list / qc_history / qc_gate.
   Everything here is a report or an append-only record: no purchase order is made, no stock is moved, and a quality hold blocks nothing unless the owner
   switched quality_block_on ON (the page only shows that state). Costs are never requested. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, nm, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q4 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);

const X = {
  title: L('স্টক রিপোর্ট ও কোয়ালিটি', 'Stock reports & quality', 'Stock report ও quality'),
  tRe: L('রিঅর্ডার', 'Reorder', 'Reorder'), tEx: L('মেয়াদ ও ব্যাচ', 'Expiry & batches', 'মেয়াদ ও batch'), tWa: L('নষ্টের কারণ', 'Wastage by reason', 'নষ্টের কারণ'), tQc: L('কোয়ালিটি', 'Quality', 'Quality'),
  place: L('লোকেশন', 'Place', 'Place'), all: L('সব', 'All', 'All'), show: L('দেখুন', 'Show', 'Show'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'),
  none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  reNote: L('এটি শুধু পরামর্শ — কোনো অর্ডার নিজে থেকে হয় না। লিড ডে মালিক সেটিংসে ঠিক করেন।', 'A suggestion only — no order is placed. The owner sets the lead days in Settings.', 'শুধু suggestion — কোনো order হয় না। Lead days owner Settings-এ ঠিক করেন।'),
  days: L('কত দিনের গড়', 'Days averaged', 'Days averaged'), onhand: L('হাতে', 'On hand', 'On hand'), min: L('ন্যূনতম', 'Min', 'Min'), avg: L('দৈনিক গড়', 'Avg/day', 'Avg/day'),
  left: L('কত দিন চলবে', 'Days left', 'Days left'), sug: L('কিনতে পারেন', 'Suggest', 'Suggest'), lead: L('লিড ডে', 'Lead days', 'Lead days'),
  w_below_min: L('ন্যূনতমের নিচে', 'Below minimum', 'Min-এর নিচে'), w_runs_out_in_lead: L('মাল আসার আগেই শেষ', 'Runs out before delivery', 'Delivery-র আগেই শেষ'), w_cover: L('কভার বাড়াতে', 'To restore cover', 'Cover বাড়াতে'),
  exDays: L('কত দিনের মধ্যে', 'Within days', 'Within days'), batch: L('ব্যাচ', 'Batch', 'Batch'), exp: L('মেয়াদ', 'Expiry', 'Expiry'), expired: L('মেয়াদ শেষ', 'Expired', 'Expired'),
  blocked: L('কোয়ালিটিতে আটক', 'Held by quality', 'Quality-তে আটক'), fefo: L('আগে মেয়াদ → আগে বিক্রি', 'FEFO order', 'FEFO order'), fefoNote: L('সেল/ইস্যুতে সিস্টেম এই ক্রমেই ব্যাচ কাটে।', 'Sales and issues take batches in this order.', 'Sale/issue-এ system এই order-এ batch কাটে।'),
  addB: L('প্রাপ্ত মালের ব্যাচ ও মেয়াদ লিখুন', 'Record batch & expiry of received goods', 'Received goods-এর batch ও expiry'), src: L('উৎস (ক্রয় বিল / GRN)', 'Source (purchase bill / GRN)', 'Source (purchase bill / GRN)'),
  item: L('আইটেম', 'Item', 'Item'), qty: L('Qty', 'Quantity', 'Quantity'), unit: L('একক', 'Unit', 'Unit'), bno: L('ব্যাচ নম্বর', 'Batch no', 'Batch no'), save: L('সেভ', 'Save', 'Save'), close: L('বন্ধ', 'Close', 'Close'),
  reason: L('কারণ', 'Reason', 'Reason'), entries: L('বার', 'Entries', 'Entries'), items: L('আইটেম', 'Items', 'Items'),
  qcNew: L('নতুন কোয়ালিটি চেক', 'New quality check', 'নতুন quality check'), qcKind: L('কিসের চেক', 'Check of', 'Check of'), kProd: L('উৎপাদন রান', 'Production run', 'Production run'), kGrn: L('মাল গ্রহণ (GRN / ক্রয়)', 'Goods received (GRN / purchase)', 'Goods received (GRN / purchase)'),
  pass: L('পাস', 'Pass', 'Pass'), hold: L('আটক', 'Hold', 'Hold'), reject: L('বাতিল', 'Reject', 'Reject'), note: L('নোট', 'Note', 'Note'), hist: L('ইতিহাস', 'History', 'History'),
  qcOff: L('কোয়ালিটি আটক এখন শুধু রেকর্ড — কিছু আটকায় না (মালিক সেটিংসে চালু করতে পারেন)।', 'Quality hold is a record only for now — nothing is blocked (the owner can switch it on in Settings).', 'Quality hold এখন শুধু record — কিছু আটকায় না (owner Settings-এ on করতে পারেন)।'),
  qcOn: L('কোয়ালিটি আটক চালু: আটক/বাতিল GRN-এ নতুন ব্যাচ হবে না।', 'Quality block is ON: a held / rejected GRN cannot get new batches.', 'Quality block ON: held/rejected GRN-এ নতুন batch হবে না।'),
  pick: L('বেছে নিন…', 'Choose…', 'বেছে নিন…'), bad: L('সংখ্যা ঠিক নেই', 'Check the numbers', 'সংখ্যা ঠিক নেই'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), bad_days: L('দিনের সংখ্যা ঠিক নেই', 'Days must be 1-365', 'Days 1-365 হতে হবে'), bad_range: L('ডেটের সীমা ঠিক নেই', 'Date range is wrong', 'Date range ঠিক নেই'),
  batch_no_exists: L('এই ব্যাচ নম্বর আগে আছে', 'This batch no already exists for the item', 'এই batch no আগে আছে'), more_than_received: L('বিলে যত এসেছে তার বেশি ব্যাচ করা যায় না', 'More than the bill received', 'Bill-এর চেয়ে বেশি'),
  more_than_on_hand: L('হাতে এত মাল নেই', 'More than the stock on hand', 'হাতে এত নেই'), bad_expiry: L('মেয়াদ আজ বা পরের তারিখ হতে হবে', 'Expiry must be today or later', 'Expiry আজ বা পরে হতে হবে'),
  bad_batch_no: L('ব্যাচ নম্বর লিখুন (৪০ অক্ষরের মধ্যে)', 'Enter a batch no (max 40 characters)', 'Batch no লিখুন'), item_not_in_source: L('এই আইটেম ওই উৎসে নেই', 'The item is not on that source', 'Item-টা source-এ নেই'),
  source_not_found: L('উৎস পাওয়া যায়নি (জমা/পোস্ট হতে হবে)', 'Source not found (it must be submitted / posted)', 'Source পাওয়া যায়নি'), qc_blocked: L('কোয়ালিটিতে আটক — নতুন ব্যাচ হবে না', 'Held by quality — no new batch', 'Quality hold — নতুন batch না'),
  pass_has_failed_check: L('ব্যর্থ আইটেম থাকলে পাস দেওয়া যায় না', 'A pass cannot have a failed check', 'Failed check থাকলে pass না'), note_required: L('আটক/বাতিলে নোট লিখুন', 'Write a note for hold / reject', 'Hold/reject-এ note লিখুন'),
  unit_unknown: L('একক চেনা যায়নি', 'Unit not recognised', 'Unit চেনা যায়নি'), bad_qty: L('Qty ঠিক নেই', 'Quantity is wrong', 'Quantity ঠিক নেই'),
};
const failx = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? toast(lab(ERR[k])) : fail(e); };
const D = { tab: 're', loc: null, locs: [], days: 30, exDays: 7, from: null, to: null, qcKind: 'grn' };
const locSel = (id) => `<label>${esc(T('place'))} <select id="${id}"><option value="">${esc(T('all'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(D.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>`;
const out = (h) => { const el = $('#sx_out'); if (el) el.innerHTML = h; };
const tbl = (head, rows) => rows.length ? `<div style="overflow-x:auto"><table class="tbl" style="font-size:.8rem;width:100%"><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>` : `<p class="muted">${esc(T('none'))}</p>`;
const loc = () => (D.loc ? Number(D.loc) : null);

/* ---------- tabs ---------- */
function frame() {
  const tabs = [['re', 'tRe'], ['ex', 'tEx'], ['wa', 'tWa'], ['qc', 'tQc']];
  shell(T('title'), `<div class="row wrap">${tabs.map((t) => `<button type="button" class="btn ${D.tab === t[0] ? 'primary' : ''}" data-act="sx_tab" data-v="${t[0]}">${esc(T(t[1]))}</button>`).join('')}</div><div id="sx_ctl"></div><div id="sx_out" class="stack"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  draw();
}
function draw() {
  const ctl = $('#sx_ctl'); if (!ctl) return;
  if (D.tab === 're') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('days'))} <input id="sx_days" type="number" min="1" max="365" value="${D.days}" style="max-width:5rem"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button></div><p class="muted" style="font-size:.8rem">${esc(T('reNote'))}</p>`;
  if (D.tab === 'ex') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('exDays'))} <input id="sx_exd" type="number" min="0" max="365" value="${D.exDays}" style="max-width:5rem"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button><button type="button" class="btn" data-act="sx_addb">${esc(T('addB'))}</button></div>`;
  if (D.tab === 'wa') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('from'))} <input type="date" id="sx_from" value="${esc(D.from)}"></label><label>${esc(T('to'))} <input type="date" id="sx_to" value="${esc(D.to)}"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button></div>`;
  if (D.tab === 'qc') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button><button type="button" class="btn primary" data-act="sx_qcnew">${esc(T('qcNew'))}</button></div>`;
  run().catch(failx);
}
async function run() {
  if (D.tab === 're') {
    const r = await sb.rpc('reorder_report', { p_loc: loc(), p_days: D.days }); if (r.error) throw r.error;
    out(tbl([T('item'), T('onhand'), T('min'), T('avg'), T('left'), T('lead'), T('sug')], (r.data || []).map((x) =>
      `<tr><td>${esc(x.code)} · ${esc(lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))}<div class="chip ${x.why === 'cover' ? '' : 'warn'}">${esc(T('w_' + x.why))}</div></td><td>${q4(x.on_hand)} ${esc(x.base_unit || '')}</td><td>${q4(x.min_stock)}</td><td>${q4(x.avg_daily)}</td><td>${q4(x.days_left)}</td><td>${q4(x.lead_days)}</td><td><b>${q4(x.suggest_qty)}</b></td></tr>`)));
  } else if (D.tab === 'ex') {
    const r = await sb.rpc('near_expiry_report', { p_loc: loc(), p_days: D.exDays }); if (r.error) throw r.error;
    out(tbl([T('item'), T('batch'), T('exp'), T('qty'), ''], (r.data || []).map((x) =>
      `<tr><td>${esc(x.code)} · ${esc(lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))}</td><td>${esc(x.batch_no || '—')}${x.qc_blocked ? `<div class="chip warn">${esc(T('blocked'))}</div>` : ''}</td><td>${esc(String(x.expires_at).slice(0, 10))}${x.expired ? `<div class="chip warn">${esc(T('expired'))}</div>` : ` · ${q4(x.days_left)}d`}</td><td>${q4(x.qty_remaining)}</td><td><button type="button" class="mini" data-act="sx_fefo" data-i="${esc(x.item_id)}" data-l="${x.location_id}">${esc(T('fefo'))}</button></td></tr>`)));
  } else if (D.tab === 'wa') {
    const r = await sb.rpc('wastage_by_reason', { p_loc: loc(), p_from: D.from, p_to: D.to }); if (r.error) throw r.error;
    out(tbl([T('reason'), T('entries'), T('items'), T('qty')], (r.data || []).map((x) =>
      `<tr><td>${esc(lab({ bn: x.label_bn, mix: x.label_mix || x.label_bn, en: x.label_en || x.label_bn }))}</td><td>${x.entries}</td><td>${x.items}</td><td>${q4(x.qty)}</td></tr>`)));
  } else {
    const [r, sw] = await Promise.all([sb.rpc('qc_list', { p_loc: loc(), p_from: null, p_to: null, p_status: null }), sb.rpc('qc_gate', { p_source_type: 'grn', p_source_id: '00000000-0000-0000-0000-000000000000' })]);
    if (r.error) throw r.error;
    const on = !!(sw.data && sw.data.switch_on);
    out(`<p class="muted" style="font-size:.8rem">${esc(T(on ? 'qcOn' : 'qcOff'))}</p>` + tbl([T('qcKind'), '', T('note'), ''], (r.data || []).map((x) =>
      `<tr><td>${esc(T(x.source_type === 'production' ? 'kProd' : 'kGrn'))}<div class="muted">${esc(String(x.created_at).slice(0, 10))}</div></td><td><span class="chip ${x.status === 'pass' ? '' : 'warn'}">${esc(T(x.status))}</span></td><td>${esc(x.note || '')}</td><td><button type="button" class="mini" data-act="sx_hist" data-t="${esc(x.source_type)}" data-s="${esc(x.source_id)}">${esc(T('hist'))} (${x.history_n})</button></td></tr>`)));
  }
}

/* ---------- batch capture ---------- */
async function addBatchSheet() {
  const l = loc();
  const [bills, grns] = await Promise.all([sb.rpc('purchase_list', { p_loc: l, p_status: 'posted' }), sb.from('entries').select('id,entry_date,data,status').eq('form_code', '04-1').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).limit(30)]);
  const opts = (bills.data || []).filter((b) => b.kind === 'bill').map((b) => `<option value="purchase:${esc(b.id)}">${esc(b.bill_no || '')} · ${esc(b.supplier_name || '')} · ${esc(b.bill_date)}</option>`)
    .concat((grns.data || []).map((g) => `<option value="grn:${esc(g.id)}">GRN ${esc(g.entry_date)} · ${esc((g.data && g.data.supplier) || '')}</option>`)).join('');
  openSheet(`<h3>${esc(T('addB'))}</h3><div class="stack"><label>${esc(T('src'))} <select id="sx_src" data-sx="srcpick"><option value="">${esc(T('pick'))}</option>${opts}</select></label>
    <label>${esc(T('item'))} <select id="sx_item"><option value="">${esc(T('pick'))}</option></select></label>
    <div class="row wrap"><input id="sx_bq" inputmode="decimal" placeholder="${esc(T('qty'))}" style="max-width:6rem"><input id="sx_bu" placeholder="${esc(T('unit'))}" style="max-width:5rem"></div>
    <input id="sx_bn" maxlength="40" placeholder="${esc(T('bno'))}"><label>${esc(T('exp'))} <input type="date" id="sx_bx" min="${today()}"></label>
    <div class="row"><button type="button" class="btn primary" data-act="sx_bsave">${esc(T('save'))}</button><button type="button" class="btn" data-act="sx_close">${esc(T('close'))}</button></div></div>`);
  D.grnData = Object.fromEntries((grns.data || []).map((g) => [g.id, g]));
}
async function pickSource(sel) {
  const [t, id] = String(sel.value).split(':'), it = $('#sx_item'); if (!it || !id) return;
  let rows = [];
  if (t === 'purchase') { const r = await sb.rpc('purchase_get', { p_id: id }); if (r.error) return failx(r.error); rows = (r.data.lines || []).filter((x) => x.item_id).map((x) => ({ id: x.item_id, label: x.description || x.item_id, unit: x.unit })); const ids = rows.map((x) => x.id); const q = await sb.from('items').select('id,code,name_bn,name_en').in('id', ids); rows.forEach((x) => { const i = (q.data || []).find((y) => y.id === x.id); if (i) x.label = i.code + ' · ' + lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn }); }); }
  else { const g = D.grnData[id]; const codes = ((g && g.data && g.data.lines) || []).map((x) => x.item).filter(Boolean); const q = await sb.from('items').select('id,code,name_bn,name_en,unit').in('code', codes); rows = (q.data || []).map((i) => ({ id: i.id, label: i.code + ' · ' + lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn }), unit: i.unit })); }
  it.innerHTML = `<option value="">${esc(T('pick'))}</option>` + rows.map((x) => `<option value="${esc(x.id)}" data-u="${esc(x.unit || '')}">${esc(x.label)}</option>`).join('');
}

/* ---------- QC ---------- */
async function qcSheet() {
  const [cl, runs, bills, grns] = await Promise.all([sb.from('option_lists').select('value_code,label_bn,label_mix,label_en,sort').eq('list_code', 'qc_checks').eq('active', true).order('sort'),
    sb.from('production_runs').select('id,made_at,note').order('made_at', { ascending: false }).limit(20), sb.rpc('purchase_list', { p_loc: loc(), p_status: 'posted' }),
    sb.from('entries').select('id,entry_date,data').eq('form_code', '04-1').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).limit(20)]);
  const src = (D.qcKind === 'production' ? (runs.data || []).map((r) => `<option value="${esc(r.id)}">${esc(String(r.made_at).slice(0, 10))} ${esc(r.note || '')}</option>`)
    : (bills.data || []).filter((b) => b.kind === 'bill').map((b) => `<option value="${esc(b.id)}">${esc(b.bill_no || '')} · ${esc(b.supplier_name || '')}</option>`).concat((grns.data || []).map((g) => `<option value="${esc(g.id)}">GRN ${esc(g.entry_date)}</option>`))).join('');
  openSheet(`<h3>${esc(T('qcNew'))}</h3><div class="stack"><label>${esc(T('qcKind'))} <select id="sx_qk" data-sx="qkind"><option value="grn" ${D.qcKind === 'grn' ? 'selected' : ''}>${esc(T('kGrn'))}</option><option value="production" ${D.qcKind === 'production' ? 'selected' : ''}>${esc(T('kProd'))}</option></select></label>
    <select id="sx_qs"><option value="">${esc(T('pick'))}</option>${src}</select>
    <div id="sx_cl" class="stack">${(cl.data || []).map((c) => `<label class="row"><input type="checkbox" class="sx_ck" data-c="${esc(c.value_code)}" checked> ${esc(lab({ bn: c.label_bn, mix: c.label_mix || c.label_bn, en: c.label_en || c.label_bn }))}</label>`).join('')}</div>
    <select id="sx_qst"><option value="pass">${esc(T('pass'))}</option><option value="hold">${esc(T('hold'))}</option><option value="reject">${esc(T('reject'))}</option></select>
    <input id="sx_qn" maxlength="300" placeholder="${esc(T('note'))}"><p class="muted" style="font-size:.8rem">${esc(T('qcOff'))}</p>
    <div class="row"><button type="button" class="btn primary" data-act="sx_qsave">${esc(T('save'))}</button><button type="button" class="btn" data-act="sx_close">${esc(T('close'))}</button></div></div>`);
}

Object.assign(H, {
  sx_tab: (a) => { D.tab = a.dataset.v; frame(); },
  sx_go: () => { collect(); run().catch(failx); },
  sx_close: () => closeSheet(),
  sx_addb: () => addBatchSheet().catch(failx),
  sx_srcpick: (a) => pickSource(a).catch(failx),
  sx_bsave: async () => {
    const src = String($('#sx_src').value).split(':'), item = $('#sx_item').value, q = nnum($('#sx_bq').value);
    if (!src[1] || !item || !(q > 0) || !$('#sx_bx').value) return toast(T('bad'));
    const r = await sb.rpc('grn_batch_add', { p_source_type: src[0], p_source_id: src[1], p_item: item, p_qty: q, p_unit: norm($('#sx_bu').value) || null, p_batch_no: $('#sx_bn').value, p_expiry: $('#sx_bx').value, p_made: null, p_client: rid() });
    if (r.error) return failx(r.error); toast(T('saved')); closeSheet(); run().catch(failx);
  },
  sx_fefo: async (a) => {
    const r = await sb.rpc('fefo_hint', { p_item: a.dataset.i, p_loc: Number(a.dataset.l) }); if (r.error) return failx(r.error);
    openSheet(`<h3>${esc(T('fefo'))}</h3><p class="muted" style="font-size:.8rem">${esc(T('fefoNote'))}</p>${tbl(['#', T('batch'), T('exp'), T('qty')], (r.data || []).map((x) => `<tr><td>${x.rank}</td><td>${esc(x.batch_no || '—')}${x.qc_blocked ? ` <span class="chip warn">${esc(T('blocked'))}</span>` : ''}</td><td>${x.expires_at ? esc(String(x.expires_at).slice(0, 10)) : '—'}${x.expired ? ` <span class="chip warn">${esc(T('expired'))}</span>` : ''}</td><td>${q4(x.qty_remaining)}</td></tr>`))}<button type="button" class="btn" data-act="sx_close">${esc(T('close'))}</button>`);
  },
  sx_qcnew: () => qcSheet().catch(failx),
  sx_qkind: (a) => { D.qcKind = a.value; qcSheet().catch(failx); },
  sx_qsave: async () => {
    const s = $('#sx_qs').value; if (!s) return toast(T('bad'));
    const checks = [...document.querySelectorAll('.sx_ck')].map((c) => ({ code: c.dataset.c, ok: c.checked }));
    const r = await sb.rpc('qc_record', { p_source_type: D.qcKind, p_source_id: s, p_status: $('#sx_qst').value, p_checks: checks, p_note: $('#sx_qn').value || null, p_photo: null, p_client: rid() });
    if (r.error) return failx(r.error); toast(T('saved')); closeSheet(); run().catch(failx);
  },
  sx_hist: async (a) => {
    const r = await sb.rpc('qc_history', { p_source_type: a.dataset.t, p_source_id: a.dataset.s }); if (r.error) return failx(r.error);
    openSheet(`<h3>${esc(T('hist'))}</h3>${tbl(['', T('note'), ''], (r.data || []).map((x) => `<tr><td><span class="chip ${x.status === 'pass' ? '' : 'warn'}">${esc(T(x.status))}</span></td><td>${esc(x.note || '')}</td><td>${esc(String(x.created_at).slice(0, 16).replace('T', ' '))}</td></tr>`))}<button type="button" class="btn" data-act="sx_close">${esc(T('close'))}</button>`);
  },
});
function collect() {
  const l = $('#sx_loc'); if (l) D.loc = l.value || null;
  const d = $('#sx_days'); if (d) D.days = Math.min(365, Math.max(1, Math.round(nnum(d.value)) || 30));
  const e = $('#sx_exd'); if (e) D.exDays = Math.min(365, Math.max(0, Math.round(nnum(e.value)) || 0));
  const f = $('#sx_from'), t = $('#sx_to'); if (f) D.from = f.value || null; if (t) D.to = t.value || null;
}
document.addEventListener('change', (e) => { const k = e.target && e.target.dataset && e.target.dataset.sx; if (k === 'srcpick') H.sx_srcpick(e.target); if (k === 'qkind') H.sx_qkind(e.target); });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  try { D.locs = B.liveLocs ? B.liveLocs(B.ENV.locs) : []; } catch (e) { D.locs = []; }
  D.from = D.from || new Date(Date.now() + 6 * 3600e3 - 30 * 864e5).toISOString().slice(0, 10); D.to = D.to || today();
  frame();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stockx: view });
})();
