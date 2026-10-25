/* Islamia BOS · collapsed control kit (controls.js). Nothing is shown OPEN in a field: dropdown, multi-select, tick, ⋮ menu.
   API (window.BOS.ctl):
     select(cfg|<select>)  cfg {options:[[v,label]|{v,l,sub}], value, onChange(v), title, placeholder, disabled, search}  -> element (.ctl-wrap); a <select> is enhanced in place
     multi(cfg)            cfg {options, values:[], onChange([v]), title, placeholder, disabled}                          -> element
     tick(cfg)             cfg {label, checked, onChange(bool), disabled}                                                 -> <label class="ctl-tick">
     menu(cfg)             cfg {items:[{label, onClick, danger, disabled}], label}                                        -> ⋮ button (secondary actions only)
     seg(cfg)              cfg {options (<=3), value, onChange}                                                           -> compact segmented control
     enhance(root)         converts existing markup (see below); idempotent; runs automatically after every render
     on() / setMode('on'|'off'|null)   global switch: rule ui_collapsed_controls (absent = ON) and per-phone localStorage bos_ctl_collapsed='off'
   enhance() rules: native <select> -> sheet dropdown (select stays in the DOM, hidden, value/events kept); CH groups ([data-act=pick]) >3 options -> dropdown,
   <=3 -> compact seg, read-only -> plain value; groups of >=4 `button.tog[data-act][data-v]` with <=1 on -> dropdown; filter / sell-unit multi groups (fl_t, data-su)
   and >=4 checkbox labels -> multi; rows with 3+ secondary buttons -> ⋮.  Opt out with data-ctl="off".  Originals stay in the DOM (visually hidden) and receive the click. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { S, esc } = A;
const L = B.L, lab = B.lab;
const X = {
  apply: L('অ্যাপ্লাই', 'Apply', 'Apply'), all: L('সব বাছুন', 'Select all', 'Select all'), clear: L('মুছুন', 'Clear', 'Clear'), close: L('বন্ধ', 'Close', 'Close'),
  search: L('খুঁজুন', 'Search', 'Search'), none: L('— বাছুন —', '— choose —', '— বাছুন —'), noval: L('(কিছু নয়)', '(none)', '(কিছু নয়)'), more: L('আরও', 'More', 'আরও'),
  nsel: L('টি বাছা', 'selected', 'selected'), nores: L('কিছু পাওয়া যায়নি', 'Nothing found', 'Nothing found'), cur: L('বর্তমান', 'current', 'current'),
};
const T = (k) => lab(X[k]);
const STATS = { select: 0, choice: 0, multi: 0, seg: 0, menu: 0, cb: 0 };
const store = { get: () => { try { return localStorage.getItem('bos_ctl_collapsed'); } catch (e) { return null; } } };
const rule = () => { try { return B.rule ? B.rule('ui_collapsed_controls', true) : true; } catch (e) { return true; } };
const on = () => store.get() !== 'off' && rule() !== false && rule() !== 'false';
function setMode(m) { try { if (m === 'off') localStorage.setItem('bos_ctl_collapsed', 'off'); else localStorage.removeItem('bos_ctl_collapsed'); } catch (e) { /* private mode */ } sync(); if (on()) enhance(document.body); }
function sync() { document.documentElement.setAttribute('data-ctl', on() ? 'on' : 'off'); }
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };
const CHEV = '<svg class="ctl-chev" viewBox="0 0 16 16" width="12" height="12" aria-hidden="true" focusable="false"><path d="M3 6l5 5 5-5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const CHECK = '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M3 8.5l3.2 3.2L13 4.8" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const norm = (o) => (Array.isArray(o) ? { v: String(o[0]), l: typeof o[1] === 'object' && o[1] ? lab(o[1]) : String(o[1] == null ? o[0] : o[1]) } : { v: String(o.v), l: o.l, sub: o.sub, disabled: o.disabled });
let uid = 0;

