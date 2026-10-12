/* Islamia BOS · Reports hub (#/reports) and report viewer (#/report/<key>[/<view id>]).
   One server function (report_run) does the work: the browser only sends filters, a grouping and a sort, and draws what comes back.
   Cost columns exist only when the server returns them. Nothing here is a business number: periods, fiscal year, week start come from the server rules. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS, F = B.filters;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const money = (n) => (n === null || n === undefined ? '—' : '৳ ' + fmt(Math.round(Number(n) * 100) / 100));
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const monthEnd = (iso) => { const d = new Date(iso.slice(0, 8) + '01T12:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0); return d.toISOString().slice(0, 10); };
const noperm = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* rules not loaded */ } return m === 'hide' ? 'hide' : 'lock'; };
const jget = (k, d) => { try { const v = JSON.parse(store.get(k) || 'null'); return v == null ? d : v; } catch (e) { return d; } };

// ---------- labels (3 modes) ----------
const X = {
  title: L('রিপোর্ট', 'Reports', 'Report'), search: L('রিপোর্ট খুঁজুন…', 'Search reports…', 'Report খুঁজুন…'), all: L('সব', 'All', 'All'),
  g_sales: L('বিক্রি', 'Sales', 'Sales (বিক্রি)'), g_pos: L('POS ও ক্যাশিয়ার', 'POS & cashier', 'POS ও Cashier'), g_cash: L('ক্যাশ ও পেমেন্ট', 'Cash & payments', 'Cash ও Payment'),
  g_customers: L('গ্রাহক ও বাকি', 'Customers & dues', 'Customer ও বাকি'),
  g_stock: L('স্টক ও অপচয়', 'Stock & wastage', 'Stock ও অপচয়'), g_purchase: L('ক্রয় ও সরবরাহকারী', 'Purchases & suppliers', 'Purchase ও Supplier'), g_expense: L('খরচ', 'Expenses', 'খরচ'),
  g_staff: L('কর্মীর হাজিরা', 'Staff attendance', 'Staff হাজিরা'), g_control: L('ব্যতিক্রম', 'Exceptions', 'Exception'),
  views: L('আমার ভিউ', 'My views', 'My Views'), views_s: L('সংরক্ষিত ভিউ', 'Saved views', 'Saved Views'), noviews: L('এখনও কোনো ভিউ সংরক্ষণ করা হয়নি', 'No saved views yet', 'এখনও কোনো View save করা হয়নি'),
  shared: L('শেয়ার করা', 'Shared', 'Shared'), mine: L('আমার', 'Mine', 'Mine'),
  pages_s: L('আলাদা পাতা', 'Other pages', 'আলাদা Page'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), nores: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'),
  engine: L('রিপোর্ট ইঞ্জিন এখনও চালু হয়নি — ডেটাবেসে phase9.sql চালাতে হবে', 'The report engine is not installed yet — phase9.sql must be run on the database', 'Report engine চালু হয়নি — database-এ phase9.sql চালাতে হবে'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), notfound: L('এই রিপোর্ট পাওয়া যায়নি', 'This report was not found', 'এই Report পাওয়া যায়নি'),
  filter: L('ফিল্টার', 'Filter', 'Filter'), colsb: L('কলাম', 'Columns', 'Columns'), viewsb: L('ভিউ', 'Views', 'Views'),
  group: L('ভাগ করুন', 'Group by', 'Group by'), then: L('তারপর', 'Then by', 'Then by'), sort: L('সাজান', 'Sort', 'Sort'),
  dflt: L('ডিফল্ট', 'Default', 'Default'), total: L('মোট', 'Total', 'Total (মোট)'), brand: L('ব্র্যান্ড', 'Brand', 'Brand'), loc: L('লোকেশন', 'Location', 'Location'), none: L('— নেই —', '— none —', '— নেই —'),
  asc: L('↑ ছোট থেকে বড়', '↑ low to high', '↑ ছোট→বড়'), desc: L('↓ বড় থেকে ছোট', '↓ high to low', '↓ বড়→ছোট'),
  compare: L('আগের সাথে তুলনা', 'Compare', 'Compare (তুলনা)'), c_prev: L('আগের সময়', 'Previous period', 'Previous period'), c_week: L('গত সপ্তাহ', 'Last week', 'Last week'), c_year: L('গত বছর', 'Last year', 'Last year'),
  vs: L('তুলনা', 'vs', 'vs'), new_: L('নতুন', 'new', 'new'),
  more: L('আরও দেখান', 'Show more', 'আরও দেখান'), of: L('/', 'of', '/'), rows: L('সারি', 'rows', 'rows'),
  totalrow: L('মোট', 'Total', 'Total'), back: L('আগের অবস্থায় ফিরুন', 'Back to previous view', 'আগের View-তে ফিরুন'),
  period: L('সময়', 'Period', 'Period'), drillhint: L('সারিতে চাপলে সেই অংশের ফিল্টার বসে', 'Tap a row to filter to it', 'Row-তে চাপলে সেই অংশের Filter বসে'),
  nodrill: L('এই সারিতে আর গভীরে যাওয়া যায় না', 'No deeper view for this row', 'এই row-তে আর deeper view নেই'),
  empty: L('তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই', 'Data needed: nothing matches this period / filters', 'Data দরকার: এই সময়/ফিল্টারে কিছু নেই'),
  need: L('তথ্য দরকার', 'Data needed', 'Data দরকার'),
  save: L('ভিউ সংরক্ষণ', 'Save this view', 'Save this View'), name: L('ভিউয়ের নাম', 'View name', 'View-এর নাম'), share: L('সবার সাথে শেয়ার করুন', 'Share with everyone', 'সবার সাথে Share করুন'),
  saved: L('ভিউ সংরক্ষিত', 'View saved', 'View saved'), loaded: L('ভিউ খোলা হয়েছে', 'View loaded', 'View খোলা হয়েছে'), del: L('মুছুন', 'Delete', 'Delete'), delq: L('এই ভিউ মুছবেন?', 'Delete this view?', 'এই View মুছবেন?'),
  needname: L('ভিউয়ের নাম লিখুন', 'Enter a view name', 'View-এর নাম লিখুন'), deleted: L('মুছে ফেলা হয়েছে', 'Deleted', 'Deleted'), open: L('খুলুন', 'Open', 'Open'),
  csv: L('CSV', 'CSV', 'CSV'), print: L('প্রিন্ট / PDF', 'Print / PDF', 'Print / PDF'), exp_lock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export-এর permission নেই'),
  exp_busy: L('তৈরি হচ্ছে…', 'Preparing…', 'তৈরি হচ্ছে…'), exp_done: L('ফাইল তৈরি', 'File ready', 'File তৈরি'),
  cols_t: L('কলাম দেখান / লুকান', 'Show / hide columns', 'Column দেখান / লুকান'), done: L('হয়েছে', 'Done', 'Done'), close: L('বন্ধ', 'Close', 'Close'),
  cost_on: L('খরচের কলাম: দেখানো হয়েছে', 'Cost columns: shown', 'Cost columns: shown'), cost_off: L('খরচের কলাম: লুকানো', 'Cost columns: hidden', 'Cost columns: hidden'),
  by: L('যিনি বের করেছেন', 'Exported by', 'Exported by'), at: L('সময়', 'At', 'At'), flt: L('ফিল্টার', 'Filters', 'Filters'),
  n_cost_hidden: L('আপনার ভূমিকার জন্য খরচ ও লাভের কলাম বন্ধ', 'Cost and profit columns are hidden for your role', 'Cost ও profit column আপনার role-এর জন্য বন্ধ'),
  n_mobile: L('গ্রাহকের মোবাইল নম্বর ঢাকা', 'Customer mobile numbers are masked', 'Customer mobile number ঢাকা'),
  n_scope: L('শুধু আপনার লোকেশনের হিসাব', 'Only your locations are included', 'শুধু আপনার Location-এর হিসাব'),
  n_cmp: L('এই রিপোর্টে তুলনা চলে না', 'Compare is not available for this report', 'এই Report-এ Compare চলে না'),
  n_ign: L('এই রিপোর্টে প্রযোজ্য নয়', 'Not applicable to this report', 'এই Report-এ প্রযোজ্য নয়'),
  n_trunc: L('অনেক সারি: ফিল্টার ছোট করুন', 'Too many rows: narrow the filters', 'অনেক row: Filter ছোট করুন'),
  n_week: L('সপ্তাহ শুরুর নিয়ম নেই: সোমবার ধরা হয়েছে', 'Week-start rule not set: weeks start on Monday', 'Week শুরুর rule নেই: সোমবার ধরা হয়েছে'),
  n_def: L('সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত', 'No period given: this month to date', 'Period দেওয়া হয়নি: এই মাসের আজ পর্যন্ত'),
  e_range: L('সময়ের পরিসর খুব বড় — ছোট করুন', 'The date range is too long — shorten it', 'Date range খুব বড় — ছোট করুন'),
  e_filter: L('ফিল্টারের মান ঠিক নেই', 'A filter value is not valid', 'Filter-এর value ঠিক নেই'),
  e_slow: L('অনেক তথ্য — ফিল্টার ছোট করে আবার চেষ্টা করুন', 'Too much data — narrow the filters and retry', 'অনেক data — Filter ছোট করে আবার চেষ্টা করুন'),
  e_off: L('ইন্টারনেট নেই — রিপোর্ট দেখতে অনলাইন লাগবে', 'You are offline — reports need a connection', 'Internet নেই — Report দেখতে online লাগবে'),
  retry: L('আবার চেষ্টা', 'Retry', 'Retry'),
};
const T = (k) => lab(X[k]);
const dimLabel = (d) => lab({ bn: d.label_bn, en: d.label_en || d.label_bn, mix: d.label_bn });
const repName = (r) => lab({ bn: r.name_bn, en: r.name_en || r.name_bn, mix: r.name_mix || r.name_bn });
const colLabel = (c) => lab({ bn: c.label_bn, en: c.label_en || c.label_bn, mix: c.label_bn });
const LOCK = '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';
const FUNNEL = '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h24L19 18v8l-6 2V18z"/></svg>';

