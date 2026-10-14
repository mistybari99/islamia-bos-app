/* Islamia BOS · service worker. Goal: the app opens with no internet after the first visit (the POS and the form outbox already work offline once open).
   Rules: only same-origin GET requests are cached; Supabase (API, auth, storage) and anything else is never touched. Network first (so a new version is picked up at once),
   cache as the fallback; navigations fall back to the cached index.html. Bump VERSION to drop the old cache. */
const VERSION = 'bos-sw-d92f6e1bd3';
/* bos110: precache at install. Without it the new cache stayed EMPTY after an update (activate deletes the old cache that held the files the page had just loaded) and after the very first visit
   (the worker is installed after the page already fetched everything), so the phone could not start offline until one more online load. Now install fetches index.html, then every local script,
   stylesheet, manifest and icon it names (cache:'reload' = never from the HTTP cache), so the new version is complete before it takes over. Best effort: any failure still installs, as before. */
const precache = async () => {
  const scope = self.registration.scope, cache = await caches.open(VERSION);
  const res = await fetch(new URL('index.html', scope).href, { cache: 'reload' }); if (!res.ok) return;
  const html = await res.clone().text(), urls = new Set();
  for (const m of html.matchAll(/<(?:script|link)\b[^>]*?\s(?:src|href)="([^"#]+)"/g)) { try { const u = new URL(m[1], scope); if (u.origin === self.location.origin && !/\/sw\.js$/.test(u.pathname)) urls.add(u.href); } catch (er) { /* skip */ } }
  await cache.put(new URL('index.html', scope).href, res.clone()); await cache.put(scope, res.clone());
  await Promise.all([...urls].map(async (u) => { try { const r = await fetch(u, { cache: 'reload' }); if (r.ok && r.type === 'basic') await cache.put(u, r); } catch (er) { /* the fetch handler caches it on first use */ } }));
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
    try {
      const res = await fetch(req);
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
