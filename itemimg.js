/* Islamia BOS · Item photos on cards and pickers (phase102, step Img, tag bos103 for the one items2.js upload line).
   OWNER OPTION, default OFF (= today: photos only in the item form). Rules: item_images_mode off | pos_only | everywhere, item_images_thumb_only on | off,
   item_images_cache_hours (owner types; blank = keep everything for this session only).
   HOW: a DECORATOR. No existing screen is rewritten. After a screen draws, B.itemimg.decorate(root) (also run by a MutationObserver on the page) finds elements that
   carry an item id and prepends a fixed-size slot: a coloured first-letter avatar at once, the photo fades in later. Mode off => nothing is added to the page at all.
     pos_only   : the POS item cards (.pos-item[data-v]).
     everywhere : POS + item list rows (data-act=itemedit), stock lookup rows (lk_item), scan matches (scan_itempick), any element with data-iimg-id="<item id>",
                  and a preview next to item pickers (a text box with a datalist, or select[data-sxl=item]) once an item is chosen.
   DATA: ids -> first photo path with ONE rpc items_first_image (no full item rows), then ONE createSignedUrls per screen (thumbnail path + '.t.jpg' and original together;
   the thumbnail is used when it exists, else the original). Images load lazily (IntersectionObserver), at most 4 at a time, never block drawing or selling.
   CACHE: memory for the session; with item_images_cache_hours set, signed links + paths also in localStorage and the picture bytes in the Cache API (shown even offline).
   Page #/itemimg (owner): mode, thumbnail, hours, clear cache, pictures loaded this session. data-act names start with img_.
   Language rule: English mode is all English; Bangla mode keeps common words English; mix = Bng/Eng. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, esc, toast, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);

const X = {
  title: L('আইটেমের ছবি', 'Item photos', 'Item এর photo'),
  intro: L('আইটেম কার্ড ও তালিকায় ছবি দেখানো হবে কি না আপনি ঠিক করুন। বন্ধ থাকলে সব আগের মতোই চলে। ছবি না থাকলে নামের প্রথম অক্ষর দেখায়। ছবি না এলেও বিক্রি কখনো আটকায় না।',
    'Choose whether item cards and lists show photos. While Off, everything works as before. An item without a photo shows the first letter of its name. If a photo does not load, selling is never blocked.',
    'Item card ও list এ photo দেখানো হবে কি না আপনি ঠিক করুন। Off থাকলে সব আগের মতোই চলে। Photo না থাকলে নামের প্রথম অক্ষর দেখায়। Photo না এলেও sale কখনো আটকায় না।'),
  mode: L('কোথায় ছবি দেখাবে', 'Where to show photos', 'কোথায় photo দেখাবে'),
  m_off: L('বন্ধ', 'Off', 'Off'), m_pos_only: L('শুধু POS', 'POS only', 'শুধু POS'), m_everywhere: L('সব জায়গায়', 'Everywhere', 'সব জায়গায়'),
  d_off: L('আগের মতো: ছবি শুধু আইটেমের ফর্মে।', 'As before: photos only in the item form.', 'আগের মতো: photo শুধু item form এ।'),
  d_pos_only: L('শুধু POS-এর আইটেম কার্ডে ছবি।', 'Photos on the POS item cards only.', 'শুধু POS এর item card এ photo।'),
  d_everywhere: L('POS, আইটেম তালিকা, stock বাছাই, purchase, recipe, scan ও online order-এ ছবি।', 'Photos on POS, item list, stock pickers, purchase, recipe, scan and online order.', 'POS, item list, stock বাছাই, purchase, recipe, scan ও online order এ photo।'),
  rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'),
  recWhy: L('ছবি মোবাইল ডেটা খরচ করে। POS-এ কার্ডের সংখ্যা সীমিত আর ব্যস্ত সময়ে ঠিক আইটেম চেনা সহজ হয়; লম্বা তালিকায় অনেক ছবি লোড হয়। তাই শুরুতে শুধু POS। নেট ভালো হলে পরে সব জায়গায় দিতে পারেন।',
    'Photos use mobile data. On the POS the number of cards is limited and a photo helps to pick the right item in busy hours, while long lists load many pictures. So start with POS only; switch to Everywhere later if your data is good.',
    'Photo mobile data খরচ করে। POS এ card এর সংখ্যা সীমিত আর busy সময়ে ঠিক item চেনা সহজ হয়; লম্বা list এ অনেক photo load হয়। তাই শুরুতে শুধু POS। Net ভালো হলে পরে সব জায়গায় দিতে পারেন।'),
  thumb: L('ছোট thumbnail আগে লোড করুন', 'Load the small thumbnail first', 'ছোট thumbnail আগে load করুন'),
  thumbH: L('নতুন আপলোড করা ছবির সাথে একটি ছোট কপি যায়; সেটা থাকলে কম ডেটা লাগে, না থাকলে আসল ছবি আসে। প্রস্তাবিত: On।',
    'A newly uploaded photo also gets a small copy; when it exists less data is used, otherwise the original is loaded. Recommended: On.',
    'নতুন upload করা photo র সাথে একটি ছোট copy যায়; সেটা থাকলে কম data লাগে, না থাকলে আসল photo আসে। Recommended: On।'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'),
  hours: L('ছবি কত ঘণ্টা মনে রাখবে', 'Hours to keep pictures', 'Photo কত ঘণ্টা মনে রাখবে'),
  hoursH: L('আপনি লিখবেন; ফাঁকা = শুধু এই সেশন। ঘণ্টা দিলে ধীর বা অফলাইন নেটেও আগে দেখা ছবি আসে, কিন্তু বদলানো ছবি দেরিতে দেখা যায়।',
    'You type it; blank = this session only. With hours set, pictures already seen also show on slow or offline data, but a changed photo shows later.',
    'আপনি লিখবেন; ফাঁকা = শুধু এই session। Hours দিলে slow বা offline net এও আগে দেখা photo আসে, কিন্তু বদলানো photo দেরিতে দেখা যায়।'),
  save: L('রাখুন', 'Save', 'Save'), clear: L('ফাঁকা করুন', 'Clear', 'Clear'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  clearCache: L('ছবির cache মুছুন', 'Clear image cache', 'Image cache মুছুন'), cleared: L('ছবির cache মোছা হয়েছে', 'Image cache cleared', 'Image cache মোছা হয়েছে'),
  usage: L('এই সেশনে লোড হওয়া ছবি', 'Pictures loaded this session', 'এই session এ load হওয়া photo'),
  usageH: L('ডেটা কতটা লাগে তা আপনার নেট ও ছবির সংখ্যার উপর নির্ভর করে, তাই আনুমানিক MB দেখানো হয় না।',
    'Data used depends on your network and the number of pictures, so no estimated MB is shown.', 'Data কতটা লাগে তা আপনার net ও photo র সংখ্যার উপর নির্ভর করে, তাই আনুমানিক MB দেখানো হয় না।'),
  cur: L('এখন', 'Current', 'Current'),
  ownerOnly: L('এটি করতে মালিক লাগবে।', 'Only the owner can do this.', 'এটা করতে owner লাগবে।'),
  bad: L('১ থেকে ৭২০ এর মধ্যে সংখ্যা লিখুন।', 'Type a number from 1 to 720.', '১ থেকে ৭২০ এর মধ্যে number লিখুন।'),
  err: L('সংরক্ষণ হয়নি', 'Could not save', 'Save হয়নি'),
};
const T = (k) => (X[k] ? lab(X[k]) : k);

/* ---------- rules (read through B.rule each time: a plain lookup, no network) ---------- */
const MODES = ['off', 'pos_only', 'everywhere'];
const rule = (k, f) => { try { return B.rule ? B.rule(k, f) : f; } catch (e) { return f; } };
const mode = () => { const m = rule('item_images_mode', 'off'); return MODES.indexOf(m) >= 0 ? m : 'off'; };
const thumbOn = () => rule('item_images_thumb_only', 'on') !== 'off';
const hours = () => { const n = Number(rule('item_images_cache_hours', null)); return Number.isFinite(n) && n > 0 ? n : null; };