// ---------------------------------------------------------------- sheet
let OPEN = null;
function closeSheet(restore = true) {
  if (!OPEN) return; const o = OPEN; OPEN = null;
  document.removeEventListener('keydown', o.key, true); o.bg.remove();
  if (o.trg) o.trg.setAttribute('aria-expanded', 'false');
  if (restore && o.back && o.back.isConnected) { try { o.back.focus(); } catch (e) { /* gone */ } }
}
// c: {title, options:[{v,l,sub,disabled}], value | values:Set, multi, search, menu, clearLabel, onPick(v), onApply(Set), trg}
function openSheet(c) {
  closeSheet(false);
  const back = c.trg || document.activeElement, id = 'ctl' + (++uid);
  const bg = el('div', 'ctl-bg'), sh = el('div', 'ctl-sheet' + (c.menu ? ' ctl-menu' : ''));
  sh.setAttribute('role', c.menu ? 'dialog' : 'dialog'); sh.setAttribute('aria-modal', 'true'); sh.setAttribute('aria-label', c.title || T('more'));
  const head = el('div', 'ctl-head', `<b>${esc(c.title || '')}</b>`); const x = el('button', 'ctl-x', '✕'); x.type = 'button'; x.setAttribute('aria-label', T('close')); head.appendChild(x); sh.appendChild(head);
  let q = null; if (c.search) { q = el('input', 'ctl-q'); q.type = 'search'; q.placeholder = T('search'); q.setAttribute('aria-label', T('search')); sh.appendChild(q); }
  const list = el('div', 'ctl-list'); list.id = id; list.setAttribute('role', c.menu ? 'menu' : 'listbox'); if (c.multi) list.setAttribute('aria-multiselectable', 'true'); sh.appendChild(list);
  const sel = new Set(c.multi ? [...c.values] : []);
  const optEls = [];
  const draw = (f) => {
    list.innerHTML = ''; optEls.length = 0; const ft = (f || '').toLowerCase();
    const rows = c.options.filter((o) => !ft || (o.l + ' ' + (o.sub || '')).toLowerCase().includes(ft));
    if (!rows.length) list.appendChild(el('div', 'ctl-empty', esc(T('nores'))));
    rows.forEach((o) => {
      const isSel = c.multi ? sel.has(o.v) : (!c.menu && String(c.value) === o.v);
      const b = el('button', 'ctl-opt' + (isSel ? ' on' : '') + (o.danger ? ' bad' : ''));
      b.type = 'button'; b.dataset.v = o.v; b.tabIndex = -1; b.disabled = !!o.disabled;
      b.setAttribute('role', c.menu ? 'menuitem' : 'option'); if (!c.menu) b.setAttribute('aria-selected', isSel ? 'true' : 'false');
      b.innerHTML = (c.multi ? `<span class="ctl-box">${isSel ? CHECK : ''}</span>` : '') + `<span class="ctl-ot">${esc(o.l)}${o.sub ? `<small>${esc(o.sub)}</small>` : ''}</span>` + (!c.multi && !c.menu && isSel ? `<span class="ctl-ck">${CHECK}</span>` : '');
      b.addEventListener('click', () => {
        if (c.multi) { if (sel.has(o.v)) sel.delete(o.v); else sel.add(o.v); const keep = list.scrollTop; draw(q ? q.value : ''); list.scrollTop = keep; const f2 = list.querySelector(`[data-v="${CSS.escape(o.v)}"]`); if (f2) f2.focus(); return; }
        closeSheet(); if (c.onPick) c.onPick(o.v);
      });
      list.appendChild(b); optEls.push(b);
    });
  };
  draw('');
  if (c.multi) {
    const foot = el('div', 'ctl-foot'); const a = el('button', 'ctl-fb', esc(T('all'))), z = el('button', 'ctl-fb', esc(T('clear'))), ap = el('button', 'ctl-fb pri', esc(T('apply')));
    [a, z, ap].forEach((b) => { b.type = 'button'; foot.appendChild(b); });
    a.addEventListener('click', () => { c.options.forEach((o) => { if (!o.disabled) sel.add(o.v); }); draw(q ? q.value : ''); });
    z.addEventListener('click', () => { sel.clear(); draw(q ? q.value : ''); });
    ap.addEventListener('click', () => { closeSheet(); if (c.onApply) c.onApply(sel); });
    sh.appendChild(foot);
  }
  bg.appendChild(sh); document.body.appendChild(bg);
  const focusables = () => [...sh.querySelectorAll('button:not([disabled]),input')].filter((e) => e.offsetParent !== null || e === document.activeElement);
  const key = (e) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeSheet(); return; }
    const opts = optEls.filter((b) => !b.disabled), i = opts.indexOf(document.activeElement);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { if (!opts.length) return; e.preventDefault(); const n = e.key === 'ArrowDown' ? (i + 1) % opts.length : (i <= 0 ? opts.length - 1 : i - 1); opts[n].focus(); }
    else if (e.key === 'Home' && i >= 0) { e.preventDefault(); opts[0].focus(); } else if (e.key === 'End' && i >= 0) { e.preventDefault(); opts[opts.length - 1].focus(); }
    else if (e.key === 'Tab') { const f = focusables(); if (!f.length) return; const j = f.indexOf(document.activeElement); if (e.shiftKey && j <= 0) { e.preventDefault(); f[f.length - 1].focus(); } else if (!e.shiftKey && j === f.length - 1) { e.preventDefault(); f[0].focus(); } }
  };
  document.addEventListener('keydown', key, true);
  bg.addEventListener('click', (e) => { if (e.target === bg) closeSheet(); }); x.addEventListener('click', () => closeSheet());
  if (q) q.addEventListener('input', () => draw(q.value));
  OPEN = { bg, key, trg: c.trg, back };
  if (c.trg) c.trg.setAttribute('aria-expanded', 'true');
  const first = list.querySelector('.ctl-opt.on') || list.querySelector('.ctl-opt:not([disabled])');
  if (first) first.focus(); else x.focus();
  return sh;
}

