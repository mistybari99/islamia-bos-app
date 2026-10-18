/* Islamia BOS · (i) information hints. Package INFO-1.
   One small round (i) button next to a critical setting or screen title. Tapping it opens a bottom sheet that says, in short plain English:
   what it does, why it matters, the default, what changes if you switch it, who can change it, and related items.
   The words live in web/data/info.json (key -> entry). This file has no words of its own except the section labels.

   API (everything is safe: a missing key, a missing data file or a bad entry renders nothing and never throws)
     BOS.info('rule:owner_approval_mode')   returns an HTML string with the (i) button, or '' when the key has no entry.
                                            While info.json is still loading it returns an empty placeholder (data-info) that is upgraded when the data arrives.
     BOS.infoMount(rootEl)                  upgrades every element under rootEl (or the document) that carries data-info="<key>": the (i) button is added as its last child.
                                            A MutationObserver also does this for elements added later, so a screen only needs to write data-info="<key>".
     BOS.info.open(key)                     opens the sheet from code.     BOS.info.has(key)   true when the key has an entry.
     BOS.info.ready()                       Promise, resolves when info.json has been read (or failed).
   Keys: rule:<rule_key>, screen:<route>, grant:<grant_key>, switch:<key>, feature:<name>.
   Do not put the (i) inside a <button>; put it beside it. A tap on the (i) never reaches the row or label around it.

   Offline: info.json is read with a plain same-origin GET at start. web/sw.js (network first, cache as the fallback) keeps a copy, so the sheet works with no internet.
   Look: tokens from theme.css only (works in Premium Dark, Premium Light and Classic), 44px touch target, text sizes in em/rem so it follows the phone text size.
   English only for now (the owner will translate). UNVERIFIED on a real phone. */
