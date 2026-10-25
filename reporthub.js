/* Islamia BOS · Business Memory (#/reports/hub): the Reports list organised by the QUESTION it answers, and the place to see "what actually happened".
   - Home: a question box ("Ask / Find"), five tools (Day replay, Timeline of a thing, Compare, Spend finder, Record trail), my favourites / recent / saved views, the catalogue of all 193 reports.
   - The catalogue is the static registry web/data/report_registry.json (built by tools/build_report_registry.py): 14 sections, status badge, source, grant. It is not live data.
   - Everything the tools show comes from READ-ONLY server functions (phases 470-476) that cut each answer down to the report rights of the person. Nothing is hidden by this page.
   - Other files extend B.rhub: reporthub_parse.js (question parser), reporthub_ask.js (Ask + Spend finder), reporthub_time.js (Day replay, Timeline, Compare, Drill, Trail).
   The page only shows and sends; the server decides every right and every number. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm, fmt, store } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const R = B.rhub = B.rhub || {};
R.views = R.views || {};

// ---------- small helpers shared by the hub files ----------
const dhakaToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const monthStart = (iso) => iso.slice(0, 8) + '01';
const monthEnd = (iso) => { const d = new Date(iso.slice(0, 8) + '01T12:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0); return d.toISOString().slice(0, 10); };
const money = (n) => (n === null || n === undefined || n === '' ? '—' : '৳ ' + fmt(Math.round(Number(n) * 100) / 100));
const qtyf = (n) => (n === null || n === undefined ? '—' : String(Math.round(Number(n) * 10000) / 10000));
const hm = (ts) => { try { return new Date(ts).toLocaleTimeString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', minute: '2-digit' }); } catch (e) { return ''; } };
const ymd = (ts) => { try { return new Date(ts).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }); } catch (e) { return ''; } };
const stamp = (ts) => (ts ? ymd(ts) + ' ' + hm(ts) : '');
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const jget = (k, d) => { try { const v = JSON.parse(store.get(k) || 'null'); return v == null ? d : v; } catch (e) { return d; } };
Object.assign(R, { dhakaToday, addDays, monthStart, monthEnd, money, qtyf, hm, ymd, stamp });

// ---------- texts (three modes) ----------
const X = R.X = Object.assign(R.X || {}, {
  title: L('বিজনেস মেমোরি', 'Business Memory', 'Business Memory'), sub: L('কী ঘটেছিল দেখুন, রিপোর্ট খুঁজুন', 'See what happened, find a report', 'কী ঘটেছিল দেখুন, Report খুঁজুন'),
  ask_h: L('জিজ্ঞাসা করুন / খুঁজুন', 'Ask / Find', 'Ask / Find'), ask_ph: L('যেমন: গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত', 'e.g. electricity bill of one branch, last 8 months', 'যেমন: গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত'), ask_go: L('খুঁজুন', 'Find', 'Find'),
  ask_hint: L('বাংলা বা ইংরেজিতে লিখুন। আমি কী বুঝলাম নিচে দেখাব, ভুল হলে ঠিক করে নিন।', 'Write in Bengali or English. I show what I understood; fix it if it is wrong.', 'বাংলা বা English-এ লিখুন। কী বুঝলাম দেখাব, ভুল হলে ঠিক করুন।'),
  tools: L('কী ঘটেছিল দেখুন', 'What happened?', 'কী ঘটেছিল দেখুন'),
  t_day: L('একটি দিনের গল্প', 'Day replay', 'Day replay'), t_day_s: L('যেকোনো ডেটে কী কী হয়েছিল', 'Everything that happened on one date', 'যেকোনো Dateে কী কী হয়েছিল'),
  t_ent: L('একটির ইতিহাস', 'Timeline of one thing', 'Timeline'), t_ent_s: L('আইটেম, গ্রাহক, সরবরাহকারী, কর্মী, শাখা, ব্যাচ', 'Item, customer, supplier, staff, outlet, batch', 'Item, Customer, Supplier, Staff, Outlet, Batch'),
  t_cmp: L('কী বদলেছে', 'Compare', 'Compare'), t_cmp_s: L('দুটি সময় পাশাপাশি, কারণসহ', 'Two periods side by side, with the reasons', 'দুটি Period পাশাপাশি'),
  t_spend: L('খরচ খুঁজুন', 'Spend finder', 'Spend finder'), t_spend_s: L('কাকে, কী বাবদ, কোথায়, কত', 'Who, for what, where, how much', 'কাকে, কী বাবদ, কোথায়, কত'),
  t_trail: L('রেকর্ডের ইতিহাস', 'Record trail', 'Record trail'), t_trail_s: L('কে বানাল, বদলাল, বাতিল করল', 'Who made, changed, voided it', 'কে বানাল, বদলাল, বাতিল করল'),
  mine: L('আমার', 'Mine', 'Mine'), fav: L('প্রিয়', 'Favourites', 'Favourites'), recent: L('সম্প্রতি খোলা', 'Recently opened', 'Recently opened'), views: L('সংরক্ষিত ভিউ', 'Saved views', 'Saved views'),
  none_yet: L('এখনও কিছু নেই', 'Nothing yet', 'এখনও কিছু নেই'),
  cat: L('সব রিপোর্ট প্রশ্ন অনুযায়ী', 'All reports, by the question they answer', 'সব Report, প্রশ্ন অনুযায়ী'), search: L('নাম, প্রশ্ন বা শব্দ লিখে খুঁজুন…', 'Search a name, a question or a word…', 'নাম, প্রশ্ন বা শব্দ খুঁজুন…'),
  f_section: L('বিভাগ', 'Section', 'Section'), f_status: L('অবস্থা', 'Status', 'Status'), f_area: L('এলাকা', 'Area', 'Area'), all: L('সব', 'All', 'All'),
  s_implemented: L('আছে', 'Implemented', 'Implemented'), s_incomplete: L('আংশিক', 'Incomplete', 'Incomplete'), s_unavailable: L('নেই', 'Unavailable', 'Unavailable'), s_unverified: L('যাচাই হয়নি', 'Unverified', 'Unverified'), s_unaudited: L('অডিট বাকি', 'Unaudited', 'Unaudited'),
  s_hint_implemented: L('চলছে ও যাচাই করা', 'Works and was checked', 'Works ও checked'), s_hint_incomplete: L('আছে কিন্তু অসম্পূর্ণ বা বিভ্রান্তিকর', 'Exists but partial or misleading', 'আছে কিন্তু partial'),
  s_hint_unavailable: L('এই তথ্য এখনও রাখা হয় না', 'The data is not captured yet', 'Data এখনও রাখা হয় না'), s_hint_unverified: L('চালিয়ে দেখা যায়নি', 'Could not be tested with data', 'Test করা যায়নি'), s_hint_unaudited: L('এই বিভাগের অডিট বাকি', 'This section is not audited yet', 'Audit বাকি'),
  open: L('খুলুন', 'Open', 'Open'), planned: L('পরিকল্পিত', 'Planned', 'Planned'), question: L('যে প্রশ্নের উত্তর দেয়', 'Question it answers', 'প্রশ্ন'), source: L('তথ্যের উৎস', 'Data source', 'Source'), grant: L('প্রয়োজনীয় অনুমতি', 'Required right', 'Required right'),
  route: L('জায়গা', 'Where', 'Where'), note: L('জানা সমস্যা', 'Known issue', 'Known issue'), details: L('বিস্তারিত', 'Details', 'Details'), no_match: L('কিছু পাওয়া যায়নি', 'Nothing matches', 'কিছু পাওয়া যায়নি'),
  unaudited_note: L('বিভাগ ৮-১৪ এর অডিট এখনও বাকি। তালিকার নম্বর আছে, নাম অডিট ৩ এর পর বসবে।', 'Sections 8-14 are not audited yet. The numbers are listed; the names appear when audit 3 is merged.', 'Section 8-14 audit বাকি। নম্বর আছে, নাম audit 3-এর পর।'),
  counts: L('মোট', 'total', 'total'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), retry: L('আবার চেষ্টা', 'Retry', 'Retry'), back: L('পেছনে', 'Back', 'Back'),
  reg_fail: L('রিপোর্টের তালিকা লোড করা গেল না', 'Could not load the report list', 'Report list load করা গেল না'),
  star: L('প্রিয়তে রাখুন', 'Add to favourites', 'Favourite-এ রাখুন'), unstar: L('প্রিয় থেকে সরান', 'Remove from favourites', 'Favourite থেকে সরান'),
  gen: L('তৈরির সময়', 'Generated at', 'Generated at'), filters: L('ফিল্টার', 'Filters', 'Filters'), from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), place: L('শাখা / জায়গা', 'Outlet / place', 'Outlet / place'), all_places: L('আমার সব জায়গা', 'All my places', 'সব Place'),
  csv: L('CSV', 'CSV', 'CSV'), csv_lock: L('এক্সপোর্টের অনুমতি নেই', 'Export is not allowed for you', 'Export-এর permission নেই'), csv_busy: L('তৈরি হচ্ছে…', 'Preparing…', 'Preparing…'), csv_done: L('ফাইল তৈরি', 'File ready', 'File ready'),
  more: L('আরও দেখান', 'Show more', 'আরও দেখান'), prev: L('আগের', 'Previous', 'Previous'), next: L('পরের', 'Next', 'Next'), of: L('/', 'of', '/'), rows: L('সারি', 'rows', 'rows'),
  save_view: L('ভিউ সেভ', 'Save this view', 'Save this view'), view_name: L('ভিউয়ের নাম', 'View name', 'View name'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), removed: L('সরানো হয়েছে', 'Removed', 'Removed'),
  pin: L('হোমে পিন', 'Pin to Home', 'Pin to Home'), pinned: L('পিন করা হয়েছে', 'Pinned', 'Pinned'), unpin: L('পিন সরান', 'Unpin', 'Unpin'),
  empty_day: L('এই দিনে এই জায়গায় কিছু লেখা নেই', 'Nothing is recorded for this day at this place', 'এই দিনে কিছু লেখা নেই'),
  nr: L('লেখা নেই', 'not recorded', 'not recorded'), hidden_h: L('আপনাকে দেখানো হচ্ছে না', 'Not shown to you', 'আপনাকে দেখানো হচ্ছে না'),
  hidden_t: L('এগুলোর জন্য সংশ্লিষ্ট রিপোর্টের অনুমতি লাগে। যা দেখানো হয়নি তার সংখ্যা বা টাকাও এখানে নেই।', 'These need the matching report right. Their counts and amounts are not included here either.', 'এগুলোর জন্য report right লাগে। count বা টাকাও এখানে নেই।'),
  cost_hidden: L('খরচ ও মূল্যের কলাম আপনার ভূমিকার জন্য বন্ধ', 'Cost and value figures are hidden for your role', 'Cost ও value আপনার role-এর জন্য বন্ধ'),
  e_off: L('ইন্টারনেট নেই — দেখতে অনলাইন লাগবে', 'You are offline — this needs a connection', 'Internet নেই — online লাগবে'), e_na: L('এই বিভাগ ডেটাবেসে এখনও চালু হয়নি (phase470-476)', 'This part is not installed on the database yet (phases 470-476)', 'Database-এ এখনও চালু হয়নি (phase470-476)'),
  e_perm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), e_range: L('ডেটের পরিসর ঠিক নেই বা খুব বড়', 'The date range is not valid or too long', 'Date range ঠিক নেই'), e_nf: L('পাওয়া যায়নি', 'Not found', 'পাওয়া যায়নি'),
  e_gen: L('কিছু একটা ভুল হয়েছে', 'Something went wrong', 'কিছু ভুল হয়েছে'), e_filter: L('ফিল্টারের মান ঠিক নেই', 'A filter value is not valid', 'Filter-এর value ঠিক নেই'),
});
const T = (k) => lab(X[k]);
R.T = T;

// areas and kinds of events, in words
const AREA = R.AREA = {
  sales: L('বিক্রি', 'Sales', 'Sales'), customers: L('গ্রাহক ও বাকি', 'Customers & dues', 'Customer ও বাকি'), cash: L('ক্যাশ ও ব্যাংক', 'Cash & bank', 'Cash ও Bank'), pos: L('POS শিট', 'POS sheets', 'POS sheet'),
  stock: L('স্টক ও উৎপাদন', 'Stock & production', 'Stock ও Production'), purchase: L('ক্রয় ও সরবরাহকারী', 'Purchases & suppliers', 'Purchase ও Supplier'), expense: L('খরচ', 'Expenses', 'Expenses'),
  payroll: L('বেতন ও অগ্রিম', 'Pay & advances', 'Pay ও Advance'), hr: L('কর্মীর অবস্থা', 'Staff status', 'Staff status'), control: L('অ্যাপ্রুভ ও ব্যতিক্রম', 'Approvals & exceptions', 'Approval ও Exception'),
  accounts: L('হিসাব ও মাস বন্ধ', 'Accounts & period lock', 'Accounts ও Period lock'), cost: L('খরচের অঙ্ক', 'Cost figures', 'Cost figure'),
};
const EV = R.EV = {
  sale: L('বিক্রি', 'Sale', 'Sale'), void: L('বাতিল', 'Void', 'Void'), return: L('ফেরত', 'Return', 'Return'), collection: L('বাকি আদায়', 'Due collected', 'Collection'), sale_payment: L('বিক্রির পেমেন্ট', 'Sale payment', 'Sale payment'),
  expense: L('দ্রুত খরচ', 'Quick expense', 'Quick expense'), voucher: L('খরচ ভাউচার', 'Expense voucher', 'Expense voucher'), supplier_payment: L('সরবরাহকারীকে পরিশোধ', 'Supplier payment', 'Supplier payment'), supplier_refund: L('সরবরাহকারীর ফেরত টাকা', 'Supplier refund', 'Supplier refund'),
  purchase: L('ক্রয় বিল', 'Purchase bill', 'Purchase bill'), purchase_return: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), production: L('উৎপাদন', 'Production run', 'Production'),
  transfer_sent: L('ট্রান্সফার পাঠানো', 'Transfer sent', 'Transfer sent'), transfer_received: L('ট্রান্সফার গ্রহণ', 'Transfer received', 'Transfer received'), transfer_cancelled: L('ট্রান্সফার বাতিল', 'Transfer cancelled', 'Transfer cancelled'),
  wastage: L('অপচয়', 'Wastage', 'Wastage'), count_adjust: L('গণনার সমন্বয়', 'Count adjustment', 'Count adjustment'), ledger: L('স্টক চলাচল', 'Stock movement', 'Stock movement'), cash_move: L('ক্যাশ/ব্যাংক লেনদেন', 'Cash / bank move', 'Cash/Bank move'),
  cash_short: L('ক্যাশ কম/বেশি', 'Cash short / over', 'Cash short/over'), other_income: L('অন্যান্য আয়', 'Other income', 'Other income'), money_transfer: L('টাকা স্থানান্তর', 'Money transfer', 'Money transfer'),
  handover: L('ক্যাশ হ্যান্ডওভার (০৩-১)', 'Cash handover (03-1)', 'Cash handover (03-1)'), day_sheet: L('শোরুম দৈনিক শিট (০৬-১)', 'Daily showroom sheet (06-1)', 'Daily sheet (06-1)'), count_sheet: L('স্টক গণনা শিট (৩৬-১)', 'Stock count sheet (36-1)', 'Count sheet (36-1)'), factory_sheet: L('কারখানা দৈনিক শিট (১২-১)', 'Factory daily sheet (12-1)', 'Factory sheet (12-1)'),
  transit_short: L('পথে কম মাল', 'Short in transit', 'Short in transit'), approval: L('অ্যাপ্রুভ', 'Approval', 'Approval'), exception: L('ব্যতিক্রম', 'Exception', 'Exception'), exception_resolved: L('ব্যতিক্রম নিষ্পত্তি', 'Exception resolved', 'Exception resolved'),
  period: L('মাস/বছর বন্ধ ও লক', 'Period / lock', 'Period / lock'), staff_status: L('কর্মীর অবস্থা বদল', 'Staff status change', 'Staff status'), staff_exit: L('কর্মীর প্রস্থান', 'Staff exit', 'Staff exit'), payroll: L('বেতন পরিশোধ', 'Salary payment', 'Salary payment'),
  advance: L('কর্মীর অগ্রিম', 'Staff advance', 'Staff advance'), price_change: L('দাম বদল', 'Price change', 'Price change'),
};
const ST = R.ST = { done: L('সম্পন্ন', 'done', 'done'), posted: L('পোস্ট করা', 'posted', 'posted'), void: L('বাতিল', 'void', 'void'), draft: L('খসড়া', 'draft', 'draft'), submitted: L('জমা', 'submitted', 'submitted'), approved: L('অনুমোদিত', 'approved', 'approved'),
  rejected: L('প্রত্যাখ্যাত', 'rejected', 'rejected'), open: L('খোলা', 'open', 'open'), resolved: L('নিষ্পন্ন', 'resolved', 'resolved'), pending: L('অপেক্ষায়', 'pending', 'pending'), requested: L('অনুরোধ', 'requested', 'requested'), received: L('গৃহীত', 'received', 'received'),
  sent: L('পাঠানো', 'sent', 'sent'), cancelled: L('বাতিল', 'cancelled', 'cancelled'), active: L('চালু', 'active', 'active'), reversed: L('উল্টানো', 'reversed', 'reversed'), ended: L('শেষ', 'ended', 'ended') };
R.evLabel = (k) => (EV[k] ? lab(EV[k]) : k);
R.stLabel = (k) => (ST[k] ? lab(ST[k]) : k || '');
R.areaLabel = (k) => (AREA[k] ? lab(AREA[k]) : k);
const stCls = (s) => (['void', 'cancelled', 'rejected'].includes(s) ? 'bad' : ['open', 'pending', 'requested', 'draft', 'sent'].includes(s) ? 'warn' : ['done', 'posted', 'approved', 'received', 'resolved', 'active'].includes(s) ? 'ok' : '');
R.stCls = stCls;

// ---------- server calls ----------
const ERRS = [['not allowed', 'e_perm'], ['bad_range', 'e_range'], ['bad_date', 'e_range'], ['not_found', 'e_nf'], ['bad_filter', 'e_filter'], ['bad_kind', 'e_filter'], ['bad_id', 'e_filter']];
R.errText = (e) => {
  const m = String((e && (e.message || e.msg)) || e || '');
  if (/could not find the function|does not exist|schema cache|404/i.test(m)) return T('e_na');
  if (/fetch|network|failed to load/i.test(m) && !navigator.onLine) return T('e_off');
  const hit = ERRS.find(([k]) => m.includes(k)); return hit ? T(hit[1]) : T('e_gen');
};
R.rpc = async (fn, args) => {
  try {
    if (!navigator.onLine) return { data: null, error: { message: 'offline' }, msg: T('e_off') };
    const r = await sb.rpc(fn, args || {});
    if (r && r.error) return { data: null, error: r.error, msg: R.errText(r.error) };
    return { data: r ? r.data : null, error: null };
  } catch (e) { return { data: null, error: e, msg: R.errText(e) }; }
};
let PERMS = null;
R.perms = async (force) => { if (PERMS && !force) return PERMS; const r = await R.rpc('rpt_hub_perms'); PERMS = r.data || { owner: !!(S.ctx && S.ctx.is_owner), areas: {}, locations: [] }; PERMS.ok = !r.error; return PERMS; };
R.locs = () => {
  const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
  const ctx = S.ctx || {}; return ctx.is_owner || (ctx.roles || []).includes('management') ? all : all.filter((l) => (ctx.locations || []).includes(l.id));
};
R.locName = (id) => { if (id === null || id === undefined) return ''; const l = ((B.ENV && B.ENV.locs) || []).find((x) => Number(x.id) === Number(id)); return l ? nm(l) : '#' + id; };
R.locSelect = (id, val, all) => `<select id="${id}" aria-label="${esc(T('place'))}"><option value="">${esc(all || T('all_places'))}</option>${R.locs().map((l) => `<option value="${l.id}" ${String(l.id) === String(val) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;

// ---------- routes with parameters: #/reports/hub/<view>?a=1&b=2 ----------
R.parts = () => {
  const h = location.hash.replace(/^#\/?/, ''), q = h.indexOf('?'), path = (q < 0 ? h : h.slice(0, q)).split('/'), params = {};
  if (q >= 0) h.slice(q + 1).split('&').forEach((kv) => { const i = kv.indexOf('='); if (i > 0) { try { params[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1).replace(/\+/g, ' ')); } catch (e) { /* skip a broken pair */ } } });
  return { view: path[2] || 'home', params };
};
R.url = (view, params) => '#/reports/hub' + (view && view !== 'home' ? '/' + view : '') + (params && Object.keys(params).length ? '?' + Object.entries(params).filter(([, v]) => v !== null && v !== undefined && v !== '').map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&') : '');
R.go = (view, params) => { location.hash = R.url(view, params); };

// ---------- the header every result carries: when it was made and with which filters ----------
R.stampHTML = (res, chips) => `<div class="muted rh-stamp"><span>${esc(T('gen'))}: <b>${esc(res && res.generated_at ? stamp(res.generated_at) : stamp(new Date().toISOString()))}</b></span>${(chips || []).filter(Boolean).length ? `<span class="rh-fl">${esc(T('filters'))}: ${(chips || []).filter(Boolean).map((c) => `<span class="chip">${esc(c)}</span>`).join(' ')}</span>` : ''}</div>`;
R.maskHTML = (masked, notes) => {
  const names = (masked || []).map((m) => (m && m.area ? R.areaLabel(m.area) : String(m).replace(/^head:|^person:/, ''))).filter(Boolean);
  const nn = (notes || []);
  return (names.length ? `<div class="notice warn mk warn"><b>${esc(T('hidden_h'))}:</b> ${esc([...new Set(names)].join(', '))}<br><span style="font-size:.9em">${esc(T('hidden_t'))}</span></div>` : '')
    + (nn.includes('cost_hidden') ? `<p class="muted">${esc(T('cost_hidden'))}</p>` : '');
};
R.stateHTML = (kind, msg, retry) => (B.ui && B.ui.state ? B.ui.state(kind, msg, retry) : `<p class="muted center pad">${esc(msg || '')}</p>`);
R.pagerHTML = (total, limit, offset, act, extra) => {
  if (!total || total <= limit) return total ? `<p class="muted center">${esc(String(total))} ${esc(T('rows'))}</p>` : '';
  const a = offset + 1, b = Math.min(total, offset + limit);
  return `<div class="row between rh-pager"><button data-act="${act}" data-o="${Math.max(0, offset - limit)}" ${offset <= 0 ? 'disabled' : ''} ${extra || ''}>‹ ${esc(T('prev'))}</button><span class="muted">${a}–${b} ${esc(T('of'))} ${total}</span><button data-act="${act}" data-o="${offset + limit}" ${b >= total ? 'disabled' : ''} ${extra || ''}>${esc(T('next'))} ›</button></div>`;
};
// CSV: a string with a BOM so Excel reads Bengali; logs one audit line when the person holds the export right
const csvCell = (v) => { const s = v === null || v === undefined ? '' : String(v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
R.csvText = (head, rows) => '﻿' + [head, ...rows].map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';
R.canExport = async () => { const p = await R.perms(); return !!(p.owner || (p.areas && p.areas.export)); };
R.download = (name, text) => {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' }), url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url; a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 500);
};
R.exportCsv = async (name, head, rowsFn, filters) => {
  if (!(await R.canExport())) return toast(T('csv_lock'));
  toast(T('csv_busy'));
  try {
    const rows = await rowsFn();
    R.download(name + '_' + dhakaToday() + '.csv', R.csvText(head, rows));
    R.rpc('rpt_hub_log_export', { p_key: name, p_filters: filters || {}, p_rows: rows.length });
    toast(T('csv_done') + ' (' + rows.length + ')');
  } catch (e) { toast(R.errText(e)); }
};
// one place for the "Save this view" + favourite pattern used by every tool
R.saveViewHTML = (key) => `<div class="row rh-save"><input id="rh_vn" maxlength="80" autocomplete="off" placeholder="${esc(T('view_name'))}" aria-label="${esc(T('view_name'))}"><button data-act="rh_save_view" data-k="${esc(key)}">${esc(T('save_view'))}</button></div>`;
R.saveView = async (key, params) => {
  const el = $('#rh_vn'), name = el ? el.value.trim() : '';
  if (!name) return toast(T('view_name'));
  const r = await R.rpc('rpt_hub_item_save', { p_kind: 'view', p_key: key, p_name: name, p_params: params || {} });
  if (r.error) return toast(r.msg); toast(T('saved')); if (el) el.value = '';
};
R.touch = (key, params) => { R.rpc('rpt_hub_touch', { p_key: key, p_params: params || {} }); };

// ---------- the registry ----------
let REG = null, REGP = null;
R.registry = () => {
  if (REG) return Promise.resolve(REG);
  if (!REGP) REGP = fetch('data/report_registry.json', { cache: 'no-cache' }).then((r) => { if (!r.ok) throw new Error('registry ' + r.status); return r.json(); }).then((j) => { REG = j; return j; }).catch((e) => { REGP = null; throw e; });
  return REGP;
};
const pick = (o) => (o ? lab({ bn: o.bn, en: o.en, mix: o.mix || o.bn }) : '');
R.pick = pick;
const norm = (s) => (B.parse ? B.parse.normalize(s) : String(s || '').toLowerCase());

// ---------- catalogue ----------
const CT = { q: '', sec: '', st: '', area: '', open: new Set(), shown: {}, my: { fav: [], recent: [], view: [] }, allowed: null };
const STAT_ORDER = ['implemented', 'incomplete', 'unavailable', 'unverified', 'unaudited'];
const badge = (s) => `<span class="chip ${{ implemented: 'ok', incomplete: 'warn', unavailable: 'bad', unverified: 'info', unaudited: '' }[s] || ''}" title="${esc(lab(X['s_hint_' + s] || X.s_unaudited))}">${esc(lab(X['s_' + s] || X.s_unaudited))}</span>`;
function score(r, q) {
  if (!q) return 1;
  const toks = q.split(' ').filter(Boolean); let s = 0;
  const no = String(r.no), name = norm([r.name.bn, r.name.en, r.name.mix].join(' ')), que = norm([r.question.bn, r.question.en].join(' ')), kw = (r.kw || []).map(norm), meta = norm((r.source || '') + ' ' + (r.grant || ''));
  for (const t of toks) {
    const t2 = t.replace(/^#/, '');
    if (/^\d+$/.test(t2) && t2 === no) s += 8;
    else if (name.includes(t)) s += 3;
    else if (kw.some((k) => k === t || k.includes(t) || (t.length > 3 && t.includes(k) && k.length > 2))) s += 3;
    else if (que.includes(t)) s += 1.5;
    else if (meta.includes(t)) s += 0.5;
    else return 0;          // every word must be found somewhere
  }
  return s;
}
R.searchReports = (reg, text, limit) => (reg.reports || []).map((r) => [r, score(r, norm(text))]).filter((x) => x[1] > 0).sort((a, b) => b[1] - a[1] || a[0].no - b[0].no).slice(0, limit || 20).map((x) => x[0]);
const openRoute = (r) => (r.route ? (r.route.startsWith('report/') ? '#/report/' + r.route.slice(7) : '#/' + r.route) : null);
R.openReport = (r) => { const h = openRoute(r); if (!h) return; R.touch(r.id, { no: r.no }); location.hash = h; };
function rowHTML(r, o) {
  o = o || {};
  const open = CT.open.has(r.id), fav = CT.my.fav.some((f) => f.key === r.id), h = openRoute(r);
  const locked = h && r.route.startsWith('report/') && CT.allowed && CT.allowed.has(r.route.slice(7)) && CT.allowed.get(r.route.slice(7)) === false;
  return `<div class="rh-rep ${open ? 'open' : ''}" data-id="${esc(r.id)}">
    <div class="rh-rep-h"><button class="rh-rep-t" data-act="rh_rep_toggle" data-v="${esc(r.id)}" aria-expanded="${open}"><span class="rh-no">#${r.no}</span><span class="nm"><b>${esc(pick(r.name))}</b><small>${esc(pick(r.question))}</small></span></button>
      <span class="rh-rep-s">${badge(r.status)}</span></div>
    <div class="rh-rep-a">${h ? (locked ? `<span class="chip">${esc(T('e_perm'))}</span>` : `<button class="primary" data-act="rh_rep_open" data-v="${esc(r.id)}">${esc(T('open'))}</button>`) : `<span class="chip">${esc(T('planned'))}</span>`}
      <button class="rh-star ${fav ? 'on' : ''}" data-act="rh_fav" data-v="${esc(r.id)}" aria-pressed="${fav}" aria-label="${esc(fav ? T('unstar') : T('star'))}">${fav ? '★' : '☆'}</button></div>
    ${open ? `<dl class="rh-dl"><dt>${esc(T('question'))}</dt><dd>${esc(pick(r.question))}</dd>${r.source ? `<dt>${esc(T('source'))}</dt><dd>${esc(r.source)}</dd>` : ''}${r.grant ? `<dt>${esc(T('grant'))}</dt><dd>${esc(r.grant)}</dd>` : ''}
      ${r.route ? `<dt>${esc(T('route'))}</dt><dd>${esc(r.route)}</dd>` : ''}${r.note ? `<dt>${esc(T('note'))}</dt><dd>${esc(r.note)}</dd>` : ''}<dt>${esc(X.s_implemented && T('f_status'))}</dt><dd>${esc(lab(X['s_hint_' + r.status] || X.s_unaudited))}</dd></dl>` : ''}
  </div>`;
}
function catalogHTML(reg) {
  const q = norm(CT.q);
  let list = reg.reports.filter((r) => (!CT.sec || String(r.section) === CT.sec || (CT.sec === 'x' && !r.section)) && (!CT.st || r.status === CT.st) && (!CT.area || r.area === CT.area));
  if (q) list = list.map((r) => [r, score(r, q)]).filter((x) => x[1] > 0).sort((a, b) => b[1] - a[1] || a[0].no - b[0].no).map((x) => x[0]);
  const askBtn = q ? `<button class="full rh-asklink" data-act="rh_ask_text" data-v="${esc(CT.q)}">${esc(lab(L('প্রশ্ন হিসেবে জিজ্ঞাসা করুন', 'Ask it as a question', 'প্রশ্ন হিসেবে Ask করুন')))}: “${esc(CT.q)}”</button>` : '';
  if (!list.length) return `<p class="muted center pad">${esc(T('no_match'))}</p>${askBtn}`;
  const secOf = (r) => reg.sections.find((s) => s.no === r.section);
  if (q) return `${askBtn}<div class="card rh-list">${list.slice(0, 60).map((r) => rowHTML(r)).join('')}</div>${list.length > 60 ? `<p class="muted center">${list.length} ${esc(T('rows'))} — ${esc(T('search'))}</p>` : ''}`;
  let h = '';
  const groups = reg.sections.map((s) => [s, list.filter((r) => r.section === s.no)]).filter(([, rs]) => rs.length);
  const orph = list.filter((r) => !r.section);
  groups.forEach(([s, rs]) => {
    const sc = {}; rs.forEach((r) => { sc[r.status] = (sc[r.status] || 0) + 1; });
    const open = CT.open.has(s.id) || !!(CT.sec || CT.st || CT.area);
    h += `<div class="rh-sec"><button class="rh-sec-h" data-act="rh_sec_toggle" data-v="${esc(s.id)}" aria-expanded="${open}"><span class="nm"><b>${s.no}. ${esc(pick(s.name))}</b><small>${STAT_ORDER.filter((k) => sc[k]).map((k) => sc[k] + ' ' + lab(X['s_' + k])).join(' · ')}</small></span><span class="cv">${open ? '⌃' : '⌄'}</span></button>
      ${open ? `<div class="card rh-list">${rs.map((r) => rowHTML(r)).join('')}</div>` : ''}</div>`;
  });
  if (orph.length) {
    const open = CT.open.has('s_x') || !!(CT.sec || CT.st || CT.area);
    h += `<div class="rh-sec"><button class="rh-sec-h" data-act="rh_sec_toggle" data-v="s_x" aria-expanded="${open}"><span class="nm"><b>8–14. ${esc(lab(L('অডিট বাকি (১০৫–১৯৩)', 'Not audited yet (105–193)', 'Audit বাকি (105–193)')))}</b><small>${orph.length} ${esc(T('counts'))}</small></span><span class="cv">${open ? '⌃' : '⌄'}</span></button>
      ${open ? `<p class="muted">${esc(T('unaudited_note'))}</p><div class="card rh-list">${orph.slice(0, CT.shown.x || 15).map((r) => rowHTML(r)).join('')}</div>${orph.length > (CT.shown.x || 15) ? `<button class="full" data-act="rh_more_x">${esc(T('more'))} (${orph.length - (CT.shown.x || 15)})</button>` : ''}` : ''}</div>`;
  }
  return h;
}
function filtersHTML(reg) {
  const sel = (id, label, opts, val) => `<label class="rh-f"><span class="muted">${esc(label)}</span><select id="${id}" aria-label="${esc(label)}"><option value="">${esc(T('all'))}</option>${opts.map(([v, t]) => `<option value="${esc(v)}" ${v === val ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>`;
  return `<div class="rh-filters">${sel('rh_fs', T('f_section'), reg.sections.filter((s) => s.count).map((s) => [String(s.no), s.no + '. ' + pick(s.name)]).concat([['x', lab(L('অডিট বাকি', 'Not audited', 'Audit বাকি'))]]), CT.sec)}
    ${sel('rh_ft', T('f_status'), STAT_ORDER.map((k) => [k, lab(X['s_' + k])]), CT.st)}
    ${sel('rh_fa', T('f_area'), Object.entries(reg.areas || {}).map(([k, v]) => [k, v]), CT.area)}</div>`;
}
const countsHTML = (reg) => `<div class="rh-counts">${STAT_ORDER.map((k) => `<button class="chip ${{ implemented: 'ok', incomplete: 'warn', unavailable: 'bad', unverified: 'info', unaudited: '' }[k]}" data-act="rh_stat" data-v="${k}" aria-pressed="${CT.st === k}">${esc(lab(X['s_' + k]))} ${reg.status_counts[k] || 0}</button>`).join('')}</div>`;

// ---------- hub home ----------
const TOOLS = [['day', 't_day', 't_day_s', '📅'], ['entity', 't_ent', 't_ent_s', '🔎'], ['compare', 't_cmp', 't_cmp_s', '⇄'], ['spend', 't_spend', 't_spend_s', '৳'], ['trail', 't_trail', 't_trail_s', '🧾']];
async function loadMine() { const r = await R.rpc('rpt_hub_my'); if (r.data) { CT.my = { fav: r.data.fav || [], recent: r.data.recent || [], view: r.data.view || [], pin: r.data.pin || [] }; } return !r.error; }
function mineHTML(reg) {
  const byId = new Map(reg.reports.map((r) => [r.id, r]));
  const favs = CT.my.fav.map((f) => byId.get(f.key)).filter(Boolean), rec = CT.my.recent.slice(0, 6);
  const tool = (k) => { const t = TOOLS.find((x) => x[0] === String(k).replace(/^tool:/, '')); return t ? lab(X[t[1]]) : k; };
  const recLine = (x) => { const r = byId.get(x.key); return r ? `<button class="rp-row" data-act="rh_rep_open" data-v="${esc(r.id)}"><span class="nm">#${r.no} ${esc(pick(r.name))}</span><span class="cv">›</span></button>`
    : `<button class="rp-row" data-act="rh_open_tool" data-v="${esc(String(x.key).replace(/^tool:/, ''))}" data-p="${esc(JSON.stringify(x.params || {}))}"><span class="nm">${esc(tool(x.key))}</span><span class="cv">›</span></button>`; };
  const viewLine = (v) => `<div class="row between rh-vrow"><button class="rp-row" data-act="rh_open_tool" data-v="${esc(String(v.key).replace(/^tool:/, ''))}" data-p="${esc(JSON.stringify(v.params || {}))}"><span class="nm">${esc(v.name || tool(v.key))}<small>${esc(tool(v.key))}</small></span><span class="cv">›</span></button>
    <span class="row"><button class="rh-mini" data-act="rh_pin" data-id="${v.id}" data-pinned="${CT.my.pin.some((p) => p.key === v.key && p.name === v.name) ? 1 : 0}" aria-label="${esc(T('pin'))}">${CT.my.pin.some((p) => p.key === v.key && p.name === v.name) ? '📌' : '📍'}</button><button class="rh-mini" data-act="rh_del_item" data-id="${v.id}" aria-label="${esc(T('removed'))}">✕</button></span></div>`;
  const block = (title, inner) => `<div class="hsec">${esc(title)}</div>${inner ? `<div class="card" style="padding:4px 12px">${inner}</div>` : `<p class="muted">${esc(T('none_yet'))}</p>`}`;
  return block(T('views'), CT.my.view.map(viewLine).join('')) + block(T('fav'), favs.map((r) => `<button class="rp-row" data-act="rh_rep_open" data-v="${esc(r.id)}"><span class="nm">#${r.no} ${esc(pick(r.name))}</span><span class="cv">›</span></button>`).join('')) + block(T('recent'), rec.map(recLine).join(''));
}
async function viewHome() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'reports');
  let reg;
  try { reg = await R.registry(); } catch (e) { return shell(T('title'), R.stateHTML('error', T('reg_fail'), 'rh_retry'), 'reports'); }
  const [okMine] = await Promise.all([loadMine(), (async () => { try { await (B.loadStatic ? B.loadStatic() : null); } catch (e) { /* rules fall back */ } })(), loadAllowed()]);
  CT.reg = reg;
  shell(T('title'), `<p class="muted">${esc(T('sub'))}</p>
    <div class="card stack rh-ask"><label for="rh_q"><b>${esc(T('ask_h'))}</b></label>
      <div class="row"><input id="rh_q" type="search" autocomplete="off" placeholder="${esc(T('ask_ph'))}" aria-label="${esc(T('ask_h'))}"><button class="primary" data-act="rh_ask">${esc(T('ask_go'))}</button></div>
      <p class="muted" style="margin:0">${esc(T('ask_hint'))}</p></div>
    <div class="hsec">${esc(T('tools'))}</div>
    <div class="rh-tools">${TOOLS.map(([k, t, s, ic]) => `<button class="rh-tool" data-act="rh_open_tool" data-v="${k}"><span class="ic" aria-hidden="true">${ic}</span><b>${esc(lab(X[t]))}</b><small>${esc(lab(X[s]))}</small></button>`).join('')}</div>
    <div id="rh_mine">${okMine ? mineHTML(reg) : ''}</div>
    <div class="hsec">${esc(T('cat'))}<small>${reg.total}</small></div>
    <p style="margin:0 0 8px"><button type="button" class="mini" data-act="go" data-v="reports/map">${esc(lab(L('রিপোর্ট মানচিত্র: বিভাগ ও অবস্থা', 'Reports map: sections and status', 'Report map: বিভাগ ও status')))} ›</button></p>
    ${countsHTML(reg)}
    <input id="rh_cq" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}" value="${esc(CT.q)}">
    ${filtersHTML(reg)}
    <div id="rh_cat">${catalogHTML(reg)}</div>`, 'reports');
  injectCss();
}
async function loadAllowed() {
  if (CT.allowed) return;
  try { const r = await sb.rpc('report_catalog'); if (r && Array.isArray(r.data)) { CT.allowed = new Map(r.data.map((x) => [x.key, x.allowed !== false])); try { if (B.reports2) { (await B.reports2.catalog()).forEach((x) => CT.allowed.set(x.key, x.allowed !== false)); } } catch (e) { /* engine 2 absent */ } } } catch (e) { /* every Open stays; the server decides */ }
}
const redrawCat = () => { const el = $('#rh_cat'); if (el && CT.reg) el.innerHTML = catalogHTML(CT.reg); };
const redrawMine = () => { const el = $('#rh_mine'); if (el && CT.reg) el.innerHTML = mineHTML(CT.reg); };

// ---------- actions ----------
Object.assign(H, {
  rh_retry: () => viewHome(),
  rh_ask_text: (a) => R.go('ask', { q: a.dataset.v }),
  rh_ask: () => { const q = ($('#rh_q') || {}).value || ''; if (!q.trim()) return $('#rh_q') && $('#rh_q').focus(); R.go('ask', { q: q.trim() }); },
  rh_open_tool: (a) => { let p = {}; try { p = JSON.parse(a.dataset.p || '{}'); } catch (e) { p = {}; } const k = a.dataset.v; R.go(k === 'ask' ? 'ask' : k, p); },
  rh_rep_toggle: (a) => { const id = a.dataset.v; CT.open.has(id) ? CT.open.delete(id) : CT.open.add(id); redrawCat(); },
  rh_sec_toggle: (a) => { const id = a.dataset.v; CT.open.has(id) ? CT.open.delete(id) : CT.open.add(id); redrawCat(); },
  rh_more_x: () => { CT.shown.x = (CT.shown.x || 15) + 30; redrawCat(); },
  rh_rep_open: (a) => { const r = CT.reg ? CT.reg.reports.find((x) => x.id === a.dataset.v) : null; if (r) R.openReport(r); },
  rh_stat: (a) => { CT.st = CT.st === a.dataset.v ? '' : a.dataset.v; const s = $('#rh_ft'); if (s) s.value = CT.st; redrawCat(); document.querySelectorAll('.rh-counts .chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.v === CT.st))); },
  rh_fav: async (a) => {
    const id = a.dataset.v, cur = CT.my.fav.find((f) => f.key === id);
    if (cur) { const r = await R.rpc('rpt_hub_item_remove', { p_id: cur.id }); if (r.error) return toast(r.msg); CT.my.fav = CT.my.fav.filter((f) => f.key !== id); }
    else { const r = await R.rpc('rpt_hub_item_save', { p_kind: 'fav', p_key: id, p_name: null, p_params: {} }); if (r.error) return toast(r.msg); CT.my.fav.unshift({ id: r.data, key: id }); }
    redrawCat(); redrawMine();
  },
  rh_del_item: async (a) => { const r = await R.rpc('rpt_hub_item_remove', { p_id: Number(a.dataset.id) }); if (r.error) return toast(r.msg); await loadMine(); redrawMine(); toast(T('removed')); },
  rh_pin: async (a) => {
    const v = CT.my.view.find((x) => String(x.id) === a.dataset.id); if (!v) return;
    if (a.dataset.pinned === '1') { const p = CT.my.pin.find((x) => x.key === v.key && x.name === v.name); if (p) await R.rpc('rpt_hub_item_remove', { p_id: p.id }); }
    else await R.rpc('rpt_hub_item_save', { p_kind: 'pin', p_key: v.key, p_name: v.name, p_params: v.params || {} });
    await loadMine(); redrawMine();
  },
  rh_save_view: (a) => { const fn = R.currentParams; return R.saveView(a.dataset.k, fn ? fn() : {}); },
});
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'rh_cq') { CT.q = e.target.value; redrawCat(); } });
document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target && e.target.id === 'rh_q') { e.preventDefault(); H.rh_ask(); } });
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !id.startsWith('rh_f')) return;
  if (id === 'rh_fs') CT.sec = e.target.value; else if (id === 'rh_ft') { CT.st = e.target.value; document.querySelectorAll('.rh-counts .chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.v === CT.st))); } else if (id === 'rh_fa') CT.area = e.target.value; else return;
  redrawCat();
});