// ---------- data access ----------
let CAT = null, catAt = 0;
async function getCatalog(force) {
  if (CAT && !force && Date.now() - catAt < 60000) return CAT;
  const r = await sb.rpc('report_catalog');
  if (r.error || !Array.isArray(r.data)) { CAT = null; const e = new Error('engine'); e.engine = true; e.cause = r.error; throw e; }
  CAT = r.data;
  // the second engine (phase21): 12 more reports; absent or failing -> the first engine's list alone
  try { if (B.reports2) { const more = await B.reports2.catalog(); if (more.length) CAT = CAT.concat(more); } } catch (e) { /* first engine only */ }
  catAt = Date.now(); return CAT;
}
async function getViews(key) {
  let q = sb.from('report_views').select('*'); if (key) q = q.eq('report_code', key);
  const r = await q.order('updated_at', { ascending: false });
  return r.error ? [] : (r.data || []);
}
const canDelView = (v) => !!(S.ctx.is_owner || !v.owner_id || v.owner_id === uid());
let EXP = null;     // may this person export? owner always; others need grant export_data (has_grant); unknown function = owner only
async function canExport() {
  if (S.ctx.is_owner) return true; if (EXP !== null) return EXP;
  try { const r = await sb.rpc('has_grant', { p_code: 'export_data' }); EXP = !r.error && r.data === true; } catch (e) { EXP = false; }
  return EXP;
}

// ---------- hub ----------
const HB = { g: '', q: '' };
async function viewHub() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* rules fall back */ }
  let cat, views;
  try { [cat, views] = await Promise.all([getCatalog(true), getViews()]); } catch (e) {
    if (e.engine) return shell(T('title'), `<div class="notice warn mk warn">${esc(T('engine'))}</div>`, true);
    return fail(e);
  }
  try { await Promise.all((B.reportLinks || []).map((l) => (l.check ? l.check() : null))); } catch (e) { /* links stay unchecked */ }
  HB.cat = cat; HB.views = views; drawHub();
}
function groupsOf(cat) { const g = []; cat.forEach((r) => { if (!g.includes(r.group)) g.push(r.group); }); return g; }
const groupName = (g) => (X['g_' + g] ? T('g_' + g) : g);
function drawHub() {
  const cat = HB.cat || [];
  shell(T('title'), `<input id="rp_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}" value="${esc(HB.q)}">
    <div class="ptabs" role="tablist" id="rp_gp">${['', ...groupsOf(cat)].map((g) => `<button role="tab" data-act="rp_grp" data-v="${esc(g)}" aria-selected="${HB.g === g}">${esc(g ? groupName(g) : T('all'))}</button>`).join('')}</div>
    <div id="rp_views"></div><div id="rp_list"></div>`, true);
  drawHubViews(); drawHubList();
}
function drawHubViews() {
  const box = $('#rp_views'); if (!box) return;
  const cat = HB.cat || [], q = HB.q.trim().toLowerCase();
  const list = (HB.views || []).filter((v) => cat.some((r) => r.key === v.report_code) && (!HB.g || (cat.find((r) => r.key === v.report_code) || {}).group === HB.g)
    && (!q || (v.name || '').toLowerCase().includes(q))).slice(0, 8);
  if (!list.length) { box.innerHTML = ''; return; }
  box.innerHTML = `<div class="hsec">${esc(T('views_s'))}<small>${list.length}</small></div><div class="card" style="padding:4px 12px">${list.map((v) => {
    const r = cat.find((x) => x.key === v.report_code), mine = canDelView(v);
    return `<button class="rp-row mk ${mine ? '' : 'info'}" data-act="rp_view_open" data-k="${esc(v.report_code)}" data-v="${esc(String(v.id))}"><span class="nm">${esc(v.name)}<small>${esc(repName(r))}</small></span>
      ${v.shared ? `<span class="chip info">${esc(T('shared'))}</span>` : ''}<span class="cv">›</span></button>`; }).join('')}</div>`;
}
function drawHubList() {
  const box = $('#rp_list'); if (!box) return;
  const cat = HB.cat || [], q = HB.q.trim().toLowerCase(), mode = noperm();
  const hit = cat.filter((r) => (!HB.g || r.group === HB.g) && (!q || [r.name_bn, r.name_en, r.name_mix, r.key].some((s) => (s || '').toLowerCase().includes(q))));
  let h = '';
  groupsOf(hit).forEach((g) => {
    const rows = hit.filter((r) => r.group === g), vis = rows.filter((r) => r.allowed || mode === 'lock');
    if (!vis.length) return;
    h += `<div class="hsec">${esc(groupName(g))}</div><div class="card" style="padding:4px 12px">${vis.map((r) => r.allowed
      ? `<button class="rp-row" data-act="rp_open" data-v="${esc(r.key)}"><span class="nm">${esc(repName(r))}</span><span class="cv">›</span></button>`
      : `<div class="rp-row lock" aria-disabled="true">${LOCK}<span class="nm">${esc(repName(r))}</span><span class="chip">${esc(T('noperm'))}</span></div>`).join('')}</div>`;
  });
  const lk = (B.reportLinks || []).filter((l) => !q || String(l.label()).toLowerCase().includes(q)).filter((l) => !HB.g || false);
  const lkv = (HB.g ? [] : lk).filter((l) => l.allowed || mode === 'lock');
  if (lkv.length) h += `<div class="hsec">${esc(T('pages_s'))}</div><div class="card" style="padding:4px 12px">${lkv.map((l) => (l.allowed
    ? `<button class="rp-row" data-act="go" data-v="${esc(l.route)}"><span class="nm">${esc(l.label())}</span><span class="cv">›</span></button>`
    : `<div class="rp-row lock" aria-disabled="true">${LOCK}<span class="nm">${esc(l.label())}</span><span class="chip">${esc(T('noperm'))}</span></div>`)).join('')}</div>`;
  box.innerHTML = h || `<p class="muted center pad">${esc(T('nores'))}</p>`;
}