// ---------------------------------------------------------------- trigger
function mkTrigger(kind, title) {
  const t = el('button', 'ctl-trg'); t.type = 'button'; t.dataset.kind = kind; t.setAttribute('aria-haspopup', kind === 'menu' ? 'menu' : 'listbox'); t.setAttribute('aria-expanded', 'false');
  if (title) t.setAttribute('aria-label', title); return t;
}
function setTrg(t, text, active, disabled) {
  t.innerHTML = `<span class="ctl-tx">${esc(text)}</span>${disabled ? '' : CHEV}`; t.classList.toggle('ctl-act', !!active); t.classList.toggle('ctl-ro', !!disabled); t.disabled = !!disabled;
}
function titleFor(node) {
  if (!node) return '';
  const a = node.getAttribute && (node.getAttribute('aria-label') || node.dataset.title); if (a) return a;
  if (node.id) { const l = document.querySelector(`label[for="${CSS.escape(node.id)}"]`); if (l) return l.textContent.replace('*', '').trim(); }
  const f = node.closest && node.closest('.fld'); if (f) { const l = f.querySelector('label'); if (l) return l.textContent.replace('*', '').trim(); }
  const s = node.closest && node.closest('details'); if (s) { const b = s.querySelector('summary b, summary'); if (b) return b.textContent.trim(); }
  let p = node.previousElementSibling; while (p) { if (/^(LABEL|H2|H3|B|SPAN)$/.test(p.tagName) && p.textContent.trim().length < 40) return p.textContent.replace('*', '').trim(); p = p.previousElementSibling; }
  return '';
}

