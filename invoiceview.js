/* Islamia BOS · Invoice view (bos92): the invoice is shown ON SCREEN right after a sale (and from today's list), phone width, with buttons
   Print · Email · SMS · WhatsApp · Share · Copy · Download.
   - Setting  pos_show_invoice_after_sale  never (default = as before) | ask (a bar offers it) | always (opens by itself).
   - Works offline: a sale that waited in the local queue is drawn from the cart that was sent, with a provisional number, marked "pending sync".
   - Print uses the existing print path (B.invoice: template -> renderDoc -> printHtml -> window.print). A phone cannot tell whether a printer is
     connected, so if printing is not available or fails, a friendly line points to Share / Download ("Save as PDF" is in the print window too).
   - Email / SMS / WhatsApp are DEVICE-SIDE deep links (mailto:, sms:, https://wa.me/<number>?text=) with the invoice as text. The message is sent by
     the user's own phone app when they tap Send there. Nothing is sent from a server; no provider account, no secret. Automatic sending would
     need a provider account and is NOT built.
   - Data: supabase/phase92.sql  invoice_data92 (one sale, no cost column, customer mobile only for those who may see it) and invoice_share_log92
     (append-only log: print / email / sms / whatsapp / share / copy / download, who, when; the number or address typed is NOT stored).
   - If the SQL is not pasted yet the sale is drawn from the data already on the phone and the log is skipped. Nothing breaks. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, openSheet, closeSheet, fmt, store } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const r2 = (n) => Math.round(n * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(Number(n) || 0));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const BRAND = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };
const SHARE_Q = 'bos_iv92_shareq';

const X = {
  title: L('ইনভয়েস', 'Invoice', 'Invoice'), show: L('ইনভয়েস দেখুন', 'Show invoice', 'Invoice দেখুন'), openHist: L('ইনভয়েস দেখুন / পাঠান', 'View / send invoice', 'Invoice দেখুন / পাঠান'),
  receipt: L('ইনভয়েস', 'Invoice', 'Invoice'), prov: L('সাময়িক নম্বর', 'Provisional no.', 'সাময়িক number'),
  pending: L('সার্ভারে এখনো যায়নি — নেট এলে নিজে জমা হবে। এই নম্বরটি সাময়িক, চূড়ান্ত নম্বর পরে পাবেন।', 'Pending sync: not on the server yet. It will be sent when the phone is online. This number is provisional; the final number comes after sync.', 'সার্ভারে এখনো যায়নি (pending sync) — net এলে নিজে জমা হবে। এই number টি সাময়িক, final number পরে পাবেন।'),
  synced: L('সার্ভারে জমা হয়েছে', 'Synced to the server', 'সার্ভারে জমা হয়েছে'), check: L('জমা হয়েছে কি দেখুন', 'Check sync', 'Sync হয়েছে কি দেখুন'), stillPending: L('এখনো জমা হয়নি', 'Not synced yet', 'এখনো sync হয়নি'),
  loading: L('ইনভয়েস আনা হচ্ছে…', 'Loading the invoice…', 'Invoice আনা হচ্ছে…'), loadFail: L('ইনভয়েস আনা যায়নি। নেট দেখে আবার চেষ্টা করুন।', 'The invoice could not be loaded. Check the connection and try again.', 'Invoice আনা যায়নি। Net দেখে আবার চেষ্টা করুন।'), retry: L('আবার চেষ্টা', 'Try again', 'আবার Try'),
  voided: L('বাতিল', 'VOID', 'VOID'), date: L('তারিখ', 'Date', 'Date'), cashier: L('বিক্রেতা', 'Cashier', 'Cashier'), customer: L('গ্রাহক', 'Customer', 'Customer'),
  item: L('আইটেম', 'Item', 'Item'), subtotal: L('মোট (ছাড়ের আগে)', 'Subtotal', 'Subtotal'), discount: L('ডিসকাউন্ট', 'Discount', 'Discount'), total: L('সর্বমোট', 'Total', 'Total'),
  vat: L('ভ্যাট', 'VAT', 'VAT'), incl: L('অন্তর্ভুক্ত', 'included', 'included'), paid: L('পরিশোধ', 'Paid', 'Paid'), due: L('বাকি', 'Due', 'Due'), change: L('ফেরত', 'Change', 'Change'),
  thanks: L('ধন্যবাদ', 'Thank you', 'ধন্যবাদ'), m_cash: L('নগদ', 'Cash', 'Cash'), m_mobile: L('মোবাইল', 'Mobile', 'Mobile'), m_card: L('কার্ড', 'Card', 'Card'), m_due: L('বাকি', 'On credit', 'বাকি'),
  print: L('প্রিন্ট', 'Print', 'Print'), email: L('ইমেইল', 'Email', 'Email'), sms: L('এসএমএস', 'SMS', 'SMS'), wa: L('হোয়াটসঅ্যাপ', 'WhatsApp', 'WhatsApp'),
  share: L('শেয়ার', 'Share', 'Share'), copy: L('কপি', 'Copy text', 'Text Copy'), dl: L('ডাউনলোড', 'Download', 'Download'), close: L('বন্ধ', 'Close', 'Close'),
  phone: L('গ্রাহকের মোবাইল নম্বর', 'Customer mobile number', 'Customer এর mobile number'), mail: L('গ্রাহকের ইমেইল ঠিকানা', 'Customer email address', 'Customer এর email address'),
  needPhone: L('ঠিক মোবাইল নম্বর লিখুন (যেমন 01XXXXXXXXX)', 'Enter a valid mobile number (like 01XXXXXXXXX)', 'ঠিক mobile number লিখুন (যেমন 01XXXXXXXXX)'),
  needMail: L('ঠিক ইমেইল ঠিকানা লিখুন', 'Enter a valid email address', 'ঠিক email address লিখুন'),
  masked: L('আপনার ভূমিকায় গ্রাহকের নম্বর দেখানো হয় না — নিজে লিখুন।', 'The customer number is hidden for your role. Type it in.', 'আপনার role এ customer এর number দেখানো হয় না — নিজে লিখুন।'),
  sendNote: L('ইমেইল, এসএমএস ও WhatsApp আপনার ফোনের নিজের অ্যাপ খুলবে; সেখানে Send চাপলে তবেই যাবে। এই অ্যাপ নিজে থেকে কিছু পাঠায় না। অটো পাঠাতে হলে আলাদা প্রোভাইডার অ্যাকাউন্ট লাগবে — তা বানানো হয়নি।',
    'Email, SMS and WhatsApp open your own phone app; the message goes only when you tap Send there. This app sends nothing by itself. Sending automatically would need a provider account, which is not built.',
    'Email, SMS ও WhatsApp আপনার ফোনের নিজের app খুলবে; সেখানে Send চাপলে তবেই যাবে। এই app নিজে থেকে কিছু পাঠায় না। Auto পাঠাতে হলে আলাদা provider account লাগবে — তা বানানো হয়নি।'),
  printHint: L('প্রিন্টার না থাকলে শেয়ার বা ডাউনলোড ব্যবহার করুন; প্রিন্ট জানালায় "Save as PDF"ও বাছা যায়।', 'No printer? Use Share or Download. The print window also offers "Save as PDF".', 'Printer না থাকলে Share বা Download ব্যবহার করুন; Print window তে "Save as PDF"ও বাছা যায়।'),
  noPrinter: L('এই ফোনে প্রিন্ট করা গেল না (প্রিন্টার সংযুক্ত নেই বা প্রিন্ট বন্ধ)। চিন্তা নেই — নিচের Share বা Download দিয়ে ইনভয়েস পাঠান বা সেভ করুন।', 'Printing did not work on this phone (no printer connected, or printing is switched off). No problem: use Share or Download below to send or save the invoice.', 'এই ফোনে Print করা গেল না (printer সংযুক্ত নেই বা print বন্ধ)। চিন্তা নেই — নিচের Share বা Download দিয়ে invoice পাঠান বা save করুন।'),
  copied: L('টেক্সট কপি হয়েছে', 'Text copied', 'Text copy হয়েছে'), shareFail: L('শেয়ার করা গেল না', 'Could not share', 'Share করা গেল না'),
  dlDone: L('ফাইল নামানো হয়েছে — খুলে প্রিন্ট বা PDF করা যাবে', 'File saved. Open it to print or save as PDF', 'File নামানো হয়েছে — খুলে print বা PDF করা যাবে'),
  opened: L('আপনার ফোনের অ্যাপ খুলেছে — সেখানে Send চাপুন', 'Your phone app opened. Tap Send there', 'আপনার ফোনের app খুলেছে — সেখানে Send চাপুন'),
  sharedBy: L('এই ইনভয়েস যতবার পাঠানো / প্রিন্ট হয়েছে', 'Times this invoice was printed or sent', 'এই invoice যতবার পাঠানো / print হয়েছে'),
};
const T = (k) => lab(X[k]);
const wl = (o) => (!o ? '' : S.lang === 'en' ? o.en || o.bn || '' : S.lang === 'mix' ? o.mix || o.bn || o.en || '' : o.bn || o.en || '');
const modeName = (m) => (X['m_' + m] ? T('m_' + m) : esc(m));

// ---------- state ----------
const V = { d: null, loading: false, err: false, last: null, tok: 0, noPrint: false };

// ---------- setting ----------
function mode() { let v = 'never'; try { v = B.rule('pos_show_invoice_after_sale', 'never'); } catch (e) { /* default */ } return v === 'always' || v === 'ask' ? v : 'never'; }

