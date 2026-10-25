/* Islamia BOS · XC owner summary: recipients and send history (#/xcsummary).
   Owner only. Lists who receives the daily owner summary, lets the owner add a recipient or switch one on or off (never deleted: "off" keeps the row),
   shows the switches and the send history. This screen SENDS NOTHING: the daily summary is sent only by the scheduled script (tools/owner_summary.py).
   Server: supabase/phase494.sql (xc_summary_recipients table read, xc_recipient_save, xc_summary_targets, xc_summary_history).
   Hidden unless the owner switch xc_summary_on is ON (see web/ia.js). Addresses are shown to the owner only (RLS). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const t = (k) => A.t(k);
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const ERR = {
  not_allowed: 'xc_err_not_allowed', name_required: 'xc_err_name', bad_address: 'xc_err_address', location_required: 'xc_err_place_needed',
  bad_location: 'xc_err_place', bad_channel: 'xc_err_channel', bad_scope: 'xc_err_scope', channel_mismatch: 'xc_err_address',
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? t(ERR[k]) : t('err_generic'); };
async function call(fn, args) {
  const r = await sb.rpc(fn, args || {});
  if (r.error) throw new Error(r.error.message || 'error');
  return r.data;
}
const U = { targets: null, rows: [], hist: [], busy: false, channel: 'email', scope: 'owner' };

function places() {
  const all = (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : (B.ENV && B.ENV.locs) || []);
  return all;
}
const placeName = (id) => { const l = places().find((x) => String(x.id) === String(id)); return l ? nm(l) : (id === null || id === undefined ? '' : String(id)); };
const CH = { email: 'xc_chan_email', telegram: 'xc_chan_telegram' };
const STATUS = { sent: 'xc_st_sent', failed: 'xc_st_failed', skipped_empty: 'xc_st_empty' };

// ---------- drawing ----------
function switchesHTML() {
  const g = U.targets;
  if (!g) return '';
  const sw = (k, on) => chip(t(k) + ': ' + (on ? t('on') : t('off')), on ? 'ok' : '');
  return `<div class="card stack"><b>${esc(t('xc_switches'))}</b><div class="row wrap">${sw('xc_sw_summary', g.on)}${sw('xc_sw_email', g.email_on)}${sw('xc_sw_telegram', g.telegram_on)}</div>
    <div class="muted">${esc(t('xc_sw_times'))}: ${esc(String(g.times))}</div></div>`;
}
function recipientsHTML() {
  if (!U.rows.length) return `<p class="muted">${esc(t('xc_none_rec'))}</p>`;
  return U.rows.map((r) => `<div class="card stack xs-row">
    <div class="row between wrap"><b>${esc(r.name)}</b>${chip(t(r.active ? 'active' : 'inactive'), r.active ? 'ok' : '')}</div>
    <div class="muted">${esc(t(CH[r.channel] || r.channel))} · ${esc(r.address)}</div>
    <div class="muted">${esc(r.scope === 'outlet' ? t('xc_scope_outlet') + ': ' + placeName(r.location_id) : t('xc_scope_owner'))}${r.quiet_when_empty ? ' · ' + esc(t('xc_quiet')) : ''}</div>
    <div class="row wrap">${r.active
      ? `<button type="button" class="btn" data-act="xs_active" data-id="${esc(String(r.id))}" data-v="0">${esc(t('xc_switch_off'))}</button>`
      : `<button type="button" class="primary" data-act="xs_active" data-id="${esc(String(r.id))}" data-v="1">${esc(t('xc_switch_on'))}</button>`}</div></div>`).join('');
}
function addHTML() {
  const locs = places();
  return `<div class="card stack"><b>${esc(t('xc_add'))}</b>
    <label>${esc(t('xc_name'))} <input id="xs_name" maxlength="80" autocomplete="off"></label>
    <label>${esc(t('xc_channel'))} <select id="xs_ch"><option value="email" ${U.channel === 'email' ? 'selected' : ''}>${esc(t('xc_chan_email'))}</option><option value="telegram" ${U.channel === 'telegram' ? 'selected' : ''}>${esc(t('xc_chan_telegram'))}</option></select></label>
    <label>${esc(t('xc_address'))} <input id="xs_addr" maxlength="200" autocomplete="off" inputmode="text"></label>
    <label>${esc(t('xc_scope'))} <select id="xs_scope"><option value="owner" ${U.scope === 'owner' ? 'selected' : ''}>${esc(t('xc_scope_owner'))}</option><option value="outlet" ${U.scope === 'outlet' ? 'selected' : ''}>${esc(t('xc_scope_outlet'))}</option></select></label>
    <label>${esc(t('xc_place'))} <select id="xs_loc"><option value="">—</option>${locs.map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select></label>
    <label class="row"><input type="checkbox" id="xs_quiet"> ${esc(t('xc_quiet'))}</label>
    <button type="button" class="primary full" data-act="xs_save">${esc(t('save'))}</button></div>`;
}
function histHTML() {
  if (!U.hist.length) return `<p class="muted">${esc(t('xc_hist_none'))}</p>`;
  return U.hist.map((h) => `<div class="card row between wrap"><span>${esc(String(h.run_date))} · ${esc(h.recipient || '—')} · ${esc(t(CH[h.channel] || h.channel))}</span>${chip(t(STATUS[h.status] || h.status), h.status === 'sent' ? 'ok' : h.status === 'failed' ? 'bad' : '')}${h.error ? `<div class="muted">${esc(h.error)}</div>` : ''}</div>`).join('');
}
function draw() {
  const el = $('#xs_body'); if (!el) return;
  el.innerHTML = `${switchesHTML()}
    <h3>${esc(t('xc_recipients'))}</h3><div class="stack" id="xs_list">${recipientsHTML()}</div>
    ${addHTML()}
    <h3>${esc(t('xc_hist'))}</h3><div class="stack" id="xs_hist">${histHTML()}</div>`;
}

// ---------- reads ----------
async function load() {
  U.targets = await call('xc_summary_targets');
  const r = await sb.from('xc_summary_recipients').select('id,name,channel,address,scope,location_id,quiet_when_empty,active').order('id');
  if (r.error) throw new Error(r.error.message || 'error');
  U.rows = r.data || [];
  const h = await call('xc_summary_history', { p_limit: 30 });
  U.hist = (h && h.denied) ? [] : ((h && h.rows) || []);
  draw();
}

// ---------- writes: recipients only (no send) ----------
async function save() {
  if (U.busy) return;
  const name = val('xs_name'), ch = val('xs_ch') || 'email', addr = val('xs_addr'), scope = val('xs_scope') || 'owner', loc = val('xs_loc');
  U.channel = ch; U.scope = scope;
  if (!name) return toast(eText({ message: 'name_required' }));
  if (!addr) return toast(eText({ message: 'bad_address' }));
  if (scope === 'outlet' && !loc) return toast(eText({ message: 'location_required' }));
  const p = { name, channel: ch, address: addr, scope, quiet_when_empty: !!$('#xs_quiet') && $('#xs_quiet').checked };
  if (scope === 'outlet') p.location_id = Number(loc);
  U.busy = true;
  try { await call('xc_recipient_save', { p_id: null, p: p }); toast(t('saved')); await load(); }
  catch (e) { toast(eText(e)); } finally { U.busy = false; }
}
async function setActive(a) {
  if (U.busy) return;
  const id = Number(a.dataset.id), on = a.dataset.v === '1';
  U.busy = true;
  try { await call('xc_recipient_save', { p_id: id, p: { active: on } }); toast(t('saved')); await load(); }
  catch (e) { toast(eText(e)); } finally { U.busy = false; }
}

Object.assign(H, {
  xs_save: () => save(),
  xs_active: (a) => setActive(a),
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(t('xc_sum_title'), `<p class="muted">${esc(t('xc_sum_intro'))}</p><div id="xs_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  try { await load(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { xcsummary: view });
})();