// ---------------------------------------------------------------- API: select / multi / tick / menu / seg
function select(cfg) {
  if (cfg && cfg.tagName === 'SELECT') { enhanceSelect(cfg); return cfg._ctl && cfg._ctl.trg; }
  const w = el('span', 'ctl-wrap'), t = mkTrigger('select', cfg.title); let value = cfg.value == null ? '' : String(cfg.value);
  const opts = () => (typeof cfg.options === 'function' ? cfg.options() : cfg.options || []).map(norm);
  const paint = () => { const o = opts().find((x) => x.v === value); setTrg(t, o ? o.l : (cfg.placeholder || T('none')), !!value, cfg.disabled); };
  t.addEventListener('click', () => { const os = opts(); openSheet({ title: cfg.title, options: os, value, search: cfg.search !== false && os.length > 8, trg: t, onPick: (v) => { value = v; paint(); if (cfg.onChange) cfg.onChange(v); } }); });
  paint(); w.appendChild(t); Object.defineProperty(w, 'value', { get: () => value, set: (v) => { value = v == null ? '' : String(v); paint(); } }); STATS.select++; return w;
}
function multi(cfg) {
  const w = el('span', 'ctl-wrap'), t = mkTrigger('multi', cfg.title); let vals = (cfg.values || []).map(String);
  const opts = () => (typeof cfg.options === 'function' ? cfg.options() : cfg.options || []).map(norm);
  const paint = () => { const os = opts(), ls = vals.map((v) => (os.find((o) => o.v === v) || { l: v }).l); setTrg(t, !ls.length ? (cfg.placeholder || T('none')) : ls.length <= 2 ? ls.join(', ') : ls.length + ' ' + T('nsel'), ls.length, cfg.disabled); };
  t.addEventListener('click', () => { const os = opts(); openSheet({ title: cfg.title, options: os, multi: true, values: new Set(vals), search: os.length > 8, trg: t, onApply: (s) => { vals = [...s]; paint(); if (cfg.onChange) cfg.onChange(vals.slice()); } }); });
  paint(); w.appendChild(t); Object.defineProperty(w, 'values', { get: () => vals.slice(), set: (v) => { vals = (v || []).map(String); paint(); } }); STATS.multi++; return w;
}
function tick(cfg) {
  const l = el('label', 'ctl-tick'), i = el('input'); i.type = 'checkbox'; i.checked = !!cfg.checked; i.disabled = !!cfg.disabled;
  l.appendChild(i); l.appendChild(el('span', 'ctl-tbox', CHECK)); l.appendChild(el('span', 'ctl-tl', esc(cfg.label || '')));
  i.addEventListener('change', () => { if (cfg.onChange) cfg.onChange(i.checked); }); return l;
}
function menu(cfg) {
  const t = mkTrigger('menu', cfg.label || T('more')); t.classList.add('ctl-dots'); t.innerHTML = '⋮'; t.classList.remove('ctl-act');
  t.addEventListener('click', () => { const its = (typeof cfg.items === 'function' ? cfg.items() : cfg.items).map((it, i) => ({ v: String(i), l: it.label, disabled: it.disabled, danger: it.danger }));
    const src = typeof cfg.items === 'function' ? cfg.items() : cfg.items;
    openSheet({ title: cfg.label || T('more'), options: its, menu: true, trg: t, onPick: (v) => { const it = src[Number(v)]; if (it && it.onClick) it.onClick(); } }); });
  STATS.menu++; return t;
}
function seg(cfg) {
  const d = el('div', 'ctl-seg'); d.setAttribute('role', 'radiogroup'); let value = cfg.value == null ? '' : String(cfg.value);
  const os = (cfg.options || []).map(norm).slice(0, 3);
  const paint = () => d.querySelectorAll('button').forEach((b) => { const o = b.dataset.v === value; b.classList.toggle('on', o); b.setAttribute('aria-checked', o ? 'true' : 'false'); });
  os.forEach((o) => { const b = el('button', 'tog', esc(o.l)); b.type = 'button'; b.dataset.v = o.v; b.setAttribute('role', 'radio'); b.addEventListener('click', () => { value = o.v; paint(); if (cfg.onChange) cfg.onChange(value); }); d.appendChild(b); });
  paint(); STATS.seg++; return d;
}