// ---------- helpers ----------
const normMobile = (v) => { let d = norm(v).replace(/[^0-9+]/g, ''); if (d.startsWith('+880')) d = '0' + d.slice(4); else if (d.startsWith('880') && d.length === 13) d = '0' + d.slice(3); return /^01[3-9][0-9]{8}$/.test(d) ? d : null; };
// the number a wa.me / sms link needs: Bangladesh mobile -> 880XXXXXXXXXX, any other +country number -> its digits
function intlNumber(v) {
  const m = normMobile(v); if (m) return '880' + m.slice(1);
  const raw = norm(v).trim(); if (raw.startsWith('+')) { const d = raw.replace(/\D/g, ''); if (d.length >= 8 && d.length <= 15) return d; }
  return null;
}
const okMail = (v) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(String(v || '').trim());
const dhakaDate = (iso) => new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const dhakaTime = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' });
const lineName = (l) => (S.lang === 'en' ? l.name_en || l.name : S.lang === 'mix' ? l.name_mix || l.name : l.name) || '';
const brandText = () => (S.lang === 'en' ? BRAND.en : BRAND.bn);

// ---------- the model: from the server ----------
function fromServer(j) {
  const cu = j.customer || null;
  return { id: j.id, client_id: j.client_id || null, pending: false, receipt: (j.location_code ? j.location_code + '-' : '') + j.receipt, loc_id: j.location_id, loc: j.location || null,
    date: j.sale_date, time: dhakaTime(j.sold_at), cashier: j.cashier || '', status: j.status || 'done',
    lines: (j.lines || []).map((l) => ({ code: l.code || '', name: l.name || '', name_en: l.name_en || '', name_mix: l.name_mix || '', unit: l.unit || '', qty: Number(l.qty) || 1, price: Number(l.price), amount: Number(l.amount) })),
    subtotal: Number(j.subtotal), discount: Number(j.discount) || 0, total: Number(j.total), paid: Number(j.paid), due: Number(j.due) || 0,
    pays: (j.payments || []).map((p) => ({ mode: p.mode, wallet: p.wallet || '', amount: Number(p.amount) })), vat: j.vat || null, change: 0,
    cust: cu ? { name: cu.name || '', mobile: cu.mobile || cu.whatsapp || '', masked: !!cu.masked } : null, shares: j.shares || [] };
}
// ---------- the model: from the cart that was sent (online fallback and the offline queue) ----------
function fromPayload(info) {
  const p = info.p || {}, data = info.data || null, lines = (p.p_lines || []).map((l) => {
    const qty = Number(l.qty) || 1, amt = l.amount !== undefined ? Number(l.amount) : r2(qty * Number(l.price));
    return { code: '', name: l.name || '', name_en: '', name_mix: '', unit: l.unit || '', qty, price: l.price !== undefined ? Number(l.price) : amt, amount: amt };
  });
  const sub = r2(lines.reduce((a, x) => a + x.amount, 0)), disc = Number(p.p_discount) || 0, total = data ? Number(data.total) : r2(sub - disc);
  const pays = (p.p_payments || []).map((x) => ({ mode: x.mode, wallet: x.wallet || '', amount: Number(x.amount) })), paid = r2(pays.reduce((a, x) => a + x.amount, 0));
  const loc = ((B.ENV && B.ENV.locs) || []).find((l) => l.id === p.p_loc) || {}, at = p.p_sold_at || new Date().toISOString();
  const prof = (S.ctx && S.ctx.profile) || {};
  return { id: data ? data.id : null, client_id: p.p_client || null, pending: !data, receipt: data ? (loc.code ? loc.code + '-' : '') + data.receipt : 'Q-' + String(p.p_client || '').replace(/-/g, '').slice(0, 6).toUpperCase(),
    loc_id: p.p_loc, loc: { bn: loc.name_bn || '', mix: loc.name_mix || '', en: loc.name_en || '' }, date: dhakaDate(at), time: dhakaTime(at), cashier: prof.full_name || prof.staff_id || '', status: 'done',
    lines, subtotal: sub, discount: disc, total, paid: data ? Number(data.paid) : Math.min(paid, total), due: data ? Number(data.due) || 0 : Math.max(0, r2(total - paid)),
    pays, vat: null, change: Number(info.change) || 0,
    cust: p.p_customer_mobile || p.p_customer_name ? { name: p.p_customer_name || '', mobile: p.p_customer_mobile || '', masked: false } : null, shares: [] };
}