// ---------- viewer state ----------
const V = { key: null, def: null, f: {}, group: null, group2: null, sort: null, hidden: new Set(), compare: null, page: 1, rows: [], res: null, tok: 0, stack: [], err: null, loading: false, exp: false, viewName: null };
const cfgOf = () => ({ f: V.f, group: V.group, group2: V.group2, sort: V.sort, hidden: [...V.hidden], compare: V.compare });
const persist = () => { try { store.set('bos_rp_' + uid() + '_' + V.key, JSON.stringify(cfgOf())); } catch (e) { /* ignore */ } };
function applyCfg(c) {
  const d = V.def, needsDate = d.needs_date !== false;
  V.f = c && c.f && typeof c.f === 'object' ? c.f : F.defaults(needsDate);
  if (needsDate && !V.f.preset && !V.f.from && !V.f.to) V.f.preset = F.DEFAULT_PRESET;
  { const cl = !(c && c.f) && B.curLoc ? B.curLoc() : null; if (cl !== null && (d.filters || []).includes('locations')) V.f.locations = [cl]; }      // a fresh report opens on the place chosen in the drawer
  const okDim = (g) => g === 'total' || (d.dims || []).some((x) => x.key === g);
  V.group = c && c.group && okDim(c.group) ? c.group : null; V.group2 = c && c.group2 && okDim(c.group2) && c.group2 !== 'total' ? c.group2 : null;
  V.sort = c && c.sort ? c.sort : null; V.hidden = new Set((c && c.hidden) || []);
  V.compare = c && d.compare && ['prev', 'week', 'year'].includes(c.compare) ? c.compare : null;
  V.page = 1; V.rows = []; V.res = null; V.stack = [];
}
async function viewReport() {
  const parts = location.hash.replace(/^#\/?/, '').split('?')[0].split('/'), key = decodeURIComponent(parts[1] || ''), vid = parts[2] || null;
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'reports');
  try { await B.loadStatic(); } catch (e) { /* rules fall back */ }
  let cat; try { cat = await getCatalog(); } catch (e) { if (e.engine) return shell(T('title'), `<div class="notice warn mk warn">${esc(T('engine'))}</div>`, 'reports'); return fail(e); }
  const def = cat.find((r) => r.key === key);
  if (!def) return shell(T('title'), `<div class="notice bad mk bad">${esc(T('notfound'))}</div>`, 'reports');
  if (!def.allowed) return shell(repName(def), `<div class="notice warn mk warn">${LOCK.replace('<svg', '<svg width="18" height="18"')} ${esc(T('noperm'))}</div>`, 'reports');
  const fresh = V.key !== key || !!vid;
  V.def = def;
  if (fresh) {
    V.key = key; V.viewName = null; V.id = null;
    let cfg = null;
    if (vid) { const r = await sb.from('report_views').select('*').eq('id', vid).maybeSingle(); if (r.data && r.data.report_code === key) { cfg = r.data.params; V.viewName = r.data.name; } }
    else cfg = jget('bos_rp_' + uid() + '_' + key, null);
    applyCfg(cfg);
  }
  V.exp = await canExport();
  await F.preload(def.filters);
  F.bind('rp', { get: () => V.f, set: (s) => { V.f = s; V.stack = []; V.page = 1; persist(); drawTop(); run(false); }, allow: def.filters, needsDate: def.needs_date !== false });
  drawPage();
  if (!V.res || fresh) run(false); else drawRes();
}
function drawPage() {
  shell(repName(V.def), `<div id="rp_top"></div><div id="rp_res"></div>`, 'reports');
  drawTop(); drawRes();
}

// ---------- controls ----------
const effGroup = () => { const g = V.group === null ? (V.def.default_group || '') : V.group; return !g || g === 'total' || g === 'none' ? [] : g.split(',').filter(Boolean); };
const groupParam = () => (V.group === null ? null : V.group === 'total' ? 'total' : V.group + (V.group2 ? ',' + V.group2 : ''));
function drawTop() {
  const box = $('#rp_top'); if (!box) return; const d = V.def, isAgg = d.kind === 'agg' || (d.engine === 2 && (d.dims || []).length > 0), dims = d.dims || [];
  const n = F.activeCount(V.f, d.filters, d.needs_date !== false), eg = effGroup();
  const hasBrand = dims.some((x) => x.key === 'brand'), hasLoc = dims.some((x) => x.key === 'location');
  const optDim = (x, sel, skip) => (x.key === skip ? '' : `<option value="${esc(x.key)}" ${sel === x.key ? 'selected' : ''} ${x.needs_rule === 'fy' && !(F.presetRange('this_fy')) ? 'disabled' : ''}>${esc(dimLabel(x))}${x.needs_rule === 'fy' && !F.presetRange('this_fy') ? ' · ' + esc(T('need')) : ''}</option>`);
  const cols = visCols(V.res ? V.res.columns : []);
  const sortOpts = cols.map((c) => `<option value="${esc(c.key)}" ${V.sort === c.key ? 'selected' : ''}>${esc(colLabel(c))} ${esc(T('asc'))}</option><option value="-${esc(c.key)}" ${V.sort === '-' + c.key ? 'selected' : ''}>${esc(colLabel(c))} ${esc(T('desc'))}</option>`).join('');
  box.innerHTML = `<div class="rp-bar"><button class="primary" data-act="rp_filter">${FUNNEL}<span>${esc(T('filter'))}</span>${n ? `<b class="rp-n">${n}</b>` : ''}</button>
      <button data-act="rp_views">${esc(T('viewsb'))}</button><button data-act="rp_cols">${esc(T('colsb'))}</button></div>
    <div id="rp_chips">${F.chips('rp')}</div>
    ${V.viewName ? `<div class="rp-meta"><span class="chip info">${esc(T('views'))}</span> <b>${esc(V.viewName)}</b></div>` : ''}
    <div class="rp-meta" id="rp_meta"></div>
    ${V.stack.length ? `<button class="rp-back" data-act="rp_back">↩ ${esc(T('back'))}</button>` : ''}
    ${isAgg && (hasBrand || hasLoc) ? `<div class="seg rp-seg" role="group" aria-label="${esc(T('group'))}"><button data-act="rp_sw" data-v="total" aria-pressed="${eg.length === 0}">${esc(T('total'))}</button>
      ${hasBrand ? `<button data-act="rp_sw" data-v="brand" aria-pressed="${eg.length === 1 && eg[0] === 'brand'}">${esc(T('brand'))}</button>` : ''}
      ${hasLoc ? `<button data-act="rp_sw" data-v="location" aria-pressed="${eg.length === 1 && eg[0] === 'location'}">${esc(T('loc'))}</button>` : ''}</div>` : ''}
    <div class="rp-sel">${isAgg ? `<div><label for="rp_g1">${esc(T('group'))}</label><select id="rp_g1"><option value="" ${V.group === null ? 'selected' : ''}>${esc(T('dflt'))}</option><option value="total" ${V.group === 'total' ? 'selected' : ''}>${esc(T('total'))}</option>${dims.map((x) => optDim(x, V.group)).join('')}</select></div>` : ''}
      <div><label for="rp_s1">${esc(T('sort'))}</label><select id="rp_s1"><option value="">${esc(T('dflt'))}</option>${sortOpts}</select></div>
      ${isAgg && d.kind === 'agg' && eg.length === 1 && V.group !== 'total' ? `<div><label for="rp_g2">${esc(T('then'))}</label><select id="rp_g2"><option value="">${esc(T('none'))}</option>${dims.map((x) => optDim(x, V.group2, eg[0])).join('')}</select></div>` : ''}</div>
    ${isAgg && d.compare ? `<div class="rp-cmp"><button class="tog ${V.compare ? 'on' : ''}" data-act="rp_cmp" aria-pressed="${!!V.compare}">${esc(T('compare'))}</button>
      ${V.compare ? `<div class="seg rp-seg" role="group">${['prev', 'week', 'year'].map((m) => `<button data-act="rp_cm" data-v="${m}" aria-pressed="${V.compare === m}">${esc(T('c_' + m))}</button>`).join('')}</div>` : ''}</div>` : ''}`;
  drawMeta();
}
function drawMeta() {
  const m = $('#rp_meta'); if (!m) return; const mt = V.res && V.res.meta;
  m.innerHTML = mt && mt.from ? `${esc(T('period'))}: <b>${esc(F.shortDate(mt.from))}${mt.to && mt.to !== mt.from ? ' – ' + esc(F.shortDate(mt.to)) : ''}</b>${V.res.compare ? ` · ${esc(T('vs'))} <b>${esc(F.shortDate(V.res.compare.from))}${V.res.compare.to !== V.res.compare.from ? ' – ' + esc(F.shortDate(V.res.compare.to)) : ''}</b>` : ''}` : '';
}