/* ---------- state ---------- */
const SIGN_SEC = 3600, MAXPAR = 4, LSK = 'bos_iimg1', CACHE = 'bos-itemimg';
const st = { paths: new Map(), urls: new Map(), missing: new Set(), blobs: new Map(), loaded: 0, queue: [], active: 0, pending: new Set(), timer: null, io: null,
  codes: null, codesAt: 0, rpcFailAt: 0, urlFailAt: 0, dirty: false, calls: { rpc: 0, sign: 0 }, saveT: null, restored: false, css: false };
const now = () => Date.now();

/* ---------- small helpers ---------- */
const hue = (id) => { let h = 0; const s = String(id); for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h % 360; };
const letter = (name) => { const s = String(name || '').trim(); const m = s.match(/[\p{L}\p{N}]/u); return m ? m[0].toUpperCase() : '•'; };
const nameOf = (el) => { const n = el.querySelector('.pn, .nm'); return ((n && n.textContent) || el.getAttribute('data-n') || el.textContent || '').trim(); };

function css() {
  if (st.css || !document.head) return; st.css = true;
  const s = document.createElement('style'); s.id = 'iimg-css';
  s.textContent = `.iimg{position:relative;display:inline-flex;align-items:center;justify-content:center;flex:none;width:44px;height:44px;border-radius:10px;overflow:hidden;background:hsl(var(--iimg-h,200) 42% 34%);color:#fff;font:700 20px/1 var(--display,inherit);user-select:none;pointer-events:none;box-sizing:border-box}
.iimg img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .18s}.iimg img.on{opacity:1}
.iimg-card{position:absolute;top:8px;right:8px;z-index:1}.pos-item.iimg-on .pn{padding-right:50px}.pos-item.iimg-on::after{display:none}
.iimg-row{margin-inline-end:2px}.p2-row.iimg-on>div:not(.iimg):not(.pr){flex:1 1 auto;min-width:0}
.lk-row.iimg-on{display:flex;align-items:center;gap:10px}.lk-row.iimg-on>span:nth-child(2){flex:1 1 auto;text-align:start;min-width:0}
.iimg-chip{width:28px;height:28px;border-radius:7px;font-size:14px;margin-inline-end:6px;vertical-align:middle}.chip.iimg-on,button.chip.iimg-on{display:inline-flex;align-items:center}
.iimg-pv{margin-top:6px;display:flex}
@media (prefers-reduced-motion:reduce){.iimg img{transition:none}}`;
  document.head.appendChild(s);
}

