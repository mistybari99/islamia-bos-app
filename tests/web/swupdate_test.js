// Step SW: the OLD public web bundle (islamia-bos-app origin/main) is replaced by the NEW one (this checkout's web/ through tools/build_web.sh --to, the real deploy path since bos114).
// Proves what the owner's phones see: no mixed versions, old caches dropped, offline POS, queued sale (old shape) sent once, signed-URL expiry, no forced reload mid-sale, Fast 3G load.
// Run: node tests/web/swupdate_test.js          (needs: git, openssl, python3; the committed web/ must be clean because build_web.sh --to refuses a dirty source)
// Env: PUB_REPO (default /home/user/islamia-bos-app) OLD_REF (default origin/main) BUILD_WEB (default tools/build_web.sh) ONLY=1,2,.. (scenario filter) JSON_OUT=path
// HTTPS (self-signed, h2) is used on purpose: web/swreg.js registers the service worker on https only, so http://localhost would test nothing.
const _P = require('./_paths');
const fs = require('fs'), os = require('os'), path = require('path'), http2 = require('http2'), https = require('https'), zlib = require('zlib'), crypto = require('crypto'), cp = require('child_process');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const PUB = process.env.PUB_REPO || '/home/user/islamia-bos-app';
const MAKE = process.env.BUILD_WEB || path.join(_P.REPO_DIR, 'tools', 'build_web.sh');
const h10 = (buf) => crypto.createHash('sha256').update(buf).digest('hex').slice(0, 10);   // same as tools/web_build.js: ?v= is the hash of the file's own bytes
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const want = (n) => !ONLY || ONLY.includes(String(n));
let pass = 0, failn = 0; const F = [];   // F = findings (info / risk) for the report
const chk = (n, ok, extra) => { if (ok) { pass++; console.log('  ok  ', n); } else { failn++; console.log('  FAIL', n, extra === undefined ? '' : JSON.stringify(extra)); } };
const find = (id, text) => { F.push({ id, text }); console.log('  FINDING', id, text); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- build OLD / NEW bundles into temp dirs ----------
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'bos-swupd-'));
function sh(cmd, args, o) { return cp.execFileSync(cmd, args, Object.assign({ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }, o)); }
function extract(ref, dir) { fs.mkdirSync(dir, { recursive: true }); sh('bash', ['-c', `git -C '${PUB}' archive '${ref}' | tar -x -C '${dir}'`]); }
function buildBundles() {
  const ref = process.env.OLD_REF || 'origin/main';
  const oldD = path.join(TMP, 'old'), newD = path.join(TMP, 'new'); extract(ref, oldD); extract(ref, newD);
  sh('git', ['init', '-q', '-b', 'tmpnew'], { cwd: newD }); sh('git', ['add', '-A'], { cwd: newD });
  sh('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'base'], { cwd: newD });
  fs.copyFileSync(path.join(_P.WEB_DIR, 'config.js'), path.join(newD, 'config.js'));   // build_web.sh --to refuses a deploy whose config.js differs from web/config.js
  const dist = path.join(TMP, 'dist');
  const out = sh('bash', [MAKE, '--out', dist, '--to', newD], { cwd: _P.REPO_DIR });
  const build = fs.existsSync(path.join(dist, '.build-id')) ? fs.readFileSync(path.join(dist, '.build-id'), 'utf8').trim() : undefined;
  const oldBuild = (fs.readFileSync(path.join(oldD, 'sw.js'), 'utf8').match(/bos-sw-([\w]+)['"]/) || [])[1];
  if (!build) throw new Error('build_web gave no build id:\n' + out);
  return { oldD, newD, build, oldBuild, makeOut: out.trim().split('\n').slice(-3).join(' | ') };
}

// ---------- test data + the supabase stand-in (tests/web/stub.js + sales/storage mocks) ----------
const smoke = fs.readFileSync(path.join(__dirname, 'smoke.js'), 'utf8');
const data = new Function('fs', smoke.slice(smoke.indexOf('const csv'), smoke.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const STUB = fs.readFileSync(path.join(__dirname, 'stub.js'), 'utf8');
const EXTRA = `;(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc.bind(c), from = c.from.bind(c);
 const NETERR = { message: 'TypeError: Failed to fetch' };
 const off = () => !navigator.onLine;
 c.rpc = async (fn, args) => {
  if (off() && window.__STRICT) return { data: null, error: NETERR };            // realistic: every database call fails with no internet
  if (fn === 'record_sale2' || fn === 'record_sale_offline') {
    if (off()) return { data: null, error: NETERR };
    return await window.__srv(fn, JSON.stringify(args)); }
  if (fn === 'items_first_image') return { data: (window.__IMGS || []).map((x) => ({ item_id: x.item_id, path: x.path })), error: null };
  if (fn === 'find_customer') return { data: { found: false, mobile: String(args.p_mobile) }, error: null };
  return rpc(fn, args); };
 c.from = (t) => { if (off() && window.__STRICT) { const e = { data: null, error: NETERR }; const p = new Proxy(function () {}, { get: (_, k) => (k === 'then' ? (res, rej) => Promise.resolve(e).then(res, rej) : () => p), apply: () => p }); return p; } return from(t); };
 c.storage = { from: () => ({ createSignedUrls: async (paths, sec) => { const r = await window.__sign(JSON.stringify({ paths, sec })); return { data: JSON.parse(r), error: null }; } }) };
 return c; }; })();`;

// ---------- an https/h2 server whose document root can be switched (= a deploy) ----------
const KEY = path.join(TMP, 'k.pem'), CRT = path.join(TMP, 'c.pem');
sh('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', KEY, '-out', CRT, '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-days', '2']);
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };
function makeServer(root) {
  const S = { root, stub: true, log: [], maxAge: 0, bytes: 0 };   // 0 = the HTTP cache is stale (phone offline later than 10 min after the visit); 1c sets 600
  const h = (req, res) => {
    if (S.down) { S.drops = (S.drops || 0) + 1; try { if (req.stream && req.stream.session) req.stream.session.destroy(); else req.socket.destroy(); } catch (e) { /* gone */ } return; }
    const u = new URL(req.url, 'https://x'); let p = decodeURIComponent(u.pathname); if (p === '/') p = '/index.html';
    S.log.push(p + u.search);
    let body;
    if (p === '/vendor/supabase.js' && S.stub) body = Buffer.from(STUB + EXTRA);
    else { const f = path.join(S.root, p); if (!f.startsWith(S.root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); } body = fs.readFileSync(f); }
    const ext = path.extname(p), etag = '"' + crypto.createHash('md5').update(body).digest('hex') + '"';
    const hd = { 'content-type': MIME[ext] || 'application/octet-stream', etag, 'cache-control': 'max-age=' + S.maxAge };   // GitHub Pages sends max-age=600 + etag
    if (req.headers['if-none-match'] === etag) { res.writeHead(304, hd); return res.end(); }
    if (/gzip/.test(req.headers['accept-encoding'] || '') && /^\.(html|js|css|json|svg)$/.test(ext)) { body = zlib.gzipSync(body); hd['content-encoding'] = 'gzip'; }
    res.writeHead(200, hd); res.end(body);
  };
  S.srv = http2.createSecureServer({ key: fs.readFileSync(KEY), cert: fs.readFileSync(CRT), allowHTTP1: true }, h);
  return new Promise((ok) => S.srv.listen(_P.freePort(), () => { S.port = S.srv.address().port; S.url = 'https://localhost:' + S.port + '/'; ok(S); }));
}
// image host on ANOTHER origin (real signed URLs live on supabase.co, the service worker must never see them)
function makeImgHost() {
  // The page's Content-Security-Policy (img-src 'self' data: blob: https://*.supabase.co) rightly blocks any other image host, so the photo host is a
  // *.supabase.co name answered by Playwright (ctx.route) instead of a localhost server. I.install(ctx) must be called on the context.
  const I = { hits: [], n: 0, ttl: 3600, base: 'https://img.test.supabase.co' };
  const GIF = Buffer.from('R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==', 'base64');
  I.srv = { close() {} };
  I.install = (ctx) => ctx.route('https://img.test.supabase.co/**', (r) => {
    const u = new URL(r.request().url()); const tok = u.searchParams.get('t'), exp = Number(u.searchParams.get('exp'));
    I.hits.push({ path: u.pathname, tok: Number(tok), exp, at: Date.now() });
    return r.fulfill({ status: 200, contentType: 'image/gif', headers: { 'access-control-allow-origin': '*', 'cache-control': 'no-store' }, body: GIF });
  });
  return Promise.resolve(I);
}

// context.setOffline() does NOT reach the service worker's own fetches in Chromium, so "no internet" = the page is told offline AND the server drops every connection.
const offline = async (ctx, srv, on) => { srv.down = !!on; await ctx.setOffline(!!on); };
// ---------- shared browser plumbing ----------
let br;
async function newCtx(srv, o) {
  o = o || {};
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, locale: 'bn-BD', ignoreHTTPSErrors: true, serviceWorkers: o.noSW ? 'block' : 'allow' });
  const errs = [], sales = {}, state = { refuse: new Set(), signN: 0 };
  ctx.on('page', (p) => { p.on('pageerror', (e) => errs.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept(d.defaultValue())); });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.fulfill({ status: 200, contentType: 'text/css', body: '' }));
  await ctx.exposeFunction('__srv', async (fn, json) => {
    const a = JSON.parse(json), key = a.p_client; (sales[key] = sales[key] || { calls: [], fn: [] }).calls.push(fn);
    if (state.refuse.has(key) || a.p_lines.some((l) => state.refuse.has(l.item_id))) return { data: null, error: { message: 'insufficient_stock' } };
    const first = !sales[key].done; sales[key].done = true;
    const tot = a.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.price || 1)), 0);
    return first ? { data: { id: 's-' + key, receipt: Object.keys(sales).length, total: tot, paid: tot, due: 0 }, error: null } : { data: { id: 's-' + key, dup: true, receipt: 1, total: tot, paid: tot, due: 0 }, error: null };
  });
  await ctx.exposeFunction('__sign', async (json) => { const { paths, sec } = JSON.parse(json); const t = ++state.signN; const skew = state.skew || 0;
    return JSON.stringify(paths.map((p) => ({ path: p, signedUrl: (state.imgBase || '') + '/' + p + '?t=' + t + '&exp=' + (Date.now() + skew + sec * 1000) }))); });
  await ctx.addInitScript(`window.__DATA=${JSON.stringify(JSON.parse(JSON.stringify(data)))};window.__STRICT=${o.strict ? 'true' : 'false'};try{localStorage.setItem('bos_lang','en')}catch(e){}
    ${o.skew ? "(function(){const R=Date.now;Date.now=function(){let s=0;try{s=Number(sessionStorage.getItem('__skew')||0)}catch(e){}return R()+s}})();" : ''}`);
  return { ctx, errs, sales, state };
}
const boot = (p) => p.waitForFunction(() => window.BOS_APP && document.querySelector('#app h1, #app .tile, #app .pos-item, #pos_body'), null, { timeout: 20000 });
const swInfo = (p) => p.evaluate(async () => {
  const r = await navigator.serviceWorker.getRegistration(); const keys = await caches.keys();
  const out = { script: r && r.active && r.active.scriptURL, state: r && r.active && r.active.state, installing: !!(r && r.installing), waiting: !!(r && r.waiting), controlled: !!navigator.serviceWorker.controller, keys, entries: {} };
  for (const k of keys) { const c = await caches.open(k); out.entries[k] = (await c.keys()).map((q) => q.url.replace(location.origin, '')); }
  return out;
});
const waitSW = async (p, sub, ms, noEntries) => { const t0 = Date.now(); let i; while (Date.now() - t0 < (ms || 15000)) { i = await swInfo(p).catch(() => null); if (noEntries && i && i.script && i.state === 'activated' && i.controlled && i.keys.every((k) => k === 'bos-sw-' + sub) && /sw\.js/.test(i.script) && (await p.evaluate(async () => { const r = await navigator.serviceWorker.getRegistration(); return !r.installing && !r.waiting; })) && Date.now() - t0 > 1500) return i;
    if (i && i.keys.length === 1 && i.keys[0] === 'bos-sw-' + sub && i.controlled && i.state === 'activated' && (noEntries || i.entries['bos-sw-' + sub].length > 5)) return i; await sleep(150); } return i; };
