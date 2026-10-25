/* bos113: accessibility, one central progressive-enhancement helper (no text, no data, no layout change for pointer users).
   Everything here only ADDS attributes / key handling to DOM that other modules render; it never edits their wording.
   1. openSheet sheets (#sheet > .sheet): role=dialog, aria-modal, aria-labelledby, focus in, Tab trap, Esc closes (clicks the existing closesheet action), focus back to the opener.
   2. controls.js pickers (.ctl-bg): Tab trap that also works from the tabindex=-1 options; roving tabindex.
   3. Menu drawer: focus in on open, trap incl. select, focus back to the Menu button on close, aria-expanded on the Menu button.
   4. div[data-act] rows that are not interactive: role=button tabindex=0, Enter / Space press the existing click handler.
   5. <label> without for: tied to the next control (for/id); unnamed fields get aria-label from placeholder or the text just before them.
   6. aria-pressed on button.tog and the cdr_set chips, kept in step with the existing on/warn class.
   7. Skip link + role=main on #app.
   8. NEW-screen only CSS (44px targets, 320px reflow) behind #app[data-a11y-new]. */
(function () {
  'use strict';
  if (window.BOS_A11Y) return;
  var doc = document;
  var B = window.BOS = window.BOS || {};
  var T = function (bn, en, mix) { try { return B.lab(B.L(bn, en, mix)); } catch (e) { return en; } };

  // ---------- helpers ----------
  var kbd = false;                                            // last input was the keyboard (so focus moves may show a ring); pointer users keep their behaviour
  doc.addEventListener('keydown', function (e) { if (e.key === 'Tab' || e.key === 'Enter' || e.key === ' ' || e.key.indexOf('Arrow') === 0) kbd = true; }, true);
  doc.addEventListener('pointerdown', function () { kbd = false; }, true);
  var uid = 0;
  var FOCUSABLE = 'a[href],button,input:not([type=hidden]),select,textarea,summary,[tabindex],[contenteditable=""],[contenteditable="true"]';
  function shown(e) {
    if (!e || e.disabled || e.hidden || e.closest('[hidden],[aria-hidden="true"],[inert]')) return false;
    if (e.matches('select.ctl-hid')) return false;
    var cs = getComputedStyle(e); if (cs.visibility === 'hidden' || cs.display === 'none') return false;
    return e.getClientRects().length > 0;
  }
  function tabStops(root) {
    var list = Array.prototype.slice.call(root.querySelectorAll(FOCUSABLE)).filter(function (e) { return e.tabIndex >= 0 && shown(e); });
    // radio group = one stop
    return list.filter(function (e, i) { return !(e.type === 'radio' && e.name && list.some(function (o, j) { return j < i && o.type === 'radio' && o.name === e.name && o.form === e.form; })); });
  }
  function after(a, b) { return !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING); }
  // Tab handling that also works when the focused element is not itself a tab stop (tabindex=-1 options, a container, <body>)
  function trap(e, root, stops, always) {
    if (!stops.length) { e.preventDefault(); return true; }
    var act = doc.activeElement, i = stops.indexOf(act), n, inside = root.contains(act);
    if (i >= 0) n = e.shiftKey ? i - 1 : i + 1;
    else if (inside && act !== root) { // focus on a non-stop inside: next / previous stop in document order
      if (e.shiftKey) { n = -1; stops.forEach(function (s, k) { if (after(s, act)) n = k; }); }
      else { n = stops.length; for (var k = stops.length - 1; k >= 0; k--) if (after(act, stops[k])) n = k; }
    } else n = e.shiftKey ? stops.length : -1;
    var wrap = n < 0 || n >= stops.length;
    if (!wrap && !always && i >= 0) return false;                                  // normal move: let the browser do it
    e.preventDefault(); n = (n + stops.length) % stops.length; stops[n].focus(); return true;
  }
  var lastOut = null;                                         // last focused element outside any dialog
  doc.addEventListener('focusin', function (e) { var t = e.target; if (t && t.nodeType === 1 && !t.closest('#sheet,.ctl-bg,#navDrawer')) lastOut = t; }, true);
  function sig(e) { return { id: e.id, act: e.getAttribute('data-act'), v: e.getAttribute('data-v'), tag: e.tagName }; }
  function refind(s, el) {
    if (el && el.isConnected) return el;
    if (!s) return null;
    if (s.id) { var a = doc.getElementById(s.id); if (a) return a; }
    if (s.act) { var q = '[data-act="' + s.act + '"]' + (s.v != null ? '[data-v="' + String(s.v).replace(/"/g, '\\"') + '"]' : ''); var b = doc.querySelector(q); if (b) return b; }
    return null;
  }
  function lostFocus() { var a = doc.activeElement; return !a || a === doc.body || a === doc.documentElement; }

  // ---------- 1. openSheet sheets ----------
  var sheet = null, opener = null, openerSig = null, retOpener = null, retSig = null;
  function headingOf(s) { return s.querySelector('h1,h2,h3,h4') || s.querySelector(':scope > b, :scope > .row > b, .card > b, b'); }
  function setupSheet(d) {
    var s = d.firstElementChild; if (!s || !s.classList.contains('sheet')) return;
    if (!s.hasAttribute('role')) s.setAttribute('role', 'dialog');
    s.setAttribute('aria-modal', 'true');
    if (!s.hasAttribute('aria-labelledby') || !doc.getElementById(s.getAttribute('aria-labelledby'))) {
      var h = headingOf(s);
      if (h && (h.textContent || '').trim()) { if (!h.id) h.id = 'a11y_sh_' + (++uid); s.setAttribute('aria-labelledby', h.id); }
      else if (!s.hasAttribute('aria-label')) s.setAttribute('aria-label', T('ডায়ালগ', 'Dialog', 'Dialog'));
    }
    if (d._a11y) return; d._a11y = 1;
    opener = retOpener || (!lostFocus() && !d.contains(doc.activeElement) ? doc.activeElement : lastOut); openerSig = retSig || (opener ? sig(opener) : null);
    retOpener = null; retSig = null;
    if (d.contains(doc.activeElement)) return;               // the sheet focused one of its own fields already
    s.tabIndex = -1;
    var first = null;
    if (kbd) first = s.querySelector('input:not([type=hidden]):not([disabled]),select:not([disabled]),textarea:not([disabled])') || s.querySelector('button:not(.sheet-x):not([disabled])') || s.querySelector('.sheet-x');
    try { (first || s).focus({ preventScroll: true }); } catch (e) { /* ignore */ }
  }
  function sheetGone() {
    retOpener = opener; retSig = openerSig; opener = null; openerSig = null;
    setTimeout(function () {
      var r = retOpener, sg = retSig; retOpener = null; retSig = null;
      if (!r && !sg) return;
      if (doc.getElementById('sheet') || doc.querySelector('.ctl-bg')) return;
      if (!lostFocus()) return;
      var t = refind(sg, r); if (t) { try { t.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }
    }, 0);
  }
  doc.addEventListener('keydown', function (e) {
    var d = doc.getElementById('sheet'); if (!d || doc.querySelector('.ctl-bg')) return;
    if (e.key === 'Escape') {
      if (e.defaultPrevented) return;
      var x = d.querySelector('[data-act="closesheet"].sheet-x') || d.querySelector('[data-act="closesheet"]');
      if (x) { e.preventDefault(); x.click(); }
    } else if (e.key === 'Tab') {
      var s = d.querySelector('.sheet') || d; trap(e, s, tabStops(s), false);
    }
  });

  // ---------- 2. picker dialogs (controls.js) ----------
  function ctlStops(sh) {
    var opts = Array.prototype.slice.call(sh.querySelectorAll('.ctl-opt:not([disabled])')), cur = opts.filter(function (o) { return o.tabIndex === 0; })[0] || null;
    var virtual = cur || sh.querySelector('.ctl-opt.on:not([disabled])') || opts[0] || null;
    return Array.prototype.slice.call(sh.querySelectorAll('button:not([disabled]),input:not([type=hidden])')).filter(function (e) {
      if (!shown(e) && e !== doc.activeElement) return false;
      return e.classList.contains('ctl-opt') ? e === virtual : e.tabIndex >= 0;
    });
  }
  doc.addEventListener('keydown', function (e) {
    if (e.key !== 'Tab') return;
    var bg = doc.querySelector('.ctl-bg'); if (!bg) return;
    var sh = bg.querySelector('.ctl-sheet'); if (!sh) return;
    if (trap(e, sh, ctlStops(sh), true)) e.stopImmediatePropagation();
  }, true);
  doc.addEventListener('focusin', function (e) {                         // roving tabindex: the focused option is the one tab stop of the list
    var t = e.target; if (!t || !t.classList || !t.classList.contains('ctl-opt')) return;
    var l = t.closest('.ctl-list'); if (!l) return;
    Array.prototype.forEach.call(l.querySelectorAll('.ctl-opt'), function (o) { o.tabIndex = o === t ? 0 : -1; });
  });

  // ---------- 3. drawer ----------
  var drawer = null, dOpener = null, dSig = null, dWasOn = false;
  function menuBtns() { return doc.querySelectorAll('[data-act="nav_open"]'); }
  function syncExpanded() { var on = !!(drawer && drawer.classList.contains('on')); Array.prototype.forEach.call(menuBtns(), function (b) { b.setAttribute('aria-expanded', on ? 'true' : 'false'); }); }
  function drawerState() {
    drawer = drawer && drawer.isConnected ? drawer : doc.getElementById('navDrawer'); if (!drawer) return;
    var on = drawer.classList.contains('on');
    if (on === dWasOn) { syncExpanded(); return; }
    dWasOn = on; syncExpanded();
    if (on) {
      dOpener = lostFocus() ? lastOut : (drawer.contains(doc.activeElement) ? lastOut : doc.activeElement); dSig = dOpener ? sig(dOpener) : null;
      setTimeout(function () {
        if (!drawer.classList.contains('on') || drawer.contains(doc.activeElement) && doc.activeElement.tagName !== 'BODY') return;
        var f = tabStops(drawer)[0]; if (f) { try { f.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }
      }, 70);
    } else {
      var o = dOpener, s = dSig; dOpener = null; dSig = null;
      setTimeout(function () {
        if (drawer.classList.contains('on')) return;
        if (!lostFocus() && !drawer.contains(doc.activeElement)) return;
        var t = refind(s, o) || doc.querySelector('[data-act="nav_open"]'); if (t) { try { t.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }
      }, 120);
    }
  }
  doc.addEventListener('keydown', function (e) {
    if (e.key !== 'Tab' || !drawer || !drawer.classList.contains('on')) return;
    var st = Array.prototype.slice.call(drawer.querySelectorAll('button:not([disabled]),input:not([type=hidden]),select:not([disabled]),a[href]')).filter(function (x) { return x.tabIndex >= 0 && shown(x); });
    if (trap(e, drawer, st, true)) e.stopImmediatePropagation();
  });

  // ---------- 4. mouse-only rows ----------
  var NATIVE = 'a,button,input,select,textarea,label,summary,option,tr,td,th,tbody,thead,table,li,form,body,html';
  var INNER = 'a[href],button,input:not([type=hidden]),select,textarea,summary,[role=button],[role=link],[tabindex]';
  function row(e) {
    if (e._a11yRow || e.matches(NATIVE) || e.matches('.scrim,.sheet-bg,.ctl-bg,#sheet,#navScrim,[aria-hidden="true"],[contenteditable]')) return;
    if (e.hasAttribute('role') && e.getAttribute('role') !== 'button') return;
    if (e.querySelector(INNER)) return;                                                   // never nest interactive controls
    e._a11yRow = 1;
    if (!e.hasAttribute('role')) e.setAttribute('role', 'button');
    if (!e.hasAttribute('tabindex')) { e.setAttribute('tabindex', '0'); e.setAttribute('data-a11y-row', ''); }
  }
  doc.addEventListener('keydown', function (e) {
    var t = e.target;
    if (!t || t.nodeType !== 1 || !t.hasAttribute || !t.hasAttribute('data-a11y-row') || e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey) return;
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); t.click(); }
  });

  // ---------- 5. labels ----------
  var CTRL = 'input:not([type=hidden]),select,textarea';
  function ctlId(c) { if (!c.id) c.id = 'a11y_f_' + (++uid); return c.id; }
  function label(l) {
    if (l.hasAttribute('for') || l.querySelector(CTRL) || !(l.textContent || '').trim()) return;
    var n = l.nextElementSibling, c = null;
    if (n && n.matches(CTRL)) c = n;
    else if (n && !n.matches('label') && n.querySelector(CTRL) && !n.querySelector('label')) c = n.querySelector(CTRL);
    if (!c || (c.id && doc.querySelector('label[for="' + c.id.replace(/"/g, '\\"') + '"]'))) return;
    l.setAttribute('for', ctlId(c));
  }
  function named(c) {
    if (c.getAttribute('aria-label') || c.getAttribute('aria-labelledby') || c.title) return true;
    if (c.closest('label')) return true;
    if (c.id && doc.querySelector('label[for="' + c.id.replace(/"/g, '\\"') + '"]')) return true;
    return !!(c.labels && c.labels.length);
  }
  function nameField(c) {
    if (c._a11yN || c.matches('select.ctl-hid') || c.closest('[aria-hidden="true"]') || named(c)) return;
    c._a11yN = 1;
    var t = c.getAttribute('placeholder');
    if (!t) { // the text just before the field (or before its wrapper)
      var p = c;
      for (var k = 0; k < 3 && p && !t; k++, p = p.parentElement) {
        var s = p.previousElementSibling;
        if (s && !s.querySelector(CTRL) && !s.matches(CTRL + ',button,table')) { var hb = s.querySelector(':scope > b,:scope > strong,:scope > h1,:scope > h2,:scope > h3,:scope > h4'), tx = ((hb || s).textContent || '').trim(); if (tx && tx.length <= 120) t = tx; }
      }
    }
    if (t) c.setAttribute('aria-label', t);
  }

  // ---------- 6. toggle state ----------
  var TOG = 'button.tog[data-act],button.chip[data-act="cdr_set"]';
  function pressed(b) { return b.classList.contains('on') || b.classList.contains('warn') || b.getAttribute('aria-current') === 'true'; }
  function tog(b) { if (b.hasAttribute('role') && b.getAttribute('role') !== 'button') return; var v = pressed(b) ? 'true' : 'false'; if (b.getAttribute('aria-pressed') !== v) b.setAttribute('aria-pressed', v); }   // only on a real change: a same-value write is still a mutation record and re-fired the observers (controls.js re-enhance loop)

  // ---------- 7. skip link + main ----------
  var skip = null;
  function content() {
    var a = doc.getElementById('app'); if (!a) return null;
    for (var c = a.firstElementChild; c; c = c.nextElementSibling) if (!c.matches('header.top,.crumb,nav,.bc') && !c.id.match(/^(nav|toast)/)) return c;
    return a;
  }
  function mountSkip() {
    var a = doc.getElementById('app'); if (a && !a.hasAttribute('role')) a.setAttribute('role', 'main');
    if (skip && skip.isConnected) { var st = T('মূল অংশে যান', 'Skip to content', 'Content-এ যান'); if (skip.textContent !== st) skip.textContent = st; return; }
    skip = doc.createElement('a'); skip.className = 'a11y-skip'; skip.href = '#app'; skip.setAttribute('data-a11y-skip', '');
    skip.textContent = T('মূল অংশে যান', 'Skip to content', 'Content-এ যান');
    skip.addEventListener('click', function (e) {
      e.preventDefault(); e.stopPropagation();                                            // the hash is the router: never touch it
      var c = content(); if (!c) return;
      var f = c.matches(FOCUSABLE) ? c : (tabStops(c)[0] || c);
      if (f === c && !c.hasAttribute('tabindex')) c.setAttribute('tabindex', '-1');
      try { f.focus(); c.scrollIntoView({ block: 'start' }); } catch (x) { /* ignore */ }
    });
    doc.body.insertBefore(skip, doc.body.firstChild);
  }

  // ---------- 8. which screens are NEW (CSS scope) ----------
  var OLD = { home: 1, items: 1, staff: 1, matrix: 1, rules: 1, settings: 1, logs: 1, backup: 1, itemreq: 1, pos: 1, '': 1 };
  var lastHash = null;
  function scope() {
    var h = location.hash; if (!B.IA || h === lastHash) return; lastHash = h;
    var a = doc.getElementById('app'); if (!a) return;
    var base = h.replace(/^#\/?/, '').split('/')[0].split('?')[0];
    var isNew = !OLD[base] && !!(B.IA || []).some(function (r) { return r.route.split('/')[0] === base; });
    if (isNew) a.setAttribute('data-a11y-new', ''); else a.removeAttribute('data-a11y-new');
  }

  // the shell header lives inside #app (role=main): a banner may not sit inside main, so it is plain content there
  function hdr(h) { if (!h.hasAttribute('role')) h.setAttribute('role', 'none'); }

  // ---------- scan ----------
  function scan(root) {
    if (root.nodeType !== 1) return;
    if (root.matches('#app > header.top')) hdr(root);
    var any = root.firstElementChild && root.querySelector('#app > header.top,[data-act],label,' + CTRL + ',' + TOG);   // bos114: one query decides whether the ten below can find anything (POS cards, table rows ...)
    if (!any) { if (root.matches('[data-act]')) row(root); if (root.matches('label')) label(root); if (root.matches(CTRL)) nameField(root); if (root.matches(TOG)) tog(root); if (root.matches('[data-act="nav_open"]')) syncExpanded(); return; }
    Array.prototype.forEach.call(root.querySelectorAll('#app > header.top'), hdr);
    if (root.matches('[data-act]')) row(root);
    Array.prototype.forEach.call(root.querySelectorAll('[data-act]'), row);
    if (root.matches('label')) label(root);
    Array.prototype.forEach.call(root.querySelectorAll('label'), label);
    if (root.matches(CTRL)) nameField(root);
    Array.prototype.forEach.call(root.querySelectorAll(CTRL), nameField);
    if (root.matches(TOG)) tog(root);
    Array.prototype.forEach.call(root.querySelectorAll(TOG), tog);
    if (root.matches('[data-act="nav_open"]')) syncExpanded();
    Array.prototype.forEach.call(root.querySelectorAll('[data-act="nav_open"]'), function () { syncExpanded(); });
  }
  var pend = [], raf = 0;
  function flush() {
    raf = 0; var l = pend; pend = [];
    l.forEach(function (n) { if (n.isConnected) { try { scan(n); } catch (e) { /* never break the app */ } } });
    try { mountSkip(); scope(); } catch (e) { /* ignore */ }
  }
  function queue(n) { pend.push(n); if (!raf) raf = requestAnimationFrame(flush); }
  var mo = new MutationObserver(function (list) {
    if (list.every(function (m) { return m.type === 'childList' && m.target.closest && m.target.closest('#pos_items'); })) { list.forEach(function (m) { Array.prototype.forEach.call(m.addedNodes, function (n) { if (n.nodeType === 1) queue(n); }); }); return; }   // bos114: POS cards drawn in chunks: label them, skip the sheet/drawer checks
    var d = doc.getElementById('sheet');
    if (d && !d._a11y) { try { setupSheet(d); } catch (e) { /* ignore */ } } else if (d && d.firstElementChild && !d.firstElementChild.hasAttribute('aria-labelledby') && !d.firstElementChild.hasAttribute('aria-label')) { try { setupSheet(d); } catch (e) { /* ignore */ } }
    if (sheet && !sheet.isConnected) { sheet = null; sheetGone(); }
    if (d) sheet = d;
    drawerState();
    list.forEach(function (m) {
      if (m.type === 'attributes') { if (m.target.matches && m.target.matches(TOG)) tog(m.target); return; }
      Array.prototype.forEach.call(m.addedNodes, function (n) { if (n.nodeType === 1 && n.id !== 'toast') queue(n); });
    });
  });
  function start() {
    mountSkip(); scope(); drawerState();
    queue(doc.body);
    mo.observe(doc.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'aria-current'] });
    window.addEventListener('hashchange', function () { scope(); });
  }

  // ---------- CSS ----------
  var css = doc.createElement('style'); css.setAttribute('data-a11y', '');
  css.textContent =
    '.a11y-skip{position:fixed;left:8px;top:-120px;z-index:100000;padding:12px 16px;min-height:44px;background:var(--gold,#e6b800);color:#000;font-weight:700;border-radius:8px;text-decoration:none;box-sizing:border-box}' +
    '.a11y-skip:focus{top:8px}' +
    '#sheet .sheet[tabindex="-1"]:focus,#app[role="main"] [tabindex="-1"]:focus{outline:none}' +
    // NEW screens only: 44px targets, 320px reflow (old screens keep their look)
    'html body #app[data-a11y-new] :is(button.mini,a.mini,.s2-dots,button.q4b-chip){min-height:44px;min-width:44px}' +
    'html body #app[data-a11y-new] a.mini{display:inline-flex;align-items:center;justify-content:center}' +
    'html body #app[data-a11y-new] :is(input,select,textarea){min-width:0;max-width:100%}' +
    'html body [data-doc] .tp-sec h3{color:inherit}html body [data-doc].tp-modern .tp-sec h3{color:#0f6b4f}' +   /* template previews are white paper: dark-theme page ink on white failed contrast; .tp-modern keeps its own green */
    'html body #app[data-a11y-new] > header.top h1{min-width:0;overflow:hidden;text-overflow:ellipsis}';
  (doc.head || doc.documentElement).appendChild(css);

  window.BOS_A11Y = { scan: scan, trap: trap, version: 1 };
  if (doc.body) start(); else doc.addEventListener('DOMContentLoaded', start);
})();