// ---------- fetch ----------
function errText(e) {
  const m = (e && e.message) || '';
  if (navigator.onLine === false) return T('e_off');
  if (/not allowed/.test(m)) return T('noperm'); if (/bad_range/.test(m)) return T('e_range'); if (/bad_filter/.test(m)) return T('e_filter');
  if (/timeout|57014/i.test(m + (e && e.code))) return T('e_slow'); return null;
}
function callRun(page) {
  const flt = F.clean(V.f); if (V.compare) flt.compare_mode = V.compare;
  if (V.def && V.def.engine === 2 && B.reports2) return B.reports2.run(V.key, flt, groupParam(), V.sort || null, page);
  return sb.rpc('report_run', { p_key: V.key, p_filters: flt, p_group: groupParam(), p_sort: V.sort || null, p_page: page, p_compare: !!V.compare });
}
async function run(append) {
  const tok = ++V.tok; V.loading = true; V.err = null;
  if (!append) { V.page = 1; V.res = null; V.rows = []; } else V.page += 1;
  drawRes();
  let r; try { r = await callRun(V.page); } catch (e) { r = { error: e }; }
  if (tok !== V.tok) return; V.loading = false;
  if (r.error || !r.data) { V.err = r.error || { message: 'empty' }; if (append) V.page -= 1; const tx = errText(V.err); if (!tx) fail(V.err); drawRes(tx); return; }
  const res = r.data;
  V.rows = append ? V.rows.concat(res.rows || []) : (res.rows || []);
  if (append && V.res) { res.compare = V.res.compare; res.totals = res.totals || V.res.totals; }
  V.res = res;
  if (V.sort && !(res.columns || []).some((c) => c.key === V.sort.replace(/^-/, ''))) V.sort = null;
  drawTop(); drawRes();
}

