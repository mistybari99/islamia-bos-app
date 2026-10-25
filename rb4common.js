/* Islamia BOS · RPT-B4 shared helpers (B.rb4) for the production, target and capacity screens: web/prodplan.js, prodreports.js, targets.js, capacity.js.
   Server: supabase/phase404.sql .. phase416.sql. Nothing here decides a figure: every number comes from a server function; this file only draws it.
   Rules kept on every screen: a missing figure is "data not captured: <field>" (never 0, never an estimate); money is drawn only when the server sent it (cost right);
   every report has a CSV (an audit line is written first by rb4_log_export, a refusal means no file) and every row opens a detail sheet with links to its source.
   B.rb4.page(cfg) builds a tabbed report page from a plain description (tabs -> server function -> blocks -> columns). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, nm, S } = A;
const H = A.H;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);

const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const isNum = (n) => n !== null && n !== undefined && n !== '' && Number.isFinite(Number(n));
const q4 = (n) => (isNum(n) ? Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }) : '—');
const money = (n) => (isNum(n) ? '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }) : '—');
const pct = (n) => (isNum(n) ? Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }) + ' %' : '—');
const d10 = (v) => (v ? String(v).slice(0, 10) : '');
const dhaka = (ms) => new Date(ms).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const today = () => dhaka(Date.now());
const daysAgo = (n) => dhaka(Date.now() - n * 86400000);
const monthStart = (iso) => String(iso || today()).slice(0, 7) + '-01';
const unitL = (c) => (B.s2 && B.s2.unitLabel ? B.s2.unitLabel(c) : c || '');

// ---------- texts shared by all four screens ----------
const X = {
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), place: L('জায়গা', 'Place', 'Place'), item: L('পণ্য', 'Item', 'Item'), all: L('সব', 'All', 'All'), show: L('দেখুন', 'Show', 'Show'),
  none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'), nc: L('তথ্য লেখা হয়নি', 'data not captured', 'data লেখা হয়নি'),
  costHidden: L('টাকার অঙ্ক দেখার অনুমতি আপনার নেই — শুধু পরিমাণ দেখানো হচ্ছে।', 'You may not see money figures — quantities only.', 'টাকার অঙ্ক দেখার permission নেই — শুধু quantity।'),
  csv: L('CSV', 'CSV', 'CSV'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export এর permission নেই'), expDone: L('ফাইল নামানো হয়েছে', 'File downloaded', 'File নামানো হয়েছে'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), trunc: L('তালিকা ছোট করা হয়েছে', 'The list is cut short', 'List ছোট করা হয়েছে'),
  paperCode: L('কাগজের ফর্মের কোড: মালিক দেবেন', 'paper form code: to be given by owner', 'paper form code: owner দেবেন'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('থাক', 'Cancel', 'Cancel'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), close: L('বন্ধ', 'Close', 'Close'), open: L('খুলুন', 'Open', 'Open'),
  why: L('কারণ (কমপক্ষে ৩ অক্ষর)', 'Reason (at least 3 characters)', 'Reason (কমপক্ষে ৩ অক্ষর)'), note: L('নোট', 'Note', 'Note'), details: L('বিস্তারিত', 'Details', 'Details'), sources: L('উৎস', 'Source', 'Source'),
  basis: L('হিসাবের ভিত্তি', 'Basis', 'Basis'), loading: L('দেখা হচ্ছে…', 'Loading…', 'Loading…'), unit: L('একক', 'Unit', 'Unit'), itemph: L('কোড বা নাম লিখুন', 'Type code or name', 'Code বা নাম লিখুন'),
  generated: L('তৈরি', 'Generated', 'Generated'),
};
const T = (k) => lab(X[k]);
const NC = (field) => `${T('nc')}: ${typeof field === 'string' ? field : field ? lab(field) : ''}`.replace(/: $/, '');

// notes the server sends as {code, field}; each says what is not captured or not set
const NOTE = {
  plan_not_captured: L('কোনো উৎপাদন পরিকল্পনা লেখা নেই', 'No production plan is entered for this period', 'কোনো production plan লেখা নেই'),
  order_not_captured: L('কোনো উৎপাদন অর্ডার লেখা নেই', 'No production order is entered', 'কোনো production order লেখা নেই'),
  actual_issue_not_captured: L('কোনো রানে আসল ব্যবহার লেখা নেই — তাই আসল-বনাম-রেসিপি বের করা যায়নি', 'No run has its real use of ingredients recorded, so real-against-recipe cannot be worked out', 'কোনো run-এ আসল ব্যবহার লেখা নেই — real-vs-recipe বের করা যায়নি'),
  no_run_fully_measured: L('কোনো রান পুরোপুরি মাপা যায়নি — নিচে লেখা ঘর ভরলে ভাগ দেখা যাবে', 'No run is fully measured; the split appears when the missing inputs below are captured', 'কোনো run পুরো মাপা যায়নি — missing ঘর ভরলে split দেখা যাবে'),
  limit_not_set: L('মালিক সীমা ঠিক করেননি, তাই কোনো রান চিহ্নিত হয়নি', 'The owner has not set a limit, so no run is flagged', 'Owner limit ঠিক করেননি, তাই কোনো run flag হয়নি'),
  actual_yield_not_captured: L('কোনো রানে আসল ফলন লেখা নেই', 'No run has an actual yield typed', 'কোনো run-এ actual yield লেখা নেই'),
  loss_not_captured: L('কোনো রানে বাতিল / পুনঃকাজ লেখা নেই', 'No run has a reject / rework record', 'কোনো run-এ reject / rework লেখা নেই'),
  labour_not_captured: L('কোনো রানে শ্রম-ঘণ্টা লেখা নেই', 'No run has labour hours recorded', 'কোনো run-এ labour hours লেখা নেই'),
  capacity_not_captured: L('কোনো রেটেড ক্ষমতা লেখা নেই', 'No rated capacity is entered', 'কোনো rated capacity লেখা নেই'),
  target_not_set: L('এই সময়ের জন্য কোনো লক্ষ্য ঠিক করা নেই', 'No target is set for this period', 'এই সময়ের কোনো target ঠিক করা নেই'),
  alert_limit_not_set: L('সীমা ঠিক করা নেই — এই ধরনের সতর্কতা বন্ধ', 'Limit not set — this kind of alert is off', 'Limit ঠিক নেই — এই alert বন্ধ'),
  not_enough_history: L('কিছু দিনের তুলনার মতো যথেষ্ট আগের দিন নেই — সেগুলোর সতর্কতা দেওয়া হয়নি', 'Some days have too few earlier days to compare — no alert was given for them', 'কিছু দিনের তুলনার মতো আগের দিন নেই — alert দেওয়া হয়নি'),
  snapshot_not_captured: L('এই সময়ের কোনো দৈনিক স্ন্যাপশট নেই — "স্ন্যাপশট নিন" চাপুন', 'There is no daily snapshot for this period — tap "Take snapshots"', 'এই সময়ের daily snapshot নেই — "Snapshot নিন" চাপুন'),
  transfers_not_valued: L('পাঠানো মালের দাম ধরা হয়নি (মালিকের সেটিং: কোনোটি নয়) — শুধু পরিমাণ ও খরচ', 'Transfers are not valued (owner setting: none) — quantities and cost only', 'Transfer-এর দাম ধরা হয়নি (owner setting: none) — শুধু quantity ও cost'),
  pct_not_set: L('শতাংশ ঠিক করা নেই, তাই দাম বের হয়নি', 'The percentage is not set, so no value is worked out', 'শতাংশ ঠিক নেই, তাই দাম বের হয়নি'),
  no_factory_place: L('আপনি দেখতে পারেন এমন কোনো কারখানা নেই', 'There is no factory place you may see', 'আপনি দেখতে পারেন এমন কোনো factory নেই'),
};
function notesHtml(notes) {
  return (notes || []).map((n) => `<div class="notice warn">${esc(NOTE[n.code] ? lab(NOTE[n.code]) : n.code)}${n.field ? ` <span class="muted">(${esc(NC(n.field))})</span>` : ''}${n.days ? ` <b>${esc(n.days)}</b>` : ''}</div>`).join('');
}

// ---------- server errors in the reader's language ----------
const ERR = {
  not_allowed: X.noperm, 'not allowed': X.noperm, 'not allowed for this location': L('এই জায়গা আপনার নয়', 'You may not see this place', 'এই place আপনার নয়'),
  bad_range: L('ডেটের সীমা ঠিক নয়', 'The date range is not valid', 'Date range ঠিক নয়'), bad_status: L('অবস্থা ঠিক নয়', 'The status is not valid', 'Status ঠিক নয়'),
  note_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'Reason লিখুন (কমপক্ষে ৩ অক্ষর)'),
  item_not_found: L('পণ্য পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি'), unit_unknown: L('এককের রূপান্তর জানা নেই', 'Unit conversion unknown', 'Unit conversion জানা নেই'),
  bad_qty: L('পরিমাণ ঠিক নয়', 'The quantity is not valid', 'Quantity ঠিক নয়'), bad_date: L('ডেট ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'), bad_location: L('জায়গা ঠিক নয়', 'The place is not valid', 'Place ঠিক নয়'),
  plan_needs_batches_or_qty: L('ব্যাচ সংখ্যা বা পরিমাণ — একটি লিখুন', 'Write the batches or the quantity', 'Batch সংখ্যা বা quantity লিখুন'), recipe_not_found: L('রেসিপি এই পণ্যের নয়', 'The recipe is not for this item', 'Recipe এই item-এর নয়'),
  order_not_open: L('অর্ডারটি আর খোলা নেই', 'The order is no longer open', 'Order আর open নেই'), link_mismatch: L('পরিকল্পনা / অর্ডার এই রানের পণ্য বা জায়গার সাথে মেলে না', "The plan / order does not match the run's item or place", 'Plan / order run-এর item বা place-এর সাথে মেলে না'),
  plan_cancelled: L('পরিকল্পনাটি বাতিল', 'The plan is cancelled', 'Plan cancelled'), run_void: L('রানটি বাতিল হয়ে গেছে', 'The run is void', 'Run void হয়ে গেছে'),
  no_lines: L('কোনো লাইন নেই', 'No lines', 'কোনো line নেই'), duplicate_item: L('একই কাঁচামাল দুইবার', 'The same ingredient twice', 'একই ingredient দুইবার'), too_many_lines: L('লাইন অনেক বেশি', 'Too many lines', 'Line অনেক বেশি'),
  reason_required: L('তালিকা থেকে একটি কারণ বেছে নিন', 'Pick a reason from the list', 'List থেকে reason বেছে নিন'), exceeds_output: L('বাতিল + পুনঃকাজ রানের উৎপাদনের চেয়ে বেশি হতে পারে না', 'Reject + rework cannot be more than the run made', 'Reject + rework run-এর output-এর বেশি হতে পারে না'),
  loss_already_recorded: L('এই রানে আগেই বাতিল / পুনঃকাজ লেখা আছে', 'This run already has a loss recorded', 'এই run-এ আগেই loss লেখা আছে'), bad_kind: L('ধরন ঠিক নয়', 'The kind is not valid', 'Kind ঠিক নয়'),
  bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'The amount is not valid', 'Amount ঠিক নয়'), bad_gp_pct: L('লাভের % ০ থেকে ১০০ হতে হবে', 'Gross profit % must be 0 to 100', 'GP % ০ থেকে ১০০'),
  day_not_closed: L('আজকের দিন শেষ হয়নি — গতকাল পর্যন্ত নেওয়া যায়', 'Today is not finished — take up to yesterday', 'আজ শেষ হয়নি — গতকাল পর্যন্ত নিন'),
  bad_name: L('নাম ঠিক নয়', 'The name is not valid', 'Name ঠিক নয়'), line_not_found: L('লাইন পাওয়া যায়নি', 'Line not found', 'Line পাওয়া যায়নি'),
  bad_capacity: L('ব্যাচ প্রতি দিন ঠিক নয়', 'Batches per day is not valid', 'Batch per day ঠিক নয়'), bad_days: L('সপ্তাহে কাজের দিন ০-৭ এর মধ্যে', 'Working days a week must be above 0 and at most 7', 'Week-এ কাজের দিন ০-৭'),
  bad_people: L('লোকসংখ্যা ঠিক নয়', 'The number of people is not valid', 'People সংখ্যা ঠিক নয়'), bad_hours: L('ঘণ্টা ঠিক নয় (০-র বেশি, ২৪ পর্যন্ত)', 'Hours are not valid (above 0, up to 24)', 'Hours ঠিক নয় (০-র বেশি, ২৪ পর্যন্ত)'),
  unknown_report: L('রিপোর্ট চেনা যায়নি', 'Unknown report', 'Report চেনা যায়নি'), client_id_taken: L('এই এন্ট্রি অন্যের', 'This entry belongs to someone else', 'এই entry অন্যের'),
  'duplicate key': L('এই নাম আগেই আছে', 'This name already exists', 'এই name আগেই আছে'), not_found: L('পাওয়া যায়নি', 'Not found', 'পাওয়া যায়নি'),
};
const errText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };

// ---------- csv ----------
const csvCell = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
function download(name, text) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }
async function exportCSV(key, name, rows, filters) {
  const r = await sb.rpc('rb4_log_export', { p_key: key, p_kind: 'csv', p_filters: filters || {}, p_rows: rows.length });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : errText(r.error)); return false; }
  const p = (S.ctx && S.ctx.profile) || {};
  download(name + '.csv', rows.concat([[], [name, new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)', p.full_name || p.staff_id || '']]).map((r2) => r2.map(csvCell).join(',')).join('\r\n') + '\r\n');
  toast(T('expDone')); return true;
}

// ---------- small html pieces ----------
const tbl = (head, rows) => (rows.length ? `<div class="scrollx"><table class="tbl" style="font-size:.8rem;width:100%"><thead><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>` : `<p class="muted">${esc(T('none'))}</p>`);
const costNote = (d) => (d && d.cost_hidden ? `<div class="notice warn">${esc(T('costHidden'))}</div>` : '');
const truncNote = (d) => (d && d.truncated ? `<div class="notice warn">${esc(T('trunc'))}</div>` : '');
const basisNote = (d) => { const txt = d ? [d.statement, d.basis && String(d.basis).includes(' ') ? d.basis : null].filter(Boolean).join(' ') : ''; return txt ? `<details class="muted" style="margin:6px 0"><summary>${esc(T('basis'))}</summary><p>${esc(txt)}</p></details>` : ''; };
const go = (hash, label) => `<button type="button" class="mini" data-act="rb4_go" data-v="${esc(hash)}">${esc(label)}</button>`;
const nmOf = (r, f) => { const en = r[(f || 'name') + '_en'], bn = r[(f || 'name') + '_bn']; return (S.lang === 'en' ? en || bn : bn || en) || ''; };
const locName = (r, k) => { const bn = r[k || 'location'], en = r[(k || 'location') + '_en']; return (S.lang === 'en' ? en || bn : bn || en) || ''; };
const itemName = (r) => (r.code ? r.code + ' · ' : '') + nmOf(r);

// ---------- base data every screen needs ----------
async function loadBase(D, o) {
  if (B.loadStatic) await B.loadStatic();
  try { D.locs = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : []; } catch (e) { D.locs = []; }
  if (!(S.ctx.is_owner || (S.ctx.roles || []).includes('management'))) D.locs = D.locs.filter((l) => (S.ctx.locations || []).includes(l.id));
  if (!o || o.items !== false) {
    const i = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,is_active,hidden,item_type').order('code'));
    D.items = i.error ? [] : (i.data || []).filter((x) => x.is_active !== false && !x.hidden);
  }
  return D;
}
const itemText = (i) => i.code + ' · ' + nm(i);
const itemFrom = (D, v) => { const s = String(v || '').trim(); if (!s) return null; const c = s.split(' · ')[0].trim().toLowerCase(); return D.items.find((i) => i.code.toLowerCase() === c) || D.items.find((i) => nm(i).toLowerCase() === s.toLowerCase()) || null; };
function itemFld(D, id, label) { return `<div><label for="${id}">${esc(label || T('item'))}</label><input id="${id}" list="${id}_dl" autocomplete="off" placeholder="${esc(T('itemph'))}"><datalist id="${id}_dl">${D.items.map((i) => `<option value="${esc(itemText(i))}"></option>`).join('')}</datalist></div>`; }
const placeSel = (D, id, val, allLabel) => `<select id="${id}"><option value="">${esc(allLabel === false ? '—' : T('all'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(val) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;

// ---------- the generic report page ----------
// cfg: { route, act, title, tabs: [tab], init(D) async, handlers(D, api) -> {name: fn}, range: 'days30' | 'month' }
// tab: { id, label, rpc, args(D), filters: ['date','loc','item'], top(d, D) html, blocks: [block], after(d, D) html, csvKey, csvName, intro(D) html }
// block: { title, rows(d) -> [], cols: [col], status: {code: L}, warn(row) bool, links(row) -> [{label, hash}], detail(row, d) html, empty }
// col: { l: L, get(row), f: 'text'|'q4'|'money'|'pct'|'date'|'int'|'status'|'bool', nc: L|string, w: 't'|'c'|'s', money: true, unit(row) }
function page(cfg) {
  const A_ = cfg.act;
  const D = { tab: cfg.tabs[0].id, from: null, to: null, loc: '', item: '', status: '', locs: [], items: [], data: {}, busy: false, ready: false };
  const cur = () => cfg.tabs.find((t) => t.id === D.tab) || cfg.tabs[0];
  const out = (h) => { const el = $('#' + A_ + '_out'); if (el) el.innerHTML = h; };
  const showFilter = (tab, k) => (tab.filters || ['date', 'loc', 'item']).includes(k);

  function cellOf(col, r, d, block) {
    let v = col.get(r);
    const hide = col.money && d && d.cost_hidden;
    if (hide) return { html: '—', raw: '' };
    if (v === null || v === undefined || v === '') {
      const nc = col.miss ? col.miss(r, d) : col.nc;      // miss(row, answer) may answer '' = "not shown for this reader", or a field name = "data not captured: <field>"
      if (nc) return { html: `<span class="muted">${esc(NC(nc))}</span>`, raw: NC(nc) };
      return { html: '—', raw: '' };
    }
    let t;
    switch (col.f) {
      case 'q4': t = q4(v) + (col.unit && col.unit(r) ? ' ' + unitL(col.unit(r)) : ''); break;
      case 'money': t = money(v); break;
      case 'pct': t = pct(v); break;
      case 'int': t = String(v); break;
      case 'date': t = d10(v); break;
      case 'bool': t = v ? '✓' : '—'; break;
      case 'status': t = block && block.status && block.status[v] ? lab(block.status[v]) : String(v); break;
      default: t = String(v);
    }
    const raw = col.f === 'status' ? String(v) : col.f === 'date' ? d10(v) : col.f === 'bool' ? (v ? 'yes' : 'no') : v;
    return { html: esc(t), raw, text: t };
  }
  function cardHtml(block, bi, r, i, d) {
    const cols = block.cols;
    const titles = cols.filter((c) => c.w === 't').map((c) => cellOf(c, r, d, block).html);
    const chips = cols.filter((c) => c.w === 'c').map((c) => { const cell = cellOf(c, r, d, block); const warn = block.warn && block.warn(r, c); return `<span class="chip ${warn ? 'warn' : ''}">${cell.html}</span>`; });
    const subs = cols.filter((c) => c.w === 's').map((c) => cellOf(c, r, d, block).html);
    const rest = cols.filter((c) => !c.w).map((c) => `<div><span class="muted">${esc(lab(c.l))}</span> <b>${cellOf(c, r, d, block).html}</b></div>`);
    return `<div class="card tap" data-act="${A_}_row" data-b="${bi}" data-i="${i}" style="cursor:pointer"><div class="row between"><b>${titles.join(' · ')}</b>${chips.join(' ')}</div>${subs.length ? `<div class="muted">${subs.join(' · ')}</div>` : ''}${rest.join('')}</div>`;
  }
  function render(tab, d) {
    let h = costNote(d) + truncNote(d) + notesHtml(d.notes) + (tab.top ? tab.top(d, D) : '');
    (tab.blocks || []).forEach((block, bi) => {
      const rows = block.rows(d) || [];
      h += (block.title ? `<h3>${esc(lab(block.title))}</h3>` : '') + (rows.length ? rows.map((r, i) => cardHtml(block, bi, r, i, d)).join('') : B.ui.state('empty', lab(block.empty || X.none)));
    });
    h += (tab.after ? tab.after(d, D) : '') + basisNote(d);
    if (tab.csvKey) h += `<div class="row"><button type="button" data-act="${A_}_csv">${esc(T('csv'))}</button></div>`;
    return h;
  }
  async function run() {
    const tab = cur();
    out(B.ui.state('loading'));
    try {
      if (tab.load) D.data[tab.id] = await tab.load(D);      // a tab may read more than one server function
      else {
        const r = await sb.rpc(tab.rpc, tab.args(D));
        if (r.error) throw r.error;
        D.data[tab.id] = r.data || {};
      }
      out(render(tab, D.data[tab.id]));
    } catch (e) { out(B.ui.state('error', errText(e))); }
  }
  function frame() {
    const tab = cur();
    const tabs = `<div class="row wrap" role="tablist">${cfg.tabs.filter((t) => !t.hidden || t.hidden(D) === false).map((t) => `<button type="button" role="tab" class="btn ${D.tab === t.id ? 'primary' : ''}" data-act="${A_}_tab" data-v="${t.id}">${esc(lab(t.label))}</button>`).join('')}</div>`;
    const f = [];
    if (showFilter(tab, 'date')) f.push(`<div class="row"><div style="flex:1"><label for="${A_}_from">${esc(T('from'))}</label><input id="${A_}_from" type="date" value="${esc(D.from)}"></div><div style="flex:1"><label for="${A_}_to">${esc(T('to'))}</label><input id="${A_}_to" type="date" value="${esc(D.to)}"></div></div>`);
    const f2 = [];
    if (showFilter(tab, 'loc')) f2.push(`<div style="flex:1"><label for="${A_}_loc">${esc(T('place'))}</label>${placeSel(D, A_ + '_loc', D.loc)}</div>`);
    if (showFilter(tab, 'item')) f2.push(`<div style="flex:1">${itemFld(D, A_ + '_item')}</div>`);
    if (f2.length) f.push(`<div class="row">${f2.join('')}</div>`);
    shell(lab(cfg.title), `<div class="stack">${cfg.top ? cfg.top(D) : ''}${tabs}${tab.intro ? tab.intro(D) : ''}${f.join('')}<button class="full" data-act="${A_}_show">${esc(T('show'))}</button><div id="${A_}_out" class="stack">${B.ui.state('loading')}</div></div>`, true);
    const it = $('#' + A_ + '_item'); if (it && D.itemTxt) it.value = D.itemTxt;
    run();
  }
  function readFilters() {
    const g = (s) => { const el = $('#' + A_ + '_' + s); return el ? el.value : undefined; };
    if (g('from') !== undefined) D.from = g('from') || D.from;
    if (g('to') !== undefined) D.to = g('to') || D.to;
    if (g('loc') !== undefined) D.loc = g('loc') || '';
    if (g('status') !== undefined) D.status = g('status') || '';
    if (g('item') !== undefined) { D.itemTxt = g('item') || ''; const it = itemFrom(D, g('item')); D.item = it ? it.id : ''; }
  }
  function csvRows(tab, d) {
    const rows = [[lab(cfg.title) + ' — ' + lab(tab.label), D.from, D.to]];
    (tab.blocks || []).forEach((block) => {
      const list = block.rows(d) || [];
      rows.push([], [block.title ? lab(block.title) : '']);
      rows.push(block.cols.map((c) => lab(c.l)));
      list.forEach((r) => rows.push(block.cols.map((c) => { const cell = cellOf(c, r, d, block); return cell.raw === undefined ? '' : cell.raw; })));
    });
    return rows;
  }
  const api = { D, run, frame, readFilters, cur, csvRows, out, act: A_, cellOf };
  const drill = (bi, i) => {
    const tab = cur(), d = D.data[tab.id] || {}, block = (tab.blocks || [])[bi]; if (!block) return;
    const r = (block.rows(d) || [])[i]; if (!r) return;
    if (block.open) return block.open(r, d);      // a block may open its own sheet instead of the generic detail
    const kv = block.cols.map((c) => `<div class="row between"><span class="muted">${esc(lab(c.l))}</span><b style="text-align:right">${cellOf(c, r, d, block).html}</b></div>`).join('');
    const links = (block.links ? block.links(r, d) : []).map((x) => go(x.hash, lab(x.label))).join(' ');
    openSheet(`<h2>${esc(lab(block.title || tab.label))}</h2><div class="stack">${kv}${block.detail ? block.detail(r, d) : ''}${links ? `<div class="row wrap">${links}</div>` : ''}<button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
  };
  Object.assign(H, {
    [A_ + '_tab']: (a) => { readFilters(); D.tab = a.dataset.v; frame(); },
    [A_ + '_show']: () => { readFilters(); run(); },
    [A_ + '_row']: (a) => drill(Number(a.dataset.b), Number(a.dataset.i)),
    [A_ + '_csv']: async (a) => {
      const tab = cur(), d = D.data[tab.id]; if (!d) return;
      if (a && a.disabled) return; if (a) a.disabled = true;
      try { await exportCSV(tab.csvKey, (tab.csvName || tab.csvKey) + '-' + (D.from || '') + '_' + (D.to || ''), csvRows(tab, d), { from: D.from, to: D.to, loc: D.loc || null, item: D.item || null }); } finally { if (a) a.disabled = false; }
    },
  });
  if (!H.rb4_go) H.rb4_go = (a) => { closeSheet(); location.hash = a.dataset.v; };
  if (cfg.handlers) Object.assign(H, cfg.handlers(D, api));
  async function view() {
    D.ready = false;
    try { await loadBase(D, cfg.base); if (cfg.init) await cfg.init(D, api); } catch (e) { /* the page still draws; a missing helper list is not fatal */ }
    D.from = D.from || (cfg.range === 'month' ? monthStart(today()) : daysAgo(30)); D.to = D.to || today();
    { const h = (location.hash.replace(/^#\/?/, '').split('?')[0].split('/')[1] || ''); if (cfg.tabs.some((t) => t.id === h)) D.tab = h; }      // #/prodreports/yield opens that tab (integration: the stock screen links here)
    D.ready = true; frame();
  }
  window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { [cfg.route]: cfg.view ? () => cfg.view(D, api, view) : view });
  return api;
}

B.rb4 = { L, lab, X, T, NC, NOTE, ERR, errText, norm, nnum, isNum, q4, money, pct, d10, today, daysAgo, monthStart, dhaka, unitL, csvCell, download, exportCSV, tbl, costNote, truncNote, basisNote, notesHtml, go,
  nmOf, locName, itemName, loadBase, itemText, itemFrom, itemFld, placeSel, page };
})();
