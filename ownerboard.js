/* Islamia BOS · Owner mode board (#/owner): the owner's own "must check every day" list, made of widgets he can add, remove, reorder, rename and give limits to.
   Server: supabase/phase45.sql (owner_board_get / owner_board_save; switch rule owner_board_on). Without the table the list lives on this phone (localStorage) - never an error.
   Widget values come ONLY from data that already exists (sales_summary, customer_dues, payables_summary, stock_levels, expiry_list, needs_you_oldest, exceptions, entries, form_rollout,
   salary_report, parallel_waiting ...). A source that is not installed (or not allowed) hides its widget; it never shows an error. One batched load, again every 2 minutes while open.
   Also drawn as the owner's Home when "Owner mode" is on (nav.js calls B.ownerboard.view({ home: true })). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, store, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const REFRESH_MS = () => Number(window.__OB_REFRESH_MS) || 120000;

// ---------- texts ----------
const X = {
  title: L('মালিকের বোর্ড', 'Owner mode', 'Owner mode'), sub: L('প্রতিদিন যা দেখা জরুরি', 'What to check every day', 'প্রতিদিন যা দেখা জরুরি'),
  asof: L('হিসাব', 'As of', 'As of'), offl: L('অফলাইন — শেষ পাওয়া সংখ্যা দেখানো হচ্ছে', 'Offline - showing the last numbers', 'Offline — শেষ numbers'), refresh: L('নতুন করে দেখুন', 'Refresh', 'Refresh'),
  edit: L('বোর্ড সাজান', 'Edit board', 'Board সাজান'), done: L('হয়েছে', 'Done', 'Done'), add: L('উইজেট যোগ', 'Add widget', 'Widget যোগ'), reset: L('ডিফল্টে ফেরান', 'Reset to default', 'Default-এ ফেরান'),
  home_off: L('সাধারণ হোম', 'Normal Home', 'Normal Home'), empty: L('বোর্ড খালি — "উইজেট যোগ" চাপুন', 'The board is empty - tap "Add widget"', 'Board খালি — "Widget যোগ" চাপুন'),
  off: L('মালিকের বোর্ড বন্ধ আছে (সুইচবোর্ডে চালু করুন)', 'The owner board is switched off (turn it on in the Switchboard)', 'Owner board বন্ধ (Switchboard-এ চালু করুন)'), onlyOwner: L('শুধু মালিকের জন্য', 'Owner only', 'শুধু Owner-এর জন্য'),
  local: L('এই ফোনে সংরক্ষিত (সার্ভারে টেবিল নেই)', 'Saved on this phone (the server table is missing)', 'এই phone-এ saved (server table নেই)'), pend: L('ফোনে সংরক্ষিত — নেট এলে পাঠানো হবে', 'Saved on the phone - will sync when online', 'Phone-এ saved — net এলে sync হবে'),
  saved: L('সংরক্ষিত', 'Saved', 'Saved'), up: L('উপরে', 'Move up', 'Move up'), down: L('নিচে', 'Move down', 'Move down'), top: L('একদম উপরে', 'Move to top', 'Move to top'), bottom: L('একদম নিচে', 'Move to bottom', 'Move to bottom'),
  rename: L('নাম ও সীমা বদলান', 'Rename & limits', 'নাম ও limit'), size_c: L('ছোট করুন', 'Make compact', 'Compact করুন'), size_w: L('চওড়া করুন', 'Make wide', 'Wide করুন'), disable: L('লুকান (বন্ধ)', 'Hide (disable)', 'Hide (disable)'), enable: L('দেখান (চালু)', 'Show (enable)', 'Show (enable)'),
  remove: L('সরান', 'Remove', 'Remove'), more: L('আরও', 'More', 'More'), open: L('খুলুন', 'Open', 'Open'), search: L('খুঁজুন…', 'Search…', 'Search…'), checking: L('দেখা হচ্ছে…', 'Checking…', 'Checking…'),
  nores: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'), na: L('এখানে চালু নেই', 'Not available here', 'এখানে available নেই'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), noload: L('এখন আনা যায়নি', "Couldn't load now", 'এখন load হয়নি'),
  name: L('নাম', 'Name', 'Name'), size: L('আকার', 'Size', 'Size'), compact: L('ছোট', 'Compact', 'Compact'), wide: L('চওড়া', 'Wide', 'Wide'), enabled: L('বোর্ডে দেখান', 'Show on the board', 'Board-এ দেখান'),
  lim: L('সীমা (খালি = কোনো সীমা নেই)', 'Limits (empty = none)', 'Limit (খালি = নেই)'), wgt: L('সংখ্যা এর বেশি হলে হলুদ', 'Yellow when above', 'এর বেশি হলে yellow'), bgt: L('সংখ্যা এর বেশি হলে লাল', 'Red when above', 'এর বেশি হলে red'),
  wlt: L('সংখ্যা এর কম হলে হলুদ', 'Yellow when below', 'এর কম হলে yellow'), blt: L('সংখ্যা এর কম হলে লাল', 'Red when below', 'এর কম হলে red'), badnum: L('সীমার সংখ্যা ঠিক নয়', 'A limit is not a valid number', 'Limit-এর সংখ্যা ঠিক নয়'),
  days: L('কত দিনের বেশি পুরনো হলে "মেয়াদোত্তীর্ণ"', 'Overdue after this many days', 'কত দিন পরে "overdue"'), text: L('কাজ / মনে করানো', 'Task / reminder', 'কাজ / reminder'), rep: L('আবার শুরু', 'Repeats', 'Repeat'),
  r_daily: L('প্রতিদিন', 'Every day', 'প্রতিদিন'), r_weekly: L('প্রতি সপ্তাহে', 'Every week', 'প্রতি সপ্তাহে'), r_never: L('একবার', 'Once', 'একবার'), report: L('রিপোর্ট', 'Report', 'Report'), period: L('সময়', 'Period', 'Period'),
  page: L('পাতা', 'Page', 'Page'), preset: L('কী গুনবে', 'What to count', 'কী গুনবে'), pick: L('বেছে নিন', 'Choose', 'Choose'), save: L('সংরক্ষণ', 'Save', 'Save'),
  ticked: L('হয়েছে ✓', 'Done ✓', 'Done ✓'), unticked: L('বাকি — চাপলে টিক', 'To do - tap to tick', 'বাকি — চাপলে tick'), confirm_reset: L('বোর্ড ডিফল্টে ফিরবে। ঠিক আছে?', 'The board goes back to the default set. OK?', 'Board default-এ ফিরবে। ঠিক আছে?'),
  nonum: L('এই উইজেটে সংখ্যার সীমা নেই', 'This widget has no numeric limits', 'এই widget-এ numeric limit নেই'), added: L('যোগ হয়েছে', 'Added', 'Added'),
  vsy: L('গতকালের তুলনায়', 'vs yesterday', 'গতকালের তুলনায়'), vsw: L('গত সপ্তাহের', 'vs last', 'গত সপ্তাহের'), cust: L('জন গ্রাহক', 'customers', 'customers'), od: L('মেয়াদোত্তীর্ণ', 'overdue', 'overdue'),
  clear: L('সব ঠিক', 'All clear', 'সব ঠিক'), voids: L('বাতিল বিক্রি', 'voids', 'voids'), disc: L('ডিসকাউন্ট', 'discounts', 'discounts'), wait: L('অপেক্ষায়', 'waiting', 'waiting'), nosales: L('এখনও বিক্রি নেই', 'No sales yet', 'এখনও sale নেই'),
  g_sales: L('বিক্রি', 'Sales', 'Sales'), g_cash: L('ক্যাশ ও দিনের শেষ', 'Cash & day close', 'Cash ও day close'), g_appr: L('সিদ্ধান্ত ও সমস্যা', 'Decisions & problems', 'Decision ও problem'),
  g_money: L('বাকি ও পাওনা', 'Dues & payables', 'Due ও payable'), g_stock: L('স্টক', 'Stock', 'Stock'), g_sys: L('সিস্টেম', 'System', 'System'), g_custom: L('নিজের তৈরি', 'Your own', 'নিজের তৈরি'),
};
const T = (k) => lab(X[k]);

// ---------- helpers ----------
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const jget = (k, d) => { try { const v = JSON.parse(store.get(k) || 'null'); return v == null ? d : v; } catch (e) { return d; } };
const jset = (k, v) => { try { store.set(k, JSON.stringify(v)); } catch (e) { /* private window */ } };
const dhaka = (d = new Date()) => d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const daysBetween = (a, b) => Math.round((new Date(b + 'T12:00:00Z') - new Date(a + 'T12:00:00Z')) / 86400000);
const money = (n) => '৳ ' + A.fmt(Math.round(Number(n || 0) * 100) / 100);
const N = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const gid = () => 'w' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const dhakaHour = () => Number(new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', hour12: false })) % 24;
const hhmm = (ms) => new Date(ms).toLocaleTimeString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', minute: '2-digit' });
const weekStart = (iso) => { const d = new Date(iso + 'T12:00:00Z'); const back = (d.getUTCDay() + 1) % 7; return addDays(iso, -back); };   // weeks start on Saturday
const age = (s) => { const h = Math.max(0, Math.round((Date.now() - new Date(s).getTime()) / 3600000)); return h >= 48 ? Math.floor(h / 24) + (S.lang === 'en' ? ' d' : ' দিন') : h + (S.lang === 'en' ? ' h' : ' ঘণ্টা'); };

// "this source is not installed / not allowed" must never show an error: it hides the widget
const MISSING = /does not exist|could not find|schema cache|42P01|42883|PGRST20[1-5]|not allowed|permission denied|row-level/i;
class Miss extends Error {}
const chk = (r) => { if (r && r.error) { const m = (r.error.message || '') + ' ' + (r.error.code || ''); if (MISSING.test(m)) throw new Miss(m); throw r.error; } return r ? r.data : null; };
const rpc = async (fn, args) => chk(await sb.rpc(fn, args || {}));
const tbl = async (qb) => chk(await qb);
const cnt = async (qb) => { const r = await qb; if (r && r.error) { const m = (r.error.message || '') + ' ' + (r.error.code || ''); if (MISSING.test(m)) throw new Miss(m); throw r.error; } return (r && r.count) || 0; };
const arr = (d) => (Array.isArray(d) ? d : d && Array.isArray(d.rows) ? d.rows : []);
const locsNow = () => B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
const locName = (l) => A.nm(l);

// ---------- shared data (each fetched once per refresh, only if a widget needs it) ----------
const mkEnv = () => { const memo = {}; return { td: dhaka(), get: (k, fn) => memo[k] || (memo[k] = fn()) }; };
const salesRows = (env) => env.get('sales', async () => arr(await rpc('sales_summary', { p_from: addDays(env.td, -7) })).map((r) => ({ d: r.sale_date, loc: r.location_id, st: r.status, n: N(r.n), total: N(r.total), disc: N(r.discount) })));
const sumDay = (rows, d, st, k) => rows.filter((r) => r.d === d && r.st === st).reduce((s, r) => s + r[k || 'total'], 0);
const pct = (a, b) => (b > 0 ? Math.round(((a - b) / b) * 100) : null);
const pctS = (p) => (p === null ? '–' : (p > 0 ? '+' : '') + p + '%');
const wd = (iso) => new Date(iso + 'T12:00:00Z').toLocaleDateString(S.lang === 'en' ? 'en-GB' : 'bn-BD', { weekday: 'short', timeZone: 'UTC' });

// ---------- widget catalog (one object: key, labels, group, loader) ----------
// loader(env, cfg) -> { value, num?, tone: ok|warn|bad|info, sub, route }  (throws Miss when the source is not installed)
const KINDS = {
  sales_vs: { g: 'sales', num: true, l: L('আজকের বিক্রি (গতকাল ও গত সপ্তাহের সাথে)', "Today's sales vs yesterday", 'আজকের Sales vs গতকাল'), route: 'biz', async load(env) {
    const r = await salesRows(env), td = env.td, a = sumDay(r, td, 'done'), y = sumDay(r, addDays(td, -1), 'done'), w = sumDay(r, addDays(td, -7), 'done');
    return { value: money(a), num: a, tone: a >= y ? 'ok' : 'info', sub: `${T('vsy')} ${pctS(pct(a, y))} · ${T('vsw')} ${wd(addDays(td, -7))} ${pctS(pct(a, w))}`, route: 'biz' }; } },
  cash_short: { g: 'cash', num: true, l: L('ক্যাশ কম / বেশি (আজ)', 'Cash short / over today', 'Cash কম / বেশি (আজ)'), route: 'exceptions', async load(env) {
    const rows = arr(await tbl(sb.from('exceptions').select('flag_code,level,status,amount,entry_date').eq('flag_code', 'cash_short_over').order('created_at', { ascending: false }).limit(500)));
    const t0 = rows.filter((x) => x.entry_date === env.td), net = t0.reduce((s, x) => s + N(x.amount), 0), old = rows.filter((x) => x.status === 'open' && x.entry_date !== env.td).length;
    const red = t0.some((x) => x.status === 'open' && x.level === 'red'), open = t0.some((x) => x.status === 'open');
    return { value: t0.length ? (net > 0 ? '+' : net < 0 ? '−' : '') + money(Math.abs(net)) : '✓ ' + money(0), num: Math.abs(net), tone: red ? 'bad' : open || old ? 'warn' : 'ok', sub: `${t0.length} ${lab(L('টি আজ', 'today', 'today'))}${old ? ` · ${old} ${lab(L('পুরনো খোলা', 'older open', 'older open'))}` : ''}`, route: 'exceptions' }; } },
  day_close: { g: 'cash', num: true, l: L('দিন শেষ — প্রতিটি শোরুম (১৪-১)', 'Day close per shop (14-1)', 'Day close — প্রতিটি shop (14-1)'), route: 'form/14-1', async load(env) {
    let shops = locsNow().filter((l) => l.kind === 'showroom'); if (!shops.length) shops = locsNow();
    const es = arr(await tbl(sb.from('entries').select('form_code,location_id,status').eq('entry_date', env.td).eq('form_code', '14-1').limit(500)));
    let roll = []; try { roll = arr(await tbl(sb.from('form_rollout').select('form_code,location_id,mode').eq('form_code', '14-1'))); } catch (e) { roll = []; }
    const paper = (id) => (roll.find((x) => x.location_id === id) || {}).mode === 'paper';
    const closed = (id) => es.some((x) => x.location_id === id && (x.status === 'submitted' || x.status === 'approved'));
    const need = shops.filter((l) => !paper(l.id)), miss = need.filter((l) => !closed(l.id)), done = need.length - miss.length;
    return { value: `${done}/${need.length}`, num: miss.length, tone: !miss.length ? 'ok' : dhakaHour() >= 18 ? 'warn' : 'info', sub: miss.length ? miss.slice(0, 3).map(locName).join(', ') + (miss.length > 3 ? ' +' + (miss.length - 3) : '') : T('clear'), route: 'form/14-1' }; } },
  needs_you: { g: 'appr', num: true, l: L('আপনার সিদ্ধান্ত দরকার (পুরনো আগে)', 'Needs you (oldest first)', 'Decision দরকার (পুরনো আগে)'), route: 'pending', async load() {
    const d = arr(await rpc('needs_you_oldest', { p_limit: 5 }));
    if (!d.length) return { value: '✓ 0', num: 0, tone: 'ok', sub: T('clear'), route: 'pending' };
    const o = d[0]; return { value: d.length >= 5 ? '5+' : String(d.length), num: d.length, tone: 'warn', sub: `${o.label || o.kind} · ${age(o.since)}`, route: 'pending' }; } },
  exceptions: { g: 'appr', num: true, l: L('খোলা লাল / হলুদ গরমিল', 'Open red / yellow exceptions', 'খোলা red / yellow exception'), route: 'exceptions', async load() {
    const q = (lv) => cnt(sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open').eq('level', lv));
    const [red, yel] = await Promise.all([q('red'), q('yellow')]);
    return { value: String(red), num: red, tone: red ? 'bad' : yel ? 'warn' : 'ok', sub: `${lab(L('হলুদ', 'yellow', 'yellow'))} ${yel}`, route: 'exceptions' }; } },
  approvals: { g: 'appr', num: true, l: L('অনুমোদনের অপেক্ষায়', 'Pending approvals', 'Approval-এর অপেক্ষায়'), route: 'pending', async load() {
    const q = (t, st) => cnt(sb.from(t).select('id', { count: 'exact', head: true }).eq('status', st)).catch((e) => { if (e instanceof Miss) return 0; throw e; });
    const [en, rel, itm, em] = await Promise.all([cnt(sb.from('entries').select('id', { count: 'exact', head: true }).eq('status', 'submitted')), q('release_requests', 'pending'), q('item_changes', 'pending'), q('emergency_requests', 'pending')]);
    const tot = en + rel + itm + em; return { value: String(tot), num: tot, tone: tot ? 'warn' : 'ok', sub: tot ? `${lab(L('ফর্ম', 'forms', 'forms'))} ${en} · ${lab(L('ছাড়', 'release', 'release'))} ${rel} · ${lab(L('আইটেম', 'items', 'items'))} ${itm}` : T('clear'), route: 'pending' }; } },
  cust_dues: { g: 'money', num: true, l: L('গ্রাহকের বাকি (মোট ও মেয়াদোত্তীর্ণ)', 'Customer dues (total & overdue)', 'Customer due (total ও overdue)'), route: 'dues', async load(env, cfg) {
    const rows = arr(await rpc('customer_dues')).filter((c) => N(c.balance) > 0), days = N(cfg.days) > 0 ? N(cfg.days) : 30;
    const tot = rows.reduce((s, c) => s + N(c.balance), 0), od = rows.filter((c) => c.oldest && daysBetween(c.oldest, env.td) > days).reduce((s, c) => s + N(c.balance), 0);
    return { value: money(tot), num: tot, tone: od > 0 ? 'warn' : 'info', sub: `${rows.length} ${T('cust')} · ${T('od')} (>${days}d) ${money(od)}`, route: 'dues' }; } },
  supp_dues: { g: 'money', num: true, l: L('সরবরাহকারীর পাওনা', 'Supplier dues', 'Supplier-এর পাওনা'), route: 'payables', async load() {
    const d = await rpc('payables_summary', { p_loc: null }), r = Array.isArray(d) ? d[0] : d; if (!r) throw new Miss('empty');
    return { value: money(r.total_payable), num: N(r.total_payable), tone: N(r.overdue) > 0 ? 'warn' : 'info', sub: `${N(r.suppliers_owed)} ${lab(L('সরবরাহকারী', 'suppliers', 'suppliers'))} · ${T('od')} ${money(r.overdue)}`, route: 'payables' }; } },
  stock_low: { g: 'stock', num: true, l: L('ন্যূনতমের নিচে স্টক ও মেয়াদ শেষের কাছে', 'Low stock & expiring soon', 'Low stock ও expiring soon'), route: 'stock', async load() {
    const low = arr(await rpc('stock_levels', { p_loc: null, p_filters: { below_min: true } })).filter((x) => x.below_min !== false).length;
    let soon = 0, exp = 0; try { const e = arr(await rpc('expiry_list', { p_loc: null, p_hours_ahead: 24 })); exp = e.filter((x) => x.expired).length; soon = e.length - exp; } catch (e) { /* expiry not installed */ }
    return { value: String(low), num: low, tone: exp ? 'bad' : low || soon ? 'warn' : 'ok', sub: `${lab(L('২৪ ঘণ্টায় মেয়াদ শেষ', 'expiring ≤24h', 'expiring ≤24h'))} ${soon} · ${lab(L('মেয়াদ গেছে', 'expired', 'expired'))} ${exp}`, route: 'stock' }; } },
  wastage: { g: 'stock', num: true, l: L('আজকের নষ্ট', 'Wastage today', 'আজকের Wastage'), route: 'stock', async load(env) {
    const rows = arr(await tbl(sb.from('stock_wastage').select('qty,made_at').gte('made_at', env.td + 'T00:00:00+06:00').limit(500)));
    let wait = 0; try { wait = arr(await rpc('wastage_pending', { p_loc: null, p_status: 'pending' })).length; } catch (e) { wait = 0; }
    const q = rows.reduce((s, x) => s + N(x.qty), 0);
    return { value: String(rows.length), num: rows.length, tone: wait ? 'warn' : 'info', sub: `${lab(L('মোট পরিমাণ', 'total qty', 'total qty'))} ${A.fmt(Math.round(q * 100) / 100)}${wait ? ` · ${wait} ${T('wait')}` : ''}`, route: 'stock' }; } },
  voids_disc: { g: 'sales', num: true, l: L('আজ বাতিল বিক্রি ও ডিসকাউন্ট', 'Voids & discounts today', 'আজ voids ও discounts'), route: 'discounts', async load(env) {
    const r = await salesRows(env), v = r.filter((x) => x.d === env.td && x.st === 'void').reduce((s, x) => s + x.n, 0), vt = sumDay(r, env.td, 'void'), d = sumDay(r, env.td, 'done', 'disc');
    return { value: `${v} ${T('voids')}`, num: v, tone: v ? 'warn' : 'ok', sub: `${money(vt)} · ${T('disc')} ${money(d)}`, route: 'discounts' }; } },
  unsent: { g: 'sys', num: true, l: L('ফোনে জমা — পাঠানো হয়নি', 'Unsent forms on this phone', 'Phone-এ জমা — পাঠানো হয়নি'), route: 'outbox', async load() {
    const n = B.outbox && B.outbox.count ? B.outbox.count() : 0; return { value: String(n), num: n, tone: n ? 'warn' : 'ok', sub: n ? '' : T('clear'), route: 'outbox' }; } },
  top_sellers: { g: 'sales', l: L('আজকের সেরা বিক্রি', 'Top sellers today', 'আজকের top seller'), route: 'reports', async load(env) {
    const rows = arr(await tbl(sb.from('sales').select('lines').eq('sale_date', env.td).eq('status', 'done').limit(500))), m = {};
    rows.forEach((s) => (Array.isArray(s.lines) ? s.lines : []).forEach((ln) => { const k = String(ln.name || ln.item_id || '?'); const o = m[k] || (m[k] = { k, q: 0, a: 0 }); o.q += N(ln.qty); o.a += N(ln.amount); }));
    const top = Object.values(m).sort((a, b) => b.a - a.a).slice(0, 3);
    return top.length ? { value: top[0].k, tone: 'info', sub: top.map((x) => `${x.k} ×${A.fmt(Math.round(x.q * 100) / 100)}`).join(' · '), route: 'reports' } : { value: '—', tone: 'info', sub: T('nosales'), route: 'reports' }; } },
  parallel: { g: 'appr', num: true, l: L('পাশাপাশি মাসের সিদ্ধান্ত বাকি', 'Parallel-month decisions waiting', 'Parallel মাসের decision বাকি'), route: 'parallel', async load() {
    const n = arr(await rpc('parallel_waiting')).length; return { value: String(n), num: n, tone: n ? 'warn' : 'ok', sub: n ? '' : T('clear'), route: 'parallel' }; } },
  rollout: { g: 'sys', num: true, l: L('ফর্ম এখনও কাগজে (রোলআউট)', 'Forms still on paper (rollout)', 'Form এখনও কাগজে (rollout)'), route: 'rollout', async load() {
    const rows = arr(await tbl(sb.from('form_rollout').select('mode').limit(2000))), p = rows.filter((x) => x.mode === 'paper').length, pa = rows.filter((x) => x.mode === 'parallel').length;
    return { value: String(p), num: p, tone: p ? 'info' : 'ok', sub: `${lab(L('পাশাপাশি', 'parallel', 'parallel'))} ${pa}`, route: 'rollout' }; } },
  backup: { g: 'sys', l: L('ব্যাকআপ অবস্থা', 'Backup status', 'Backup status'), route: 'backup', async load(env) {
    const rows = arr(await tbl(sb.from('backup_runs').select('*').limit(50))); if (!rows.length) return { value: '—', tone: 'warn', sub: lab(L('এখনও ব্যাকআপ হয়নি', 'No backup yet', 'এখনও backup হয়নি')), route: 'backup' };
    const tk = (r) => String(r.finished_at || r.ran_at || r.created_at || r.started_at || ''), last = rows.sort((a, b) => (tk(a) < tk(b) ? 1 : -1))[0], ok = !/fail|error/i.test(String(last.status || 'ok')), hrs = tk(last) ? (Date.now() - new Date(tk(last)).getTime()) / 3600000 : null;
    return { value: ok ? 'OK' : lab(L('ব্যর্থ', 'Failed', 'Failed')), tone: !ok ? 'bad' : hrs !== null && hrs > 36 ? 'warn' : 'ok', sub: hrs !== null ? age(tk(last)) + ' ' + lab(L('আগে', 'ago', 'ago')) : '', route: 'backup' }; } },
  notifications: { g: 'sys', num: true, l: L('অপঠিত নোটিফিকেশন', 'Unread notifications', 'Unread notification'), route: 'home', async load() {
    const rows = arr(await tbl(sb.from('notifications').select('*').limit(300))), n = rows.filter((x) => x.read_at == null && x.read !== true && x.is_read !== true && x.seen !== true).length;
    return { value: String(n), num: n, tone: n ? 'info' : 'ok', sub: n ? '' : T('clear'), route: B.ia && B.ia.byRoute('notifications') ? 'notifications' : 'home' }; } },
  attendance: { g: 'sys', num: true, l: L('আজ হাজিরা', 'Attendance today', 'আজকের attendance'), route: 'staff', async load(env) {
    const rows = arr(await tbl(sb.from('attendance_days').select('*').limit(1000))), key = ['day', 'att_date', 'work_date', 'date'].find((k) => rows.length && k in rows[0]) || 'day';
    const t0 = rows.filter((x) => String(x[key] || '').slice(0, 10) === env.td), pres = t0.filter((x) => !/absent|leave/i.test(String(x.status || ''))).length;
    return { value: String(pres), num: pres, tone: 'info', sub: `${lab(L('মোট এন্ট্রি', 'entries', 'entries'))} ${t0.length}`, route: B.ia && B.ia.byRoute('attendance') ? 'attendance' : 'staff' }; } },
  payroll: { g: 'money', num: true, l: L('এই মাসের বেতন দেয় (শিট থেকে)', 'Payroll due this month', 'এই মাসের payroll due'), route: 'salary', async load(env) {
    const d = await rpc('salary_report', { p_loc: null, p_month: env.td.slice(0, 8) + '01' }); if (!d || !d.totals) throw new Miss('empty');
    return { value: money(d.totals.net), num: N(d.totals.net), tone: 'info', sub: `${N(d.totals.people)} ${lab(L('জন', 'people', 'people'))} · ${N(d.sheets)} ${lab(L('শিট', 'sheets', 'sheets'))}`, route: 'salary' }; } },
  balance_check: { g: 'money', num: true, l: L('হিসাবের ব্যালেন্স শিট মিলছে?', 'Balance sheet check', 'Balance sheet মিলছে?'), route: 'biz', async load() {
    const d = await rpc('balance_sheet'); if (!d || typeof d !== 'object') throw new Miss('empty');
    const a = N(d.assets), le = N(d.liabilities) + N(d.equity), diff = d.diff !== undefined ? N(d.diff) : d.difference !== undefined ? N(d.difference) : a - le, okb = Math.abs(diff) < 0.5;
    return { value: okb ? '✓' : money(Math.abs(diff)), num: Math.abs(diff), tone: okb ? 'ok' : 'bad', sub: okb ? lab(L('মিলেছে', 'Balanced', 'Balanced')) : lab(L('অমিল', 'Out of balance', 'Out of balance')), route: 'biz' }; } },
  report: { g: 'custom', l: L('রিপোর্ট শর্টকাট', 'Report shortcut', 'Report shortcut'), route: 'reports', cfg: 'report', async load(env, cfg) {
    if (!cfg.report) return { value: '—', tone: 'info', sub: T('pick'), route: 'reports' };
    const cat = await reportCatalog(), def = cat.find((r) => r.key === cfg.report); if (!def) throw new Miss('report');
    const flt = def.needs_date === false ? {} : { preset: cfg.preset || 'today' };
    const r = def.engine === 2 && B.reports2 ? await B.reports2.run(def.key, flt, null, null, 1) : await sb.rpc('report_run', { p_key: def.key, p_filters: flt, p_group: null, p_sort: null, p_page: 1, p_compare: false });
    const res = chk(r) || {}, tot = res.totals || {}, col = (res.columns || []).find((c) => c.role === 'measure' && (c.type === 'money' || c.type === 'int' || c.type === 'num') && tot[c.key] !== undefined && tot[c.key] !== null);
    const nmR = lab({ bn: def.name_bn, en: def.name_en || def.name_bn, mix: def.name_mix || def.name_bn });
    return col ? { value: col.type === 'money' ? money(tot[col.key]) : A.fmt(tot[col.key]), num: N(tot[col.key]), tone: 'info', sub: lab({ bn: col.label_bn, en: col.label_en || col.label_bn, mix: col.label_bn }), route: 'report/' + encodeURIComponent(def.key), name: nmR }
      : { value: '—', tone: 'info', sub: nmR, route: 'report/' + encodeURIComponent(def.key), name: nmR }; } },
  page: { g: 'custom', l: L('পাতার শর্টকাট', 'Page shortcut', 'Page shortcut'), route: 'home', cfg: 'page', async load(env, cfg) {
    const r = cfg.route && B.ia && B.ia.byRoute(cfg.route); if (!r) return { value: '›', tone: 'info', sub: T('pick'), route: 'home' };
    return { value: '›', tone: 'info', sub: B.ia.groupLabel(r.group), route: r.route, name: B.ia.label(r) }; } },
  counter: { g: 'custom', num: true, l: L('গণনা (টেবিলের সংখ্যা)', 'Counter', 'Counter (table count)'), route: 'home', cfg: 'counter', async load(env, cfg) {
    const p = COUNTERS[cfg.preset]; if (!p) return { value: '—', tone: 'info', sub: T('pick'), route: 'home' };
    let qb = sb.from(p.t).select('id', { count: 'exact', head: true }); Object.keys(p.f || {}).forEach((k) => { qb = qb.eq(k, p.f[k]); }); if (p.today) qb = qb.eq(p.today, env.td);
    const n = await cnt(qb); return { value: String(n), num: n, tone: 'info', sub: lab(p.l), route: p.route, name: lab(p.l) }; } },
  note: { g: 'custom', l: L('নোট / রোজকার চেকলিস্ট', 'Note / daily checklist', 'Note / daily checklist'), route: 'home', cfg: 'note', local: true },
};
const COUNTERS = {
  staff_pending: { t: 'profiles', f: { status: 'pending' }, route: 'staff', l: L('অনুমোদনের অপেক্ষায় স্টাফ', 'Staff waiting for approval', 'Staff approval-এর অপেক্ষায়') },
  exceptions_open: { t: 'exceptions', f: { status: 'open' }, route: 'exceptions', l: L('খোলা গরমিল', 'Open exceptions', 'খোলা exception') },
  entries_submitted: { t: 'entries', f: { status: 'submitted' }, route: 'pending', l: L('জমা দেওয়া, অনুমোদন বাকি ফর্ম', 'Submitted forms awaiting approval', 'Submitted form (approval বাকি)') },
  entries_today: { t: 'entries', f: {}, today: 'entry_date', route: 'pending', l: L('আজকের ফর্ম', 'Forms entered today', 'আজকের form') },
  item_changes: { t: 'item_changes', f: { status: 'pending' }, route: 'itemreq', l: L('আইটেম বদলের অনুরোধ', 'Item change requests', 'Item change request') },
  releases: { t: 'release_requests', f: { status: 'pending' }, route: 'releases', l: L('ছাড়ের অনুরোধ', 'Release requests', 'Release request') },
  emergency: { t: 'emergency_requests', f: { status: 'pending' }, route: 'emergency', l: L('জরুরি অনুরোধ', 'Emergency requests', 'Emergency request') },
  customers: { t: 'customers', f: {}, route: 'dues', l: L('মোট গ্রাহক', 'Customers', 'Customers') },
  items_active: { t: 'items', f: { is_active: true }, route: 'items', l: L('চালু আইটেম', 'Active items', 'Active items') },
};
const DEFAULT_KINDS = ['sales_vs', 'cash_short', 'day_close', 'needs_you', 'exceptions', 'approvals', 'cust_dues', 'supp_dues', 'stock_low', 'wastage', 'voids_disc', 'unsent', 'backup', 'notifications'];
const DEFAULT_NOTES = [L('ক্যাশ গণনা মিলিয়ে দেখুন', 'Check the cash counts', 'Cash count মিলিয়ে দেখুন'), L('স্টক গণনা দেখুন', 'Check the stock counts', 'Stock count দেখুন'), L('গরমিল (exceptions) দেখে সিদ্ধান্ত নিন', 'Review the exceptions', 'Exception দেখে decision নিন')];
const defaults = () => DEFAULT_KINDS.map((k) => ({ cid: gid(), widget: k, config: {}, enabled: true })).concat(DEFAULT_NOTES.map((n) => ({ cid: gid(), widget: 'note', config: { text: n.en, label: lab(n), repeat: 'daily' }, enabled: true })));
const kindLabel = (k) => (KINDS[k] ? lab(KINDS[k].l) : k);
const itemLabel = (it, v) => (it.config && it.config.label) || (v && v.name) || kindLabel(it.widget);

let REPS = null;
async function reportCatalog() {
  if (REPS) return REPS; let cat = [];
  try { const r = await sb.rpc('report_catalog'); if (r && !r.error && Array.isArray(r.data)) cat = r.data; } catch (e) { /* none */ }
  try { if (B.reports2) cat = cat.concat(await B.reports2.catalog()); } catch (e) { /* first engine only */ }
  REPS = cat.filter((r) => r.allowed !== false); return REPS;
}

// ---------- state + storage ----------
const ST = { items: [], edit: false, vals: {}, asOf: null, busy: false, src: 'default', note: '', home: false, av: {}, timer: null, bound: false };
const K = (n) => 'bos_ob_' + n + '_' + uid();
const cleanCfg = (c) => { const o = {}; Object.keys(c || {}).forEach((k) => { const v = c[k]; if (v !== undefined && v !== null && v !== '') o[k] = v; }); return o; };
const fromServer = (rows) => rows.map((r) => { const c = r.config && typeof r.config === 'object' ? r.config : {}; return { cid: c.cid || gid(), widget: r.widget, config: c, enabled: r.enabled !== false }; });
const toServer = (items) => items.map((i) => ({ widget: i.widget, config: Object.assign({}, cleanCfg(i.config), { cid: i.cid }), enabled: i.enabled !== false }));
async function loadItems() {
  const local = jget(K('items'), null), dirty = store.get(K('dirty')) === '1', custom = store.get(K('custom')) === '1';
  let rows = null, reachable = false;
  if (navigator.onLine !== false) { try { rows = arr(await rpc('owner_board_get')); reachable = true; } catch (e) { rows = null; } }
  if (dirty && Array.isArray(local)) { ST.items = fromServer(local); ST.src = reachable ? 'server' : 'local'; if (reachable) persist(true); return; }
  if (reachable && rows.length) { ST.items = fromServer(rows); ST.src = 'server'; jset(K('items'), toServer(ST.items)); return; }
  if (Array.isArray(local) && (custom || !reachable)) { ST.items = fromServer(local); ST.src = reachable ? 'server' : 'local'; return; }
  ST.items = defaults(); ST.src = reachable ? 'server' : 'local';
}
let saving = Promise.resolve();
function persist(quiet) {
  const payload = toServer(ST.items);
  jset(K('items'), payload); try { store.set(K('custom'), '1'); } catch (e) { /* ignore */ }
  saving = saving.then(async () => {
    if (navigator.onLine === false) { try { store.set(K('dirty'), '1'); } catch (e) { /* ignore */ } ST.note = T('pend'); if (!quiet) toast(T('pend')); return drawNote(); }
    try { await rpc('owner_board_save', { p_items: payload }); try { store.set(K('dirty'), '0'); } catch (e) { /* ignore */ } ST.src = 'server'; ST.note = ''; if (!quiet) toast(T('saved')); }
    catch (e) {
      if (e instanceof Miss) { try { store.set(K('dirty'), '0'); } catch (e2) { /* ignore */ } ST.src = 'local'; ST.note = T('local'); }
      else if (/feature_off/.test(String(e && e.message))) { ST.note = T('off'); }
      else { try { store.set(K('dirty'), '1'); } catch (e2) { /* ignore */ } ST.note = T('pend'); if (!quiet) toast(T('pend')); }
    }
    drawNote();
  });
  return saving;
}

// ---------- loading values ----------
const cacheGet = () => jget(K('vals'), { at: 0, v: {} });
const tone = (v, cfg) => {
  if (!v || !Number.isFinite(v.num)) return v && v.tone ? v.tone : 'info';
  const n = v.num, g = (k) => (cfg && cfg[k] !== undefined && cfg[k] !== null && cfg[k] !== '' ? Number(cfg[k]) : null);
  const bg = g('bad_gt'), wg = g('warn_gt'), bl = g('bad_lt'), wl = g('warn_lt');
  if ((bg !== null && n > bg) || (bl !== null && n < bl)) return 'bad';
  if ((wg !== null && n > wg) || (wl !== null && n < wl)) return v.tone === 'bad' ? 'bad' : 'warn';
  return (bg !== null || wg !== null || bl !== null || wl !== null) && v.tone === 'warn' ? 'ok' : v.tone || 'info';
};
async function refresh(manual) {
  if (ST.busy || !$('#ob_main')) return; ST.busy = true; drawBar();
  const cached = cacheGet(); if (!ST.asOf && cached.at) { ST.asOf = cached.at; Object.keys(cached.v || {}).forEach((k) => { if (!ST.vals[k]) ST.vals[k] = Object.assign({ stale: true }, cached.v[k]); }); draw(); }
  if (navigator.onLine === false) { ST.busy = false; drawBar(); return draw(); }
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const env = mkEnv(), live = ST.items.filter((i) => i.enabled !== false && KINDS[i.widget] && !KINDS[i.widget].local);
  await Promise.all(live.map(async (it) => {
    const k = KINDS[it.widget];
    try { const v = await k.load(env, it.config || {}); ST.vals[it.cid] = Object.assign({}, v); ST.av[it.widget] = true; }
    catch (e) { if (e instanceof Miss) { ST.av[it.widget] = it.widget === 'report' || it.widget === 'counter' || it.widget === 'page' ? ST.av[it.widget] : false; ST.vals[it.cid] = { hidden: true }; } else { const old = ST.vals[it.cid]; ST.vals[it.cid] = old && !old.hidden ? Object.assign({}, old, { stale: true }) : { err: true, value: '—', tone: 'info', sub: T('noload'), route: k.route }; } }
  }));
  ST.asOf = Date.now(); ST.busy = false;
  const keep = {}; ST.items.forEach((i) => { const v = ST.vals[i.cid]; if (v && !v.err && !v.hidden) keep[i.cid] = { value: v.value, num: v.num, tone: v.tone, sub: v.sub, route: v.route, name: v.name }; });
  jset(K('vals'), { at: ST.asOf, v: keep });
  if ($('#ob_main')) { draw(); if (manual) toast(T('refresh') + ' ✓'); }
}
async function probeCatalog() {   // which kinds exist on this install (so the catalog hides the missing ones)
  const env = mkEnv(), todo = Object.keys(KINDS).filter((k) => !KINDS[k].local && !KINDS[k].cfg && ST.av[k] === undefined);
  await Promise.all(todo.map(async (k) => { try { await KINDS[k].load(env, {}); ST.av[k] = true; } catch (e) { ST.av[k] = e instanceof Miss ? false : true; } }));
}

// ---------- drawing ----------
const noteDone = (c, td) => { const d = c.done_on; if (!d) return false; if (c.repeat === 'weekly') return d >= weekStart(td); if (c.repeat === 'never') return true; return d === td; };
function widgetHtml(it, i, n) {
  const k = KINDS[it.widget]; if (!k) return '';
  const c = it.config || {}, td = dhaka(), edit = ST.edit, on = it.enabled !== false;
  let v = ST.vals[it.cid] || null, val, sub, tn, act, stale = false;
  if (it.widget === 'note') { const dn = noteDone(c, td); val = dn ? '☑' : '☐'; sub = dn ? T('ticked') : T('unticked'); tn = dn ? 'ok' : 'warn'; act = 'ob_tick'; }
  else {
    if (v && v.hidden && !edit) return '';
    if (v && v.hidden) { val = '—'; sub = T('na'); tn = 'info'; act = 'ob_edit'; }
    else if (!v) { val = '…'; sub = T('loading'); tn = 'info'; act = 'obd_open'; }
    else { val = v.value; sub = v.sub; tn = tone(v, c); act = 'obd_open'; stale = !!v.stale; }
  }
  if (edit) act = 'ob_edit';
  const label = it.widget === 'note' ? (c.label || c.text || kindLabel('note')) : itemLabel(it, v);
  const size = c.size === 'wide' ? 'wide' : '';
  const ed = edit ? `<div class="ob-ed"><button data-act="ob_mv" data-cid="${esc(it.cid)}" data-d="-1" aria-label="${esc(T('up'))}" ${i === 0 ? 'disabled' : ''}>↑</button><button data-act="ob_mv" data-cid="${esc(it.cid)}" data-d="1" aria-label="${esc(T('down'))}" ${i === n - 1 ? 'disabled' : ''}>↓</button><button data-act="ob_menu" data-cid="${esc(it.cid)}" aria-haspopup="menu" aria-label="${esc(T('more'))}">⋮</button></div>` : '';
  return `<div class="ob-w mk ${esc(tn)} ${size} ${on ? '' : 'off'}" data-w="${esc(it.widget)}" data-cid="${esc(it.cid)}"><button class="ob-main" data-act="${act}" data-cid="${esc(it.cid)}"><span class="k">${esc(label)}${!on ? ' · ' + esc(T('disable')) : ''}</span><span class="v">${esc(val)}</span>${sub ? `<span class="s">${esc(sub)}</span>` : ''}${stale ? '<span class="s">⏱</span>' : ''}</button>${ed}</div>`;
}
function draw() {
  const box = $('#ob_grid'); if (!box) return;
  const items = ST.items, shown = items.filter((i) => ST.edit || i.enabled !== false);
  const html = shown.map((it) => widgetHtml(it, items.indexOf(it), items.length)).join('');
  box.innerHTML = html || (ST.edit || !items.length ? B.ui.state('empty', T('empty')) : '');
  drawBar(); drawNote();
}
function drawBar() {
  const b = $('#ob_bar'); if (!b) return;
  const off = navigator.onLine === false, at = ST.asOf ? `${T('asof')} ${hhmm(ST.asOf)}` : '';
  b.innerHTML = `<span class="ob-at" id="ob_at">${esc(off ? T('offl') + (at ? ' · ' + at : '') : at)}</span>
    <button class="mini" data-act="ob_refresh" aria-label="${esc(T('refresh'))}" ${ST.busy ? 'disabled' : ''}>${ST.busy ? '…' : '↻'}</button>
    <button class="tog ${ST.edit ? 'on' : ''}" data-act="ob_edit_toggle" aria-pressed="${ST.edit}">${esc(ST.edit ? T('done') : T('edit'))}</button>
    ${ST.home ? `<button class="tog" data-act="ob_home_off">${esc(T('home_off'))}</button>` : ''}`;
  const ea = $('#ob_editbar'); if (ea) ea.innerHTML = ST.edit ? `<button class="primary" data-act="ob_add">＋ ${esc(T('add'))}</button><button data-act="ob_reset">${esc(T('reset'))}</button>` : '';
}
function drawNote() { const n = $('#ob_note'); if (n) n.innerHTML = ST.note ? `<div class="notice warn" data-state="note">${esc(ST.note)}</div>` : ''; }

// ---------- menus ----------
function popMenu(title, items) {
  if (B.ctl && B.ctl.menu) { const old = document.getElementById('ob_pop'); if (old) old.remove(); const t = B.ctl.menu({ label: title, items }); t.id = 'ob_pop'; t.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0'; document.body.appendChild(t); t.click(); return; }
  openSheet(`<h2>${esc(title)}</h2><div class="stack">${items.map((it, i) => `<button class="full" data-act="ob_pick" data-i="${i}" ${it.disabled ? 'disabled' : ''}>${esc(it.label)}</button>`).join('')}</div>`);
  H.ob_pick = (a) => { closeSheet(); const it = items[Number(a.dataset.i)]; if (it && it.onClick) it.onClick(); };
}
const byCid = (cid) => ST.items.find((i) => i.cid === cid);
function move(cid, how) {
  const i = ST.items.findIndex((x) => x.cid === cid); if (i < 0) return;
  let j = how === 'top' ? 0 : how === 'bottom' ? ST.items.length - 1 : i + Number(how);
  j = Math.max(0, Math.min(ST.items.length - 1, j)); if (j === i) return;
  const [x] = ST.items.splice(i, 1); ST.items.splice(j, 0, x); draw(); persist(true);
}
function itemMenu(cid) {
  const it = byCid(cid); if (!it) return; const i = ST.items.indexOf(it), n = ST.items.length;
  popMenu(itemLabel(it, ST.vals[cid]), [
    { label: T('up'), disabled: i === 0, onClick: () => move(cid, -1) }, { label: T('down'), disabled: i === n - 1, onClick: () => move(cid, 1) },
    { label: T('top'), disabled: i === 0, onClick: () => move(cid, 'top') }, { label: T('bottom'), disabled: i === n - 1, onClick: () => move(cid, 'bottom') },
    { label: T('rename'), onClick: () => editSheet(cid) },
    { label: it.config && it.config.size === 'wide' ? T('size_c') : T('size_w'), onClick: () => { it.config = Object.assign({}, it.config, { size: it.config && it.config.size === 'wide' ? 'compact' : 'wide' }); draw(); persist(true); } },
    { label: it.enabled === false ? T('enable') : T('disable'), onClick: () => { it.enabled = it.enabled === false; draw(); persist(true); if (it.enabled) refresh(); } },
    { label: T('remove'), danger: true, onClick: () => { ST.items = ST.items.filter((x) => x.cid !== cid); delete ST.vals[cid]; draw(); persist(true); } },
  ]);
}

// ---------- edit sheet (name, size, limits, kind-specific settings) ----------
function pageOptions() {
  const gi = (B.ia && B.ia.GID) || [], recs = (B.IA || []).filter((r) => r.status === 'live' && r.route !== 'home' && r.drawer !== false && r.route !== 'owner').sort((a, b) => gi.indexOf(a.group) - gi.indexOf(b.group));
  return recs.map((r) => ({ v: r.route, l: B.ia.label(r), g: B.ia.groupLabel(r.group) }));
}
async function editSheet(cid) {
  const it = byCid(cid); if (!it) return; const k = KINDS[it.widget], c = it.config || {}, v = ST.vals[cid];
  const num = (key) => (c[key] === undefined || c[key] === null ? '' : String(c[key]));
  let extra = '';
  if (k.cfg === 'note') extra = `<div class="fld"><label for="ob_text">${esc(T('text'))}</label><input id="ob_text" maxlength="300" value="${esc(c.text || '')}"></div><div class="fld"><label for="ob_rep">${esc(T('rep'))}</label><select id="ob_rep">${['daily', 'weekly', 'never'].map((r) => `<option value="${r}" ${(c.repeat || 'daily') === r ? 'selected' : ''}>${esc(T('r_' + r))}</option>`).join('')}</select></div>`;
  if (k.cfg === 'report') { const cat = await reportCatalog(); extra = `<div class="fld"><label for="ob_report">${esc(T('report'))}</label><select id="ob_report"><option value=""></option>${cat.map((r) => `<option value="${esc(r.key)}" ${c.report === r.key ? 'selected' : ''}>${esc(lab({ bn: r.name_bn, en: r.name_en || r.name_bn, mix: r.name_mix || r.name_bn }))}</option>`).join('')}</select></div>
    <div class="fld"><label for="ob_prs">${esc(T('period'))}</label><select id="ob_prs">${['today', 'yesterday', 'this_week', 'this_month', 'last_30'].map((p) => `<option value="${p}" ${(c.preset || 'today') === p ? 'selected' : ''}>${esc(B.filters && B.filters.presetName ? B.filters.presetName(p) : p)}</option>`).join('')}</select></div>`; }
  if (k.cfg === 'page') extra = `<div class="fld"><label for="ob_route">${esc(T('page'))}</label><select id="ob_route"><option value=""></option>${pageOptions().map((o) => `<option value="${esc(o.v)}" ${c.route === o.v ? 'selected' : ''}>${esc(o.g + ' › ' + o.l)}</option>`).join('')}</select></div>`;
  if (k.cfg === 'counter') extra = `<div class="fld"><label for="ob_preset">${esc(T('preset'))}</label><select id="ob_preset"><option value=""></option>${Object.keys(COUNTERS).map((p) => `<option value="${p}" ${c.preset === p ? 'selected' : ''}>${esc(lab(COUNTERS[p].l))}</option>`).join('')}</select></div>`;
  if (it.widget === 'cust_dues') extra = `<div class="fld"><label for="ob_days">${esc(T('days'))}</label><input id="ob_days" inputmode="numeric" value="${esc(num('days'))}" placeholder="30"></div>`;
  const lim = k.num ? `<h3 style="margin:10px 0 4px">${esc(T('lim'))}</h3><div class="row wrap">${[['warn_gt', 'wgt'], ['bad_gt', 'bgt'], ['warn_lt', 'wlt'], ['bad_lt', 'blt']].map(([key, lb]) => `<div class="fld" style="flex:1 1 140px"><label for="ob_${key}">${esc(T(lb))}</label><input id="ob_${key}" inputmode="decimal" value="${esc(num(key))}"></div>`).join('')}</div>` : '';
  openSheet(`<h2>${esc(kindLabel(it.widget))}</h2><div class="stack" id="ob_form" data-cid="${esc(cid)}">
    <div class="fld"><label for="ob_label">${esc(T('name'))}</label><input id="ob_label" maxlength="80" value="${esc(c.label || '')}" placeholder="${esc((v && v.name) || kindLabel(it.widget))}"></div>
    <div class="fld"><label for="ob_size">${esc(T('size'))}</label><select id="ob_size"><option value="compact" ${c.size !== 'wide' ? 'selected' : ''}>${esc(T('compact'))}</option><option value="wide" ${c.size === 'wide' ? 'selected' : ''}>${esc(T('wide'))}</option></select></div>
    ${extra}${lim}
    <label class="row" style="min-height:44px;gap:8px"><input type="checkbox" id="ob_en" ${it.enabled !== false ? 'checked' : ''}><span>${esc(T('enabled'))}</span></label>
    <button class="primary full" data-act="ob_save" data-cid="${esc(cid)}">${esc(T('save'))}</button></div>`);
}
function saveEdit(cid) {
  const it = byCid(cid); if (!it) return; const k = KINDS[it.widget], g = (id) => { const e = $('#' + id); return e ? e.value.trim() : ''; };
  const cfg = Object.assign({}, it.config); const set = (key, val) => { if (val === '' || val === undefined || val === null) delete cfg[key]; else cfg[key] = val; };
  set('label', g('ob_label')); set('size', g('ob_size') === 'wide' ? 'wide' : undefined);
  if (k.num) { for (const key of ['warn_gt', 'bad_gt', 'warn_lt', 'bad_lt']) { const s = g('ob_' + key); if (s === '') { delete cfg[key]; continue; } const n = Number(s); if (!Number.isFinite(n) || Math.abs(n) > 1e12) return toast(T('badnum')); cfg[key] = n; } }
  if (k.cfg === 'note') { set('text', g('ob_text')); set('repeat', g('ob_rep') || 'daily'); if (!cfg.label && !cfg.text) cfg.text = lab(X.text); }
  if (k.cfg === 'report') { set('report', g('ob_report')); set('preset', g('ob_prs')); const o = $('#ob_report'); if (o && o.value && !cfg.label) { /* name comes from the report itself */ } }
  if (k.cfg === 'page') set('route', g('ob_route'));
  if (k.cfg === 'counter') set('preset', g('ob_preset'));
  if (it.widget === 'cust_dues') { const d = g('ob_days'); if (d === '') delete cfg.days; else { const n = Math.floor(Number(d)); if (!(n > 0 && n <= 3650)) return toast(T('badnum')); cfg.days = n; } }
  it.config = cfg; it.enabled = !!($('#ob_en') || {}).checked; delete ST.vals[cid]; closeSheet(); draw(); persist(true); refresh();
}

// ---------- add widget ----------
const GROUP_ORDER = ['sales', 'cash', 'appr', 'money', 'stock', 'sys', 'custom'];
async function addSheet() {
  openSheet(`<h2>${esc(T('add'))}</h2><input id="ob_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}"><div id="ob_cat" style="margin:8px 0">${B.ui.state('loading', T('checking'))}</div>`);
  await probeCatalog(); drawCatalog('');
}
function drawCatalog(q) {
  const box = $('#ob_cat'); if (!box) return; const ql = (q || '').trim().toLowerCase();
  const ks = Object.keys(KINDS).filter((k) => ST.av[k] !== false && (!ql || kindLabel(k).toLowerCase().includes(ql) || lab(X['g_' + KINDS[k].g]).toLowerCase().includes(ql)));
  box.innerHTML = GROUP_ORDER.map((g) => { const l = ks.filter((k) => KINDS[k].g === g); return l.length ? `<div class="hsec">${esc(lab(X['g_' + g]))}</div>${l.map((k) => `<button class="hrow" data-act="ob_addk" data-k="${esc(k)}"><span>${esc(kindLabel(k))}</span><span class="cv">＋</span></button>`).join('')}` : ''; }).join('') || B.ui.state('empty', T('nores'));
}
function addKind(k) {
  const it = { cid: gid(), widget: k, config: k === 'note' ? { repeat: 'daily' } : {}, enabled: true };
  ST.items.push(it); closeSheet(); draw(); persist(true);
  if (KINDS[k].cfg) editSheet(it.cid); else { refresh(); toast(T('added')); }
  setTimeout(() => { const e = document.querySelector(`.ob-w[data-cid="${it.cid}"]`); if (e && e.scrollIntoView) e.scrollIntoView({ block: 'nearest' }); }, 50);
}

// ---------- handlers ----------
const setEdit = (on) => { ST.edit = on; draw(); };
Object.assign(H, {
  ob_refresh: () => refresh(true),
  ob_edit_toggle: () => setEdit(!ST.edit),
  obd_open: (a) => { const it = byCid(a.dataset.cid), v = it && ST.vals[it.cid]; const r = (v && v.route) || (it && KINDS[it.widget].route) || 'home'; location.hash = '#/' + r; },
  ob_edit: (a) => editSheet(a.dataset.cid),
  ob_tick: (a) => { const it = byCid(a.dataset.cid); if (!it) return; const c = Object.assign({}, it.config), td = dhaka(); if (noteDone(c, td)) delete c.done_on; else c.done_on = c.repeat === 'weekly' ? weekStart(td) : td; it.config = c; draw(); persist(true); },
  ob_mv: (a) => move(a.dataset.cid, a.dataset.d),
  ob_menu: (a) => itemMenu(a.dataset.cid),
  ob_save: (a) => saveEdit(a.dataset.cid),
  ob_add: addSheet,
  ob_addk: (a) => addKind(a.dataset.k),
  ob_reset: () => { if (!window.confirm(T('confirm_reset'))) return; ST.items = defaults(); ST.vals = {}; draw(); persist(true); refresh(); },
  ob_home_off: () => { try { store.set('bos_ownermode_' + uid(), '0'); } catch (e) { /* ignore */ } window.dispatchEvent(new HashChangeEvent('hashchange')); },
});
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'ob_q') drawCatalog(e.target.value); });
window.addEventListener('online', () => { if ($('#ob_main')) { loadItems().then(() => { draw(); refresh(); }); } });
window.addEventListener('offline', () => { if ($('#ob_main')) drawBar(); });

