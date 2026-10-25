/* Islamia BOS · Business Memory: "Ask / Find" and the Spend finder.
   A sentence in Bengali or English is turned into filters by the rule-based parser (reporthub_parse.js, word lists in web/data/report_registry.json). NO AI call at run time.
   The page ALWAYS shows "I understood: person · what · place · period" as editable chips next to the answer, so a wrong reading is visible. If the parser is unsure it does
   not run a guess: it shows the guided filter builder, pre-filled, and the best matching reports. The numbers come from rpt_hub_spend (supabase/phase476.sql), read only.
   A row says whether it matched by head, by memo or both; a person filter never guesses: rows that name no person are counted apart as "not linked to a person". */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { esc, toast, shell, H, nm, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const R = B.rhub;
const $ = (s, el = document) => el.querySelector(s);
const { money, addDays, monthStart, monthEnd, dhakaToday } = R;
const T = R.T;

const Y = {
  title: L('জিজ্ঞাসা / খরচ খুঁজুন', 'Ask / Spend finder', 'Ask / Spend finder'), q_ph: L('প্রশ্ন লিখুন…', 'Type a question…', 'প্রশ্ন লিখুন…'), run: L('চালান', 'Run', 'Run'), understood: L('আমি যা বুঝেছি', 'I understood', 'I understood'),
  c_person: L('কে', 'Person', 'Person'), c_head: L('কী বাবদ', 'What', 'What'), c_place: L('কোথায়', 'Place', 'Place'), c_period: L('কখন', 'Period', 'Period'),
  any: L('যেকোনো', 'any', 'any'), choose: L('বেছে নিন', 'choose', 'choose'), pick_person: L('কোনজন?', 'Which one?', 'Which one?'), not_found: L('পাওয়া যায়নি', 'not found', 'not found'), looking: L('খুঁজছি…', 'Looking…', 'Looking…'),
  edit: L('বদলান', 'Edit', 'Edit'), apply: L('প্রয়োগ', 'Apply', 'Apply'), clear: L('মুছুন', 'Clear', 'Clear'), close: L('বন্ধ', 'Close', 'Close'), lookup: L('খুঁজুন', 'Look up', 'Look up'),
  not_run: L('আমি কোনো সংখ্যা অনুমান করিনি। নিচের ঘরগুলো ঠিক করুন বা একটি রিপোর্ট বেছে নিন।', 'I did not guess a number. Fix the chips below or open one of the reports.', 'কোনো সংখ্যা অনুমান করিনি। chip ঠিক করুন বা report বেছে নিন।'),
  need_period: L('সময় লেখা হয়নি — একটি বেছে নিন', 'No period was given — choose one', 'সময় দেওয়া হয়নি — বেছে নিন'), need_person: L('এই নামটি আগে খুঁজে নিন', 'Look this name up first', 'এই নামটি আগে খুঁজুন'),
  amb_head: L('একাধিক অর্থ হতে পারে — বেছে নিন', 'More than one reading — choose', 'একাধিক অর্থ — বেছে নিন'), amb_place: L('একাধিক জায়গা — বেছে নিন', 'More than one place — choose', 'একাধিক place — বেছে নিন'),
  fiscal_na: L('অর্থবছরের শুরুর মাস নিয়মে (Rules) বসানো নেই', 'The fiscal-year start month is not set in Rules', 'Fiscal year start month Rules-এ নেই'),
  reports_h: L('মিলে যাওয়া রিপোর্ট', 'Reports that match', 'Matching reports'), builder: L('ফিল্টার ঠিক করুন', 'Guided filters', 'Guided filters'), examples: L('উদাহরণ', 'Examples', 'Examples'),
  total: L('মোট', 'Total', 'Total'), txns: L('লেনদেন', 'transactions', 'transactions'), by_month: L('মাস অনুযায়ী', 'Month by month', 'Month by month'), by_head: L('খাত অনুযায়ী', 'By head', 'By head'), by_kind: L('উৎস অনুযায়ী', 'By source', 'By source'),
  matched: L('কীভাবে মিলেছে', 'Matched by', 'Matched by'), m_head: L('খাত', 'head', 'head'), m_memo: L('বিবরণ', 'memo', 'memo'), m_both: L('দুটোই', 'both', 'both'), m_filter: L('ফিল্টার', 'filter', 'filter'),
  linked: L('ব্যক্তির সাথে সংযুক্ত', 'Linked to the person', 'Linked to the person'), l_direct: L('সরাসরি রেকর্ডে', 'stored on the record', 'stored on the record'), l_text: L('বিবরণে নাম আছে (যাচাই করা সংযোগ নয়)', 'name appears in the memo (not a verified link)', 'memo-তে নাম আছে (verified নয়)'),
  unlinked_h: L('কোনো ব্যক্তির সাথে যুক্ত নয়', 'Not linked to a person', 'Not linked to a person'), unlinked_t: L('এই খরচগুলো একই খাত/শব্দে মিলেছে কিন্তু কার জন্য তা লেখা নেই। আমি আন্দাজ করিনি।', 'These match the same head / words but the record does not say for whom. I did not guess.', 'এগুলো match করেছে কিন্তু কার জন্য লেখা নেই। আন্দাজ করিনি।'),
  missing_field: L('যে ঘর থাকলে সংযোগ করা যেত', 'Field that would make the link possible', 'Missing field'),
  mf_quick_expenses_person_id: L('দ্রুত খরচে কর্মীর আইডি (এখন শুধু "কাকে দেওয়া" লেখা)', 'a person id on quick expenses (today only a free-text "paid to")', 'quick expense-এ person id'),
  mf_entries_10_2_lines_person_id: L('খরচ ভাউচারের প্রতি লাইনে কর্মীর আইডি (এখন শুধু "কার কাছে")', 'a person id on each 11-1 voucher line (today only a free-text "to")', '11-1 line-এ person id'),
  mf_cost_source_bills_person_id: L('ইউটিলিটি বিলে ব্যক্তির ঘর নেই', 'utility bills have no person field', 'utility bill-এ person field নেই'), mf_journal_lines_party_id: L('জার্নাল লাইনে পার্টি আইডি', 'a party id on the journal line', 'journal line-এ party id'),
  overlap: L('একই খরচ ভাউচারেও আছে হতে পারে (মোটে ধরা হয়নি)', 'may repeat an expense voucher (left out of the total)', 'voucher-এও থাকতে পারে (total-এ নেই)'),
  no_src: L('পেমেন্টের উৎস লেখা নেই বলে বাদ', 'left out: the payment source is not recorded', 'payment source নেই বলে বাদ'),
  n_account_filter_reads_the_journal_only: L('হিসাবের ঘর বাছলে শুধু জার্নাল পড়া হয়', 'An account filter reads the journal only', 'Account filter শুধু journal পড়ে'),
  n_journal_shows_manual_entries_only_when_combined: L('অন্য উৎসের সাথে মিলিয়ে দেখলে জার্নালের শুধু হাতে-লেখা এন্ট্রি আসে (বাকিগুলো আগেই গোনা)', 'Combined with other sources, only manual journal entries are added (the rest repeat them)', 'Journal-এর শুধু manual entry আসে'),
  n_purchase_and_payment_both_selected_count_twice: L('ক্রয় বিল ও তার পরিশোধ একসাথে বাছলে একই টাকা দুবার গোনা হবে', 'A bill and its payment together count the money twice', 'Bill ও payment একসাথে দুবার গোনা'),
  n_rows_without_a_recorded_payment_source_are_left_out: L('যাদের পেমেন্টের উৎস লেখা নেই তারা বাদ', 'Rows with no recorded payment source are left out', 'Payment source নেই এমন row বাদ'),
  n_utility_bills_may_repeat_a_voucher: L('ইউটিলিটি বিল ও ভাউচার একই খরচ হতে পারে — "যা ভাউচারেও আছে" দেখুন', 'A utility bill and a voucher can be the same payment — see "may repeat"', 'Utility bill ও voucher একই হতে পারে'),
  n_person_needs_a_right: L('এই ব্যক্তির খরচ দেখতে বিশেষ অনুমতি লাগে (বেতন/ক্রয়/বিক্রি)', 'This person filter needs a right you do not have (payroll / purchases / sales)', 'এই person filter-এর permission নেই'),
  masked_pay: L('কর্মীর বেতন/অগ্রিম/খাবার-মজুরির সারি বেতনের অনুমতি ছাড়া দেখানো হয় না', 'Staff pay, advance, meal and labour rows need the payroll right and are not shown to you', 'Staff pay/advance/meal/labour row payroll right ছাড়া দেখানো হয় না'),
  k_quick_expense: L('দ্রুত খরচ', 'Quick expenses', 'Quick expenses'), k_expense_voucher: L('খরচ ভাউচার', 'Expense vouchers', 'Expense vouchers'), k_advance: L('কর্মীর অগ্রিম', 'Staff advances', 'Staff advances'), k_salary: L('বেতন', 'Salary', 'Salary'),
  k_purchase: L('ক্রয় বিল', 'Purchase bills', 'Purchase bills'), k_supplier_payment: L('সরবরাহকারীকে পরিশোধ', 'Supplier payments', 'Supplier payments'), k_customer_refund: L('গ্রাহকের রিফান্ড', 'Customer refunds', 'Customer refunds'), k_utility_bill: L('ইউটিলিটি বিল', 'Utility bills', 'Utility bills'), k_journal: L('জার্নাল (খরচের হিসাব)', 'Journal (expense accounts)', 'Journal'),
  st_posted: L('পোস্ট করা', 'Posted only', 'Posted only'), st_all: L('সব (খসড়া, বাতিল, উল্টানো সহ)', 'All (drafts, voids, reversals too)', 'All'), st_draft: L('খসড়া', 'Drafts', 'Drafts'), st_void: L('বাতিল', 'Voids', 'Voids'), st_reversed: L('উল্টানো', 'Reversals', 'Reversals'),
  from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), kinds: L('কোন উৎস', 'Sources', 'Sources'), status: L('অবস্থা', 'Status', 'Status'), pay: L('পেমেন্টের উৎস', 'Payment source', 'Payment source'), account: L('হিসাবের খাত (জার্নাল)', 'Account (journal)', 'Account'), words: L('বিবরণে শব্দ (কমা দিয়ে)', 'Words in the memo (comma separated)', 'Memo words'),
  head_any: L('— যেকোনো —', '— any —', '— any —'), person_kind: L('ব্যক্তির ধরন', 'Kind of person', 'Kind of person'), p_staff: L('কর্মী', 'Staff', 'Staff'), p_supplier: L('সরবরাহকারী', 'Supplier', 'Supplier'), p_customer: L('গ্রাহক', 'Customer', 'Customer'), p_auto: L('যেকোনো', 'Any', 'Any'),
  name_ph: L('নাম লিখুন', 'Type a name', 'নাম লিখুন'), preset_q: L('বা লিখুন (যেমন: গত ৬ মাস)', 'or type (e.g. last 6 months)', 'বা লিখুন (e.g. last 6 months)'), px_this_month: L('এই মাস', 'This month', 'This month'), px_last_month: L('গত মাস', 'Last month', 'Last month'), px_this_year: L('এই বছর', 'This year', 'This year'), px_last_year: L('গত বছর', 'Last year', 'Last year'), px_l3: L('শেষ ৩ মাস', 'Last 3 months', 'Last 3 months'), px_l12: L('শেষ ১২ মাস', 'Last 12 months', 'Last 12 months'),
  csv_h: ['date', 'source', 'status', 'amount', 'head', 'head_label', 'memo', 'outlet', 'payment_mode', 'recorded_by', 'matched_by', 'person_link', 'record_table', 'record_id'],
  none: L('কিছু পাওয়া যায়নি', 'No matching transaction', 'কিছু পাওয়া যায়নি'), as_of: L('সময়কাল', 'Period', 'Period'), more_info: L('বিস্তারিত', 'Details', 'Details'), h_label: L('খাতের নাম', 'Head', 'Head'),
  ex1: L('গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত', 'electricity bill of main branch, last 8 months', 'গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল'), ex2: L('গত এক বছরে একজন কর্মীর খাবার বাবদ কত দিয়েছি', 'how much was paid for one staff member\'s meals in the last year', 'গত এক বছরে কর্মীর খাবার বাবদ কত'),
  ex3: L('এই মাসের পরিবহন খরচ', 'transport this month', 'এই মাসের transport খরচ'), ex4: L('গতকাল কী হয়েছিল', 'what happened yesterday', 'গতকাল কী হয়েছিল'),
};
const TY = (k) => lab(Y[k]);

