/* Islamia BOS · Customer lists (#/crmlists). Package CRM-C, screen S5. Build a list of customers from a few plain rules (not seen for N days, big spenders, birthday soon, by outlet, tier, type,
   item bought, agreed to messages ...), see how many customers it holds BEFORE saving, look at them page by page, save the list, freeze it (copy today's customers), export it (if allowed).
   Server: supabase/phase306.sql (scores), phase307.sql (lists), phase308.sql (export). The screen only asks; the server decides every call (a hidden button is also a refused request).
   The rule is data, never SQL: the server checks it field by field against a fixed catalog. Nothing is sent to anyone from here.
   Register the route only through web/ia.js and add the script tag in index.html (integrator, see docs/integration/CRM-C.md).
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const money = (n) => (n === null || n === undefined ? '-' : '৳' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 }));
const dt = (v) => (v ? String(v).replace('T', ' ').slice(0, 16) : '-');
const MAXC = 5;   // the screen offers five conditions; the server allows eight
const OPS = { eq: 'is', ne: 'is not', gt: 'more than', ge: 'at least', lt: 'less than', le: 'at most', between: 'between', in: 'is any of', not_in: 'is none of', is: 'is' };
const ERR = {
  not_allowed: 'You do not have permission.', segments_off: 'Saving lists is switched off. The owner can switch it on in Settings.', name_taken: 'A list with this name already exists.',
  bad_name: 'Write a name (1 to 60 characters).', reason_required: 'Write a reason (at least 3 characters).', empty_segment: 'No customer matches. Change the rules first.',
  export_off: 'Export is switched off. The owner can switch it on in Settings.', set_export_max_rows: 'The owner must set the largest export size in Settings first.', segment_retired: 'This list was retired.',
  'bad_rule:unknown_field': 'That rule is not available.', 'bad_rule:bad_operator': 'That comparison does not fit this rule.', 'bad_rule:bad_value': 'A value is missing or not allowed.',
  'bad_rule:no_conditions': 'Add at least one rule.', 'bad_rule:too_many_conditions': 'Too many rules.', 'bad_rule:too_big': 'The rule is too big.', bad_value: 'That value is not allowed.', 'not found': 'Not found.',
};
const eText = (e) => {
  const m = String((e && e.message) || e || '');
  const oc = m.match(/over_cap:(\d+)/); if (oc) return 'This list has ' + oc[1] + ' customers, more than the largest list that can be frozen. Narrow the rules, or ask the owner to raise the limit.';
  const ox = m.match(/over_export_cap:(\d+)/); if (ox) return 'This list has ' + ox[1] + ' customers, more than the largest export the owner allows. Narrow the rules.';
  const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error';
};
const D = { tab: 'lists', me: null, cat: null, status: null, segs: null, conds: [], match: 'all', prev: null, usedPreset: '', loaded: false, page: null, itemQ: '', itemHits: [] };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const cuid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : '00000000-0000-4000-8000-' + String(Date.now()).padStart(12, '0').slice(-12));
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fieldDef = (f) => ((D.cat && D.cat.fields) || []).find((x) => x.field === f);

/* ---- conditions: one object per row. c = {field, op, v, v2, sel[], txt, items[{id,name}], days, ch} ---- */
function newCond(field) {
  const f = fieldDef(field) || (D.cat.fields[0]);
  return { field: f.field, op: f.ops[f.kind === 'num' ? 3 : 0], v: '', v2: '', sel: [], txt: '', items: [], days: '', ch: 'any' };
}
function selOptions(c) {
  const k = D.cat;
  return ({ tier: (k.tiers || []).map((x) => [x.code, x.name]), type: (k.types || []).map((x) => [x.code, x.name]), type_code: (k.groups || []).map((x) => [x.code, x.name]),
    outlet: (k.outlets || []).map((x) => [String(x.id), x.name]), rfm_label: (k.labels || []).map((x) => [x, x]) })[c.field] || [];
}
function readConds() {
  D.conds.forEach((c, i) => {
    const g = (id) => { const el = $('#cs_' + i + '_' + id); return el ? el.value : undefined; };
    const def = fieldDef(c.field); if (!def) return;
    if (g('op') !== undefined) c.op = g('op');
    if (g('v') !== undefined) c.v = g('v');
    if (g('v2') !== undefined) c.v2 = g('v2');
    if (g('txt') !== undefined) c.txt = g('txt');
    if (g('days') !== undefined) c.days = g('days');
    if (g('ch') !== undefined) c.ch = g('ch');
  });
  const m = $('#cs_match'); if (m) D.match = m.value;
}
function toRule() {
  readConds();
  const out = [];
  for (const c of D.conds) {
    const def = fieldDef(c.field); const cond = { field: c.field, op: c.op };
    if (def.kind === 'num' || def.kind === 'within') {
      const a = norm(c.v); if (a === '' || Number.isNaN(Number(a))) throw new Error('Type a number for "' + def.label + '".');
      if (c.op === 'between') { const b = norm(c.v2); if (b === '' || Number.isNaN(Number(b))) throw new Error('Type both numbers for "' + def.label + '".'); cond.value = [Number(a), Number(b)]; } else cond.value = Number(a);
    } else if (def.kind === 'bool') cond.value = c.v !== 'no';
    else if (def.kind === 'optin') { cond.value = c.v !== 'no'; cond.channel = c.ch || 'any'; }
    else if (def.kind === 'set_text' && c.field === 'source') {
      const list = String(c.txt || '').split(',').map((x) => x.trim()).filter(Boolean); if (!list.length) throw new Error('Type at least one value for "' + def.label + '".'); cond.value = list;
    } else if (def.kind === 'set_text') { if (!c.sel.length) throw new Error('Choose at least one for "' + def.label + '".'); cond.value = c.sel.slice(); }
    else if (def.kind === 'set_int') { if (!c.sel.length) throw new Error('Choose at least one for "' + def.label + '".'); cond.value = c.sel.map(Number); }
    else if (def.kind === 'items') {
      if (!c.items.length) throw new Error('Search and choose at least one item.'); cond.value = c.items.map((x) => x.id);
      const d = norm(c.days); if (d !== '') { if (Number.isNaN(Number(d))) throw new Error('Days must be a number.'); cond.within_days = Number(d); }
    }
    out.push(cond);
  }
  if (!out.length) throw new Error(ERR['bad_rule:no_conditions']);
  return { match: D.match, conditions: out };
}

