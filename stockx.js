/* Islamia BOS · Stock extras (#/stockx): reorder suggestion, near-expiry + batch capture + FEFO hint, wastage by reason, quality checks.
   Server: supabase/phase60.sql — reorder_report, near_expiry_report, fefo_hint, grn_batch_add, wastage_by_reason, qc_record / qc_list / qc_history / qc_gate.
   Everything here is a report or an append-only record: no purchase order is made, no stock is moved, and a quality hold blocks nothing unless the owner
   switched quality_block_on ON (the page only shows that state). Costs are never requested.
   RPT-B3 additions (phases 432-436): the quality check can carry the item, the quantity and the supplier (filters on the list), a tab for goods damaged on transfer receipt,
   a tab for the actual yield of production runs, and the notice "shelf life not set" on the expiry tab. A blank value is always said (data not captured), never shown as 0.
   Each new tab has a CSV (same export right as the other reports). Paper form code of the new captures: to be given by owner. */
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
  pick: L('বেছে নিন…', 'Choose…', 'বেছে নিন…'), mixed: L('ভিন্ন একক: যোগ করা হয়নি', 'Different units: not added up', 'ভিন্ন unit: যোগ করা হয়নি'), mixNote: L('পুরনো ডেটাবেস: ভিন্ন এককের পরিমাণ যোগ হয়ে যেতে পারে (phase 420 চালান)', 'Old database: quantities of different units may be added together (paste phase 420)', 'Old database: ভিন্ন unit যোগ হতে পারে (phase 420 চালান)'), bad: L('সংখ্যা ঠিক নেই', 'Check the numbers', 'সংখ্যা ঠিক নেই'),
  tDm: L('পথে নষ্ট', 'Damaged on receipt', 'Damaged on receipt'), tYi: L('ফলন', 'Yield', 'Yield'),
  yiMoved: L('ফলনের রিপোর্ট এখন উৎপাদন রিপোর্টে', 'The yield report is on the Production reports screen', 'Yield report এখন Production reports এ'), yiMovedSub: L('প্রতিটি রানের আসল ফলন, মালিকের সীমা, কোন তথ্য লেখা হয়নি এবং CSV সেখানে আছে।', 'Actual yield of each run, the owner limit, what is not captured and the CSV are there.', 'প্রতিটি run এর actual yield, owner limit, কোন data লেখা হয়নি, CSV সেখানে।'), yiOpen: L('ফলন রিপোর্ট খুলুন', 'Open the yield report', 'Yield report খুলুন'),
  nc: L('তথ্য লেখা হয়নি', 'data not captured', 'data লেখা হয়নি'), fItem: L('আইটেম', 'item', 'item'), fQty: L('পরিমাণ', 'quantity', 'quantity'), fSupplier: L('সাপ্লায়ার', 'supplier', 'supplier'), fDamaged: L('ক্ষতিগ্রস্ত পরিমাণ', 'damaged quantity', 'damaged quantity'),
  fActual: L('আসল ফলন', 'actual yield', 'actual yield'), fStd: L('স্ট্যান্ডার্ড ফলন', 'standard yield', 'standard yield'),
  shelfMissing: L('এই পণ্যগুলোর মেয়াদের নিয়ম বসানো নেই — তাই এদের ব্যাচে মেয়াদ থাকে না এবং মেয়াদের তালিকা এদের কথা বলে না', 'Shelf life is NOT set for these products — their batches get no expiry, so the expiry lists say nothing about them', 'এই product গুলোর shelf life set নেই — batch এ expiry হয় না, expiry list এদের কথা বলে না'),
  shelfSet: L('মেয়াদের নিয়ম বসান', 'Set the shelf life', 'Shelf life set করুন'),
  qcStatus: L('অবস্থা', 'Status', 'Status'), qcItem: L('আইটেম (ঐচ্ছিক)', 'Item (optional)', 'Item (optional)'), qcQty: L('পরিমাণ (ঐচ্ছিক)', 'Quantity (optional)', 'Quantity (optional)'), qcUnit: L('একক', 'Unit', 'Unit'), qcSup: L('সাপ্লায়ার (ঐচ্ছিক; রসিদে থাকলে নিজে আসে)', 'Supplier (optional; taken from the receipt when it has one)', 'Supplier (optional; receipt এ থাকলে নিজে আসে)'),
  qcPaper: L('কাগজের ফর্মের কোড: মালিক দেবেন', 'paper form code: to be given by owner', 'paper form code: owner দেবেন'), baseUnit: L('— বেস একক —', '— base unit —', '— base unit —'), itemph: L('কোড বা নাম লিখুন', 'Type code or name', 'Code বা নাম লিখুন'),
  dmFrom: L('থেকে', 'From', 'From'), sent: L('পাঠানো', 'Sent', 'Sent'), recv: L('গ্রহণ', 'Received', 'Received'), short: L('কম', 'Short', 'Short'), dmg: L('ক্ষতিগ্রস্ত', 'Damaged', 'Damaged'), dmNote: L('ক্ষতিগ্রস্ত মাল স্টকে গোনা হয়; নষ্ট ধরতে নষ্ট-মাল স্ক্রিন ব্যবহার করুন।', 'Damaged goods are still counted in stock; write them off with the wastage screen.', 'Damaged মাল stock এ গোনা হয়; write-off wastage screen থেকে।'),
  dmNc: L('টি গ্রহণে ক্ষতিগ্রস্ত পরিমাণ লেখা নেই', 'receipts without a damaged quantity', 'receipt এ damaged quantity লেখা নেই'), dmTotal: L('লেখা ক্ষতিগ্রস্ত মোট', 'Damaged total (where written)', 'Damaged total (যেখানে লেখা)'),
  runs: L('রান', 'runs', 'runs'), actualN: L('আসল ফলন লেখা', 'actual yield written', 'actual yield লেখা'), diffPct: L('পার্থক্য', 'Difference', 'Difference'), std: L('স্ট্যান্ডার্ড', 'Standard', 'Standard'), actual: L('আসল', 'Actual', 'Actual'),
  trace: L('ট্রেস', 'Trace', 'Trace'), csv: L('CSV', 'CSV', 'CSV'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export এর permission নেই'), expDone: L('ফাইল নামানো হয়েছে', 'File downloaded', 'File নামানো হয়েছে'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), bad_days: L('দিনের সংখ্যা ঠিক নেই', 'Days must be 1-365', 'Days 1-365 হতে হবে'), bad_range: L('ডেটের সীমা ঠিক নেই', 'Date range is wrong', 'Date range ঠিক নেই'),
  batch_no_exists: L('এই ব্যাচ নম্বর আগে আছে', 'This batch no already exists for the item', 'এই batch no আগে আছে'), more_than_received: L('বিলে যত এসেছে তার বেশি ব্যাচ করা যায় না', 'More than the bill received', 'Bill-এর চেয়ে বেশি'),
  more_than_on_hand: L('হাতে এত মাল নেই', 'More than the stock on hand', 'হাতে এত নেই'), bad_expiry: L('মেয়াদ আজ বা পরের ডেট হতে হবে', 'Expiry must be today or later', 'Expiry আজ বা পরে হতে হবে'),
  bad_batch_no: L('ব্যাচ নম্বর লিখুন (৪০ অক্ষরের মধ্যে)', 'Enter a batch no (max 40 characters)', 'Batch no লিখুন'), item_not_in_source: L('এই আইটেম ওই উৎসে নেই', 'The item is not on that source', 'Item-টা source-এ নেই'),
  source_not_found: L('উৎস পাওয়া যায়নি (জমা/পোস্ট হতে হবে)', 'Source not found (it must be submitted / posted)', 'Source পাওয়া যায়নি'), qc_blocked: L('কোয়ালিটিতে আটক — নতুন ব্যাচ হবে না', 'Held by quality — no new batch', 'Quality hold — নতুন batch না'),
  pass_has_failed_check: L('ব্যর্থ আইটেম থাকলে পাস দেওয়া যায় না', 'A pass cannot have a failed check', 'Failed check থাকলে pass না'), note_required: L('আটক/বাতিলে নোট লিখুন', 'Write a note for hold / reject', 'Hold/reject-এ note লিখুন'),
  unit_unknown: L('একক চেনা যায়নি', 'Unit not recognised', 'Unit চেনা যায়নি'), bad_qty: L('Qty ঠিক নেই', 'Quantity is wrong', 'Quantity ঠিক নেই'),
};
const failx = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? toast(lab(ERR[k])) : fail(e); };
const D = { tab: 're', loc: null, locs: [], days: 30, exDays: 7, from: null, to: null, qcKind: 'grn', csv: null, csvOk: false, qcFrom: '', qcTo: '', qcStatus: '', qcItem: '', qcSupplier: '', sups: [], items: [], data: {} };
const ruleDays = () => { try { const v = Number(B.rule('report_expiry_soon_days', null)); if (Number.isFinite(v) && v >= 0) return v; const w = Number(B.rule('expiry_warn_days', null)); return Number.isFinite(w) && w >= 0 ? w : null; } catch (e) { return null; } };
const locSel = (id) => `<label>${esc(T('place'))} <select id="${id}"><option value="">${esc(T('all'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(D.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>`;
const KIT = () => B.repkit;
const out = (h) => { const el = $('#sx_out'); if (!el) return; const k = KIT(), c = D.csv; el.innerHTML = h + (k && c ? `<div class="rp-foot">${k.csvBtn(D.csvOk, c.key)}</div>` : ''); };
const setCsv = (key, head, rows, flt) => { const k = KIT(); if (!k) return; const cols = head.map((h, i) => ({ key: 'c' + i, label_bn: h, label_en: h, type: 'text' })); D.csv = { key }; k.last[key] = { cols, rows: rows.map((r) => { const o = {}; r.forEach((v, i) => { o['c' + i] = v; }); return o; }), flt }; };
const tbl = (head, rows) => rows.length ? `<div style="overflow-x:auto"><table class="tbl" style="font-size:.8rem;width:100%"><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>` : `<p class="muted">${esc(T('none'))}</p>`;
const loc = () => (D.loc ? Number(D.loc) : null);