// ---------- result drawing ----------
function visCols(cols) {
  const en = new Set(), out = [];
  (cols || []).forEach((c) => { if (/_en$/.test(c.key) && /\(EN\)/.test(c.label_en || '')) { const b = c.key.slice(0, -3); const base = cols.find((x) => x.key === b || x.key === b + '_bn'); if (base) { en.add(c.key); base.en = c.key; } } });
  (cols || []).forEach((c) => { if (c.type !== 'id' && !en.has(c.key)) out.push(c); });
  return out;
}
const shownCols = () => { const all = visCols(V.res ? V.res.columns : []); const v = all.filter((c, i) => i === 0 || !V.hidden.has(c.key)); return v.length ? v : all; };
const RAW_INT = new Set(['fiscal_year', 'hour', 'dow', 'receipt']);
function fmtVal(c, row, money_ = false) {
  let v = row[c.key];
  if (c.en && S.lang === 'en' && row[c.en] !== null && row[c.en] !== undefined && row[c.en] !== '') v = row[c.en];
  if (v === null || v === undefined || v === '') return '—';
  switch (c.type) {
    case 'money': return money_ ? money(v) : fmt(Math.round(Number(v) * 100) / 100);
    case 'pct': return Number(v).toFixed(1) + '%';
    case 'int': return RAW_INT.has(c.key) || c.role === 'dim' ? String(v) : fmt(v);
    case 'num': return fmt(v);
    case 'date': return String(v);
    default: return String(v);
  }
}
const BADUP = /void|disc|due|missing|dup|over_limit|no_limit|override|uncosted|short/i;
function deltaHTML(key, cur, prev) {
  if (cur === null || cur === undefined || prev === undefined) return '';
  const c = Number(cur), p = Number(prev);
  if (!Number.isFinite(c) || !Number.isFinite(p)) return '';
  if (p === 0) return c === 0 ? '' : `<small class="dl neu">${esc(T('new_'))}</small>`;
  const pc = Math.round((1000 * (c - p)) / Math.abs(p)) / 10; if (pc === 0) return `<small class="dl neu">0%</small>`;
  const up = pc > 0, bad = BADUP.test(key) ? up : !up;
  return `<small class="dl ${bad ? 'warn' : 'ok'}">${up ? '▲' : '▼'} ${Math.abs(pc)}%</small>`;
}
const sigOf = (cols, row) => cols.filter((c) => c.role === 'dim').map((c) => row[c.key]).join('|');
function noteText(n) {
  const c = n.code, pick = () => lab({ bn: n.text_bn || n.text_en, en: n.text_en || n.text_bn, mix: n.text_bn || n.text_en });
  const map = { cost_hidden: 'n_cost_hidden', mobile_masked: 'n_mobile', location_scope: 'n_scope', compare_unavailable: 'n_cmp', truncated: 'n_trunc', week_default: 'n_week', default_period: 'n_def' };
  if (map[c]) return T(map[c]);
  if (c === 'filter_ignored' || c === 'group_ignored' || c === 'sort_ignored' || c === 'compare_mode_ignored') return `${T('n_ign')}${n.what ? ': ' + (Array.isArray(n.what) ? n.what.join(', ') : n.what) : ''}`;
  if (c === 'data_needed') return `${T('need')}: ${n.what || ''} — ${pick() || ''}`;
  return pick() || c || '';
}
function drawRes(errTxt) {
  const box = $('#rp_res'); if (!box) return;
  if (V.err) { box.innerHTML = `<div class="notice bad mk bad">${esc(errTxt || T('e_slow'))}</div><button class="full" data-act="rp_retry">${esc(T('retry'))}</button>`; return; }
  if (V.loading && !V.res) { box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`; return; }
  const res = V.res; if (!res) { box.innerHTML = ''; return; }
  const cols = shownCols(), all = res.columns || [], cmp = res.compare, d = V.def;
  const notes = (res.notes || []).filter((n) => n.code !== 'no_data');
  const noteH = notes.map((n) => `<div class="rp-note mk ${/^(data_needed|truncated)$/.test(n.code) ? 'warn' : 'info'}">${esc(noteText(n))}</div>`).join('');
  const empty = res.data_needed && !(V.rows || []).length;
  const tot = res.totals || null;
  // summary strip: first four money / count measures
  const meas = cols.filter((c) => c.role === 'measure' && (c.type === 'money' || c.type === 'int' || c.type === 'num') && tot && tot[c.key] !== undefined && tot[c.key] !== null).slice(0, 4);
  const stats = meas.length && !empty ? `<div class="stats rp-stats">${meas.map((c, i) => {
    const dl = cmp && cmp.delta && cmp.delta[c.key]; const val = c.type === 'money' ? money(tot[c.key]) : fmt(tot[c.key]);
    const warn = BADUP.test(c.key) && Number(tot[c.key]) > 0;
    return `<div class="stat ${warn ? 'mk warn' : ''} ${i === 0 && meas.length % 2 ? 'wide' : ''}"><div class="k">${esc(colLabel(c))}</div><div class="v">${esc(val)}</div>
      ${dl ? `<div class="s">${deltaHTML(c.key, dl.current, dl.previous)} <span>${esc(T('vs'))} ${esc(c.type === 'money' ? money(dl.previous) : fmt(dl.previous))}</span></div>` : ''}</div>`; }).join('')}</div>` : '';
  let tbl = '';
  if (!empty && cols.length) {
    const pmap = new Map(); if (cmp && cmp.rows) cmp.rows.forEach((r) => pmap.set(sigOf(all, r), r));
    const drillable = d.kind === 'agg' && effGroup().length > 0;
    const sk = (res.meta && res.meta.sort) || null, sd = (res.meta && res.meta.dir) || 'asc';
    tbl = `<div class="scrollx rp-tw"><table class="rp-t" id="rp_tbl"><thead><tr>${cols.map((c) => `<th class="${c.role === 'measure' || ['money', 'int', 'num', 'pct'].includes(c.type) && c.role !== 'dim' ? 'n' : ''}"><button class="rp-th" data-act="rp_sortcol" data-k="${esc(c.key)}" aria-label="${esc(T('sort') + ': ' + colLabel(c))}">${esc(colLabel(c))}${sk === c.key ? `<i>${sd === 'desc' ? '↓' : '↑'}</i>` : ''}</button></th>`).join('')}</tr></thead>
      <tbody>${(V.rows || []).map((row, i) => {
        const pr = cmp ? pmap.get(sigOf(all, row)) : null;
        return `<tr ${drillable ? `class="tap" data-act="rp_drill" data-i="${i}"` : ''}>${cols.map((c, ci) => {
          const num = c.role !== 'dim' && ['money', 'int', 'num', 'pct'].includes(c.type);
          const dl = cmp && c.role === 'measure' && (c.type === 'money' || c.type === 'int' || c.type === 'num') ? deltaHTML(c.key, row[c.key], pr ? pr[c.key] : 0) : '';
          return `<${ci === 0 ? 'th scope="row"' : 'td'} class="${num ? 'n' : ''}">${esc(fmtVal(c, row))}${dl}</${ci === 0 ? 'th' : 'td'}>`; }).join('')}</tr>`; }).join('')}</tbody>
      ${tot ? `<tfoot><tr>${cols.map((c, ci) => `<${ci === 0 ? 'th' : 'td'} class="${ci && c.role !== 'dim' ? 'n' : ''}">${ci === 0 ? esc(T('totalrow')) : tot[c.key] !== undefined && tot[c.key] !== null ? esc(fmtVal(c, tot)) : ''}</${ci === 0 ? 'th' : 'td'}>`).join('')}</tr></tfoot>` : ''}</table></div>
      ${drillable ? `<div class="muted rp-hint">${esc(T('drillhint'))}</div>` : ''}`;
  }
  const pg = res.page || {}, shown = (V.rows || []).length;
  const more = res.has_more ? `<button class="full" data-act="rp_more" ${V.loading ? 'disabled' : ''}>${esc(T('more'))} · ${shown} ${esc(T('of'))} ${esc(String(Math.min(pg.groups || shown, pg.cap || 500)))}</button>` : '';
  const exp = (ok, act, label) => (ok ? `<button data-act="${act}">${esc(label)}</button>` : noperm() === 'lock' ? `<button disabled aria-label="${esc(label + ' · ' + T('exp_lock'))}">${LOCK.replace('<svg', '<svg width="16" height="16"')} ${esc(label)}</button>` : '');
  box.innerHTML = `${noteH}${stats}${empty ? `<div class="notice warn mk warn">${esc(T('empty'))}</div>` : ''}${tbl}${more}
    ${!empty ? `<div class="rp-foot">${exp(V.exp, 'rp_csv', T('csv'))}${exp(V.exp, 'rp_print', T('print'))}</div>` : ''}`;
}

// ---------- drill-down ----------
function drillPatch(row) {
  const d = V.def, allow = new Set(d.filters || []), f = {}, used = [], names = {};
  const set = (k, v) => { if (allow.has(k)) f[k] = v; };
  effGroup().concat(V.group2 && V.group !== 'total' && V.group !== null && !effGroup().includes(V.group2) ? [V.group2] : []).forEach((g) => {
    const v = (k) => row[k];
    if (g === 'location' && v('location_id') != null) { set('locations', [Number(v('location_id'))]); used.push(g); }
    else if (g === 'brand' && v('brand_code') && v('brand_code') !== 'none') { set('brands', [v('brand_code')]); used.push(g); }
    else if (g === 'staff' && v('staff') && v('staff') !== '-') { set('staff', [v('staff')]); used.push(g); }
    else if ((g === 'pay_mode' || g === 'mode') && v(g)) { set('modes', [v(g)]); used.push(g); }
    else if (g === 'sale_type' && v('sale_type')) { set('sale_type', v('sale_type')); used.push(g); }
    else if (g === 'item' && v('item_id') && v('item_id') !== 'none') { set('items', [v('item_id')]); names.items = { [v('item_id')]: v('item_name') || v('item_code') }; used.push(g); }
    else if (g === 'category' && v('category') && v('category') !== '(none)') { set('categories', [v('category')]); used.push(g); }
    else if (g === 'customer' && v('customer_id') && v('customer_id') !== 'none') { set('customer', [v('customer_id')]); names.customer = { [v('customer_id')]: v('customer_name') }; used.push(g); }
    else if (g === 'day' && v('day')) { f.from = f.to = v('day'); used.push(g); }
    else if (g === 'week' && v('week')) { f.from = v('week'); f.to = addDays(v('week'), 6); used.push(g); }
    else if (g === 'month' && v('month')) { f.from = v('month'); f.to = monthEnd(v('month')); used.push(g); }
  });
  return { f, used, names };
}
function drill(i) {
  const row = V.rows[i]; if (!row) return;
  const { f, used, names } = drillPatch(row);
  if (!used.length || !Object.keys(f).length) return toast(T('nodrill'));
  V.stack.push({ f: JSON.parse(JSON.stringify(V.f)), group: V.group, group2: V.group2, sort: V.sort });
  const nf = JSON.parse(JSON.stringify(V.f));
  Object.keys(f).forEach((k) => { nf[k] = f[k]; });
  if (f.from) delete nf.preset;
  nf._n = nf._n || {}; Object.keys(names).forEach((k) => { nf._n[k] = Object.assign(nf._n[k] || {}, names[k]); });
  V.f = nf;
  const dims = V.def.dims || [], usedSet = new Set(used);
  const next = dims.find((x) => !x.time && !usedSet.has(x.key) && x.key !== 'fy');
  if (next) { V.group = next.key; V.group2 = null; }
  V.sort = null; persist(); drawTop(); run(false);
}

// ---------- export ----------
async function fetchAll() {
  let rows = V.rows.slice(), page = V.page, more = V.res && V.res.has_more, last = V.res;
  while (more && page < 80) { page += 1; const r = await callRun(page); if (r.error || !r.data) throw r.error || new Error('page'); rows = rows.concat(r.data.rows || []); more = r.data.has_more; last = r.data; }
  return { rows, res: V.res || last };
}
const csvCell = (c, v) => {
  if (v === null || v === undefined) return '';
  let s = (c.type === 'money' || c.type === 'int' || c.type === 'num' || c.type === 'pct') && !RAW_INT.has(c.key) && c.role !== 'dim' ? String(Number(v)) : String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && c.type === 'text' && /[^\d.\-]/.test(s) && s.length > 1)) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
const expMeta = (res) => {
  const mt = res.meta || {}, nowS = new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', dateStyle: 'medium', timeStyle: 'short' });
  const p = S.ctx.profile || {};
  return [[repName(V.def)], [T('period'), `${mt.from || ''}${mt.to && mt.to !== mt.from ? ' – ' + mt.to : ''}`], [T('flt'), F.summary(V.f, V.def.filters, V.def.needs_date !== false) || '—'],
    [mt.cost_shown ? T('cost_on') : T('cost_off')], [T('by'), p.full_name || p.staff_id || ''], [T('at'), nowS + ' (Asia/Dhaka)']];
};
function buildCSV(rows, res) {
  const cols = shownCols(), tot = res.totals;
  const out = [cols.map((c) => csvCell({ type: 'text', key: '_' }, colLabel(c))).join(',')];
  rows.forEach((r) => out.push(cols.map((c) => csvCell(c, (c.en && S.lang === 'en' && r[c.en]) ? r[c.en] : r[c.key])).join(',')));
  if (tot) out.push(cols.map((c, i) => (i === 0 ? csvCell({ type: 'text', key: '_' }, T('totalrow')) : tot[c.key] !== undefined ? csvCell(c, tot[c.key]) : '')).join(','));
  out.push(''); expMeta(res).forEach((m) => out.push(m.map((x) => csvCell({ type: 'text', key: '_' }, x)).join(',')));
  return '﻿' + out.join('\r\n') + '\r\n';
}
function download(name, text, type) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
let logMissing = false;
function logExport(kind, n) {
  if (logMissing) return;      // best effort: the audit function arrives with the next SQL file
  Promise.resolve(V.def && V.def.engine === 2 && B.reports2 ? B.reports2.log(V.key, kind, F.clean(V.f), n) : sb.rpc('log_report_export', { p_key: V.key, p_kind: kind, p_filters: F.clean(V.f), p_rows: n })).then((r) => { if (r && r.error) logMissing = true; }, () => { logMissing = true; });
}
async function exportCSV() {
  if (!V.exp || !V.res) return; toast(T('exp_busy'));
  let all; try { all = await fetchAll(); } catch (e) { return fail(e); }
  const mt = all.res.meta || {};
  download(`report-${V.key}-${mt.from || ''}${mt.to && mt.to !== mt.from ? '_' + mt.to : ''}.csv`, buildCSV(all.rows, all.res), 'text/csv;charset=utf-8');
  logExport('csv', all.rows.length); toast(T('exp_done'));
}
async function exportPrint() {
  if (!V.exp || !V.res) return; toast(T('exp_busy'));
  let all; try { all = await fetchAll(); } catch (e) { return fail(e); }
  const cols = shownCols(), tot = all.res.totals, old = $('#rp_print'); if (old) old.remove();
  const meta = expMeta(all.res), d = document.createElement('div'); d.id = 'rp_print';
  d.innerHTML = `<h1>${esc(meta[0][0])}</h1><p class="pm">${meta.slice(1).map((m) => esc(m.join(': '))).join(' · ')}</p>
    <table><thead><tr>${cols.map((c) => `<th class="${c.role !== 'dim' && ['money', 'int', 'num', 'pct'].includes(c.type) ? 'n' : ''}">${esc(colLabel(c))}</th>`).join('')}</tr></thead>
    <tbody>${all.rows.map((r) => `<tr>${cols.map((c) => `<td class="${c.role !== 'dim' && ['money', 'int', 'num', 'pct'].includes(c.type) ? 'n' : ''}">${esc(fmtVal(c, r))}</td>`).join('')}</tr>`).join('')}</tbody>
    ${tot ? `<tfoot><tr>${cols.map((c, i) => `<th class="${i && c.role !== 'dim' ? 'n' : ''}">${i === 0 ? esc(T('totalrow')) : tot[c.key] !== undefined && tot[c.key] !== null ? esc(fmtVal(c, tot)) : ''}</th>`).join('')}</tr></tfoot>` : ''}</table>`;
  document.body.appendChild(d);
  logExport('print', all.rows.length);
  const clean = () => { const e = $('#rp_print'); if (e) e.remove(); window.removeEventListener('afterprint', clean); };
  window.addEventListener('afterprint', clean);
  setTimeout(() => { try { window.print(); } catch (e) { clean(); } }, 80);
}

// ---------- sheets: columns, views ----------
function colsSheet() {
  const cols = visCols(V.res ? V.res.columns : []);
  openSheet(`<h2 style="margin-top:0">${esc(T('cols_t'))}</h2><div class="stack">${cols.map((c, i) => `<button class="fl-r ${i === 0 || !V.hidden.has(c.key) ? 'on' : ''}" ${i === 0 ? 'disabled' : ''} aria-pressed="${i === 0 || !V.hidden.has(c.key)}" data-act="rp_coltog" data-k="${esc(c.key)}"><i class="bx"></i><span>${esc(colLabel(c))}</span></button>`).join('')}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('done'))}</button>`);
}
async function viewsSheet() {
  const list = await getViews(V.key);
  openSheet(`<h2 style="margin-top:0">${esc(T('views'))}</h2>
    <div id="rp_vl">${list.length ? list.map((v) => `<div class="rp-row mk ${canDelView(v) ? '' : 'info'}"><button class="rp-vb" data-act="rp_vload" data-v="${esc(String(v.id))}"><span class="nm">${esc(v.name)}</span>${v.shared ? `<span class="chip info">${esc(T('shared'))}</span>` : ''}</button>
      ${canDelView(v) ? `<button class="rp-x" data-act="rp_vdel" data-v="${esc(String(v.id))}" aria-label="${esc(T('del') + ': ' + v.name)}">×</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('noviews'))}</p>`}</div>
    <h3 style="margin:16px 0 6px">${esc(T('save'))}</h3>
    <label for="rp_vn">${esc(T('name'))}</label><input id="rp_vn" maxlength="80" autocomplete="off" value="${esc(V.viewName || '')}">
    <button class="tog" id="rp_vs" data-act="rp_vshare" aria-pressed="false" style="margin:10px 0">${esc(T('share'))}</button>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="rp_vsave">${esc(T('save'))}</button></div>`);
  V.vlist = list;
}