/* ---- presets: starting points; the numbers are typed by the person (or come from the owner's settings), never invented ---- */
function presets() {
  const wb = D.status && D.status.winback_days; const sm = D.status && D.status.spend_min;
  return [
    ['notseen', 'Not seen for N days', () => [{ field: 'days_since_last', op: 'gt', v: wb || '' }, { field: 'orders_total', op: 'ge', v: '1' }]],
    ['spenders', 'High spenders', () => [{ field: 'spend_12m', op: 'ge', v: sm || '' }]],
    ['birthday', 'Birthday soon', () => [{ field: 'birthday_in_days', op: 'le', v: '' }]],
    ['bday_month', 'Birthday this month', () => [{ field: 'birthday_this_month', op: 'is', v: 'yes' }]],
    ['onetime', 'One-time buyers', () => [{ field: 'orders_total', op: 'eq', v: '1' }]],
    ['atrisk', 'At risk', () => [{ field: 'rfm_label', op: 'in', sel: ['At risk', 'At-risk'] }]],
    ['optin', 'Not yet agreed to messages', () => [{ field: 'opted_in', op: 'is', v: 'no' }]],
    ['outlet', 'By outlet', () => [{ field: 'outlet', op: 'in', sel: [] }]],
    ['tier', 'By tier', () => [{ field: 'tier', op: 'in', sel: [] }]],
    ['item', 'Bought an item', () => [{ field: 'bought_item', op: 'in', items: [] }]],
  ];
}
function applyPreset(code) {
  const p = presets().find((x) => x[0] === code); if (!p) return;
  D.conds = p[2]().map((x) => Object.assign(newCond(x.field), x)); D.match = 'all'; D.prev = null; D.usedPreset = code; D.tab = 'build'; draw();
}

