/* Islamia BOS · service worker. Goal: the app opens with no internet after the first visit (the POS and the form outbox already work offline once open).
   Rules: only same-origin GET requests are cached; Supabase (API, auth, storage) and anything else is never touched. Network first (so a new version is picked up at once),
   cache as the fallback; navigations fall back to the cached index.html. Bump VERSION to drop the old cache. */
const VERSION = 'bos-sw-v6';   // union merge: above v5 (our line) and v1 (advanced line); the build (tools/web_build.js) writes bos-sw-<build id>
/* bos110: precache at install. Without it the new cache stayed EMPTY after an update (activate deletes the old cache that held the files the page had just loaded) and after the very first visit
   (the worker is installed after the page already fetched everything), so the phone could not start offline until one more online load. Now install fetches index.html, then every local script,
   stylesheet, manifest and icon it names (cache:'reload' = never from the HTTP cache), so the new version is complete before it takes over. Best effort: any failure still installs, as before. */
/* bos114: the build (tools/web_build.js) writes the exact list of files to keep for offline start (core bundle, css, decorators, manifest, icons); the lazy screen scripts are NOT listed: they are fetched and saved the first
   time a screen opens (they are not needed offline: offline only Home and POS work). PRECACHE = null (plain web/ folder) keeps the old behaviour: everything index.html names. */
const PRECACHE = null; /*bos114-precache*/
const precache = async () => {
  const scope = self.registration.scope, cache = await caches.open(VERSION);
  const res = await fetch(new URL('index.html', scope).href, { cache: 'reload' }); if (!res.ok) return;
  const html = await res.clone().text(), urls = new Set();
  for (const m of html.matchAll(/<(?:script|link)\b[^>]*?\s(?:src|href)="([^"#]+)"/g)) { try { const u = new URL(m[1], scope); if (u.origin === self.location.origin && !/\/sw\.js$/.test(u.pathname)) urls.add(u.href); } catch (er) { /* skip */ } }
  await cache.put(new URL('index.html', scope).href, res.clone()); await cache.put(scope, res.clone());
  if (PRECACHE) for (const f of PRECACHE) { try { urls.add(new URL(f, scope).href); } catch (er) { /* skip */ } }
  // update = only what changed: a file whose URL (it carries ?v=<content hash>) is already in an older cache is copied, not downloaded again
  const olds = (await caches.keys()).filter((k) => k.startsWith('bos-sw-') && k !== VERSION);
  const have = async (u) => { if (!/[?&]v=[0-9a-f]{10}/.test(u)) return null; for (const k of olds) { const c = await caches.open(k); const h = await c.match(u, { ignoreSearch: false }); if (h && h.ok) return h; } return null; };
  await Promise.all([...urls].map(async (u) => { try { const h = await have(u); if (h) { await cache.put(u, h); return; } const r = await fetch(u, { cache: /[?&]v=[0-9a-f]{10}/.test(u) ? 'force-cache' : 'reload' }); if (r.ok && r.type === 'basic') await cache.put(u, r); } catch (er) { /* the fetch handler caches it on first use */ } }));   // bos114: a ?v=<hash> file is immutable: take it from the HTTP cache (the page just downloaded it) instead of a second download
};
self.addEventListener('install', (e) => { e.waitUntil((async () => { try { await precache(); } catch (er) { /* best effort */ } await self.skipWaiting(); })()); });
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => { const keys = await caches.keys(); await Promise.all(keys.filter((k) => k.startsWith('bos-sw-') && k !== VERSION).map((k) => caches.delete(k))); await self.clients.claim(); })());
});
self.addEventListener('fetch', (e) => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  if (/\/(rest|auth|storage|realtime|functions)\/v1\//.test(url.pathname)) return;
  e.respondWith((async () => {
    const cache = await caches.open(VERSION);
    // bos114: a file named with ?v=<content hash> never changes: the saved copy is the answer (no network round trip per script on every start)
    if (req.mode !== 'navigate' && /[?&]v=[0-9a-f]{10}(&|$)/.test(url.search)) { const hit = await cache.match(req, { ignoreSearch: false }); if (hit) return hit; }
    // the vendor library never changes between deploys: saved copy first, refreshed in the background
    if (/\/vendor\/[^/]+\.js$/.test(url.pathname)) { const hit = await cache.match(req, { ignoreSearch: true }); if (hit) { fetch(req).then((r) => { if (r && r.ok && r.type === 'basic') cache.put(req, r); }).catch(() => {}); return hit; } }
    try {
      // bos114: a page start waits for the network at most 4 s when a saved index.html exists (slow mobile data); the network answer still refreshes the copy
      const res = await (req.mode === 'navigate' ? Promise.race([fetch(req), (async () => { await new Promise((r) => setTimeout(r, 4000)); const c = await cache.match('index.html') || await cache.match(self.registration.scope); if (c) return c; return new Promise(() => {}); })()]) : fetch(req));
      if (res && res.ok && res.type === 'basic') cache.put(req, res.clone()).catch(() => {});
      return res;
    } catch (err) {
      const hit = await cache.match(req, { ignoreSearch: false }) || await cache.match(req, { ignoreSearch: true });
      if (hit) return hit;
      if (req.mode === 'navigate') { const idx = await cache.match('index.html') || await cache.match('./') || await cache.match(self.registration.scope); if (idx) return idx; }
      return new Response('offline', { status: 503, statusText: 'offline' });
    }
  })());
});