// ---------- handlers ----------
Object.assign(A.H, {
  rp_open: (a) => { location.hash = '#/report/' + encodeURIComponent(a.dataset.v); },
  rp_view_open: (a) => { location.hash = '#/report/' + encodeURIComponent(a.dataset.k) + '/' + encodeURIComponent(a.dataset.v); },
  rp_grp: (a) => { HB.g = a.dataset.v; document.querySelectorAll('#rp_gp button').forEach((b) => b.setAttribute('aria-selected', b.dataset.v === HB.g)); drawHubViews(); drawHubList(); },
  rp_filter: () => F.open({ allow: V.def.filters, state: V.f, needsDate: V.def.needs_date !== false, title: repName(V.def), onApply: (s) => { V.f = s; V.stack = []; V.viewName = V.viewName; persist(); drawTop(); run(false); } }),
  rp_sw: (a) => { V.group = a.dataset.v; V.group2 = null; V.sort = null; V.stack = []; persist(); drawTop(); run(false); },
  rp_cmp: () => { V.compare = V.compare ? null : 'prev'; persist(); drawTop(); run(false); },
  rp_cm: (a) => { V.compare = a.dataset.v; persist(); drawTop(); run(false); },
  rp_more: () => run(true),
  rp_retry: () => run(false),
  rp_sortcol: (a) => { const k = a.dataset.k; V.sort = V.sort === k ? '-' + k : V.sort === '-' + k ? null : k; persist(); drawTop(); run(false); },
  rp_drill: (a) => drill(Number(a.dataset.i)),
  rp_back: () => { const s = V.stack.pop(); if (!s) return; V.f = s.f; V.group = s.group; V.group2 = s.group2; V.sort = s.sort; persist(); drawTop(); run(false); },
  rp_cols: colsSheet,
  rp_coltog: (a) => { const k = a.dataset.k; if (V.hidden.has(k)) V.hidden.delete(k); else V.hidden.add(k); a.classList.toggle('on', !V.hidden.has(k)); a.setAttribute('aria-pressed', !V.hidden.has(k)); persist(); drawTop(); drawRes(); },
  rp_views: viewsSheet,
  rp_vshare: (a) => { const on = a.getAttribute('aria-pressed') !== 'true'; a.setAttribute('aria-pressed', on); a.classList.toggle('on', on); },
  rp_vsave: async () => {
    const name = (($('#rp_vn') || {}).value || '').trim(); if (!name) return toast(T('needname'));
    const shared = ($('#rp_vs') || {}).getAttribute('aria-pressed') === 'true';
    const { error } = await sb.from('report_views').insert({ name, report_code: V.key, params: cfgOf(), shared });
    if (error) return fail(error); V.viewName = name; toast(T('saved')); closeSheet(); drawTop();
  },
  rp_vload: (a) => {
    const v = (V.vlist || []).find((x) => String(x.id) === a.dataset.v); if (!v) return;
    applyCfg(v.params); V.viewName = v.name; persist(); closeSheet(); toast(T('loaded')); drawTop(); run(false);
  },
  rp_vdel: async (a) => {
    if (!confirm(T('delq'))) return;
    const { error } = await sb.from('report_views').delete().eq('id', a.dataset.v); if (error) return fail(error);
    toast(T('deleted')); const d = V.vlist && V.vlist.find((x) => String(x.id) === a.dataset.v); if (d && d.name === V.viewName) V.viewName = null; viewsSheet(); drawTop();
  },
  rp_csv: exportCSV,
  rp_print: exportPrint,
});
document.addEventListener('input', (e) => { if (e.target.id === 'rp_q') { HB.q = e.target.value; drawHubViews(); drawHubList(); } });
document.addEventListener('change', (e) => {
  const id = e.target.id;
  if (id === 'rp_g1') { V.group = e.target.value === '' ? null : e.target.value; V.group2 = null; V.sort = null; V.stack = []; persist(); drawTop(); run(false); }
  else if (id === 'rp_g2') { V.group2 = e.target.value || null; V.sort = null; persist(); drawTop(); run(false); }
  else if (id === 'rp_s1') { V.sort = e.target.value || null; persist(); run(false); }
});