/* ---------- persistence (only while item_images_cache_hours is set) ---------- */
function restore() {
  if (st.restored) return; st.restored = true; if (!hours()) return;
  try {
    const o = JSON.parse(localStorage.getItem(LSK) || 'null'); if (!o || o.v !== 1) return; const t = now(), ttl = hours() * 3600e3;
    Object.keys(o.p || {}).forEach((id) => { const e = o.p[id]; if (e && t - e[1] < ttl && !st.paths.has(id)) st.paths.set(id, e[0] || null); });
    Object.keys(o.u || {}).forEach((p) => { const e = o.u[p]; if (e && e[1] > t + 60e3 && !st.urls.has(p)) st.urls.set(p, { url: e[0], exp: e[1] }); });
  } catch (e) { /* storage blocked: memory only */ }
}
function persist() {
  if (!hours() || st.saveT) return;
  st.saveT = setTimeout(() => {
    st.saveT = null;
    try {
      const t = now(), p = {}, u = {}; let n = 0;
      st.paths.forEach((v, id) => { if (n++ < 400) p[id] = [v || 0, t]; }); n = 0;
      st.urls.forEach((v, k) => { if (v.exp > t + 60e3 && n++ < 400) u[k] = [v.url, v.exp]; });
      localStorage.setItem(LSK, JSON.stringify({ v: 1, p, u }));
    } catch (e) { /* quota or blocked */ }
  }, 400);
}
const cacheOK = () => { try { return !!(window.caches && window.caches.open); } catch (e) { return false; } };
const ckey = (k) => location.origin + '/__itemimg/' + encodeURIComponent(k);
async function cacheGet(k) {
  const h = hours(); if (!h || !cacheOK()) return null;
  try { const c = await caches.open(CACHE), r = await c.match(ckey(k)); if (!r) return null; const at = Number(r.headers.get('x-t') || 0); if (!at || now() - at > h * 3600e3) return null; return await r.blob(); } catch (e) { return null; }
}
async function cachePut(k, blob) {
  if (!hours() || !cacheOK()) return;
  try { const c = await caches.open(CACHE); await c.put(ckey(k), new Response(blob, { headers: { 'content-type': 'image/jpeg', 'x-t': String(now()) } })); } catch (e) { /* ignore */ }
}
async function clearCache() {
  st.paths.clear(); st.urls.clear(); st.missing.clear(); st.codes = null; st.rpcFailAt = 0; st.urlFailAt = 0;
  st.blobs.forEach((u) => { try { URL.revokeObjectURL(u); } catch (e) { /* ignore */ } }); st.blobs.clear();
  try { localStorage.removeItem(LSK); } catch (e) { /* ignore */ }
  if (cacheOK()) { try { await caches.delete(CACHE); } catch (e) { /* ignore */ } }
}

