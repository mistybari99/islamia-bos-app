/* Islamia BOS · Cost sources and allocation (#/costsources): type a bill ONCE (electricity, gas, rent, licence, repair ... any shape: one site, or one bill for several sites), the code splits it
   to factory (product cost, through the pools) / showroom / admin (branch P&L). Tabs: status (বিল বাকি, ভাগ নির্ধারিত নয়, অভাগিত, duplicates), sources, rules (draft -> approved by ANOTHER person), bills.
   Server: supabase/phase75.sql. COST-RIGHT HOLDERS ONLY (every call refuses without the right). Nothing is guessed: percentages, meter numbers, areas start blank; a month with no bill says "বিল বাকি".
   The location pickers read the locations list, so a new site appears by itself. Handlers are prefixed cb_. Loaded after costing.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
// owner approving his own change: the server (phase87) allows it and returns a NON-blocking suggestion to ask another approver
const selfHint = (d) => (d && d.suggestion ? ' · ' + lab({ bn: d.suggestion_bn, mix: d.suggestion_mix, en: d.suggestion_en }) : '');
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const num = (v) => { const s = norm(v); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const money = (n) => '৳ ' + q(n);
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);

const X = {
  title: L('খরচের সোর্স ও ভাগ', 'Cost sources & allocation', 'Cost source ও ভাগ'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'),
  noperm: L('অনুমতি নেই — খরচ দেখার অধিকার লাগবে', 'Not allowed — the cost right is needed', 'অনুমতি নেই — cost right লাগবে'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), save: L('সংরক্ষণ', 'Save', 'Save'),
  tStat: L('অবস্থা', 'Status', 'Status'), tSrc: L('সোর্স', 'Sources', 'Sources'), tRule: L('ভাগের নিয়ম', 'Split rules', 'ভাগের rule'), tBill: L('বিল', 'Bills', 'Bills'),
  month: L('মাস', 'Month', 'Month'), pending: L('বিল বাকি', 'Bill pending', 'বিল বাকি'), noSplit: L('ভাগ নির্ধারিত নয়', 'Split not set', 'ভাগ নির্ধারিত নয়'), unalloc: L('অভাগিত', 'Unallocated', 'অভাগিত'),
  dups: L('১০-২ ভাউচারের সাথে মিল (ডুপ্লিকেট?)', 'Looks like a 10-2 voucher (duplicate?)', '১০-২ voucher-এর সাথে মিল'), ack: L('এটি আলাদা খরচ', 'This is a different cost', 'এটি আলাদা'), why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'),
  newSrc: L('নতুন সোর্স', 'New source', 'নতুন source'), type: L('খরচের ধরন', 'Cost type', 'Cost type'), newType: L('☐ অন্য: নতুন ধরন যোগ', '☐ Other: add a new type', '☐ অন্য: নতুন type'), newTypeAsk: L('নতুন ধরনের নাম', 'Name of the new type', 'নতুন type-এর নাম'),
  provider: L('প্রদানকারী / মিটার / চুক্তি নং (ফাঁকা চলে)', 'Provider / meter / contract no. (may be blank)', 'Provider / meter / contract no (blank চলে)'), kind: L('ধরন', 'Kind', 'Kind'),
  kSep: L('আলাদা — এক জায়গা দেয়', 'Separate — one place pays', 'আলাদা — এক place দেয়'), kShared: L('ভাগ করা — একটি বিল কয়েক জায়গার', 'Shared — one bill for several places', 'ভাগ করা — একটি bill কয়েক place-এর'),
  dest: L('কোথায় যাবে', 'Goes to', 'Goes to'), dF: L('কারখানা (পণ্যের খরচে)', 'Factory (product cost)', 'Factory (product cost)'), dS: L('শোরুম (শাখার লাভ-ক্ষতি)', 'Showroom (branch P&L)', 'Showroom (branch P&L)'), dA: L('অ্যাডমিন (শাখার লাভ-ক্ষতি)', 'Admin (branch P&L)', 'Admin (branch P&L)'),
  places: L('কোন কোন জায়গা', 'Which places', 'কোন কোন place'), place: L('জায়গা', 'Place', 'Place'), freq: L('কতদিন পরপর', 'How often', 'How often'), fM: L('প্রতি মাসে', 'Monthly', 'Monthly'), fY: L('বছরে একবার', 'Yearly', 'Yearly'), fI: L('অনিয়মিত', 'Irregular', 'Irregular'),
  eff: L('কার্যকর তারিখ', 'Effective from', 'Effective from'), retire: L('বন্ধ', 'Retire', 'Retire'),
  method: L('ভাগের পদ্ধতি', 'Allocation method', 'Allocation method'), mMeter: L('সাব-মিটার রিডিং', 'Sub-meter reading', 'Sub-meter reading'), mPct: L('নির্দিষ্ট শতাংশ', 'Fixed percent', 'Fixed percent'), mArea: L('জায়গার মাপ (বর্গফুট)', 'Floor area (sq ft)', 'Floor area (sq ft)'),
  mHead: L('কর্মী সংখ্যা', 'Headcount', 'Headcount'), mOut: L('উৎপাদন (কেজি) — নিজে থেকে', 'Output kg — automatic', 'Output kg — automatic'), mOne: L('পুরোটা এক জায়গায়', 'Whole bill to one place', 'পুরোটা এক place-এ'), mMan: L('☐ অন্য: হাতে লেখা অঙ্ক', '☐ Other: hand-typed amounts', '☐ অন্য: hand-typed'),
  value: L('মান (ফাঁকা চলে)', 'Value (may stay blank)', 'Value (blank চলে)'), pctSum: L('শতাংশের যোগফল ১০০ হতে হবে', 'Percentages must total 100', 'Percent-এর যোগফল ১০০'), sum: L('যোগফল', 'Total', 'Total'),
  draft: L('খসড়া', 'Draft', 'Draft'), approved: L('অনুমোদিত', 'Approved', 'Approved'), approve: L('অনুমোদন করুন', 'Approve', 'Approve'), incomplete: L('অসম্পূর্ণ', 'Incomplete', 'অসম্পূর্ণ'), newRule: L('নতুন নিয়ম', 'New rule', 'নতুন rule'),
  newBill: L('নতুন বিল', 'New bill', 'নতুন bill'), source: L('সোর্স', 'Source', 'Source'), periodK: L('কিসের জন্য', 'Covers', 'Covers'), pM: L('একটি মাস', 'One month', 'One month'), pY: L('পুরো বছর (÷১২)', 'A whole year (÷12)', 'Whole year (÷12)'),
  amount: L('টাকা', 'Amount', 'Amount'), mode: L('পরিশোধ', 'Paid by', 'Paid by'), billNo: L('বিল নং', 'Bill no.', 'Bill no.'), billDate: L('বিলের তারিখ', 'Bill date', 'Bill date'), oneOff: L('একবারের খরচ', 'One-off', 'One-off'), vref: L('১০-২ নং (শুধু নম্বর)', '10-2 no. (number only)', '10-2 no.'),
  readings: L('এই বিলের রিডিং / অঙ্ক', 'Readings / amounts for this bill', 'এই bill-এর reading / amount'), void: L('বাতিল', 'Void', 'Void'), realloc: L('আবার ভাগ', 'Allocate again', 'আবার ভাগ'), voided: L('বাতিল', 'Void', 'Void'),
  badNum: L('সংখ্যা ঠিক নয়', 'Number is not valid', 'Number ঠিক নয়'), needLocs: L('জায়গা বাছুন', 'Choose the places', 'Place বাছুন'), needAmt: L('টাকা লিখুন', 'Write the amount', 'Amount লিখুন'), needSrc: L('সোর্স বাছুন', 'Choose a source', 'Source বাছুন'),
  split: L('ভাগ হয়েছে', 'Split', 'Split'), sqlMissing: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase75)', 'The database part is not installed yet (phase75)', 'Database অংশ চালু হয়নি (phase75)'),
};
const T = (k) => lab(X[k]);
const DEST = { factory: 'dF', showroom: 'dS', admin: 'dA' };
const METH = { sub_meter: 'mMeter', fixed_percent: 'mPct', floor_area: 'mArea', headcount: 'mHead', output_kg: 'mOut', whole_to_one: 'mOne', other_manual: 'mMan' };
const ERR = { percent_not_100: L('শতাংশের যোগফল ১০০ নয়', 'The percentages do not total 100', 'Percent-এর যোগফল ১০০ নয়'), self_approve_refused: L('যে নিয়ম লিখেছে সে অনুমোদন করতে পারবে না — অন্য কেউ লাগবে', 'The person who entered the rule cannot approve it', 'যে rule লিখেছে সে approve করতে পারবে না'),
  rule_incomplete: L('নিয়মে ফাঁকা ঘর আছে — আগে পূরণ করুন', 'The rule has blank values — fill them first', 'Rule-এ blank আছে'), shares_exceed_bill: L('হাতে লেখা অঙ্কের যোগফল বিলের চেয়ে বেশি', 'The typed amounts total more than the bill', 'Typed amount bill-এর চেয়ে বেশি'),
  duplicate_bill: L('এই বিল নম্বর এই সোর্সে আগেই আছে', 'This bill number already exists on this source', 'এই bill no আগেই আছে'), already_allocated: L('বিল আগেই পুরো ভাগ হয়েছে — বদলায় না', 'The bill is already fully split — it does not change', 'Bill আগেই ভাগ হয়েছে'),
  source_in_use: L('বিল থাকলে সোর্সের ধরন/জায়গা বদলানো যায় না', 'With bills on it, the source type / places cannot change', 'Bill থাকলে source বদলায় না') };
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/function .* does not exist|schema cache/i.test(m)) return toast(T('sqlMissing')); return fail(e); };
const D = { tab: 'stat', month: today().slice(0, 7), locs: [], types: [], sources: [], slocs: [], rules: [], rshares: [], bills: [], shares: [], stat: null };

async function loadAll() {
  const lo = await sb.rpc('cost_pick_locations'); if (lo.error) throw lo.error; D.locs = lo.data || [];
  const [ty, so, sl, ru, rs, bi, sh] = await Promise.all([sb.from('cost_source_types').select('*').eq('active', true).order('code'), sb.from('cost_sources').select('*').order('id'), sb.from('cost_source_locs').select('*'),
    sb.from('cost_source_rules').select('*').order('id', { ascending: false }), sb.from('cost_source_rule_shares').select('*'), sb.from('cost_source_bills').select('*').order('id', { ascending: false }).limit(60), sb.from('cost_bill_shares').select('*').eq('active', true)]);
  D.types = ty.data || []; D.sources = so.data || []; D.slocs = sl.data || []; D.rules = ru.data || []; D.rshares = rs.data || []; D.bills = bi.data || []; D.shares = sh.data || [];
  const st = await sb.rpc('cost_sources_status', { p_month: D.month + '-01' }); D.stat = st.error ? null : st.data;
}
const locName = (id) => { const l = D.locs.find((x) => x.id === id); return l ? lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }) : '#' + id; };
const typeName = (c) => { const t = D.types.find((x) => x.code === c); return t ? lab({ bn: t.label_bn, mix: t.label_bn, en: t.label_en || t.label_bn }) : c; };
const srcOf = (id) => D.sources.find((s) => s.id === id);
const srcLocs = (id) => D.slocs.filter((x) => x.source_id === id).map((x) => x.location_id);
const srcName = (s) => s ? `${s.code} · ${typeName(s.cost_type)}${s.provider ? ' · ' + s.provider : ''}` : '—';
const inForce = (sid, ym) => D.rules.filter((r) => r.source_id === sid && r.status === 'approved' && r.complete && r.effective_from <= ym + '-31').sort((a, b) => (a.effective_from < b.effective_from ? 1 : -1))[0];

function draw() {
  const el = $('#cb_body'); if (!el) return;
  const tabs = [['stat', 'tStat'], ['src', 'tSrc'], ['rule', 'tRule'], ['bill', 'tBill']];
  el.innerHTML = `<div class="tabs" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${tabs.map((t) => `<button type="button" data-act="cb_tab" data-v="${t[0]}" class="${D.tab === t[0] ? 'on' : ''}" style="min-width:0;flex:1 1 40%">${esc(T(t[1]))}</button>`).join('')}</div><div id="cb_pane">${D.tab === 'stat' ? paneStat() : D.tab === 'src' ? paneSrc() : D.tab === 'rule' ? paneRule() : paneBill()}</div>`;
}
const monthSel = () => `<label>${esc(T('month'))}<input type="month" id="cb_month" value="${esc(D.month)}"></label>`;

/* ---------- status ---------- */
function list(title, rows, fn) { return `<div class="card stack"><b>${esc(title)} <span class="chip ${rows.length ? 'warn' : 'ok'}">${rows.length}</span></b>${rows.length ? rows.map(fn).join('') : `<span class="muted">${esc(T('none'))}</span>`}</div>`; }
function paneStat() {
  const s = D.stat; if (!s) return `<div class="card">${monthSel()}</div><p class="muted">${esc(T('noperm'))}</p>`;
  return `<div class="card">${monthSel()}</div>` +
    list(T('pending'), s.bills_pending || [], (x) => `<div class="row between wrap"><span>${esc(srcName(srcOf(x.source_id)))}</span><span class="chip warn">${esc(T('pending'))}</span></div>`) +
    list(T('noSplit'), s.split_not_set || [], (x) => `<div class="row between wrap"><span>${esc(srcName(srcOf(x.source_id)))}</span><span class="chip warn">${esc(T('noSplit'))}</span></div>`) +
    list(T('unalloc'), s.unallocated || [], (x) => `<div class="row between wrap"><span>${esc(srcName(srcOf(x.source_id)))} · #${x.bill_id}</span><span><b>${money(x.amount)}</b> <span class="chip warn">${esc(T('unalloc'))}</span></span></div>`) +
    list(T('dups'), s.duplicates || [], (x) => `<div class="row between wrap"><span>${esc(srcName(srcOf(x.source_id)))} · #${x.bill_id} · ${money(x.amount)}</span><button type="button" class="mini" data-act="cb_ack" data-id="${x.bill_id}">${esc(T('ack'))}</button></div>`);
}

