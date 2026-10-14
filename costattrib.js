/* Islamia BOS · Which showroom does a cost belong to (#/costattrib): the showroom / admin shares of a cost bill (cost-source screen, phase75) can be charged to that showroom's
   own profit-and-loss, kept at the MAIN CENTRE, or left unallocated - per place, per cost type if wanted, from a month on (earlier months never change). One share can be moved
   to another showroom / the main centre with a compulsory reason; every move stays in a trail. Tabs: options, cost view (every share and where it is charged), history, rules & duty
   (owner: the P&L switch, recipe-approval and production-recipe switches in plain words, and the "give approval to someone else" suggestion).
   Server: supabase/phase78.sql (branch_cost_view, cost_attrib_set / _retire / _main_set, cost_share_reassign, grant_separation_hint / _report). COST-RIGHT HOLDERS ONLY.
   Nothing is set for the owner: every place starts "not charged anywhere" (today's behaviour). Handlers are prefixed ca_. Loaded after costsources.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const q = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const money = (n) => '৳ ' + q(n);
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);

const X = {
  title: L('কস্ট কোন শাখার', 'Which showroom a cost belongs to', 'cost কোন শাখার'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই', 'Nothing', 'কিছু নেই'),
  noperm: L('অনুমতি নেই — কস্ট দেখার অনুমতি লাগবে', 'Not allowed — the cost right is needed', 'অনুমতি নেই — cost right লাগবে'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  sqlMissing: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase78)', 'The database part is not installed yet (phase78)', 'Database অংশ চালু হয়নি (phase78)'),
  tOpt: L('কোথায় ধরব', 'Where to charge', 'কোথায় ধরব'), tView: L('কস্টের হিসাব', 'Cost view', 'Cost view'), tHist: L('ইতিহাস', 'History', 'ইতিহাস'), tRules: L('নিয়ম ও দায়িত্ব', 'Rules & duty', 'Rule ও দায়িত্ব'),
  intro: L('কারখানার খরচ পণ্যের কস্টে যায়। শোরুম ও অ্যাডমিনের অংশ নিচের পছন্দ অনুযায়ী ধরা হয়। কিছু ঠিক না করলে কোথাও ধরা হয় না (আজকের মতোই)।', 'Factory cost goes into the product cost. The showroom and admin shares are charged as you choose below. If nothing is set, nothing is charged anywhere (as today).', 'Factory খরচ product cost-এ যায়। Showroom ও admin অংশ নিচের পছন্দে ধরা হয়। কিছু না বাছলে কোথাও ধরা হয় না (আজকের মতো)।'),
  dShow: L('এই শোরুমের লাভ-ক্ষতিতে ধরুন', "Charge to this showroom's P&L", 'এই showroom-এর P&L-এ ধরুন'), dMain: L('মূল কেন্দ্রে রাখুন', 'Keep at the main centre', 'মূল কেন্দ্রে রাখুন'), dNone: L('কোথাও ধরবেন না (ভাগ-না-হওয়া)', 'Charge nowhere (unallocated)', 'কোথাও ধরবেন না (ভাগ-না-হওয়া)'),
  dShort: { showroom: L('শোরুমে', 'Showroom', 'Showroom'), main_centre: L('মূল কেন্দ্রে', 'Main centre', 'মূল কেন্দ্রে'), unallocated: L('ভাগ-না-হওয়া', 'Unallocated', 'ভাগ-না-হওয়া'), location: L('শোরুমে', 'Showroom', 'Showroom') },
  allTypes: L('সব কস্টের ধরন', 'All cost types', 'সব ধরন'), type: L('কস্টের ধরন', 'Cost type', 'Cost type'), change: L('বদলান', 'Change', 'বদলান'), from: L('কোন মাস থেকে', 'From month', 'কোন মাস থেকে'),
  reason: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), reasonNeed: L('কারণ লিখতে হবে (কমপক্ষে ৩ অক্ষর)', 'A reason is needed (at least 3 characters)', 'কারণ লাগবে (কমপক্ষে ৩ অক্ষর)'),
  fromNote: L('নতুন পছন্দ বাছা মাস থেকে চলবে; আগের মাসের হিসাব বদলায় না। পুরনো পছন্দ ইতিহাসে থাকে।', 'A new choice applies from the chosen month; earlier months never change. The old choice stays in the history.', 'নতুন পছন্দ বাছা মাস থেকে চলবে; আগের মাস বদলায় না। পুরনো পছন্দ history-তে থাকে।'),
  now: L('এখন', 'Now', 'এখন'), upcoming: L('আসছে', 'Upcoming', 'আসছে'), notSet: L('ঠিক করা নেই — কোথাও ধরা হয় না', 'Not set — charged nowhere', 'ঠিক করা নেই — কোথাও ধরা হয় না'), retire: L('ফিরিয়ে নিন', 'Take back', 'ফিরিয়ে নিন'),
  main: L('মূল কেন্দ্র কোনটি', 'Which place is the main centre', 'মূল কেন্দ্র কোনটি'), mainNone: L('কোনো জায়গা নয় (শুধু হিসাবে দেখাবে)', 'No place (shown in the cost view only)', 'কোনো জায়গা নয় (শুধু হিসাবে দেখাবে)'),
  mainNote: L('"মূল কেন্দ্রে রাখুন" বাছা কস্ট এই জায়গার লাভ-ক্ষতিতে আলাদা সারিতে যাবে। কিছু না বাছলে শুধু কস্টের হিসাবে দেখা যাবে।', 'Costs set to "main centre" go to this place as separate rows. If none is chosen they show in the cost view only.', '"মূল কেন্দ্র" cost এই place-এর P&L-এ আলাদা সারিতে যাবে।'),
  month: L('মাস', 'Month', 'Month'), allPlaces: L('সব জায়গা', 'All places', 'সব জায়গা'), place: L('জায়গা', 'Place', 'Place'), goesTo: L('যাচ্ছে', 'Charged to', 'যাচ্ছে'), amount: L('টাকা', 'Amount', 'Amount'),
  vSetting: L('পছন্দ অনুযায়ী', 'by setting', 'setting অনুযায়ী'), vDefault: L('কিছু ঠিক নেই', 'nothing set', 'কিছু ঠিক নেই'), vRe: L('হাতে বদলানো', 'moved by hand', 'হাতে বদলানো'), locked: L('বন্ধ মাসে বদল (মালিক)', 'closed month changed (owner)', 'বন্ধ মাসে বদল (মালিক)'),
  admin: L('অ্যাডমিন', 'Admin', 'Admin'), showroom: L('শোরুম', 'Showroom', 'Showroom'), totals: L('মোট কোথায় কত', 'Totals by destination', 'মোট কোথায় কত'), inPl: L('লাভ-ক্ষতির হিসাবে যুক্ত', 'Included in the P&L', 'P&L-এ যুক্ত'), notInPl: L('লাভ-ক্ষতিতে এখনো যুক্ত নয় (সুইচ বন্ধ)', 'Not in the P&L yet (switch off)', 'P&L-এ যুক্ত নয় (switch বন্ধ)'),
  moveTo: L('অন্য জায়গায় সরান', 'Move to another place', 'অন্য জায়গায় সরান'), moveTitle: L('এই অংশ সরান', 'Move this share', 'এই অংশ সরান'), toWhere: L('কোথায় যাবে', 'Move to', 'কোথায় যাবে'),
  hMoves: L('হাতে সরানোর তালিকা (মোছা যায় না)', 'Hand-made moves (cannot be deleted)', 'হাতে সরানো (মোছা যায় না)'), hSettings: L('পছন্দের ইতিহাস', 'History of choices', 'পছন্দের history'), was: L('আগে', 'was', 'আগে'), inactive: L('বাতিল/বদলানো', 'replaced / taken back', 'বাতিল/বদলানো'),
  swHead: L('সুইচ (মালিক ঠিক করেন)', 'Switches (the owner decides)', 'Switch (মালিক ঠিক করেন)'), on: L('চালু', 'On', 'চালু'), off: L('বন্ধ', 'Off', 'বন্ধ'),
  swPl: L('শাখার লাভ-ক্ষতিতে কস্টের অংশ দেখান', 'Show cost shares in the branch P&L', 'শাখার P&L-এ cost-এর অংশ দেখান'),
  swPlHelp: L('বন্ধ (এখনকার মতো): লাভ-ক্ষতির হিসাব একটুও বদলায় না। চালু: উপরের পছন্দ অনুযায়ী খরচের অংশ আলাদা সারিতে যোগ হয়; আগের সারি অপরিবর্তিত থাকে।', 'Off (as today): the P&L does not change at all. On: the shares, as chosen above, are added as separate rows; the existing rows stay unchanged.', 'বন্ধ: P&L বদলায় না। চালু: পছন্দ অনুযায়ী অংশ আলাদা সারিতে যোগ হয়।'),
  swRec: L('রেসিপি অ্যাপ্রুভ', 'Recipe approval', 'Recipe approve'),
  swRecHelp: L('বন্ধ: অ্যাপ্রুভ ছাড়াই চলে (এখনকার মতো)। সতর্ক: অ্যাপ্রুভ না থাকলে হলুদ সতর্কতা আসে, কাজ আটকায় না। জরুরি: অ্যাপ্রুভ ছাড়া রেসিপির কস্ট ও উৎপাদন চলবে না।', 'Off: works without approval (as today). Warn: a yellow warning without approval, work goes on. Required: no recipe cost or production before approval.', 'Off: আজকের মতো। Warn: approve না থাকলে হলুদ সতর্কতা। Required: approve ছাড়া চলবে না।'),
  recOpt: { off: L('বন্ধ', 'Off', 'Off'), warn: L('সতর্ক', 'Warn', 'Warn'), on: L('জরুরি', 'Required', 'Required') },
  swProd: L('উৎপাদনে রেসিপি জরুরি', 'Recipe required for production', 'উৎপাদনে recipe জরুরি'),
  swProdHelp: L('চালু করলে: রেসিপি ছাড়া হাতে কস্ট লিখে উৎপাদন ঢোকানো যাবে না; প্রতিটি পণ্যের কস্ট রেসিপি থেকেই আসবে (সুপারিশ)। বন্ধ থাকলে হাতে লেখা কস্ট চলে, তবে হলুদ সতর্কতা আসে।', 'If on: production cannot be entered with a hand-typed cost without a recipe; every product cost comes from a recipe (recommended). If off: a typed cost works, with a yellow warning.', 'On: recipe ছাড়া হাতে cost দিয়ে production হবে না (সুপারিশ)। Off: চলে, তবে হলুদ সতর্কতা।'),
  swMethod: L('খরচ ধরার পদ্ধতি (জায়গা অনুযায়ী: বন্ধ / রেসিপির হার / মাসিক পুল)', 'Costing method per place (off / recipe rate / monthly pool)', 'Costing পদ্ধতি (place অনুযায়ী: off / recipe / pool)'),
  swMethodGo: L('"খরচ ও ওভারহেড" পাতায় ঠিক করুন', 'Set it in the "Costing & overhead" page', '"Costing ও overhead" পাতায় ঠিক করুন'), ownerOnly: L('এই অংশ শুধু মালিকের', 'This part is for the owner only', 'এই অংশ শুধু মালিকের'),
  hintHead: L('অ্যাপ্রুভের দায়িত্ব — পরামর্শ', 'Approval duty — suggestion', 'approve-এর দায়িত্ব — পরামর্শ'), person: L('কাকে', 'To whom', 'কাকে'), right: L('কোন অনুমতি', 'Which right', 'কোন right'),
  pick: L('বাছুন', 'Choose', 'বাছুন'), check: L('পরামর্শ দেখুন', 'See the suggestion', 'পরামর্শ দেখুন'), hintOk: L('কোনো ঝুঁকি দেখা যাচ্ছে না — একই ব্যক্তি এন্ট্রি ও অ্যাপ্রুভ দুটোই ধরছে না।', 'No risk seen — the same person does not hold both entry and approval.', 'ঝুঁকি দেখা যাচ্ছে না।'),
  hintNote: L('এটি শুধু পরামর্শ — মালিক চাইলে নিজে অ্যাপ্রুভ করতে বা যে কাউকে দায়িত্ব দিতে পারেন; কিছু আটকায় না।', 'This is advice only — the owner may approve himself or give the duty to anyone; nothing is blocked.', 'শুধু পরামর্শ — কিছু আটকায় না।'),
  bothHead: L('এখন যারা এন্ট্রি ও অ্যাপ্রুভ দুটোই ধরে', 'Who holds both entry and approval now', 'এখন যারা entry ও approve দুটোই ধরে'),
};
const T = (k) => lab(X[k]);
const ERR = {
  reason_required: X.reasonNeed, effective_in_past: L('আগের মাস বদলানো যায় না — এই মাস বা পরের মাস বাছুন', 'An earlier month cannot be changed — choose this month or later', 'আগের মাস বদলায় না — এই মাস বা পরের মাস'),
  period_closed: L('এই মাসের হিসাব বন্ধ — মালিক ছাড়া বদলানো যায় না', 'This month is closed — only the owner can change it', 'এই মাস বন্ধ — মালিক ছাড়া নয়'),
  same_destination: L('অংশটি ইতিমধ্যে ওখানেই আছে', 'The share is already there', 'অংশটি ওখানেই আছে'), factory_share_not_reassignable: L('কারখানার অংশ পণ্যের কস্টে যায়, সরানো যায় না', 'A factory share is product cost and cannot be moved', 'Factory অংশ সরানো যায় না'),
  bill_not_fully_allocated: L('বিলের ভাগ-না-হওয়া অংশ আগে ভাগ করুন', 'Allocate the unallocated part of the bill first', 'আগে ভাগ-না-হওয়া অংশ ভাগ করুন'), unknown_location: L('জায়গা বাছুন', 'Choose a place', 'জায়গা বাছুন'), share_not_active: L('এই অংশ আর চালু নেই', 'This share is no longer active', 'এই অংশ চালু নেই'),
};
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/function .* does not exist|schema cache/i.test(m)) return toast(T('sqlMissing')); return A.fail(e); };
const D = { tab: 'opt', month: today().slice(0, 7), floc: '', locs: [], types: [], attr: [], main: [], moves: [], view: null, rules: [], people: [], defs: [], both: [], hint: null, manage: false, owner: false };
const RULE_KEYS = ['cost_attrib_in_pl', 'recipe_approval_required', 'production_requires_recipe'];

async function loadAll() {
  const lo = await sb.rpc('cost_pick_locations'); if (lo.error) throw lo.error; D.locs = lo.data || [];
  const [ty, at, ma, mv, ru] = await Promise.all([sb.from('cost_source_types').select('code,label_bn,label_en').eq('active', true).order('code'), sb.from('location_cost_attribution').select('*').order('id', { ascending: false }),
    sb.from('cost_attrib_main').select('*').order('id', { ascending: false }), sb.from('cost_share_reassign').select('*').order('id', { ascending: false }).limit(80), sb.from('rules').select('key,kind,value,default_value').in('key', RULE_KEYS)]);
  if (at.error) throw at.error;
  D.types = ty.data || []; D.attr = at.data || []; D.main = ma.data || []; D.moves = mv.data || []; D.rules = ru.data || [];
  await loadView();
  if (D.owner) {
    const [pe, df, bo] = await Promise.all([sb.from('profiles').select('id,staff_id,full_name,status').eq('status', 'active').order('full_name'), sb.from('grant_defs').select('grant_code,label_bn,label_en,sort').order('sort'), sb.rpc('grant_separation_report')]);
    D.people = pe.data || []; D.defs = df.data || []; D.both = bo.error ? [] : (bo.data || []);
  }
}
async function loadView() { const r = await sb.rpc('branch_cost_view', { p_month: D.month + '-01', p_loc: D.floc === '' ? null : Number(D.floc) }); D.view = r.error ? null : r.data; if (r.error && !/not allowed/.test(r.error.message || '')) throw r.error; }
const locName = (id) => { const l = D.locs.find((x) => x.id === id); return l ? lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }) : (id === null || id === undefined ? '—' : '#' + id); };
const typeName = (c) => { const t = D.types.find((x) => x.code === c); return t ? lab({ bn: t.label_bn, mix: t.label_bn, en: t.label_en || t.label_bn }) : c; };
const destLbl = (k) => lab(X.dShort[k] || X.dShort.unallocated);
const destOf = (kind, loc) => (kind === 'unallocated' ? destLbl('unallocated') : kind === 'main_centre' ? destLbl('main_centre') + (loc ? ' (' + locName(loc) + ')' : '') : locName(loc));
const SET_L = { showroom: 'dShow', main_centre: 'dMain', unallocated: 'dNone' };
const ruleVal = (k) => { const r = D.rules.find((x) => x.key === k); if (!r) return null; return r.value !== null && r.value !== undefined ? r.value : r.default_value; };
const ym = today().slice(0, 7);

function draw() {
  const el = $('#ca_body'); if (!el) return;
  const tabs = [['opt', 'tOpt'], ['view', 'tView'], ['hist', 'tHist'], ['rules', 'tRules']];
  el.innerHTML = `<div class="tabs" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${tabs.map((t) => `<button type="button" data-act="ca_tab" data-v="${t[0]}" class="${D.tab === t[0] ? 'on' : ''}" style="min-width:0;flex:1 1 40%">${esc(T(t[1]))}</button>`).join('')}</div><div id="ca_pane">${D.tab === 'opt' ? paneOpt() : D.tab === 'view' ? paneView() : D.tab === 'hist' ? paneHist() : paneRules()}</div>`;
}

/* ---------- options per place ---------- */
function curRows(loc) { // rows in force this month (general + typed) and upcoming ones; only active rows count
  const rows = D.attr.filter((a) => a.location_id === loc && a.active);
  const key = (a) => a.cost_type || '';
  const inForce = {}; rows.filter((a) => a.effective_from.slice(0, 7) <= ym).sort((a, b) => (a.effective_from < b.effective_from ? -1 : 1)).forEach((a) => { inForce[key(a)] = a; });
  return { now: Object.values(inForce), next: rows.filter((a) => a.effective_from.slice(0, 7) > ym).sort((a, b) => (a.effective_from < b.effective_from ? -1 : 1)) };
}
function paneOpt() {
  const mainNow = D.main.filter((m) => m.active && m.effective_from.slice(0, 7) <= ym).sort((a, b) => (a.effective_from < b.effective_from ? 1 : -1))[0];
  const mainNext = D.main.filter((m) => m.active && m.effective_from.slice(0, 7) > ym).sort((a, b) => (a.effective_from < b.effective_from ? -1 : 1));
  const chip = (a) => `<div class="row between wrap"><span><span class="chip">${esc(a.cost_type ? typeName(a.cost_type) : T('allTypes'))}</span> ${esc(lab(X[SET_L[a.dest]]))} <span class="muted">${esc(a.effective_from.slice(0, 7))}</span></span>${D.manage && a.effective_from.slice(0, 7) >= ym ? `<button type="button" class="mini" data-act="ca_retire" data-id="${a.id}">${esc(T('retire'))}</button>` : ''}</div>`;
  return `<div class="card muted">${esc(T('intro'))}</div>` + `<div class="card stack"><b>${esc(T('main'))}</b><div>${mainNow ? esc(mainNow.location_id ? locName(mainNow.location_id) : T('mainNone')) : esc(T('notSet'))} ${mainNext.map((m) => `<span class="chip warn">${esc(T('upcoming'))} ${esc(m.effective_from.slice(0, 7))}: ${esc(m.location_id ? locName(m.location_id) : T('mainNone'))}</span>`).join(' ')}</div>
      <div class="muted">${esc(T('mainNote'))}</div>${D.manage ? `<button type="button" class="mini" data-act="ca_main">${esc(T('change'))}</button>` : ''}</div>` +
    D.locs.map((l) => { const c = curRows(l.id); return `<div class="card stack" data-loc="${l.id}"><div class="row between wrap"><b>${esc(locName(l.id))}</b>${D.manage ? `<button type="button" class="mini" data-act="ca_set" data-loc="${l.id}">${esc(T('change'))}</button>` : ''}</div>
      ${c.now.length ? c.now.map(chip).join('') : `<span class="chip warn">${esc(T('notSet'))}</span>`}${c.next.length ? `<div class="muted">${esc(T('upcoming'))}</div>` + c.next.map(chip).join('') : ''}</div>`; }).join('');
}
function setSheet(loc) {
  const types = `<option value="">${esc(T('allTypes'))}</option>` + D.types.map((t) => `<option value="${esc(t.code)}">${esc(typeName(t.code))}</option>`).join('');
  openSheet(`<h3>${esc(locName(loc))}</h3><div class="stack"><label>${esc(T('type'))}<select id="ca_type">${types}</select></label>
    <div class="stack">${['showroom', 'main_centre', 'unallocated'].map((d, i) => `<label class="row"><input type="radio" name="ca_dest" value="${d}" ${i === 0 ? 'checked' : ''}> ${esc(lab(X[SET_L[d]]))}</label>`).join('')}</div>
    <label>${esc(T('from'))}<input type="month" id="ca_from" min="${esc(ym)}" value="${esc(ym)}"></label><div class="muted">${esc(T('fromNote'))}</div>
    <label>${esc(T('reason'))}<input id="ca_why" maxlength="300"></label>
    <button type="button" class="btn primary full" data-act="ca_save" data-loc="${loc}">${esc(T('change'))}</button></div>`);
}
function mainSheet() {
  openSheet(`<h3>${esc(T('main'))}</h3><div class="stack"><label>${esc(T('place'))}<select id="cm_loc"><option value="">${esc(T('mainNone'))}</option>${D.locs.map((l) => `<option value="${l.id}">${esc(locName(l.id))}</option>`).join('')}</select></label>
    <label>${esc(T('from'))}<input type="month" id="cm_from" min="${esc(ym)}" value="${esc(ym)}"></label><div class="muted">${esc(T('fromNote'))}</div><label>${esc(T('reason'))}<input id="cm_why" maxlength="300"></label>
    <button type="button" class="btn primary full" data-act="ca_main_save">${esc(T('change'))}</button></div>`);
}

