/* Islamia BOS · Templates page (#/templates, owner). Server side: supabase/phase93.sql (doc_template_choice, set_doc_template, get_doc_templates).
   Lists every document type with a live preview carousel (SAMPLE data only), a one-line recommendation (advice, never blocking), and "Set as default".
   No choice saved = today's output stays exactly as it is. The owner can set a default for all locations or for one location.
   Rendering lives in tpl_registry.js (BOS.tpl.render); other screens call that, this page only chooses. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS, T = B.tpl;
const { sb, esc, toast, fail, shell, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  title: L('টেমপ্লেট', 'Templates', 'Template'),
  intro: L('প্রতিটি কাগজ বা মেসেজের জন্য ডিজাইন বেছে ডিফল্ট করুন। প্রিভিউতে শুধু নমুনা তথ্য। কিছু না বাছলে আজকের মতোই ছাপা হবে।', 'Pick a design for each paper or message and set it as the default. Previews use sample data only. If you pick nothing, printing stays exactly as it is today.', 'প্রতিটি paper বা message-এর design বেছে default করুন। Preview-তে শুধু sample data। কিছু না বাছলে আজকের মতোই print হবে।'),
  where: L('কোথায় প্রযোজ্য', 'Applies to', 'Applies to'), allLoc: L('সব লোকেশন', 'All locations', 'সব location'),
  now: L('এখন ডিফল্ট', 'Current default', 'Current default'), today: L('আজকের ছাপা (কোনো টেমপ্লেট বাছা নেই)', "Today's output (no template chosen)", 'আজকের print (কোনো template বাছা নেই)'),
  rec: L('প্রস্তাব', 'Suggestion', 'Suggestion'), set: L('ডিফল্ট করুন', 'Set as default', 'Default করুন'), isdef: L('এটাই ডিফল্ট ✓', 'This is the default ✓', 'এটাই default ✓'), clear: L('আজকের ছাপায় ফিরুন', "Back to today's output", 'আজকের print-এ ফিরুন'),
  prev: L('আগের', 'Previous', 'Previous'), next: L('পরের', 'Next', 'Next'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), cleared: L('আজকের ছাপায় ফিরেছে', "Back to today's output", 'আজকের print-এ ফিরেছে'),
  sample: L('নমুনা তথ্য', 'Sample data', 'Sample data'), recmark: L('প্রস্তাবিত', 'Suggested', 'Suggested'), of: L('এর', 'of', 'of'),
  sms: L('SMS', 'SMS', 'SMS'), wa: L('WhatsApp', 'WhatsApp', 'WhatsApp'), em: L('Email', 'Email', 'Email'), plain: L('শুধু লেখা, কোনো ছবি বা কোড নেই', 'Plain text only', 'Plain text only'),
  sql: L('এই অংশ চালু করতে নতুন SQL (phase93) চালাতে হবে।', 'The new SQL (phase93) must be run to switch this part on.', 'এই অংশ চালু করতে নতুন SQL (phase93) চালাতে হবে।'),
};
for (const k of Object.keys(X)) X[k].bn = X[k].mix || X[k].bn;   // Bangla mode keeps the common words English, same as the mix text
const TX = (k) => lab(X[k]);
const lg = () => (A.S && A.S.lang) || 'bn';
const D = { rows: [], loc: null, idx: {}, chan: 'sms', ready: false, shop: null };
const docIdx = (id) => (Object.prototype.hasOwnProperty.call(D.idx, id) ? D.idx[id] : Math.max(0, T.docs[id].tpls.findIndex((t) => t.id === T.docs[id].rec[0])));
const locName = (l) => (A.nm ? A.nm(l) : l.name_en || l.name_bn || String(l.id));
const locs = () => ((B.ENV && B.ENV.locs) || []).filter((l) => l.is_active !== false);
const current = (docType) => {                 // the saved choice for the selected place (this location's row, else the all-locations row)
  const a = D.loc !== null ? D.rows.find((r) => r.doc_type === docType && r.location_id === D.loc) : null;
  const b = D.rows.find((r) => r.doc_type === docType && (r.location_id === null || r.location_id === undefined));
  return (a || b || {}).template_id || null;
};
const scoped = (docType) => D.rows.find((r) => r.doc_type === docType && (D.loc === null ? (r.location_id === null || r.location_id === undefined) : r.location_id === D.loc));
function preview(docType, tp) {
  const sp = T.docs[docType], d = T.sample(docType), l = lg();
  if (sp.kind === 'text') {
    const txt = T.render(docType, d, tp.id, { lang: l === 'en' ? 'en' : 'bn', channel: D.chan });
    return `<pre class="card" style="white-space:pre-wrap;word-break:break-word;margin:0;font:inherit">${esc(txt)}</pre>`;
  }
  const html = T.render(docType, d, tp.id, { lang: l, shop: D.shop || T.sampleShop });
  const pg = (T.pages[tp.page] || [0, 0, 0])[2] + 2 * ((T.pages[tp.page] || [0, 0])[1]);
  const w = tp.page === 'label' ? 100 : pg + 8;
  // strip the print-only @page rule: a preview must not change how the app itself prints
  return `<div class="tpl93-pv" data-w="${w}" style="overflow:hidden;border:1px solid var(--line,#ccc);border-radius:8px;background:#fff;padding:4px"><div class="tpl93-in" style="width:${w}mm;transform-origin:top left">${html.replace(/@page\{[^}]*\}/g, '')}</div></div>`;
}
function card(sp) {
  const id = sp.id, i = docIdx(id), tp = sp.tpls[i], cur = current(id), curT = sp.tpls.find((t) => t.id === cur), rec = T.recommend(id), l = lg();
  const here = scoped(id), isDef = here && here.template_id === tp.id;
  return `<div class="card stack" id="tpl93_${esc(id)}"><b>${esc(T.lbl(sp.title, l))}</b>
    <div class="muted" style="font-size:.9rem">${esc(TX('now'))}: <b>${esc(curT ? T.tplName(curT, l) : TX('today'))}</b></div>
    <div class="notice">${esc(TX('rec'))}: ${esc(rec.text(l))}</div>
    <div class="row between"><button type="button" class="btn" data-act="tpl93_prev" data-v="${esc(id)}" aria-label="${esc(TX('prev'))}">&lsaquo; ${esc(TX('prev'))}</button><span class="muted">${i + 1} ${esc(TX('of'))} ${sp.tpls.length}</span><button type="button" class="btn" data-act="tpl93_next" data-v="${esc(id)}" aria-label="${esc(TX('next'))}">${esc(TX('next'))} &rsaquo;</button></div>
    <div class="row wrap">${sp.tpls.map((t, k) => `<button type="button" class="chip ${k === i ? 'warn' : ''}" data-act="tpl93_go" data-v="${esc(id)}" data-i="${k}" ${k === i ? 'aria-current="true"' : ''}>${esc(T.tplName(t, l))}${t.id === sp.rec[0] ? ' · ' + esc(TX('recmark')) : ''}</button>`).join('')}</div>
    ${sp.kind === 'text' ? `<div class="row wrap"><button type="button" class="chip ${D.chan === 'sms' ? 'warn' : ''}" data-act="tpl93_chan" data-v="sms">${esc(TX('sms'))}</button><button type="button" class="chip ${D.chan === 'whatsapp' ? 'warn' : ''}" data-act="tpl93_chan" data-v="whatsapp">${esc(TX('wa'))}</button><button type="button" class="chip ${D.chan === 'email' ? 'warn' : ''}" data-act="tpl93_chan" data-v="email">${esc(TX('em'))}</button></div>` : ''}
    <div class="muted" style="font-size:.8rem">${esc(TX('sample'))}</div>${preview(id, tp)}
    <div class="row wrap">${isDef ? `<span class="chip">${esc(TX('isdef'))}</span>` : `<button type="button" class="btn primary" data-act="tpl93_set" data-v="${esc(id)}">${esc(TX('set'))}</button>`}
      ${here ? `<button type="button" class="btn" data-act="tpl93_clear" data-v="${esc(id)}">${esc(TX('clear'))}</button>` : ''}</div></div>`;
}
function fit() {
  if (typeof document === 'undefined') return;
  document.querySelectorAll('.tpl93-pv').forEach((el) => {
    const inn = el.firstElementChild; if (!inn) return; inn.style.transform = 'none'; const nat = inn.scrollWidth || 1, avail = el.clientWidth - 8 || nat, s = Math.min(1, avail / nat);
    inn.style.transform = `scale(${s})`; el.style.height = Math.ceil(inn.scrollHeight * s + 8) + 'px';
  });
}
function draw() {
  const el = $('#tpl93_body'); if (!el) return;
  const groups = []; for (const sp of T.docTypes()) { let g = groups.find((x) => x.id === sp.group); if (!g) { g = { id: sp.group, list: [] }; groups.push(g); } g.list.push(sp); }
  const lc = locs();
  el.innerHTML = `<p class="muted">${esc(TX('intro'))}</p>
    <div class="card stack"><label for="tpl93_loc"><b>${esc(TX('where'))}</b></label><select id="tpl93_loc"><option value="">${esc(TX('allLoc'))}</option>${lc.map((l) => `<option value="${esc(l.id)}" ${D.loc === l.id ? 'selected' : ''}>${esc(locName(l))}</option>`).join('')}</select></div>`
    + groups.map((g) => `<h2>${esc(T.lbl(g.id, lg()))}</h2>${g.list.map(card).join('')}`).join('');
  if (typeof requestAnimationFrame === 'function') requestAnimationFrame(fit);
}
const redraw = (id) => { const old = $('#tpl93_' + id); if (!old) return draw(); const tmp = document.createElement('div'); tmp.innerHTML = card(T.docs[id]); old.replaceWith(tmp.firstElementChild); if (typeof requestAnimationFrame === 'function') requestAnimationFrame(fit); };
const step = (id, d) => { const n = T.docs[id].tpls.length; D.idx[id] = (docIdx(id) + d + n) % n; redraw(id); };
async function reload() { const r = await sb.rpc('get_doc_templates', { p_location_id: D.loc }); if (r.error) throw r.error; D.rows = Array.isArray(r.data) ? r.data : []; T.setChoices(D.rows); }
async function shopSettings() {      // logo / shop name / footer / tax id placeholders come from Settings when they exist; otherwise the sample shop
  try {
    const r = await sb.from('settings').select('key,value').in('key', ['business_name', 'shop_logo', 'invoice_footer', 'tax_id', 'shop_address', 'shop_phone']);
    if (r.error || !Array.isArray(r.data)) return null;
    const m = {}; for (const x of r.data) m[x.key] = typeof x.value === 'string' ? x.value : (x.value === null || x.value === undefined ? '' : String(x.value));
    const s = { name: m.business_name, logo: m.shop_logo, footer: m.invoice_footer, taxId: m.tax_id, address: m.shop_address, phone: m.shop_phone };
    return Object.keys(s).some((k) => s[k]) ? Object.assign({}, T.sampleShop, Object.fromEntries(Object.entries(s).filter(([, v]) => v))) : null;
  } catch (e) { return null; }
}
Object.assign(H, {
  tpl93_prev: (a) => step(a.dataset.v, -1), tpl93_next: (a) => step(a.dataset.v, 1),
  tpl93_go: (a) => { D.idx[a.dataset.v] = Number(a.dataset.i) || 0; redraw(a.dataset.v); },
  tpl93_chan: (a) => { D.chan = a.dataset.v; draw(); },
  tpl93_set: async (a) => {
    const id = a.dataset.v, sp = T.docs[id]; if (!sp) return; const tp = sp.tpls[docIdx(id)];
    const r = await sb.rpc('set_doc_template', { p_doc_type: id, p_template_id: tp.id, p_location_id: D.loc }); if (r.error) return fail(r.error);
    toast(TX('saved')); try { await reload(); redraw(id); } catch (e) { fail(e); }
  },
  tpl93_clear: async (a) => {
    const id = a.dataset.v; const r = await sb.rpc('set_doc_template', { p_doc_type: id, p_template_id: null, p_location_id: D.loc }); if (r.error) return fail(r.error);
    toast(TX('cleared')); try { await reload(); redraw(id); } catch (e) { fail(e); }
  },
});
document.addEventListener('change', async (e) => {
  if (!e.target || e.target.id !== 'tpl93_loc') return;
  D.loc = e.target.value === '' ? null : Number(e.target.value); try { await reload(); draw(); } catch (er) { fail(er); }
});
async function viewTemplates() {
  shell(TX('title'), '<div id="tpl93_body"><p class="muted">…</p></div>', true);
  try { await reload(); } catch (e) { const el = $('#tpl93_body'); if (el) el.innerHTML = `<div class="notice bad">${esc(TX('sql'))}</div>`; return; }
  D.shop = await shopSettings(); D.ready = true; draw();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { templates: viewTemplates });
})();
