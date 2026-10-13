/* Islamia BOS · Day book (#/daybook): cash / bank / mobile money in and out by day, per location or all together.
   Built by the server (phase13.sql day_book) from real rows only: POS payments, due collections, expense vouchers 10-2, supplier / bill payments,
   cash handover slips 10-1 and (for people who may see salaries) staff advances 02-3 and salary payments 02-2.
   Opening / closing = running total from the owner's start date; no start date = movements only ("Data needed").
   The screen only guides and formats; it never computes money the server did not return, except the per-mode view of a day (a filter). Loaded after purchase.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const signed = (dir, n) => (dir === 'in' ? '+' : '−') + ' ' + money(n);
const LOCK = '<svg viewBox="0 0 32 32" aria-hidden="true" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';
const DOTS = '<svg viewBox="0 0 32 32" aria-hidden="true" width="20" height="20" fill="currentColor"><circle cx="16" cy="7" r="2.6"/><circle cx="16" cy="16" r="2.6"/><circle cx="16" cy="25" r="2.6"/></svg>';
const noperm = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* rules not loaded */ } return m === 'hide' ? 'hide' : 'lock'; };
const owner = () => !!(S.ctx && S.ctx.is_owner);

// ---------- labels (3 modes) ----------
const X = {
  title: L('দিনের খাতা', 'Day book', 'Day book'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), close: L('বন্ধ', 'Close', 'Close'), done: L('হয়েছে', 'Done', 'Done'),
  location: L('জায়গা', 'Location', 'Location'), allLoc: L('সব জায়গা', 'All locations', 'সব Location'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'),
  today: L('আজ', 'Today', 'Today'), d7: L('৭ দিন', '7 days', '7 days'), month: L('এই মাস', 'This month', 'This month'),
  all: L('সব', 'All', 'All'), cash: L('নগদ', 'Cash', 'Cash'), bank: L('ব্যাংক', 'Bank', 'Bank'), mobile: L('মোবাইল', 'Mobile', 'Mobile'),
  open: L('শুরুর জের', 'Opening', 'Opening'), in: L('জমা (ইন)', 'Money in', 'Money in'), out: L('খরচ (আউট)', 'Money out', 'Money out'), close_: L('শেষ জের', 'Closing', 'Closing'),
  need: L('তথ্য দরকার', 'Data needed', 'Data দরকার'), needStart: L('শুরুর তারিখ বসানো নেই, তাই শুরু ও শেষ জের দেখানো যাচ্ছে না — শুধু লেনদেন। (মালিক ⋮ মেনু → সেটিংস থেকে বসাবেন)',
    'No start date is set, so opening and closing balances are not shown — movements only. (The owner sets it in ⋮ → Settings.)', 'Start date বসানো নেই, তাই opening/closing দেখানো যাচ্ছে না — শুধু movement। (Owner ⋮ → Settings থেকে বসাবেন)'),
  startNote: L('জের গোনা হয় শুরুর তারিখ থেকে (', 'Running totals count from ', 'Running total শুরু '), none: L('এই সময়ে কোনো লেনদেন নেই', 'No movements in this period', 'এই সময়ে কোনো movement নেই'),
  lines: L('টি লাইন', 'lines', 'lines'), net: L('নিট', 'Net', 'Net'), total: L('মোট', 'Total', 'Total'), ref: L('রেফারেন্স', 'Reference', 'Reference'),
  salHidden: L('বেতন সংক্রান্ত লাইন (অ্যাডভান্স, বেতন) আপনার অনুমতি না থাকায় এখানে নেই', 'Salary lines (advances, salary payments) are left out because you may not see salaries', 'Salary-র লাইন (advance, salary) আপনার permission না থাকায় এখানে নেই'),
  notes: L('কী কীভাবে গোনা হয়', 'How this is counted', 'কী কীভাবে গোনা হয়'),
  n_card_as_bank: L('কার্ডের টাকা ব্যাংকে ধরা হয়', 'Card payments are counted as bank', 'Card-এর টাকা Bank-এ ধরা হয়'),
  n_imprest_in_cash: L('নগদ = বিক্রির নগদ + ইমপ্রেস্টের খরচ একসাথে (আলাদা ড্রয়ার/ইমপ্রেস্ট হিসাব নেই)', 'Cash = sales cash and imprest spending together (no separate drawer / imprest books)', 'Cash = sales cash + imprest খরচ একসাথে'),
  n_bank_deposit_not_dated: L('ব্যাংকে জমা (10-3) তারিখ ধরে নেই বলে এখানে আসেনি', 'Bank deposits (10-3) are not dated per day, so they are not included', 'Bank deposit (10-3) দিনের তারিখে নেই, তাই আসেনি'),
  n_hub_receipt_not_recorded: L('হাবে ক্যাশ হ্যান্ডওভারের গ্রহণ কোন লোকেশনে — তা লেখা থাকে না; সব-জায়গা দেখলে হ্যান্ডওভার বাদ থাকে', 'The hub side of a cash handover has no location on record; the all-locations view leaves handovers out', 'Hub-এ handover কোন location-এ তা লেখা থাকে না; সব-location দেখলে handover বাদ'),
  n_drafts_excluded: L('খসড়া ও বাতিল ফর্ম ধরা হয় না; বাতিল পেমেন্টও না', 'Drafts, rejected forms and voided payments are not counted', 'Draft, rejected form, void payment ধরা হয় না'),
  menu: L('আরও', 'More', 'More'), csv: L('CSV এক্সপোর্ট', 'Export CSV', 'CSV Export'), print: L('প্রিন্ট / PDF', 'Print / PDF', 'Print / PDF'), settings: L('সেটিংস', 'Settings', 'Settings'),
  refresh: L('নতুন করে আনুন', 'Refresh', 'Refresh'), openSrc: L('মূল রেকর্ড খুলুন', 'Open source record', 'মূল record খুলুন'), copyRef: L('রেফারেন্স কপি', 'Copy reference', 'Reference copy'),
  copied: L('কপি হয়েছে', 'Copied', 'Copied'), noRef: L('রেফারেন্স নেই', 'No reference', 'Reference নেই'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export-এর permission নেই'),
  expDone: L('ফাইল তৈরি হয়েছে', 'File created', 'File তৈরি হয়েছে'), dayCsv: L('এই দিনের CSV', 'CSV of this day', 'এই দিনের CSV'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), lockedPage: L('দিনের খাতা দেখার অনুমতি নেই — মালিক আপনাকে "দিনের খাতা দেখা" অনুমতি দিতে পারেন', 'You may not see the day book — the owner can give you the "See the day book" permission', 'Day book দেখার permission নেই — Owner "Day book দেখা" permission দিতে পারেন'),
  off: L('দিনের খাতা বন্ধ করা আছে (মালিকই শুধু দেখতে পারেন)', 'The day book is switched off (only the owner can open it)', 'Day book বন্ধ করা আছে (শুধু Owner দেখতে পারেন)'),
  sqlMissing: L('দিনের খাতার ডেটাবেস অংশ এখনও চালু হয়নি (phase13)', 'The day book database part is not installed yet (phase13)', 'Day book-এর database অংশ এখনও চালু হয়নি (phase13)'),
  bad_range: L('তারিখের সীমা ঠিক নয় (সর্বোচ্চ ৩৬৬ দিন)', 'Date range is not valid (366 days at most)', 'Date range ঠিক নয় (সর্বোচ্চ ৩৬৬ দিন)'), bad_date: L('তারিখ ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'),
  enabled: L('দিনের খাতা চালু', 'Day book is on', 'Day book চালু'), enabledHint: L('বন্ধ করলে মালিক ছাড়া কেউ খুলতে পারবে না। অন্যদের জন্য "Who may do what"-এ অনুমতি লাগে।', 'When off only the owner can open it. Others need the permission in Who may do what.', 'বন্ধ করলে Owner ছাড়া কেউ খুলতে পারবে না। অন্যদের জন্য permission লাগে।'),
  startLbl: L('শুরুর তারিখ (YYYY-MM-DD)', 'Start date (YYYY-MM-DD)', 'Start date (YYYY-MM-DD)'), save: L('সংরক্ষণ', 'Save', 'Save'), clear: L('তারিখ মুছুন', 'Clear date', 'Date মুছুন'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  on: L('চালু', 'On', 'On'), off_: L('বন্ধ', 'Off', 'Off'), by: L('কে', 'By', 'By'), at: L('সময়', 'Time', 'Time'), period: L('সময়', 'Period', 'Period'),
  sum: L('সারাংশ', 'Summary', 'Summary'), internal: L('অভ্যন্তরীণ (হিসাবে ধরা হয়নি)', 'Internal (not in totals)', 'Internal (total-এ নেই)'),
  netOpen: L('শুরু থেকে নিট (শুরুতে)', 'Net since start (at day start)', 'Net since start (day start)'), netClose: L('শুরু থেকে নিট (শেষে)', 'Net since start (at day end)', 'Net since start (day end)'),
  neg: L('ঋণাত্মক', 'Negative', 'Negative'), transfers: L('অভ্যন্তরীণ ট্রান্সফার (ক্যাশ হ্যান্ডওভার)', 'Internal transfers (cash handover)', 'Internal transfer (cash handover)'),
  trNote: L('সব-জায়গার যোগফলে ধরা হয় না; এক জায়গার দেখায় নগদ আউট ধরা হয়', 'Not in the all-locations totals; counted as cash out in a single-location view', 'সব-location total-এ ধরা হয় না; এক location-এ cash out'),
  skipped: L('টি লাইনের টাকার অঙ্ক পড়া যায়নি (বাদ গেছে)', 'lines could not be read (left out)', 'lines পড়া যায়নি (বাদ গেছে)'),
  startAfter: L('শুরুর তারিখ এই সময়ের পরে — তাই কোনো জের নেই, শুধু লেনদেন', 'The start date is after this period — no balances, movements only', 'Start date এই period-এর পরে — কোনো জের নেই, শুধু movement'),
  straddle: L('শুরুর তারিখ এই সময়ের মাঝখানে — তার আগের দিনগুলোতে জের নেই', 'The start date falls inside this period — days before it have no balances', 'Start date period-এর মাঝে — তার আগের দিনে জের নেই'),
  netOnly: L('জের গোনা হয় শুরুর তারিখ থেকে (নিট) — শুরুর নগদ/ব্যাংক/মোবাইল জের বসানো নেই, তাই "শুরু/শেষ জের" নয়, "শুরু থেকে নিট"', 'Net movement counted from the start date — opening balances are not set, so this is "Net since start", not Opening/Closing', 'Start date থেকে net — opening balance বসানো নেই, তাই "Net since start"'),
  masked: L('নাম ও রেফারেন্স লুকানো আছে', 'Names and references are masked', 'নাম ও reference লুকানো'), capped: L('আজকের পরের তারিখ দেখানো হয় না', 'Dates after today are not shown', 'আজকের পরের date দেখানো হয় না'),
  scope: L('পরিধি', 'Scope', 'Scope'), wholePeriod: L('পুরো সময়', 'whole period', 'পুরো period'),
  openBal: L('শুরুর তারিখে জের (৳) — খালি = দেখানো হবে না', 'Opening balances at the start date (৳) — empty = not shown', 'Start date-এ জের (৳) — খালি = দেখানো হবে না'), balHint: L('শুধু "সব জায়গা" দেখায় ব্যবহৃত হয়; তিনটিই লাগবে', 'Used in the all-locations view only; all three are needed', 'শুধু "সব জায়গা" view-এ; তিনটিই লাগবে'),
  maskNames: L('মালিক ছাড়া অন্যদের জন্য নাম/রেফারেন্স লুকান', 'Mask names / references for non-owners', 'Owner ছাড়া অন্যদের জন্য নাম/ref লুকান'), bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount ঠিক নয়'),
  t_bank_deposit: L('ব্যাংকে জমা', 'Bank deposit', 'Bank জমা'), t_bank_withdraw: L('ব্যাংক থেকে তোলা', 'Bank withdrawal', 'Bank থেকে তোলা'), t_owner_topup: L('মালিকের টাকা ঢুকেছে', 'Owner top-up', 'Owner top-up'),
  t_owner_draw: L('মালিক টাকা নিয়েছেন', 'Owner draw', 'Owner draw'), t_cust_advance: L('গ্রাহকের অগ্রিম', 'Customer advance', 'Customer advance'), t_cust_advance_refund: L('অগ্রিম ফেরত', 'Advance refunded', 'Advance ফেরত'),
  t_hub_receipt: L('হাবে ক্যাশ গ্রহণ', 'Hub cash receipt', 'Hub cash গ্রহণ'),
  t_sale_return: L('বিক্রি ফেরতে টাকা ফেরত', 'Sale return refund', 'Sale return refund'), t_supplier_refund: L('সাপ্লায়ারের ফেরত টাকা', 'Supplier refund', 'Supplier refund'),
  n_refunds_included: L('বিক্রি ফেরতের নগদ ফেরত (আউট) ও সাপ্লায়ারের ফেরত টাকা (ইন) ধরা হয় (phase12 থাকলে)', 'Customer refunds paid (out) and supplier refunds received (in) are included when phase12 is installed', 'Customer refund (out) ও supplier refund (in) ধরা হয় (phase12 থাকলে)'),
  n_future_dates_capped: L('আজকের পরের তারিখের লেনদেন ধরা হয় না', 'Movements dated after today are not counted', 'আজকের পরের date-এর movement ধরা হয় না'),
  t_sale: L('বিক্রি', 'Sale', 'Sale'), t_collection: L('বাকি আদায়', 'Due collected', 'Due আদায়'), t_supplier: L('সাপ্লায়ারকে', 'Supplier paid', 'Supplier-কে'), t_bill: L('ক্রয় বিলের টাকা', 'Bill payment', 'Bill payment'),
  t_expense: L('খরচ ভাউচার', 'Expense voucher', 'Expense voucher'), t_handover: L('ক্যাশ হ্যান্ডওভার', 'Cash handover', 'Cash handover'), t_advance: L('স্টাফ অ্যাডভান্স', 'Staff advance', 'Staff advance'), t_salary: L('বেতন', 'Salary', 'Salary'),
};
const T = (k) => lab(X[k]);
const TYPE_TONE = { bank_deposit: 'info', bank_withdraw: 'info', owner_topup: 'ok', owner_draw: 'warn', cust_advance: 'ok', cust_advance_refund: 'warn', hub_receipt: 'info', sale_return: 'warn', supplier_refund: 'ok', sale: 'ok', collection: 'info', supplier: 'warn', bill: 'warn', expense: 'warn', handover: 'info', advance: 'warn', salary: 'warn' };
const typeLabel = (t) => (X['t_' + t] ? T('t_' + t) : t);
const modeLabel = (m) => (X[m] ? T(m) : m);

// ---------- helpers ----------
const todayS = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const monthStart = () => todayS().slice(0, 8) + '01';
const addDays = (s, n) => new Date(new Date(s + 'T12:00:00Z').getTime() + n * 86400e3).toISOString().slice(0, 10);
const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(new Date(s + 'T12:00:00Z').getTime());
const fd = (s) => { try { return new Date(s + 'T12:00:00Z').toLocaleDateString(S.lang === 'bn' ? 'bn-BD' : 'en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }); } catch (e) { return s; } };
const ft = (iso) => { try { return new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' }); } catch (e) { return ''; } };
const LOCS = () => { const all = (B.ENV && B.ENV.locs) || []; return owner() || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const allLocs = () => owner() || (S.ctx.roles || []).includes('management') || LOCS().length > 1;
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? nm(l) : (id === null || id === undefined ? '' : '#' + id); };
const optHTML = (pairs, sel) => pairs.map(([v, l]) => `<option value="${esc(String(v))}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const missingFn = (e) => !!e && (e.code === 'PGRST202' || /could not find the function|schema cache|does not exist/i.test(e.message || ''));
const sheetBar = (title, extra = '') => `<div class="row" style="align-items:center;justify-content:space-between"><h2 style="margin:0">${title}</h2>${extra}</div>`;

let EXPOK = null;
async function canExport() {
  if (owner()) return true; if (EXPOK !== null) return EXPOK;
  try { const r = await sb.rpc('has_grant', { p_code: 'export_data' }); EXPOK = !r.error && r.data === true; } catch (e) { EXPOK = false; }
  return EXPOK;
}

// ---------- state ----------
const D = { loc: undefined, from: null, to: null, mode: '', data: null, err: null, exp: false, openDay: null, busy: 0 };

async function load() {
  const tok = ++D.busy; D.err = null;
  const r = await sb.rpc('day_book', { p_loc: D.loc === null ? null : D.loc, p_from: D.from, p_to: D.to });
  if (tok !== D.busy) return;
  if (r.error) { D.data = null; D.err = r.error; } else D.data = r.data;
}

// ---------- per-mode view of the server answer (a filter, no new maths on balances) ----------
const pick = (o, mode) => (o ? (mode ? o[mode] : o.total) : null);
const bal = () => !!(D.data && D.data.balances);
function dayView(d) {
  const m = D.mode, lines = (d.lines || []).filter((l) => !m || l.mode === m);
  const counted = lines.filter((l) => !l.internal);
  const inn = pick(d.in, m), out = pick(d.out, m);
  return { date: d.date, lines, nin: counted.filter((l) => l.dir === 'in').length, nout: counted.filter((l) => l.dir === 'out').length,
    open: pick(bal() ? d.open : d.net_open, m), close: pick(bal() ? d.close : d.net_close, m), in: inn, out, tr: Number(d.transfers || 0), has: lines.length > 0 };
}
function totalsView() {
  const t = (D.data && D.data.totals) || {}, m = D.mode;
  return { open: pick(bal() ? t.open : t.net_open, m), in: pick(t.in, m), out: pick(t.out, m), close: pick(bal() ? t.close : t.net_close, m), tr: Number(t.transfers || 0) };
}

// ---------- main view ----------
async function view() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  if (D.loc === undefined) D.loc = allLocs() ? null : (LOCS()[0] || {}).id;
  if (!D.from) { D.from = monthStart(); D.to = todayS(); }
  D.exp = await canExport();
  await load(); draw();
}
function lockCard(msg) { return `<div class="lockcard">${LOCK}<span>${esc(msg)}</span></div>`; }
function errBox(e) {
  const m = (e && e.message) || '';
  if (missingFn(e)) return `<div class="notice warn mk warn">${esc(T('sqlMissing'))}</div>`;
  if (/daybook_off/.test(m)) return lockCard(T('off'));
  if (/not allowed/.test(m)) return lockCard(T('lockedPage'));
  if (/bad_range/.test(m)) return `<div class="notice warn mk warn">${esc(T('bad_range'))}</div>`;
  return `<div class="notice warn mk warn">${esc(m || 'error')}</div>`;
}
function statCell(label, val, tone, chkNeg) {
  return `<div class="stat mk ${tone || ''}"><div class="k">${esc(label)}</div><div class="v">${val === null || val === undefined ? `<span class="chip warn">${esc(T('need'))}</span>` : esc(money(val))}${chkNeg && Number(val) < 0 ? ` <span class="chip warn neg">${esc(T('neg'))}</span>` : ''}</div></div>`;
}
function draw() {
  const locs = LOCS(), locked = !!(D.err && /not allowed|daybook_off/.test(D.err.message || ''));
  const filters = `<div class="stack">
    ${(locs.length > 1 || allLocs()) ? `<select id="db_loc" aria-label="${esc(T('location'))}">${allLocs() ? `<option value="">${esc(T('allLoc'))}</option>` : ''}${optHTML(locs.map((l) => [l.id, nm(l)]), D.loc === null ? '' : D.loc)}</select>` : ''}
    <div class="row wrap" style="align-items:end;gap:8px">
      <div style="flex:1;min-width:130px"><label for="db_from">${esc(T('from'))}</label><input type="date" id="db_from" value="${esc(D.from)}"></div>
      <div style="flex:1;min-width:130px"><label for="db_to">${esc(T('to'))}</label><input type="date" id="db_to" value="${esc(D.to)}"></div>
    </div>
    <div class="row wrap" style="gap:6px"><button data-act="db_q" data-v="today">${esc(T('today'))}</button><button data-act="db_q" data-v="7">${esc(T('d7'))}</button><button data-act="db_q" data-v="month">${esc(T('month'))}</button>
      <button id="db_menu" data-act="db_menu" aria-label="${esc(T('menu'))}" style="margin-inline-start:auto;min-width:48px">${DOTS}</button></div>
    <div class="row wrap" role="group" style="gap:6px" data-ctl="select">${['', 'cash', 'bank', 'mobile'].map((m) => `<button class="tog ${D.mode === m ? 'on' : ''}" data-act="db_mode" data-v="${m}" aria-pressed="${D.mode === m}">${esc(m ? T(m) : T('all'))}</button>`).join('')}</div>
  </div>`;
  let body = '';
  if (D.err) body = errBox(D.err);
  else if (D.data) body = summary() + dayList() + notesBox();
  else body = `<p class="muted">${esc(T('loading'))}</p>`;
  shell(T('title'), `${locked ? '' : filters}<div id="db_body">${body}</div>`, true);
}
function startBanner() {
  const d = D.data, st = d.start;
  if (!st) return `<div class="notice warn mk warn" id="db_needstart">${esc(T('needStart'))}</div>`;
  if (st > d.to) return `<div class="notice warn mk warn" id="db_startafter">${esc(T('startAfter'))}</div>`;
  let h = '';
  if (st > d.from) h += `<p class="muted" style="font-size:.85rem" id="db_straddle">${esc(T('straddle'))}</p>`;
  h += `<p class="muted" style="font-size:.85rem" id="db_startnote">${esc(bal() ? T('startNote') + st + (S.lang === 'bn' ? ')' : '') : T('netOnly') + ' (' + st + ')')}</p>`;
  return h;
}
function summary() {
  const v = totalsView(), known = D.data.opening_known, ob = bal();
  return `<div class="stats" id="db_sum">${statCell(ob ? T('open') : T('netOpen'), known ? v.open : null, '', true)}${statCell(T('in'), v.in, 'ok')}${statCell(T('out'), v.out, 'warn')}${statCell(ob ? T('close_') : T('netClose'), known ? v.close : null, '', true)}</div>
    ${startBanner()}
    ${v.tr > 0 ? `<p class="muted" style="font-size:.85rem" id="db_tr"><span class="chip info">${esc(T('transfers'))}</span> ${esc(money(v.tr))} · ${esc(T('trNote'))}</p>` : ''}
    ${D.data.skipped_rows > 0 ? `<div class="notice warn mk warn" id="db_skipped">${esc(String(D.data.skipped_rows))} ${esc(T('skipped'))}</div>` : ''}
    ${D.data.salary_hidden ? `<p class="muted" style="font-size:.85rem" id="db_salhid">${esc(T('salHidden'))}</p>` : ''}
    ${D.data.names_masked ? `<p class="muted" style="font-size:.85rem" id="db_masked">${esc(T('masked'))}</p>` : ''}
    ${D.data.capped ? `<p class="muted" style="font-size:.85rem" id="db_capped">${esc(T('capped'))}</p>` : ''}`;
}
function dayList() {
  const days = (D.data.days || []).map(dayView).filter((d) => d.has).reverse();
  if (!days.length) return `<p class="muted center pad" id="db_empty">${esc(T('none'))}</p>`;
  return `<div class="card" style="padding:4px 12px" id="db_days">${days.map((d) => {
    const net = (d.in || 0) - (d.out || 0), tone = net < 0 ? 'warn' : 'ok';
    return `<button class="rp-row mk ${tone} db-day" data-act="db_day" data-v="${esc(d.date)}" style="display:flex;width:100%;align-items:center;gap:8px;text-align:start">
      <span class="nm" style="flex:1">${esc(fd(d.date))}<small style="display:block">${esc(T('in'))} ${esc(money(d.in))} · ${esc(T('out'))} ${esc(money(d.out))}${d.close !== null && d.close !== undefined && D.data.opening_known ? ' · ' + esc(bal() ? T('close_') : T('netClose')) + ' ' + esc(money(d.close)) : ''}</small></span>
      ${d.close < 0 && D.data.opening_known ? `<span class="chip warn neg">${esc(T('neg'))}</span>` : ''}<span class="chip ${tone}">${esc((net < 0 ? '− ' : '+ ') + money(Math.abs(net)))}</span><span class="cv">›</span></button>`;
  }).join('')}</div>`;
}
function notesBox() {
  const ns = (D.data.notes || []).filter((k) => X['n_' + k]);
  return ns.length ? `<details class="card" style="margin-top:12px"><summary><b>${esc(T('notes'))}</b></summary><ul>${ns.map((k) => `<li>${esc(T('n_' + k))}</li>`).join('')}</ul></details>` : '';
}
X.none = X.none || L('এই সময়ে কোনো লেনদেন নেই', 'No movements in this period', 'কোনো movement নেই');

// ---------- day sheet ----------
function sourceRoute(l) {
  if (!l.src) return null;
  if (l.src === 'entry' && l.src_id) return '#/entry/' + l.src_id;
  if (l.src === 'bill' && l.src_id) return '#/purchase/' + l.src_id;
  if (l.src === 'supplier') return '#/payables';
  if (l.src === 'customer') return '#/dues';
  return null;     // a POS sale has no page of its own; the receipt number is the reference
}
function lineRow(l, i) {
  const tone = l.internal ? 'info' : (l.dir === 'in' ? 'ok' : 'warn');
  return `<div class="db-line" data-i="${i}"><div class="rp-row mk ${tone}" style="display:flex;align-items:center;gap:8px;min-height:56px">
    <span class="nm" style="flex:1"><span class="chip ${TYPE_TONE[l.type] || ''}">${esc(typeLabel(l.type))}</span> <span class="chip">${esc(modeLabel(l.mode))}</span>${D.loc === null ? ` <span class="chip">${esc(locName(l.loc))}</span>` : ''}
      <small style="display:block">${esc([l.ref, l.text, l.who, ft(l.at)].filter(Boolean).join(' · '))}${l.internal ? ' · ' + esc(T('internal')) : ''}</small></span>
    <b class="${l.dir === 'in' ? 'amt-ok' : ''}" style="white-space:nowrap">${esc(signed(l.dir, l.amount))}</b>
    <button class="rp-x" style="color:inherit" data-act="db_lmenu" data-i="${i}" aria-label="${esc(T('menu'))}">${DOTS}</button></div>
    <div class="db-lm" hidden style="display:none;gap:6px;padding:4px 0 8px"></div></div>`;
}
function daySheet(date) {
  const d = (D.data.days || []).find((x) => x.date === date); if (!d) return;
  const v = dayView(d); D.openDay = date; D.shown = v.lines;
  openSheet(`${sheetBar(esc(fd(date)), `<button data-act="db_dmenu" aria-label="${esc(T('menu'))}" style="min-width:48px">${DOTS}</button>`)}
    <div class="stats" style="margin:8px 0">${statCell(bal() ? T('open') : T('netOpen'), D.data.opening_known ? v.open : null, '', true)}${statCell(T('in'), v.in, 'ok')}${statCell(T('out'), v.out, 'warn')}${statCell(bal() ? T('close_') : T('netClose'), D.data.opening_known ? v.close : null, '', true)}</div>
    ${v.tr > 0 ? `<p class="muted" style="font-size:.85rem"><span class="chip info">${esc(T('transfers'))}</span> ${esc(money(v.tr))}</p>` : ''}
    <div class="card" style="padding:4px 12px" id="db_lines">${v.lines.map(lineRow).join('')}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
function lineMenu(a) {
  const i = Number(a.dataset.i), l = (D.shown || [])[i]; const box = a.closest('.db-line').querySelector('.db-lm'); if (!l || !box) return;
  if (!box.hidden) { box.hidden = true; box.style.display = 'none'; return; }
  document.querySelectorAll('.db-lm').forEach((x) => { x.hidden = true; x.style.display = 'none'; });
  const route = sourceRoute(l);
  box.innerHTML = `<button ${route ? `data-act="db_src" data-i="${i}"` : 'disabled'}>${esc(T('openSrc'))}</button><button ${l.ref ? `data-act="db_copy" data-i="${i}"` : 'disabled'}>${esc(l.ref ? T('copyRef') : T('noRef'))}</button>`;
  box.hidden = false; box.style.display = 'flex';
}

// ---------- export ----------
const csvCell = (v) => {
  if (v === null || v === undefined) return '';
  let s = String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && /[^\d.\-]/.test(s))) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
function exportRows(dates) {
  const rows = [];
  (D.data.days || []).forEach((d) => { if (dates && !dates.includes(d.date)) return;
    (d.lines || []).filter((l) => !D.mode || l.mode === D.mode).forEach((l) => rows.push({ date: d.date, ...l })); });
  return rows;
}
function scopeTotals(dates) {
  if (!dates) return Object.assign({}, totalsView(), { label: T('wholePeriod') });
  const ds = (D.data.days || []).filter((d) => dates.includes(d.date)).sort((a, z) => (a.date < z.date ? -1 : 1)), m = D.mode, f = ds[0], l = ds[ds.length - 1];
  const sum = (k) => ds.reduce((a, d) => a + Number(pick(d[k], m) || 0), 0);
  return { in: sum('in'), out: sum('out'), open: f ? pick(bal() ? f.open : f.net_open, m) : null, close: l ? pick(bal() ? l.close : l.net_close, m) : null, tr: ds.reduce((a, d) => a + Number(d.transfers || 0), 0), label: dates.join(', ') };
}
function buildCSV(rows, dates) {
  const head = ['date', 'location', 'direction', 'mode', 'type', 'amount', 'reference', 'details', 'by', 'time', 'internal'];
  const out = [head.join(',')];
  rows.forEach((r) => out.push([r.date, locName(r.loc), r.dir, r.mode, r.type, Number(r.amount), r.ref, r.text, r.who, r.at ? new Date(r.at).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) : '', r.internal ? 'yes' : ''].map(csvCell).join(',')));
  const p = (S.ctx && S.ctx.profile) || {}, tv = scopeTotals(dates), ob = bal();
  out.push('');
  [[T('title')], [T('period'), D.from + ' - ' + D.to], [T('location'), D.loc === null ? T('allLoc') : locName(D.loc)], [T('cash') + '/' + T('bank') + '/' + T('mobile'), D.mode ? T(D.mode) : T('all')],
    [T('scope'), tv.label], [T('in'), tv.in], [T('out'), tv.out], [T('transfers'), tv.tr], [ob ? T('open') : T('netOpen'), D.data.opening_known && tv.open !== null ? tv.open : T('need')], [ob ? T('close_') : T('netClose'), D.data.opening_known && tv.close !== null ? tv.close : T('need')],
    [T('by'), p.full_name || p.staff_id || ''], [T('at'), new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)']].forEach((m) => out.push(m.map(csvCell).join(',')));
  return '﻿' + out.join('\r\n') + '\r\n';
}
function download(name, text, type) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
// the server check comes FIRST (needs the owner or export_data); only then is the file built
async function auditExport(kind, n) {
  const r = await sb.rpc('log_page_export', { p_key: 'daybook', p_kind: kind, p_filters: { loc: D.loc, from: D.from, to: D.to, mode: D.mode || null }, p_rows: n });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : (r.error.message || 'error')); return false; }
  return true;
}
async function doCSV(dates) {
  if (!D.data) return; const rows = exportRows(dates);
  if (!(await auditExport('csv', rows.length))) return;
  download(`daybook-${D.from}${D.to !== D.from ? '_' + D.to : ''}${dates ? '-day' : ''}.csv`, buildCSV(rows, dates), 'text/csv;charset=utf-8'); toast(T('expDone'));
}
async function doPrint(dates) {
  if (!D.data) return; const rows = exportRows(dates);
  if (!(await auditExport('print', rows.length))) return;
  const old = $('#rp_print'); if (old) old.remove();
  const tv = scopeTotals(dates), ob = bal(), d = document.createElement('div'); d.id = 'rp_print';
  d.innerHTML = `<h1>${esc(T('title'))}</h1><p class="pm">${esc(D.from + ' – ' + D.to)} · ${esc(D.loc === null ? T('allLoc') : locName(D.loc))} · ${esc(D.mode ? T(D.mode) : T('all'))}
    · ${esc(T('scope'))}: ${esc(tv.label)} · ${esc(T('in'))} ${esc(money(tv.in))} · ${esc(T('out'))} ${esc(money(tv.out))}${D.data.opening_known && tv.open !== null ? ' · ' + esc(ob ? T('open') : T('netOpen')) + ' ' + esc(money(tv.open)) + ' · ' + esc(ob ? T('close_') : T('netClose')) + ' ' + esc(money(tv.close)) : ''}</p>
    <table><thead><tr><th>${esc(T('period'))}</th><th>${esc(T('location'))}</th><th></th><th></th><th>${esc(T('ref'))}</th><th class="n">${esc(T('total'))}</th></tr></thead>
    <tbody>${rows.map((r) => `<tr><td>${esc(r.date)}</td><td>${esc(locName(r.loc))}</td><td>${esc(typeLabel(r.type))}</td><td>${esc(modeLabel(r.mode))}</td><td>${esc([r.ref, r.text].filter(Boolean).join(' · '))}${r.internal ? ' (' + esc(T('internal')) + ')' : ''}</td><td class="n">${esc(signed(r.dir, r.amount))}</td></tr>`).join('')}</tbody></table>`;
  document.body.appendChild(d);
  const clean = () => { const e = $('#rp_print'); if (e) e.remove(); window.removeEventListener('afterprint', clean); };
  window.addEventListener('afterprint', clean);
  setTimeout(() => { try { window.print(); } catch (e) { clean(); } }, 80);
}

// ---------- menus & settings ----------
function menuBtn(act, label, enabled, lockTxt) {
  if (enabled) return `<button class="full" data-act="${act}">${esc(label)}</button>`;
  return noperm() === 'lock' ? `<button class="full" disabled aria-label="${esc(label + ' · ' + lockTxt)}">${LOCK} ${esc(label)}</button>` : '';
}
function pageMenu() {
  openSheet(`<h2 style="margin-top:0">${esc(T('title'))}</h2><div class="stack">
    ${menuBtn('db_csv', T('csv'), D.exp && !!D.data, T('expLock'))}${menuBtn('db_print', T('print'), D.exp && !!D.data, T('expLock'))}
    <button class="full" data-act="db_refresh">${esc(T('refresh'))}</button>
    ${owner() ? `<button class="full" data-act="db_settings">${esc(T('settings'))}</button>` : ''}
    <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}
function dayMenu() {
  openSheet(`<h2 style="margin-top:0">${esc(fd(D.openDay))}</h2><div class="stack">
    ${menuBtn('db_csv_day', T('dayCsv'), D.exp, T('expLock'))}${menuBtn('db_print_day', T('print'), D.exp, T('expLock'))}
    <button class="full" data-act="db_backday">${esc(T('close'))}</button></div>`);
}
async function settingsSheet() {
  if (!owner()) return;
  const on = D.data ? D.data.enabled !== false : true, st = (D.data && D.data.start) || '', maskOn = D.mask !== undefined ? D.mask : (ruleVal('daybook_mask_names') === 'true');
  openSheet(`<h2 style="margin-top:0">${esc(T('settings'))}</h2><div class="stack">
    <div class="card stack"><b>${esc(T('enabled'))}</b><small class="muted">${esc(T('enabledHint'))}</small>
      <div class="row wrap"><button class="tog ${on ? 'on' : ''}" id="db_en" data-act="db_en" data-v="1" aria-pressed="${on}">${esc(T('on'))}</button><button class="tog ${on ? '' : 'on'}" data-act="db_en" data-v="0" aria-pressed="${!on}">${esc(T('off_'))}</button></div></div>
    <div class="card stack"><label for="db_st">${esc(T('startLbl'))}</label><input id="db_st" inputmode="numeric" autocomplete="off" value="${esc(st)}" placeholder="2026-10-01">
      <div class="row"><button class="primary full" data-act="db_st_save">${esc(T('save'))}</button><button class="full" data-act="db_st_clear">${esc(T('clear'))}</button></div></div>
    <div class="card stack"><b>${esc(T('openBal'))}</b><small class="muted">${esc(T('balHint'))}</small>
      ${['cash', 'bank', 'mobile'].map((k) => `<label for="db_ob_${k}">${esc(T(k))}</label><input id="db_ob_${k}" inputmode="decimal" autocomplete="off" value="${esc(ruleVal('daybook_open_' + k))}">`).join('')}
      <button class="primary full" data-act="db_ob_save">${esc(T('save'))}</button></div>
    <div class="card stack"><b>${esc(T('maskNames'))}</b><div class="row wrap"><button class="tog ${maskOn ? 'on' : ''}" data-act="db_mask" data-v="1" aria-pressed="${maskOn}">${esc(T('on'))}</button><button class="tog ${maskOn ? '' : 'on'}" data-act="db_mask" data-v="0" aria-pressed="${!maskOn}">${esc(T('off_'))}</button></div></div>
    <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}
const ruleVal = (k) => { try { const v = B.rule(k, null); return v === null || v === undefined ? '' : String(v); } catch (e) { return ''; } };

Object.assign(H, {
  db_q: async (a) => { const v = a.dataset.v; D.to = todayS(); D.from = v === 'today' ? D.to : v === '7' ? addDays(D.to, -6) : monthStart(); await reload(); },
  db_mode: (a) => { D.mode = a.dataset.v || ''; draw(); },
  db_day: (a) => daySheet(a.dataset.v),
  db_lmenu: lineMenu,
  db_src: (a) => { const l = (D.shown || [])[Number(a.dataset.i)], r = l && sourceRoute(l); if (r) { closeSheet(); location.hash = r; } },
  db_copy: async (a) => { const l = (D.shown || [])[Number(a.dataset.i)]; if (!l || !l.ref) return toast(T('noRef'));
    try { await navigator.clipboard.writeText(String(l.ref)); toast(T('copied')); } catch (e) { toast(String(l.ref)); } },
  db_menu: pageMenu, db_dmenu: dayMenu, db_backday: () => daySheet(D.openDay),
  db_csv: () => { closeSheet(); return doCSV(null); }, db_print: () => { closeSheet(); return doPrint(null); },
  db_csv_day: () => { const d = D.openDay; closeSheet(); return doCSV([d]); }, db_print_day: () => { const d = D.openDay; closeSheet(); return doPrint([d]); },
  db_refresh: async () => { closeSheet(); await reload(); },
  db_settings: settingsSheet,
  db_en: async (a) => { const r = await sb.rpc('set_rule', { p_key: 'daybook_enabled', p_value: a.dataset.v === '1' }); if (r.error) return fail(r.error); toast(T('saved')); if (D.data) D.data.enabled = a.dataset.v === '1'; settingsSheet(); },
  db_st_save: async () => { const v = norm($('#db_st').value); if (!isDate(v)) return toast(T('bad_date'));
    const r = await sb.rpc('set_daybook_start', { p_date: v }); if (r.error) return /bad_date/.test(r.error.message || '') ? toast(T('bad_date')) : fail(r.error); toast(T('saved')); closeSheet(); await reload(); },
  db_mask: async (a) => { const r = await sb.rpc('set_rule', { p_key: 'daybook_mask_names', p_value: a.dataset.v === '1' }); if (r.error) return fail(r.error); D.mask = a.dataset.v === '1'; toast(T('saved')); settingsSheet(); },
  db_ob_save: async () => {
    const v = (k) => { const x = norm($('#db_ob_' + k).value).replace(/,/g, ''); if (x === '') return null; const n = Number(x); return Number.isFinite(n) ? n : NaN; };
    const c = v('cash'), b = v('bank'), m = v('mobile'); if ([c, b, m].some((x) => Number.isNaN(x))) return toast(T('bad_amount'));
    const r = await sb.rpc('set_daybook_opening', { p_cash: c, p_bank: b, p_mobile: m });
    if (r.error) return /bad_amount/.test(r.error.message || '') ? toast(T('bad_amount')) : fail(r.error); toast(T('saved')); closeSheet(); await reload(); },
  db_st_clear: async () => { const r = await sb.rpc('set_daybook_start', { p_date: null }); if (r.error) return fail(r.error); toast(T('saved')); closeSheet(); await reload(); },
});
async function reload() { await load(); draw(); }
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !id.startsWith('db_') || location.hash.replace(/^#\/?/, '').split('/')[0] !== 'daybook') return;
  if (id === 'db_loc') { D.loc = e.target.value === '' ? null : Number(e.target.value); reload(); }
  else if (id === 'db_from' || id === 'db_to') {
    const f = norm($('#db_from').value), t = norm($('#db_to').value);
    if (!isDate(f) || !isDate(t)) return; D.from = f; D.to = t; reload();
  }
});

// reports hub link
B.reportLinks = B.reportLinks || [];
B.reportLinks.push({ key: 'daybook', route: 'daybook', label: () => T('title'), allowed: null,
  check: async () => { const l = B.reportLinks.find((x) => x.key === 'daybook'); if (owner()) { l.allowed = true; return; }
    const locs = LOCS(); let ok = false;
    for (const x of locs) { try { const r = await sb.rpc('has_grant', { p_code: 'view_daybook', p_loc: x.id }); if (r && !r.error && r.data === true) { ok = true; break; } } catch (e) { /* no */ } }
    l.allowed = ok; } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { daybook: view });
B.daybook = { open: () => { location.hash = '#/daybook'; } };
})();
