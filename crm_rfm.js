/* Islamia BOS · Customer value (#/crmvalue). Package CRM-C. How loyal and how valuable are our customers: repeat-purchase rate, average lifetime value, customer labels (Champion, Loyal, At risk ...)
   made from the owner's own cut-offs, the lapsed and at-risk lists, the biggest customers, and (for people who may see cost) which customers earn us the most.
   Server: supabase/phase306.sql (scores, settings), phase308.sql (overview, labels, lists, profit). The screen only asks; the server decides every call.
   Spend is net of returns. Lifetime value here is what the customer has really spent, not a forecast. Nothing is sent to anyone from here.
   Register the route only through web/ia.js and add the script tag in index.html (integrator, see docs/integration/CRM-C.md).
   English labels only for now (the owner will translate them later). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const money = (n) => (n === null || n === undefined ? '-' : '৳' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 }));
const pct = (n) => (n === null || n === undefined ? '-' : Number(n).toFixed(1) + '%');
const dt = (v) => (v ? String(v).replace('T', ' ').slice(0, 16) : '-');
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const ERR = { not_allowed: 'You do not have permission.', set_winback_days: 'Type how many days first (or ask the owner to set it in Settings).', bad_range: 'Choose a period of at most 400 days.', bad_value: 'That value is not allowed.', cost_data_missing: 'Cost data is not set up.' };
const eText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
const SORTS = [['lifetime', 'Total spent'], ['last12m', 'Spent in 12 months'], ['orders', 'Number of orders'], ['avg_bill', 'Average bill'], ['silent_longest', 'Longest not seen'], ['due', 'Amount owed']];
const D = { tab: 'overview', me: null, status: null, ov: null, sum: null, label: null, list: null, outlet: '', outlets: [], lapsedKind: 'lapsed', days: '', sort: 'lifetime', from: '', to: '', profit: null, offset: 0 };

async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; }
  return r.data;
}
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const tile = (label, value, id, sub) => `<div class="card cv-tile" ${id ? `id="${id}"` : ''}><div class="muted">${esc(label)}</div><b style="font-size:1.4rem">${esc(String(value ?? '-'))}</b>${sub ? `<div class="muted">${esc(sub)}</div>` : ''}</div>`;

function tabsBar() {
  const tabs = [['overview', 'Overview'], ['labels', 'Labels'], ['lapsed', 'Lapsed'], ['top', 'Top customers']].concat(D.me && D.me.cost ? [['profit', 'Profit']] : []);
  return `<div class="row wrap" id="cv_tabs" style="gap:.3rem">${tabs.map(([k, l]) => `<button type="button" class="tog ${D.tab === k ? 'on' : ''}" data-act="cv_tab" data-v="${k}">${esc(l)}</button>`).join('')}</div>`;
}
function freshHTML() {
  const s = D.status || {};
  const note = s.never_scored ? `${s.never_scored} customers have no score yet. ` : '';
  return `<div class="card" id="cv_fresh"><div class="row between"><span class="muted">Scores last updated ${esc(dt(s.newest))}</span>${D.me && D.me.run ? '<button data-act="cv_refresh" id="cv_refresh">Refresh scores</button>' : ''}</div>
    ${note || s.stale ? `<div class="muted">${esc(note)}${s.stale ? esc(String(s.stale)) + ' scores are older than the latest sales.' : ''}</div>` : ''}</div>`;
}
function memberRows(rows) {
  return (rows || []).map((r) => `<div class="card cv-mem"><div class="row between"><b>${esc(r.name)}</b>${r.label ? chip(r.label) : ''}</div><div class="muted">${esc(r.mobile || '')}</div>
    <div class="muted">${r.last_visit ? 'Last visit ' + esc(r.last_visit) + ' (' + esc(String(r.days_since_last)) + ' days ago)' : 'No visit yet'} · ${esc(String(r.orders_total ?? 0))} orders · total ${esc(money(r.lifetime_spend))} · 12 months ${esc(money(r.spend_12m))}${Number(r.due_amount) > 0 ? ' · owes ' + esc(money(r.due_amount)) : ''}</div></div>`).join('');
}
function pager(list) {
  if (!list) return '';
  const more = (list.offset + list.rows.length) < list.total;
  return `<div class="muted" id="cv_pg_sum">${esc(String(list.total))} customers${list.masked ? ' · phone numbers are hidden for you' : ''}</div><div class="stack" id="cv_rows">${memberRows(list.rows) || '<p class="muted">Nobody.</p>'}</div>
    <div class="row">${list.offset > 0 ? `<button data-act="cv_page" data-v="${Math.max(list.offset - 50, 0)}">Previous 50</button>` : ''}${more ? `<button class="primary" data-act="cv_page" data-v="${list.offset + 50}">Next 50</button>` : ''}</div>`;
}
function overviewHTML() {
  const o = D.ov; if (!o) return '<p class="muted">…</p>';
  const outlets = `<div class="row"><label for="cv_outlet" class="muted">Outlet</label><select id="cv_outlet" data-act="cv_outlet"><option value="">All outlets</option>${D.outlets.map((x) => `<option value="${esc(x.id)}" ${String(D.outlet) === String(x.id) ? 'selected' : ''}>${esc(x.name)}</option>`).join('')}</select></div>`;
  return outlets + `<div class="stack">${tile('Customers who bought', o.buyers, 'cv_buyers', o.customers_scored + ' scored')}
    ${tile('Repeat-purchase rate', pct(o.repeat_rate_pct), 'cv_repeat', o.repeat_buyers + ' bought more than once')}
    ${tile('Average lifetime value', money(o.avg_lifetime_value), 'cv_ltv', 'middle customer ' + money(o.median_lifetime_value))}
    ${tile('At risk', o.at_risk, 'cv_atrisk', 'good customers gone quiet')}</div>
    <details><summary>More numbers</summary><div class="stack">${tile('Repeat rate, last 12 months', pct(o.repeat_rate_12m_pct), 'cv_repeat12', o.active_12m + ' bought in 12 months')}
      ${tile('New customers, last 12 months', o.new_12m)}${tile('Spent in the last 12 months', money(o.spend_12m))}${tile('Biggest tenth holds', pct(o.top_tenth_share_pct), null, 'of all money spent')}
      ${tile('Owing money', o.owing_customers, null, money(o.owed_total))}${tile('Not seen for ' + (o.winback_days ? o.winback_days + '+ days' : 'many days'), o.lapsed === null ? 'set days' : o.lapsed, 'cv_lapsed', o.lapsed === null ? 'The owner sets the days in Settings' : '')}</div></details>
    <p class="muted" id="cv_note">${esc(o.note)}</p>`;
}
function labelsHTML() {
  const s = D.sum; if (!s) return '<p class="muted">…</p>';
  const missing = s.mode !== 'owner' ? '<div class="notice" id="cv_std">These are the standard labels. The owner can set three numbers in Settings (recent days, frequent orders, big-spender amount) to use your own cut-offs.</div>' : '';
  const rows = (s.labels || []).map((l) => `<div class="card cv-label"><div class="row between"><b>${esc(l.label)}</b>${chip(l.customers + ' customers (' + pct(l.share_pct) + ')')}</div>
    <div class="muted">Average total spent ${esc(money(l.avg_lifetime_value ?? l.avg_lifetime_spend))} · 12 months ${esc(money(l.spend_12m))}</div><button data-act="cv_label" data-v="${esc(l.label)}">Show customers</button></div>`).join('');
  return missing + `<p class="muted" id="cv_explain">${esc(s.explain)}</p>` + rows + (D.label ? `<h3>${esc(D.label)}</h3>` + pager(D.list) : '');
}
function lapsedHTML() {
  const kinds = [['lapsed', 'Not seen for N days'], ['at_risk', 'At risk']].map(([k, l]) => `<button type="button" class="tog ${D.lapsedKind === k ? 'on' : ''}" data-act="cv_kind" data-v="${k}">${esc(l)}</button>`).join('');
  const days = D.lapsedKind === 'lapsed' ? `<div class="row"><label for="cv_days" class="muted">Days</label><input id="cv_days" inputmode="numeric" value="${esc(D.days)}" style="max-width:6rem"><button class="primary" data-act="cv_lapsedgo" id="cv_go">Show</button></div>` : '<div class="row"><button class="primary" data-act="cv_lapsedgo" id="cv_go">Show</button></div>';
  return `<div class="row wrap">${kinds}</div>${days}${D.list ? pager(D.list) : '<p class="muted">Press Show.</p>'}`;
}
function topHTML() {
  return `<div class="row"><label for="cv_sort" class="muted">Order by</label><select id="cv_sort" data-act="cv_sort">${SORTS.map(([k, l]) => `<option value="${k}" ${D.sort === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>${pager(D.list)}`;
}
function profitHTML() {
  const p = D.profit;
  const form = `<div class="row wrap"><label for="cv_from" class="muted">From</label><input id="cv_from" type="date" value="${esc(D.from)}"><label for="cv_to" class="muted">To</label><input id="cv_to" type="date" value="${esc(D.to)}"><button class="primary" data-act="cv_profitgo" id="cv_pgo">Show</button></div>`;
  if (!p) return form;
  const rows = p.rows.map((r) => `<div class="card cv-profit"><div class="row between"><b>${esc(r.name)}</b>${r.cost_partial ? chip('some cost unknown', 'warn') : ''}</div><div class="muted">${esc(r.mobile || '')}</div>
    <div class="muted">Sold ${esc(money(r.revenue))} · cost ${esc(money(r.cogs))} · profit ${esc(money(r.margin))}${r.margin_pct === null ? '' : ' (' + esc(pct(r.margin_pct)) + ')'}${Number(r.unknown_cost_revenue) ? ' · ' + esc(money(r.unknown_cost_revenue)) + ' sold with no known cost' : ''}</div></div>`).join('');
  const more = (p.offset + p.rows.length) < p.customers;
  return form + `<p class="muted" id="cv_psum">${esc(String(p.customers))} customers · ${esc(money(p.customer_revenue))} of ${esc(money(p.all_revenue))} sold to named customers</p><div class="stack" id="cv_prows">${rows || '<p class="muted">Nothing sold in this period.</p>'}</div>
    <div class="row">${p.offset > 0 ? `<button data-act="cv_ppage" data-v="${Math.max(p.offset - 50, 0)}">Previous 50</button>` : ''}${more ? `<button class="primary" data-act="cv_ppage" data-v="${p.offset + 50}">Next 50</button>` : ''}</div><p class="muted">${esc(p.note)}</p>`;
}
function draw() {
  const el = $('#cv_body'); if (!el) return;
  const pane = ({ overview: overviewHTML, labels: labelsHTML, lapsed: lapsedHTML, top: topHTML, profit: profitHTML })[D.tab]();
  el.innerHTML = freshHTML() + tabsBar() + `<div id="cv_pane">${pane}</div>`;
}
async function load(tab) {
  D.tab = tab || D.tab; D.offset = 0;
  if (D.tab === 'overview') D.ov = await call('crmc_overview', { p_outlet: D.outlet ? Number(D.outlet) : null });
  if (D.tab === 'labels') { D.sum = await call('crmc_rfm_summary', {}); D.list = null; D.label = null; }
  if (D.tab === 'lapsed') { D.list = null; if (!D.days && D.status && D.status.winback_days) D.days = String(D.status.winback_days); if (D.lapsedKind === 'at_risk') D.list = await call('crmc_lapsed', { p_days: null, p_kind: 'at_risk', p_limit: 50, p_offset: 0 }); }
  if (D.tab === 'top') D.list = await call('crmc_value_list', { p_sort: D.sort, p_limit: 50, p_offset: 0 });
  if (D.tab === 'profit') { if (!D.to) { D.to = today(); D.from = addDays(D.to, -29); } }
}
async function show(tab) { try { await load(tab); draw(); } catch (e) { toast(e.message || 'error'); draw(); } }
async function relist() {
  if (D.tab === 'labels' && D.label) D.list = await call('crmc_rfm_list', { p_label: D.label, p_sort: 'lifetime', p_limit: 50, p_offset: D.offset });
  else if (D.tab === 'top') D.list = await call('crmc_value_list', { p_sort: D.sort, p_limit: 50, p_offset: D.offset });
  else if (D.tab === 'lapsed') D.list = await call('crmc_lapsed', { p_days: D.lapsedKind === 'lapsed' ? Number(norm(D.days)) : null, p_kind: D.lapsedKind, p_limit: 50, p_offset: D.offset });
}

Object.assign(H, {
  cv_tab: (a) => show(a.dataset.v),
  cv_refresh: act(async () => {
    const r = await call('crmc_metrics_refresh', { p_dry: false, p_limit: null });
    toast('Scored ' + r.processed + (r.remaining ? ', ' + r.remaining + ' left: press again' : ', all up to date')); D.status = await call('crmc_metrics_status', {}); await load(); draw();
  }),
  cv_outlet: act(async (a) => { D.outlet = a.value; await load('overview'); draw(); }),
  cv_label: act(async (a) => { D.label = a.dataset.v; D.offset = 0; await relist(); draw(); }),
  cv_page: act(async (a) => { D.offset = Number(a.dataset.v); await relist(); draw(); }),
  cv_kind: act(async (a) => { D.lapsedKind = a.dataset.v; await load('lapsed'); draw(); }),
  cv_lapsedgo: act(async () => {
    const el = $('#cv_days'); if (el) D.days = el.value;
    if (D.lapsedKind === 'lapsed') { const n = Number(norm(D.days)); if (!n || n < 1) return toast(ERR.set_winback_days); }
    D.offset = 0; await relist(); draw();
  }),
  cv_sort: act(async (a) => { D.sort = a.value; D.offset = 0; await relist(); draw(); }),
  cv_profitgo: act(async () => {
    D.from = ($('#cv_from') || {}).value || D.from; D.to = ($('#cv_to') || {}).value || D.to; D.offset = 0;
    D.profit = await call('crmc_profit', { p_from: D.from, p_to: D.to, p_sort: 'margin', p_limit: 50, p_offset: 0 }); draw();
  }),
  cv_ppage: act(async (a) => { D.profit = await call('crmc_profit', { p_from: D.from, p_to: D.to, p_sort: 'margin', p_limit: 50, p_offset: Number(a.dataset.v) }); draw(); }),
});
document.addEventListener('change', (e) => {
  const a = e.target && e.target.closest && e.target.closest('select[data-act="cv_outlet"],select[data-act="cv_sort"]'); if (a) Promise.resolve(H[a.dataset.act](a)).catch(fail);
});

async function view() {
  if (B && B.loadStatic) await B.loadStatic();
  shell('Customer value', '<div id="cv_body"><p class="muted">…</p></div>', true);
  try {
    D.me = await call('crmc_me', {});
    if (!D.me.view) { $('#cv_body').innerHTML = '<p class="muted" id="cv_noperm">You do not have permission to see customer value.</p>'; return; }
    D.status = await call('crmc_metrics_status', {});
    const loc = await sb.from('locations').select('id,name_en,name_bn').eq('is_active', true).order('sort'); D.outlets = ((loc && loc.data) || []).map((x) => ({ id: x.id, name: x.name_en || x.name_bn }));
    await show('overview');
  } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmvalue: view });
})();
