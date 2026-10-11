/* Islamia BOS · Invoice & print: template designer + print settings (invoice_templates / print_profiles), live preview in a paper-width box,
   window.print with @page size from the template (thermal 58 / 80 mm, A4), barcode label sheet (inline Code128), and the receipt hook
   for the POS (B.invoice.offer / printSaleId). If no template exists a built-in simple receipt is used. Route #/invoice (owner or grant settings_invoice). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const pnum = (v) => { const s = norm(v).trim(); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const r2 = (n) => Math.round(n * 100) / 100;
const hhmm = (iso) => new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' });
const jget = (k, d) => { try { const v = JSON.parse(store.get(k)); return v == null ? d : v; } catch (e) { return d; } };

// ---------- labels ----------
const KINDS = ['thermal80', 'thermal58', 'common', 'a4', 'label'];
const KL = { common: L('সাধারণ (A4 / যেকোনো প্রিন্টার)', 'Common (A4 / any printer)', 'Common (A4 / any printer)'), a4: L('ইনভয়েস (A4)', 'Invoice (A4)', 'Invoice (A4)'), thermal58: L('থার্মাল ৫৮ মিমি', 'Thermal 58 mm', 'Thermal 58 mm'),
  thermal80: L('থার্মাল ৮০ মিমি', 'Thermal 80 mm', 'Thermal 80 mm'), label: L('বারকোড লেবেল', 'Barcode label', 'Barcode Label') };
const KW = { common: 210, a4: 210, thermal58: 58, thermal80: 80, label: 210 };
const FLAGS = { brand: L('প্রতিষ্ঠানের নাম', 'Business name', 'Business নাম'), logo: L('লোগো', 'Logo', 'Logo'), location: L('শাখার নাম', 'Branch name', 'Branch নাম'), receipt_no: L('রসিদ নম্বর', 'Receipt number', 'Receipt number'),
  datetime: L('তারিখ ও সময়', 'Date and time', 'Date ও Time'), cashier: L('বিক্রেতা', 'Cashier', 'Cashier'), customer: L('গ্রাহক', 'Customer', 'Customer'), item_code: L('আইটেম কোড', 'Item code', 'Item code'),
  unit_price: L('একক দাম', 'Unit price', 'Unit price'), discount: L('ডিসকাউন্ট', 'Discount', 'Discount'), payments: L('পেমেন্টের ধরন', 'Payment lines', 'Payment lines'), due: L('বাকি', 'Due', 'Due'), barcode: L('রসিদে বারকোড', 'Barcode on receipt', 'Receipt এ Barcode') };
const LFLAGS = { l_name: L('আইটেমের নাম', 'Item name', 'Item নাম'), l_price: L('দাম', 'Price', 'Price'), l_code: L('বারকোডের নিচে নম্বর', 'Number under the barcode', 'Barcode এর নিচে number') };
const dflFlags = (k) => (k === 'label' ? { l_name: true, l_price: true, l_code: true, label_w: 50, label_h: 30, cols: 4 }
  : { brand: true, logo: k !== 'thermal58', location: true, receipt_no: true, datetime: true, cashier: true, customer: true, item_code: k === 'a4', unit_price: true, discount: true, payments: true, due: true, barcode: false });
const X = {
  title: L('ইনভয়েস ও প্রিন্ট', 'Invoice & print', 'Invoice ও Print'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), edit: L('বদলান', 'Edit', 'Edit'), del: L('মুছুন', 'Delete', 'Delete'), add: L('＋ নতুন', '＋ New', '＋ New'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), need: L('তথ্য লাগবে', 'Data needed', 'Data লাগবে'), back: L('সব টেমপ্লেট', 'All templates', 'সব Template'),
  noacc: L('এই পাতা দেখতে ইনভয়েস-সেটিংসের অনুমতি লাগবে।', 'The invoice-settings permission is needed for this page.', 'এই page এর জন্য Invoice-settings permission লাগবে।'),
  sql: L('এই অংশ চালু করতে নতুন SQL চালাতে হবে।', 'The new SQL must be run to switch this part on.', 'এই অংশ চালু করতে নতুন SQL চালাতে হবে।'),
  dev: L('এই ডিভাইস', 'This device', 'এই Device'), devName: L('ডিভাইসের নাম', 'Device name', 'Device নাম'), devKind: L('এই ডিভাইসে রসিদ ছাপা হবে', 'Receipts on this device print as', 'এই Device এ Receipt print হবে'), devOffer: L('বিক্রির পর "রসিদ প্রিন্ট" বোতাম দেখান', 'Show a "Print receipt" button after a sale', 'Sale এর পর "Receipt Print" button দেখান'),
  tplEmpty: L('তথ্য লাগবে — এই ধরনের কোনো টেমপ্লেট নেই। না থাকলে সাধারণ সরল রসিদ ছাপা হয়।', 'Data needed — no template of this kind. Without one a simple built-in receipt prints.', 'Data লাগবে — এই ধরনের কোনো template নেই। না থাকলে simple built-in receipt print হয়।'),
  def: L('ডিফল্ট', 'default', 'default'), allLoc: L('সব শাখা', 'All branches', 'সব Branch'), inactive: L('বন্ধ', 'off', 'off'), labels: L('বারকোড লেবেল ছাপুন', 'Print barcode labels', 'Barcode Label Print'),
  profiles: L('প্রিন্ট প্রোফাইল (ডিভাইস অনুযায়ী)', 'Print profiles (per device)', 'Print Profile (Device অনুযায়ী)'), profEmpty: L('তথ্য লাগবে — কোনো প্রোফাইল নেই', 'Data needed — no profile yet', 'Data লাগবে — কোনো profile নেই'),
  p_name: L('নাম', 'Name', 'Name'), p_type: L('প্রিন্টারের ধরন', 'Printer type', 'Printer type'), p_size: L('কাগজ (যেমন A4, 58mm, 80mm)', 'Paper (e.g. A4, 58mm, 80mm)', 'Paper (যেমন A4, 58mm, 80mm)'), p_w: L('প্রস্থ (মিমি)', 'Width (mm)', 'Width (mm)'), p_tpl: L('টেমপ্লেট', 'Template', 'Template'), p_dev: L('ডিভাইসের নাম (খালি = সব)', 'Device name (empty = any)', 'Device নাম (খালি = সব)'), p_loc: L('শাখা', 'Branch', 'Branch'),
  // editor
  e_name: L('টেমপ্লেটের নাম', 'Template name', 'Template নাম'), e_kind: L('ধরন', 'Kind', 'Kind'), e_loc: L('কোন শাখায় ডিফল্ট', 'Default for branch', 'কোন Branch এর default'), e_default: L('এই ধরনের ডিফল্ট', 'Default of this kind', 'এই Kind এর default'), e_active: L('চালু', 'Active', 'Active'),
  e_head: L('উপরের লেখা', 'Header text', 'Header text'), e_foot: L('নিচের লেখা', 'Footer text', 'Footer text'), e_logo: L('লোগো (লিংক বা ফাইল)', 'Logo (link or file)', 'Logo (link বা file)'), e_logoFile: L('ফাইল বাছুন', 'Choose a file', 'File বাছুন'), e_logoBrand: L('প্রতিষ্ঠানের লোগো', 'Brand logo', 'Brand logo'), e_logoNone: L('লোগো সরান', 'Remove logo', 'Logo সরান'),
  e_show: L('কী কী দেখাবে', 'What to show', 'কী কী দেখাবে'), e_vat: L('ভ্যাট লাইন', 'VAT line', 'VAT line'), e_vatOff: L('ভ্যাট সেটিংসে বন্ধ — এখানে চালু করলেও ছাপা হবে না', 'VAT is off in settings — it will not print even if on here', 'VAT Settings এ Off — এখানে On করলেও print হবে না'), e_vatRate: L('ভ্যাটের হার বসানো নেই — তথ্য লাগবে', 'VAT rate not set — data needed', 'VAT হার বসানো নেই — Data লাগবে'),
  e_paper: L('কাগজ', 'Paper', 'Paper'), e_w: L('প্রস্থ (মিমি)', 'Width (mm)', 'Width (mm)'), e_fs: L('লেখার মাপ (গুণক)', 'Font scale', 'Font scale'), e_m: L('মার্জিন (মিমি)', 'Margins (mm)', 'Margins (mm)'), m_top: L('উপর', 'Top', 'Top'), m_right: L('ডান', 'Right', 'Right'), m_bottom: L('নিচ', 'Bottom', 'Bottom'), m_left: L('বাম', 'Left', 'Left'),
  e_lw: L('লেবেলের প্রস্থ (মিমি)', 'Label width (mm)', 'Label width (mm)'), e_lh: L('লেবেলের উচ্চতা (মিমি)', 'Label height (mm)', 'Label height (mm)'), e_cols: L('এক সারিতে লেবেল', 'Labels per row', 'Labels per row'),
  e_prev: L('প্রিভিউ', 'Preview', 'Preview'), e_print: L('টেস্ট প্রিন্ট', 'Test print', 'Test print'), e_badw: L('প্রস্থ, মার্জিন ও মাপ ঠিক সংখ্যা হতে হবে', 'Width, margins and scale must be valid numbers', 'Width, margin ও scale ঠিক সংখ্যা হতে হবে'), e_needname: L('টেমপ্লেটের নাম লিখুন', 'Enter the template name', 'Template নাম লিখুন'),
  e_hint: L('ভাষা অনুযায়ী আলাদা লেখা দেওয়া যায়; ফাঁকা থাকলে বাংলা লেখা ব্যবহার হবে।', 'Text can differ per language; an empty one falls back to Bangla.', 'Language অনুযায়ী আলাদা text দেওয়া যায়; ফাঁকা থাকলে বাংলা use হবে।'),
  // labels page
  lb_tpl: L('লেবেল টেমপ্লেট', 'Label template', 'Label template'), lb_items: L('আইটেম বাছুন', 'Choose items', 'Item বাছুন'), lb_copies: L('প্রতিটির কপি', 'Copies each', 'Copies each'), lb_search: L('আইটেম খুঁজুন', 'Search item', 'Item খুঁজুন'), lb_none: L('অন্তত একটি আইটেম বাছুন', 'Choose at least one item', 'অন্তত একটি item বাছুন'), lb_sel: L('বাছাই করা', 'selected', 'selected'),
  // document words
  d_receipt: L('রসিদ', 'Receipt', 'Receipt'), d_invoice: L('ইনভয়েস', 'Invoice', 'Invoice'), d_date: L('তারিখ', 'Date', 'Date'), d_cashier: L('বিক্রেতা', 'Cashier', 'Cashier'), d_customer: L('গ্রাহক', 'Customer', 'Customer'), d_item: L('আইটেম', 'Item', 'Item'), d_qty: L('পরিমাণ', 'Qty', 'Qty'), d_price: L('দাম', 'Price', 'Price'), d_amount: L('টাকা', 'Amount', 'Amount'),
  d_sub: L('মোট (ছাড়ের আগে)', 'Subtotal', 'Subtotal'), d_disc: L('ডিসকাউন্ট', 'Discount', 'Discount'), d_total: L('সর্বমোট', 'Total', 'Total'), d_due: L('বাকি', 'Due', 'Due'), d_vat: L('ভ্যাট', 'VAT', 'VAT'), d_incl: L('অন্তর্ভুক্ত', 'included', 'included'), d_thanks: L('ধন্যবাদ', 'Thank you', 'ধন্যবাদ'),
  m_cash: L('নগদ', 'Cash', 'Cash'), m_mobile: L('মোবাইল', 'Mobile', 'Mobile'), m_card: L('কার্ড', 'Card', 'Card'),
  // offer
  o_print: L('রসিদ প্রিন্ট', 'Print receipt', 'Receipt Print'), o_close: L('বন্ধ', 'Close', 'Close'), o_fail: L('রসিদ খোলা যায়নি', 'The receipt could not be loaded', 'Receipt load হয়নি'),
};
const T = (k) => lab(X[k]);
const wl = (o, lang) => (!o ? '' : lang === 'en' ? o.en || o.bn : lang === 'mix' ? o.mix || o.bn : o.bn || o.en);   // a label in a chosen language
const BRAND = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };

// ---------- Code128 (subset B), inline ----------
const C128 = ['212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213', '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132', '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211', '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313', '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331', '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111', '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214', '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111', '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141', '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141', '114131', '311141', '411131', '211412', '211214', '211232', '2331112'];
function code128(text) {
  const s = String(text ?? '').replace(/[^\x20-\x7e]/g, '?') || ' ';
  const codes = [104]; let sum = 104;
  [...s].forEach((c, i) => { const v = c.charCodeAt(0) - 32; codes.push(v); sum += v * (i + 1); });
  codes.push(sum % 103, 106);
  return codes.map((c) => C128[c]).join('');
}
function barcodeSvg(text, h = 40) {
  const pat = code128(text); let x = 10, bars = '';   // 10 modules of quiet zone each side
  [...pat].forEach((d, i) => { const w = Number(d); if (i % 2 === 0) bars += `<rect x="${x}" y="0" width="${w}" height="${h}"/>`; x += w; });
  return `<svg class="ivbc" viewBox="0 0 ${x + 10} ${h}" preserveAspectRatio="none" role="img" aria-label="${esc(text)}" fill="#000" shape-rendering="crispEdges">${bars}</svg>`;
}

// ---------- document rendering ----------
const SAMPLE = { loc: { bn: 'ইসলামিয়া মিষ্টি ঘর — প্রধান শাখা', en: 'Islamiya Misty Ghar — Main branch' }, receipt: 'M-1042', date: '2026-10-11', time: '18:42', cashier: 'karim02', customer: 'Rafiq · 01711111111',
  lines: [{ code: 'S-01', name: { bn: 'রসগোল্লা', en: 'Rasgolla' }, qty: 1.5, unit: 'kg', price: 520, amount: 780 }, { code: 'S-14', name: { bn: 'সন্দেশ', en: 'Sandesh' }, qty: 0.5, unit: 'kg', price: 640, amount: 320 }, { code: 'D-02', name: { bn: 'মিষ্টি দই', en: 'Sweet doi' }, qty: 2, unit: 'pc', price: 90, amount: 180 }],
  subtotal: 1280, discount: 80, total: 1200, pays: [{ mode: 'cash', amount: 1000 }, { mode: 'mobile', amount: 100 }], due: 100 };
function vatInfo(tpl, total) {
  if (!(tpl.vat_line_on && B.rule('vat_on', false) === true)) return null;
  const rate = B.rule('vat_rate', null); if (rate === null || !(rate >= 0)) return null;
  return { rate, amount: r2(total * rate / (100 + rate)) };
}
function renderDoc(tpl, d, lang) {
  const fl = tpl.show_flags || {}, m = tpl.margins || {}, w = Number(tpl.paper_width_mm) || KW[tpl.kind] || 80, th = tpl.kind === 'thermal58' || tpl.kind === 'thermal80';
  const fs = (th ? 11.5 : 13) * (Number(tpl.font_scale) || 1), l = (k) => esc(wl(X[k], lang)), txt = (o) => esc((o && (lang === 'en' ? o.en || o.bn : lang === 'mix' ? o.mix || o.bn : o.bn || o.en)) || '');
  const nmOf = (n) => (typeof n === 'string' ? n : wl(n, lang));
  const money = (n) => fmt(r2(n));
  const va = vatInfo(tpl, d.total), invoice = tpl.kind === 'a4';
  const head = txt(tpl.header), foot = txt(tpl.footer);
  const metaRows = [fl.receipt_no !== false ? `${l(invoice ? 'd_invoice' : 'd_receipt')} ${esc(d.receipt)}` : '', fl.datetime !== false ? `${esc(d.date)} ${esc(d.time)}` : '', fl.cashier !== false && d.cashier ? `${l('d_cashier')}: ${esc(d.cashier)}` : '', fl.customer !== false && d.customer ? `${l('d_customer')}: ${esc(d.customer)}` : ''].filter(Boolean);
  const showCode = !!fl.item_code, showPrice = fl.unit_price !== false;
  const lines = th
    ? d.lines.map((x) => `<div class="ivl"><div>${showCode && x.code ? esc(x.code) + ' ' : ''}${esc(nmOf(x.name))}</div><div class="ivr"><span>${showPrice ? `${fmt(x.qty)}${x.unit ? ' ' + esc(x.unit) : ''} × ${money(x.price)}` : fmt(x.qty)}</span><b>${money(x.amount)}</b></div></div>`).join('')
    : `<table class="ivt"><thead><tr>${showCode ? `<th>#</th>` : ''}<th class="ivL">${l('d_item')}</th><th>${l('d_qty')}</th>${showPrice ? `<th>${l('d_price')}</th>` : ''}<th>${l('d_amount')}</th></tr></thead><tbody>${d.lines.map((x) => `<tr>${showCode ? `<td>${esc(x.code || '')}</td>` : ''}<td class="ivL">${esc(nmOf(x.name))}</td><td>${fmt(x.qty)}${x.unit ? ' ' + esc(x.unit) : ''}</td>${showPrice ? `<td>${money(x.price)}</td>` : ''}<td>${money(x.amount)}</td></tr>`).join('')}</tbody></table>`;
  const tot = (k, v, b) => `<div class="ivr${b ? ' ivb' : ''}"><span>${k}</span><span>${v}</span></div>`;
  const loc = typeof d.loc === 'string' ? d.loc : wl(d.loc, lang);
  return `<div class="ivdoc ${th ? 'ivth' : 'iva4'}" style="width:${w}mm;padding:${m.top ?? 4}mm ${m.right ?? 4}mm ${m.bottom ?? 4}mm ${m.left ?? 4}mm;font-size:${fs}px">
    ${fl.logo !== false && tpl.logo_ref ? `<div class="ivc"><img class="ivlogo" src="${esc(tpl.logo_ref)}" alt=""></div>` : ''}
    ${fl.brand !== false ? `<div class="ivc ivbrand">${esc(lang === 'en' ? BRAND.en : BRAND.bn)}</div>` : ''}
    ${invoice ? `<div class="ivc ivtitle">${l('d_invoice')}</div>` : ''}
    ${head ? `<div class="ivc ivtxt">${head}</div>` : ''}${fl.location !== false && loc ? `<div class="ivc">${esc(loc)}</div>` : ''}
    <div class="ivmeta">${metaRows.map((x) => `<div>${x}</div>`).join('')}</div><div class="ivhr"></div>${lines}<div class="ivhr"></div>
    ${d.discount > 0 && fl.discount !== false ? tot(l('d_sub'), money(d.subtotal)) + tot(l('d_disc'), '− ' + money(d.discount)) : ''}
    ${va ? tot(`${l('d_vat')} ${va.rate}% (${l('d_incl')})`, money(va.amount)) : ''}
    ${tot(l('d_total'), '৳ ' + money(d.total), true)}
    ${fl.payments !== false ? d.pays.map((p) => tot(esc(wl(X['m_' + p.mode], lang) || p.mode), money(p.amount))).join('') : ''}
    ${fl.due !== false && d.due > 0 ? tot(l('d_due'), '৳ ' + money(d.due), true) : ''}
    ${fl.barcode ? `<div class="ivc ivbcw">${barcodeSvg(d.receipt, 36)}<div class="ivcode">${esc(d.receipt)}</div></div>` : ''}
    <div class="ivhr"></div>${foot ? `<div class="ivc ivtxt">${foot}</div>` : ''}<div class="ivc">${l('d_thanks')}</div></div>`;
}
function renderLabels(tpl, items, lang) {
  const fl = tpl.show_flags || {}, m = tpl.margins || {}, w = Number(tpl.paper_width_mm) || 210, lw = Number(fl.label_w) || 50, lh = Number(fl.label_h) || 30, cols = Math.max(1, Math.floor(Number(fl.cols) || 4));
  const fs = 10 * (Number(tpl.font_scale) || 1);
  return `<div class="ivdoc ivlabels" style="width:${w}mm;padding:${m.top ?? 5}mm ${m.right ?? 5}mm ${m.bottom ?? 5}mm ${m.left ?? 5}mm;font-size:${fs}px"><div style="display:grid;grid-template-columns:repeat(${cols},${lw}mm);gap:0">
    ${items.map((it) => `<div class="ivlab" style="width:${lw}mm;height:${lh}mm">${fl.l_name !== false ? `<div class="ivln">${esc(it.name)}</div>` : ''}<div class="ivlb">${barcodeSvg(it.barcode, 30)}</div>${fl.l_code !== false ? `<div class="ivcode">${esc(it.barcode)}</div>` : ''}${fl.l_price !== false && it.price !== null && it.price !== undefined ? `<div class="ivlp">৳ ${fmt(it.price)}</div>` : ''}</div>`).join('')}</div></div>`;
}
const CSS = `.ivdoc{background:#fff;color:#000;box-sizing:border-box;font-family:"Hind Siliguri","Anek Bangla",system-ui,sans-serif;line-height:1.35;overflow:hidden}
.ivdoc .ivc{text-align:center}.ivdoc .ivbrand{font-weight:700;font-size:1.25em}.ivdoc .ivtitle{font-weight:700;font-size:1.5em;letter-spacing:.04em;margin:2mm 0}.ivdoc .ivtxt{white-space:pre-wrap}
.ivdoc .ivlogo{max-height:16mm;max-width:60%;object-fit:contain}.ivdoc .ivmeta{margin:1.5mm 0}.ivdoc .ivhr{border-top:1px dashed #000;margin:1.5mm 0}
.ivdoc .ivr{display:flex;justify-content:space-between;gap:3mm}.ivdoc .ivb{font-weight:700;font-size:1.1em}.ivdoc .ivl{margin:.6mm 0}
.ivdoc .ivt{width:100%;border-collapse:collapse}.ivdoc .ivt th,.ivdoc .ivt td{border-bottom:1px solid #999;padding:1mm 1.5mm;text-align:right}.ivdoc .ivt .ivL{text-align:left}
.ivdoc .ivbcw{margin-top:2mm}.ivdoc .ivbc{width:80%;height:11mm;display:block;margin:0 auto}.ivdoc .ivcode{font:600 .85em monospace;text-align:center}
.ivdoc.ivlabels{font-family:system-ui,sans-serif}.ivdoc .ivlab{box-sizing:border-box;padding:1.2mm 1.5mm;overflow:hidden;text-align:center;border:.1mm dotted #bbb;page-break-inside:avoid;break-inside:avoid}
.ivdoc .ivln{font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.ivdoc .ivlb .ivbc{width:100%;height:9mm}.ivdoc .ivlp{font-weight:700}
.iv-pvw{border:1px solid var(--line);border-radius:12px;background:#d9d2c3;padding:10px;overflow:hidden}.iv-pvi{transform-origin:top left;box-shadow:0 2px 10px rgba(0,0,0,.25);width:max-content}
.iv-offer{position:fixed;left:12px;right:12px;bottom:calc(86px + env(safe-area-inset-bottom));z-index:19;max-width:616px;margin:0 auto;display:flex;gap:10px;align-items:center;justify-content:space-between;padding:10px 12px;border-radius:14px;background:var(--card);border:1px solid var(--gold);box-shadow:var(--shadow)}
.iv-offer button{min-height:44px}.ivflags{display:flex;flex-wrap:wrap;gap:8px}.ivfs{display:flex;gap:6px;align-items:center}.ivfs input{text-align:center}
.iv-two{display:grid;grid-template-columns:1fr 1fr;gap:10px}`;
(() => { const st = document.createElement('style'); st.id = 'iv_css'; st.textContent = CSS; document.head.appendChild(st); })();

// ---------- print ----------
function cleanupPrint() { ['iv_print', 'iv_print_css'].forEach((id) => { const e = document.getElementById(id); if (e) e.remove(); }); }
function measureMm(html) {
  const m = document.createElement('div'); m.style.cssText = 'position:absolute;left:-9999px;top:0;visibility:hidden'; m.innerHTML = html; document.body.appendChild(m);
  const h = m.firstElementChild ? m.firstElementChild.getBoundingClientRect().height : 0; m.remove(); return Math.ceil(h * 25.4 / 96) + 2;
}
// print: html = rendered doc(s); w = paper width mm; thermal = height follows the content, otherwise a full sheet
function printHtml(html, w, thermal) {
  cleanupPrint();
  const h = thermal ? Math.max(40, measureMm(html)) : 297;
  const css = document.createElement('style'); css.id = 'iv_print_css';
  css.textContent = `@page{size:${w}mm ${h}mm;margin:0}@media screen{#iv_print{display:none}}@media print{html,body{margin:0!important;padding:0!important;background:#fff!important}body>*:not(#iv_print){display:none!important}#iv_print{display:block}}`;
  const box = document.createElement('div'); box.id = 'iv_print'; box.innerHTML = html;
  document.head.appendChild(css); document.body.appendChild(box);
  const imgs = [...box.querySelectorAll('img')].filter((i) => !i.complete);
  const go = () => { window.addEventListener('afterprint', cleanupPrint, { once: true }); setTimeout(cleanupPrint, 180000); window.print(); };
  if (imgs.length) { let n = imgs.length; const one = () => { if (--n <= 0) go(); }; imgs.forEach((i) => { i.addEventListener('load', one); i.addEventListener('error', one); }); setTimeout(() => { n = 0; go(); }, 1500); } else go();
}
const BUILTIN = (kind) => ({ id: null, name: 'built-in', kind, header: {}, footer: {}, show_flags: dflFlags(kind), logo_ref: null, vat_line_on: false, paper_width_mm: KW[kind] || 80, margins: { top: 4, right: 4, bottom: 4, left: 4 }, font_scale: 1, location_id: null, is_default: false, active: true });

// ---------- sale -> document ----------
async function docOfSale(id) {
  const sr = await sb.from('sales').select('*').eq('id', id).maybeSingle(); const s = sr.data; if (sr.error || !s) throw new Error('sale');
  const [pr, cu, ir] = await Promise.all([sb.from('sale_payments').select('mode,wallet,amount,voided').eq('sale_id', id), s.customer_id ? sb.from('customers').select('name,mobile').eq('id', s.customer_id).maybeSingle() : { data: null }, sb.from('items').select('id,code')]);
  await B.loadStatic();
  const loc = (B.ENV.locs || []).find((l) => l.id === s.location_id) || {}, codes = new Map(((ir && ir.data) || []).map((i) => [i.id, i.code]));
  const lines = (s.lines || []).map((x) => ({ code: x.item_id ? codes.get(x.item_id) || '' : '', name: x.name || '', qty: Number(x.qty) || 1, unit: x.unit || '', price: Number(x.price !== undefined ? x.price : x.amount), amount: Number(x.amount) }));
  return { loc: nm(loc), receipt: `${loc.code || ''}-${s.receipt}`, date: s.sale_date, time: hhmm(s.sold_at), cashier: s.created_staff || '', customer: cu.data ? `${cu.data.name} · ${cu.data.mobile}` : s.customer || '',
    lines, subtotal: lines.reduce((a, x) => a + x.amount, 0), discount: Number(s.discount) || 0, total: Number(s.total), pays: ((pr && pr.data) || []).filter((p) => !p.voided).map((p) => ({ mode: p.mode, amount: Number(p.amount) })), due: Number(s.due_amount) || 0 };
}
const devKey = () => { let k = store.get('bos_device_key'); if (!k) { k = 'dev-' + Math.random().toString(36).slice(2, 6); store.set('bos_device_key', k); } return k; };
const prefKind = () => { const k = store.get('bos_print_kind'); return KINDS.includes(k) && k !== 'label' ? k : 'thermal80'; };
async function templateFor(loc) {
  try {   // 1) a print profile of this device (and branch) that names a template
    const pr = await sb.from('print_profiles').select('*').eq('active', true);
    const mine = ((pr && pr.data) || []).filter((p) => p.template_id && (p.location_id === null || p.location_id === undefined || p.location_id === loc) && (!p.device_key || p.device_key === devKey()))
      .sort((a, b) => (b.device_key ? 2 : 0) + (b.location_id ? 1 : 0) - ((a.device_key ? 2 : 0) + (a.location_id ? 1 : 0)))[0];
    if (mine) { const tr = await sb.from('invoice_templates').select('*').eq('id', mine.template_id).maybeSingle(); if (tr.data && tr.data.active) return tr.data; }
  } catch (e) { /* fall through */ }
  try { const r = await sb.rpc('template_for', { p_kind: prefKind(), p_loc: loc }); if (r && !r.error && r.data && r.data.id) return r.data; } catch (e) { /* fall through */ }
  return BUILTIN(prefKind());   // nothing set up yet: a simple receipt still prints
}
async function printSaleId(id, loc) {
  try {
    const [d, tpl] = await Promise.all([docOfSale(id), templateFor(loc)]);
    const th = tpl.kind === 'thermal58' || tpl.kind === 'thermal80';
    printHtml(renderDoc(tpl, d, S.lang), Number(tpl.paper_width_mm) || KW[tpl.kind] || 80, th);
  } catch (e) { toast(T('o_fail')); }
}
let offerTimer = null;
function offer(id, loc) {
  if (!id || store.get('bos_print_offer') === '0') return;
  const old = document.getElementById('iv_offer'); if (old) old.remove(); clearTimeout(offerTimer);
  const el = document.createElement('div'); el.id = 'iv_offer'; el.className = 'iv-offer'; el.setAttribute('role', 'status');
  el.innerHTML = `<button class="primary" data-act="iv_offer_print" data-id="${esc(id)}" data-loc="${esc(loc ?? '')}" style="flex:1">${esc(T('o_print'))}</button><button data-act="iv_offer_close" aria-label="${esc(T('o_close'))}">✕</button>`;
  document.body.appendChild(el); offerTimer = setTimeout(() => el.remove(), 25000);
}

