/* Islamia BOS · Error log for a phone-only owner (step Errlog, phase107, tag bos107). NEW file; no existing file is rewritten.
   WHY: the owner cannot open a browser console. When a screen breaks nothing told us. This file sends a small, anonymised note to the server (client_error_log, phase107):
     script error (window error) · unhandled promise rejection · an rpc call that failed for a NON-business reason (system / network / missing function) · a note typed in "Report a problem".
   WHEN: automatic capture only while the rule client_errors_on is true (default OFF). The rule is read ONCE per session (B.rule when the rules are already loaded, else one single-row read);
     the last answer is kept in localStorage so the next start captures from the first second. Rule off (or not yet known) => no window listener, no sb.rpc wrapper, no timer, nothing sent.
     "Report a problem" works even while the rule is off (a person pressed Send on purpose): it starts a flush timer only while its note waits.
   NEVER: a business error (raise exception, constraint, permission) is not logged; nothing is logged while the phone is offline (network failures); request bodies / arguments / tokens / customer data are never read.
     Messages lose JWT-looking strings, e-mail addresses and digit runs of 8+; routes lose the query string and ids. The server cleans again (defence in depth).
   HOW: batches (max 20) from a memory queue mirrored to localStorage (max 50, oldest dropped); one flush every 30 s and on visibilitychange(hidden) / pagehide / online; one attempt per tick, exponential back-off
     after a failure (30 s .. 10 min), gives up after 8 failures; the flush calls the ORIGINAL rpc so logging can never log itself; every entry point is try/catch and never throws.
   SCREENS: #/reportproblem (everybody: note <= 1000, shows exactly what will be sent, Send -> kind user_report, queued when offline; also a button in the drawer footer bar)
            #/problems (owner, or a holder of view_client_errors who opens the link): grouped by fingerprint, count, last seen, route, Resolve, filter open / resolved, copy as text.
   data-act names start with er_. Language rule: English mode is all English; Bangla mode keeps common words English; mix = Bng/Eng. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B || (B.errlog && B.errlog.loaded)) return;
const { sb, S, esc, toast, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);

/* ---------- storage (every access guarded) ---------- */
const LS = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private window / full */ } },
  del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } },
};
const K_Q = 'bos_er_q', K_ON = 'bos_er_on', K_REC = 'bos_er_recent', K_CID = 'bos_er_cid';
const MAXQ = 50, BATCH = 20, MAX_FAILS = 8;
const flushMs = () => Number(window.__ER_FLUSH_MS) || 30000;
const st = { on: false, installed: false, infra: false, q: [], recent: [], busy: false, fails: 0, next: 0, timer: null, inLog: 0, orig: null, patched: false, ruleDone: false, tries: 0, prev: null, prevAt: 0, win: { m: 0, n: 0 }, cid: null, sent: 0, dropped: 0 };

