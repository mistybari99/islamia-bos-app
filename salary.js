/* Islamia BOS · Salary report (#/salary): monthly summary per person from forms 02-2 (salary sheet), 02-3 (advances) and 02-1 (attendance).
   For the owner and holders of the grant salary_view only (server: salary_report in phase13.sql). Only what the forms contain is shown:
   gross = due + overtime + other, net = gross - advance deduction - other deduction (the exact formulas of form 02-2). No rate or rule is invented.
   Export (CSV / print) needs the grant export_data; the server check runs first and leaves an audit row. Loaded after daybook.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const num = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const LOCK = '<svg viewBox="0 0 32 32" aria-hidden="true" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';
const DOTS = '<svg viewBox="0 0 32 32" aria-hidden="true" width="20" height="20" fill="currentColor"><circle cx="16" cy="7" r="2.6"/><circle cx="16" cy="16" r="2.6"/><circle cx="16" cy="25" r="2.6"/></svg>';
const noperm = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* rules not loaded */ } return m === 'hide' ? 'hide' : 'lock'; };
const owner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('বেতন রিপোর্ট', 'Salary report', 'Salary report'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), close: L('বন্ধ', 'Close', 'Close'),
  location: L('জায়গা', 'Location', 'Location'), allLoc: L('সব জায়গা', 'All locations', 'সব Location'), month: L('মাস', 'Month', 'Month'),
  prev: L('আগের মাস', 'Previous month', 'আগের মাস'), next: L('পরের মাস', 'Next month', 'পরের মাস'),
  gross: L('মোট পাওনা', 'Gross', 'Gross'), ded: L('কর্তন', 'Deductions', 'Deductions'), netL: L('নিট', 'Net', 'Net'), people: L('জন', 'people', 'people'),
  salary: L('মাসিক বেতন', 'Monthly salary', 'Monthly salary'), due: L('পাওনা বেতন', 'Salary due', 'Salary due'), ot: L('ওভারটাইম', 'Overtime', 'Overtime'), other: L('অন্যান্য', 'Other', 'Other'),
  advDed: L('অ্যাডভান্স কর্তন', 'Advance deduction', 'Advance deduction'), otherDed: L('অন্য কর্তন', 'Other deduction', 'Other deduction'), remark: L('কারণ / মন্তব্য', 'Reason / remark', 'Reason / remark'),
  workDays: L('কাজের দিন', 'Working days', 'Working days'), absent: L('অনুপস্থিত', 'Absent days', 'Absent days'), leave: L('ছুটি', 'Leave days', 'Leave days'),
  paid: L('প্রাপ্তি স্বীকারে নিট', 'Net on receipt list', 'Receipt-এ net'), signed: L('স্বাক্ষর', 'Signed', 'Signed'), yes: L('হ্যাঁ', 'Yes', 'Yes'), no: L('না', 'No', 'No'),
  sheet: L('শিট নং', 'Sheet no.', 'Sheet no.'), status: L('অবস্থা', 'Status', 'Status'),
  need: L('তথ্য দরকার', 'Data needed', 'Data দরকার'), noSheet: L('এই মাসের জন্য কোনো বেতন শিট (02-2) জমা নেই — তাই কোনো সংখ্যা নেই', 'No salary sheet (02-2) has been submitted for this month, so there are no figures', 'এই মাসের কোনো Salary sheet (02-2) জমা নেই — তাই কোনো সংখ্যা নেই'),
  secSheet: L('বেতন শিট (02-2)', 'Salary sheet (02-2)', 'Salary sheet (02-2)'), secAdv: L('অ্যাডভান্স (02-3)', 'Advances (02-3)', 'Advance (02-3)'), secAtt: L('হাজিরা (02-1)', 'Attendance (02-1)', 'Hajira (02-1)'),
  given: L('এ মাসে দেওয়া', 'Given this month', 'এ মাসে দেওয়া'), deducted: L('এ মাসে কর্তন', 'Deducted this month', 'এ মাসে কর্তন'), outstanding: L('বাকি (ফর্মের যোগফল)', 'Outstanding (form total)', 'বাকি (form-এর total)'),
  present: L('উপস্থিত', 'Present', 'Present'), late: L('দেরি', 'Late', 'Late'), otH: L('ওভারটাইম ঘণ্টা', 'Overtime hours', 'OT hours'), lu: L('বিনা বেতনের ছুটি', 'Unpaid leave', 'Unpaid leave'), lp: L('সবেতন ছুটি', 'Paid leave', 'Paid leave'),
  note: L('শুধু জমা/অনুমোদিত ফর্মের তথ্য; খসড়া ধরা হয় না। হিসাব ফর্ম 02-2-এর সূত্র অনুযায়ী — নিজে থেকে কোনো হার বা নিয়ম বসানো হয় না।', 'Only submitted / approved forms; drafts are not counted. Figures follow the formulas of form 02-2 — no rate or rule is added.', 'শুধু submitted/approved form; draft ধরা হয় না। Form 02-2-এর সূত্র অনুযায়ী — কোনো rate/rule নিজে বসানো হয় না।'),
  menu: L('আরও', 'More', 'More'), csv: L('CSV এক্সপোর্ট', 'Export CSV', 'CSV Export'), print: L('প্রিন্ট / PDF', 'Print / PDF', 'Print / PDF'), refresh: L('নতুন করে আনুন', 'Refresh', 'Refresh'),
  openForm: L('ফর্ম খুলুন', 'Open the form', 'Form খুলুন'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export-এর permission নেই'), expDone: L('ফাইল তৈরি হয়েছে', 'File created', 'File তৈরি হয়েছে'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), lockedPage: L('বেতন রিপোর্ট দেখার অনুমতি নেই — মালিক "বেতন দেখা" অনুমতি দিতে পারেন', 'You may not see salaries — the owner can give you the "See salaries" permission', 'Salary report দেখার permission নেই — Owner "Salary দেখা" permission দিতে পারেন'),
  sqlMissing: L('বেতন রিপোর্টের ডেটাবেস অংশ এখনও চালু হয়নি (phase13)', 'The salary report database part is not installed yet (phase13)', 'Salary report-এর database অংশ এখনও চালু হয়নি (phase13)'),
  dupSheets: L('একই লোকেশনে এই মাসের একাধিক বেতন শিট আছে — সংখ্যা আলাদা লাইনে আছে, নিজে থেকে মেলানো হয়নি', 'More than one salary sheet exists for the same location and month — every line is listed; nothing was merged or de-duplicated', 'একই location-এ এই মাসের একাধিক salary sheet — প্রতিটি line আলাদা; নিজে থেকে মেলানো হয়নি'),
  ambiguous: L('একই নাম একাধিকবার', 'Same name more than once', 'একই নাম একাধিকবার'), ambHint: L('একই নামের একাধিক লাইন — প্রাপ্তি/স্বাক্ষর আন্দাজে মেলানো হয়নি', 'Same name on several lines — receipt / signature not guessed', 'একই নামের একাধিক line — receipt/signature আন্দাজে মেলানো হয়নি'),
  by: L('কে', 'By', 'By'), at: L('সময়', 'Time', 'Time'), name: L('নাম', 'Name', 'Name'), none: L('কিছু নেই', 'Nothing', 'Nothing'),
};
const T = (k) => lab(X[k]);
const missingFn = (e) => !!e && (e.code === 'PGRST202' || /could not find the function|schema cache|does not exist/i.test(e.message || ''));
const LOCS = () => { const all = (B.ENV && B.ENV.locs) || []; return owner() || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const allLocs = () => owner() || (S.ctx.roles || []).includes('management') || LOCS().length > 1;
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? nm(l) : (id === null || id === undefined ? '' : '#' + id); };
const optHTML = (pairs, sel) => pairs.map(([v, l]) => `<option value="${esc(String(v))}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const thisMonth = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 7);
const shiftMonth = (ym, n) => { const [y, m] = ym.split('-').map(Number); const d = new Date(Date.UTC(y, m - 1 + n, 1)); return d.toISOString().slice(0, 7); };
const monthLabel = (ym) => { try { return new Date(ym + '-15T12:00:00Z').toLocaleDateString(S.lang === 'bn' ? 'bn-BD' : 'en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' }); } catch (e) { return ym; } };
const isMonth = (s) => /^\d{4}-(0[1-9]|1[0-2])$/.test(s);

let EXPOK = null;
async function canExport() {
  if (owner()) return true; if (EXPOK !== null) return EXPOK;
  try { const r = await sb.rpc('has_grant', { p_code: 'export_data' }); EXPOK = !r.error && r.data === true; } catch (e) { EXPOK = false; }
  return EXPOK;
}

const D = { loc: undefined, month: null, data: null, err: null, exp: false, busy: 0, shown: [] };
async function load() {
  const tok = ++D.busy; D.err = null;
  const r = await sb.rpc('salary_report', { p_loc: D.loc === null ? null : D.loc, p_month: D.month + '-01' });
  if (tok !== D.busy) return;
  if (r.error) { D.data = null; D.err = r.error; } else D.data = r.data;
}
async function view() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  if (D.loc === undefined) D.loc = allLocs() ? null : (LOCS()[0] || {}).id;
  if (!D.month) D.month = thisMonth();
  D.exp = await canExport();
  await load(); draw();
}
const lockCard = (msg) => `<div class="lockcard">${LOCK}<span>${esc(msg)}</span></div>`;
function statCell(label, val, tone) { return `<div class="stat mk ${tone || ''}"><div class="k">${esc(label)}</div><div class="v">${esc(money(val))}</div></div>`; }
function draw() {
  const locs = LOCS(), m = (D.err && D.err.message) || '', locked = /not allowed/.test(m);
  const filters = `<div class="stack">
    ${(locs.length > 1 || allLocs()) ? `<select id="sa_loc" aria-label="${esc(T('location'))}">${allLocs() ? `<option value="">${esc(T('allLoc'))}</option>` : ''}${optHTML(locs.map((l) => [l.id, nm(l)]), D.loc === null ? '' : D.loc)}</select>` : ''}
    <div class="row" style="align-items:center;gap:6px;flex-wrap:nowrap"><button data-act="sa_m" data-v="-1" aria-label="${esc(T('prev'))}" style="min-width:44px;padding-inline:0">‹</button>
      <input type="month" id="sa_month" value="${esc(D.month)}" aria-label="${esc(T('month'))}" style="flex:1;min-width:0"><button data-act="sa_m" data-v="1" aria-label="${esc(T('next'))}" style="min-width:44px;padding-inline:0">›</button>
      <button id="sa_menu" data-act="sa_menu" aria-label="${esc(T('menu'))}" style="min-width:44px;padding-inline:0">${DOTS}</button></div></div>`;
  let body;
  if (D.err) body = missingFn(D.err) ? `<div class="notice warn mk warn">${esc(T('sqlMissing'))}</div>` : locked ? lockCard(T('lockedPage')) : `<div class="notice warn mk warn">${esc(m || 'error')}</div>`;
  else if (!D.data) body = `<p class="muted">${esc(T('loading'))}</p>`;
  else body = content();
  shell(T('title'), `${locked ? '' : filters}<div id="sa_body">${body}</div>`, true);
}
function content() {
  const d = D.data, t = d.totals || {};
  if (d.data_needed) return `<div class="notice warn mk warn" id="sa_need"><b>${esc(T('need'))}</b> — ${esc(T('noSheet'))}</div>${extra(d)}<p class="muted" style="font-size:.85rem">${esc(T('note'))}</p>`;
  D.shown = d.rows || [];
  const dup = (d.duplicate_sheets || []).length ? `<div class="notice warn mk warn" id="sa_dup">${esc(T('dupSheets'))} (${d.duplicate_sheets.map((x) => esc(locName(x.loc)) + ': ' + Number(x.n)).join(', ')})</div>` : '';
  return `${dup}<div class="stats" id="sa_sum">${statCell(T('gross'), t.gross, '')}${statCell(T('ded'), t.deductions, 'warn')}${statCell(T('netL'), t.net, 'ok')}</div>
    <div class="hsec">${esc(T('secSheet'))}<small>${Number(t.people || 0)} ${esc(T('people'))}</small></div>
    <div class="card" style="padding:4px 12px" id="sa_rows">${D.shown.map((r, i) => `<button class="rp-row mk ${Number(r.net) < 0 ? 'bad' : 'info'} sa-row" data-act="sa_row" data-i="${i}" style="display:flex;width:100%;align-items:center;gap:8px;text-align:start;min-height:56px">
      <span class="nm" style="flex:1">${esc(r.name)}${r.ambiguous ? ` <span class="chip warn amb">${esc(T('ambiguous'))}</span>` : ''}<small style="display:block">${esc(T('gross'))} ${esc(money(r.gross))} · ${esc(T('ded'))} ${esc(money(r.deductions))}${D.loc === null ? ' · ' + esc(locName(r.loc)) : ''}</small></span>
      <b>${esc(money(r.net))}</b><span class="cv">›</span></button>`).join('')}</div>
    ${extra(d)}<p class="muted" style="font-size:.85rem">${esc(T('note'))}</p>`;
}
function extra(d) {
  let h = '';
  if ((d.advances || []).length) h += `<div class="hsec">${esc(T('secAdv'))}</div><div class="card" style="padding:4px 12px" id="sa_adv">${d.advances.map((a) => `<div class="rp-row mk info" style="min-height:56px"><span class="nm">${esc(a.name || '')}${a.post ? ' · ' + esc(a.post) : ''}
      <small style="display:block">${esc(T('given'))} ${esc(money(a.given))} · ${esc(T('deducted'))} ${esc(money(a.deducted))} · ${esc(T('outstanding'))} ${esc(money(a.outstanding))}</small></span></div>`).join('')}</div>`;
  if ((d.attendance || []).length) h += `<div class="hsec">${esc(T('secAtt'))}</div><div class="card" style="padding:4px 12px" id="sa_att">${d.attendance.map((a) => `<div class="rp-row mk info" style="min-height:56px"><span class="nm">${esc(a.name || '')}
      <small style="display:block">${esc(T('present'))} ${esc(num(a.present))} · ${esc(T('absent'))} ${esc(num(a.absent))} · ${esc(T('late'))} ${esc(num(a.late))} · ${esc(T('otH'))} ${esc(num(a.ot_hours))}</small></span></div>`).join('')}</div>`;
  return h;
}
function rowSheet(i) {
  const r = D.shown[i]; if (!r) return;
  const kv = (k, v) => `<div class="row" style="justify-content:space-between;gap:8px;padding:6px 0;border-bottom:1px solid var(--hair)"><span>${esc(T(k))}</span><b>${v}</b></div>`;
  openSheet(`<div class="row" style="align-items:center;justify-content:space-between"><h2 style="margin:0">${esc(r.name)}</h2><button data-act="sa_rmenu" data-i="${i}" aria-label="${esc(T('menu'))}" style="min-width:48px">${DOTS}</button></div>
    <div class="stack" style="margin-top:8px">${kv('salary', esc(money(r.salary)))}${kv('workDays', esc(num(r.work_days)))}${kv('absent', esc(num(r.absent)))}${kv('leave', esc(num(r.leave)))}
    ${kv('due', esc(money(r.due)))}${kv('ot', esc(money(r.overtime)))}${kv('other', esc(money(r.other)))}${kv('gross', esc(money(r.gross)))}
    ${kv('advDed', esc(money(r.adv_ded)))}${kv('otherDed', esc(money(r.other_ded)))}${kv('netL', esc(money(r.net)))}
    ${kv('paid', esc(money(r.paid)))}${kv('signed', r.signed === null || r.signed === undefined ? esc('—') : esc(r.signed ? T('yes') : T('no')))}
    ${r.ambiguous ? `<p class="muted" style="font-size:.85rem">${esc(T('ambHint'))}</p>` : ''}${r.remark ? kv('remark', esc(r.remark)) : ''}${kv('sheet', '#' + esc(String(r.serial)) + ' · ' + esc(locName(r.loc)))}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ---------- export ----------
const csvCell = (v) => {
  if (v === null || v === undefined) return '';
  let s = String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && /[^\d.\-]/.test(s))) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
