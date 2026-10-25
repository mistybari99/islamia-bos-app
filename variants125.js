/* Islamia BOS · Variants (#/variants): option lists (size / colour / fabric ...), styles, the size x colour matrix, "generate variants", and channel price lists for ONE business.
   Server (supabase/phase125.sql), every call takes the business id (org unit) and is scoped by it:
     my_businesses125() -> rows {id, code, name_bn, name_en, template_code, variants_on}; variants_overview(p_org) -> {variants_on, can_manage, option_sets[{values[]}], styles[{axes[],variant_count}], price_lists[]};
     option_set_save(p_org, p_id, p_code, p_name_bn, p_name_en, p_kind, p_group, p_active, p_client); option_values_save(p_set, p_values json);
     style_save(p_org, p_id, p_code, p_name_bn, p_name_en, p_group, p_sub, p_unit, p_item_type, p_price, p_axes bigint[], p_status, p_client);
     variants_generate(p_style, p_pick, p_dry) (dry run first, then real; idempotent); variant_matrix(p_style, p_loc);
     price_list_save(p_org, p_id, p_code, p_name_bn, p_name_en, p_channel, p_from, p_to, p_active, p_client); price_list_items_set(p_list, p_rows json).
   No list, option value, size, colour or business name is written here: everything comes from the data. Variants are ordinary items, so stock / POS / purchase use them unchanged. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'v' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const num = (v) => { const s = String(v == null ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim(); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fmt = (n) => (n == null ? '' : Number(n).toLocaleString('en-US', { maximumFractionDigits: 3 }));
const nm = (o) => lab(L(o.name_bn || o.label_bn || '', o.name_en || o.label_en || o.name_bn || o.label_bn || '', o.name_bn || o.label_bn || ''));
const X = {
  title: L('ভ্যারিয়েন্ট (সাইজ / রং)', 'Variants (size / colour)', 'Variants (size / colour)'), biz: L('ব্যবসা', 'Business', 'Business'),
  tabSets: L('অপশন তালিকা', 'Option lists', 'Option lists'), tabStyles: L('স্টাইল', 'Styles', 'Styles'), tabPrices: L('দামের তালিকা', 'Price lists', 'Price lists'),
  off: L('ভ্যারিয়েন্ট সুইচ বন্ধ আছে। দেখা যায়, কিন্তু লেখা যায় না। মালিক সুইচবোর্ড থেকে চালু করবেন।', 'The variants switch is off. You can look but not change. The owner turns it on in the switchboard.', 'Variants switch off আছে। দেখা যায়, লেখা যায় না। Owner switchboard থেকে on করবেন।'),
  noperm: L('কোনো ব্যবসা পাওয়া যায়নি বা অনুমতি নেই।', 'No business found, or no permission.', 'কোনো business পাওয়া যায়নি বা অনুমতি নেই।'),
  none: L('এখনো কিছু নেই', 'Nothing yet', 'এখনো কিছু নেই'), save: L('সেভ', 'Save', 'Save'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), close: L('বন্ধ', 'Closed', 'Closed'),
  addSet: L('নতুন অপশন তালিকা', 'New option list', 'নতুন option list'), addVals: L('মান যোগ', 'Add values', 'Value যোগ'), code: L('কোড (বড় ইংরেজি অক্ষর/সংখ্যা)', 'Code (capital letters / digits)', 'Code (capital letters / digits)'),
  nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'), kind: L('ধরন', 'Kind', 'Kind'), group: L('পণ্যের গ্রুপ (ক্যাটাগরি)', 'Product group (category)', 'Product group (category)'),
  kSize: L('সাইজ', 'Size', 'Size'), kColour: L('রং', 'Colour', 'Colour'), kFabric: L('কাপড়', 'Fabric', 'Fabric'), kAge: L('বয়স', 'Age band', 'Age band'), kOther: L('অন্য', 'Other', 'Other'),
  valsHelp: L('প্রতি লাইনে একটি: কোড, বাংলা নাম, ইংরেজি নাম (নাম না দিলে কোডই নাম)। যেমন: M, মাঝারি, Medium', 'One per line: code, Bangla label, English label (label optional). Example: M, Medium, Medium', 'প্রতি line-এ একটি: code, বাংলা নাম, English নাম। যেমন: M, মাঝারি, Medium'),
  addStyle: L('নতুন স্টাইল', 'New style', 'নতুন style'), price: L('দাম (ডিফল্ট)', 'Default price', 'Default price'), axis: L('অপশন তালিকা', 'Option list', 'Option list'), none1: L('— নেই —', '— none —', '— নেই —'),
  axesHelp: L('১ম তালিকা সারি, ২য় তালিকা কলাম হবে (সর্বোচ্চ ৪টি)।', 'The 1st list makes the rows, the 2nd the columns (up to 4 lists).', '১ম list সারি, ২য় list কলাম (max ৪টি)।'),
  variants: L('ভ্যারিয়েন্ট', 'variants', 'variants'), open: L('খুলুন', 'Open', 'Open'), matrix: L('ম্যাট্রিক্স (স্টক)', 'Matrix (stock)', 'Matrix (stock)'), missing: L('এখনো তৈরি হয়নি', 'Not created yet', 'এখনো তৈরি হয়নি'),
  gen: L('ভ্যারিয়েন্ট তৈরি', 'Generate variants', 'Variants তৈরি'), check: L('আগে পরীক্ষা করুন', 'Check first', 'আগে check করুন'), make: L('তৈরি করুন', 'Create', 'তৈরি করুন'), pick: L('কোনগুলো তৈরি হবে', 'Which values', 'কোনগুলো তৈরি হবে'),
  plan: L('তৈরি হবে', 'Would create', 'তৈরি হবে'), already: L('আগেই আছে', 'already exist', 'আগেই আছে'), created: L('তৈরি হয়েছে', 'Created', 'তৈরি হয়েছে'), barcode: L('বারকোড', 'Barcode', 'Barcode'),
  addList: L('নতুন দামের তালিকা', 'New price list', 'নতুন price list'), channel: L('চ্যানেল', 'Channel', 'Channel'), retail: L('খুচরা', 'Retail', 'Retail'), wholesale: L('পাইকারি', 'Wholesale', 'Wholesale'), online: L('অনলাইন', 'Online', 'Online'),
  from: L('শুরুর ডেট', 'Valid from', 'Valid from'), to: L('শেষ ডেট (খালি = চলবে)', 'Valid to (empty = open)', 'Valid to (খালি = open)'), rows: L('সারি', 'rows', 'rows'),
  applyP: L('স্টাইলের সব ভ্যারিয়েন্টে এই দাম', 'Set one price for all variants of a style', 'Style-এর সব variant-এ এই price'), style: L('স্টাইল', 'Style', 'Style'), list: L('তালিকা', 'List', 'List'), amt: L('দাম', 'Price', 'Price'),
  itemNote: L('আইটেমের নিজের দাম বদলায় না।', 'The item\'s own price is not changed.', 'Item-এর নিজের দাম বদলায় না।'), total: L('মোট', 'Total', 'Total'), stockT: L('স্টক', 'Stock', 'Stock'),
};
const T = (k) => lab(X[k]);
const ERR = {
  variants_off: X.off, 'not allowed': L('অনুমতি নেই', 'Not allowed', 'Not allowed'), code_taken: L('এই কোড আগেই আছে (আইটেমের কোড সব ব্যবসায় আলাদা হতে হবে)', 'This code is already used (item codes are still unique across businesses)', 'This code is already used (item codes are still unique across businesses)'),
  bad_code: L('কোড ঠিক নয় (বড় ইংরেজি অক্ষর, সংখ্যা)', 'Code is not valid (capital letters and digits)', 'Code is not valid (capital letters and digits)'), bad_name: L('নাম ঠিক নয়', 'Name is not valid', 'Name is not valid'), bad_axes: L('অপশন তালিকা ঠিক নয় (১-৪টি, আলাদা)', 'Option lists are not valid (1-4, all different)', 'Option lists are not valid (1-4, all different)'),
  axes_locked: L('ভ্যারিয়েন্ট তৈরি হয়ে গেছে, তালিকা বদলানো যায় না', 'Variants exist, the lists can no longer change', 'Variants exist, the lists can no longer change'), too_many: L('একবারে ৫০০-র বেশি হবে না; কিছু মান বাদ দিন', 'More than 500 at once; leave some values out', 'More than 500 at once; leave some values out'),
  no_values: L('কোনো মান নেই; আগে অপশন তালিকায় মান যোগ করুন', 'No values; add values to the option lists first', 'No values; add values to the option lists first'), no_axes: L('স্টাইলে অপশন তালিকা নেই', 'The style has no option lists', 'The style has no option lists'),
  bad_price: L('দাম ঠিক নয়', 'Price is not valid', 'Price is not valid'), bad_date: L('ডেট ঠিক নয়', 'Date is not valid', 'Date is not valid'), bad_channel: L('চ্যানেল বাছুন', 'Choose a channel', 'Choose a channel'), bad_values: L('মান লিখুন (১-২০০ লাইন)', 'Enter values (1-200 lines)', 'Enter values (1-200 lines)'),
  style_inactive: L('স্টাইল বন্ধ', 'The style is inactive', 'The style is inactive'), client_id_needed: L('আবার চেষ্টা করুন', 'Please try again', 'Please try again'), item_not_in_business: L('আইটেম এই ব্যবসার নয়', 'The item is not in this business', 'The item is not in this business'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const KINDS = [['size', 'kSize'], ['colour', 'kColour'], ['fabric', 'kFabric'], ['age', 'kAge'], ['other', 'kOther']];
const D = { biz: [], org: null, tab: 'styles', ov: null, style: null, mx: null, client: rid() };
const cur = () => D.biz.find((b) => String(b.id) === String(D.org)) || null;
const canW = () => !!(D.ov && D.ov.can_manage && D.ov.variants_on);
const err = (m) => { const o = $('#vr_err'); if (o) { o.textContent = m; o.hidden = false; } else toast(m); };
const inp = (id, label, extra = '') => `<div><label for="${id}">${esc(label)}</label><input id="${id}" autocomplete="off" ${extra}></div>`;
const btn = (act, label, extra = '', cls = '') => `<button class="${cls}" style="min-height:44px;padding:0 14px" data-act="${act}" ${extra}>${esc(label)}</button>`;
const setOf = (id) => ((D.ov && D.ov.option_sets) || []).find((s) => String(s.id) === String(id));

async function load() {
  const b = await sb.rpc('my_businesses125'); if (b.error) throw b.error;
  D.biz = b.data || [];
  if (!cur()) D.org = D.biz[0] ? D.biz[0].id : null;
  D.ov = null;
  if (!D.org) return;
  const o = await sb.rpc('variants_overview', { p_org: D.org }); if (o.error) throw o.error;
  D.ov = o.data;
}
function head() {
  const pick = D.biz.length > 1 ? `<div><label for="vr_biz">${esc(T('biz'))}</label><select id="vr_biz">${D.biz.map((x) => `<option value="${esc(x.id)}" ${String(x.id) === String(D.org) ? 'selected' : ''}>${esc(nm(x))}</option>`).join('')}</select></div>` : '';
  const tab = (k, key) => `<button class="full ${D.tab === k ? 'primary' : ''}" style="min-height:44px" data-act="vr_tab" data-v="${k}">${esc(T(key))}</button>`;
  return `${pick}${D.ov.variants_on ? '' : `<div class="card" id="vr_off"><p class="muted">${esc(T('off'))}</p></div>`}<div class="row">${tab('sets', 'tabSets')}${tab('styles', 'tabStyles')}${tab('prices', 'tabPrices')}</div>`;
}
function setsHTML() {
  const sets = D.ov.option_sets;
  const add = canW() ? `<button class="full primary" style="min-height:44px" data-act="vr_setnew">＋ ${esc(T('addSet'))}</button>` : '';
  const rows = sets.length ? sets.map((s) => `<div class="card vr-set"><div class="row between"><b>${esc(s.code)} · ${esc(nm(s))}</b>${s.active ? '' : `<span class="chip">${esc(T('close'))}</span>`}</div>
      <div class="muted">${esc(lab(X[(KINDS.find((k) => k[0] === s.kind) || ['', 'kOther'])[1]]))}${s.product_group ? ' · ' + esc(s.product_group) : ''}</div>
      <div class="vr-vals">${s.values.map((v) => `<span class="chip" ${v.active ? '' : 'style="opacity:.5"'}>${esc(v.code)}${nm(v) && nm(v) !== v.code ? ' · ' + esc(nm(v)) : ''}</span>`).join(' ') || `<span class="muted">${esc(T('none'))}</span>`}</div>
      ${canW() ? `<div class="row">${btn('vr_valnew', T('addVals'), `data-id="${esc(s.id)}"`)}</div>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return add + rows;
}
function stylesHTML() {
  const add = canW() ? `<button class="full primary" style="min-height:44px" data-act="vr_stynew">＋ ${esc(T('addStyle'))}</button>` : '';
  const rows = D.ov.styles.length ? D.ov.styles.map((s) => `<div class="card vr-sty"><div class="row between"><b>${esc(s.code)} · ${esc(nm(s))}</b><span class="chip">${esc(s.variant_count)} ${esc(T('variants'))}</span></div>
      <div class="muted">${s.product_group ? esc(s.product_group) + ' · ' : ''}${s.base_price == null ? '' : esc(fmt(s.base_price))} ${s.status === 'inactive' ? '· ' + esc(T('close')) : ''}</div>
      <div class="row">${btn('vr_open', T('open'), `data-id="${esc(s.id)}"`)}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return add + rows;
}
function pricesHTML() {
  const add = canW() ? `<button class="full primary" style="min-height:44px" data-act="vr_plnew">＋ ${esc(T('addList'))}</button>${D.ov.price_lists.length && D.ov.styles.length ? btn('vr_papply', T('applyP'), '', 'full') : ''}` : '';
  const rows = D.ov.price_lists.length ? D.ov.price_lists.map((p) => `<div class="card vr-pl"><div class="row between"><b>${esc(p.code)} · ${esc(nm(p))}</b><span class="chip">${esc(T(p.channel))}</span></div>
      <div class="muted">${esc(p.valid_from)} → ${esc(p.valid_to || '…')} · ${esc(p.rows)} ${esc(T('rows'))} ${p.active ? '' : '· ' + esc(T('close'))}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return add + `<p class="muted">${esc(T('itemNote'))}</p>` + rows;
}
function matrixHTML() {
  const m = D.mx, ax = m.axes, cells = m.cells;
  const byKey = {}; cells.forEach((c) => { byKey[c.key] = c; });
  const cell = (k) => { const c = byKey[k]; return c ? `<td data-k="${esc(k)}" title="${esc(c.code)} · ${esc(c.barcode || '')}"><b>${esc(fmt(c.stock))}</b></td>` : `<td data-k="${esc(k)}" class="muted">–</td>`; };
  let body;
  if (ax.length === 2) {
    const [r, c] = ax;
    body = `<div style="overflow-x:auto"><table class="vr-mx" style="border-collapse:collapse;width:100%"><thead><tr><th></th>${c.values.map((v) => `<th style="padding:4px;text-align:center">${esc(nm(v))}</th>`).join('')}</tr></thead>
      <tbody>${r.values.map((rv) => `<tr><th style="padding:4px;text-align:left">${esc(nm(rv))}</th>${c.values.map((cv) => cell(rv.code + '|' + cv.code)).join('')}</tr>`).join('')}</tbody></table></div>`;
  } else {
    body = cells.length ? cells.map((c) => `<div class="row between"><span>${esc(c.code)}</span><b>${esc(fmt(c.stock))}</b></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  }
  return `<div class="card" id="vr_matrix"><b>${esc(T('matrix'))}</b> <span class="muted">${esc(cells.length)} ${esc(T('variants'))}</span>${body}</div>`;
}
function styleHTML() {
  const s = D.mx.style;
  const axes = D.mx.axes.map((a, i) => `<div><b>${esc(nm(a))}</b><div class="row" style="flex-wrap:wrap">${a.values.filter((v) => v.active).map((v) => `<label style="display:inline-flex;gap:4px;align-items:center;min-height:40px"><input type="checkbox" class="vr-pick" data-set="${esc(a.code)}" value="${esc(v.code)}" checked> ${esc(nm(v))}</label>`).join('')}</div></div>`).join('');
  return `<div class="row between"><b>${esc(s.code)} · ${esc(nm(s))}</b>${btn('vr_back', '←')}</div>${matrixHTML()}
    ${canW() ? `<div class="card stack" id="vr_gen"><b>${esc(T('gen'))}</b><span class="muted">${esc(T('pick'))}</span>${axes}
      <div class="row">${btn('vr_dry', T('check'), '', 'full')}${btn('vr_make', T('make'), '', 'full primary')}</div><div id="vr_out" class="muted"></div></div>` : ''}`;
}
function draw() {
  const el = $('#vr_body'); if (!el) return;
  if (!cur() || !D.ov) { el.innerHTML = `<div class="card" id="vr_noperm"><p class="muted">${esc(T('noperm'))}</p></div>`; return; }
  if (D.mx) { el.innerHTML = styleHTML(); return; }
  el.innerHTML = head() + (D.tab === 'sets' ? setsHTML() : D.tab === 'prices' ? pricesHTML() : stylesHTML());
}
async function refresh() { await load(); if (D.style && D.ov) await loadMx(); draw(); }
async function loadMx() { const r = await sb.rpc('variant_matrix', { p_style: D.style, p_loc: null }); if (r.error) throw r.error; D.mx = r.data; }

function setSheet() {
  D.client = rid();
  openSheet(`<h3>${esc(T('addSet'))}</h3><div class="stack" id="vr_form">${inp('vr_c', T('code'), 'maxlength="24" autocapitalize="characters"')}${inp('vr_bn', T('nbn'), 'maxlength="80"')}${inp('vr_en', T('nen'), 'maxlength="80"')}
    <div><label for="vr_k">${esc(T('kind'))}</label><select id="vr_k">${KINDS.map(([k, key]) => `<option value="${k}">${esc(T(key))}</option>`).join('')}</select></div>${inp('vr_g', T('group'), 'maxlength="80"')}
    <p id="vr_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="vr_set_save">${esc(T('save'))}</button></div>`);
}
function valSheet(id) {
  const s = setOf(id);
  openSheet(`<h3>${esc(s ? s.code : '')} · ${esc(T('addVals'))}</h3><div class="stack"><p class="muted">${esc(T('valsHelp'))}</p><textarea id="vr_vals" rows="6" style="width:100%" placeholder="S, ছোট, Small&#10;M, মাঝারি, Medium"></textarea>
    <p id="vr_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="vr_val_save" data-id="${esc(id)}">${esc(T('save'))}</button></div>`);
}
function styleSheet() {
  D.client = rid(); const sets = D.ov.option_sets.filter((s) => s.active);
  const sel = (i) => `<div><label for="vr_ax${i}">${esc(T('axis'))} ${i}</label><select id="vr_ax${i}"><option value="">${esc(T('none1'))}</option>${sets.map((s) => `<option value="${esc(s.id)}">${esc(s.code)} · ${esc(nm(s))}</option>`).join('')}</select></div>`;
  openSheet(`<h3>${esc(T('addStyle'))}</h3><div class="stack">${inp('vr_c', T('code'), 'maxlength="24" autocapitalize="characters"')}${inp('vr_bn', T('nbn'), 'maxlength="120"')}${inp('vr_en', T('nen'), 'maxlength="120"')}
    ${inp('vr_g', T('group'), 'maxlength="80"')}${inp('vr_p', T('price'), 'inputmode="decimal"')}<p class="muted">${esc(T('axesHelp'))}</p>${[1, 2, 3, 4].map(sel).join('')}
    <p id="vr_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="vr_sty_save">${esc(T('save'))}</button></div>`);
}
function listSheet() {
  D.client = rid();
  openSheet(`<h3>${esc(T('addList'))}</h3><div class="stack">${inp('vr_c', T('code'), 'maxlength="24" autocapitalize="characters"')}${inp('vr_bn', T('nbn'), 'maxlength="80"')}${inp('vr_en', T('nen'), 'maxlength="80"')}
    <div><label for="vr_ch">${esc(T('channel'))}</label><select id="vr_ch"><option value="retail">${esc(T('retail'))}</option><option value="wholesale">${esc(T('wholesale'))}</option><option value="online">${esc(T('online'))}</option></select></div>
    <div><label for="vr_from">${esc(T('from'))}</label><input id="vr_from" type="date"></div><div><label for="vr_to">${esc(T('to'))}</label><input id="vr_to" type="date"></div>
    <p id="vr_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="vr_pl_save">${esc(T('save'))}</button></div>`);
}
function applySheet() {
  openSheet(`<h3>${esc(T('applyP'))}</h3><div class="stack"><div><label for="vr_pl">${esc(T('list'))}</label><select id="vr_pl">${D.ov.price_lists.filter((p) => p.active).map((p) => `<option value="${esc(p.id)}">${esc(p.code)} · ${esc(T(p.channel))}</option>`).join('')}</select></div>
    <div><label for="vr_ps">${esc(T('style'))}</label><select id="vr_ps">${D.ov.styles.map((s) => `<option value="${esc(s.id)}">${esc(s.code)} · ${esc(nm(s))}</option>`).join('')}</select></div>${inp('vr_pa', T('amt'), 'inputmode="decimal"')}
    <p class="muted">${esc(T('itemNote'))}</p><p id="vr_err" class="muted" role="alert" hidden></p><button class="full primary" data-act="vr_apply_save">${esc(T('save'))}</button></div>`);
}
const pickOf = () => {
  const boxes = [...document.querySelectorAll('#vr_gen .vr-pick')]; if (!boxes.length || boxes.every((b) => b.checked)) return null;
  const o = {}; boxes.forEach((b) => { (o[b.dataset.set] = o[b.dataset.set] || []); if (b.checked) o[b.dataset.set].push(b.value); }); return o;
};
async function gen(dry) {
  const r = await sb.rpc('variants_generate', { p_style: D.style, p_pick: pickOf(), p_dry: !!dry });
  const out = $('#vr_out'); if (r.error) { if (out) out.textContent = eText(r.error); return toast(eText(r.error)); }
  const d = r.data || {};
  if (dry) { if (out) out.textContent = `${T('plan')}: ${d.would_create} · ${d.existing} ${T('already')}`; return; }
  toast(`${T('created')}: ${d.created}`); await refresh();
}
Object.assign(H, {
  vr_tab: (a) => { D.tab = a.dataset.v; draw(); },
  vr_setnew: () => setSheet(), vr_valnew: (a) => valSheet(a.dataset.id), vr_stynew: () => styleSheet(), vr_plnew: () => listSheet(), vr_papply: () => applySheet(),
  vr_open: async (a) => { D.style = Number(a.dataset.id); try { await loadMx(); draw(); } catch (e) { fail(e); } },
  vr_back: () => { D.style = null; D.mx = null; draw(); },
  vr_dry: () => gen(true), vr_make: () => gen(false),
  vr_set_save: async () => {
    const c = $('#vr_c').value.trim().toUpperCase(); if (!c) return err(lab(ERR.bad_code)); if (!$('#vr_bn').value.trim()) return err(lab(ERR.bad_name));
    const r = await sb.rpc('option_set_save', { p_org: D.org, p_id: null, p_code: c, p_name_bn: $('#vr_bn').value.trim(), p_name_en: $('#vr_en').value.trim() || null, p_kind: $('#vr_k').value, p_group: $('#vr_g').value.trim() || null, p_active: true, p_client: D.client });
    if (r.error) return err(eText(r.error)); closeSheet(); toast(T('saved')); await refresh(); },
  vr_val_save: async (a) => {
    const vals = []; for (const line of $('#vr_vals').value.split('\n')) { const p = line.split(',').map((x) => x.trim()); if (!p[0]) continue; vals.push({ code: p[0].toUpperCase(), label_bn: p[1] || p[0].toUpperCase(), label_en: p[2] || null, sort: (vals.length + 1) * 10 }); }
    if (!vals.length || vals.length > 200) return err(lab(ERR.bad_values));
    const r = await sb.rpc('option_values_save', { p_set: Number(a.dataset.id), p_values: vals });
    if (r.error) return err(eText(r.error)); closeSheet(); toast(T('saved')); await refresh(); },
  vr_sty_save: async () => {
    const c = $('#vr_c').value.trim().toUpperCase(); if (!c) return err(lab(ERR.bad_code)); if (!$('#vr_bn').value.trim()) return err(lab(ERR.bad_name));
    const axes = [1, 2, 3, 4].map((i) => $('#vr_ax' + i).value).filter(Boolean).map(Number); if (!axes.length) return err(lab(ERR.bad_axes));
    const pr = num($('#vr_p').value); if (Number.isNaN(pr) || (pr !== null && pr < 0)) return err(lab(ERR.bad_price));
    const r = await sb.rpc('style_save', { p_org: D.org, p_id: null, p_code: c, p_name_bn: $('#vr_bn').value.trim(), p_name_en: $('#vr_en').value.trim() || null, p_group: $('#vr_g').value.trim() || null, p_sub: null,
      p_unit: 'pc', p_item_type: 'resale', p_price: pr, p_axes: axes, p_status: 'active', p_client: D.client });
    if (r.error) return err(eText(r.error)); closeSheet(); toast(T('saved')); await refresh(); },
  vr_pl_save: async () => {
    const c = $('#vr_c').value.trim().toUpperCase(); if (!c) return err(lab(ERR.bad_code)); if (!$('#vr_bn').value.trim()) return err(lab(ERR.bad_name));
    const r = await sb.rpc('price_list_save', { p_org: D.org, p_id: null, p_code: c, p_name_bn: $('#vr_bn').value.trim(), p_name_en: $('#vr_en').value.trim() || null, p_channel: $('#vr_ch').value,
      p_from: $('#vr_from').value || null, p_to: $('#vr_to').value || null, p_active: true, p_client: D.client });
    if (r.error) return err(eText(r.error)); closeSheet(); toast(T('saved')); await refresh(); },
  vr_apply_save: async () => {
    const pr = num($('#vr_pa').value); if (pr === null || Number.isNaN(pr) || pr < 0) return err(lab(ERR.bad_price));
    const m = await sb.rpc('variant_matrix', { p_style: Number($('#vr_ps').value), p_loc: null }); if (m.error) return err(eText(m.error));
    const rows = (m.data.cells || []).map((c) => ({ item_id: c.item_id, price: pr })); if (!rows.length) return err(lab(X.none));
    const r = await sb.rpc('price_list_items_set', { p_list: Number($('#vr_pl').value), p_rows: rows });
    if (r.error) return err(eText(r.error)); closeSheet(); toast(T('saved')); await refresh(); },
});
document.addEventListener('change', (e) => { if (e.target.id === 'vr_biz') { D.org = Number(e.target.value); D.style = null; D.mx = null; refresh().catch(fail); } });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="vr_body" class="stack"><p class="muted">…</p></div>', true);
  try { await refresh(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { variants: view });
})();