/* ---------- sources ---------- */
function paneSrc() {
  return `<div class="card"><button type="button" class="btn primary full" data-act="cb_snew">${esc(T('newSrc'))}</button></div>` + D.sources.map((s) => `<div class="card stack" style="${s.active ? '' : 'opacity:.55'}"><div class="row between wrap"><b>${esc(srcName(s))}</b><span class="chip">${esc(s.kind === 'shared' ? T('kShared') : T('kSep'))}</span></div>
    <div class="muted">${srcLocs(s.id).map(locName).map(esc).join(' · ')}${s.dest ? ' → ' + esc(T(DEST[s.dest])) : ''} · ${esc(T(s.frequency === 'monthly' ? 'fM' : s.frequency === 'yearly' ? 'fY' : 'fI'))} · ${esc(s.effective_from)}</div>
    ${s.active ? `<button type="button" class="mini" data-act="cb_sret" data-id="${s.id}">${esc(T('retire'))}</button>` : ''}</div>`).join('');
}
function sourceSheet() {
  const types = D.types.map((t) => `<option value="${t.code}">${esc(lab({ bn: t.label_bn, mix: t.label_bn, en: t.label_en || t.label_bn }))}</option>`).join('');
  openSheet(`<h3>${esc(T('newSrc'))}</h3><div class="stack"><label>${esc(T('type'))}<select id="cs_type">${types}<option value="__new">${esc(T('newType'))}</option></select></label>
    <label>${esc(T('provider'))}<input id="cs_prov" maxlength="120"></label>
    <label>${esc(T('kind'))}<select id="cs_kind"><option value="separate">${esc(T('kSep'))}</option><option value="shared">${esc(T('kShared'))}</option></select></label>
    <label id="cs_destw">${esc(T('dest'))}<select id="cs_dest">${Object.keys(DEST).map((d) => `<option value="${d}">${esc(T(DEST[d]))}</option>`).join('')}</select></label>
    <div id="cs_locs"><b>${esc(T('places'))}</b>${D.locs.map((l) => `<label class="row"><input type="checkbox" data-cs-loc value="${l.id}"> ${esc(locName(l.id))}</label>`).join('')}</div>
    <label>${esc(T('freq'))}<select id="cs_freq"><option value="monthly">${esc(T('fM'))}</option><option value="yearly">${esc(T('fY'))}</option><option value="irregular">${esc(T('fI'))}</option></select></label>
    <label>${esc(T('eff'))}<input type="date" id="cs_eff" value="${today().slice(0, 8)}01"></label>
    <button type="button" class="btn primary full" data-act="cb_ssave">${esc(T('save'))}</button></div>`);
}