// ---------------------------------------------------------------- enhancer: native <select>
function enhanceSelect(sel) {
  if (sel._ctl || sel.multiple || sel.size > 1 || sel.dataset.ctl === 'off' || sel.closest('[data-ctl="off"],.ctl-bg')) return false;
  const t = mkTrigger('select', ''); const st = (sel.style && sel.style.cssText) || ''; const m = /(?:^|;)\s*(width|max-width|min-width|flex)\s*:[^;]+/g; let mm, keep = '';
  while ((mm = m.exec(st))) keep += mm[0].replace(/^;/, '') + ';'; if (keep) t.style.cssText = keep;
  const paint = () => { const o = sel.options[sel.selectedIndex]; const txt = o && o.value !== '' ? o.textContent.trim() : ''; t.setAttribute('aria-label', titleFor(sel) || ''); setTrg(t, txt || (o && o.textContent.trim()) || T('none'), !!(o && o.value !== ''), sel.disabled); if (!txt) t.classList.add('ctl-empty'); else t.classList.remove('ctl-empty'); };
  const own = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value');
  Object.defineProperty(sel, 'value', { configurable: true, get() { return own.get.call(sel); }, set(v) { own.set.call(sel, v); paint(); } });
  const si = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'selectedIndex');
  Object.defineProperty(sel, 'selectedIndex', { configurable: true, get() { return si.get.call(sel); }, set(v) { si.set.call(sel, v); paint(); } });
  const mo = new MutationObserver(() => paint()); mo.observe(sel, { childList: true, subtree: true, attributes: true, attributeFilter: ['disabled', 'selected', 'label'] });
  sel.addEventListener('change', paint);
  t.addEventListener('click', () => {
    const os = [...sel.options].map((o) => ({ v: o.value, l: o.textContent.trim() || (o.value === '' ? T('noval') : o.value), disabled: o.disabled, empty: o.value === '' }));
    openSheet({ title: titleFor(sel), options: os, value: sel.value, search: os.length > 8, trg: t, onPick: (v) => {
      own.set.call(sel, v); paint(); sel.dispatchEvent(new Event('input', { bubbles: true })); sel.dispatchEvent(new Event('change', { bubbles: true })); } });
  });
  sel.classList.add('ctl-hid'); sel.setAttribute('aria-hidden', 'true'); sel.tabIndex = -1; sel.after(t); sel._ctl = { trg: t, mo }; paint(); STATS.select++; return true;
}

