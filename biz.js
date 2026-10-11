/* Islamia BOS · business analysis: every figure is computed from what staff entered (phase4.sql functions).
   No limit or budget is fixed here: limits are suggested from history and applied only when the owner taps "apply". */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, nm, fmt } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const money = (n) => (n === null || n === undefined ? '—' : '৳ ' + fmt(Math.round(Number(n) * 100) / 100));
const pct = (n, d = 1) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toFixed(d) + '%');
const num = (v) => { const n = Number(String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d))); return Number.isFinite(n) ? n : 0; };
const dhaka = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

B.SETTING_DEFS.push(
  { key: 'fixed_cost_month', group: 'A', label: L('মাসিক স্থির খরচ (ভাড়া, বেতন ইত্যাদি) — ব্রেক-ইভেনের জন্য', 'Monthly fixed costs (rent, salaries etc.) — for break-even'), kind: 'number', unit: '৳' },
  { key: 'anomaly_ratio', group: 'A', label: L('স্টাফ সূচক: সহকর্মীদের মধ্যমার কত গুণ হলে দেখার মতো (যেমন ২)', 'Staff indicators: how many times the peer median counts as worth a look (e.g. 2)'), kind: 'number', unit: '×' });

const X = {
  title: L('ব্যবসার হিসাব', 'Business analysis', 'ব্যবসার Analysis'), period: L('সময়কাল', 'Period', 'Period'), days: L('দিন', 'days', 'days'),
  all: L('সব লোকেশন', 'All locations', 'All Location'), rev: L('বিক্রি (নিট)', 'Sales (net)', 'Sales (Net)'), disc: L('ডিসকাউন্ট', 'Discounts', 'Discount'), voids: L('বাতিল সেল', 'Voided sales', 'Void Sale'),
  avg: L('দৈনিক গড় বিক্রি', 'Average daily sales', 'Daily গড় Sales'), cogs: L('পণ্যের ক্রয়মূল্য (COGS)', 'Cost of goods (COGS)', 'COGS (ক্রয়মূল্য)'), gp: L('মোট মুনাফা', 'Gross profit', 'Gross Profit'),
  gm: L('গ্রস মার্জিন', 'Gross margin', 'Gross Margin'), mk: L('মার্কআপ', 'Markup', 'Markup'),
  costnote: L('হিসাব হয় আইটেম ধরে করা সেলের উপর, আইটেমের বর্তমান ক্রয়মূল্য দিয়ে। কুইক সেলে আইটেম নেই, তাই তার খরচ ধরা হয় না।', 'Calculated on item-wise sales using each item’s current cost price. Quick sales have no item, so no cost is counted for them.', 'হিসাব item-wise sales এর উপর, item এর current ক্রয়মূল্য দিয়ে। Quick sale এ item নেই, তাই cost ধরা হয় না।'),
  uncosted: L('ক্রয়মূল্যহীন বিক্রির অংশ', 'Share of sales without a cost', 'Cost ছাড়া sales এর অংশ'), nocost: L('ক্রয়মূল্য দেখার অনুমতি নেই — মুনাফা দেখানো যাচ্ছে না', 'No permission to see cost price — profit cannot be shown', 'ক্রয়মূল্য দেখার permission নেই — Profit দেখানো যাচ্ছে না'),
  be: L('ব্রেক-ইভেন', 'Break-even', 'Break-even'), beneed: L('মাসিক স্থির খরচ লোকেশন সেটিংসে দিলে এখানে ব্রেক-ইভেন দেখাবে', 'Enter the monthly fixed costs in Location settings to see break-even here', 'Monthly fixed cost Location settings এ দিলে Break-even দেখাবে'),
  bemonth: L('মাসে এত বিক্রি লাগবে', 'Sales needed per month', 'Monthly Sales লাগবে'), beday: L('দিনে গড়ে এত', 'Per day on average', 'Daily গড়ে'), beformula: L('= মাসিক স্থির খরচ ÷ গ্রস মার্জিন (এই সময়ের হার ধরে)', '= monthly fixed costs ÷ gross margin (at this period’s rate)', '= Monthly fixed cost ÷ Gross margin (এই period এর rate)'),
  outlook: L('ক্রয় পরিকল্পনা (আগামী ৭ দিন)', 'Purchase outlook (next 7 days)', 'Purchase Outlook (আগামী ৭ দিন)'), exprev: L('সম্ভাব্য বিক্রি', 'Expected sales', 'Expected Sales'), ratio: L('প্রতি ৳১ বিক্রিতে পণ্যের খরচ', 'Goods cost per ৳1 of sales', '৳১ Sales এ Goods cost'),
  need: L('সম্ভাব্য ক্রয়ের প্রয়োজন (আনুমানিক)', 'Estimated purchase need', 'Estimated Purchase প্রয়োজন'), needhint: L('গত দিনগুলোর একই বারের গড় ধরে হিসাব। এটা পরিকল্পনার অনুমান, সীমা নয়।', 'Based on the average of the same weekday in past days. A planning estimate, not a limit.', 'Past দিনের একই বারের গড় ধরে। এটা Planning estimate, limit নয়।'),
  fewdays: L('এখনও যথেষ্ট দিনের সেল নেই (কমপক্ষে ৭ দিন লাগে) — সংখ্যা ভরসাযোগ্য নয়', 'Not enough days of sales yet (at least 7 needed) — treat numbers with care', 'যথেষ্ট দিনের Sales নেই (কমপক্ষে ৭ দিন) — সংখ্যা ভরসাযোগ্য নয়'),
  pickone: L('এই অংশ দেখতে একটি লোকেশন বাছুন', 'Pick one location to see this part', 'এই অংশ দেখতে একটি Location বাছুন'),
  items: L('আইটেম: কোনটা বেশি টাকা আনছে (A/B/C)', 'Items: what brings the money (A/B/C)', 'Items: কোনটা বেশি টাকা আনছে (A/B/C)'), abc: L('A = প্রথম ৮০% বিক্রি, B = পরের ১৫%, C = বাকি (পারেতো নিয়ম)', 'A = first 80% of sales, B = next 15%, C = the rest (Pareto rule)', 'A = প্রথম ৮০%, B = পরের ১৫%, C = বাকি (Pareto)'),
  unsold: L('এই সময়ে একটিও বিক্রি হয়নি এমন চালু আইটেম', 'Active items with no sale in this period', 'এই সময়ে বিক্রি হয়নি এমন Active item'), qty: L('পরিমাণ', 'Qty', 'Qty'),
  staff: L('স্টাফ সূচক (সহকর্মীদের মধ্যমার সাথে)', 'Staff indicators (vs peer median)', 'Staff Indicators (peer median এর সাথে)'),
  staffnote: L('এগুলো শুধু দেখার সূচক, প্রমাণ নয়। কিছু চোখে পড়লে রেকর্ড মিলিয়ে নিরপেক্ষভাবে দেখুন। তিনজনের কম সহকর্মী থাকলে তুলনা অর্থহীন।', 'These are indicators only, not proof. If something stands out, check the records fairly. With fewer than three peers the comparison means little.', 'এগুলো শুধু Indicator, proof নয়। কিছু চোখে পড়লে records মিলিয়ে দেখুন। তিনজনের কম peer থাকলে তুলনা অর্থহীন।'),
  medhint: L('ছোট ধূসর সংখ্যা = সহকর্মীদের মধ্যমা', 'small grey number = peer median', 'ছোট grey সংখ্যা = peer median'),
  s_disc: L('ডিসকাউন্ট %', 'Discount %', 'Discount %'), s_void: L('বাতিল %', 'Void %', 'Void %'), s_ovr: L('দাম বদল %', 'Price change %', 'Price change %'), s_quick: L('কুইক %', 'Quick %', 'Quick %'), s_due: L('বাকি %', 'Due %', 'Due %'), med: L('মধ্যমা', 'median', 'median'),
  setratio: L('কত গুণ হলে চিহ্নিত হবে সেটা লোকেশন সেটিংসে দিন', 'Set the multiple that counts as unusual in Location settings', 'কত গুণে চিহ্নিত হবে Location settings এ দিন'), look: L('দেখার মতো', 'worth a look', 'worth a look'),
  sugg: L('সীমার পরামর্শ (আপনার আগের খরচ থেকে)', 'Limit suggestions (from your own past expenses)', 'Limit Suggestions (আগের খরচ থেকে)'), sgn: L('ভাউচারের লাইন', 'voucher lines', 'voucher lines'), sgd: L('দিনের হিসাব', 'days of data', 'days of data'),
  sg_single: L('একক খরচের সীমা (৯০% খরচ এর ভেতরে)', 'Single-expense limit (covers 90% of past expenses)', 'Single expense limit (৯০% খরচ এর ভেতরে)'), sg_imp: L('ইমপ্রেস্ট (৯০% দিনে যথেষ্ট)', 'Imprest (enough on 90% of days)', 'Imprest (৯০% দিনে যথেষ্ট)'),
  now: L('এখন', 'Now', 'Now'), apply: L('এটা বসান', 'Apply', 'Apply'), applied: L('সেটিংসে বসানো হয়েছে', 'Saved to settings', 'Settings এ বসানো হয়েছে'), noset: L('(সেটিংসে নেই)', '(not set)', '(set করা নেই)'),
  fewsugg: L('নমুনা কম — এখনই বসানো ঠিক হবে না', 'Few samples — not a good basis yet', 'Sample কম — এখনই বসানো ঠিক নয়'), none: L('এখনও তথ্য নেই', 'No data yet', 'এখনও data নেই'), p90: L('৯০% এর ভেতরে', '90th percentile', '90th percentile'),
  sugghint: L('আপনি "বসান" না চাপা পর্যন্ত কিছুই বদলায় না। সীমা পরে যেকোনো সময় লোকেশন সেটিংসে বদলানো যাবে।', 'Nothing changes until you tap Apply. You can change the limit later in Location settings.', 'Apply না চাপলে কিছু বদলায় না। Limit পরে Location settings এ বদলানো যাবে।'),
};
const T = (k) => lab(X[k]);

