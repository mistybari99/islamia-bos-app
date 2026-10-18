/* Islamia BOS · service worker. Goal: the app opens with no internet after the first visit (the POS and the form outbox already work offline once open).
   Rules: only same-origin GET requests are cached; Supabase (API, auth, storage) and anything else is never touched. Network first (so a new version is picked up at once),
   cache as the fallback; navigations fall back to the cached index.html. Bump VERSION to drop the old cache. */
const VERSION = 'bos-sw-v5';
self.addEventListener('install', (e) => { e.waitUntil(self.skipWaiting()); });
// X5 explicit precache hook: small recognition helpers and the ZXing barcode fallback (336 KB). The OCR files (about 7 MB) are NOT here:
// they are fetched when the OCR switch is on and then kept by web/scan.js. Add a path here on purpose only.
const PRECACHE = ['vendor/zxing/zxing-library-0.21.3.min.js', 'scan_core.js', 'photo.js', 'scan.js', 'scan_native.js'];
self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    try {
      const c = await caches.open(VERSION);
      await Promise.all(PRECACHE.map((u) => fetch(new URL(u, self.location).href, { cache: 'reload' }).then((r) => (r && r.ok ? c.put(new URL(u, self.location).href, r) : null)).catch(() => {})));
    } catch (err) { /* precache is best effort: the app still works online */ }
    await self.skipWaiting();
  })());
});
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