// ---------------------------------------------------------------- enhancer: button groups (CH, filter chips, tabs-like single choice) and multi
const keyOf = (b) => [b.dataset.act, b.dataset.k || b.dataset.g || b.dataset.h || '', b.dataset.v !== undefined ? b.dataset.v : (b.dataset.su || '')].join('|');
const isOn = (b) => b.classList.contains('on') || b.getAttribute('aria-pressed') === 'true';
const btnLabel = (b) => b.textContent.replace(/\s+/g, ' ').replace(/^[✓＋+]\s*/, '').trim();
const liveBtn = (k) => [...document.querySelectorAll('button.tog[data-act]')].find((b) => keyOf(b) === k && !b.closest('.ctl-bg'));
const SKIP_ACT = /(^|_)(tab|tabs)$|^pos_|^pay_|preset|lang|_add$|^sheettog$|^nav_|^go$|^e_/;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function rebuild(container, sig, build) {
  const s = container._ctl; if (s && s.sig === sig && s.trg.isConnected) return false;
  if (s) { s.trg.remove(); }
  const trg = build(); container._ctl = { sig, trg, mo: container._ctlmo };
  /* add only what is missing: classList.add of a class already there still queues an attribute mutation, which the group observer below read as an outside change and rebuilt the trigger forever */ if (!container.classList.contains('ctl-grp')) container.classList.add('ctl-grp'); const gn = [...container.children].filter((c) => c.matches && c.matches('button.tog')); gn.forEach((c) => { if (!c.classList.contains('ctl-hid')) c.classList.add('ctl-hid'); }); spread(gn); container.prepend(trg); return true;
}
function groupCfg(container, btns, multiMode) {
  const k0 = btns[0], isPick = k0.dataset.act === 'pick', ro = btns.every((b) => b.disabled);
  const reqFld = isPick && (container.dataset.req === '1' || !!(container.closest('.fld') && container.closest('.fld').querySelector('label .req')));
  const cur = container.dataset.cur;
  return { isPick, ro, reqFld, cur, title: titleFor(container) };
}
function spread(nodes) { nodes.forEach((n, i) => { n.style.setProperty('--cx', i % 20); n.style.setProperty('--cy', Math.floor(i / 20)); }); }
function enhanceGroup(container, btns, multiMode) {
  btns = btns.concat([...container.children].filter((c) => c.matches && c.matches('button.tog[aria-disabled="true"]') && !btns.includes(c)));
  const g = groupCfg(container, btns, multiMode); const lbl = btns.map(btnLabel);
  const sig = (multiMode ? 'M' : 'S') + btns.map((b) => keyOf(b) + (isOn(b) ? '*' : '') + (b.disabled ? 'd' : '')).join(',') + '#' + lbl.join('|') + (g.cur || '');
  const changed = rebuild(container, sig, () => {
    const t = mkTrigger(multiMode ? 'multi' : 'choice', g.title);
    const items = btns.map((b, i) => ({ v: keyOf(b), l: lbl[i] || b.dataset.v, on: isOn(b), disabled: b.disabled }));
    if (multiMode) {
      const sel = items.filter((i) => i.on); setTrg(t, !sel.length ? T('none') : sel.length <= 2 ? sel.map((i) => i.l).join(', ') : sel.length + ' ' + T('nsel'), sel.length, g.ro);
      t.addEventListener('click', () => { const os = items.map((i) => ({ v: i.v, l: i.l })); const was = new Set(items.filter((i) => i.on).map((i) => i.v));
        openSheet({ title: g.title, options: os, multi: true, values: was, search: os.length > 8, trg: t, onApply: async (set) => {
          for (const i of items) { if (set.has(i.v) !== was.has(i.v)) { const b = liveBtn(i.v); if (b) { b.click(); await wait(40); } } } } }); });
    } else {
      const cur = items.find((i) => i.on); let txt = cur ? cur.l : (g.cur ? String(g.cur).replace(/^other:/, '') : '');
      const first = items[0];
      setTrg(t, (container.dataset.title && txt ? container.dataset.title + ': ' : '') + (txt || T('none')), !!txt && !(cur && !g.isPick && cur === first), g.ro); if (!txt) t.classList.add('ctl-empty');
      const clearable = !g.reqFld && (g.isPick || btns[0].dataset.act === 'fl_one');
      t.addEventListener('click', () => { const os = items.map((i) => ({ v: i.v, l: i.l, disabled: i.disabled }));
        openSheet({ title: g.title, options: os, value: cur ? cur.v : '', search: os.length > 8, trg: t, onPick: (v) => {
          const sameAsCur = cur && cur.v === v; if (sameAsCur && !clearable) return; const b = liveBtn(v); if (b) b.click(); } });
        if (clearable && cur) { const sh = document.querySelector('.ctl-sheet'); if (sh) { const c = el('button', 'ctl-fb', esc(T('clear'))); c.type = 'button'; c.addEventListener('click', () => { closeSheet(); const b = liveBtn(cur.v); if (b) b.click(); }); const f = el('div', 'ctl-foot'); f.appendChild(c); sh.appendChild(f); } } });
    }
    return t;
  });
  if (changed) { STATS[multiMode ? 'multi' : 'choice']++; }
  if (!container._ctlmo) { const mo = new MutationObserver(() => { container._ctl && container._ctl.sig && (container._ctl.sig = null, schedule()); }); mo.observe(container, { attributes: true, attributeFilter: ['class', 'aria-pressed', 'disabled'], subtree: true }); container._ctlmo = mo; }
}
function enhanceSeg(container) { if (!container.classList.contains('ctl-segc')) container.classList.add('ctl-segc'); }