// ---------- state ----------
const AS = { q: '', parsed: null, f: null, person: null, cands: null, opts: null, res: null, off: 0, reg: null, edit: null };
const defaultKinds = ['quick_expense', 'expense_voucher', 'advance', 'salary', 'purchase', 'utility_bill'];
const emptyF = () => ({ from: '', to: '', loc: '', person: null, heads: [], terms: [], topic: '', kinds: [], status: ['posted'], pay_mode: '', money_account_id: '', account_id: '', label: {} });
const PAGE = 50;
const rule = (k, d) => { try { return B.rule ? B.rule(k, d) : d; } catch (e) { return d; } };
async function ensure() {
  if (!AS.reg) AS.reg = await R.registry();
  if (!AS.opts) { const r = await R.rpc('rpt_hub_spend_options'); AS.opts = r.data || { heads: [], utility_types: [], accounts: [], money_accounts: [], locations: [] }; AS.optsErr = r.error ? r.msg : null; }
  R.headLabel = (c) => { const h = (AS.opts.heads || []).find((x) => x.code === c); return h ? lab({ bn: h.label_bn, en: h.label_en, mix: h.label_en }) : c; };
}
const ctxFor = () => ({ today: dhakaToday(), locations: R.locs().map((l) => ({ id: l.id, code: l.code, kind: l.kind, name_bn: l.name_bn, name_en: l.name_en })), registry: AS.reg, fiscalStartMonth: Number(rule('fiscal_year_start_month', null)) || null, weekStart: { sat: 6, sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5 }[rule('week_start', 'sat')] ?? 6 });
const topicByKey = (k) => (AS.reg.parser.heads || []).find((h) => h.key === k);