/* ---------- rules ---------- */
function paneRule() {
  const shared = D.sources.filter((s) => s.kind === 'shared' && s.active);
  return `<div class="card"><button type="button" class="btn primary full" data-act="cb_rnew">${esc(T('newRule'))}</button></div>` + shared.map((s) => {
    const rs = D.rules.filter((r) => r.source_id === s.id);
    return `<div class="card stack"><b>${esc(srcName(s))}</b>${rs.length ? rs.map((r) => `<div class="rowcard"><div class="row between wrap"><span>${esc(T(METH[r.method]))} · ${esc(r.effective_from)}</span><span><span class="chip ${r.status === 'approved' ? 'ok' : 'warn'}">${esc(r.status === 'approved' ? T('approved') : T('draft'))}</span>${r.complete ? '' : ` <span class="chip warn">${esc(T('incomplete'))}</span>`}</span></div>
      <div class="muted">${D.rshares.filter((x) => x.rule_id === r.id).map((x) => esc(locName(x.location_id)) + ' ' + esc(T(DEST[x.dest])) + (x.value === null || x.value === undefined ? '' : ' = ' + q(x.value))).join(' · ')}</div>
      ${r.status === 'draft' ? `<button type="button" class="mini" data-act="cb_rapp" data-id="${r.id}">${esc(T('approve'))}</button>` : ''}</div>`).join('') : `<span class="chip warn">${esc(T('noSplit'))}</span>`}</div>`; }).join('');
}
function ruleSheet() {
  const shared = D.sources.filter((s) => s.kind === 'shared' && s.active);
  openSheet(`<h3>${esc(T('newRule'))}</h3><div class="stack"><label>${esc(T('source'))}<select id="cr_src">${shared.map((s) => `<option value="${s.id}">${esc(srcName(s))}</option>`).join('')}</select></label>
    <label>${esc(T('method'))}<select id="cr_meth">${Object.keys(METH).map((m) => `<option value="${m}">${esc(T(METH[m]))}</option>`).join('')}</select></label>
    <label>${esc(T('eff'))}<input type="date" id="cr_eff" value="${today().slice(0, 8)}01"></label><div id="cr_grid"></div><div class="muted" id="cr_sum"></div>
    <button type="button" class="btn primary full" data-act="cb_rsave">${esc(T('save'))}</button></div>`);
  drawGrid();
}
function drawGrid() {
  const sid = Number(($('#cr_src') || {}).value); const g = $('#cr_grid'); if (!g) return; const meth = $('#cr_meth').value; const withVal = ['fixed_percent', 'floor_area', 'headcount'].includes(meth);
  g.innerHTML = srcLocs(sid).map((l) => Object.keys(DEST).map((d) => `<div class="row wrap" data-pair="${l}:${d}"><label class="row"><input type="checkbox" data-cr-on> ${esc(locName(l))} · ${esc(T(DEST[d]))}</label>${withVal ? `<input data-cr-val inputmode="decimal" placeholder="${esc(T('value'))}" style="max-width:8rem">` : ''}</div>`).join('')).join('');
  sumLine();
}
function sumLine() {
  const el = $('#cr_sum'); if (!el) return; if ($('#cr_meth').value !== 'fixed_percent') { el.textContent = ''; return; }
  let t = 0, blank = 0; document.querySelectorAll('#cr_grid [data-pair]').forEach((r) => { if (r.querySelector('[data-cr-on]').checked) { const v = num(r.querySelector('[data-cr-val]').value); if (v === null) blank++; else t += v || 0; } });
  el.textContent = `${T('pctSum')} · ${T('sum')}: ${q(t)}${blank ? ' · ' + T('incomplete') + ' ×' + blank : ''}`;
}

