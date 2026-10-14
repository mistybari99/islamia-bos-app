/* Islamia BOS · Step W: unknown-cost board (#/costunknown). A small page for the owner / cost-right holders that shows, in one place, where profit is "provisional" because a cost is unknown:
   - sales whose cost is neither in the stock ledger nor in the item cost (unknown_cost_rev) and sales priced with the fallback cost, from profit_source_check (phase72)
   - production runs finished without a full cost (production_runs.cost_complete = false)
   - active tracked items with no cost on file (items_with_cost)
   - the switch production_requires_cost (warn / refuse) next to the system's recommendation
   It does not touch biz.js / reports.js; ia.js links here. Costs are shown only to those the server allows (the calls refuse everyone else). Handlers are prefixed wcb_. English mode has no Bangla letters. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.w) return;
const { sb, esc, shell } = A;
const L = B.L, lab = B.lab, W = B.w;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('অজানা খরচ', 'Unknown costs', 'অজানা cost'),
  intro: L('যেখানে খরচ জানা নেই সেখানে লাভের অঙ্ক সাময়িক। এখানে সেই জায়গাগুলো একসাথে দেখুন। কোনো অঙ্ক নিজে থেকে বসানো হয় না।', 'Where a cost is unknown the profit figure is provisional. See those places together here. No figure is ever filled in by itself.', 'যেখানে cost জানা নেই সেখানে profit সাময়িক। সেই জায়গাগুলো একসাথে দেখুন। কোনো অঙ্ক নিজে থেকে বসানো হয় না।'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখুন', 'Show', 'Show'),
  sec1: L('বিক্রি: খরচ অজানা', 'Sales: cost unknown', 'Sale: cost অজানা'), rev: L('নিট বিক্রি', 'Net sales', 'Net sale'), unk: L('সাময়িক: খরচহীন বিক্রি', 'Provisional: sales with no cost', 'সাময়িক: খরচহীন sale'),
  share: L('মোট বিক্রির অংশ', 'share of net sales', 'মোট sale-এর অংশ'), fb: L('পুরনো খরচে ধরা বিক্রি', 'Sales costed from the item cost', 'Item cost-এ ধরা sale'), fbc: L('সেই খরচ', 'that cost', 'সেই cost'),
  led: L('stock খাতার খরচ', 'Cost from the stock ledger', 'Stock ledger-এর cost'), diff: L('খাতার সাথে ফারাক', 'Difference from the books', 'Books-এর সাথে ফারাক'),
  agree: L('হিসাব মিলেছে ✓', 'The figures agree ✓', 'Figure মিলেছে ✓'), noJournal: L('হিসাবের খাতা চালু নেই', 'The books are not on', 'Books চালু নেই'),
  n_fallback_used: L('কিছু বিক্রির খরচ পুরনো item cost থেকে', 'Some sales use the item cost, not the ledger', 'কিছু sale-এর cost item cost থেকে'),
  n_unknown_cost: L('কিছু বিক্রির কোনো খরচ নেই', 'Some sales have no cost at all', 'কিছু sale-এর কোনো cost নেই'),
  n_journal_pending: L('কিছু বিক্রি এখনও হিসাবের খাতায় ওঠেনি', 'Some sales are not in the books yet', 'কিছু sale এখনও books-এ ওঠেনি'),
  n_journal_unavailable: L('হিসাবের খাতার সাথে তুলনা করা গেল না', 'Could not compare with the books', 'Books-এর সাথে তুলনা করা গেল না'),
  sec2: L('উৎপাদন: খরচ অসম্পূর্ণ', 'Production: cost incomplete', 'Production: cost অসম্পূর্ণ'), sec3: L('আইটেম: কোনো খরচ বসানো নেই', 'Items with no cost on file', 'Item: কোনো cost বসানো নেই'),
  item: L('আইটেম', 'Item', 'Item'), batches: L('ব্যাচ', 'Batches', 'Batch'), place: L('জায়গা', 'Place', 'Place'),
  more: L('আরও আছে — প্রথম ৫০টি দেখানো হলো', 'More exist - the first 50 are shown', 'আরও আছে — প্রথম ৫০টি দেখানো হলো'),
  fix: L('খরচ বসাতে', 'To fill a cost', 'Cost বসাতে'), items: L('আইটেম', 'Items', 'Items'), purchase: L('ক্রয়', 'Purchases', 'Purchases'), biz: L('লাভ-ক্ষতি', 'Profit & loss', 'Profit-Loss'), reports: L('রিপোর্ট', 'Reports', 'Reports'),
  swTitle: L('উপকরণের খরচ অজানা থাকলে উৎপাদন', 'Production when an ingredient cost is unknown', 'Ingredient cost অজানা থাকলে production'),
  c_warn: L('সতর্কতা (চলতে দিন)', 'Warn (let it go on)', 'Warn (চলতে দিন)'), c_refuse: L('আটকান', 'Refuse', 'Refuse'),
  rWarn: L('এখনও অনেক উপকরণের খরচ বসানো নেই; এখন আটকালে উৎপাদনই থেমে যাবে। আগে খরচ বসান, তারপর "আটকান" করুন।', 'Some costs are still missing; refusing now would stop production. Fill the costs first, then switch to Refuse.', 'এখনও অনেক ingredient-এর cost বসানো নেই; এখন আটকালে production থেমে যাবে। আগে cost বসান, তারপর Refuse করুন।'),
  rRefuse: L('কোনো অসম্পূর্ণ উৎপাদন বা খরচহীন আইটেম নেই — "আটকান" নিরাপদ, ভবিষ্যতে খরচহীন তৈরি মাল ঢুকবে না।', 'No incomplete production or cost-less item is left - Refuse is safe and keeps cost-less finished goods out.', 'কোনো অসম্পূর্ণ production বা cost-ছাড়া item নেই — Refuse নিরাপদ, ভবিষ্যতে cost-ছাড়া finished good ঢুকবে না।'),
  noperm: L('খরচ দেখার অধিকার লাগবে', 'The cost right is needed', 'Cost দেখার অধিকার লাগবে'), loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing here ✓', 'কিছু নেই ✓'),
};
const T = (k) => lab(X[k]);
const D = { from: null, to: null, loc: '' };
const pct = (a, b) => (b > 0 ? Math.round((a / b) * 1000) / 10 + '%' : '—');

// the recommendation for production_requires_cost, from what this page found (pure, tested)
function recommend(unkRev, badRuns, noCostItems) { return unkRev > 0 || badRuns > 0 || noCostItems > 0 ? 'warn' : 'refuse'; }

async function view() {
  await W.locs();
  D.from = D.from || W.today().slice(0, 8) + '01'; D.to = D.to || W.today();
  shell(T('title'), `${W.links([['biz', X.biz], ['reports', X.reports], ['items', X.items], ['purchase', X.purchase]])}<p class="muted">${esc(T('intro'))}</p>
    <div class="row wrap"><label>${esc(T('from'))}<input type="date" id="wcb_f" value="${esc(D.from)}"></label><label>${esc(T('to'))}<input type="date" id="wcb_t" value="${esc(D.to)}"></label>
    <select id="wcb_l">${W.locOpts(D.loc, true)}</select></div><button class="primary full" data-act="wcb_go">${esc(T('show'))}</button>
    <div id="wcb_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  W.setRedraw(draw); return draw();
}
async function draw() {
  const el = $('#wcb_body'); if (!el) return;
  const loc = D.loc === '' ? null : Number(D.loc);
  const [pc, runs, ic, its] = await Promise.all([
    sb.rpc('profit_source_check', { p_from: D.from, p_to: D.to, p_loc: loc }),
    sb.from('production_runs').select('id,item_id,location_id,made_at,cost_complete').eq('cost_complete', false).order('made_at', { ascending: false }).limit(50),
    sb.rpc('items_with_cost'),
    sb.from('items').select('id,code,name_bn,name_en,tracked,is_active').eq('is_active', true).eq('tracked', true).order('code').limit(1000),
  ]);
  if (pc.error && /not allowed/i.test(pc.error.message || '') && ic.error) { el.innerHTML = `<div class="notice warn">${esc(T('noperm'))}</div>`; return; }
  const items = Object.fromEntries((its.data || []).map((i) => [i.id, i]));
  let h = '';
  if (pc.error) h += `<div class="notice warn">${esc(W.errText(pc.error) || pc.error.message)}</div>`;
  else {
    const d = pc.data, unk = Number(d.unknown_cost_rev) || 0;
    h += `<h3>${esc(T('sec1'))}</h3><div class="card ${unk > 0 ? 'bad' : ''}"><div class="row between"><span>${esc(T('rev'))}</span><b>${esc(W.q(d.net_revenue))}</b></div>
      <div class="row between"><span>${esc(T('unk'))}</span><b>${esc(W.q(unk))}</b></div><div class="muted">${esc(pct(unk, Number(d.net_revenue)))} ${esc(T('share'))}</div>
      <div class="row between"><span>${esc(T('fb'))}</span><span>${esc(W.q(d.fallback_rev))} · ${esc(T('fbc'))} ${esc(W.q(d.fallback_cogs))}</span></div>
      <div class="row between"><span>${esc(T('led'))}</span><span>${esc(W.q(d.ledger_cogs))}</span></div>
      <div class="row between"><span>${esc(T('diff'))}</span><span>${d.difference === null || d.difference === undefined ? esc(T('noJournal')) : esc(W.q(d.difference))}</span></div>
      ${d.agree ? `<div class="notice info">${esc(T('agree'))}</div>` : (d.notes || []).map((n) => `<div class="notice warn">${esc(X['n_' + n] ? T('n_' + n) : n)}</div>`).join('')}</div>`;
  }
  const bad = runs.error ? [] : (runs.data || []);
  h += `<h3>${esc(T('sec2'))}</h3>` + (runs.error ? `<p class="muted">${esc(T('noperm'))}</p>` : bad.length ? bad.map((r) => `<div class="card"><b>${esc(W.nmItem(items[r.item_id]))}</b><div class="muted">${esc(W.day(r.made_at))} · ${esc(W.locName(r.location_id))}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
  let nocost = [];
  if (!ic.error && !its.error) { const has = new Set((ic.data || []).filter((c) => Number(c.cost_price) > 0).map((c) => c.item_id)); nocost = (its.data || []).filter((i) => !has.has(i.id)); }
  h += `<h3>${esc(T('sec3'))}</h3>` + (ic.error ? `<p class="muted">${esc(T('noperm'))}</p>` : nocost.length ? nocost.slice(0, 50).map((i) => `<div class="card">${esc(W.nmItem(i))}</div>`).join('') + (nocost.length > 50 ? `<p class="muted">${esc(T('more'))}</p>` : '') : `<p class="muted">${esc(T('none'))}</p>`);
  h += `<p class="muted">${esc(T('fix'))}: ${esc(T('items'))} · ${esc(T('purchase'))}</p>`;
  const rec = recommend(pc.error ? 0 : Number(pc.data.unknown_cost_rev) || 0, bad.length, nocost.length);
  h += W.recCard({ key: 'production_requires_cost', kind: 'choice', label: T('swTitle'), current: B.rule ? B.rule('production_requires_cost', 'warn') : 'warn', recommended: rec, reason: rec === 'warn' ? T('rWarn') : T('rRefuse'),
    choices: [{ v: 'warn', l: X.c_warn }, { v: 'refuse', l: X.c_refuse }] });
  el.innerHTML = h;
}
A.H = A.H || {};
Object.assign(A.H, { wcb_go: () => { D.from = ($('#wcb_f') || {}).value || D.from; D.to = ($('#wcb_t') || {}).value || D.to; D.loc = ($('#wcb_l') || {}).value || ''; return draw(); } });
B.costboard = { X, T, recommend, pct };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { costunknown: view });
})();