// ---------- style (phone first; tokens of the app, no colours of its own) ----------
function injectCss() {
  if (document.getElementById('rh_css')) return;
  const s = document.createElement('style'); s.id = 'rh_css';
  s.textContent = `
.rh-ask input[type=search]{flex:1;min-width:0}.rh-ask .row{gap:8px;flex-wrap:nowrap}
.rh-tools{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:6px}.rh-tool{display:flex;flex-direction:column;align-items:flex-start;gap:2px;text-align:start;min-height:84px;padding:10px 12px;border-radius:14px;border:1px solid var(--line,#0002);background:var(--card)}
.rh-tool .ic{font-size:1.3rem}.rh-tool small{color:var(--muted);font-size:.8rem;line-height:1.3}
.rh-counts{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0 8px}.rh-counts .chip{cursor:pointer;min-height:32px}.rh-counts .chip[aria-pressed=true]{outline:2px solid currentColor}
.rh-filters{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;margin:8px 0}.rh-f{display:flex;flex-direction:column;gap:2px;font-size:.8rem;min-width:0}.rh-f select{min-width:0;width:100%}
.rh-sec{margin-bottom:6px}.rh-sec-h{display:flex;width:100%;justify-content:space-between;align-items:center;gap:8px;min-height:52px;padding:8px 12px;border-radius:12px;border:1px solid var(--line,#0002);background:var(--card);text-align:start}
.rh-sec-h .nm,.rh-rep-t .nm{display:flex;flex-direction:column;min-width:0}.rh-sec-h small,.rh-rep-t small{color:var(--muted);font-size:.8rem;line-height:1.35;font-weight:500}
.rh-list{padding:2px 10px}.rh-rep{padding:8px 0;border-bottom:1px solid var(--hair,#0001)}.rh-rep:last-child{border-bottom:0}
.rh-rep-h{display:flex;gap:8px;align-items:flex-start;justify-content:space-between}.rh-rep-t{display:flex;gap:8px;text-align:start;background:none;border:0;padding:0;min-height:44px;flex:1;min-width:0}
.rh-no{color:var(--muted);font-size:.8rem;min-width:30px;padding-top:2px}.rh-rep-s{flex:none}.rh-rep-a{display:flex;gap:8px;align-items:center;justify-content:flex-end;margin-top:4px}
.rh-star{min-width:44px;min-height:44px;font-size:1.25rem;background:none;border:0}.rh-star.on{color:var(--gold,#c8962c)}
.rh-dl{display:grid;grid-template-columns:auto 1fr;gap:2px 10px;margin:6px 0 0;font-size:.88rem}.rh-dl dt{color:var(--muted)}.rh-dl dd{margin:0;overflow-wrap:anywhere}
.rh-vrow .rp-row{flex:1}.rh-mini{min-width:40px;min-height:40px;background:none;border:0;font-size:1rem}
.rh-stamp{display:flex;flex-direction:column;gap:4px;margin:4px 0 8px;font-size:.85rem}.rh-fl{display:flex;flex-wrap:wrap;gap:4px;align-items:center}
.rh-pager{margin:8px 0}.rh-pager button{min-height:44px}
.rh-ev{display:grid;grid-template-columns:44px 1fr auto;gap:2px 8px;align-items:start;padding:8px 0;border-bottom:1px solid var(--hair,#0001)}.rh-ev:last-child{border-bottom:0}
.rh-ev .t{color:var(--muted);font-size:.85rem;font-variant-numeric:tabular-nums}.rh-ev .b{min-width:0;overflow-wrap:anywhere}.rh-ev .b small{display:block;color:var(--muted);font-size:.82rem;line-height:1.35}
.rh-ev .a{text-align:end;font-weight:700;font-variant-numeric:tabular-nums;white-space:nowrap}.rh-ev .a.in{color:var(--ok)}.rh-ev .a.out{color:var(--bad)}.rh-ev.void .b,.rh-ev.void .a{opacity:.55;text-decoration:line-through}
.rh-ev .x{grid-column:2 / 4;display:flex;gap:8px;flex-wrap:wrap}.rh-ev .x button{min-height:36px;padding:0 10px;font-size:.85rem}
.rh-tot{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin:8px 0}.rh-tot button{display:flex;flex-direction:column;align-items:flex-start;text-align:start;min-height:58px;padding:8px 10px;border-radius:12px;border:1px solid var(--line,#0002);background:var(--card)}
.rh-tot small{color:var(--muted);font-size:.78rem}.rh-tot b{font-size:1.05rem;font-variant-numeric:tabular-nums}
.rh-kinds{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}.rh-kinds .chip{cursor:pointer;min-height:32px}.rh-kinds .chip[aria-pressed=true]{outline:2px solid currentColor}
.rh-chips{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0}.rh-chip{display:inline-flex;gap:4px;align-items:center;min-height:40px;padding:0 12px;border-radius:20px;border:1px solid var(--line,#0003);background:var(--card);font-size:.92rem;text-align:start}
.rh-chip.missing,.rh-chip.ambiguous{border-color:var(--warn);color:var(--warn)}.rh-chip.any{color:var(--muted)}.rh-chip small{color:var(--muted)}
.rh-bar{height:8px;border-radius:4px;background:var(--hair,#0002);overflow:hidden}.rh-bar i{display:block;height:100%;background:var(--ruby,#9c1c2c)}
.rh-mrow{display:grid;grid-template-columns:62px 1fr auto;gap:8px;align-items:center;padding:4px 0}
.rh-cmp{width:100%;border-collapse:collapse;font-size:.88rem}.rh-cmp th,.rh-cmp td{padding:6px 4px;text-align:end;border-bottom:1px solid var(--hair,#0001)}.rh-cmp th:first-child,.rh-cmp td:first-child{text-align:start}
.rh-cmp td.d.up{color:var(--ok)}.rh-cmp td.d.down{color:var(--bad)}
.rh-dates{display:grid;grid-template-columns:1fr 1fr;gap:8px}.rh-dates label{display:flex;flex-direction:column;font-size:.8rem;color:var(--muted)}
.rh-sub{margin:12px 0 4px;font-weight:700}.rh-kv{display:grid;grid-template-columns:auto 1fr;gap:2px 10px;font-size:.88rem}.rh-kv dt{color:var(--muted)}.rh-kv dd{margin:0;overflow-wrap:anywhere}
.rh-tl .e{border-inline-start:3px solid var(--hair,#0003);padding:0 0 10px 10px;margin-inline-start:6px}
@media (max-width:380px){.rh-filters{grid-template-columns:1fr}.rh-tools{gap:8px}}
`;
  document.head.appendChild(s);
}
R.injectCss = injectCss;