/* ---------- texts ---------- */
const X = {
  foot: L('সমস্যা জানান', 'Report a problem', 'Problem জানান'),
  rp_title: L('সমস্যা জানান', 'Report a problem', 'Problem জানান'),
  rp_intro: L('কোনো স্ক্রিন ভুল দেখালে বা ভেঙে গেলে এখানে লিখে পাঠান। নিচে দেখুন ঠিক কী কী পাঠানো হবে।', 'If a screen shows something wrong or breaks, write it here and send it. Below you can see exactly what will be sent.', 'কোনো screen ভুল দেখালে বা ভেঙে গেলে এখানে লিখে পাঠান। নিচে দেখুন ঠিক কী কী পাঠানো হবে।'),
  rp_note: L('কী হয়েছে? (সর্বোচ্চ ১০০০ অক্ষর)', 'What happened? (up to 1000 characters)', 'কী হয়েছে? (max 1000 অক্ষর)'),
  rp_ph: L('যেমন: বিক্রির পাতায় মোট ভুল দেখাচ্ছে', 'For example: the total on the sale screen looks wrong', 'যেমন: sale পাতায় total ভুল দেখাচ্ছে'),
  rp_will: L('যা পাঠানো হবে', 'What will be sent', 'যা পাঠানো হবে'),
  rp_route: L('স্ক্রিন', 'Screen', 'Screen'), rp_build: L('অ্যাপ সংস্করণ', 'App build', 'App build'), rp_lang: L('ভাষা', 'Language', 'ভাষা'),
  rp_last: L('শেষ ৫টি ত্রুটি', 'Last 5 errors', 'শেষ ৫টি error'),
  rp_none: L('এই ফোনে কোনো ত্রুটি ধরা পড়েনি', 'No error was captured on this phone', 'এই phone এ কোনো error ধরা পড়েনি'),
  rp_priv: L('পাসওয়ার্ড, টোকেন, গ্রাহকের তথ্য বা বিক্রির হিসাব পাঠানো হয় না।', 'No password, token, customer data or sale figures are sent.', 'Password, token, customer এর তথ্য বা sale এর হিসাব পাঠানো হয় না।'),
  send: L('পাঠান', 'Send', 'Send'),
  need_note: L('আগে কয়েক শব্দ লিখুন', 'Write a few words first', 'আগে কয়েক শব্দ লিখুন'),
  sent: L('পাঠানো হয়েছে। ধন্যবাদ।', 'Sent. Thank you.', 'পাঠানো হয়েছে। Thank you।'),
  queued: L('ফোনে রাখা হয়েছে; নেট এলে নিজে থেকে যাবে।', 'Saved on this phone; it will be sent when the network is back.', 'Phone এ রাখা হয়েছে; net এলে নিজে থেকে যাবে।'),
  pr_title: L('অ্যাপের সমস্যা', 'App problems', 'App এর problems'),
  pr_intro: L('ফোন বা কম্পিউটারে যে ভুলগুলো ধরা পড়েছে, একই ভুল একসাথে।', 'Errors caught on phones and computers, the same error grouped together.', 'Phone বা computer এ যে error ধরা পড়েছে, একই error একসাথে।'),
  pr_off: L('স্বয়ংক্রিয় সংগ্রহ বন্ধ আছে (client_errors_on)। চালু করা ভালো: সেটিংস > সুইচ।', 'Automatic collection is off (client_errors_on). Turning it on is recommended: Settings > switches.', 'Automatic collection বন্ধ আছে (client_errors_on)। চালু করা ভালো: Settings > switches।'),
  open: L('খোলা', 'Open', 'Open'), resolved: L('সমাধান হয়েছে', 'Resolved', 'Resolved'), all: L('সব', 'All', 'All'),
  resolve: L('সমাধান হয়েছে', 'Resolve', 'Resolve'), rnote: L('সমাধানের নোট (ঐচ্ছিক)', 'Resolve note (optional)', 'Resolve note (optional)'),
  copy: L('লেখা হিসেবে কপি', 'Copy as text', 'Text হিসেবে copy'), refresh: L('আবার আনুন', 'Refresh', 'Refresh'),
  copied: L('কপি হয়েছে', 'Copied', 'Copied'), copy_manual: L('নিচের লেখা বেছে কপি করুন', 'Select the text below and copy it', 'নিচের text বেছে copy করুন'),
  count: L('বার', 'times', 'বার'), last: L('শেষ', 'last', 'last'), users: L('জন', 'users', 'user'),
  none: L('কোনো সমস্যা নেই ✓', 'No problems ✓', 'কোনো problem নেই ✓'),
  noaccess: L('এটি দেখতে মালিক বা অনুমতি লাগবে।', 'You need to be the owner or have permission to see this.', 'এটা দেখতে owner বা permission লাগবে।'),
  loading: L('আনা হচ্ছে…', 'Loading…', 'Loading…'),
  fail: L('আনা যায়নি', 'Could not load', 'Load করা যায়নি'),
  done: L('সমাধান করা হয়েছে', 'Marked resolved', 'Resolved করা হয়েছে'),
  by: L('সংস্করণ', 'build', 'build'), note: L('নোট', 'note', 'note'),
};
const T = (k) => (X[k] ? lab(X[k]) : k);

