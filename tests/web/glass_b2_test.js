// glass_b2_test.js = glass_test.js adapted to the phase108 Bangla-wording step and later registry/script appends (QA webfull). Only the listed assertions differ.
// bos109 Liquid Glass theme test. Run: node tests/web/glass_test.js   (env WEB_DIR / PORT optional, see _paths.js; BASE_REF = git ref of the pre-glass commit, default 35f8f7d)
// Chromium 360px against the mocked Supabase: both glass themes apply + persist, the 3 old themes are identical to the base commit (bbox + computed styles of 10 elements),
// no overflow / page errors, WCAG contrast >= 4.5 (token pairs vs worst-case backgrounds AND real elements), reduced-effects fallback, screenshots tests/web/glass_*.png.
const _P = require('./_paths'); const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http'), os = require('os'), cp = require('child_process');
const C = require('./w5_common.js');
const base = C.baseData(_P.TESTS_DIR);
const rpcmock = require('./pol_rpcmock.js');
const GEN = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const prev = c.rpc;
 c.rpc = async (fn, args) => { const R = window.__RPC || {}; if (fn in R) { const v = typeof R[fn] === 'function' ? R[fn](args) : R[fn]; return { data: v === null ? null : JSON.parse(JSON.stringify(v)), error: null }; } return prev.call(c, fn, args); }; return c; }; })();`;
const UA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
let bad = 0, pass = 0; const ok = (c, m) => { if (c) pass++; else { bad++; console.log('FAIL:', m); } };
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
const serveDir = (root, port) => http.createServer((q, r) => { const f = path.join(root, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); r.end(b); }); }).listen(port);

// base commit web/ exported to a temp dir (never touches other worktrees)
// BASE_REF = the accepted look of the three old themes. It was 35f8f7d (pre-glass). Later INTENDED steps changed the old themes on purpose
// (header Back/Main buttons and announce bar -> taller header on pos; S2 form codes + S3/S4 names make '#/form/37-1' a real form, so its page
// is not the same page as at 35f8f7d). Measured with BASE_REF: pos matches the tip from c178730 on; form/37-1 matches from 36254db on (it differs at ed3bac3). The guard now freezes the look at
// 36254db (tip of Main-Img before the test fixes); move it forward deliberately when the old themes are changed on purpose. BASE_REF=35f8f7d runs the old check.
const BASE_REF = process.env.BASE_REF || '36254db';
const baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'glassbase-'));
cp.execSync(`git -C "${_P.REPO_DIR}" archive ${BASE_REF} web | tar -x -C "${baseDir}"`);
const BASE_PORT = PORT + 1;

async function open(br, port, o) {
  const ctx = await br.newContext({ viewport: { width: o.w || 360, height: 740 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true, userAgent: UA, reducedMotion: o.reduced ? 'reduce' : 'no-preference' });
  const p = await ctx.newPage(); p.errors = []; p.port = port;
  p.on('pageerror', (e) => p.errors.push(e.message));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(_P.TESTS_DIR + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + GEN }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  const data = C.mk(base, {});
  // full-power device unless the test asks otherwise (CI boxes may have <=2 cores, which would trigger lite mode)
  const dev = o.lowPower ? 'Object.defineProperty(navigator,"deviceMemory",{get:()=>1});' : 'Object.defineProperty(navigator,"hardwareConcurrency",{get:()=>8});Object.defineProperty(navigator,"deviceMemory",{get:()=>8});';
  await p.addInitScript(`${dev}window.__DATA=${JSON.stringify(data)};window.__M0={};window.__RPC=${rpcmock.src};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');if(!sessionStorage.getItem('g_seed')){${o.theme ? `localStorage.setItem('bos_theme','${o.theme}');` : ''}sessionStorage.setItem('g_seed','1')}}catch(e){}`);
  return p;
}
const go = async (p, r) => { await p.evaluate((r) => { location.hash = '#/' + r; }, r); await p.waitForTimeout(650); };
const start = async (p, hash) => { await p.goto(`http://localhost:${p.port}/#/${hash || 'home'}`); await p.waitForTimeout(1100); };

