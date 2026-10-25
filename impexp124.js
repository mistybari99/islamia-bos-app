/* Islamia BOS · Import-Export (#/impexp): a small register of import / export shipments for ONE import_export business, plus its currency list and exchange rates.
   Server (supabase/phase124.sql), all calls take the business id (org unit) and are scoped by it:
     ie_businesses124() -> rows {id, code, name_bn, name_en, base_currency, can_manage, impexp_on}; ie_currencies_list(p_org); ie_fx_rates_list(p_org, p_currency, p_limit);
     currency_save(p_org, p_code, p_name_bn, p_name_en, p_decimals, p_active, p_client); fx_rate_set(p_org, p_currency, p_rate, p_valid_from, p_note, p_client);
     shipment_save(p_org, p_id, p_direction, p_reference, p_counterparty, p_currency, p_amount, p_rate, p_ship_date, p_eta_date, p_notes, p_freight, p_insurance, p_duty_tax, p_other, p_client);
     shipment_set_status(p_org, p_id, p_status, p_note, p_client); shipments_list(p_org, p_status, p_direction, p_limit); shipments_by_currency(p_org, p_from, p_to).
   Nothing is posted to the accounts. No currency, rate or business name is written here: everything comes from the data. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'i' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const num = (v) => { const s = String(v == null ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim(); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fmt = (n, d = 2) => (n == null ? '' : Number(n).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }));
const X = {
  title: L('আমদানি-রপ্তানি', 'Import-Export', 'Import-Export'), ship: L('শিপমেন্ট', 'Shipments', 'Shipments'), money: L('মুদ্রা ও রেট', 'Currencies & rates', 'Currency ও Rate'),
  add: L('নতুন শিপমেন্ট', 'New shipment', 'নতুন Shipment'), edit: L('বদলান', 'Edit', 'বদলান'), st: L('অবস্থা', 'Status', 'Status'), all: L('সব', 'All', 'সব'),
  dir: L('ধরন', 'Type', 'ধরন'), imp: L('আমদানি', 'Import', 'Import'), exp: L('রপ্তানি', 'Export', 'Export'), ref: L('রেফারেন্স / নম্বর', 'Reference / number', 'Reference / নম্বর'),
  party: L('পার্টি (যার সাথে লেনদেন)', 'Counterparty', 'Party'), cur: L('মুদ্রা', 'Currency', 'Currency'), amt: L('পণ্যের দাম (ওই মুদ্রায়)', 'Goods amount (in that currency)', 'পণ্যের দাম'),
  rate: L('রেট (খালি = চালু রেট)', 'Rate (empty = current rate)', 'Rate (খালি = চালু rate)'), sdate: L('শিপমেন্টের ডেট', 'Shipment date', 'Shipment date'), eta: L('পৌঁছানোর আনুমানিক ডেট', 'Expected arrival', 'Expected arrival'),
  notes: L('নোট', 'Notes', 'Note'), costs: L('অতিরিক্ত খরচ (আপনার দেওয়া অঙ্ক, মূল মুদ্রায়)', 'Extra costs (amounts you enter, base currency)', 'অতিরিক্ত খরচ (আপনার দেওয়া, base currency)'),
  freight: L('ভাড়া', 'Freight', 'Freight'), insur: L('বীমা', 'Insurance', 'Insurance'), duty: L('শুল্ক / কর', 'Duty / tax', 'Duty / tax'), other: L('অন্যান্য', 'Other', 'Other'),
  save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('এখনো কিছু নেই', 'Nothing yet', 'এখনো কিছু নেই'), goods: L('পণ্য', 'Goods', 'Goods'), landed: L('মোট খরচ', 'Landed cost', 'Landed cost'),
  bycur: L('মুদ্রা অনুযায়ী', 'By currency', 'Currency অনুযায়ী'), biz: L('ব্যবসা', 'Business', 'Business'), base: L('মূল মুদ্রা', 'Base currency', 'Base currency'),
  off: L('এই মডিউল এখন বন্ধ। দেখা যায়, কিন্তু লেখা যায় না। মালিক সুইচবোর্ড থেকে চালু করবেন।', 'This module is off: you can look but not write. The owner turns it on in the Switchboard.', 'এই module এখন off। দেখা যায়, লেখা যায় না। Owner Switchboard থেকে on করবেন।'),
  noperm: L('এই পাতা দেখার অনুমতি বা কোনো আমদানি-রপ্তানি ব্যবসা নেই।', 'No import-export business, or no permission to see it.', 'Import-export business নেই, বা permission নেই।'),
  nogl: L('হিসাবে (GL) কিছু পোস্ট হয় না।', 'Nothing is posted to the accounts.', 'হিসাবে (GL) কিছু post হয় না।'),
  curs: L('মুদ্রার তালিকা', 'Currency list', 'Currency list'), addcur: L('মুদ্রা যোগ', 'Add currency', 'Currency যোগ'), code: L('কোড (৩ অক্ষর, যেমন USD)', 'Code (3 letters, e.g. USD)', 'Code (৩ অক্ষর)'),
  nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'), dec: L('দশমিক ঘর', 'Decimals', 'Decimals'), active: L('চালু', 'Active', 'Active'),
  setrate: L('রেট দিন', 'Set rate', 'Rate দিন'), rate1: L('১ একক = কত (মূল মুদ্রায়)', '1 unit = how much (base currency)', '১ unit = কত (base)'), from: L('কার্যকর ডেট', 'Valid from', 'Valid from'),
  norate: L('রেট নেই', 'No rate', 'Rate নেই'), hist: L('রেটের ইতিহাস', 'Rate history', 'Rate history'), setst: L('অবস্থা বদলান', 'Change status', 'Status বদলান'), note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note'),
  close: L('বন্ধ', 'Close', 'Close'), listed: L('তালিকায় মুদ্রা নেই; আগে "মুদ্রা ও রেট" থেকে যোগ করুন।', 'No currency listed; add one under "Currencies & rates" first.', 'Currency নেই; আগে "Currency ও Rate" থেকে যোগ করুন।'),
};
const T = (k) => lab(X[k]);
const STAT = { draft: L('খসড়া', 'Draft', 'Draft'), booked: L('বুক হয়েছে', 'Booked', 'Booked'), in_transit: L('পথে', 'In transit', 'In transit'), received: L('পৌঁছেছে', 'Received', 'Received'),
  closed: L('শেষ', 'Closed', 'Closed'), cancelled: L('বাতিল', 'Cancelled', 'Cancelled') };
const NEXT = { draft: ['booked', 'cancelled'], booked: ['in_transit', 'received', 'cancelled'], in_transit: ['received', 'cancelled'], received: ['closed'], closed: [], cancelled: [] };
const ERR = {
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'Not allowed'), impexp_off: L('এই মডিউল বন্ধ আছে', 'The module is switched off', 'The module is switched off'), business_not_active: L('ব্যবসাটি চালু নেই', 'The business is not active', 'The business is not active'),
  client_id_needed: L('আবার চেষ্টা করুন', 'Please try again', 'Please try again'), reference_taken: L('এই রেফারেন্স আগেই আছে', 'This reference already exists', 'This reference already exists'), bad_reference: L('রেফারেন্স লিখুন (১-৬০ অক্ষর)', 'Enter a reference (1-60 characters)', 'Enter a reference (1-60 characters)'),
  bad_amount: L('অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount is not valid'), bad_rate: L('রেট ঠিক নয়', 'Rate is not valid', 'Rate is not valid'), no_rate: L('এই মুদ্রার রেট নেই; রেট দিন বা "মুদ্রা ও রেট" থেকে যোগ করুন', 'No rate for this currency: type one or add it under Currencies & rates', 'No rate for this currency: type one or add it under Currencies & rates'),
  currency_not_listed: L('মুদ্রাটি তালিকায় নেই বা বন্ধ', 'Currency is not in the list (or inactive)', 'Currency is not in the list (or inactive)'), bad_currency: L('মুদ্রার কোড ঠিক নয়', 'Currency code is not valid', 'Currency code is not valid'), is_base_currency: L('এটি মূল মুদ্রা; যোগ করতে হবে না', 'This is the base currency; no need to add it', 'This is the base currency; no need to add it'),
  bad_date: L('ডেট ঠিক নয়', 'Date is not valid', 'Date is not valid'), period_closed: L('এই মাসের হিসাব বন্ধ', 'This period is closed', 'This period is closed'), amount_locked: L('পথে/পৌঁছানোর পর দাম বদলানো যায় না', 'The amount cannot change after the goods are on the way', 'The amount cannot change after the goods are on the way'),
  shipment_final: L('শেষ/বাতিল শিপমেন্ট বদলানো যায় না', 'A closed or cancelled shipment cannot be changed', 'A closed or cancelled shipment cannot be changed'), bad_transition: L('এই অবস্থায় যাওয়া যায় না', 'Cannot move to that status', 'Cannot move to that status'),
  bad_direction: L('ধরন বাছুন', 'Choose import or export', 'Choose import or export'), bad_name: L('নাম ঠিক নয়', 'Name is not valid', 'Name is not valid'), bad_decimals: L('দশমিক ঘর ০-৪', 'Decimals must be 0-4', 'Decimals must be 0-4'), shipment_not_found: L('শিপমেন্ট পাওয়া যায়নি', 'Shipment not found', 'Shipment not found'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const D = { biz: [], org: null, tab: 'ship', filt: '', ships: [], sum: [], curs: [], rates: [], client: rid() };
const cur = () => D.biz.find((b) => String(b.id) === String(D.org)) || null;
const canW = () => { const b = cur(); return !!(b && b.can_manage && b.impexp_on); };
const curOpts = (sel) => { const b = cur(); const base = b ? b.base_currency : ''; const list = [base].concat(D.curs.filter((c) => c.active).map((c) => c.code)).filter(Boolean);
  return list.map((c) => `<option value="${esc(c)}" ${c === sel ? 'selected' : ''}>${esc(c)}</option>`).join(''); };

async function load() {
  const b = await sb.rpc('ie_businesses124'); if (b.error) throw b.error;
  D.biz = b.data || [];
  if (!cur()) D.org = D.biz[0] ? D.biz[0].id : null;
  if (!D.org) { D.ships = []; D.sum = []; D.curs = []; D.rates = []; return; }
  const [s, y, c, r] = await Promise.all([
    sb.rpc('shipments_list', { p_org: D.org, p_status: D.filt || null, p_direction: null, p_limit: 200 }),
    sb.rpc('shipments_by_currency', { p_org: D.org, p_from: null, p_to: null }),
    sb.rpc('ie_currencies_list', { p_org: D.org }),
    sb.rpc('ie_fx_rates_list', { p_org: D.org, p_currency: null, p_limit: 100 }),
  ]);
  for (const x of [s, y, c, r]) if (x.error) throw x.error;
  D.ships = s.data || []; D.sum = y.data || []; D.curs = c.data || []; D.rates = r.data || [];
}
function head() {
  const b = cur();
  const pick = D.biz.length > 1 ? `<div><label for="ie_biz">${esc(T('biz'))}</label><select id="ie_biz">${D.biz.map((x) => `<option value="${esc(x.id)}" ${String(x.id) === String(D.org) ? 'selected' : ''}>${esc(lab(L(x.name_bn, x.name_en || x.name_bn, x.name_bn)))}</option>`).join('')}</select></div>` : '';
  return `${pick}<div class="muted">${esc(T('base'))}: <b>${esc(b.base_currency || '')}</b> · ${esc(T('nogl'))}</div>
    ${b.impexp_on ? '' : `<div class="card" id="ie_off"><p class="muted">${esc(T('off'))}</p></div>`}
    <div class="row"><button class="full ${D.tab === 'ship' ? 'primary' : ''}" data-act="ie_tab" data-v="ship">${esc(T('ship'))}</button><button class="full ${D.tab === 'money' ? 'primary' : ''}" data-act="ie_tab" data-v="money">${esc(T('money'))}</button></div>`;
}
function shipHTML() {
  const b = cur();
  const sum = D.sum.length ? `<div class="card"><b>${esc(T('bycur'))}</b>${D.sum.map((r) => `<div class="muted">${esc(r.currency)} · ${esc(lab(r.direction === 'import' ? X.imp : X.exp))} · ${esc(r.shipments)} · ${fmt(r.amount)} → <b>${fmt(r.amount_base)} ${esc(b.base_currency)}</b></div>`).join('')}</div>` : '';
  const filt = `<div><label for="ie_filt">${esc(T('st'))}</label><select id="ie_filt"><option value="">${esc(T('all'))}</option>${Object.keys(STAT).map((k) => `<option value="${k}" ${D.filt === k ? 'selected' : ''}>${esc(lab(STAT[k]))}</option>`).join('')}</select></div>`;
  const add = canW() ? `<button class="full primary" data-act="ie_new">＋ ${esc(T('add'))}</button>` : '';
  const rows = D.ships.length ? D.ships.map((s) => `<div class="card ie-ship" data-id="${esc(s.id)}"><div class="row between"><b>${esc(s.reference)}</b><span class="chip">${esc(lab(STAT[s.status] || L(s.status, s.status, s.status)))}</span></div>
      <div class="muted">${esc(lab(s.direction === 'import' ? X.imp : X.exp))}${s.counterparty ? ' · ' + esc(s.counterparty) : ''} · ${esc(s.ship_date)}</div>
      <div>${esc(s.currency)} ${fmt(s.amount)} × ${esc(Number(s.rate))} = <b>${fmt(s.amount_base)} ${esc(b.base_currency)}</b></div>
      <div class="muted">${esc(T('landed'))}: <b>${fmt(s.landed_base)} ${esc(b.base_currency)}</b></div>
      ${canW() && NEXT[s.status] ? `<div class="row">${s.status !== 'closed' && s.status !== 'cancelled' ? `<button style="min-height:44px;padding:0 14px" data-act="ie_edit" data-id="${esc(s.id)}">${esc(T('edit'))}</button>` : ''}${NEXT[s.status].length ? `<button style="min-height:44px;padding:0 14px" data-act="ie_status" data-id="${esc(s.id)}">${esc(T('setst'))}</button>` : ''}</div>` : ''}</div>`).join('')
    : `<p class="muted">${esc(T('none'))}</p>`;
  return add + sum + filt + rows;
}
function moneyHTML() {
  const b = cur();
  const latest = (c) => { const r = D.rates.find((x) => x.currency === c); return r ? `${esc(Number(r.rate))} <span class="muted">(${esc(r.valid_from)})</span>` : `<span class="muted">${esc(T('norate'))}</span>`; };
  const add = canW() ? `<button class="full" data-act="ie_curnew">＋ ${esc(T('addcur'))}</button>` : '';
  const rows = D.curs.length ? D.curs.map((c) => `<div class="card"><div class="row between"><b>${esc(c.code)} · ${esc(lab(L(c.name_bn, c.name_en || c.name_bn, c.name_bn)))}</b>${c.active ? '' : `<span class="chip">${esc(T('close'))}</span>`}</div>
      <div>1 ${esc(c.code)} = ${latest(c.code)} ${esc(b.base_currency)}</div>
      ${canW() ? `<div class="row"><button style="min-height:44px;padding:0 14px" data-act="ie_ratenew" data-c="${esc(c.code)}">${esc(T('setrate'))}</button><button style="min-height:44px;padding:0 14px" data-act="ie_curedit" data-c="${esc(c.code)}">${esc(T('edit'))}</button></div>` : ''}</div>`).join('') : `<p class="muted">${esc(T('listed'))}</p>`;
  const hist = D.rates.length ? `<details data-ctl="off"><summary>${esc(T('hist'))}</summary>${D.rates.slice(0, 30).map((r) => `<div class="muted">${esc(r.valid_from)} · ${esc(r.currency)} = ${esc(Number(r.rate))}${r.note ? ' · ' + esc(r.note) : ''}</div>`).join('')}</details>` : '';
  return `<h3>${esc(T('curs'))}</h3>${add}${rows}${hist}`;
}
function draw() {
  const el = $('#ie_body'); if (!el) return;
  if (!cur()) { el.innerHTML = `<div class="card" id="ie_noperm"><p class="muted">${esc(T('noperm'))}</p></div>`; return; }
  el.innerHTML = head() + (D.tab === 'ship' ? shipHTML() : moneyHTML());
}
async function refresh() { await load(); draw(); }
const err = (m) => { const o = $('#ie_err'); if (o) { o.textContent = m; o.hidden = false; } else toast(m); };
const inp = (id, label, extra = '') => `<div><label for="${id}">${esc(label)}</label><input id="${id}" autocomplete="off" ${extra}></div>`;

function shipSheet(s) {
  const e = s || {}; const lock = s && !['draft', 'booked'].includes(s.status);
  if (!s) D.client = rid();
  openSheet(`<h3>${esc(s ? s.reference : T('add'))}</h3><div class="stack" id="ie_form">
    <div><label for="ie_dir">${esc(T('dir'))}</label><select id="ie_dir" ${s ? 'disabled' : ''}><option value="import" ${e.direction === 'import' ? 'selected' : ''}>${esc(T('imp'))}</option><option value="export" ${e.direction === 'export' ? 'selected' : ''}>${esc(T('exp'))}</option></select></div>
    ${inp('ie_ref', T('ref'), `maxlength="60" value="${esc(e.reference || '')}" ${s ? 'disabled' : ''}`)}
    ${inp('ie_party', T('party'), `maxlength="200" value="${esc(e.counterparty || '')}"`)}
    <div><label for="ie_cur">${esc(T('cur'))}</label><select id="ie_cur" ${lock ? 'disabled' : ''}>${curOpts(e.currency)}</select></div>
    ${inp('ie_amt', T('amt'), `inputmode="decimal" value="${esc(e.amount == null ? '' : e.amount)}" ${lock ? 'disabled' : ''}`)}
    ${inp('ie_rate', T('rate'), `inputmode="decimal" value="${esc(e.rate == null ? '' : Number(e.rate))}" ${lock ? 'disabled' : ''}`)}
    <div><label for="ie_sd">${esc(T('sdate'))}</label><input id="ie_sd" type="date" value="${esc(e.ship_date || today())}"></div>
    <div><label for="ie_eta">${esc(T('eta'))}</label><input id="ie_eta" type="date" value="${esc(e.eta_date || '')}"></div>
    <b>${esc(T('costs'))}</b>
    ${inp('ie_fr', T('freight'), `inputmode="decimal" value="${esc(e.freight || '')}"`)}${inp('ie_in', T('insur'), `inputmode="decimal" value="${esc(e.insurance || '')}"`)}
    ${inp('ie_du', T('duty'), `inputmode="decimal" value="${esc(e.duty_tax || '')}"`)}${inp('ie_ot', T('other'), `inputmode="decimal" value="${esc(e.other_cost || '')}"`)}
    ${inp('ie_nt', T('notes'), `maxlength="1000" value="${esc(e.notes || '')}"`)}
    <p id="ie_err" class="muted" role="alert" hidden></p>
    <button class="full primary" data-act="ie_ship_save" data-id="${esc(s ? s.id : '')}">${esc(T('save'))}</button></div>`);
}
function statusSheet(s) {
  openSheet(`<h3>${esc(s.reference)}</h3><div class="stack"><div class="muted">${esc(T('st'))}: ${esc(lab(STAT[s.status]))}</div>
    ${NEXT[s.status].map((k) => `<button class="full" data-act="ie_status_go" data-id="${esc(s.id)}" data-to="${k}">${esc(lab(STAT[k]))}</button>`).join('')}
    ${inp('ie_stnote', T('note'), 'maxlength="500"')}<p id="ie_err" class="muted" role="alert" hidden></p></div>`);
}
function curSheet(c) {
  const e = c || {}; D.client = rid();
  openSheet(`<h3>${esc(c ? c.code : T('addcur'))}</h3><div class="stack">
    ${inp('ie_cc', T('code'), `maxlength="3" autocapitalize="characters" value="${esc(e.code || '')}" ${c ? 'disabled' : ''}`)}${inp('ie_cbn', T('nbn'), `maxlength="80" value="${esc(e.name_bn || '')}"`)}${inp('ie_cen', T('nen'), `maxlength="80" value="${esc(e.name_en || '')}"`)}
    ${inp('ie_cd', T('dec'), `inputmode="numeric" maxlength="1" value="${esc(e.decimals == null ? 2 : e.decimals)}"`)}
    <div><label for="ie_ca">${esc(T('active'))}</label><select id="ie_ca"><option value="1" ${e.active === false ? '' : 'selected'}>${esc(T('active'))}</option><option value="0" ${e.active === false ? 'selected' : ''}>${esc(T('close'))}</option></select></div>
    <p id="ie_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="ie_cur_save">${esc(T('save'))}</button></div>`);
}
function rateSheet(code) {
  D.client = rid();
  openSheet(`<h3>${esc(T('setrate'))} · ${esc(code)}</h3><div class="stack"><input type="hidden" id="ie_rc" value="${esc(code)}">
    ${inp('ie_rv', T('rate1'), 'inputmode="decimal"')}<div><label for="ie_rd">${esc(T('from'))}</label><input id="ie_rd" type="date" value="${today()}"></div>${inp('ie_rn', T('note'), 'maxlength="300"')}
    <p id="ie_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="ie_rate_save">${esc(T('save'))}</button></div>`);
}
const money = (id) => { const v = num($(id).value); return v === null ? 0 : v; };
Object.assign(H, {
  ie_tab: (a) => { D.tab = a.dataset.v; draw(); },
  ie_new: () => shipSheet(null),
  ie_edit: (a) => { const s = D.ships.find((x) => String(x.id) === a.dataset.id); if (s) shipSheet(s); },
  ie_status: (a) => { const s = D.ships.find((x) => String(x.id) === a.dataset.id); if (s) statusSheet(s); },
  ie_curnew: () => curSheet(null),
  ie_curedit: (a) => { const c = D.curs.find((x) => x.code === a.dataset.c); if (c) curSheet(c); },
  ie_ratenew: (a) => rateSheet(a.dataset.c),
  ie_ship_save: async (a) => {
    const id = a.dataset.id ? Number(a.dataset.id) : null; const amt = num($('#ie_amt').value), rt = num($('#ie_rate').value);
    const costs = ['#ie_fr', '#ie_in', '#ie_du', '#ie_ot'].map(money);
    if (!id && !$('#ie_ref').value.trim()) return err(lab(ERR.bad_reference));
    if (amt === null || Number.isNaN(amt) || amt < 0 || Number.isNaN(rt) || costs.some((c) => Number.isNaN(c) || c < 0)) return err(lab(ERR.bad_amount));
    const r = await sb.rpc('shipment_save', { p_org: D.org, p_id: id, p_direction: id ? null : $('#ie_dir').value, p_reference: id ? null : $('#ie_ref').value.trim(), p_counterparty: $('#ie_party').value.trim() || null,
      p_currency: $('#ie_cur').value, p_amount: amt, p_rate: rt, p_ship_date: $('#ie_sd').value || null, p_eta_date: $('#ie_eta').value || null, p_notes: $('#ie_nt').value.trim() || null,
      p_freight: costs[0], p_insurance: costs[1], p_duty_tax: costs[2], p_other: costs[3], p_client: id ? null : D.client });
    if (r.error) return err(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
  ie_status_go: async (a) => {
    const r = await sb.rpc('shipment_set_status', { p_org: D.org, p_id: Number(a.dataset.id), p_status: a.dataset.to, p_note: ($('#ie_stnote').value || '').trim() || null, p_client: rid() });
    if (r.error) return err(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
  ie_cur_save: async () => {
    const d = num($('#ie_cd').value);
    const r = await sb.rpc('currency_save', { p_org: D.org, p_code: $('#ie_cc').value.trim().toUpperCase(), p_name_bn: $('#ie_cbn').value.trim() || $('#ie_cen').value.trim(), p_name_en: $('#ie_cen').value.trim() || null,
      p_decimals: d === null ? 2 : d, p_active: $('#ie_ca').value === '1', p_client: D.client });
    if (r.error) return err(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
  ie_rate_save: async () => {
    const v = num($('#ie_rv').value); if (!(v > 0)) return err(lab(ERR.bad_rate));
    const r = await sb.rpc('fx_rate_set', { p_org: D.org, p_currency: $('#ie_rc').value, p_rate: v, p_valid_from: $('#ie_rd').value || null, p_note: $('#ie_rn').value.trim() || null, p_client: D.client });
    if (r.error) return err(eText(r.error));
    closeSheet(); toast(T('saved')); await refresh(); },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'ie_biz') { D.org = e.target.value; refresh().catch(fail); }
  if (e.target.id === 'ie_filt') { D.filt = e.target.value; refresh().catch(fail); }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="ie_body" class="stack"><p class="muted">…</p></div>', true);
  try { await refresh(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { impexp: view });
})();