// ---------- text for sharing ----------
function text(d, short) {
  const loc = wl(d.loc), lines = d.lines.map((l) => `${lineName(l)}${l.qty !== 1 || l.unit ? ` ${fmt(l.qty)}${l.unit ? ' ' + l.unit : ''} × ${fmt(l.price)}` : ''} = ${fmt(l.amount)}`);
  const head = [brandText(), loc, `${T('receipt')} ${d.receipt}${d.pending ? ' (' + T('prov') + ')' : ''} · ${d.date} ${d.time}`];
  if (short) return [...head, `${T('total')}: ${fmt(d.total)}`, d.due > 0 ? `${T('due')}: ${fmt(d.due)}` : null, T('thanks')].filter(Boolean).join('\n');
  return [...head, '—', ...lines, '—', d.discount > 0 ? `${T('discount')}: -${fmt(d.discount)}` : null,
    d.vat ? `${T('vat')} ${d.vat.rate}%${d.vat.included ? ' (' + T('incl') + ')' : ''}: ${fmt(d.vat.amount)}` : null, `${T('total')}: ${fmt(d.total)}`,
    ...d.pays.map((p) => `${lab(X['m_' + p.mode] || L(p.mode, p.mode, p.mode))}${p.wallet ? ' (' + p.wallet + ')' : ''}: ${fmt(p.amount)}`),
    d.due > 0 ? `${T('due')}: ${fmt(d.due)}` : null, d.pending ? T('prov') + ' — ' + lab(L('সার্ভারে জমা হলে চূড়ান্ত নম্বর হবে', 'final number after sync', 'final number sync এর পর')) : null, T('thanks')].filter(Boolean).join('\n');
}