/* ---------- tabs ---------- */
function frame() {
  const tabs = [['re', 'tRe'], ['ex', 'tEx'], ['wa', 'tWa'], ['qc', 'tQc'], ['dm', 'tDm'], ['yi', 'tYi']];
  shell(T('title'), `<div class="row wrap">${tabs.map((t) => `<button type="button" class="btn ${D.tab === t[0] ? 'primary' : ''}" data-act="sx_tab" data-v="${t[0]}">${esc(T(t[1]))}</button>`).join('')}</div><div id="sx_ctl"></div><div id="sx_out" class="stack"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  draw();
}
function draw() {
  const ctl = $('#sx_ctl'); if (!ctl) return;
  if (D.tab === 're') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('days'))} <input id="sx_days" type="number" min="1" max="365" value="${D.days}" style="max-width:5rem"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button></div><p class="muted" style="font-size:.8rem">${esc(T('reNote'))}</p>`;
  if (D.tab === 'ex') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('exDays'))} <input id="sx_exd" type="number" min="0" max="365" value="${D.exDays}" style="max-width:5rem"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button><button type="button" class="btn" data-act="sx_addb">${esc(T('addB'))}</button></div>`;
  if (D.tab === 'wa') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('from'))} <input type="date" id="sx_from" value="${esc(D.from)}"></label><label>${esc(T('to'))} <input type="date" id="sx_to" value="${esc(D.to)}"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button></div>`;
  if (D.tab === 'qc') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('qcStatus'))} <select id="sx_qst_f"><option value="">${esc(T('all'))}</option>${['pass', 'hold', 'reject'].map((v) => `<option value="${v}" ${D.qcStatus === v ? 'selected' : ''}>${esc(T(v))}</option>`).join('')}</select></label>
    <label>${esc(T('item'))} <input id="sx_qit_f" list="sx_qit_dl" autocomplete="off" value="${esc(D.qcItem)}" placeholder="${esc(T('itemph'))}" style="max-width:9rem"><datalist id="sx_qit_dl">${D.items.map((i) => `<option value="${esc(itemText(i))}"></option>`).join('')}</datalist></label>
    <label>${esc(lab(L('সাপ্লায়ার', 'Supplier', 'Supplier')))} <select id="sx_qsu_f"><option value="">${esc(T('all'))}</option>${D.sups.map((x) => `<option value="${esc(x.id)}" ${D.qcSupplier === x.id ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select></label>
    <label>${esc(T('from'))} <input type="date" id="sx_qfr_f" value="${esc(D.qcFrom)}"></label><label>${esc(T('to'))} <input type="date" id="sx_qto_f" value="${esc(D.qcTo)}"></label>
    <button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button><button type="button" class="btn primary" data-act="sx_qcnew">${esc(T('qcNew'))}</button></div>`;
  if (D.tab === 'dm' || D.tab === 'yi') ctl.innerHTML = `<div class="row wrap">${locSel('sx_loc')}<label>${esc(T('from'))} <input type="date" id="sx_from" value="${esc(D.from)}"></label><label>${esc(T('to'))} <input type="date" id="sx_to" value="${esc(D.to)}"></label><button type="button" class="btn" data-act="sx_go">${esc(T('show'))}</button></div>${D.tab === 'dm' ? `<p class="muted" style="font-size:.8rem">${esc(T('dmNote'))}</p>` : ''}`;
  run().catch(failx);
}
async function run() {
  D.csv = null; try { D.csvOk = KIT() ? await KIT().canExport() : false; } catch (e) { D.csvOk = false; }
  if (D.tab === 're') {
    const r = await sb.rpc('reorder_report', { p_loc: loc(), p_days: D.days }); if (r.error) throw r.error;
    setCsv('stockx_reorder', [T('item'), T('onhand'), T('min'), T('avg'), T('left'), T('lead'), T('sug')], (r.data || []).map((x) => [x.code + ' ' + (x.name_en || x.name_bn), x.on_hand, x.min_stock, x.avg_daily, x.days_left, x.lead_days, x.suggest_qty]), { loc: loc(), days: D.days });
    out(tbl([T('item'), T('onhand'), T('min'), T('avg'), T('left'), T('lead'), T('sug')], (r.data || []).map((x) =>
      `<tr><td>${esc(x.code)} · ${esc(lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))}<div class="chip ${x.why === 'cover' ? '' : 'warn'}">${esc(T('w_' + x.why))}</div></td><td>${q4(x.on_hand)} ${esc(x.base_unit || '')}</td><td>${q4(x.min_stock)}</td><td>${q4(x.avg_daily)}</td><td>${q4(x.days_left)}</td><td>${q4(x.lead_days)}</td><td><b>${q4(x.suggest_qty)}</b></td></tr>`)));
  } else if (D.tab === 'ex') {
    const r = await sb.rpc('near_expiry_report', { p_loc: loc(), p_days: D.exDays }); if (r.error) throw r.error;
    setCsv('stockx_expiry', [T('item'), T('batch'), T('exp'), T('qty')], (r.data || []).map((x) => [x.code + ' ' + (x.name_en || x.name_bn), x.batch_no || '', String(x.expires_at).slice(0, 10), x.qty_remaining]), { loc: loc(), days: D.exDays });
    let shelfNote = '';
    try { const sm = await sb.rpc('shelf_life_missing', { p_loc: loc() }); const it = sm && !sm.error && sm.data && sm.data.items; if (it && it.length) shelfNote = `<div class="notice warn" data-shelf-missing="1"><b>${esc(T('shelfMissing'))}</b><div>${it.map((x) => esc(x.code + ' · ' + lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))).join(', ')}</div><button type="button" class="mini" data-act="go" data-v="settings2/shelf">${esc(T('shelfSet'))}</button></div>`; } catch (e) { /* phase 433 not installed */ }
    out(shelfNote + tbl([T('item'), T('batch'), T('exp'), T('qty'), ''], (r.data || []).map((x) =>
      `<tr><td>${esc(x.code)} · ${esc(lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))}</td><td>${esc(x.batch_no || '—')}${x.qc_blocked ? `<div class="chip warn">${esc(T('blocked'))}</div>` : ''}</td><td>${esc(String(x.expires_at).slice(0, 10))}${x.expired ? `<div class="chip warn">${esc(T('expired'))}</div>` : ` · ${q4(x.days_left)}d`}</td><td>${q4(x.qty_remaining)}</td><td><button type="button" class="mini" data-act="sx_fefo" data-i="${esc(x.item_id)}" data-l="${x.location_id}">${esc(T('fefo'))}</button></td></tr>`)));
  } else if (D.tab === 'wa') {
    let r = await sb.rpc('wastage_by_reason2', { p_loc: loc(), p_from: D.from, p_to: D.to }), two = true;
    if (r.error && /could not find|does not exist|schema cache/i.test(r.error.message || '')) { r = await sb.rpc('wastage_by_reason', { p_loc: loc(), p_from: D.from, p_to: D.to }); two = false; }
    if (r.error) throw r.error;
    const qtyOf = (x) => (two ? (x.units || []).map((u) => `${q4(u.qty)} ${esc(u.unit)}`).join(' + ') : q4(x.qty));
    setCsv('stockx_wastage', [T('reason'), T('entries'), T('items'), T('qty')], (r.data || []).map((x) => [x.label_en || x.label_bn, x.entries, x.items, two ? (x.units || []).map((u) => u.qty + ' ' + u.unit).join(' + ') : x.qty]), { loc: loc(), from: D.from, to: D.to });
    out(`${two ? '' : `<div class="notice warn">${esc(T('mixNote'))}</div>`}` + tbl([T('reason'), T('entries'), T('items'), T('qty')], (r.data || []).map((x) =>
      `<tr><td>${esc(lab({ bn: x.label_bn, mix: x.label_mix || x.label_bn, en: x.label_en || x.label_bn }))}</td><td>${x.entries}</td><td>${x.items}</td><td>${qtyOf(x)}${two && x.mixed_units ? `<div class="chip warn">${esc(T('mixed'))}</div>` : ''}</td></tr>`)));
  } else if (D.tab === 'qc') {
    const args = { p_loc: loc(), p_from: D.qcFrom || null, p_to: D.qcTo || null, p_status: D.qcStatus || null };
    const it = itemFrom(D.items, D.qcItem); if (it) args.p_item = it.id; if (D.qcSupplier) args.p_supplier = D.qcSupplier;
    const [r, sw] = await Promise.all([sb.rpc('qc_list', args), sb.rpc('qc_gate', { p_source_type: 'grn', p_source_id: '00000000-0000-0000-0000-000000000000' })]);
    if (r.error) throw r.error;
    D.data.qc = r.data || [];
    const on = !!(sw.data && sw.data.switch_on);
    const ncT = (k) => `<span class="muted">${esc(T('nc'))}: ${esc(T(k))}</span>`;
    out(`<p class="muted" style="font-size:.8rem">${esc(T(on ? 'qcOn' : 'qcOff'))}</p>` + tbl([T('qcKind'), '', T('item'), T('note'), ''], D.data.qc.map((x) =>
      `<tr><td>${esc(T(x.source_type === 'production' ? 'kProd' : 'kGrn'))}<div class="muted">${esc(String(x.created_at).slice(0, 10))}</div><div class="muted">${x.supplier_name ? esc(x.supplier_name) : ncT('fSupplier')}</div></td><td><span class="chip ${x.status === 'pass' ? '' : 'warn'}">${esc(T(x.status))}</span></td>
        <td>${x.item_id ? esc(x.item_code) + ' · ' + esc(lab({ bn: x.item_name_bn, mix: x.item_name_bn, en: x.item_name_en || x.item_name_bn })) : ncT('fItem')}<div>${x.qty !== null && x.qty !== undefined ? q4(x.qty) + ' ' + esc(x.base_unit || '') : ncT('fQty')}</div></td><td>${esc(x.note || '')}</td><td><button type="button" class="mini" data-act="sx_hist" data-t="${esc(x.source_type)}" data-s="${esc(x.source_id)}">${esc(T('hist'))} (${x.history_n})</button></td></tr>`))
      + `<div class="row"><button type="button" class="btn" data-act="sx_csv">${esc(T('csv'))}</button></div>`);
  } else if (D.tab === 'dm') {
    const r = await sb.rpc('transfer_damage_report', { p_from: D.from, p_to: D.to, p_loc: loc() }); if (r.error) throw r.error;
    const d = D.data.dm = r.data || {};
    out(`<div class="card">${esc(T('recv'))}: <b>${d.received_n ?? 0}</b> · ${esc(T('dmTotal'))}: ${d.damaged_total_captured === null || d.damaged_total_captured === undefined ? `<span class="muted">${esc(T('nc'))}: ${esc(T('fDamaged'))}</span>` : '<b>' + q4(d.damaged_total_captured) + '</b>'}${d.damaged_not_captured_n ? ` <span class="muted">(${d.damaged_not_captured_n} ${esc(T('dmNc'))})</span>` : ''}</div>`
      + tbl([T('item'), T('dmFrom'), T('sent'), T('recv'), T('dmg'), ''], (d.rows || []).map((x) =>
        `<tr><td>${esc(x.code)} · ${esc(lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }))}<div class="muted">${esc(String(x.day))}</div></td><td>${esc(x.from_name)} → ${esc(x.to_name)}</td><td>${q4(x.qty_sent)}</td><td>${q4(x.received_qty)}${Number(x.short) > 0 ? `<div class="chip warn">${esc(T('short'))} ${q4(x.short)}</div>` : ''}</td>
          <td>${x.damaged === null || x.damaged === undefined ? `<span class="muted">${esc(T('nc'))}: ${esc(T('fDamaged'))}</span>` : `<b>${q4(x.damaged)}</b>${x.reason_label ? `<div class="muted">${esc(lab({ bn: x.reason_label_bn || x.reason_label, mix: x.reason_label, en: x.reason_label }))}</div>` : ''}`}</td>
          <td>${x.batch_id ? `<button type="button" class="mini" data-act="go" data-v="trace/${esc(x.batch_id)}">${esc(T('trace'))}</button>` : ''}</td></tr>`))
      + `<div class="row"><button type="button" class="btn" data-act="sx_csv">${esc(T('csv'))}</button></div>`);
  } else {
    // INTEGRATION: the yield of production runs has ONE screen, Production reports > Yield (RPT-B4: owner limit, "not captured" states, drill-down, CSV).
    // This tab only leads there; the server function yield_report (phase 433) stays and answers the same question.
    D.data.yi = null; D.csv = null;
    out(`<div class="card stack"><b>${esc(T('yiMoved'))}</b><p class="muted" style="margin:0">${esc(T('yiMovedSub'))}</p><button type="button" class="primary full" data-act="go" data-v="prodreports/yield">${esc(T('yiOpen'))} ›</button></div>`);
  }
}

/* ---------- RPT-B3 helpers ---------- */
const itemText = (i) => i.code + ' · ' + lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn });
const itemFrom = (items, v) => { const x = String(v || '').trim(); if (!x) return null; const c = x.split(' · ')[0].trim().toLowerCase(); return items.find((i) => i.code.toLowerCase() === c) || null; };
async function qcItems(sel) {            // fill the optional item list of the quality sheet from the chosen source
  const box = $('#sx_qi'); if (!box) return; const id = sel.value; box.innerHTML = `<option value="">${esc(T('pick'))}</option>`; if (!id) return;
  let ids = [], codes = [];
  if (D.qcKind === 'production') { const r = await sb.from('production_runs').select('item_id').eq('id', id).maybeSingle(); if (r.data && r.data.item_id) ids = [r.data.item_id]; }
  else {
    const b = await sb.rpc('purchase_get', { p_id: id });
    if (b && !b.error && b.data && b.data.lines) ids = b.data.lines.filter((x) => x.item_id).map((x) => x.item_id);
    else { const g = await sb.from('entries').select('data').eq('id', id).maybeSingle(); codes = ((g.data && g.data.data && g.data.data.lines) || []).map((x) => x.item).filter(Boolean); }
  }
  const found = D.items.filter((i) => ids.includes(i.id) || codes.includes(i.code));
  box.innerHTML += found.map((i) => `<option value="${esc(i.id)}">${esc(itemText(i))}</option>`).join('');
  if (found.length === 1) box.value = found[0].id;
}
const csvCell = (v) => { let t = v === null || v === undefined ? '' : String(v); if (/^[=+\-@]/.test(t) && !/^-?\d+(\.\d+)?$/.test(t)) t = "'" + t; return /[",\r\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
async function exportCsv() {
  const nc = (k) => T('nc') + ': ' + T(k);
  let key, name, rows;
  if (D.tab === 'qc') {
    key = 'quality_checks'; name = 'quality-checks'; rows = [[T('qcKind'), 'date', 'status', 'code', T('item'), 'qty', 'unit', 'supplier', T('note')]];
    (D.data.qc || []).forEach((x) => rows.push([x.source_type, String(x.created_at).slice(0, 10), x.status, x.item_code || '', x.item_id ? lab({ bn: x.item_name_bn, mix: x.item_name_bn, en: x.item_name_en || x.item_name_bn }) : nc('fItem'), x.qty ?? nc('fQty'), x.qty === null || x.qty === undefined ? '' : x.base_unit || '', x.supplier_name || nc('fSupplier'), x.note || '']));
  } else if (D.tab === 'dm') {
    key = 'transfer_damage'; name = `damaged-on-receipt-${D.from}_${D.to}`; const d = D.data.dm || {};
    rows = [['date', 'code', T('item'), T('dmFrom'), T('sent'), T('recv'), T('short'), T('dmg'), 'reason']];
    (d.rows || []).forEach((x) => rows.push([x.day, x.code, lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }), x.from_name + ' > ' + x.to_name, x.qty_sent, x.received_qty, x.short, x.damaged ?? nc('fDamaged'), x.reason_label || '']));
    rows.push([], [T('dmTotal'), d.damaged_total_captured ?? nc('fDamaged'), d.damaged_not_captured_n + ' ' + T('dmNc')]);
  } else {
    key = 'yield'; name = `production-yield-${D.from}_${D.to}`; const d = D.data.yi || {};
    rows = [['date', 'code', T('item'), 'place', T('std'), T('actual'), T('diffPct') + ' %']];
    (d.rows || []).forEach((x) => rows.push([x.day, x.code, lab({ bn: x.name_bn, mix: x.name_bn, en: x.name_en || x.name_bn }), x.location, x.yield_std ?? nc('fStd'), x.yield_actual ?? nc('fActual'), x.var_pct ?? '']));
    rows.push([], ['summary', 'runs', 'actual written', 'actual not captured', 'difference %']); (d.summary || []).forEach((x) => rows.push([x.code, x.runs, x.actual_captured, x.actual_not_captured, x.var_pct ?? nc('fActual')]));
  }
  const r = await sb.rpc('rb3_log_export', { p_key: key, p_kind: 'csv', p_filters: { tab: D.tab, from: D.from, to: D.to, loc: loc() }, p_rows: rows.length });
  if (r && r.error) return toast(/not allowed/.test(r.error.message || '') ? T('expLock') : r.error.message);
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['\ufeff' + rows.map((r2) => r2.map(csvCell).join(',')).join('\r\n') + '\r\n'], { type: 'text/csv;charset=utf-8' })); a.download = name + '.csv'; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); toast(T('expDone'));
}

