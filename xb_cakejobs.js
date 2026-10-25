/* Islamia BOS · XB custom cake jobs: list, status chain and the "due tomorrow" sheet (#/cakejobs).
   Each cake moves one step at a time: quoted -> confirmed (advance in the order) -> slip -> baked -> decorated -> ready -> delivered.
   The server refuses a skipped or backwards step, and refuses "delivered" until the app order is delivered (and the photo, when that switch is on).
   Writes: xb_cake_confirm and xb_cake_move only. Reads: cake_jobs (own RLS), online_orders (order number), xb_cake_due for the sheet.
   Nothing is sent to the customer from this screen. Server: supabase/phase492.sql. Price and capacity rules are set elsewhere (the server reads them).
   UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, H, nm } = A;
const t = (k) => A.t(k);
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const CHAIN = ['quoted', 'confirmed', 'slip', 'baked', 'decorated', 'ready', 'delivered'];
const NEXT = { quoted: 'confirmed', confirmed: 'slip', slip: 'baked', baked: 'decorated', decorated: 'ready', ready: 'delivered' };
const ERR = [
  ['not allowed', 'xc_err_not_allowed'], ['module_off', 'xc_err_off'], ['bad_status', 'xb_err_status'], ['not_found', 'xb_err_not_found'],
  ['order_not_delivered', 'xb_err_order_open'], ['photo_required', 'xb_err_photo'], ['order_total_below_quote', 'xb_err_total'],
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

const U = { loc: '', from: today(), to: addDays(today(), 14), rows: [], busy: false };

// ---------- drawing ----------
function chainHTML(state) {
  return `<div class="row wrap xb-chain" aria-label="${esc(t('xb_cake_chain'))}">${CHAIN.map((s) => chip(t('xb_state_' + s), s === state ? 'ok' : '')).join('')}${state === 'cancelled' ? chip(t('xb_state_cancelled'), 'bad') : ''}</div>`;
}
function rowHTML(j) {
  const to = NEXT[j.state];
  const btn = to ? `<button type="button" class="primary" data-act="cj_move" data-id="${esc(j.id)}" data-v="${to}">${esc(t('xb_act_' + to))}</button>` : '';
  return `<div class="card stack cj-row">
    <div class="row between wrap"><b>#${esc(String((j.online_orders || {}).order_no || ''))}</b><span class="muted">${esc(String(j.due_date))}${j.due_slot_from ? ' · ' + esc(String(j.due_slot_from).slice(0, 5)) : ''}</span></div>
    ${chainHTML(j.state)}
    <div class="muted">${esc(String(j.weight_kg))} kg${j.layers ? ' · ' + esc(String(j.layers)) + ' ' + esc(t('xb_cake_layers')) : ''}${j.flavour_code ? ' · ' + esc(String(j.flavour_code)) : ''}</div>
    ${j.message ? `<div class="muted">${esc(t('xb_cake_message'))}: ${esc(j.message)}</div>` : ''}
    <div class="muted">${esc(t('xb_cake_balance'))}: ${esc(String(j.balance))}</div>
    <div class="row wrap">${btn}</div></div>`;
}
function listHTML() {
  if (!U.loc) return `<div class="notice">${esc(t('xc_pick_place'))}</div>`;
  if (!U.rows.length) return `<p class="muted">${esc(t('xb_cake_empty'))}</p>`;
  return U.rows.map(rowHTML).join('');
}
function draw() {
  const el = $('#cj_body'); if (!el) return;
  el.innerHTML = `<div class="card stack"><div class="row wrap">
      <label>${esc(t('xc_place'))} <select id="cj_loc"><option value="">${esc(t('xc_pick_place'))}</option>${places().map((l) => `<option value="${l.id}" ${String(U.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>
      <label>${esc(t('xb_cake_from'))} <input type="date" id="cj_from" value="${esc(U.from)}"></label>
      <label>${esc(t('xb_cake_to'))} <input type="date" id="cj_to" value="${esc(U.to)}"></label></div>
      <div class="row wrap"><button type="button" class="primary" data-act="cj_show">${esc(t('xc_show'))}</button>
      <button type="button" class="btn" data-act="cj_due">${esc(t('xb_cake_due_btn'))}</button></div></div>
    <div class="stack" id="cj_list">${listHTML()}</div>`;
}

// ---------- reads ----------
async function load() {
  U.loc = val('cj_loc') || U.loc; U.from = val('cj_from') || U.from; U.to = val('cj_to') || U.to;
  if (!U.loc) { U.rows = []; return draw(); }
  if (U.to < U.from || (new Date(U.to) - new Date(U.from)) > 62 * 86400000) return toast(t('xb_cake_range'));
  const r = await sb.from('cake_jobs')
    .select('id,order_id,location_id,due_date,due_slot_from,weight_kg,flavour_code,layers,message,state,balance,online_orders(order_no)')
    .eq('location_id', Number(U.loc)).gte('due_date', U.from).lte('due_date', U.to)
    .order('due_date', { ascending: true }).order('due_slot_from', { ascending: true, nullsFirst: false }).limit(300);
  if (r.error) throw new Error(r.error.message || 'error');
  U.rows = r.data || [];
  draw();
}

// ---------- one step forward (the server checks the order of the chain) ----------
async function move(a) {
  if (U.busy) return;
  const id = a.dataset.id, to = a.dataset.v;
  U.busy = true;
  try {
    if (to === 'confirmed') await call('xb_cake_confirm', { p_job: id });
    else await call('xb_cake_move', { p_job: id, p_to: to, p_note: null });
    toast(t('xb_cake_moved'));
    await load();
  } catch (e) { toast(eText(e)); } finally { U.busy = false; }
}

// ---------- the due-tomorrow sheet (read only) ----------
async function dueSheet() {
  if (!U.loc) return toast(t('xc_pick_place'));
  const d = addDays(today(), 1);
  try {
    const r = await call('xb_cake_due', { p_date: d, p_loc: Number(U.loc) });
    const rows = (r && r.rows) || [];
    const line = (x) => `<div class="card stack"><div class="row between wrap"><b>#${esc(String(x.order_no || ''))}</b><span class="muted">${esc(String(x.slot || '').slice(0, 5))}</span></div>
      <div class="muted">${esc(String(x.weight_kg))} kg${x.layers ? ' · ' + esc(String(x.layers)) : ''}${x.flavour ? ' · ' + esc(String(x.flavour)) : ''}${x.eggless ? ' · ' + esc(t('xb_cake_eggless')) : ''}${x.halal ? ' · ' + esc(t('xb_cake_halal')) : ''}</div>
      ${x.message ? `<div>${esc(t('xb_cake_message'))}: ${esc(x.message)}</div>` : ''}
      ${x.design ? `<div>${esc(t('xb_cake_design'))}: ${esc(x.design)}</div>` : ''}
      ${x.allergen ? `<div class="notice warn">${esc(t('xb_cake_allergen'))}: ${esc(x.allergen)}</div>` : ''}
      <div class="muted">${esc(t('xb_state_' + x.state) || x.state)} · ${esc(t('xb_cake_balance'))}: ${esc(String(x.balance))}</div></div>`;
    openSheet(`<h3>${esc(t('xb_cake_due_title'))}: ${esc(d)}</h3>
      <p class="muted">${esc(t('xb_cake_count'))}: ${esc(String(r.count || 0))} · ${esc(t('xb_cake_kg'))}: ${esc(String(r.total_kg || 0))}</p>
      <div class="stack">${rows.length ? rows.map(line).join('') : `<p class="muted">${esc(t('xb_cake_none_due'))}</p>`}</div>`);
  } catch (e) { toast(eText(e)); }
}

Object.assign(H, {
  cj_show: () => load().catch((e) => fail(e)),
  cj_move: (a) => move(a),
  cj_due: () => dueSheet(),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(t('xb_cake_title'), `<p class="muted">${esc(t('xb_cake_intro'))}</p><div id="cj_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const mine = places();
  if (mine.length === 1) U.loc = String(mine[0].id);
  draw();
  if (U.loc) { try { await load(); } catch (e) { fail(e); } }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { cakejobs: view });
})();