/* ---------- cost view ---------- */
function paneView() {
  const v = D.view; const filt = `<div class="card stack"><label>${esc(T('month'))}<input type="month" id="ca_month" value="${esc(D.month)}"></label>
    <label>${esc(T('place'))}<select id="ca_floc"><option value="">${esc(T('allPlaces'))}</option>${D.locs.map((l) => `<option value="${l.id}" ${String(D.floc) === String(l.id) ? 'selected' : ''}>${esc(locName(l.id))}</option>`).join('')}</select></label>
    <span class="chip ${v && v.in_pl ? 'ok' : ''}">${esc(v && v.in_pl ? T('inPl') : T('notInPl'))}</span></div>`;
  if (!v) return filt + `<p class="muted">${esc(T('noperm'))}</p>`;
  const tot = (v.totals || []).map((t) => `<div class="row between"><span>${esc(destOf(t.dest_kind, t.dest_location))}</span><b>${money(t.amount)}</b></div>`).join('') || `<span class="muted">${esc(T('none'))}</span>`;
  const rows = (v.rows || []).map((r) => `<div class="card stack" data-share="${r.share_id}"><div class="row between wrap"><b>${esc(lab({ bn: r.type_bn, mix: r.type_bn, en: r.type_en || r.type_bn }))} · ${esc(r.source)}</b><b>${money(r.amount)}</b></div>
      <div class="muted">${esc(locName(r.share_location))} · ${esc(r.share_dest === 'admin' ? T('admin') : T('showroom'))}</div>
      <div>→ <span class="chip ${r.dest_kind === 'unallocated' ? 'warn' : 'ok'}">${esc(destOf(r.dest_kind, r.dest_location))}</span> <span class="chip">${esc(r.via === 'reassigned' ? T('vRe') : r.via === 'setting' ? T('vSetting') : T('vDefault'))}</span>${r.locked_override ? ` <span class="chip warn">${esc(T('locked'))}</span>` : ''}</div>
      ${r.reassigned && r.reason ? `<div class="muted">“${esc(r.reason)}”</div>` : ''}${D.manage ? `<button type="button" class="mini" data-act="ca_re" data-id="${r.share_id}">${esc(T('moveTo'))}</button>` : ''}</div>`).join('');
  return filt + `<div class="card stack"><b>${esc(T('totals'))}</b>${tot}</div>` + (rows || `<p class="muted center">${esc(T('none'))}</p>`);
}
function moveSheet(id) {
  const r = ((D.view && D.view.rows) || []).find((x) => String(x.share_id) === String(id)); if (!r) return;
  openSheet(`<h3>${esc(T('moveTitle'))}</h3><div class="muted">${esc(lab({ bn: r.type_bn, mix: r.type_bn, en: r.type_en || r.type_bn }))} · ${esc(locName(r.share_location))} · ${money(r.amount)}<br>${esc(destOf(r.dest_kind, r.dest_location))}</div>
    <div class="stack"><label>${esc(T('toWhere'))}<select id="cr_to"><option value="">${esc(T('pick'))}</option>${D.locs.map((l) => `<option value="loc:${l.id}">${esc(locName(l.id))}</option>`).join('')}<option value="main_centre">${esc(destLbl('main_centre'))}</option><option value="unallocated">${esc(destLbl('unallocated'))}</option></select></label>
    <label>${esc(T('reason'))}<input id="cr_why" maxlength="300"></label><button type="button" class="btn primary full" data-act="ca_re_save" data-id="${id}">${esc(T('moveTo'))}</button></div>`);
}

