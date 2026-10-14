/* Islamia BOS · Purchase bill Print / Share / Download / Email / SMS / WhatsApp (bos104, step PBill). WEB ONLY, no SQL.
   - purchase.js has no print path. This file is a decorator: when a purchase bill page (#/purchase/<id>) is open, a small button group is added
     (MutationObserver on the app root). B.purchaseprint.open(id) opens the full sheet. A page #/purchaseprint lists recent bills, so the feature is
     reachable even if the decorator fails. purchase.js itself is not touched.
   - Data: the same RPC purchase_get(p_id) the bill page uses. If the server refuses it (no purchase permission) NOTHING is shown or built.
   - Layout: the owner's chosen template B.tpl.render('purchase_bill' / 'grn') after B.tpl.ensure(sb); nothing chosen (render -> null) or any error:
     a plain built-in layout below, so Print always works.
   - COST SECRECY: a purchase bill is a cost document. Only people who may open the bill get it; the document has the bill's own unit rates (a supplier-side
     paper) and NEVER a sale price or margin: fields are picked one by one below. The GRN carries quantities only.
   - Status: DRAFT / VOID are printed in a clear band at the top and in every message. POSTED bills have no band.
   - Print: hidden iframe + print() (same idea as B.tpl.print). Email / SMS / WhatsApp are DEVICE-SIDE links (mailto:, sms:, https://wa.me/<n>?text=);
     the person sends from their own phone app. Nothing is sent by this app. No printer: a friendly line points to Share / Download. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, openSheet, closeSheet, fmt } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(n));
const BRAND = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };
const brandText = () => (S.lang === 'en' ? BRAND.en : BRAND.bn);

const X = {
  title: L('ক্রয় বিল প্রিন্ট ও পাঠান', 'Print and send purchase bills', 'Purchase Bill Print ও পাঠান'),
  intro: L('একটি বিল বেছে নিন — প্রিন্ট, শেয়ার, ডাউনলোড, Email, SMS, WhatsApp।', 'Pick a bill to print, share, download, email, SMS or WhatsApp.', 'একটি Bill বেছে নিন — Print, Share, Download, Email, SMS, WhatsApp।'),
  none: L('কোনো বিল নেই', 'No bills', 'কোনো Bill নেই'), loading: L('আনা হচ্ছে…', 'Loading…', 'আনা হচ্ছে…'),
  noperm: L('এই বিল দেখার অনুমতি নেই', 'You are not allowed to see purchase bills', 'Purchase Bill দেখার অনুমতি নেই'),
  loadFail: L('বিল আনা যায়নি। নেট দেখে আবার চেষ্টা করুন।', 'Could not load the bill. Check the connection and try again.', 'Bill আনা যায়নি। নেট দেখে আবার চেষ্টা করুন।'),
  grpHead: L('প্রিন্ট ও পাঠান', 'Print / Send', 'Print / Send'),
  print: L('প্রিন্ট', 'Print', 'Print'), grn: L('GRN প্রিন্ট', 'Print GRN', 'GRN Print'), share: L('শেয়ার', 'Share', 'Share'), dl: L('ডাউনলোড', 'Download', 'Download'),
  email: L('ইমেইল', 'Email', 'Email'), sms: L('এসএমএস', 'SMS', 'SMS'), wa: L('হোয়াটসঅ্যাপ', 'WhatsApp', 'WhatsApp'), more: L('Email · SMS · WhatsApp', 'Email · SMS · WhatsApp', 'Email · SMS · WhatsApp'),
  close: L('বন্ধ', 'Close', 'Close'), open: L('খুলুন', 'Open', 'Open'),
  phone: L('সাপ্লায়ারের মোবাইল নম্বর', 'Supplier mobile number', 'Supplier-এর mobile number'), mail: L('সাপ্লায়ারের ইমেইল ঠিকানা', 'Supplier email address', 'Supplier-এর email address'),
  needPhone: L('ঠিক মোবাইল নম্বর লিখুন (যেমন 01XXXXXXXXX)', 'Enter a valid mobile number (like 01XXXXXXXXX)', 'ঠিক mobile number লিখুন (যেমন 01XXXXXXXXX)'),
  needMail: L('ঠিক ইমেইল ঠিকানা লিখুন', 'Enter a valid email address', 'ঠিক email address লিখুন'),
  sendNote: L('ইমেইল, এসএমএস ও WhatsApp আপনার ফোনের নিজের অ্যাপ খুলবে; সেখানে Send চাপলে তবেই যাবে। এই অ্যাপ নিজে কিছু পাঠায় না।', 'Email, SMS and WhatsApp open your own phone app; the message goes only when you tap Send there. This app sends nothing by itself.', 'Email, SMS ও WhatsApp আপনার ফোনের নিজের app খুলবে; সেখানে Send চাপলে তবেই যাবে। এই app নিজে কিছু পাঠায় না।'),
  noPrinter: L('এই ফোনে প্রিন্ট করা গেল না (প্রিন্টার সংযুক্ত নেই বা প্রিন্ট বন্ধ)। শেয়ার বা ডাউনলোড ব্যবহার করুন; প্রিন্ট জানালায় "Save as PDF"ও আছে।', 'Printing did not work here (no printer connected, or printing is off). Use Share or Download instead; "Save as PDF" is also in the print window.', 'এই ফোনে Print করা গেল না (printer নেই বা print বন্ধ)। Share বা Download ব্যবহার করুন; print window-এ "Save as PDF"ও আছে।'),
  opened: L('আপনার ফোনের অ্যাপ খুলেছে — সেখানে Send চাপুন', 'Your phone app opened. Tap Send there', 'আপনার ফোনের app খুলেছে — সেখানে Send চাপুন'),
  copied: L('টেক্সট কপি হয়েছে', 'Text copied', 'Text copy হয়েছে'), shareFail: L('শেয়ার করা গেল না', 'Could not share', 'Share করা গেল না'),
  dlDone: L('ফাইল নামানো হয়েছে — খুলে প্রিন্ট বা PDF করা যাবে', 'File saved. Open it to print or save as PDF', 'File নামানো হয়েছে — খুলে print বা PDF করা যাবে')
};
const T = (k) => lab(X[k]);
// words printed on the documents: common words stay English in every language (Bill, Supplier, Date, Qty, Rate, Total, Paid, Due)
const W = { bill: 'Purchase Bill', ret: 'Purchase Return', grn: 'Goods Received Note (GRN)', no: 'Bill no.', sup: 'Supplier', date: 'Date', loc: 'Branch', item: 'Item', qty: 'Qty', unit: 'Unit', rate: 'Rate', amount: 'Amount',
  sub: 'Subtotal', disc: 'Discount', total: 'Total', paid: 'Paid', due: 'Due', note: 'Note', draft: 'DRAFT - not posted', void: 'VOID', recv: 'Received by', chk: 'Checked by', prep: 'Prepared by', auth: 'Authorised by' };

const V = { m: null, id: null };
const dshort = (iso) => (iso ? new Date(String(iso).slice(0, 10) + 'T12:00:00Z').toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }) : '');
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const normMobile = (v) => { let d = norm(v).replace(/[^0-9+]/g, ''); if (d.startsWith('+880')) d = '0' + d.slice(4); else if (d.startsWith('880') && d.length === 13) d = '0' + d.slice(3); return /^01[3-9][0-9]{8}$/.test(d) ? d : null; };
function intlNumber(v) { const m = normMobile(v); if (m) return '880' + m.slice(1); const raw = norm(v).trim(); if (raw.startsWith('+')) { const d = raw.replace(/\D/g, ''); if (d.length >= 8 && d.length <= 15) return d; } return null; }
const okMail = (v) => /^[^\s@,;?&#<>"]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(String(v || '').trim());   // bos111 (L2): no ?bcc= / &cc= / list tricks in the address
const pickName = (o) => !o ? '' : (S.lang === 'en' ? (o.name_en || o.name || o.name_bn) : S.lang === 'mix' ? (o.name_mix || o.name_bn || o.name) : (o.name_bn || o.name || o.name_en)) || '';
const locObj = (id) => (((B.ENV && B.ENV.locs) || []).find((l) => l.id === id)) || null;
const locName = (id) => { const l = locObj(id); return l ? (S.lang === 'en' ? (l.name_en || l.code || '') : S.lang === 'mix' ? (l.name_mix || l.name_bn || l.code || '') : (l.name_bn || l.name_en || l.code || '')) : ''; };

// ---------- the model: only the fields a supplier-side bill needs. No sale price, no margin, ever. ----------
function lineName(l) {
  if (l.description) return String(l.description);
  const items = (B.ENV && B.ENV.items) || [];
  const it = l.item_id ? items.find((x) => x.id === l.item_id) : null;
  return (it && pickName(it)) || l.item_name || l.name || '—';
}
function modelOf(b) {
  const sup = (((B.ENV && B.ENV.sup) || []).find((s) => s.id === b.supplier_id)) || {};
  const posted = b.status === 'posted', ret = b.kind === 'return';
  const m = { id: b.id, status: b.status || 'posted', ret, no: b.bill_no || '', date: b.bill_date ? dshort(b.bill_date) : '', loc_id: b.location_id, location: locName(b.location_id),
    supplier: { name: b.supplier_name || sup.name || '', phone: sup.mobile || '' }, mobile: sup.mobile || '', email: sup.email || '',
    items: (b.lines || []).map((l, i) => ({ code: String(i + 1), name: lineName(l), qty: Number(l.qty) || 0, unit: l.unit || '', rate: Number(l.unit_cost) || 0, amount: Number(l.amount) || 0 })),
    subtotal: Number(b.subtotal) || 0, discount: Number(b.discount) || 0, total: Number(b.total) || 0, paid: posted && !ret ? Number(b.paid) || 0 : null, due: posted && !ret ? Number(b.due) || 0 : null,
    note: b.note || '', void_note: b.void_note || '' };
  return m;
}
async function load(id) {   // -> model, or null (refused / failed): then nothing is shown
  try {
    const r = await sb.rpc('purchase_get', { p_id: id });
    if (!r || r.error || !r.data) return { err: r && r.error && /not allowed/.test(r.error.message || '') ? 'noperm' : 'loadFail' };
    return { m: modelOf(r.data) };
  } catch (e) { return { err: 'loadFail' }; }
}

// ---------- documents ----------
const statusLine = (m) => (m.status === 'void' ? W.void : m.status === 'draft' ? W.draft : '');
const docTitle = (m, grn) => (grn ? W.grn : m.ret ? W.ret : W.bill);
function tplData(m, grn) {   // keys avoid the template engine's cost-word filter; the GRN has no rate / amount at all
  const note = [statusLine(m), m.note, m.status === 'void' && m.void_note ? m.void_note : ''].filter(Boolean).join(' - ');
  const d = { no: m.no || '', date: m.date, supplier_bill_no: m.no || '', location: m.location, supplier: { name: m.supplier.name, phone: m.supplier.phone }, note,
    items: m.items.map((l) => (grn ? { code: l.code, name: l.name, qty: l.qty, unit: l.unit } : { code: l.code, name: l.name, qty: l.qty, unit: l.unit, rate: l.rate, amount: l.amount })) };
  if (!grn) { d.subtotal = m.subtotal; d.discount = m.discount; d.total = m.total; if (m.paid !== null) { d.paid = m.paid; d.due = m.due; } }
  return d;
}
const band = (m) => { const s = statusLine(m); return s ? `<div data-pbp="status" style="border:3px solid #b3261e;color:#b3261e;font:700 22px system-ui,sans-serif;text-align:center;padding:6px;margin:0 0 10px;letter-spacing:2px">${esc(s)}</div>` : ''; };
function builtin(m, grn) {
  const th = (t, r) => `<th style="border-bottom:2px solid #333;padding:4px 6px;text-align:${r ? 'right' : 'left'}">${esc(t)}</th>`;
  const td = (t, r) => `<td style="border-bottom:1px solid #ccc;padding:4px 6px;text-align:${r ? 'right' : 'left'};${r ? 'white-space:nowrap' : ''}">${esc(t)}</td>`;
  const rows = m.items.map((l) => `<tr>${td(l.name)}${td(fmt(l.qty), 1)}${td(l.unit)}${grn ? '' : td(money(l.rate), 1) + td(money(l.amount), 1)}</tr>`).join('');
  const tr = (k, v, bold) => `<tr><td style="padding:2px 6px;${bold ? 'font-weight:700;' : ''}">${esc(k)}</td><td style="padding:2px 6px;text-align:right;${bold ? 'font-weight:700;' : ''}">${esc(money(v))}</td></tr>`;
  const sign = (grn ? [W.recv, W.chk] : [W.prep, W.auth]).map((s) => `<div style="flex:1;border-top:1px solid #333;padding-top:4px;text-align:center">${esc(s)}</div>`).join('');
  const meta = [[W.no, m.no || '—'], [W.date, m.date], [W.sup, m.supplier.name], [W.loc, m.location]].filter((x) => x[1]).map((x) => `<div><span style="color:#555">${esc(x[0])}: </span><b>${esc(x[1])}</b></div>`).join('');
  return `<div data-pbp="builtin" style="font:14px system-ui,sans-serif;color:#111;max-width:760px;margin:0 auto;padding:8px"><div style="text-align:center;font-weight:700;font-size:18px">${esc(brandText())}</div>
    <div style="text-align:center;font-size:16px;margin:2px 0 10px">${esc(docTitle(m, grn))}</div>${band(m)}<div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 12px;margin-bottom:10px">${meta}</div>
    <table style="width:100%;border-collapse:collapse"><thead><tr>${th(W.item)}${th(W.qty, 1)}${th(W.unit)}${grn ? '' : th(W.rate, 1) + th(W.amount, 1)}</tr></thead><tbody>${rows}</tbody></table>
    ${grn ? '' : `<table style="margin:10px 0 0 auto;border-collapse:collapse;min-width:220px">${tr(W.sub, m.subtotal)}${m.discount ? tr(W.disc, -m.discount) : ''}${tr(W.total, m.total, 1)}${m.paid !== null ? tr(W.paid, m.paid) + tr(W.due, m.due) : ''}</table>`}
    ${m.note ? `<div style="margin-top:10px"><span style="color:#555">${esc(W.note)}: </span>${esc(m.note)}</div>` : ''}${m.status === 'void' && m.void_note ? `<div style="margin-top:4px">${esc(m.void_note)}</div>` : ''}
    <div style="display:flex;gap:24px;margin-top:40px">${sign}</div></div>`;
}
async function fragment(m, grn) {   // -> { html, used: 'tpl' | 'builtin' }
  try {
    if (B.tpl && B.tpl.render) {
      try { if (B.tpl.ensure) await B.tpl.ensure(sb); } catch (e) { /* keep going: no choice known */ }
      const h = B.tpl.render(grn ? 'grn' : 'purchase_bill', tplData(m, grn), undefined, { lang: S.lang, loc: m.loc_id, shop: { name: brandText() } });
      if (typeof h === 'string' && h) return { html: band(m) + h, used: 'tpl' };
    }
  } catch (e) { /* fall through to the built-in layout */ }
  return { html: builtin(m, grn), used: 'builtin' };
}
const pageOf = (frag, m, grn) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(docTitle(m, grn) + ' ' + (m.no || ''))}</title><style>html,body{margin:0;background:#fff}@page{margin:10mm}</style></head><body>${frag}</body></html>`;
function textOf(m, grn) {
  const out = [`${docTitle(m, grn)} ${m.no || ''}`.trim(), brandText(), `${W.sup}: ${m.supplier.name}`, `${W.date}: ${m.date}`];
  if (statusLine(m)) out.push(statusLine(m));
  for (const l of m.items) out.push(grn ? `- ${l.name}: ${fmt(l.qty)} ${l.unit}`.trim() : `- ${l.name}: ${fmt(l.qty)} ${l.unit} x ${money(l.rate)} = ${money(l.amount)}`.replace(/ +/g, ' '));
  if (!grn) { out.push(`${W.total}: ${money(m.total)}`); if (m.paid !== null) out.push(`${W.paid}: ${money(m.paid)}`, `${W.due}: ${money(m.due)}`); }
  return out.join('\n');
}

// ---------- the actions ----------
function go(url, blank) { const a = document.createElement('a'); a.href = url; if (blank) { a.target = '_blank'; a.rel = 'noopener'; } a.style.display = 'none'; document.body.appendChild(a); a.click(); a.remove(); }
function notice(on) { const el = $('#pbp_np'); if (el) el.innerHTML = on ? `<div class="notice warn">${esc(T('noPrinter'))}</div>` : ''; }
async function doPrint(grn) {
  const m = V.m; if (!m) return; notice(false);
  if (typeof window.print !== 'function' || typeof document === 'undefined') return notice(true);
  try {
    const f = await fragment(m, grn), html = pageOf(f.html, m, grn);
    const fr = document.createElement('iframe'); fr.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0'; fr.setAttribute('data-pbp', 'frame'); document.body.appendChild(fr);
    fr.onload = () => { try { fr.contentWindow.focus(); fr.contentWindow.print(); } catch (e) { notice(true); } setTimeout(() => { try { fr.remove(); } catch (e) { /* gone */ } }, 2000); };
    fr.srcdoc = html;
  } catch (e) { notice(true); }
}
async function copyText(txt) {
  try { if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(txt); return true; } } catch (e) { /* fall through */ }
  try { const ta = document.createElement('textarea'); ta.value = txt; ta.style.cssText = 'position:fixed;left:-9999px'; document.body.appendChild(ta); ta.select(); const ok = document.execCommand && document.execCommand('copy'); ta.remove(); return !!ok; } catch (e) { return false; }
}
async function doShare() {
  const m = V.m; if (!m) return; const txt = textOf(m, false);
  try { if (navigator.share) { await navigator.share({ title: `${docTitle(m)} ${m.no || ''}`.trim(), text: txt }); return; } } catch (e) { if (e && e.name === 'AbortError') return; }
  toast((await copyText(txt)) ? T('copied') : T('shareFail'));
}
async function doDl() {
  const m = V.m; if (!m) return;
  try {
    const f = await fragment(m, false), blob = new Blob([pageOf(f.html, m, false)], { type: 'text/html' }), url = URL.createObjectURL(blob), a = document.createElement('a');
    a.href = url; a.download = `purchase-bill-${String(m.no || m.id || 'x').replace(/[^A-Za-z0-9_-]/g, '_')}.html`; a.style.display = 'none'; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000); toast(T('dlDone'));
  } catch (e) { toast(T('shareFail')); }
}
const phoneNum = () => { const n = intlNumber(($('#pbp_phone') || {}).value || ''); if (!n) toast(T('needPhone')); return n; };
function doSms() { const m = V.m; if (!m) return; const n = phoneNum(); if (!n) return; const ios = /iPhone|iPad|iPod/i.test((window.navigator && window.navigator.userAgent) || '');
  go(`sms:+${n}${ios ? '&' : '?'}body=${encodeURIComponent(textOf(m, false))}`); toast(T('opened')); }