/* ---------- helpers ---------- */
const now = () => Date.now();
const rid = () => Math.random().toString(36).slice(2, 10) + now().toString(36).slice(-4);
const clientId = () => { if (st.cid) return st.cid; let c = LS.get(K_CID); if (!c) { c = 'd' + rid(); LS.set(K_CID, c); } st.cid = c; return c; };
function scrub(s, max) {
  if (s === null || s === undefined) return '';
  return String(s).replace(/eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+){0,2}/g, '[jwt]').replace(/Bearer\s+[^\s"',;]+/gi, 'Bearer [x]')
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[email]').replace(/[0-9০-৯]{8,}/g, '[num]').slice(0, max);
}
function normRoute(r) {
  let x = String(r === undefined || r === null ? '' : r).split('?')[0];
  x = x.replace(/[#&;]?(access_token|refresh_token|token|key|apikey)=.*$/i, '');
  x = x.replace(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g, ':id').replace(/\/[0-9]{2,}(?=\/|$)/g, '/:id');
  return x.slice(0, 200);
}
const curRoute = () => normRoute(location.hash || '#/home');
function appBuild() {
  try {
    for (const s of document.querySelectorAll('script[src]')) { const m = /[?&]v=([A-Za-z0-9._-]{1,40})/.exec(s.getAttribute('src') || ''); if (m) return m[1]; }
    const m2 = /[?&]v=([A-Za-z0-9._-]{1,40})/.exec(location.search || ''); if (m2) return m2[1];
  } catch (e) { /* ignore */ }
  return 'dev';
}
const langNow = () => { try { return (S && S.lang) || 'bn'; } catch (e) { return 'bn'; } };
const cleanStack = (s) => scrub(String(s || '').replace(/https?:\/\/[^\s/)]+/g, '').replace(/\?[^\s:)]*/g, ''), 2000);
const online = () => navigator.onLine !== false;

/* ---------- the queue ---------- */
function persist() { try { LS.set(K_Q, JSON.stringify(st.q.slice(-MAXQ))); } catch (e) { /* ignore */ } }
function loadQ() {
  try { const v = JSON.parse(LS.get(K_Q) || '[]'); if (Array.isArray(v)) st.q = v.filter((x) => x && typeof x === 'object' && typeof x.kind === 'string' && typeof x.cid === 'string').slice(-MAXQ); } catch (e) { st.q = []; }
  try { const r = JSON.parse(LS.get(K_REC) || '[]'); if (Array.isArray(r)) st.recent = r.filter((x) => x && typeof x.m === 'string').slice(0, 5); } catch (e) { st.recent = []; }
}
function enqueue(item) {
  const k = item.kind + '|' + String(item.message || '').split('\n')[0].replace(/[0-9]+/g, '#') + '|' + item.route;
  if (item.kind !== 'user_report') {
    const same = st.q.find((x) => x.kind !== 'user_report' && x.k === k);
    if (same) { same.count = Math.min((same.count || 1) + 1, 1000); persist(); return same; }
  }
  item.k = k; item.count = item.count || 1;
  st.q.push(item); while (st.q.length > MAXQ) { st.q.shift(); st.dropped++; }
  persist(); return item;
}
function remember(kind, message, route) {
  st.recent.unshift({ t: new Date().toISOString(), k: kind, m: String(message || '').split('\n')[0].slice(0, 120), r: route }); st.recent = st.recent.slice(0, 5);
  LS.set(K_REC, JSON.stringify(st.recent));
}
// kind: js_error | unhandled_rejection | rpc_error. Never throws, never recurses.
function report(kind, message, stack, extra) {
  if (st.inLog) return false;
  st.inLog++;
  try {
    const m = Math.floor(now() / 60000);
    if (st.win.m !== m) st.win = { m, n: 0 };
    if (++st.win.n > 20) { st.dropped++; return false; }                       // runaway guard on the phone itself: 20 per minute
    const route = curRoute(), msg = scrub(message, 500);
    if (!msg) return false;
    enqueue({ cid: rid(), kind, message: msg, stack: cleanStack(stack), route, app_build: appBuild(), lang: langNow(), ua: String(navigator.userAgent || '').slice(0, 200), extra: extra || null, count: 1 });
    remember(kind, msg, route);
    return true;
  } catch (e) { return false; } finally { st.inLog--; }
}

/* ---------- classification of rpc errors: business errors are never logged ---------- */
function systemError(err) {
  if (!err) return false;
  const code = String(err.code || '');
  if (code === 'P0001' || /^23/.test(code) || code === '42501' || /^28/.test(code) || code === 'PGRST116' || code === 'PGRST301' || code === 'PGRST302') return false;
  if (/^(42|22|XX|53|54|55|57|58|08|PGRST)/.test(code)) return true;
  if (!code) return /fetch|network|load failed|timeout|timed out|aborted|failed to|5\d\d/i.test(String(err.message || err)) && online();
  return false;
}
function observe(fn, v, e) {
  try {
    if (!st.on || fn === 'client_error_log') return;
    const err = e || (v && v.error);
    if (!err || !systemError(err)) return;
    report('rpc_error', 'rpc ' + fn + ': ' + (err.message || err), '', { fn: String(fn).slice(0, 60), code: String(err.code || '').slice(0, 12) });
  } catch (x) { /* never throws */ }
}
function wrapRpc() {
  if (st.patched || !sb || typeof sb.rpc !== 'function') return;
  const orig = sb.rpc; st.orig = orig;
  const w = function (fn) {
    const p = orig.apply(sb, arguments);
    try {
      if (!st.on || fn === 'client_error_log' || !p || typeof p.then !== 'function') return p;
      if (p instanceof Promise) return p.then((v) => { observe(fn, v); return v; }, (e) => { observe(fn, null, e); throw e; });
      const ot = p.then.bind(p);                                                  // a query builder: keep it chainable, observe on its own then
      p.then = function (res, rej) { return ot((v) => { observe(fn, v); return res ? res(v) : v; }, (e) => { observe(fn, null, e); if (rej) return rej(e); throw e; }); };
      return p;
    } catch (x) { return p; }
  };
  w.__erWrap = true; sb.rpc = w; st.patched = true;
}
function unwrapRpc() { if (st.patched && sb.rpc && sb.rpc.__erWrap && st.orig) sb.rpc = st.orig; st.patched = false; }

/* ---------- window listeners ---------- */
function onErr(ev) {
  try {
    if (!ev) return;
    const file = String(ev.filename || '');
    if (/^(chrome|moz|safari)-extension:/.test(file)) return;
    const msg = ev.message || (ev.error && ev.error.message) || '';
    if (!msg || /^Script error\.?$/.test(msg) || /ResizeObserver loop/.test(msg)) return;
    const base = file.split('?')[0].split('/').pop();
    report('js_error', msg + (base ? ' @ ' + base + ':' + (ev.lineno || 0) + ':' + (ev.colno || 0) : ''), ev.error && ev.error.stack, { file: base || '', line: Number(ev.lineno) || 0, col: Number(ev.colno) || 0 });
  } catch (e) { /* never throws */ }
}
function onRej(ev) {
  try {
    const r = ev && ev.reason;
    if (r && typeof r === 'object' && ('code' in r) && !systemError(r)) return;      // a rejected business error object
    const msg = r && r.message ? r.message : typeof r === 'string' ? r : 'unhandled rejection';
    if (/^(AbortError|The user aborted|Load failed|Failed to fetch|NetworkError)/i.test(String(msg)) && !online()) return;
    report('unhandled_rejection', msg, r && r.stack, null);
  } catch (e) { /* never throws */ }
}

/* ---------- flushing ---------- */
const onVis = () => { if (document.visibilityState === 'hidden') flush(true); };
const onHide = () => { flush(true); };
const onOnline = () => { flush(true); };
function startInfra() {
  if (st.infra) return; st.infra = true;
  st.timer = setInterval(() => { flush(false); }, flushMs());
  document.addEventListener('visibilitychange', onVis); window.addEventListener('pagehide', onHide); window.addEventListener('online', onOnline);
}
function stopInfra() {
  if (!st.infra) return; st.infra = false;
  if (st.timer) { clearInterval(st.timer); st.timer = null; }
  document.removeEventListener('visibilitychange', onVis); window.removeEventListener('pagehide', onHide); window.removeEventListener('online', onOnline);
}
const hasReports = () => st.q.some((x) => x.kind === 'user_report');
function fail() { st.fails++; st.next = now() + Math.min(30000 * Math.pow(2, st.fails - 1), 600000); if (st.fails >= MAX_FAILS) { st.q = st.q.filter((x) => x.kind === 'user_report'); st.fails = MAX_FAILS - 2; st.dropped++; } }
async function flush(force) {
  try {
    if (st.busy || !st.q.length || !online()) return;
    if (now() < st.next) return;                                                  // a forced flush (tab hidden / online) also respects the back-off: no retry storm
    if (!st.on && !hasReports()) return;
    st.busy = true;
    const batch = st.q.slice(0, BATCH), ids = new Set(batch.map((x) => x.cid));
    const payload = batch.map((x) => ({ cid: x.cid, kind: x.kind, message: x.message, stack: x.stack, route: x.route, app_build: x.app_build, lang: x.lang, ua: x.ua, extra: x.extra, note: x.note, count: x.count }));
    const call = (st.orig || sb.rpc).call(sb, 'client_error_log', { p_client: clientId(), p_batch: payload });
    const r = await Promise.race([Promise.resolve(call), new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 8000))]);
    const d = r && !r.error ? r.data : null;
    if (d && (d.ok === true || d.error === 'bad_batch')) { st.q = st.q.filter((x) => !ids.has(x.cid)); st.fails = 0; st.next = 0; st.sent += batch.length; }
    else fail();
  } catch (e) { fail(); } finally {
    st.busy = false; persist();
    try { if (!st.q.length && !st.installed) stopInfra(); } catch (e2) { /* ignore */ }
  }
}