/* ---------- data: paths (one rpc) and signed links (one call) ---------- */
async function ensurePaths(ids) {
  restore();
  const need = [...new Set(ids)].filter((id) => !st.paths.has(id)); if (!need.length) return;
  if (now() - st.rpcFailAt < 60e3) return;
  for (let i = 0; i < need.length; i += 500) {
    const chunk = need.slice(i, i + 500);
    try {
      st.calls.rpc++; const r = await sb.rpc('items_first_image', { item_ids: chunk });
      if (!r || r.error || !Array.isArray(r.data)) { st.rpcFailAt = now(); return; }
      const got = new Map(r.data.map((x) => [String(x.item_id), x.path]));
      chunk.forEach((id) => st.paths.set(id, got.get(id) || null));
    } catch (e) { st.rpcFailAt = now(); return; }
  }
  persist();
}
const urlOK = (p) => { const e = st.urls.get(p); return !!(e && e.exp > now() + 60e3); };
async function ensureUrls(paths) {
  const want = new Set();
  paths.forEach((p) => { if (!p) return; if (!urlOK(p)) want.add(p); if (thumbOn() && !urlOK(p + '.t.jpg') && !st.missing.has(p + '.t.jpg')) want.add(p + '.t.jpg'); });
  if (!want.size || now() - st.urlFailAt < 30e3) return;
  try {
    st.calls.sign++; const r = await sb.storage.from('photos').createSignedUrls([...want], SIGN_SEC);
    if (!r || r.error || !Array.isArray(r.data)) { st.urlFailAt = now(); return; }
    const exp = now() + SIGN_SEC * 1000;
    r.data.forEach((x) => { if (x && x.path) { if (x.signedUrl) st.urls.set(x.path, { url: x.signedUrl, exp }); else st.missing.add(x.path); } });
    persist();
  } catch (e) { st.urlFailAt = now(); }
}