function doWa() { const m = V.m; if (!m) return; const n = phoneNum(); if (!n) return; const txt = textOf(m, false);
  const base = B.tpl && B.tpl.waUrl ? B.tpl.waUrl(txt) : 'https://wa.me/?text=' + encodeURIComponent(txt);
  go(base.replace('https://wa.me/?', `https://wa.me/${n}?`), true); toast(T('opened')); }
function doEmail() { const m = V.m; if (!m) return; const e = (($('#pbp_email') || {}).value || '').trim(); if (!okMail(e)) return toast(T('needMail'));
  go(`mailto:${e}?subject=${encodeURIComponent(`${docTitle(m)} ${m.no || ''} ${statusLine(m)}`.trim())}&body=${encodeURIComponent(textOf(m, false))}`); toast(T('opened')); }

// ---------- the sheet ----------
function sheetHTML(m) {
  const chip = statusLine(m) ? ` <span class="chip bad">${esc(statusLine(m))}</span>` : '';
  const btn = (act, label, cls) => `<button type="button" class="${cls || ''}" data-act="${act}" style="flex:1 1 44%">${esc(label)}</button>`;
  return `<h2>${esc(T('grpHead'))}</h2><div class="card stack" data-pbp="card"><div><b>${esc(m.supplier.name)}</b>${chip}</div><div class="muted">${esc(m.no || '—')} · ${esc(m.date)}${m.location ? ' · ' + esc(m.location) : ''}</div><div class="mnum">${esc(money(m.total))}</div></div>
    <div id="pbp_np"></div>
    <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:10px">${btn('pbp_print', T('print'), 'primary')}${m.ret ? '' : btn('pbp_grn', T('grn'))}${btn('pbp_share', T('share'))}${btn('pbp_dl', T('dl'))}</div>
    <div class="stack" style="margin-top:10px"><div><label for="pbp_phone">${esc(T('phone'))}</label><input id="pbp_phone" inputmode="tel" autocomplete="off" value="${esc(m.mobile)}"></div>
      <div><label for="pbp_email">${esc(T('mail'))}</label><input id="pbp_email" type="email" autocomplete="off" value="${esc(m.email)}"></div></div>
    <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px">${btn('pbp_email_go', T('email'))}${btn('pbp_sms', T('sms'))}${btn('pbp_wa', T('wa'))}</div>
    <p class="muted" style="font-size:.85rem">${esc(T('sendNote'))}</p>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`;
}
async function open(id) {
  if (!id) return false;
  const r = await load(id);
  if (!r.m) { toast(T(r.err)); return false; }      // refused or failed: nothing is shown, nothing is built
  V.m = r.m; V.id = id; openSheet(sheetHTML(r.m)); return true;
}