// ---------- from a parse to filters ----------
function fromParse(pz) {
  const f = emptyF(), S = pz.slots;
  if (S.period && !S.period.needs_setting) { f.from = S.period.from; f.to = S.period.to; f.label.period = lab({ bn: S.period.label_bn, en: S.period.label_en, mix: S.period.label_en }); }
  if (S.place) { f.loc = String(S.place.id); }
  if (S.head) { f.topic = S.head.key; f.heads = [...new Set((S.head.heads || []).concat(S.head.utility || []))]; f.terms = S.head.terms || []; }
  if (S.kind_list && S.kind_list.length) f.kinds = S.kind_list;
  if (S.person) f.person = { kind: S.person.kind, query: S.person.query, alts: S.person.alts, id: null, label: null };
  return f;
}
const periodLabel = (f) => (f.from ? (f.label.period ? f.label.period + ' · ' : '') + f.from + ' → ' + f.to : '');
const apiFilters = (f) => {
  const o = { from: f.from, to: f.to };
  if (f.loc !== '' && f.loc !== null) o.loc = Number(f.loc);
  if (f.person && f.person.id) o.person = { kind: f.person.kind, id: String(f.person.id) };
  if (f.heads.length) o.heads = f.heads; if (f.terms.length) o.terms = f.terms;
  if (f.kinds.length) o.kinds = f.kinds; if (f.status.length) o.status = f.status;
  if (f.pay_mode) o.pay_mode = f.pay_mode; if (f.money_account_id) o.money_account_id = Number(f.money_account_id); if (f.account_id) o.account_id = Number(f.account_id);
  return o;
};

// ---------- person lookup ----------
async function lookupPerson(f) {
  const p = f.person; if (!p || p.id) return { state: 'ok' };
  const kinds = p.kind === 'auto' || !p.kind ? ['staff', 'supplier', 'customer'] : [p.kind];
  const out = [];
  for (const k of kinds) for (const q of (p.alts && p.alts.length ? p.alts : [p.query])) {
    const r = await R.rpc('rpt_hub_find_entity', { p_kind: k, p_q: q, p_limit: 10 });
    if (r.data && r.data.length) { r.data.forEach((x) => { if (!out.some((o) => o.id === x.id)) out.push(Object.assign({ pkind: x.kind === 'employee' ? 'staff' : x.kind }, x)); }); break; }
  }
  if (!out.length) return { state: 'none' };
  if (out.length === 1) { p.id = out[0].id; p.kind = out[0].pkind; p.label = out[0].label; return { state: 'ok' }; }
  AS.cands = out; return { state: 'many' };
}

// ---------- screen ----------
async function viewAsk(p) {
  shell(TY('title'), `<div class="card stack rh-ask"><div class="row"><input id="rh_aq" type="search" autocomplete="off" value="${esc(p.q || '')}" placeholder="${esc(TY('q_ph'))}" aria-label="${esc(TY('q_ph'))}"><button class="primary" data-act="rh_ask_run">${esc(TY('run'))}</button></div></div>
    <div id="rh_chips"></div><div id="rh_out">${R.stateHTML('loading')}</div>`, 'reports/hub');
  R.currentParams = () => ({ f: JSON.stringify(AS.f ? apiFilters(AS.f) : {}), q: AS.q });
  try { await ensure(); } catch (e) { return setOut(R.stateHTML('error', T('reg_fail'), 'rh_retry')); }
  if (p.q) { AS.q = p.q; return runQuestion(p.q); }
  return setOut(examples());
}
async function viewSpend(p) {
  shell(TY('title'), `<div id="rh_chips"></div><div id="rh_out">${R.stateHTML('loading')}</div>`, 'reports/hub');
  R.currentParams = () => ({ f: JSON.stringify(AS.f ? apiFilters(AS.f) : {}), q: AS.q });
  try { await ensure(); } catch (e) { return setOut(R.stateHTML('error', T('reg_fail'), 'rh_retry')); }
  let f = emptyF(); const t = dhakaToday();
  if (p.f) { try { const o = JSON.parse(p.f); f = fromApi(o); } catch (e) { /* keep empty */ } }
  if (!f.from) { f.from = monthStart(t); f.to = t; f.label.period = lab(L('এই মাস', 'this month', 'this month')); }
  AS.f = f; AS.q = ''; AS.off = 0; AS.parsed = null;
  chipsDraw(); builderDraw(true);
  if (p.f) return runSpend();
  setOut(builderHTML(true));
}
function fromApi(o) {
  const f = emptyF(); f.from = o.from || ''; f.to = o.to || ''; f.loc = o.loc == null ? '' : String(o.loc);
  if (o.person) f.person = { kind: o.person.kind, id: o.person.id, label: o.person.label || null, query: o.person.label || '' };
  f.heads = o.heads || []; f.terms = o.terms || []; f.kinds = o.kinds || []; f.status = o.status && o.status.length ? o.status : ['posted'];
  f.pay_mode = o.pay_mode || ''; f.money_account_id = o.money_account_id == null ? '' : String(o.money_account_id); f.account_id = o.account_id == null ? '' : String(o.account_id);
  const tp = (AS.reg.parser.heads || []).find((h) => h.heads.every((x) => f.heads.includes(x)) && f.heads.length && (h.utility || []).every((x) => f.heads.includes(x))); if (tp) f.topic = tp.key;
  return f;
}
const setOut = (h) => { const el = $('#rh_out'); if (el) el.innerHTML = h; };
function examples() {
  return `<div class="card stack"><b>${esc(TY('examples'))}</b>${['ex1', 'ex2', 'ex3', 'ex4'].map((k) => `<button class="rp-row" data-act="rh_ex" data-v="${esc(lab(Y[k]))}"><span class="nm">${esc(lab(Y[k]))}</span><span class="cv">›</span></button>`).join('')}
    <button class="full" data-act="rh_open_tool" data-v="spend">${esc(TY('builder'))}</button></div>`;
}