/* ---- drawing ---- */
function headHTML() {
  const s = D.status || {}; const me = D.me || {};
  const need = (s.stale || 0) + 0;
  return `<div class="card" id="cs_head"><div class="row between"><b id="cs_sum">${esc(String(s.scored ?? 0))} of ${esc(String(s.customers ?? 0))} customers scored</b>
    ${me.run ? `<button class="primary" data-act="cs_refresh">Refresh scores</button>` : ''}</div>
    <div class="muted">Last score: ${esc(dt(s.newest))}${need ? ` · ${esc(String(need))} need a refresh` : ''}</div>
    ${s.never_scored ? `<div class="notice" id="cs_unscored">${esc(String(s.never_scored))} customers have no score yet. Rules about orders, spending or visits skip them until you press Refresh scores.</div>` : ''}</div>`;
}
function tabsBar() {
  return `<div class="row wrap" id="cs_tabs" style="gap:.3rem">${[['lists', 'Saved lists'], ['build', 'New list']].map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="crs_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
}
function listsHTML() {
  const me = D.me || {};
  const off = me.edit && !me.segments_on ? `<div class="notice" id="cs_off">Saving lists is switched off. You can still build a list and see how many customers it holds. The owner switches saving on in Settings.</div>` : '';
  const rows = (D.segs || []).map((s) => `<div class="card cs-seg" data-id="${esc(s.id)}"><div class="row between"><b>${esc(s.name)}</b>${chip(s.kind === 'list' ? 'Frozen' : 'Live', s.kind === 'list' ? 'ok' : '')}</div>
      <div class="muted">${s.kind === 'list' ? esc(String(s.member_count)) + ' customers, frozen ' + esc(dt(s.frozen_at)) : 'Last count ' + esc(String(s.last_count ?? '-')) + ' · ' + esc(dt(s.last_count_at))}${s.note ? ' · ' + esc(s.note) : ''}</div>
      <div class="row wrap"><button class="primary" data-act="crs_open" data-v="${esc(s.id)}">Show customers</button><button data-act="cs_count" data-v="${esc(s.id)}">Count now</button>
        <details><summary>More</summary><div class="row wrap">
          ${me.edit && me.segments_on && s.kind === 'dynamic' ? `<button data-act="cs_freezesaved" data-v="${esc(s.id)}">Freeze as list</button><button data-act="cs_edit" data-v="${esc(s.id)}">Change rules</button>` : ''}
          ${me.export && me.export_on ? `<button data-act="cs_exportsaved" data-v="${esc(s.id)}">Export</button>` : ''}
          ${me.edit && me.segments_on ? `<button class="danger" data-act="cs_retire" data-v="${esc(s.id)}">Retire</button>` : ''}</div></details></div></div>`).join('');
  return off + (rows || '<p class="muted" id="cs_none">No saved lists yet. Open "New list" to build one.</p>');
}
function condHTML(c, i) {
  const def = fieldDef(c.field); const id = (k) => `cs_${i}_${k}`;
  const fieldSel = `<select id="${id('field')}" data-act="cs_field" data-i="${i}">${D.cat.fields.map((f) => `<option value="${esc(f.field)}" ${f.field === c.field ? 'selected' : ''}>${esc(f.label)}</option>`).join('')}</select>`;
  const opSel = def.ops.length > 1 ? `<select id="${id('op')}">${def.ops.map((o) => `<option value="${o}" ${o === c.op ? 'selected' : ''}>${esc(OPS[o] || o)}</option>`).join('')}</select>` : `<input id="${id('op')}" type="hidden" value="${esc(def.ops[0])}">`;
  let val = '';
  if (def.kind === 'num' || def.kind === 'within') val = `<input id="${id('v')}" inputmode="decimal" placeholder="number" value="${esc(c.v)}" style="max-width:8rem">` + (c.op === 'between' ? ` and <input id="${id('v2')}" inputmode="decimal" placeholder="number" value="${esc(c.v2)}" style="max-width:8rem">` : '') + (def.unit ? ` <span class="muted">${esc(def.unit)}</span>` : '');
  else if (def.kind === 'bool') val = `<select id="${id('v')}"><option value="yes" ${c.v !== 'no' ? 'selected' : ''}>Yes</option><option value="no" ${c.v === 'no' ? 'selected' : ''}>No</option></select>`;
  else if (def.kind === 'optin') val = `<select id="${id('v')}"><option value="yes" ${c.v !== 'no' ? 'selected' : ''}>Yes</option><option value="no" ${c.v === 'no' ? 'selected' : ''}>No</option></select> <select id="${id('ch')}">${['any', 'sms', 'whatsapp'].map((x) => `<option value="${x}" ${c.ch === x ? 'selected' : ''}>${x === 'any' ? 'any channel' : x}</option>`).join('')}</select>`;
  else if (def.kind === 'set_text' && c.field === 'source') val = `<input id="${id('txt')}" placeholder="words, separated by commas" value="${esc(c.txt)}">`;
  else if (def.kind === 'set_text' || def.kind === 'set_int') val = `<div class="row wrap" style="gap:.25rem">${selOptions(c).map(([k, l]) => `<button type="button" class="tog ${c.sel.includes(k) ? 'on' : ''}" data-act="cs_sel" data-i="${i}" data-v="${esc(k)}">${esc(l)}</button>`).join('') || '<span class="muted">Nothing to choose.</span>'}</div>`;
  else if (def.kind === 'items') val = `<div class="row wrap" style="gap:.25rem">${c.items.map((x) => `<button type="button" class="tog on" data-act="cs_itemdel" data-i="${i}" data-v="${esc(x.id)}">${esc(x.name)} ✕</button>`).join('')}</div>
      <div class="row"><input id="${id('q')}" placeholder="Search an item" autocomplete="off"><button data-act="cs_itemfind" data-i="${i}">Search</button></div><div id="cs_${i}_hits" class="row wrap" style="gap:.25rem"></div>
      <div class="row"><label for="${id('days')}" class="muted">Within the last (days, optional)</label><input id="${id('days')}" inputmode="numeric" value="${esc(c.days)}" style="max-width:6rem"></div>`;
  return `<div class="card cs-cond" data-i="${i}"><div class="stack">${fieldSel}${opSel}<div>${val}</div></div><button class="danger" data-act="cs_del" data-i="${i}" aria-label="Remove this rule">Remove rule</button></div>`;
}
function buildHTML() {
  const pr = presets().map(([k, l]) => `<button type="button" class="tog ${D.usedPreset === k ? 'on' : ''}" data-act="cs_preset" data-v="${k}">${esc(l)}</button>`).join('');
  const conds = D.conds.map(condHTML).join('') || '<p class="muted" id="cs_nocond">Choose a starting point above, or add a rule.</p>';
  const me = D.me || {}; const pv = D.prev;
  return `<div class="row wrap" id="cs_presets" style="gap:.3rem">${pr}</div>${conds}
    <div class="row wrap">${D.conds.length < MAXC ? '<button data-act="cs_add" id="cs_add">Add a rule</button>' : ''}
      ${D.conds.length > 1 ? `<label for="cs_match" class="muted">Customers must match</label><select id="cs_match"><option value="all" ${D.match === 'all' ? 'selected' : ''}>all rules</option><option value="any" ${D.match === 'any' ? 'selected' : ''}>any rule</option></select>` : ''}</div>
    <div class="row"><button class="primary full" data-act="cs_preview" id="cs_preview">How many customers?</button></div>${pv ? previewHTML(pv) : ''}`;
}
function previewHTML(pv) {
  const me = D.me || {};
  const by = Object.entries(pv.by_label || {}).map(([k, n]) => chip(k + ' ' + n)).join(' ');
  return `<div class="card" id="cs_result"><div class="row between"><b id="cs_count">${esc(String(pv.count))} customers</b>${pv.over_cap ? chip('Too big to freeze', 'bad') : ''}</div>
    <div class="muted">Total spent ${esc(money(pv.lifetime_spend))} · last 12 months ${esc(money(pv.spend_12m))}</div><div class="row wrap">${by}</div>
    ${pv.members_unscored ? `<div class="notice" id="cs_unsc_note">${esc(String(pv.members_unscored))} of them have no score yet; rules about orders or visits cannot see them. Press Refresh scores.</div>` : ''}
    ${pv.over_cap ? `<div class="muted">More than ${esc(String(pv.cap))} customers: you can look at them, but not freeze them.</div>` : ''}
    <div class="row wrap"><button class="primary" data-act="cs_members" ${pv.count ? '' : 'disabled'}>Show customers</button>
      ${me.edit ? `<button data-act="cs_savesheet" ${me.segments_on ? '' : 'disabled title="Saving is switched off"'}>Save list</button><button data-act="cs_freezesheet" ${me.segments_on && pv.count && !pv.over_cap ? '' : 'disabled'}>Freeze as list</button>` : ''}
      ${me.export && me.export_on && pv.count ? '<button data-act="cs_exportnew">Export</button>' : ''}</div></div>`;
}
function draw() {
  const el = $('#cs_body'); if (!el) return;
  el.innerHTML = headHTML() + tabsBar() + `<div id="cs_pane">${D.tab === 'lists' ? listsHTML() : D.cat ? buildHTML() : '<p class="muted">…</p>'}</div>`;
}

async function reload() {
  D.me = await call('crmc_me', {});
  if (!D.me.view) { D.status = null; D.segs = null; return; }
  const [st, sg] = await Promise.all([call('crmc_metrics_status', {}), call('crmc_segments_list', { p_include_retired: false })]);
  D.status = st; D.segs = sg || [];
  if (!D.cat) D.cat = await call('crmc_field_catalog', {});
}
function memberRows(rows) {
  return (rows || []).map((r) => `<div class="card cs-mem"><div class="row between"><b>${esc(r.name)}</b>${r.label ? chip(r.label) : chip('not scored')}</div>
    <div class="muted">${esc(r.mobile || '')}${r.tier ? ' · ' + esc(r.tier) : ''}</div>
    <div class="muted">${r.last_visit ? 'Last visit ' + esc(r.last_visit) + ' (' + esc(String(r.days_since_last)) + ' days)' : 'No visit yet'} · 12 months ${esc(money(r.spend_12m))} · total ${esc(money(r.lifetime_spend))}${Number(r.due_amount) > 0 ? ' · owes ' + esc(money(r.due_amount)) : ''}</div></div>`).join('');
}
async function showPage(args, title, offset) {
  const r = await call('crmc_members', Object.assign({ p_rule: null, p_segment: null, p_limit: 50, p_offset: offset || 0 }, args));
  D.page = { args, title };
  const more = (r.offset + r.rows.length) < r.total;
  const html = `<h2>${esc(title)}</h2><div class="muted" id="cs_pg_sum">${esc(String(r.total))} customers · showing ${esc(String(r.offset + 1))} to ${esc(String(r.offset + r.rows.length))}${r.masked ? ' · phone numbers are hidden for you' : ''}</div>
    <div class="stack" id="cs_pg_rows">${memberRows(r.rows) || '<p class="muted">Nobody.</p>'}</div>
    <div class="row">${r.offset > 0 ? `<button data-act="cs_pg" data-v="${Math.max(r.offset - 50, 0)}">Previous 50</button>` : ''}${more ? `<button class="primary" data-act="cs_pg" data-v="${r.offset + 50}">Next 50</button>` : ''}<button data-act="closesheet">Close</button></div>`;
  A.openSheet(html);
}
const segArgs = () => ({ p_rule: toRule() });
function askText(q) { const r = window.prompt(q); return r === null ? null : r.trim(); }

Object.assign(H, {
  crs_tab: (a) => { readConds(); D.tab = a.dataset.v; draw(); },
  cs_refresh: act(async () => {
    let r = await call('crmc_metrics_refresh', { p_dry: false, p_limit: null });
    toast('Scored ' + r.processed + (r.remaining ? ', ' + r.remaining + ' left: press again' : ', all up to date'));
    D.status = await call('crmc_metrics_status', {}); draw();
  }),
  cs_preset: (a) => applyPreset(a.dataset.v),
  cs_add: () => { readConds(); if (D.conds.length < MAXC) D.conds.push(newCond('days_since_last')); D.prev = null; draw(); },
  cs_del: (a) => { readConds(); D.conds.splice(Number(a.dataset.i), 1); D.prev = null; draw(); },
  cs_field: (a) => { readConds(); const i = Number(a.dataset.i); D.conds[i] = newCond(a.value); D.prev = null; draw(); },
  cs_sel: (a) => { readConds(); const c = D.conds[Number(a.dataset.i)]; const v = a.dataset.v; c.sel = c.sel.includes(v) ? c.sel.filter((x) => x !== v) : c.sel.concat(v); draw(); },
  cs_itemfind: act(async (a) => {
    readConds(); const i = Number(a.dataset.i); const q = ($('#cs_' + i + '_q') || {}).value || '';
    const hits = await call('crmc_item_search', { p_q: q, p_limit: 12 }); D.itemHits = hits;
    $('#cs_' + i + '_hits').innerHTML = hits.map((h) => `<button type="button" class="tog" data-act="cs_itemadd" data-i="${i}" data-v="${esc(h.id)}" data-n="${esc(h.name)}">${esc(h.name)}</button>`).join('') || '<span class="muted">No item found.</span>';
  }),
  cs_itemadd: (a) => { readConds(); const c = D.conds[Number(a.dataset.i)]; if (c.items.length < 10 && !c.items.some((x) => x.id === a.dataset.v)) c.items.push({ id: a.dataset.v, name: a.dataset.n }); draw(); },
  cs_itemdel: (a) => { readConds(); const c = D.conds[Number(a.dataset.i)]; c.items = c.items.filter((x) => x.id !== a.dataset.v); draw(); },
  cs_preview: act(async () => {
    D.prev = await call('crmc_preview', { p_rule: toRule(), p_segment: null }); D.prevSeg = null; draw();
    const el = $('#cs_result'); if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' });
  }),
  cs_members: act(async () => { const r = toRule(); await showPage({ p_rule: r }, 'Customers in this list', 0); }),
  cs_pg: act(async (a) => { await showPage(D.page.args, D.page.title, Number(a.dataset.v)); }),
  crs_open: act(async (a) => { const s = D.segs.find((x) => String(x.id) === a.dataset.v); await showPage({ p_segment: s.id }, s.name, 0); }),
  cs_count: act(async (a) => { const s = D.segs.find((x) => String(x.id) === a.dataset.v); const pv = await call('crmc_preview', { p_rule: null, p_segment: s.id }); toast(s.name + ': ' + pv.count + ' customers'); }),
  cs_edit: (a) => {
    const s = D.segs.find((x) => String(x.id) === a.dataset.v); D.editing = s.id;
    D.conds = (s.rule.conditions || []).map((c) => { const d = fieldDef(c.field); const x = newCond(c.field); x.op = c.op;
      if (d.kind === 'num' || d.kind === 'within') { x.v = Array.isArray(c.value) ? String(c.value[0]) : String(c.value); x.v2 = Array.isArray(c.value) ? String(c.value[1]) : ''; }
      else if (d.kind === 'bool') x.v = c.value ? 'yes' : 'no'; else if (d.kind === 'optin') { x.v = c.value ? 'yes' : 'no'; x.ch = c.channel || 'any'; }
      else if (d.kind === 'set_text' && c.field === 'source') x.txt = c.value.join(', '); else if (d.kind === 'set_text') x.sel = c.value.slice(); else if (d.kind === 'set_int') x.sel = c.value.map(String);
      else if (d.kind === 'items') { x.items = c.value.map((id) => ({ id, name: id.slice(0, 8) })); x.days = c.within_days ? String(c.within_days) : ''; }
      return x; });
    D.match = s.rule.match || 'all'; D.prev = null; D.tab = 'build'; draw();
  },
  cs_savesheet: () => {
    const cur = D.editing ? (D.segs.find((x) => x.id === D.editing) || {}) : {};
    A.openSheet(`<h2>${D.editing ? 'Save changes' : 'Save list'}</h2><div class="stack"><label for="cs_name">Name</label><input id="cs_name" maxlength="60" value="${esc(cur.name || '')}">
      <label for="cs_note">Note (optional)</label><input id="cs_note" maxlength="200" value="${esc(cur.note || '')}">
      <div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="cs_save">Save</button></div></div>`);
  },
  cs_save: act(async () => {
    const name = ($('#cs_name') || {}).value || ''; const note = ($('#cs_note') || {}).value || '';
    if (!name.trim()) return toast(ERR.bad_name);
    await call('crmc_segment_save', { p_client: cuid(), p_id: D.editing || null, p_name: name.trim(), p_rule: toRule(), p_note: note.trim() || null });
    A.closeSheet(); toast('Saved'); D.editing = null; await reload(); D.tab = 'lists'; draw();
  }),
  cs_freezesheet: () => {
    A.openSheet(`<h2>Freeze as list</h2><p class="muted">Today's customers are copied into a new list. It never changes afterwards, even when customers buy again.</p><div class="stack"><label for="cs_fname">Name</label><input id="cs_fname" maxlength="60">
      <div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="cs_freeze">Freeze</button></div></div>`);
  },
  cs_freeze: act(async () => {
    const name = (($('#cs_fname') || {}).value || '').trim(); if (!name) return toast(ERR.bad_name);
    await call('crmc_segment_freeze', { p_client: cuid(), p_segment: null, p_rule: toRule(), p_name: name, p_note: null });
    A.closeSheet(); toast('Frozen'); await reload(); D.tab = 'lists'; draw();
  }),
  cs_freezesaved: act(async (a) => {
    const s = D.segs.find((x) => String(x.id) === a.dataset.v); const name = askText('Name for the frozen copy'); if (name === null) return; if (!name) return toast(ERR.bad_name);
    await call('crmc_segment_freeze', { p_client: cuid(), p_segment: s.id, p_rule: null, p_name: name, p_note: null }); toast('Frozen'); await reload(); draw();
  }),
  cs_retire: act(async (a) => {
    const s = D.segs.find((x) => String(x.id) === a.dataset.v); const why = askText('Why is this list retired? (kept in the log)'); if (why === null) return; if (why.length < 3) return toast(ERR.reason_required);
    await call('crmc_segment_retire', { p_id: s.id, p_active: false, p_reason: why }); toast('Retired'); await reload(); draw();
  }),
  cs_exportnew: act(async () => { await doExport({ p_rule: toRule(), p_segment: null }); }),
  cs_exportsaved: act(async (a) => { await doExport({ p_rule: null, p_segment: Number(a.dataset.v) }); }),
});

function csv(columns, rows) {
  const q = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; /* spreadsheet formula guard */ return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  return [columns.join(',')].concat(rows.map((r) => r.map(q).join(','))).join('\n');
}
async function doExport(args) {
  const why = askText('Why do you need this list? (kept in the export log)'); if (why === null) return; if (why.length < 3) return toast(ERR.reason_required);
  const r = await call('crmc_export', Object.assign({ p_client: cuid(), p_reason: why, p_fields: null }, args));
  if (r.repeat) return toast('Already exported');
  const text = csv(r.columns, r.rows);
  try { const blob = new Blob([text], { type: 'text/csv' }); const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = 'customer_list.csv'; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000); } catch (e) { /* download blocked: the text is still shown */ }
  toast('Exported ' + r.total + ' customers' + (r.mobile_masked ? ' (phone numbers hidden for you)' : ''));
}

document.addEventListener('change', (e) => { const a = e.target && e.target.closest && e.target.closest('select[data-act="cs_field"]'); if (a) Promise.resolve(H.cs_field(a)).catch(fail); });

async function view() {
  if (B && B.loadStatic) await B.loadStatic();
  shell('Customer lists', '<div id="cs_body"><p class="muted">…</p></div>', true);
  try {
    await reload();
    if (!D.me || !D.me.view) { $('#cs_body').innerHTML = '<p class="muted" id="cs_noperm">You do not have permission to see customer lists.</p>'; return; }
    draw();
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmlists: view });
})();