// ---------- page ----------
function css() {
  if (document.getElementById('ob_css')) return; const s = document.createElement('style'); s.id = 'ob_css';
  s.textContent = `#ob_main .ob-bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:4px 0 10px}#ob_main .ob-at{flex:1 1 auto;font-size:.8rem;color:var(--muted);min-width:0}
  #ob_main .ob-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}#ob_main .ob-w{position:relative;border:1px solid var(--hair);border-radius:14px;background:var(--card);min-width:0;overflow:hidden}
  #ob_main .ob-w.wide{grid-column:1/-1}#ob_main .ob-w.off{opacity:.55}#ob_main .ob-main{display:flex;flex-direction:column;align-items:flex-start;gap:2px;width:100%;min-height:88px;padding:10px 12px;border:0;background:transparent;color:var(--ink);text-align:start;font:inherit;border-radius:0}
  #ob_main .ob-main .k{font-size:.8rem;color:var(--muted);overflow-wrap:anywhere}#ob_main .ob-main .v{font-weight:700;font-size:1.35rem;line-height:1.2;overflow-wrap:anywhere;font-variant-numeric:lining-nums tabular-nums}#ob_main .ob-main .s{font-size:.76rem;color:var(--muted);overflow-wrap:anywhere}
  #ob_main .ob-ed{display:flex;gap:2px;border-top:1px solid var(--hair);justify-content:flex-end}#ob_main .ob-ed button{min-width:44px;min-height:44px;border:0;background:transparent;color:var(--ink);font-size:1.1rem}#ob_main .ob-ed button[disabled]{opacity:.3}
  #ob_main .ob-bar button{min-height:40px;min-width:40px}#ob_main .ob-edit button{min-height:44px}#ob_main .ob-edit{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 10px}`;
  document.head.appendChild(s);
}
const isOn = () => { try { return B.rule('owner_board_on', true) !== false; } catch (e) { return true; } };
async function view(opts) {
  opts = opts || {}; css();
  if (!S.ctx || !S.ctx.is_owner) { location.hash = '#/home'; return; }
  ST.home = !!opts.home; ST.edit = false;
  const title = ST.home ? A.t('app') : T('title');
  shell(title, `<div id="ob_main"><p class="muted center pad">${esc(T('loading'))}</p></div>`, !ST.home);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  if (!$('#ob_main')) return;
  if (!isOn()) { $('#ob_main').innerHTML = `<div class="notice warn" data-state="off">${esc(T('off'))}</div>${ST.home ? `<button class="full" data-act="ob_home_off">${esc(T('home_off'))}</button>` : ''}`; return; }
  await loadItems(); if (!$('#ob_main')) return;
  ST.vals = {}; ST.asOf = null;
  $('#ob_main').innerHTML = `${ST.home ? '' : `<p class="muted" style="margin:0 0 4px">${esc(T('sub'))}</p>`}<div class="ob-bar" id="ob_bar" data-ctl="off"></div><div id="ob_note"></div><div class="ob-edit" id="ob_editbar" data-ctl="off"></div><div class="ob-grid" id="ob_grid" data-ctl="off"></div>`;
  draw(); await refresh();
  clearInterval(ST.timer); ST.timer = setInterval(() => { if (!$('#ob_main')) { clearInterval(ST.timer); return; } if (document.hidden || ST.edit || document.querySelector('#sheet,.ctl-bg')) return; refresh(); }, REFRESH_MS());
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { owner: () => view({ home: false }) });
B.ownerboard = { view, isOn, refresh, KINDS, defaults, state: ST };
})();
