/* Islamia BOS · Integrations desk (#/integrations) - P3 gaps #21 SMS/WhatsApp queue, #22 payment-gateway reconciliation, #23 accounting CSV export, #30 assistant access.
   Server side: supabase/phase62.sql. This page READS and exports only (nothing here calls an SMS provider or a payment gateway):
     notify_outbox_summary (queue counts, last 50 masked) / notify_cancel · payment_recon · acct_export_csv · assistant_access_list.
   Who sees what: SMS tab = owner or customer_manage · Payments + Export tabs = owner or accounts_manage · Assistant tab = owner only. The server decides; a refused call shows a friendly line.
   Sending SMS is done by tools/notify_sms.py (secrets in GitHub secrets, default OFF); the gateway is reached only by an Edge function (docs/INTEGRATIONS_P3C.md). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('সংযোগ ও এক্সপোর্ট', 'Integrations & export', 'Integrations ও export'),
  intro: L('এখানে কিছুই বাইরে পাঠানো হয় না — শুধু কিউ, মিলানো ও ফাইল। পাঠানোর কাজ আলাদা স্ক্রিপ্টে, গোপন চাবি অ্যাপে নেই।', 'Nothing is sent out from here - only the queue, matching and files. Sending runs in a separate script; no secret key is in the app.', 'এখানে থেকে কিছু বাইরে যায় না — queue, matching ও file। পাঠানো আলাদা script-এ; secret key app-এ নেই।'),
  t_sms: L('SMS/WhatsApp', 'SMS/WhatsApp', 'SMS/WhatsApp'), t_pay: L('পেমেন্ট মিলান', 'Payments', 'Payment মিলান'), t_exp: L('হিসাব এক্সপোর্ট', 'Accounts export', 'Accounts export'), t_ast: L('সহকারী অনুমতি', 'Assistant access', 'Assistant access'),
  on: L('চালু', 'ON', 'ON'), off: L('বন্ধ (সুইচবোর্ডে চালু করুন)', 'OFF (switch on in the Switchboard)', 'OFF (Switchboard-এ চালু করুন)'),
  queued: L('অপেক্ষায়', 'Queued', 'Queued'), sending: L('পাঠানো হচ্ছে', 'Sending', 'Sending'), sent: L('গেছে', 'Sent', 'Sent'), failed: L('ব্যর্থ', 'Failed', 'Failed'), cancelled: L('ক্যান্সেল', 'Cancelled', 'Cancelled'),
  cancel: L('ক্যান্সেল করুন', 'Cancel', 'Cancel'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'), tries: L('চেষ্টা', 'tries', 'tries'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখুন', 'Show', 'Show'), state: L('অবস্থা', 'State', 'State'), all: L('সব', 'All', 'All'),
  s_open: L('খোলা', 'Open', 'Open'), s_closed_unpaid: L('অনাদায়ী বন্ধ', 'Closed unpaid', 'Closed unpaid'), s_refunded: L('ফেরত', 'Refunded', 'Refunded'),
  s_missing_payment: L('পেমেন্ট এন্ট্রি নেই', 'Payment not entered', 'Payment entry নেই'), s_voided_payment: L('পেমেন্ট ভয়েড', 'Payment voided', 'Payment voided'),
  s_amount_mismatch: L('টাকা মেলেনি', 'Amount mismatch', 'Amount মেলেনি'), s_matched: L('মিলেছে', 'Matched', 'Matched'),
  orphans: L('অচেনা ইভেন্ট', 'Unknown events', 'Unknown events'), diff: L('পার্থক্য', 'Difference', 'Difference'),
  k_journal: L('জার্নাল (প্রতিটি লাইন)', 'Journal (every line)', 'Journal (প্রতিটি line)'), k_tb: L('ট্রায়াল ব্যালান্স', 'Trial balance', 'Trial balance'),
  dl: L('CSV ডাউনলোড', 'Download CSV', 'CSV download'), cols: L('কলাম', 'Columns', 'Columns'), trunc: L('অনেক লাইন — প্রথম ৫০,০০০টি; ডেট ছোট করুন', 'Many lines - first 50,000 only; narrow the dates', 'অনেক line — প্রথম 50,000; date ছোট করুন'),
  needData: L('হিসাব শুরুর ডেট দেওয়া নেই (তথ্য দরকার)', 'The accounting start date is not set (data needed)', 'Accounting start date নেই (data needed)'),
  ready: L('ফাইল তৈরি', 'File ready', 'File তৈরি'), rowsT: L('সারি', 'rows', 'rows'),
  astIntro: L('মালিক ছাড়া কেউ সহকারী দেখে না — যতক্ষণ না আপনি "ব্যবসার সহকারী ব্যবহার" অনুমতি দেন। দিতে/তুলে নিতে দায়িত্ব বণ্টন পেজ ব্যবহার করুন।', 'Only the owner sees the assistant unless you give the "Use the business assistant" right. Give or take it back on the delegation page.', 'Owner ছাড়া কেউ assistant দেখে না — যতক্ষণ আপনি "assistant_use" অনুমতি না দেন। দিতে/তুলতে Delegation পেজ।'),
  astOpen: L('দায়িত্ব বণ্টন খুলুন', 'Open delegation', 'Delegation খুলুন'), astUsers: L('যাদের আছে', 'Who has it', 'যাদের আছে'), astRoles: L('যে রোলে', 'Roles', 'Roles'), astAll: L('সব জায়গা', 'All places', 'সব জায়গা'),
  e_not_allowed: L('এই অংশ দেখার অনুমতি আপনার নেই', 'You do not have access to this part', 'এই অংশের access নেই'), e_bad_range: L('ডেটের সীমা ঠিক নয়', 'The date range is not valid', 'Date range ঠিক নয়'),
  e_not_cancellable: L('এটি আর ক্যান্সেল করা যায় না', 'This can no longer be cancelled', 'এটা আর cancel হয় না'),
};
const T = (k) => lab(X[k]);
const D = { tab: 'sms', sms: null, pay: null, exp: null, ast: null, st: '', from: '', to: '', ek: 'journal', ef: '', et: '', err: {} };
const FRIENDLY = { 'not allowed': 'e_not_allowed', bad_range: 'e_bad_range', not_cancellable: 'e_not_cancellable' };
const msg = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(FRIENDLY).find((x) => m.indexOf(x) >= 0); return k ? T(FRIENDLY[k]) : m; };
const dhaka = (off) => new Date(Date.now() + 6 * 3600e3 + (off || 0) * 864e5).toISOString().slice(0, 10);
const num = (v) => (Number.isFinite(Number(v)) ? Number(v).toLocaleString('en-US', { maximumFractionDigits: 2 }) : '-');

/* ---------- pure helpers (tested) ---------- */
const stateTxt = (s) => (X['s_' + s] ? T('s_' + s) : String(s || ''));
const stateTone = (s) => ({ matched: 'ok', open: '', refunded: '', closed_unpaid: '', missing_payment: 'warn', voided_payment: 'warn', amount_mismatch: 'bad' }[s] || '');
const guardCsv = (t) => String(t).replace(/(^|,|\n)("?)([=+\-@\t\r])(?!\d*(\.\d+)?(,|\n|"|$))/g, "$1$2'$3");   // spreadsheet formula guard: a cell starting with = + - @ tab CR gets a leading apostrophe (plain numbers are left alone)
const csvFile = (r) => ({ name: String((r && r.filename) || 'export.csv').replace(/[^A-Za-z0-9_.\-]/g, '_').replace(/\.{2,}/g, '.'), text: '﻿' + guardCsv((r && r.csv) || '') });
function download(name, text) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' })); a.download = name;
  document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
}

