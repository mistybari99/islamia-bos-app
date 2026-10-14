/* Islamia BOS · Costing & overhead (#/costing): conversion-cost rates on a recipe, monthly pools of actual factory cost, the per-location choice (off / recipe / pool + normal output),
   the month-end true-up (actual vs absorbed = "অনাবশোষিত ওভারহেড") and the cost snapshot of production runs. COST-RIGHT HOLDERS ONLY: every number comes from a server call that refuses without the right.
   Server: supabase/phase74.sql (recipe_cost, recipe_cost_component_set / _retire / _get, cost_type_add, pool_set, loc_cost_cfg_set, overhead_trueup, production_run_costs).
   Nothing is guessed: a blank amount stays blank and the server flags "রূপান্তর খরচ অসম্পূর্ণ". Minutes x people from the recipe steps is shown only as a SUGGESTION next to the hours box.
   Handlers are prefixed cs_. Loaded after recipebook.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const num = (v) => { const s = norm(v); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q = (n, d = 4) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: d }));
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + q(n));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const owner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('খরচ ও ওভারহেড', 'Costing & overhead', 'Costing ও overhead'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
  noperm: L('অনুমতি নেই — খরচ দেখার অধিকার লাগবে', 'Not allowed — the cost right is needed', 'অনুমতি নেই — cost right লাগবে'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), save: L('সংরক্ষণ', 'Save', 'Save'),
  tRec: L('রেসিপির রেট', 'Recipe rates', 'Recipe rate'), tPool: L('মাসিক পুল', 'Monthly pools', 'Monthly pool'), tLoc: L('জায়গা অনুযায়ী পদ্ধতি', 'Method per place', 'Place অনুযায়ী method'), tTrue: L('অনাবশোষিত', 'Unabsorbed', 'Unabsorbed'), tRuns: L('রান খরচ', 'Run costs', 'Run cost'),
  place: L('জায়গা', 'Place', 'Place'), month: L('মাস', 'Month', 'Month'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখুন', 'Show', 'Show'),
  open: L('খুলুন', 'Open', 'Open'), version: L('ভার্সন', 'Version', 'Version'),
  mode: L('খরচ ধরার পদ্ধতি', 'Costing method', 'Costing method'), mOff: L('বন্ধ (শুধু কাঁচামাল — আগের মতো)', 'Off (material only, as before)', 'Off (শুধু material, আগের মতো)'), mRec: L('রেসিপির রেট', 'Recipe rates', 'Recipe rate'), mPool: L('মাসিক পুল ÷ স্বাভাবিক উৎপাদন', 'Monthly pool ÷ normal output', 'Monthly pool ÷ normal output'),
  normal: L('স্বাভাবিক মাসিক উৎপাদন (কেজি)', 'Normal monthly output (kg)', 'Normal monthly output (kg)'), ownerOnly: L('শুধু মালিক বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner বদলাতে পারেন'), blankNote: L('ফাঁকা থাকলে পুল-পদ্ধতিতে খরচ অসম্পূর্ণ দেখাবে', 'Blank = the pool method shows the cost as incomplete', 'Blank হলে pool method-এ cost অসম্পূর্ণ'),
  rows: L('খরচের সারি', 'Cost rows', 'Cost rows'), raw: L('কাঁচামাল', 'Raw material', 'Raw material'), pack: L('প্যাকেজিং', 'Packaging', 'Packaging'), conv: L('রূপান্তর খরচ', 'Conversion cost', 'Conversion cost'),
  batch: L('এক ব্যাচ', 'One batch', 'One batch'), unit: L('প্রতি একক', 'Per unit', 'Per unit'), todayRow: L('আজকের কেনা দাম (শুধু দেখানো — হিসাবে ধরা হয় না)', "Today's purchase price (display only — not booked)", "আজকের কেনা দাম (display only)"),
  gap: L('গড় ও আজকের ফারাক', 'Gap average vs today', 'Gap avg vs today'), gapWarn: L('ফারাক সীমার বেশি', 'Gap above the limit', 'Gap সীমার বেশি'), incomplete: L('রূপান্তর খরচ অসম্পূর্ণ', 'Conversion cost incomplete', 'রূপান্তর খরচ অসম্পূর্ণ'),
  matIncomplete: L('কিছু উপকরণের দাম জানা নেই', 'Some ingredient costs are unknown', 'কিছু ingredient-এর cost অজানা'),
  rates: L('রূপান্তর রেট', 'Conversion rates', 'Conversion rate'), addRate: L('রেট যোগ / বদল', 'Add / change a rate', 'Rate যোগ / বদল'), type: L('ধরন', 'Type', 'Type'), typeNote: L('অন্য — কী লিখুন', 'Other — what is it', 'অন্য — কী'),
  newType: L('☐ অন্য: নতুন ধরন যোগ', '☐ Other: add a new type', '☐ অন্য: নতুন type'), newTypeAsk: L('নতুন খরচের ধরনের নাম', 'Name of the new cost type', 'নতুন type-এর নাম'),
  basis: L('হিসাবের ভিত্তি', 'Basis', 'Basis'), bBatch: L('প্রতি ব্যাচ', 'Per batch', 'Per batch'), bUnit: L('প্রতি কেজি (বেস একক)', 'Per kg (base unit)', 'Per kg (base unit)'), bHour: L('প্রতি শ্রম-ঘণ্টা', 'Per labour-hour', 'Per labour-hour'),
  amount: L('টাকা (ফাঁকা রাখা যায়)', 'Amount (may stay blank)', 'Amount (blank চলে)'), hours: L('প্রতি ব্যাচে ঘণ্টা (নিজে বসান)', 'Hours per batch (type it yourself)', 'Hours per batch (নিজে বসান)'),
  sugg: L('অনুমান', 'Suggestion', 'Suggestion'), suggNote: L('ধাপ থেকে অনুমান — খরচে নিজে থেকে যোগ হয় না', 'from the steps — never added to cost by itself', 'steps থেকে — নিজে থেকে cost-এ যোগ হয় না'),
  retire: L('বন্ধ', 'Retire', 'Retire'), history: L('আগের মান সংরক্ষিত থাকে', 'Previous values are kept', 'আগের মান থাকে'),
  poolHead: L('এই মাসের বাস্তব কারখানা খরচ', 'Actual factory cost of the month', 'এই মাসের actual factory cost'), yearly: L('বছরের খরচ (÷১২)', 'Yearly (÷12)', 'Yearly (÷12)'), oneOff: L('একবারের খরচ', 'One-off', 'One-off'),
  poolNote: L('শো-রুম ও অ্যাডমিন খরচ এখানে নয় — সেগুলো শাখার লাভ-ক্ষতিতে যায়', 'Showroom and admin cost are not here — they go to the branch P&L', 'Showroom ও admin cost এখানে নয় — branch P&L-এ'),
  actual: L('বাস্তব', 'Actual', 'Actual'), absorbed: L('পণ্যে ধরা', 'Absorbed', 'Absorbed'), unabs: L('অনাবশোষিত ওভারহেড', 'Unabsorbed overhead', 'অনাবশোষিত ওভারহেড'), noActual: L('বাস্তব খরচ ঢোকানো নেই', 'no actual entered', 'actual ঢোকানো নেই'),
  total: L('মোট', 'Total', 'Total'), runsHead: L('উৎপাদনের খরচ', 'Production costs', 'Production cost'), mat: L('কাঁচামাল', 'Material', 'Material'), std: L('স্ট্যান্ডার্ড', 'Standard', 'Standard'), act: L('আসল', 'Actual', 'Actual'), out: L('উৎপাদন', 'Output', 'Output'),
  voided: L('বাতিল', 'Void', 'Void'), badNum: L('সংখ্যা ঠিক নয়', 'Number is not valid', 'Number ঠিক নয়'), sqlMissing: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase74)', 'The database part is not installed yet (phase74)', 'Database অংশ চালু হয়নি (phase74)'),
};
const T = (k) => lab(X[k]);
const TYPE_LBL = (t) => lab({ bn: t.label_bn, mix: t.label_bn, en: t.label_en || t.label_bn });
const ERR = { type_note_needed: L('"অন্য" হলে কী তা লিখুন', 'For "Other" write what it is', '"অন্য" হলে কী তা লিখুন'), bad_cost: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount ঠিক নয়'), recipe_not_approved: L('রেসিপি অনুমোদিত নয়', 'The recipe is not approved', 'Recipe approved নয়') };
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/function .* does not exist|schema cache/i.test(m)) return toast(T('sqlMissing')); return fail(e); };
const D = { tab: 'rec', locs: [], loc: null, month: today().slice(0, 7), types: [], recipes: [], items: {}, cfg: {}, pools: [], out: null, rc: null, runs: null, from: today().slice(0, 8) + '01', to: today() };

async function loadBase() {
  const [lo, ty, rc, it, cf] = await Promise.all([sb.from('locations').select('id,name_bn,name_en,kind').order('id'), sb.from('cost_component_types').select('*').eq('active', true).order('code'),
    sb.from('recipes').select('id,item_id,version,active,yield_qty').order('item_id').order('version', { ascending: false }), sb.from('items').select('id,code,name_bn,name_en').eq('item_type', 'finished_good'), sb.from('location_cost_cfg').select('*')]);
  if (ty.error) throw ty.error;
  D.locs = lo.data || []; D.types = ty.data || []; D.recipes = rc.data || []; D.items = Object.fromEntries((it.data || []).map((x) => [x.id, x]));
  D.cfg = Object.fromEntries((cf.data || []).map((c) => [c.location_id, c]));
  if (!D.loc) { const f = D.locs.find((l) => l.kind === 'factory') || D.locs[0]; D.loc = f ? f.id : null; }
}
const locOpts = () => D.locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }))}</option>`).join('');
const itemName = (id) => { const i = D.items[id]; return i ? i.code + ' · ' + lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn }) : '—'; };

/* ---------- tabs ---------- */
function draw() {
  const el = $('#cs_body'); if (!el) return;
  const tabs = [['rec', 'tRec'], ['pool', 'tPool'], ['loc', 'tLoc'], ['true', 'tTrue'], ['runs', 'tRuns']];
  el.innerHTML = `<div class="tabs" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${tabs.map((t) => `<button type="button" data-act="cs_tab" data-v="${t[0]}" class="${D.tab === t[0] ? 'on' : ''}" style="min-width:0;flex:1 1 30%">${esc(T(t[1]))}</button>`).join('')}</div><div id="cs_pane">${pane()}</div>`;
}
const pane = () => (D.tab === 'rec' ? paneRec() : D.tab === 'pool' ? panePool() : D.tab === 'loc' ? paneLoc() : D.tab === 'true' ? paneTrue() : paneRuns());
const locSel = (id) => `<label>${esc(T('place'))}<select id="${id}">${locOpts()}</select></label>`;