/* ---------- history ---------- */
function paneHist() {
  const mv = D.moves.map((m) => `<div class="card stack"><div class="row between wrap"><b>${esc(typeName(m.cost_type))} · ${money(m.amount)}</b><span class="muted">${esc(String(m.created_at).slice(0, 10))}</span></div>
      <div class="muted">${esc(locName(m.share_loc))} · ${esc(String(m.period_month).slice(0, 7))}</div><div>${esc(destOf(m.from_kind, m.from_loc))} → <b>${esc(destOf(m.to_kind, m.to_loc))}</b>${m.locked_override ? ` <span class="chip warn">${esc(T('locked'))}</span>` : ''}</div><div class="muted">“${esc(m.reason)}”</div></div>`).join('');
  const at = D.attr.map((a) => `<div class="card stack" style="${a.active ? '' : 'opacity:.6'}"><div class="row between wrap"><b>${esc(locName(a.location_id))} · ${esc(a.cost_type ? typeName(a.cost_type) : T('allTypes'))}</b><span class="muted">${esc(a.effective_from.slice(0, 7))}</span></div>
      <div>${esc(lab(X[SET_L[a.dest]]))}${a.prev_dest ? ` <span class="muted">(${esc(T('was'))}: ${esc(lab(X[SET_L[a.prev_dest]]))})</span>` : ''}${a.active ? '' : ` <span class="chip">${esc(T('inactive'))}</span>`}</div>${a.reason ? `<div class="muted">“${esc(a.reason)}”</div>` : ''}${a.retired_reason ? `<div class="muted">${esc(a.retired_reason)}</div>` : ''}</div>`).join('');
  return `<h4>${esc(T('hMoves'))}</h4>${mv || `<p class="muted">${esc(T('none'))}</p>`}<h4>${esc(T('hSettings'))}</h4>${at || `<p class="muted">${esc(T('none'))}</p>`}`;
}

