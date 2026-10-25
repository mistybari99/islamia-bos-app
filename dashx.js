/* Islamia BOS · Owner dashboard (#/dashx, step Dash). NEW file. Needs web/charts.js (B.charts: TYPES, render, compatible, convert) and web/dashx_metrics.js.
   Tiles on a 2-column grid (phone) / 4-6 columns (tablet). Every tile: title, metric picker (bottom sheet), a row of 10 chart-type buttons (only the types that fit the data are enabled),
   refresh and a menu (rename, duplicate, remove, size, target, full screen). KPI tiles: value + change vs the previous period + sparkline.
   Re-order by long-press-and-drag on touch (250 ms), by mouse drag, or with the up / down buttons in "Edit layout" mode.
   The layout (order, metric, chart type, size, period, location) is saved per person: server phase104 (dash_layout_get / dash_layout_save, debounced) + this phone (localStorage fallback).
   Every tile fails soft ("No data"), loads only when it scrolls into view, shares one server call per source (60 s cache) and stops on leaving the screen. Up to 12 tiles. data-act prefix: dx_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B || !B.dashx_metrics) return;
const { sb, S, esc, toast, shell, H, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab, MX = B.dashx_metrics;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
const MAX_TILES = 12, SAVE_MS = () => (window.__DX_SAVE_MS === 0 ? 0 : Number(window.__DX_SAVE_MS) || 800), PRESS_MS = 250;

// ---------- texts ----------
const X = {
  title: L('মালিকের ড্যাশবোর্ড', 'Owner dashboard', 'Owner dashboard'), open: L('ড্যাশবোর্ড খুলুন', 'Open dashboard', 'Dashboard খুলুন'),
  edit: L('লেআউট সাজান', 'Edit layout', 'Layout সাজান'), done: L('হয়েছে', 'Done', 'Done'), add: L('টাইল যোগ', 'Add tile', 'Tile যোগ'), reset: L('ডিফল্টে ফেরান', 'Reset to default', 'Default-এ ফেরান'),
  refresh_all: L('সব নতুন করুন', 'Refresh all', 'সব refresh'), refresh: L('নতুন করুন', 'Refresh', 'Refresh'), nodata: L('তথ্য নেই', 'No data', 'No data'), retry: L('আবার চেষ্টা', 'Try again', 'আবার try'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), period: L('সময়', 'Period', 'Period'), from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), loc_all: L('সব লোকেশন', 'All locations', 'সব location'),
  loc: L('লোকেশন', 'Location', 'Location'), rename: L('নাম বদলান', 'Rename', 'Rename'), remove: L('সরান', 'Remove', 'Remove'), dup: L('কপি করুন', 'Duplicate', 'Duplicate'), size: L('আকার', 'Size', 'Size'),
  full: L('পুরো স্ক্রিন', 'Full screen', 'Full screen'), close: L('বন্ধ করুন', 'Close', 'Close'), target: L('লক্ষ্য / সীমা (গেজ ও বুলেটের জন্য)', 'Target / limit (for gauge and bullet)', 'Target / limit (gauge ও bullet-এর জন্য)'),
  name: L('নাম', 'Name', 'Name'), save: L('সেভ', 'Save', 'Save'), metric: L('কী দেখাবে', 'Choose what to show', 'কী দেখাবে'), tile_menu: L('টাইলের মেনু', 'Tile menu', 'Tile menu'),
  up: L('উপরে সরান', 'Move up', 'Move up'), down: L('নিচে সরান', 'Move down', 'Move down'), vs: L('আগের সময়ের তুলনায়', 'vs previous period', 'আগের সময়ের তুলনায়'),
  saved: L('সংরক্ষিত', 'Saved', 'Saved'), local: L('শুধু এই ফোনে সংরক্ষিত', 'Saved on this phone only', 'শুধু এই phone-এ saved'), max: L('সর্বোচ্চ ১২টি টাইল', 'Up to 12 tiles', 'সর্বোচ্চ 12টি tile'),
  nocharts: L('চার্ট লোড হয়নি', 'Charts are not loaded', 'Charts load হয়নি'), search: L('খুঁজুন…', 'Search…', 'Search…'), kpi: L('সংখ্যা (KPI)', 'KPI number', 'KPI number'),
  moved: L('সরানো হয়েছে, অবস্থান', 'Moved to position', 'Moved to position'), hint: L('টাইল ধরে রেখে টেনে সাজান, অথবা "লেআউট সাজান" চাপুন', 'Press and hold a tile to drag it, or use "Edit layout"', 'Tile ধরে রেখে টেনে সাজান, অথবা "Layout সাজান" চাপুন'),
  confirm_reset: L('ড্যাশবোর্ড ডিফল্টে ফিরবে। ঠিক আছে?', 'The dashboard goes back to the default. Continue?', 'Dashboard default-এ ফিরবে। ঠিক আছে?'), confirm_rm: L('এই টাইল সরাবেন?', 'Remove this tile?', 'এই tile সরাবেন?'),
  badnum: L('সংখ্যা ঠিক নয়', 'That number is not valid', 'Number ঠিক নয়'), empty: L('কোনো টাইল নেই — "টাইল যোগ" চাপুন', 'No tiles - tap "Add tile"', 'কোনো tile নেই — "Tile যোগ" চাপুন'),
  sz_S: L('ছোট', 'Small', 'Small'), sz_M: L('মাঝারি', 'Medium', 'Medium'), sz_L: L('বড়', 'Large', 'Large'),
  w_value: L('একটি সংখ্যা লাগে', 'Needs a single number', 'একটি number লাগে'), w_series: L('সময় বা একাধিক সারি লাগে', 'Needs a series over time', 'Time series লাগে'),
  w_parts: L('অংশের তালিকা লাগে', 'Needs a list of parts', 'অংশের list লাগে'), w_list: L('সারি বা তালিকা লাগে', 'Needs a series or a list', 'Series বা list লাগে'),
  why: L('এই তথ্যের জন্য নয়', 'Not available for this data', 'এই data-র জন্য নয়'),
  none_found: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'), prev: L('আগের সময়', 'Previous', 'Previous'),
};
const T = (k) => lab(X[k]);

// ---------- helpers ----------
const jget = (s, d) => { try { const v = JSON.parse(s); return v == null ? d : v; } catch (e) { return d; } };
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const lsKey = () => 'bos_dashx_' + uid();
const lsGet = () => { try { return window.localStorage.getItem(lsKey()); } catch (e) { return null; } };
const lsSet = (v) => { try { window.localStorage.setItem(lsKey(), v); } catch (e) { /* blocked: the server copy still works */ } };
const gid = () => 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
const N = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const INV = new Set(['voids', 'discounts', 'cogs', 'cust_dues', 'supp_dues', 'total_expense', 'exceptions_open', 'low_stock', 'cost_wait', 'no_sale', 'ledger_problems', 'expiring']);   // up is bad
const SIZES = ['S', 'M', 'L'];
const HEIGHT = { S: 112, M: 176, L: 264 };
const tl = (x) => { if (!x) return ''; if (typeof x === 'string') return x; try { return lab(x) || x.en || x.id || ''; } catch (e) { return ''; } };
const types = () => (B.charts && Array.isArray(B.charts.TYPES) ? B.charts.TYPES : []);
const tType = (id) => types().find((x) => x.id === id);
const ST = { layout: null, data: {}, inst: {}, edit: false, ctrl: null, saveT: null, saveState: '', io: null, dirty: false, caps: null, client: gid(), seq: 0 };