function buildCSV() {
  const d = D.data, line = (a) => a.map(csvCell).join(',');
  const out = [line(['sheet', 'location', 'name', 'monthly_salary', 'working_days', 'absent_days', 'leave_days', 'salary_due', 'overtime', 'other', 'gross', 'advance_deduction', 'other_deduction', 'net', 'receipt_net', 'signed', 'remark', 'same_name_more_than_once'])];
  (d.rows || []).forEach((r) => out.push(line([r.serial, locName(r.loc), r.name, r.salary, r.work_days, r.absent, r.leave, r.due, r.overtime, r.other, r.gross, r.adv_ded, r.other_ded, r.net, r.paid, r.signed === null || r.signed === undefined ? '' : (r.signed ? 'yes' : 'no'), r.remark, r.ambiguous ? 'yes' : ''])));
  const t = d.totals || {}; out.push(line(['TOTAL', '', '', '', '', '', '', t.due, t.overtime, t.other, t.gross, t.adv_ded, t.other_ded, t.net]));
  if ((d.advances || []).length) { out.push(''); out.push(line(['advances (02-3)', 'location', 'name', 'post', 'given_this_month', 'deducted_this_month', 'outstanding']));
    d.advances.forEach((a) => out.push(line([a.serial, locName(a.loc), a.name, a.post, a.given, a.deducted, a.outstanding]))); }
  if ((d.attendance || []).length) { out.push(''); out.push(line(['attendance (02-1)', 'location', 'name', 'present', 'absent', 'late', 'unpaid_leave', 'paid_leave', 'overtime_hours']));
    d.attendance.forEach((a) => out.push(line([a.serial, locName(a.loc), a.name, a.present, a.absent, a.late, a.leave_unpaid, a.leave_paid, a.ot_hours]))); }
  const p = (S.ctx && S.ctx.profile) || {};
  out.push(''); [[T('title'), D.month], [T('location'), D.loc === null ? T('allLoc') : locName(D.loc)], [T('by'), p.full_name || p.staff_id || ''], [T('at'), new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)']].forEach((m) => out.push(line(m)));
  return '﻿' + out.join('\r\n') + '\r\n';
}
function download(name, text, type) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
// server check first (owner or export_data + salary_view), then the file
async function audit(kind) {
  const r = await sb.rpc('log_page_export', { p_key: 'salary', p_kind: kind, p_filters: { loc: D.loc, month: D.month }, p_rows: (D.data.rows || []).length });
  if (r && r.error) { toast(/not allowed/.test(r.error.message || '') ? T('expLock') : (r.error.message || 'error')); return false; }
  return true;
}
async function doCSV() { if (!D.data || D.data.data_needed) return; if (!(await audit('csv'))) return; download(`salary-${D.month}.csv`, buildCSV(), 'text/csv;charset=utf-8'); toast(T('expDone')); }
async function doPrint() {
  if (!D.data || D.data.data_needed) return; if (!(await audit('print'))) return;
  const old = $('#rp_print'); if (old) old.remove();
  const t = D.data.totals || {}, d = document.createElement('div'); d.id = 'rp_print';
  d.innerHTML = `<h1>${esc(T('title'))} · ${esc(monthLabel(D.month))}</h1><p class="pm">${esc(D.loc === null ? T('allLoc') : locName(D.loc))} · ${esc(T('gross'))} ${esc(money(t.gross))} · ${esc(T('ded'))} ${esc(money(t.deductions))} · ${esc(T('netL'))} ${esc(money(t.net))}</p>
    <table><thead><tr><th>${esc(T('name'))}</th><th class="n">${esc(T('gross'))}</th><th class="n">${esc(T('advDed'))}</th><th class="n">${esc(T('otherDed'))}</th><th class="n">${esc(T('netL'))}</th></tr></thead>
    <tbody>${(D.data.rows || []).map((r) => `<tr><td>${esc(r.name)}</td><td class="n">${esc(money(r.gross))}</td><td class="n">${esc(money(r.adv_ded))}</td><td class="n">${esc(money(r.other_ded))}</td><td class="n">${esc(money(r.net))}</td></tr>`).join('')}</tbody>
    <tfoot><tr><th>${esc(T('gross'))}</th><th class="n">${esc(money(t.gross))}</th><th class="n">${esc(money(t.adv_ded))}</th><th class="n">${esc(money(t.other_ded))}</th><th class="n">${esc(money(t.net))}</th></tr></tfoot></table>`;
  document.body.appendChild(d);
  const clean = () => { const e = $('#rp_print'); if (e) e.remove(); window.removeEventListener('afterprint', clean); };
  window.addEventListener('afterprint', clean);
  setTimeout(() => { try { window.print(); } catch (e) { clean(); } }, 80);
}
function menuBtn(act, label, enabled) {
  if (enabled) return `<button class="full" data-act="${act}">${esc(label)}</button>`;
  return noperm() === 'lock' ? `<button class="full" disabled aria-label="${esc(label + ' · ' + T('expLock'))}">${LOCK} ${esc(label)}</button>` : '';
}
function pageMenu() {
  const ok = D.exp && D.data && !D.data.data_needed;
  openSheet(`<h2 style="margin-top:0">${esc(T('title'))}</h2><div class="stack">${menuBtn('sa_csv', T('csv'), ok)}${menuBtn('sa_print', T('print'), ok)}
    <button class="full" data-act="sa_refresh">${esc(T('refresh'))}</button><button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}
async function reload() { await load(); draw(); }
Object.assign(H, {
  sa_m: async (a) => { D.month = shiftMonth(D.month, Number(a.dataset.v)); await reload(); },
  sa_row: (a) => rowSheet(Number(a.dataset.i)),
  sa_rmenu: (a) => { const r = D.shown[Number(a.dataset.i)]; if (!r) return; openSheet(`<h2 style="margin-top:0">${esc(r.name)}</h2><div class="stack">
      <button class="full" data-act="sa_openform" data-v="${esc(r.entry_id)}">${esc(T('openForm'))} (02-2 #${esc(String(r.serial))})</button><button class="full" data-act="sa_back" data-i="${a.dataset.i}">${esc(T('close'))}</button></div>`); },
  sa_back: (a) => rowSheet(Number(a.dataset.i)),
  sa_openform: (a) => { closeSheet(); location.hash = '#/entry/' + a.dataset.v; },
  sa_menu: pageMenu, sa_csv: () => { closeSheet(); return doCSV(); }, sa_print: () => { closeSheet(); return doPrint(); }, sa_refresh: async () => { closeSheet(); await reload(); },
});
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !id.startsWith('sa_') || location.hash.replace(/^#\/?/, '').split('/')[0] !== 'salary') return;
  if (id === 'sa_loc') { D.loc = e.target.value === '' ? null : Number(e.target.value); reload(); }
  else if (id === 'sa_month' && isMonth(e.target.value)) { D.month = e.target.value; reload(); }
});

B.reportLinks = B.reportLinks || [];
B.reportLinks.push({ key: 'salary', route: 'salary', label: () => T('title'), allowed: null,
  check: async () => { const l = B.reportLinks.find((x) => x.key === 'salary'); if (owner()) { l.allowed = true; return; }
    let ok = false; for (const x of LOCS()) { try { const r = await sb.rpc('has_grant', { p_code: 'salary_view', p_loc: x.id }); if (r && !r.error && r.data === true) { ok = true; break; } } catch (e) { /* no */ } }
    l.allowed = ok; } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { salary: view });
})();