/* ---------- rules & duty ---------- */
function paneRules() {
  if (!D.owner) return `<div class="card muted">${esc(T('ownerOnly'))}</div>`;
  const sw = (key, title, help) => { const v = ruleVal(key) === true; return `<div class="card stack"><div class="row between wrap"><b>${esc(T(title))}</b><button type="button" class="tog ${v ? 'on' : ''}" data-act="ca_sw" data-k="${key}">${esc(v ? T('on') : T('off'))}</button></div><div class="muted">${esc(T(help))}</div></div>`; };
  const rec = ruleVal('recipe_approval_required') || 'off';
  const hintBox = D.hint === null ? '' : D.hint.suggest ? `<div class="notice warn" id="ca_hintbox">${esc(lab({ bn: D.hint.message_bn, mix: D.hint.message_bn, en: D.hint.message_en }))}<div class="muted">${esc(T('hintNote'))}</div></div>` : `<div class="notice ok" id="ca_hintbox">${esc(T('hintOk'))}</div>`;
  return `<h4>${esc(T('swHead'))}</h4>${sw('cost_attrib_in_pl', 'swPl', 'swPlHelp')}
    <div class="card stack"><b>${esc(T('swRec'))}</b><div class="row wrap">${['off', 'warn', 'on'].map((o) => `<button type="button" class="tog ${rec === o ? 'on' : ''}" data-act="ca_rec" data-v="${o}">${esc(lab(X.recOpt[o]))}</button>`).join('')}</div><div class="muted">${esc(T('swRecHelp'))}</div></div>
    ${sw('production_requires_recipe', 'swProd', 'swProdHelp')}
    <div class="card stack"><b>${esc(T('swMethod'))}</b><a class="btn full" href="#/costing" style="white-space:normal;height:auto;min-height:44px;text-align:center;display:block;padding:10px">${esc(T('swMethodGo'))}</a></div>
    <h4>${esc(T('hintHead'))}</h4><div class="card stack"><label>${esc(T('person'))}<select id="ca_hp"><option value="">${esc(T('pick'))}</option>${D.people.map((p) => `<option value="${esc(p.id)}">${esc(p.full_name || p.staff_id)}</option>`).join('')}</select></label>
      <label>${esc(T('right'))}<select id="ca_hg"><option value="">${esc(T('pick'))}</option>${D.defs.map((d) => `<option value="${esc(d.grant_code)}">${esc(lab({ bn: d.label_bn, mix: d.label_bn, en: d.label_en || d.label_bn }))}</option>`).join('')}</select></label>
      <button type="button" class="btn primary full" data-act="ca_hint">${esc(T('check'))}</button>${hintBox}</div>
    <div class="card stack"><b>${esc(T('bothHead'))}</b>${D.both.length ? D.both.map((x) => { const p = D.people.find((y) => y.id === x.user_id); return `<div>${esc(p ? (p.full_name || p.staff_id) : '—')} · ${esc(lab({ bn: x.label_bn, mix: x.label_bn, en: x.label_en }))}</div>`; }).join('') : `<span class="muted">${esc(T('none'))}</span>`}</div>`;
}