/* ---------- loading a picture into a slot (lazy, at most MAXPAR at once) ---------- */
function getIO() {
  if (st.io || !('IntersectionObserver' in window)) return st.io;
  st.io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { st.io.unobserve(e.target); enqueue(e.target); } }), { rootMargin: '240px' });
  return st.io;
}
function enqueue(slot) { st.queue.push(slot); pump(); }
function pump() {
  while (st.active < MAXPAR && st.queue.length) {
    const slot = st.queue.shift(); if (!slot.isConnected || slot.querySelector('img')) continue;
    st.active++; load(slot).catch(() => {}).then(() => { st.active--; pump(); });
  }
}
function showImg(slot, src) {
  return new Promise((res) => {
    const im = new Image(); im.alt = ''; im.decoding = 'async'; im.draggable = false;   // lazy = IntersectionObserver (a detached img with loading=lazy would never start)
    im.onload = () => { if (slot.isConnected) { slot.appendChild(im); requestAnimationFrame(() => im.classList.add('on')); st.loaded++; } res(true); };
    im.onerror = () => res(false);
    im.src = src;
  });
}
async function blobUrl(k) { if (st.blobs.has(k)) return st.blobs.get(k); const b = await cacheGet(k); if (!b) return null; const u = URL.createObjectURL(b); st.blobs.set(k, u); return u; }
async function load(slot) {
  const path = st.paths.get(slot.dataset.iid); if (!path) return;
  const keys = thumbOn() ? [path + '.t.jpg', path] : [path];
  if (hours()) {
    for (const k of keys) { const u = await blobUrl(k); if (u && await showImg(slot, u)) return; }
  }
  if (!urlOK(path) && !keys.some(urlOK)) { await ensureUrls([path]); }
  for (const k of keys) {
    const e = st.urls.get(k); if (!e || e.exp <= now()) continue;
    if (hours() && cacheOK()) {
      try { const r = await fetch(e.url); if (r.ok) { const b = await r.blob(); cachePut(k, b); const u = URL.createObjectURL(b); st.blobs.set(k, u); if (await showImg(slot, u)) return; } } catch (er) { /* offline: letter stays */ }
      continue;
    }
    if (await showImg(slot, e.url)) return;
  }
}
function paint(slot) {
  if (slot.dataset.done) return; const id = slot.dataset.iid; if (!st.paths.has(id)) return;
  slot.dataset.done = '1'; if (!st.paths.get(id)) return;
  const io = getIO(); if (io) io.observe(slot); else enqueue(slot);
}
function paintAll() { document.querySelectorAll('.iimg[data-iid]:not([data-done])').forEach(paint); }
function schedule(ids) {
  ids.forEach((id) => { if (!st.paths.has(id)) st.pending.add(id); });
  if (st.timer || !st.pending.size) return;
  st.timer = setTimeout(async () => {
    st.timer = null; const ids2 = [...st.pending]; st.pending.clear();
    try {
      await ensurePaths(ids2);
      await ensureUrls(ids2.map((id) => st.paths.get(id)).filter(Boolean));
    } catch (e) { /* fail soft: letters stay */ }
    paintAll();
  }, 40);
}

/* ---------- decorating ---------- */
const POS = [{ sel: '.pos-item[data-v]', id: (e) => e.dataset.v, kind: 'card' }];
const ALL = [
  { sel: '[data-act="itemedit"][data-v]', id: (e) => e.dataset.v, kind: 'row' },
  { sel: '[data-act="lk_item"][data-v]', id: (e) => e.dataset.v, kind: 'row' },
  { sel: '[data-act="scan_itempick"][data-id]', id: (e) => e.dataset.id, kind: 'chip' },
  { sel: '[data-iimg-id]', id: (e) => e.dataset.iimgId, kind: 'row' },
];
function makeSlot(id, name, kind) {
  const s = document.createElement('span'); s.className = 'iimg iimg-' + kind; s.setAttribute('aria-hidden', 'true');
  s.dataset.iid = id; s.style.setProperty('--iimg-h', String(hue(id))); s.textContent = letter(name); return s;
}
function decorate(root) {
  const m = mode();
  if (m === 'off') { if (st.dirty) undecorate(); return 0; }
  root = root || document; css(); restore(); st.dirty = true;
  const defs = m === 'pos_only' ? POS : POS.concat(ALL); const ids = []; let n = 0;
  defs.forEach((d) => {
    const list = root.querySelectorAll ? [...root.querySelectorAll(d.sel)] : [];
    if (root.matches && root.nodeType === 1 && root.matches(d.sel)) list.unshift(root);
    list.forEach((el) => {
      if (el.hasAttribute('data-iimg') || el.classList.contains('iimg')) return;
      const id = d.id(el); if (!id) return;
      const slot = makeSlot(id, nameOf(el), d.kind);
      el.setAttribute('data-iimg', '1'); el.classList.add('iimg-on'); el.insertBefore(slot, el.firstChild);
      ids.push(id); n++; paint(slot);
    });
  });
  if (m === 'everywhere') syncPickers(root);
  if (ids.length) schedule(ids);
  return n;
}
function undecorate() {
  st.dirty = false;
  document.querySelectorAll('.iimg').forEach((s) => s.remove());
  document.querySelectorAll('[data-iimg]').forEach((e) => { e.removeAttribute('data-iimg'); e.classList.remove('iimg-on'); });
  const c = document.getElementById('iimg-css'); if (c) { c.remove(); st.css = false; }
  document.querySelectorAll('input[data-iimg-pv], select[data-iimg-pv]').forEach((e) => e.removeAttribute('data-iimg-pv'));
}