// ---------- pages ----------
const V = { tpls: [], profs: [], tab: null, ok: null };
const canEdit = async () => { if (S.ctx.is_owner) return true; const r = await sb.rpc('has_grant', { p_code: 'settings_invoice', p_loc: null }); return !!(r && !r.error && r.data === true); };
const locName = (id) => (id ? nm((B.ENV.locs || []).find((l) => l.id === id) || { name_bn: '#' + id }) : T('allLoc'));
const tg = (on, act, attrs = '', label) => `<button class="tog ${on ? 'on' : ''}" data-act="${act}" ${attrs} aria-pressed="${!!on}">${esc(label || (on ? T('on') : T('off')))}</button>`;
const opts = (arr, sel, blank) => (blank !== undefined ? `<option value="">${esc(blank)}</option>` : '') + arr.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(l)}</option>`).join('');
async function view() {
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  if (!S.ctx) return;
  if (!(await canEdit())) return shell(T('title'), `<div class="notice bad">${esc(T('noacc'))}</div>`, true);
  await B.loadStatic(); if (!B.ENV.rules) await B.reloadRules();
  const p = location.hash.replace(/^#\/?/, '').split('/');
  if (p[1] === 'edit' || p[1] === 'new') return editorPage(p[1] === 'edit' ? p[2] : null, p[1] === 'new' ? p[2] : null);
  if (p[1] === 'labels') return labelsPage();
  return listPage();
}
async function loadAll() {
  const [a, b] = await Promise.all([sb.from('invoice_templates').select('*').order('id'), sb.from('print_profiles').select('*').order('id')]);
  V.err = a.error; V.tpls = a.data || []; V.profs = b.data || [];
}
async function listPage() {
  await loadAll();
  if (V.err) return shell(T('title'), `<div class="notice bad">${esc(T('sql'))}</div>`, true);
  const kind = prefKind();
  const card = (x) => `<div class="card item" data-act="go" data-v="invoice/edit/${x.id}" style="cursor:pointer;${x.active ? '' : 'opacity:.55'}"><div><div class="nm">${esc(x.name)}</div><div class="muted" style="font-size:.85rem">${esc(locName(x.location_id))} · ${esc(String(x.paper_width_mm || KW[x.kind]))} mm</div></div>
    <div class="row">${x.is_default ? `<span class="chip ok">${esc(T('def'))}</span>` : ''}${x.active ? '' : `<span class="chip">${esc(T('inactive'))}</span>`}<span class="muted" style="font-size:1.3rem">›</span></div></div>`;
  shell(T('title'), `<div class="card stack"><b>${esc(T('dev'))}</b><div><label>${esc(T('devName'))}</label><div class="row"><input id="iv_dev" value="${esc(devKey())}" style="flex:1"><button data-act="iv_dev_save">${esc(T('save'))}</button></div></div>
      <div><label>${esc(T('devKind'))}</label><div class="row wrap">${['thermal80', 'thermal58', 'common', 'a4'].map((k) => tg(kind === k, 'iv_pref', `data-v="${k}"`, lab(KL[k]))).join('')}</div></div>
      <div class="row between"><span>${esc(T('devOffer'))}</span>${tg(store.get('bos_print_offer') !== '0', 'iv_offer_tog')}</div></div>
    ${KINDS.map((k) => { const l = V.tpls.filter((x) => x.kind === k); return `<div class="row between" style="margin-top:14px"><h2 style="margin:0">${esc(lab(KL[k]))}</h2><button data-act="go" data-v="invoice/new/${k}">${esc(T('add'))}</button></div>${l.map(card).join('') || `<div class="notice warn">${esc(T('tplEmpty'))}</div>`}`; }).join('')}
    <button class="full" style="margin-top:12px" data-act="go" data-v="invoice/labels">${esc(T('labels'))} ›</button>
    <div class="row between" style="margin-top:18px"><h2 style="margin:0">${esc(T('profiles'))}</h2><button data-act="iv_prof_new">${esc(T('add'))}</button></div>
    ${V.profs.map((p) => `<div class="card item" data-act="iv_prof_edit" data-id="${p.id}" style="cursor:pointer;${p.active ? '' : 'opacity:.55'}"><div><div class="nm">${esc(p.name)}</div><div class="muted" style="font-size:.85rem">${esc(locName(p.location_id))} · ${esc(p.device_key || '*')} · ${esc(p.paper_size || '')}</div></div><span class="muted" style="font-size:1.3rem">›</span></div>`).join('') || `<div class="notice warn">${esc(T('profEmpty'))}</div>`}`, true);
}
function profSheet(p) {
  const v = (k) => esc(p && p[k] !== null && p[k] !== undefined ? String(p[k]) : '');
  openSheet(`<h2>${esc(p ? p.name : T('profiles'))}</h2><div class="stack">
    <div><label>${esc(T('p_name'))}</label><input id="pf_name" value="${v('name')}"></div>
    <div class="iv-two"><div><label>${esc(T('p_loc'))}</label><select id="pf_loc">${opts((B.ENV.locs || []).map((l) => [l.id, nm(l)]), p && p.location_id, T('allLoc'))}</select></div>
      <div><label>${esc(T('p_type'))}</label><select id="pf_type">${opts([['thermal', 'Thermal'], ['a4', 'A4'], ['label', 'Label'], ['other', 'Other']], p ? p.printer_type : 'thermal')}</select></div></div>
    <div><label>${esc(T('p_dev'))}</label><input id="pf_dev" value="${v('device_key') || (p ? '' : esc(devKey()))}"></div>
    <div class="iv-two"><div><label>${esc(T('p_size'))}</label><input id="pf_size" value="${v('paper_size')}"></div><div><label>${esc(T('p_w'))}</label><input id="pf_w" inputmode="decimal" value="${v('paper_width_mm')}"></div></div>
    <div><label>${esc(T('p_tpl'))}</label><select id="pf_tpl">${opts(V.tpls.map((x) => [x.id, `${x.name} (${lab(KL[x.kind])})`]), p && p.template_id, '—')}</select></div>
    <div class="row between"><b>${esc(T('on'))}</b>${tg(!p || p.active, 'sheettog', 'id="pf_active"')}</div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button>${p ? `<button class="danger full" data-act="iv_prof_del" data-id="${p.id}">${esc(T('del'))}</button>` : ''}<button class="primary full" data-act="iv_prof_save" data-id="${p ? p.id : ''}">${esc(T('save'))}</button></div></div>`);
}

// ----- editor -----
const E = { tpl: null, lang: 'bn' };
async function editorPage(id, newKind) {
  await loadAll();
  if (V.err) return shell(T('title'), `<div class="notice bad">${esc(T('sql'))}</div>`, true);
  let tpl;
  if (id) { tpl = V.tpls.find((x) => String(x.id) === String(id)); if (!tpl) return listPage(); tpl = JSON.parse(JSON.stringify(tpl)); }
  else { const k = KINDS.includes(newKind) ? newKind : 'thermal80'; tpl = { ...BUILTIN(k), name: lab(KL[k]), is_default: !V.tpls.some((x) => x.kind === k && x.is_default && x.active && x.location_id === null) }; }
  tpl.header = tpl.header || {}; tpl.footer = tpl.footer || {}; tpl.show_flags = { ...dflFlags(tpl.kind), ...(tpl.show_flags || {}) }; tpl.margins = tpl.margins || {};
  E.tpl = tpl; E.lang = S.lang; drawEditor();
}
function drawEditor() {
  const tp = E.tpl, fl = tp.show_flags, m = tp.margins, isLabel = tp.kind === 'label', vatOn = B.rule('vat_on', false) === true, rate = B.rule('vat_rate', null);
  const lt = (o, k) => (o && o[k]) || '';
  const flagKeys = isLabel ? LFLAGS : FLAGS;
  const langBtns = ['bn', 'mix', 'en'].map((l) => `<button class="tog ${E.lang === l ? 'on' : ''}" data-act="iv_lang" data-v="${l}" style="min-width:56px">${l === 'bn' ? 'বাংলা' : l === 'en' ? 'English' : 'Bng-Eng'}</button>`).join('');
  shell(tp.id ? tp.name : T('add') + ' ' + lab(KL[tp.kind]), `<div class="stack">
    <div class="card stack"><div><label>${esc(T('e_name'))}</label><input id="iv_name" value="${esc(tp.name)}"></div>
      <div class="iv-two"><div><label>${esc(T('e_kind'))}</label><select id="iv_kind">${opts(KINDS.map((k) => [k, lab(KL[k])]), tp.kind)}</select></div>
        <div><label>${esc(T('e_loc'))}</label><select id="iv_loc">${opts((B.ENV.locs || []).map((l) => [l.id, nm(l)]), tp.location_id, T('allLoc'))}</select></div></div>
      <div class="row between"><b>${esc(T('e_default'))}</b>${tg(tp.is_default, 'iv_tog', 'data-k="is_default"')}</div><div class="row between"><b>${esc(T('e_active'))}</b>${tg(tp.active, 'iv_tog', 'data-k="active"')}</div></div>
    <div class="card stack"><div class="muted" style="font-size:.85rem">${esc(T('e_hint'))}</div><div class="row wrap">${langBtns}</div>
      ${isLabel ? '' : `<div><label>${esc(T('e_head'))}</label><textarea id="iv_head" rows="3">${esc(lt(tp.header, E.lang))}</textarea></div><div><label>${esc(T('e_foot'))}</label><textarea id="iv_foot" rows="2">${esc(lt(tp.footer, E.lang))}</textarea></div>
      <div><label>${esc(T('e_logo'))}</label><input id="iv_logo" value="${esc((tp.logo_ref || '').startsWith('data:') ? '' : tp.logo_ref || '')}" placeholder="https://… / logo.webp">
        <div class="row wrap" style="margin-top:6px"><label class="btn" style="display:inline-flex;align-items:center;margin:0;min-height:44px;padding:0 14px" for="iv_logofile">${esc(T('e_logoFile'))}</label><input id="iv_logofile" type="file" accept="image/*" style="display:none"><button data-act="iv_logo_brand">${esc(T('e_logoBrand'))}</button><button data-act="iv_logo_none">${esc(T('e_logoNone'))}</button></div></div>`}</div>
    <div class="card stack"><b>${esc(T('e_show'))}</b><div class="ivflags">${Object.keys(flagKeys).map((k) => tg(k === 'barcode' ? !!fl[k] : fl[k] !== false, 'iv_flag', `data-k="${k}"`, lab(flagKeys[k]))).join('')}</div>
      ${isLabel ? '' : `<div class="row between" style="margin-top:6px"><b>${esc(T('e_vat'))}</b>${tg(tp.vat_line_on, 'iv_tog', 'data-k="vat_line_on"')}</div>${tp.vat_line_on && !vatOn ? `<div class="notice warn">${esc(T('e_vatOff'))}</div>` : tp.vat_line_on && rate === null ? `<div class="notice warn">${esc(T('e_vatRate'))}</div>` : ''}`}</div>
    <div class="card stack"><b>${esc(T('e_paper'))}</b>
      <div class="iv-two"><div><label>${esc(T('e_w'))}</label><input id="iv_w" inputmode="decimal" value="${esc(String(tp.paper_width_mm))}"></div>
        <div><label>${esc(T('e_fs'))}</label><div class="ivfs"><button class="mini" data-act="iv_fs" data-d="-0.05" aria-label="−">−</button><input id="iv_fs" inputmode="decimal" value="${esc(String(tp.font_scale))}"><button class="mini" data-act="iv_fs" data-d="0.05" aria-label="+">＋</button></div></div></div>
      <label>${esc(T('e_m'))}</label><div class="iv-two">${['top', 'right', 'bottom', 'left'].map((k) => `<div><label>${esc(T('m_' + k))}</label><input id="iv_m_${k}" inputmode="decimal" value="${esc(String(m[k] ?? 4))}"></div>`).join('')}</div>
      ${isLabel ? `<div class="iv-two"><div><label>${esc(T('e_lw'))}</label><input id="iv_lw" inputmode="decimal" value="${esc(String(fl.label_w))}"></div><div><label>${esc(T('e_lh'))}</label><input id="iv_lh" inputmode="decimal" value="${esc(String(fl.label_h))}"></div></div><div><label>${esc(T('e_cols'))}</label><input id="iv_cols" inputmode="numeric" value="${esc(String(fl.cols))}"></div>` : ''}</div>
    <div class="card"><div class="row between"><b>${esc(T('e_prev'))}</b><span class="muted" id="iv_pvinfo"></span></div><div class="iv-pvw" id="iv_pvw" style="margin-top:8px"><div class="iv-pvi" id="iv_pvi"></div></div></div>
    <div class="row"><button class="full" data-act="go" data-v="invoice">${esc(T('back'))}</button><button class="full" data-act="iv_test">${esc(T('e_print'))}</button></div>
    <div class="row">${tp.id ? `<button class="danger full" data-act="iv_del" data-id="${tp.id}">${esc(T('del'))}</button>` : ''}<button class="primary full" data-act="iv_save">${esc(T('save'))}</button></div></div>`, 'invoice');
  updatePreview();
}
const sampleItems = () => ((B.ENV.items || []).filter((i) => i.sell_price !== null).slice(0, 8).map((i) => ({ name: nm(i), barcode: i.barcode || i.code, price: i.sell_price })));
function previewHtml() {
  const tp = E.tpl;
  return tp.kind === 'label' ? renderLabels(tp, sampleItems().length ? sampleItems() : [{ name: 'Rasgolla 1 kg', barcode: 'S-01', price: 520 }, { name: 'Sandesh 500 g', barcode: 'S-14', price: 320 }, { name: 'Sweet doi', barcode: 'D-02', price: 90 }], E.lang) : renderDoc(tp, SAMPLE, E.lang);
}
function updatePreview() {
  const i = $('#iv_pvi'), w = $('#iv_pvw'); if (!i || !E.tpl) return;
  i.innerHTML = previewHtml();
  const doc = i.firstElementChild, avail = w.clientWidth - 20, nat = doc ? doc.offsetWidth : 0, sc = nat > avail && nat > 0 ? avail / nat : 1;
  i.style.transform = `scale(${sc})`; w.style.height = (doc ? doc.offsetHeight * sc + 20 : 40) + 'px';
  const info = $('#iv_pvinfo'); if (info) info.textContent = `${E.tpl.paper_width_mm || ''} mm`;
}
function readForm() {
  const tp = E.tpl, g = (id) => ($(id) || {}).value;
  if ($('#iv_name')) tp.name = g('#iv_name');
  if ($('#iv_loc')) tp.location_id = g('#iv_loc') === '' ? null : Number(g('#iv_loc'));
  if ($('#iv_head')) { tp.header[E.lang] = g('#iv_head'); tp.footer[E.lang] = g('#iv_foot'); }
  const w = pnum(g('#iv_w')); if (w !== null) tp.paper_width_mm = w;
  const fs = pnum(g('#iv_fs')); if (fs !== null) tp.font_scale = fs;
  ['top', 'right', 'bottom', 'left'].forEach((k) => { const v = pnum(g('#iv_m_' + k)); if (v !== null) tp.margins[k] = v; });
  if ($('#iv_lw')) { const f = tp.show_flags; const a = pnum(g('#iv_lw')), b = pnum(g('#iv_lh')), c = pnum(g('#iv_cols')); if (a !== null) f.label_w = a; if (b !== null) f.label_h = b; if (c !== null) f.cols = c; }
}
function validTpl() {
  const tp = E.tpl, nums = [tp.paper_width_mm, tp.font_scale, ...['top', 'right', 'bottom', 'left'].map((k) => tp.margins[k])];
  if (!(tp.name || '').trim()) return T('e_needname');
  if (nums.some((n) => !Number.isFinite(Number(n)) || Number(n) < 0) || !(Number(tp.paper_width_mm) > 0) || !(Number(tp.font_scale) > 0.2 && Number(tp.font_scale) < 4)) return T('e_badw');
  if (tp.kind === 'label') { const f = tp.show_flags; if (![f.label_w, f.label_h, f.cols].every((n) => Number(n) > 0)) return T('e_badw'); }
  return null;
}
async function saveTpl() {
  readForm(); const bad = validTpl(); if (bad) return toast(bad);
  const tp = E.tpl;
  const row = { name: tp.name.trim(), kind: tp.kind, header: tp.header, footer: tp.footer, show_flags: tp.show_flags, logo_ref: tp.logo_ref || null, vat_line_on: !!tp.vat_line_on, paper_width_mm: Number(tp.paper_width_mm), margins: tp.margins,
    font_scale: Number(tp.font_scale), location_id: tp.location_id ?? null, is_default: !!tp.is_default, active: !!tp.active, updated_at: new Date().toISOString(), updated_by: S.ctx.profile.id };
  if (row.is_default && row.active) {   // only one default per kind and branch: take it off the others first
    const ids = V.tpls.filter((x) => x.id !== tp.id && x.kind === row.kind && (x.location_id ?? null) === row.location_id && x.is_default && x.active).map((x) => x.id);
    if (ids.length) { const r = await sb.from('invoice_templates').update({ is_default: false }).in('id', ids); if (r.error) return denied(r.error); }
  } else row.is_default = false;
  const r = tp.id ? await sb.from('invoice_templates').update(row).eq('id', tp.id) : await sb.from('invoice_templates').insert(row);
  if (r.error) return denied(r.error);
  toast(T('saved')); location.hash = '#/invoice';
}
function denied(e) { if (/row-level|permission|denied/i.test((e && e.message) || '') && B.emergency) return B.emergency.offer({ grant: 'settings_invoice', loc: null, context: { page: 'invoice' }, message: lab(L('ইনভয়েস সেটিংস বদলাতে অনুমতি নেই', 'No permission to change invoice settings', 'Invoice settings বদলাতে permission নেই')) }); return fail(e); }
function pickLogo(file) {
  const fr = new FileReader();
  fr.onload = () => { const im = new Image(); im.onload = () => {
    const k = Math.min(1, 420 / im.width), c = document.createElement('canvas'); c.width = Math.max(1, Math.round(im.width * k)); c.height = Math.max(1, Math.round(im.height * k)); c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
    let u = c.toDataURL('image/png'); if (u.length > 200000) u = c.toDataURL('image/jpeg', 0.85);
    E.tpl.logo_ref = u; const i = $('#iv_logo'); if (i) i.value = ''; updatePreview(); }; im.src = fr.result; };
  fr.readAsDataURL(file);
}

// ----- barcode label sheet -----
const LB = { tpl: null, sel: {}, q: '', items: [], tpls: [] };
async function labelsPage() {
  await loadAll(); if (V.err) return shell(T('title'), `<div class="notice bad">${esc(T('sql'))}</div>`, true);
  const ir = await sb.from('items').select('id,code,name_bn,name_en,name_mix,sell_price,barcode,is_active').eq('is_active', true).order('code');
  LB.items = (ir.data || []); LB.tpls = V.tpls.filter((x) => x.kind === 'label' && x.active);
  const d = LB.tpls.find((x) => x.is_default) || LB.tpls[0]; LB.tpl = d || null; LB.sel = {}; LB.q = '';
  drawLabels();
}
const labTpl = () => LB.tpl || BUILTIN('label');
const labItems = () => LB.items.filter((i) => LB.sel[i.id]).flatMap((i) => Array.from({ length: Math.max(1, Math.floor(Number(($('#lb_copies') || {}).value) || 1)) }, () => ({ name: nm(i), barcode: i.barcode || i.code, price: i.sell_price })));
function drawLabels() {
  const q = LB.q.toLowerCase(), list = LB.items.filter((i) => !q || [i.code, i.name_bn, i.name_en, i.name_mix].some((x) => (x || '').toLowerCase().includes(q))).slice(0, 80);
  shell(T('labels'), `<div class="card stack"><div><label>${esc(T('lb_tpl'))}</label><select id="lb_tpl">${opts(LB.tpls.map((x) => [x.id, x.name]), LB.tpl && LB.tpl.id, '(built-in)')}</select></div>
      <div class="iv-two"><div><label>${esc(T('lb_copies'))}</label><input id="lb_copies" inputmode="numeric" value="1"></div><div><label>${esc(T('lb_search'))}</label><input id="lb_q" type="search" value="${esc(LB.q)}"></div></div>
      <div id="lb_list" style="max-height:240px;overflow:auto">${list.map((i) => `<label class="row" style="min-height:44px;margin:0"><input type="checkbox" style="width:24px;min-height:24px" data-lb="${esc(i.id)}" ${LB.sel[i.id] ? 'checked' : ''}><span>${esc(i.code)} · ${esc(nm(i))}</span></label>`).join('')}</div>
      <div class="muted" id="lb_cnt"></div></div>
    <div class="card"><b>${esc(T('e_prev'))}</b><div class="iv-pvw" id="iv_pvw" style="margin-top:8px"><div class="iv-pvi" id="iv_pvi"></div></div></div>
    <button class="primary full" data-act="iv_lb_print">${esc(T('e_print'))}</button>`, 'invoice');
  drawLabelPreview();
}
function drawLabelPreview() {
  const items = labItems(), i = $('#iv_pvi'), w = $('#iv_pvw'); if (!i) return;
  const c = $('#lb_cnt'); if (c) c.textContent = `${Object.values(LB.sel).filter(Boolean).length} ${T('lb_sel')}`;
  i.innerHTML = renderLabels(labTpl(), items.length ? items.slice(0, 24) : sampleItems().slice(0, 8), S.lang);
  const doc = i.firstElementChild, avail = w.clientWidth - 20, nat = doc.offsetWidth, sc = nat > avail ? avail / nat : 1;
  i.style.transform = `scale(${sc})`; w.style.height = doc.offsetHeight * sc + 20 + 'px';
}

// ---------- handlers ----------
const val = (id) => ($(id) || {}).value;
const idv = (x) => (/^\d+$/.test(x) ? Number(x) : x);
Object.assign(A.H, {
  iv_dev_save: () => { const v = val('#iv_dev').trim(); if (v) { store.set('bos_device_key', v); toast(T('saved')); } },
  iv_pref: (a) => { store.set('bos_print_kind', a.dataset.v); listPage(); },
  iv_offer_tog: () => { store.set('bos_print_offer', store.get('bos_print_offer') === '0' ? '1' : '0'); listPage(); },
  iv_offer_print: (a) => { const el = document.getElementById('iv_offer'); if (el) el.remove(); return printSaleId(a.dataset.id, a.dataset.loc === '' ? null : Number(a.dataset.loc)); },
  iv_offer_close: () => { const el = document.getElementById('iv_offer'); if (el) el.remove(); },
  iv_lang: (a) => { readForm(); E.lang = a.dataset.v; drawEditor(); },
  iv_tog: (a) => { readForm(); E.tpl[a.dataset.k] = !E.tpl[a.dataset.k]; drawEditor(); },
  iv_flag: (a) => { readForm(); const f = E.tpl.show_flags, k = a.dataset.k, cur = k === 'barcode' ? !!f[k] : f[k] !== false; f[k] = !cur; drawEditor(); },
  iv_fs: (a) => { const i = $('#iv_fs'), n = Math.round(((pnum(i.value) || 1) + Number(a.dataset.d)) * 100) / 100; i.value = String(Math.max(0.5, Math.min(3, n))); readForm(); updatePreview(); },
  iv_logo_brand: () => { E.tpl.logo_ref = 'logo.webp'; const i = $('#iv_logo'); if (i) i.value = 'logo.webp'; updatePreview(); },
  iv_logo_none: () => { E.tpl.logo_ref = null; const i = $('#iv_logo'); if (i) i.value = ''; updatePreview(); },
  iv_save: saveTpl,
  iv_test: () => { readForm(); const bad = validTpl(); if (bad) return toast(bad); const tp = E.tpl; printHtml(previewHtml(), Number(tp.paper_width_mm) || 80, tp.kind === 'thermal58' || tp.kind === 'thermal80'); },
  iv_del: async (a) => { if (!confirm(lab(L('এই টেমপ্লেট মুছবেন?', 'Delete this template?', 'এই template মুছবেন?')))) return; const { error } = await sb.from('invoice_templates').delete().eq('id', idv(a.dataset.id)); if (error) return denied(error); toast(T('saved')); location.hash = '#/invoice'; },
  iv_prof_new: () => profSheet(null),
  iv_prof_edit: (a) => profSheet(V.profs.find((x) => String(x.id) === a.dataset.id)),
  iv_prof_save: async (a) => { const name = val('#pf_name').trim(); if (!name) return toast(T('e_needname')); const w = pnum(val('#pf_w')); if (Number.isNaN(w) || (w !== null && w <= 0)) return toast(T('e_badw'));
    const row = { name, location_id: val('#pf_loc') === '' ? null : Number(val('#pf_loc')), device_key: val('#pf_dev').trim() || null, printer_type: val('#pf_type'), paper_size: val('#pf_size').trim() || null, paper_width_mm: w, template_id: val('#pf_tpl') === '' ? null : Number(val('#pf_tpl')), active: $('#pf_active').classList.contains('on'), updated_by: S.ctx.profile.id };
    const r = a.dataset.id ? await sb.from('print_profiles').update(row).eq('id', idv(a.dataset.id)) : await sb.from('print_profiles').insert(row); if (r.error) return denied(r.error); closeSheet(); toast(T('saved')); listPage(); },
  iv_prof_del: async (a) => { const { error } = await sb.from('print_profiles').delete().eq('id', idv(a.dataset.id)); if (error) return denied(error); closeSheet(); listPage(); },
  iv_lb_print: () => { const items = labItems(); if (!items.length) return toast(T('lb_none')); const tp = labTpl(); printHtml(renderLabels(tp, items, S.lang), Number(tp.paper_width_mm) || 210, false); },
});
document.addEventListener('input', (e) => {
  const id = e.target.id || '';
  if (id === 'iv_logo' && E.tpl) { E.tpl.logo_ref = e.target.value.trim() || null; updatePreview(); }
  else if (id.startsWith('iv_') && E.tpl && $('#iv_pvi')) { readForm(); updatePreview(); }
  else if (id === 'lb_q') { LB.q = e.target.value; const v = e.target.value; drawLabels(); const i = $('#lb_q'); if (i) { i.focus(); i.setSelectionRange(v.length, v.length); } }
  else if (id === 'lb_copies') drawLabelPreview();
});
document.addEventListener('change', (e) => {
  const id = e.target.id || '';
  if (id === 'iv_kind' && E.tpl) { readForm(); const old = E.tpl.kind; E.tpl.kind = e.target.value; if (Number(E.tpl.paper_width_mm) === KW[old]) E.tpl.paper_width_mm = KW[E.tpl.kind]; E.tpl.show_flags = { ...dflFlags(E.tpl.kind), ...E.tpl.show_flags }; if (E.tpl.kind === 'label' && E.tpl.show_flags.label_w === undefined) Object.assign(E.tpl.show_flags, dflFlags('label')); drawEditor(); }
  else if (id === 'iv_logofile' && e.target.files && e.target.files[0]) pickLogo(e.target.files[0]);
  else if (id === 'lb_tpl') { LB.tpl = LB.tpls.find((x) => String(x.id) === e.target.value) || null; drawLabelPreview(); }
  else if (e.target.dataset && e.target.dataset.lb) { LB.sel[e.target.dataset.lb] = e.target.checked; drawLabelPreview(); }
  else if (id.startsWith('iv_') && E.tpl && $('#iv_pvi')) { readForm(); updatePreview(); }
});
window.addEventListener('resize', () => { if ($('#iv_pvi') && E.tpl) updatePreview(); });
B.invoice = { offer, printSaleId, renderDoc, renderLabels, code128, barcodeSvg, templateFor, printHtml };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { invoice: view });
})();
