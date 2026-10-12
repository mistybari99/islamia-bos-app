/* Islamia BOS · 3D glass icon set. BOS.icon(key, size) -> inline <svg> string.
   Style: translucent glass body (gradient fill + edge + top sheen) with an accent-coloured core, drawn in a 32x32 box.
   Colours come from CSS variables (--i3-*) set per theme in theme.css, so one string works in every theme.
   No external assets. To add an icon: add a record to DEF below: { g: glass shapes, c: accent core shapes, l: accent strokes, w: stroke width of l }.
   Shapes are bare SVG elements (no fill / stroke attributes). Keys are listed in docs/DESIGN_SYSTEM.md. */
(() => {
'use strict';
const B = (window.BOS = window.BOS || {});
const R = (x, y, w, h, r) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}"/>`;
const C = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}"/>`;
const P = (d) => `<path d="${d}"/>`;
const STAR = 'M16 3.5l3.9 8 8.8 1.2-6.4 6.2 1.6 8.8L16 23.4 8.1 27.7l1.6-8.8L3.3 12.7l8.8-1.2z';
const PIN = 'M16 29S6 20.5 6 13a10 10 0 0 1 20 0c0 7.5-10 16-10 16z';
const BELL = 'M16 3a2 2 0 0 1 2 2v.7A9 9 0 0 1 25 15v6l3 3H4l3-3v-6a9 9 0 0 1 7-9.3V5a2 2 0 0 1 2-2z';
const GEAR = 'M13.5 3h5l.8 3.4 2.3 1 3-1.8 3.5 3.5-1.8 3 1 2.3 3.4.8v5l-3.4.8-1 2.3 1.8 3-3.5 3.5-3-1.8-2.3 1-.8 3.4h-5l-.8-3.4-2.3-1-3 1.8-3.5-3.5 1.8-3-1-2.3L3 18.5v-5l3.4-.8 1-2.3-1.8-3 3.5-3.5 3 1.8 2.3-1z';
const DISC = C(16, 16, 12);