/* ---------- install / uninstall (what the rule switches) ---------- */
function install() {
  if (st.installed) return; st.installed = true; st.on = true;
  window.addEventListener('error', onErr); window.addEventListener('unhandledrejection', onRej);
  wrapRpc(); startInfra();
  if (st.q.length) flush(false);
}
function uninstall() {
  const was = st.installed; st.installed = false; st.on = false;
  if (was) { window.removeEventListener('error', onErr); window.removeEventListener('unhandledrejection', onRej); }
  unwrapRpc();
  st.q = st.q.filter((x) => x.kind === 'user_report'); persist();
  if (!st.q.length) stopInfra();
}
const schedule = () => {
  if (st.ruleDone) return;
  const d = st.tries < 12 ? Math.min(200 * Math.pow(2, st.tries), 15000) : 60000;
  if (++st.tries > 40) return;                                                    // gives up quietly (not signed in for a very long time)
  setTimeout(resolveRule, d);
};
async function resolveRule() {
  if (st.ruleDone) return;
  try {
    if (!(S && S.ctx)) return schedule();
    let on;
    if (B.ENV && B.ENV.rules && typeof B.rule === 'function') on = B.rule('client_errors_on', false) === true;
    else {
      const r = await sb.from('rules').select('key,value,default_value').eq('key', 'client_errors_on').maybeSingle();
      if (!r || r.error) return schedule();
      const row = r.data; const v = row ? (row.value !== null && row.value !== undefined ? row.value : row.default_value) : false;
      on = v === true;
    }
    st.ruleDone = true; LS.set(K_ON, on ? '1' : '0');
    if (on) install(); else uninstall();
  } catch (e) { schedule(); }
}