// ---------- layout ----------
const metricOk = (id) => !!MX.get(id);
function defaults(caps) {
  const raw = [['sales_total', 'S', 'kpi'], ['gross_profit', 'S', 'kpi'], ['cust_dues', 'S', 'kpi'], ['sales_trend', 'M', 'line'], ['sales_by_cat', 'M', 'donut'], ['top_items', 'M', 'bar'],
    ['stock_value_cat', 'M', 'treemap'], ['expense_by_head', 'M', 'pie'], ['dues_mix', 'M', 'stacked_bar'], ['orders_by_channel', 'M', 'column'], ['alerts_overview', 'M', 'bar']];
  const tiles = raw.filter((r) => !caps || MX.allowed(MX.get(r[0]), caps)).map((r, i) => ({ id: 'd' + (i + 1), metric: r[0], size: r[1], type: r[2] }));
  return { v: 1, period: '7d', loc: null, tiles, u: 0 };
}
function norm(x, caps) {
  if (!x || typeof x !== 'object') return null;
  const per = MX.PERIODS.some((p) => p.id === x.period) ? x.period : '7d';
  const out = { v: 1, period: per, loc: x.loc === null || x.loc === undefined || x.loc === '' ? null : String(x.loc), tiles: [], u: N(x.u) };
  if (per === 'custom' && x.custom && x.custom.from && x.custom.to) out.custom = { from: String(x.custom.from).slice(0, 10), to: String(x.custom.to).slice(0, 10) };
  else if (per === 'custom') out.period = '7d';
  const seen = new Set();
  (Array.isArray(x.tiles) ? x.tiles : []).forEach((t) => {
    if (!t || typeof t !== 'object' || !metricOk(t.metric) || out.tiles.length >= MAX_TILES) return;
    const m = MX.get(t.metric); let id = typeof t.id === 'string' && t.id ? t.id.slice(0, 30) : gid(); while (seen.has(id)) id = gid(); seen.add(id);
    const ty = t.type === 'kpi' && m.shape === 'value' ? 'kpi' : (tType(t.type) || (!types().length && typeof t.type === 'string') ? t.type : m.type);
    const o = { id, metric: t.metric, size: SIZES.includes(t.size) ? t.size : 'M', type: ty };
    if (typeof t.title === 'string' && t.title.trim()) o.title = t.title.trim().slice(0, 60);
    if (Number.isFinite(Number(t.target)) && t.target !== null && t.target !== '' && t.target !== undefined) o.target = Number(t.target);
    out.tiles.push(o);
  });
  return out;
}
const visibleTiles = () => ST.layout.tiles.filter((t) => { const m = MX.get(t.metric); return m && MX.allowed(m, ST.caps); });

async function loadLayout() {
  const caps = ST.caps, local = norm(jget(lsGet(), null), caps);
  let server = null, serverOk = false;
  try {
    const r = await Promise.race([sb.rpc('dash_layout_get'), new Promise((_, rej) => setTimeout(() => rej(new Error('dx_timeout')), Number(window.__DX_CAP_MS) || 2000))]);
    if (r && !r.error) { serverOk = true; server = norm(r.data && r.data.layout, caps); }
  } catch (e) { /* phase104 not pasted / offline: this phone's copy is used */ }
  ST.serverOk = serverOk;
  let pick = null;
  if (server && local) pick = local.u > server.u ? local : server;
  else pick = server || local;
  ST.layout = pick || Object.assign(defaults(caps), { u: 0 });
  if (!pick) ST.layout.u = 0;
  if (pick === local && local && serverOk && (!server || local.u > server.u)) persist(true);   // this phone is newer: push it
  else if (pick === server) lsSet(JSON.stringify(ST.layout));
}
function persist(quiet) {
  ST.layout.u = Date.now(); lsSet(JSON.stringify(ST.layout));
  clearTimeout(ST.saveT); ST.dirty = true;
  const go = async () => {
    ST.saveT = null; const snap = JSON.parse(JSON.stringify(ST.layout));
    try { const r = await sb.rpc('dash_layout_save', { p_layout: snap, p_client: ST.client }); ST.saveState = r && r.error ? 'local' : 'saved'; } catch (e) { ST.saveState = 'local'; }
    ST.dirty = false; drawStatus();
  };
  if (SAVE_MS() === 0) go(); else ST.saveT = setTimeout(go, SAVE_MS());
  if (!quiet) drawStatus();
}
function drawStatus() { const e = $('#dx_status'); if (e) e.textContent = ST.saveState === 'saved' ? T('saved') : ST.saveState === 'local' ? T('local') : ''; }

// ---------- data ----------
const tileById = (id) => ST.layout.tiles.find((t) => t.id === id);
const tileTitle = (t) => t.title || lab((MX.get(t.metric) || {}).label);
function rangeNow() { return MX.range(ST.layout.period, ST.layout.custom); }
async function loadTile(id, force) {
  const t = tileById(id); if (!t) return; const m = MX.get(t.metric); if (!m) return;
  const key = ++ST.seq; const cur = ST.data[id] = { state: 'loading', key, metric: t.metric }; paintTile(id);
  try {
    const d = await MX.run(m, rangeNow(), ST.layout.loc, ST.ctrl && ST.ctrl.signal);
    if (ST.data[id] !== cur) return;
    if (!hasData(m, d)) { cur.state = 'empty'; } else { cur.state = 'ok'; cur.d = d; }
  } catch (e) { if (e && e.aborted) return; if (ST.data[id] !== cur) return; cur.state = 'error'; }
  paintTile(id);
}
function hasData(m, d) {
  if (!d) return false;
  if (m.shape === 'value') return d.value !== null && d.value !== undefined && Number.isFinite(Number(d.value));
  if (m.shape === 'slices') return Array.isArray(d.slices) && d.slices.length > 0 && (d.keepZero || d.slices.some((s) => N(s.value) > 0));
  return Array.isArray(d.series) && d.series.some((s) => (s.points || []).some((p) => N(p.y) !== 0));
}
function loadAll(force) {
  if (force) MX.clearCache();
  visibleTiles().forEach((t) => { if (!tileEl(t.id)) return; if (ST.seen.has(t.id)) loadTile(t.id, force); else { delete ST.data[t.id]; paintTile(t.id); } });
}

