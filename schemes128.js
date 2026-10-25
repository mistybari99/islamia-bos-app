/* Islamia BOS · Principal schemes (#/schemes): schemes of a principal (slab / target rebate / flat per pack, purchase or sale basis, period), a PREVIEW of what has been earned so far
   (nothing is written), accrual, the claim register to the principal (claim, receipt, reject) and the accrued vs claimed vs received report. Server: supabase/phase128.sql
   (scheme_save / scheme_activate / scheme_accrue with p_dry / scheme_close / claim_create / claim_receive / claim_reject / scheme_list / claim_list / scheme_reconciliation).
   Amounts come only from the rules the owner enters here; the principal is a supplier row (no name is built in). Switch: dealer_scheme_on. One business at a time. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, esc, toast, fail, shell, H, nm } = A;
const L = B.L, lab = B.lab;
const { money, nnum, rid, LOCS } = B.s2;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const X = {
  title: L('প্রিন্সিপাল স্কিম ও ক্লেইম', 'Principal schemes & claims', 'Principal scheme ও claim'), biz: L('ব্যবসা', 'Business', 'Business'),
  tS: L('স্কিম', 'Schemes', 'Schemes'), tC: L('ক্লেইম', 'Claims', 'Claims'), tR: L('মিলানো', 'Reconcile', 'Reconcile'), tN: L('নতুন স্কিম', 'New scheme', 'নতুন scheme'),
  principal: L('প্রিন্সিপাল (সাপ্লায়ার)', 'Principal (supplier)', 'Principal (supplier)'), name: L('স্কিমের নাম', 'Scheme name', 'Scheme নাম'), kind: L('ধরন', 'Kind', 'Kind'),
  slab: L('স্ল্যাব', 'Slab', 'Slab'), target: L('টার্গেট রিবেট', 'Target rebate', 'Target rebate'), flat: L('প্যাক প্রতি ফ্ল্যাট', 'Flat per pack', 'Flat per pack'),
  basis: L('ভিত্তি', 'Basis', 'Basis'), purchase: L('কেনা', 'Purchases', 'Purchases'), sale: L('বিক্রি', 'Sales', 'Sales'), measure: L('মাপ', 'Measured by', 'Measured by'),
  value: L('টাকা', 'Value', 'Value'), qty: L('পরিমাণ', 'Quantity', 'Quantity'), from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'),
  mode: L('স্ল্যাব নিয়ম', 'Slab rule', 'Slab rule'), whole: L('পুরো টাকায় (যে স্ল্যাবে পড়ে)', 'Whole value at the slab reached', 'Whole value'), marginal: L('টুকরো টুকরো করে', 'Each slice at its own rate', 'Marginal'),
  slabs: L('স্ল্যাব (প্রতি লাইনে: থেকে, পর্যন্ত, হার%)', 'Slabs (one per line: from, to, rate %)', 'Slabs (প্রতি line: from, to, rate %)'),
  tgt: L('টার্গেট', 'Target', 'Target'), pct: L('রিবেট %', 'Rebate %', 'Rebate %'), flatAmt: L('ফ্ল্যাট টাকা', 'Flat amount', 'Flat amount'), perPack: L('প্যাক প্রতি টাকা', 'Per pack amount', 'Per pack amount'),
  items: L('আইটেম কোড (কমা দিয়ে, খালি = সব)', 'Item codes (comma separated, empty = all)', 'Item codes (comma, খালি = সব)'), note: L('নোট', 'Note', 'Note'),
  save: L('সেভ (ড্রাফট)', 'Save (draft)', 'Save (draft)'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing yet', 'কিছু নেই'), pick: L('— বাছুন —', '— choose —', '— বাছুন —'),
  activate: L('চালু করুন', 'Activate', 'Activate'), preview: L('হিসাব দেখুন (কিছু লেখা হবে না)', 'Preview (nothing is saved)', 'Preview (কিছু লেখা হবে না)'), accrue: L('হিসাবে তুলুন', 'Accrue', 'Accrue'),
  close: L('বন্ধ করুন', 'Close', 'Close'), claim: L('ক্লেইম', 'Claim', 'Claim'), receive: L('টাকা পেলাম', 'Received', 'Received'), reject: L('প্রত্যাখ্যাত', 'Rejected', 'Rejected'),
  amt: L('টাকা', 'Amount', 'Amount'), claimNo: L('ক্লেইম নম্বর', 'Claim no.', 'Claim no.'), why: L('কারণ', 'Reason', 'Reason'), ref: L('রেফারেন্স', 'Reference', 'Reference'),
  base: L('ভিত্তি অঙ্ক', 'Base', 'Base'), earned: L('অর্জিত', 'Earned', 'Earned'), already: L('আগে তোলা', 'Already accrued', 'Already accrued'), delta: L('এবার যোগ', 'This time', 'This time'), nothingSaved: L('কিছু লেখা হয়নি', 'nothing was saved', 'কিছু লেখা হয়নি'),
  accrued: L('অর্জিত (তোলা)', 'Accrued', 'Accrued'), claimed: L('ক্লেইম করা', 'Claimed', 'Claimed'), received: L('পাওয়া', 'Received', 'Received'), unclaimed: L('ক্লেইম বাকি', 'Unclaimed', 'Unclaimed'),
  outstanding: L('পাওনা আছে', 'Outstanding', 'Outstanding'), over: L('বেশি ক্লেইম', 'Over-claimed', 'Over-claimed'), ok: L('ঠিক আছে', 'OK', 'OK'), confirm: L('তুলবেন?', 'Accrue now?', 'Accrue করবেন?'),
  e_feature_off: L('স্কিম সুইচ বন্ধ আছে (মালিক সুইচবোর্ডে চালু করবেন)', 'Schemes are switched off (the owner turns them on in the switchboard)', 'Scheme off আছে (owner switchboard-এ on করবেন)'),
  e_not_allowed: L('এই ব্যবসায় আপনার অনুমতি নেই', 'You are not allowed in this business', 'এই business-এ permission নেই'), e_exceeds_accrual: L('তোলা অঙ্কের চেয়ে বেশি ক্লেইম করা যায় না', 'A claim cannot be more than what is accrued and unclaimed', 'Accrued-এর চেয়ে বেশি claim করা যায় না'),
  e_overpaid: L('পাওয়ার অঙ্ক ক্লেইমের চেয়ে বেশি', 'More than the claim outstanding', 'Claim-এর চেয়ে বেশি'), e_scheme_frozen: L('চালু স্কিম বদলানো যায় না', 'An active scheme cannot be changed', 'Active scheme বদলানো যায় না'),
  e_bad_status: L('এই অবস্থায় এটা করা যায় না', 'Not possible in this status', 'এই status-এ করা যায় না'), e_slab_overlap: L('স্ল্যাব মিলে গেছে', 'Slabs overlap', 'Slabs overlap'), e_bad_slab: L('স্ল্যাবের লাইন ঠিক নয়', 'A slab line is not valid', 'Slab line ঠিক নয়'),
  e_slabs_required: L('স্ল্যাব দিন', 'Enter the slabs', 'Slabs দিন'), e_sale_scheme_needs_items: L('বিক্রি-ভিত্তিক স্কিমে আইটেম দিতে হবে', 'A sales-based scheme needs items', 'Sale-based scheme-এ items লাগবে'),
  e_bad_period: L('মেয়াদ ঠিক নয়', 'The period is not valid', 'Period ঠিক নয়'), e_period_closed: L('এই মাসের হিসাব বন্ধ', 'This period is closed', 'এই মাসের হিসাব বন্ধ'), e_bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'The amount is not valid', 'Amount ঠিক নয়'),
  e_duplicate_claim_no: L('এই ক্লেইম নম্বর আগেই আছে', 'This claim number already exists', 'এই claim number আগেই আছে'), e_item_not_found: L('আইটেম কোড পাওয়া যায়নি', 'An item code was not found', 'Item code পাওয়া যায়নি'),
  e_supplier_not_found: L('প্রিন্সিপাল বাছুন', 'Choose the principal', 'Principal বাছুন'), e_target_needs_amount_and_rebate: L('টার্গেট ও রিবেট দিন', 'Enter the target and a rebate', 'Target ও rebate দিন'),
};
const T = (k) => lab(X[k]);
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? lab(X[k]) : m || 'error'; };
const D = { tab: 's', biz: null, bizs: [], schemes: [], claims: [], recon: [], supp: [], out: '', client: rid(), err: null };

async function businesses() {
  const out = new Map();
  await Promise.all(LOCS().map(async (l) => { const r = await sb.rpc('org_unit_scope', { p_location: l.id }); const d = r.data; if (d && d.business_id && !out.has(d.business_id)) out.set(d.business_id, d.business_code || String(d.business_id)); }));
  D.bizs = [...out.entries()].map(([id, code]) => ({ id, code }));
  if (!D.biz || !D.bizs.find((b) => b.id === D.biz)) D.biz = (D.bizs[0] || {}).id || null;
}
async function load() {
  D.err = null; if (!D.biz) { D.schemes = D.claims = D.recon = []; return; }
  const [a, b, c, s] = await Promise.all([sb.rpc('scheme_list', { p_business: D.biz, p_status: null }), sb.rpc('claim_list', { p_business: D.biz, p_supplier: null, p_status: null }),
    sb.rpc('scheme_reconciliation', { p_business: D.biz, p_supplier: null }), sb.from('suppliers').select('id,name').order('name').limit(500)]);
  D.schemes = a.data || []; D.claims = b.data || []; D.recon = c.data || []; D.supp = s.data || []; if (a.error) D.err = a.error;
}
const chip = (s) => `<span class="chip ${s === 'active' || s === 'settled' ? 'ok' : s === 'rejected' || s === 'cancelled' ? 'bad' : 'warn'}">${esc(s)}</span>`;
const kv = (k, v) => `<span>${esc(T(k))}: <b>${money(v)}</b></span>`;
function schemeCard(s) {
  const b = (act, k, cls = '') => `<button class="mini ${cls}" data-act="${act}" data-v="${esc(s.id)}">${esc(T(k))}</button>`;
  return `<div class="card"><div class="row between wrap"><b>${esc(s.name)}</b>${chip(s.status)}</div><div class="muted">${esc(s.supplier_name || '')} · ${esc(s.kind)} · ${esc(s.basis)} · ${esc(s.valid_from)} → ${esc(s.valid_to)}</div>
    <div class="row wrap">${kv('accrued', s.accrued)}${kv('claimed', s.claimed)}${kv('received', s.received)}</div>
    <div class="row wrap">${b('sc_prev', 'preview')}${s.status === 'draft' ? b('sc_act', 'activate', 'primary') : ''}${s.status === 'active' ? b('sc_accr', 'accrue', 'primary') + b('sc_close', 'close') : ''}${s.status === 'active' || s.status === 'closed' ? b('sc_claim', 'claim') : ''}</div></div>`;
}
function claimCard(c) {
  const b = (act, k) => `<button class="mini" data-act="${act}" data-v="${esc(c.id)}">${esc(T(k))}</button>`;
  return `<div class="card"><div class="row between wrap"><b>${esc(c.claim_no || '—')} · ${esc(c.scheme_name || '')}</b><b>${money(c.amount)}</b></div><div class="muted">${esc(c.supplier_name || '')} · ${esc(c.claim_date)}</div>
    <div class="row between wrap">${chip(c.status)}<span>${esc(T('received'))}: ${money(c.received)} · ${esc(T('outstanding'))}: ${money(c.outstanding)}</span></div>
    ${c.status === 'submitted' || c.status === 'part_settled' ? `<div class="row wrap">${b('sc_recv', 'receive')}${c.status === 'submitted' ? b('sc_rej', 'reject') : ''}</div>` : ''}</div>`;
}
function reconCard(r) {
  return `<div class="card"><div class="row between wrap"><b>${esc(r.scheme_name)}</b>${chip(r.status)}</div><div class="muted">${esc(r.supplier_name || '')}</div>
    <div class="row wrap">${kv('accrued', r.accrued)}${kv('claimed', r.claimed)}${kv('received', r.received)}</div>
    <div class="row wrap">${kv('unclaimed', r.unclaimed)}${kv('outstanding', r.outstanding)}${Number(r.over_claimed) > 0 ? `<span class="chip bad">${esc(T('over'))}: ${money(r.over_claimed)}</span>` : `<span class="chip ok">${esc(T('ok'))}</span>`}</div></div>`;
}
function formH() {
  const opt = (v, k) => `<option value="${v}">${esc(T(k))}</option>`;
  return `<div class="card stack">
    <div><label for="sc_sup">${esc(T('principal'))}</label><select id="sc_sup"><option value="">${esc(T('pick'))}</option>${D.supp.map((p) => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('')}</select></div>
    <div><label for="sc_name">${esc(T('name'))}</label><input id="sc_name" autocomplete="off"></div>
    <div><label for="sc_kind">${esc(T('kind'))}</label><select id="sc_kind">${opt('slab', 'slab')}${opt('target', 'target')}${opt('flat_pack', 'flat')}</select></div>
    <div><label for="sc_basis">${esc(T('basis'))}</label><select id="sc_basis">${opt('purchase', 'purchase')}${opt('sale', 'sale')}</select></div>
    <div><label for="sc_measure">${esc(T('measure'))}</label><select id="sc_measure">${opt('value', 'value')}${opt('qty', 'qty')}</select></div>
    <div><label for="sc_from">${esc(T('from'))}</label><input id="sc_from" type="date" value="${today()}"></div>
    <div><label for="sc_to">${esc(T('to'))}</label><input id="sc_to" type="date"></div>
    <div id="sc_slabw"><label for="sc_mode">${esc(T('mode'))}</label><select id="sc_mode">${opt('whole', 'whole')}${opt('marginal', 'marginal')}</select>
      <label for="sc_slabs">${esc(T('slabs'))}</label><textarea id="sc_slabs" rows="4" placeholder="0,50000,1&#10;50000,100000,2&#10;100000,,3"></textarea></div>
    <div id="sc_tgtw" hidden><label for="sc_tgt">${esc(T('tgt'))}</label><input id="sc_tgt" inputmode="decimal"><label for="sc_pct">${esc(T('pct'))}</label><input id="sc_pct" inputmode="decimal"><label for="sc_flat">${esc(T('flatAmt'))}</label><input id="sc_flat" inputmode="decimal"></div>
    <div id="sc_ppw" hidden><label for="sc_pp">${esc(T('perPack'))}</label><input id="sc_pp" inputmode="decimal"></div>
    <div><label for="sc_items">${esc(T('items'))}</label><input id="sc_items" autocomplete="off"></div>
    <div><label for="sc_note">${esc(T('note'))}</label><input id="sc_note" autocomplete="off"></div>
    <button class="full primary" data-act="sc_save">${esc(T('save'))}</button></div>`;
}
function syncKind() { const k = ($('#sc_kind') || {}).value; const s = (id, v) => { const e = $(id); if (e) e.hidden = !v; }; s('#sc_slabw', k === 'slab'); s('#sc_tgtw', k === 'target'); s('#sc_ppw', k === 'flat_pack'); if (k === 'flat_pack' && $('#sc_measure')) $('#sc_measure').value = 'qty'; }
function draw() {
  const el = $('#sc_body'); if (!el) return;
  const bizSel = D.bizs.length > 1 ? `<div class="card"><label for="sc_biz">${esc(T('biz'))}</label><select id="sc_biz">${D.bizs.map((b) => `<option value="${b.id}" ${b.id === D.biz ? 'selected' : ''}>${esc(b.code)}</option>`).join('')}</select></div>` : '';
  const tabs = [['s', 'tS'], ['c', 'tC'], ['r', 'tR'], ['n', 'tN']];
  const bar = `<div class="row wrap">${tabs.map(([k, l]) => `<button class="mini ${D.tab === k ? 'primary' : ''}" data-act="sc_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
  const out = D.out ? `<div class="notice" id="sc_out">${D.out}</div>` : '';
  let body = '';
  if (D.err) body = `<div class="notice warn">${esc(eText(D.err))}</div>`;
  else if (D.tab === 's') body = D.schemes.length ? D.schemes.map(schemeCard).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  else if (D.tab === 'c') body = D.claims.length ? D.claims.map(claimCard).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  else if (D.tab === 'r') body = D.recon.length ? D.recon.map(reconCard).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  else body = formH();
  el.innerHTML = bizSel + bar + out + body; if (D.tab === 'n') syncKind();
}
async function show() { await load(); draw(); }
async function call(fn, args, okMsg) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } if (okMsg) toast(T(okMsg)); return r.data || {}; }
const pv = (x) => `${esc(T('base'))}: <b>${money(x.base_value)}</b> · ${esc(T('earned'))}: <b>${money(x.earned)}</b> · ${esc(T('already'))}: ${money(x.already_accrued)} · ${esc(T('delta'))}: <b>${money(x.delta)}</b> (${esc(T('nothingSaved'))})`;
Object.assign(H, {
  sc_tab: (a) => { D.tab = a.dataset.v; D.out = ''; draw(); },
  sc_prev: async (a) => { const x = await call('scheme_accrue', { p_id: a.dataset.v, p_upto: null, p_dry: true, p_client: null, p_note: null }); if (!x) return; D.out = pv(x); draw(); },
  sc_act: async (a) => { if (await call('scheme_activate', { p_id: a.dataset.v }, 'saved')) await show(); },
  sc_accr: async (a) => {
    const x = await call('scheme_accrue', { p_id: a.dataset.v, p_upto: null, p_dry: true, p_client: null, p_note: null }); if (!x) return;
    D.out = pv(x); draw(); if (!window.confirm(T('confirm') + ' ' + money(x.delta))) return;
    if (await call('scheme_accrue', { p_id: a.dataset.v, p_upto: null, p_dry: false, p_client: rid(), p_note: null }, 'saved')) { D.out = ''; await show(); }
  },
  sc_close: async (a) => { if (await call('scheme_close', { p_id: a.dataset.v, p_client: rid() }, 'saved')) await show(); },
  sc_claim: async (a) => {
    const amt = nnum(window.prompt(T('amt'))); if (!(amt > 0)) return; const no = window.prompt(T('claimNo')) || null;
    if (await call('claim_create', { p_client: rid(), p_scheme: a.dataset.v, p_claim_no: no && no.trim() || null, p_date: today(), p_amount: amt, p_note: null }, 'saved')) { D.tab = 'c'; await show(); }
  },
  sc_recv: async (a) => { const amt = nnum(window.prompt(T('amt'))); if (!(amt > 0)) return; const ref = window.prompt(T('ref')) || null;
    if (await call('claim_receive', { p_claim: a.dataset.v, p_client: rid(), p_amount: amt, p_date: today(), p_ref: ref && ref.trim() || null, p_note: null }, 'saved')) await show(); },
  sc_rej: async (a) => { const why = window.prompt(T('why')); if (!why || !why.trim()) return; if (await call('claim_reject', { p_claim: a.dataset.v, p_client: rid(), p_reason: why.trim() }, 'saved')) await show(); },
  sc_save: async () => {
    const kind = $('#sc_kind').value; const params = {}; let slabs = [];
    if (kind === 'slab') {
      params.slab_mode = $('#sc_mode').value;
      slabs = $('#sc_slabs').value.split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const p = l.split(',').map((x) => x.trim()); return { from: nnum(p[0]), to: p[1] === '' || p[1] === undefined ? null : nnum(p[1]), rate: nnum(p[2]) }; });
    }
    if (kind === 'target') { params.target_amount = nnum($('#sc_tgt').value) || null; if ($('#sc_pct').value) params.rebate_pct = nnum($('#sc_pct').value); if ($('#sc_flat').value) params.rebate_flat = nnum($('#sc_flat').value); }
    if (kind === 'flat_pack') params.per_pack_amount = nnum($('#sc_pp').value) || null;
    let ids = [];
    const codes = $('#sc_items').value.split(',').map((x) => x.trim()).filter(Boolean);
    if (codes.length) { const r = await sb.from('items').select('id,code').in('code', codes); ids = (r.data || []).map((x) => x.id); if (ids.length !== codes.length) return toast(lab(X.e_item_not_found)); }
    const r = await sb.rpc('scheme_save', { p_id: null, p_client: D.client, p_business: D.biz, p_supplier: $('#sc_sup').value || null, p_name: $('#sc_name').value.trim(), p_kind: kind, p_basis: $('#sc_basis').value, p_measure: kind === 'flat_pack' ? 'qty' : $('#sc_measure').value,
      p_from: $('#sc_from').value, p_to: $('#sc_to').value || null, p_params: params, p_items: ids, p_slabs: slabs, p_note: $('#sc_note').value.trim() || null });
    if (r.error) return toast(eText(r.error));
    D.client = rid(); toast(T('saved')); D.tab = 's'; await show();
  },
});
document.addEventListener('change', async (e) => { if (e.target.id === 'sc_kind') syncKind(); if (e.target.id === 'sc_biz') { D.biz = Number(e.target.value); D.out = ''; await show(); } });
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="sc_body"><p class="muted">…</p></div>', true);
  try { await businesses(); await show(); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { schemes: view });
})();
