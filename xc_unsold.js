/* Islamia BOS · XC unsold stock and markdown, end of day (#/xcunsold).
   Lists the units whose expiry falls before the end of tomorrow (Dhaka), with the markdown price suggested by the server, and lets the person
   record ONE decision per line: sold at a markdown, staff meal, donation or waste. The only write is the existing decision RPC xc_unsold_record.
   Nothing here moves stock or money; waste is still booked on the stock screen. No void, no edit: those are not in this screen.
   Server: supabase/phase497.sql (xc_unsold_candidates, xc_unsold_record, table xc_unsold_outcomes read for today's lines).
   Hidden unless the owner switch xc_unsold_on is ON (see web/ia.js). The server decides every right. UNVERIFIED on a real phone and on a real Supabase project. */
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
const addDays = (d, n) => { const x = new Date(d + 'T00:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };
const OUT = ['sold_discount', 'staff_meal', 'donation', 'waste'];
const ERR = {
  not_allowed: 'xc_err_not_allowed', switch_off: 'xc_err_off', bad_location: 'xc_err_place', bad_date: 'xc_err_date', bad_outcome: 'xc_err_outcome',
  bad_value: 'xc_err_qty', bad_discount: 'xc_err_pct', markdown_pct_not_set: 'xc_err_pct_missing', item_not_found: 'xc_err_item',
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? t(ERR[k]) : t('err_generic'); };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) throw new Error(r.error.message || 'error');
  return r.data;
}