// ---------- specs ----------
const niceMax = (v) => { if (!(v > 0)) return 1; const p = Math.pow(10, Math.floor(Math.log10(v))), f = v / p; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p; };
function cssVar(n, d) { try { return getComputedStyle(document.documentElement).getPropertyValue(n).trim() || d; } catch (e) { return d; } }
function baseSpec(t, m, d) {
  const sp = { type: 'line', format: MX.fmtOf(m, true), theme: 'auto', height: HEIGHT[t.size] || HEIGHT.M, mini: t.size === 'S' };
  if (m.shape === 'series') sp.series = d.series.map((s) => ({ name: s.name, points: (s.points || []).map((p) => ({ x: p.x, y: N(p.y) })) }));
  else if (m.shape === 'slices') sp.slices = d.slices.map((s) => ({ label: s.label, value: N(s.value) }));
  else {
    const mx = Math.max(N(d.value), N(d.prev), N(t.target));
    sp.value = N(d.value); sp.min = d.min !== undefined ? d.min : 0; sp.max = d.max !== undefined ? d.max : niceMax(t.target ? Math.max(N(t.target) * 1.25, N(d.value)) : mx * 1.25);
    if (t.target) { sp.target = N(t.target); sp.ranges = [{ to: sp.target * 0.5, color: cssVar('--bad', '#ef4444') }, { to: sp.target * 0.8, color: cssVar('--warn', '#f59e0b') }, { to: sp.max, color: cssVar('--ok', '#22c55e') }]; }
  }
  return sp;
}
function shapeSpec(m) {
  const pts = [{ x: 'a', y: 1 }, { x: 'b', y: 2 }];
  return m.shape === 'series' ? { type: 'line', series: [{ name: 's', points: pts }] } : m.shape === 'slices' ? { type: 'bar', slices: [{ label: 'a', value: 1 }, { label: 'b', value: 2 }] } : { type: 'gauge', value: 1, min: 0, max: 2 };
}
function compat(spec) { try { const r = B.charts && B.charts.compatible ? B.charts.compatible(spec) : null; return Array.isArray(r) ? r : []; } catch (e) { return []; } }
const whyNot = (id, m) => {
  const need = id === 'gauge' || id === 'bullet' ? 'w_value' : id === 'line' || id === 'area' || id === 'stacked_bar' ? 'w_series' : id === 'pie' || id === 'donut' || id === 'treemap' ? 'w_parts' : 'w_list';
  return T('why') + ' - ' + T(need);
};

// ---------- tile html ----------
const spark = (pts) => {
  if (!pts || pts.length < 2) return '';
  const ys = pts.map((p) => N(p.y)), lo = Math.min(...ys), hi = Math.max(...ys), w = 100, h = 30, sp = hi - lo || 1;
  const xy = ys.map((y, i) => [(i / (ys.length - 1)) * w, h - 3 - ((y - lo) / sp) * (h - 6)]);
  const line = xy.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  return `<svg class="dx-sp" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" aria-hidden="true"><path d="${line} L${w} ${h} L0 ${h} Z" class="a"/><path d="${line}" class="l"/></svg>`;
};
function kpiHtml(t, m, d) {
  const f = MX.fmtOf(m, false), pv = d.prev, hasPrev = pv !== undefined && pv !== null && N(pv) > 0 && ST.layout.period !== undefined;
  const pct = hasPrev ? ((N(d.value) - N(pv)) / N(pv)) * 100 : null, up = pct !== null && pct >= 0, bad = INV.has(m.id) ? up : !up;
  const delta = pct === null ? '' : `<div class="dx-dl ${Math.abs(pct) < 0.05 ? 'z' : bad ? 'bad' : 'ok'}"><span aria-hidden="true">${up ? '▲' : '▼'}</span> ${esc((Math.round(Math.abs(pct) * 10) / 10) + '%')} <small>${esc(T('vs'))}</small></div>`;
  return `<div class="dx-kpi"><div class="dx-kv">${esc(f(d.value))}</div>${delta}${d.note ? `<div class="dx-note">${esc(d.note)}</div>` : ''}${spark(d.spark)}</div>`;   /* bos112: optional note under the value (provisional profit) */
}
function typeRow(t, m, spec, enabled) {
  const ts = types(); const btn = (id, icon, label, on, ok, why) => `<button type="button" class="dx-tb ${on ? 'on' : ''} ${ok ? '' : 'off'}" data-act="dx_type" data-id="${esc(t.id)}" data-v="${esc(id)}" aria-pressed="${on ? 'true' : 'false'}" ${ok ? '' : 'aria-disabled="true"'} title="${esc(ok ? label : label + ' - ' + why)}" aria-label="${esc(ok ? label : label + ' - ' + why)}">${icon}</button>`;
  let h = '';
  if (m.shape === 'value') h += btn('kpi', '<span class="dx-ic">123</span>', T('kpi'), t.type === 'kpi', true, '');
  ts.forEach((x) => {
    const ok = enabled.includes(x.id); const ic = typeof x.icon === 'string' && x.icon.trim().charAt(0) === '<' ? x.icon : `<span class="dx-ic">${esc(x.icon || x.id.slice(0, 2))}</span>`;
    h += btn(x.id, ic, tl(x.label) || x.id, t.type === x.id, ok, ok ? '' : whyNot(x.id, m));
  });
  return h;
}
function tileHtml(t) {
  const m = MX.get(t.metric);
  return `<section class="dx-t" data-id="${esc(t.id)}" data-size="${esc(t.size)}" data-m="${esc(t.metric)}" aria-label="${esc(tileTitle(t))}">
    <div class="dx-hd"><span class="dx-grip" aria-hidden="true"><svg viewBox="0 0 12 18" width="12" height="18"><g fill="currentColor"><circle cx="3" cy="3" r="1.5"/><circle cx="9" cy="3" r="1.5"/><circle cx="3" cy="9" r="1.5"/><circle cx="9" cy="9" r="1.5"/><circle cx="3" cy="15" r="1.5"/><circle cx="9" cy="15" r="1.5"/></g></svg></span>
      <button type="button" class="dx-ti" data-act="dx_pick" data-id="${esc(t.id)}" title="${esc(T('metric'))}"><span class="dx-tt">${esc(tileTitle(t))}</span><span aria-hidden="true">▾</span></button>
      <button type="button" class="dx-ib" data-act="dx_menu" data-id="${esc(t.id)}" aria-label="${esc(T('tile_menu'))}">⋮</button></div>
    <div class="dx-rw"><div class="dx-ty" role="group" aria-label="${esc(m ? lab(m.label) : '')}"></div><button type="button" class="dx-ib dx-rf" data-act="dx_refresh" data-id="${esc(t.id)}" aria-label="${esc(T('refresh'))}">↻</button></div>
    <div class="dx-bd"></div>
    <div class="dx-ed"><button type="button" data-act="dx_up" data-id="${esc(t.id)}" aria-label="${esc(T('up'))}">▲</button><button type="button" data-act="dx_dn" data-id="${esc(t.id)}" aria-label="${esc(T('down'))}">▼</button><button type="button" data-act="dx_dup" data-id="${esc(t.id)}" aria-label="${esc(T('dup'))}">⧉</button><button type="button" data-act="dx_rm" data-id="${esc(t.id)}" aria-label="${esc(T('remove'))}">✕</button></div>
  </section>`;
}
const tileEl = (id) => $(`#dx_grid .dx-t[data-id="${CSS.escape(id)}"]`);
function destroyInst(id) { const i = ST.inst[id]; if (i) { try { i.chart && i.chart.destroy(); } catch (e) { /* ignore */ } delete ST.inst[id]; } }

