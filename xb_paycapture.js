/* Islamia BOS · XB mobile payment capture and verify (#/paycapture).
   The counter writes a bKash / Nagad / Rocket payment (Trx-ID, sender, amount, time, and what it is for). A Trx-ID is written once: a second try is refused by the server.
   The server answers with a flag (ok, overpay, underpay, no_target) and the difference; the screen shows it. A second person verifies the capture; nobody verifies their own.
   A paste box reads a pasted SMS with BOS.xbPaySms (web/xb_paysms.js). The reader saves nothing; the person checks every field before Save.
   Writes: xb_pay_capture and xb_pay_capture_decide only. Reads: xb_pay_captures_list, d_wallet_balances, online_orders (open orders of the place).
   Nothing is posted to the books by this screen: a capture is a record that is tied out later. Server: supabase/phase491.sql. Hidden only by permission, not by a switch;
   the module switch pay_capture_on defaults OFF and the server refuses every write until the owner turns it on. UNVERIFIED on a real phone and on a real Supabase project. */
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
const nowLocal = () => new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Dhaka' }).replace(' ', 'T').slice(0, 16);
const PROV = ['bkash', 'nagad', 'rocket', 'other'];
const TARGET = ['none', 'order', 'advance'];
const ERR = [
  ['duplicate_trx', 'xb_err_dup'], ['module_off', 'xc_err_off'], ['not allowed', 'xc_err_not_allowed'], ['bad_trx_id', 'xb_err_trx'], ['bad_amount', 'xb_err_amount'],
  ['bad_time', 'xb_err_time'], ['bad_sender', 'xb_err_sender'], ['bad_wallet', 'xb_err_wallet'], ['bad_target', 'xb_err_target'], ['bad_provider', 'xb_err_provider'],
  ['other_location', 'xb_err_other_place'], ['order_closed', 'xb_err_order_closed'], ['not_found', 'xb_err_not_found'], ['reason_required', 'xb_err_note'],
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

const U = { loc: '', wallets: [], orders: [], pending: [], last: null, sms: null, fromSms: false, busy: false, client: rid(), smsText: '' };

// ---------- drawing ----------
function placeSel() {
  return `<select id="xp_loc"><option value="">${esc(t('xc_pick_place'))}</option>${places().map((l) => `<option value="${l.id}" ${String(U.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;
}
function smsHTML() {
  const s = U.sms;
  return `<div class="card stack"><b>${esc(t('xb_pay_paste'))}</b>
    <textarea id="xp_sms" rows="3" spellcheck="false" autocomplete="off" placeholder="${esc(t('xb_pay_paste_hint'))}">${esc(U.smsText)}</textarea>
    <button type="button" class="btn" data-act="xp_read">${esc(t('xb_pay_read'))}</button>
    ${s ? (s.ok ? `<div class="notice">${esc(t('xb_pay_sms_check'))}</div>` : `<div class="notice warn">${esc(t('xb_pay_sms_unclear'))}</div>`) : ''}</div>`;
}
function formHTML() {
  const f = U.form || {};
  const wallets = U.wallets.map((w) => `<option value="${esc(w.code)}" ${f.wallet === w.code ? 'selected' : ''}>${esc(nm(w) || w.code)}</option>`).join('');
  const orders = U.orders.map((o) => `<option value="${esc(o.id)}" ${f.order === o.id ? 'selected' : ''}>#${esc(String(o.order_no))} · ${esc(o.customer_name || '')}</option>`).join('');
  return `<div class="card stack"><b>${esc(t('xb_pay_new'))}</b>
    <div class="row wrap">
      <label>${esc(t('xb_pay_provider'))} <select id="xp_prov">${PROV.map((p) => `<option value="${p}" ${f.provider === p ? 'selected' : ''}>${esc(t('xb_prov_' + p))}</option>`).join('')}</select></label>
      <label>${esc(t('xb_pay_wallet'))} <select id="xp_wal">${wallets || `<option value="">${esc(t('xb_pay_no_wallet'))}</option>`}</select></label></div>
    <div class="row wrap">
      <label>${esc(t('xb_pay_trx'))} <input id="xp_trx" maxlength="20" autocapitalize="characters" autocomplete="off" value="${esc(f.trx || '')}"></label>
      <label>${esc(t('xb_pay_amount'))} <input id="xp_amt" inputmode="decimal" value="${esc(f.amount || '')}"></label></div>
    <div class="row wrap">
      <label>${esc(t('xb_pay_sender'))} <input id="xp_sen" inputmode="tel" maxlength="20" autocomplete="off" value="${esc(f.sender || '')}"></label>
      <label>${esc(t('xb_pay_paid_at'))} <input id="xp_at" type="datetime-local" value="${esc(f.paid_at || nowLocal())}"></label></div>
    <div class="row wrap">
      <label>${esc(t('xb_pay_target'))} <select id="xp_tgt">${TARGET.map((x) => `<option value="${x}" ${f.target === x ? 'selected' : ''}>${esc(t('xb_tgt_' + x))}</option>`).join('')}</select></label>
      <label>${esc(t('xb_pay_order'))} <select id="xp_ord"><option value="">—</option>${orders}</select></label></div>
    <label>${esc(t('xb_pay_note'))} <input id="xp_note" maxlength="300" autocomplete="off"></label>
    <button type="button" class="primary full" data-act="xp_save">${esc(t('xb_pay_save'))}</button></div>`;
}
function resultHTML() {
  const r = U.last; if (!r) return '';
  const flag = r.flag;
  const cls = flag === 'ok' ? 'ok' : (flag === 'overpay' || flag === 'underpay') ? 'bad' : 'warn';
  const msg = flag === 'ok' ? t('xb_pay_res_ok') : flag === 'overpay' ? t('xb_pay_res_over') : flag === 'underpay' ? t('xb_pay_res_under') : t('xb_pay_res_none');
  return `<div class="card stack"><div class="row wrap">${chip(msg, cls)}</div>
    ${r.expected !== null && r.expected !== undefined ? `<div class="muted">${esc(t('xb_pay_expected'))}: ${esc(String(r.expected))} · ${esc(t('xb_pay_diff'))}: ${esc(String(r.diff))}</div>` : ''}
    ${r.note_needed_to_verify ? `<div class="notice warn">${esc(t('xb_pay_note_needed'))}</div>` : ''}</div>`;
}
function pendingHTML() {
  if (!U.pending.length) return `<p class="muted">${esc(t('xb_pay_none_pending'))}</p>`;
  return U.pending.map((c) => `<div class="card stack xp-row">
    <div class="row between wrap"><b>${esc(t('xb_prov_' + c.provider) || c.provider)} · ${esc(c.trx_id)}</b>${chip(esc(String(c.amount)), c.flag === 'ok' ? 'ok' : 'warn')}</div>
    <div class="muted">${esc(t('xb_pay_flag_' + c.flag) || c.flag)}${c.diff !== null && c.diff !== undefined ? ' · ' + esc(t('xb_pay_diff')) + ': ' + esc(String(c.diff)) : ''} · ${esc(String(c.paid_at || '').slice(0, 16).replace('T', ' '))}</div>
    <label>${esc(t('xb_pay_note'))} <input id="xp_dn${esc(String(c.id))}" maxlength="300" autocomplete="off"></label>
    <div class="row wrap"><button type="button" class="primary" data-act="xp_decide" data-id="${esc(String(c.id))}" data-v="1">${esc(t('xb_pay_verify'))}</button>
      <button type="button" class="btn" data-act="xp_decide" data-id="${esc(String(c.id))}" data-v="0">${esc(t('xb_pay_reject'))}</button></div></div>`).join('');
}
function draw() {
  const el = $('#xp_body'); if (!el) return;
  if ($('#xp_trx') && !U.skipSnap) U.form = { provider: val('xp_prov'), trx: val('xp_trx'), amount: val('xp_amt'), sender: val('xp_sen'), paid_at: val('xp_at'), target: val('xp_tgt'), order: val('xp_ord'), wallet: val('xp_wal'), note: val('xp_note') };
  U.skipSnap = false;
  el.innerHTML = `<div class="card stack"><div class="row wrap"><label>${esc(t('xc_place'))} ${placeSel()}</label></div>
      <button type="button" class="full" data-act="xp_show">${esc(t('xc_show'))}</button></div>
    ${U.loc ? smsHTML() + formHTML() + resultHTML() : `<div class="notice">${esc(t('xc_pick_place'))}</div>`}
    ${U.loc ? `<h3>${esc(t('xb_pay_pending_title'))}</h3><div class="stack" id="xp_pending">${pendingHTML()}</div>` : ''}`;
}

// ---------- reads ----------
async function load() {
  U.loc = val('xp_loc') || U.loc;
  if (!U.loc) return draw();
  const loc = Number(U.loc);
  const w = await call('d_wallet_balances', { p_asof: today() }).catch(() => []);
  U.wallets = (w || []).filter((x) => x.active !== false);
  const o = await sb.from('online_orders').select('id,order_no,customer_name,status,location_id').eq('location_id', loc).in('status', ['new', 'confirmed', 'packed']).order('order_no', { ascending: false }).limit(200);
  U.orders = o.error ? [] : (o.data || []);
  U.pending = await call('xb_pay_captures_list', { p_loc: loc, p_status: 'pending', p_day: null, p_limit: 100 }).catch(() => []);
  draw();
}

// ---------- SMS paste: read, then the person checks and saves ----------
function readSms() {
  const text = val('xp_sms'); U.smsText = text;
  const P = B.xbPaySms;
  if (!P || typeof P.parseMobilePaySms !== 'function') { U.sms = { ok: false }; return draw(); }
  const r = P.parseMobilePaySms(text);
  U.sms = r;
  U.form = U.form || {};
  if (r && r.ok) {
    U.form = Object.assign({}, U.form, { provider: r.provider, trx: r.trx, amount: r.amount !== null && r.amount !== undefined ? String(r.amount) : '', sender: r.sender || '', target: 'none' });
    U.fromSms = true;
  } else { U.fromSms = false; }
  draw();
}

// ---------- the one write: capture (the server checks the Trx-ID, the amount and the target) ----------
async function save() {
  if (U.busy) return;
  const loc = Number(U.loc);
  const provider = val('xp_prov'), trx = val('xp_trx').toUpperCase(), sender = val('xp_sen'), amtT = val('xp_amt'), at = val('xp_at'), wallet = val('xp_wal');
  const target = val('xp_tgt') || 'none', order = val('xp_ord') || null, note = val('xp_note');
  if (!/^[A-Z0-9]{6,20}$/.test(trx)) return toast(t('xb_err_trx'));
  const amount = Number(amtT);
  if (!Number.isFinite(amount) || amount <= 0) return toast(t('xb_err_amount'));
  if (!wallet) return toast(t('xb_pay_no_wallet'));
  if ((target === 'order' || target === 'advance') && !order) return toast(t('xb_pay_pick_order'));
  const paidAt = at ? new Date(at + ':00+06:00') : new Date();
  U.form = { provider, trx, amount: amtT, sender, paid_at: at, target, order, wallet, note };
  U.busy = true;
  try {
    const res = await call('xb_pay_capture', {
      p_client: U.client, p_provider: provider, p_trx: trx, p_sender: sender || null, p_amount: amount, p_paid_at: paidAt.toISOString(),
      p_wallet: wallet, p_loc: loc, p_target: target, p_order: target === 'none' ? null : order, p_sale: null,
      p_source: U.fromSms ? 'sms_paste' : 'manual', p_note: note || null,
    });
    U.last = res; U.client = rid(); U.fromSms = false; U.sms = null; U.smsText = '';
    U.form = { provider, wallet, target: 'none' }; U.skipSnap = true;
    toast(t('xb_pay_saved'));
    await load();
  } catch (e) { toast(eText(e)); } finally { U.busy = false; }
}

// ---------- verify or reject a pending capture (the server refuses your own) ----------
async function decide(a) {
  if (U.busy) return;
  const id = Number(a.dataset.id), approve = a.dataset.v === '1', note = val('xp_dn' + id);
  const row = U.pending.find((x) => Number(x.id) === id);
  if ((!approve || (row && row.flag !== 'ok')) && !note) return toast(t('xb_err_note'));
  U.busy = true;
  try { await call('xb_pay_capture_decide', { p_id: id, p_approve: approve, p_note: note || null }); toast(t('xb_pay_decided')); await load(); }
  catch (e) { toast(eText(e)); } finally { U.busy = false; }
}

Object.assign(H, {
  xp_show: () => load().catch((e) => fail(e)),
  xp_read: () => readSms(),
  xp_save: () => save(),
  xp_decide: (a) => decide(a),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(t('xb_pay_title'), `<p class="muted">${esc(t('xb_pay_intro'))}</p><div id="xp_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const mine = places();
  if (mine.length === 1) U.loc = String(mine[0].id);
  U.form = U.form || { provider: 'bkash', target: 'none' };
  try { await load(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { paycapture: view });
})();