// ---------- handlers ----------
Object.assign(A.H, {
  pbp_open: (a) => open(a.dataset.v),
  pbp_print: () => doPrint(false), pbp_grn: () => doPrint(true), pbp_share: () => doShare(), pbp_dl: () => doDl(),
  pbp_email_go: () => doEmail(), pbp_sms: () => doSms(), pbp_wa: () => doWa(),
  pbp_quick: async (a) => { if (await open(a.dataset.v)) doPrint(false); }       // the Print button on the bill page / list: opens the sheet and prints
});

// ---------- the decorator: a button group on the purchase bill page ----------
function billIdFromHash() {
  const p = String(location.hash || '').replace(/^#\/?/, '').split('/');
  if (p[0] !== 'purchase' || !p[1] || ['new', 'return', 'edit'].includes(p[1])) return null;
  return decodeURIComponent(p[1]);
}
function decorate() {
  try {
    const id = billIdFromHash(); if (!id) return;
    const root = document.getElementById('app'); if (!root || root.querySelector('#pbp_grp')) return;
    if (root.querySelector('#pe_save, #pe_post')) return;                    // the editor, not the bill page
    const bar = root.querySelector('.s2-bar'), card = root.querySelector('.s2-led'); if (!bar || !card) return;   // the bill page has its lines and its action bar
    const b = (act, label, cls) => `<button type="button" class="${cls || ''}" data-act="${act}" data-v="${esc(id)}" style="flex:1 1 40%">${esc(label)}</button>`;
    const at = (card.closest && card.closest('.card')) || bar;   // above the lines card: visible without scrolling past the sticky action bar
    at.insertAdjacentHTML('beforebegin', `<div class="card stack" id="pbp_grp" data-pbp="group"><h3>${esc(T('grpHead'))}</h3><div class="row" style="gap:8px;flex-wrap:wrap">${b('pbp_quick', T('print'), 'primary')}${b('pbp_open', T('share'))}${b('pbp_open', T('dl'))}${b('pbp_open', T('more'))}</div></div>`);
  } catch (e) { /* the decorator never breaks the bill page; #/purchaseprint is the other way in */ }
}
let pend = 0;
function schedule() { if (pend) return; pend = setTimeout(() => { pend = 0; decorate(); }, 0); }
try {
  const root = document.getElementById('app') || document.body;
  if (typeof MutationObserver === 'function' && root) new MutationObserver(schedule).observe(root, { childList: true, subtree: true });
  window.addEventListener('hashchange', schedule);
  schedule();
} catch (e) { /* no observer: the page route still works */ }

// ---------- the page #/purchaseprint ----------
async function page() {
  A.shell(T('title'), `<p class="muted">${esc(T('intro'))}</p><div id="pbp_list"><p class="muted center">${esc(T('loading'))}</p></div>`, true);
  const el = () => $('#pbp_list'); let rows = [];
  try {
    const r = await sb.rpc('purchase_list', { p_loc: null, p_from: null, p_to: null, p_supplier: null, p_status: null, p_limit: 40 });
    if (r && r.error) { if (el()) el().innerHTML = `<div class="notice ${/not allowed/.test(r.error.message || '') ? 'warn' : 'bad'}">${esc(T(/not allowed/.test(r.error.message || '') ? 'noperm' : 'loadFail'))}</div>`; return; }
    rows = (r && r.data) || [];
  } catch (e) { if (el()) el().innerHTML = `<div class="notice bad">${esc(T('loadFail'))}</div>`; return; }
  if (!el()) return;
  el().innerHTML = rows.length ? rows.map((b) => `<div class="card item" data-act="pbp_open" data-v="${esc(b.id)}" role="button" tabindex="0"><div><div class="nm">${esc(b.supplier_name)}</div>
    <div class="muted" style="font-size:.85rem">${esc(b.bill_no || '—')} · ${esc(dshort(b.bill_date))}${b.status && b.status !== 'posted' ? ' · ' + esc(b.status === 'void' ? W.void : 'DRAFT') : ''}</div></div>
    <div class="pr"><b>${esc(money(b.total))}</b><button type="button" class="mini" data-act="pbp_quick" data-v="${esc(b.id)}">${esc(T('print'))}</button></div></div>`).join('') : `<p class="muted center">${esc(T('none'))}</p>`;
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { purchaseprint: page });

B.purchaseprint = { open, load, modelOf, tplData, builtin, fragment, textOf, pageOf, decorate, intlNumber, okMail, X, T, W };
})();