/* ---------- handlers ---------- */
async function refresh() { try { await loadAll(); draw(); } catch (e) { errMsg(e); } }
const setRule = async (k, v) => { const r = await sb.rpc('set_rule', { p_key: k, p_value: v }); if (r.error) return errMsg(r.error); try { if (B.reloadRules) await B.reloadRules(); } catch (e) { /* ignore */ } toast(T('saved')); await refresh(); };
Object.assign(H, {
  ca_tab: (a) => { D.tab = a.dataset.v; draw(); },
  ca_set: (a) => setSheet(Number(a.dataset.loc)),
  ca_main: mainSheet,
  ca_save: async (a) => {
    const why = ($('#ca_why').value || '').trim(); const type = $('#ca_type').value || null;
    const hasPrev = D.attr.some((x) => x.active && x.location_id === Number(a.dataset.loc) && (x.cost_type || null) === type);
    if (hasPrev && why.length < 3) return toast(T('reasonNeed'));
    const r = await sb.rpc('cost_attrib_set', { p_loc: Number(a.dataset.loc), p_cost_type: type, p_dest: (document.querySelector('input[name=ca_dest]:checked') || {}).value, p_effective: ($('#ca_from').value || ym) + '-01', p_reason: why || null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  ca_main_save: async () => {
    const loc = $('#cm_loc').value; const why = ($('#cm_why').value || '').trim();
    const r = await sb.rpc('cost_attrib_main_set', { p_loc: loc === '' ? null : Number(loc), p_effective: ($('#cm_from').value || ym) + '-01', p_reason: why || null, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  ca_retire: async (a) => { const w = window.prompt(T('reason')); if (!w) return; const r = await sb.rpc('cost_attrib_retire', { p_id: Number(a.dataset.id), p_reason: w }); if (r.error) return errMsg(r.error); toast(T('saved')); await refresh(); },
  ca_re: (a) => moveSheet(a.dataset.id),
  ca_re_save: async (a) => {
    const to = $('#cr_to').value; const why = ($('#cr_why').value || '').trim(); if (!to) return toast(T('pick')); if (why.length < 3) return toast(T('reasonNeed'));
    const kind = to.startsWith('loc:') ? 'location' : to;
    const r = await sb.rpc('cost_share_reassign', { p_share: Number(a.dataset.id), p_to_kind: kind, p_to_loc: kind === 'location' ? Number(to.slice(4)) : null, p_reason: why, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  ca_sw: (a) => setRule(a.dataset.k, !(ruleVal(a.dataset.k) === true)),
  ca_rec: (a) => setRule('recipe_approval_required', a.dataset.v),
  ca_hint: async () => {
    const u = $('#ca_hp').value, g = $('#ca_hg').value; if (!u || !g) return toast(T('pick'));
    const r = await sb.rpc('grant_separation_hint', { p_user: u, p_grant: g }); if (r.error) return errMsg(r.error); D.hint = r.data; draw();
    const sel = $('#ca_hp'); if (sel) sel.value = u; const sg = $('#ca_hg'); if (sg) sg.value = g;
  },
});
document.addEventListener('change', async (e) => {
  const t = e.target; if (!t || !t.id) return;
  if (t.id === 'ca_month') { D.month = t.value || D.month; await loadView().catch(errMsg); draw(); }
  if (t.id === 'ca_floc') { D.floc = t.value; await loadView().catch(errMsg); draw(); }
});

async function view() {
  shell(T('title'), `<div id="ca_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try {
    D.owner = !!(S.ctx && S.ctx.is_owner); let ok = D.owner; if (!ok) { try { ok = !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { ok = false; } }
    if (!ok) { const b = $('#ca_body'); if (b) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; }
    D.manage = D.owner; if (!D.manage) { try { D.manage = !!(await A.hasAnyGrant(['cost_attrib_manage'])); } catch (e) { D.manage = false; } }
    D.hint = null; await loadAll(); draw();
  } catch (e) { const b = $('#ca_body'); if (b && /not allowed|permission/i.test((e && e.message) || '')) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; else errMsg(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { costattrib: view });
})();
