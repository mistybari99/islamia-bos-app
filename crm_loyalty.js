/* Islamia BOS · CRM-F · Loyalty extras (#/crmloyalty).
   Tabs: Expiry (preview, apply, warning list, past runs), Referral (list, reject with a reason), Hooks (birthday / anniversary / festival rules, who is due, bonus run),
   Statement (one customer's points), Summary (what the programme did), Settings (every CRM-F setting with an (i) info sheet; the owner edits).
   Server: supabase/phase316.sql to phase319.sql. Coupons live in web/crm_coupons.js (#/crmcoupons).
   Every setting is OFF or blank by default; nothing here starts by itself. English labels only (owner decision); L() keeps the three modes ready.
   The (i) info texts are the same entries as docs/integration/CRM-F_info.json (generated; a test compares them). UNVERIFIED on a real phone and on a real Supabase project. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const E = (s) => L(s, s, s);
const $ = (s, el = document) => el.querySelector(s);
const val = (id) => (($('#' + id) || {}).value || '').trim();
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const pt = (n) => { const v = Number(n); return Number.isFinite(v) ? v.toLocaleString('en-IN') : '-'; };
const chip = (txt, cls) => `<span class="chip ${cls || ''}">${esc(txt)}</span>`;
const fld = (id, label, inner) => `<div><label for="${id}">${esc(label)}</label>${inner}</div>`;
const inp = (id, v, extra) => `<input id="${id}" autocomplete="off" value="${esc(v ?? '')}" ${extra || ''}>`;

// info sheet entries: generated from docs/integration/CRM-F_info.json by the build helper; do not edit by hand
const INFO = /*INFO-START*/{"crm_points_expiry_months": {"key": "crm_points_expiry_months", "kind": "setting", "title": "Points expire after this many months", "what_it_does": "Sets how old unspent points must be before the owner can expire them.", "why_it_matters": "Points nobody spends pile up as a promise to customers. A time limit keeps the promise honest and encourages visits.", "default": "Blank. Points never expire, as today.", "what_changes_if_switched": "Once a number is set (and the start date below), the owner can preview who would lose points and then apply it. Nothing expires by itself.", "who_can_change": "Only the owner (Settings)."}, "crm_points_expiry_from": {"key": "crm_points_expiry_from", "kind": "setting", "title": "Points expiry counts from this date", "what_it_does": "The first day expiry may count. Points earned before this date are treated as earned on this date.", "why_it_matters": "Stops old points from being wiped on the day expiry is switched on. Customers get the full period from the start date.", "default": "Blank. Expiry cannot be applied.", "what_changes_if_switched": "With a date set, a points expiry run can be applied. Choose a date a few months ahead and tell customers first.", "who_can_change": "Only the owner (Settings)."}, "crm_points_expiry_warn_days": {"key": "crm_points_expiry_warn_days", "kind": "setting", "title": "Warn this many days before points expire", "what_it_does": "Shows the list of customers who will lose points within this many days.", "why_it_matters": "A friendly reminder before points vanish is kinder and brings customers back.", "default": "Blank. No warning list.", "what_changes_if_switched": "The Expiry tab lists who is about to lose points. Sending a message is done from the campaign screens.", "who_can_change": "Only the owner (Settings)."}, "crm_burn_max_percent": {"key": "crm_burn_max_percent", "kind": "setting", "title": "Points can pay at most this percent of a bill", "what_it_does": "Limits how much of one bill can be paid with points.", "why_it_matters": "Stops a bill from being paid almost entirely with points when you do not want that.", "default": "Blank. No limit, as today.", "what_changes_if_switched": "The till check shows the largest points allowed for the bill and refuses more. The owner can allow an exception with a reason.", "who_can_change": "Only the owner (Settings)."}, "crm_burn_max_points": {"key": "crm_burn_max_points", "kind": "setting", "title": "Most points that can be used on one bill", "what_it_does": "A fixed cap on points per bill.", "why_it_matters": "Keeps one large redemption from emptying a customer's balance by mistake.", "default": "Blank. No limit.", "what_changes_if_switched": "More than this number on one bill is refused unless the owner allows it with a reason.", "who_can_change": "Only the owner (Settings)."}, "crm_burn_step_points": {"key": "crm_burn_step_points", "kind": "setting", "title": "Points must be used in steps of", "what_it_does": "Points can only be used in multiples of this number (for example 50).", "why_it_matters": "Keeps redemptions tidy and easy to explain at the counter.", "default": "Blank. Any number of points.", "what_changes_if_switched": "A number that is not a multiple is refused unless the owner allows it with a reason.", "who_can_change": "Only the owner (Settings)."}, "crm_points_adjust_alert_over": {"key": "crm_points_adjust_alert_over", "kind": "setting", "title": "Tell the owner when a manual points change is larger than", "what_it_does": "A manual points change above this size also appears in the Exceptions list.", "why_it_matters": "Large hand-made changes are the easiest place for mistakes or misuse.", "default": "Blank. No alert. A reason is always required anyway.", "what_changes_if_switched": "Changes above the number show as a yellow line in Exceptions with the reason.", "who_can_change": "Only the owner (Settings)."}, "crm_referral_on": {"key": "crm_referral_on", "kind": "setting", "title": "Referral codes and rewards", "what_it_does": "Lets each customer have a short code. A new customer who gives it earns the referrer points after their first completed sale.", "why_it_matters": "Customers bringing friends is the cheapest way to grow.", "default": "OFF. No code is made and no reward is given.", "what_changes_if_switched": "Codes can be made, a new customer can be linked to a referrer, and the reward is given once on the new customer's first completed sale. Loyalty points must also be ON.", "who_can_change": "Only the owner (Settings)."}, "crm_referral_reward_points": {"key": "crm_referral_reward_points", "kind": "setting", "title": "Points the referring customer earns", "what_it_does": "The number of points the referrer gets.", "why_it_matters": "A blank number means no reward is promised.", "default": "Blank. No reward can be given.", "what_changes_if_switched": "Rewards are given only when this number is set.", "who_can_change": "Only the owner (Settings)."}, "crm_referral_referred_points": {"key": "crm_referral_referred_points", "kind": "setting", "title": "Points the new customer earns", "what_it_does": "Extra welcome points for the referred customer.", "why_it_matters": "Gives the new customer a reason to say who sent them.", "default": "Blank. Nothing extra.", "what_changes_if_switched": "The new customer gets these points together with the referrer's reward.", "who_can_change": "Only the owner (Settings)."}, "crm_referral_min_bill": {"key": "crm_referral_min_bill", "kind": "setting", "title": "First bill must be at least", "what_it_does": "The smallest first bill that earns a referral reward.", "why_it_matters": "Stops rewards for tiny test purchases.", "default": "Blank. Any first bill counts.", "what_changes_if_switched": "A smaller first bill closes the referral without a reward.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_on": {"key": "crm_voucher_on", "kind": "setting", "title": "Coupons and vouchers", "what_it_does": "Lets the till check a coupon code and record its use against a sale.", "why_it_matters": "Gives staff a controlled way to give offers instead of typing free discounts.", "default": "OFF. Coupons can be prepared but not used.", "what_changes_if_switched": "Coupon checks and redemptions start working. The discount is still entered through the normal discount control, with its normal approval.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_max_percent": {"key": "crm_voucher_max_percent", "kind": "setting", "title": "Largest percent a coupon may give", "what_it_does": "The most a percent coupon may take off.", "why_it_matters": "A safety limit so a typing mistake cannot create a 90 percent coupon.", "default": "Blank. Percent coupons cannot be created.", "what_changes_if_switched": "Percent coupons up to this number can be created. Above it only the owner can, with a reason.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_max_amount": {"key": "crm_voucher_max_amount", "kind": "setting", "title": "Largest taka amount a coupon may give", "what_it_does": "The most an amount coupon may take off.", "why_it_matters": "Same safety limit for taka coupons.", "default": "Blank. Amount coupons cannot be created.", "what_changes_if_switched": "Amount coupons up to this number can be created. Above it only the owner can, with a reason.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_liability_on": {"key": "crm_voucher_liability_on", "kind": "setting", "title": "Book coupon liability in the accounts", "what_it_does": "For amount coupons marked 'post liability', holds the unused value in the accounts as a provision and releases it as the coupon is used or expires.", "why_it_matters": "Shows a promise to customers on the books. It changes accounting figures, so it is a deliberate choice for the owner and the accountant.", "default": "OFF. Coupons never touch the accounts.", "what_changes_if_switched": "From the effective-from date, new marked coupons write balanced entries (Dr expense, Cr liability). It can be wound down to zero before switching off.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_liability_from": {"key": "crm_voucher_liability_from", "kind": "setting", "title": "Coupon liability counts from this date", "what_it_does": "The first day coupon liability may be booked. Only coupons made on or after it are booked.", "why_it_matters": "Protects history: the past never changes.", "default": "Blank. Liability cannot be switched on.", "what_changes_if_switched": "Required before switching on, and it must not be in the past at that moment.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_liability_account": {"key": "crm_voucher_liability_account", "kind": "setting", "title": "Liability account for unused coupon value", "what_it_does": "The chart account (code) that holds the unused coupon value.", "why_it_matters": "The books need to know where to hold it.", "default": "Blank. Liability cannot be switched on.", "what_changes_if_switched": "Must be an existing active liability account.", "who_can_change": "Only the owner (Settings)."}, "crm_voucher_expense_account": {"key": "crm_voucher_expense_account", "kind": "setting", "title": "Expense account for the coupon provision", "what_it_does": "The chart account (code) charged when the provision is set up.", "why_it_matters": "Shows the cost of the offer in the right place.", "default": "Blank. Liability cannot be switched on.", "what_changes_if_switched": "Must be an existing active expense account.", "who_can_change": "Only the owner (Settings)."}, "crm_hooks_on": {"key": "crm_hooks_on", "kind": "setting", "title": "Birthday, anniversary and festival hooks", "what_it_does": "Lets the owner see who is due for a birthday or anniversary bonus and give the bonus points once per year.", "why_it_matters": "Small gifts on special days build loyalty. This only gives points; messages are sent from campaigns.", "default": "OFF. The due list is empty and nothing is given.", "what_changes_if_switched": "The due list works and the owner can run the bonus (preview first). Loyalty points must also be ON.", "who_can_change": "Only the owner (Settings)."}, "points_expiry": {"key": "points_expiry", "kind": "feature", "title": "Points expiry", "what_it_does": "Preview, then apply: points earned before the cut date and not yet spent or expired are removed once.", "why_it_matters": "Keeps outstanding points under control.", "default": "Off until months and a start date are set.", "what_changes_if_switched": "Applying writes expire lines in the points history and an audit line. A second apply the same day finds nothing.", "who_can_change": "The owner, or a person with the loyalty manage right. A customer-manage holder can preview only."}, "burn_rules": {"key": "burn_rules", "kind": "feature", "title": "Using points at the till", "what_it_does": "Checks the burn limits before points are used on a bill.", "why_it_matters": "Stops mistakes at the counter.", "default": "No limits.", "what_changes_if_switched": "The till calls the checked redeem. The old redeem still works for screens that have not changed.", "who_can_change": "Owner sets the limits. The owner or the loyalty manage right can go past a limit, with a reason."}, "referral": {"key": "referral", "kind": "feature", "title": "Referral", "what_it_does": "A code per customer, a link for a new customer, and a one-time reward.", "why_it_matters": "Word of mouth.", "default": "Off.", "what_changes_if_switched": "See the Referral tab. The reward is taken back if the first sale is voided.", "who_can_change": "Staff at the till can link a new customer. The owner or loyalty manage right can reject a referral with a reason."}, "coupons": {"key": "coupons", "kind": "feature", "title": "Coupons and vouchers", "what_it_does": "A code with a value, dates, a minimum bill, use limits and optional outlet or item scope.", "why_it_matters": "Controlled offers with a record of every use.", "default": "Off.", "what_changes_if_switched": "Use a coupon: check it at the till, give the discount through the normal discount control, then record it after the sale. A different discount raises a yellow Exceptions line.", "who_can_change": "The owner or a person with the coupon issue right makes coupons. The owner or a person with the coupon override right can accept an expired or limited coupon with a reason."}, "coupon_override": {"key": "coupon_override", "kind": "feature", "title": "Coupon exceptions", "what_it_does": "Accepts a coupon that is expired, not started, below the minimum bill, at another outlet or past the per-customer limit.", "why_it_matters": "Real life has exceptions; they must leave a trace.", "default": "Not allowed.", "what_changes_if_switched": "Needs a reason. Writes an audit line and a yellow Exceptions line. A used-up, retired or someone else's personal coupon can never be accepted.", "who_can_change": "The owner, or a person with the coupon override right."}, "points_statement": {"key": "points_statement", "kind": "feature", "title": "Points statement", "what_it_does": "One customer's points: opening balance, every line with a running balance, closing balance.", "why_it_matters": "Settles questions at the counter.", "default": "Always available to staff who can see customers.", "what_changes_if_switched": "Nothing changes. It only reads.", "who_can_change": "Anyone who can see customers."}, "loyalty_summary": {"key": "loyalty_summary", "kind": "feature", "title": "Loyalty summary", "what_it_does": "Points given, used and expired, points outstanding, referrals, coupons and bonuses for a date range.", "why_it_matters": "Shows what the programme costs and does.", "default": "Always available to managers.", "what_changes_if_switched": "Nothing changes. Outstanding points are shown for information and are not booked in the accounts.", "who_can_change": "The owner, customer-manage holders and loyalty managers."}}/*INFO-END*/;

// every CRM-F setting: [key, kind, English label, unit]
const SETS = [
  ['crm_points_expiry_months', 'number', 'Points expire after this many months', 'months', 'expiry'], ['crm_points_expiry_from', 'text', 'Points expiry counts from (YYYY-MM-DD)', '', 'expiry'],
  ['crm_points_expiry_warn_days', 'number', 'Warn this many days before points expire', 'days', 'expiry'], ['crm_burn_max_percent', 'number', 'Points can pay at most this percent of a bill', '%', 'burn'],
  ['crm_burn_max_points', 'number', 'Most points on one bill', 'pts', 'burn'], ['crm_burn_step_points', 'number', 'Points must be used in steps of', 'pts', 'burn'],
  ['crm_points_adjust_alert_over', 'number', 'Alert on manual points changes larger than', 'pts', 'burn'],
  ['crm_referral_on', 'switch', 'Referral codes and rewards', '', 'referral'], ['crm_referral_reward_points', 'number', 'Points the referring customer earns', 'pts', 'referral'],
  ['crm_referral_referred_points', 'number', 'Points the new customer earns', 'pts', 'referral'], ['crm_referral_min_bill', 'number', 'First bill must be at least', 'taka', 'referral'],
  ['crm_voucher_on', 'switch', 'Coupons and vouchers', '', 'coupons'], ['crm_voucher_max_percent', 'number', 'Largest percent a coupon may give', '%', 'coupons'],
  ['crm_voucher_max_amount', 'number', 'Largest taka amount a coupon may give', 'taka', 'coupons'], ['crm_voucher_liability_on', 'switch', 'Book coupon liability in the accounts', '', 'coupons'],
  ['crm_voucher_liability_from', 'text', 'Coupon liability counts from (YYYY-MM-DD)', '', 'coupons'], ['crm_voucher_liability_account', 'text', 'Liability account code', '', 'coupons'],
  ['crm_voucher_expense_account', 'text', 'Expense account code', '', 'coupons'], ['crm_hooks_on', 'switch', 'Birthday, anniversary and festival hooks', '', 'hooks'],
];
const X = {
  title: E('Loyalty extras'), t_expiry: E('Expiry'), t_referral: E('Referral'), t_hooks: E('Hooks'), t_stmt: E('Statement'), t_sum: E('Summary'), t_set: E('Settings'),
  cancel: E('Cancel'), save: E('Save'), saved: E('Saved'), none: E('Nothing yet'), reason: E('Reason'), done: E('Done'), setFirst: E('Set this first'), notSet: E('Not set'), on: E('ON'), off: E('OFF'),
  expHint: E('Points earned before the cut date and not yet spent or expired can be removed once, by the owner, after a preview. Nothing expires by itself.'),
  expOff: E('Points never expire: the months number or the start date is blank.'), preview: E('Preview'), apply: E('Apply expiry'), cut: E('Cut date'), customers: E('Customers'), points: E('Points'),
  value: E('Worth in taka'), warn: E('About to lose points'), runs: E('Past runs'), note: E('Note (optional)'), confirmApply: E('Remove these points now? This is recorded and cannot be undone.'),
  applied: E('Expiry applied'), nothing: E('Nothing to expire'),
  refHint: E('A new customer who gives a referral code earns the referrer points after their first completed sale.'), refOff: E('Referral is switched OFF.'), reject: E('Reject'), pending: E('Pending'),
  rewarded: E('Rewarded'), rejected: E('Rejected'), reversed: E('Taken back'), referrer: E('Referred by'),
  hkHint: E('A hook is a rule: from some days before a birthday or anniversary, give bonus points. Messages are sent from the campaign screens.'), hkOff: E('Hooks are switched OFF: nothing is due and nothing is given.'),
  newHook: E('New hook'), hkKind: E('Kind'), hkBirthday: E('Birthday'), hkAnniv: E('Anniversary'), hkFest: E('Festival (date typed by you)'), hkName: E('Name'), hkOffset: E('Days before'), hkBonus: E('Bonus points'),
  hkDate: E('Festival date'), switchOn: E('Switch on'), switchOff: E('Switch off'), due: E('Who is due'), runPrev: E('Preview the bonus'), runGo: E('Give the bonus'), granted: E('Given'),
  stmtHint: E('Type the customer mobile to see their points.'), mobile: E('Customer mobile'), find: E('Find'), opening: E('Opening'), closing: E('Closing'), earned: E('Earned'), used: E('Used'), expired: E('Expired'),
  from: E('From'), to: E('To'), show: E('Show'), notFound: E('Customer not found'),
  sumHint: E('What the programme gave and cost in the chosen days. Points outstanding are shown for information; they are not booked in the accounts.'), outstanding: E('Points outstanding'),
  members: E('Customers with points'), coupons: E('Coupons'), referrals: E('Referrals'), bonus: E('Bonus points'),
  setHint: E('Every setting is OFF or blank until the owner sets it. The (i) button explains each one.'), ownerOnly: E('Only the owner can change settings.'), info: E('What is this?'),
  iWhat: E('What it does'), iWhy: E('Why it matters'), iDef: E('Default'), iChange: E('What changes if you switch it'), iWho: E('Who can change it'),
  noperm: E('You do not have permission.'), nofn: E('The server does not have this feature yet (phase 316 to 319 not pasted).'),
};
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: 'You do not have permission.', expiry_not_set: 'Set the months and the start date in Settings first.', reason_required: 'Write a reason (at least 3 letters).', not_pending: 'This referral is already decided.',
  hooks_off: 'Hooks are switched OFF.', loyalty_off: 'Loyalty points are switched OFF.', referral_off: 'Referral is switched OFF.', name_required: 'Write a name.', festival_date_required: 'A festival hook needs a date.',
  festival_no_points: 'A festival hook cannot give points.', bad_number: 'A number is not valid.', bad_date: 'A date is not valid.', bad_value: 'The value is not valid.', bad_account: 'That account code is not an active account.',
  bad_account_type: 'The account is of the wrong type.', liability_from_needed: 'Set the effective-from date first.', liability_from_in_the_past: 'The effective-from date must not be in the past.',
  liability_accounts_needed: 'Set both account codes first.', accounting_not_on: 'Accounting must be switched on first.', customer_not_found: 'Customer not found.',
};
const eText = (e) => { const m = String((e && e.message) || ''); if (/could not find|does not exist|PGRST202/i.test(m + ' ' + ((e && e.code) || ''))) return lab(X.nofn); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? ERR[k] : m || 'error'; };
async function call(fn, args) { const r = await sb.rpc(fn, args || {}); if (r.error) { const e = new Error(eText(r.error)); e.raw = r.error; throw e; } return r.data; }
const act = (fn) => async (a) => { try { await fn(a); } catch (e) { toast(e.message || 'error'); } };

const LY = { tab: 'expiry', st: null, rules: {}, prev: null, soon: null, runs: [], refs: [], hooks: [], due: null, stmt: null, sum: null, from: '', to: '', cust: null };
const TABS = [['expiry', 't_expiry'], ['referral', 't_referral'], ['hooks', 't_hooks'], ['stmt', 't_stmt'], ['sum', 't_sum'], ['set', 't_set']];
const tabsBar = () => `<div class="row wrap" id="ly_tabs" style="gap:.3rem">${TABS.map(([k, l]) => `<button type="button" class="tog ${LY.tab === k ? 'on' : ''}" data-act="ly_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
const infoBtn = (key) => `<button type="button" class="mini" data-act="ly_info" data-v="${esc(key)}" aria-label="${esc(T('info'))}">(i)</button>`;
const can = (k) => !!(LY.st && LY.st.can && LY.st.can[k]);

async function loadRules() {
  const r = await sb.from('rules').select('key,value,default_value').in('key', SETS.map((s) => s[0]));
  const o = {}; (r.data || []).forEach((x) => { o[x.key] = x.value === null || x.value === undefined ? x.default_value : x.value; }); LY.rules = o;
}
const rv = (k) => (LY.rules[k] === undefined ? null : LY.rules[k]);

function expiryHTML() {
  const e = (LY.st && LY.st.expiry) || {}; const blank = e.months == null || !e.from;
  let h = `<p class="muted">${esc(T('expHint'))} ${infoBtn('points_expiry')}</p>`;
  h += blank ? `<div class="notice" id="ex_off">${esc(T('expOff'))} <b>${esc(T('setFirst'))}</b></div>` : '';
  h += `<div class="card"><div class="row between"><span>${esc(SETS[0][2])}</span><b>${e.months == null ? esc(T('notSet')) : esc(e.months)}</b></div><div class="row between"><span>${esc(SETS[1][2])}</span><b>${e.from ? esc(e.from) : esc(T('notSet'))}</b></div></div>`;
  h += `<div class="row"><button type="button" class="full" data-act="ex_prev">${esc(T('preview'))}</button>${can('apply') ? `<button type="button" class="full primary" data-act="ex_apply" ${blank ? 'disabled' : ''}>${esc(T('apply'))}</button>` : ''}</div>`;
  const p = LY.prev;
  if (p && !p.off) {
    h += `<div class="card" id="ex_prev"><b>${esc(T('cut'))}: ${esc(p.cut)}</b><div>${esc(T('customers'))}: ${pt(p.customers)} · ${esc(T('points'))}: ${pt(p.points)} · ${esc(T('value'))}: ${fm(p.value_taka)}</div><div class="muted">${esc(p.rule || '')}</div>
      ${(p.sample || []).map((s) => `<div class="row between"><span>${esc(s.name)}</span><span>${pt(s.points)} / ${pt(s.balance)}</span></div>`).join('')}</div>`;
  }
  if (LY.soon && !LY.soon.off) h += `<h3>${esc(T('warn'))} (${pt(LY.soon.days)})</h3>${(LY.soon.rows || []).map((s) => `<div class="row between"><span>${esc(s.name)} <span class="muted">${esc(s.mobile)}</span></span><b>${pt(s.points)}</b></div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}`;
  h += `<h3>${esc(T('runs'))}</h3>${(LY.runs || []).map((r) => `<div class="card"><div class="row between"><b>#${esc(r.id)} · ${esc(r.as_of)}</b><span>${pt(r.points)} · ${pt(r.customers)}</span></div><div class="muted">${esc(T('cut'))} ${esc(r.cut_date)}${r.note ? ' · ' + esc(r.note) : ''}</div></div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}`;
  return h;
}
function referralHTML() {
  const on = LY.st && LY.st.referral && LY.st.referral.on;
  const rows = (LY.refs || []).map((r) => `<div class="card"><div class="row between"><b>${esc(r.referred_name)}</b>${chip(T(r.status === 'reversed' ? 'reversed' : r.status), r.status === 'rewarded' ? 'ok' : '')}</div>
    <div class="muted">${esc(T('referrer'))} ${esc(r.referrer_name)} · ${esc(r.code)}${r.reward_points ? ' · ' + pt(r.reward_points) + ' pts' : ''}${r.reason ? ' · ' + esc(r.reason) : ''}</div>
    ${r.status === 'pending' && can('apply') ? `<div class="row"><button type="button" class="mini" data-act="rf_reject" data-v="${esc(r.id)}">${esc(T('reject'))}</button></div>` : ''}</div>`).join('');
  return `<p class="muted">${esc(T('refHint'))} ${infoBtn('referral')}</p>${on ? '' : `<div class="notice" id="rf_off">${esc(T('refOff'))}</div>`}${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function hooksHTML() {
  const on = LY.st && LY.st.hooks_on;
  const rows = (LY.hooks || []).map((h) => `<div class="card ${h.active ? '' : 'muted'}"><div class="row between"><b>${esc(h.name)}</b>${chip(h.active ? T('on') : T('off'), h.active ? 'ok' : '')}</div>
    <div class="muted">${esc(T(h.kind === 'birthday' ? 'hkBirthday' : h.kind === 'anniversary' ? 'hkAnniv' : 'hkFest'))} · ${esc(T('hkOffset'))} ${esc(h.offset_days)}${h.bonus_points ? ' · ' + pt(h.bonus_points) + ' pts' : ''}${h.festival_date ? ' · ' + esc(h.festival_date) : ''}${h.coupon_code ? ' · ' + esc(h.coupon_code) : ''} · ${esc(T('granted'))} ${esc(h.grants)}</div>
    ${can('apply') ? `<div class="row"><button type="button" class="mini" data-act="hk_toggle" data-v="${esc(h.id)}">${esc(h.active ? T('switchOff') : T('switchOn'))}</button></div>` : ''}</div>`).join('');
  const due = LY.due; let dh = '';
  if (due) dh = due.off ? `<div class="notice">${esc(T('hkOff'))}</div>` : `<h3>${esc(T('due'))}</h3>${(due.rows || []).map((r) => `<div class="row between"><span>${esc(r.customer_name || r.hook_name)} <span class="muted">${esc(r.occasion)}</span></span><span>${r.bonus_points ? pt(r.bonus_points) : ''} ${r.granted ? chip(T('granted'), 'ok') : ''}</span></div>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}`;
  return `<p class="muted">${esc(T('hkHint'))} ${infoBtn('crm_hooks_on')}</p>${on ? '' : `<div class="notice" id="hk_off">${esc(T('hkOff'))}</div>`}
    ${can('apply') ? `<div class="row"><button type="button" class="full" data-act="hk_new">+ ${esc(T('newHook'))}</button></div>` : ''}${rows || `<p class="muted">${esc(T('none'))}</p>`}
    <div class="row"><button type="button" class="full" data-act="hk_due">${esc(T('due'))}</button>${can('apply') ? `<button type="button" class="full" data-act="hk_run" data-v="dry">${esc(T('runPrev'))}</button><button type="button" class="full primary" data-act="hk_run" data-v="go">${esc(T('runGo'))}</button>` : ''}</div>${dh}`;
}
function stmtHTML() {
  const s = LY.stmt;
  let h = `<p class="muted">${esc(T('stmtHint'))} ${infoBtn('points_statement')}</p><div class="card stack">${fld('st_mobile', T('mobile'), inp('st_mobile', LY.cust ? LY.cust.mobile : '', 'inputmode="numeric" maxlength="14"'))}
    <div class="row">${fld('st_from', T('from'), inp('st_from', LY.from, 'type="date"'))}${fld('st_to', T('to'), inp('st_to', LY.to, 'type="date"'))}</div><button type="button" class="full primary" data-act="st_go">${esc(T('find'))}</button></div>`;
  if (s) {
    h += `<div class="card" id="st_head"><b>${esc(s.customer.name)}</b><div>${esc(T('opening'))} ${pt(s.opening)} · ${esc(T('earned'))} ${pt(s.earned)} · ${esc(T('used'))} ${pt(s.used)} · ${esc(T('expired'))} ${pt(s.expired)} · ${esc(T('closing'))} ${pt(s.closing)}</div>
      <div class="muted">${pt(s.balance_now)} pts = ${fm(s.value_taka)}${s.expiring_soon ? ' · ' + esc(T('warn')) + ': ' + pt(s.expiring_soon) : ''}</div></div>`;
    h += (s.rows || []).map((r) => `<div class="card"><div class="row between"><span>${esc(String(r.at).slice(0, 10))} · ${esc(r.reason)}${r.receipt ? ' #' + esc(r.receipt) : ''}</span><b>${r.delta > 0 ? '+' : ''}${pt(r.delta)}</b></div><div class="muted">${esc(r.note || '')} · ${pt(r.balance)}</div></div>`).join('');
  }
  return h;
}
function sumHTML() {
  const s = LY.sum;
  let h = `<p class="muted">${esc(T('sumHint'))} ${infoBtn('loyalty_summary')}</p><div class="card stack"><div class="row">${fld('sm_from', T('from'), inp('sm_from', LY.from, 'type="date"'))}${fld('sm_to', T('to'), inp('sm_to', LY.to, 'type="date"'))}</div><button type="button" class="full primary" data-act="sm_go">${esc(T('show'))}</button></div>`;
  if (s) {
    const p = s.points || {}; const r = s.referrals || {}; const c = s.coupons || {}; const k = s.hooks || {};
    h += `<div class="card" id="sm_body"><div class="row between"><span>${esc(T('earned'))}</span><b>${pt(Number(p.earned_sales) + Number(p.earned_referral) + Number(p.earned_bonus) + Number(p.adjusted_up))}</b></div>
      <div class="row between"><span>${esc(T('used'))}</span><b>${pt(p.redeemed)}</b></div><div class="row between"><span>${esc(T('expired'))}</span><b>${pt(p.expired)}</b></div>
      <div class="row between"><span>${esc(T('outstanding'))}</span><b>${pt(s.outstanding_points)} = ${fm(s.outstanding_value_taka)}</b></div><div class="row between"><span>${esc(T('members'))}</span><b>${pt(s.members_with_points)}</b></div>
      <div class="row between"><span>${esc(T('referrals'))}</span><b>${pt(r.rewarded)} / ${pt(r.pending)}</b></div><div class="row between"><span>${esc(T('coupons'))}</span><b>${pt(c.uses)} · ${fm(c.discount_given)}</b></div>
      <div class="row between"><span>${esc(T('bonus'))}</span><b>${pt(k.points)}</b></div><div class="muted">${esc(s.note)}</div></div>`;
  }
  return h;
}
function setHTML() {
  const owner = !!(S.ctx && S.ctx.is_owner);
  const row = ([k, kind, label, unit]) => {
    const v = rv(k); let ctl;
    if (kind === 'switch') ctl = `<label class="row"><input type="checkbox" id="sv_${k}" ${v === true ? 'checked' : ''} ${owner ? '' : 'disabled'}> ${esc(label)}</label>`;
    else ctl = fld('sv_' + k, label + (unit ? ' (' + unit + ')' : ''), inp('sv_' + k, v == null ? '' : v, `${kind === 'number' ? 'inputmode="decimal"' : ''} placeholder="${esc(T('notSet'))}" ${owner ? '' : 'disabled'}`));
    return `<div class="card stack set-row" data-key="${esc(k)}"><div class="row between"><span class="muted">${esc(k)}</span>${infoBtn(k)}</div>${ctl}${v == null && kind !== 'switch' ? `<div class="muted">${esc(T('setFirst'))}</div>` : ''}</div>`;
  };
  return `<p class="muted">${esc(T('setHint'))}</p>${owner ? `<button type="button" class="primary full" data-act="sv_save">${esc(T('save'))}</button>` : `<p class="muted">${esc(T('ownerOnly'))}</p>`}${SETS.map(row).join('')}`;
}
function draw() {
  const el = $('#ly_body'); if (!el) return;
  el.innerHTML = tabsBar() + ({ expiry: expiryHTML, referral: referralHTML, hooks: hooksHTML, stmt: stmtHTML, sum: sumHTML, set: setHTML }[LY.tab] || expiryHTML)();
}
async function load(tab) {
  LY.tab = tab || LY.tab;
  try { LY.st = await call('crmf_status', {}); } catch (e) { LY.st = null; }
  if (LY.tab === 'expiry') { LY.runs = await call('crmf_points_expiry_runs', { p_limit: 20 }).catch(() => []); if (LY.st && LY.st.expiry && LY.st.expiry.warn_days != null) LY.soon = await call('crmf_points_expiry_soon', { p_days: null }).catch(() => null); }
  if (LY.tab === 'referral') LY.refs = await call('crmf_referral_list', { p_status: null, p_limit: 100 }).catch(() => []);
  if (LY.tab === 'hooks') LY.hooks = await call('crmf_hook_list', {}).catch(() => []);
  if (LY.tab === 'set') await loadRules();
  draw();
}

Object.assign(H, {
  ly_tab: act(async (a) => { await load(a.dataset.v); }),
  ly_info: (a) => {
    const i = INFO[a.dataset.v]; if (!i) return toast(T('nofn'));
    openSheet(`<h3>${esc(i.title)}</h3><div class="stack" id="ly_info"><div><b>${esc(T('iWhat'))}</b><p>${esc(i.what_it_does)}</p></div><div><b>${esc(T('iWhy'))}</b><p>${esc(i.why_it_matters)}</p></div>
      <div><b>${esc(T('iDef'))}</b><p>${esc(i.default)}</p></div><div><b>${esc(T('iChange'))}</b><p>${esc(i.what_changes_if_switched)}</p></div><div><b>${esc(T('iWho'))}</b><p>${esc(i.who_can_change)}</p></div>
      <button type="button" class="full" data-act="closesheet">${esc(T('done'))}</button></div>`);
  },
  ex_prev: act(async () => { LY.prev = await call('crmf_points_expiry_preview', { p_as_of: null }); draw(); }),
  ex_apply: () => openSheet(`<h3>${esc(T('apply'))}</h3><div class="stack"><p>${esc(T('confirmApply'))}</p>${fld('ex_note', T('note'), inp('ex_note', '', 'maxlength="300"'))}<div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="ex_applygo">${esc(T('apply'))}</button></div></div>`),
  ex_applygo: act(async () => { const r = await call('crmf_points_expiry_apply', { p_client: rid(), p_note: val('ex_note') || null }); closeSheet(); toast(r && r.run_id ? T('applied') + ': ' + pt(r.points) : T('nothing')); LY.prev = null; await load('expiry'); }),
  rf_reject: (a) => openSheet(`<h3>${esc(T('reject'))}</h3><div class="stack">${fld('rf_why', T('reason'), inp('rf_why', '', 'maxlength="300"'))}<div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="rf_rejectgo" data-v="${esc(a.dataset.v)}">${esc(T('reject'))}</button></div></div>`),
  rf_rejectgo: act(async (a) => { const w = val('rf_why'); if (w.length < 3) return toast(ERR.reason_required); await call('crmf_referral_reject', { p_id: Number(a.dataset.v), p_reason: w }); closeSheet(); toast(T('saved')); await load('referral'); }),
  hk_new: () => openSheet(`<h3>${esc(T('newHook'))}</h3><div class="stack">${fld('hk_kind', T('hkKind'), `<select id="hk_kind"><option value="birthday">${esc(T('hkBirthday'))}</option><option value="anniversary">${esc(T('hkAnniv'))}</option><option value="festival">${esc(T('hkFest'))}</option></select>`)}
    ${fld('hk_name', T('hkName'), inp('hk_name', '', 'maxlength="80"'))}${fld('hk_offd', T('hkOffset'), inp('hk_offd', '7', 'inputmode="numeric"'))}${fld('hk_bonus', T('hkBonus'), inp('hk_bonus', '', 'inputmode="numeric"'))}${fld('hk_date', T('hkDate'), inp('hk_date', '', 'type="date"'))}
    <div class="row"><button type="button" class="full" data-act="closesheet">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="hk_newgo">${esc(T('save'))}</button></div></div>`),
  hk_newgo: act(async () => {
    const kind = val('hk_kind'); const p = { kind, name: val('hk_name'), offset_days: nnum(val('hk_offd')) };
    const b = nnum(val('hk_bonus')); if (Number.isNaN(b)) throw new Error(ERR.bad_number); if (b !== null) p.bonus_points = b;
    if (kind === 'festival') p.festival_date = val('hk_date');
    await call('crmf_hook_save', { p_id: null, p }); closeSheet(); toast(T('saved')); await load('hooks');
  }),
  hk_toggle: act(async (a) => { const h = LY.hooks.find((x) => String(x.id) === a.dataset.v); if (!h) return; await call('crmf_hook_save', { p_id: Number(h.id), p: { active: !h.active } }); toast(T('saved')); await load('hooks'); }),
  hk_due: act(async () => { LY.due = await call('crmf_hooks_due', { p_date: null, p_limit: 500 }); draw(); }),
  hk_run: act(async (a) => { const dry = a.dataset.v === 'dry'; const r = await call('crmf_hook_run', { p_date: null, p_dry: dry }); toast((dry ? T('runPrev') : T('runGo')) + ': ' + pt(dry ? r.due : r.granted)); LY.due = await call('crmf_hooks_due', { p_date: null, p_limit: 500 }); await load('hooks'); }),
  st_go: act(async () => {
    const m = norm(val('st_mobile')); LY.from = val('st_from'); LY.to = val('st_to');
    const r = await sb.from('customers').select('id,name,mobile').eq('mobile', m).limit(1);
    if (!r.data || !r.data[0]) { LY.stmt = null; draw(); return toast(T('notFound')); }
    LY.cust = r.data[0]; LY.stmt = await call('crmf_points_statement', { p_customer: LY.cust.id, p_from: LY.from || null, p_to: LY.to || null }); draw();
  }),
  sm_go: act(async () => { LY.from = val('sm_from'); LY.to = val('sm_to'); LY.sum = await call('crmf_loyalty_summary', { p_from: LY.from || null, p_to: LY.to || null }); draw(); }),
  sv_save: act(async () => {
    const todo = [];
    for (const [k, kind] of SETS) {
      const el = $('#sv_' + k); if (!el) continue; let v;
      if (kind === 'switch') v = el.checked; else if (kind === 'number') { v = nnum(el.value); if (Number.isNaN(v)) throw new Error(ERR.bad_number); } else v = el.value.trim() === '' ? null : el.value.trim();
      if (kind === 'text' && /_from$/.test(k) && v !== null && !/^\d{4}-\d{2}-\d{2}$/.test(v)) throw new Error(ERR.bad_date);      // check everything first: nothing is half saved
      const cur = rv(k); if ((cur === undefined || cur === null ? null : cur) === v || (kind === 'switch' && !!cur === v)) continue;
      todo.push([k, v]);
    }
    for (const [k, v] of todo) await call('set_rule', { p_key: k, p_value: v });
    toast(T('saved')); await load('set');
  }),
});

async function viewLoyalty() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), '<div id="ly_body"><p class="muted">…</p></div>', true);
  try { await load(LY.tab); } catch (e) { fail(e); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { crmloyalty: viewLoyalty });
B.crmf = Object.assign(B.crmf || {}, { info: INFO, settingKeys: SETS.map((s) => s[0]) });
})();