// ---------- the card (what the customer would see on paper) ----------
function card(d) {
  const row = (k, v, b) => `<div class="iv92r${b ? ' iv92b' : ''}"><span>${k}</span><span>${v}</span></div>`;
  return `<div class="iv92doc" data-iv92="card">
    <div class="iv92c iv92brand">${esc(brandText())}</div>${wl(d.loc) ? `<div class="iv92c">${esc(wl(d.loc))}</div>` : ''}
    <div class="iv92c">${esc(T('receipt'))} <b>${esc(d.receipt)}</b>${d.pending ? ` <span class="iv92tag">${esc(T('prov'))}</span>` : ''}</div>
    <div class="iv92c iv92m">${esc(d.date)} ${esc(d.time)}${d.cashier ? ' · ' + esc(d.cashier) : ''}${d.cust && d.cust.name ? ' · ' + esc(d.cust.name) : ''}</div>
    ${d.status === 'void' ? `<div class="iv92c iv92tag iv92void">${esc(T('voided'))}</div>` : ''}
    <div class="iv92hr"></div>
    ${d.lines.map((l) => `<div class="iv92l"><div>${esc(lineName(l))}</div><div class="iv92r iv92m"><span>${fmt(l.qty)}${l.unit ? ' ' + esc(l.unit) : ''} × ${fmt(l.price)}</span><b>${fmt(l.amount)}</b></div></div>`).join('')}
    <div class="iv92hr"></div>
    ${d.discount > 0 ? row(esc(T('subtotal')), fmt(d.subtotal)) + row(esc(T('discount')), '− ' + fmt(d.discount)) : ''}
    ${d.vat ? row(`${esc(T('vat'))} ${esc(d.vat.rate)}%${d.vat.included ? ' (' + esc(T('incl')) + ')' : ''}`, fmt(d.vat.amount)) : ''}
    ${row(esc(T('total')), money(d.total), true)}
    ${d.pays.map((p) => row(`${modeName(p.mode)}${p.wallet ? ' · ' + esc(p.wallet) : ''}`, fmt(p.amount))).join('')}
    ${d.change > 0 ? row(esc(T('change')), fmt(d.change)) : ''}
    ${d.due > 0 ? row(esc(T('due')), money(d.due), true) : ''}
    <div class="iv92hr"></div><div class="iv92c">${esc(T('thanks'))}</div></div>`;
}
const CSS = `.iv92doc{background:#fff;color:#000;border:1px solid #bbb;border-radius:10px;padding:12px;max-width:100%;box-sizing:border-box;font-size:.92rem;line-height:1.35;word-break:break-word}
.iv92c{text-align:center}.iv92brand{font-weight:700;font-size:1.15em}.iv92m{font-size:.85em;color:#444}.iv92hr{border-top:1px dashed #000;margin:7px 0}
.iv92r{display:flex;justify-content:space-between;gap:10px}.iv92b{font-weight:700;font-size:1.1em}.iv92l{margin:3px 0}
.iv92tag{display:inline-block;border:1px solid #b45309;color:#b45309;border-radius:6px;padding:0 6px;font-size:.8em;font-weight:700}.iv92void{border-color:#b91c1c;color:#b91c1c;margin:4px auto}
.iv92bar{position:fixed;left:12px;right:12px;bottom:calc(86px + env(safe-area-inset-bottom));z-index:19;max-width:616px;margin:0 auto;display:flex;gap:10px;align-items:center;padding:10px 12px;border-radius:14px;background:var(--card,#fff);box-shadow:0 4px 18px rgba(0,0,0,.25)}
.iv92bar button{min-height:44px}.iv92btns{display:grid;grid-template-columns:1fr 1fr;gap:8px}.iv92btns button{min-height:46px;margin:0}`;
(() => { try { const st = document.createElement('style'); st.id = 'iv92_css'; st.textContent = CSS; document.head.appendChild(st); } catch (e) { /* no DOM */ } })();