const scriptUrls = (p) => p.evaluate(() => [...document.querySelectorAll('script[src],link[rel=stylesheet]')].map((e) => e.getAttribute('src') || e.getAttribute('href')).filter((u) => !/^https?:/.test(u)));
const vOf = (u) => (u.match(/[?&]v=([0-9a-f]{10})/) || [])[1] || null;
// (the <head> file theme_glass.js carries the build id instead of its own hash)
// ?v= is the hash of each file's own bytes (bos114), so "same build" means: every stamped URL carries the hash of THAT file in the bundle dir.
const fileOf = (u) => u.split('?')[0].replace(/^\//, '');
const stampOkIn = (dir, bid) => (u) => { const v = vOf(u); if (!v) return true; if (v === bid) return true; if (fileOf(u) === 'config.js') return true;   // config.js is the public repo's own protected file (build_web.sh never overwrites it): its ?v= is the hash of the built copy, not of the file kept there
     try { return h10(fs.readFileSync(path.join(dir, fileOf(u)))) === v; } catch (e) { return false; } };
const stampedFiles = (urls) => urls.filter((u) => /\.(js|css)\?/.test(u));
const lsq = (p, k) => p.evaluate((k) => JSON.parse(localStorage.getItem(k) || '[]'), k);
async function sellItem(p, itemId) {   // POS: one item card -> cart -> pay cash in full
  await p.click(`.pos-item[data-v="${itemId}"]`); await p.waitForTimeout(100);
  const q = await p.$('[data-act=pos_q_ok]'); if (q) await q.click();
  await p.click('[data-act=pos_cart]'); await p.waitForSelector('#cart_ok'); await p.click('#cart_ok'); await p.waitForTimeout(500);
}
let firstVisitEntries = null, PRECACHE_N = 0;
async function firstVisit(p, url, sub) {   // first ever visit, then the second load that really fills the cache (clients.claim() comes after the first load's requests)
  await p.goto(url); await boot(p); await p.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 10000 }).catch(() => {});
  const i = await swInfo(p); const n = i.keys.length ? i.entries[i.keys[0]].length : 0; if (firstVisitEntries === null) firstVisitEntries = n;
  await p.reload(); await boot(p); return waitSW(p, sub);
}
const piece = data.tables.items.filter((i) => i.unit === 'pc');