/* ---------- drawer footer entry ---------- */
function injectCss() {
  if (document.getElementById('er-css')) return;
  const s = document.createElement('style'); s.id = 'er-css';
  s.textContent = '.er-foot{min-height:44px;margin-left:auto;padding:0 10px;background:transparent;color:var(--ink);border:1px solid var(--hair);border-radius:10px;font-size:.85rem;cursor:pointer}'
    + '.er-grp{border:1px solid var(--hair);border-radius:12px;padding:10px;display:grid;gap:6px}.er-grp.res{opacity:.7}.er-msg{font-weight:600;word-break:break-word}.er-meta{font-size:.85rem;color:var(--muted);word-break:break-word}'
    + '.er-pre{white-space:pre-wrap;word-break:break-all;font-size:.78rem;max-height:9rem;overflow:auto;margin:0}.er-ta{width:100%;box-sizing:border-box;min-height:7rem}.er-box{width:100%;box-sizing:border-box;min-height:9rem;font-size:.8rem}';
  document.head.appendChild(s);
}
function syncFoot() {
  try {
    const bar = $('#navDrawer .dr-fbar'); if (!bar) return;
    const old = bar.querySelector('[data-act=er_open]');
    if (old) { if (old.textContent !== T('foot')) old.textContent = T('foot'); return; }
    injectCss();
    const b = document.createElement('button'); b.type = 'button'; b.className = 'er-foot'; b.setAttribute('data-act', 'er_open'); b.textContent = T('foot'); bar.appendChild(b);
  } catch (e) { /* the entry is a convenience */ }
}
function watchDrawer() {
  if (!window.MutationObserver || !document.body) return;
  const attach = (d) => { new MutationObserver(syncFoot).observe(d, { childList: true }); syncFoot(); };
  const d = document.getElementById('navDrawer'); if (d) return attach(d);
  const mo = new MutationObserver(() => { const d2 = document.getElementById('navDrawer'); if (d2) { mo.disconnect(); attach(d2); } });
  mo.observe(document.body, { childList: true });
}