function paintTile(id) {
  const t = tileById(id), el = tileEl(id); if (!t || !el) return; const m = MX.get(t.metric); if (!m) return;
  const st = ST.data[id], bd = $('.dx-bd', el), ty = $('.dx-ty', el);
  el.dataset.size = t.size; el.dataset.m = t.metric; el.dataset.state = st ? st.state : 'idle';
  $('.dx-tt', el).textContent = tileTitle(t);
  const spec0 = st && st.state === 'ok' ? baseSpec(t, m, st.d) : null;
  const enabled = compat(spec0 || shapeSpec(m));
  if (types().length || m.shape === 'value') ty.innerHTML = typeRow(t, m, spec0, enabled); else ty.innerHTML = '';
  ty.hidden = !ty.innerHTML;
  if (!st || st.state === 'loading') { destroyInst(id); bd.innerHTML = `<div class="dx-sk" role="status" aria-label="${esc(T('loading'))}"></div>`; return; }
  if (st.state !== 'ok') { destroyInst(id); bd.innerHTML = `<div class="dx-nd" data-state="nodata"><b>${esc(T('nodata'))}</b><button type="button" class="dx-lk" data-act="dx_refresh" data-id="${esc(t.id)}">${esc(T('retry'))}</button></div>`; return; }
  if (t.type === 'kpi' && m.shape === 'value') { destroyInst(id); bd.innerHTML = kpiHtml(t, m, st.d); return; }
  if (!B.charts || typeof B.charts.render !== 'function') { destroyInst(id); bd.innerHTML = `<div class="dx-nd"><b>${esc(T('nocharts'))}</b></div>`; return; }
  let type = t.type === 'kpi' ? m.type : t.type;
  if (!enabled.includes(type)) type = enabled.includes(m.type) ? m.type : (enabled[0] || type);
  let spec; try { spec = B.charts.convert ? B.charts.convert(spec0, type) : Object.assign({}, spec0, { type }); } catch (e) { spec = Object.assign({}, spec0, { type }); }
  if (!spec) spec = Object.assign({}, spec0, { type });
  let i = ST.inst[id];
  if (i && i.type === type && i.host && bd.contains(i.host)) { try { i.chart.update(spec); i.spec = spec; return; } catch (e) { destroyInst(id); i = null; } }
  destroyInst(id); bd.innerHTML = '<div class="dx-ch"></div>'; const host = $('.dx-ch', bd);
  try { ST.inst[id] = { chart: B.charts.render(host, spec), type, host, spec }; } catch (e) { bd.innerHTML = `<div class="dx-nd"><b>${esc(T('nodata'))}</b></div>`; }
}

// ---------- page ----------
function css() {
  if (document.getElementById('dx_css')) return; const s = document.createElement('style'); s.id = 'dx_css';
  s.textContent = `#dx_root{--dx-a:#ff8a3d;--dx-b:#22d3ee;--dx-tile:var(--card,#fff);--dx-bd:var(--hair,rgba(0,0,0,.12));--dx-ink:var(--ink,#222);--dx-mut:var(--muted,#777);--dx-r:16px;--dx-sh:0 1px 3px rgba(0,0,0,.08);min-width:0}
:root[data-theme="dark"] #dx_root{--dx-tile:linear-gradient(155deg,#2d2f37 0%,#202228 55%,#1a1b20 100%);--dx-bd:rgba(255,255,255,.09);--dx-sh:0 6px 16px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.07)}
#dx_root [hidden]{display:none!important}#dx_root .dx-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:2px 0 10px}#dx_root .dx-bar select,#dx_root .dx-bar input{font-size:16px;min-height:44px;max-width:100%;min-width:0}
#dx_root .dx-chips{display:flex;gap:6px;flex-wrap:wrap;width:100%}#dx_root .dx-chip{min-height:44px;padding:0 14px;border-radius:22px;border:1px solid var(--dx-bd);background:var(--dx-tile);color:var(--dx-ink);font-size:13px;box-shadow:none}
#dx_root .dx-chip[aria-pressed="true"]{border-color:var(--dx-a);color:var(--dx-a);background:rgba(255,138,61,.12);font-weight:700}
#dx_root .dx-cust{display:flex;gap:8px;width:100%;flex-wrap:wrap}#dx_root .dx-cust label{flex:1 1 130px;min-width:0;display:flex;flex-direction:column;font-size:12px;color:var(--dx-mut)}
#dx_root .dx-act{display:flex;gap:8px;flex-wrap:wrap;width:100%;align-items:center}#dx_root .dx-act button{min-height:44px;min-width:44px;font-size:13px}#dx_root .dx-st{font-size:12px;color:var(--dx-mut);margin-inline-start:auto}
#dx_root .dx-hint{font-size:12px;color:var(--dx-mut);margin:0 0 8px}
#dx_grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;align-items:start}
.dx-t{position:relative;min-width:0;overflow:hidden;border:1px solid var(--dx-bd);border-radius:var(--dx-r);background:var(--dx-tile);box-shadow:var(--dx-sh);color:var(--dx-ink);grid-column:span 1;display:flex;flex-direction:column}
.dx-t[data-size="M"],.dx-t[data-size="L"]{grid-column:span 2}
.dx-hd{display:flex;align-items:center;gap:2px;min-height:44px;padding:0 2px 0 8px;cursor:grab;touch-action:pan-y;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}
.dx-grip{flex:none;display:inline-flex;align-items:center;justify-content:center;width:18px;height:44px;color:var(--dx-mut)}
.dx-ti{flex:1 1 auto;min-width:0;display:flex;align-items:center;gap:4px;min-height:44px;padding:0 6px;border:0;background:transparent;color:var(--dx-ink);font-size:13.5px;font-weight:700;text-align:start;box-shadow:none}
.dx-tt{min-width:0;overflow:hidden;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;line-height:1.25;overflow-wrap:anywhere;flex:0 1 auto}.dx-ti>span:last-child{flex:none;color:var(--dx-mut);font-size:11px}
.dx-ib{flex:none;min-width:44px;min-height:44px;width:44px;padding:0;border:0;border-radius:12px;background:transparent;color:var(--dx-ink);font-size:20px;line-height:1;box-shadow:none}
.dx-rw{display:flex;align-items:center;gap:0;padding:0 0 0 4px;border-block:1px solid var(--dx-bd)}
.dx-ty{flex:1 1 auto;min-width:0;display:flex;gap:2px;overflow-x:auto;overflow-y:hidden;scrollbar-width:none;overscroll-behavior-x:contain;scroll-snap-type:x proximity;touch-action:pan-x pan-y}.dx-ty::-webkit-scrollbar{display:none}
.dx-ty[hidden]{display:none}
.dx-tb{flex:none;scroll-snap-align:start;width:40px;min-width:40px;height:44px;min-height:44px;padding:0;border:0;border-radius:10px;background:transparent;color:var(--dx-mut);font-size:12px;box-shadow:none;display:inline-flex;align-items:center;justify-content:center}
.dx-tb svg{width:20px;height:20px}.dx-ic{font-size:12px;font-weight:700;letter-spacing:0}
.dx-tb.on{color:#111;background:var(--dx-a)}:root[data-theme="dark"] .dx-tb.on{box-shadow:0 0 12px rgba(255,138,61,.45)}
.dx-tb.off{opacity:.3;cursor:not-allowed}
.dx-bd{padding:8px 10px 10px;min-width:0}.dx-ch{min-width:0;overflow:hidden}
.dx-t[data-size="S"] .dx-bd{min-height:128px}.dx-t[data-size="M"] .dx-bd{min-height:192px}.dx-t[data-size="L"] .dx-bd{min-height:280px}
.dx-kpi{display:flex;flex-direction:column;gap:4px;min-height:100px;justify-content:flex-end}.dx-kv{font-size:1.5rem;font-weight:800;line-height:1.15;overflow-wrap:anywhere;font-variant-numeric:lining-nums tabular-nums;color:var(--dx-ink)}
.dx-t[data-size="S"] .dx-kv{font-size:1.25rem}
.dx-note{font-size:11px;line-height:1.3;color:var(--warn,#b45309)}.dx-dl{font-size:12px;font-weight:700}.dx-dl small{font-weight:400;color:var(--dx-mut)}.dx-dl.ok{color:var(--ok,#16a34a)}.dx-dl.bad{color:var(--bad,#dc2626)}.dx-dl.z{color:var(--dx-mut)}
.dx-sp{width:100%;height:34px;margin-top:2px}.dx-sp .l{fill:none;stroke:var(--dx-a);stroke-width:2;vector-effect:non-scaling-stroke}.dx-sp .a{fill:var(--dx-a);opacity:.15}
.dx-sk{height:96px;border-radius:12px;background:linear-gradient(90deg,transparent,rgba(127,127,127,.18),transparent) var(--dx-bd);background-size:200% 100%;animation:dxsk 1.2s linear infinite}
@keyframes dxsk{from{background-position:200% 0}to{background-position:-200% 0}}@media (prefers-reduced-motion:reduce){.dx-sk{animation:none}}
.dx-nd{min-height:96px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;color:var(--dx-mut);text-align:center}
.dx-lk{min-height:44px;padding:0 14px;border:0;background:transparent;color:var(--dx-b);text-decoration:underline;font-size:13px;box-shadow:none}
.dx-ed{display:none;border-top:1px solid var(--dx-bd);justify-content:flex-end}.dx-edit .dx-ed{display:flex}.dx-ed button{min-width:44px;min-height:44px;border:0;background:transparent;color:var(--dx-ink);font-size:18px;box-shadow:none}.dx-ed button[disabled]{opacity:.3}
.dx-edit .dx-t{outline:1px dashed var(--dx-bd)}
.dx-lift{position:fixed!important;z-index:60;margin:0;pointer-events:none;box-shadow:0 18px 40px rgba(0,0,0,.45)!important;transform:scale(1.03);opacity:.96}
.dx-ph{border:2px dashed var(--dx-a);border-radius:var(--dx-r);background:rgba(255,138,61,.08);min-width:0;grid-column:span 1}.dx-ph[data-size="M"],.dx-ph[data-size="L"]{grid-column:span 2}
body.dx-dragging{user-select:none;-webkit-user-select:none;overscroll-behavior:contain}body.dx-dragging .dx-hd{cursor:grabbing}
#dx_full{position:fixed;inset:0;z-index:50;background:var(--bg,#fff);color:var(--dx-ink,#222);display:flex;flex-direction:column;padding:10px 12px;overflow:auto}
#dx_full .dx-fh{display:flex;align-items:center;gap:8px}#dx_full .dx-fh b{flex:1;min-width:0;overflow-wrap:anywhere}#dx_full button{min-width:44px;min-height:44px}
.dx-menu button.hrow{width:100%;text-align:start}.dx-menu .dx-sz{display:flex;gap:6px}.dx-menu .dx-sz button{flex:1;min-height:44px}.dx-menu .dx-sz button[aria-pressed="true"]{border-color:var(--dx-a,#ff8a3d);font-weight:700}
.dx-homelink{display:flex;margin:0 0 10px;width:100%;min-height:44px}
#dx_sr{position:absolute;left:-9999px;width:1px;height:1px;overflow:hidden}
@media (min-width:600px){#dx_grid{grid-template-columns:repeat(4,minmax(0,1fr))}.dx-t[data-size="M"]{grid-column:span 2}.dx-t[data-size="L"]{grid-column:span 4}.dx-ph[data-size="M"]{grid-column:span 2}.dx-ph[data-size="L"]{grid-column:span 4}.dx-t[data-size="L"] .dx-bd{min-height:320px}}
@media (min-width:1000px){#dx_grid{grid-template-columns:repeat(6,minmax(0,1fr))}.dx-t[data-size="S"]{grid-column:span 2}.dx-t[data-size="M"]{grid-column:span 3}.dx-t[data-size="L"]{grid-column:span 6}.dx-ph{grid-column:span 2}.dx-ph[data-size="M"]{grid-column:span 3}.dx-ph[data-size="L"]{grid-column:span 6}}`;
  document.head.appendChild(s);
}
const canOpen = async () => { try { const r = await MX.resolved(); return r.own || r.reports; } catch (e) { return false; } };
const locsNow = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); const mine = (S.ctx && S.ctx.locations) || []; return S.ctx && S.ctx.is_owner || !mine.length ? all : all.filter((l) => mine.includes(l.id)); };