/* ---------- recipes ---------- */
function paneRec() {
  return `<div class="card stack">${locSel('cs_loc_r')}</div>` + (D.recipes.length ? D.recipes.map((r) => `<div class="card row between wrap"><b>${esc(itemName(r.item_id))} · v${r.version}${r.active ? '' : ' (off)'}</b><button type="button" class="btn" data-act="cs_open" data-id="${esc(r.id)}">${esc(T('open'))}</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
}
function costBlock(c) {
  const rw = (c.rows || []).map((r) => `<tr><td>${esc(r.row === 'raw' ? T('raw') : r.row === 'packaging' ? T('pack') : T('conv'))}${r.row === 'conversion' && r.mode ? ` <span class="muted">(${esc(r.mode)})</span>` : ''}</td><td style="text-align:right">${money(r.amount)}${r.row === 'conversion' && r.complete === false ? ` <span class="chip warn">${esc(T('incomplete'))}</span>` : ''}</td></tr>`).join('');
  const t = c.today || {};
  return `<table style="width:100%;border-collapse:collapse"><tr><th></th><th style="text-align:right">${esc(T('batch'))}</th></tr>${rw}
    <tr><td><b>${esc(T('batch'))}</b></td><td style="text-align:right"><b>${money(c.batch_cost)}</b></td></tr><tr><td><b>${esc(T('unit'))}</b></td><td style="text-align:right"><b>${money(c.unit_cost)}</b></td></tr></table>
    ${c.complete === false ? `<div class="chip warn">${esc(T('matIncomplete'))}</div>` : ''}
    <div class="card"><b>${esc(T('todayRow'))}</b><div>${esc(T('batch'))}: ${money(t.batch_cost)} · ${esc(T('unit'))}: ${money(t.unit_cost)}</div>
      <div>${esc(T('gap'))}: ${t.gap_pct === null || t.gap_pct === undefined ? '—' : q(t.gap_pct, 2) + '%'} ${t.gap_warn ? `<span class="chip warn">${esc(T('gapWarn'))}</span>` : ''}</div></div>`;
}
async function openRecipe(id) {
  const loc = Number(($('#cs_loc_r') || {}).value) || D.loc; D.loc = loc;
  const [c, g] = await Promise.all([sb.rpc('recipe_cost', { p_recipe: id, p_loc: loc }), sb.rpc('recipe_cost_components_get', { p_recipe: id })]);
  if (c.error) return errMsg(c.error); if (g.error) return errMsg(g.error);
  D.rc = { id, cost: c.data, comp: g.data };
  const comps = (g.data.components || []).map((x) => `<div class="rowcard"><b>${esc(lab({ bn: x.label_bn, mix: x.label_bn, en: x.label_en || x.label_bn }))}${x.type_note ? ' — ' + esc(x.type_note) : ''}</b> · ${esc(x.basis === 'per_batch' ? T('bBatch') : x.basis === 'per_unit' ? T('bUnit') : T('bHour'))}
    · ${x.amount === null ? `<span class="chip warn">${esc(T('incomplete'))}</span>` : money(x.amount)}${x.basis === 'per_labour_hour' ? ' · ' + esc(T('hours')) + ': ' + (x.hours_per_batch === null ? '—' : q(x.hours_per_batch)) : ''}
    <button type="button" class="mini" data-act="cs_rcedit" data-id="${x.id}">${esc(T('addRate'))}</button><button type="button" class="mini" data-act="cs_rcret" data-id="${x.id}">${esc(T('retire'))}</button></div>`).join('');
  D.rc.rows = g.data.components || [];
  openSheet(`<h3>${esc(T('rows'))}</h3>${costBlock(c.data)}<h4>${esc(T('rates'))}</h4>${g.data.incomplete ? `<div class="chip warn">${esc(g.data.flag || T('incomplete'))}</div>` : ''}${comps}
    <div class="muted">${esc(T('history'))} · ${esc(T('sugg'))}: ${q(g.data.suggested_labour_hours, 2)} h (${esc(T('suggNote'))})</div>
    <button type="button" class="btn primary full" data-act="cs_rcnew">${esc(T('addRate'))}</button>`);
}
function rateForm(x) {
  const types = D.types.map((t) => `<option value="${t.code}" ${x && x.type === t.code ? 'selected' : ''}>${esc(TYPE_LBL(t))}</option>`).join('');
  const bs = (v) => ['per_batch', 'per_unit', 'per_labour_hour'].map((b) => `<option value="${b}" ${x && x.basis === b ? 'selected' : ''}>${esc(b === 'per_batch' ? T('bBatch') : b === 'per_unit' ? T('bUnit') : T('bHour'))}</option>`).join('');
  openSheet(`<h3>${esc(T('addRate'))}</h3><div class="stack"><label>${esc(T('type'))}<select id="cr_type">${types}<option value="__new">${esc(T('newType'))}</option></select></label>
    <input id="cr_tnote" maxlength="80" placeholder="${esc(T('typeNote'))}" value="${esc(x ? x.type_note || '' : '')}">
    <label>${esc(T('basis'))}<select id="cr_basis">${bs()}</select></label>
    <label>${esc(T('amount'))}<input id="cr_amt" inputmode="decimal" value="${esc(x && x.amount !== null ? x.amount : '')}"></label>
    <label>${esc(T('hours'))}<input id="cr_hrs" inputmode="decimal" value="${esc(x && x.hours_per_batch !== null && x.hours_per_batch !== undefined ? x.hours_per_batch : '')}"></label>
    <div class="muted">${esc(T('sugg'))}: ${q(D.rc && D.rc.comp ? D.rc.comp.suggested_labour_hours : null, 2)} h — ${esc(T('suggNote'))}</div>
    <button type="button" class="btn primary full" data-act="cs_rcsave">${esc(T('save'))}</button></div>`);
}

/* ---------- pools ---------- */
async function loadPools() {
  const m = D.month + '-01';
  const r = await sb.from('factory_cost_pools').select('*').eq('location_id', D.loc).eq('month', m).eq('active', true);
  if (r.error) throw r.error; D.pools = r.data || [];
}
function panePool() {
  const rows = D.types.map((t) => { const p = D.pools.find((x) => x.component_type === t.code && x.source === 'manual'); const a = D.pools.filter((x) => x.component_type === t.code && x.source === 'allocated').reduce((s, x) => s + Number(x.actual_amount), 0);
    return `<div class="rowcard" data-t="${t.code}"><b>${esc(TYPE_LBL(t))}</b>${a ? ` <span class="chip">${esc(q(a))} (bill)</span>` : ''}<div class="row wrap"><input data-cs-amt inputmode="decimal" placeholder="${esc(T('actual'))}" value="${esc(p ? p.actual_amount : '')}" style="max-width:9rem">
      <label class="row"><input type="checkbox" data-cs-year ${p && p.period_kind === 'year' ? 'checked' : ''}> ${esc(T('yearly'))}</label><label class="row"><input type="checkbox" data-cs-oneoff ${p && p.one_off ? 'checked' : ''}> ${esc(T('oneOff'))}</label>
      <button type="button" class="mini" data-act="cs_poolsave" data-ty="${t.code}">${esc(T('save'))}</button></div></div>`; }).join('');
  return `<div class="card stack">${locSel('cs_loc_p')}<label>${esc(T('month'))}<input type="month" id="cs_month" value="${esc(D.month)}"></label><div class="muted">${esc(T('poolNote'))}</div></div><h4>${esc(T('poolHead'))}</h4>${rows}`;
}

/* ---------- per-location method ---------- */
function paneLoc() {
  return `<div class="muted">${esc(owner() ? T('blankNote') : T('ownerOnly'))}</div>` + D.locs.map((l) => { const c = D.cfg[l.id] || { mode: 'off', normal_monthly_output: null };
    return `<div class="card stack" data-l="${l.id}"><b>${esc(lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }))}</b>
      <label>${esc(T('mode'))}<select data-cs-mode ${owner() ? '' : 'disabled'}><option value="off" ${c.mode === 'off' ? 'selected' : ''}>${esc(T('mOff'))}</option><option value="recipe" ${c.mode === 'recipe' ? 'selected' : ''}>${esc(T('mRec'))}</option><option value="pool" ${c.mode === 'pool' ? 'selected' : ''}>${esc(T('mPool'))}</option></select></label>
      <label>${esc(T('normal'))}<input data-cs-normal inputmode="decimal" ${owner() ? '' : 'disabled'} value="${esc(c.normal_monthly_output ?? '')}"></label>
      ${owner() ? `<button type="button" class="btn" data-act="cs_locsave" data-loc="${l.id}">${esc(T('save'))}</button>` : ''}</div>`; }).join('');
}

/* ---------- true-up / runs ---------- */
function paneTrue() {
  const o = D.out;
  return `<div class="card stack">${locSel('cs_loc_t')}<label>${esc(T('month'))}<input type="month" id="cs_month_t" value="${esc(D.month)}"></label><button type="button" class="btn primary full" data-act="cs_true">${esc(T('show'))}</button></div>` + (o ? `<div class="card">
    ${(o.rows || []).map((r) => `<div class="row between wrap"><span>${esc(lab({ bn: r.label_bn, mix: r.label_bn, en: r.label_en || r.label_bn }))}</span><span>${esc(T('actual'))}: ${r.actual === null ? `<i>${esc(T('noActual'))}</i>` : money(r.actual)} · ${esc(T('absorbed'))}: ${money(r.absorbed)}</span></div>`).join('')}
    <hr><div class="row between"><b>${esc(T('total'))} ${esc(T('actual'))}</b><b>${money(o.actual_total)}</b></div><div class="row between"><b>${esc(T('absorbed'))}</b><b>${money(o.absorbed_total)}</b></div>
    <div class="row between" id="cs_unabs"><b>${esc(T('unabs'))}</b><b>${money(o.unabsorbed_overhead)}</b></div></div>` : '');
}
function paneRuns() {
  const r = D.runs;
  return `<div class="card stack">${locSel('cs_loc_u')}<div class="row wrap"><label>${esc(T('from'))} <input type="date" id="cs_from" value="${esc(D.from)}"></label><label>${esc(T('to'))} <input type="date" id="cs_to" value="${esc(D.to)}"></label></div><button type="button" class="btn primary full" data-act="cs_runs">${esc(T('show'))}</button></div>` +
    (r ? (r.length ? r.map((x) => `<div class="card stack"${x.status === 'void' ? ' style="opacity:.55"' : ''}><div class="row between wrap"><b>${esc(x.code)} · ${esc(String(x.made_at).slice(0, 10))}${x.status === 'void' ? ' (' + esc(T('voided')) + ')' : ''}</b><span class="muted">${esc(T('out'))}: ${q(x.output)}</span></div>
      <div>${esc(T('mat'))}: ${money(x.material_cost)} · ${esc(T('conv'))}: ${money(x.conversion_cost)}${x.conversion_complete === false ? ` <span class="chip warn">${esc(T('incomplete'))}</span>` : ''}</div>
      <div>${esc(T('unit'))}: <b>${money(x.unit_cost)}</b> · ${esc(T('std'))}: ${money(x.std_cost)} · ${esc(T('act'))}: ${money(x.actual_cost)}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`) : '');
}

/* ---------- handlers ---------- */
async function refresh() { try { await loadBase(); if (D.tab === 'pool') await loadPools(); draw(); } catch (e) { errMsg(e); } }
Object.assign(H, {
  cs_tab: async (a) => { D.tab = a.dataset.v; try { if (D.tab === 'pool') await loadPools(); } catch (e) { errMsg(e); } draw(); },
  cs_open: (a) => openRecipe(a.dataset.id).catch(errMsg),
  cs_rcnew: () => { D.rc.edit = null; rateForm(null); },
  cs_rcedit: (a) => { const x = (D.rc.rows || []).find((r) => String(r.id) === a.dataset.id); D.rc.edit = x || null; rateForm(x || null); },
  cs_rcret: async (a) => { const r = await sb.rpc('recipe_cost_component_retire', { p_id: Number(a.dataset.id) }); if (r.error) return errMsg(r.error); toast(T('saved')); openRecipe(D.rc.id).catch(errMsg); },
  cs_rcsave: async () => {
    let type = $('#cr_type').value;
    if (type === '__new') { const nm = window.prompt(T('newTypeAsk')); if (!nm) return; const r = await sb.rpc('cost_type_add', { p_label_bn: nm, p_label_en: null }); if (r.error) return errMsg(r.error); type = r.data.code; await loadBase(); }
    const amt = num($('#cr_amt').value), hrs = num($('#cr_hrs').value);
    if (Number.isNaN(amt) || Number.isNaN(hrs)) return toast(T('badNum'));
    const r = await sb.rpc('recipe_cost_component_set', { p_recipe: D.rc.id, p_type: type, p_basis: $('#cr_basis').value, p_amount: amt, p_hours: hrs, p_type_note: $('#cr_tnote').value || null, p_note: null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); openRecipe(D.rc.id).catch(errMsg);
  },
  cs_poolsave: async (a) => {
    const card = a.closest('[data-t]'); const amt = num(card.querySelector('[data-cs-amt]').value); if (amt === null || Number.isNaN(amt)) return toast(T('badNum'));
    const r = await sb.rpc('pool_set', { p_loc: D.loc, p_month: D.month + '-01', p_type: a.dataset.ty, p_amount: amt, p_period_kind: card.querySelector('[data-cs-year]').checked ? 'year' : 'month', p_one_off: card.querySelector('[data-cs-oneoff]').checked, p_note: null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); await loadPools(); draw();
  },
  cs_locsave: async (a) => {
    const card = a.closest('[data-l]'); const n = num(card.querySelector('[data-cs-normal]').value); if (Number.isNaN(n)) return toast(T('badNum'));
    const r = await sb.rpc('loc_cost_cfg_set', { p_loc: Number(a.dataset.loc), p_mode: card.querySelector('[data-cs-mode]').value, p_normal: n });
    if (r.error) return errMsg(r.error); toast(T('saved')); await refresh();
  },
  cs_true: async () => { const r = await sb.rpc('overhead_trueup', { p_loc: D.loc, p_month: D.month + '-01' }); if (r.error) return errMsg(r.error); D.out = r.data; draw(); },
  cs_runs: async () => { D.from = $('#cs_from').value || D.from; D.to = $('#cs_to').value || D.to; const r = await sb.rpc('production_run_costs', { p_loc: D.loc, p_from: D.from, p_to: D.to }); if (r.error) return errMsg(r.error); D.runs = r.data || []; draw(); },
});
document.addEventListener('change', async (e) => {
  const t = e.target; if (!t || !t.id) return;
  if (/^cs_loc_[rptu]$/.test(t.id)) { D.loc = Number(t.value); try { if (D.tab === 'pool') await loadPools(); } catch (x) { errMsg(x); } D.out = null; D.runs = null; draw(); }
  if (t.id === 'cs_month' || t.id === 'cs_month_t') { D.month = t.value || D.month; try { if (D.tab === 'pool') await loadPools(); } catch (x) { errMsg(x); } D.out = null; draw(); }
  if (t.id === 'cr_type' && t.value === '__new') { /* the name is asked on save */ }
});

async function view() {
  shell(T('title'), `<div id="cs_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try {
    let ok = owner(); if (!ok) { try { ok = !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { ok = false; } }
    if (!ok) { const b = $('#cs_body'); if (b) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
    await loadBase(); draw();
  } catch (e) { const b = $('#cs_body'); if (b && /not allowed|permission/i.test((e && e.message) || '')) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; else errMsg(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { costing: view });
})();