/* ---------- #/reportproblem ---------- */
function prevRoute() {
  if (st.prev && now() - st.prevAt < 120000) return st.prev;
  try { const uid = S && S.ctx && S.ctx.profile && S.ctx.profile.id; const r = (B.ia && B.ia.recent ? B.ia.recent(uid) : []).find((x) => x && x !== 'reportproblem'); if (r) return normRoute('#/' + r); } catch (e) { /* ignore */ }
  return '';
}
function viewReport() {
  injectCss();
  const route = prevRoute() || '(unknown)', build = appBuild(), lang = langNow();
  const last = st.recent.slice(0, 5);
  const lastHtml = last.length ? `<ul style="margin:.25rem 0;padding-left:1.1rem">${last.map((x) => `<li class="er-meta">${esc(x.k)} · ${esc(x.m)} · ${esc(x.r || '')}</li>`).join('')}</ul>` : `<div class="er-meta">${esc(T('rp_none'))}</div>`;
  shell(T('rp_title'), `<div id="er_body"><p class="muted">${esc(T('rp_intro'))}</p>
    <div class="card stack"><label for="er_note"><b>${esc(T('rp_note'))}</b></label>
      <textarea id="er_note" class="er-ta" maxlength="1000" rows="4" placeholder="${esc(T('rp_ph'))}"></textarea><div class="muted" id="er_cnt">0 / 1000</div></div>
    <div class="card stack"><b>${esc(T('rp_will'))}</b>
      <div class="er-meta">${esc(T('rp_route'))}: <b>${esc(route)}</b></div><div class="er-meta">${esc(T('rp_build'))}: <b>${esc(build)}</b></div><div class="er-meta">${esc(T('rp_lang'))}: <b>${esc(lang)}</b></div>
      <div class="er-meta">${esc(T('rp_last'))}:</div>${lastHtml}<div class="muted">${esc(T('rp_priv'))}</div></div>
    <button type="button" class="primary full" data-act="er_send">${esc(T('send'))}</button><div id="er_res" role="status" aria-live="polite"></div></div>`, true);
  const ta = $('#er_note'); if (ta) ta.addEventListener('input', () => { const c = $('#er_cnt'); if (c) c.textContent = ta.value.length + ' / 1000'; });
}
async function sendReport() {
  const ta = $('#er_note'), note = String((ta && ta.value) || '').trim().slice(0, 1000);
  if (!note) return toast(T('need_note'));
  const btn = $('[data-act=er_send]'); if (btn) btn.disabled = true;
  const item = { cid: 'r' + rid(), kind: 'user_report', message: 'User report', stack: '', route: prevRoute() || '(unknown)', app_build: appBuild(), lang: langNow(), ua: String(navigator.userAgent || '').slice(0, 200),
    note, extra: { recent: st.recent.slice(0, 5).map((x) => ({ k: x.k, m: x.m, r: x.r })) }, count: 1 };
  try {
    enqueue(item); startInfra();
    st.next = 0; await flush(true);
    const still = st.q.some((x) => x.cid === item.cid);
    const res = $('#er_res'); if (res) res.innerHTML = `<div class="notice ${still ? 'warn' : ''}">${esc(still ? T('queued') : T('sent'))}</div>`;
    if (!still && ta) { ta.value = ''; const c = $('#er_cnt'); if (c) c.textContent = '0 / 1000'; }
  } catch (e) { const res = $('#er_res'); if (res) res.innerHTML = `<div class="notice warn">${esc(T('queued'))}</div>`; }
  if (btn) btn.disabled = false;
}

