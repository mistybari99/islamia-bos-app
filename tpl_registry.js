/* Islamia BOS · Template registry (phase 93, step Tpl). Pure HTML / CSS / plain-text templates that render from a plain data object.
   Public API (what other screens call, e.g. the post-sale invoice view):
     BOS.tpl.render(docType, data, templateId?, opts?)  -> HTML string (a fragment: <style> + <div class="tp ...">), or plain text for message types.
         templateId omitted  -> the owner's saved default for (docType, opts.loc); NO saved default -> returns null: the caller keeps printing what it printed before.
         opts: { lang: 'bn'|'en'|'mix', loc: <location id>, shop: {name, logo, address, phone, taxId, footer}, channel: 'sms'|'whatsapp'|'email' (messages) }
     BOS.tpl.printHTML(docType, data, templateId, opts) -> a full HTML document string (with @page) ready for an iframe / window print.
     BOS.tpl.list(docType) / BOS.tpl.docTypes() / BOS.tpl.recommend(docType) / BOS.tpl.pick(docType, loc) / BOS.tpl.setChoices(rows) / BOS.tpl.load(sb)
   Rules kept here: every value is escaped (XSS safe); keys that look like a cost / purchase price are dropped from the data before rendering;
   English mode is all English, Bangla mode keeps common words English, Bng-Eng mixes both (labels carry 3 variants). The document specs live in tpl_docs.js,
   labels / price tags in tpl_labels.js, message texts in tpl_msgs.js, sample data in tpl_samples.js, the owner page in tplpicker.js. Server side: supabase/phase93.sql. */