// read-only CH group (all disabled) -> plain value
function readonlyValue(container, btns) {
  const cur = btns.find(isOn); const txt = cur ? btnLabel(cur) : (container.dataset.cur ? String(container.dataset.cur).replace(/^other:/, '') : '—');
  const sig = 'R' + txt + btns.length; const s = container._ctl;
  if (s && s.sig === sig && s.trg.isConnected) return;
  if (s) s.trg.remove(); const v = el('span', 'ctl-roval', esc(txt)); container._ctl = { sig, trg: v }; /* add only what is missing: classList.add of a class already there still queues an attribute mutation, which the group observer below read as an outside change and rebuilt the trigger forever */ if (!container.classList.contains('ctl-grp')) container.classList.add('ctl-grp'); const gn = [...container.children].filter((c) => c.matches && c.matches('button.tog')); gn.forEach((c) => { if (!c.classList.contains('ctl-hid')) c.classList.add('ctl-hid'); }); spread(gn); container.prepend(v);
}

function enhanceChecks(root) {
  let n = 0; const seen = new Set();
  root.querySelectorAll('input[type=checkbox]').forEach((cb) => {
    const lab0 = cb.closest('label'); const p = lab0 && lab0.parentElement; if (!p || seen.has(p) || p.closest('.ctl-bg,[data-ctl="off"],table,.tbl') || p.dataset.ctl === 'off') return; seen.add(p);
    const kids = [...p.children].filter((k) => !k.classList.contains('ctl-trg')); if (kids.length < 4 || !kids.every((k) => k.tagName === 'LABEL' && k.querySelectorAll('input[type=checkbox]').length === 1)) return;
    const items = kids.map((k) => ({ cb: k.querySelector('input'), l: k.textContent.replace(/\s+/g, ' ').trim() }));
    const sig = 'C' + items.map((i) => i.l + (i.cb.checked ? '*' : '')).join('|'); const s = p._ctl; if (s && s.sig === sig && s.trg.isConnected) return;
    if (s) s.trg.remove(); const t = mkTrigger('multi', titleFor(p)); const sel = items.filter((i) => i.cb.checked);
    setTrg(t, !sel.length ? T('none') : sel.length <= 2 ? sel.map((i) => i.l).join(', ') : sel.length + ' ' + T('nsel'), sel.length, items.every((i) => i.cb.disabled));
    t.addEventListener('click', () => { const os = items.map((i, ix) => ({ v: String(ix), l: i.l })); openSheet({ title: t.getAttribute('aria-label'), options: os, multi: true, values: new Set(items.map((i, ix) => (i.cb.checked ? String(ix) : null)).filter((x) => x !== null)), trg: t, onApply: (set) => {
      items.forEach((i, ix) => { const w = set.has(String(ix)); if (i.cb.checked !== w) { i.cb.checked = w; i.cb.dispatchEvent(new Event('input', { bubbles: true })); i.cb.dispatchEvent(new Event('change', { bubbles: true })); } }); p._ctl.sig = null; schedule(); } }); });
    kids.forEach((k) => k.classList.add('ctl-hid')); spread(kids); p._ctl = { sig, trg: t }; p.classList.add('ctl-grp'); p.prepend(t); n++; STATS.cb++;
  });
  return n;
}

