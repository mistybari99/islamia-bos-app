/* Islamia BOS · Path switches + shadow copies (#/paths, owner) and the day-book quick expense (#/quickexp).
   Server side: supabase/phase48-51.sql. Browser reads path_switches() / shadow_report() / daybook_vs_journal() / dup_suspects() and writes only through
   path_switch_set, quick_expense_add / void / close_day. Nothing is deleted. One record is counted; its other path is a locked shadow copy. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('পথ সুইচ ও শ্যাডো কপি', 'Path switches & shadow copies', 'Path switch ও shadow copy'),
  intro: L('একই কাজ দুই পথে (দ্রুত ট্যাব / কাগজের ফর্ম) করা গেলে একটাই মূল রেকর্ড গোনা হয়; অন্যটি লক করা শ্যাডো কপি।', 'When one job can be entered two ways (quick tab / paper form), only ONE record is counted; the other is a locked shadow copy.', 'একই কাজ দুই পথে করা গেলে একটাই record গোনা হয়; অন্যটা locked shadow copy।'),
  open: L('খোলা', 'Open', 'Open'), locked: L('লক', 'Locked', 'Locked'), primary: L('মূল রেকর্ড', 'Primary record', 'Primary record'),
  pa: L('পথ ক (অ্যাপ/দ্রুত)', 'Path A (app / quick)', 'Path A'), pb: L('পথ খ (ফর্ম)', 'Path B (form)', 'Path B'),
  pfirst: L('যেটা আগে', 'Whichever is first', 'Whichever first'), save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  pending: L('শ্যাডো কপি বাকি', 'Shadow copies owed', 'Shadow copy বাকি'), rep: L('রিপোর্ট (শুধু দেখা)', 'Reports (read only)', 'Reports (read only)'),
  dvj: L('ডে-বুক বনাম জার্নাল', 'Day book vs journal', 'Day book vs journal'), dup: L('ডুপ্লিকেট সন্দেহ', 'Duplicate suspects', 'Duplicate suspects'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), run: L('দেখুন', 'Show', 'Show'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
  qtitle: L('দ্রুত খরচ এন্ট্রি', 'Quick expense', 'Quick expense'), head: L('খাত', 'Head', 'Head'), to2: L('কাকে / কী বাবদ', 'Paid to / for', 'Paid to / for'),
  amt: L('টাকা', 'Amount', 'Amount'), mode: L('মাধ্যম', 'Mode', 'Mode'), rcpt: L('রসিদ আছে', 'Receipt', 'Receipt'), add: L('যোগ করুন', 'Add', 'Add'),
  close: L('দিন শেষ — ১০-২ ফর্ম বানান', 'Day end - make the 10-2 form', 'Day end - 10-2 form বানান'), void: L('বাতিল', 'Void', 'Void'),
  total: L('আজকের মোট', "Today's total", "Today's total"), owed: L('ফর্মে বাকি', 'Not yet in a form', 'ফর্মে বাকি'), place: L('লোকেশন', 'Place', 'Place'),
  made: L('ফর্ম তৈরি', 'Form made', 'Form তৈরি'), why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), alo: L('সব জায়গা', 'All places', 'All places'),
};
const T = (k) => lab(X[k]);
const D = { sw: [], locs: [], q: { loc: null, day: null } };
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);

/* ---------- owner: switches ---------- */
function rowHTML(d) {
  const c = d.cfg || {}, nmDom = lab({ bn: d.a_bn + ' ⇄ ' + d.b_bn, mix: d.a_bn + ' ⇄ ' + d.b_bn, en: d.a_en + ' ⇄ ' + d.b_en });
  const tog = (p, on) => `<button type="button" class="tog ${on ? 'on' : ''}" role="switch" aria-checked="${on}" data-act="pt_tog" data-d="${esc(d.domain)}" data-p="${p}">${esc(T(p === 'a' ? 'pa' : 'pb'))}: ${esc(T(on ? 'open' : 'locked'))}</button>`;
  const opts = ['a', 'b'].concat(d.allow_first ? ['first'] : []);
  return `<div class="card stack" data-dom="${esc(d.domain)}"><b>${esc(nmDom)}</b><div class="muted" style="font-size:.85rem">${esc(lab({ bn: d.note_bn || '', mix: d.note_bn || '', en: d.note_en || '' }))}</div>
    <div class="row wrap">${tog('a', c.a_open !== false)}${tog('b', c.b_open !== false)}
      <label class="row">${esc(T('primary'))} <select data-pt-primary="${esc(d.domain)}">${opts.map((o) => `<option value="${o}" ${c.primary === o ? 'selected' : ''}>${esc(o === 'a' ? T('pa') : o === 'b' ? T('pb') : T('pfirst'))}</option>`).join('')}</select></label></div></div>`;
}
async function loadSw() {
  const [r, d, l] = await Promise.all([sb.rpc('path_switches'), sb.from('path_domains').select('domain,allow_first'), sb.from('locations').select('id,name_bn,name_en').order('id')]);
  if (r.error) throw r.error;
  const af = Object.fromEntries((d.data || []).map((x) => [x.domain, x.allow_first]));
  D.sw = (r.data || []).map((x) => ({ ...x, allow_first: !!af[x.domain] })); D.locs = l.data || [];
}
function drawSw() {
  const el = $('#pt_body'); if (!el) return;
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>${D.sw.map(rowHTML).join('')}
    <div class="card stack"><b>${esc(T('rep'))}</b><div class="row wrap"><label>${esc(T('from'))} <input type="date" id="pt_from" value="${today().slice(0, 8)}01"></label><label>${esc(T('to'))} <input type="date" id="pt_to" value="${today()}"></label></div>
      <div class="row wrap"><button type="button" class="btn" data-act="pt_dvj">${esc(T('dvj'))}</button><button type="button" class="btn" data-act="pt_dup">${esc(T('dup'))}</button><button type="button" class="btn" data-act="pt_pend">${esc(T('pending'))}</button></div>
      <pre id="pt_out" class="muted" style="white-space:pre-wrap;font-size:.8rem"></pre></div>`;
}
async function setSw(dom, patch) {
  const d = D.sw.find((x) => x.domain === dom), c = Object.assign({}, d.cfg, patch);
  if (patch.primary && window.BOS.freshness && !(await window.BOS.freshness.confirmSwitch('path:' + dom, patch.primary))) return;   // bos98 (W1-G)
  const r = await sb.rpc('path_switch_set', { p_domain: dom, p_loc: 0, p_a_open: c.a_open !== false, p_b_open: c.b_open !== false, p_primary: c.primary, p_note: null });
  if (r.error) return fail(r.error);
  toast(T('saved')); await loadSw(); drawSw();
}
async function show(name, args) {
  const r = await sb.rpc(name, args); if (r.error) return fail(r.error);
  const o = $('#pt_out'); const rows = JSON.stringify(r.data, null, 1);
  o.textContent = rows.length > 6000 ? rows.slice(0, 6000) + ' …' : rows;
}
Object.assign(H, {
  pt_tog: (a) => { const d = D.sw.find((x) => x.domain === a.dataset.d), k = a.dataset.p + '_open'; return setSw(a.dataset.d, { [k]: !(d.cfg[k] !== false) }); },
  pt_dvj: () => show('daybook_vs_journal', { p_from: $('#pt_from').value, p_to: $('#pt_to').value, p_loc: null }),
  pt_dup: () => show('dup_suspects', { p_from: $('#pt_from').value, p_to: $('#pt_to').value }),
  pt_pend: () => show('shadow_report', { p_domain: null, p_loc: null }),
});
document.addEventListener('change', (e) => { if (e.target.dataset && e.target.dataset.ptPrimary) setSw(e.target.dataset.ptPrimary, { primary: e.target.value }); });
async function viewPaths() {
  shell(T('title'), '<div id="pt_body"><p class="muted">…</p></div>', true);
  try { await loadSw(); drawSw(); } catch (e) { fail(e); }
}

/* ---------- quick expense (day book tab) ---------- */
const HEADS = [['staff_meal', 'স্টাফের খাবার', 'Staff meals'], ['transport', 'যাতায়াত', 'Transport'], ['hospitality', 'আপ্যায়ন', 'Hospitality'], ['repair', 'মেরামত/ইউটিলিটি', 'Repairs/utilities'],
  ['labour', 'অস্থায়ী মজুরি', 'Temporary labour'], ['sourcing', 'বাইরের সোর্সিং', 'Outside sourcing'], ['other', 'অন্যান্য', 'Other']];
async function loadQx() {
  const l = await sb.from('locations').select('id,name_bn,name_en').order('id'); D.locs = l.data || [];
  if (!D.q.loc && D.locs[0]) D.q.loc = D.locs[0].id; D.q.day = D.q.day || today();
  const r = await sb.rpc('quick_expense_day', { p_loc: D.q.loc, p_date: D.q.day }); if (r.error) throw r.error; D.qd = r.data;
}
function drawQx() {
  const el = $('#qx_body'); if (!el) return; const d = D.qd;
  el.innerHTML = `<div class="card stack"><div class="row wrap"><label>${esc(T('place'))} <select id="qx_loc">${D.locs.map((l) => `<option value="${l.id}" ${l.id === D.q.loc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></label>
      <input type="date" id="qx_day" value="${esc(D.q.day)}"></div>
    <div class="row wrap"><select id="qx_head">${HEADS.map((h) => `<option value="${h[0]}">${esc(lab({ bn: h[1], mix: h[1], en: h[2] }))}</option>`).join('')}</select>
      <input id="qx_to" placeholder="${esc(T('to2'))}" maxlength="120"><input id="qx_amt" type="number" inputmode="decimal" min="0" step="0.01" placeholder="${esc(T('amt'))}" style="max-width:8rem">
      <select id="qx_mode"><option value="cash">cash</option><option value="bank">bank</option><option value="mobile">mobile</option></select>
      ${B.moneySrc ? B.moneySrc.slot('qx', 'quick_expense', { locSel: '#qx_loc' }) : ''}
      <label class="row"><input type="checkbox" id="qx_rc"> ${esc(T('rcpt'))}</label><button type="button" class="btn primary" data-act="qx_add">${esc(T('add'))}</button></div></div>
    <div class="card stack"><div class="row between"><b>${esc(T('total'))}: ৳ ${esc(String(d.total))}</b><span class="chip ${d.owed ? 'warn' : ''}">${esc(T('owed'))}: ${d.owed}</span></div>
      ${(d.rows || []).map((r) => `<div class="row between"${r.status === 'void' ? ' style="opacity:.5;text-decoration:line-through"' : ''}><span>${esc(r.head)} · ${esc(r.paid_to || '')} · ${esc(r.mode)}${r.receipt ? ' 🧾' : ''}</span><b>৳ ${esc(String(r.amount))}</b>
        ${r.status === 'done' && !r.form ? `<button type="button" class="mini" data-act="qx_void" data-id="${esc(r.id)}">${esc(T('void'))}</button>` : r.form ? '<span class="chip">10-2</span>' : ''}</div>`).join('')}
      ${d.owed ? `<button type="button" class="btn primary" data-act="qx_close">${esc(T('close'))}</button>` : ''}</div>`;
}
const refreshQx = async () => { await loadQx(); drawQx(); };
Object.assign(H, {
  qx_add: async () => {
    const amt = Number($('#qx_amt').value); if (!(amt > 0)) return toast(T('amt'));
    const r = await sb.rpc('quick_expense_add', { p_loc: D.q.loc, p_date: D.q.day, p_head: $('#qx_head').value, p_to: $('#qx_to').value, p_amount: amt, p_mode: $('#qx_mode').value, p_receipt: $('#qx_rc').checked, p_note: B.moneySrc ? B.moneySrc.tag('qx', null) : null, p_client: crypto.randomUUID() });
    if (r.error) return fail(r.error); toast(T('saved')); await refreshQx();
  },
  qx_void: async (a) => { const why = window.prompt(T('why')); if (!why) return; const r = await sb.rpc('quick_expense_void', { p_id: a.dataset.id, p_note: why }); if (r.error) return fail(r.error); await refreshQx(); },
  qx_close: async () => { const r = await sb.rpc('quick_expense_close_day', { p_loc: D.q.loc, p_date: D.q.day }); if (r.error) return fail(r.error); toast(T('made') + ' ×' + (r.data.made || 0)); await refreshQx(); },
});
document.addEventListener('change', (e) => {
  if (e.target.id === 'qx_loc') { D.q.loc = Number(e.target.value); refreshQx().catch(fail); }
  if (e.target.id === 'qx_day') { D.q.day = e.target.value; refreshQx().catch(fail); }
});
async function viewQx() {
  shell(T('qtitle'), '<div id="qx_body"><p class="muted">…</p></div>', true);
  try { await loadQx(); drawQx(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { paths: viewPaths, quickexp: viewQx });
})();