/* ---------- drawing ---------- */
const errBox = (k) => (D.err[k] ? `<p class="muted" role="alert">${esc(D.err[k])}</p>` : '');
function drawSms() {
  const d = D.sms; if (!d) return D.err.sms ? errBox('sms') : '<p class="muted">…</p>';
  const c = d.counts || {};
  return `<div class="card stack"><div class="row between"><b>${esc(T('t_sms'))}</b><span class="chip ${d.on ? 'ok' : 'warn'}">${esc(d.on ? T('on') : T('off'))}</span></div>
    <div class="row wrap">${['queued', 'sending', 'sent', 'failed', 'cancelled'].map((s) => `<span class="chip">${esc(T(s))}: ${esc(String(c[s] || 0))}</span>`).join('')}</div></div>
    <div class="card stack">${(d.recent || []).length ? d.recent.map((r) => `<div class="row between wrap"><span>#${esc(String(r.id))} · ${esc(r.channel)} · ${esc(r.template)} · ${esc(r.to)}</span>
      <span class="muted">${esc(T(r.status))} · ${esc(String(r.attempts))}/${esc(String(r.max_attempts))} ${esc(T('tries'))}${r.last_error ? ' · ' + esc(r.last_error) : ''}</span>
      ${r.status === 'queued' || r.status === 'failed' ? `<button type="button" class="mini" data-act="ig_cancel" data-id="${esc(String(r.id))}">${esc(T('cancel'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}
function drawPay() {
  const d = D.pay;
  const filt = `<div class="row wrap"><label>${esc(T('from'))} <input type="date" id="ig_pf" value="${esc(D.from)}"></label><label>${esc(T('to'))} <input type="date" id="ig_pt" value="${esc(D.to)}"></label>
    <select id="ig_ps"><option value="">${esc(T('all'))}</option>${['open', 'closed_unpaid', 'refunded', 'missing_payment', 'voided_payment', 'amount_mismatch', 'matched'].map((s) => `<option value="${s}" ${D.st === s ? 'selected' : ''}>${esc(stateTxt(s))}</option>`).join('')}</select>
    <button type="button" class="btn" data-act="ig_pay_go">${esc(T('show'))}</button></div>`;
  if (!d) return `<div class="card stack">${filt}${errBox('pay')}${D.err.pay ? '' : '<p class="muted">…</p>'}</div>`;
  const cn = d.counts || {};
  return `<div class="card stack">${filt}<div class="row wrap"><span class="chip ${d.on ? 'ok' : 'warn'}">${esc(d.on ? T('on') : T('off'))}</span>${Object.keys(cn).map((s) => `<span class="chip ${stateTone(s)}">${esc(stateTxt(s))}: ${esc(String(cn[s]))}</span>`).join('')}</div></div>
    <div class="card stack">${(d.rows || []).length ? d.rows.map((r) => `<div class="row between wrap"><span>#${esc(String(r.intent_id))} · ${esc(r.provider)} · ${esc(r.provider_ref || '-')} · ৳ ${esc(num(r.intent_amount))}</span>
      <span class="chip ${stateTone(r.state)}">${esc(stateTxt(r.state))}${Number(r.diff) ? ' · ' + esc(T('diff')) + ' ' + esc(num(r.diff)) : ''}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>
    ${(d.orphan_events || []).length ? `<div class="card stack"><b>${esc(T('orphans'))}</b>${d.orphan_events.map((o) => `<div class="muted">${esc(o.provider)} · ${esc(o.provider_ref || '-')} · ${esc(o.note)} · ${esc(num(o.amount))}</div>`).join('')}</div>` : ''}`;
}
function drawExp() {
  const d = D.exp;
  return `<div class="card stack"><div class="row wrap"><select id="ig_ek"><option value="journal" ${D.ek === 'journal' ? 'selected' : ''}>${esc(T('k_journal'))}</option><option value="trial_balance" ${D.ek === 'trial_balance' ? 'selected' : ''}>${esc(T('k_tb'))}</option></select>
    <label>${esc(T('from'))} <input type="date" id="ig_ef" value="${esc(D.ef)}"></label><label>${esc(T('to'))} <input type="date" id="ig_et" value="${esc(D.et)}"></label>
    <button type="button" class="btn primary" data-act="ig_export">${esc(T('dl'))}</button></div>${errBox('exp')}
    ${d ? (d.data_needed ? `<p class="muted">${esc(T('needData'))}</p>` : `<p>${esc(T('ready'))}: ${esc(d.filename)} · ${esc(String(d.rows))} ${esc(T('rowsT'))}</p>${d.truncated ? `<p class="muted">${esc(T('trunc'))}</p>` : ''}
      <p class="muted" style="font-size:.85rem">${esc(T('cols'))}: ${esc((d.columns || []).join(', '))}</p>`) : ''}</div>`;
}
function drawAst() {
  const d = D.ast; if (!d) return D.err.ast ? errBox('ast') : '<p class="muted">…</p>';
  return `<div class="card stack"><p>${esc(T('astIntro'))}</p><a class="btn" href="#/delegation">${esc(T('astOpen'))}</a>
    <b>${esc(T('astUsers'))}</b>${(d.users || []).length ? d.users.map((u) => `<div class="row between"><span>${esc(u.name || '')}</span><span class="muted">${u.location_id ? '#' + esc(String(u.location_id)) : esc(T('astAll'))}${u.valid_until ? ' · ' + esc(String(u.valid_until).slice(0, 10)) : ''}</span></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    ${(d.roles || []).length ? `<b>${esc(T('astRoles'))}</b><div class="row wrap">${d.roles.map((r) => `<span class="chip">${esc(r)}</span>`).join('')}</div>` : ''}</div>`;
}
function draw() {
  const el = $('#ig_body'); if (!el) return;
  const tabs = ['sms', 'pay', 'exp', 'ast'];
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p><div class="row wrap" role="tablist">${tabs.map((t) => `<button type="button" class="btn ${D.tab === t ? 'primary' : ''}" role="tab" aria-selected="${D.tab === t}" data-act="ig_tab" data-t="${t}">${esc(T('t_' + t))}</button>`).join('')}</div>
    ${D.tab === 'sms' ? drawSms() : D.tab === 'pay' ? drawPay() : D.tab === 'exp' ? drawExp() : drawAst()}`;
}

/* ---------- loading ---------- */
async function load(tab) {
  D.err[tab] = '';
  try {
    if (tab === 'sms') { D.sms = null; const r = await sb.rpc('notify_outbox_summary'); if (r.error) throw r.error; D.sms = r.data; }
    if (tab === 'pay') { D.pay = null; const r = await sb.rpc('payment_recon', { p_from: D.from || null, p_to: D.to || null, p_state: D.st || null }); if (r.error) throw r.error; D.pay = r.data; }
    if (tab === 'ast') { D.ast = null; const r = await sb.rpc('assistant_access_list'); if (r.error) throw r.error; D.ast = r.data; }
  } catch (e) { D.err[tab] = msg(e); }
  draw();
}
Object.assign(H, {
  ig_tab: async (a) => { D.tab = a.dataset.t; draw(); await load(D.tab); },
  ig_cancel: async (a) => { const r = await sb.rpc('notify_cancel', { p_id: Number(a.dataset.id) }); if (r.error) return toast(msg(r.error)); await load('sms'); },
  ig_pay_go: async () => { D.from = ($('#ig_pf') || {}).value || ''; D.to = ($('#ig_pt') || {}).value || ''; D.st = ($('#ig_ps') || {}).value || ''; await load('pay'); },
  ig_export: async () => {
    D.ek = ($('#ig_ek') || {}).value || 'journal'; D.ef = ($('#ig_ef') || {}).value || ''; D.et = ($('#ig_et') || {}).value || '';
    D.err.exp = '';
    const r = await sb.rpc('acct_export_csv', { p_kind: D.ek, p_from: D.ef || null, p_to: D.et || null, p_loc: null });
    if (r.error) { D.err.exp = msg(r.error); D.exp = null; return draw(); }
    D.exp = r.data; if (!r.data.data_needed) { const f = csvFile(r.data); download(f.name, f.text); }
    draw();
  },
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  D.sms = D.pay = D.exp = D.ast = null; D.from = dhaka(-30); D.to = dhaka(0); D.ef = ''; D.et = dhaka(0);
  shell(T('title'), '<div id="ig_body" class="stack"></div>', true);
  draw(); await load(D.tab);
}
B.integrations = { stateTxt, stateTone, csvFile, msg };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { integrations: view });
})();