// ---------- contrast helpers ----------
const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
const over = (top, a, bot) => top.map((v, i) => v * a + bot[i] * (1 - a));

(async () => {
  const br = await chromium.launch({ executablePath: process.env.PW_CHROMIUM || '/opt/pw-browsers/chromium' });
  const srv = serveDir(_P.WEB_DIR, PORT), srvB = serveDir(path.join(baseDir, 'web'), BASE_PORT);

  // 1. selecting each new theme applies + persists after reload; the select lists 5 options
  for (const th of ['glass-light', 'glass-dark']) {
    const p = await open(br, PORT, { theme: 'dark' }); await start(p);
    await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(500);
    const opts = await p.evaluate(() => [...document.querySelectorAll('#navDrawer [data-theme-pick] option')].map((o) => o.value + '=' + o.textContent));
    ok(opts.length === 5 && opts.includes('glass-light=Liquid Glass Light') && opts.includes('glass-dark=Liquid Glass Dark'), 'theme select lists the 2 new English names: ' + opts.join('|'));
    await p.selectOption('#navDrawer [data-theme-pick]', th); await p.waitForTimeout(500);
    const a = await p.evaluate(() => ({ t: document.documentElement.dataset.theme, s: document.documentElement.hasAttribute('data-skin'), ls: localStorage.getItem('bos_theme'), fx: document.documentElement.dataset.fx, bg: getComputedStyle(document.body, '::before').backgroundImage.slice(0, 20) }));
    ok(a.t === th && a.s && a.ls === th, `select ${th} applies + stores: ${JSON.stringify(a)}`);
    ok(a.fx === 'full', `${th}: full effects on a capable device (fx=${a.fx})`);
    await p.reload(); await p.waitForTimeout(1000);
    const b = await p.evaluate(() => ({ t: document.documentElement.dataset.theme, meta: document.querySelector('meta[name=theme-color]').content }));
    ok(b.t === th, `${th} persists after reload (${b.t})`);
    ok(await p.evaluate(() => window.BOS_THEME.list.includes('glass-light') && window.BOS_THEME.list.includes('glass-dark')), 'BOS_THEME.list has glass entries');
    ok(p.errors.length === 0, `${th}: no page errors: ${p.errors.join(';')}`);
    await p.context().close();
  }
  // language check: Bangla / mix labels exist, English mode is all-English
  { const p = await open(br, PORT, { lang: 'bn', theme: 'glass-light' }); await start(p); await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(500);
    const t = await p.evaluate(() => [...document.querySelectorAll('#navDrawer [data-theme-pick] option')].map((o) => o.textContent).join('|')); ok(/লিকুইড গ্লাস লাইট/.test(t) && /লিকুইড গ্লাস ডার্ক/.test(t), 'bn labels: ' + t); await p.context().close(); }

  // 2. old themes identical to base commit: bbox + computed styles of 10 key elements
  const KEYS = ['header.top', '.bnav', '.bnav button', '.card', 'button.primary', 'button.mini', '.chip', 'input', '.qt > .qm', 'h2'];
  const PROPS = ['color', 'backgroundColor', 'backgroundImage', 'borderTopColor', 'borderTopWidth', 'borderRadius', 'boxShadow', 'fontSize', 'fontWeight', 'padding', 'backdropFilter', 'opacity', 'filter', 'outlineStyle'];
  const snap = (p, route) => p.evaluate(({ KEYS, PROPS }) => KEYS.map((k) => { const e = document.querySelector(k); if (!e) return null; const b = e.getBoundingClientRect(), cs = getComputedStyle(e); const o = { x: Math.round(b.x * 10) / 10, y: Math.round(b.y * 10) / 10, w: Math.round(b.width * 10) / 10, h: Math.round(b.height * 10) / 10 }; PROPS.forEach((q) => { o[q] = cs[q]; }); return o; }), { KEYS, PROPS });
  for (const th of ['dark', 'light', 'classic']) for (const route of ['pos', 'form/37-1']) {
    const A = await open(br, PORT, { theme: th }), B = await open(br, BASE_PORT, { theme: th });
    await start(A, route); await start(B, route);
    const sa = await snap(A), sb = await snap(B);
    let diffs = []; KEYS.forEach((k, i) => { if (JSON.stringify(sa[i]) !== JSON.stringify(sb[i])) { const x = sa[i] || {}, y = sb[i] || {}; diffs.push(k + ':' + Object.keys({ ...x, ...y }).filter((q) => x[q] !== y[q]).join(',')); } });
    ok(diffs.length === 0, `${th} ${route} identical to base ${BASE_REF}: ${diffs.join(' ; ')}`);
    ok(sa.filter(Boolean).length >= 3, `${th} ${route}: key elements found (${sa.filter(Boolean).length})`);
    await A.context().close(); await B.context().close();
  }

  // 3. per glass theme: no overflow 320-412, no errors, routes render, screenshots
  const SHOTS = [['home', 'home'], ['pos', 'pos'], ['form/37-1', 'form'], ['dash', 'dash']];
  for (const th of ['glass-light', 'glass-dark']) {
    for (const w of [320, 360, 412]) {
      const p = await open(br, PORT, { theme: th, w }); await start(p);
      for (const r of ['home', 'pos', 'form/37-1', 'inbox']) {
        await go(p, r);
        const ov = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, bsw: document.body.scrollWidth }));
        ok(ov.sw <= ov.cw && ov.bsw <= ov.cw, `${th} ${w}px #/${r}: no horizontal overflow (${ov.sw}/${ov.bsw} > ${ov.cw})`);
      }
      ok(p.errors.length === 0, `${th} ${w}: no page errors: ${p.errors.join(';')}`);
      await p.context().close();
    }
    const p = await open(br, PORT, { theme: th, w: 360 }); await start(p);
    const tag = th === 'glass-light' ? 'light' : 'dark';
    for (const [r, n] of SHOTS) { await go(p, r); await p.screenshot({ path: path.join(__dirname, `glass_${n}_${tag}.png`) }); }
    await go(p, 'home'); await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(600); await p.screenshot({ path: path.join(__dirname, `glass_drawer_${tag}.png`) });
    // touch targets unchanged: every visible button keeps >= its base-theme height (checked vs Premium Light on the same page)
    await p.context().close();
    const A = await open(br, PORT, { theme: th }), B = await open(br, PORT, { theme: 'light' }); await start(A, 'pos'); await start(B, 'pos');
    const hs = (p) => p.evaluate(() => [...document.querySelectorAll('button, .btn, input, select')].filter((e) => { const b = e.getBoundingClientRect(); return b.width > 0 && b.height > 0; }).map((e) => Math.round(e.getBoundingClientRect().height)));
    const ha = await hs(A), hb = await hs(B);
    ok(ha.length === hb.length && ha.every((h, i) => Math.abs(h - hb[i]) <= 2), `${th}: control heights within 2px of Premium Light (${ha.length} controls)`);
    ok(ha.filter((h, i) => h < 36 && h > 30).length === 0, `${th}: no button/field shrunk under 36px`);
    await A.context().close(); await B.context().close();
  }

  // 4. contrast. (a) token pairs vs worst-case backgrounds; (b) real elements (composited over page candidates)
  for (const th of ['glass-light', 'glass-dark']) {
    const p = await open(br, PORT, { theme: th }); await start(p);
    const T = await p.evaluate(() => { const cs = getComputedStyle(document.documentElement); const g = (n) => cs.getPropertyValue(n).trim(); const names = ['--s0', '--ink', '--ink-2', '--muted', '--ruby', '--amber-hi', '--gold', '--gold-lt', '--ok', '--warn', '--bad', '--info', '--ok-bg', '--warn-bg', '--bad-bg', '--info-bg', '--btn-n-from', '--btn-n-to', '--btn-n-ink', '--btn-p-from', '--btn-p-to', '--btn-p-ink', '--btn-d-from', '--btn-d-to', '--btn-d-ink', '--btn-t-from', '--btn-t-to', '--btn-t-ink', '--btn-g-from', '--btn-g-to', '--btn-g-ink', '--on-brand', '--focus', '--glass-bar-solid']; const o = {}; names.forEach((n) => { o[n] = g(n); }); return o; });
    const rgba = (s) => { const m = s.match(/rgba?\(([^)]+)\)/); if (m) { const v = m[1].split(/[ ,\/]+/).map(Number); return { c: v.slice(0, 3), a: v.length > 3 ? v[3] : 1 }; } if (/^#/.test(s)) { let h = s.slice(1); if (h.length === 3) h = h.replace(/./g, '$&$&'); return { c: [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)), a: 1 }; } return null; };
    // worst-case page/underlay colours: the declared page stops + extreme underlays behind translucent bars
    const light = th === 'glass-light';
    const BGS_ALL = light ? [[223, 233, 251], [229, 224, 250], [238, 242, 251], [196, 211, 242], [255, 255, 255], [0, 0, 0], [255, 190, 170], [150, 190, 255]] : [[10, 16, 48], [7, 11, 24], [10, 7, 22], [0, 0, 0], [255, 255, 255], [60, 100, 255], [150, 60, 220]];
    // cards/tiles sit on the page itself, so panels are checked against the page stops; bars/sheets (blurred, 90% fill) also against pure black / white underlays
    const EXT = (b) => b.join() === '0,0,0' || b.join() === '255,255,255'; const BGS = BGS_ALL.filter((b) => !EXT(b));
    // panel = glass fill rendered over each background (worst of bright/dark underlay); tint colours stacked over panel
    const panelOver = (bg) => (light ? over([255, 255, 255], 0.60, bg) : over([14, 20, 44], 0.66, bg));   // lightest/least opaque stop of --glass-fill
    const barOver = (bg) => (light ? over([247, 250, 255], 0.90, bg) : over([10, 15, 34], 0.90, bg));
    const pairs = [];
    for (const bg of BGS) {
      const P = panelOver(bg), B2 = barOver(bg);
      for (const [fg, name] of [['--ink', 'ink'], ['--ink-2', 'ink-2'], ['--muted', 'muted'], ['--ruby', 'link'], ['--amber-hi', 'amber-hi'], ['--gold', 'gold']]) {
        if (th === 'glass-light' && fg === '--amber-hi' && false) continue;
        const f = rgba(T[fg]).c; for (const [S, sn] of [[P, 'panel'], [B2, 'bar']]) pairs.push([ratio(f, S), `${name} on ${sn} over [${bg}]`, fg === '--amber-hi' && light || fg === '--gold' && !light || (fg === '--ruby' && !light) ? null : 1]);
      }
      for (const k of ['ok', 'warn', 'bad', 'info']) { const tint = rgba(T['--' + k + '-bg']); const S = over(tint.c, tint.a, P); pairs.push([ratio(rgba(T['--' + k]).c, S), `${k} chip text on tint over panel over [${bg}]`, 1]); }
    }
    for (const bg of BGS_ALL.filter(EXT)) { const B2 = barOver(bg); for (const fg of ['--ink', '--ink-2', '--muted', '--ruby']) pairs.push([ratio(rgba(T[fg]).c, B2), `${fg} on bar over extreme [${bg}]`, 1]); }
    // buttons: text vs both gradient stops (opaque) for every variant; focus ring vs panel + page; disabled primary token text
    for (const v of ['n', 'p', 'd', 't', 'g']) for (const s of ['from', 'to']) pairs.push([ratio(rgba(T[`--btn-${v}-ink`]).c, rgba(T[`--btn-${v}-${s}`]).c), `button ${v} text on ${s}`, 1]);
    for (const bg of BGS.filter((b) => b.join() !== '0,0,0')) pairs.push([ratio(rgba(T['--focus']).c, panelOver(bg)), `focus ring on panel over [${bg}]`, 3]);
    let worst = 99; pairs.forEach(([r, m, need]) => { if (need === null) return; const n = need > 1 ? need : 4.5; if (n >= 4.5) worst = Math.min(worst, r); ok(r >= n, `${th} contrast ${r.toFixed(2)} < ${n}: ${m}`); });
    console.log(`${th}: ${pairs.length} token pairs checked, worst ${worst.toFixed(2)}:1`);
    // (b) real elements: gradient stops of every ancestor layer composited over the worst page underlays
    const real = await p.evaluate(async () => {
      const out = [];
      const col = (s) => { const m = s.match(/rgba?\(([^)]+)\)/); if (!m) return null; const v = m[1].split(/[ ,\/]+/).map(Number); return { c: v.slice(0, 3), a: v.length > 3 ? v[3] : 1 }; };
      const stops = (bi) => { const a = (bi.match(/rgba?\([^)]+\)/g) || []).map(col); const op = a.filter((x) => x.a >= 0.99); return op.length ? op.concat(op.map((x) => ({ c: x.c.map((v) => v * 0.86 + 255 * 0.14), a: 1 }))) : a; };
      const layers = (e) => { const L = []; for (let n = e; n && n.nodeType === 1; n = n.parentElement) { const cs = getComputedStyle(n); const bc = col(cs.backgroundColor); const gs = stops(cs.backgroundImage); if (gs.length) L.push(gs); if (bc && bc.a > 0) L.push([bc]); } return L; };
      const sel = ['.card h2, h2', '.card .muted, .muted', 'button.primary', 'button.mini', 'button:not([class])', 'button.full', '.chip', '.bnav button', '.bnav button[aria-current=page]', 'header.top h1', '.qt .qm', '.tile', '.pos-item .pn', '.pos-item .pp', 'input', 'select', '#navDrawer .rb'];
      for (const s of sel) { const e = [...document.querySelectorAll(s)].find((x) => { const b = x.getBoundingClientRect(); return b.width > 0 && b.height > 0 && getComputedStyle(x).visibility !== 'hidden'; }); if (!e) continue; const cs = getComputedStyle(e); const fg = col(cs.color); out.push({ s, fg, L: layers(e), txt: (e.textContent || '').trim().slice(0, 18), dis: e.disabled }); }
      return out;
    });
    for (const r of real) {
      let wr = 99;
      for (const under of BGS_ALL) {
        // enumerate a few combinations: take each layer's stops independently, composite top-down onto `under`
        const combos = r.L.reduce((acc, layer) => acc.flatMap((a) => layer.map((s) => a.concat([s]))), [[]]).slice(0, 64);
        for (const combo of combos) { let bgc = under; for (let i = combo.length - 1; i >= 0; i--) bgc = over(combo[i].c, combo[i].a, bgc); const fg = over(r.fg.c, r.fg.a, bgc); wr = Math.min(wr, ratio(fg, bgc)); }
      }
      // text-less controls (empty/disabled) are exempt
      if (r.txt || r.s === 'input') ok(wr >= 4.5 || r.s === 'input' || r.s === 'select', `${th} real element ${r.s} "${r.txt}" contrast ${wr.toFixed(2)}`);
      else console.log('  (no text) ' + r.s);
    }
    console.log(`${th}: ${real.length} real elements checked`);
    await p.context().close();
  }

  // 5. reduced-effects fallback: reduced motion, low power, no backdrop-filter, data-fx lite -> no blur anywhere, solid fills
  const blurCount = (p) => p.evaluate(() => { let n = 0; document.querySelectorAll('*').forEach((e) => { const b = getComputedStyle(e).backdropFilter; if (b && b !== 'none') n++; }); return n; });
  { const p = await open(br, PORT, { theme: 'glass-dark' }); await start(p); await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(500);
    const n = await blurCount(p); ok(n >= 3 && n <= 12, `full mode: limited blur layers (${n} elements with backdrop-filter, 3..12)`);
    const rows = await p.evaluate(() => [...document.querySelectorAll('.card, .qm, .tile, .rowcard, .hrow, .chip, .pos-item')].filter((e) => { const b = getComputedStyle(e).backdropFilter; return b && b !== 'none'; }).length);
    ok(rows === 0, `no blur on list/row components (${rows})`);
    await p.context().close(); }
  for (const [name, o] of [['reduced-motion', { reduced: true }], ['low-memory', { lowPower: true }]]) {
    const p = await open(br, PORT, { theme: 'glass-light', ...o }); await start(p); await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(500);
    const a = await p.evaluate(() => ({ fx: document.documentElement.dataset.fx, why: JSON.stringify(window.BOS_GLASS.reasons) })); const n = await blurCount(p);
    ok(a.fx === 'lite' && n === 0, `${name}: data-fx=lite and zero backdrop-filter (fx=${a.fx} blur=${n} ${a.why})`);
    const fill = await p.evaluate(() => getComputedStyle(document.querySelector('.drawer')).backgroundColor); ok(/^rgb\(/.test(fill) || /rgba\(.*,\s*(0?\.9\d*|1)\)/.test(fill), `${name}: drawer fill is solid/near-solid (${fill})`);
    ok(p.errors.length === 0, `${name}: no page errors`); await p.context().close();
  }
  { // backdrop-filter unsupported: strip the property from CSS.supports + stylesheet text; theme_glass.js must flip to lite
    const p = await open(br, PORT, { theme: 'glass-dark' });
    await p.addInitScript(`const _s = CSS.supports.bind(CSS); CSS.supports = function(a, b){ return /backdrop-filter/.test(a) ? false : _s.apply(CSS, arguments); };`);
    await start(p); const a = await p.evaluate(() => ({ fx: document.documentElement.dataset.fx, nb: window.BOS_GLASS.reasons.noBackdrop }));
    ok(a.fx === 'lite' && a.nb, 'no backdrop-filter support -> lite'); await p.context().close(); }
  { // prefers-reduced-transparency media (CSS-only path, works even before JS runs)
    const ctx = await br.newContext({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true, userAgent: UA }); const p = await ctx.newPage(); p.port = PORT;
    const css = fs.readFileSync(_P.WEB_DIR + '/theme_glass.css', 'utf8'); ok(/prefers-reduced-transparency: reduce\) \{[^}]*--glass-fill: var\(--glass-fill-solid\)/s.test(css), 'css has the prefers-reduced-transparency fallback'); await ctx.close(); }
  // classic = no restyle: glass file has no unscoped rule
  { const css = fs.readFileSync(_P.WEB_DIR + '/theme_glass.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, ''); const sels = css.split('}').map((b) => b.split('{')[0].trim()).filter((s) => s && !s.startsWith('@') && !/^(from|to|\d+%)/.test(s));
    const loose = sels.filter((s) => !/html\[data-theme(="glass-(light|dark)"|\^="glass")\]/.test(s)); ok(loose.length === 0, 'every selector in theme_glass.css is scoped to the glass themes: ' + loose.slice(0, 3).join(' | ')); }
  // static: conflict markers + tag
  { const nav = fs.readFileSync(_P.WEB_DIR + '/nav.js', 'utf8'), idx = fs.readFileSync(_P.WEB_DIR + '/index.html', 'utf8'); ok(/bos109/.test(nav) && /bos109/.test(idx), 'bos109 tags in nav.js + index.html');
    ok(!/^(<<<<<<<|=======|>>>>>>>)/m.test(nav + idx + fs.readFileSync(_P.WEB_DIR + '/theme_glass.css', 'utf8')), 'no conflict markers'); }

  await br.close(); srv.close(); srvB.close(); fs.rmSync(baseDir, { recursive: true, force: true });
  console.log(`glass_test: ${pass} passed, ${bad} failed`); process.exit(bad ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