/* ---------- pickers: a small preview beside a text box with a datalist / the online-order item select, shown once an item is chosen ---------- */
async function loadCodes() {
  if (st.codes) return st.codes; if (now() - st.codesAt < 60e3) return null; st.codesAt = now();
  try {
    const m = new Map();
    for (let from = 0, k = 0; k < 20; k++, from += 1000) {
      const r = await sb.from('items').select('id,code').range(from, from + 999); if (!r || r.error || !Array.isArray(r.data)) return null;
      r.data.forEach((x) => { if (x.code) m.set(String(x.code), String(x.id)); }); if (r.data.length < 1000) break;
    }
    st.codes = m; return m;
  } catch (e) { return null; }
}
function pvOf(inp) { return inp.__iimgPv && inp.__iimgPv.isConnected ? inp.__iimgPv : null; }
function setPv(inp, id, name) {
  let pv = pvOf(inp);
  if (!id) { if (pv) pv.remove(); inp.__iimgPv = null; return; }
  if (pv && pv.dataset.iid === id) return; if (pv) pv.remove();
  css();
  pv = makeSlot(id, name, 'pv'); pv.classList.add('iimg-pv'); pv.style.display = 'flex';
  inp.__iimgPv = pv; inp.setAttribute('data-iimg-pv', '1'); inp.insertAdjacentElement('afterend', pv);
  if (st.paths.has(id)) paint(pv); else schedule([id]);
}
async function syncPicker(inp) {
  try {
    if (mode() !== 'everywhere') return;
    if (inp.tagName === 'SELECT') { const o = inp.selectedOptions && inp.selectedOptions[0]; setPv(inp, inp.value || '', o ? o.textContent : ''); return; }
    const v = inp.value || '', dl = inp.list;
    if (!v || !dl || ![...dl.options].some((o) => o.value === v)) { setPv(inp, '', ''); return; }
    const code = v.split(' · ')[0].trim(), codes = await loadCodes(); if (!codes) return;
    if (inp.value !== v) return; setPv(inp, codes.get(code) || '', v.split(' · ').slice(1).join(' · '));
  } catch (e) { /* preview is optional */ }
}
function syncPickers(root) {
  const q = (root.querySelectorAll ? [...root.querySelectorAll('input[list], select[data-sxl="item"]')] : []);
  if (root.matches && root.nodeType === 1 && root.matches('input[list], select[data-sxl="item"]')) q.unshift(root);
  q.forEach((e) => { if ((e.tagName === 'SELECT' && e.value) || (e.tagName === 'INPUT' && e.value)) syncPicker(e); });
}
const onPick = (e) => { const t = e.target; if (t && t.matches && t.matches('input[list], select[data-sxl="item"]') && mode() === 'everywhere') syncPicker(t); };
document.addEventListener('input', onPick, true); document.addEventListener('change', onPick, true);

/* ---------- observer: decorate whatever was drawn, in one batch ---------- */
let obs = null, addQ = new Set(), obsT = null;
function startObserver() {
  if (obs || !window.MutationObserver || !document.body) return;
  obs = new MutationObserver((ms) => {
    if (mode() === 'off' && !st.dirty) return;
    for (const m of ms) for (const n of m.addedNodes) {
      if (n.nodeType !== 1 || (n.classList && n.classList.contains('iimg')) || (n.parentNode && n.parentNode.classList && n.parentNode.classList.contains('iimg'))) continue;
      addQ.add(n);
    }
    if (addQ.size && !obsT) obsT = setTimeout(() => { obsT = null; const q = [...addQ]; addQ = new Set(); q.forEach((n) => { if (n.isConnected) decorate(n); }); }, 30);
  });
  obs.observe(document.body, { childList: true, subtree: true });
}
startObserver();
if (document.readyState !== 'loading') setTimeout(() => decorate(document), 0);

