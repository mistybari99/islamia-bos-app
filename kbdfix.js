/* bos102: on-screen keyboard must never hide the action buttons.
   - tracks the VISUAL viewport (window.visualViewport) -> CSS vars --vvh / --vvt and html.kbd-open
   - marks each sheet's trailing button group (.row / action bar holding the primary button) as sticky (.kbd-act)
   - keeps the focused field in view; Enter in a numeric sheet field presses the primary button
   No text, no data: layout only. Without visualViewport support nothing breaks (sheet keeps its old sizing). */
(function () {
  'use strict';
  var de = document.documentElement, vv = window.visualViewport || null;
  var baseH = 0, baseW = 0, open = false, raf = 0;
  var EDIT = 'input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]):not([type=range]):not([type=color]):not([type=file]):not([type=hidden]),textarea,select,[contenteditable=""],[contenteditable="true"]';
  function editing() { var a = document.activeElement; return !!(a && a !== document.body && a.matches && a.matches(EDIT)); }
  function vh() { return vv ? vv.height : window.innerHeight; }
  function measure() {
    raf = 0;
    var h = vh(), w = vv ? vv.width : window.innerWidth, top = vv ? vv.offsetTop : 0;
    var full = Math.max(window.innerHeight, h + top);
    if (Math.abs(w - baseW) > 40 || !baseH) { baseW = w; baseH = full; }            // new width = rotation / first run
    if (!editing() || full > baseH) baseH = full;
    var was = open;
    open = editing() && h < baseH - 110;                                             // a keyboard is >110px tall everywhere
    de.style.setProperty('--vvh', Math.round(h) + 'px');
    de.style.setProperty('--vvt', Math.round(top) + 'px');
    de.classList.toggle('kbd-open', open);
    if (open) keepInView(); else if (was) de.style.removeProperty('--kbd-gap');
  }
  function sched() { if (!raf) raf = requestAnimationFrame(measure); }
  function keepInView() {
    var a = document.activeElement; if (!a || !a.scrollIntoView || !editing()) return;
    var go = function () { try { if (document.activeElement === a) a.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {} };
    setTimeout(go, 30); setTimeout(go, 280);
  }
  // the group of buttons that finishes a sheet: the nearest .row/.actionbar around the last primary (or last) button
  function trailing(sheet, last) {
    var g = last.parentElement;
    while (g && g !== sheet && !(g.classList.contains('row') || g.classList.contains('actionbar') || g.classList.contains('p2-bar2'))) g = g.parentElement;
    if (!g || g === sheet) g = last;                                                  // a lone full-width button (Close, Done)
    // only a trailing group: no field or button may follow it inside the sheet
    var cur = g;
    while (cur && cur !== sheet) {
      for (var s = cur.nextElementSibling; s; s = s.nextElementSibling) if (s.matches('input,select,textarea,button') || s.querySelector('input,select,textarea,button')) return null;
      cur = cur.parentElement;
    }
    return g;
  }
  function actGroup(sheet) {
    var btns = [].slice.call(sheet.querySelectorAll('button')).filter(function (b) { return !b.classList.contains('sheet-x') && !b.closest('details'); });
    if (!btns.length) return null;
    var pri = btns.filter(function (b) { return b.classList.contains('primary'); });
    return (pri.length && trailing(sheet, pri[pri.length - 1])) || trailing(sheet, btns[btns.length - 1]);
  }
  function mark(bg) {
    var sheet = bg && bg.querySelector('.sheet'); if (!sheet) return;
    try { var g = actGroup(sheet); if (g) g.classList.add('kbd-act'); } catch (e) {}
  }
  function onSheet(bg) {
    mark(bg);
    var s = bg && bg.querySelector('.sheet'); if (!s) return;
    s.addEventListener('focusin', function (e) { if (e.target.matches && e.target.matches(EDIT)) { sched(); keepInView(); } });
  }
  window.BOS_KBD = { sheet: onSheet, mark: mark, measure: measure, isOpen: function () { return open; } };
  if (vv) { vv.addEventListener('resize', sched); vv.addEventListener('scroll', sched); }
  window.addEventListener('resize', sched); window.addEventListener('orientationchange', sched);
  document.addEventListener('focusin', function () { sched(); setTimeout(sched, 120); setTimeout(sched, 400); }, true);
  document.addEventListener('focusout', function () { setTimeout(sched, 60); setTimeout(sched, 350); }, true);
  // late re-renders of a sheet (innerHTML swaps) keep a marked bar
  new MutationObserver(function (ml) {
    for (var i = 0; i < ml.length; i++) for (var j = 0; j < ml[i].addedNodes.length; j++) {
      var n = ml[i].addedNodes[j]; if (n.nodeType === 1 && n.id === 'sheet' && !n.querySelector('.kbd-act')) onSheet(n);
    }
  }).observe(document.body, { childList: true });
  // Enter in a numeric field of a sheet = the sheet's primary action (only when nothing else handled the key)
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || e.defaultPrevented || e.isComposing) return;
    var t = e.target; if (!t || t.tagName !== 'INPUT' || !t.closest) return;
    var sheet = t.closest('.sheet'); if (!sheet) return;
    var im = (t.getAttribute('inputmode') || '').toLowerCase();
    if (!(im === 'decimal' || im === 'numeric' || t.type === 'number')) return;
    var b = sheet.querySelector('.kbd-act button.primary:not([disabled])'); if (!b) return;
    e.preventDefault(); b.click();
  });
  sched();
})();