/* ---------- bills ---------- */
function paneBill() {
  return `<div class="card"><button type="button" class="btn primary full" data-act="cb_bnew">${esc(T('newBill'))}</button></div>` + D.bills.map((b) => {
    const sh = D.shares.filter((x) => x.bill_id === b.id); const un = sh.filter((x) => x.kind === 'unallocated');
    return `<div class="card stack" style="${b.status === 'void' ? 'opacity:.5' : ''}"><div class="row between wrap"><b>#${b.id} · ${esc(srcName(srcOf(b.source_id)))}</b><b>${money(b.amount)}</b></div>
      <div class="muted">${esc(b.period_month.slice(0, 7))}${b.period_kind === 'year' ? ' (÷12)' : ''}${b.bill_no ? ' · ' + esc(b.bill_no) : ''}${b.one_off ? ' · ' + esc(T('oneOff')) : ''}${b.status === 'void' ? ' · ' + esc(T('voided')) : ''}</div>
      <div>${sh.filter((x) => x.kind === 'share').map((x) => `<span class="chip">${esc(locName(x.location_id))} ${esc(T(DEST[x.dest]))} ${money(x.amount)}</span>`).join(' ')}${un.map((x) => `<span class="chip warn">${esc(T('unalloc'))} ${money(x.amount)}</span>`).join(' ')}
      ${b.dup_entry_id && !b.dup_ack ? `<span class="chip warn">${esc(T('dups'))}</span>` : ''}</div>
      ${b.status === 'active' ? `<div class="row wrap">${un.length ? `<button type="button" class="mini" data-act="cb_realloc" data-id="${b.id}">${esc(T('realloc'))}</button>` : ''}<button type="button" class="mini" data-act="cb_bvoid" data-id="${b.id}">${esc(T('void'))}</button></div>` : ''}</div>`; }).join('');
}
function inputsHTML(sid, ym) {
  const r = inForce(sid, ym); if (!r || !['sub_meter', 'other_manual'].includes(r.method)) return '';
  return `<div class="stack"><b>${esc(T('readings'))}</b>${D.rshares.filter((x) => x.rule_id === r.id).map((x) => `<label>${esc(locName(x.location_id))} · ${esc(T(DEST[x.dest]))}<input data-bi="${x.location_id}:${x.dest}" inputmode="decimal"></label>`).join('')}</div>`;
}
function billSheet() {
  const act = D.sources.filter((s) => s.active);
  openSheet(`<h3>${esc(T('newBill'))}</h3><div class="stack"><label>${esc(T('source'))}<select id="cb_src">${act.map((s) => `<option value="${s.id}">${esc(srcName(s))}</option>`).join('')}</select></label>
    <label>${esc(T('periodK'))}<select id="cb_pk"><option value="month">${esc(T('pM'))}</option><option value="year">${esc(T('pY'))}</option></select></label>
    <label>${esc(T('month'))}<input type="month" id="cb_pm" value="${esc(D.month)}"></label><label>${esc(T('amount'))}<input id="cb_amt" inputmode="decimal"></label>
    <label>${esc(T('mode'))}<select id="cb_mode"><option value="">—</option><option value="cash">cash</option><option value="bank">bank</option><option value="mobile">mobile</option><option value="card">card</option></select></label>
    <label>${esc(T('billNo'))}<input id="cb_no" maxlength="60"></label><label>${esc(T('billDate'))}<input type="date" id="cb_date"></label>
    <label class="row"><input type="checkbox" id="cb_one"> ${esc(T('oneOff'))}</label><label>${esc(T('vref'))}<input id="cb_vref" maxlength="40"></label><div id="cb_inputs">${act[0] ? inputsHTML(act[0].id, D.month) : ''}</div>
    <button type="button" class="btn primary full" data-act="cb_bsave">${esc(T('save'))}</button></div>`);
}
const readInputs = (root) => [...document.querySelectorAll(root + ' [data-bi]')].map((i) => { const [l, d] = i.dataset.bi.split(':'); return { location_id: Number(l), dest: d, value: norm(i.value) === '' ? null : norm(i.value) }; }).filter((x) => x.value !== null);