(() => {
'use strict';
const B = (window.BOS = window.BOS || {});
const T = (B.tpl = B.tpl || {});

/* ---------- helpers ---------- */
const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' };
const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"'`]/g, (c) => ESC[c]);
const COSTRE = /cost|cogs|purchase|landed|wholesale|(^|_)cp(_|$)|supplier_?(price|rate)|gross|buy(ing)?_?(price|rate)|margin|profit|markup/i;
function strip(v, depth) {            // deep copy without cost-like keys (customer-facing safety net); depth-limited so a cyclic object cannot hang
  if ((depth || 0) > 8 || v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map((x) => strip(x, (depth || 0) + 1));
  const o = {}; for (const k of Object.keys(v)) { if (COSTRE.test(k)) continue; o[k] = strip(v[k], (depth || 0) + 1); } return o;
}
const get = (o, p) => { let c = o; for (const k of String(p).split('.')) { if (c === null || c === undefined) return undefined; c = c[k]; } return c; };
const has = (v) => v !== null && v !== undefined && v !== '';
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const grp = (s) => s.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
const qty = (v) => { const n = Number(v); return Number.isFinite(n) ? String(Math.round(n * 1000) / 1000) : esc(v); };
const lang = (o) => { const l = (o && o.lang) || (window.BOS_APP && window.BOS_APP.S && window.BOS_APP.S.lang) || 'bn'; return l === 'en' || l === 'mix' ? l : 'bn'; };
const money = (v, lg) => { const n = Number(v); if (!Number.isFinite(n)) return esc(v); const f = (Math.round(n * 100) / 100).toFixed(2).replace(/\.00$/, ''); const [a, b] = f.split('.'); return (lg === 'en' ? 'Tk ' : '৳') + grp(a) + (b ? '.' + b : ''); };
// safe image source: data:image (png/jpeg/webp/gif, base64) or a plain relative / https path; anything else is dropped
const safeSrc = (s) => { s = String(s || '').trim(); if (s.startsWith('//') || s.includes('..')) return ''; return /^data:image\/(png|jpe?g|webp|gif);base64,[A-Za-z0-9+/=]+$/.test(s) || /^(https:\/\/|\.\/|\/)?[\w\-./%~]+(\?[\w\-.=&%]*)?$/.test(s) ? s : ''; };
T.esc = esc; T.strip = strip; T.money = money; T.qty = qty; T.safeSrc = safeSrc; T.get = get; T.has = has; T.num = num; T.lang = lang; T.grp = grp;

/* ---------- labels: key -> [en, bn, mix] ---------- */
const LB = {};
T.addLabels = (o) => { Object.assign(LB, o); };
const lbl = (k, lg) => { const e = LB[k]; if (!e) return String(k); return lg === 'en' ? e[0] : lg === 'mix' ? (e[2] || e[1]) : e[1]; };
T.lbl = lbl; T.labels = LB;
// Language rule: English = all English; Bangla mode keeps the common words English (Invoice, Total, Date, Qty, Price, Item, Receipt ...); Bng-Eng mix the same words inside Bangla.
// finishLabels() is called at the end of every tpl_*.js file: the common one-word labels become English in every mode, all other Bangla-mode labels follow the mix text.
const COMMON = ['thanks', 'tax', 'sample', 'd_receipt', 'd_invoice', 'm_no', 'm_date', 'm_time', 'm_cashier', 'm_loc', 'm_ref', 'm_batch', 'm_vehicle', 'm_yield', 'm_product', 'm_month', 'p_cust', 'p_sup', 'p_recv', 'c_code', 'c_item', 'c_qty', 'c_unit', 'c_price', 'c_amt', 'c_rate', 'c_bal', 'c_dr', 'c_cr', 'c_desc', 'c_reason', 't_sub', 't_disc', 't_vat', 't_total', 't_paid', 't_due', 't_change', 't_refund', 't_net', 't_open', 't_close', 'lb_sale', 'lb_was', 'lb_unit', 'g_owner'];
T.finishLabels = () => { for (const k of Object.keys(LB)) { const e = LB[k]; if (COMMON.includes(k) || /^(lk_|pg_)/.test(k)) { e[1] = e[0]; e[2] = e[0]; } else if (e[2]) e[1] = e[2]; } };
T.addLabels({
  ph_shop: ['[Shop name]', '[দোকানের নাম]', '[Shop name]'], ph_tax: ['[Tax ID]', '[ট্যাক্স আইডি]', '[Tax ID]'], tax: ['Tax ID', 'ট্যাক্স আইডি', 'Tax ID'],
  thanks: ['Thank you', 'ধন্যবাদ', 'ধন্যবাদ'], sample: ['SAMPLE', 'নমুনা', 'SAMPLE'],
  lk_classic: ['Classic', 'ক্লাসিক', 'Classic'], lk_modern: ['Modern', 'মডার্ন', 'Modern'], lk_minimal: ['Minimal', 'মিনিমাল', 'Minimal'], lk_boxed: ['Boxed', 'বক্স', 'Boxed'],
  lk_compact: ['Compact', 'কম্প্যাক্ট', 'Compact'], lk_formal: ['Formal', 'ফরমাল', 'Formal'], lk_split: ['Split header', 'দুই-ভাগ হেডার', 'Split header'],
  lk_slip: ['Centered slip', 'মাঝখানে স্লিপ', 'Centered slip'], lk_receipt: ['Plain receipt', 'সাদামাটা রসিদ', 'Plain receipt'],
  pg_thermal80: ['Thermal 80 mm', 'থার্মাল ৮০ মিমি', 'Thermal 80 mm'], pg_thermal58: ['Thermal 58 mm', 'থার্মাল ৫৮ মিমি', 'Thermal 58 mm'], pg_a4: ['A4', 'A4', 'A4'], pg_a5: ['A5', 'A5', 'A5'], pg_a6: ['A6', 'A6', 'A6'],
  grp_sales: ['Sales & customers', 'বিক্রি ও গ্রাহক', 'Sales ও Customer'], grp_purch: ['Purchasing', 'ক্রয়', 'Purchase'], grp_stock: ['Stock', 'স্টক', 'Stock'], grp_factory: ['Production', 'উৎপাদন', 'Production'],
  grp_people: ['People & partners', 'স্টাফ ও অংশীদার', 'Staff ও Partner'], grp_acc: ['Accounts print', 'হিসাব প্রিন্ট', 'Accounts print'], grp_msg: ['Messages', 'মেসেজ', 'Message'], grp_label: ['Labels & price tags', 'লেবেল ও প্রাইস ট্যাগ', 'Label ও Price tag'],
});

T.finishLabels();
/* ---------- registry ---------- */
const DOCS = {}; T.docs = DOCS;
const ORDER = [];
const PAGES = {   // key -> [CSS @page size, margin mm, content width mm, label key, thermal?]
  thermal80: ['80mm auto', 0, 74, 'pg_thermal80', true], thermal58: ['58mm auto', 0, 50, 'pg_thermal58', true],
  a4: ['A4', 12, 186, 'pg_a4', false], a5: ['A5', 8, 132, 'pg_a5', false], a6: ['A6', 6, 93, 'pg_a6', false],
};
T.pages = PAGES;
/* defineDoc(spec): spec.id, spec.group, spec.kind ('doc' | 'text' | 'label'), spec.title (label key), spec.rec = [recommended template id, label key of the one-line advice],
   spec.templates = array of [pageKey, lookKey] (documents) or { id, name:[en,bn,mix], ... } objects (labels / messages).  */
T.defineDoc = (spec) => {
  spec.kind = spec.kind || 'doc';
  spec.tpls = (spec.templates || []).map((t) => {
    if (Array.isArray(t)) return { id: t[0] + '_' + t[1], page: t[0], look: t[1], name: null };
    return t;
  });
  if (!DOCS[spec.id]) ORDER.push(spec.id);
  DOCS[spec.id] = spec;
};
T.docTypes = () => ORDER.map((id) => DOCS[id]);
T.list = (docType) => { const s = DOCS[docType]; return s ? s.tpls.map((t) => ({ id: t.id, page: t.page || null, look: t.look || null, name: (lg) => tplName(t, lg) })) : []; };
const tplName = (t, lg) => (t.name ? (lg === 'en' ? t.name[0] : lg === 'mix' ? (t.name[2] || t.name[1]) : t.name[1]) : lbl('lk_' + t.look, lg) + ' · ' + lbl('pg_' + t.page, lg));
T.tplName = tplName;
T.recommend = (docType) => { const s = DOCS[docType]; if (!s || !s.rec) return null; return { id: s.rec[0], text: (lg) => lbl(s.rec[1], lg) }; };

/* ---------- the owner's saved choices (rows of get_doc_templates) ---------- */
let CH = [];
T.setChoices = (rows) => { CH = Array.isArray(rows) ? rows.filter((r) => r && typeof r.doc_type === 'string' && typeof r.template_id === 'string') : []; };
T.choices = () => CH.slice();
T.pick = (docType, loc) => {
  const l = has(loc) ? Number(loc) : null;
  const a = l !== null ? CH.find((r) => r.doc_type === docType && r.location_id === l) : null;
  const b = CH.find((r) => r.doc_type === docType && (r.location_id === null || r.location_id === undefined));
  const id = (a || b || {}).template_id;
  return id && DOCS[docType] && DOCS[docType].tpls.some((t) => t.id === id) ? id : null;
};
T.load = async (sb, loc) => {
  const r = await sb.rpc('get_doc_templates', { p_location_id: has(loc) ? loc : null });
  if (r.error) throw r.error; T.setChoices(r.data); return CH;
};

/* bos98: fetch the owner choices ONCE per session for the output screens (2-second cap, cached; a failure or timeout is not cached for long and
   never throws: the caller then keeps today's output). Resolves to true when choices are loaded. */
let ENS = null, ENS_FAIL = 0;
T.ensure = (sb, ms) => {
  if (ENS) return ENS;
  if (ENS_FAIL && Date.now() - ENS_FAIL < 30000) return Promise.resolve(false);
  const cap = new Promise((res) => setTimeout(() => res(false), ms || 2000));
  const run = Promise.resolve().then(() => T.load(sb, null)).then(() => true, () => false);
  ENS = Promise.race([run, cap]).then((ok) => { if (!ok) { ENS = null; ENS_FAIL = Date.now(); } return ok; });
  return ENS;
};
T.ensureReset = () => { ENS = null; ENS_FAIL = 0; };

/* ---------- shop block (logo / name / footer / tax id come from settings; placeholders if empty) ---------- */
T.shop = {};
T.setShop = (s) => { T.shop = Object.assign({}, s || {}); };

/* ---------- barcode (EAN-13 and Code 39 as SVG bars) ---------- */
const EL = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011'];
const EG = ['0100111', '0110011', '0011011', '0100001', '0011101', '0111001', '0000101', '0010001', '0001001', '0010111'];
const ER = EL.map((s) => s.replace(/[01]/g, (c) => (c === '0' ? '1' : '0')));
const EP = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL'];
const C39 = { 0: 'nnnwwnwnn', 1: 'wnnwnnnnw', 2: 'nnwwnnnnw', 3: 'wnwwnnnnn', 4: 'nnnwwnnnw', 5: 'wnnwwnnnn', 6: 'nnwwwnnnn', 7: 'nnnwnnwnw', 8: 'wnnwnnwnn', 9: 'nnwwnnwnn',
  A: 'wnnnnwnnw', B: 'nnwnnwnnw', C: 'wnwnnwnnn', D: 'nnnnwwnnw', E: 'wnnnwwnnn', F: 'nnwnwwnnn', G: 'nnnnnwwnw', H: 'wnnnnwwnn', I: 'nnwnnwwnn', J: 'nnnnwwwnn',
  K: 'wnnnnnnww', L: 'nnwnnnnww', M: 'wnwnnnnwn', N: 'nnnnwnnww', O: 'wnnnwnnwn', P: 'nnwnwnnwn', Q: 'nnnnnnwww', R: 'wnnnnnwwn', S: 'nnwnnnwwn', T: 'nnnnwnwwn',
  U: 'wwnnnnnnw', V: 'nwwnnnnnw', W: 'wwwnnnnnn', X: 'nwnnwnnnw', Y: 'wwnnwnnnn', Z: 'nwwnwnnnn', '-': 'nwnnnnwnw', '.': 'wwnnnnwnn', ' ': 'nwwnnnwnn', '*': 'nwnnwnwnn',
  $: 'nwnwnwnnn', '/': 'nwnwnnnwn', '+': 'nwnnnwnwn', '%': 'nnnwnwnwn' };
function ean13Modules(code) {
  let d = String(code).replace(/\D/g, ''); const cs = (x) => { let t = 0; for (let i = 0; i < 12; i++) t += Number(x[i]) * (i % 2 ? 3 : 1); return (10 - (t % 10)) % 10; };
  if (d.length === 12) d += String(cs(d));
  if (d.length !== 13 || Number(d[12]) !== cs(d)) return null;            // a wrong check digit is never silently "fixed": the caller falls back to Code 39 so the printed digits stay exactly what was typed
  const par = EP[Number(d[0])]; let m = '101';
  for (let i = 1; i <= 6; i++) m += (par[i - 1] === 'L' ? EL : EG)[Number(d[i])];
  m += '01010'; for (let i = 7; i <= 12; i++) m += ER[Number(d[i])];
  return { mods: m + '101', text: d, kind: 'ean13' };
}
function c39Modules(code) {
  const raw = String(code).toUpperCase(); if (!raw || /[^0-9A-Z\-. $/+%]/.test(raw)) return null;   // unsupported character: no barcode (never a silently different one)
  const s = '*' + raw + '*'; let m = '';
  for (let i = 0; i < s.length; i++) { const p = C39[s[i]]; for (let j = 0; j < 9; j++) m += (j % 2 === 0 ? '1' : '0').repeat(p[j] === 'w' ? 3 : 1); if (i < s.length - 1) m += '0'; }
  return { mods: m, text: raw, kind: 'code39' };
}
T.barcodeModules = (code) => { const c = String(code === null || code === undefined ? '' : code).trim(); const e = /^\d{12,13}$/.test(c) ? ean13Modules(c) : null; const r = e || c39Modules(c); if (r && !e && /^\d{13}$/.test(c)) r.warn = 'ean_check_digit'; return r; };
const QUIET = 10, MINMOD = 0.19;                 // quiet zone in modules each side; narrowest bar in mm that a thermal / laser head still prints
T.barcodeFits = (code, wmm) => { const b = T.barcodeModules(code); return !!b && wmm / (b.mods.length + 2 * QUIET) >= MINMOD; };
// width/height in mm; returns an <svg> string (bars only, no text), or '' when the code cannot be drawn readable in that width (module < 0.19 mm) or is invalid
T.barcodeSVG = (code, wmm, hmm) => {
  const b = T.barcodeModules(code); if (!b || !b.mods.length || !T.barcodeFits(code, wmm)) return '';
  const n = b.mods.length + 2 * QUIET; let r = '', i = 0;
  while (i < b.mods.length) { if (b.mods[i] === '1') { let j = i; while (j < b.mods.length && b.mods[j] === '1') j++; r += `<rect x="${i + QUIET}" y="0" width="${j - i}" height="10"/>`; i = j; } else i++; }
  return `<svg class="tp-bc" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${n} 10" preserveAspectRatio="none" style="width:${num(wmm)}mm;height:${num(hmm)}mm" role="img" aria-label="barcode"${b.warn ? ' data-warn="' + b.warn + '"' : ''}><g fill="#000">${r}</g></svg>`;
};

/* ---------- the layout engine for documents ---------- */
const BASE = '.tp{font:12px/1.4 system-ui,"Noto Sans Bengali","Segoe UI",sans-serif;color:#111;background:#fff;box-sizing:border-box;margin:0 auto;overflow-wrap:anywhere;word-break:break-word}.tp *{box-sizing:border-box;min-width:0}'
  + '.tp table{width:100%;border-collapse:collapse;font:inherit}.tp th,.tp td{padding:2px 4px;vertical-align:top;overflow-wrap:anywhere;word-break:break-word}.tp .r{text-align:right}.tp .c{text-align:center}'
  + '.tp h1,.tp h2,.tp h3,.tp p{margin:0}.tp-logo{max-height:16mm;max-width:50%;object-fit:contain}.tp-sh{font-weight:700}.tp-mu{color:#555}.tp-ti{font-weight:700;letter-spacing:.04em;text-transform:uppercase}'
  + '.tp-mt{display:grid;gap:2px 10px}.tp-m span{color:#555;margin-right:4px}.tp-m b{overflow-wrap:anywhere}.tp-bl{display:inline-block;min-width:18mm;height:6mm;border:1px solid #333}'
  + '.tp-sg{display:flex;gap:10mm;margin-top:14mm}.tp-sg div{flex:1;border-top:1px solid #333;padding-top:2px;text-align:center;font-size:.85em}.tp-ft{text-align:center;margin-top:6px;color:#444}'
  + '.tp-ca{border-bottom:1px dashed #000;padding:2px 0}.tp-ca .l2{display:flex;justify-content:space-between;gap:6px}.tp-ca .l2 span,.tp-ca .l2 b{overflow-wrap:anywhere;word-break:break-word}.tp-ca .nm{font-weight:600;overflow-wrap:anywhere;word-break:break-word}'
  + '.tp-p80 table,.tp-pthermal80 table,.tp-pthermal58 table{table-layout:fixed}.tp-tot{margin-top:4px}.tp-tot div{display:flex;justify-content:space-between;gap:8px}'
  + '.tp-tot .s{font-weight:700;font-size:1.1em}.tp-sec{margin-top:8px}.tp-sec h3{font-size:1em;margin-bottom:2px}.tp-sec .t td{font-weight:700;border-top:1px solid #333}.tp-ol{margin:4px 0 0 18px;padding:0}.tp-no{margin-top:6px;white-space:pre-wrap}'
  + '.tp-cards{display:grid;gap:4px}.tp-card{border:1px solid #bbb;border-radius:4px;padding:3px 6px}.tp-card .h{font-weight:700;margin-bottom:2px}.tp-card .g{display:grid;grid-template-columns:repeat(auto-fit,minmax(24mm,1fr));gap:1px 8px}.tp-card .g span{color:#555;margin-right:3px}'
  + '.tp-two{display:flex;gap:8mm;align-items:flex-start;margin-top:6px}.tp-two .nt{flex:1}.tp-two .tp-tot{flex:0 0 46%;margin-top:0}.tp-cols2{display:grid;grid-template-columns:1fr 1fr;gap:0 8mm}';
// look: hdr (center|left|split|band), cols (info grid columns), tbl (grid|cards|ledger), tot (right|box|two|full), sec (stack|cols2)
const LOOKS = {
  classic: { hdr: 'center', cols: 2, tbl: 'grid', tot: 'right', sec: 'stack', css: '.tp-classic th{border-top:1px solid #000;border-bottom:1px solid #000;text-align:left}.tp-classic td{border-bottom:1px solid #ccc}.tp-classic .tp-ti{text-align:center;margin:6px 0;font-size:1.15em}' },
  modern: { hdr: 'band', cols: 2, tbl: 'grid', tot: 'box', sec: 'stack', css: '.tp-modern .tp-hd{background:#0f6b4f;color:#fff;padding:6px 8px;border-radius:3px}.tp-modern .tp-hd .tp-mu{color:#d6efe6}.tp-modern th{background:#e6f2ed;text-align:left;color:#0f6b4f}.tp-modern tbody tr:nth-child(even) td{background:#f6faf8}.tp-modern .tp-tot{background:#e6f2ed;border-left:4px solid #0f6b4f;padding:4px 8px;margin-left:40%}.tp-modern .tp-tot .s{color:#0f6b4f}.tp-modern .tp-sec h3{color:#0f6b4f;border-bottom:2px solid #0f6b4f}' },
  minimal: { hdr: 'left', cols: 1, tbl: 'grid', tot: 'right', sec: 'stack', css: '.tp-minimal{font-size:11.5px}.tp-minimal th{text-align:left;font-weight:500;color:#555;border-bottom:1px solid #999}.tp-minimal td{border-bottom:1px solid #eee}.tp-minimal .tp-ti{font-weight:500;color:#555;margin:6px 0}.tp-minimal .tp-m{display:flex;justify-content:space-between;max-width:90mm}.tp-minimal .tp-tot{margin-left:55%}' },
  boxed: { hdr: 'center', cols: 2, tbl: 'grid', tot: 'full', sec: 'stack', css: '.tp-boxed .tp-mt{border:1px solid #000;padding:4px}.tp-boxed th,.tp-boxed td{border:1px solid #000}.tp-boxed th{background:#eee;text-align:left}.tp-boxed .tp-ti{border:2px solid #000;text-align:center;padding:2px;margin:6px 0}.tp-boxed .tp-sec table{border:1px solid #000}.tp-boxed .tp-sec td{border:1px solid #bbb}.tp-boxed .tp-tot{border:1px solid #000;padding:2px 6px}.tp-boxed .tp-tot div{border-bottom:1px solid #ccc}' },
  compact: { hdr: 'left', cols: 3, tbl: 'grid', tot: 'two', sec: 'cols2', css: '.tp-compact{font-size:10.5px;line-height:1.25}.tp-compact th,.tp-compact td{padding:1px 3px}.tp-compact th{text-align:left;background:#f0f0f0}.tp-compact td{border-bottom:1px dotted #888}.tp-compact .tp-ti{margin:3px 0}' },
  formal: { hdr: 'split', cols: 2, tbl: 'ledger', tot: 'two', sec: 'stack', css: '.tp-formal{border:3px double #000;padding:5mm}.tp-formal th{border-top:2px solid #000;border-bottom:2px solid #000;text-align:left}.tp-formal td{border-bottom:1px solid #999}.tp-formal .tp-ledger td+td,.tp-formal .tp-ledger th+th{border-left:1px solid #999}.tp-formal .tp-ledger tbody tr:nth-child(5n) td{border-bottom:2px solid #000}.tp-formal .tp-ti{font-size:1.3em;margin:4px 0}.tp-formal .tp-ft{border-top:1px solid #000;padding-top:3px}.tp-formal .tp-tot{border-top:2px solid #000;border-bottom:2px double #000}' },
  split: { hdr: 'split', cols: 2, tbl: 'cards', tot: 'right', sec: 'cols2', css: '.tp-split .tp-hd{border-bottom:3px solid #222;padding-bottom:4px;margin-bottom:4px}.tp-split .tp-ti{font-size:1.4em}.tp-split .tp-card{border-left:4px solid #222}.tp-split .tp-card .h{background:#222;color:#fff;margin:-3px -6px 3px;padding:2px 6px}.tp-split th{background:#222;color:#fff;text-align:left}' },
  slip: { hdr: 'center', cols: 1, tbl: 'grid', tot: 'right', sec: 'stack', css: '.tp-slip{font-size:11px}.tp-slip .tp-ti{text-align:center;border-top:1px dashed #000;border-bottom:1px dashed #000;margin:4px 0;padding:2px 0}.tp-slip .tp-m{display:flex;justify-content:space-between}' },
  receipt: { hdr: 'left', cols: 1, tbl: 'grid', tot: 'right', sec: 'stack', css: '.tp-receipt{font:11px/1.3 "Courier New",ui-monospace,monospace}.tp-receipt .tp-ti{margin:4px 0;border-bottom:1px solid #000}.tp-receipt .tp-m{display:flex;justify-content:space-between}.tp-receipt .tp-ca{border-bottom:1px dotted #000}' },
};
T.looks = LOOKS;
const obj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
const arr = (x) => (Array.isArray(x) ? x.filter(obj) : []);

function cell(c, v, lg) {
  const t = c[2];
  if (t === 'blank') return '<span class="tp-bl"></span>';
  if (t === 'money') return has(v) ? money(v, lg) : '';
  if (t === 'num') return has(v) ? qty(v) : '';
  return esc(v);
}
function partyHTML(p, lg, d) {
  const v = get(d, p[1]); if (!has(v)) return '';
  const body = obj(v) ? [v.name, v.phone, v.address].filter(has).map(esc).join('<br>') : esc(v);
  return `<div class="tp-m"><span>${esc(lbl(p[0], lg))}</span><b>${body}</b></div>`;
}
function head(sp, lk, d, ctx, lg) {
  const sh = ctx.shop, name = has(sh.name) ? esc(sh.name) : esc(lbl('ph_shop', lg));
  const logoSrc = safeSrc(sh.logo), logo = logoSrc ? `<img class="tp-logo" src="${esc(logoSrc)}" alt="">` : '';
  const sub = [sh.address, sh.phone].filter(has).map(esc).join(' · ') + `<div>${esc(lbl('tax', lg))}: ${has(sh.taxId) ? esc(sh.taxId) : esc(lbl('ph_tax', lg))}</div>`;
  const shopBlock = `${logo}<div class="tp-sh">${name}</div><div class="tp-mu">${sub}</div>`;
  const title = `<div class="tp-ti">${esc(lbl(sp.title, lg))}</div>`;
  if (lk.hdr === 'split') return `<div class="tp-hd" style="display:flex;justify-content:space-between;gap:8px"><div>${shopBlock}</div><div class="r">${title}</div></div>`;
  if (lk.hdr === 'band') return `<div class="tp-hd"><div style="display:flex;justify-content:space-between;gap:8px;align-items:center"><div>${logo}<div class="tp-sh">${name}</div><div class="tp-mu">${sub}</div></div><div class="tp-ti">${esc(lbl(sp.title, lg))}</div></div></div>`;
  if (lk.hdr === 'left') return `<div class="tp-hd">${shopBlock}</div>${title}`;
  return `<div class="tp-hd c">${shopBlock}</div>${title}`;
}
function table(sp, d, mode, lg) {                // mode: 'thermal' (2-line cards) | 'cards' (bordered cards) | 'ledger' | 'grid'
  const rows = arr(get(d, sp.rows || 'items')); if (!sp.cols || !rows.length) return '';
  const ni = Math.max(0, sp.cols.findIndex((c) => c[0] === 'name'));
  if (mode === 'thermal') {
    return rows.map((r) => {
      const first = esc(r[sp.cols[ni][0]]), rest = sp.cols.filter((c, i) => i !== ni && c[0] !== 'code' && c[2] !== 'blank');
      if (sp.cardFmt === 'mul') return `<div class="tp-ca"><div class="nm">${first}</div><div class="l2"><span>${cell(sp.cols[1], r.qty, lg)} × ${cell(sp.cols[2], r.price, lg)}</span><b>${cell(sp.cols[3], r.amount, lg)}</b></div></div>`;
      return `<div class="tp-ca"><div class="nm">${first}</div><div class="l2"><span>${rest.slice(0, -1).map((c) => cell(c, r[c[0]], lg)).filter(Boolean).join(' · ')}</span><b>${rest.length ? cell(rest[rest.length - 1], r[rest[rest.length - 1][0]], lg) : ''}</b></div></div>`;
    }).join('');
  }
  if (mode === 'cards') {
    return `<div class="tp-cards">${rows.map((r) => `<div class="tp-card"><div class="h">${esc(r[sp.cols[ni][0]])}</div><div class="g">${sp.cols.filter((c, i) => i !== ni).map((c) => `<div><span>${esc(lbl(c[1], lg))}</span><b>${cell(c, r[c[0]], lg)}</b></div>`).join('')}</div></div>`).join('')}</div>`;
  }
  const th = sp.cols.map((c) => `<th class="${c[2] === 'money' || c[2] === 'num' ? 'r' : ''}">${esc(lbl(c[1], lg))}</th>`).join('');
  const tb = rows.map((r) => `<tr>${sp.cols.map((c) => `<td class="${c[2] === 'money' || c[2] === 'num' ? 'r' : ''}">${cell(c, r[c[0]], lg)}</td>`).join('')}</tr>`).join('');
  return `<table class="${mode === 'ledger' ? 'tp-ledger' : ''}"><thead><tr>${th}</tr></thead><tbody>${tb}</tbody></table>`;
}
function sections(sp, d, lg, cols2) {
  const secs = get(d, sp.sections); if (!Array.isArray(secs)) return '';
  const h = secs.filter(obj).map((s) => `<div class="tp-sec"><h3>${esc(s.title)}</h3><table><tbody>${arr(s.rows).map((r) => `<tr><td>${esc(r.label)}</td><td class="r">${money(r.amount, lg)}</td></tr>`).join('')}${has(s.total) ? `<tr class="t"><td>${esc(lbl('t_total', lg))}</td><td class="r">${money(s.total, lg)}</td></tr>` : ''}</tbody></table></div>`).join('');
  return cols2 ? `<div class="tp-cols2">${h}</div>` : h;
}
function renderDoc(sp, tp, data, opts) {
  const lg = lang(opts), d = obj(data) ? strip(data) : {}, pg = PAGES[tp.page] || PAGES.a4, lk = LOOKS[tp.look] || LOOKS.classic;
  const ctx = { shop: Object.assign({}, T.shop, (opts && opts.shop) || {}) }, thermal = pg[4];
  const meta = (sp.meta || []).filter((m) => has(get(d, m[1]))).map((m) => `<div class="tp-m"><span>${esc(lbl(m[0], lg))}</span><b>${m[2] === 'money' ? money(get(d, m[1]), lg) : esc(get(d, m[1]))}</b></div>`).join('')
    + (sp.party || []).map((p) => partyHTML(p, lg, d)).join('');
  const tots = (sp.totals || []).filter((t) => has(get(d, t[1]))).map((t) => `<div class="${t[2] ? 's' : ''}"><span>${esc(lbl(t[0], lg))}</span><span>${money(get(d, t[1]), lg)}</span></div>`).join('');
  const lst = sp.list ? get(d, sp.list[1]) : null;
  const list = Array.isArray(lst) ? `<div class="tp-sec"><h3>${esc(lbl(sp.list[0], lg))}</h3><ol class="tp-ol">${lst.filter((x) => !obj(x) && x !== null).map((x) => `<li>${esc(x)}</li>`).join('')}</ol></div>` : '';
  const note = sp.note && has(get(d, sp.note)) ? `<div class="tp-no">${esc(get(d, sp.note))}</div>` : '';
  const sign = !thermal && sp.sign ? `<div class="tp-sg">${sp.sign.map((k) => `<div>${esc(lbl(k, lg))}</div>`).join('')}</div>` : '';
  const foot = `<div class="tp-ft">${has(ctx.shop.footer) ? esc(ctx.shop.footer) : esc(lbl('thanks', lg))}</div>`;
  const css = `@page{size:${pg[0]};margin:${pg[1]}mm}` + BASE + `.tp-p${tp.page}{width:${pg[2]}mm;${thermal ? 'padding:3mm;' : ''}}` + `.tp-${tp.look} .tp-mt{grid-template-columns:repeat(${thermal ? 1 : lk.cols},1fr)}` + lk.css;
  const totBox = tots ? `<div class="tp-tot">${tots}</div>` : '';
  const two = !thermal && lk.tot === 'two' && totBox;                         // two-column summary: notes / payment info on the left, totals on the right
  const tbl = table(sp, d, thermal ? 'thermal' : lk.tbl, lg);
  const body = head(sp, lk, d, ctx, lg) + (meta ? `<div class="tp-mt">${meta}</div>` : '') + '<div style="height:4px"></div>' + tbl + sections(sp, d, lg, !thermal && lk.sec === 'cols2') + list
    + (two ? `<div class="tp-two"><div class="nt">${note}</div>${totBox}</div>` : totBox + note) + sign + foot;
  return `<style>${css}</style><div class="tp tp-${esc(tp.look)} tp-p${esc(tp.page)}" data-doc="${esc(sp.id)}" data-tpl="${esc(tp.id)}" lang="${lg === 'en' ? 'en' : 'bn'}">${body}</div>`;
}

/* ---------- public render ---------- */
T.render = (docType, data, templateId, opts) => {
  const sp = DOCS[docType]; if (!sp) return null;
  opts = opts || {};
  const id = templateId === undefined ? T.pick(docType, opts.loc) : templateId;
  if (!id) return null;                                       // no template chosen: caller keeps today's output
  const tp = sp.tpls.find((t) => t.id === id); if (!tp) return null;
  if (sp.kind === 'doc') return renderDoc(sp, tp, data, opts);
  if (sp.render) return sp.render(tp, obj(data) ? strip(data) : {}, opts, T);        // label / message types bring their own renderer
  return null;
};
T.isText = (docType) => !!DOCS[docType] && DOCS[docType].kind === 'text';
T.printHTML = (docType, data, templateId, opts) => {
  const h = T.render(docType, data, templateId, opts); if (h === null || T.isText(docType)) return null;
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(docType)}</title><style>html,body{margin:0;background:#fff}</style></head><body>${h}</body></html>`;
};
T.print = (docType, data, templateId, opts) => {      // browser only: hidden iframe, then print()
  const html = T.printHTML(docType, data, templateId, opts); if (!html || typeof document === 'undefined') return false;
  const f = document.createElement('iframe'); f.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0'; document.body.appendChild(f);
  f.srcdoc = html; f.onload = () => { try { f.contentWindow.focus(); f.contentWindow.print(); } catch (e) { /* print blocked */ } setTimeout(() => f.remove(), 2000); };
  return true;
};
})();