// ---------- the sheet ----------
function sheetHtml() {
  const d = V.d;
  if (!d) return `<h2>${esc(T('title'))}</h2>${V.err ? `<div class="notice bad">${esc(T('loadFail'))}</div><button class="full" data-act="iv92_retry">${esc(T('retry'))}</button>` : `<p class="muted center">${esc(T('loading'))}</p>`}<button class="full" data-act="closesheet">${esc(T('close'))}</button>`;
  const mobile = d.cust && d.cust.mobile ? d.cust.mobile : '';
  return `<h2>${esc(T('title'))} · ${esc(d.receipt)}</h2>
    <div id="iv92_pend">${d.pending ? `<div class="notice warn">${esc(T('pending'))}</div><button class="full" data-act="iv92_check">${esc(T('check'))}</button>` : ''}</div>
    <div id="iv92_card">${card(d)}</div>
    <div class="stack" style="margin-top:12px">
      <button class="primary full" data-act="iv92_print">${esc(T('print'))}</button>
      <div id="iv92_np" role="status">${V.noPrint ? `<div class="notice warn">${esc(T('noPrinter'))}</div>` : `<div class="muted" style="font-size:.85rem">${esc(T('printHint'))}</div>`}</div>
      <label for="iv92_phone">${esc(T('phone'))}</label>
      <input id="iv92_phone" type="tel" inputmode="tel" autocomplete="off" value="${esc(mobile)}" placeholder="01XXXXXXXXX">
      ${d.cust && d.cust.masked && !mobile ? `<div class="muted" style="font-size:.85rem">${esc(T('masked'))}</div>` : ''}
      <div class="iv92btns"><button data-act="iv92_sms">${esc(T('sms'))}</button><button data-act="iv92_wa">${esc(T('wa'))}</button></div>
      <label for="iv92_email">${esc(T('mail'))}</label>
      <input id="iv92_email" type="email" inputmode="email" autocomplete="off" value="" placeholder="name@example.com">
      <button class="full" data-act="iv92_email">${esc(T('email'))}</button>
      <div class="iv92btns" style="grid-template-columns:1fr 1fr 1fr"><button data-act="iv92_share">${esc(T('share'))}</button><button data-act="iv92_copy">${esc(T('copy'))}</button><button data-act="iv92_dl">${esc(T('dl'))}</button></div>
      <div class="muted" style="font-size:.85rem">${esc(T('sendNote'))}</div>
      ${d.shares && d.shares.length ? `<div class="muted" style="font-size:.85rem">${esc(T('sharedBy'))}: ${d.shares.length}</div>` : ''}
      <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`;
}
function draw() { openSheet(sheetHtml()); }
function redrawKeepInputs() {   // refresh the card + notes without losing what was typed in the number / email boxes
  const ph = $('#iv92_phone'), em = $('#iv92_email'); const keep = { ph: ph && ph.value, em: em && em.value };
  if (!ph) return draw();
  const c = $('#iv92_card'), pe = $('#iv92_pend'); if (c) c.innerHTML = card(V.d); if (pe) pe.innerHTML = V.d.pending ? `<div class="notice warn">${esc(T('pending'))}</div><button class="full" data-act="iv92_check">${esc(T('check'))}</button>` : '';
  if (keep.ph === '' && V.d.cust && V.d.cust.mobile) ph.value = V.d.cust.mobile;
}

