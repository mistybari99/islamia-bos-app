/* Islamia BOS · Stockout log (#/stockout): a simple shop entry for "the customer wanted it and we had none" - date, place, item, note, estimated missed quantity (optional).
   Server: supabase/phase433.sql (stockout_add / stockout_void / stockout_list / stockout_summary), phase436.sql (rb3_log_export for the CSV).
   Every number is what a person wrote. A blank estimate is "data not captured", never 0, and is never added into a total. Nothing here moves stock or money.
   Paper form code: to be given by owner (this is the digital entry for now). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, nm, H, S } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q4 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const d10 = (v) => (v ? String(v).slice(0, 10) : '');
const X = {
  title: L('স্টক শেষ (চাহিদা পূরণ হয়নি)', 'Stockout log (unmet demand)', 'Stockout log (চাহিদা পূরণ হয়নি)'),
  intro: L('ক্রেতা যা চেয়েছিলেন কিন্তু দোকানে ছিল না — এখানে লিখে রাখুন। আনুমানিক কত চাহিদা ছিল তা না জানলে খালি রাখুন।', 'Write down what a customer asked for and the shop did not have. Leave the estimate blank if you do not know it.', 'Customer যা চেয়েছিল কিন্তু ছিল না — লিখে রাখুন। আনুমানিক পরিমাণ না জানলে খালি রাখুন।'),
  paperCode: L('কাগজের ফর্মের কোড: মালিক দেবেন', 'paper form code: to be given by owner', 'paper form code: owner দেবেন'),
  date: L('ডেট', 'Date', 'Date'), place: L('জায়গা', 'Place', 'Place'), item: L('আইটেম', 'Item', 'Item'), itemph: L('কোড বা নাম লিখুন', 'Type code or name', 'Code বা নাম লিখুন'), note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (optional)'),
  est: L('আনুমানিক কত চাহিদা (ঐচ্ছিক)', 'Estimated quantity missed (optional)', 'আনুমানিক চাহিদা (optional)'), unit: L('একক', 'Unit', 'Unit'), baseUnit: L('— বেস একক —', '— base unit —', '— base unit —'),
  save: L('সেভ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), dup: L('আগেই সংরক্ষিত', 'Already saved', 'আগেই saved'), cancel: L('থাক', 'Cancel', 'Cancel'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), all: L('সব', 'All', 'All'), show: L('দেখুন', 'Show', 'Show'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  summary: L('সারাংশ: কোন মাল কতবার শেষ', 'Summary: which item ran out how often', 'Summary: কোন মাল কতবার শেষ'), entries: L('এন্ট্রি', 'Entries', 'Entries'),
  ev: L('বার', 'times', 'times'), days: L('দিন', 'days', 'days'), last: L('শেষবার', 'last', 'last'), estTotal: L('আনুমানিক চাহিদা (যেখানে লেখা)', 'Estimated missed (where written)', 'আনুমানিক চাহিদা (যেখানে লেখা)'),
  nc: L('তথ্য লেখা হয়নি', 'data not captured', 'data লেখা হয়নি'), fEst: L('আনুমানিক পরিমাণ', 'estimate', 'estimate'), notCap: L('টিতে আনুমানিক পরিমাণ লেখা নেই', 'without an estimate', 'এ estimate লেখা নেই'),
  onHand: L('এখন স্টকে', 'On hand now', 'On hand now'), notTracked: L('স্টক ট্র্যাক হয় না', 'stock not tracked', 'stock tracked নয়'), noBal: L('স্টকের হিসাব নেই', 'no stock record', 'stock record নেই'),
  voidIt: L('বাতিল', 'Void', 'Void'), voided: L('বাতিল', 'void', 'void'), why: L('কেন বাতিল (কমপক্ষে ৩ অক্ষর)', 'Why void (at least 3 characters)', 'কেন void (কমপক্ষে ৩ অক্ষর)'),
  csv: L('CSV (সারাংশ)', 'CSV (summary)', 'CSV (summary)'), csv2: L('CSV (এন্ট্রি)', 'CSV (entries)', 'CSV (entries)'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export এর permission নেই'), expDone: L('ফাইল নামানো হয়েছে', 'File downloaded', 'File নামানো হয়েছে'),
  needItem: L('আইটেম বাছুন', 'Choose an item', 'Item বাছুন'), needQty: L('পরিমাণ ঠিক নয়', 'The quantity is not valid', 'Quantity ঠিক নয়'), by: L('লিখেছেন', 'by', 'by'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: X.noperm, bad_date: L('ডেট আজকের পরে হতে পারে না', 'The date cannot be in the future', 'Date আজকের পরে হবে না'), item_not_found: L('আইটেম পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি'),
  bad_qty: X.needQty, unit_unknown: L('এককের রূপান্তর জানা নেই', 'Unit conversion unknown', 'Unit conversion জানা নেই'), bad_note: L('নোট ৩০০ অক্ষরের মধ্যে', 'Note: max 300 characters', 'Note: max 300 অক্ষর'),
  note_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'Reason লিখুন (কমপক্ষে ৩ অক্ষর)'), bad_range: L('ডেটের সীমা ঠিক নয়', 'The date range is not valid', 'Date range ঠিক নয়'),
  bad_location: L('জায়গা ঠিক নয়', 'The place is not valid', 'Place ঠিক নয়'), 'not allowed for this location': L('এই জায়গা আপনার নয়', 'You may not use this place', 'এই place আপনার নয়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const D = { items: [], locs: [], from: null, to: null, loc: '', sum: null, list: null, client: rid(), busy: false, voidId: null };
const itemText = (i) => i.code + ' · ' + nm(i);
const itemFrom = (v) => { const s = String(v || '').trim(); if (!s) return null; const c = s.split(' · ')[0].trim().toLowerCase(); return D.items.find((i) => i.code.toLowerCase() === c) || D.items.find((i) => nm(i).toLowerCase() === s.toLowerCase()) || null; };
const locN = (r) => (S.lang === 'en' ? (r.location_en || r.location) : r.location) || '';
const unit = (c) => (B.s2 && B.s2.unitLabel ? B.s2.unitLabel(c) : c || '');
const unitOpts = () => ((B.ENV && B.ENV.lists && B.ENV.lists.units) || []).filter((r) => r.active !== false);
const csvCell = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
function download(name, text) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); }
async function exportCSV(name, rows) {
  const r = await sb.rpc('rb3_log_export', { p_key: 'stockout', p_kind: 'csv', p_filters: { from: D.from, to: D.to, loc: D.loc || null }, p_rows: rows.length });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : eText(r.error)); return; }
  const p = (S.ctx && S.ctx.profile) || {};
  download(name + '.csv', rows.concat([[], [name, new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)', p.full_name || p.staff_id || '']]).map((r2) => r2.map(csvCell).join(',')).join('\r\n') + '\r\n'); toast(T('expDone'));
}

async function load() {
  const [s, l] = await Promise.all([sb.rpc('stockout_summary', { p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null }), sb.rpc('stockout_list', { p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null, p_item: null, p_with_void: true })]);
  if (s.error) throw s.error; if (l.error) throw l.error;
  D.sum = s.data; D.list = l.data;
}
function paint() {
  const el = $('#so_out'); if (!el || !D.sum) return;
  const rows = D.sum.rows || [], list = (D.list && D.list.rows) || [];
  const estCell = (r) => (r.est_captured_n > 0 ? `<b>${q4(r.est_missed_total)}</b> ${esc(unit(r.base_unit))}${r.est_not_captured_n > 0 ? ` <span class="muted">(+${r.est_not_captured_n} ${esc(T('notCap'))})</span>` : ''}` : `<span class="muted">${esc(T('nc'))}: ${esc(T('fEst'))}</span>`);
  const hand = (r) => (r.on_hand_now !== null && r.on_hand_now !== undefined ? q4(r.on_hand_now) + ' ' + esc(unit(r.base_unit)) : `<span class="muted">${esc(r.tracked ? T('noBal') : T('notTracked'))}</span>`);
  el.innerHTML = `<h3>${esc(T('summary'))}</h3>` + (rows.length ? rows.map((r) => `<div class="card"><div class="row between"><b>${esc(r.code)} · ${esc(nm(r))}</b><span class="chip warn">${r.events} ${esc(T('ev'))}</span></div>
      <div class="muted">${esc(locN(r))} · ${r.days} ${esc(T('days'))} · ${esc(T('last'))} ${esc(d10(r.last_date))}</div><div>${esc(T('estTotal'))}: ${estCell(r)}</div><div class="muted">${esc(T('onHand'))}: ${hand(r)}</div></div>`).join('') : B.ui.state('empty', T('none')))
    + `<h3>${esc(T('entries'))}</h3>` + (list.length ? list.map((x) => `<div class="card" style="${x.status === 'void' ? 'opacity:.6' : ''}"><div class="row between"><b>${esc(x.code)} · ${esc(nm(x))}</b>${x.status === 'void' ? `<span class="chip">${esc(T('voided'))}</span>` : ''}</div>
      <div class="muted">${esc(d10(x.log_date))} · ${esc(locN(x))}${x.created_staff ? ' · ' + esc(T('by')) + ' ' + esc(x.created_staff) : ''}</div>
      <div>${x.note ? esc(x.note) : ''} ${x.est_missed_qty !== null && x.est_missed_qty !== undefined ? '· ' + q4(x.est_missed_qty) + ' ' + esc(unit(x.base_unit)) : `<span class="muted">· ${esc(T('nc'))}: ${esc(T('fEst'))}</span>`}</div>
      ${x.void_note ? `<div class="muted">${esc(x.void_note)}</div>` : ''}${x.status === 'open' ? `<div class="row"><button class="mini" data-act="so_void" data-v="${esc(x.id)}">⋮ ${esc(T('voidIt'))}</button></div>` : ''}</div>`).join('') : B.ui.state('empty', T('none')))
    + `<div class="row"><button data-act="so_csv">${esc(T('csv'))}</button><button data-act="so_csv2">${esc(T('csv2'))}</button></div>`;
}
function frame() {
  const locOpts = D.locs.map((l) => `<option value="${l.id}" ${String(D.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('');
  const entLocs = D.locs;
  shell(T('title'), `<div class="stack"><p class="muted">${esc(T('intro'))}</p>
    <div class="card stack"><div class="muted">${esc(T('paperCode'))}</div>
      <div class="row"><div style="flex:1"><label for="so_date">${esc(T('date'))}</label><input id="so_date" type="date" value="${esc(today())}" max="${esc(today())}"></div>
        ${entLocs.length > 1 ? `<div style="flex:1"><label for="so_place">${esc(T('place'))}</label><select id="so_place">${entLocs.map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select></div>` : `<input type="hidden" id="so_place" value="${entLocs[0] ? entLocs[0].id : ''}">`}</div>
      <div><label for="so_item">${esc(T('item'))}</label><input id="so_item" list="so_dl" autocomplete="off" placeholder="${esc(T('itemph'))}"><datalist id="so_dl">${D.items.map((i) => `<option value="${esc(itemText(i))}"></option>`).join('')}</datalist></div>
      <div><label for="so_note">${esc(T('note'))}</label><input id="so_note" maxlength="300" autocomplete="off"></div>
      <div class="row"><div style="flex:1"><label for="so_est">${esc(T('est'))}</label><input id="so_est" inputmode="decimal" autocomplete="off"></div>
        <div style="flex:1"><label for="so_unit">${esc(T('unit'))}</label><select id="so_unit"><option value="">${esc(T('baseUnit'))}</option>${unitOpts().map((r) => `<option value="${esc(r.value_code)}">${esc(lab({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined }))}</option>`).join('')}</select></div></div>
      <button class="primary full" data-act="so_save">${esc(T('save'))}</button></div>
    <div class="row"><div style="flex:1"><label for="so_from">${esc(T('from'))}</label><input id="so_from" type="date" value="${esc(D.from)}"></div><div style="flex:1"><label for="so_to">${esc(T('to'))}</label><input id="so_to" type="date" value="${esc(D.to)}"></div></div>
    <div><label for="so_loc">${esc(T('place'))}</label><select id="so_loc"><option value="">${esc(T('all'))}</option>${locOpts}</select></div>
    <button class="full" data-act="so_show">${esc(T('show'))}</button><div id="so_out" class="stack">${B.ui.state('loading')}</div></div>`, true);
}
const refresh = async () => { try { await load(); paint(); } catch (e) { const el = $('#so_out'); if (el) el.innerHTML = B.ui.state('error', eText(e)); } };

Object.assign(H, {
  so_show: () => { D.from = ($('#so_from') || {}).value || D.from; D.to = ($('#so_to') || {}).value || D.to; D.loc = ($('#so_loc') || {}).value || ''; refresh(); },
  so_save: async (a) => {
    if (D.busy) return;
    const it = itemFrom(($('#so_item') || {}).value); if (!it) return toast(T('needItem'));
    const estRaw = norm(($('#so_est') || {}).value); const est = estRaw === '' ? null : nnum(estRaw); if (est !== null && !(est > 0)) return toast(T('needQty'));
    D.busy = true; a.disabled = true;
    try {
      const r = await sb.rpc('stockout_add', { p_date: ($('#so_date') || {}).value || today(), p_loc: Number(($('#so_place') || {}).value), p_item: it.id, p_note: (($('#so_note') || {}).value || '').trim() || null, p_est_qty: est, p_unit: est === null ? null : (($('#so_unit') || {}).value || null), p_client: D.client });
      if (r.error) return toast(eText(r.error));
      D.client = rid(); toast(r.data && r.data.dup ? T('dup') : T('saved'));
      ['so_item', 'so_note', 'so_est'].forEach((id) => { const e = $('#' + id); if (e) e.value = ''; });
      await refresh();
    } catch (e) { fail(e); } finally { D.busy = false; a.disabled = false; }
  },
  so_void: (a) => { D.voidId = a.dataset.v; openSheet(`<h2>${esc(T('voidIt'))}</h2><div class="stack"><div><label for="so_vn">${esc(T('why'))}</label><input id="so_vn" maxlength="300" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="danger full" data-act="so_vgo">${esc(T('voidIt'))}</button></div></div>`); },
  so_vgo: async () => {
    const n = (($('#so_vn') || {}).value || '').trim(); if (n.length < 3) return toast(lab(ERR.note_required));
    const r = await sb.rpc('stockout_void', { p_id: D.voidId, p_note: n }); if (r.error) return toast(eText(r.error));
    closeSheet(); toast(T('saved')); refresh();
  },
  so_csv: () => {
    const rows = [[T('title'), D.from, D.to], [T('place'), 'code', T('item'), T('ev'), T('days'), T('last'), T('estTotal'), 'captured', 'not captured', T('onHand')]];
    ((D.sum && D.sum.rows) || []).forEach((r) => rows.push([locN(r), r.code, nm(r), r.events, r.days, d10(r.last_date), r.est_captured_n > 0 ? r.est_missed_total : T('nc') + ': ' + T('fEst'), r.est_captured_n, r.est_not_captured_n,
      r.on_hand_now !== null && r.on_hand_now !== undefined ? r.on_hand_now : (r.tracked ? T('noBal') : T('notTracked'))]));
    exportCSV(`stockout-summary-${D.from}_${D.to}`, rows);
  },
  so_csv2: () => {
    const rows = [[T('title'), D.from, D.to], [T('date'), T('place'), 'code', T('item'), T('note'), T('fEst'), 'status']];
    ((D.list && D.list.rows) || []).forEach((x) => rows.push([d10(x.log_date), locN(x), x.code, nm(x), x.note || '', x.est_missed_qty !== null && x.est_missed_qty !== undefined ? x.est_missed_qty : T('nc') + ': ' + T('fEst'), x.status]));
    exportCSV(`stockout-entries-${D.from}_${D.to}`, rows);
  },
});

async function view() {
  if (B.loadStatic) await B.loadStatic();
  try { D.locs = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : []; } catch (e) { D.locs = []; }
  if (!(S.ctx.is_owner || (S.ctx.roles || []).includes('management'))) D.locs = D.locs.filter((l) => (S.ctx.locations || []).includes(l.id));
  const r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,is_active,hidden').order('code'));
  D.items = r.error ? [] : (r.data || []).filter((i) => i.is_active !== false && !i.hidden);
  D.from = D.from || new Date(Date.now() + 6 * 3600e3 - 30 * 864e5).toISOString().slice(0, 10); D.to = D.to || today();
  frame(); await refresh();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stockout: view });
})();
