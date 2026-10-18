/* Registers sw.js (offline start). Off switch: the rule offline_cache_on (Switchboard) or this phone's localStorage bos_sw = 'off'. Never blocks the app; any failure is silent. */
(() => {
'use strict';
if (!('serviceWorker' in navigator)) return;
const secure = location.protocol === 'https:';      // real sites only: a local test or dev server is never cached
let off = false; try { off = localStorage.getItem('bos_sw') === 'off'; } catch (e) { /* storage blocked */ }
// a phone that was switched off by the rule is re-checked after the rules load: if the rule is ON again the flag is removed and the cache comes back on the next start
const kill = async () => { try { const rs = await navigator.serviceWorker.getRegistrations(); await Promise.all(rs.map((r) => r.unregister())); const ks = await caches.keys(); await Promise.all(ks.filter((k) => k.startsWith('bos-sw-')).map((k) => caches.delete(k))); } catch (e) { /* ignore */ } };
if (!secure) return;
if (off) { window.addEventListener('load', () => setTimeout(() => { try { const B = window.BOS; if (B && B.rule && B.rule('offline_cache_on', true) !== false) { localStorage.removeItem('bos_sw'); navigator.serviceWorker.register('sw.js').catch(() => {}); } else kill(); } catch (e) { /* ignore */ } }, 5000)); return; }
window.addEventListener('load', () => {
  navigator.serviceWorker.register('sw.js').catch(() => {});
  setTimeout(() => { try { const B = window.BOS; if (B && B.rule && B.rule('offline_cache_on', true) === false) { try { localStorage.setItem('bos_sw', 'off'); } catch (e) { /* ignore */ } kill(); } else { try { if (localStorage.getItem('bos_sw') === 'off') localStorage.removeItem('bos_sw'); } catch (e) { /* ignore */ } } } catch (e) { /* ignore */ } }, 5000);
});
})();