(async () => {
  const B = buildBundles();
  const swNew = fs.readFileSync(path.join(B.newD, 'sw.js'), 'utf8');
  PRECACHE_N = (JSON.parse((swNew.match(/PRECACHE\s*=\s*(\[[^\]]*\])/) || [, '[]'])[1]) || []).length;
  console.log('OLD build', B.oldBuild, '| NEW build', B.build, '|', B.makeOut);
  br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--ignore-certificate-errors'] }).catch(() => chromium.launch({ args: ['--ignore-certificate-errors'] }));
  const results = { oldBuild: B.oldBuild, newBuild: B.build };

  // ===== 1. update OLD -> NEW =====
  if (want(1)) {
    console.log('\n[1] update: OLD bundle active, then the NEW bundle is deployed');
    const srv = await makeServer(B.oldD); const { ctx, errs } = await newCtx(srv); const p = await ctx.newPage();
    const i0 = await firstVisit(p, srv.url, B.oldBuild);
    chk('first visit: cache holds ' + firstVisitEntries + ' files before the 2nd load (SW-3 if 0)', true);
    { const ou = await scriptUrls(p); chk('old index: every stamped js/css carries the hash of its own file in the OLD bundle, and one carries the old build id', stampedFiles(ou).length > 0 && ou.every(stampOkIn(B.oldD, B.oldBuild)) && ou.some((u) => vOf(u) === B.oldBuild), ou.slice(0, 4)); }
    const oldEntries = i0 ? i0.entries['bos-sw-' + B.oldBuild].length : 0; results.oldCacheEntries = oldEntries; results.cacheEntriesAfterVeryFirstLoad = firstVisitEntries;
    if (firstVisitEntries === 0) find('SW-3', 'OLD bundle (sw.js without bos110): on the very first visit the SW installs after the page has fetched everything, so the cache is EMPTY (0 files) until the 2nd load; offline start only works after a second online open.');
    srv.root = B.newD; srv.log.length = 0; errs.length = 0;   // DEPLOY
    await p.reload(); await boot(p);                           // reload 1
    await sleep(1500);
    let urls = await scriptUrls(p); const vs = new Set(urls.filter((u) => /\.(js|css)\?/.test(u)).map(vOf));
    chk('reload 1: index.html is the NEW one (a file carries build id ' + B.build + ', every stamp is the hash of its file in the NEW bundle)', vs.has(B.build) && urls.every(stampOkIn(B.newD, B.build)), [...vs]);
    chk('reload 1: every local script/css has ?v= (none unstamped; vendor/supabase.js is never stamped on purpose)', urls.every((u) => /\?v=/.test(u) || /^vendor\//.test(u)), urls.filter((u) => !/\?v=/.test(u) && !/^vendor\//.test(u)));
    const i1 = await waitSW(p, B.build, 15000, true); results.afterReload1 = i1 && { keys: i1.keys, entries: i1.entries['bos-sw-' + B.build] ? i1.entries['bos-sw-' + B.build].length : 0 };
    chk('reload 1: SW updated (script ' + (i1 && /sw\.js/.test(i1.script || '')) + ') and the old cache bos-sw-' + B.oldBuild + ' is gone', !!i1 && !i1.keys.includes('bos-sw-' + B.oldBuild) && i1.keys.every((k) => k === 'bos-sw-' + B.build), i1 && i1.keys);
    chk('reload 1: new cache already holds the precache list (' + PRECACHE_N + ' files, core only since bos114; lazy screens are cached when used)', results.afterReload1.entries >= PRECACHE_N, results.afterReload1);
    const e1 = i1 && i1.entries['bos-sw-' + B.build] ? i1.entries['bos-sw-' + B.build].length : 0;
    await p.reload(); await boot(p);                           // reload 2
    urls = await scriptUrls(p);
    const res = await p.evaluate(() => performance.getEntriesByType('resource').map((r) => r.name.replace(location.origin, '')).filter((n) => /\.(js|css)(\?|$)/.test(n)));
    const rv = new Set(res.map(vOf).filter(Boolean)); const unst = res.filter((n) => !vOf(n) && !/sw\.js|^\/?vendor\//.test(n));   // vendor/ is never stamped (SW serves it stale-while-revalidate)
    chk('reload 2: every loaded js/css is the NEW file (its ?v= is the hash of that file in the NEW bundle; none from the old one)', rv.has(B.build) && res.every(stampOkIn(B.newD, B.build)) && unst.length === 0, { versions: [...rv], unstamped: unst.slice(0, 5), wrong: res.filter((n) => !stampOkIn(B.newD, B.build)(n)).slice(0, 5) });
    const i2 = await waitSW(p, B.build);
    chk('reload 2: exactly one cache, bos-sw-' + B.build + ', no old keys', i2 && i2.keys.length === 1 && i2.keys[0] === 'bos-sw-' + B.build, i2 && i2.keys);
    const ents = (i2 && i2.entries['bos-sw-' + B.build]) || [];
    chk('reload 2: new cache holds no js/css of another build (every stamp is the hash of its file in the NEW bundle)', ents.filter((u) => /\.(js|css)\?/.test(u)).every(stampOkIn(B.newD, B.build)), ents.filter((u) => !stampOkIn(B.newD, B.build)(u)).slice(0, 3));
    results.cacheEntries = { old: oldEntries, afterReload1: e1, afterReload2: ents.length };
    chk('reload 2: cache is complete (>= 90% of old cache entry count)', ents.length >= oldEntries * 0.9, { old: oldEntries, now: ents.length });
    chk('no console / page errors through the whole update', errs.length === 0, errs.slice(0, 5));
    chk('app boots on the new bundle (BOS_APP + a screen)', await p.evaluate(() => !!(window.BOS_APP && document.querySelector('#app').children.length)));
    results.swControlsNewScript = i2 && i2.script;
    chk('registered SW script is /sw.js and its VERSION is the new build', /\/sw\.js/.test(i2.script || '') && fs.readFileSync(path.join(B.newD, 'sw.js'), 'utf8').includes("bos-sw-" + B.build));
    await ctx.close(); srv.srv.close();
  }

  // ===== 1b. how long after the update is the new shell usable offline? =====
  if (want('1b')) {
    console.log('\n[1b] window: go offline right after the SW swapped caches, before a second online load');
    const srv = await makeServer(B.oldD); const { ctx } = await newCtx(srv); const p = await ctx.newPage();
    await firstVisit(p, srv.url, B.oldBuild); srv.root = B.newD;
    await p.reload(); await boot(p); const i1 = await waitSW(p, B.build, 15000, true);
    const n1 = i1 && i1.entries['bos-sw-' + B.build] ? i1.entries['bos-sw-' + B.build].length : 0;
    await offline(ctx, srv, true);
    let ok = true; try { await p.reload({ timeout: 8000 }); await p.waitForFunction(() => window.BOS_APP, null, { timeout: 8000 }); } catch (e) { ok = false; }
    results.offlineRightAfterUpdate = { cacheEntriesBeforeOffline: n1, shellLoaded: ok };
    chk('offline right after the first updated load: shell opens (new cache already populated)', ok, { cacheEntries: n1 });
    if (!ok) find('SW-1', 'After an update the new cache bos-sw-' + B.build + ' is empty (' + n1 + ' entries) until one MORE online load: install() does not precache and activate() deletes the old cache that held the freshly fetched files. A phone that goes offline in that window opens "offline" (503).');
    await ctx.close(); srv.srv.close();
  }

  // ===== 1d. brand-new phone on the NEW bundle: offline after ONE visit =====
  if (want('1d')) {
    console.log('\n[1d] new phone, NEW bundle, one visit only, then offline');
    const srv = await makeServer(B.newD); const { ctx } = await newCtx(srv); const p = await ctx.newPage();
    await p.goto(srv.url); await boot(p); await p.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 10000 }).catch(() => {}); await sleep(2500);
    const i = await swInfo(p); const n = i.keys.length ? i.entries[i.keys[0]].length : 0; results.newBundleCacheAfterOneVisit = n;
    await offline(ctx, srv, true); let ok = true; try { await p.reload({ timeout: 8000 }); await p.waitForFunction(() => window.BOS_APP, null, { timeout: 8000 }); } catch (e) { ok = false; }
    chk('NEW bundle: after a single visit the cache holds the precache list (' + n + ' of ' + PRECACHE_N + ' files) and the shell opens offline', ok && n >= PRECACHE_N, { n, ok });
    await ctx.close(); srv.srv.close();
  }

  // ===== 1c. fresh navigation within the HTTP max-age (GitHub Pages: 600 s) =====
  if (want('1c')) {
    console.log('\n[1c] fresh navigation (not reload) right after a deploy, Pages-like max-age=600');
    const srv = await makeServer(B.oldD); srv.maxAge = 600; const { ctx } = await newCtx(srv); const p = await ctx.newPage();
    await firstVisit(p, srv.url, B.oldBuild); srv.root = B.newD; srv.log.length = 0;
    await p.goto(srv.url + '?x=1'); await boot(p);
    let vs = new Set((await scriptUrls(p)).filter((u) => /\.js\?/.test(u)).map(vOf));
    results.freshNavStamp = [...vs].join();
    const stale = vs.has(B.oldBuild); const idxFetched = srv.log.filter((x) => x === '/index.html').length;
    // a navigation to a different URL has no HTTP-cache entry, so test the REAL case: same URL, new tab/visit
    await p.goto(srv.url); await boot(p); vs = new Set((await scriptUrls(p)).filter((u) => /\.js\?/.test(u)).map(vOf));
    results.freshNavSameUrlStamp = [...vs].join();
    console.log('  stamps after goto(/?x=1):', results.freshNavStamp, '| goto(/):', results.freshNavSameUrlStamp);
    if (vs.has(B.oldBuild) && !vs.has(B.build)) find('SW-2', 'A normal visit (not a reload) to the same URL within Pages max-age (600 s) still gets the OLD index.html from the HTTP cache (stamp ' + B.oldBuild + '); the phone keeps the old, internally consistent version for up to 10 minutes. Not a mix; it is a delay.');
    else chk('fresh visit after deploy shows the NEW bundle', vs.has(B.build), [...vs]);
    { const fu = await scriptUrls(p); chk('no mixed versions on a fresh visit (all stamps from the OLD bundle or all from the NEW one)', fu.every(stampOkIn(B.oldD, B.oldBuild)) || fu.every(stampOkIn(B.newD, B.build)), fu.slice(0, 6)); }
    await ctx.close(); srv.srv.close();
  }

  // ===== 2/3. offline POS on the NEW bundle; queued sale made under OLD survives =====
  async function offlineRun(strict) {
    const tag = strict ? 'STRICT (database calls fail offline like production)' : 'TOLERANT (mock keeps answering reads)';
    console.log('\n[2] NEW bundle, offline POS --', tag);
    const srv = await makeServer(B.oldD); const { ctx, errs, sales, state } = await newCtx(srv, { strict }); const p = await ctx.newPage();
    await firstVisit(p, srv.url + '#/pos', B.oldBuild);
    // [3] a sale queued under the OLD bundle's code (real old queue shape)
    await offline(ctx, srv, true); await p.waitForSelector('.pos-item', { timeout: 10000 });
    await sellItem(p, piece[0].id);
    const oldQ = await lsq(p, 'bos_pos_queue_u1'); chk('[3] sale queued by the OLD bundle while offline (queue length 1)', oldQ.length === 1, oldQ.length);
    const oldKeys = Object.keys(oldQ[0] || {}).sort(); const oldClient = oldQ[0] && oldQ[0].p_client;
    srv.root = B.newD; await offline(ctx, srv, false);          // deploy happened while the sale waited; phone gets signal
    await p.waitForTimeout(100);
    await p.reload(); await boot(p); await waitSW(p, B.build); await p.waitForTimeout(300);
    await p.reload(); await boot(p);                           // two reloads on the NEW bundle
    await p.evaluate(() => window.BOS && window.BOS.pos && window.BOS.pos.flush && window.BOS.pos.flush()).catch(() => {}); await p.waitForTimeout(800);
    const sent = sales[oldClient];
    chk('[3] OLD-shape queued sale was sent by the NEW bundle exactly once', !!sent && sent.calls.length >= 1 && sent.done === true && (await lsq(p, 'bos_pos_queue_u1')).length === 0, sent && sent.calls);
    chk('[3] it was replayed via record_sale_offline (new replay path) or record_sale2, one successful call', sent && sent.calls.filter((x) => x).length === 1 || (sent && sent.calls.length === 1), sent && sent.calls);
    results['oldQueueKeys'] = oldKeys;
    // [2] go offline on the NEW bundle
    await p.goto(srv.url + '#/pos'); await boot(p); await p.waitForSelector('.pos-item', { timeout: 10000 }); await p.waitForTimeout(500);
    const iN = await waitSW(p, B.build); chk('[2] new SW controls the page before going offline', !!iN && iN.controlled, iN && iN.keys);
    await offline(ctx, srv, true);
    let shell = true; try { await p.reload({ timeout: 10000 }); await p.waitForFunction(() => window.BOS_APP, null, { timeout: 10000 }); } catch (e) { shell = false; }
    chk('[2] offline reload: app shell (index + js) loads from the cache', shell);
    const bodyTxt = shell ? await p.evaluate(() => document.body.innerText.slice(0, 200).replace(/\s+/g, ' ')) : '';
    let posOpen = false; if (shell) { try { await p.waitForSelector('.pos-item', { timeout: 6000 }); posOpen = true; } catch (e) { /* login/err screen */ } }
    if (!strict) chk('[2] offline: POS screen opens with its item cards', posOpen, bodyTxt);
    if (shell && !posOpen && strict) find('APP-1', 'Offline cold start shows "' + bodyTxt.slice(0, 80) + '" instead of the POS: app.js start() calls the my_context rpc, on error runs fail()+viewAuth() (login screen). The service worker serves the shell fine; the app itself needs one successful database call to open. (Not sw.js/swreg.js: out of scope to patch here.) POS works offline only if the app was already open when the connection dropped.');
    results['offline_' + (strict ? 'strict' : 'tolerant')] = { shell, posOpen, body: bodyTxt };
    if (posOpen) {
      state.refuse.add(piece[1].id);
      await sellItem(p, piece[0].id); await sellItem(p, piece[1].id);
      const q = await lsq(p, 'bos_pos_queue_u1'); chk('[2] two offline sales are in the queue (localStorage bos_pos_queue_u1)', q.length === 2, q.length);
      chk('[2] chip "pending" is shown', await p.locator('#pos_qchip').count() === 1);
      const ids = q.map((x) => x.p_client);
      await offline(ctx, srv, false); await p.waitForTimeout(1500);
      let ql = (await lsq(p, 'bos_pos_queue_u1')).length;
      if (ql) { await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(800); ql = (await lsq(p, 'bos_pos_queue_u1')).length; find('POS-0', 'online event alone did not drain the queue; needed flush()'); }
      chk('[2] back online: queue drained', ql === 0, ql);
      for (let k = 0; k < 3; k++) { await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(200); }
      const okSale = sales[ids[0]], refSale = sales[ids[1]];
      chk('[2] accepted sale replayed EXACTLY once (despite repeated flush)', okSale && okSale.calls.length === 1, okSale && okSale.calls);
      chk('[2] refused sale tried once, not retried forever', refSale && refSale.calls.length === 1, refSale && refSale.calls);
      const failed = await lsq(p, 'bos_pos_failed_u1'); chk('[2] refused sale is kept as a failed card', failed.length === 1 && failed[0].p_client === ids[1], failed.length);
      await p.click('[data-act=pos_tab][data-v=today]'); await p.waitForTimeout(600);
      chk('[2] failed-sale card is visible on the Today tab', await p.locator('.notice.bad').count() >= 1 && /refused|Could not be recorded/i.test(await p.locator('.notice.bad').first().innerText()), await p.locator('.notice.bad').count());
    }
    if (strict && !posOpen) {   // the realistic case: POS already open, connection drops (no reload)
      await offline(ctx, srv, false); await p.goto(srv.url + '?r=2#/pos'); await boot(p); await p.waitForSelector('.pos-item', { timeout: 10000 });
      await offline(ctx, srv, true); await sellItem(p, piece[0].id);
      const q = await lsq(p, 'bos_pos_queue_u1'); chk('[2] strict, POS already open: offline sale is queued', q.length === 1, q.length);
      await offline(ctx, srv, false); await p.waitForTimeout(1500); await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(600);
      chk('[2] strict, POS already open: replayed exactly once after reconnect', sales[q[0].p_client] && sales[q[0].p_client].calls.length === 1 && (await lsq(p, 'bos_pos_queue_u1')).length === 0, sales[q[0].p_client]);
    }
    const rel = errs.filter((e) => !/Failed to load resource|net::ERR/.test(e)); if (!strict) chk('[2] no unexpected JS errors offline/online', rel.length === 0, rel.slice(0, 4));
    await ctx.close(); srv.srv.close();
  }
  if (want(2) || want(3)) { await offlineRun(false); await offlineRun(true); }

  // ===== 4. signed-URL expiry in itemimg.js =====
  if (want(4)) {
    console.log('\n[4] item photos: signed URL is not reused after expiry');
    const srv = await makeServer(B.newD); const img = await makeImgHost(); const { ctx, state } = await newCtx(srv, { skew: true }); state.imgBase = img.base; await img.install(ctx);
    const p = await ctx.newPage(); const it = data.tables.items[0];   // first card = on screen, so the lazy loader fires
    await p.addInitScript(`window.__IMGS=[{item_id:'${it.id}',path:'items/${it.id}/1.jpg'}];`);
    await p.goto(srv.url + '#/pos'); await boot(p); await p.waitForSelector('.pos-item');
    await p.evaluate(() => { const B = window.BOS, R = B.rule; B.rule = (k, f) => ({ item_images_mode: 'pos_only', item_images_thumb_only: 'off' })[k] || R.call(B, k, f); });
    const goPos = async () => { await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(300); await p.evaluate(() => { location.hash = '#/pos'; }); await p.waitForSelector('.pos-item'); await p.waitForTimeout(1200); };
    await goPos();
    const shown1 = await p.evaluate(() => [...document.querySelectorAll('.iimg img')].map((i) => i.src));
    chk('photo shown on a POS card (signed URL, token 1)', shown1.length >= 1 && /[?&]t=1&/.test(shown1[0]), shown1);
    const h1 = img.hits.length; img.hits.forEach((h) => (h.pre = true));
    await p.evaluate(() => sessionStorage.setItem('__skew', String(2 * 3600 * 1000))); state.skew = 2 * 3600 * 1000;   // 2 h later: link expired
    await goPos();
    const after = img.hits.filter((h) => !h.pre);
    const staleAfter = after.filter((h) => h.exp < Date.now() + state.skew);
    chk('2 h later: the card asked for a NEW signed link (token > 1)', after.some((h) => h.tok > 1) || (await p.evaluate(() => [...document.querySelectorAll('.iimg img')].map((i) => i.src))).some((s) => /[?&]t=[2-9]/.test(s)), after);
    chk('2 h later: no image request used an expired link', staleAfter.length === 0, staleAfter);
    // persisted cache (hours rule): expired link must not be restored after a reload
    await p.evaluate(() => { const B = window.BOS, R = B.rule; B.rule = (k, f) => ({ item_images_mode: 'pos_only', item_images_thumb_only: 'off', item_images_cache_hours: 24 })[k] || R.call(B, k, f); });
    await goPos(); const ls = await p.evaluate(() => localStorage.getItem('bos_iimg1'));
    await p.evaluate(() => sessionStorage.setItem('__skew', String(5 * 3600 * 1000))); state.skew = 5 * 3600 * 1000;
    img.hits.forEach((h) => (h.pre = true));
    await p.reload(); await boot(p); await p.evaluate(() => { const B = window.BOS, R = B.rule; B.rule = (k, f) => ({ item_images_mode: 'pos_only', item_images_thumb_only: 'off', item_images_cache_hours: 24 })[k] || R.call(B, k, f); });
    await goPos();
    const after2 = img.hits.filter((h) => !h.pre), stale2 = after2.filter((h) => h.exp < Date.now() + state.skew);
    chk('cache_hours rule: after a reload 5 h later no expired link is used (localStorage copy dropped)', stale2.length === 0, { ls: !!ls, stale2 });
    chk('image host (other origin) never went through the service worker cache', !(await swInfo(p)).entries['bos-sw-' + B.build].some((u) => /__itemimg|\.gif|\/items\//.test(u)));
    await ctx.close(); srv.srv.close(); img.srv.close();
  }

  // ===== 5. update while a sale sheet is open =====
  if (want(5)) {
    console.log('\n[5] SW update while the cashier is mid-sale');
    const srv = await makeServer(B.oldD); const { ctx, errs, sales } = await newCtx(srv); const p = await ctx.newPage();
    let navs = 0; p.on('framenavigated', (f) => { if (f === p.mainFrame()) navs++; });
    await firstVisit(p, srv.url + '#/pos', B.oldBuild); await p.waitForSelector('.pos-item');
    await p.click(`.pos-item[data-v="${piece[0].id}"]`); await p.waitForTimeout(100); const q = await p.$('[data-act=pos_q_ok]'); if (q) await q.click();
    await p.click('[data-act=pos_cart]'); await p.waitForSelector('#cart_ok');
    await p.evaluate(() => { window.__mark = 'alive'; window.__ctl = 0; navigator.serviceWorker.addEventListener('controllerchange', () => window.__ctl++); });
    const n0 = navs; srv.root = B.newD; srv.log.length = 0;
    await p.evaluate(async () => { const r = await navigator.serviceWorker.getRegistration(); await r.update(); });   // what the browser does on its own schedule / next navigation
    const iN = await waitSW(p, B.build, 20000, true); await p.waitForTimeout(1500);
    const st = await p.evaluate(() => ({ mark: window.__mark, ctl: window.__ctl, sheet: !!document.querySelector('#cart_ok'), build: (document.querySelector('script[src*="pos.js"]') || {}).getAttribute && document.querySelector('script[src*="pos.js"]').getAttribute('src') }));
    results.midSale = { swSwapped: !!iN, controllerchange: st.ctl, pageReloaded: st.mark !== 'alive', sheetOpen: st.sheet, runningStamp: vOf(st.build || ''), extraRequests: srv.log.filter((x) => !/sw\.js/.test(x)).slice(0, 8) };
    chk('SW swapped to the new build in the background (old cache gone)', !!iN && iN.keys.every((k) => k === 'bos-sw-' + B.build) && (await p.evaluate(() => window.__ctl)) >= 1, iN && iN.keys);
    chk('NO forced reload: page object alive, no new navigation', st.mark === 'alive' && navs === n0, { navs: navs - n0 });
    chk('sale sheet still open under the cashier', st.sheet);
    await p.click('#cart_ok'); await p.waitForTimeout(700);
    chk('the sale in progress completes normally (recorded once)', Object.values(sales).filter((s) => s.done).length === 1 && (await lsq(p, 'bos_pos_queue_u1')).length === 0, Object.keys(sales).length);
    console.log('  page keeps running the OLD scripts (stamp ' + results.midSale.runningStamp + ') until the next reload; controllerchange fired ' + st.ctl + 'x; requests after swap:', JSON.stringify(results.midSale.extraRequests));
    const rel = errs.filter((e) => !/Failed to load resource/.test(e)); chk('no JS errors during the swap', rel.length === 0, rel.slice(0, 3));
    await ctx.close(); srv.srv.close();
  }

  // ===== 6. cold first load on throttled Fast 3G =====
  if (want(6)) {
    console.log('\n[6] first load on Fast 3G (CDP): 1.6 Mbps down, 750 kbps up, 562.5 ms RTT, gzip, h2, cold cache');
    const meas = async (dir, label) => {
      const srv = await makeServer(dir); srv.stub = false; srv.maxAge = 600;
      const { ctx } = await newCtx(srv, { noSW: true }); const p = await ctx.newPage(); const cdp = await ctx.newCDPSession(p);
      await cdp.send('Network.enable'); await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 562.5, downloadThroughput: 1.6 * 1024 * 1024 / 8 * 0.9, uploadThroughput: 750 * 1024 / 8 * 0.9 });
      let wire = 0, reqs = 0; cdp.on('Network.loadingFinished', (e) => { wire += e.encodedDataLength; reqs++; });
      const t0 = Date.now(); await p.goto(srv.url, { waitUntil: 'load', timeout: 240000 }); const tLoad = (Date.now() - t0) / 1000;
      const nav = await p.evaluate(() => { const n = performance.getEntriesByType('navigation')[0]; return { dcl: n.domContentLoadedEventEnd / 1000, load: n.loadEventEnd / 1000 }; });
      const raw = await p.evaluate(() => performance.getEntriesByType('resource').reduce((s, r) => s + (r.decodedBodySize || 0), 0));
      const jsCount = await p.evaluate(() => document.scripts.length);
      await ctx.close(); srv.srv.close();
      return { label, seconds: +tLoad.toFixed(1), dcl: +nav.dcl.toFixed(1), wireKB: Math.round(wire / 1024), decodedKB: Math.round(raw / 1024), requests: reqs, scripts: jsCount };
    };
    const o = await meas(B.oldD, 'OLD'); const n = await meas(B.newD, 'NEW'); results.fast3g = { old: o, new: n };
    console.log('  OLD', JSON.stringify(o)); console.log('  NEW', JSON.stringify(n));
    const ratioT = n.seconds / o.seconds, ratioB = n.wireKB / o.wireKB; results.fast3g.ratioTime = +ratioT.toFixed(2); results.fast3g.ratioBytes = +ratioB.toFixed(2);
    chk('Fast 3G first load of NEW <= 2x OLD (time ' + o.seconds + 's -> ' + n.seconds + 's, x' + ratioT.toFixed(2) + ')', ratioT <= 2);
    chk('transfer size of NEW <= 2x OLD (' + o.wireKB + ' KB -> ' + n.wireKB + ' KB, x' + ratioB.toFixed(2) + ')', ratioB <= 2);
  }

  await br.close();
  if (process.env.JSON_OUT) fs.writeFileSync(process.env.JSON_OUT, JSON.stringify({ results, findings: F, pass, fail: failn }, null, 1));
  console.log('\nRESULTS', JSON.stringify(results)); F.forEach((f) => console.log('FINDING', f.id, f.text));
  console.log(`\nswupdate_test: ${pass} passed, ${failn} failed`);
  fs.rmSync(TMP, { recursive: true, force: true });
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.error('SWUPDATE FAIL', e); process.exit(2); });