function barHtml() {
  const lo = ST.layout, p = lo.period, c = lo.custom || { from: MX.range('7d').from, to: MX.range('7d').to };
  return `<div class="dx-chips" role="group" aria-label="${esc(T('period'))}">${MX.PERIODS.map((x) => `<button type="button" class="dx-chip" data-act="dx_period" data-v="${x.id}" aria-pressed="${p === x.id}">${esc(lab(x.label))}</button>`).join('')}</div>
    <div class="dx-cust" id="dx_cust" ${p === 'custom' ? '' : 'hidden'}><label>${esc(T('from'))}<input type="date" id="dx_from" value="${esc(c.from)}"></label><label>${esc(T('to'))}<input type="date" id="dx_to" value="${esc(c.to)}"></label></div>
    <select id="dx_loc" aria-label="${esc(T('loc'))}"><option value="">${esc(T('loc_all'))}</option>${locsNow().map((l) => `<option value="${esc(l.id)}" ${String(l.id) === String(lo.loc) ? 'selected' : ''}>${esc(A.nm(l))}</option>`).join('')}</select>
    <div class="dx-act"><button type="button" data-act="dx_add">＋ ${esc(T('add'))}</button><button type="button" data-act="dx_edit" aria-pressed="${ST.edit}">${esc(ST.edit ? T('done') : T('edit'))}</button><button type="button" data-act="dx_all" aria-label="${esc(T('refresh_all'))}">↻ ${esc(T('refresh_all'))}</button><button type="button" data-act="dx_reset">${esc(T('reset'))}</button><span class="dx-st" id="dx_status" role="status"></span></div>`;
}
function drawBar() { const b = $('#dx_bar'); if (b) b.innerHTML = barHtml(); drawStatus(); }
function drawGrid() {
  const g = $('#dx_grid'); if (!g) return; Object.keys(ST.inst).forEach(destroyInst);
  const ts = visibleTiles();
  g.innerHTML = ts.map(tileHtml).join('') || `<p class="muted" style="grid-column:1/-1">${esc(T('empty'))}</p>`;
  $('#dx_root').classList.toggle('dx-edit', ST.edit);
  ts.forEach((t) => { paintTile(t.id); observe(t.id); });
  syncArrows();
}
function observe(id) {
  const el = tileEl(id); if (!el) return;
  if (!ST.io) { lazy(id); return; }
  ST.io.observe(el);
}
function lazy(id) { if (ST.seen.has(id)) return; ST.seen.add(id); const d = ST.data[id]; if (!d || d.metric !== (tileById(id) || {}).metric || d.state === 'idle') loadTile(id); else paintTile(id); }
function syncArrows() {
  const els = $$('#dx_grid .dx-t');
  els.forEach((el, i) => { const u = $('[data-act="dx_up"]', el), d = $('[data-act="dx_dn"]', el); if (u) u.disabled = i === 0; if (d) d.disabled = i === els.length - 1; });
}
function orderFromDom() {
  const ids = $$('#dx_grid .dx-t').map((e) => e.dataset.id), hidden = ST.layout.tiles.filter((t) => !ids.includes(t.id));
  ST.layout.tiles = ids.map((id) => tileById(id)).filter(Boolean).concat(hidden);
}
function announce(i) { const r = $('#dx_sr'); if (r) r.textContent = T('moved') + ' ' + i; }