const P = { days: 30, loc: '', locs: [] };
const catName = (i) => nm(i);

async function viewBiz() {
  if (!(S.ctx.is_owner || (S.ctx.perms.POS && S.ctx.perms.POS.approve))) return (location.hash = '#/home');
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, true);
  await B.loadStatic();
  const all = B.ENV.locs;
  P.locs = S.ctx.is_owner || S.ctx.roles.includes('management') ? all : all.filter((l) => S.ctx.locations.includes(l.id));
  if (P.loc && !P.locs.find((l) => String(l.id) === String(P.loc))) P.loc = '';
  if (!P.loc && P.locs.length === 1) P.loc = String(P.locs[0].id);
  draw();
}
async function draw() {
  shell(T('title'), `<div class="row wrap" style="margin-bottom:8px">
      <select id="bz_loc" style="flex:1"><option value="">${esc(T('all'))}</option>${P.locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(P.loc) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>
    <div class="row wrap" style="margin-bottom:10px"><span class="muted">${esc(T('period'))}:</span>${[7, 14, 30, 90].map((d) => `<button class="tog ${P.days === d ? 'on' : ''}" data-act="bz_days" data-v="${d}">${d} ${esc(T('days'))}</button>`).join('')}</div>
    <div id="bz_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const td = dhaka(), from = addDays(td, -(P.days - 1)), loc = P.loc ? Number(P.loc) : null;
  const q = (p) => p.then((r) => r, (e) => ({ data: null, error: e }));
  const [dly, itm, stf] = await Promise.all([
    q(sb.rpc('biz_daily', { p_from: from, p_to: td, p_loc: loc })), q(sb.rpc('biz_items', { p_from: from, p_to: td, p_loc: loc })), q(sb.rpc('biz_staff', { p_from: from, p_to: td, p_loc: loc }))]);
  if (dly.error) return fail(dly.error);
  const rows = dly.data || [];
  const sum = (k) => rows.reduce((s, r) => s + Number(r[k] || 0), 0);
  const hasCost = rows.length ? rows[0].cogs !== null : false;
  const rev = sum('revenue'), costed = sum('costed_rev'), cogs = sum('cogs');
  const gp = hasCost ? costed - cogs : null;           // gross profit on the costed part
  const gmRatio = hasCost && costed > 0 ? (costed - cogs) / costed : null;
  const saleDays = new Set(rows.filter((r) => Number(r.revenue) > 0).map((r) => r.sale_date)).size;
  const card = (k, v, sub) => `<div class="card"><div class="muted" style="font-size:.85rem">${esc(k)}</div><div class="mnum">${v}</div>${sub ? `<div class="muted" style="font-size:.8rem">${sub}</div>` : ''}</div>`;
  let h = `<div class="bz-cards">${card(T('rev'), money(rev), saleDays ? `${T('avg')}: ${money(rev / saleDays)}` : '')}
    ${card(T('disc'), money(sum('discount')), rev + sum('discount') > 0 ? pct(100 * sum('discount') / (rev + sum('discount'))) : '')}
    ${card(T('voids'), String(rows.reduce((s, r) => s + Number(r.void_n || 0), 0)), money(sum('void_amt')))}
    ${hasCost ? card(T('gp'), money(gp), `${T('gm')} ${pct(gmRatio === null ? null : 100 * gmRatio)} · ${T('mk')} ${pct(cogs > 0 ? 100 * (costed - cogs) / cogs : null)}`) : card(T('gp'), '—', T('nocost'))}</div>`;
  if (hasCost) h += `<div class="notice ok">${esc(T('costnote'))}${rev > 0 ? ` · ${esc(T('uncosted'))}: ${pct(100 * (1 - costed / rev))}` : ''}</div>`;
  if (saleDays < 7) h += `<div class="notice warn">${esc(T('fewdays'))}</div>`;

  // break-even + outlook + suggestions need one location
  if (!loc) h += `<div class="notice warn">${esc(T('pickone'))}</div>`;
  else {
    const [ls, out, sg] = await Promise.all([
      q(sb.from('location_settings').select('key,value').eq('location_id', loc)), hasCost ? q(sb.rpc('biz_outlook', { p_loc: loc, p_ahead: 7, p_lookback: 28 })) : { data: null },
      S.ctx.is_owner ? q(sb.rpc('biz_suggest', { p_loc: loc, p_days: 90 })) : { data: null }]);
    const st = {}; (ls.data || []).forEach((x) => { st[x.key] = x.value; });
    const fixed = st.fixed_cost_month;
    if (hasCost) {
      h += `<div class="card panel"><h3>${esc(T('be'))}</h3>`;
      if (fixed === null || fixed === undefined || fixed === '') h += `<div class="muted">${esc(T('beneed'))}</div>`;
      else if (!gmRatio || gmRatio <= 0) h += `<div class="notice bad">${esc(T('nocost'))}</div>`;
      else { const m = num(fixed) / gmRatio; h += `<div class="row between"><span>${esc(T('bemonth'))}</span><b class="mnum">${money(m)}</b></div><div class="row between"><span>${esc(T('beday'))}</span><b>${money(m / 30)}</b></div><div class="muted" style="font-size:.8rem">${esc(T('beformula'))}</div>`; }
      h += `</div>`;
      const o = out.data;
      h += `<div class="card panel"><h3>${esc(T('outlook'))}</h3>${o && o.sale_days > 0 ? `
        <div class="row between"><span>${esc(T('exprev'))}</span><b>${money(o.expected_revenue)}</b></div>
        <div class="row between"><span>${esc(T('ratio'))}</span><b>${o.cost_ratio === null ? '—' : '৳ ' + Number(o.cost_ratio).toFixed(2)}</b></div>
        <div class="row between"><span>${esc(T('need'))}</span><b class="mnum">${money(o.est_purchase_need)}</b></div>
        <div class="muted" style="font-size:.8rem">${esc(T('needhint'))}</div>${o.enough ? '' : `<div class="notice warn" style="margin-top:6px">${esc(T('fewdays'))}</div>`}` : `<div class="muted">${esc(T('none'))}</div>`}</div>`;
    }
    if (sg.data) h += sugHTML(sg.data);
    P.cache = { st, loc };
  }

  // items
  if (!itm.error && itm.data) {
    const top = itm.data.filter((i) => i.abc !== '-').slice(0, 10), unsold = itm.data.filter((i) => i.abc === '-');
    h += `<div class="card panel"><h3>${esc(T('items'))}</h3><div class="muted" style="font-size:.8rem">${esc(T('abc'))}</div>
      ${top.map((i) => `<div class="row between perm"><span><span class="chip ${i.abc === 'A' ? 'ok' : i.abc === 'B' ? 'warn' : ''}">${i.abc}</span> ${esc(nm(i))}</span><span style="text-align:right"><b>${money(i.revenue)}</b><div class="muted" style="font-size:.78rem">${T('qty')} ${fmt(i.qty)} · ${pct(i.share_pct)}</div></span></div>`).join('') || `<div class="muted">${esc(T('none'))}</div>`}
      ${unsold.length ? `<details style="margin-top:8px"><summary>${esc(T('unsold'))}: <b>${unsold.length}</b></summary><div class="muted" style="font-size:.9rem">${unsold.map((i) => esc(nm(i))).join(' · ')}</div></details>` : ''}</div>`;
  }
  // staff
  if (!stf.error && stf.data && stf.data.length) {
    const ratio = P.cache && P.cache.st ? num(P.cache.st.anomaly_ratio) : 0;
    const peers = stf.data[0].peers;
    const flag = (v, m) => ratio > 0 && peers >= 3 && v !== null && Number(m) > 0 && Number(v) >= ratio * Number(m);
    const cell = (v, m) => `<td class="${flag(v, m) ? 'hot' : ''}">${pct(v)}<small>${pct(m)}</small></td>`;
    h += `<div class="card panel"><h3>${esc(T('staff'))}</h3><div class="notice ok">${esc(T('staffnote'))}</div>
      <div class="scrollx"><table class="bz"><thead><tr><th></th><th>${esc(T('s_disc'))}</th><th>${esc(T('s_void'))}</th><th>${esc(T('s_ovr'))}</th><th>${esc(T('s_quick'))}</th><th>${esc(T('s_due'))}</th></tr></thead><tbody>
      ${stf.data.map((s) => `<tr><th>${esc(s.staff_id)}<small>${fmt(s.n)} · ${money(s.revenue)}</small></th>${cell(s.discount_pct, s.med_discount_pct)}${cell(s.void_pct, s.med_void_pct)}${cell(s.override_pct, s.med_override_pct)}${cell(s.quick_pct, s.med_quick_pct)}${cell(s.due_pct, s.med_due_pct)}</tr>`).join('')}</tbody></table></div>
      <div class="muted" style="font-size:.8rem">${esc(T('medhint'))}${ratio > 0 ? '' : ' · ' + esc(T('setratio'))}</div></div>`;
  }
  const b = $('#bz_body'); if (b) b.innerHTML = h;
}

function sugHTML(s) {
  const e = s.expense || {}, d = s.daily_total || {};
  const row = (label, sample, val, cur, key) => `<div class="stack" style="margin:8px 0"><div><b>${esc(label)}</b></div>
    <div class="row between"><span>${esc(T('p90'))}: <b class="mnum">${val === null || val === undefined ? '—' : money(val)}</b></span><span class="muted">${sample}</span></div>
    <div class="row between"><span class="muted">${esc(T('now'))}: ${cur === null || cur === undefined ? esc(T('noset')) : money(cur)}</span>
      ${val ? `<button class="primary" data-act="bz_apply" data-k="${key}" data-v="${Math.ceil(Number(val))}">${esc(T('apply'))}</button>` : ''}</div>
    ${sample && Number(sample.split(' ')[0]) < 20 ? `<div class="notice warn">${esc(T('fewsugg'))}</div>` : ''}</div>`;
  return `<div class="card panel"><h3>${esc(T('sugg'))}</h3>
    ${row(T('sg_single'), `${e.n || 0} ${T('sgn')}`, e.p90, s.current_expense_max, 'expense_max')}
    ${row(T('sg_imp'), `${d.days || 0} ${T('sgd')}`, d.p90, s.current_imprest, 'imprest')}
    <div class="muted" style="font-size:.8rem">${esc(T('sugghint'))}</div></div>`;
}

Object.assign(A.H, {
  bz_days: (a) => { P.days = Number(a.dataset.v); draw(); },
  bz_apply: async (a) => {
    const loc = Number(P.loc); if (!loc) return;
    const { error } = await sb.from('location_settings').upsert({ location_id: loc, key: a.dataset.k, value: Number(a.dataset.v) }, { onConflict: 'location_id,key' });
    if (error) return fail(error); toast(T('applied')); draw();
  },
});
document.addEventListener('change', (e) => { if (e.target.id === 'bz_loc') { P.loc = e.target.value; draw(); } });

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { biz: viewBiz });
})();