/* ---------- batch capture ---------- */
async function addBatchSheet() {
  const l = loc();
  const [bills, grns] = await Promise.all([sb.rpc('purchase_list', { p_loc: l, p_status: 'posted' }), sb.from('entries').select('id,entry_date,data,status').eq('form_code', '13-1').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).limit(30)]);
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
    sb.from('entries').select('id,entry_date,data').eq('form_code', '13-1').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).limit(20)]);
  const src = (D.qcKind === 'production' ? (runs.data || []).map((r) => `<option value="${esc(r.id)}">${esc(String(r.made_at).slice(0, 10))} ${esc(r.note || '')}</option>`)
    : (bills.data || []).filter((b) => b.kind === 'bill').map((b) => `<option value="${esc(b.id)}">${esc(b.bill_no || '')} · ${esc(b.supplier_name || '')}</option>`).concat((grns.data || []).map((g) => `<option value="${esc(g.id)}">GRN ${esc(g.entry_date)}</option>`))).join('');
  openSheet(`<h3>${esc(T('qcNew'))}</h3><div class="stack"><label>${esc(T('qcKind'))} <select id="sx_qk" data-sx="qkind"><option value="grn" ${D.qcKind === 'grn' ? 'selected' : ''}>${esc(T('kGrn'))}</option><option value="production" ${D.qcKind === 'production' ? 'selected' : ''}>${esc(T('kProd'))}</option></select></label>
    <select id="sx_qs" data-sx="qsrc"><option value="">${esc(T('pick'))}</option>${src}</select>
    <div id="sx_cl" class="stack">${(cl.data || []).map((c) => `<label class="row"><input type="checkbox" class="sx_ck" data-c="${esc(c.value_code)}" checked> ${esc(lab({ bn: c.label_bn, mix: c.label_mix || c.label_bn, en: c.label_en || c.label_bn }))}</label>`).join('')}</div>
    <select id="sx_qst"><option value="pass">${esc(T('pass'))}</option><option value="hold">${esc(T('hold'))}</option><option value="reject">${esc(T('reject'))}</option></select>
    <input id="sx_qn" maxlength="300" placeholder="${esc(T('note'))}">
    <label>${esc(T('qcItem'))} <select id="sx_qi"><option value="">${esc(T('pick'))}</option></select></label>
    <div class="row wrap"><input id="sx_qq" inputmode="decimal" placeholder="${esc(T('qcQty'))}" style="max-width:9rem"><select id="sx_qu"><option value="">${esc(T('baseUnit'))}</option>${(((B.ENV && B.ENV.lists && B.ENV.lists.units) || []).filter((u) => u.active !== false)).map((u) => `<option value="${esc(u.value_code)}">${esc(lab({ bn: u.label_bn, en: u.label_en || undefined, mix: u.label_mix || undefined }))}</option>`).join('')}</select></div>
    <label>${esc(T('qcSup'))} <select id="sx_qs2"><option value="">—</option>${D.sups.map((x) => `<option value="${esc(x.id)}">${esc(x.name)}</option>`).join('')}</select></label>
    <p class="muted" style="font-size:.8rem">${esc(T('qcOff'))}</p><p class="muted" style="font-size:.8rem">${esc(T('qcPaper'))}</p>
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
  sx_qsrc: (a) => qcItems(a).catch(failx),
  sx_csv: () => exportCsv().catch(failx),
  sx_qkind: (a) => { D.qcKind = a.value; qcSheet().catch(failx); },
  sx_qsave: async () => {
    const s = $('#sx_qs').value; if (!s) return toast(T('bad'));
    const checks = [...document.querySelectorAll('.sx_ck')].map((c) => ({ code: c.dataset.c, ok: c.checked }));
    const base = { p_source_type: D.qcKind, p_source_id: s, p_status: $('#sx_qst').value, p_checks: checks, p_note: $('#sx_qn').value || null, p_photo: null, p_client: rid() };
    const item = ($('#sx_qi') || {}).value || '', qraw = norm(($('#sx_qq') || {}).value), sup = ($('#sx_qs2') || {}).value || '';
    const qty = qraw === '' ? null : nnum(qraw); if (qty !== null && !(qty > 0)) return toast(T('bad')); if (qty !== null && !item) return toast(T('qcItem'));
    const args = (item || qty !== null || sup) ? Object.assign(base, { p_item: item || null, p_qty: qty, p_unit: qty === null ? null : (($('#sx_qu') || {}).value || null), p_supplier: sup || null }) : base;
    const r = await sb.rpc('qc_record', args);
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
  const e = $('#sx_exd'); if (e) D.exTouched = true; if (e) D.exDays = Math.min(365, Math.max(0, Math.round(nnum(e.value)) || 0));
  const f = $('#sx_from'), t = $('#sx_to'); if (f) D.from = f.value || null; if (t) D.to = t.value || null;
  const qs = $('#sx_qst_f'); if (qs) { D.qcStatus = qs.value || ''; D.qcItem = ($('#sx_qit_f') || {}).value || ''; D.qcSupplier = ($('#sx_qsu_f') || {}).value || ''; D.qcFrom = ($('#sx_qfr_f') || {}).value || ''; D.qcTo = ($('#sx_qto_f') || {}).value || ''; }
}
document.addEventListener('change', (e) => { const k = e.target && e.target.dataset && e.target.dataset.sx; if (k === 'srcpick') H.sx_srcpick(e.target); if (k === 'qkind') H.sx_qkind(e.target); if (k === 'qsrc') H.sx_qsrc(e.target); });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  try { D.locs = B.liveLocs ? B.liveLocs(B.ENV.locs) : []; } catch (e) { D.locs = []; }
  { const rd = ruleDays(); if (rd !== null && !D.exTouched) D.exDays = rd; }
  D.from = D.from || new Date(Date.now() + 6 * 3600e3 - 30 * 864e5).toISOString().slice(0, 10); D.to = D.to || today();
  try {                                    // optional lists for the quality filters (the page works without them)
    const [su, it] = await Promise.all([sb.from('suppliers').select('id,name,active').order('name'), window.BOS_ALL ? window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,is_active').order('code')) : Promise.resolve({ data: [] })]);
    D.sups = ((su && su.data) || []).filter((x) => x.active !== false); D.items = ((it && it.data) || []).filter((x) => x.is_active !== false);
  } catch (e) { D.sups = []; D.items = []; }
  frame();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stockx: view });
})();