async function runQuestion(text) {
  AS.q = text; AS.off = 0; AS.cands = null;
  const pz = B.parse.parse(text, ctxFor()); AS.parsed = pz;
  if (pz.intent === 'day' && pz.slots.period && pz.slots.period.day) { return R.go('day', { date: pz.slots.period.from, loc: pz.slots.place ? pz.slots.place.id : '' }); }
  if (pz.intent === 'compare' && pz.slots.period && pz.slots.period2) { const a = pz.slots.period, b = pz.slots.period2; return R.go('compare', { af: a.from, at: a.to, bf: b.from, bt: b.to, loc: pz.slots.place ? pz.slots.place.id : '' }); }
  const f = fromParse(pz); AS.f = f;
  if (f.person) { const lk = await lookupPerson(f); f.person.state = lk.state; }
  chipsDraw(pz);
  const missing = [];
  if (pz.missing.includes('period')) missing.push('period');
  if (pz.ambiguities.length) missing.push('ambiguous');
  if (f.person && !f.person.id) missing.push('person');
  if (pz.intent === 'spend' && !missing.length) { builderDraw(false); return runSpend(); }
  // unsure: the builder, pre-filled, and the best reports. No number.
  const reports = reportsFor(text, pz);
  setOut(`<div class="notice warn mk warn">${esc(TY('not_run'))}${missing.includes('period') ? '<br>' + esc(pz.notes.includes('fiscal_year_not_set') ? TY('fiscal_na') : TY('need_period')) : ''}${missing.includes('person') && f.person.state === 'none' ? '<br>' + esc(TY('not_found')) + ': ' + esc(f.person.query) : ''}</div>
    ${f.person && AS.cands && AS.cands.length ? candsHTML() : ''}${reports}${pz.intent === 'spend' || pz.intent === 'unknown' || pz.intent === 'report' ? builderHTML(false) : ''}${examples()}`);
}
function reportsFor(text, pz) {
  const list = (pz && pz.reports && pz.reports.length ? pz.reports.map((x) => AS.reg.reports.find((r) => r.no === x.no)).filter(Boolean) : R.searchReports(AS.reg, text, 5));
  if (!list.length) return '';
  return `<div class="hsec">${esc(TY('reports_h'))}</div><div class="card" style="padding:4px 12px">${list.slice(0, 5).map((r) => `<div class="row between rh-mrow2"><span class="nm" style="min-width:0"><b>#${r.no} ${esc(R.pick(r.name))}</b><br><small class="muted">${esc(R.pick(r.question))}</small></span>${r.route ? `<button data-act="rh_open_rep" data-v="${esc(r.id)}">${esc(T('open'))}</button>` : `<span class="chip">${esc(T('planned'))}</span>`}</div>`).join('')}</div>`;
}
function candsHTML() {
  return `<div class="card"><b>${esc(TY('pick_person'))}</b>${AS.cands.map((x, i) => `<button class="rp-row" data-act="rh_pick_person" data-i="${i}"><span class="nm">${esc(x.label)}<small>${esc(TY('p_' + x.pkind))} · ${esc(x.sub || '')}</small></span><span class="cv">›</span></button>`).join('')}</div>`;
}