/* ---------- settings page #/itemimg (owner) ---------- */
const isOwner = () => { try { return !!(A.S && A.S.ctx && A.S.ctx.is_owner); } catch (e) { return false; } };
const rpcSet = async (k, v) => { const r = await sb.rpc('set_rule', { p_key: k, p_value: v }); if (r && r.error) throw r.error; if (B.reloadRules) await B.reloadRules(); };
function pageHTML() {
  const cur = mode(), th = thumbOn() ? 'on' : 'off', hv = hours();
  const chip = (act, val, on, text, extra) => `<button type="button" class="tog ${on ? 'on' : ''}" data-act="${act}" data-v="${val}" aria-pressed="${on ? 'true' : 'false'}" ${extra || ''}>${esc(text)}</button>`;
  return `<p class="muted">${esc(T('intro'))}</p>
  <div class="card stack" id="img_mode_card"><b>${esc(T('mode'))}</b>
    <div class="row wrap">${MODES.map((m) => chip('img_mode', m, cur === m, T('m_' + m))).join('')}</div>
    <div class="muted" id="img_mode_d">${esc(T('cur'))}: ${esc(T('d_' + cur))}</div>
    <div class="notice"><b>${esc(T('rec'))}: ${esc(T('m_pos_only'))}</b><div>${esc(T('recWhy'))}</div></div></div>
  <div class="card stack"><b>${esc(T('thumb'))}</b>
    <div class="row wrap">${chip('img_thumb', 'on', th === 'on', T('on'))}${chip('img_thumb', 'off', th === 'off', T('off'))}</div>
    <div class="muted">${esc(T('thumbH'))}</div></div>
  <div class="card stack"><label for="img_hours"><b>${esc(T('hours'))}</b></label>
    <div class="row wrap"><input id="img_hours" inputmode="numeric" autocomplete="off" value="${hv ? esc(String(hv)) : ''}" style="flex:1;min-width:6rem">
    <button type="button" class="primary" data-act="img_hours_save">${esc(T('save'))}</button><button type="button" data-act="img_hours_clear">${esc(T('clear'))}</button></div>
    <div class="muted">${esc(T('hoursH'))}</div></div>
  <div class="card stack"><button type="button" class="full" data-act="img_clear">${esc(T('clearCache'))}</button>
    <div>${esc(T('usage'))}: <b id="img_loaded">${st.loaded}</b></div><div class="muted">${esc(T('usageH'))}</div></div>`;
}
function viewItemImg() {
  shell(T('title'), `<div id="img_body">${isOwner() ? pageHTML() : `<div class="notice warn">${esc(T('ownerOnly'))}</div>`}</div>`, true);
}
const redraw = () => { const b = $('#img_body'); if (b && isOwner()) b.innerHTML = pageHTML(); };
const guard = async (fn) => { if (!isOwner()) return toast(T('ownerOnly')); try { await fn(); toast(T('saved')); redraw(); } catch (e) { toast(T('err') + (e && e.message ? ': ' + e.message : '')); } };
Object.assign(A.H || {}, {
  img_mode: (a) => guard(async () => { await rpcSet('item_images_mode', a.dataset.v); if (mode() === 'off') undecorate(); else decorate(document); }),
  img_thumb: (a) => guard(() => rpcSet('item_images_thumb_only', a.dataset.v)),
  img_hours_save: () => {
    const v = String(($('#img_hours') || {}).value || '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim(), n = Number(v);
    if (v === '') return guard(() => rpcSet('item_images_cache_hours', null));
    if (!Number.isInteger(n) || n < 1 || n > 720) return toast(T('bad'));
    return guard(() => rpcSet('item_images_cache_hours', n));
  },
  img_hours_clear: () => guard(() => rpcSet('item_images_cache_hours', null)),
  img_clear: async () => { await clearCache(); toast(T('cleared')); redraw(); },
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { itemimg: viewItemImg });
B.itemimg = { decorate, undecorate, mode, thumbOn, hours, clearCache, stats: () => ({ loaded: st.loaded, rpcCalls: st.calls.rpc, signCalls: st.calls.sign, paths: st.paths.size, urls: st.urls.size }), pickerSync: syncPicker, X };
})();