// rows with 3+ secondary inline buttons -> ⋮ (the .primary / first button stays)
function enhanceRows(root) {
  const seen = new Set();
  root.querySelectorAll('[data-ctl="menu"] > button[data-act]:not(.tog):not(.primary)').forEach((b) => {
    const p = b.parentElement; if (!p || seen.has(p)) return; seen.add(p);
    const all = [...p.children].filter((c) => c.tagName === 'BUTTON' && c.dataset.act && !c.classList.contains('tog') && !c.classList.contains('ctl-trg') && !c.classList.contains('mini') && c.id !== 'e_notsent');
    if (all.length < 3) return;
    const keep = all.find((c) => c.classList.contains('primary')) || all[0]; const rest = all.filter((c) => c !== keep);
    const sig = 'K' + rest.map((c) => c.dataset.act + c.textContent).join('|'); if (p._ctlm && p._ctlm.sig === sig && p._ctlm.trg.isConnected) return;
    if (p._ctlm) p._ctlm.trg.remove();
    const items = rest.map((c) => ({ label: btnLabel(c) || c.getAttribute('aria-label') || c.dataset.act, disabled: c.disabled, danger: /del|remove|void|cancel|reject/.test(c.dataset.act), ref: c }));
    const t = menu({ label: lab(X.more), items: items.map((i) => ({ label: i.label, disabled: i.disabled, danger: i.danger, onClick: () => { if (i.ref.isConnected) i.ref.click(); } })) });
    rest.forEach((c) => c.classList.add('ctl-hid')); spread(rest); keep.after(t); p._ctlm = { sig, trg: t };
  });
}

function enhance(root) {
  sync(); root = root || document.body; if (!on() || !root) return null;
  const before = { ...STATS };
  root.querySelectorAll('select').forEach((s) => enhanceSelect(s));
  const byParent = new Map();
  root.querySelectorAll('button.tog[data-act]').forEach((b) => { const p = b.parentElement; if (!p || p.closest('.ctl-bg,[data-ctl="off"],header,.actionbar,nav,.lang,.dr-foot') || p.dataset.ctl === 'off') return;
    if (!byParent.has(p)) byParent.set(p, new Map()); const m = byParent.get(p); if (!m.has(b.dataset.act)) m.set(b.dataset.act, []); m.get(b.dataset.act).push(b); });
  byParent.forEach((m, p) => m.forEach((btns, act) => {
    if (act === 'pick') { const all = [...p.children].filter((c) => c.dataset && c.dataset.act === 'pick'); if (all.every((b) => b.disabled)) return readonlyValue(p, all); if (all.length > 3) return enhanceGroup(p, all, false); return enhanceSeg(p); }
    const mk = p.dataset.ctl, fl = p.classList.contains('fl-chipset');
    if (btns.length >= 2 && (act === 'fl_t' || btns.every((b) => b.dataset.su !== undefined) || mk === 'multi')) return enhanceGroup(p, btns, true);
    if (!(fl || mk === 'select') || (!mk && SKIP_ACT.test(act))) return;          // generic button rows are actions/navigation: never converted
    if (btns.length < 4) { if (btns.every((b) => b.dataset.v !== undefined)) enhanceSeg(p); return; }
    if (!btns.every((b) => b.dataset.v !== undefined) || btns.filter(isOn).length > 1) return;
    enhanceGroup(p, btns, false);
  }));
  enhanceChecks(root); enhanceRows(root);
  return Object.fromEntries(Object.keys(STATS).map((k) => [k, STATS[k] - before[k]]));
}

// ---------------------------------------------------------------- auto-run after every render
let timer = null, last = 0, busy = false;
function schedule() {
  if (timer) return; const wait0 = Math.max(0, 30 - (Date.now() - last));
  timer = setTimeout(() => { timer = null; run(); }, wait0);
}
function run() { if (busy) return; busy = true; last = Date.now(); try { enhance(document.body); } catch (e) { /* never break the app */ if (window.console) console.warn('ctl', e && e.message); } busy = false; }
function start() {
  sync(); const mo = new MutationObserver((recs) => { if (!on()) { sync(); return; } if (recs.every((r) => r.target.closest && r.target.closest('.ctl-bg,#pos_items'))) return; schedule(); });   /* bos114: POS cards (drawn in chunks) hold nothing to enhance */
  mo.observe(document.body, { childList: true, subtree: true }); run();
}

B.ctl = { select, multi, tick, menu, seg, enhance, on, setMode, close: closeSheet, stats: STATS, version: 1 };
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