/* ---------- #/problems ---------- */
const PR = { rows: null, filter: 'open', err: null, loading: false };
const fmtT = (x) => { try { return new Date(x).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', hour12: false, day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }); } catch (e) { return String(x || ''); } };
function groups() {
  const m = new Map();
  (PR.rows || []).forEach((r) => {
    const k = r.fingerprint || 'id' + r.id; let g = m.get(k);
    if (!g) { g = { fp: k, kind: r.kind, message: r.message || r.user_note || '', route: r.route || '', count: 0, last: r.last_at, first: r.at, users: new Set(), builds: new Set(), ids: [], openIds: [], stack: r.stack || '', notes: [], ua: r.ua || '', latest: r.id }; m.set(k, g); }
    g.count += Number(r.count) || 1; if (r.last_at > g.last) g.last = r.last_at; if (r.at < g.first) g.first = r.at; if (r.user_id) g.users.add(r.user_id); else if (r.staff_id) g.users.add(r.staff_id);
    if (r.app_build) g.builds.add(r.app_build); g.ids.push(r.id); if (!r.resolved_at) g.openIds.push(r.id); if (r.user_note) g.notes.push(r.user_note);
    if (r.id > g.latest) { g.latest = r.id; if (r.stack) g.stack = r.stack; }
  });
  const out = [...m.values()].map((g) => Object.assign(g, { resolved: g.openIds.length === 0 }));
  return out.filter((g) => PR.filter === 'all' || (PR.filter === 'open' ? !g.resolved : g.resolved)).sort((a, b) => (a.last < b.last ? 1 : -1));
}
function groupText(g, i) {
  const head = `${i + 1}. [${g.kind}] ${g.count}x · last ${fmtT(g.last)} · ${g.route || '-'} · build ${[...g.builds].join('/') || '-'} · ${g.users.size} user(s)${g.resolved ? ' · RESOLVED' : ''}`;
  const lines = [head, '   ' + String(g.message).split('\n')[0].slice(0, 300)];
  if (g.stack) lines.push('   ' + String(g.stack).split('\n').slice(0, 3).join('\n   ').slice(0, 400));
  g.notes.slice(0, 3).forEach((n) => lines.push('   note: ' + String(n).slice(0, 300)));
  return lines.join('\n');
}
function asText() {
  const gs = groups();
  return `BOS problems (${PR.filter}) · ${new Date().toISOString().slice(0, 10)} · ${gs.length} group(s)\n\n` + gs.map(groupText).join('\n\n');
}
function prHTML() {
  const chip = (v, on, text) => `<button type="button" class="tog ${on ? 'on' : ''}" data-act="er_filter" data-v="${v}" aria-pressed="${on ? 'true' : 'false'}">${esc(text)}</button>`;
  const gs = PR.rows ? groups() : [];
  const off = B.rule && B.ENV && B.ENV.rules && B.rule('client_errors_on', false) !== true ? `<div class="notice warn">${esc(T('pr_off'))}</div>` : '';
  let body;
  if (PR.loading && !PR.rows) body = `<p class="muted center pad">${esc(T('loading'))}</p>`;
  else if (PR.err) body = `<div class="notice ${PR.err === 'denied' ? 'warn' : 'bad'}">${esc(PR.err === 'denied' ? T('noaccess') : T('fail'))}</div>`;
  else if (!gs.length) body = `<p class="muted center pad">${esc(T('none'))}</p>`;
  else body = gs.map((g) => `<div class="er-grp${g.resolved ? ' res' : ''}" data-fp="${esc(g.fp)}">
      <div class="er-msg">${esc(String(g.message).split('\n')[0].slice(0, 200))}</div>
      <div class="er-meta">${esc(g.kind)} · ${g.count} ${esc(T('count'))} · ${esc(T('last'))} ${esc(fmtT(g.last))} · ${g.users.size} ${esc(T('users'))}</div>
      <div class="er-meta">${esc(g.route || '-')} · ${esc(T('by'))} ${esc([...g.builds].join(', ') || '-')}</div>
      ${g.notes.length ? `<div class="er-meta">${esc(T('note'))}: ${esc(g.notes[0].slice(0, 300))}</div>` : ''}
      ${g.stack ? `<details><summary class="er-meta">stack</summary><pre class="er-pre">${esc(g.stack)}</pre></details>` : ''}
      ${g.resolved ? '' : `<button type="button" data-act="er_resolve" data-v="${g.openIds[0]}">${esc(T('resolve'))}</button>`}</div>`).join('');
  return `<p class="muted">${esc(T('pr_intro'))}</p>${off}
    <div class="row wrap">${chip('open', PR.filter === 'open', T('open'))}${chip('resolved', PR.filter === 'resolved', T('resolved'))}${chip('all', PR.filter === 'all', T('all'))}</div>
    <div class="row wrap"><input id="er_rnote" maxlength="500" autocomplete="off" placeholder="${esc(T('rnote'))}" style="flex:1;min-width:8rem">
      <button type="button" data-act="er_copy">${esc(T('copy'))}</button><button type="button" data-act="er_refresh">${esc(T('refresh'))}</button></div>
    <div class="stack" id="er_list">${body}</div><textarea id="er_copybox" class="er-box" readonly hidden></textarea>`;
}
function paintPR() { const b = $('#er_body'); if (!b) return; const keep = ($('#er_rnote') || {}).value || ''; b.innerHTML = prHTML(); const n = $('#er_rnote'); if (n) n.value = keep; }
async function loadPR() {
  PR.loading = true; PR.err = null;
  try {
    const r = await sb.rpc('client_errors_list', { p_from: null, p_to: null, p_kind: null, p_limit: 400, p_status: 'all' });
    if (r && r.error) PR.err = /not allowed|permission|denied/i.test(String(r.error.message)) ? 'denied' : 'fail'; else PR.rows = (r && r.data) || [];
  } catch (e) { PR.err = 'fail'; }
  PR.loading = false; paintPR();
}
function viewProblems() {
  injectCss(); PR.rows = null; PR.err = null; PR.filter = 'open';
  shell(T('pr_title'), `<div id="er_body">${prHTML()}</div>`, true);
  loadPR();
}
async function copyText() {
  const text = asText();
  try { if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(text); toast(T('copied')); return text; } } catch (e) { /* fall through */ }
  const box = $('#er_copybox'); if (box) { box.hidden = false; box.value = text; box.focus(); box.select(); try { if (document.execCommand && document.execCommand('copy')) { toast(T('copied')); return text; } } catch (e) { /* manual */ } }
  toast(T('copy_manual')); return text;
}

Object.assign(A.H || {}, {
  er_open: () => {
    st.prev = curRoute(); st.prevAt = now();
    if (A.H && A.H.nav_go) A.H.nav_go({ dataset: { v: 'reportproblem' } }); else location.hash = '#/reportproblem';
  },
  er_send: () => sendReport(),
  er_filter: (a) => { PR.filter = ['open', 'resolved', 'all'].indexOf(a.dataset.v) >= 0 ? a.dataset.v : 'open'; paintPR(); },
  er_refresh: () => loadPR(),
  er_copy: () => copyText(),
  er_resolve: async (a) => {
    try {
      const note = String(($('#er_rnote') || {}).value || '').trim().slice(0, 500) || null;
      const r = await sb.rpc('client_error_resolve', { p_id: Number(a.dataset.v), p_note: note });
      if (r && r.error) throw r.error;
      toast(T('done')); await loadPR();
    } catch (e) { toast(T('fail') + (e && e.message ? ': ' + e.message : '')); }
  },
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { reportproblem: viewReport, problems: viewProblems });

/* ---------- start ---------- */
loadQ();
if (LS.get(K_ON) === '1') install();                           // last known answer: capture from the first second; resolveRule() confirms or switches it off
else if (hasReports()) startInfra();                           // a note typed while offline is still waiting
watchDrawer();
setTimeout(resolveRule, 0);
B.errlog = { loaded: true, report, flush: () => flush(true), state: () => ({ on: st.on, installed: st.installed, queue: st.q.length, recent: st.recent.length, fails: st.fails, sent: st.sent, dropped: st.dropped, infra: st.infra, patched: st.patched, ruleDone: st.ruleDone }),
  resolveRule, install, uninstall, normRoute, scrub, systemError, X };
})();