// ---------- styles ----------
if (!document.getElementById('rp_css')) {
  const st = document.createElement('style'); st.id = 'rp_css';
  st.textContent = `
#rp_q{margin-bottom:6px}
.rp-row{display:flex;align-items:center;gap:10px;width:100%;min-height:56px;padding-block:6px;border:0;border-bottom:1px solid var(--hair);border-radius:0;background:transparent;color:var(--ink);text-align:start;font:600 1rem/1.4 var(--text-font);box-shadow:none}
.rp-row:last-child{border-bottom:0}
.rp-row .nm{flex:1;min-width:0;overflow-wrap:anywhere} .rp-row .nm small{display:block;color:var(--muted);font:500 .8rem var(--text-font)}
.rp-row .cv{color:var(--muted);font-size:1.3rem}
.rp-row.lock{color:var(--muted);font-weight:500} .rp-row.lock svg{width:18px;height:18px;flex:none}
.rp-bar{display:flex;gap:8px;margin:2px 0 4px} .rp-bar button{flex:1;min-width:0;padding:0 8px;display:inline-flex;align-items:center;justify-content:center;gap:6px}
.rp-bar button svg{width:18px;height:18px;flex:none} .rp-n{display:inline-grid;place-items:center;min-width:22px;height:22px;border-radius:11px;background:rgba(255,255,255,.22);font:700 .78rem var(--text-font);padding:0 5px}
.rp-meta{font-size:.88rem;color:var(--muted);margin:6px 0 2px} .rp-meta b{color:var(--ink)}
.rp-back{border:0;background:transparent;text-decoration:underline;min-height:44px;padding:0 4px;color:var(--ink-2)}
.rp-seg{margin:8px 0 6px} .rp-seg button{font-size:.92rem}
.rp-sel{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:6px 0} .rp-sel select{padding:0 8px;font-size:.92rem} .rp-sel label{margin-bottom:2px;font-size:.78rem}
.rp-cmp{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin:8px 0} .rp-cmp .seg{flex:1;margin:0;min-width:240px}
.rp-note{font-size:.88rem;margin:6px 0;padding-block:4px;color:var(--ink-2)}
.rp-stats{margin:10px 0} .rp-stats .stat .s{display:flex;gap:6px;flex-wrap:wrap;align-items:baseline}
.rp-tw{margin:10px -16px;padding:0 16px;border-top:1px solid var(--hair);border-bottom:1px solid var(--hair)}
table.rp-t{border-collapse:collapse;width:100%;font-size:.9rem;font-variant-numeric:tabular-nums}
.rp-t th,.rp-t td{padding:8px 10px;border-bottom:1px solid var(--hair);text-align:start;white-space:nowrap;vertical-align:top}
.rp-t .n{text-align:end}
.rp-t thead th{padding:0;font:700 .8rem var(--text-font);color:var(--ink-2);background:var(--bg)}
.rp-th{width:100%;min-height:44px;padding:0 10px;border:0;border-radius:0;background:transparent;color:inherit;font:inherit;text-align:inherit;box-shadow:none;white-space:nowrap}
.rp-t th.n .rp-th{text-align:end} .rp-th i{font-style:normal;margin-inline-start:4px}
.rp-t tbody th{font-weight:700;position:sticky;inset-inline-start:0;background:var(--bg);max-width:46vw;overflow:hidden;text-overflow:ellipsis}
.rp-t thead th:first-child{position:sticky;inset-inline-start:0;z-index:1}
.rp-t tr.tap{cursor:pointer} .rp-t tr.tap:active td,.rp-t tr.tap:active th{background:var(--chip-on)}
.rp-t tfoot th,.rp-t tfoot td{font-weight:800;border-top:2px solid var(--ink-2);border-bottom:0;background:var(--bg)}
.rp-t tfoot th{position:sticky;inset-inline-start:0}
.rp-t small.dl{display:block;font:600 .72rem var(--text-font)} .dl.ok{color:var(--sig-ok)} .dl.warn{color:var(--sig-warn)} .dl.neu{color:var(--muted)}
.rp-hint{font-size:.8rem;margin:2px 0 10px}
.rp-foot{display:flex;gap:8px;margin:14px 0} .rp-foot button{flex:1;display:inline-flex;align-items:center;justify-content:center;gap:6px}
.rp-vb{flex:1;min-height:52px;border:0;background:transparent;display:flex;align-items:center;gap:8px;text-align:start;color:var(--ink);font:600 1rem var(--text-font);padding:0;box-shadow:none}
.rp-x{width:48px;min-height:48px;padding:0;border:0;background:transparent;color:var(--sig-bad);font-size:1.5rem;box-shadow:none}
#rp_print{display:none}
@media print{
  body>*:not(#rp_print){display:none!important}
  body{background:#fff!important;color:#000!important}
  #rp_print{display:block!important;font:11pt/1.4 var(--text-font);color:#000;background:#fff;padding:0}
  #rp_print h1{font:700 16pt var(--display);margin:0 0 4pt;color:#000}
  #rp_print .pm{font-size:9pt;margin:0 0 10pt;color:#333}
  #rp_print table{width:100%;border-collapse:collapse;font-size:9.5pt}
  #rp_print th,#rp_print td{border-bottom:.5pt solid #999;padding:3pt 4pt;text-align:left}
  #rp_print .n{text-align:right} #rp_print thead{display:table-header-group} #rp_print tr{break-inside:avoid}
  #rp_print tfoot th,#rp_print tfoot td{border-top:1.5pt solid #000;font-weight:700}
  @page{margin:12mm}
}
`;
  document.head.appendChild(st);
}