// ---------- chips ----------
function chipsDraw(pz) {
  const el = $('#rh_chips'); if (!el || !AS.f) return;
  const f = AS.f, pzz = pz || AS.parsed;
  const chip = (slot, state, label, val) => `<button class="rh-chip ${state}" data-act="rh_chip" data-s="${slot}" aria-label="${esc(TY('edit') + ': ' + label)}"><small>${esc(label)}</small> <b>${esc(val)}</b></button>`;
  const amb = (pzz && pzz.ambiguities) || [];
  const headVal = f.topic ? lab(topicByKey(f.topic).label ? { bn: topicByKey(f.topic).label.bn, en: topicByKey(f.topic).label.en, mix: topicByKey(f.topic).label.en } : { en: f.topic, bn: f.topic, mix: f.topic }) : (f.heads.length ? f.heads.map((c) => R.headLabel ? R.headLabel(c) : c).join(', ') : (f.terms.length ? f.terms.join(', ') : ''));
  const personVal = f.person ? (f.person.label || f.person.query || '') + (f.person.id ? '' : f.person.state === 'none' ? ' — ' + TY('not_found') : f.person.state === 'many' ? ' — ' + TY('choose') : ' — ' + TY('need_person')) : '';
  const placeVal = f.loc !== '' ? R.locName(f.loc) : '';
  const perVal = f.from ? periodLabel(f) : '';
  const perState = !f.from ? 'missing' : 'ok';
  el.innerHTML = `<div class="muted" style="margin:6px 0 0">${esc(TY('understood'))}:</div><div class="rh-chips">
    ${chip('person', f.person ? (f.person.id ? 'ok' : 'ambiguous') : 'any', TY('c_person'), personVal || TY('any'))}
    ${chip('head', amb.some((a) => a.slot === 'head') ? 'ambiguous' : (headVal ? 'ok' : 'any'), TY('c_head'), amb.some((a) => a.slot === 'head') ? TY('amb_head') : (headVal || TY('any')))}
    ${chip('place', amb.some((a) => a.slot === 'place') ? 'ambiguous' : (placeVal ? 'ok' : 'any'), TY('c_place'), amb.some((a) => a.slot === 'place') ? TY('amb_place') : (placeVal || TY('any')))}
    ${chip('period', perState, TY('c_period'), perVal || TY('need_period'))}</div>`;
}
function openEditor(slot) {
  const f = AS.f; if (!f) return;
  let body = '';
  if (slot === 'person') {
    body = `<h3>${esc(TY('c_person'))}</h3><div class="stack"><select id="rh_ek" aria-label="${esc(TY('person_kind'))}">${['auto', 'staff', 'supplier', 'customer'].map((k) => `<option value="${k}" ${((f.person && f.person.kind) || 'auto') === k ? 'selected' : ''}>${esc(TY('p_' + k))}</option>`).join('')}</select>
      <input id="rh_eq2" autocomplete="off" value="${esc((f.person && (f.person.label || f.person.query)) || '')}" placeholder="${esc(TY('name_ph'))}" aria-label="${esc(TY('name_ph'))}">
      <div class="row"><button class="primary" data-act="rh_ed_person">${esc(TY('lookup'))}</button><button data-act="rh_ed_clear" data-s="person">${esc(TY('clear'))}</button></div><div id="rh_ecand"></div></div>`;
  } else if (slot === 'head') {
    const tops = AS.reg.parser.heads.map((h) => `<option value="${esc(h.key)}" ${f.topic === h.key ? 'selected' : ''}>${esc(lab({ bn: h.label.bn, en: h.label.en, mix: h.label.en }))}</option>`).join('');
    const raw = (AS.opts.heads || []).filter((h) => h.list !== 'other_income_heads').map((h) => `<option value="code:${esc(h.code)}" ${!f.topic && f.heads.length === 1 && f.heads[0] === h.code ? 'selected' : ''}>${esc(lab({ bn: h.label_bn, en: h.label_en, mix: h.label_en }))}</option>`).join('');
    body = `<h3>${esc(TY('c_head'))}</h3><div class="stack"><select id="rh_eh" aria-label="${esc(TY('c_head'))}"><option value="">${esc(TY('head_any'))}</option><optgroup label="${esc(TY('examples'))}">${tops}</optgroup><optgroup label="${esc(TY('h_label'))}">${raw}</optgroup></select>
      <label class="muted">${esc(TY('words'))}<input id="rh_ew" autocomplete="off" value="${esc((f.terms || []).join(', '))}"></label>
      <div class="row"><button class="primary" data-act="rh_ed_head">${esc(TY('apply'))}</button><button data-act="rh_ed_clear" data-s="head">${esc(TY('clear'))}</button></div></div>`;
  } else if (slot === 'place') {
    body = `<h3>${esc(TY('c_place'))}</h3><div class="stack">${R.locSelect('rh_el', f.loc, TY('any'))}<div class="row"><button class="primary" data-act="rh_ed_place">${esc(TY('apply'))}</button></div></div>`;
  } else if (slot === 'period') {
    body = `<h3>${esc(TY('c_period'))}</h3><div class="stack"><div class="rh-kinds">${['this_month', 'last_month', 'this_year', 'last_year', 'l3', 'l12'].map((k) => `<button class="chip" data-act="rh_ed_pre" data-v="${k}">${esc(TY('px_' + k))}</button>`).join('')}</div>
      <div class="rh-dates"><label>${esc(TY('from'))}<input id="rh_ef" type="date" value="${esc(f.from)}"></label><label>${esc(TY('to'))}<input id="rh_et" type="date" value="${esc(f.to)}"></label></div>
      <input id="rh_ep" autocomplete="off" placeholder="${esc(TY('preset_q'))}" aria-label="${esc(TY('preset_q'))}"><div class="row"><button class="primary" data-act="rh_ed_period">${esc(TY('apply'))}</button></div></div>`;
  }
  openSheet(body);
}
const todayP = () => dhakaToday();
function presetRange(k) {
  const t = todayP(), ms = monthStart(t);
  if (k === 'this_month') return [ms, t, TY('px_this_month')];
  if (k === 'last_month') { const lm = addDays(ms, -1); return [monthStart(lm), monthEnd(lm), TY('px_last_month')]; }
  if (k === 'this_year') return [t.slice(0, 4) + '-01-01', t, TY('px_this_year')];
  if (k === 'last_year') { const y = String(parseInt(t.slice(0, 4), 10) - 1); return [y + '-01-01', y + '-12-31', TY('px_last_year')]; }
  if (k === 'l3') return [addDays(B.parse.addMonths(t, -3), 1), t, TY('px_l3')];
  return [addDays(B.parse.addMonths(t, -12), 1), t, TY('px_l12')];
}
function setPeriod(a, b, label) { AS.f.from = a; AS.f.to = b; AS.f.label.period = label || ''; }