async function view() {
  css(); teardown();
  if (!S.ctx) { location.hash = '#/home'; return; }
  shell(T('title'), `<div id="dx_root"><p class="muted center pad">${esc(T('loading'))}</p></div>`, true);
  ST.ctrl = typeof AbortController === 'function' ? new AbortController() : null; ST.seen = new Set(); ST.data = {}; ST.edit = false;
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const root = $('#dx_root'); if (!root) return;
  ST.caps = await MX.resolved();
  if (!(ST.caps.own || ST.caps.reports)) { location.hash = '#/home'; return; }
  await loadLayout(); if (!$('#dx_root')) return;
  root.innerHTML = `<p class="dx-hint">${esc(T('hint'))}</p><div class="dx-bar" id="dx_bar"></div><div id="dx_grid"></div><div id="dx_sr" role="status" aria-live="polite"></div>`;
  drawBar();
  if (typeof IntersectionObserver === 'function') ST.io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { ST.io.unobserve(e.target); lazy(e.target.dataset.id); } }), { rootMargin: '200px 0px' });
  drawGrid();
  window.addEventListener('hashchange', onHash);
  if (!ST.themeObs && window.MutationObserver) { ST.themeObs = new MutationObserver(() => { if ($('#dx_grid')) visibleTiles().forEach((t) => { if (ST.data[t.id] && ST.data[t.id].state === 'ok') { destroyInst(t.id); paintTile(t.id); } }); }); ST.themeObs.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] }); }
}
function onHash() { if (!/^#\/?dashx(\/|$)/.test(location.hash)) teardown(); }
function teardown() {
  try { if (ST.ctrl) ST.ctrl.abort(); } catch (e) { /* ignore */ }
  ST.ctrl = null; if (ST.io) { try { ST.io.disconnect(); } catch (e) { /* ignore */ } ST.io = null; }
  Object.keys(ST.inst).forEach(destroyInst); window.removeEventListener('hashchange', onHash);
  if (ST.themeObs) { ST.themeObs.disconnect(); ST.themeObs = null; }
  const f = $('#dx_full'); if (f) f.remove();
  dndCancel();
  if (ST.saveT && ST.layout) { clearTimeout(ST.saveT); ST.saveT = null; try { sb.rpc('dash_layout_save', { p_layout: JSON.parse(JSON.stringify(ST.layout)), p_client: ST.client }); } catch (e) { /* local copy kept */ } }
}

// ---------- sheets ----------
function metricSheet(mode, id) {
  const caps = ST.caps, ms = MX.list(caps);
  const groups = Object.keys(MX.GROUPS).map((g) => ({ g, items: ms.filter((m) => m.group === g) })).filter((x) => x.items.length);
  const cur = id ? (tileById(id) || {}).metric : null;
  const body = (q) => { const ql = (q || '').trim().toLowerCase(); const out = groups.map((x) => { const its = x.items.filter((m) => !ql || lab(m.label).toLowerCase().includes(ql)); return its.length ? `<div class="hsec">${esc(lab(MX.GROUPS[x.g]))}</div>${its.map((m) => `<button type="button" class="hrow" data-act="dx_setm" data-m="${esc(m.id)}" data-id="${esc(id || '')}" data-mode="${mode}" ${m.id === cur ? 'aria-current="true"' : ''}><span>${esc(lab(m.label))}</span></button>`).join('')}` : ''; }).join(''); return out || `<p class="muted">${esc(T('none_found'))}</p>`; };
  openSheet(`<h2>${esc(mode === 'add' ? T('add') : T('metric'))}</h2><input id="dx_q" type="search" autocomplete="off" style="font-size:16px" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}"><div id="dx_cat" style="margin:8px 0" data-mode="${mode}" data-id="${esc(id || '')}">${body('')}</div>`);
  ST.sheetBody = body;
}
function menuSheet(id) {
  const t = tileById(id); if (!t) return; const m = MX.get(t.metric);
  openSheet(`<h2>${esc(tileTitle(t))}</h2><div class="stack dx-menu" id="dx_menu" data-id="${esc(id)}">
    <div class="fld"><label for="dx_rn">${esc(T('name'))}</label><input id="dx_rn" maxlength="60" style="font-size:16px" value="${esc(t.title || '')}" placeholder="${esc(lab(m.label))}"></div>
    ${m.shape === 'value' ? `<div class="fld"><label for="dx_tg">${esc(T('target'))}</label><input id="dx_tg" inputmode="decimal" style="font-size:16px" value="${t.target !== undefined ? esc(String(t.target)) : ''}"></div>` : ''}
    <button type="button" class="primary full" data-act="dx_mensave" data-id="${esc(id)}">${esc(T('save'))}</button>
    <div class="fld"><label>${esc(T('size'))}</label><div class="dx-sz">${SIZES.map((s) => `<button type="button" data-act="dx_size" data-id="${esc(id)}" data-v="${s}" aria-pressed="${t.size === s}">${esc(T('sz_' + s))}</button>`).join('')}</div></div>
    <button type="button" class="hrow" data-act="dx_full" data-id="${esc(id)}">${esc(T('full'))}</button>
    <button type="button" class="hrow" data-act="dx_dup" data-id="${esc(id)}">${esc(T('dup'))}</button>
    <button type="button" class="hrow" data-act="dx_rm" data-id="${esc(id)}">${esc(T('remove'))}</button></div>`);
}
function fullScreen(id) {
  const t = tileById(id), st = ST.data[id]; if (!t) return; const m = MX.get(t.metric); closeSheet();
  const d = document.createElement('div'); d.id = 'dx_full'; d.setAttribute('role', 'dialog'); d.setAttribute('aria-label', tileTitle(t));
  d.innerHTML = `<div class="dx-fh"><b>${esc(tileTitle(t))}</b><button type="button" data-act="dx_fclose" aria-label="${esc(T('close'))}">✕</button></div><div id="dx_fb" style="flex:1;min-height:0;padding-top:8px"></div>`;
  document.body.appendChild(d); const fb = $('#dx_fb', d);
  if (!st || st.state !== 'ok') { fb.innerHTML = `<div class="dx-nd"><b>${esc(T('nodata'))}</b></div>`; return; }
  if (t.type === 'kpi' && m.shape === 'value') { fb.innerHTML = kpiHtml(t, m, st.d); return; }
  if (!B.charts) { fb.innerHTML = `<div class="dx-nd"><b>${esc(T('nocharts'))}</b></div>`; return; }
  const spec0 = baseSpec(Object.assign({}, t, { size: 'L' }), m, st.d), en = compat(spec0); let type = t.type === 'kpi' ? m.type : t.type; if (!en.includes(type)) type = en[0] || type;
  let spec; try { spec = B.charts.convert(spec0, type) || spec0; } catch (e) { spec = Object.assign({}, spec0, { type }); }
  spec.height = Math.max(240, window.innerHeight - 150); spec.mini = false;
  ST.full = { chart: B.charts.render(fb, spec) };
}
function closeFull() { const f = $('#dx_full'); if (f) { try { ST.full && ST.full.chart && ST.full.chart.destroy(); } catch (e) { /* ignore */ } ST.full = null; f.remove(); } }

// ---------- actions ----------
function addTile(metric, atIndex) {
  if (ST.layout.tiles.length >= MAX_TILES) return toast(T('max'));
  const m = MX.get(metric); if (!m) return;
  const t = { id: gid(), metric, size: m.shape === 'value' ? 'S' : 'M', type: m.type }; ST.layout.tiles.push(t);
  const g = $('#dx_grid'); if (g && !$('.dx-t', g)) g.innerHTML = '';
  g.insertAdjacentHTML('beforeend', tileHtml(t)); ST.seen.add(t.id); paintTile(t.id); loadTile(t.id); syncArrows(); persist(); const e = tileEl(t.id); if (e && e.scrollIntoView) e.scrollIntoView({ block: 'nearest' });
}
function removeTile(id) {
  const i = ST.layout.tiles.findIndex((t) => t.id === id); if (i < 0) return; destroyInst(id); ST.layout.tiles.splice(i, 1); delete ST.data[id];
  const e = tileEl(id); if (e) e.remove(); if (ST.io && e) ST.io.unobserve(e); syncArrows(); persist();
  if (!$('#dx_grid .dx-t')) $('#dx_grid').innerHTML = `<p class="muted" style="grid-column:1/-1">${esc(T('empty'))}</p>`;
}
function dupTile(id) {
  if (ST.layout.tiles.length >= MAX_TILES) return toast(T('max'));
  const i = ST.layout.tiles.findIndex((t) => t.id === id); if (i < 0) return; const c = Object.assign({}, ST.layout.tiles[i], { id: gid() });
  ST.layout.tiles.splice(i + 1, 0, c); ST.data[c.id] = ST.data[id]; ST.seen.add(c.id);
  const e = tileEl(id); e.insertAdjacentHTML('afterend', tileHtml(c)); paintTile(c.id); syncArrows(); persist();
}
function moveTile(id, dir) {
  const e = tileEl(id); if (!e) return; const sib = dir < 0 ? e.previousElementSibling : e.nextElementSibling; if (!sib || !sib.classList.contains('dx-t')) return;
  if (dir < 0) e.parentNode.insertBefore(e, sib); else e.parentNode.insertBefore(sib, e);
  orderFromDom(); syncArrows(); persist(); announce($$('#dx_grid .dx-t').indexOf(e) + 1);
  const b = $(`[data-act="${dir < 0 ? 'dx_up' : 'dx_dn'}"]`, e); if (b && !b.disabled) b.focus(); else { const o = $(`[data-act="${dir < 0 ? 'dx_dn' : 'dx_up'}"]`, e); if (o) o.focus(); }
  if (e.scrollIntoView) e.scrollIntoView({ block: 'nearest' });
}
function setType(id, type) {
  const t = tileById(id); if (!t) return; const m = MX.get(t.metric), st = ST.data[id];
  if (type === 'kpi') { if (m.shape !== 'value') return; }
  else {
    const spec0 = st && st.state === 'ok' ? baseSpec(t, m, st.d) : shapeSpec(m);
    if (!compat(spec0).includes(type)) { toast(whyNot(type, m)); return; }
  }
  t.type = type; paintTile(id); persist();
}
function setMetric(id, metric) {
  const t = tileById(id), m = MX.get(metric); if (!t || !m) return; t.metric = metric; t.type = m.type; delete t.title; delete t.target; if (m.shape === 'value') t.size = t.size; destroyInst(id);
  ST.data[id] = null; const el = tileEl(id); if (el) { el.outerHTML = tileHtml(t); } ST.seen.add(id); loadTile(id); persist();
}

Object.assign(H, {
  dx_open: () => { location.hash = '#/dashx'; },
  dx_period: (a) => {
    const p = a.dataset.v; ST.layout.period = p; if (p === 'custom' && !ST.layout.custom) { const r = MX.range('7d'); ST.layout.custom = { from: r.from, to: r.to }; }
    drawBar(); persist(); loadAll(true);
  },
  dx_all: () => { persist(true); loadAll(true); },
  dx_refresh: (a) => { MX.clearCache(); loadTile(a.dataset.id, true); },
  dx_edit: () => { ST.edit = !ST.edit; const r = $('#dx_root'); if (r) r.classList.toggle('dx-edit', ST.edit); drawBar(); },
  dx_add: () => { if (ST.layout.tiles.length >= MAX_TILES) return toast(T('max')); metricSheet('add'); },
  dx_pick: (a) => { if (DND.swallow) return; metricSheet('set', a.dataset.id); },
  dx_setm: (a) => { const mode = a.dataset.mode; closeSheet(); if (mode === 'add') addTile(a.dataset.m); else setMetric(a.dataset.id, a.dataset.m); },
  dx_type: (a) => { if (a.getAttribute('aria-disabled') === 'true') { toast(a.getAttribute('title')); return; } setType(a.dataset.id, a.dataset.v); },
  dx_menu: (a) => { if (DND.swallow) return; menuSheet(a.dataset.id); },
  dx_mensave: (a) => {
    const t = tileById(a.dataset.id); if (!t) return; const nm = ($('#dx_rn') || {}).value || '', tg = $('#dx_tg');
    if (tg && tg.value.trim() !== '') { const n = Number(tg.value.trim().replace(/,/g, '')); if (!Number.isFinite(n) || n <= 0 || n > 1e12) return toast(T('badnum')); t.target = n; } else if (tg) delete t.target;
    if (nm.trim()) t.title = nm.trim().slice(0, 60); else delete t.title;
    closeSheet(); paintTile(t.id); persist();
  },
  dx_size: (a) => { const t = tileById(a.dataset.id); if (!t) return; t.size = a.dataset.v; closeSheet(); destroyInst(t.id); paintTile(t.id); persist(); },
  dx_up: (a) => moveTile(a.dataset.id, -1), dx_dn: (a) => moveTile(a.dataset.id, 1),
  dx_dup: (a) => { closeSheet(); dupTile(a.dataset.id); },
  dx_rm: (a) => { if (!window.confirm(T('confirm_rm'))) return; closeSheet(); removeTile(a.dataset.id); },
  dx_full: (a) => fullScreen(a.dataset.id), dx_fclose: closeFull,
  dx_reset: () => {
    if (!window.confirm(T('confirm_reset'))) return;
    ST.layout = Object.assign(defaults(ST.caps), { u: Date.now() }); ST.data = {}; ST.seen = new Set(); lsSet(JSON.stringify(ST.layout)); persist(); drawBar(); drawGrid();
  },
});
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'dx_q') { const c = $('#dx_cat'); if (c && ST.sheetBody) c.innerHTML = ST.sheetBody(e.target.value); } });
document.addEventListener('change', (e) => {
  const t = e.target; if (!t || !$('#dx_root')) return;
  if (t.id === 'dx_loc') { ST.layout.loc = t.value || null; persist(); loadAll(true); }
  else if (t.id === 'dx_from' || t.id === 'dx_to') { const f = $('#dx_from').value, to = $('#dx_to').value; if (/^\d{4}-\d{2}-\d{2}$/.test(f) && /^\d{4}-\d{2}-\d{2}$/.test(to)) { ST.layout.custom = { from: f, to }; persist(); loadAll(true); } }
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { if (DND.s) dndCancel(); else closeFull(); } });

