/* Islamia BOS · Report notices and small helpers shared by the RPT-C1 screens (reports.js notices, #/expenseregister, #/statements).
   - B.reportnotes.load(key, filters, columns): asks the server (report_notes, phase 440) for the basis lines of one hub report: management view, what is missing,
     the returns line of the sales reports, the expense basis, the attendance sources, the cut-offs in use, the case status. It never throws: an older database answers [] and nothing is shown.
   - B.reportnotes.html(notes): the notices as small blocks (language follows the screen), with the link the server names (for example Profit check).
   - B.reportnotes.csvRows(notes): the same notices as lines for the end of a CSV file.
   - B.c1: csv cell / download / export gate (c1_export_log, phase 444) used by the new screens, so every CSV has the same rules: server check first, then the file.
   The server owns every sentence and every number; this file only draws what comes back. Nothing here is a business figure. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast } = A;
const L = B.L, lab = B.lab;

const X = {
  nocap: L('সংগ্রহ হয়নি', 'Not captured', 'Not captured'),
  basis: L('হিসাবের ভিত্তি', 'How this is worked out', 'How this is worked out'),
  notInstalled: L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part is not installed yet', 'The database part is not installed yet'),
  expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export not allowed', 'Export not allowed'),
  expDone: L('ফাইল তৈরি হয়েছে', 'File created', 'File created'),
};
const T = (k) => lab(X[k]);
const pick = (o, bn, en) => lab({ bn: o[bn] || o[en], en: o[en] || o[bn], mix: o[bn] || o[en] });

let MISSING = false;
async function load(key, flt, cols) {
  if (MISSING || !key) return [];
  let r; try { r = await sb.rpc('report_notes', { p_key: key, p_filters: flt || {}, p_cols: cols && cols.length ? cols : null }); } catch (e) { return []; }
  if (!r || r.error || !Array.isArray(r.data)) {
    const m = (r && r.error && (r.error.message || '')) || '';
    if (/could not find|does not exist|schema cache|404/i.test(m + ((r && r.error && r.error.code) || ''))) MISSING = true;   // phase 440 not pasted yet: stay quiet for this session
    return [];
  }
  return r.data;
}
function linkHTML(n) {
  const k = n && n.link; if (!k || !k.route) return '';
  return ` <a href="#/${esc(String(k.route).replace(/^#?\/?/, ''))}" data-nonotes="1">${esc(pick(k, 'label_bn', 'label_en'))}</a>`;
}
function html(notes) {
  if (!Array.isArray(notes) || !notes.length) return '';
  return notes.map((n) => {
    const tone = n.level === 'warn' ? 'warn' : 'info';
    const basis = Array.isArray(n.basis) && n.basis.length
      ? `<details class="rp-basis"><summary>${esc(T('basis'))}</summary>${n.basis.map((b) => `<p class="muted">${esc(pick(b, 'text_bn', 'text_en'))}</p>`).join('')}</details>` : '';
    return `<div class="rp-note rp-c1 mk ${tone}" data-code="${esc(n.code || '')}">${esc(pick(n, 'text_bn', 'text_en'))}${linkHTML(n)}${basis}</div>`;
  }).join('');
}
function csvRows(notes) {
  const out = [];
  (notes || []).forEach((n) => {
    out.push([pick(n, 'text_bn', 'text_en')]);
    (n.basis || []).forEach((b) => out.push(['  ' + pick(b, 'text_bn', 'text_en')]));
  });
  return out;
}

// ---------- CSV helpers (same rules as the hub and the day book: a leading = + @ is neutralised; the BOM makes Excel read Bangla) ----------
function csvCell(v) {
  if (v === null || v === undefined) return '';
  let s = String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && /[^\d.\-]/.test(s) && s.length > 1)) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
const csvLine = (arr) => arr.map(csvCell).join(',');
const csvFile = (lines) => '﻿' + lines.join('\r\n') + '\r\n';
function download(name, text, type) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: type || 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
// the server check comes FIRST (owner or export_data, and the right to read that screen); only then is the file built. An old database without phase 444 refuses too.
async function exportOk(key, kind, filters, n) {
  let r; try { r = await sb.rpc('c1_export_log', { p_key: key, p_kind: kind || 'csv', p_filters: filters || {}, p_rows: n || 0 }); } catch (e) { r = { error: e }; }
  if (r && r.error) {
    const m = r.error.message || '';
    toast(/not allowed/.test(m) ? T('expLock') : /could not find|does not exist|schema cache/i.test(m) ? T('notInstalled') : (m || 'error'));
    return false;
  }
  return true;
}
const metaLines = (title, pairs) => {
  const p = (A.S && A.S.ctx && A.S.ctx.profile) || {};
  return [[title]].concat(pairs || [], [['By', p.full_name || p.staff_id || ''], ['At', new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)']]);
};
B.c1 = { csvCell, csvLine, csvFile, download, exportOk, metaLines, T, pick, expDone: () => toast(T('expDone')) };
B.reportnotes = { load, html, csvRows, notCaptured: () => T('nocap') };
})();