// ---------- opening ----------
async function fetchServer(args) {
  const r = await sb.rpc('invoice_data92', args);
  if (r.error || !r.data || !r.data.id) throw new Error((r.error && r.error.message) || 'none');
  return fromServer(r.data);
}
async function openSale(id) {   // from today's list / history
  const tok = ++V.tok; V.d = null; V.err = false; V.noPrint = false; tplReady(); draw();
  try { const d = await fetchServer({ p_sale: id }); if (tok !== V.tok) return; V.d = d; draw(); flushShares(); }
  catch (e) { if (tok !== V.tok) return; V.err = true; V.retryId = id; draw(); }
}
async function openInfo(info) {   // right after a sale: draw at once from the cart, then replace by the server copy
  const tok = ++V.tok; V.d = fromPayload(info); V.err = false; V.noPrint = false; V.last = info; tplReady(); draw();
  if (V.d.pending) return;
  try { const d = await fetchServer({ p_sale: info.data.id }); if (tok !== V.tok || !$('#iv92_card')) return; d.change = V.d.change; V.d = d; redrawKeepInputs(); } catch (e) { /* the local copy stays (old database or no net) */ }
  flushShares();
}
function removeOldOffer() { const o = document.getElementById('iv_offer'); if (o) o.remove(); }
function bar(info) {
  const old = document.getElementById('iv92_bar'); if (old) old.remove(); removeOldOffer(); V.last = info;
  const el = document.createElement('div'); el.id = 'iv92_bar'; el.className = 'iv92bar'; el.setAttribute('role', 'status');
  el.innerHTML = `<button class="primary" data-act="iv92_show" style="flex:1">${esc(T('show'))}</button><button data-act="iv92_barx" aria-label="${esc(T('close'))}">✕</button>`;
  document.body.appendChild(el); setTimeout(() => { const e = document.getElementById('iv92_bar'); if (e === el) el.remove(); }, 30000);
}
// called by pos.js right after a sale was recorded (info.data) or queued (info.pending); never throws
function afterSale(info) {
  try {
    const m = mode(); if (m === 'never' || !info || !info.p) return false;
    if (m === 'always') { removeOldOffer(); openInfo(info); return true; }
    bar(info); return true;
  } catch (e) { return false; }
}

// ---------- the actions ----------
function go(url, blank) {
  const a = document.createElement('a'); a.href = url; if (blank) { a.target = '_blank'; a.rel = 'noopener'; } a.style.display = 'none'; document.body.appendChild(a); a.click(); a.remove();
}
function logShare(channel) {
  const d = V.d; if (!d) return;
  const rec = d.id ? { p_sale: d.id, p_channel: channel } : d.client_id ? { p_client: d.client_id, p_channel: channel } : null; if (!rec) return;
  if (d.pending) return queueShare(rec);
  try { Promise.resolve(sb.rpc('invoice_share_log92', rec)).then((r) => { if (r && r.error && /fetch|network|offline|load failed/i.test(r.error.message || '')) queueShare(rec); }).catch(() => queueShare(rec)); } catch (e) { queueShare(rec); }
}
const jget = (k, dft) => { try { const v = JSON.parse(store.get(k)); return v == null ? dft : v; } catch (e) { return dft; } };
function queueShare(rec) { try { const q = jget(SHARE_Q, []); q.push(rec); store.set(SHARE_Q, JSON.stringify(q.slice(-50))); } catch (e) { /* ignore */ } }
async function flushShares() {   // log entries made while the sale was pending or the phone was offline
  const q = jget(SHARE_Q, []); if (!q.length) return; const left = [];
  for (const rec of q) { try { const r = await sb.rpc('invoice_share_log92', rec); if (r && r.error && /fetch|network|offline|load failed/i.test(r.error.message || '')) left.push(rec); } catch (e) { left.push(rec); } }
  try { store.set(SHARE_Q, JSON.stringify(left)); } catch (e) { /* ignore */ }
}
const need = () => !!V.d;

function toDoc(d) {   // the shape B.invoice.renderDoc draws
  return { loc: wl(d.loc), receipt: d.receipt, date: d.date, time: d.time, cashier: d.cashier, customer: d.cust ? (d.cust.name + (d.cust.mobile ? ' · ' + d.cust.mobile : '')).trim() : '',
    lines: d.lines.map((l) => ({ code: l.code, name: lineName(l), qty: l.qty, unit: l.unit, price: l.price, amount: l.amount })), subtotal: d.subtotal, discount: d.discount, total: d.total,
    pays: d.pays.map((p) => ({ mode: p.mode, amount: p.amount })), due: d.due };
}
// bos98: template system hooks. Every one is guarded: no B.tpl, no owner choice, or any error -> today's output, unchanged. No cost field ever goes in (the card has none).
function tplReady() { try { if (B.tpl && B.tpl.ensure) B.tpl.ensure(sb); } catch (e) { /* offline-safe: nothing */ } }
function tplOpts(d) { return { lang: S.lang, loc: d.loc_id, shop: { name: brandText() } }; }
function tplRecvData(d) {   // pos_receipt data: customer-facing numbers only
  return { no: d.receipt, date: d.date + ' ' + d.time, cashier: d.cashier, location: wl(d.loc), customer: d.cust ? { name: d.cust.name, phone: d.cust.mobile || '' } : null,
    items: d.lines.map((l) => ({ name: lineName(l), qty: l.qty, price: l.price, amount: l.amount })), subtotal: d.subtotal, discount: d.discount, vat: d.vat ? d.vat.amount : 0, total: d.total, paid: d.paid, change: d.change, due: d.due };
}
function tplMsg(d, channel) {   // msg_invoice text for sms / whatsapp / email, or null (nothing chosen)
  try {
    if (!B.tpl || !B.tpl.render) return null;
    const t = B.tpl.render('msg_invoice', { customer: d.cust ? d.cust.name : '', no: d.receipt, date: d.date, total: d.total, paid: d.paid, due: d.due, shop: { name: brandText() },
      items: d.lines.map((l) => ({ name: lineName(l), qty: l.qty, amount: l.amount })) }, undefined, { lang: S.lang, loc: d.loc_id, channel });
    return typeof t === 'string' && t ? t : null;
  } catch (e) { return null; }
}
function tplPage(d) {   // the full printable document of the chosen receipt template, or null
  try { return B.tpl && B.tpl.printHTML ? B.tpl.printHTML('pos_receipt', tplRecvData(d), undefined, tplOpts(d)) : null; } catch (e) { return null; }
}
async function doPrint() {
  if (!need()) return; const d = V.d;
  logShare('print');
  if (B.tpl && B.tpl.ensure && typeof window.print === 'function') {   // bos98
    try { await B.tpl.ensure(sb); if (tplPage(d) && B.tpl.print('pos_receipt', tplRecvData(d), undefined, tplOpts(d))) return; } catch (e) { /* keep today's print path */ }
  }
  const iv = B.invoice;
  if (!iv || !iv.renderDoc || !iv.printHtml || typeof window.print !== 'function') return noPrinter();
  try {
    const tpl = await iv.templateFor(d.loc_id), th = tpl.kind === 'thermal58' || tpl.kind === 'thermal80';
    iv.printHtml(iv.renderDoc(tpl, toDoc(d), S.lang), Number(tpl.paper_width_mm) || (th ? 80 : 210), th);
  } catch (e) { noPrinter(); }
}
function noPrinter() { V.noPrint = true; const el = $('#iv92_np'); if (el) el.innerHTML = `<div class="notice warn">${esc(T('noPrinter'))}</div>`; }

