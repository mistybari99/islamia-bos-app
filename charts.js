/* Islamia BOS · charts.js — dependency-free inline-SVG chart library (no CDN, no external lib). Exposes B.charts.
   API:  B.charts.TYPES            ordered [{id,label:L(bn,en,mix),icon:'<svg…>'}]  (line, area, bar, column, stacked_bar, pie, donut, treemap, gauge, bullet)
         B.charts.render(host,spec) -> {update(spec),destroy()}
         B.charts.compatible(spec)  -> [type ids that make sense for the data shape]
         B.charts.convert(spec,to)  -> new spec in the target data shape (series | slices | value), lossless back to the original shape
         B.charts.palette(theme)    -> 8 colour-blind-safe colours ('dark'|'light')
   spec = { type, title?, series:[{name,color?,points:[{x,y}]}], slices:[{label,value,color?}], value,min,max,target,ranges:[{to,color}],
            format:(n)=>string, axisFormat?, unit?, height?, theme:'auto'|'dark'|'light', mini?, grouping?:'bd'|'intl'|'none', compact? }
   All text goes through textContent / createElementNS (XSS-safe). Styles: one injected <style id="bch-css">, every class is .bch-… */
(() => {
'use strict';
const B = window.BOS = window.BOS || {};
const NS = 'http://www.w3.org/2000/svg';
const L = (bn, en, mix) => ({ bn, en, mix });
const lab = (x) => (B.lab ? B.lab(x) : (x && (x.en || x.bn)) || '');
const T = {
  nodata: L('কোনো তথ্য নেই', 'No data', 'কোনো Data নেই'),
  other: L('অন্যান্য', 'Other', 'Other'),
  value: L('মান', 'Value', 'Value'),
  rest: L('বাকি', 'Remaining', 'Remaining'),
  total: L('মোট', 'Total', 'Total'),
  target: L('লক্ষ্য', 'Target', 'Target'),
  series: L('সিরিজ', 'series', 'series'),
  points: L('পয়েন্ট', 'points', 'points'),
  untitled: L('চার্ট', 'Chart', 'Chart'),
  last: L('শেষ', 'last', 'last'),
  min: L('সর্বনিম্ন', 'min', 'min'),
  max: L('সর্বোচ্চ', 'max', 'max'),
};

// ---------- types ----------
const ico = (d) => '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>';
const TYPES = [
  { id: 'line', label: L('লাইন চার্ট', 'Line chart', 'Line chart · লাইন'), icon: ico('<path d="M3 17l5-6 4 3 8-9"/><path d="M3 21h18"/>') },
  { id: 'area', label: L('এরিয়া চার্ট', 'Area chart', 'Area chart · এরিয়া'), icon: ico('<path d="M3 17l5-6 4 3 8-9v13H3z" fill="currentColor" fill-opacity=".25"/><path d="M3 17l5-6 4 3 8-9"/>') },
  { id: 'bar', label: L('বার চার্ট', 'Bar chart', 'Bar chart · বার'), icon: ico('<path d="M4 6h10M4 12h16M4 18h7"/>') },
  { id: 'column', label: L('কলাম চার্ট', 'Column chart', 'Column chart · কলাম'), icon: ico('<path d="M6 20V10M12 20V4M18 20v-7"/>') },
  { id: 'stacked_bar', label: L('স্ট্যাকড বার চার্ট', 'Stacked bar chart', 'Stacked bar chart · স্ট্যাকড বার'), icon: ico('<path d="M4 7h9M13 7h6M4 14h5M9 14h10"/>') },
  { id: 'pie', label: L('পাই চার্ট', 'Pie chart', 'Pie chart · পাই'), icon: ico('<path d="M12 3v9h9"/><circle cx="12" cy="12" r="9"/>') },
  { id: 'donut', label: L('ডোনাট চার্ট', 'Donut chart', 'Donut chart · ডোনাট'), icon: ico('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/>') },
  { id: 'treemap', label: L('ট্রি-ম্যাপ চার্ট', 'Treemap', 'Treemap · ট্রি-ম্যাপ'), icon: ico('<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M12 3v18M12 12h9"/>') },
  { id: 'gauge', label: L('গেজ চার্ট', 'Gauge chart', 'Gauge chart · গেজ'), icon: ico('<path d="M4 17a8 8 0 0116 0"/><path d="M12 17l4-5"/>') },
  { id: 'bullet', label: L('বুলেট চার্ট', 'Bullet chart', 'Bullet chart · বুলেট'), icon: ico('<path d="M3 8h18M3 16h18" opacity=".35"/><path d="M3 12h11"/><path d="M17 8v8"/>') },
];
const TYPE_IDS = TYPES.map((t) => t.id);
const SHAPE_OF = { line: 'series', area: 'series', bar: 'series', column: 'series', stacked_bar: 'series', pie: 'slices', donut: 'slices', treemap: 'slices', gauge: 'value', bullet: 'value' };

// ---------- palette (Okabe-Ito order: orange, cyan, green, yellow, blue, red, purple, grey; all >= 3:1 on the tile colour) ----------
const PAL = {
  dark: ['#f5a623', '#35c7ea', '#4fd1a5', '#f0e442', '#7aa7ff', '#ff7a5c', '#d68bd0', '#a8b0bd'],
  light: ['#c76a00', '#0b7fa8', '#0f8a63', '#8a7a00', '#2f5fd0', '#c2381b', '#9b4a97', '#5f6b7a'],
};
const COLOR_RE = /^(#[0-9a-f]{3,8}|(rgb|hsl)a?\([0-9 ,.%\/-]+\)|[a-z]{3,20}|var\(--[a-z0-9-]+\))$/i;
const okColor = (c) => (typeof c === 'string' && COLOR_RE.test(c.trim()) ? c.trim() : null);

// ---------- numbers ----------
const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const toNum = (v) => { if (v === null || v === undefined || v === '' || typeof v === 'boolean') return null; const n = Number(v); return Number.isFinite(n) ? n : null; };
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const f1 = (n) => (isNum(n) ? Math.round(n * 100) / 100 : 0);
function group(n, mode, dec) {
  const neg = n < 0;
  let [i, f] = Math.abs(n).toFixed(dec).split('.');
  if (mode === 'intl') i = i.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  else if (mode !== 'none') { const last = i.slice(-3), rest = i.slice(0, -3); i = (rest ? rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' : '') + last; } // Bangladeshi / lakh grouping
  if (f) f = f.replace(/0+$/, '');
  return (neg ? '-' : '') + i + (f ? '.' + f : '');
}
function defFmt(mode) { return (n) => (isNum(n) ? group(n, mode, Number.isInteger(n) ? 0 : 2) : '–'); }
function compact(n) { // k / L (lakh) / Cr (crore)
  if (!isNum(n)) return '–';
  const a = Math.abs(n), s = n < 0 ? '-' : '';
  const f = (v) => String(Math.round(v * 10) / 10);
  if (a >= 1e7) return s + f(a / 1e7) + 'Cr';
  if (a >= 1e5) return s + f(a / 1e5) + 'L';
  if (a >= 1e3) return s + f(a / 1e3) + 'k';
  return s + f(a);
}
function niceNum(x, round) {
  const e = Math.floor(Math.log10(x)), f = x / Math.pow(10, e);
  const nf = round ? (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) : (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10);
  return nf * Math.pow(10, e);
}
function niceScale(lo, hi, count) {
  if (!isNum(lo) || !isNum(hi)) { lo = 0; hi = 1; }
  if (lo > hi) { const t = lo; lo = hi; hi = t; }
  if (lo === hi) { if (lo === 0) hi = 1; else { const d = Math.abs(lo) * 0.1 || 1; lo -= d; hi += d; } }
  const step = niceNum(niceNum(hi - lo, false) / Math.max(1, count - 1), true);
  const dp = Math.max(0, -Math.floor(Math.log10(step)) + 1);
  const min = Math.floor(lo / step + 1e-9) * step, max = Math.ceil(hi / step - 1e-9) * step;
  const ticks = [];
  for (let v = min, i = 0; v <= max + step * 1e-6 && i < 20; v += step, i++) ticks.push(Number(v.toFixed(dp)));
  return { min: ticks[0], max: ticks[ticks.length - 1], step, ticks };
}
const tw = (s, size) => { let w = 0; for (const ch of String(s)) w += ch.charCodeAt(0) > 255 ? 1.15 : 0.56; return w * (size || 11); };
function trunc(s, px, size) {
  s = String(s === null || s === undefined ? '' : s);
  if (tw(s, size) <= px) return s;
  let out = s;
  while (out.length > 1 && tw(out + '…', size) > px) out = out.slice(0, -1);
  return px < tw('…', size) ? '' : out.trimEnd() + '…';
}

// ---------- spec model ----------
function cleanSeries(spec) {
  const out = [];
  (Array.isArray(spec.series) ? spec.series : []).forEach((s, i) => {
    if (!s) return;
    const pts = (Array.isArray(s.points) ? s.points : []).map((p) => ({ x: p && p.x !== undefined && p.x !== null ? String(p.x) : '', y: p ? toNum(p.y) : null, c: p ? okColor(p.color) : null }));
    out.push({ name: s.name === undefined || s.name === null ? '' : String(s.name), color: okColor(s.color), points: pts, i });
  });
  return out;
}
function cleanSlices(spec) {
  return (Array.isArray(spec.slices) ? spec.slices : []).filter(Boolean).map((s) => ({ label: s.label === undefined || s.label === null ? '' : String(s.label), value: toNum(s.value), color: okColor(s.color) }));
}
function detectShape(spec) {
  if (!spec) return null;
  if (spec._shape) return spec._shape;
  if (cleanSeries(spec).some((s) => s.points.length)) return 'series';
  if (cleanSlices(spec).length) return 'slices';
  if (toNum(spec.value) !== null) return 'value';
  return SHAPE_OF[spec.type] || null;
}
function hasData(spec, shape) {
  if (shape === 'series') return cleanSeries(spec).some((s) => s.points.some((p) => p.y !== null));
  if (shape === 'slices') return cleanSlices(spec).some((s) => s.value !== null);
  if (shape === 'value') return toNum(spec.value) !== null;
  return false;
}
const COMMON = ['title', 'format', 'axisFormat', 'unit', 'height', 'theme', 'mini', 'grouping', 'compact'];
function convert(spec, toType) {
  spec = spec || {};
  if (TYPE_IDS.indexOf(toType) < 0) toType = TYPE_IDS.indexOf(spec.type) >= 0 ? spec.type : 'column';
  const tgt = SHAPE_OF[toType], src = detectShape(spec) || tgt;
  const out = { type: toType, _shape: src };
  COMMON.forEach((k) => { if (spec[k] !== undefined) out[k] = spec[k]; });
  if (src === 'series') out.series = spec.series;
  else if (src === 'slices') out.slices = spec.slices;
  else ['value', 'min', 'max', 'target', 'ranges'].forEach((k) => { if (spec[k] !== undefined) out[k] = spec[k]; });
  if (src === tgt) return out;
  if (src === 'series' && tgt === 'slices') {
    const ser = cleanSeries(spec).filter((s) => s.points.length);
    if (ser.length === 1) out.slices = ser[0].points.map((p) => ({ label: p.x, value: p.y === null ? 0 : p.y, color: p.c || undefined }));
    else out.slices = ser.map((s) => ({ label: s.name, value: s.points.reduce((a, p) => a + (p.y || 0), 0), color: s.color || undefined }));
  } else if (src === 'slices' && tgt === 'series') {
    out.series = [{ name: spec.title ? String(spec.title) : lab(T.value), points: cleanSlices(spec).map((s) => ({ x: s.label, y: s.value === null ? 0 : s.value, color: s.color || undefined })) }];
  } else if (src === 'series' && tgt === 'value') {
    const ser = cleanSeries(spec).filter((s) => s.points.some((p) => p.y !== null));
    const first = ser[0] ? ser[0].points.filter((p) => p.y !== null) : [];
    const vals = [].concat(...ser.map((s) => s.points.map((p) => p.y).filter(isNum)));
    out.value = first.length ? first[first.length - 1].y : 0;
    out.min = Math.min(0, ...vals); out.max = niceScale(out.min, Math.max(1, out.value, ...vals), 5).max;
    if (first.length > 1) out.target = f1(first.reduce((a, p) => a + p.y, 0) / first.length);
  } else if (src === 'slices' && tgt === 'value') {
    const sl = cleanSlices(spec).filter((s) => s.value !== null);
    out.value = sl.length ? sl[0].value : 0; out.min = 0; out.max = Math.max(1, out.value, sl.reduce((a, s) => a + Math.max(0, s.value), 0));
  } else if (src === 'value' && tgt === 'series') {
    out.series = [{ name: spec.title ? String(spec.title) : lab(T.value), points: [{ x: lab(T.value), y: toNum(spec.value) || 0 }].concat(toNum(spec.target) !== null ? [{ x: lab(T.target), y: toNum(spec.target) }] : []) }];
  } else if (src === 'value' && tgt === 'slices') {
    const v = toNum(spec.value) || 0, mx = toNum(spec.max);
    out.slices = [{ label: lab(T.value), value: v }].concat(mx !== null && mx > v ? [{ label: lab(T.rest), value: mx - v }] : []);
  }
  return out;
}
function compatible(spec) {
  const shape = detectShape(spec);
  if (!shape || !hasData(spec, shape)) return [];
  let ids;
  if (shape === 'series') { ids = ['line', 'area', 'bar', 'column']; if (cleanSeries(spec).filter((s) => s.points.length).length >= 2) ids.push('stacked_bar'); }
  else if (shape === 'slices') {
    const sl = cleanSlices(spec);
    ids = ['bar', 'column'];
    if (!sl.some((s) => s.value !== null && s.value < 0) && sl.some((s) => s.value > 0)) ids.push('pie', 'donut', 'treemap');
  } else ids = ['gauge', 'bullet'];
  return TYPE_IDS.filter((i) => ids.indexOf(i) >= 0);
}

// ---------- css ----------
const CSS = `
.bch{position:relative;display:block;width:100%;box-sizing:border-box;font:12px/1.35 system-ui,-apple-system,"Segoe UI",Roboto,"Noto Sans Bengali",sans-serif;color:var(--bch-ink);text-align:left;-webkit-tap-highlight-color:transparent}
.bch *{box-sizing:border-box}
.bch[data-th="dark"]{--bch-ink:#f4eee6;--bch-muted:#a9a29a;--bch-grid:rgba(255,255,255,.11);--bch-sep:#23252b;--bch-tile:#23252b;--bch-tip:#0d0e10;--bch-tipink:#f4eee6;--bch-track:rgba(255,255,255,.10);--bch-oncol:#101114}
.bch[data-th="light"]{--bch-ink:#2b1b17;--bch-muted:#6c5a53;--bch-grid:rgba(110,60,30,.16);--bch-sep:#ffffff;--bch-tile:#ffffff;--bch-tip:#2b1b17;--bch-tipink:#fff;--bch-track:rgba(110,60,30,.10);--bch-oncol:#ffffff}
.bch.bch-auto[data-th="dark"]{--bch-ink:var(--ink,#f4eee6);--bch-muted:var(--muted,#a9a29a);--bch-sep:var(--card,#23252b);--bch-tile:var(--card,#23252b)}
.bch.bch-auto[data-th="light"]{--bch-ink:var(--ink,#2b1b17);--bch-muted:var(--muted,#6c5a53);--bch-sep:var(--card,#ffffff);--bch-tile:var(--card,#ffffff)}
.bch-tile{background:var(--bch-tile);border-radius:14px;padding:12px}
.bch-title{font-weight:600;font-size:13px;margin:0 0 6px;color:var(--bch-ink);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bch-svgwrap{position:relative;width:100%;overflow:hidden}
.bch-svg{display:block;width:100%;touch-action:pan-y;user-select:none;-webkit-user-select:none;overflow:hidden}
.bch-svg text{font-family:inherit;fill:var(--bch-ink)}
.bch-svg .bch-t-m{fill:var(--bch-muted);font-size:11px}
.bch-svg .bch-t-v{font-size:11px;font-weight:600}
.bch-svg .bch-t-c{font-size:11px;font-weight:600;fill:var(--bch-oncol)}
.bch-svg .bch-empty{fill:var(--bch-muted);font-size:13px}
.bch-grid{stroke:var(--bch-grid);stroke-width:1;shape-rendering:crispEdges}
.bch-axis{stroke:var(--bch-muted);stroke-width:1;shape-rendering:crispEdges;opacity:.7}
.bch-sep{stroke:var(--bch-sep)}
.bch-track{fill:var(--bch-track)}
.bch-hit{fill:transparent;stroke:none;cursor:pointer;outline:none}
.bch-band.on{fill:var(--bch-ink);fill-opacity:.08}
.bch-line{fill:none;stroke-width:2.25;stroke-linejoin:round;stroke-linecap:round}
.bch-pt{stroke:var(--bch-sep);stroke-width:1.5;transition:r .12s}
.bch-pt.bch-sel{r:5.5}
.bch-needle{stroke:var(--bch-ink);stroke-width:3;stroke-linecap:round}
.bch-hub{fill:var(--bch-ink)}
.bch-tgt{stroke:var(--bch-ink);stroke-width:3;stroke-linecap:round}
.bch-has-sel [data-s]{opacity:.4;transition:opacity .15s}
.bch-has-sel [data-s].bch-sel{opacity:1}
.bch-slice,.bch-cell{cursor:pointer;transition:transform .18s,opacity .15s;outline:none}
.bch-slice.bch-sel{transform:translate(var(--dx,0px),var(--dy,0px))}
.bch-svg [tabindex]:focus-visible{outline:2px solid var(--bch-ink);outline-offset:1px}
.bch-legend{display:flex;flex-wrap:wrap;gap:4px 6px;margin-top:8px;min-width:0}
.bch-lg{all:unset;box-sizing:border-box;display:inline-flex;align-items:center;gap:6px;min-height:28px;max-width:100%;padding:2px 8px;border-radius:999px;font-size:11.5px;color:var(--bch-ink);cursor:pointer;border:1px solid var(--bch-grid)}
.bch-lg:focus-visible{outline:2px solid var(--bch-ink)}
.bch-lg.off{opacity:.45;text-decoration:line-through}
.bch-lg.on{border-color:var(--bch-ink)}
.bch-sw{flex:none;width:10px;height:10px;border-radius:3px}
.bch-lgt{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bch-lgv{color:var(--bch-muted);font-variant-numeric:tabular-nums;white-space:nowrap}
.bch-tip{position:absolute;z-index:5;left:0;top:0;max-width:min(240px,92%);padding:6px 9px;border-radius:9px;background:var(--bch-tip);color:var(--bch-tipink);font-size:12px;line-height:1.35;pointer-events:none;box-shadow:0 6px 18px rgba(0,0,0,.35);opacity:0;visibility:hidden;transition:opacity .12s}
.bch-tip.show{opacity:1;visibility:visible}
.bch-tip b{display:block;font-weight:600;margin-bottom:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bch-tr{display:flex;align-items:center;gap:6px;white-space:nowrap}
.bch-tr .bch-sw{width:8px;height:8px}
.bch-sr{position:absolute!important;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap;border:0}
@keyframes bch-gy{from{transform:scaleY(0)}to{transform:scaleY(1)}}
@keyframes bch-gx{from{transform:scaleX(0)}to{transform:scaleX(1)}}
@keyframes bch-draw{from{stroke-dashoffset:1}to{stroke-dashoffset:0}}
@keyframes bch-fade{from{opacity:0}to{opacity:1}}
@keyframes bch-pop{from{opacity:0;transform:scale(.88)}to{opacity:1;transform:scale(1)}}
@keyframes bch-needle{from{transform:rotate(var(--bch-n0,-90deg))}to{transform:rotate(0deg)}}
.bch-anim .bch-bv{transform-box:fill-box;transform-origin:50% 100%;animation:bch-gy .6s cubic-bezier(.2,.7,.2,1) both}
.bch-anim .bch-bvn{transform-box:fill-box;transform-origin:50% 0;animation:bch-gy .6s cubic-bezier(.2,.7,.2,1) both}
.bch-anim .bch-bh{transform-box:fill-box;transform-origin:0 50%;animation:bch-gx .6s cubic-bezier(.2,.7,.2,1) both}
.bch-anim .bch-bhn{transform-box:fill-box;transform-origin:100% 50%;animation:bch-gx .6s cubic-bezier(.2,.7,.2,1) both}
.bch-anim .bch-line{stroke-dasharray:1;animation:bch-draw .8s ease both}
.bch-anim .bch-areafill,.bch-anim .bch-pt,.bch-anim .bch-fade{animation:bch-fade .7s .15s ease both}
.bch-anim .bch-slice{animation:bch-pop .6s cubic-bezier(.2,.7,.2,1) both}
.bch-anim .bch-cell{animation:bch-fade .5s ease both}
.bch-anim .bch-needle{animation:bch-needle .9s cubic-bezier(.2,.8,.2,1) both}
@media (prefers-reduced-motion:reduce){.bch *{animation:none!important;transition:none!important}}
`;
function injectCss() {
  if (document.getElementById('bch-css')) return;
  const st = document.createElement('style'); st.id = 'bch-css'; st.textContent = CSS;
  (document.head || document.documentElement).appendChild(st);
}

// ---------- svg / html helpers ----------
const safeAttr = (v) => (typeof v === 'number' ? (Number.isFinite(v) ? String(Math.round(v * 100) / 100) : '0') : String(v === undefined || v === null ? '' : v).replace(/NaN|undefined|Infinity/g, '0'));
function S(tag, attrs, parent, text) {
  const e = document.createElementNS(NS, tag);
  if (attrs) for (const k in attrs) if (attrs[k] !== undefined && attrs[k] !== null) e.setAttribute(k, safeAttr(attrs[k]));
  if (text !== undefined && text !== null) e.textContent = String(text);
  if (parent) parent.appendChild(e);
  return e;
}
function H(tag, cls, parent, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = String(text);
  if (parent) parent.appendChild(e);
  return e;
}
const polarA = (cx, cy, r, deg) => [cx + r * Math.sin(deg * Math.PI / 180), cy - r * Math.cos(deg * Math.PI / 180)]; // 0 = 12 o'clock, clockwise
const polarG = (cx, cy, r, deg) => [cx - r * Math.cos(deg * Math.PI / 180), cy - r * Math.sin(deg * Math.PI / 180)]; // 0 = left, 180 = right (gauge)
function ring(pf, cx, cy, r0, r1, a0, a1) { // ring / pie segment path, angles in degrees, clockwise on screen
  const sweep = a1 - a0, P = (x, y) => f1(x) + ' ' + f1(y);
  if (sweep >= 359.99) {
    const [x0, y0] = pf(cx, cy, r1, a0), [x1, y1] = pf(cx, cy, r1, a0 + 180);
    let d = `M${P(x0, y0)}A${f1(r1)} ${f1(r1)} 0 1 1 ${P(x1, y1)}A${f1(r1)} ${f1(r1)} 0 1 1 ${P(x0, y0)}Z`;
    if (r0 > 0) { const [u0, v0] = pf(cx, cy, r0, a0), [u1, v1] = pf(cx, cy, r0, a0 + 180); d += `M${P(u0, v0)}A${f1(r0)} ${f1(r0)} 0 1 0 ${P(u1, v1)}A${f1(r0)} ${f1(r0)} 0 1 0 ${P(u0, v0)}Z`; }
    return d;
  }
  const large = sweep > 180 ? 1 : 0;
  const [ox0, oy0] = pf(cx, cy, r1, a0), [ox1, oy1] = pf(cx, cy, r1, a1);
  if (r0 <= 0) return `M${P(cx, cy)}L${P(ox0, oy0)}A${f1(r1)} ${f1(r1)} 0 ${large} 1 ${P(ox1, oy1)}Z`;
  const [ix0, iy0] = pf(cx, cy, r0, a0), [ix1, iy1] = pf(cx, cy, r0, a1);
  return `M${P(ox0, oy0)}A${f1(r1)} ${f1(r1)} 0 ${large} 1 ${P(ox1, oy1)}L${P(ix1, iy1)}A${f1(r0)} ${f1(r0)} 0 ${large} 0 ${P(ix0, iy0)}Z`;
}

// ---------- squarified treemap ----------
function squarify(items, x, y, w, h) { // items sorted desc with v>0; returns items with x,y,w,h tiling the rect exactly
  const total = items.reduce((a, it) => a + it.v, 0), out = [];
  if (!items.length || total <= 0 || w <= 0 || h <= 0) return out;
  const scale = (w * h) / total, q = items.map((it) => Object.assign({}, it, { a: it.v * scale }));
  let rx = x, ry = y, rw = w, rh = h, i = 0;
  const worst = (row, side) => { const s = row.reduce((a, it) => a + it.a, 0); let mx = 0, mn = Infinity; row.forEach((it) => { mx = Math.max(mx, it.a); mn = Math.min(mn, it.a); }); return Math.max(side * side * mx / (s * s), (s * s) / (side * side * mn)); };
  while (i < q.length) {
    const side = Math.min(rw, rh), row = [q[i]]; i++;
    while (i < q.length && worst(row.concat(q[i]), side) <= worst(row, side)) { row.push(q[i]); i++; }
    const s = row.reduce((a, it) => a + it.a, 0), last = i >= q.length;
    if (rw >= rh) { // a column on the left
      const cw = last ? rw : s / rh; let cy = ry;
      row.forEach((it, k) => { const hh = k === row.length - 1 ? ry + rh - cy : it.a / cw; Object.assign(it, { x: rx, y: cy, w: cw, h: hh }); out.push(it); cy += hh; });
      rx += cw; rw -= cw;
    } else { // a strip on top
      const sh = last ? rh : s / rw; let cx = rx;
      row.forEach((it, k) => { const ww = k === row.length - 1 ? rx + rw - cx : it.a / sh; Object.assign(it, { x: cx, y: ry, w: ww, h: sh }); out.push(it); cx += ww; });
      ry += sh; rh -= sh;
    }
  }
  return out;
}

// ---------- theme ----------
function resolveTheme(host, theme) {
  if (theme === 'dark' || theme === 'light') return theme;
  try {
    const el = host.closest ? host.closest('[data-theme]') : null;
    const t = el ? el.getAttribute('data-theme') : document.documentElement.getAttribute('data-theme');
    if (t === 'dark') return 'dark';
    if (t === 'light' || t === 'classic') return 'light';
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
  } catch (e) { return 'dark'; }
}

let UID = 0;
const colorOf = (i, th, given) => given || PAL[th][i % PAL[th].length];

// ---------- the chart ----------
function render(host, spec0) {
  injectCss();
  const uid = ++UID;
  let spec = spec0 || {};
  let destroyed = false, lastW = 0, lastKey = '', timer = 0, rafId = 0, selKey = null;
  const hidden = new Set(); // legend-hidden series names
  const offs = []; // listener removers
  const on = (t, ev, fn, o) => { t.addEventListener(ev, fn, o); offs.push(() => t.removeEventListener(ev, fn, o)); };

  const root = H('div', 'bch');
  const titleEl = H('div', 'bch-title', root); titleEl.style.display = 'none';
  const wrap = H('div', 'bch-svgwrap', root);
  const legend = H('div', 'bch-legend', root);
  const tip = H('div', 'bch-tip', wrap); tip.setAttribute('aria-hidden', 'true');
  const sr = H('div', 'bch-sr', root);
  let svg = null, model = { items: [] };
  host.textContent = '';
  host.appendChild(root);

  const reduced = () => { try { return window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
  const hostW = () => Math.round(host.clientWidth || host.getBoundingClientRect().width || 0) || 320;

  function fmtFns(sp) {
    const mode = sp.grouping === 'intl' || sp.grouping === 'none' ? sp.grouping : 'bd';
    const base = typeof sp.format === 'function' ? sp.format : defFmt(mode);
    const safe = (f) => (n) => { try { const s = f(n); return s === undefined || s === null ? '' : String(s); } catch (e) { return String(n); } };
    const f = safe(base), unit = sp.unit ? ' ' + String(sp.unit) : '';
    const ax = typeof sp.axisFormat === 'function' ? safe(sp.axisFormat) : (typeof sp.format === 'function' && !sp.compact ? f : compact);
    return { f, fu: (n) => f(n) + unit, ax };
  }

  // ----- tooltip / selection -----
  function setSel(key) {
    selKey = key;
    root.classList.toggle('bch-has-sel', key !== null && key !== undefined);
    root.querySelectorAll('.bch-sel,.on').forEach((e) => { e.classList.remove('bch-sel'); e.classList.remove('on'); });
    if (key === null || key === undefined) return;
    root.querySelectorAll('[data-s="' + key + '"]').forEach((e) => e.classList.add('bch-sel'));
    root.querySelectorAll('.bch-band[data-k="' + key + '"],.bch-lg[data-k="' + key + '"]').forEach((e) => e.classList.add('on'));
  }
  function hideTip() { tip.classList.remove('show'); setSel(null); }
  function showTip(key, cx, cy) {
    const it = model.items[key]; if (!it) return;
    setSel(key);
    tip.textContent = '';
    H('b', '', tip, it.title);
    (it.rows || []).forEach((r) => { const row = H('div', 'bch-tr', tip); if (r.color) { const sw = H('span', 'bch-sw', row); sw.style.background = r.color; } H('span', '', row, (r.name ? r.name + ': ' : '') + r.text); });
    tip.classList.add('show');
    const wb = wrap.getBoundingClientRect(), tb = tip.getBoundingClientRect();
    let x = cx - wb.left + 12, y = cy - wb.top - tb.height - 12;
    if (x + tb.width > wb.width - 2) x = cx - wb.left - tb.width - 12;
    x = clamp(x, 2, Math.max(2, wb.width - tb.width - 2));
    if (y < 2) y = cy - wb.top + 16;
    tip.style.left = f1(x) + 'px'; tip.style.top = f1(y) + 'px';
  }
  const hitOf = (e) => { const t = e.target && e.target.closest ? e.target.closest('[data-k]') : null; return t && wrap.contains(t) ? t : null; };
  const centre = (t) => { const b = t.getBoundingClientRect(); return [b.left + b.width / 2, b.top]; };
  function onPointer(e) {
    if (spec.mini) return;
    const t = hitOf(e);
    if (!t) { if (e.type === 'pointerdown') hideTip(); return; }
    const k = Number(t.getAttribute('data-k'));
    if (e.type === 'pointerdown' && e.pointerType !== 'mouse' && selKey === k && tip.classList.contains('show')) { hideTip(); return; }
    showTip(k, e.clientX, e.clientY);
  }
  on(wrap, 'pointerdown', onPointer);
  on(wrap, 'pointermove', (e) => { if (e.pointerType === 'mouse') onPointer(e); });
  on(wrap, 'pointerleave', (e) => { if (e.pointerType === 'mouse') hideTip(); });
  on(wrap, 'focusin', (e) => { const t = hitOf(e); if (t && !spec.mini) { const [x, y] = centre(t); showTip(Number(t.getAttribute('data-k')), x, y); } });
  on(wrap, 'keydown', (e) => {
    if (e.key === 'Escape') hideTip();
    else if (e.key === 'Enter' || e.key === ' ') { const t = hitOf(e); if (t) { e.preventDefault(); const [x, y] = centre(t); showTip(Number(t.getAttribute('data-k')), x, y); } }
  });
  on(document, 'pointerdown', (e) => { if (!root.contains(e.target)) hideTip(); }, true);
  on(legend, 'click', (e) => {
    const b = e.target.closest ? e.target.closest('.bch-lg') : null; if (!b) return;
    if (b.getAttribute('data-mode') === 'toggle') {
      const nm = b.getAttribute('data-name');
      if (hidden.has(nm)) hidden.delete(nm); else if ((model.serNames || []).length - hidden.size > 1) hidden.add(nm);
      draw(false);
    } else {
      const k = Number(b.getAttribute('data-k')), wb = wrap.getBoundingClientRect();
      if (selKey === k) hideTip(); else showTip(k, wb.left + wb.width / 2, wb.top + 30);
    }
  });

  // ----- shared frame -----
  function frame(W, Hh) {
    const s = S('svg', { class: 'bch-svg', viewBox: `0 0 ${W} ${Hh}`, width: W, height: Hh, role: 'img', preserveAspectRatio: 'xMidYMid meet' });
    s.style.height = Hh + 'px';
    return s;
  }
  const plotBox = (s, x, y, w, h) => { s.setAttribute('data-px', f1(x)); s.setAttribute('data-py', f1(y)); s.setAttribute('data-pw', f1(w)); s.setAttribute('data-ph', f1(h)); };
  function empty(W, Hh) { const s = frame(W, Hh); S('text', { class: 'bch-empty', x: W / 2, y: Hh / 2, 'text-anchor': 'middle', 'dominant-baseline': 'middle' }, s, lab(T.nodata)); return s; }

  // ----- series charts: line, area, bar, column, stacked_bar -----
  function catData(sp, th) {
    const all = cleanSeries(sp).filter((s) => s.points.length);
    const cats = [], seen = new Map();
    all.forEach((s) => s.points.forEach((p) => { if (!seen.has(p.x)) { seen.set(p.x, cats.length); cats.push(p.x); } }));
    all.forEach((s, i) => {
      s.color = colorOf(i, th, s.color); s.label = s.name || ('#' + (i + 1));
      s.vals = cats.map(() => null); s.cols = cats.map(() => null);
      s.points.forEach((p) => { const ci = seen.get(p.x); if (p.y !== null) s.vals[ci] = (s.vals[ci] || 0) + p.y; if (p.c) s.cols[ci] = p.c; });
    });
    let vis = all.filter((s) => !hidden.has(s.label));
    if (!vis.length) vis = all;
    return { cats, all, vis };
  }

  function drawSeries(sp, type, W, th, fm) {
    const mini = !!sp.mini;
    const { cats, all, vis } = catData(sp, th);
    if (!cats.length || !vis.some((s) => s.vals.some((v) => v !== null))) return null;
    const horiz = type === 'bar' || type === 'stacked_bar', stacked = type === 'stacked_bar';
    const nS = vis.length, n = cats.length;
    let lo = Infinity, hi = -Infinity;
    if (stacked) cats.forEach((_, ci) => { let p = 0, q = 0; vis.forEach((s) => { const v = s.vals[ci] || 0; if (v >= 0) p += v; else q += v; }); lo = Math.min(lo, q); hi = Math.max(hi, p); });
    else vis.forEach((s) => s.vals.forEach((v) => { if (v !== null) { lo = Math.min(lo, v); hi = Math.max(hi, v); } }));
    const zeroBased = type !== 'line' || (lo >= 0 && lo <= hi * 0.5) || lo < 0;
    if (zeroBased) { lo = Math.min(lo, 0); hi = Math.max(hi, 0); }
    if (lo === hi) hi = lo + 1;
    const rowH = horiz ? (stacked ? 28 : Math.max(24, nS * 15 + 8)) : 0;
    let Hh = Number(sp.height); if (!isNum(Hh) || Hh < 30) Hh = mini ? 36 : horiz ? clamp(n * rowH + 36, 190, 2400) : 220;
    const sc = niceScale(lo, hi, mini ? 2 : clamp(Math.floor((horiz ? W - 120 : Hh - 40) / 52) + 1, 3, 6));
    const fa = fm.ax;
    const axW = Math.max(8, ...sc.ticks.map((t) => tw(fa(t))));
    const catW = horiz ? clamp(Math.max(...cats.map((c) => tw(c))), 36, W * 0.36) : 0;
    const valLbl = !mini && !stacked && nS === 1;
    const padR = horiz ? (valLbl ? clamp(Math.max(0, ...vis[0].vals.map((v) => (v === null ? 0 : tw(fa(v))))) + 8, 10, 70) : 12) : 10;
    const m = mini ? { l: 2, r: 2, t: 3, b: 3 } : horiz ? { l: catW + 10, r: padR, t: 8, b: 22 } : { l: axW + 10, r: 10, t: valLbl ? 16 : 10, b: 24 };
    const pw = Math.max(10, W - m.l - m.r), ph = Math.max(10, Hh - m.t - m.b);
    const vS = (v) => (horiz ? m.l + (v - sc.min) / (sc.max - sc.min) * pw : m.t + ph - (v - sc.min) / (sc.max - sc.min) * ph);
    const el = frame(W, Hh); plotBox(el, m.l, m.t, pw, ph);
    const items = cats.map((c, ci) => ({ title: c, rows: vis.map((s) => ({ name: s.label, color: s.color, text: s.vals[ci] === null ? '–' : fm.fu(s.vals[ci]) })) }));
    const g0 = S('g', { class: 'bch-fade' }, el);
    if (!mini) {
      sc.ticks.forEach((t) => {
        const p = vS(t);
        if (horiz) { S('line', { class: 'bch-grid', x1: p, x2: p, y1: m.t, y2: m.t + ph }, g0); S('text', { class: 'bch-t-m', x: p, y: Hh - 6, 'text-anchor': t === sc.max && p + 18 > W ? 'end' : 'middle' }, g0, fa(t)); }
        else { S('line', { class: 'bch-grid', x1: m.l, x2: m.l + pw, y1: p, y2: p }, g0); S('text', { class: 'bch-t-m', x: m.l - 6, y: p, 'text-anchor': 'end', 'dominant-baseline': 'middle' }, g0, fa(t)); }
      });
    }
    const zero = vS(clamp(0, sc.min, sc.max));
    if (!mini && zeroBased) { if (horiz) S('line', { class: 'bch-axis', x1: zero, x2: zero, y1: m.t, y2: m.t + ph }, g0); else S('line', { class: 'bch-axis', x1: m.l, x2: m.l + pw, y1: zero, y2: zero }, g0); }
    const band = (horiz ? ph : pw) / n, catPos = (ci) => (horiz ? m.t : m.l) + band * (ci + 0.5);
    if (!mini) {
      if (horiz) cats.forEach((c, ci) => S('text', { class: 'bch-t-m', x: m.l - 8, y: catPos(ci), 'text-anchor': 'end', 'dominant-baseline': 'middle' }, g0, trunc(c, catW)));
      else if (type === 'line' || type === 'area') {
        const xAt = (ci) => (n === 1 ? m.l + pw / 2 : m.l + pw * ci / (n - 1)), stride = Math.max(1, Math.ceil((Math.max(...cats.map((c) => Math.min(tw(c), 56))) + 8) / (pw / Math.max(1, n - 1))));
        cats.forEach((c, ci) => { if (ci % stride === 0) { const x = xAt(ci); S('text', { class: 'bch-t-m', x: clamp(x, m.l + 14, W - 14), y: Hh - 7, 'text-anchor': 'middle' }, g0, trunc(c, 56)); } });
      } else {
        const stride = Math.max(1, Math.ceil((Math.max(...cats.map((c) => Math.min(tw(c), 56))) + 6) / band));
        cats.forEach((c, ci) => { if (ci % stride === 0) S('text', { class: 'bch-t-m', x: catPos(ci), y: Hh - 7, 'text-anchor': 'middle' }, g0, trunc(c, Math.max(band * stride - 4, 20))); });
      }
    }
    if (type === 'line' || type === 'area') {
      const xAt = (ci) => (n === 1 ? m.l + pw / 2 : m.l + pw * ci / (n - 1));
      const defs = S('defs', null, el);
      vis.forEach((s, si) => {
        const gid = `bchg${uid}_${si}`, grad = S('linearGradient', { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
        S('stop', { offset: '0%', 'stop-color': s.color, 'stop-opacity': 0.42 }, grad); S('stop', { offset: '100%', 'stop-color': s.color, 'stop-opacity': 0.03 }, grad);
        const segs = []; let cur = [];
        s.vals.forEach((v, ci) => { if (v === null) { if (cur.length) segs.push(cur); cur = []; } else cur.push([xAt(ci), vS(v)]); });
        if (cur.length) segs.push(cur);
        const g = S('g', { class: 'bch-ser' }, el);
        segs.forEach((sg) => {
          const d = sg.map((p, i) => (i ? 'L' : 'M') + f1(p[0]) + ' ' + f1(p[1])).join('');
          if (type === 'area' && sg.length > 1) S('path', { class: 'bch-areafill', d: d + `L${f1(sg[sg.length - 1][0])} ${f1(zero)}L${f1(sg[0][0])} ${f1(zero)}Z`, fill: `url(#${gid})`, stroke: 'none' }, g);
          if (sg.length > 1) S('path', { class: 'bch-line', d, stroke: s.color, pathLength: 1 }, g);
        });
        if (!mini && n <= 40) s.vals.forEach((v, ci) => { if (v !== null) S('circle', { class: 'bch-pt', cx: xAt(ci), cy: vS(v), r: n > 20 ? 2.2 : 3.4, fill: s.color, 'data-s': ci }, g); });
        else if (segs.length) { const lp = segs[segs.length - 1].slice(-1)[0]; S('circle', { cx: lp[0], cy: lp[1], r: 2.6, fill: s.color }, g); }
      });
      if (!mini) { const bw = n === 1 ? pw : pw / (n - 1); cats.forEach((c, ci) => { const x = xAt(ci); S('rect', { class: 'bch-hit bch-band', x: clamp(x - bw / 2, m.l, m.l + pw), y: m.t, width: Math.min(bw, pw), height: ph, 'data-k': ci }, el); }); }
    } else {
      const inner = Math.min(band * 0.78, horiz ? 26 : 44), bw = stacked ? inner : Math.max(2, (inner - (nS - 1) * 2) / nS);
      const span = stacked ? bw : nS * bw + (nS - 1) * 2;
      cats.forEach((c, ci) => {
        let posAcc = 0, negAcc = 0;
        vis.forEach((s, si) => {
          const v = s.vals[ci]; if (v === null) return;
          let a = 0, b = v;
          if (stacked) { if (v >= 0) { a = posAcc; b = posAcc + v; posAcc = b; } else { a = negAcc; b = negAcc + v; negAcc = b; } }
          const pa = vS(a), pb = vS(b), off = stacked ? -bw / 2 : -span / 2 + si * (bw + 2), neg = v < 0;
          const col = (nS === 1 && s.cols[ci]) || s.color;
          if (horiz) S('rect', { class: 'bch-bar ' + (neg ? 'bch-bhn' : 'bch-bh'), x: Math.min(pa, pb), y: catPos(ci) + off, width: Math.abs(pb - pa) || (v === 0 ? 0 : 1), height: bw, rx: 3, fill: col, 'data-s': ci }, el);
          else S('rect', { class: 'bch-bar ' + (neg ? 'bch-bvn' : 'bch-bv'), x: catPos(ci) + off, y: Math.min(pa, pb), width: bw, height: Math.abs(pb - pa) || (v === 0 ? 0 : 1), rx: 3, fill: col, 'data-s': ci }, el);
          if (valLbl) {
            const txt = fa(v);
            if (horiz) S('text', { class: 'bch-t-v', x: neg ? Math.min(pa, pb) - 4 : Math.max(pa, pb) + 4, y: catPos(ci), 'text-anchor': neg ? 'end' : 'start', 'dominant-baseline': 'middle', 'data-s': ci }, el, txt);
            else if (band >= tw(txt) * 0.8) S('text', { class: 'bch-t-v', x: catPos(ci), y: neg ? Math.max(pa, pb) + 12 : Math.min(pa, pb) - 4, 'text-anchor': 'middle', 'data-s': ci }, el, txt);
          }
        });
        if (!mini) {
          if (horiz) S('rect', { class: 'bch-hit bch-band', x: m.l, y: m.t + band * ci, width: pw, height: band, 'data-k': ci }, el);
          else S('rect', { class: 'bch-hit bch-band', x: m.l + band * ci, y: m.t, width: band, height: ph, 'data-k': ci }, el);
        }
      });
    }
    if (!mini && n <= 30) el.querySelectorAll('.bch-band').forEach((b) => b.setAttribute('tabindex', '0'));
    const lg = !mini && all.length > 1 ? all.map((s) => ({ name: s.label, color: s.color, mode: 'toggle', off: hidden.has(s.label) })) : [];
    const summary = all.map((s) => { const v = s.vals.filter((x) => x !== null); return v.length ? `${s.label}: ${lab(T.min)} ${fm.f(Math.min(...v))}, ${lab(T.max)} ${fm.f(Math.max(...v))}, ${lab(T.last)} ${fm.f(v[v.length - 1])}` : s.label; }).join('; ') + ` (${all.length} ${lab(T.series)}, ${cats.length} ${lab(T.points)})`;
    return { svg: el, H: Hh, items, legend: lg, serNames: all.map((s) => s.label), summary, table: { head: [''].concat(all.map((s) => s.label)), rows: cats.map((c, ci) => [c].concat(all.map((s) => (s.vals[ci] === null ? '' : fm.fu(s.vals[ci]))))) } };
  }

  // ----- composition charts: pie, donut, treemap -----
  function drawSlices(sp, type, W, th, fm) {
    const mini = !!sp.mini;
    let sl = cleanSlices(sp).filter((s) => s.value !== null && s.value > 0).map((s) => ({ label: s.label, v: s.value, color: s.color }));
    const total = sl.reduce((a, s) => a + s.v, 0);
    if (!sl.length || !(total > 0)) return null;
    sl.sort((a, b) => b.v - a.v);
    if (type !== 'treemap' && sl.length > 8) { const rest = sl.slice(7); sl = sl.slice(0, 7); sl.push({ label: lab(T.other), v: rest.reduce((a, s) => a + s.v, 0), color: null }); }
    sl.forEach((s, i) => { s.color = colorOf(i, th, s.color); s.pct = s.v / total * 100; });
    const items = sl.map((s) => ({ title: s.label, rows: [{ name: '', color: s.color, text: fm.fu(s.v) + ' · ' + f1(s.pct) + '%' }] }));
    const lg = mini ? [] : sl.map((s, i) => ({ name: s.label, color: s.color, mode: 'hl', k: i, value: fm.fu(s.v) }));
    const table = { head: ['', lab(T.value)], rows: sl.map((s) => [s.label, fm.fu(s.v)]) };
    const summary = sl.slice(0, 8).map((s) => `${s.label} ${fm.f(s.v)} (${Math.round(s.pct)}%)`).join('; ');
    let Hh = Number(sp.height); if (!isNum(Hh) || Hh < 30) Hh = mini ? 36 : type === 'treemap' ? 240 : 220;
    const el = frame(W, Hh);
    if (type === 'treemap') {
      plotBox(el, 0, 0, W, Hh);
      squarify(sl.map((s) => ({ v: s.v, s })), 0, 0, W, Hh).forEach((r) => {
        const s = r.s, idx = sl.indexOf(s);
        const g = S('g', { class: 'bch-cell', 'data-k': idx, 'data-s': idx, tabindex: mini ? undefined : 0 }, el);
        S('rect', { class: 'bch-tm bch-sep', x: r.x, y: r.y, width: r.w, height: r.h, fill: s.color, 'stroke-width': 2 }, g);
        if (!mini && r.w > 44 && r.h > 26) {
          S('text', { class: 'bch-t-c', x: r.x + 7, y: r.y + 16 }, g, trunc(s.label, r.w - 14));
          if (r.h > 40) S('text', { class: 'bch-t-c', x: r.x + 7, y: r.y + 31, style: 'font-weight:400' }, g, trunc(f1(s.pct) + '%', r.w - 14));
        }
      });
      return { svg: el, H: Hh, items, legend: lg, table, summary };
    }
    const R = Math.max(10, Math.min(W / 2 - 10, Hh / 2 - 6)), cx = W / 2, cy = Hh / 2, r0 = type === 'donut' ? R * 0.58 : 0;
    plotBox(el, cx - R, cy - R, 2 * R, 2 * R);
    let a = 0;
    sl.forEach((s, i) => {
      const a0 = a, a1 = i === sl.length - 1 ? 360 : a + s.pct * 3.6, mid = (a0 + a1) / 2;
      a = a1;
      const [dx, dy] = polarA(0, 0, mini ? 0 : 7, mid);
      const p = S('path', { class: 'bch-slice bch-sep', d: ring(polarA, cx, cy, r0, R, a0, a1), fill: s.color, 'stroke-width': sl.length > 1 ? 1.5 : 0, 'data-a0': f1(a0), 'data-a1': f1(a1), 'data-k': i, 'data-s': i, tabindex: mini ? undefined : 0 }, el);
      p.style.setProperty('--dx', f1(dx) + 'px'); p.style.setProperty('--dy', f1(dy) + 'px'); p.style.transformOrigin = `${f1(cx)}px ${f1(cy)}px`;
      if (!mini && a1 - a0 >= 22) { const [tx, ty] = polarA(cx, cy, type === 'donut' ? (R + r0) / 2 : R * 0.64, mid); S('text', { class: 'bch-t-c', x: tx, y: ty, 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'pointer-events': 'none' }, el, Math.round(s.pct) + '%'); }
    });
    if (type === 'donut' && !mini && r0 > 30) {
      S('text', { class: 'bch-t-v', x: cx, y: cy - 2, 'text-anchor': 'middle', style: 'font-size:16px', 'pointer-events': 'none' }, el, trunc(fm.fu(total), r0 * 1.7, 16));
      S('text', { class: 'bch-t-m', x: cx, y: cy + 14, 'text-anchor': 'middle', 'pointer-events': 'none' }, el, lab(T.total));
    }
    return { svg: el, H: Hh, items, legend: lg, table, summary };
  }

  // ----- single-value charts: gauge, bullet -----
  function valueRanges(sp, mn, mx) {
    const rs = (Array.isArray(sp.ranges) ? sp.ranges : []).map((r) => ({ to: r ? toNum(r.to) : null, color: r && okColor(r.color) })).filter((r) => r.to !== null).sort((a, b) => a.to - b.to);
    const out = []; let from = mn;
    rs.forEach((r) => { const to = Math.min(r.to, mx); if (to > from) { out.push({ from, to, color: r.color }); from = to; } });
    return out;
  }
  function valueScale(sp) {
    const v = toNum(sp.value); if (v === null) return null;
    const rs = (Array.isArray(sp.ranges) ? sp.ranges : []).map((r) => (r ? toNum(r.to) : null)).filter((x) => x !== null), tg = toNum(sp.target);
    let mn = toNum(sp.min); if (mn === null) mn = Math.min(0, v, tg === null ? 0 : tg);
    let mx = toNum(sp.max); if (mx === null) mx = niceScale(mn, Math.max(v, tg === null ? v : tg, ...rs, mn + 1) * 1.05, 5).max;
    if (mx <= mn) mx = mn + 1;
    return { v, tg, mn, mx };
  }
  function valueResult(sp, th, fm, vs, el, Hh) {
    const { v, tg, mn, mx } = vs;
    const rows = [{ name: lab(T.value), color: PAL[th][0], text: fm.fu(v) }];
    if (tg !== null) rows.push({ name: lab(T.target), color: null, text: fm.fu(tg) });
    return { svg: el, H: Hh, items: [{ title: sp.title ? String(sp.title) : lab(T.value), rows }], legend: [], table: { head: [lab(T.value), lab(T.target), lab(T.min), lab(T.max)], rows: [[fm.fu(v), tg === null ? '' : fm.fu(tg), fm.f(mn), fm.f(mx)]] }, summary: `${fm.fu(v)} (${fm.f(mn)} – ${fm.f(mx)})` + (tg !== null ? `, ${lab(T.target)} ${fm.fu(tg)}` : '') };
  }

  function drawGauge(sp, W, th, fm) {
    const vs = valueScale(sp); if (!vs) return null;
    const mini = !!sp.mini, { v, tg, mn, mx } = vs, frac = (x) => clamp((x - mn) / (mx - mn), 0, 1);
    const hSet = Number(sp.height) > 30 ? Number(sp.height) : 0;
    let R = mini ? Math.min((W - 8) / 2, hSet ? hSet - 6 : 30) : Math.min((W - 40) / 2, 150, hSet ? hSet - 70 : 150);
    R = Math.max(R, 20);
    const tk = mini ? R * 0.28 : clamp(R * 0.2, 12, 26), cx = W / 2, cy = R + (mini ? 3 : 14);
    const Hh = Math.round(mini ? cy + 3 : hSet || cy + 56);
    const el = frame(W, Hh); plotBox(el, cx - R, cy - R, 2 * R, R);
    const g = S('g', { class: 'bch-fade' }, el), rs = valueRanges(sp, mn, mx);
    if (rs.length) {
      rs.forEach((r, i) => S('path', { class: 'bch-range bch-sep', d: ring(polarG, cx, cy, R - tk, R, frac(r.from) * 180, frac(r.to) * 180), fill: r.color || PAL[th][(i + 4) % 8], 'fill-opacity': r.color ? 1 : 0.55, 'stroke-width': 1.5, 'data-from': f1(r.from), 'data-to': f1(r.to) }, g));
      const covered = rs[rs.length - 1].to;
      if (covered < mx) S('path', { class: 'bch-track', d: ring(polarG, cx, cy, R - tk, R, frac(covered) * 180, 180) }, g);
    } else {
      S('path', { class: 'bch-track', d: ring(polarG, cx, cy, R - tk, R, 0, 180) }, g);
      if (frac(v) > 0) S('path', { class: 'bch-valarc', d: ring(polarG, cx, cy, R - tk, R, 0, Math.max(frac(v) * 180, 0.5)), fill: PAL[th][0] }, g);
    }
    if (tg !== null && tg >= mn && tg <= mx) { const ang = frac(tg) * 180, [x1, y1] = polarG(cx, cy, R - tk - 3, ang), [x2, y2] = polarG(cx, cy, R + 4, ang); S('line', { class: 'bch-tgt', x1, y1, x2, y2, 'data-deg': f1(ang) }, g); }
    const angle = frac(v) * 180, [nx, ny] = polarG(cx, cy, R - tk - 6 > 6 ? R - tk - 6 : R - 4, angle);
    const nd = S('line', { class: 'bch-needle', x1: cx, y1: cy, x2: nx, y2: ny, 'data-deg': f1(angle), 'data-value': v }, el);
    nd.style.transformOrigin = `${f1(cx)}px ${f1(cy)}px`; nd.style.setProperty('--bch-n0', f1(-angle) + 'deg');
    S('circle', { class: 'bch-hub', cx, cy, r: mini ? 3 : 6 }, el);
    if (!mini) {
      S('text', { class: 'bch-t-m', x: cx - R + tk / 2, y: cy + 15, 'text-anchor': 'middle' }, el, trunc(fm.ax(mn), tk * 3));
      S('text', { class: 'bch-t-m', x: cx + R - tk / 2, y: cy + 15, 'text-anchor': 'middle' }, el, trunc(fm.ax(mx), tk * 3));
      S('text', { class: 'bch-t-v', x: cx, y: cy + 40, 'text-anchor': 'middle', style: 'font-size:22px', 'data-role': 'value' }, el, trunc(fm.fu(v), W - 20, 22));
      S('rect', { class: 'bch-hit', x: cx - R, y: cy - R, width: 2 * R, height: R + 10, 'data-k': 0 }, el);
    }
    return valueResult(sp, th, fm, vs, el, Hh);
  }

  function drawBullet(sp, W, th, fm) {
    const vs = valueScale(sp); if (!vs) return null;
    const mini = !!sp.mini, { v, tg, mn, mx } = vs;
    let Hh = Number(sp.height); if (!isNum(Hh) || Hh < 20) Hh = mini ? 24 : 96;
    const ml = mini ? 2 : 14, pw = W - 2 * ml, y0 = mini ? 4 : 14, bandH = mini ? Hh - 8 : 34;
    const X = (x) => ml + clamp((x - mn) / (mx - mn), 0, 1) * pw;
    const el = frame(W, Hh); plotBox(el, ml, y0, pw, bandH);
    const g = S('g', { class: 'bch-fade' }, el), rs = valueRanges(sp, mn, mx);
    if (!rs.length) rs.push({ from: mn, to: mx, color: null });
    else if (rs[rs.length - 1].to < mx) rs.push({ from: rs[rs.length - 1].to, to: mx, color: null });
    rs.forEach((r, i) => S('rect', { class: 'bch-range bch-track', x: X(r.from), y: y0, width: Math.max(0, X(r.to) - X(r.from)), height: bandH, fill: r.color || undefined, 'fill-opacity': r.color ? 0.55 : undefined, style: r.color ? undefined : `fill-opacity:${f1(rs.length > 1 ? 0.5 + 0.5 * i / (rs.length - 1) : 1)}` }, g));
    const base = clamp(0, mn, mx), bh = bandH * 0.36;
    S('rect', { class: 'bch-bar ' + (v < base ? 'bch-bhn' : 'bch-bh'), x: X(Math.min(base, v)), y: y0 + (bandH - bh) / 2, width: Math.abs(X(v) - X(base)), height: bh, rx: 2, fill: PAL[th][0], 'data-role': 'value', 'data-v': v }, el);
    if (tg !== null && tg >= mn && tg <= mx) S('line', { class: 'bch-tgt', x1: X(tg), x2: X(tg), y1: y0 + bandH * 0.14, y2: y0 + bandH * 0.86, 'data-v': tg }, el);
    if (!mini) {
      const ticks = niceScale(mn, mx, clamp(Math.floor(pw / 70) + 1, 3, 6)).ticks.filter((t) => t >= mn - 1e-9 && t <= mx + 1e-9);
      ticks.forEach((t, i) => {
        S('line', { class: 'bch-grid', x1: X(t), x2: X(t), y1: y0 + bandH, y2: y0 + bandH + 4 }, el);
        S('text', { class: 'bch-t-m', x: X(t), y: y0 + bandH + 17, 'text-anchor': i === 0 ? 'start' : i === ticks.length - 1 ? 'end' : 'middle' }, el, fm.ax(t));
      });
      S('text', { class: 'bch-t-v', x: ml, y: y0 + bandH + 37, 'text-anchor': 'start', 'data-role': 'value' }, el, trunc(fm.fu(v), pw * 0.5));
      if (tg !== null) S('text', { class: 'bch-t-m', x: ml + pw, y: y0 + bandH + 37, 'text-anchor': 'end' }, el, trunc(lab(T.target) + ' ' + fm.fu(tg), pw * 0.5));
      S('rect', { class: 'bch-hit', x: ml, y: y0, width: pw, height: bandH, 'data-k': 0 }, el);
    }
    return valueResult(sp, th, fm, vs, el, Hh);
  }

  // ----- draw -----
  function draw(animate) {
    if (destroyed) return;
    const W = Math.max(120, hostW());
    const th = resolveTheme(host, spec.theme);
    root.setAttribute('data-th', th);
    root.classList.toggle('bch-auto', spec.theme !== 'dark' && spec.theme !== 'light');
    const type = TYPE_IDS.indexOf(spec.type) >= 0 ? spec.type : 'column', shape = SHAPE_OF[type];
    let sp = spec;
    const ds = detectShape(spec);
    if (ds !== shape && hasData(spec, ds)) sp = convert(spec, type);
    const fm = fmtFns(sp), ttl = sp.title ? String(sp.title) : '';
    titleEl.textContent = ttl; titleEl.style.display = ttl && !sp.mini ? '' : 'none';
    let res = null;
    try {
      res = shape === 'series' ? drawSeries(sp, type, W, th, fm) : shape === 'slices' ? drawSlices(sp, type, W, th, fm) : type === 'gauge' ? drawGauge(sp, W, th, fm) : drawBullet(sp, W, th, fm);
    } catch (e) { res = null; }
    const typeLabel = lab(TYPES[TYPE_IDS.indexOf(type)].label);
    if (!res) {
      let Hh = Number(sp.height); if (!isNum(Hh) || Hh < 20) Hh = sp.mini ? 36 : 160;
      res = { svg: empty(W, Hh), H: Hh, items: [], legend: [], table: { head: [], rows: [] }, summary: lab(T.nodata) };
    }
    model = { items: res.items, serNames: res.serNames };
    res.svg.setAttribute('aria-label', [ttl || lab(T.untitled), typeLabel, res.summary].filter(Boolean).join('. '));
    res.svg.setAttribute('data-type', type);
    hideTip();
    if (svg) svg.remove();
    svg = res.svg; wrap.insertBefore(svg, tip);
    wrap.style.minHeight = res.H + 'px';
    legend.textContent = '';
    legend.style.display = res.legend.length ? '' : 'none';
    res.legend.forEach((l) => {
      const b = H('button', 'bch-lg' + (l.off ? ' off' : ''), legend); b.type = 'button';
      b.setAttribute('data-name', l.name); b.setAttribute('data-mode', l.mode); if (l.mode === 'hl') b.setAttribute('data-k', l.k);
      if (l.mode === 'toggle') b.setAttribute('aria-pressed', l.off ? 'false' : 'true');
      const sw = H('span', 'bch-sw', b); sw.style.background = l.color;
      H('span', 'bch-lgt', b, l.name || '–'); b.title = l.name;
      if (l.value) H('span', 'bch-lgv', b, l.value);
    });
    sr.textContent = '';
    const tb = H('table', '', sr);
    H('caption', '', tb, [ttl || lab(T.untitled), typeLabel].join(' · '));
    if (res.table.head.length) { const tr = H('tr', '', H('thead', '', tb)); res.table.head.forEach((h) => H('th', '', tr, h).setAttribute('scope', 'col')); }
    const tbd = H('tbody', '', tb);
    res.table.rows.forEach((r) => { const tr = H('tr', '', tbd); r.forEach((c, ci) => { const cell = H(ci === 0 ? 'th' : 'td', '', tr, c); if (ci === 0) cell.setAttribute('scope', 'row'); }); });
    const key = type + '|' + (sp.mini ? 1 : 0);
    const doAnim = animate !== false && key !== lastKey && !reduced();
    lastKey = key; lastW = W;
    root.classList.remove('bch-anim');
    if (doAnim) { void root.offsetWidth; root.classList.add('bch-anim'); clearTimeout(timer); timer = setTimeout(() => root.classList.remove('bch-anim'), 1100); }
  }

  // ----- observers -----
  let ro = null, mo = null;
  const onResize = () => { if (destroyed) return; cancelAnimationFrame(rafId); rafId = requestAnimationFrame(() => { if (!destroyed && Math.abs(hostW() - lastW) >= 1) draw(false); }); };
  if (typeof ResizeObserver !== 'undefined') { ro = new ResizeObserver(onResize); ro.observe(host); } else on(window, 'resize', onResize);
  const autoTheme = () => spec.theme !== 'dark' && spec.theme !== 'light';
  if (typeof MutationObserver !== 'undefined') { mo = new MutationObserver(() => { if (autoTheme()) draw(false); }); mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] }); }
  try { const mq = window.matchMedia('(prefers-color-scheme: light)'), h = () => { if (autoTheme()) draw(false); }; if (mq.addEventListener) { mq.addEventListener('change', h); offs.push(() => mq.removeEventListener('change', h)); } } catch (e) { /* no matchMedia */ }

  draw(true);
  return {
    update(next) { if (destroyed) return; spec = next || {}; hidden.clear(); draw(true); },
    destroy() {
      if (destroyed) return; destroyed = true;
      clearTimeout(timer); cancelAnimationFrame(rafId);
      if (ro) ro.disconnect();
      if (mo) mo.disconnect();
      offs.splice(0).forEach((f) => { try { f(); } catch (e) { /* ignore */ } });
      if (root.parentNode) root.parentNode.removeChild(root);
    },
  };
}

B.charts = { TYPES, render, compatible, convert, palette: (t) => PAL[t === 'light' ? 'light' : 'dark'].slice(), compactFormat: compact, bdFormat: defFmt('bd'), _squarify: squarify, _niceScale: niceScale };
})();
