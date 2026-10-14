/* bos109 Liquid Glass: picks the effects level once per page load. data-fx="lite" = no blur, solid fills (see theme_glass.css section 8).
   Lite when: prefers-reduced-motion / prefers-reduced-transparency, backdrop-filter unsupported, or a low-power phone (deviceMemory <= 2 or hardwareConcurrency <= 2). */
(function () {
  var h = document.documentElement;
  function mq(q) { try { return !!(window.matchMedia && matchMedia(q).matches); } catch (e) { return false; } }
  function sup() { try { return !!(window.CSS && CSS.supports && (CSS.supports('backdrop-filter', 'blur(1px)') || CSS.supports('-webkit-backdrop-filter', 'blur(1px)'))); } catch (e) { return false; } }
  var n = navigator, lowMem = typeof n.deviceMemory === 'number' && n.deviceMemory <= 2, lowCpu = typeof n.hardwareConcurrency === 'number' && n.hardwareConcurrency > 0 && n.hardwareConcurrency <= 2;
  var lite = mq('(prefers-reduced-motion: reduce)') || mq('(prefers-reduced-transparency: reduce)') || !sup() || lowMem || lowCpu;
  h.setAttribute('data-fx', lite ? 'lite' : 'full');
  window.BOS_GLASS = { lite: lite, reasons: { motion: mq('(prefers-reduced-motion: reduce)'), transparency: mq('(prefers-reduced-transparency: reduce)'), noBackdrop: !sup(), lowMem: lowMem, lowCpu: lowCpu } };
})();
