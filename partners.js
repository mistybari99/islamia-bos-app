/* Islamia BOS · Partners (#/partners) - OWNER ONLY. Partnership / investment / profit-sharing / franchise: parties, ventures, the DEED (clauses + the profit-sharing rule builder),
   trial calculation, settlements (draft -> approve -> pay), capital ledger, party statement (printable).
   Server: supabase/phase44.sql - partner_party_save, partner_venture_save, partner_agreement_save / _party_set / _activate / _amend / _close / _from_template, partner_rule_save / _validate,
   partner_rules_reorder, partner_calculate (trial, writes nothing), partner_settlement_save / _approve / _void / _pay, partner_capital_add / _void / _balances,
   partner_party_statement, partner_overview. Reads the tables partner_* directly (owner-only RLS). Nothing is deleted: rules are retired, rows voided, a live deed is amended. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, H, nm, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab;
const U = B.s2;
const { money, nnum, rid, LOCS } = U;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
const t3 = (bn, en, mix) => lab(L(bn, en, mix || bn));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const r2 = (n) => Math.round(num(n) * 100) / 100;
const mny = (n) => (n === null || n === undefined || n === '' ? '-' : money(n));

const ROLES = { owner: L('মালিক', 'Owner'), partner: L('অংশীদার', 'Partner'), investor: L('বিনিয়োগকারী', 'Investor'), franchisee: L('ফ্র্যাঞ্চাইজি', 'Franchisee'), manager: L('ম্যানেজার', 'Manager'), lender: L('ঋণদাতা', 'Lender') };
const MODELS = { own: L('নিজস্ব', 'Own'), franchise: L('ফ্র্যাঞ্চাইজ', 'Franchise'), funded: L('বিনিয়োগে চালিত', 'Funded'), partnership: L('অংশীদারি', 'Partnership'), loan: L('ঋণ', 'Loan'), custom: L('অন্য', 'Custom') };
const SCOPES = { location: L('একটি জায়গা', 'One place'), business: L('পুরো ব্যবসা', 'Whole business'), product_line: L('পণ্যের ধারা', 'Product line'), custom: L('অন্য', 'Custom') };
const STATUS = { draft: L('খসড়া', 'Draft'), active: L('চালু', 'Active'), amended: L('সংশোধিত (পুরনো)', 'Amended (old)'), closed: L('বন্ধ', 'Closed'), approved: L('অনুমোদিত', 'Approved'), paid: L('শোধ', 'Paid'), void: L('বাতিল', 'Void') };
const BASES = { gross_sales: L('মোট বিক্রি', 'Gross sales'), net_sales: L('ফেরত বাদে বিক্রি', 'Net sales'), gross_profit: L('মোট লাভ (বিক্রি - মালের খরচ)', 'Gross profit'), net_profit_before_fees: L('ফি বাদ দেওয়ার আগের নিট লাভ', 'Net profit before fees'),
  net_profit: L('নিট লাভ (ফি বাদে)', 'Net profit'), fixed_amount: L('নির্দিষ্ট অঙ্ক', 'Fixed amount'), manual: L('হাতে লেখা অঙ্ক', 'Typed amount') };
const BASE4 = ['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees'];
const KINDL = { base: L('কিসের লাভ ভাগ হবে', 'What is shared'), royalty: L('রয়্যালটি', 'Royalty'), management_fee: L('ম্যানেজমেন্ট ফি', 'Management fee'), expense_allow: L('বাড়তি খরচ ধরা', 'Allow extra costs'),
  expense_disallow: L('খরচ ফেরত যোগ', 'Add back costs'), loss_carry_forward: L('আগের ক্ষতি টেনে নেওয়া', 'Carry losses forward'), priority_return: L('আগে নির্দিষ্ট রিটার্ন', 'Priority return'), payback: L('পুঁজি ফেরত', 'Payback'),
  split: L('ভাগ (শতাংশ)', 'Split'), tiered_split: L('ধাপে ধাপে ভাগ', 'Tiered split'), minimum_guarantee: L('নিম্নতম গ্যারান্টি', 'Minimum guarantee'), cap: L('সর্বোচ্চ সীমা', 'Cap'), floor: L('নিম্নতম সীমা', 'Floor'), rounding: L('গোল করা', 'Rounding') };
const CKIND = { contribution: L('পুঁজি দিলেন', 'Contribution'), return_of_capital: L('পুঁজি ফেরত', 'Return of capital'), loan_in: L('ঋণ নিলাম', 'Loan received'), loan_repayment: L('ঋণ শোধ', 'Loan repayment'), owner_drawing: L('মালিকের উত্তোলন', 'Owner drawing') };
const LKIND = { share: L('লাভের ভাগ', 'Share'), royalty: L('রয়্যালটি', 'Royalty'), fee: L('ফি', 'Fee'), return: L('রিটার্ন', 'Return'), payback: L('পুঁজি ফেরত', 'Payback'), guarantee: L('গ্যারান্টি', 'Guarantee') };
const MODES = { cash: L('নগদ', 'Cash'), bank: L('ব্যাংক', 'Bank'), mobile: L('মোবাইল', 'Mobile'), in_kind: L('মালপত্র', 'In kind') };
const lb = (o, k) => (o[k] ? lab(o[k]) : k);
const X = {
  title: L('অংশীদারি ও বিনিয়োগ', 'Partners & investment', 'অংশীদারি ও Investment'),
  tabs: { overview: L('সারসংক্ষেপ', 'Overview'), parties: L('পক্ষ (মানুষ/কোম্পানি)', 'Parties'), ventures: L('ব্যবসা/ডিল', 'Ventures'), deeds: L('চুক্তি (দলিল)', 'Deeds'), calc: L('পরীক্ষামূলক হিসাব', 'Trial calculation'),
    settle: L('হিসাব-নিকাশ (সেটলমেন্ট)', 'Settlements'), capital: L('পুঁজির খাতা', 'Capital ledger'), stmt: L('পক্ষের বিবরণী', 'Party statement') },
  save: L('সংরক্ষণ', 'Save'), add: L('যোগ করুন', 'Add'), edit: L('বদলান', 'Edit'), none: L('কিছু নেই', 'Nothing yet'), name: L('নাম', 'Name'), saved: L('সংরক্ষিত', 'Saved'), why: L('কারণ লিখুন', 'Write the reason'),
  example: L('উদাহরণ - সংখ্যা বদলান', 'EXAMPLE - change the numbers'), sec_owner: L('শুধু মালিক দেখেন', 'Owner only'),
};
const ERR = {
  'not allowed': L('শুধু মালিক এটা করতে পারেন', 'Only the owner can do this'), module_off: L('এই মডিউল বন্ধ (সুইচবোর্ডে চালু করুন)', 'This module is switched off (turn it on in the Switchboard)'),
  name_required: L('নাম লিখুন', 'A name is needed'), split_not_100: L('ভাগের যোগফল ঠিক ১০০% হতে হবে', 'The shares must add up to exactly 100%'), slab_order: L('ধাপগুলো ছোট থেকে বড় হতে হবে, শেষটা ফাঁকা (বাকি সব)', 'Slabs must go up, and only the last may be open-ended'),
  bad_config: L('এই ধাপের তথ্য ঠিক নয়', 'This step is not filled in correctly'), period_overlap: L('এই সময়ের মধ্যে আগেই হিসাব হয়ে গেছে', 'This period overlaps an earlier settlement'),
  base_estimated: L('লাভের ভিত্তিতে অনুমানের কস্ট আছে (সেটিং: আটকানো) - নিজে ভিত্তি অঙ্ক লিখুন', 'The profit base contains an estimated cost (setting: refuse) - type a manual base', 'Profit base-এ অনুমানের cost আছে (setting: refuse) - নিজে base লিখুন'),
  calc_incomplete: L('হিসাব অসম্পূর্ণ - হাতে ভিত্তি অঙ্ক লিখুন', 'The calculation is incomplete - type a manual base'), outside_deed_dates: L('সময়টা চুক্তির তারিখের বাইরে', 'The period is outside the deed dates'),
  bad_date: L('তারিখ ঠিক নয়', 'The date is not valid'), bad_range: L('তারিখের সীমা ঠিক নয়', 'The date range is not valid'), bad_amount: L('অঙ্ক ঠিক নয়', 'The amount is not valid'),
  exceeds_capital: L('ফেরত দেওয়া অঙ্ক পুঁজির বেশি', 'More than the capital held'), overpay: L('পাওনার চেয়ে বেশি দেওয়া যায় না', 'Cannot pay more than is due'), not_approved: L('আগে অনুমোদন করুন', 'Approve it first'),
  has_payments: L('টাকা দেওয়া হয়ে গেছে - বাতিল করা যাবে না', 'Payments exist - cannot void'), cannot_void: L('এখন বাতিল করা যাবে না', 'Cannot void now'),
  agreement_immutable: L('চালু চুক্তি বদলানো যায় না - সংশোধন (amend) করুন', 'A live deed cannot be edited - make an amendment'), no_parties: L('অন্তত একজন পক্ষ যোগ করুন', 'Add at least one party'),
  no_rules: L('অন্তত একটি ধাপ যোগ করুন', 'Add at least one rule step'), base_step_first: L('প্রথম ধাপ হবে "কিসের লাভ ভাগ হবে" (একটিই)', 'The first step must be the base (exactly one)'),
  party_unresolved: L('একটি ধাপে পক্ষ বা ভূমিকা মেলেনি', 'A step names a party or role that is not in this deed'), example_numbers_not_confirmed: L('উদাহরণের সংখ্যাগুলো আপনি নিশ্চিত করেননি', 'The example numbers are not confirmed'),
  dates_required: L('কার্যকরের তারিখ দিন', 'Set the start date'), period_already_settled: L('এই তারিখের আগের সময়ের হিসাব হয়ে গেছে', 'That start date falls inside a period already settled'),
  draft_exists: L('একটি সংশোধনী খসড়া আগেই আছে', 'An amendment draft already exists'), not_active: L('চুক্তি চালু নেই', 'The deed is not active'), not_draft: L('এটা খসড়া নয়', 'This is not a draft'),
  reason_required: L('কারণ লিখুন', 'Write the reason'), party_not_in_deed: L('এই পক্ষ এই চুক্তিতে নেই', 'This party is not in the deed'), bad_manual: L('হাতে লেখা অঙ্ক ঠিক নয়', 'A typed figure is not valid'),
  base_twice: L('"কিসের লাভ" ধাপ একটির বেশি', 'More than one base step'), bad_clauses: L('ধারা ঠিক নয় বা বেশি বড়', 'A clause is not valid or too long'), bad_order: L('ক্রম ঠিক নয়', 'The order is not valid'),
  location_not_found: L('জায়গা বাছুন', 'Choose a place'), agreements_open: L('চালু চুক্তি আছে - আগে বন্ধ করুন', 'An active deed exists - close it first'), 'duplicate key': L('এটা আগেই আছে', 'This already exists'),
};
const eText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) + (k === 'party_unresolved' && m.includes(':') ? ' (' + m.split(':').slice(1).join(':').trim() + ')' : '') : m || 'error'; };
const D = { rule: { step: null, kind: 'split' }, tab: 'overview', parties: [], ventures: [], deeds: [], aps: [], rules: [], caps: [], sets: [], lines: [], pays: [], tpl: [], ov: null, deed: null, venture: '', calc: null, calcArgs: null, setf: '', capd: '', stmt: null, photo: null, doc: null };

// ---------------- data ----------------
async function loadAll() {
  const g = async (tb, ord) => { const r = await sb.from(tb).select('*').order(ord || 'id', { ascending: true }).limit(2000); if (r.error) throw r.error; return r.data || []; };
  const [pa, ve, de, ap, ru, ca, se, li, py, tp, ov] = await Promise.all([g('partner_parties'), g('partner_ventures'), g('partner_agreements'), g('agreement_parties'), g('partner_rules', 'step_no'), g('partner_capital'),
    g('partner_settlements'), g('partner_settlement_lines'), g('partner_settlement_payments'), g('partner_templates', 'code'), sb.rpc('partner_overview')]);
  Object.assign(D, { parties: pa, ventures: ve, deeds: de, aps: ap, rules: ru, caps: ca, sets: se, lines: li, pays: py, tpl: tp, ov: ov && !ov.error ? ov.data : null });
}
const byId = (arr, id) => arr.find((x) => String(x.id) === String(id));
const pname = (id) => { const p = byId(D.parties, id); return p ? p.name : '#' + id; };
const vname = (id) => { const v = byId(D.ventures, id); return v ? (v.name_bn && S.lang !== 'en' ? v.name_bn : (v.name_en || v.name_bn)) : '#' + id; };
const deedOf = (id) => byId(D.deeds, id);
const deedLabel = (d) => `${vname(d.venture_id)} · ${d.title} v${d.version}`;
const deedParties = (id) => D.aps.filter((x) => String(x.agreement_id) === String(id) && x.active);
const deedRules = (id) => D.rules.filter((x) => String(x.agreement_id) === String(id)).sort((a, b) => a.step_no - b.step_no);
const chip = (st) => `<span class="chip ${st === 'active' || st === 'paid' ? 'ok' : st === 'void' || st === 'closed' ? 'bad' : 'warn'}">${esc(lb(STATUS, st))}</span>`;
const opt = (v, l, sel) => `<option value="${esc(v)}" ${String(sel) === String(v) ? 'selected' : ''}>${esc(l)}</option>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" value="${esc(v === null || v === undefined ? '' : v)}" autocomplete="off" ${extra || ''}>`;
const refV = (ref) => (ref && ref.role ? 'r:' + ref.role : ref && ref.party_id ? 'p:' + ref.party_id : '');
const refOf = (v) => (!v ? null : v.startsWith('r:') ? { role: v.slice(2) } : { party_id: Number(v.slice(2)) });
const refName = (ref) => (ref && ref.role ? lb(ROLES, ref.role) : ref && ref.party_id ? pname(ref.party_id) : '?');
function partyOpts(deedId, sel) {
  const aps = deedParties(deedId), roles = Array.from(new Set(aps.map((x) => x.role)));
  return '<option value="">-</option>' + aps.map((x) => opt('p:' + x.party_id, `${pname(x.party_id)} (${lb(ROLES, x.role)})`, sel)).join('') + roles.map((r) => opt('r:' + r, t3('ভূমিকা: ', 'Role: ') + lb(ROLES, r), sel)).join('');
}

// ---------------- the rule catalog: fields + the plain sentence ----------------
const baseSel = (id, v, withNone) => `<select id="${id}">${withNone ? opt('', '-', v) : ''}${BASE4.map((b) => opt(b, lb(BASES, b), v)).join('')}</select>`;
const perSel = (id, v) => `<select id="${id}">${opt('period', t3('প্রতি হিসাবের সময়ে', 'per settlement period'), v)}${opt('month', t3('প্রতি মাসে', 'per month'), v)}</select>`;
const ctxf = (c, k) => (c && c[k] !== undefined && c[k] !== null ? c[k] : '');
function sharesHTML(deedId, id, shares) {
  const rows = (shares && shares.length ? shares : [{}, {}]).map((s) => shareRow(deedId, s)).join('');
  return `<div class="stack" id="${id}" data-deed="${esc(deedId)}">${rows}<div class="row between"><button type="button" class="mini" data-act="pt_addshare" data-v="${id}">+ ${esc(lab(X.add))}</button><b class="pt-sum"></b></div></div>`;
}
function shareRow(deedId, s) {
  return `<div class="row pt-share"><select class="sh-p" style="flex:2">${partyOpts(deedId, refV(s))}</select><input class="sh-pc" style="flex:1;min-width:0" inputmode="decimal" placeholder="%" value="${esc(ctxf(s, 'percent'))}" autocomplete="off"></div>`;
}
function readShares(root) { return $$('.pt-share', root).map((r) => ({ ref: refOf($('.sh-p', r).value), percent: nnum($('.sh-pc', r).value) })).filter((x) => x.ref || x.percent > 0).map((x) => Object.assign({}, x.ref || {}, { percent: x.percent })); }
function itemsHTML(id, items) {
  const rows = (items && items.length ? items : [{}]).map((i) => itemRow(i)).join('');
  return `<div class="stack" id="${id}">${rows}<button type="button" class="mini" data-act="pt_additem" data-v="${id}">+ ${esc(lab(X.add))}</button></div>`;
}
function itemRow(i) { return `<div class="row pt-item"><input class="it-n" style="flex:2;min-width:0" placeholder="${esc(lab(X.name))}" value="${esc(ctxf(i, 'name'))}" autocomplete="off"><input class="it-a" style="flex:1;min-width:0" inputmode="decimal" placeholder="৳" value="${esc(ctxf(i, 'amount'))}" autocomplete="off"></div>`; }
function readItems(root) { return $$('.pt-item', root).map((r) => ({ name: $('.it-n', r).value.trim(), amount: nnum($('.it-a', r).value) })).filter((x) => x.name || x.amount > 0); }
function slabsHTML(deedId, slabs) {
  const rows = (slabs && slabs.length ? slabs : [{ upto: '' }, { upto: '' }]).map((s) => slabRow(deedId, s)).join('');
  return `<div class="stack" id="pt_slabs" data-deed="${esc(deedId)}">${rows}<button type="button" class="mini" data-act="pt_addslab">+ ${esc(t3('ধাপ যোগ', 'Add slab'))}</button></div>`;
}
function slabRow(deedId, s) {
  return `<div class="card stack pt-slab"><div><label>${esc(t3('এই ধাপে লাভ কতটাকা পর্যন্ত (শেষ ধাপে ফাঁকা = বাকি সব)', 'Profit up to (leave empty on the last slab = everything above)'))}</label><input class="sl-up" inputmode="decimal" value="${esc(ctxf(s, 'upto'))}" autocomplete="off"></div>${sharesHTML(deedId, 'sh' + Math.random().toString(36).slice(2, 7), s.shares)}</div>`;
}
const CAT = {
  base: { f: (d, c) => fld('pt_f_base', t3('কিসের লাভ ভাগ হবে', 'What is shared'), `<select id="pt_f_base">${['net_profit_before_fees', 'gross_profit', 'net_sales', 'gross_sales', 'net_profit', 'fixed_amount', 'manual'].map((b) => opt(b, lb(BASES, b), c.base)).join('')}</select>`)
      + fld('pt_f_amount', t3('নির্দিষ্ট অঙ্ক (শুধু "নির্দিষ্ট অঙ্ক" হলে)', 'Amount (only for "fixed amount")'), inp('pt_f_amount', c.amount, 'inputmode="decimal"')),
    r: () => { const o = { base: $('#pt_f_base').value }; if (o.base === 'fixed_amount') o.amount = nnum($('#pt_f_amount').value); return o; },
    s: (c) => t3(`${lb(BASES, c.base)} থেকে শুরু${c.base === 'fixed_amount' ? ' (' + mny(c.amount) + ')' : ''}`, `Start from ${lb(BASES, c.base).toLowerCase()}${c.base === 'fixed_amount' ? ' (' + mny(c.amount) + ')' : ''}`) },
  royalty: { f: (d, c) => fld('pt_f_party', t3('কে পাবেন', 'Who receives'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`) + fld('pt_f_pct', t3('শতাংশ', 'Percent'), inp('pt_f_pct', c.percent, 'inputmode="decimal"')) + fld('pt_f_rbase', t3('কিসের উপর', 'Of what'), baseSel('pt_f_rbase', c.base || 'net_sales')),
    r: () => Object.assign(refOf($('#pt_f_party').value) || {}, { percent: nnum($('#pt_f_pct').value), base: $('#pt_f_rbase').value }),
    s: (c) => t3(`${refName(c)} পান ${c.percent}% ${lb(BASES, c.base || 'net_sales')}-এর উপর (লাভ থেকে বাদ)`, `${refName(c)} gets ${c.percent}% of ${lb(BASES, c.base || 'net_sales').toLowerCase()} (taken off the profit first)`) },
  management_fee: { f: (d, c) => fld('pt_f_party', t3('কে পাবেন', 'Who receives'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`)
      + fld('pt_f_pct', t3('লাভের শতাংশ (অথবা নিচের নির্দিষ্ট অঙ্ক)', 'Percent of the profit (or the fixed amount below)'), inp('pt_f_pct', c.percent, 'inputmode="decimal"'))
      + fld('pt_f_fixed', t3('নির্দিষ্ট অঙ্ক', 'Fixed amount'), inp('pt_f_fixed', c.fixed, 'inputmode="decimal"')) + fld('pt_f_per', t3('নির্দিষ্ট অঙ্ক কখন', 'Fixed amount how often'), perSel('pt_f_per', c.per || 'month')),
    r: () => { const o = refOf($('#pt_f_party').value) || {}; const fx = nnum($('#pt_f_fixed').value); if (fx > 0) { o.fixed = fx; o.per = $('#pt_f_per').value; } else o.percent = nnum($('#pt_f_pct').value); return o; },
    s: (c) => (c.fixed !== undefined && c.fixed !== null ? t3(`${refName(c)} পান ${mny(c.fixed)} ${c.per === 'month' ? 'প্রতি মাসে' : 'প্রতি হিসাবে'} ফি`, `${refName(c)} gets a fee of ${mny(c.fixed)} ${c.per === 'month' ? 'a month' : 'per period'}`)
      : t3(`${refName(c)} পান লাভের ${c.percent}% ফি`, `${refName(c)} gets ${c.percent}% of the profit as a fee`)) },
  expense_allow: { f: (d, c) => fld('pt_f_items', t3('বাড়তি খরচ (নাম ও অঙ্ক)', 'Extra costs (name and amount)'), itemsHTML('pt_f_items', c.items)), r: () => ({ items: readItems($('#pt_f_items')) }),
    s: (c) => t3(`বাড়তি খরচ ${mny(sumItems(c))} লাভ থেকে বাদ`, `Extra costs of ${mny(sumItems(c))} are deducted from the profit`) },
  expense_disallow: { f: (d, c) => fld('pt_f_items', t3('যে খরচ ফেরত যোগ হবে (নাম ও অঙ্ক)', 'Costs to add back (name and amount)'), itemsHTML('pt_f_items', c.items)), r: () => ({ items: readItems($('#pt_f_items')) }),
    s: (c) => t3(`${mny(sumItems(c))} খরচ লাভে ফেরত যোগ`, `${mny(sumItems(c))} of costs are added back to the profit`) },
  loss_carry_forward: { f: () => `<p class="muted">${esc(t3('আগের মাসের ক্ষতি এই মাসের লাভ থেকে আগে মেটানো হবে। কিছু লিখতে হবে না।', 'Earlier losses are made up from this month\'s profit before anything is shared. Nothing to fill in.'))}</p>`, r: () => ({}),
    s: () => t3('আগের ক্ষতি মেটানোর পরেই লাভ ভাগ', 'Earlier losses are made up before any sharing') },
  priority_return: { f: (d, c) => fld('pt_f_party', t3('কে পাবেন', 'Who receives'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`)
      + fld('pt_f_ppy', t3('পুঁজির উপর বছরে %', 'Percent a year on the capital'), inp('pt_f_ppy', c.percent_per_year, 'inputmode="decimal"')) + fld('pt_f_fm', t3('অথবা প্রতি মাসে নির্দিষ্ট অঙ্ক', 'Or a fixed amount a month'), inp('pt_f_fm', c.fixed_monthly, 'inputmode="decimal"'))
      + fld('pt_f_cap', t3('মোট সর্বোচ্চ (ফাঁকা = সীমা নেই)', 'Total ceiling (empty = none)'), inp('pt_f_cap', c.cap, 'inputmode="decimal"'))
      + `<label class="row"><input type="checkbox" id="pt_f_cu" ${c.catch_up ? 'checked' : ''}> ${esc(t3('কম পড়লে পরের মাসে পুষিয়ে দেওয়া', 'Make up a shortfall in later periods (catch-up)'))}</label>`,
    r: () => { const o = refOf($('#pt_f_party').value) || {}; const fm = nnum($('#pt_f_fm').value); if (fm > 0) o.fixed_monthly = fm; else o.percent_per_year = nnum($('#pt_f_ppy').value); const cp = nnum($('#pt_f_cap').value); if (cp >= 0) o.cap = cp; o.catch_up = $('#pt_f_cu').checked; return o; },
    s: (c) => t3(`${refName(c)} আগে পান ${c.percent_per_year !== undefined && c.percent_per_year !== null ? 'পুঁজির উপর বছরে ' + c.percent_per_year + '%' : 'প্রতি মাসে ' + mny(c.fixed_monthly)}${c.cap ? ', মোট সর্বোচ্চ ' + mny(c.cap) : ''}${c.catch_up ? ', কম পড়লে পরে পুষিয়ে' : ''}`,
      `${refName(c)} first gets ${c.percent_per_year !== undefined && c.percent_per_year !== null ? c.percent_per_year + '% a year on the capital' : mny(c.fixed_monthly) + ' a month'}${c.cap ? ', up to ' + mny(c.cap) + ' in all' : ''}${c.catch_up ? ', a shortfall is caught up later' : ''}`) },
  payback: { f: (d, c) => fld('pt_f_party', t3('কে পাবেন', 'Who receives'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`) + fld('pt_f_pct', t3('পুঁজি ফেরত না আসা পর্যন্ত লাভের কত %', 'Percent of the profit until paid back'), inp('pt_f_pct', c.percent === undefined ? 100 : c.percent, 'inputmode="decimal"'))
      + fld('pt_f_tg', t3('ফেরতের লক্ষ্য (ফাঁকা = পুঁজির খাতার পুঁজি)', 'Target (empty = the capital in the ledger)'), inp('pt_f_tg', c.target, 'inputmode="decimal"')) + fld('pt_f_then', t3('ফেরত শেষ হলে তারপর লাভের %', 'Then this percent of the profit afterwards'), inp('pt_f_then', c.then_percent, 'inputmode="decimal"')),
    r: () => { const o = Object.assign(refOf($('#pt_f_party').value) || {}, { percent: nnum($('#pt_f_pct').value) }); const tg = nnum($('#pt_f_tg').value), th = nnum($('#pt_f_then').value); if (tg > 0) o.target = tg; if (th >= 0) o.then_percent = th; return o; },
    s: (c) => t3(`${refName(c)} পান লাভের ${c.percent === undefined ? 100 : c.percent}% যতক্ষণ না ${c.target ? mny(c.target) : 'পুঁজি'} ফেরত আসে${c.then_percent !== undefined && c.then_percent !== null ? ', তারপর ' + c.then_percent + '%' : ''}`,
      `${refName(c)} gets ${c.percent === undefined ? 100 : c.percent}% of the profit until ${c.target ? mny(c.target) : 'the capital'} is paid back${c.then_percent !== undefined && c.then_percent !== null ? ', then ' + c.then_percent + '%' : ''}`) },
  split: { f: (d, c) => fld('pt_f_shares', t3('বাকি লাভ কে কত % পাবেন (যোগফল ১০০)', 'Who gets what percent of the rest (must total 100)'), sharesHTML(d, 'pt_f_shares', c.shares)), r: () => ({ shares: readShares($('#pt_f_shares')) }),
    s: (c) => t3('বাকি লাভ ভাগ: ', 'The rest is shared: ') + (c.shares || []).map((s) => `${refName(s)} ${s.percent}%`).join(', ') },
  tiered_split: { f: (d, c) => fld('pt_slabs', t3('ধাপ ও প্রতি ধাপের ভাগ', 'Slabs and the split in each'), slabsHTML(d, c.slabs)),
    r: () => ({ slabs: $$('.pt-slab', $('#pt_slabs')).map((s) => { const up = nnum($('.sl-up', s).value); const o = { shares: readShares($('.stack', s)) }; o.upto = up > 0 ? up : null; return o; }) }),
    s: (c) => (c.slabs || []).map((s, i, a) => `${i === 0 ? t3('প্রথম ', 'First ') : i === a.length - 1 && !s.upto ? t3('তার উপরে ', 'Above ') : t3('পরের ', 'Next ')}${s.upto ? mny(s.upto) : ''}: ${(s.shares || []).map((x) => refName(x) + ' ' + x.percent + '%').join(', ')}`).join(' | ') },
  minimum_guarantee: { f: (d, c) => fld('pt_f_party', t3('কার জন্য', 'For whom'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`) + fld('pt_f_amt', t3('অন্তত কত', 'At least'), inp('pt_f_amt', c.amount, 'inputmode="decimal"'))
      + fld('pt_f_per', t3('কখন', 'How often'), perSel('pt_f_per', c.per || 'month')) + fld('pt_f_fb', t3('ঘাটতি কোথা থেকে', 'The top-up comes from'), `<select id="pt_f_fb">${opt('pool', t3('লাভের ভাগ থেকে', 'the profit pool'), c.funded_by || 'pool')}${opt('outside', t3('বাইরে থেকে (অন্য পক্ষ দেবে)', 'outside (another party pays)'), c.funded_by)}</select>`),
    r: () => Object.assign(refOf($('#pt_f_party').value) || {}, { amount: nnum($('#pt_f_amt').value), per: $('#pt_f_per').value, funded_by: $('#pt_f_fb').value }),
    s: (c) => t3(`${refName(c)} অন্তত ${mny(c.amount)} ${c.per === 'month' ? 'প্রতি মাসে' : 'প্রতি হিসাবে'} পাবেন (${c.funded_by === 'outside' ? 'বাইরে থেকে' : 'লাভের ভাগ থেকে'})`,
      `${refName(c)} is guaranteed at least ${mny(c.amount)} ${c.per === 'month' ? 'a month' : 'per period'} (${c.funded_by === 'outside' ? 'paid from outside' : 'from the profit pool'})`) },
  cap: null, floor: null,
  rounding: { f: (d, c) => fld('pt_f_to', t3('কতয় গোল করা', 'Round to'), `<select id="pt_f_to">${[0.01, 1, 5, 10, 50, 100, 1000].map((v) => opt(v, String(v), c.to || 1)).join('')}</select>`)
      + fld('pt_f_mode', t3('কীভাবে', 'How'), `<select id="pt_f_mode">${opt('nearest', t3('কাছের', 'Nearest'), c.mode)}${opt('down', t3('নিচে', 'Down'), c.mode)}${opt('up', t3('উপরে', 'Up'), c.mode)}</select>`),
    r: () => ({ to: Number($('#pt_f_to').value), mode: $('#pt_f_mode').value }), s: (c) => t3(`অঙ্ক ${c.to}-এ গোল (${c.mode || 'nearest'}); অবশিষ্ট বড় ভাগের পক্ষে`, `Amounts are rounded to ${c.to} (${c.mode || 'nearest'}); the odd rest goes to the largest share`) },
};
function capFloor(word) {
  return { f: (d, c) => fld('pt_f_tg', t3('কিসের উপর', 'Applies to'), `<select id="pt_f_tg">${opt('pool', t3('মোট ভাগযোগ্য লাভ', 'the whole profit pool'), c.target || 'pool')}${opt('party', t3('একজন পক্ষ', 'one party'), c.target)}</select>`)
      + fld('pt_f_party', t3('পক্ষ (শুধু "একজন পক্ষ" হলে)', 'Party (only for "one party")'), `<select id="pt_f_party">${partyOpts(d, refV(c))}</select>`) + fld('pt_f_amt', t3('অঙ্ক', 'Amount'), inp('pt_f_amt', c.amount, 'inputmode="decimal"')) + fld('pt_f_per', t3('কখন (পক্ষের জন্য)', 'How often (for a party)'), perSel('pt_f_per', c.per || 'period')),
    r: () => { const o = { target: $('#pt_f_tg').value, amount: nnum($('#pt_f_amt').value), per: $('#pt_f_per').value }; if (o.target === 'party') Object.assign(o, refOf($('#pt_f_party').value) || {}); return o; },
    s: (c) => (c.target === 'party' ? t3(`${refName(c)}-এর ভাগ ${word === 'cap' ? 'সর্বোচ্চ' : 'অন্তত'} ${mny(c.amount)}`, `${refName(c)}'s total is ${word === 'cap' ? 'limited to' : 'at least'} ${mny(c.amount)}`)
      : t3(`ভাগযোগ্য লাভ ${word === 'cap' ? 'সর্বোচ্চ' : 'অন্তত'} ${mny(c.amount)}`, `The profit pool is ${word === 'cap' ? 'limited to' : 'lifted to at least'} ${mny(c.amount)}`)) };
}
CAT.cap = capFloor('cap'); CAT.floor = capFloor('floor');
function sumItems(c) { return (c.items || []).reduce((s, i) => s + num(i.amount), 0); }
const sentence = (kind, cfg) => { try { return CAT[kind].s(cfg || {}); } catch (e) { return lb(KINDL, kind); } };

// ---------------- pages ----------------
function tabsBar() {
  return `<div class="pt-noprint"><label for="pt_tab" class="muted">${esc(t3('কোন অংশ', 'Section'))}</label><select id="pt_tab">${Object.keys(X.tabs).map((k) => opt(k, lab(X.tabs[k]), D.tab)).join('')}</select></div>`;
}
function ovHTML() {
  const ov = D.ov || { ventures: [], owed_total: 0, capital_total: 0 };
  const v = (ov.ventures || []).map((x) => `<div class="card stack"><div class="row between"><b>${esc(S.lang === 'en' ? (x.name_en || x.name_bn) : x.name_bn)}</b>${chip(x.status)}</div>
    <div class="muted">${esc(lb(MODELS, x.model))} · ${esc(lb(SCOPES, x.scope))} · ${esc(String(x.agreements))} ${esc(t3('চালু চুক্তি', 'live deeds'))}${x.drafts ? ' · ' + esc(String(x.drafts)) + ' ' + esc(t3('খসড়া', 'draft')) : ''}</div>
    <div class="row between"><span>${esc(t3('পুঁজি', 'Capital'))}</span><b>${money(x.capital)}</b></div>
    <div class="row between"><span>${esc(t3('পরের হিসাব শুরু', 'Next settlement from'))}</span><b>${esc(x.next_due || '-')}</b></div>
    <div class="row between"><span>${esc(t3('এখনো দেওয়া বাকি', 'Still to be paid'))}</span><b>${money(x.owed)}</b></div>
    <div class="row"><button class="mini" data-act="pt_ventdeeds" data-v="${x.id}">${esc(t3('চুক্তিগুলো', 'Deeds'))}</button></div></div>`).join('');
  return `<div class="s2-sum"><div class="stat"><div class="muted">${esc(t3('মোট পুঁজি', 'Total capital'))}</div><b>${money(ov.capital_total)}</b></div><div class="stat"><div class="muted">${esc(t3('মোট পাওনা (দেওয়া বাকি)', 'Owed (unpaid)'))}</div><b>${money(ov.owed_total)}</b></div></div>
    ${v || `<p class="muted">${esc(lab(X.none))}</p>`}<button class="full primary" data-act="pt_newvent">+ ${esc(t3('নতুন ব্যবসা/ডিল', 'New venture'))}</button>`;
}
function partiesHTML() {
  return D.parties.map((p) => `<div class="card"><div class="row between"><b>${esc(p.name)}</b><span class="chip ${p.active ? 'ok' : 'bad'}">${esc(p.active ? t3('সক্রিয়', 'active') : t3('বন্ধ', 'inactive'))}</span></div>
    <div class="muted">${esc(p.kind === 'company' ? t3('কোম্পানি', 'Company') : t3('ব্যক্তি', 'Individual'))} ${p.mobile ? '· ' + esc(p.mobile) : ''} ${p.email ? '· ' + esc(p.email) : ''} ${p.nid_or_reg ? '· ' + esc(p.nid_or_reg) : ''}</div>
    ${p.photo_path ? `<img class="pt-th" data-path="${esc(p.photo_path)}" alt="" width="64" height="64">` : ''}
    <div class="row"><button class="mini" data-act="pt_editparty" data-v="${p.id}">${esc(lab(X.edit))}</button><button class="mini" data-act="pt_stmt" data-v="${p.id}">${esc(t3('বিবরণী', 'Statement'))}</button></div></div>`).join('')
    + `<button class="full primary" data-act="pt_newparty">+ ${esc(t3('নতুন পক্ষ', 'New party'))}</button>`;
}
function partySheet(id) {
  const p = id ? byId(D.parties, id) : {}; D.photo = null;
  openSheet(`<h2>${esc(id ? p.name : t3('নতুন পক্ষ', 'New party'))}</h2><div class="stack" id="pt_ps">
    ${fld('pp_name', lab(X.name), inp('pp_name', p.name))}
    ${fld('pp_kind', t3('ধরন', 'Kind'), `<select id="pp_kind">${opt('individual', t3('ব্যক্তি', 'Individual'), p.kind)}${opt('company', t3('কোম্পানি', 'Company'), p.kind)}</select>`)}
    ${fld('pp_mobile', t3('মোবাইল', 'Mobile'), inp('pp_mobile', p.mobile, 'inputmode="tel"'))}${fld('pp_email', 'Email', inp('pp_email', p.email))}
    ${fld('pp_nid', t3('NID / রেজি. নম্বর', 'NID / registration no.'), inp('pp_nid', p.nid_or_reg))}${fld('pp_addr', t3('ঠিকানা', 'Address'), inp('pp_addr', p.address))}
    ${fld('pp_notes', t3('নোট', 'Notes'), inp('pp_notes', p.notes))}
    <div class="s2-ph"><label class="phadd">${esc(t3('ছবি / কাগজ', 'Photo / paper'))}<input id="pp_photo" type="file" accept="image/*" hidden></label><span id="pp_phn" class="muted">${p.photo_path ? '✓' : ''}</span></div>
    <label class="row"><input type="checkbox" id="pp_active" ${p.active === false ? '' : 'checked'}> ${esc(t3('সক্রিয়', 'Active'))}</label>
    <button class="full primary" data-act="pt_saveparty" data-v="${id || ''}">${esc(lab(X.save))}</button></div>`);
}
function ventSheet(id) {
  const v = id ? byId(D.ventures, id) : { scope: 'business', model: 'partnership', status: 'draft' }; const locs = LOCS();
  openSheet(`<h2>${esc(id ? vname(id) : t3('নতুন ব্যবসা/ডিল', 'New venture'))}</h2><div class="stack">
    ${fld('pv_bn', t3('নাম (বাংলা)', 'Name (Bangla)'), inp('pv_bn', v.name_bn))}${fld('pv_en', t3('নাম (ইংরেজি)', 'Name (English)'), inp('pv_en', v.name_en))}
    ${fld('pv_scope', t3('কিসের উপর', 'Scope'), `<select id="pv_scope">${Object.keys(SCOPES).map((k) => opt(k, lb(SCOPES, k), v.scope)).join('')}</select>`)}
    ${fld('pv_loc', t3('জায়গা (শুধু "একটি জায়গা" হলে)', 'Place (only for "one place")'), `<select id="pv_loc"><option value="">-</option>${locs.map((l) => opt(l.id, nm(l), v.location_id)).join('')}</select>`)}
    ${fld('pv_model', t3('মডেল', 'Model'), `<select id="pv_model">${Object.keys(MODELS).map((k) => opt(k, lb(MODELS, k), v.model)).join('')}</select>`)}
    ${fld('pv_start', t3('শুরু', 'Start'), inp('pv_start', v.start_date, 'type="date"'))}${fld('pv_end', t3('শেষ (ফাঁকা = চলছে)', 'End (empty = ongoing)'), inp('pv_end', v.end_date, 'type="date"'))}
    ${fld('pv_status', t3('অবস্থা', 'Status'), `<select id="pv_status">${['draft', 'active', 'closed'].map((k) => opt(k, lb(STATUS, k), v.status)).join('')}</select>`)}
    ${fld('pv_notes', t3('নোট', 'Notes'), inp('pv_notes', v.notes))}
    <button class="full primary" data-act="pt_savevent" data-v="${id || ''}">${esc(lab(X.save))}</button></div>`);
}
function venturesHTML() {
  return D.ventures.map((v) => `<div class="card"><div class="row between"><b>${esc(vname(v.id))}</b>${chip(v.status)}</div><div class="muted">${esc(lb(MODELS, v.model))} · ${esc(lb(SCOPES, v.scope))} ${v.start_date ? '· ' + esc(v.start_date) : ''}</div>
    <div class="row"><button class="mini" data-act="pt_editvent" data-v="${v.id}">${esc(lab(X.edit))}</button><button class="mini" data-act="pt_ventdeeds" data-v="${v.id}">${esc(t3('চুক্তিগুলো', 'Deeds'))}</button></div></div>`).join('')
    + `<button class="full primary" data-act="pt_newvent">+ ${esc(t3('নতুন ব্যবসা/ডিল', 'New venture'))}</button>`;
}
function deedsHTML() {
  const list = D.deeds.filter((d) => !D.venture || String(d.venture_id) === String(D.venture)).sort((a, b) => b.id - a.id);
  return `${fld('pd_vf', t3('ব্যবসা/ডিল', 'Venture'), `<select id="pd_vf"><option value="">${esc(t3('সব', 'All'))}</option>${D.ventures.map((v) => opt(v.id, vname(v.id), D.venture)).join('')}</select>`)}
    ${list.map((d) => `<div class="card"><div class="row between"><b>${esc(d.title)} <span class="muted">v${d.version}</span></b>${chip(d.status)}</div>
      <div class="muted">${esc(vname(d.venture_id))} · ${esc(d.effective_from || '?')} → ${esc(d.effective_to || '…')} ${d.is_example ? ' · <span class="chip warn">' + esc(lab(X.example)) + '</span>' : ''}</div>
      <div class="row"><button class="mini" data-act="pt_opendeed" data-v="${d.id}">${esc(t3('খুলুন', 'Open'))}</button></div></div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`}
    <button class="full primary" data-act="pt_newdeed">+ ${esc(t3('নতুন চুক্তি', 'New deed'))}</button>`;
}
function newDeedSheet() {
  if (!D.ventures.length) return toast(t3('আগে একটি ব্যবসা/ডিল বানান', 'Create a venture first'));
  openSheet(`<h2>${esc(t3('নতুন চুক্তি', 'New deed'))}</h2><div class="stack">
    ${fld('nd_v', t3('ব্যবসা/ডিল', 'Venture'), `<select id="nd_v">${D.ventures.map((v) => opt(v.id, vname(v.id), D.venture)).join('')}</select>`)}
    ${fld('nd_title', t3('চুক্তির নাম', 'Deed title'), inp('nd_title', ''))}
    ${fld('nd_tpl', t3('উদাহরণ থেকে শুরু (বদলে নেওয়া যায়)', 'Start from an example (editable)'), `<select id="nd_tpl"><option value="">${esc(t3('ফাঁকা থেকে', 'Blank'))}</option>${D.tpl.map((x) => opt(x.code, (S.lang === 'en' ? x.name_en : x.name_bn), '')).join('')}</select>`)}
    <p class="muted" id="nd_hint"></p><button class="full primary" data-act="pt_makedeed">${esc(lab(X.save))}</button></div>`);
}
// ----- the deed editor
function deedHTML() {
  const d = deedOf(D.deed); if (!d) return `<p class="muted">${esc(lab(X.none))}</p>`;
  const draft = d.status === 'draft', aps = deedParties(d.id), rules = deedRules(d.id), cl = d.clauses || [];
  const clauses = cl.map((c, i) => `<div class="card stack pt-cl" data-i="${i}"><div class="row between"><b>${i + 1}.</b><span>${draft ? `<button class="mini" data-act="pt_clmv" data-v="${i}" data-d="-1" aria-label="up">↑</button><button class="mini" data-act="pt_clmv" data-v="${i}" data-d="1" aria-label="down">↓</button><button class="mini" data-act="pt_cldel" data-v="${i}" aria-label="remove">✕</button>` : ''}</span></div>
    <input class="cl-tb" placeholder="${esc(t3('শিরোনাম (বাংলা)', 'Title (Bangla)'))}" value="${esc(c.title_bn || '')}" ${draft ? '' : 'readonly'}><input class="cl-te" placeholder="${esc(t3('শিরোনাম (ইংরেজি)', 'Title (English)'))}" value="${esc(c.title_en || '')}" ${draft ? '' : 'readonly'}>
    <textarea class="cl-xb" rows="3" placeholder="${esc(t3('ধারা (বাংলা)', 'Clause (Bangla)'))}" ${draft ? '' : 'readonly'}>${esc(c.text_bn || '')}</textarea><textarea class="cl-xe" rows="3" placeholder="${esc(t3('ধারা (ইংরেজি)', 'Clause (English)'))}" ${draft ? '' : 'readonly'}>${esc(c.text_en || '')}</textarea></div>`).join('');
  const parts = aps.map((x) => `<div class="row between card"><span><b>${esc(pname(x.party_id))}</b> · ${esc(lb(ROLES, x.role))}${x.share_percent !== null && x.share_percent !== undefined ? ' · ' + esc(String(x.share_percent)) + '%' : ''}</span>${draft ? `<button class="mini" data-act="pt_rmparty" data-p="${x.party_id}" data-r="${x.role}">✕</button>` : ''}</div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`;
  const rl = rules.map((r, i) => `<div class="card stack ${r.active ? '' : 'muted'}"><div class="row between"><b>${r.step_no}. ${esc(r.name)}</b><span class="chip info">${esc(lb(KINDL, r.kind))}</span></div>
    <div class="pt-sent">${esc(sentence(r.kind, r.config))}</div>${r.active ? '' : `<div class="muted">${esc(t3('বন্ধ রাখা', 'Switched off'))}</div>`}
    ${draft ? `<div class="row"><button class="mini" data-act="pt_ruledit" data-v="${r.step_no}">${esc(lab(X.edit))}</button><button class="mini" data-act="pt_rulemv" data-v="${r.step_no}" data-d="-1" aria-label="up">↑</button><button class="mini" data-act="pt_rulemv" data-v="${r.step_no}" data-d="1" aria-label="down">↓</button><button class="mini" data-act="pt_ruleoff" data-v="${r.step_no}">${esc(r.active ? t3('বন্ধ', 'Retire') : t3('চালু', 'Enable'))}</button></div>` : ''}</div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`;
  const acts = [draft ? `<button class="full primary" data-act="pt_activate">${esc(t3('চালু করুন (আর বদলানো যাবে না)', 'Activate (then it cannot be edited)'))}</button>` : '',
    d.status === 'active' ? `<button class="full" data-act="pt_amend">${esc(t3('সংশোধনী (নতুন সংস্করণ)', 'Amend (new revision)'))}</button><button class="full" data-act="pt_closedeed">${esc(t3('চুক্তি বন্ধ', 'Close the deed'))}</button>` : '',
    `<button class="full" data-act="pt_trial" data-v="${d.id}">${esc(t3('পরীক্ষামূলক হিসাব', 'Trial calculation'))}</button>`].join('');
  const chain = D.deeds.filter((x) => x.supersedes_id === d.id || d.supersedes_id === x.id);
  return `<div class="card stack"><div class="row between"><b>${esc(d.title)} <span class="muted">v${d.version}</span></b>${chip(d.status)}</div>
    <div class="muted">${esc(vname(d.venture_id))}${d.is_example ? ' · <span class="chip warn">' + esc(lab(X.example)) + '</span>' : ''}</div>
    ${chain.map((x) => `<div class="row between"><span class="muted">${x.id === d.supersedes_id ? t3('আগের সংস্করণ', 'Previous revision') : t3('পরের সংস্করণ', 'Next revision')}: v${x.version} (${esc(lb(STATUS, x.status))})</span><button class="mini" data-act="pt_opendeed" data-v="${x.id}">${esc(t3('খুলুন', 'Open'))}</button></div>`).join('')}
    ${fld('de_title', t3('চুক্তির নাম', 'Title'), inp('de_title', d.title, draft ? '' : 'readonly'))}
    <div class="row">${fld('de_from', t3('কার্যকর শুরু', 'Effective from'), inp('de_from', d.effective_from, 'type="date" ' + (draft ? '' : 'readonly')))}${fld('de_to', t3('শেষ', 'To'), inp('de_to', d.effective_to, 'type="date" ' + (draft ? '' : 'readonly')))}</div>
    <div class="s2-ph"><label class="phadd">${esc(t3('সই করা কাগজের ছবি', 'Signed paper (photo)'))}<input id="de_doc" type="file" accept="image/*" hidden></label>${d.signed_doc_path ? `<img class="pt-th" data-path="${esc(d.signed_doc_path)}" alt="" width="64" height="64">` : ''}</div>
    ${draft ? `<button class="full" data-act="pt_savedeed">${esc(lab(X.save))}</button>` : ''}</div>
    <h3>${esc(t3('পক্ষ ও ভূমিকা', 'Parties and roles'))}</h3>${parts}${draft ? `<button class="full" data-act="pt_addparty">+ ${esc(t3('পক্ষ যোগ', 'Add a party'))}</button>` : ''}
    <h3>${esc(t3('ধারা (দলিলের লেখা)', 'Clauses'))}</h3><div id="pt_clauses">${clauses || `<p class="muted">${esc(lab(X.none))}</p>`}</div>
    ${draft ? `<div class="row"><button class="full" data-act="pt_addcl">+ ${esc(t3('ধারা যোগ', 'Add a clause'))}</button><button class="full" data-act="pt_savecl">${esc(t3('ধারাগুলো সংরক্ষণ', 'Save clauses'))}</button></div>` : ''}
    <h3>${esc(t3('লাভ ভাগের নিয়ম (ধাপে ধাপে)', 'Profit-sharing rules (in order)'))}</h3>${rl}${draft ? `<button class="full primary" data-act="pt_rulenew">+ ${esc(t3('ধাপ যোগ', 'Add a step'))}</button>` : ''}
    <div class="stack" style="margin-top:12px">${acts}</div>`;
}
function readClauses() { return $$('.pt-cl').map((c) => ({ title_bn: $('.cl-tb', c).value, title_en: $('.cl-te', c).value, text_bn: $('.cl-xb', c).value, text_en: $('.cl-xe', c).value })); }
async function rpc(fn, args) { const r = await sb.rpc(fn, args); if (r.error) { toast(eText(r.error)); return null; } return r.data === null || r.data === undefined ? {} : r.data; }
async function refresh() { await loadAll(); paint(); }
async function saveDraftClauses(d, cl) {
  return rpc('partner_agreement_save', { p_id: d.id, p_venture: d.venture_id, p_title: $('#de_title') ? $('#de_title').value.trim() || d.title : d.title, p_from: $('#de_from') ? $('#de_from').value || null : d.effective_from,
    p_to: $('#de_to') ? $('#de_to').value || null : d.effective_to, p_clauses: cl, p_signed_doc: D.doc || null });
}
// rule editor
function ruleSheet(stepNo) {
  const d = deedOf(D.deed), r = stepNo ? deedRules(d.id).find((x) => x.step_no === stepNo) : null; D.rule = { step: stepNo, kind: r ? r.kind : 'split' };
  openSheet(`<h2>${esc(r ? r.name : t3('নতুন ধাপ', 'New step'))}</h2><div class="stack" id="pt_rule">
    ${fld('pr_kind', t3('ধাপের ধরন', 'Kind of step'), `<select id="pr_kind" ${r ? 'disabled' : ''}>${Object.keys(KINDL).map((k) => opt(k, lb(KINDL, k), D.rule.kind)).join('')}</select>`)}
    ${fld('pr_name', t3('ধাপের নাম', 'Name of the step'), inp('pr_name', r ? r.name : ''))}
    <div class="stack" id="pr_fields">${CAT[D.rule.kind].f(d.id, r ? r.config : {})}</div>
    <div class="card pt-sent" id="pr_sum"></div>
    <button class="full primary" data-act="pt_rulesave">${esc(lab(X.save))}</button></div>`);
  sumRule(); sums();
}
function ruleCfg() { return CAT[$('#pr_kind').value].r(); }
function sumRule() { const el = $('#pr_sum'); if (!el) return; try { el.textContent = sentence($('#pr_kind').value, ruleCfg()); } catch (e) { el.textContent = ''; } }
function sums() { $$('.pt-sum').forEach((el) => { const root = el.closest('.stack'); const s = readShares(root).reduce((a, x) => a + num(x.percent), 0); el.textContent = `Σ ${r2(s)}%`; el.className = 'pt-sum ' + (Math.abs(s - 100) < 0.0001 ? 'ok' : 'warn'); }); }

// ----- trial calculation
function calcFormHTML() {
  const deeds = D.deeds.filter((d) => ['draft', 'active'].includes(d.status));
  const cur = D.calcArgs || {}; const t = new Date(today() + 'T00:00:00Z'); t.setUTCDate(1); const to = new Date(t.getTime() - 86400000), from = new Date(Date.UTC(to.getUTCFullYear(), to.getUTCMonth(), 1));
  const f = cur.from || from.toISOString().slice(0, 10), tt = cur.to || to.toISOString().slice(0, 10);
  return `<div class="card stack">${fld('pc_deed', t3('চুক্তি', 'Deed'), `<select id="pc_deed">${deeds.map((d) => opt(d.id, deedLabel(d) + ' · ' + lb(STATUS, d.status), cur.deed || D.deed)).join('')}</select>`)}
    <div class="row">${fld('pc_from', t3('থেকে', 'From'), inp('pc_from', f, 'type="date"'))}${fld('pc_to', t3('পর্যন্ত', 'To'), inp('pc_to', tt, 'type="date"'))}</div>
    <details data-ctl="off"><summary>${esc(t3('হাতে অঙ্ক লিখুন (বই থেকে না নিয়ে)', 'Type figures by hand (instead of the books)'))}</summary><div class="stack">
      ${['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'manual', 'carry_in'].map((k) => fld('pc_m_' + k, k === 'manual' ? lb(BASES, 'manual') : k === 'carry_in' ? t3('আগের ক্ষতি (টানা)', 'Loss carried in') : lb(BASES, k), inp('pc_m_' + k, (cur.manual || {})[k], 'inputmode="decimal"'))).join('')}</div></details>
    <button class="full primary" data-act="pt_calc">${esc(t3('হিসাব করুন (কিছু লেখা হবে না)', 'Calculate (writes nothing)'))}</button></div><div id="pc_out"></div>`;
}
function manualArgs() { const m = {}; ['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'manual', 'carry_in'].forEach((k) => { const v = nnum(($('#pc_m_' + k) || {}).value); if (Number.isFinite(v)) m[k] = v; }); return Object.keys(m).length ? m : null; }
function waterfall(c, saveBtn) {
  const w = (c.warnings || []).map((x) => `<div class="chip ${x.code === 'retained' || x.code === 'no_profit' ? 'warn' : 'bad'}" style="display:block;margin:4px 0;white-space:normal">${esc(wmsg(x))}</div>`).join('');
  const b = c.bases || {}; const src = c.sources || {};
  const bases = ['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees'].map((k) => `<div class="row between"><span>${esc(lb(BASES, k))}</span><b>${b[k] === null || b[k] === undefined ? esc(t3('পাওয়া যায়নি', 'not available')) : money(b[k])} <small class="muted">${esc(src[k] === 'manual' ? t3('হাতে', 'typed') : src[k] === 'books' ? t3('বই থেকে', 'books') : '')}</small></b></div>`).join('');
  const steps = (c.steps || []).map((s) => `<div class="card stack ${s.skipped ? 'muted' : ''}"><div class="row between"><b>${s.step_no}. ${esc(s.name)}</b><span class="chip info">${esc(lb(KINDL, s.kind))}</span></div>
    <div class="row between"><span class="muted">${esc(t3('আগে', 'Before'))} ${s.pool_before === null || s.pool_before === undefined ? '-' : money(s.pool_before)}</span><b>${s.skipped ? esc(t3('বাদ (ভিত্তি নেই)', 'skipped (no base)')) : (num(s.amount) >= 0 ? '' : '− ') + money(Math.abs(num(s.amount)))}</b><span class="muted">${esc(t3('পরে', 'After'))} ${s.pool_after === null || s.pool_after === undefined ? '-' : money(s.pool_after)}</span></div></div>`).join('');
  const pt = (c.party_totals || []).map((p) => `<div class="row between"><span>${esc(p.name)}</span><b>${money(p.amount)}</b></div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`;
  return `<h3>${esc(t3('সূত্র', 'Bases'))}</h3><div class="card stack">${bases}</div>${w}<h3>${esc(t3('ধাপে ধাপে', 'Step by step'))}</h3>${steps}
    <h3>${esc(t3('কে কত পাবেন', 'Who gets what'))}</h3><div class="card stack">${pt}<hr><div class="row between"><b>${esc(t3('মোট ভাগ হলো', 'Total shared'))}</b><b>${money(c.total_distributable)}</b></div>
    ${num(c.outside_total) ? `<div class="row between"><span>${esc(t3('বাইরে থেকে (ভাগের বাইরে)', 'Funded outside'))}</span><b>${money(c.outside_total)}</b></div>` : ''}
    ${num(c.retained) ? `<div class="row between"><span>${esc(t3('কাউকে দেওয়া হয়নি', 'Not given to anybody'))}</span><b>${money(c.retained)}</b></div>` : ''}
    ${num(c.carry_out) ? `<div class="row between"><span>${esc(t3('পরের মাসে ক্ষতি টানা', 'Loss carried on'))}</span><b>${money(c.carry_out)}</b></div>` : ''}</div>${saveBtn || ''}`;
}
const WMSG = { uncosted_sales: L('কিছু মালের কেনা দাম নেই, তাই মোট লাভ অনুমান করা হয়নি - হাতে লিখুন', 'Some items have no cost price, so gross profit is not guessed - type it'), manual_only: L('এই ডিলের নিজস্ব বই নেই - হাতে অঙ্ক লিখুন', 'This venture has no books of its own - type the figures'),
  base_unavailable: L('এই সূত্র বই থেকে পাওয়া যায়নি - হাতে লিখুন', 'This base is not available from the books - type it'), no_book_rows: L('এই সময়ে কোনো বিক্রি/খরচ লেখা নেই', 'No sales, expenses or salary were recorded in this period'),
  no_profit: L('এই ধাপে ভাগ করার মতো লাভ নেই', 'There is no profit to share at this step'), retained: L('লাভের কিছু অংশ নিয়মে কাউকে দেওয়া হয়নি', 'Part of the profit was not given to anybody by the rules'),
  guarantee_short: L('গ্যারান্টির পুরোটা মেটানোর মতো লাভ ছিল না', 'The pool could not pay the whole guarantee'), return_short: L('অগ্রাধিকার রিটার্নের পুরোটা মেটানোর মতো লাভ ছিল না', 'The profit was not enough for the whole priority return'),
  floor_topup: L('নিম্নতম সীমা ছোঁয়াতে বাইরে থেকে টাকা ধরা হয়েছে', 'The floor was met with money from outside the books') };
const wmsg = (x) => (WMSG[x.code] ? lab(WMSG[x.code]) : x.msg || x.code) + (x.detail !== undefined && x.detail !== null && !['uncosted_sales'].includes(x.code) ? ' (' + money(x.detail) + ')' : '');
// ----- settlements
function settleHTML() {
  const list = D.sets.filter((s) => !D.setf || String(s.agreement_id) === String(D.setf)).sort((a, b) => b.id - a.id);
  return `${fld('ps_f', t3('চুক্তি', 'Deed'), `<select id="ps_f"><option value="">${esc(t3('সব', 'All'))}</option>${D.deeds.map((d) => opt(d.id, deedLabel(d), D.setf)).join('')}</select>`)}
    ${list.map((s) => `<div class="card stack"><div class="row between"><b>${esc(s.period_from)} → ${esc(s.period_to)}</b>${chip(s.status)}</div><div class="muted">${esc(deedLabel(deedOf(s.agreement_id) || { venture_id: 0, title: '#' + s.agreement_id, version: '' }))}</div>
      <div class="row between"><span>${esc(t3('মোট ভাগ', 'Shared'))}</span><b>${money(s.total_distributable)}</b></div><div class="row"><button class="mini" data-act="pt_openset" data-v="${s.id}">${esc(t3('খুলুন', 'Open'))}</button></div></div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`}
    <p class="muted">${esc(t3('নতুন হিসাব: "পরীক্ষামূলক হিসাব" থেকে সংরক্ষণ করুন।', 'To make a new one, use "Trial calculation" and save it as a draft.'))}</p>`;
}
function setSheet(id) {
  const s = byId(D.sets, id); if (!s) return; const ls = D.lines.filter((l) => l.settlement_id === s.id);
  const lines = ls.map((l) => `<div class="card stack"><div class="row between"><b>${esc(pname(l.party_id))}</b><span>${esc(lb(LKIND, l.kind))}${l.funded_outside ? ' · ' + esc(t3('বাইরে', 'outside')) : ''}</span></div>
    <div class="row between"><span>${money(l.amount)}</span><span class="muted">${esc(t3('দেওয়া', 'paid'))} ${money(l.paid_amount)}</span></div>
    ${s.status === 'approved' && num(l.amount) - num(l.paid_amount) > 0.004 ? `<button class="mini" data-act="pt_payline" data-v="${l.id}">${esc(t3('টাকা দিলাম', 'Record a payment'))}</button>` : ''}</div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`;
  openSheet(`<h2>${esc(s.period_from)} → ${esc(s.period_to)} ${chip(s.status)}</h2>${s.note ? `<p class="muted">${esc(s.note)}</p>` : ''}
    <div class="stack">${lines}${s.status === 'draft' ? `<button class="full primary" data-act="pt_approve" data-v="${s.id}">${esc(t3('অনুমোদন করুন (আর বদলানো যাবে না)', 'Approve (then it cannot be changed)'))}</button>` : ''}
    ${['draft', 'approved'].includes(s.status) ? `<button class="full" data-act="pt_voidset" data-v="${s.id}">${esc(t3('বাতিল', 'Void'))}</button>` : ''}
    <details data-ctl="off"><summary>${esc(t3('সংরক্ষিত পূর্ণ হিসাব', 'The saved calculation'))}</summary>${waterfall(s.calc || {}, '')}</details></div>`);
}
// ----- capital
function capitalHTML() {
  const deeds = D.deeds.filter((d) => ['active', 'closed', 'amended'].includes(d.status)), cur = D.capd || (deeds[0] && deeds[0].id) || '';
  const d = deedOf(cur); const rows = D.caps.filter((c) => String(c.agreement_id) === String(cur)).sort((a, b) => (b.cap_date > a.cap_date ? 1 : -1) || b.id - a.id);
  return `${fld('pk_d', t3('চুক্তি', 'Deed'), `<select id="pk_d">${deeds.map((x) => opt(x.id, deedLabel(x), cur)).join('')}</select>`)}
    <div id="pk_bal" class="stack"></div>
    ${d && d.status === 'active' ? `<button class="full primary" data-act="pt_capnew">+ ${esc(t3('পুঁজি / ঋণ / উত্তোলন লিখুন', 'Record capital / loan / drawing'))}</button>` : ''}
    <h3>${esc(t3('লেনদেন', 'Entries'))}</h3>${rows.map((c) => `<div class="card ${c.status === 'void' ? 'muted' : ''}"><div class="row between"><b>${esc(pname(c.party_id))} · ${esc(lb(CKIND, c.kind))}</b><b>${money(c.amount)}</b></div>
      <div class="muted">${esc(c.cap_date)} · ${esc(lb(MODES, c.mode))}${c.description ? ' · ' + esc(c.description) : ''}${c.ref ? ' · ' + esc(c.ref) : ''}${c.status === 'void' ? ' · ' + esc(t3('বাতিল', 'void')) : ''}</div>
      ${c.status === 'posted' ? `<button class="mini" data-act="pt_capvoid" data-v="${c.id}">${esc(t3('বাতিল', 'Void'))}</button>` : ''}</div>`).join('') || `<p class="muted">${esc(lab(X.none))}</p>`}`;
}
async function capBalances() {
  const el = $('#pk_bal'); const cur = ($('#pk_d') || {}).value; if (!el || !cur) return;
  const r = await sb.rpc('partner_capital_balances', { p_agr: Number(cur) }); if (r.error) return;
  el.innerHTML = (r.data || []).map((x) => `<div class="card stack"><b>${esc(x.name)}</b><div class="row between"><span>${esc(t3('পুঁজি এখন', 'Capital now'))}</span><b>${money(x.balance)}</b></div>
    <div class="muted">${esc(t3('দিয়েছেন', 'in'))} ${money(num(x.contributed) + num(x.loan_in))} · ${esc(t3('ফেরত', 'back'))} ${money(num(x.returned) + num(x.repaid))} · ${esc(t3('উত্তোলন', 'drawings'))} ${money(x.drawings)}</div>
    <div class="row between"><span>${esc(t3('ফেরত পাওনা (লাভ থেকে)', 'Still to pay back (from profit)'))}</span><b>${money(x.outstanding_payback)}</b></div></div>`).join('');
}
// ----- statement
function stmtHTML() {
  const t = new Date(today() + 'T00:00:00Z'), f = new Date(Date.UTC(t.getUTCFullYear(), 0, 1)); const cur = Object.assign({ party: D.parties[0] && D.parties[0].id, from: f.toISOString().slice(0, 10), to: today() }, D.stmtArgs || {});
  return `<div class="card stack pt-noprint">${fld('pst_p', t3('পক্ষ', 'Party'), `<select id="pst_p">${D.parties.map((p) => opt(p.id, p.name, cur.party)).join('')}</select>`)}
    <div class="row">${fld('pst_f', t3('থেকে', 'From'), inp('pst_f', cur.from, 'type="date"'))}${fld('pst_t', t3('পর্যন্ত', 'To'), inp('pst_t', cur.to, 'type="date"'))}</div>
    <div class="row"><button class="full primary" data-act="pt_stmtgo">${esc(t3('বিবরণী দেখান', 'Show statement'))}</button><button class="full" data-act="pt_print">${esc(t3('ছাপুন', 'Print'))}</button></div></div><div id="pst_out" class="pt-print"></div>`;
}
function stmtBody(s) {
  const p = s.party || {};
  const sec = (title, rows) => `<h3>${esc(title)}</h3>${rows || `<p class="muted">${esc(lab(X.none))}</p>`}`;
  return `<div class="card stack"><b>${esc(p.name)}</b><div class="muted">${esc([p.mobile, p.email, p.nid_or_reg, p.address].filter(Boolean).join(' · '))}</div><div class="muted">${esc(s.from)} → ${esc(s.to)}</div></div>
    ${sec(t3('পুঁজি', 'Capital'), `<div class="row between"><span>${esc(t3('শুরুতে', 'Opening'))}</span><b>${money(s.capital_opening)}</b></div>${(s.capital_movements || []).map((m) => `<div class="row between"><span>${esc(m.date)} ${esc(lb(CKIND, m.kind))}</span><b>${money(m.amount)}</b></div>`).join('')}<div class="row between"><span>${esc(t3('শেষে', 'Closing'))}</span><b>${money(s.capital_closing)}</b></div>${num(s.drawings) ? `<div class="row between"><span>${esc(t3('উত্তোলন', 'Drawings'))}</span><b>${money(s.drawings)}</b></div>` : ''}`)}
    ${sec(t3('পাওনা (অনুমোদিত হিসাব)', 'Shares due (approved)'), (s.shares_due || []).map((d) => `<div class="row between"><span>${esc(d.period_from)} → ${esc(d.period_to)} · ${esc(lb(LKIND, d.kind))}</span><b>${money(d.amount)}</b></div>`).join(''))}
    ${sec(t3('পাওয়া গেছে', 'Paid'), (s.payments || []).map((d) => `<div class="row between"><span>${esc(d.date)} · ${esc(lb(MODES, d.mode))}${d.ref ? ' · ' + esc(d.ref) : ''}</span><b>${money(d.amount)}</b></div>`).join(''))}
    <div class="card stack"><div class="row between"><span>${esc(t3('এই সময়ের পাওনা', 'Due in the period'))}</span><b>${money(s.due_in_period)}</b></div><div class="row between"><span>${esc(t3('এই সময়ে পেয়েছেন', 'Paid in the period'))}</span><b>${money(s.paid_in_period)}</b></div>
    <div class="row between"><b>${esc(t3('এখনো পাবেন (সব মিলিয়ে)', 'Still owed (all time)'))}</b><b>${money(s.balance_owed)}</b></div></div>`;
}

// ---------------- paint ----------------
function paint() {
  const el = $('#pt_body'); if (!el) return;
  const T = D.tab;
  el.innerHTML = tabsBar() + '<div id="pt_main" class="stack">' + (T === 'overview' ? ovHTML() : T === 'parties' ? partiesHTML() : T === 'ventures' ? venturesHTML() : T === 'deeds' ? (D.deed ? `<button class="mini pt-noprint" data-act="pt_backdeeds">← ${esc(t3('সব চুক্তি', 'All deeds'))}</button>` + deedHTML() : deedsHTML())
    : T === 'calc' ? calcFormHTML() : T === 'settle' ? settleHTML() : T === 'capital' ? capitalHTML() : stmtHTML()) + '</div>';
  $$('.pt-th', el).forEach((i) => U.thumb(i, i.dataset.path));
  if (T === 'capital') capBalances();
  if (T === 'calc' && D.calc) { const o = $('#pc_out'); if (o) o.innerHTML = waterfall(D.calc, D.calc.status === 'ok' && D.calcArgs && deedOf(D.calcArgs.deed) && deedOf(D.calcArgs.deed).status === 'active' ? `<div class="stack"><input id="pc_note" placeholder="${esc(t3('নোট', 'Note'))}" autocomplete="off"><button class="full primary" data-act="pt_savecalc">${esc(t3('খসড়া হিসাব হিসেবে সংরক্ষণ', 'Save as a draft settlement'))}</button></div>` : ''); }
  if (T === 'stmt' && D.stmt) { const o = $('#pst_out'); if (o) o.innerHTML = stmtBody(D.stmt); }
}
const css = document.createElement('style'); css.id = 'ptcss';
css.textContent = `#pt_body select,#pt_body input,#pt_body textarea,.sheet select,.sheet input,.sheet textarea{max-width:100%;box-sizing:border-box}.pt-sent{font-size:.9rem;overflow-wrap:anywhere}.pt-th{object-fit:cover;border-radius:8px;border:1px solid var(--hair)}
.pt-sum.ok{color:var(--ok)}.pt-sum.warn{color:var(--bad)}.pt-share{gap:6px;flex-wrap:nowrap}.pt-item{gap:6px;flex-wrap:nowrap}#pt_body .card,.sheet .card{overflow-wrap:anywhere}
@media print{.pt-noprint,header.top,.bnav,nav,#sheet,.sheet-bg{display:none!important}body{background:#fff!important}}`;
document.head.appendChild(css);

// ---------------- handlers ----------------
const photoPick = async (file, setter, hintSel) => { try { const loc = ((LOCS()[0]) || {}).id; const path = await U.uploadPhoto(file, ['STOCK', '04-1', '04-2'], loc); setter(path); const h = $(hintSel); if (h) h.textContent = '✓'; } catch (e) { fail(e); } };
document.addEventListener('change', (e) => {
  const id = e.target.id;
  if (id === 'pt_tab') { D.tab = e.target.value; D.deed = null; D.calc = null; paint(); }
  else if (id === 'pd_vf') { D.venture = e.target.value; paint(); }
  else if (id === 'ps_f') { D.setf = e.target.value; paint(); }
  else if (id === 'pk_d') { D.capd = e.target.value; paint(); }
  else if (id === 'pp_photo' && e.target.files[0]) photoPick(e.target.files[0], (p) => { D.photo = p; }, '#pp_phn');
  else if (id === 'de_doc' && e.target.files[0]) photoPick(e.target.files[0], async (p) => { D.doc = p; const d = deedOf(D.deed); const r = await rpc('partner_agreement_save', { p_id: d.id, p_venture: d.venture_id, p_title: d.title, p_from: d.effective_from, p_to: d.effective_to, p_clauses: d.clauses || [], p_signed_doc: p }); if (r) { toast(lab(X.saved)); await refresh(); } }, '#none');
  else if (id === 'pr_kind') { D.rule.kind = e.target.value; const d = deedOf(D.deed); $('#pr_fields').innerHTML = CAT[D.rule.kind].f(d.id, {}); sumRule(); sums(); }
  else if (id === 'nd_tpl') { const x = D.tpl.find((q) => q.code === e.target.value); const h = $('#nd_hint'); if (h) h.textContent = x ? (S.lang === 'en' ? x.description_en : x.description_bn) || '' : ''; }
  else if (e.target.closest && e.target.closest('#pt_rule')) { sumRule(); sums(); }
});
document.addEventListener('input', (e) => { if (e.target.closest && e.target.closest('#pt_rule')) { sumRule(); sums(); } });
Object.assign(H, {
  pt_newparty: () => partySheet(null), pt_editparty: (a) => partySheet(a.dataset.v),
  pt_saveparty: async (a) => { const r = await rpc('partner_party_save', { p_id: a.dataset.v ? Number(a.dataset.v) : null, p_name: $('#pp_name').value, p_kind: $('#pp_kind').value, p_mobile: $('#pp_mobile').value, p_email: $('#pp_email').value, p_nid: $('#pp_nid').value,
    p_address: $('#pp_addr').value, p_photo: D.photo, p_notes: $('#pp_notes').value, p_active: $('#pp_active').checked, p_client: a.dataset.v ? null : (D.cp = D.cp || rid()) }); if (!r) return; D.cp = null; closeSheet(); toast(lab(X.saved)); await refresh(); },
  pt_newvent: () => ventSheet(null), pt_editvent: (a) => ventSheet(a.dataset.v),
  pt_savevent: async (a) => { const r = await rpc('partner_venture_save', { p_id: a.dataset.v ? Number(a.dataset.v) : null, p_name_bn: $('#pv_bn').value, p_name_en: $('#pv_en').value, p_scope: $('#pv_scope').value, p_location_id: $('#pv_loc').value ? Number($('#pv_loc').value) : null,
    p_model: $('#pv_model').value, p_start: $('#pv_start').value || null, p_end: $('#pv_end').value || null, p_status: $('#pv_status').value, p_notes: $('#pv_notes').value, p_client: a.dataset.v ? null : (D.cv = D.cv || rid()) }); if (!r) return; D.cv = null; closeSheet(); toast(lab(X.saved)); await refresh(); },
  pt_ventdeeds: (a) => { D.tab = 'deeds'; D.venture = a.dataset.v; D.deed = null; const s = $('#pt_tab'); if (s) s.value = 'deeds'; paint(); },
  pt_newdeed: () => newDeedSheet(),
  pt_makedeed: async () => { const v = Number($('#nd_v').value), title = $('#nd_title').value.trim(), tp = $('#nd_tpl').value; D.cd = D.cd || rid();
    const r = tp ? await rpc('partner_agreement_from_template', { p_venture: v, p_code: tp, p_title: title || null, p_client: D.cd }) : await rpc('partner_agreement_save', { p_id: null, p_venture: v, p_title: title, p_from: null, p_to: null, p_clauses: [], p_signed_doc: null, p_client: D.cd });
    if (!r) return; D.cd = null; closeSheet(); await loadAll(); D.deed = r.id; D.tab = 'deeds'; paint(); },
  pt_opendeed: (a) => { D.deed = Number(a.dataset.v); D.tab = 'deeds'; const s = $('#pt_tab'); if (s) s.value = 'deeds'; D.doc = null; paint(); },
  pt_backdeeds: () => { D.deed = null; paint(); },
  pt_savedeed: async () => { const d = deedOf(D.deed); const r = await saveDraftClauses(d, d.clauses || []); if (r) { toast(lab(X.saved)); await refresh(); } },
  pt_addcl: async () => { const d = deedOf(D.deed); const cl = readClauses(); cl.push({ title_bn: '', title_en: '', text_bn: '', text_en: '' }); const r = await saveDraftClauses(d, cl); if (r) await refresh(); },
  pt_savecl: async () => { const d = deedOf(D.deed); const r = await saveDraftClauses(d, readClauses()); if (r) { toast(lab(X.saved)); await refresh(); } },
  pt_cldel: async (a) => { const d = deedOf(D.deed); const cl = readClauses(); cl.splice(Number(a.dataset.v), 1); const r = await saveDraftClauses(d, cl); if (r) await refresh(); },
  pt_clmv: async (a) => { const d = deedOf(D.deed); const cl = readClauses(), i = Number(a.dataset.v), j = i + Number(a.dataset.d); if (j < 0 || j >= cl.length) return; [cl[i], cl[j]] = [cl[j], cl[i]]; const r = await saveDraftClauses(d, cl); if (r) await refresh(); },
  pt_addparty: () => { const d = deedOf(D.deed); openSheet(`<h2>${esc(t3('পক্ষ যোগ', 'Add a party'))}</h2><div class="stack">
    ${fld('ap_p', t3('পক্ষ', 'Party'), `<select id="ap_p">${D.parties.filter((p) => p.active).map((p) => opt(p.id, p.name, '')).join('')}</select>`)}
    ${fld('ap_r', t3('ভূমিকা', 'Role'), `<select id="ap_r">${Object.keys(ROLES).map((k) => opt(k, lb(ROLES, k), '')).join('')}</select>`)}${fld('ap_s', t3('উল্লেখিত ভাগ % (ঐচ্ছিক, তথ্যের জন্য)', 'Stated share % (optional, for the record)'), inp('ap_s', '', 'inputmode="decimal"'))}
    <button class="full primary" data-act="pt_saveap">${esc(lab(X.save))}</button></div>`); void d; },
  pt_saveap: async () => { const sh = nnum($('#ap_s').value); const r = await rpc('partner_agreement_party_set', { p_agr: D.deed, p_party: Number($('#ap_p').value), p_role: $('#ap_r').value, p_share: Number.isFinite(sh) ? sh : null, p_notes: null, p_active: true }); if (!r) return; closeSheet(); await refresh(); },
  pt_rmparty: async (a) => { const r = await rpc('partner_agreement_party_set', { p_agr: D.deed, p_party: Number(a.dataset.p), p_role: a.dataset.r, p_share: null, p_notes: null, p_active: false }); if (r) await refresh(); },
  pt_addshare: (a) => { const box = document.getElementById(a.dataset.v); if (!box) return; box.lastElementChild.insertAdjacentHTML('beforebegin', shareRow(box.dataset.deed, {})); sums(); },
  pt_additem: (a) => { const box = document.getElementById(a.dataset.v); if (box) box.lastElementChild.insertAdjacentHTML('beforebegin', itemRow({})); },
  pt_addslab: () => { const box = $('#pt_slabs'); if (box) { box.lastElementChild.insertAdjacentHTML('beforebegin', slabRow(box.dataset.deed, {})); sums(); } },
  pt_rulenew: () => ruleSheet(null), pt_ruledit: (a) => ruleSheet(Number(a.dataset.v)),
  pt_rulesave: async () => { const kind = $('#pr_kind').value; let cfg; try { cfg = ruleCfg(); } catch (e) { return toast(eText(e)); }
    const r = await rpc('partner_rule_save', { p_agr: D.deed, p_step_no: D.rule.step || null, p_name: $('#pr_name').value || lb(KINDL, kind), p_kind: kind, p_config: cfg, p_active: true }); if (!r) return; closeSheet(); toast(lab(X.saved)); await refresh(); },
  pt_ruleoff: async (a) => { const r0 = deedRules(D.deed).find((x) => x.step_no === Number(a.dataset.v)); const r = await rpc('partner_rule_save', { p_agr: D.deed, p_step_no: r0.step_no, p_name: r0.name, p_kind: r0.kind, p_config: r0.config, p_active: !r0.active }); if (r) await refresh(); },
  pt_rulemv: async (a) => { const rs = deedRules(D.deed).map((x) => x.step_no), i = rs.indexOf(Number(a.dataset.v)), j = i + Number(a.dataset.d); if (j < 0 || j >= rs.length) return; [rs[i], rs[j]] = [rs[j], rs[i]]; const r = await rpc('partner_rules_reorder', { p_agr: D.deed, p_order: rs }); if (r) await refresh(); },
  pt_activate: async () => { const d = deedOf(D.deed); const ex = d.is_example; if (ex && !window.confirm(t3('এই চুক্তির সংখ্যাগুলো উদাহরণ থেকে এসেছে। আপনি কি সব সংখ্যা দেখে নিশ্চিত করছেন?', 'These numbers started as an EXAMPLE. Do you confirm every number is the real deal?'))) return;
    if (!window.confirm(t3('চালু করলে আর বদলানো যাবে না (শুধু সংশোধনী)। চালু করবেন?', 'Once active it cannot be edited (only amended). Activate?'))) return;
    const r = await rpc('partner_agreement_activate', { p_agr: d.id, p_numbers_confirmed: !!ex }); if (r) { toast(lab(X.saved)); await refresh(); } },
  pt_amend: async () => { const r = await rpc('partner_agreement_amend', { p_agr: D.deed, p_client: rid() }); if (!r) return; await loadAll(); D.deed = r.id; paint(); },
  pt_closedeed: async () => { const n = window.prompt(lab(X.why)); if (!n) return; const r = await rpc('partner_agreement_close', { p_agr: D.deed, p_note: n, p_date: null }); if (r) await refresh(); },
  pt_trial: (a) => { D.tab = 'calc'; D.calc = null; D.calcArgs = { deed: Number(a.dataset.v) }; paint(); },
  pt_calc: async () => { const deed = Number($('#pc_deed').value), from = $('#pc_from').value, to = $('#pc_to').value, manual = manualArgs(); D.calcArgs = { deed, from, to, manual };
    const r = await rpc('partner_calculate', { p_agr: deed, p_from: from, p_to: to, p_manual: manual }); if (!r) return; D.calc = r; paint(); },
  pt_savecalc: async () => { const a = D.calcArgs; const r = await rpc('partner_settlement_save', { p_agr: a.deed, p_from: a.from, p_to: a.to, p_manual: a.manual, p_note: ($('#pc_note') || {}).value || null, p_client: (D.cs = D.cs || rid()) });
    if (!r) return; D.cs = null; D.calc = null; toast(lab(X.saved)); D.tab = 'settle'; await refresh(); },
  pt_openset: (a) => setSheet(a.dataset.v),
  pt_approve: async (a) => { if (!window.confirm(t3('অনুমোদনের পর হিসাব বদলানো যাবে না। অনুমোদন?', 'After approval the figures cannot change. Approve?'))) return; const r = await rpc('partner_settlement_approve', { p_id: Number(a.dataset.v) }); if (r) { closeSheet(); await refresh(); } },
  pt_voidset: async (a) => { const n = window.prompt(lab(X.why)); if (!n) return; const r = await rpc('partner_settlement_void', { p_id: Number(a.dataset.v), p_reason: n }); if (r) { closeSheet(); await refresh(); } },
  pt_payline: (a) => { const l = byId(D.lines, a.dataset.v); openSheet(`<h2>${esc(pname(l.party_id))} · ${esc(lb(LKIND, l.kind))}</h2><div class="stack">
    <p class="muted">${esc(t3('বাকি', 'Remaining'))}: ${money(num(l.amount) - num(l.paid_amount))}</p>
    ${fld('pp_amt', t3('অঙ্ক', 'Amount'), inp('pp_amt', r2(num(l.amount) - num(l.paid_amount)), 'inputmode="decimal"'))}
    ${fld('pp_mode', t3('কীভাবে', 'How'), `<select id="pp_mode">${['cash', 'bank', 'mobile'].map((k) => opt(k, lb(MODES, k), '')).join('')}</select>`)}
    ${fld('pp_date', t3('তারিখ', 'Date'), inp('pp_date', today(), 'type="date"'))}${fld('pp_ref', t3('রেফারেন্স', 'Reference'), inp('pp_ref', ''))}
    <button class="full primary" data-act="pt_paysave" data-v="${l.id}">${esc(lab(X.save))}</button></div>`); },
  pt_paysave: async (a) => { const amt = nnum($('#pp_amt').value); if (!(amt > 0)) return toast(eText('bad_amount'));
    const r = await rpc('partner_settlement_pay', { p_line: Number(a.dataset.v), p_amount: amt, p_mode: $('#pp_mode').value, p_date: $('#pp_date').value, p_ref: $('#pp_ref').value || null, p_client: (D.cpay = D.cpay || rid()) }); if (!r) return; D.cpay = null; closeSheet(); toast(lab(X.saved)); await refresh(); },
  pt_capnew: () => { const aps = deedParties(D.capd || (D.deeds.find((d) => d.status === 'active') || {}).id); openSheet(`<h2>${esc(t3('পুঁজির লেনদেন', 'Capital entry'))}</h2><div class="stack">
    ${fld('ck_p', t3('পক্ষ', 'Party'), `<select id="ck_p">${aps.map((x) => opt(x.party_id, pname(x.party_id) + ' (' + lb(ROLES, x.role) + ')', '')).join('')}</select>`)}
    ${fld('ck_k', t3('কী ধরনের', 'Kind'), `<select id="ck_k">${Object.keys(CKIND).map((k) => opt(k, lb(CKIND, k), '')).join('')}</select>`)}
    ${fld('ck_a', t3('অঙ্ক', 'Amount'), inp('ck_a', '', 'inputmode="decimal"'))}${fld('ck_d', t3('তারিখ', 'Date'), inp('ck_d', today(), 'type="date"'))}
    ${fld('ck_m', t3('কীভাবে', 'How'), `<select id="ck_m">${Object.keys(MODES).map((k) => opt(k, lb(MODES, k), '')).join('')}</select>`)}${fld('ck_n', t3('বিবরণ', 'Description'), inp('ck_n', ''))}${fld('ck_r', t3('রেফারেন্স', 'Reference'), inp('ck_r', ''))}
    <button class="full primary" data-act="pt_capsave">${esc(lab(X.save))}</button></div>`); },
  pt_capsave: async () => { const amt = nnum($('#ck_a').value); if (!(amt > 0)) return toast(eText('bad_amount'));
    const r = await rpc('partner_capital_add', { p_agr: Number(D.capd || (D.deeds.find((d) => d.status === 'active') || {}).id), p_party: Number($('#ck_p').value), p_kind: $('#ck_k').value, p_amount: amt, p_date: $('#ck_d').value, p_mode: $('#ck_m').value, p_desc: $('#ck_n').value || null, p_ref: $('#ck_r').value || null, p_client: (D.ccap = D.ccap || rid()) });
    if (!r) return; D.ccap = null; closeSheet(); toast(lab(X.saved)); await refresh(); },
  pt_capvoid: async (a) => { const n = window.prompt(lab(X.why)); if (!n) return; const r = await rpc('partner_capital_void', { p_id: Number(a.dataset.v), p_reason: n }); if (r) await refresh(); },
  pt_stmt: (a) => { D.tab = 'stmt'; D.stmt = null; D.stmtArgs = { party: Number(a.dataset.v) }; paint(); },
  pt_stmtgo: async () => { const party = Number($('#pst_p').value), from = $('#pst_f').value, to = $('#pst_t').value; D.stmtArgs = { party, from, to }; const r = await rpc('partner_party_statement', { p_party: party, p_from: from, p_to: to }); if (!r) return; D.stmt = r; $('#pst_out').innerHTML = stmtBody(r); },
  pt_print: () => { if (!D.stmt) return toast(t3('আগে বিবরণী দেখান', 'Show the statement first')); window.print(); },
});
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(lab(X.title), '<div id="pt_body"><p class="muted">…</p></div>', true);
  if (!(S.ctx && S.ctx.is_owner)) { $('#pt_body').innerHTML = `<p class="muted">${esc(lab(ERR['not allowed']))}</p>`; return; }
  try { await loadAll(); paint(); } catch (e) { $('#pt_body').innerHTML = `<p class="muted">${esc(eText(e))}</p>`; }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { partners: view });
})();