// ---------- router: #/reports/hub[/view][?params] is served by the reports page (reports.js stays untouched) ----------
R.views.home = viewHome;
const wrap = () => {
  const pages = window.BOS_PAGES = window.BOS_PAGES || {}, orig = pages.reports;
  if (orig && orig.__rhub) return;
  const fn = function () {
    const p = R.parts(), h = location.hash.replace(/^#\/?/, '').split('?')[0].split('/');
    if (h[0] === 'reports' && h[1] === 'hub') { injectCss(); const v = R.views[p.view] || R.views.home; return v(p.params); }
    const out = orig ? orig.apply(this, arguments) : null;
    banner();
    return out;
  };
  fn.__rhub = true; pages.reports = fn;
};
// the old reports list gets one card at the top that leads to the hub (nothing in reports.js changes)
function banner() {
  let tries = 0;
  const put = () => {
    const q = $('#rp_q'); if (!q && ++tries < 25) return setTimeout(put, 100);
    if ($('#rh_banner')) return; injectCss();
    const d = document.createElement('div'); d.id = 'rh_banner'; d.className = 'card stack';
    d.innerHTML = `<div class="row between"><div><b>${esc(T('title'))}</b><div class="muted">${esc(T('sub'))}</div></div><button class="primary" data-act="go" data-v="reports/hub">${esc(T('open'))}</button></div>`;
    if (q) q.parentNode.insertBefore(d, q);
    else { const hd = $('#app header.top'); if (hd) { let at = hd; if (hd.nextElementSibling && hd.nextElementSibling.classList.contains('crumb')) at = hd.nextElementSibling; at.insertAdjacentElement('afterend', d); } }   // the report engine is not installed: the card still shows
  };
  put();
}
wrap();
B.reportLinks = B.reportLinks || [];
if (!B.reportLinks.some((l) => l.key === 'rpthub')) B.reportLinks.push({ key: 'rpthub', route: 'reports/hub', label: () => T('title'), allowed: true });
R.currentParams = null;
})();