/* ============ Brand-level P&L (#/brandpnl) and Discounts (#/discounts) — phase20 ============
   brand_pnl = the existing gross-profit figures (biz_daily) grouped by brand through report_brand_map (owner-editable). Cost and profit come back NULL unless the caller may see costs:
   then the cards simply do not show them. discounts_report = every discounted sale with who approved it (a granted role = the seller, an emergency approval = the person who approved it). */
{
const Y = {
  bp_title: L('ব্র্যান্ড অনুযায়ী লাভ-ক্ষতি', 'Brand-level P&L', 'Brand-level P&L'), dc_title: L('ডিসকাউন্ট ও অনুমোদনকারী', 'Discounts and approvers', 'Discounts ও approver'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), brand: L('ব্র্যান্ড অনুযায়ী', 'By brand', 'By brand'), comb: L('সব মিলিয়ে', 'Combined', 'Combined'),
  rev: L('বিক্রি', 'Sales', 'Sales'), disc: L('ডিসকাউন্ট', 'Discount', 'Discount'), voids: L('বাতিল বিক্রি', 'Voided sales', 'Voided sales'), cogs: L('পণ্যের ক্রয়মূল্য', 'Cost of goods', 'Cost of goods'),
  gp: L('মোট লাভ (খরচ জানা অংশে)', 'Gross profit (costed part)', 'Gross profit (costed part)'), gpp: L('লাভ %', 'GP %', 'GP %'), unc: L('ক্রয়মূল্যহীন বিক্রির অংশ', 'Share of sales without a cost', 'Share without a cost'),
  places: L('লোকেশন', 'places', 'places'), bills: L('বিল', 'bills', 'bills'), nocost: L('খরচের তথ্য আপনার জন্য বন্ধ', 'Cost figures are hidden for your role', 'Cost figures are hidden'),
  note: L('ব্র্যান্ড ঠিক করা আছে "রিপোর্ট ব্র্যান্ড ম্যাপ"-এ (মালিক বদলাতে পারেন)। কোনো সংখ্যা অনুমান করা হয়নি।', 'The brand of a place comes from the report brand map (the owner can change it). No figure is estimated.', 'Brand comes from the report brand map. Nothing is estimated.'),
  none: L('এই সময়ে কিছু নেই', 'Nothing in this period', 'Nothing in this period'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), place: L('লোকেশন', 'Place', 'Place'), allp: L('সব লোকেশন', 'All places', 'All places'),
  onlyap: L('শুধু অনুমোদিত', 'Approved only', 'Approved only'), count: L('ডিসকাউন্টের বিক্রি', 'Discounted sales', 'Discounted sales'), total: L('মোট ডিসকাউন্ট', 'Total discount', 'Total discount'),
  seller: L('বিক্রেতা', 'Seller', 'Seller'), appr: L('অনুমোদনকারী', 'Approver', 'Approver'), k_grant: L('ভূমিকার অনুমতিতে', 'by role right', 'by role right'), k_emergency: L('জরুরি অনুমোদনে', 'by emergency approval', 'by emergency approval'),
  within: L('সীমার ভেতরে / রেকর্ড নেই', 'within the limit / not recorded', 'within the limit / not recorded'), void: L('বাতিল', 'void', 'void'), recno: L('রসিদ', 'Receipt', 'Receipt'),
};
const Ty = (k) => lab(Y[k]);
const dhakaToday = () => new Date(Date.now() + 6 * 3600 * 1000).toISOString().slice(0, 10);
const PB = { from: null, to: null, mode: 'brand', loc: '', onlyap: false };
const initDates = () => { if (!PB.to) { PB.to = dhakaToday(); PB.from = PB.to.slice(0, 8) + '01'; } };
const dateBar = (extra) => `<div class="row wrap" style="margin-bottom:8px"><label class="muted" style="flex:1">${esc(Ty('from'))}<input type="date" id="px_from" value="${esc(PB.from)}" style="width:100%"></label>
  <label class="muted" style="flex:1">${esc(Ty('to'))}<input type="date" id="px_to" value="${esc(PB.to)}" style="width:100%"></label></div>${extra || ''}`;
const card = (k, v, sub) => `<div class="card"><div class="muted" style="font-size:.85rem">${esc(k)}</div><div class="mnum">${v}</div>${sub ? `<div class="muted" style="font-size:.8rem">${sub}</div>` : ''}</div>`;
const pc = (n) => (n === null || n === undefined ? '—' : fmt(Math.round(Number(n) * 10) / 10) + '%');
async function viewBrandPnl() {
  initDates();
  shell(Ty('bp_title'), `${dateBar(`<div class="row wrap" style="margin-bottom:8px"><button class="tog ${PB.mode === 'brand' ? 'on' : ''}" data-act="px_mode" data-v="brand">${esc(Ty('brand'))}</button><button class="tog ${PB.mode === 'comb' ? 'on' : ''}" data-act="px_mode" data-v="comb">${esc(Ty('comb'))}</button></div>`)}<div id="px_body"><p class="muted center pad">${esc(Ty('loading'))}</p></div>`, true);
  const r = await sb.rpc('brand_pnl', { p_from: PB.from, p_to: PB.to, p_brand: null });
  const box = $('#px_body'); if (!box) return;
  if (r.error) return fail(r.error);
  const rows = r.data || [], sum = (k) => rows.reduce((a, x) => a + Number(x[k] || 0), 0), costOn = rows.length > 0 && rows.every((x) => x.gross_profit !== null && x.gross_profit !== undefined);
  const one = (name, x) => {
    const rev = Number(x.revenue || 0), unc = costOn && rev > 0 ? 100 * (1 - Number(x.costed_rev || 0) / rev) : null;
    return `<div class="card panel"><h3>${esc(name)}</h3><div class="muted" style="font-size:.8rem">${esc(fmt(x.locations))} ${esc(Ty('places'))} · ${esc(fmt(x.n))} ${esc(Ty('bills'))}</div>
      <div class="bz-cards">${card(Ty('rev'), money(rev))}${card(Ty('disc'), money(x.discount))}${card(Ty('voids'), esc(fmt(x.void_n)), money(x.void_amt))}
      ${costOn ? card(Ty('gp'), money(x.gross_profit), `${esc(Ty('gpp'))} ${pc(x.gp_pct)}`) : ''}</div>
      ${costOn ? `<div class="row between muted" style="font-size:.85rem"><span>${esc(Ty('cogs'))}: ${money(x.cogs)}</span><span>${esc(Ty('unc'))}: ${pc(unc)}</span></div>` : `<div class="muted" style="font-size:.85rem">${esc(Ty('nocost'))}</div>`}</div>`;
  };
  let h = '';
  if (!rows.length) h = `<p class="muted center pad">${esc(Ty('none'))}</p>`;
  else if (PB.mode === 'comb') {
    const tot = { locations: sum('locations'), n: sum('n'), revenue: sum('revenue'), discount: sum('discount'), void_n: sum('void_n'), void_amt: sum('void_amt'), costed_rev: sum('costed_rev'), cogs: sum('cogs'),
      gross_profit: costOn ? sum('gross_profit') : null }; tot.gp_pct = costOn && sum('costed_rev') > 0 ? 100 * tot.gross_profit / sum('costed_rev') : null;
    h = one(Ty('comb'), tot);
  } else h = rows.map((x) => one(lab({ bn: x.brand_bn, en: x.brand_en }), x)).join('');
  box.innerHTML = h + `<div class="notice ok" style="font-size:.85rem">${esc(Ty('note'))}</div>`;
}
async function viewDiscounts() {
  initDates(); const locs = ((B.ENV && B.ENV.locs) || []).filter((l) => S.ctx.is_owner || (S.ctx.roles || []).includes('management') || (S.ctx.locations || []).includes(l.id));
  shell(Ty('dc_title'), `${dateBar(`<div class="row wrap" style="margin-bottom:8px"><select id="px_loc" aria-label="${esc(Ty('place'))}" style="flex:1"><option value="">${esc(Ty('allp'))}</option>${locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(PB.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
      <button class="tog ${PB.onlyap ? 'on' : ''}" data-act="px_onlyap">${esc(Ty('onlyap'))}</button></div>`)}<div id="px_body"><p class="muted center pad">${esc(Ty('loading'))}</p></div>`, true);
  const r = await sb.rpc('discounts_report', { p_from: PB.from, p_to: PB.to, p_loc: PB.loc === '' ? null : Number(PB.loc), p_only_approved: PB.onlyap });
  const box = $('#px_body'); if (!box) return;
  if (r.error) return fail(r.error);
  const rows = r.data || [];
  box.innerHTML = (rows.length ? `<div class="bz-cards">${card(Ty('count'), esc(fmt(rows.length)))}${card(Ty('total'), money(rows.filter((x) => x.status !== 'void').reduce((a, x) => a + Number(x.discount || 0), 0)))}</div>
    <div class="card" style="padding:4px 12px">${rows.map((x) => `<div class="row between" style="min-height:56px;padding:6px 0;border-bottom:1px solid var(--line,#0001)"><div><b>${esc(Ty('recno'))} ${esc(x.receipt)}</b> <span class="muted" style="font-size:.8rem">${esc(x.sale_date)}${x.status === 'void' ? ' · ' + esc(Ty('void')) : ''}</span>
      <div class="muted" style="font-size:.8rem">${esc(Ty('seller'))}: ${esc(x.seller_staff || '—')} · ${esc(Ty('appr'))}: ${x.approval ? esc(x.approver_staff || '—') + ' (' + esc(Ty('k_' + x.approval)) + ')' : esc(Ty('within'))}</div></div>
      <div style="text-align:end"><b class="mnum">${money(x.discount)}</b><div class="muted" style="font-size:.8rem">${x.discount_kind === 'percent' && x.discount_input !== null ? esc(fmt(x.discount_input)) + '%' : ''}</div></div></div>`).join('')}</div>` : `<p class="muted center pad">${esc(Ty('none'))}</p>`);
}
Object.assign(A.H, {
  px_mode: (a) => { PB.mode = a.dataset.v; return viewBrandPnl(); },
  px_onlyap: () => { PB.onlyap = !PB.onlyap; return viewDiscounts(); },
});
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !id.startsWith('px_')) return;
  const page = location.hash.replace(/^#\/?/, '').split('/')[0]; if (page !== 'brandpnl' && page !== 'discounts') return;
  if (id === 'px_from' || id === 'px_to') { const v = e.target.value; if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return; PB[id === 'px_from' ? 'from' : 'to'] = v; }
  else if (id === 'px_loc') PB.loc = e.target.value;
  return page === 'brandpnl' ? viewBrandPnl() : viewDiscounts();
});
B.reportLinks = B.reportLinks || [];
const bizCheck = (key) => async () => { const l = B.reportLinks.find((x) => x.key === key); if (S.ctx && S.ctx.is_owner) { l.allowed = true; return; }
  const to = dhakaToday(); try { const r = await sb.rpc(key === 'brandpnl' ? 'brand_pnl' : 'discounts_report', key === 'brandpnl' ? { p_from: to, p_to: to, p_brand: null } : { p_from: to, p_to: to, p_loc: null, p_only_approved: false }); l.allowed = !!(r && !r.error); } catch (e) { l.allowed = false; } };
B.reportLinks.push({ key: 'brandpnl', route: 'brandpnl', label: () => Ty('bp_title'), allowed: null, check: bizCheck('brandpnl') });
B.reportLinks.push({ key: 'discounts', route: 'discounts', label: () => Ty('dc_title'), allowed: null, check: bizCheck('discounts') });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { brandpnl: viewBrandPnl, discounts: viewDiscounts });
}

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { reports: viewHub, report: viewReport });
B.reports = { open: (key) => { location.hash = '#/report/' + encodeURIComponent(key); } };
})();