// places this person may use (same rule as the other reports: owner and management see all live places)
function places() {
  const all = (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : (B.ENV && B.ENV.locs) || []);
  const mine = S.ctx && (S.ctx.is_owner || (S.ctx.roles || []).includes('management')) ? all : all.filter((l) => S.ctx && (S.ctx.locations || []).includes(l.id));
  return mine;
}
const placeSel = () => `<select id="xu_loc"><option value="">${esc(t('xc_pick_place'))}</option>${places().map((l) => `<option value="${l.id}" ${String(U.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;

const U = { day: today(), loc: '', cand: null, recorded: [], client: {}, busy: false };

// ---------- the screen ----------
function filtersHTML() {
  return `<div class="card stack"><div class="row wrap">
    <label>${esc(t('xc_day'))} <input type="date" id="xu_day" value="${esc(U.day)}" min="${esc(addDays(today(), -7))}" max="${esc(addDays(today(), 1))}"></label>
    <label>${esc(t('xc_place'))} ${placeSel()}</label></div>
    <button type="button" class="primary full" data-act="xu_show">${esc(t('xc_show'))}</button></div>`;
}
function rowHTML(r, i) {
  const c = U.client[i] || (U.client[i] = rid());
  const pct = r.markdown_pct;
  const showPrice = r.markdown_price !== null && r.markdown_price !== undefined;
  return `<div class="card stack xu-row" data-i="${i}">
    <div class="row between wrap"><b>${esc(r.name_en || r.code || '')}</b>${chip(String(r.qty_at_risk) + ' ' + t('xc_units'))}</div>
    <div class="muted">${esc(t('xc_expiry'))}: ${esc(String(r.earliest_expiry || '').slice(0, 10))} · ${esc(t('xc_batches'))}: ${esc(String(r.batches))}</div>
    <div class="muted">${esc(t('xc_sell_price'))}: ${esc(String(r.sell_price))}${showPrice ? ' · ' + esc(t('xc_markdown_price')) + ': ' + esc(String(r.markdown_price)) : ''}</div>
    <div class="row wrap">
      <label>${esc(t('xc_outcome'))} <select id="xu_o${i}">${OUT.map((o) => `<option value="${o}">${esc(t('xc_out_' + o))}</option>`).join('')}</select></label>
      <label>${esc(t('xc_qty'))} <input id="xu_q${i}" inputmode="decimal" value="${esc(String(r.qty_at_risk))}"></label>
      <label>${esc(t('xc_pct'))} <input id="xu_p${i}" inputmode="decimal" value="${esc(pct === null || pct === undefined ? '' : String(pct))}"></label>
    </div>
    <label>${esc(t('xc_note'))} <input id="xu_n${i}" maxlength="300" autocomplete="off"></label>
    <input type="hidden" id="xu_c${i}" value="${esc(c)}">
    <button type="button" class="btn" data-act="xu_rec" data-i="${i}">${esc(t('xc_record'))}</button></div>`;
}
function recordedHTML() {
  if (!U.recorded.length) return '';
  return `<div class="stack"><b>${esc(t('xc_recorded_today'))}</b>${U.recorded.map((o) => `<div class="card row between wrap"><span>${esc((o.items && (o.items.name_en || o.items.name_bn)) || '')} · ${esc(String(o.qty))}</span>${chip(t('xc_out_' + o.outcome) + (o.state === 'void' ? ' (void)' : ''), o.state === 'void' ? 'bad' : '')}</div>`).join('')}</div>`;
}
function resultHTML() {
  if (!U.loc) return `<div class="notice">${esc(t('xc_pick_place'))}</div>`;
  const c = U.cand;
  if (!c) return `<p class="muted">${esc(t('xc_press_show'))}</p>`;
  if (c.skipped === 'switch_off') return `<div class="notice warn">${esc(t('xc_err_off'))}</div>`;
  const notes = [];
  if (Array.isArray(c.data_needed) && c.data_needed.length) notes.push(`<div class="notice warn">${esc(t('xc_need_markdown'))}</div>`);
  if (c.no_expiry_captured && Number(c.no_expiry_captured.batches) > 0) {
    notes.push(`<div class="notice">${esc(t('xc_no_expiry').replace('{n}', c.no_expiry_captured.batches).replace('{u}', c.no_expiry_captured.units))}</div>`);
  }
  const rows = (c.rows || []).map((r, i) => rowHTML(r, i)).join('');
  return notes.join('') + (rows || `<p class="muted">${esc(t('xc_nothing'))}</p>`) + recordedHTML();
}
function draw() {
  const el = $('#xu_body'); if (!el) return;
  el.innerHTML = filtersHTML() + `<div id="xu_out">${resultHTML()}</div>`;
}

// ---------- reads ----------
async function show() {
  U.day = val('xu_day') || today(); U.loc = val('xu_loc');
  if (!U.loc) { U.cand = null; U.recorded = []; return draw(); }
  const loc = Number(U.loc);
  U.cand = await call('xc_unsold_candidates', { p_date: U.day, p_loc: loc });
  U.client = {};
  const r = await sb.from('xc_unsold_outcomes').select('id,qty,outcome,state,items(name_en,name_bn)').eq('location_id', loc).eq('day', U.day).order('id');
  U.recorded = r.error ? [] : (r.data || []);
  draw();
}

// ---------- the one write: the existing decision RPC ----------
async function record(a) {
  if (U.busy) return;
  const i = Number(a.dataset.i), row = (U.cand && U.cand.rows || [])[i]; if (!row) return;
  const outcome = val('xu_o' + i), qty = Number(val('xu_q' + i)), pctT = val('xu_p' + i), note = val('xu_n' + i);
  if (!OUT.includes(outcome)) return toast(eText({ message: 'bad_outcome' }));
  if (!Number.isFinite(qty) || qty <= 0) return toast(eText({ message: 'bad_value' }));
  let pct = null;
  if (outcome === 'sold_discount') {
    if (pctT === '') pct = null; else { pct = Number(pctT); if (!Number.isFinite(pct) || pct <= 0 || pct > 90) return toast(eText({ message: 'bad_discount' })); }
  }
  U.busy = true;
  try {
    const client = val('xu_c' + i) || (U.client[i] = rid());
    const res = await call('xc_unsold_record', { p_client: client, p_loc: Number(U.loc), p_item: row.item_id, p_day: U.day, p_qty: qty, p_outcome: outcome,
      p_discount_pct: pct, p_note: note || null });
    U.client[i] = null;
    toast(t('xc_recorded_ok') + (res && res.value !== undefined && res.value !== null ? ' · ' + res.value : ''));
    await show();
  } catch (e) { toast(eText(e)); } finally { U.busy = false; }
}

Object.assign(H, {
  xu_show: async () => { try { await show(); } catch (e) { fail(e); } },
  xu_rec: (a) => record(a),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(t('xc_unsold_title'), `<p class="muted">${esc(t('xc_unsold_intro'))}</p><div id="xu_body"><p class="muted">…</p></div>`, true);
  const mine = places();
  if (mine.length === 1) U.loc = String(mine[0].id);
  draw();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { xcunsold: view });
})();
