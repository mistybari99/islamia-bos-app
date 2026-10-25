/* Islamia BOS · Marketing campaigns and their reports (#/campaigns): the campaign master list, spend by campaign (#164), spend vs sales (#165), campaign revenue and contribution (#166),
   discount campaigns (#167), customer acquisition cost (#169), repeat purchase after a promotion (#170), marketing ROI (#171), and posting 17-1 spend to the books (setting marketing_post_on).
   The server (supabase/phase458..461.sql) does every calculation and every permission check; this page guides and formats. Also the till's optional "campaign / offer code" box
   (B.mkt.posBox / afterSale / queued) that pos.js calls when it is loaded. A campaign is an ordinary list (Add new / Other / retire come from the lists framework). Loaded after rptkit.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab, K = B.rptkit;
const cn = (r) => (r.campaign_code ? (S.lang === 'en' ? (r.name_en || r.name_bn) : (r.name_bn || r.name_en)) || r.campaign_code : lab(L('(ক্যাম্পেইন নেই)', '(no campaign)', '(no campaign)')));
const F = { money: 'money', num: 'num', pct: 'pct', date: 'date', bool: 'bool', place: 'place' };
const c = (k, bn, en, fmt, extra) => Object.assign({ k, label: L(bn, en, en), fmt }, extra || {});
const nameCol = { k: 'name', label: L('ক্যাম্পেইন', 'Campaign', 'Campaign'), get: cn };
const inRange = { dates: true, loc: true };

// ---------- the campaign master list (custom tab) ----------
function master(box, P, ctx) {
  const { esc: e } = ctx;
  box.innerHTML = `<p class="muted" id="cp_m_load">${e(K.X.loading ? lab(K.X.loading) : '')}</p>`;
  sb.from('option_lists').select('*').eq('list_code', 'marketing_campaigns').order('sort').then((r) => {
    const rows = r.error ? [] : (r.data || []); const mgr = K.owner();
    const nm_ = (o) => (S.lang === 'en' ? (o.label_en || o.label_bn) : (o.label_bn || o.label_en));
    box.innerHTML = `${mgr ? `<button class="primary full" id="cp_m_add" data-act="cp_m_edit" data-v="">${e(lab(L('＋ নতুন ক্যাম্পেইন', '＋ New campaign', '＋ New campaign')))}</button>` : `<p class="muted">${e(lab(L('ক্যাম্পেইন যোগ করেন মালিক বা তালিকার দায়িত্বপ্রাপ্ত', 'The owner or the list manager adds campaigns', 'Campaign যোগ করেন Owner বা list manager')))}</p>`}
      ${rows.length ? `<div class="card" style="padding:4px 12px;margin-top:8px" id="cp_m_list">${rows.map((o) => { const x = o.extra || {};
        return `<button class="rp-row mk ${o.active ? '' : 'info'}" data-act="cp_m_edit" data-v="${e(o.value_code)}" style="display:block;width:100%;text-align:start"><span class="nm"><b>${e(nm_(o) || o.value_code)}</b>${o.active ? '' : ` <span class="chip">${e(lab(L('বন্ধ', 'Retired', 'Retired')))}</span>`}
          <small style="display:inline-block;margin-inline-end:10px"><span class="muted">${e(lab(L('শুরু–শেষ', 'Dates', 'Dates')))}:</span> ${e(x.start || '—')} → ${e(x.end || '—')}</small>
          <small style="display:inline-block;margin-inline-end:10px"><span class="muted">${e(lab(L('বাজেট', 'Budget', 'Budget')))}:</span> ${x.budget ? e(String(x.budget)) : '—'}</small>
          ${x.channel ? `<small><span class="muted">${e(lab(L('মাধ্যম', 'Channel', 'Channel')))}:</span> ${e(x.channel)}</small>` : ''}</span></button>`; }).join('')}</div>`
        : `<p class="muted center pad" id="cp_m_empty">${e(lab(L('এখনও কোনো ক্যাম্পেইন নেই', 'No campaign yet', 'এখনও কোনো campaign নেই')))}</p>`}`;
    P.camps = rows;
  });
}
function campSheet(code) {
  const P = K.pages.cp, o = (P.camps || []).find((x) => x.value_code === code), x = (o && o.extra) || {};
  const f = (id, label, v, ph) => `<div><label for="cp_f_${id}">${esc(lab(label))}</label><input id="cp_f_${id}" autocomplete="off" value="${esc(v || '')}" ${ph ? `placeholder="${esc(ph)}"` : ''}></div>`;
  openSheet(`<h2 style="margin-top:0">${esc(lab(o ? L('ক্যাম্পেইন সম্পাদনা', 'Edit campaign', 'Edit campaign') : L('নতুন ক্যাম্পেইন', 'New campaign', 'New campaign')))}</h2><div class="stack" id="cp_m_form">
    ${f('bn', L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), o && o.label_bn)}${f('en', L('ইংরেজি নাম', 'English name', 'English নাম'), o && o.label_en)}
    ${f('start', L('শুরু (YYYY-MM-DD)', 'Start (YYYY-MM-DD)', 'Start (YYYY-MM-DD)'), x.start, '2026-11-01')}${f('end', L('শেষ (YYYY-MM-DD)', 'End (YYYY-MM-DD)', 'End (YYYY-MM-DD)'), x.end)}
    ${f('budget', L('বাজেট ৳ (ফাঁকা = নেই)', 'Budget ৳ (blank = none)', 'Budget ৳ (ফাঁকা = নেই)'), x.budget)}${f('channel', L('মাধ্যম', 'Channel', 'Channel'), x.channel)}${f('note', L('টীকা', 'Note', 'Note'), x.note)}
    <div class="row"><button class="full" data-act="closesheet">${esc(lab(L('বাতিল', 'Cancel', 'Cancel')))}</button><button class="primary full" id="cp_m_save" data-act="cp_m_save" data-v="${esc(code || '')}">${esc(lab(L('সেভ', 'Save', 'Save')))}</button></div></div>`);
}
async function campSave(code) {
  const g = (id) => K.norm((document.getElementById('cp_f_' + id) || {}).value);
  const patch = { name_bn: g('bn'), name_en: g('en'), start: g('start'), end: g('end'), budget: g('budget'), channel: g('channel'), note: g('note') };
  if (!code && !patch.name_bn) return toast(lab(L('বাংলা নাম লিখুন', 'Enter the Bangla name', 'বাংলা নাম লিখুন')));
  let r = await sb.rpc('mkt_campaign_save', { p_value: code || null, p_patch: patch });
  if (!r.error && r.data && r.data.status === 'similar') {
    if (!window.confirm(lab(L('একই রকম নাম আছে। তবুও যোগ করবেন?', 'A similar name exists. Add it anyway?', 'একই রকম নাম আছে। তবুও যোগ করবেন?')))) return;
    r = await sb.rpc('mkt_campaign_save', { p_value: null, p_patch: Object.assign(patch, { force: true }) });
  }
  if (r.error) { const m = r.error.message || ''; if (/end_before_start/.test(m)) return toast(lab(L('শেষের ডেট শুরুর আগে হতে পারে না', 'The end cannot be before the start', 'শেষের Date শুরুর আগে হতে পারে না'))); if (/bad_date|bad_amount/.test(m)) return toast(K.T('badRange')); return fail(r.error); }
  if (r.data && r.data.status && !['added', 'saved'].includes(r.data.status)) return toast(String(r.data.status));
  closeSheet(); toast(lab(L('সংরক্ষিত', 'Saved', 'Saved'))); location.hash = '#/campaigns'; K.pages.cp.tab = 'master'; const v = window.BOS_PAGES.campaigns; v();
}

// ---------- the tabs ----------
const tabs = [
  { k: 'master', label: L('ক্যাম্পেইন তালিকা', 'Campaigns', 'Campaign list'), rpc: null, custom: master, info: { what: L('মার্কেটিং ক্যাম্পেইনের মূল তালিকা: নাম, শুরু–শেষ, বাজেট, মাধ্যম।', 'The master list of marketing campaigns: name, dates, budget and channel.', 'The master list of marketing campaigns.'),
      why: L('১৭-১ খরচ, বিল ও অনলাইন অর্ডার এই তালিকার ক্যাম্পেইনে বাঁধা হয়; নইলে কোনো রিপোর্ট ক্যাম্পেইন ধরে হিসাব করতে পারে না।', 'Form 17-1 lines, bills and online orders point to a campaign here; without it no report can work per campaign.', 'Lines, bills and orders point to a campaign here.') } },
  { k: 'spend', label: L('ক্যাম্পেইন অনুযায়ী খরচ', 'Spend by campaign', 'Spend by campaign'), rpc: 'mkt_spend_by_campaign', exportKey: 'mkt_spend', ...inRange,
    info: { what: L('১৭-১ রেজিস্টারের পরিশোধিত খরচ ক্যাম্পেইন ধরে।', 'The paid amounts of the 17-1 register, by campaign.', 'Paid 17-1 amounts by campaign.'), why: L('কোন প্রচারে কত টাকা গেল এবং বাজেটের কত শতাংশ — তা এক নজরে।', 'See how much each campaign cost and how much of its budget is used.', 'See what each campaign cost.') },
    stats: [{ label: L('মোট খরচ', 'Total spend', 'Total spend'), path: 'totals.spend', fmt: 'money' }, { label: L('টাকা ছাড়া মূল্য', 'Value without payment', 'Value without payment'), path: 'totals.nonpay_value', fmt: 'money' },
      { label: L('ক্যাম্পেইন-বসানো লাইন', 'Lines with a campaign', 'Lines with a campaign'), path: 'coverage.pct', fmt: 'pct', tone: 'info' }],
    tables: [{ title: L('ক্যাম্পেইন', 'Campaigns', 'Campaigns'), path: 'rows', cols: [nameCol, c('spend', 'খরচ', 'Spend', F.money), c('lines', 'লাইন', 'Lines', F.num), c('budget', 'বাজেট', 'Budget', F.money), c('budget_used_pct', 'বাজেটের %', 'Budget used', F.pct), c('first_day', 'প্রথম', 'First', F.date), c('last_day', 'শেষ', 'Last', F.date), c('nonpay_value', 'টাকা ছাড়া', 'No-pay value', F.money)],
        drill: { rpc: 'mkt_spend_lines', args: (r, a) => ({ p_from: a.p_from, p_to: a.p_to, p_loc: a.p_loc, p_campaign: r.campaign_code || '__none', p_limit: 500 }),
          cols: [c('day', 'তারিখ', 'Date', F.date), c('head_name', 'খাত', 'Head', null, { get: (x) => x.head_name || x.head }), c('amt', 'টাকা', 'Amount', F.money), c('source', 'উৎস', 'Source'), c('campaign_txt', 'লেখা নাম', 'Typed name'), c('receipt', 'রসিদ', 'Receipt'), c('status', 'অবস্থা', 'Status'), c('in_books', 'খাতায় আছে', 'In the books', F.bool)] } },
      { title: L('মাস অনুযায়ী', 'By month', 'By month'), path: 'by_month', cols: [c('month', 'মাস', 'Month', F.date), { k: 'camp', label: L('ক্যাম্পেইন', 'Campaign', 'Campaign'), get: (r) => r.campaign_code || lab(L('(নেই)', '(none)', '(none)')) }, c('spend', 'খরচ', 'Spend', F.money)] }],
    panel: (d) => [[L('ক্যাম্পেইন-বসানো টাকা', 'Money with a campaign', 'Money with a campaign'), d.coverage && d.coverage.spend_with_campaign_pct != null ? d.coverage.spend_with_campaign_pct + ' %' : null]] },
  { k: 'vs', label: L('খরচ ও বিক্রি (একই দিন)', 'Spend vs sales', 'Spend vs sales'), rpc: 'mkt_spend_vs_sales', exportKey: 'mkt_vs_sales', ...inRange,
    info: { what: L('একই দিন ও জায়গার মার্কেটিং খরচ আর বিলের মোট, পাশাপাশি।', 'Marketing spend and bill totals of the same day and place, side by side.', 'Spend and sales of the same day.'), why: L('দুটো একসাথে ঘটেছে কি না দেখায়; একটি অন্যটির কারণ — তা বলে না।', 'It shows what happened together, not what caused what.', 'Shows what happened together, not the cause.') },
    stats: [{ label: L('খরচ', 'Spend', 'Spend'), path: 'totals.spend', fmt: 'money' }, { label: L('বিলের মোট', 'Bill totals', 'Bill totals'), path: 'totals.sales_total', fmt: 'money' }, { label: L('চিহ্নিত বিক্রি (ফেরত বাদে)', 'Campaign-tagged net', 'Tagged net'), path: 'totals.campaign_tagged_net', fmt: 'money' }],
    tables: [{ title: L('দিন অনুযায়ী', 'By day', 'By day'), path: 'rows', cols: [c('day', 'তারিখ', 'Date', F.date), c('location_bn', 'জায়গা', 'Place'), c('spend', 'খরচ', 'Spend', F.money), c('sales_total', 'বিক্রি', 'Sales', F.money), c('sales_n', 'বিল', 'Bills', F.num), c('heads', 'খাত', 'Heads'), c('nonpay_value', 'টাকা ছাড়া', 'No-pay value', F.money)] }] },
  { k: 'perf', label: L('ক্যাম্পেইনের বিক্রি ও লাভ', 'Revenue and contribution', 'Revenue & contribution'), rpc: 'mkt_campaign_performance', exportKey: 'mkt_campaign_perf', ...inRange,
    info: { what: L('ক্যাম্পেইন-চিহ্নিত বিলের নিট বিক্রি, ছাড়, এবং খরচ-জানা অংশের লাভ।', 'Net sales and discounts of bills tagged with the campaign, and the contribution on the part whose cost is known.', 'Net sales and contribution of tagged bills.'), why: L('চিহ্নহীন বিক্রি কোনো ক্যাম্পেইনে ধরা হয় না — তাই কত শতাংশ বিল চিহ্নিত তা সবসময় দেখানো হয়।', 'Untagged sales are never guessed into a campaign, so the share of bills with a tag is always shown.', 'Untagged sales are never guessed.') },
    stats: [{ label: L('চিহ্নিত বিল %', 'Bills with a tag', 'Bills tagged'), path: 'coverage.tagged_pct', fmt: 'pct', tone: 'info' }, { label: L('চিহ্নিত বিক্রি %', 'Sales with a tag', 'Sales tagged'), path: 'coverage.tagged_revenue_pct', fmt: 'pct', tone: 'info' }, { label: L('চিহ্নিত নিট বিক্রি', 'Tagged net sales', 'Tagged net sales'), path: 'totals.revenue_net', fmt: 'money' }],
    tables: [{ title: L('ক্যাম্পেইন', 'Campaigns', 'Campaigns'), path: 'rows', cols: [nameCol, c('tagged_bills', 'বিল', 'Bills', F.num), c('revenue_net', 'নিট বিক্রি', 'Net sales', F.money), c('discount_given', 'ছাড়', 'Discount', F.money), c('cogs', 'পণ্যের খরচ', 'Cost of goods', F.money), c('contribution_costed', 'লাভ (খরচ-জানা অংশ)', 'Contribution (costed part)', F.money), c('cost_coverage_pct', 'খরচ জানা %', 'Costed share', F.pct), c('spend', 'খরচ', 'Spend', F.money), c('after_spend_costed', 'খরচের পর', 'After spend', F.money), c('identified_customers', 'পরিচিত গ্রাহক', 'Known customers', F.num)],
        tone: (r) => (r.no_tagged_sales ? 'info' : ''), empty: L('কোনো ক্যাম্পেইন-চিহ্নিত বিল নেই', 'No bill carries a campaign yet', 'কোনো tagged bill নেই'),
        drill: { rpc: 'mkt_campaign_sales', args: (r, a) => ({ p_from: a.p_from, p_to: a.p_to, p_loc: a.p_loc, p_campaign: r.campaign_code, p_limit: 500 }),
          cols: [c('sale_date', 'তারিখ', 'Date', F.date), c('receipt', 'রসিদ', 'Receipt', F.num), c('offer_code', 'কোড', 'Code'), c('total', 'মোট', 'Total', F.money), c('discount', 'ছাড়', 'Discount', F.money), c('ret', 'ফেরত', 'Returned', F.money), c('net', 'নিট', 'Net', F.money), c('customer', 'গ্রাহক', 'Customer')] } }] },
  { k: 'disc', label: L('ছাড়ের ক্যাম্পেইন', 'Discount campaigns', 'Discount campaigns'), rpc: 'mkt_discount_campaigns', exportKey: 'mkt_discount', ...inRange,
    info: { what: L('ছাড়-দেওয়া বিল ক্যাম্পেইন ধরে, ছাড় ছাড়া বিলের গড়ের সাথে।', 'Bills with a discount by campaign, next to the average bill without a discount.', 'Discount bills by campaign.'), why: L('ছাড়ে বড় বিল হচ্ছে কি না দেখতে — তুলনা প্রমাণ নয়।', 'To see whether discounts go with bigger bills - a comparison, not proof.', 'A comparison, not proof.') },
    stats: [{ label: L('ছাড়-ছাড়া বিল', 'Bills without discount', 'Bills without discount'), path: 'baseline_no_discount.bills', fmt: 'num' }, { label: L('ছাড়-ছাড়া বিলের গড়', 'Their average bill', 'Their average bill'), path: 'baseline_no_discount.avg_bill_net', fmt: 'money' }],
    tables: [{ title: L('ক্যাম্পেইন', 'Campaigns', 'Campaigns'), path: 'rows', cols: [nameCol, c('discount_bills', 'ছাড়ের বিল', 'Discount bills', F.num), c('discount_total', 'মোট ছাড়', 'Discount', F.money), c('gross_of_those_bills', 'ছাড়ের আগে', 'Before discount', F.money), c('discount_pct_of_gross', 'ছাড় %', 'Discount %', F.pct), c('avg_bill_net', 'গড় বিল', 'Average bill', F.money), c('offer_code_without_discount', 'কোড আছে, ছাড় নেই', 'Code, no discount', F.num)] }] },
  { k: 'roi', label: L('মার্কেটিং ROI', 'Marketing ROI', 'Marketing ROI'), rpc: 'mkt_roi', exportKey: 'mkt_roi', ...inRange,
    info: { what: L('ক্যাম্পেইনের খরচের বিপরীতে চিহ্নিত বিক্রির লাভ।', 'Contribution of tagged sales against the campaign spend.', 'Contribution against spend.'), why: L('শুধু চিহ্নিত বিল ও ক্যাম্পেইন-বসানো খরচ ধরা হয়; কোনো সংখ্যার উপাদান না থাকলে সংখ্যাটি দেখানো হয় না, কারণ লেখা থাকে।', 'Only tagged bills and campaign-assigned spend are used; when an input is missing the figure is blank and the reason is shown.', 'Blank when an input is missing.') },
    stats: [{ label: L('ক্যাম্পেইন-ছাড়া খরচ (ROI-তে নেই)', 'Unassigned spend (not in ROI)', 'Unassigned spend'), path: 'unassigned_spend_not_in_roi', fmt: 'money' }, { label: L('চিহ্নিত বিল %', 'Bills with a tag', 'Bills tagged'), path: 'coverage.tagged_pct', fmt: 'pct', tone: 'info' }],
    tables: [{ title: L('ক্যাম্পেইন', 'Campaigns', 'Campaigns'), path: 'rows', cols: [nameCol, c('roi_pct_costed_part', 'ROI % (খরচ-জানা অংশ)', 'ROI % (costed part)', F.pct), c('revenue_per_taka', 'প্রতি ৳ খরচে বিক্রি', 'Sales per ৳ spent', F.num), c('revenue_net', 'নিট বিক্রি', 'Net sales', F.money), c('contribution_costed', 'লাভ', 'Contribution', F.money), c('spend', 'খরচ', 'Spend', F.money), c('cost_coverage_pct', 'খরচ জানা %', 'Costed share', F.pct),
        { k: 'why_no_roi', label: L('কেন সংখ্যা নেই', 'Why no figure', 'Why no figure'), get: (r) => (r.why_no_roi ? { no_spend_recorded: lab(L('খরচ লেখা নেই', 'no spend recorded', 'no spend recorded')), no_tagged_sales: lab(L('চিহ্নিত বিক্রি নেই', 'no tagged sales', 'no tagged sales')), cost_hidden: lab(L('খরচ দেখার অধিকার নেই', 'cost hidden', 'cost hidden')), no_costed_sales: lab(L('খরচ-জানা বিক্রি নেই', 'no costed sales', 'no costed sales')) }[r.why_no_roi] : null) }] }] },
  { k: 'cac', label: L('নতুন গ্রাহকের খরচ (CAC)', 'Customer acquisition cost', 'Customer acquisition cost'), rpc: 'mkt_cac', exportKey: 'mkt_cac', ...inRange,
    info: { what: L('মার্কেটিং খরচ ÷ নতুন গ্রাহক, উৎস অনুযায়ী।', 'Marketing spend divided by new customers, by source.', 'Spend / new customers by source.'), why: L('নতুন গ্রাহকের কতজনের "উৎস" লেখা তা সবসময় দেখানো হয়; উৎস না থাকলে খরচ ভাগ করা যায় না।', 'The share of new customers with a source is always shown; without a source the spend cannot be split.', 'Source coverage always shown.') },
    stats: [{ label: L('উৎস লেখা নতুন গ্রাহক', 'New customers with a source', 'With a source'), path: 'coverage.source_pct', fmt: 'pct', tone: 'info' }, { label: L('নতুন গ্রাহক', 'New customers', 'New customers'), path: 'totals.new_customers', fmt: 'num' }, { label: L('মোট খরচ', 'Total spend', 'Total spend'), path: 'totals.marketing_spend', fmt: 'money' }, { label: L('CAC (সব)', 'CAC (all)', 'CAC (all)'), path: 'totals.cac_all', fmt: 'money' }, { label: L('CAC (ক্যাম্পেইন-ধরা)', 'CAC (attributable)', 'CAC (attributable)'), path: 'totals.cac_attributable', fmt: 'money' }],
    tables: [{ title: L('উৎস অনুযায়ী', 'By source', 'By source'), path: 'rows', cols: [{ k: 'source', label: L('উৎস', 'Source', 'Source'), get: (r) => r.source || lab(L('(লেখা নেই)', '(not written)', '(not written)')) }, c('new_customers', 'নতুন গ্রাহক', 'New customers', F.num), { k: 'campaign_code', label: L('ক্যাম্পেইন', 'Campaign', 'Campaign') }, c('campaign_spend', 'ক্যাম্পেইনের খরচ', 'Campaign spend', F.money), c('cac', 'CAC', 'CAC', F.money)] }] },
  { k: 'repeat', label: L('প্রচারের পর আবার কেনা', 'Repeat after a promotion', 'Repeat after a promotion'), rpc: 'mkt_repeat_after_promo', exportKey: 'mkt_repeat', a: {},
    inputs: [{ k: 'days', arg: 'p_days', label: L('প্রচার শেষের পর কত দিন', 'Days after the promotion ended', 'Days after the promotion'), type: 'number', ph: '30', req: false }],
    args: (a) => ({ p_campaign: null, p_days: a.p_days }),
    info: { what: L('যারা প্রচারের বিলে কিনেছে, তাদের কতজন নির্দিষ্ট দিনের মধ্যে আবার কিনেছে।', 'Of the customers who bought on a promotion bill, how many bought again within the days you give.', 'Customers who bought again.'), why: L('দিন-সংখ্যা আপনি লেখেন বা মালিক সেটিংসে দেন; কিছু ধরে নেওয়া হয় না। শেষ না-হওয়া সময়সীমায় শতাংশ দেখানো হয় না।', 'You type the days (or the owner sets them); nothing is assumed. A window not over yet shows no percentage.', 'You type the days.') },
    stats: [{ label: L('দিন', 'Window days', 'Window days'), path: 'window_days', fmt: 'num' }],
    tables: [{ title: L('ক্যাম্পেইন', 'Campaigns', 'Campaigns'), path: 'rows', cols: [nameCol, c('promo_end', 'প্রচার শেষ', 'Promotion end', F.date), c('promo_customers', 'প্রচারের গ্রাহক', 'Promotion customers', F.num), c('repeat_customers', 'আবার কিনেছে', 'Bought again', F.num), c('repeat_pct', 'আবার কেনা %', 'Repeat %', F.pct), c('repeat_pct_so_far', 'এখন পর্যন্ত %', 'So far %', F.pct), c('window_complete', 'সময়সীমা শেষ', 'Window over', F.bool), c('identified_pct', 'পরিচিত বিল %', 'Bills with customer', F.pct)] }] },
  { k: 'post', label: L('খাতায় পোস্ট (১৭-১)', 'Post to the books (17-1)', 'Post 17-1 to books'), rpc: 'mkt_post_preview', exportKey: 'mkt_post', ...inRange,
    info: { what: L('অনুমোদিত ১৭-১ লাইনগুলো খাতায় তোলার আগে ভাগ করে দেখায়; সেটিং চালু থাকলে শুধু "পোস্ট হবে" লাইন পোস্ট হয়।', 'Shows each approved 17-1 line before it is posted; with the setting ON only the "to post" lines are posted.', 'Preview of what would be posted.'), why: L('একই খরচ ১১-১ ভাউচারে থাকলে দুবার ধরা হতো — তাই মিল-থাকা লাইন সিদ্ধান্তের অপেক্ষায় থাকে, ইমপ্রেস্টের লাইন কখনো পোস্ট হয় না।', 'The same spend in a 11-1 voucher would be counted twice, so look-alike lines wait for a decision and imprest lines are never posted.', 'No double counting with 11-1.') },
    stats: [{ label: L('সেটিং', 'Setting', 'Setting'), get: (d) => (d.setting ? (d.setting.on ? lab(L('চালু', 'ON', 'ON')) : lab(L('বন্ধ', 'OFF', 'OFF'))) : null), fmt: 'text' }, { label: L('শুরুর ডেট', 'Posts from', 'Posts from'), path: 'setting.from', fmt: 'text' }],
    beforeTables: (d) => `<div class="row wrap" style="gap:6px;margin:8px 0"><button data-act="cp_post" data-v="dry" id="cp_post_dry">${esc(lab(L('পোস্টের মহড়া (কিছু লেখা হয় না)', 'Dry run (writes nothing)', 'Dry run (writes nothing)')))}</button><button class="primary" data-act="cp_post" data-v="real" id="cp_post_real" ${d.setting && d.setting.on ? '' : 'disabled'}>${esc(lab(L('এখন পোস্ট করুন', 'Post now', 'Post now')))}</button></div><div id="cp_post_out"></div>`,
    tables: [{ title: L('১৭-১ লাইন', '17-1 lines', '17-1 lines'), path: 'rows', cols: [c('day', 'তারিখ', 'Date', F.date), c('cls', 'অবস্থা', 'State', 'lab', { labels: { posted: L('পোস্ট হয়েছে', 'Posted', 'Posted'), to_post: L('পোস্ট হবে', 'To post', 'To post'), skip_imprest: L('ইমপ্রেস্ট — পোস্ট নয়', 'Imprest - not posted', 'Imprest - not posted'), needs_source: L('টাকার উৎস নেই', 'No source of money', 'No source'), owner_money: L('মালিকের টাকা — পোস্ট নয়', 'Owner money - not posted', 'Owner money'), possible_duplicate: L('১০-২-এর সাথে মিল — সিদ্ধান্ত লাগবে', 'Looks like a 11-1 line - decide', 'Looks like 11-1'), decided_skip: L('বাদ দেওয়া হয়েছে', 'Skipped by decision', 'Skipped'), before_start: L('শুরুর ডেটের আগে', 'Before the start date', 'Before start'), not_set_up: L('সেটিং বসানো হয়নি', 'Not set up', 'Not set up'), period_locked: L('মাস বন্ধ', 'Period locked', 'Period locked') } }), c('amt', 'টাকা', 'Amount', F.money), c('head', 'খাত', 'Head'), c('source', 'উৎস', 'Source'), c('serial', 'শিট নং', 'Sheet no.', F.num), c('campaign_code', 'ক্যাম্পেইন', 'Campaign'), c('why', 'কারণ', 'Why')],
        tone: (r) => (r.cls === 'possible_duplicate' ? 'warn' : r.cls === 'posted' ? 'ok' : ''),
        detail: (r) => (r.cls === 'possible_duplicate' || r.decision ? `<div class="row" style="gap:6px;margin-top:8px"><button data-act="cp_dec" data-v="skip" data-e="${esc(r.entry_id)}" data-l="${r.line_no}">${esc(lab(L('বাদ দিন', 'Skip it', 'Skip it')))}</button><button data-act="cp_dec" data-v="post" data-e="${esc(r.entry_id)}" data-l="${r.line_no}">${esc(lab(L('তবুও পোস্ট করুন', 'Post it anyway', 'Post anyway')))}</button></div>` : '') }],
    panel: (d) => [[L('সেটিং চালু', 'Setting ON', 'Setting ON'), d.setting ? String(d.setting.on) : null], [L('হিসাব শুরুর ডেট', 'Accounting start', 'Accounting start'), d.setting && d.setting.accounting_start], [L('অ্যাকাউন্ট ম্যাপিং ঠিক', 'Account mappings present', 'Mappings present'), d.setting ? String(d.setting.mappings_ok) : null]] },
];

const view = K.make({ id: 'cp', route: 'campaigns', title: L('মার্কেটিং ক্যাম্পেইন ও রিপোর্ট', 'Marketing campaigns and reports', 'Marketing campaigns ও reports'), tabs });
Object.assign(H, {
  cp_m_edit: (a) => campSheet(a.dataset.v || null), cp_m_save: (a) => campSave(a.dataset.v || null),
  cp_post: async (a) => {
    const dry = a.dataset.v === 'dry', out = document.getElementById('cp_post_out'); if (out) out.innerHTML = `<p class="muted">${esc(K.T('loading'))}</p>`;
    const r = await sb.rpc('mkt_post_run', { p_dry: dry, p_limit: 200 });
    if (r.error) { const m = r.error.message || ''; if (out) out.innerHTML = `<div class="notice warn mk warn">${esc(/marketing_post_off/.test(m) ? lab(L('সেটিং বন্ধ আছে', 'The setting is OFF', 'Setting বন্ধ')) : /not allowed/.test(m) ? K.T('notAllowed') : m)}</div>`; return; }
    const d = r.data; if (out) out.innerHTML = `<div class="notice ok" id="cp_post_res">${esc(lab(dry ? L('মহড়া', 'Dry run', 'Dry run') : L('পোস্ট হয়েছে', 'Posted', 'Posted')))}: ${d.posted} · ${esc(lab(L('উল্টানো', 'Reversed', 'Reversed')))}: ${d.reversed} · ${esc(lab(L('মাস বন্ধ', 'Period locked', 'Period locked')))}: ${d.period_locked}${d.errors && d.errors.length ? ' · ' + d.errors.length + ' error' : ''}</div>`;
    if (!dry) { closeSheet(); }
  },
  cp_dec: async (a) => {
    const reason = window.prompt(lab(L('কারণ লিখুন (অন্তত ৩ অক্ষর)', 'Write the reason (3 letters at least)', 'কারণ লিখুন (অন্তত 3 অক্ষর)')));
    if (!reason) return;
    const r = await sb.rpc('mkt_post_decide', { p_entry: a.dataset.e, p_line: Number(a.dataset.l), p_decision: a.dataset.v, p_reason: reason });
    if (r.error) return fail(r.error); closeSheet(); toast(lab(L('সংরক্ষিত', 'Saved', 'Saved'))); window.BOS_PAGES.campaigns();
  },
});

// ---------- the till: optional campaign / offer code (pos.js calls these when this file is loaded) ----------
const PS = { camps: null, camp: '', code: '' };
const QK = 'bos_mkt_pending';
const qget = () => { try { return JSON.parse(localStorage.getItem(QK) || '[]'); } catch (e) { return []; } };
const qset = (v) => { try { localStorage.setItem(QK, JSON.stringify(v)); } catch (e) { /* storage blocked: the tag is simply not retried */ } };
async function loadCamps() { try { const r = await sb.rpc('mkt_active_campaigns'); PS.camps = r && !r.error && Array.isArray(r.data) ? r.data : []; } catch (e) { PS.camps = []; } }
async function flushTags() {
  const q = qget(); if (!q.length || !navigator.onLine) return; const keep = [];
  for (const t of q) { const r = await sb.rpc('mkt_tag_sale_client', { p_client: t.client, p_campaign: t.camp || null, p_offer: t.code || null }); if (r.error && !/sale_not_found|unknown_campaign|bad_offer_code|nothing_to_tag|tag_change_needs_approver|sale_not_done/.test(r.error.message || '')) keep.push(t); }
  qset(keep);
}
window.addEventListener('online', flushTags); setInterval(flushTags, 30000);
B.mkt = {
  prefetch: loadCamps,
  posBox() {
    PS.camp = ''; PS.code = '';
    const opts = (PS.camps || []).map((x) => `<option value="${esc(x.code)}">${esc(S.lang === 'en' ? (x.name_en || x.name_bn) : (x.name_bn || x.name_en))}</option>`).join('');
    return `<details id="cart_mkt" style="margin:8px 0"><summary>${esc(lab(L('ক্যাম্পেইন / অফার কোড (ঐচ্ছিক)', 'Campaign / offer code (optional)', 'Campaign / offer code (optional)')))}</summary><div class="stack" style="margin-top:6px">
      ${opts ? `<select id="mkt_camp" aria-label="${esc(lab(L('ক্যাম্পেইন', 'Campaign', 'Campaign')))}"><option value="">—</option>${opts}</select>` : ''}
      <input id="mkt_code" autocomplete="off" maxlength="30" placeholder="${esc(lab(L('অফার কোড', 'Offer code', 'Offer code')))}" aria-label="${esc(lab(L('অফার কোড', 'Offer code', 'Offer code')))}">
      <small class="muted">${esc(lab(L('কোড শুধু বিলে চিহ্ন হিসেবে থাকে; ছাড় আলাদা বাক্সে দিন।', 'The code is only a label on the bill; give any discount in the discount box.', 'Code is only a label on the bill.')))}</small></div></details>`;
  },
  current: () => ({ camp: PS.camp, code: PS.code }),
  async afterSale(saleId) {
    const camp = PS.camp, code = K.norm(PS.code).toUpperCase(); PS.camp = ''; PS.code = '';
    if (!saleId || (!camp && !code)) return;
    const r = await sb.rpc('mkt_tag_sale', { p_sale: saleId, p_campaign: camp || null, p_offer: code || null });
    if (r.error) toast(lab(L('ক্যাম্পেইন চিহ্ন বসেনি: ', 'Campaign tag not saved: ', 'Campaign tag বসেনি: ')) + (r.error.message || ''));
    else if (r.data && r.data.outside_campaign_dates) toast(lab(L('বিলটি ক্যাম্পেইনের ডেটের বাইরে', 'This bill is outside the campaign dates', 'Bill campaign dates-এর বাইরে')));
  },
  queued(client) {
    const camp = PS.camp, code = K.norm(PS.code).toUpperCase(); PS.camp = ''; PS.code = '';
    if (client && (camp || code)) qset(qget().concat([{ client, camp, code }]));
  },
};
document.addEventListener('click', (e) => { if (e.target && e.target.closest && e.target.closest('[data-act="closesheet"]')) { PS.camp = ''; PS.code = ''; } });
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'mkt_camp') PS.camp = e.target.value; });
document.addEventListener('input', (e) => { if (e.target && e.target.id === 'mkt_code') PS.code = e.target.value; });
setTimeout(() => { try { if (S.ctx) loadCamps(); } catch (x) { /* not signed in yet */ } }, 2500);
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { campaigns: view });
})();
