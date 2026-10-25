/* Islamia BOS · Print & books (#/printbooks): the paper book register (first / last serial of each printed book per form x place, gaps and overlaps flagged,
   the number the app continues from) and the print notes (what to change at the next print; cleared only by recording the new print). Server: supabase/phase28.sql. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('প্রিন্ট ও বই', 'Print & books', 'Print ও books'), notes: L('প্রিন্টের নোট (পরের ছাপায় যা বদলাতে হবে)', 'Print notes (what to change at the next print)', 'Print note (পরের ছাপায় যা বদলাতে হবে)'),
  books: L('বইয়ের নিবন্ধন', 'Book register', 'Book register'), loc: L('জায়গা', 'Place', 'Place'), form: L('ফর্ম', 'Form', 'Form'), first: L('প্রথম সিরিয়াল', 'First serial', 'First serial'),
  last: L('শেষ সিরিয়াল', 'Last serial', 'Last serial'), prefix: L('অক্ষর/উপসর্গ (ঐচ্ছিক)', 'Prefix (optional)', 'Prefix (optional)'), holder: L('কার কাছে', 'Held by', 'Held by'), issued: L('দেওয়ার ডেট', 'Issued on', 'Issued on'),
  add: L('বই যোগ', 'Add book', 'Book যোগ'), save: L('সেভ', 'Save', 'Save'), noBooks: L('এই ফর্ম/জায়গায় কোনো বই নেই', 'No books for this form / place', 'কোনো book নেই'),
  gap: L('ফাঁক', 'Gap', 'Gap'), overlap: L('মিলে গেছে', 'Overlap', 'Overlap'), cont: L('অ্যাপ চালু রাখবে', 'The app continues from', 'App চালু রাখবে'), none: L('কোনো নোট নেই', 'No notes', 'কোনো note নেই'),
  open: L('খোলা', 'Open', 'Open'), cleared: L('শেষ', 'Cleared', 'Cleared'), printed: L('প্রিন্টের ডেট', 'Printed on', 'Printed on'), clear: L('নতুন প্রিন্ট লিখুন', 'Record the new print', 'নতুন print লিখুন'),
  addNote: L('নোট যোগ', 'Add note', 'Note যোগ'), reason: L('কী বদলেছে', 'What changed', 'কী বদলেছে'), change: L('পরের ছাপায় কী করতে হবে', 'What to do at the next print', 'পরের print-এ কী করতে হবে'),
  allForms: L('সব ফর্ম', 'All forms', 'সব form'), void: L('ভয়েড', 'Void', 'Void'), used: L('শেষ হয়েছে', 'Used up', 'Used up'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), why: L('কারণ', 'Why', 'কারণ'),
  e_books_overlap: L('এই সিরিয়ালগুলো আগের বইয়ের সাথে মিলে গেছে', 'These serials overlap an earlier book', 'আগের book-এর সাথে মিলে গেছে'), e_bad_range: L('সিরিয়ালের সীমা ঠিক নয়', 'The serial range is not valid', 'সিরিয়ালের সীমা ঠিক নয়'),
  e_not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), e_reason_required: L('কারণ লিখুন', 'Write what changed', 'কারণ লিখুন'), e_note_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'),
};
const T = (k) => lab(X[k]);
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? lab(X[k]) : m; };
const D = { loc: null, form: null, forms: [], books: [], notes: [], check: null };
const LOCS = () => (B.liveLocs ? B.liveLocs : (a) => a)((S.ctx.is_owner || (S.ctx.roles || []).includes('management')) ? ((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []).filter((l) => (S.ctx.locations || []).includes(l.id)));
async function load() {
  if (!D.forms.length) { const f = await sb.from('forms').select('code').order('code'); D.forms = (f.data || []).map((x) => x.code); }
  if (!D.form) D.form = D.forms.includes('06-1') ? '06-1' : D.forms[0];
  const [b, n, c] = await Promise.all([sb.from('paper_books').select('*').eq('location_id', D.loc).eq('form_code', D.form).order('first_no'), sb.from('print_notes').select('*').eq('location_id', D.loc).order('created_at', { ascending: false }).limit(50), sb.rpc('paper_books_check', { p_form: D.form, p_loc: D.loc })]);
  D.books = b.data || []; D.notes = n.data || []; D.check = c.error ? null : c.data;
}
function draw() {
  const el = $('#pb_body'); if (!el) return;
  const locs = LOCS();
  const sel = `<div class="card stack"><select id="pb_loc" aria-label="${esc(T('loc'))}">${locs.map((l) => `<option value="${l.id}" ${l.id === D.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
    <select id="pb_form" aria-label="${esc(T('form'))}">${D.forms.map((f) => `<option ${f === D.form ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select></div>`;
  const ck = D.check || {};
  const issues = (ck.issues || []).map((i) => `<div class="notice ${i.type === 'overlap' ? 'bad' : 'warn'}"><b>${esc(T(i.type))}</b> ${esc(String(i.from))} – ${esc(String(i.to))}</div>`).join('');
  const books = `<div class="card stack"><b>${esc(T('books'))}</b>${issues}${ck.app_continues_from ? `<div class="muted">${esc(T('cont'))}: <b>${esc(String(ck.app_continues_from))}</b></div>` : ''}
    ${D.books.length ? D.books.map((b) => `<div class="row between"><span>${esc(b.prefix || '')}${b.first_no} – ${esc(b.prefix || '')}${b.last_no}<div class="muted" style="font-size:.8rem">${esc(b.holder || '')} ${esc(b.issued_on || '')} ${b.status !== 'active' ? '· ' + esc(b.status) : ''}</div></span>
      ${b.status === 'active' ? `<button class="mini" data-act="pb_status" data-v="${b.id}" data-s="used">⋮ ${esc(T('used'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('noBooks'))}</p>`}
    <details data-ctl="off"><summary>＋ ${esc(T('add'))}</summary><div class="stack"><input id="bk_first" inputmode="numeric" placeholder="${esc(T('first'))}"><input id="bk_last" inputmode="numeric" placeholder="${esc(T('last'))}">
      <input id="bk_prefix" placeholder="${esc(T('prefix'))}" autocomplete="off"><input id="bk_holder" placeholder="${esc(T('holder'))}" autocomplete="off"><input id="bk_date" type="date" value="${today()}"><button class="primary" data-act="pb_add">${esc(T('save'))}</button></div></details></div>`;
  const notes = `<div class="card stack"><b>${esc(T('notes'))}</b>${D.notes.length ? D.notes.map((n) => `<div class="row between"><span>${esc(n.reason)}<div class="muted" style="font-size:.8rem">${esc(n.form_code || lab(X.allForms))} · ${esc(String(n.created_at).slice(0, 10))}${n.change_to ? ' · ' + esc(n.change_to) : ''}</div></span>
      ${n.cleared_at ? `<span class="chip ok">${esc(T('cleared'))} ${esc(n.cleared_on || '')}</span>` : `<span class="stack"><input type="date" data-pn-d="${n.id}" value="${today()}" max="${today()}"><button class="mini" data-act="pb_clear" data-v="${n.id}">${esc(T('clear'))}</button></span>`}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}
    <details data-ctl="off"><summary>＋ ${esc(T('addNote'))}</summary><div class="stack"><input id="pn_reason" placeholder="${esc(T('reason'))}" autocomplete="off"><input id="pn_change" placeholder="${esc(T('change'))}" autocomplete="off"><button class="primary" data-act="pb_note">${esc(T('save'))}</button></div></details></div>`;
  el.innerHTML = sel + books + notes;
}
Object.assign(H, {
  pb_add: async () => { const r = await sb.rpc('paper_book_add', { p_form: D.form, p_loc: D.loc, p_first: Number($('#bk_first').value), p_last: Number($('#bk_last').value), p_prefix: $('#bk_prefix').value || null, p_issued: $('#bk_date').value || null, p_holder: $('#bk_holder').value || null });
    if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
  pb_status: async (a) => { const r = await sb.rpc('paper_book_set_status', { p_id: Number(a.dataset.v), p_status: a.dataset.s }); if (r.error) return toast(eText(r.error)); await load(); draw(); },
  pb_note: async () => { const r = await sb.rpc('print_note_add', { p_loc: D.loc, p_form: null, p_reason: $('#pn_reason').value, p_change: $('#pn_change').value || null }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
  pb_clear: async (a) => { const id = a.dataset.v; const r = await sb.rpc('print_note_clear', { p_id: Number(id), p_printed_on: ($(`[data-pn-d="${id}"]`) || {}).value }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await load(); draw(); },
});
document.addEventListener('change', async (e) => {
  if (e.target.id === 'pb_loc') { D.loc = Number(e.target.value); await load(); draw(); }
  if (e.target.id === 'pb_form') { D.form = e.target.value; await load(); draw(); }
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  const locs = LOCS(); if (!D.loc || !locs.find((l) => l.id === D.loc)) D.loc = (locs[0] || {}).id;
  shell(T('title'), '<div id="pb_body"><p class="muted">…</p></div>', true);
  try { await load(); draw(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { printbooks: view });
})();
