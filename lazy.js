/* Islamia BOS · Lazy screens (bos114, step WebLoad). Tiny loader: a screen's script is fetched the first time its route opens, not at start-up.
   The map (window.BOS_LAZY_MAP = { v:{file:hash}, routes:{page:[files in load order]}, idle:[files] }) is written by tools/web_build.js into the built core bundle.
   WITHOUT the map (the plain web/ folder, tests, dev) this file does nothing: every script is already loaded by index.html and need() is always false.
   - need(page)  : true when the page's script set is not fully loaded yet.      load(page) : Promise, resolves when every file ran (in the original order, once each).
   - app.js dispatch() awaits load() before it draws the route, so a deep link (#/employees on a cold start) and a menu tap both work; the screen code is unchanged.
   - idle files (decorators such as item photos, Home badges, dashboard link) are fetched in the background after the first screen is drawn, one per idle slot, and never while a route is loading.
   - Also swaps the print-media Google Fonts link to "all" (non-blocking font CSS; font-display=swap is in the URL). */
(() => {
'use strict';
const Z = window.BOS_LAZY = { loaded: Object.create(null), inflight: Object.create(null), busy: 0, seq: 0, idleStarted: false };
const map = () => window.BOS_LAZY_MAP || null;
const url = (f) => { const m = map(), v = m && m.v && m.v[f]; return f + (v ? '?v=' + v : ''); };
function one(f) {
  if (Z.loaded[f]) return Promise.resolve();
  if (Z.inflight[f]) return Z.inflight[f];
  return (Z.inflight[f] = new Promise((res, rej) => {
    const s = document.createElement('script');
    s.async = false;   // dynamically added scripts with async=false run in insertion order = the original index.html order
    s.src = url(f);
    s.onload = () => { Z.loaded[f] = true; delete Z.inflight[f]; res(); };
    s.onerror = () => { delete Z.inflight[f]; try { s.remove(); } catch (e) { /* gone */ } rej(new Error('lazy script failed: ' + f)); };
    document.head.appendChild(s);
  }));
}
const ensure = (files) => Promise.all(files.map(one));
Z.files = (page) => { const m = map(); return (m && m.routes && m.routes[page]) || []; };
Z.need = (page) => Z.files(page).some((f) => !Z.loaded[f]);
Z.load = (page) => {
  const root = document.documentElement;
  Z.busy++; root.classList.add('lz-busy');
  return ensure(Z.files(page)).then(() => { Z.busy--; if (!Z.busy) root.classList.remove('lz-busy'); }, (e) => { Z.busy--; if (!Z.busy) root.classList.remove('lz-busy'); throw e; });
};
// background files, after the first screen is drawn
const whenIdle = (fn) => { if (window.requestIdleCallback) window.requestIdleCallback(fn, { timeout: 4000 }); else setTimeout(fn, 800); };
Z.first = () => {
  if (Z.idleStarted) return; Z.idleStarted = true;
  const m = map(); if (!m || !m.idle || !m.idle.length) return;
  const queue = m.idle.slice();
  const next = () => {
    if (!queue.length) return;
    if (Z.busy) return setTimeout(() => whenIdle(next), 400);   // a screen is loading: let it have the network
    const f = queue.shift();
    one(f).then(() => whenIdle(next), () => { /* offline / blocked: the decorator is optional, try the rest */ whenIdle(next); });
  };
  whenIdle(next);
};
// loading feedback for EVERY screen that waits (bos114): a thin bar after 150 ms, a "slow connection" bar with Retry after 6 s. page = the route being drawn; settles when the view's promise does.
let slowEl = null, trackSeq = 0;
const pageNow = () => (location.hash.replace(/^#\/?/, '') || 'home').split('/')[0];
function clearSlow() { if (slowEl) { slowEl.remove(); slowEl = null; } }
Z.track = (p, page) => {
  if (!p || typeof p.then !== 'function') return p;
  const my = ++trackSeq, root = document.documentElement; let on = false;
  const live = () => my === trackSeq && pageNow() === page;
  const t1 = setTimeout(() => { if (live()) { on = true; Z.busy++; root.classList.add('lz-busy'); } }, 150);
  const t2 = setTimeout(() => {
    if (!live()) return; const A = window.BOS_APP, B = window.BOS; if (!A || !B || !B.L) return;
    const T = { s: B.L('ধীর সংযোগ — এখনও লোড হচ্ছে…', 'Slow connection — still loading…', 'Slow connection — এখনও loading…'), r: B.L('আবার চেষ্টা', 'Retry', 'আবার চেষ্টা') };
    clearSlow(); slowEl = document.createElement('div'); slowEl.id = 'lz_slow'; slowEl.setAttribute('role', 'status');
    slowEl.innerHTML = `<span>${A.esc(B.lab(T.s))}</span><button type="button" data-act="lz_retry">${A.esc(B.lab(T.r))}</button>`; document.body.appendChild(slowEl);
  }, 6000);
  const done = () => { clearTimeout(t1); clearTimeout(t2); if (on) { on = false; Z.busy--; if (!Z.busy) root.classList.remove('lz-busy'); } if (my === trackSeq) clearSlow(); };
  p.then(done, done); return p;
};
window.addEventListener('hashchange', clearSlow);
// screen could not be fetched (no internet and not in the saved copy): say so, offer a retry
Z.fail = (page) => {
  const A = window.BOS_APP, B = window.BOS; if (!A) return;
  const cs = window.BOS_CS;
  if (cs && cs.needsNet && (A.S.offline || navigator.onLine === false)) return cs.needsNet(page);
  const L = B.L, lab = B.lab, esc = A.esc;
  const T = { h: L('স্ক্রিন লোড হয়নি', 'This screen did not load', 'Screen load হয়নি'), p: L('ইন্টারনেট দেখে আবার চেষ্টা করুন।', 'Check the internet and try again.', 'Internet দেখে আবার চেষ্টা করুন।'), r: L('আবার চেষ্টা', 'Try again', 'আবার চেষ্টা'), b: L('হোম', 'Home', 'Home') };
  A.shell(lab(T.h), `<div class="card stack center" id="lz_fail"><h2>${esc(lab(T.h))}</h2><p>${esc(lab(T.p))}</p><button class="primary full" data-act="lz_retry">${esc(lab(T.r))}</button><button class="full" data-act="go" data-v="home">${esc(lab(T.b))}</button></div>`, 'home');
};
if (window.BOS_APP && window.BOS_APP.H) window.BOS_APP.H.lz_retry = () => window.dispatchEvent(new HashChangeEvent('hashchange'));
// fonts: the stylesheet link is added with media="print" (does not block the first paint); switch it on once it has loaded
(() => {
  const swap = (l) => { if (l.media !== 'all') l.media = 'all'; };
  document.querySelectorAll('link[data-fontswap]').forEach((l) => { if (l.sheet) swap(l); else l.addEventListener('load', () => swap(l), { once: true }); l.addEventListener('error', () => { /* offline: system fonts */ }, { once: true }); });
})();
})();