// ---------- drag and drop (touch long-press, pointer events, mouse) ----------
const DND = { s: null, swallow: false, raf: 0 };
function dndDown(e) {
  if (!$('#dx_grid') || DND.s) return; if (e.pointerType === 'mouse' && e.button !== 0) return;
  const hd = e.target.closest && e.target.closest('.dx-hd'); if (!hd) return; const tile = hd.closest('.dx-t'); if (!tile) return;
  const touch = e.pointerType !== 'mouse';
  const s = DND.s = { tile, pid: e.pointerId, x0: e.clientX, y0: e.clientY, x: e.clientX, y: e.clientY, touch, active: false, timer: null };
  if (touch) s.timer = setTimeout(() => { if (DND.s === s && !s.active) lift(); }, PRESS_MS);
}
function dndMove(e) {
  const s = DND.s; if (!s || e.pointerId !== s.pid) return; s.x = e.clientX; s.y = e.clientY;
  if (!s.active) { const d = Math.hypot(s.x - s.x0, s.y - s.y0); if (s.touch) { if (d > 10) dndCancel(); } else if (d > 5) lift(); return; }
  if (e.cancelable) e.preventDefault(); follow(); place();
}
function lift() {
  const s = DND.s; if (!s) return; clearTimeout(s.timer); s.active = true;
  const r = s.tile.getBoundingClientRect(); s.dx = s.x - r.left; s.dy = s.y - r.top; s.next = s.tile.nextElementSibling;
  const ph = s.ph = document.createElement('div'); ph.className = 'dx-ph'; ph.dataset.size = s.tile.dataset.size; ph.style.height = r.height + 'px'; s.tile.parentNode.insertBefore(ph, s.tile);
  s.tile.classList.add('dx-lift'); s.tile.style.left = r.left + 'px'; s.tile.style.top = r.top + 'px'; s.tile.style.width = r.width + 'px';
  document.body.classList.add('dx-dragging'); try { if (navigator.vibrate) navigator.vibrate(15); } catch (e) { /* no haptics */ }
  try { s.tile.setPointerCapture && s.tile.setPointerCapture(s.pid); } catch (e) { /* synthetic pointer */ }
  loopScroll();
}
function follow() { const s = DND.s; if (!s || !s.active) return; s.tile.style.left = (s.x - s.dx) + 'px'; s.tile.style.top = (s.y - s.dy) + 'px'; }
function place() {
  const s = DND.s; if (!s || !s.active) return; const g = $('#dx_grid'); if (!g) return;
  const el = document.elementFromPoint(s.x, s.y); const tgt = el && el.closest ? el.closest('.dx-t') : null;
  if (!tgt || tgt === s.tile || tgt.parentNode !== g) {
    const last = Array.from(g.querySelectorAll('.dx-t')).filter((x) => x !== s.tile).pop();   // below every tile = the end
    if (!tgt && last && s.y > last.getBoundingClientRect().bottom && g.contains(el || g)) g.appendChild(s.ph);
    return;
  }
  const r = tgt.getBoundingClientRect(), pr = s.ph.getBoundingClientRect(); const sameRow = Math.abs(pr.top - r.top) < 12;
  const before = sameRow ? s.x < r.left + r.width / 2 : s.y < r.top + r.height / 2;
  const ref = before ? tgt : tgt.nextSibling; if (ref !== s.ph && s.ph.nextSibling !== ref) g.insertBefore(s.ph, ref);
}
function loopScroll() {
  cancelAnimationFrame(DND.raf);
  const step = () => {
    const s = DND.s; if (!s || !s.active) return; const vh = window.innerHeight, zone = 80; let v = 0;
    if (s.y < zone) v = -Math.ceil(((zone - s.y) / zone) * 18); else if (s.y > vh - zone) v = Math.ceil(((s.y - (vh - zone)) / zone) * 18);
    if (v) { window.scrollBy(0, v); place(); }
    DND.raf = requestAnimationFrame(step);
  };
  DND.raf = requestAnimationFrame(step);
}
function dndUp(e) {
  const s = DND.s; if (!s || (e && e.pointerId !== undefined && e.pointerId !== s.pid)) return;
  clearTimeout(s.timer); cancelAnimationFrame(DND.raf);
  if (!s.active) { DND.s = null; return; }
  const g = $('#dx_grid'); if (g && s.ph.parentNode) g.insertBefore(s.tile, s.ph); s.ph.remove(); reset(s);
  DND.s = null; DND.swallow = true; setTimeout(() => { DND.swallow = false; }, 400);
  try { if (navigator.vibrate) navigator.vibrate(10); } catch (er) { /* no haptics */ }
  orderFromDom(); syncArrows(); persist(); announce($$('#dx_grid .dx-t').indexOf(s.tile) + 1);
}
function reset(s) { s.tile.classList.remove('dx-lift'); s.tile.style.left = s.tile.style.top = s.tile.style.width = ''; document.body.classList.remove('dx-dragging'); try { s.tile.releasePointerCapture && s.tile.releasePointerCapture(s.pid); } catch (e) { /* ignore */ } }
function dndCancel() {
  const s = DND.s; if (!s) return; clearTimeout(s.timer); cancelAnimationFrame(DND.raf); DND.s = null;
  if (s.active) { const g = s.tile.parentNode; if (g) g.insertBefore(s.tile, s.next && s.next.parentNode === g ? s.next : null); if (s.ph) s.ph.remove(); reset(s); }
}
document.addEventListener('pointerdown', dndDown);
document.addEventListener('pointermove', dndMove, { passive: false });
document.addEventListener('pointerup', dndUp);
document.addEventListener('pointercancel', () => { if (DND.s && DND.s.active) dndUp({}); else dndCancel(); });
document.addEventListener('touchmove', (e) => { if (DND.s && DND.s.active && e.cancelable) e.preventDefault(); }, { passive: false });
document.addEventListener('contextmenu', (e) => { if (DND.s && DND.s.touch && e.target.closest && e.target.closest('.dx-hd')) e.preventDefault(); });
document.addEventListener('click', (e) => { if (DND.swallow && e.target.closest && e.target.closest('.dx-hd')) { e.stopPropagation(); e.preventDefault(); } }, true);

// ---------- Home link (guarded: only for people who may open the dashboard; the page itself checks again) ----------
let linkOk = null, tick = 0;
function placeLink() {
  const host = $('#hv_main') && $('#hv_main').firstElementChild ? $('#hv_main') : $('#ob_main') && $('#ob_bar') ? $('#ob_main') : null;
  if (!host || $('#dx_home')) return; if (linkOk === false) return;
  if (linkOk === null) { linkOk = undefined; canOpen().then((v) => { linkOk = !!v; placeLink(); }); return; }
  if (linkOk !== true) return;
  const b = document.createElement('button'); b.type = 'button'; b.id = 'dx_home'; b.className = 'dx-homelink full'; b.setAttribute('data-act', 'dx_open'); b.textContent = T('open'); host.insertBefore(b, host.firstChild);
}
try { if (window.MutationObserver && document.body) new MutationObserver(() => { if (tick) return; tick = setTimeout(() => { tick = 0; try { css(); placeLink(); } catch (e) { /* optional */ } }, 60); }).observe(document.body, { childList: true, subtree: true }); } catch (e) { /* optional */ }

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { dashx: view });
B.dashx = { view, defaults, norm, state: ST, X, teardown, MAX_TILES };
})();