function phoneNum() { const v = ($('#iv92_phone') || {}).value || ''; const n = intlNumber(v); if (!n) { toast(T('needPhone')); return null; } return n; }
function doSms() { if (!need()) return; const n = phoneNum(); if (!n) return; const ios = /iPhone|iPad|iPod/i.test((window.navigator && window.navigator.userAgent) || '');
  logShare('sms'); go(`sms:+${n}${ios ? '&' : '?'}body=${encodeURIComponent((B.tpl && tplMsg(V.d, 'sms')) || text(V.d, true))}`); toast(T('opened')); }   // bos98: chosen sms template, else today's text
function doWa() { if (!need()) return; const n = phoneNum(); if (!n) return; logShare('whatsapp'); const wm = B.tpl && B.tpl.waUrl ? tplMsg(V.d, 'whatsapp') : null;   // bos98
  go(wm ? B.tpl.waUrl(wm).replace('https://wa.me/?', `https://wa.me/${n}?`) : `https://wa.me/${n}?text=${encodeURIComponent(text(V.d))}`, true); toast(T('opened')); }
function doEmail() { if (!need()) return; const e = (($('#iv92_email') || {}).value || '').trim(); if (!okMail(e)) return toast(T('needMail'));
  logShare('email'); let sj = `${brandText()} · ${T('receipt')} ${V.d.receipt}`, bd = text(V.d);
  { const tm = B.tpl && tplMsg(V.d, 'email'), m = tm && /^Subject: ([^\n]*)\n\n([\s\S]*)$/.exec(tm); if (m) { sj = m[1]; bd = m[2]; } }   // bos98
  go(`mailto:${e}?subject=${encodeURIComponent(sj)}&body=${encodeURIComponent(bd)}`); toast(T('opened')); }
async function copyText(txt) {
  try { if (navigator.clipboard && navigator.clipboard.writeText) { await navigator.clipboard.writeText(txt); return true; } } catch (e) { /* fall through */ }
  try { const ta = document.createElement('textarea'); ta.value = txt; ta.style.cssText = 'position:fixed;left:-9999px'; document.body.appendChild(ta); ta.select(); const ok = document.execCommand && document.execCommand('copy'); ta.remove(); return !!ok; } catch (e) { return false; }
}
async function doCopy() { if (!need()) return; logShare('copy'); toast((await copyText(text(V.d))) ? T('copied') : T('shareFail')); }
async function doShare() {
  if (!need()) return; const txt = text(V.d);
  try {
    if (navigator.share) { await navigator.share({ title: `${T('receipt')} ${V.d.receipt}`, text: txt }); logShare('share'); return; }
  } catch (e) { if (e && e.name === 'AbortError') return; }   // the person closed the share window: not an error
  const ok = await copyText(txt); if (ok) { logShare('copy'); toast(T('copied')); } else toast(T('shareFail'));
}
function fileHtml(d) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(T('receipt'))} ${esc(d.receipt)}</title><style>body{font-family:system-ui,sans-serif;margin:0;padding:12px;background:#fff}.iv92doc{max-width:420px;margin:0 auto}${CSS}@media print{.iv92doc{border:0}}</style></head><body>${card(d)}</body></html>`;
}
function doDl() {
  if (!need()) return; const d = V.d;
  try {
    const blob = new Blob([(B.tpl && tplPage(d)) || fileHtml(d)], { type: 'text/html' }),   /* bos98 */ url = URL.createObjectURL(blob), a = document.createElement('a');
    a.href = url; a.download = `invoice-${String(d.receipt).replace(/[^A-Za-z0-9_-]/g, '_')}.html`; a.style.display = 'none'; document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000); logShare('download'); toast(T('dlDone'));
  } catch (e) { toast(T('shareFail')); }
}
async function doCheck() {   // a queued sale: has it reached the server yet?
  const d = V.d; if (!d || !d.client_id) return;
  try { const nd = await fetchServer({ p_client: d.client_id }); nd.change = d.change; V.d = nd; redrawKeepInputs(); toast(T('synced')); flushShares(); }
  catch (e) { toast(T('stillPending')); }
}