const DEF = {
  home: { g: P('M4 15 16 5l12 10v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z'), c: R(13, 17.5, 6, 10.5, 1.5) },
  box: { g: P('M16 4 27 9.5v13L16 28 5 22.5v-13z'), c: P('M16 4 27 9.5 16 15 5 9.5z'), l: P('M16 15v13'), w: 1.4 },
  bag: { g: P('M7 11h18l-1.5 16h-15z'), l: P('M11 14V9a5 5 0 0 1 10 0v5'), c: C(16, 19.5, 3) },
  list: { g: R(5, 4, 22, 24, 4), l: P('M10 11h12M10 16h12M10 21h7') },
  cart: { g: P('M7 10h21l-2.6 10H10z'), l: P('M3 5h4l3.2 15'), c: C(12, 25, 2.5) + C(23, 25, 2.5) },
  pos: { g: R(6, 3, 20, 26, 4), c: R(9.5, 6.5, 13, 7, 1.8), l: P('M11 19h2M15 19h2M19 19h2M11 24h2M15 24h2M19 24h2'), w: 2.2 },
  dues: { g: C(13, 10, 5) + P('M3 27c.7-6 5-9 10-9s9.3 3 10 9z'), c: C(24, 21, 6), l: P('M24 18v6M22.3 19.7h3.4'), w: 1.6 },
  money: { g: DISC, c: C(16, 16, 7), l: P('M18 13c-1-.9-4-.9-4 1s4 1.2 4 3.2-3.3 2.3-4.2 1M16 11v1.5M16 19.6V21'), w: 1.6 },
  chart: { g: R(5, 16, 5.5, 11, 1.5) + R(21.5, 12, 5.5, 15, 1.5), c: R(13.2, 5, 5.6, 22, 1.5), l: P('M3 29h26'), w: 1.6 },
  pie: { g: DISC, c: P('M16 16V4a12 12 0 0 1 12 12z') },
  warn: { g: P('M16 4 29 27H3z'), l: P('M16 12.5v7'), c: C(16, 23.2, 1.7) },
  alert: { g: P('M8 25v-8a8 8 0 0 1 16 0v8z') + R(5, 25, 22, 3.5, 1.5), c: C(16, 17, 3.5), l: P('M16 3.5v3M5.5 8l2 2M26.5 8l-2 2'), w: 1.8 },
  swap: { g: R(4, 9, 24, 14, 4), l: P('M21 12.5H11l3.5-3.5M11 19.5h10l-3.5 3.5'), w: 2 },
  unlock: { g: R(6, 14, 20, 14, 3.5), l: P('M10 14V9a6 6 0 0 1 11.5-2.4'), c: C(16, 21, 2.4) },
  lock: { g: R(6, 14, 20, 14, 3.5), l: P('M10 14v-3.5a6 6 0 0 1 12 0V14'), c: C(16, 21, 2.4) },
  hash: { g: R(4, 4, 24, 24, 5), l: P('M12.5 9l-2 14M21.5 9l-2 14M8 13.5h16M7.5 19h16'), w: 1.8 },
  users: { g: C(11.5, 11, 4.6) + P('M2.5 26c.6-5.5 4.4-8 9-8s8.4 2.5 9 8z'), c: C(22.5, 12, 3.8) + P('M17.5 19.5c1.2-.8 3-1.2 5-1.2 3.7 0 6.3 2 6.8 6.7H25') },
  user: { g: P('M4 28c.8-7 5.6-10 12-10s11.2 3 12 10z'), c: C(16, 10, 5.5) },
  matrix: { g: R(4, 4, 10, 10, 2.5) + R(18, 18, 10, 10, 2.5), c: R(18, 4, 10, 10, 2.5) + R(4, 18, 10, 10, 2.5) },
  sliders: { g: R(3, 5, 26, 22, 5), l: P('M8 12h16M8 20h16'), c: C(12, 12, 3) + C(21, 20, 3), w: 1.6 },
  gear: { g: P(GEAR), c: C(16, 16, 4.6) },
  shield: { g: P('M16 3 27 7v8c0 7-4.6 11.6-11 14C9.6 26.6 5 22 5 15V7z'), l: P('M11 15.5l3.6 3.6 6.9-7.2'), w: 2.2 },
  rules: { g: R(5, 4, 22, 24, 4), l: P('M9.5 10.5l2 2 3.6-3.8M9.5 19l2 2 3.6-3.8M19 11h5M19 19.5h5'), w: 1.8 },
  clock: { g: DISC, l: P('M16 9v7.5l5 3'), w: 2.2 },
  download: { g: P('M5 20v5a3 3 0 0 0 3 3h16a3 3 0 0 0 3-3v-5z'), l: P('M16 4v14M10.5 13 16 18.5 21.5 13'), w: 2.4 },
  upload: { g: P('M5 20v5a3 3 0 0 0 3 3h16a3 3 0 0 0 3-3v-5z'), l: P('M16 18V4M10.5 9.5 16 4l5.5 5.5'), w: 2.4 },
  store: { g: P('M5 14v14h22V14'), c: P('M3 13 6 5h20l3 8a4 4 0 0 1-8 0 4 4 0 0 1-5 0 4 4 0 0 1-5 0 4 4 0 0 1-8 0z') },
  pin: { g: P(PIN), c: C(16, 13, 4) },
  pinset: { g: P(PIN), c: C(16, 13, 4), l: P('M13 13h6'), w: 1.8 },
  doc: { g: P('M7 3h13l6 6v20H7z'), c: P('M20 3v6h6z'), l: P('M11 15h10M11 20h10M11 25h6'), w: 1.8 },
  plus: { g: DISC, l: P('M16 9.5v13M9.5 16h13'), w: 2.6 },
  edit: { g: P('M5 27l2-7L21 6l5 5L12 25z'), c: P('M21 6l5 5 2-2a2.1 2.1 0 0 0 0-3l-2-2a2.1 2.1 0 0 0-3 0z') },
  search: { g: C(14, 14, 9), c: C(14, 14, 4.3), l: P('M21 21l7 7'), w: 2.8 },
  filter: { g: P('M4 6h24l-9 11v9l-6-3v-6z'), c: P('M9 6h14l-3 4H12z') },
  more: { g: R(10, 3, 12, 26, 6), c: C(16, 9, 2) + C(16, 16, 2) + C(16, 23, 2) },
  check: { g: DISC, l: P('M10 16.5l4 4 8-9'), w: 3 },
  close: { g: DISC, l: P('M11 11l10 10M21 11 11 21'), w: 2.8 },
  info: { g: DISC, l: P('M16 14.5v7.5'), c: C(16, 10, 1.9), w: 2.6 },
  print: { g: R(4, 11, 24, 12, 3.5) + P('M9 11V4h14v7'), c: R(9, 19, 14, 9, 1.5) },
  camera: { g: P('M3 11a3 3 0 0 1 3-3h3l2-3h10l2 3h3a3 3 0 0 1 3 3v13a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3z'), c: C(16, 17, 5.5) },
  barcode: { g: R(3, 6, 26, 20, 4), l: P('M8 10v12M12 10v12M20 10v12M24 10v12'), c: R(14.4, 10, 3.2, 12, 1), w: 1.5 },
  calendar: { g: R(4, 6, 24, 22, 4), c: P('M4 10a4 4 0 0 1 4-4h16a4 4 0 0 1 4 4v3H4z'), l: P('M10 3v5M22 3v5'), w: 2 },
  truck: { g: R(2, 8, 17, 14, 3) + P('M19 13h5l5 5v4H19z'), c: C(9, 24, 3) + C(23, 24, 3) },
  factory: { g: P('M3 28V13l8 5v-5l8 5V6h6v22z'), c: R(7, 22, 3, 3, .6) + R(14, 22, 3, 3, .6) + R(21, 22, 3, 3, .6) },
  chef: { g: P('M9 16a5 5 0 0 1 1-9.8A6 6 0 0 1 21 6a5 5 0 0 1 2 9.9V25H9z'), c: R(9, 21, 14, 5, 1.5) },
  book: { g: P('M5 6a3 3 0 0 1 3-3h17v22H8a3 3 0 0 0-3 3z'), c: P('M19 3v9l3-2 3 2V3z'), l: P('M10 9h5M10 14h7'), w: 1.6 },
  tool: { g: P('M20 4a7 7 0 0 0-6.6 9.3L4 22.7 9.3 28l9.4-9.4A7 7 0 0 0 28 12l-4.2 4.2-4-1-1-4L23 7a7 7 0 0 0-3-3z'), c: C(8.4, 23.6, 1.8) },
  stamp: { g: P('M12 4h8v8l4 5H8l4-5z') + R(5, 19, 22, 4, 1.5), c: R(5, 25, 22, 3.5, 1.5) },
  bell: { g: P(BELL), c: P('M12.5 26.5a3.5 3.5 0 0 0 7 0z') },
  star: { g: P(STAR), c: C(16, 16, 3.6) },
  history: { g: DISC, l: P('M16 9v7.5l5 3M5 8v6h6'), w: 2.2 },
  tag: { g: P('M4 5a1 1 0 0 1 1-1h11l12 12-12 12L4 16z'), c: C(10.5, 10.5, 2.4) },
  link: { g: R(3, 10, 14, 9, 4.5), c: R(15, 14, 14, 9, 4.5) },
  scale: { g: R(4, 23, 24, 5, 2), l: P('M16 5v18M6 9.5h20'), c: P('M3 16l3-6.5 3 6.5a3 3 0 0 1-6 0zM23 16l3-6.5 3 6.5a3 3 0 0 1-6 0z'), w: 1.8 },
  menu: { g: R(4, 5, 24, 22, 6), l: P('M10 11h12M10 16h12M10 21h12'), w: 2.4 },
  chev: { g: '', l: P('M12 6l10 10-10 10'), w: 3 },
  sell: { g: P('M5 12h22l-2 15H7z'), l: P('M11 12V9.5a5 5 0 0 1 10 0V12'), c: P('M16 15.5v7M12.5 19h7'), w: 2 },
  x: { g: '', l: P('M8 8l16 16M24 8L8 24'), w: 3 },
};
// aliases: record ids / old icon keys / actions -> definition above
const ALIAS = {
  items: 'bag', products: 'bag', lists: 'list', stock: 'box', assets: 'tool', asset: 'tool', purchase: 'cart', payables: 'money', suppliers: 'store', supplier: 'store',
  recipes: 'chef', recipe: 'chef', salereturn: 'swap', return: 'swap', itemreq: 'swap', invoice: 'print', daybook: 'book', ledgerlinks: 'link', itemmap: 'link', link: 'link',
  exceptions: 'warn', warning: 'warn', emergency: 'alert', releases: 'unlock', numaudit: 'hash', pending: 'stamp', approval: 'stamp', changes: 'edit', outbox: 'upload',
  reports: 'chart', report: 'chart', biz: 'pie', brandpnl: 'pie', discounts: 'tag', itemtypes: 'tag', itemimport: 'download', backup: 'download', bulkitems: 'bag', salary: 'money',
  staff: 'users', me: 'user', matrix: 'matrix', control: 'sliders', rollout: 'sliders', rulehub: 'shield', rules: 'rules', settings: 'gear', settings2: 'sliders', logs: 'history',
  locations: 'pin', location: 'pin', locset: 'pinset', locsheet: 'pinset', control2: 'sliders', camera: 'camera', cash: 'money', expense: 'money', transfer: 'truck', favourite: 'star',
  user_: 'user', cashier: 'pos', register: 'pos', report_chart: 'chart', approvalstamp: 'stamp', checkmark: 'check', times: 'close', dots: 'more', kebab: 'more', sale: 'pos',
  'settings2/units': 'scale', units: 'scale', 'purchase/new': 'plus', 'items/new': 'plus', add: 'plus', 'purchase/return': 'swap', calendar: 'calendar', clock: 'clock',
  // the 13 drawer categories
  'g:dash': 'home', 'g:item': 'bag', 'g:stock': 'box', 'g:purch': 'cart', 'g:factory': 'factory', 'g:sale': 'sell', 'g:cust': 'dues', 'g:acc': 'money', 'g:appr': 'stamp',
  'g:reports': 'chart', 'g:people': 'users', 'g:loc': 'pin', 'g:settings': 'gear', 'g:cust2': 'dues',
};
let seq = 0;
const resolve = (key) => (DEF[key] ? key : ALIAS[key] && DEF[ALIAS[key]] ? ALIAS[key] : null);
function icon(key, size) {
  const k = resolve(key); if (!k) return '';
  const d = DEF[k], n = 'i3' + (++seq).toString(36), s = Number(size) > 0 ? Number(size) : 22;
  const shade = d.g ? `<g style="fill:url(#${n}h);stroke:none">${d.g}</g>` : '';
  return `<svg class="i3 i3-${k}" viewBox="0 0 32 32" width="${s}" height="${s}" aria-hidden="true" focusable="false">`
    + `<defs><linearGradient id="${n}g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" style="stop-color:var(--i3-g1);stop-opacity:var(--i3-ga1)"/><stop offset="1" style="stop-color:var(--i3-g2);stop-opacity:var(--i3-ga2)"/></linearGradient>`
    + `<linearGradient id="${n}c" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(--i3-c1)"/><stop offset="1" style="stop-color:var(--i3-c2)"/></linearGradient>`
    + `<linearGradient id="${n}h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(--i3-hi);stop-opacity:var(--i3-hia)"/><stop offset=".55" style="stop-color:var(--i3-hi);stop-opacity:0"/></linearGradient></defs>`
    + (d.g ? `<g style="fill:url(#${n}g);stroke:var(--i3-edge)" stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round">${d.g}</g>${shade}` : '')
    + (d.c ? `<g style="fill:url(#${n}c);stroke:var(--i3-core-edge)" stroke-width=".7" stroke-linejoin="round">${d.c}</g>` : '')
    + (d.l ? `<g style="fill:none;stroke:var(--i3-line)" stroke-width="${d.w || 2.2}" stroke-linecap="round" stroke-linejoin="round">${d.l}</g>` : '')
    + '</svg>';
}
icon.has = (key) => !!resolve(key);
icon.keys = () => Object.keys(DEF).concat(Object.keys(ALIAS));
B.icon = icon;
})();