// ---------- the guided builder ----------
function builderHTML(open) {
  const f = AS.f || emptyF();
  const kinds = ['quick_expense', 'expense_voucher', 'advance', 'salary', 'purchase', 'supplier_payment', 'customer_refund', 'utility_bill', 'journal'];
  const on = f.kinds.length ? f.kinds : defaultKinds;
  return `<details id="rh_bld" class="card" ${open ? 'open' : ''}><summary><b>${esc(TY('builder'))}</b></summary><div class="stack">
    <div class="rh-dates"><label>${esc(TY('from'))}<input id="rh_bf" type="date" value="${esc(f.from)}"></label><label>${esc(TY('to'))}<input id="rh_bt" type="date" value="${esc(f.to)}"></label></div>
    <div class="rh-kinds">${['this_month', 'last_month', 'this_year', 'last_year', 'l3', 'l12'].map((k) => `<button class="chip" data-act="rh_b_pre" data-v="${k}">${esc(TY('px_' + k))}</button>`).join('')}</div>
    <label class="muted">${esc(TY('c_place'))}${R.locSelect('rh_bl', f.loc, TY('any'))}</label>
    <label class="muted">${esc(TY('c_head'))}<select id="rh_bh"><option value="">${esc(TY('head_any'))}</option>${AS.reg.parser.heads.map((h) => `<option value="${esc(h.key)}" ${f.topic === h.key ? 'selected' : ''}>${esc(lab({ bn: h.label.bn, en: h.label.en, mix: h.label.en }))}</option>`).join('')}${(AS.opts.heads || []).filter((h) => h.list !== 'other_income_heads').map((h) => `<option value="code:${esc(h.code)}" ${!f.topic && f.heads.length === 1 && f.heads[0] === h.code ? 'selected' : ''}>${esc(lab({ bn: h.label_bn, en: h.label_en, mix: h.label_en }))}</option>`).join('')}</select></label>
    <label class="muted">${esc(TY('words'))}<input id="rh_bw" autocomplete="off" value="${esc((f.terms || []).join(', '))}"></label>
    <label class="muted">${esc(TY('person_kind'))}<select id="rh_bpk">${['', 'staff', 'supplier', 'customer'].map((k) => `<option value="${k}" ${((f.person && f.person.kind) || '') === k ? 'selected' : ''}>${k ? esc(TY('p_' + k)) : esc(TY('any'))}</option>`).join('')}</select></label>
    <input id="rh_bpn" autocomplete="off" value="${esc(f.person ? (f.person.label || f.person.query || '') : '')}" placeholder="${esc(TY('name_ph'))}" aria-label="${esc(TY('name_ph'))}">
    <div class="muted">${esc(TY('kinds'))}</div><div class="rh-kinds">${kinds.map((k) => `<label class="chip"><input type="checkbox" class="rh_bk" value="${k}" ${on.includes(k) ? 'checked' : ''}> ${esc(TY('k_' + k))}</label>`).join('')}</div>
    <label class="muted">${esc(TY('status'))}<select id="rh_bs">${[['posted', 'st_posted'], ['all', 'st_all'], ['draft', 'st_draft'], ['void', 'st_void'], ['reversed', 'st_reversed']].map(([v, t]) => `<option value="${v}" ${(f.status.length === 4 ? 'all' : f.status[0]) === v ? 'selected' : ''}>${esc(TY(t))}</option>`).join('')}</select></label>
    <label class="muted">${esc(TY('pay'))}<select id="rh_bpm"><option value="">${esc(TY('any'))}</option>${(AS.opts.pay_modes || []).map((m) => `<option value="${m}" ${f.pay_mode === m ? 'selected' : ''}>${esc(m)}</option>`).join('')}</select></label>
    ${(AS.opts.money_accounts || []).length ? `<label class="muted">${esc(TY('pay'))} #<select id="rh_bma"><option value="">${esc(TY('any'))}</option>${AS.opts.money_accounts.map((m) => `<option value="${m.id}" ${String(f.money_account_id) === String(m.id) ? 'selected' : ''}>${esc(lab({ bn: m.label_bn, en: m.label_en, mix: m.label_en }))}</option>`).join('')}</select></label>` : ''}
    ${(AS.opts.accounts || []).length ? `<label class="muted">${esc(TY('account'))}<select id="rh_bac"><option value="">${esc(TY('any'))}</option>${AS.opts.accounts.map((m) => `<option value="${m.id}" ${String(f.account_id) === String(m.id) ? 'selected' : ''}>${esc(m.code + ' ' + lab({ bn: m.label_bn, en: m.label_en, mix: m.label_en }))}</option>`).join('')}</select></label>` : ''}
    <button class="primary full" data-act="rh_b_run">${esc(TY('run'))}</button></div></details>`;
}
function builderDraw() { /* the builder lives inside #rh_out; it is drawn by builderHTML where needed */ }
async function readBuilder() {
  const f = AS.f || emptyF(), g = (id) => ($('#' + id) || {}).value;
  f.from = g('rh_bf') || f.from; f.to = g('rh_bt') || f.to; f.loc = g('rh_bl') === undefined ? f.loc : g('rh_bl');
  const h = g('rh_bh'); f.topic = ''; f.heads = [];
  if (h && h.startsWith('code:')) f.heads = [h.slice(5)]; else if (h) { const t = topicByKey(h); f.topic = h; f.heads = [...new Set((t.heads || []).concat(t.utility || []))]; }
  const words = (g('rh_bw') || '').split(',').map((x) => x.trim().toLowerCase()).filter((x) => x.length >= 2);
  f.terms = words.length ? words : (f.topic ? topicByKey(f.topic).en.concat(topicByKey(f.topic).bn).map((x) => x.trim()) : []);
  const pk = g('rh_bpk'), pn = (g('rh_bpn') || '').trim();
  if (pk && pn) { if (!f.person || f.person.query !== pn || f.person.kind !== pk) f.person = { kind: pk, query: pn, alts: [pn], id: null, label: null }; } else if (!pn) f.person = null;
  const ks = [...document.querySelectorAll('.rh_bk:checked')].map((x) => x.value); f.kinds = ks.length === defaultKinds.length && defaultKinds.every((k) => ks.includes(k)) ? [] : ks;
  const st = g('rh_bs'); f.status = st === 'all' ? ['posted', 'draft', 'void', 'reversed'] : [st || 'posted'];
  f.pay_mode = g('rh_bpm') || ''; f.money_account_id = g('rh_bma') || ''; f.account_id = g('rh_bac') || '';
  AS.f = f; return f;
}

// ---------- run + draw ----------
async function runSpend() {
  const f = AS.f; if (!f || !f.from) return;
  if (f.person && !f.person.id) { const lk = await lookupPerson(f); f.person.state = lk.state; chipsDraw(); if (!f.person.id) return setOut(`${AS.cands && AS.cands.length ? candsHTML() : `<div class="notice warn mk warn">${esc(TY('not_found'))}: ${esc(f.person.query)}</div>`}${builderHTML(true)}`); }
  setOut(R.stateHTML('loading'));
  const r = await R.rpc('rpt_hub_spend', { p_filters: apiFilters(f), p_limit: PAGE, p_offset: AS.off });
  if (r.error) return setOut(R.stateHTML('error', r.msg, 'rh_spend_retry') + builderHTML(true));
  AS.res = r.data; chipsDraw(); R.touch('tool:spend', { f: JSON.stringify(apiFilters(f)) });
  setOut(spendHTML(r.data) + builderHTML(false));
}
const bar = (v, max) => `<div class="rh-bar"><i style="width:${max > 0 ? Math.max(2, Math.round(Math.abs(v) / max * 100)) : 0}%"></i></div>`;
function spendHTML(d) {
  const f = d.filters || {}, rows = d.rows || [], mx = Math.max(0, ...((d.by_month || []).map((m) => Math.abs(m.amount))));
  const nm_ = (n) => (n || '').replace(/^utility_bill$/, 'utility_bill');
  const matched = d.matched || {}, hasFilter = (f.heads || []).length || (f.terms || []).length;
  const mfield = (k) => { const key = 'mf_' + String(k).replace(/[^a-z0-9]+/gi, '_'); return Y[key] ? lab(Y[key]) : k; };
  const chips = [f.from + ' → ' + f.to, f.loc == null ? T('all_places') : R.locName(f.loc), (f.kinds || []).length ? (f.kinds || []).map((k) => TY('k_' + k)).join(' + ') : null, (f.status || []).join('+')];
  const noteText = (n) => (Y['n_' + n] ? lab(Y['n_' + n]) : null);
  return `${R.stampHTML(d, chips)}
    ${R.maskHTML(d.masked && d.masked.filter((m) => !/^head:|^person:|^advance$|^salary$/.test(m)).map((m) => ({ area: ({ quick_expense: 'expense', expense_voucher: 'expense', purchase: 'purchase', supplier_payment: 'purchase', customer_refund: 'sales', utility_bill: 'cost', journal: 'accounts' })[m] || 'expense' })), [])}
    ${(d.masked || []).some((m) => /^head:|^advance$|^salary$|^person:staff$/.test(m)) ? `<div class="notice warn mk warn">${esc(TY('masked_pay'))}</div>` : ''}
    <div class="card stack"><div class="rh-tot" style="margin:0"><button disabled><small>${esc(TY('total'))}</small><b>${esc(money(d.total))}</b></button><button disabled><small>${esc(TY('txns'))}</small><b>${d.count}</b></button></div>
      ${hasFilter ? `<div class="muted">${esc(TY('matched'))}: ${esc(TY('m_head'))} ${matched.head || 0} · ${esc(TY('m_memo'))} ${matched.memo || 0} · ${esc(TY('m_both'))} ${matched.both || 0}</div>` : ''}
      ${d.person && d.person.allowed ? `<div class="muted">${esc(TY('linked'))} (${esc(d.person.label || '')}): ${esc(TY('l_direct'))} ${(d.linked || {}).direct || 0} · ${esc(TY('l_text'))} ${(d.linked || {}).text || 0}</div>` : ''}</div>
    ${d.unlinked && d.unlinked.count > 0 ? `<div class="notice warn mk warn"><b>${esc(TY('unlinked_h'))}:</b> ${d.unlinked.count} · ${esc(money(d.unlinked.amount))}<br>${esc(TY('unlinked_t'))}<br><b>${esc(TY('missing_field'))}:</b> ${(d.unlinked.missing_fields || []).map((x) => esc(mfield(x))).join('; ')}</div>` : ''}
    ${d.overlap && d.overlap.count > 0 ? `<div class="notice warn mk warn">${d.overlap.count} · ${esc(money(d.overlap.amount))} — ${esc(TY('overlap'))}</div>` : ''}
    ${d.no_source > 0 ? `<p class="muted">${d.no_source} — ${esc(TY('no_src'))}</p>` : ''}
    ${(d.notes || []).map(noteText).filter(Boolean).map((t) => `<p class="muted">${esc(t)}</p>`).join('')}
    ${(d.by_month || []).length ? `<div class="hsec">${esc(TY('by_month'))}</div><div class="card">${d.by_month.map((m) => `<div class="rh-mrow"><span>${esc(m.month)}</span>${bar(m.amount, mx)}<b>${esc(money(m.amount))}</b></div>`).join('')}</div>` : ''}
    ${(d.by_head || []).length > 1 ? `<div class="hsec">${esc(TY('by_head'))}</div><div class="card" style="padding:4px 12px">${d.by_head.slice(0, 8).map((h) => `<div class="row between" style="min-height:36px"><span>${esc(lab({ bn: h.label_bn || h.label_en || h.head, en: h.label_en || h.head, mix: h.label_en || h.head }))}</span><span><small class="muted">${h.n}</small> <b>${esc(money(h.amount))}</b></span></div>`).join('')}</div>` : ''}
    ${(d.by_kind || []).length > 1 ? `<div class="hsec">${esc(TY('by_kind'))}</div><div class="card" style="padding:4px 12px">${d.by_kind.map((h) => `<div class="row between" style="min-height:36px"><span>${esc(TY('k_' + h.kind))}</span><span><small class="muted">${h.n}</small> <b>${esc(money(h.amount))}</b></span></div>`).join('')}</div>` : ''}
    ${rows.length ? `<div class="hsec">${esc(TY('txns'))}<small>${d.count}</small></div><div class="card" style="padding:2px 12px">${rows.map(rowHTML).join('')}</div>` : `<p class="muted center pad">${esc(TY('none'))}</p>`}
    ${R.pagerHTML(d.count, PAGE, AS.off, 'rh_spend_page')}
    ${rows.length ? `<div class="row"><button class="full" data-act="rh_spend_csv">${esc(T('csv'))}</button></div>` : ''}${R.saveViewHTML('tool:spend')}`;
}
function rowHTML(x) {
  const void_ = x.status !== 'posted';
  const head = lab({ bn: x.head_bn || x.head_en || x.head, en: x.head_en || x.head, mix: x.head_en || x.head });
  const how = x.matched_by && x.matched_by !== 'filter' ? `<span class="chip info">${esc(TY('m_' + x.matched_by))}</span>` : '';
  const pl = x.person_link ? `<span class="chip ${x.person_link === 'direct' ? 'ok' : 'warn'}">${esc(x.person_link === 'direct' ? TY('l_direct') : TY('l_text'))}</span>` : '';
  return `<div class="rh-ev ${void_ ? 'void' : ''}"><div class="t">${esc(String(x.date).slice(5))}<br><small>${esc(String(x.date).slice(0, 4))}</small></div>
    <div class="b"><b>${esc(TY('k_' + x.kind))}</b> · ${esc(head)} ${how} ${pl}${x.status !== 'posted' ? ` <span class="chip ${R.stCls(x.status)}">${esc(R.stLabel(x.status))}</span>` : ''}${x.possible_duplicate ? ` <span class="chip warn">${esc(TY('overlap'))}</span>` : ''}
      <small>${esc(x.memo || '')}${x.loc != null ? ' · ' + esc(R.locName(x.loc)) : ''}${x.mode ? ' · ' + esc(x.mode) : ''} · ${esc(x.who || T('nr'))}</small></div>
    <div class="a out">${esc(money(x.amount))}</div>
    <div class="x">${x.ref_table ? `<button data-act="rh_trail" data-t="${esc(x.ref_table)}" data-i="${esc(x.ref_id)}">${esc(lab(L('রেকর্ড', 'Record', 'Record')))}</button>` : ''}${x.link ? `<button data-act="rh_screen" data-v="${esc(x.link)}">${esc(lab(L('পাতা খুলুন', 'Open screen', 'Open screen')))}</button>` : ''}</div></div>`;
}
async function spendCsv() {
  const f = AS.f; if (!f) return;
  await R.exportCsv('spend', Y.csv_h, async () => {
    const out = []; for (let off = 0; off < 20000; off += 500) {
      const r = await R.rpc('rpt_hub_spend', { p_filters: apiFilters(f), p_limit: 500, p_offset: off }); if (r.error) throw r.error;
      (r.data.rows || []).forEach((x) => out.push([x.date, x.kind, x.status, x.amount, x.head, x.head_en || '', x.memo || '', x.loc != null ? R.locName(x.loc) : '', x.mode || '', x.who || '', x.matched_by || '', x.person_link || '', x.ref_table || '', x.ref_id || '']));
      if (off + 500 >= r.data.count) break;
    }
    return out;
  }, apiFilters(f));
}

// ---------- actions ----------
Object.assign(H, {
  rh_retry: () => location.reload(),
  rh_ask_run: () => { const q = ($('#rh_aq') || {}).value || ''; if (!q.trim()) return; AS.off = 0; R.go('ask', { q: q.trim() }); },
  rh_ex: (a) => R.go('ask', { q: a.dataset.v }),
  rh_open_rep: (a) => { const r = AS.reg && AS.reg.reports.find((x) => x.id === a.dataset.v); if (r) R.openReport(r); },
  rh_chip: (a) => openEditor(a.dataset.s),
  rh_pick_person: (a) => { const x = (AS.cands || [])[Number(a.dataset.i)]; if (!x || !AS.f) return; AS.f.person = { kind: x.pkind, query: x.label, alts: [x.label], id: x.id, label: x.label, state: 'ok' }; AS.cands = null; closeSheet(); chipsDraw(); return runSpend(); },
  rh_ed_clear: (a) => { const s = a.dataset.s; if (s === 'person') AS.f.person = null; if (s === 'head') { AS.f.topic = ''; AS.f.heads = []; AS.f.terms = []; } closeSheet(); chipsDraw(); return AS.f.from ? runSpend() : null; },
  rh_ed_person: async () => {
    const q = (($('#rh_eq2') || {}).value || '').trim(), k = ($('#rh_ek') || {}).value || 'auto'; if (!q) return;
    AS.f.person = { kind: k, query: q, alts: [q], id: null, label: null }; const box = $('#rh_ecand'); if (box) box.innerHTML = TY('looking');
    const lk = await lookupPerson(AS.f); AS.f.person.state = lk.state;
    if (lk.state === 'ok') { closeSheet(); chipsDraw(); return runSpend(); }
    if (lk.state === 'many' && box) { box.innerHTML = AS.cands.map((x, i) => `<button class="rp-row" data-act="rh_pick_person" data-i="${i}"><span class="nm">${esc(x.label)}<small>${esc(TY('p_' + x.pkind))} · ${esc(x.sub || '')}</small></span><span class="cv">›</span></button>`).join(''); return; }
    if (box) box.innerHTML = `<p class="muted">${esc(TY('not_found'))}</p>`; chipsDraw();
  },
  rh_ed_head: () => {
    const v = ($('#rh_eh') || {}).value || '', words = (($('#rh_ew') || {}).value || '').split(',').map((x) => x.trim().toLowerCase()).filter((x) => x.length >= 2);
    const f = AS.f; f.topic = ''; f.heads = []; f.terms = words;
    if (v.startsWith('code:')) f.heads = [v.slice(5)]; else if (v) { const t = topicByKey(v); f.topic = v; f.heads = [...new Set((t.heads || []).concat(t.utility || []))]; if (!words.length) f.terms = t.en.concat(t.bn).map((x) => x.trim()); }
    closeSheet(); if (AS.parsed) AS.parsed.ambiguities = AS.parsed.ambiguities.filter((x) => x.slot !== 'head'); chipsDraw(); return f.from ? runSpend() : null;
  },
  rh_ed_place: () => { AS.f.loc = ($('#rh_el') || {}).value || ''; closeSheet(); if (AS.parsed) AS.parsed.ambiguities = AS.parsed.ambiguities.filter((x) => x.slot !== 'place'); chipsDraw(); return AS.f.from ? runSpend() : null; },
  rh_ed_pre: (a) => { const r = presetRange(a.dataset.v); setPeriod(r[0], r[1], r[2]); closeSheet(); chipsDraw(); AS.off = 0; return runSpend(); },
  rh_ed_period: () => {
    const txt = ($('#rh_ep') || {}).value || '', ctx = ctxFor();
    if (txt.trim()) { const ps = B.parse.periodFrom(B.parse.normalize(txt), ctx, AS.reg.parser); const p = ps[0]; if (p && p.from) { setPeriod(p.from, p.to, lab({ bn: p.label_bn, en: p.label_en, mix: p.label_en })); closeSheet(); chipsDraw(); AS.off = 0; return runSpend(); } return toast(TY('need_period')); }
    const a = ($('#rh_ef') || {}).value, b = ($('#rh_et') || {}).value; if (!a || !b || b < a) return toast(TY('need_period'));
    setPeriod(a, b, ''); closeSheet(); chipsDraw(); AS.off = 0; return runSpend();
  },
  rh_b_pre: (a) => { const r = presetRange(a.dataset.v); const f1 = $('#rh_bf'), t1 = $('#rh_bt'); if (f1) f1.value = r[0]; if (t1) t1.value = r[1]; if (AS.f) { AS.f.label.period = r[2]; } },
  rh_b_run: async () => { await readBuilder(); AS.off = 0; AS.q = ''; AS.parsed = AS.parsed && null; chipsDraw(); if (!AS.f.from || AS.f.to < AS.f.from) return toast(TY('need_period')); return runSpend(); },
  rh_spend_page: (a) => { AS.off = Number(a.dataset.o); return runSpend(); },
  rh_spend_retry: () => runSpend(),
  rh_spend_csv: () => spendCsv(),
});
document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target && e.target.id === 'rh_aq') { e.preventDefault(); H.rh_ask_run(); } });
R.views.ask = viewAsk;
R.views.spend = viewSpend;
R.ask = { AS, runQuestion, fromParse, apiFilters };
})();
