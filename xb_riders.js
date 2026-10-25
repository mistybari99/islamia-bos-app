/* Islamia BOS · XB riders, delivery status and cash on delivery (#/riders).
   Three parts: (1) delivery jobs of the place with the next status step; (2) assign an open home or courier order to a rider and a zone;
   (3) cash on delivery: check a day (rider by rider), record a deposit, and explain an open difference case.
   Writes: xb_delivery_assign, xb_delivery_move, xb_cod_reconcile (checking a day can open one case per rider where collected and deposited differ),
   xb_cod_deposit, xb_cod_case_explain. Reads: delivery_jobs, riders, delivery_zones, cod_cases, online_orders (own RLS).
   No SMS or message is sent to a rider or a customer, and no cash is posted to the books from this screen. Server: supabase/phase493.sql.
   Rider and zone set-up (rider_manage) is not on this screen. UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const t = (k) => A.t(k);
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const ERR = [
  ['not allowed', 'xc_err_not_allowed'], ['module_off', 'xc_err_off'], ['order_closed', 'xb_err_order_closed'], ['rider_not_found_or_inactive', 'xb_rd_err_rider'],
  ['rider_other_location', 'xb_rd_err_rider_place'], ['zone_not_found_or_inactive', 'xb_rd_err_zone'], ['reason_required', 'xb_err_note'], ['too_many_attempts', 'xb_rd_err_attempts'],
  ['bad_amount', 'xb_err_amount'], ['bad_status', 'xb_err_status'], ['not_found', 'xb_err_not_found'], ['case_closed', 'xb_rd_err_closed'],
];
const eText = (e) => {
  const m = String((e && e.message) || '');
  const hit = ERR.find(([k]) => m.includes(k));
  return hit ? t(hit[1]) : t('err_generic') + (m ? ' · ' + m.slice(0, 80) : '');
};
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) throw new Error(r.error.message || 'error');
  return r.data;
}
function places() {
  const all = (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : (B.ENV && B.ENV.locs) || []);
  return S.ctx && (S.ctx.is_owner || (S.ctx.roles || []).includes('management')) ? all : all.filter((l) => S.ctx && (S.ctx.locations || []).includes(l.id));
}
const riderName = (r) => (r ? (r.name_en || r.name_bn || '') : '');
const STATE = ['unassigned', 'assigned', 'out', 'delivered', 'failed', 'returned'];

const U = { loc: '', day: today(), tab: 'jobs', jobs: [], riders: [], zones: [], orders: [], check: null, cases: [], busy: false };

// ---------- drawing ----------
function riderSel(id, sel) {
  return `<select id="${id}"><option value="">${esc(t('xb_rd_pick_rider'))}</option>${U.riders.map((r) => `<option value="${esc(String(r.id))}" ${String(sel) === String(r.id) ? 'selected' : ''}>${esc(riderName(r))}</option>`).join('')}</select>`;
}
function jobActions(j) {
  const id = esc(String(j.id));
  if (j.state === 'assigned') return `<button type="button" class="primary" data-act="rd_move" data-id="${id}" data-v="out">${esc(t('xb_rd_act_out'))}</button>`;
  if (j.state === 'out') return `<div class="row wrap"><label>${esc(t('xb_rd_cod_amt'))} <input id="rd_cod${id}" inputmode="decimal" value="${esc(j.cod_amount === null || j.cod_amount === undefined ? '' : String(j.cod_amount))}"></label>
      <button type="button" class="primary" data-act="rd_move" data-id="${id}" data-v="delivered">${esc(t('xb_rd_act_delivered'))}</button></div>
      <div class="row wrap"><label>${esc(t('xb_rd_reason'))} <input id="rd_rs${id}" maxlength="300" autocomplete="off"></label>
      <button type="button" class="btn" data-act="rd_move" data-id="${id}" data-v="failed">${esc(t('xb_rd_act_failed'))}</button></div>`;
  if (j.state === 'failed') return `<div class="row wrap"><button type="button" class="primary" data-act="rd_move" data-id="${id}" data-v="reattempt">${esc(t('xb_rd_act_reattempt'))}</button>
      <button type="button" class="btn" data-act="rd_move" data-id="${id}" data-v="returned">${esc(t('xb_rd_act_returned'))}</button></div>`;
  return '';
}
function jobsHTML() {
  if (!U.loc) return `<div class="notice">${esc(t('xc_pick_place'))}</div>`;
  if (!U.jobs.length) return `<p class="muted">${esc(t('xb_rd_none_jobs'))}</p>`;
  const rName = (id) => riderName(U.riders.find((r) => String(r.id) === String(id)));
  return U.jobs.map((j) => `<div class="card stack rd-job">
      <div class="row between wrap"><b>#${esc(String((j.online_orders || {}).order_no || ''))}</b>${chip(t('xb_rd_state_' + j.state) || j.state, j.state === 'delivered' ? 'ok' : j.state === 'failed' || j.state === 'returned' ? 'bad' : '')}</div>
      <div class="muted">${esc(t('xb_rd_rider'))}: ${esc(rName(j.rider_id) || '—')} · ${esc(t('xb_rd_zone'))}: ${esc(j.zone_code || '—')} · ${esc(t('xb_rd_fee'))}: ${esc(String(j.fee ?? '—'))}</div>
      ${j.failed_reason ? `<div class="muted">${esc(t('xb_rd_reason'))}: ${esc(j.failed_reason)}</div>` : ''}
      ${jobActions(j)}</div>`).join('');
}
function assignHTML() {
  const taken = new Set(U.jobs.map((j) => String(j.order_id)));
  const open = U.orders.filter((o) => !taken.has(String(o.id)));
  return `<div class="card stack"><b>${esc(t('xb_rd_assign'))}</b>
    <label>${esc(t('xb_rd_order'))} <select id="rd_ord"><option value="">${esc(t('xb_rd_pick_order'))}</option>${open.map((o) => `<option value="${esc(o.id)}">#${esc(String(o.order_no))} · ${esc(o.customer_name || '')} · ${esc(t('xb_rd_mode_' + o.delivery_mode) || o.delivery_mode)}</option>`).join('')}</select></label>
    ${open.length ? '' : `<div class="muted">${esc(t('xb_rd_none_orders'))}</div>`}
    <label>${esc(t('xb_rd_rider'))} ${riderSel('rd_rid', '')}</label>
    <label>${esc(t('xb_rd_zone'))} <select id="rd_zone"><option value="">${esc(t('xb_rd_pick_zone'))}</option>${U.zones.map((z) => `<option value="${esc(z.code)}">${esc(nm(z) || z.code)} · ${esc(String(z.fee))}</option>`).join('')}</select></label>
    <label>${esc(t('xb_rd_map'))} <input id="rd_map" maxlength="300" autocomplete="off" inputmode="url" placeholder="https://"></label>
    <button type="button" class="primary full" data-act="rd_assign">${esc(t('xb_rd_assign_btn'))}</button></div>`;
}
function codHTML() {
  const c = U.check;
  const rows = c ? (c.rows || []) : [];
  const table = c ? `<div class="stack">${rows.length ? rows.map((r) => `<div class="card row between wrap"><span>${esc(r.rider || '')}</span>
      <span class="muted">${esc(t('xb_rd_collected'))} ${esc(String(r.collected))} · ${esc(t('xb_rd_deposited'))} ${esc(String(r.deposited))} · ${esc(t('xb_rd_diff'))} ${esc(String(r.difference))}</span>
      ${chip(t('xb_rd_st_' + r.status) || r.status, r.status === 'matched' ? 'ok' : 'warn')}</div>`).join('') : `<p class="muted">${esc(t('xb_rd_none_rows'))}</p>`}</div>` : '';
  const cases = U.cases.length ? U.cases.map((k) => `<div class="card stack">
      <div class="row between wrap"><b>${esc(String(k.case_day))} · ${esc(riderName(U.riders.find((r) => String(r.id) === String(k.rider_id))))}</b>${chip(esc(String(k.difference)), 'warn')}</div>
      <div class="muted">${esc(t('xb_rd_collected'))} ${esc(String(k.collected))} · ${esc(t('xb_rd_deposited'))} ${esc(String(k.deposited))}</div>
      <label>${esc(t('xb_rd_explain'))} <input id="rd_ex${esc(String(k.id))}" maxlength="300" autocomplete="off"></label>
      <button type="button" class="primary" data-act="rd_explain" data-id="${esc(String(k.id))}">${esc(t('xb_rd_explain_btn'))}</button></div>`).join('') : `<p class="muted">${esc(t('xb_rd_none_cases'))}</p>`;
  return `<div class="card stack"><b>${esc(t('xb_rd_cod'))}</b>
      <label>${esc(t('xc_day'))} <input type="date" id="rd_day" value="${esc(U.day)}"></label>
      <div class="notice">${esc(t('xb_rd_check_note'))}</div>
      <button type="button" class="btn full" data-act="rd_check">${esc(t('xb_rd_check_btn'))}</button>${table}</div>
    <div class="card stack"><b>${esc(t('xb_rd_deposit'))}</b>
      <label>${esc(t('xb_rd_rider'))} ${riderSel('rd_drid', '')}</label>
      <label>${esc(t('xb_rd_amount'))} <input id="rd_damt" inputmode="decimal"></label>
      <label>${esc(t('xb_pay_note'))} <input id="rd_dnote" maxlength="300" autocomplete="off"></label>
      <button type="button" class="primary full" data-act="rd_deposit">${esc(t('xb_rd_deposit_btn'))}</button></div>
    <h3>${esc(t('xb_rd_cases'))}</h3><div class="stack">${cases}</div>`;
}
function draw() {
  const el = $('#rd_body'); if (!el) return;
  const tabs = [['jobs', 'xb_rd_jobs'], ['assign', 'xb_rd_assign'], ['cod', 'xb_rd_cod']];
  el.innerHTML = `<div class="card stack"><div class="row wrap"><label>${esc(t('xc_place'))} <select id="rd_loc"><option value="">${esc(t('xc_pick_place'))}</option>${places().map((l) => `<option value="${l.id}" ${String(U.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label></div>
      <button type="button" class="full" data-act="rd_show">${esc(t('xc_show'))}</button></div>
    <div class="row wrap" id="rd_tabs">${tabs.map(([k, l]) => `<button type="button" class="tog ${U.tab === k ? 'on' : ''}" data-act="rd_tab" data-v="${k}">${esc(t(l))}</button>`).join('')}</div>
    <div class="stack" id="rd_part">${U.tab === 'jobs' ? jobsHTML() : U.tab === 'assign' ? (U.loc ? assignHTML() : `<div class="notice">${esc(t('xc_pick_place'))}</div>`) : codHTML()}</div>`;
}

// ---------- reads ----------
async function load() {
  U.loc = val('rd_loc') || U.loc;
  const rr = await sb.from('riders').select('id,name_en,name_bn,kind,location_id,active').eq('active', true).order('id');
  U.riders = (rr.data || []).filter((r) => !U.loc || !r.location_id || String(r.location_id) === String(U.loc));
  const zz = await sb.from('delivery_zones').select('code,name_en,name_bn,fee,active').eq('active', true).order('code');
  U.zones = zz.data || [];
  if (!U.loc) { U.jobs = []; U.orders = []; U.cases = []; return draw(); }
  const loc = Number(U.loc);
  const jj = await sb.from('delivery_jobs').select('id,order_id,location_id,rider_id,zone_code,fee,state,attempts,cod_amount,cod_collected,failed_reason,online_orders(order_no,customer_name)')
    .eq('location_id', loc).order('state_at', { ascending: false }).limit(150);
  if (jj.error) throw new Error(jj.error.message || 'error');
  U.jobs = jj.data || [];
  const oo = await sb.from('online_orders').select('id,order_no,customer_name,status,delivery_mode,location_id').eq('location_id', loc)
    .in('status', ['new', 'confirmed', 'packed']).in('delivery_mode', ['home', 'courier']).order('order_no', { ascending: false }).limit(100);
  U.orders = oo.data || [];
  const cc = await sb.from('cod_cases').select('id,rider_id,case_day,collected,deposited,difference,state').eq('location_id', loc).eq('state', 'open').order('case_day', { ascending: false }).limit(50);
  U.cases = cc.data || [];
  draw();
}

// ---------- writes ----------
async function run(fn, args, msg) {
  if (U.busy) return;
  U.busy = true;
  try { const res = await call(fn, args); toast(msg); await load(); return res; }
  catch (e) { toast(eText(e)); } finally { U.busy = false; }
}
function move(a) {
  const id = a.dataset.id, to = a.dataset.v;
  if (to === 'delivered') { const c = val('rd_cod' + id); const cod = c === '' ? null : Number(c); if (cod !== null && !Number.isFinite(cod)) return toast(t('xb_err_amount')); return run('xb_delivery_move', { p_job: id, p_to: to, p_cod: cod, p_reason: null }, t('xb_rd_saved')); }
  if (to === 'failed') { const r = val('rd_rs' + id); if (!r) return toast(t('xb_err_note')); return run('xb_delivery_move', { p_job: id, p_to: to, p_cod: null, p_reason: r }, t('xb_rd_saved')); }
  return run('xb_delivery_move', { p_job: id, p_to: to, p_cod: null, p_reason: null }, t('xb_rd_saved'));
}
function assign() {
  const order = val('rd_ord'), rider = val('rd_rid'), zone = val('rd_zone'), map = val('rd_map');
  if (!order) return toast(t('xb_rd_pick_order'));
  if (!rider) return toast(t('xb_rd_pick_rider'));
  if (!zone) return toast(t('xb_rd_pick_zone'));
  if (map && !/^https:\/\//.test(map)) return toast(t('xb_rd_err_map'));
  return run('xb_delivery_assign', { p_order: order, p_rider: Number(rider), p_zone: zone, p_map_link: map || null }, t('xb_rd_assigned'));
}
async function check() {
  U.day = val('rd_day') || U.day;
  try { U.check = await call('xb_cod_reconcile', { p_day: U.day, p_loc: Number(U.loc) }); toast(t('xb_rd_checked')); await load(); }
  catch (e) { toast(eText(e)); }
}
function deposit() {
  const rider = val('rd_drid'), amt = Number(val('rd_damt')), note = val('rd_dnote');
  if (!rider) return toast(t('xb_rd_pick_rider'));
  if (!Number.isFinite(amt) || amt <= 0) return toast(t('xb_err_amount'));
  U.depClient = U.depClient || rid();
  return run('xb_cod_deposit', { p_client: U.depClient, p_rider: Number(rider), p_loc: Number(U.loc), p_day: U.day, p_amount: amt, p_note: note || null }, t('xb_rd_deposited_ok'))
    .then(() => { U.depClient = null; });
}
function explain(a) {
  const id = a.dataset.id, note = val('rd_ex' + id);
  if (!note) return toast(t('xb_err_note'));
  return run('xb_cod_case_explain', { p_id: Number(id), p_note: note }, t('xb_rd_explained'));
}

Object.assign(H, {
  rd_show: () => load().catch((e) => fail(e)),
  rd_tab: (a) => { U.tab = a.dataset.v; draw(); },
  rd_move: (a) => move(a),
  rd_assign: () => assign(),
  rd_check: () => check(),
  rd_deposit: () => deposit(),
  rd_explain: (a) => explain(a),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(t('xb_rd_title'), `<p class="muted">${esc(t('xb_rd_intro'))}</p><div id="rd_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const mine = places();
  if (mine.length === 1) U.loc = String(mine[0].id);
  try { await load(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { riders: view });
})();