(() => {
'use strict';
const B = (window.BOS = window.BOS || {});
const DATA_URL = 'data/info.json';
const ST = { data: null, loading: null, failedAt: 0, stack: [], opener: null };
const LABEL = { does: 'What it does', why: 'Why it matters', default: 'Default', change: 'What changes if you switch it', who: 'Who can change it', related: 'Related' };
const T = { ask: 'What is this?', close: 'Close', done: 'Done', back: 'Back', warn: 'Warning.', unsure: 'This text is not fully confirmed yet.' };

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const keyOf = (k) => String(k == null ? '' : k).trim();

// ---------- style (injected once; tokens only) ----------
function style() {
  if (document.getElementById('ihint-style')) return;
  const s = document.createElement('style'); s.id = 'ihint-style';
  s.textContent = `
.ihint-host { display: inline-flex; align-items: center; gap: var(--sp-1, 4px); vertical-align: middle; max-width: 100%; }
.ihint { box-sizing: border-box; display: inline-flex; align-items: center; justify-content: center; flex: none; min-width: var(--tap, 44px); min-height: var(--tap, 44px);
  margin: calc((var(--tap, 44px) - 2em) / -2) 0; padding: 0; border: 0; background: transparent; color: var(--ink-2, var(--muted, currentColor)); font: inherit; cursor: pointer; -webkit-tap-highlight-color: transparent; }
.ihint-i { box-sizing: border-box; display: inline-flex; align-items: center; justify-content: center; width: 1.8em; height: 1.8em; border: var(--bw-2, 1px) solid currentColor; border-radius: var(--r-full, 999px);
  font-family: Georgia, 'Times New Roman', serif; font-style: italic; font-weight: 700; line-height: 1; background: var(--s1, transparent); }
.ihint:hover { color: var(--ink, currentColor); }
.ihint:focus-visible { outline: var(--bw-3, 2px) solid var(--amber, currentColor); outline-offset: calc(var(--bw-3, 2px) * -1); border-radius: var(--r-full, 999px); }
.ihint-bg { position: fixed; inset: 0; z-index: 90; display: flex; align-items: flex-end; justify-content: center; background: var(--scrim, rgba(0, 0, 0, .55)); font-size: 1rem; line-height: var(--lh-text, 1.6); }
.ihint-sheet { box-sizing: border-box; position: relative; width: 100%; max-width: 640px; max-height: 88vh; max-height: 88dvh; overflow: auto; overscroll-behavior: contain;
  background: var(--raised, var(--card, Canvas)); color: var(--ink, CanvasText); border-top: var(--bw-3, 2px) solid var(--amber-a, var(--gold, currentColor));
  border-radius: var(--r-4, 18px) var(--r-4, 18px) 0 0; box-shadow: var(--sh-3, none); padding: var(--sp-4, 16px) var(--sp-4, 16px) calc(var(--sp-4, 16px) + env(safe-area-inset-bottom, 0px)); overflow-wrap: anywhere; outline: none; }
.ihint-head { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--sp-2, 8px); }
.ihint-head h2 { margin: 0; padding: var(--sp-2, 8px) 0; font-size: 1.15em; line-height: 1.35; color: var(--ink, CanvasText); }
.ihint-x, .ihint-link, .ihint-back, .ihint-done { box-sizing: border-box; min-height: var(--tap, 44px); font: inherit; cursor: pointer; }
.ihint-x { flex: none; min-width: var(--tap, 44px); padding: 0; border: var(--bw-2, 1px) solid var(--hair, currentColor); border-radius: var(--r-full, 999px); background: var(--s1, transparent); color: var(--ink, CanvasText); }
.ihint-warn { margin: var(--sp-2, 8px) 0 0; padding: var(--sp-3, 12px); border: var(--bw-2, 1px) solid var(--warn, currentColor); border-radius: var(--r-3, 12px); background: var(--warn-bg, transparent); color: var(--ink, CanvasText); }
.ihint-dl { margin: 0; }
.ihint-dl dt { margin: var(--sp-3, 12px) 0 var(--sp-1, 4px); font-size: .85em; font-weight: 700; color: var(--muted, currentColor); }
.ihint-dl dd { margin: 0; color: var(--ink, CanvasText); }
.ihint-note { margin: var(--sp-3, 12px) 0 0; color: var(--muted, currentColor); font-size: .85em; }
.ihint-rel { display: flex; flex-wrap: wrap; gap: var(--sp-2, 8px); margin: 0; padding: 0; list-style: none; }
.ihint-rel a, .ihint-link { display: inline-flex; align-items: center; padding: 0 var(--sp-3, 12px); border: var(--bw-2, 1px) solid var(--hair, currentColor); border-radius: var(--r-3, 12px); background: var(--s1, transparent); color: var(--ink, CanvasText); text-decoration: none; min-height: var(--tap, 44px); font: inherit; text-align: left; }
.ihint-back { margin-top: var(--sp-3, 12px); padding: 0 var(--sp-3, 12px); border: var(--bw-2, 1px) solid var(--hair, currentColor); border-radius: var(--r-3, 12px); background: transparent; color: var(--ink, CanvasText); }
.ihint-done { display: block; width: 100%; margin-top: var(--sp-4, 16px); min-height: var(--tap-primary, 48px); border: 0; border-radius: var(--r-3, 12px); background: var(--brand, ButtonFace); color: var(--on-brand, ButtonText); font-weight: 700; }
.ihint-x:focus-visible, .ihint-link:focus-visible, .ihint-back:focus-visible, .ihint-done:focus-visible, .ihint-rel a:focus-visible { outline: var(--bw-3, 2px) solid var(--amber, currentColor); outline-offset: 2px; }
`;
  (document.head || document.documentElement).appendChild(s);
}

// ---------- data ----------
function load() {
  if (ST.data) return Promise.resolve(ST.data);
  if (ST.loading) return ST.loading;
  ST.loading = fetch(DATA_URL, { cache: 'no-cache' }).then((r) => { if (!r.ok) throw new Error('info ' + r.status); return r.json(); })
    .then((j) => {
      const e = j && typeof j === 'object' ? j.entries : null;
      if (!e || typeof e !== 'object') throw new Error('info shape');
      ST.data = e; ST.loading = null; sweep(); return e;
    })
    .catch(() => { ST.failedAt = Date.now(); ST.loading = null; dropPlaceholders(); return null; });
  return ST.loading;
}
function ensure() { if (!ST.data && !ST.loading && Date.now() - ST.failedAt > 30000) load(); }
function entry(key) {
  try { const k = keyOf(key); if (!k || !ST.data || !has(ST.data, k)) return null; const e = ST.data[k]; return e && typeof e === 'object' && typeof e.title === 'string' && e.title ? e : null; } catch (err) { return null; }
}

// ---------- the button ----------
function btnHTML(key) {
  return `<button type="button" class="ihint" data-ihint="${esc(key)}" aria-label="${esc(T.ask)}" aria-haspopup="dialog"><span class="ihint-i" aria-hidden="true">i</span></button>`;
}
function info(key) {
  try {
    const k = keyOf(key); if (!k) return '';
    ensure();
    if (!ST.data) return ST.failedAt && !ST.loading ? '' : `<span class="ihint-host" data-info="${esc(k)}"></span>`;
    return entry(k) ? btnHTML(k) : '';
  } catch (err) { return ''; }
}
function upgrade(el) {
  try {
    if (!el || el.__ihint) return;
    if (!ST.data) { ensure(); return; }
    el.__ihint = 1;
    const k = keyOf(el.getAttribute('data-info'));
    if (!entry(k)) return;
    if (el.querySelector(':scope > .ihint')) return;
    el.classList.add('ihint-host');
    el.insertAdjacentHTML('beforeend', btnHTML(k));
  } catch (err) { /* render nothing */ }
}
function mount(root) {
  try {
    style();
    const r = root && root.querySelectorAll ? root : document;
    if (r.matches && r.matches('[data-info]')) upgrade(r);
    r.querySelectorAll('[data-info]').forEach(upgrade);
  } catch (err) { /* render nothing */ }
}
function sweep() { mount(document); }
function dropPlaceholders() { try { document.querySelectorAll('span.ihint-host[data-info]:empty').forEach((e) => e.remove()); } catch (err) { /* ignore */ } }

// ---------- the sheet ----------
function sheetEl() { return document.getElementById('ihint-sheet'); }
function routeLabel(k) {
  const e = entry(k); if (e) return e.title;
  return k.replace(/^[a-z]+:/, '').replace(/[_:]+/g, ' ');
}
function renderInto(bg) {
  const key = ST.stack[ST.stack.length - 1], e = entry(key), sh = bg.querySelector('.ihint-sheet');
  if (!e) return false;
  const row = (k) => (typeof e[k] === 'string' && e[k].trim() ? `<dt>${esc(LABEL[k])}</dt><dd>${esc(e[k])}</dd>` : '');
  let rel = '';
  if (Array.isArray(e.related)) {
    const items = e.related.map((r) => {
      const k = keyOf(r); if (!k || k === key) return '';
      if (/^screen:/.test(k)) return `<li><a href="#/${esc(k.slice(7))}" data-ihint-route="1">${esc(routeLabel(k))}</a></li>`;
      return entry(k) ? `<li><button type="button" class="ihint-link" data-ihint-go="${esc(k)}">${esc(entry(k).title)}</button></li>` : '';
    }).join('');
    if (items) rel = `<dt>${esc(LABEL.related)}</dt><dd><ul class="ihint-rel">${items}</ul></dd>`;
  }
  sh.innerHTML = `<div class="ihint-head"><h2 id="ihint-title">${esc(e.title)}</h2><button type="button" class="ihint-x" data-ihint-close="1" aria-label="${esc(T.close)}">✕</button></div>`
    + (typeof e.warn === 'string' && e.warn.trim() ? `<p class="ihint-warn" role="note"><strong>${esc(T.warn)}</strong> ${esc(e.warn)}</p>` : '')
    + `<dl class="ihint-dl">${row('does')}${row('why')}${row('default')}${row('change')}${row('who')}${rel}</dl>`
    + (e.verified === false ? `<p class="ihint-note">${esc(T.unsure)}</p>` : '')
    + (ST.stack.length > 1 ? `<button type="button" class="ihint-back" data-ihint-back="1">${esc(T.back)}</button>` : '')
    + `<button type="button" class="ihint-done" data-ihint-close="1">${esc(T.done)}</button>`;
  sh.scrollTop = 0;
  return true;
}
function open(key, opener) {
  try {
    if (!entry(key)) return;
    style(); close(true);
    ST.stack = [keyOf(key)]; ST.opener = opener || document.activeElement;
    const bg = document.createElement('div'); bg.id = 'ihint-sheet'; bg.className = 'ihint-bg';
    bg.innerHTML = '<div class="ihint-sheet" role="dialog" aria-modal="true" aria-labelledby="ihint-title" tabindex="-1"></div>';
    if (!renderInto(bg)) return;
    document.body.appendChild(bg);
    const sh = bg.querySelector('.ihint-sheet'); try { sh.focus({ preventScroll: true }); } catch (err) { sh.focus(); }
  } catch (err) { /* render nothing */ }
}
function close(silent) {
  try {
    const bg = sheetEl(); if (!bg) return;
    bg.remove();
    const o = ST.opener; ST.opener = null; ST.stack = [];
    if (!silent && o && o.isConnected && o.focus) o.focus();
  } catch (err) { /* ignore */ }
}

// ---------- events (document level, capture: a tap on the (i) never reaches the row around it) ----------
document.addEventListener('click', (ev) => {
  try {
    const t = ev.target && ev.target.closest ? ev.target : null; if (!t) return;
    const b = t.closest('.ihint');
    if (b) { ev.preventDefault(); ev.stopPropagation(); open(b.getAttribute('data-ihint'), b); return; }
    const bg = sheetEl(); if (!bg || !bg.contains(t) && t !== bg) return;
    if (t === bg) { ev.stopPropagation(); close(); return; }
    if (t.closest('[data-ihint-close]')) { ev.preventDefault(); ev.stopPropagation(); close(); return; }
    const go = t.closest('[data-ihint-go]');
    if (go) { ev.preventDefault(); ev.stopPropagation(); ST.stack.push(go.getAttribute('data-ihint-go')); if (!renderInto(bg)) ST.stack.pop(); else bg.querySelector('.ihint-sheet').focus(); return; }
    if (t.closest('[data-ihint-back]')) { ev.preventDefault(); ev.stopPropagation(); ST.stack.pop(); renderInto(bg); bg.querySelector('.ihint-sheet').focus(); return; }
    if (t.closest('[data-ihint-route]')) { ST.opener = null; close(true); }   // the link navigates by itself
  } catch (err) { /* ignore */ }
}, true);
document.addEventListener('keydown', (ev) => {
  try {
    const bg = sheetEl();
    if (bg) {
      if (ev.key === 'Escape' || ev.key === 'Esc') { ev.preventDefault(); ev.stopPropagation(); close(); return; }
      if (ev.key === 'Tab') {
        const f = Array.from(bg.querySelectorAll('button, a[href]')).filter((x) => !x.disabled);
        if (!f.length) { ev.preventDefault(); return; }
        const first = f[0], last = f[f.length - 1], a = document.activeElement, sh = bg.querySelector('.ihint-sheet');
        if (ev.shiftKey && (a === first || a === sh)) { ev.preventDefault(); last.focus(); }
        else if (!ev.shiftKey && a === last) { ev.preventDefault(); first.focus(); }
        else if (!bg.contains(a)) { ev.preventDefault(); first.focus(); }
        return;
      }
    }
    if ((ev.key === 'Enter' || ev.key === ' ') && ev.target && ev.target.closest && ev.target.closest('.ihint')) ev.stopPropagation();   // keep row key handlers out; the native click still fires
  } catch (err) { /* ignore */ }
}, true);

// ---------- elements added later ----------
function watch() {
  try {
    if (!window.MutationObserver || !document.body) return;
    let queue = new Set(), busy = false;
    const flush = () => { busy = false; const q = queue; queue = new Set(); q.forEach((n) => { if (n.isConnected) mount(n); }); };
    new MutationObserver((muts) => {
      for (const m of muts) m.addedNodes.forEach((n) => { if (n.nodeType === 1 && (n.hasAttribute('data-info') || n.querySelector('[data-info]'))) queue.add(n); });
      if (queue.size && !busy) { busy = true; (window.requestAnimationFrame || setTimeout)(flush); }
    }).observe(document.body, { childList: true, subtree: true });
  } catch (err) { /* ignore */ }
}

info.open = (k) => open(k);
info.has = (k) => !!entry(k);
info.ready = () => load();
info.close = () => close();
B.info = info; B.infoMount = mount;

style();
load();
window.addEventListener('online', () => { if (!ST.data) { ST.failedAt = 0; load(); } });
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => { watch(); sweep(); }); else { watch(); sweep(); }
})();