// ---------- handlers ----------
Object.assign(A.H, {
  iv92_open: (a) => openSale(a.dataset.v),
  iv92_show: () => { const b = document.getElementById('iv92_bar'); if (b) b.remove(); if (V.last) openInfo(V.last); },
  iv92_barx: () => { const b = document.getElementById('iv92_bar'); if (b) b.remove(); },
  iv92_retry: () => { if (V.retryId) openSale(V.retryId); },
  iv92_print: () => doPrint(), iv92_sms: () => doSms(), iv92_wa: () => doWa(), iv92_email: () => doEmail(),
  iv92_share: () => doShare(), iv92_copy: () => doCopy(), iv92_dl: () => doDl(), iv92_check: () => doCheck(),
});

// ---------- a small page: today's / any day's invoices, to view or send again (#/invoiceview) ----------
const PG = { day: '' };
X.pgTitle = L('ইনভয়েস দেখুন ও পাঠান', 'View and send invoices', 'Invoice দেখুন ও পাঠান');
X.pgIntro = L('একটি তারিখের বিক্রি — যেটায় চাপবেন সেটার ইনভয়েস খুলবে, সেখান থেকে Print, Email, SMS, WhatsApp।', 'The sales of one day. Tap one to open its invoice, with Print, Email, SMS and WhatsApp.', 'একটি তারিখের sale — যেটায় চাপবেন সেটার invoice খুলবে, সেখান থেকে Print, Email, SMS, WhatsApp।');
X.pgNone = L('এই দিনে কোনো বিক্রি নেই', 'No sales on this day', 'এই দিনে কোনো sale নেই');
async function page() {
  const d0 = PG.day || dhakaDate(new Date().toISOString());
  A.shell(T('pgTitle'), `<p class="muted">${esc(T('pgIntro'))}</p><label for="iv92_day">${esc(T('date'))}</label><input id="iv92_day" type="date" value="${esc(d0)}"><div id="iv92_list"><p class="muted center">${esc(T('loading'))}</p></div>`, true);
  await drawList(d0);
}
async function drawList(day) {
  const el = $('#iv92_list'); if (!el) return; PG.day = day;
  let rows = [];
  try { const r = await sb.from('sales').select('id,receipt,location_id,sold_at,total,status,customer,due_amount').eq('sale_date', day).order('sold_at', { ascending: false }).limit(60); rows = r.data || []; if (r.error) throw r.error; }
  catch (e) { el.innerHTML = `<div class="notice bad">${esc(T('loadFail'))}</div>`; return; }
  const locs = (B.ENV && B.ENV.locs) || [];
  el.innerHTML = rows.length ? rows.map((s) => { const l = locs.find((z) => z.id === s.location_id) || {};
    return `<div class="card item" data-act="iv92_open" data-v="${esc(s.id)}" style="${s.status === 'void' ? 'opacity:.55' : ''}"><div><div class="nm">#${esc((l.code ? l.code + '-' : '') + s.receipt)} · ${esc(dhakaTime(s.sold_at))}</div><div class="muted" style="font-size:.85rem">${s.customer ? esc(s.customer) : ''}</div></div><div class="pr"><b>${money(s.total)}</b>${s.status === 'void' ? `<div><span class="chip bad">${esc(T('voided'))}</span></div>` : Number(s.due_amount) > 0 ? `<div><span class="chip warn">${esc(T('due'))} ${money(s.due_amount)}</span></div>` : ''}</div></div>`; }).join('')
    : `<p class="muted center">${esc(T('pgNone'))}</p>`;
}
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'iv92_day' && e.target.value) drawList(e.target.value); });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { invoiceview: page });

B.invoiceview = { afterSale, openSale, openInfo, mode, text, card, fromServer, fromPayload, intlNumber, normMobile, okMail, flushShares, X, T };
})();
