/* Islamia BOS · Tinting machine (#/tinting): shade formulas (a shade code for one base item and pack, colorants with the quantity per pack, versions - a change makes a new version),
   tint jobs (base + colorants are taken from stock; a check first shows quantities, stock on hand and shortages, and the cost for people who may see cost), the customer's shade history,
   void, and the cost per shade. Server: supabase/phase129.sql (tint_formula_save / tint_formula_list / tint_job_run with p_dry / tint_job_void / tint_job_list / tint_customer_shades /
   tint_cost_report). Stock is moved by the existing stock function on the server; this screen never computes stock or cost itself. Switch: dealer_tint_on. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const { money, nnum, rid, LOCS } = B.s2;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('টিন্টিং মেশিন', 'Tinting machine', 'Tinting machine'), biz: L('ব্যবসা', 'Business', 'Business'), loc: L('জায়গা', 'Location', 'Location'),
  tJ: L('জব', 'Jobs', 'Jobs'), tF: L('ফর্মুলা', 'Formulas', 'Formulas'), tN: L('নতুন ফর্মুলা', 'New formula', 'নতুন formula'), tC: L('খরচ', 'Cost', 'Cost'),
  formula: L('ফর্মুলা', 'Formula', 'Formula'), packs: L('প্যাক সংখ্যা', 'Packs', 'Packs'), customer: L('গ্রাহক', 'Customer', 'Customer'), walkin: L('নাম (গ্রাহক না থাকলে)', 'Name (no customer)', 'Name (customer না থাকলে)'),
  charge: L('গ্রাহকের কাছে নেওয়া টাকা', 'Amount charged', 'Charged amount'), note: L('নোট', 'Note', 'Note'), check: L('আগে দেখুন (স্টক কাটবে না)', 'Check first (no stock is used)', 'Check (stock কাটবে না)'),
  run: L('জব চালান', 'Run the job', 'Job চালান'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), pick: L('— বাছুন —', '— choose —', '— বাছুন —'),
  base: L('বেস', 'Base', 'Base'), colorant: L('কালারেন্ট', 'Colorant', 'Colorant'), onhand: L('স্টকে আছে', 'On hand', 'On hand'), short: L('কম পড়বে', 'short', 'short'), estCost: L('আনুমানিক খরচ', 'Estimated cost', 'Estimated cost'),
  noSave: L('কিছু লেখা হয়নি', 'nothing was saved', 'কিছু লেখা হয়নি'), done: L('জব হয়েছে', 'Job done', 'Job হয়েছে'), cost: L('খরচ', 'Cost', 'Cost'), void: L('ভয়েড', 'Void', 'Void'), why: L('কারণ', 'Reason', 'Reason'),
  history: L('এই গ্রাহকের শেড', 'Shades of this customer', 'এই customer-এর shade'), jobs: L('জব', 'jobs', 'jobs'),
  shade: L('শেড কোড', 'Shade code', 'Shade code'), shadeName: L('শেডের নাম', 'Shade name', 'Shade name'), baseCode: L('বেস আইটেমের কোড', 'Base item code', 'Base item code'), pack: L('প্যাক (যেমন 4L)', 'Pack (e.g. 4L)', 'Pack (e.g. 4L)'),
  baseQty: L('প্রতি প্যাকে বেস কত', 'Base used per pack', 'Base per pack'), lines: L('কালারেন্ট (প্রতি লাইনে: আইটেম কোড, প্রতি প্যাকে পরিমাণ)', 'Colorants (one per line: item code, quantity per pack)', 'Colorants (প্রতি line: item code, qty per pack)'),
  save: L('সেভ', 'Save', 'Save'), version: L('ভার্সন', 'version', 'version'), retired: L('বাতিল ভার্সন', 'retired', 'retired'), active: L('চালু', 'active', 'active'),
  e_feature_off: L('টিন্টিং সুইচ বন্ধ আছে (মালিক সুইচবোর্ডে চালু করবেন)', 'Tinting is switched off (the owner turns it on in the switchboard)', 'Tinting off আছে (owner switchboard-এ on করবেন)'),
  e_not_allowed: L('এই জায়গায় আপনার অনুমতি নেই', 'You are not allowed here', 'এই জায়গায় permission নেই'), e_insufficient_stock: L('স্টকে কম আছে, জব হয়নি', 'Not enough stock, the job was not made', 'Stock কম, job হয়নি'),
  e_bad_packs: L('প্যাক সংখ্যা ঠিক নয়', 'The number of packs is not valid', 'Packs ঠিক নয়'), e_bad_date: L('ডেট ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'), e_formula_retired: L('এই ভার্সন বাতিল, নতুনটা বাছুন', 'This version is retired, choose the new one', 'এই version retired, নতুনটা বাছুন'),
  e_period_closed: L('এই মাসের হিসাব বন্ধ', 'This period is closed', 'এই মাসের হিসাব বন্ধ'), e_reason_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'), e_item_not_found: L('আইটেম কোড পাওয়া যায়নি', 'An item code was not found', 'Item code পাওয়া যায়নি'),
  e_lines_required: L('কালারেন্ট দিন', 'Enter the colorants', 'Colorants দিন'), e_bad_qty: L('পরিমাণ ঠিক নয়', 'A quantity is not valid', 'Quantity ঠিক নয়'), e_duplicate_colorant: L('একই কালারেন্ট দুবার', 'The same colorant twice', 'একই colorant দুবার'),
  e_colorant_is_base: L('বেসই কালারেন্ট হতে পারে না', 'The base cannot be a colorant', 'Base-ই colorant হতে পারে না'), e_shade_code_required: L('শেড কোড দিন', 'Enter the shade code', 'Shade code দিন'),
};
const T = (k) => lab(X[k]);
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? lab(X[k]) : m || 'error'; };
const D = { tab: 'j', biz: null, bizs: [], locBiz: {}, forms: [], jobs: [], cust: [], cost: [], itm: {}, hist: [], out: '', client: rid(), err: null, costErr: null };
const iname = (id) => { const i = D.itm[id]; return i ? (i.code + ' ' + (lab(L(i.name_bn, i.name_en || i.name_bn, i.name_mix || i.name_bn)) || '')).trim() : String(id).slice(0, 8); };

async function businesses() {
  const out = new Map(); D.locBiz = {};
  await Promise.all(LOCS().map(async (l) => { const r = await sb.rpc('org_unit_scope', { p_location: l.id }); const d = r.data; if (d && d.business_id) { D.locBiz[l.id] = d.business_id; if (!out.has(d.business_id)) out.set(d.business_id, d.business_code || String(d.business_id)); } }));
  D.bizs = [...out.entries()].map(([id, code]) => ({ id, code })); if (!D.biz || !D.bizs.find((b) => b.id === D.biz)) D.biz = (D.bizs[0] || {}).id || null;
}
async function names(ids) {
  const miss = [...new Set(ids)].filter((i) => i && !D.itm[i]); if (!miss.length) return;
  const r = await sb.from('items').select('id,code,name_bn,name_en,name_mix').in('id', miss); (r.data || []).forEach((i) => { D.itm[i.id] = i; });
}
async function load() {
  D.err = null; if (!D.biz) { D.forms = D.jobs = D.cost = []; return; }
  const [f, j, c, cu] = await Promise.all([sb.rpc('tint_formula_list', { p_business: D.biz, p_shade: null, p_status: null }), sb.rpc('tint_job_list', { p_business: D.biz, p_from: null, p_to: null, p_customer: null, p_limit: 100 }),
    sb.rpc('tint_cost_report', { p_business: D.biz, p_from: null, p_to: null }), sb.from('customers').select('id,name,mobile').order('name').limit(500)]);
  D.forms = f.data || []; D.jobs = j.data || []; D.cost = c.data || []; D.costErr = c.error || null; D.cust = cu.data || []; if (f.error) D.err = f.error;
  await names(D.forms.map((x) => x.base_item_id).concat(D.jobs.map((x) => x.base_item_id)));
}
const chip = (s, c) => `<span class="chip ${c || ''}">${esc(s)}</span>`;
function jobForm() {
  const act = D.forms.filter((f) => f.status === 'active'), locs = LOCS().filter((l) => D.locBiz[l.id] === D.biz);
  return `<div class="card stack">
    <div><label for="tj_loc">${esc(T('loc'))}</label><select id="tj_loc">${locs.map((l) => `<option value="${l.id}">${esc(nm(l))}</option>`).join('')}</select></div>
    <div><label for="tj_f">${esc(T('formula'))}</label><select id="tj_f"><option value="">${esc(T('pick'))}</option>${act.map((f) => `<option value="${esc(f.id)}">${esc(f.shade_code)} · ${esc(iname(f.base_item_id))}${f.pack_label ? ' · ' + esc(f.pack_label) : ''} · ${esc(T('version'))} ${f.version}</option>`).join('')}</select></div>
    <div><label for="tj_p">${esc(T('packs'))}</label><input id="tj_p" inputmode="decimal" autocomplete="off" value="1"></div>
    <div><label for="tj_c">${esc(T('customer'))}</label><select id="tj_c"><option value="">${esc(T('pick'))}</option>${D.cust.map((c) => `<option value="${esc(c.id)}">${esc(c.name)} · ${esc(c.mobile || '')}</option>`).join('')}</select></div>
    <div><label for="tj_n">${esc(T('walkin'))}</label><input id="tj_n" autocomplete="off"></div>
    <div><label for="tj_ch">${esc(T('charge'))}</label><input id="tj_ch" inputmode="decimal" autocomplete="off"></div>
    <div><label for="tj_note">${esc(T('note'))}</label><input id="tj_note" autocomplete="off"></div>
    <div class="row"><button class="full" data-act="tj_check">${esc(T('check'))}</button><button class="full primary" data-act="tj_run">${esc(T('run'))}</button></div></div>`;
}
function linesH(x) {
  return (x.lines || []).map((l) => `<div class="row between wrap"><span>${esc(T(l.role === 'base' ? 'base' : 'colorant'))} · ${esc(iname(l.item_id))}</span><span><b>${esc(String(l.qty))}</b> · ${esc(T('onhand'))} ${esc(String(l.on_hand))}${l.short ? ' ' + chip(T('short'), 'bad') : ''}</span></div>`).join('')
    + (x.estimated_cost !== null && x.estimated_cost !== undefined ? `<div>${esc(T('estCost'))}: <b>${money(x.estimated_cost)}</b></div>` : '');
}
function draw() {
  const el = $('#tn_body'); if (!el) return;
  const bizSel = D.bizs.length > 1 ? `<div class="card"><label for="tn_biz">${esc(T('biz'))}</label><select id="tn_biz">${D.bizs.map((b) => `<option value="${b.id}" ${b.id === D.biz ? 'selected' : ''}>${esc(b.code)}</option>`).join('')}</select></div>` : '';
  const tabs = [['j', 'tJ'], ['f', 'tF'], ['n', 'tN'], ['c', 'tC']];
  const bar = `<div class="row wrap">${tabs.map(([k, l]) => `<button class="mini ${D.tab === k ? 'primary' : ''}" data-act="tn_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
  const out = D.out ? `<div class="notice" id="tn_out">${D.out}</div>` : '';
  let body = '';
  if (D.err) body = `<div class="notice warn">${esc(eText(D.err))}</div>`;
  else if (D.tab === 'j') {
    body = jobForm() + (D.jobs.length ? D.jobs.map((j) => `<div class="card ${j.status === 'void' ? 'muted' : ''}"><div class="row between wrap"><b>#${esc(String(j.job_no))} · ${esc(j.shade_code)}</b><b>${esc(String(j.packs))}</b></div>
      <div class="muted">${esc(j.job_date)} · ${esc(iname(j.base_item_id))} · ${esc(j.customer_name || '')}</div><div class="row between wrap"><span>${j.charge_amount !== null && j.charge_amount !== undefined ? money(j.charge_amount) : ''}</span>${j.status === 'void' ? chip(T('void'), 'bad') : `<span><button class="mini" data-act="tn_hist" data-v="${esc(j.customer_id || '')}">${esc(T('history'))}</button><button class="mini" data-act="tn_void" data-v="${esc(j.id)}">${esc(T('void'))}</button></span>`}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
    if (D.hist.length) body += `<div class="card"><b>${esc(T('history'))}</b>${D.hist.map((h) => `<div class="row between wrap"><span>${esc(h.shade_code)}</span><span>${esc(String(h.jobs))} ${esc(T('jobs'))} · ${esc(String(h.packs))} · ${esc(h.last_date)}</span></div>`).join('')}</div>`;
  } else if (D.tab === 'f') body = D.forms.length ? D.forms.map((f) => `<div class="card"><div class="row between wrap"><b>${esc(f.shade_code)}${f.shade_name ? ' · ' + esc(f.shade_name) : ''}</b>${chip(f.status === 'active' ? T('active') : T('retired'), f.status === 'active' ? 'ok' : '')}</div>
      <div class="muted">${esc(iname(f.base_item_id))}${f.pack_label ? ' · ' + esc(f.pack_label) : ''} · ${esc(T('baseQty'))}: ${esc(String(f.base_qty_per_pack))} · ${esc(T('version'))} ${f.version} · ${esc(String(f.colorants))} ${esc(T('colorant'))}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  else if (D.tab === 'c') body = D.costErr ? `<div class="notice warn">${esc(eText(D.costErr))}</div>` : D.cost.length ? D.cost.map((c) => `<div class="card"><div class="row between wrap"><b>${esc(c.shade_code)}</b><b>${money(c.cost_total)}</b></div><div class="muted">${esc(String(c.jobs))} ${esc(T('jobs'))} · ${esc(String(c.packs))} · ${money(c.cost_per_pack)} / pack</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  else body = `<div class="card stack">
    <div><label for="tf_code">${esc(T('shade'))}</label><input id="tf_code" autocomplete="off"></div><div><label for="tf_name">${esc(T('shadeName'))}</label><input id="tf_name" autocomplete="off"></div>
    <div><label for="tf_base">${esc(T('baseCode'))}</label><input id="tf_base" autocomplete="off"></div><div><label for="tf_pack">${esc(T('pack'))}</label><input id="tf_pack" autocomplete="off"></div>
    <div><label for="tf_bq">${esc(T('baseQty'))}</label><input id="tf_bq" inputmode="decimal" value="1"></div>
    <div><label for="tf_lines">${esc(T('lines'))}</label><textarea id="tf_lines" rows="4" placeholder="I-101, 12.5&#10;I-102, 7.25"></textarea></div>
    <button class="full primary" data-act="tn_fsave">${esc(T('save'))}</button></div>`;
  el.innerHTML = bizSel + bar + out + body;
}
async function show() { await load(); draw(); }
const jobArgs = (dry) => ({ p_client: dry ? rid() : D.client, p_loc: Number($('#tj_loc').value), p_formula: $('#tj_f').value, p_packs: nnum($('#tj_p').value), p_customer: $('#tj_c').value || null, p_customer_name: $('#tj_n').value.trim() || null,
  p_date: null, p_charge: $('#tj_ch').value ? nnum($('#tj_ch').value) : null, p_note: $('#tj_note').value.trim() || null, p_dry: !!dry });
async function codesToIds(codes) { const r = await sb.from('items').select('id,code').in('code', codes); const m = {}; (r.data || []).forEach((i) => { m[i.code] = i.id; }); return m; }
Object.assign(H, {
  tn_tab: (a) => { D.tab = a.dataset.v; D.out = ''; draw(); },
  tj_check: async () => {
    if (!$('#tj_f').value) return;
    const ids = ['tj_loc', 'tj_f', 'tj_p', 'tj_c', 'tj_n', 'tj_ch', 'tj_note'], keep = ids.map((id) => [id, $('#' + id).value]);
    const r = await sb.rpc('tint_job_run', jobArgs(true)); if (r.error) return toast(eText(r.error));
    await names((r.data.lines || []).map((l) => l.item_id)); D.out = linesH(r.data) + `<div class="muted">${esc(T('noSave'))}</div>`; draw();
    keep.forEach(([id, v]) => { const e = $('#' + id); if (e) e.value = v; });
  },
  tj_run: async () => {
    if (!$('#tj_f').value) return;
    const r = await sb.rpc('tint_job_run', jobArgs(false)); if (r.error) return toast(eText(r.error));
    D.client = rid(); D.out = ''; toast(T('done')); await show();
  },
  tn_void: async (a) => { const why = window.prompt(T('why')); if (!why || !why.trim()) return toast(lab(X.e_reason_required)); const r = await sb.rpc('tint_job_void', { p_job: a.dataset.v, p_client: rid(), p_reason: why.trim() }); if (r.error) return toast(eText(r.error)); toast(T('saved')); await show(); },
  tn_hist: async (a) => { if (!a.dataset.v) return; const r = await sb.rpc('tint_customer_shades', { p_customer: a.dataset.v, p_business: D.biz }); if (r.error) return toast(eText(r.error)); D.hist = r.data || []; draw(); },
  tn_fsave: async () => {
    const base = $('#tf_base').value.trim(), rows = $('#tf_lines').value.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => l.split(',').map((x) => x.trim()));
    const ids = await codesToIds([base].concat(rows.map((r) => r[0])).filter(Boolean));
    if (!ids[base] || rows.some((r) => !ids[r[0]])) return toast(lab(X.e_item_not_found));
    const r = await sb.rpc('tint_formula_save', { p_client: D.client, p_business: D.biz, p_shade_code: $('#tf_code').value, p_shade_name: $('#tf_name').value.trim() || null, p_base_item: ids[base], p_pack_label: $('#tf_pack').value.trim() || null,
      p_base_qty: nnum($('#tf_bq').value), p_lines: rows.map((x) => ({ item: ids[x[0]], qty: nnum(x[1]) })), p_note: null });
    if (r.error) return toast(eText(r.error));
    D.client = rid(); toast(T('saved')); D.tab = 'f'; await show();
  },
});
document.addEventListener('change', async (e) => { if (e.target.id === 'tn_biz') { D.biz = Number(e.target.value); D.out = ''; D.hist = []; await show(); } });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="tn_body"><p class="muted">…</p></div>', true);
  try { await businesses(); await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { tinting: view });
})();