/* ---------- handlers ---------- */
async function refresh() { try { await loadAll(); draw(); } catch (e) { errMsg(e); } }
Object.assign(H, {
  cb_tab: (a) => { D.tab = a.dataset.v; draw(); },
  cb_snew: sourceSheet, cb_rnew: ruleSheet, cb_bnew: billSheet,
  cb_ssave: async () => {
    let type = $('#cs_type').value;
    if (type === '__new') { const nm = window.prompt(T('newTypeAsk')); if (!nm) return; const r = await sb.rpc('cost_source_type_add', { p_label_bn: nm, p_label_en: null, p_component_type: 'other' }); if (r.error) return errMsg(r.error); type = r.data.code; }
    const kind = $('#cs_kind').value; const locs = [...document.querySelectorAll('[data-cs-loc]:checked')].map((c) => Number(c.value)); if (!locs.length) return toast(T('needLocs'));
    const r = await sb.rpc('cost_source_save', { p_id: null, p_type: type, p_provider: $('#cs_prov').value || null, p_kind: kind, p_dest: kind === 'separate' ? $('#cs_dest').value : null, p_locs: locs, p_frequency: $('#cs_freq').value, p_effective: $('#cs_eff').value, p_note: null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  cb_sret: async (a) => { const w = window.prompt(T('why')); if (!w) return; const r = await sb.rpc('cost_source_set_active', { p_id: Number(a.dataset.id), p_active: false, p_reason: w }); if (r.error) return errMsg(r.error); await refresh(); },
  cb_rsave: async () => {
    const shares = []; let bad = false;
    document.querySelectorAll('#cr_grid [data-pair]').forEach((r) => { if (!r.querySelector('[data-cr-on]').checked) return; const [l, d] = r.dataset.pair.split(':'); const vi = r.querySelector('[data-cr-val]'); const v = vi ? num(vi.value) : null; if (Number.isNaN(v)) bad = true; shares.push({ location_id: Number(l), dest: d, value: v }); });
    if (bad) return toast(T('badNum')); if (!shares.length) return toast(T('needLocs'));
    const r = await sb.rpc('cost_rule_save', { p_source: Number($('#cr_src').value), p_method: $('#cr_meth').value, p_effective: $('#cr_eff').value, p_shares: shares, p_note: null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  cb_rapp: async (a) => { const r = await sb.rpc('cost_rule_approve', { p_rule: Number(a.dataset.id), p_note: null }); if (r.error) return errMsg(r.error); toast(T('approved') + selfHint(r.data)); await refresh(); },
  cb_bsave: async () => {
    const sid = Number($('#cb_src').value); if (!sid) return toast(T('needSrc')); const amt = num($('#cb_amt').value); if (amt === null || Number.isNaN(amt) || amt <= 0) return toast(T('needAmt'));
    const r = await sb.rpc('cost_bill_add', { p_source: sid, p_period_kind: $('#cb_pk').value, p_month: ($('#cb_pm').value || D.month) + '-01', p_amount: amt, p_pay_mode: $('#cb_mode').value || null, p_bill_no: $('#cb_no').value || null, p_bill_date: $('#cb_date').value || null,
      p_one_off: $('#cb_one').checked, p_inputs: readInputs('#cb_inputs'), p_voucher_ref: $('#cb_vref').value || null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  cb_bvoid: async (a) => { const w = window.prompt(T('why')); if (!w) return; const r = await sb.rpc('cost_bill_void', { p_bill: Number(a.dataset.id), p_note: w }); if (r.error) return errMsg(r.error); await refresh(); },
  cb_ack: async (a) => { const w = window.prompt(T('why')); if (!w) return; const r = await sb.rpc('cost_bill_dup_ack', { p_bill: Number(a.dataset.id), p_note: w }); if (r.error) return errMsg(r.error); await refresh(); },
  cb_realloc: async (a) => {
    const b = D.bills.find((x) => String(x.id) === a.dataset.id); const r0 = b && inForce(b.source_id, b.period_month.slice(0, 7));
    if (r0 && ['sub_meter', 'other_manual'].includes(r0.method)) { openSheet(`<h3>${esc(T('realloc'))} #${b.id}</h3><div class="stack"><div id="cb_rinputs">${inputsHTML(b.source_id, b.period_month.slice(0, 7))}</div><button type="button" class="btn primary full" data-act="cb_rgo" data-id="${b.id}">${esc(T('save'))}</button></div>`); return; }
    const r = await sb.rpc('cost_bill_reallocate', { p_bill: Number(a.dataset.id), p_inputs: null }); if (r.error) return errMsg(r.error); await refresh();
  },
  cb_rgo: async (a) => { const r = await sb.rpc('cost_bill_reallocate', { p_bill: Number(a.dataset.id), p_inputs: readInputs('#cb_rinputs') }); if (r.error) return errMsg(r.error); closeSheet(); toast(T('saved')); await refresh(); },
});
document.addEventListener('change', async (e) => {
  const t = e.target; if (!t || !t.id) return;
  if (t.id === 'cb_month') { D.month = t.value || D.month; await refresh(); }
  if (t.id === 'cs_kind') { const sep = t.value === 'separate'; const w = $('#cs_destw'); if (w) w.style.display = sep ? '' : 'none'; }
  if (t.id === 'cr_src' || t.id === 'cr_meth') drawGrid();
  if (t.id === 'cb_src' || t.id === 'cb_pm') { const c = $('#cb_inputs'); if (c) c.innerHTML = inputsHTML(Number($('#cb_src').value), $('#cb_pm').value || D.month); }
});
document.addEventListener('input', (e) => { const t = e.target; if (t && t.matches && t.matches('[data-cr-val]')) sumLine(); if (t && t.matches && t.matches('[data-cr-on]')) sumLine(); });
document.addEventListener('change', (e) => { const t = e.target; if (t && t.matches && t.matches('[data-cr-on]')) sumLine(); });

async function view() {
  shell(T('title'), `<div id="cb_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try {
    let ok = !!(S.ctx && S.ctx.is_owner); if (!ok) { try { ok = !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { ok = false; } }
    if (!ok) { const b = $('#cb_body'); if (b) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
    await loadAll(); draw();
  } catch (e) { const b = $('#cb_body'); if (b && /not allowed|permission/i.test((e && e.message) || '')) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; else errMsg(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { costsources: view });
})();
