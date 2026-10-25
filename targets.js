/* Islamia BOS · Targets, KPI and comparison (#/targets), package RPT-B4 / R5 and R9. Three tabs:
   target vs achievement (#9 #24) with the owner's target entry · KPI trends and exception alerts (#10) from the daily snapshots · factory vs retail (#7).
   Server: supabase/phase409.sql (sales_targets, kpi_snapshots, sales_target_set / retire / list), phase410.sql (rb4_target_report, kpi_snapshot_take, rb4_kpi_trend), phase415.sql (the transfer valuation setting),
   phase416.sql (rb4_factory_vs_retail, rb4_log_export). The owner board tile is a widget in web/ownerboard.js (rb4_target_tile, phase411.sql).
   No target, no limit and no transfer value is ever invented: a missing one is "data not captured: <field>" / "target not set" / "not valued". Targets are set by the owner (or the grant sales_target_manage).
   Paper form code of the target entry: to be given by owner. Built on web/rb4common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!B || !B.rb4) return;
const { sb, esc, toast, fail, openSheet, closeSheet, nm } = A;
const R = B.rb4, L = R.L, lab = R.lab;
const $ = (s, el = document) => el.querySelector(s);
const L_ = {
  title: L('লক্ষ্য, KPI ও তুলনা', 'Targets, KPI & comparison', 'Target, KPI ও comparison'), tTarget: L('লক্ষ্য বনাম অর্জন', 'Target vs achievement', 'Target vs achievement'), tKpi: L('KPI ধারা ও সতর্কতা', 'KPI trends & alerts', 'KPI trend ও alert'), tCmp: L('কারখানা বনাম খুচরা', 'Factory vs retail', 'Factory vs retail'),
  status: L('অবস্থা', 'Status', 'Status'), month: L('মাস', 'Month', 'Month'), target: L('লক্ষ্য', 'Target', 'Target'), achieved: L('অর্জন', 'Achieved', 'Achieved'), ach: L('অর্জন %', 'Achievement %', 'Achievement %'), shortfall: L('বাকি', 'Shortfall', 'Shortfall'),
  pace: L('এ পর্যন্ত যা হওয়ার কথা %', 'Pace %', 'Pace %'), paceAmt: L('এ পর্যন্ত যা হওয়ার কথা', 'Pace amount', 'Pace amount'), gpT: L('লাভের লক্ষ্য %', 'GP target %', 'GP target %'), gp: L('লাভ %', 'GP %', 'GP %'), gpGap: L('লাভের ফারাক (পয়েন্ট)', 'GP gap (points)', 'GP gap (points)'),
  uncosted: L('খরচ জানা নেই এমন বিক্রি %', 'Uncosted sales %', 'Uncosted sales %'), gross: L('মোট বিক্রি', 'Gross sales', 'Gross sales'), returns: L('ফেরত', 'Returns', 'Returns'), bills: L('বিল', 'Bills', 'Bills'),
  s_target_not_set: L('লক্ষ্য ঠিক নেই', 'target not set', 'target ঠিক নেই'), s_not_started: L('শুরু হয়নি', 'not started', 'not started'), s_closed_met: L('মাস শেষ — পূরণ', 'closed — met', 'closed — met'), s_closed_missed: L('মাস শেষ — পূরণ হয়নি', 'closed — missed', 'closed — missed'),
  s_met: L('পূরণ', 'met', 'met'), s_on_track: L('ঠিক পথে', 'on track', 'on track'), s_behind: L('পিছিয়ে', 'behind', 'behind'),
  fTarget: L('বিক্রির লক্ষ্য', 'sales target', 'sales target'), fCost: L('খরচ', 'cost', 'cost'), fGpTarget: L('লাভের লক্ষ্য', 'gross-profit target', 'GP target'),
  setTarget: L('লক্ষ্য ঠিক করুন', 'Set a target', 'Target ঠিক করুন'), changeTarget: L('লক্ষ্য বদলান', 'Change this target', 'Target বদলান'), retire: L('লক্ষ্য বাতিল', 'Retire this target', 'Target retire'), amount: L('টাকার লক্ষ্য', 'Target amount', 'Target amount'),
  gpPct: L('লাভের লক্ষ্য % (ঐচ্ছিক)', 'Gross-profit target % (optional)', 'GP target % (optional)'), monthF: L('মাস', 'Month', 'Month'), noteF: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (optional)'), ownerOnly: L('লক্ষ্য শুধু মালিক বা অনুমতিপ্রাপ্ত ঠিক করেন', 'Targets are set by the owner or a holder of the right', 'Target owner বা permission-holder ঠিক করেন'),
  // KPI
  snap: L('স্ন্যাপশট নিন', 'Take snapshots', 'Snapshot নিন'), snapDone: L('স্ন্যাপশট নেওয়া হয়েছে', 'Snapshots taken', 'Snapshot নেওয়া হয়েছে'), snapNote: L('গতকাল পর্যন্ত বন্ধ হওয়া দিনের সংখ্যা সেভ হয়। আগে নেওয়া দিন বদলায় না।', 'Closed days up to yesterday are kept. A day taken earlier is not changed.', 'গতকাল পর্যন্ত closed দিন save হয়। আগের দিন বদলায় না।'),
  missingDays: L('স্ন্যাপশট নেই এমন দিন', 'Days without a snapshot', 'Snapshot নেই এমন দিন'), alerts: L('সতর্কতা', 'Alerts', 'Alerts'), days: L('দিন অনুযায়ী', 'Per day', 'Per day'), places: L('জায়গা অনুযায়ী', 'Per place', 'Per place'),
  a_sales_drop: L('বিক্রি কমেছে', 'sales drop', 'sales drop'), a_discount_high: L('ডিসকাউন্ট বেশি', 'discount high', 'discount high'), a_void_high: L('বাতিল বেশি', 'voids high', 'voids high'), kind: L('ধরন', 'Kind', 'Kind'), day: L('দিন', 'Day', 'Day'), place: L('জায়গা', 'Place', 'Place'),
  value: L('মান', 'Value', 'Value'), ref: L('আগের ৪ একই বারের গড়', 'Average of the 4 same weekdays', 'Avg of 4 same weekdays'), limit: L('মালিকের সীমা', 'Owner limit', 'Owner limit'), dropPct: L('কমেছে %', 'Drop %', 'Drop %'), refDays: L('তুলনার দিন', 'Days compared', 'Days compared'),
  net: L('নিট বিক্রি', 'Net sales', 'Net sales'), avgBill: L('গড় বিল', 'Average bill', 'Avg bill'), discPct: L('ডিসকাউন্ট %', 'Discount %', 'Discount %'), voids: L('বাতিল বিক্রি', 'Voids', 'Voids'), runs: L('উৎপাদন রান', 'Production runs', 'Prod runs'), yieldV: L('ফলন পার্থক্য %', 'Yield variance %', 'Yield var %'), cover: L('জায়গা', 'Places', 'Places'),
  exc: L('খোলা গরমিল', 'Open exceptions', 'Open exceptions'), red: L('লাল', 'red', 'red'), yellow: L('হলুদ', 'yellow', 'yellow'), openExc: L('গরমিল দেখুন', 'Open exceptions', 'Exceptions খুলুন'), limits: L('মালিকের সীমা', 'Owner limits', 'Owner limits'),
  salesDrop: L('বিক্রি কমলে %', 'Sales drop %', 'Sales drop %'), discHigh: L('ডিসকাউন্ট %', 'Discount %', 'Discount %'), voidHigh: L('বাতিল সংখ্যা', 'Void count', 'Void count'), fLimit: L('সীমা', 'limit', 'limit'), settingsHint: L('সীমা বদলাতে: সেটিংস → নিয়ম (রিপোর্ট)', 'Change limits in Settings → Rules (reports)', 'Limit বদলাতে: Settings → Rules (reports)'),
  // compare
  basis: L('পাঠানো মালের দাম ধরার নিয়ম', 'Transfer valuation basis', 'Transfer valuation basis'), b_none: L('ধরা হয়নি (মালিকের সেটিং)', 'not valued (owner setting)', 'not valued (owner setting)'), b_cost: L('কারখানার খরচে', 'at factory cost', 'at factory cost'), b_price_pct: L('বিক্রয়মূল্যের শতাংশে', 'a % of the selling price', 'selling price-এর %'),
  factory: L('কারখানা', 'Factory', 'Factory'), transfers: L('কারখানা → শোরুম', 'Factory → shops', 'Factory → shops'), retail: L('শোরুম', 'Shops', 'Shops'), item: L('পণ্য', 'Item', 'Item'), runs2: L('রান', 'Runs', 'Runs'), output: L('উৎপাদন', 'Output', 'Output'), prodCost: L('উৎপাদন খরচ', 'Production cost', 'Production cost'),
  sent: L('পাঠানো', 'Sent', 'Sent'), recd: L('গ্রহণ', 'Received', 'Received'), transit: L('পথে', 'In transit', 'In transit'), costVal: L('মালের খরচ', 'Cost of the goods', 'Cost of goods'), trVal: L('ধরা দাম', 'Transfer value', 'Transfer value'), margin: L('কারখানার মার্জিন', 'Factory margin', 'Factory margin'),
  cogs: L('বিক্রিত মালের খরচ', 'Cost of goods sold', 'COGS'), gprofit: L('মোট লাভ', 'Gross profit', 'Gross profit'), vs_not_valued: L('দাম ধরা হয়নি', 'not valued', 'not valued'), vs_cost: L('খরচে', 'at cost', 'at cost'), vs_price_pct: L('বিক্রয়মূল্যের %', '% of price', '% of price'),
  vs_pct_not_set: L('শতাংশ ঠিক নেই', 'percentage not set', 'percentage ঠিক নেই'), vs_price_not_captured: L('বিক্রয়মূল্য লেখা নেই', 'selling price not captured', 'selling price লেখা নেই'), vs_cost_not_captured: L('খরচ লেখা নেই', 'cost not captured', 'cost লেখা নেই'),
  cs_known: L('জানা', 'known', 'known'), tot: L('মোট', 'Totals', 'Totals'), shopsNoCost: L('খরচ ছাড়া শোরুম', 'Shops without a cost', 'Shops without cost'),
};
const st = (o) => o;
const mnth = (r) => R.d10(r.month).slice(0, 7);
const filt = (D) => ({ p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null });
const gpMiss = (r) => (r.gp_state === 'cost_hidden' ? '' : r.gp_state === 'cost_not_captured' ? L_.fCost : r.gp_state === 'gp_target_not_set' ? L_.fGpTarget : '');
const valMiss = (r) => (r.value_state === 'cost_hidden' ? '' : r.value_state === 'not_valued' ? L_.vs_not_valued : r.value_state === 'cost_not_captured' ? L_.fCost : r.value_state === 'pct_not_set' ? L_.vs_pct_not_set : r.value_state === 'price_not_captured' ? L_.vs_price_not_captured : '');
const costMiss = (r) => (r.cost_state === 'cost_hidden' ? '' : L_.fCost);
const base = (r) => r.base_unit;
const place = { l: L_.place, get: (r) => R.locName(r), w: 't' };

const tabs = [
  { id: 'target', label: L_.tTarget, rpc: 'rb4_target_report', args: (D) => ({ p_from_month: D.from, p_to_month: D.to, p_loc: D.loc ? Number(D.loc) : null }), filters: ['date', 'loc'], csvKey: 'target_report', csvName: 'target-vs-achievement',
    top: (d, D) => `${D.canTarget ? `<button type="button" class="primary full" data-act="tg_new">${esc(lab(L_.setTarget))}</button><p class="muted">${esc(lab(R.X.paperCode))}</p>` : `<p class="muted">${esc(lab(L_.ownerOnly))}</p>`}`,
    blocks: [{ title: null, rows: (d) => d.rows, status: { target_not_set: L_.s_target_not_set, not_started: L_.s_not_started, closed_met: L_.s_closed_met, closed_missed: L_.s_closed_missed, met: L_.s_met, on_track: L_.s_on_track, behind: L_.s_behind },
      warn: (r) => ['behind', 'closed_missed', 'target_not_set'].includes(r.status),
      detail: (r, d) => (r.target_id && window.__tgCanEdit ? `<div class="row wrap"><button type="button" class="mini" data-act="tg_edit" data-loc="${r.location_id}" data-m="${R.d10(r.month)}" data-amt="${r.target ?? ''}" data-gp="${r.gp_target_pct ?? ''}">${esc(lab(L_.changeTarget))}</button><button type="button" class="mini" data-act="tg_retire" data-id="${r.target_id}">${esc(lab(L_.retire))}</button></div>` : (!r.target_id && window.__tgCanEdit ? `<button type="button" class="mini" data-act="tg_edit" data-loc="${r.location_id}" data-m="${R.d10(r.month)}" data-amt="" data-gp="">${esc(lab(L_.setTarget))}</button>` : '')),
      cols: [place, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.month, get: (r) => mnth(r), w: 's' },
        { l: L_.target, get: (r) => r.target, f: 'money', nc: L_.fTarget }, { l: L_.achieved, get: (r) => r.achieved, f: 'money' }, { l: L_.ach, get: (r) => r.achievement_pct, f: 'pct' }, { l: L_.shortfall, get: (r) => r.shortfall, f: 'money' },
        { l: L_.pace, get: (r) => r.pace_pct, f: 'pct' }, { l: L_.paceAmt, get: (r) => r.pace_amount, f: 'money' }, { l: L_.gpT, get: (r) => r.gp_target_pct, f: 'pct', miss: (r) => (r.target_id ? L_.fGpTarget : '') },
        { l: L_.gp, get: (r) => r.gp_pct, f: 'pct', miss: gpMiss }, { l: L_.gpGap, get: (r) => r.gp_gap_pp, f: 'q4', miss: gpMiss }, { l: L_.uncosted, get: (r) => r.uncosted_pct, f: 'pct', miss: (r) => '' },
        { l: L_.gross, get: (r) => r.gross_sales, f: 'money' }, { l: L_.returns, get: (r) => r.returns, f: 'money' }, { l: L_.bills, get: (r) => r.bills, f: 'int' }] }] },
  { id: 'kpi', label: L_.tKpi, rpc: 'rb4_kpi_trend', args: filt, filters: ['date', 'loc'], csvKey: 'kpi_trend', csvName: 'kpi-trend',
    top: (d, D) => `<div class="card"><b>${esc(lab(L_.exc))}</b>: ${esc(lab(L_.red))} <b>${d.open_exceptions ? d.open_exceptions.red : '—'}</b> · ${esc(lab(L_.yellow))} <b>${d.open_exceptions ? d.open_exceptions.yellow : '—'}</b> ${R.go('#/exceptions', lab(L_.openExc))}</div>
      <div class="card"><b>${esc(lab(L_.limits))}</b>: ${esc(lab(L_.salesDrop))} <b>${d.limits.sales_drop_pct ?? esc(R.NC(L_.fLimit))}</b> · ${esc(lab(L_.discHigh))} <b>${d.limits.discount_pct ?? esc(R.NC(L_.fLimit))}</b> · ${esc(lab(L_.voidHigh))} <b>${d.limits.void_n ?? esc(R.NC(L_.fLimit))}</b><div class="muted">${esc(lab(L_.settingsHint))}</div></div>
      <div class="card"><b>${esc(lab(L_.missingDays))}</b>: ${(d.missing_days || []).length}${(d.missing_days || []).length ? ` <span class="muted">(${esc((d.missing_days || []).slice(0, 5).join(', '))}${(d.missing_days || []).length > 5 ? ' …' : ''})</span>` : ''}<div class="muted">${esc(lab(L_.snapNote))}</div><button type="button" class="full" data-act="tg_snap">${esc(lab(L_.snap))}</button></div>`,
    blocks: [
      { title: L_.alerts, rows: (d) => d.alerts, status: { sales_drop: L_.a_sales_drop, discount_high: L_.a_discount_high, void_high: L_.a_void_high }, warn: () => true,
        cols: [place, { l: L_.kind, get: (r) => r.kind, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, { l: L_.value, get: (r) => r.value, f: 'q4' }, { l: L_.ref, get: (r) => r.reference, f: 'q4' }, { l: L_.dropPct, get: (r) => r.drop_pct, f: 'pct' }, { l: L_.refDays, get: (r) => r.reference_days, f: 'int' }, { l: L_.limit, get: (r) => r.limit, f: 'q4' }] },
      { title: L_.days, rows: (d) => d.days, cols: [{ l: L_.day, get: (r) => r.day, f: 'date', w: 't' }, { l: L_.cover, get: (r) => r.places_covered, f: 'int', w: 'c' }, { l: L_.net, get: (r) => r.net_sales, f: 'money' }, { l: L_.bills, get: (r) => r.bills, f: 'int' }, { l: L_.avgBill, get: (r) => r.avg_bill, f: 'money' },
        { l: L_.discPct, get: (r) => r.discount_pct, f: 'pct' }, { l: L_.voids, get: (r) => r.void_n, f: 'int' }, { l: L_.runs, get: (r) => r.runs_n, f: 'int' }, { l: L_.yieldV, get: (r) => r.yield_var_pct, f: 'pct' }] },
      { title: L_.places, rows: (d) => d.places, cols: [place, { l: L_.days, get: (r) => r.days, f: 'int', w: 'c' }, { l: L_.net, get: (r) => r.net_sales, f: 'money' }, { l: L_.bills, get: (r) => r.bills, f: 'int' }, { l: L_.avgBill, get: (r) => r.avg_bill, f: 'money' }, { l: L_.discPct, get: (r) => r.discount_pct, f: 'pct' }, { l: L_.voids, get: (r) => r.void_n, f: 'int' }] }] },
  { id: 'cmp', label: L_.tCmp, rpc: 'rb4_factory_vs_retail', args: (D) => ({ p_from: D.from, p_to: D.to }), filters: ['date'], csvKey: 'factory_vs_retail', csvName: 'factory-vs-retail',
    top: (d) => `<div class="card"><b>${esc(lab(L_.basis))}</b>: ${esc(lab(L_['b_' + d.basis] || L_.b_none))}${d.basis === 'price_pct' ? ` · ${d.price_pct === null || d.price_pct === undefined ? esc(R.NC('transfer_price_pct')) : R.pct(d.price_pct)}` : ''}
      <div class="muted">${esc(lab(L_.tot))}: ${esc(lab(L_.costVal))} ${R.money(d.transfers.totals.cost_value)} · ${esc(lab(L_.trVal))} ${d.transfers.totals.transfer_value === null || d.transfers.totals.transfer_value === undefined ? esc(lab(L_.vs_not_valued)) : R.money(d.transfers.totals.transfer_value)} · ${esc(lab(L_.margin))} ${d.transfers.totals.factory_margin === null || d.transfers.totals.factory_margin === undefined ? esc(lab(L_.vs_not_valued)) : R.money(d.transfers.totals.factory_margin)} · ${esc(lab(L_.gprofit))} (${esc(lab(L_.retail))}) ${R.money(d.retail.totals.gross_profit)}</div></div>`,
    blocks: [
      { title: L_.factory, rows: (d) => d.factory.rows, cols: [{ l: L_.item, get: (r) => R.itemName(r), w: 't' }, { l: L_.place, get: (r) => R.locName(r), w: 's' }, { l: L_.runs2, get: (r) => r.runs, f: 'int', w: 'c' }, { l: L_.output, get: (r) => r.output, f: 'q4', unit: base }, { l: L_.prodCost, get: (r) => r.production_cost, f: 'money', miss: costMiss }] },
      { title: L_.transfers, rows: (d) => d.transfers.rows, cols: [{ l: L_.item, get: (r) => R.itemName(r), w: 't' }, { l: L_.place, get: (r) => R.locName(r, 'from_location') + ' → ' + R.locName(r, 'to_location'), w: 's' }, { l: L_.sent, get: (r) => r.sent, f: 'q4', unit: base, w: 'c' }, { l: L_.recd, get: (r) => r.received, f: 'q4', unit: base },
        { l: L_.transit, get: (r) => r.in_transit, f: 'q4', unit: base }, { l: L_.costVal, get: (r) => r.cost_value, f: 'money', miss: costMiss }, { l: L_.trVal, get: (r) => r.transfer_value, f: 'money', miss: valMiss }, { l: L_.margin, get: (r) => r.margin, f: 'money', miss: valMiss }] },
      { title: L_.retail, rows: (d) => d.retail.rows, cols: [place, { l: L_.net, get: (r) => r.net_sales, f: 'money', w: 'c' }, { l: L_.gross, get: (r) => r.gross_sales, f: 'money' }, { l: L_.returns, get: (r) => r.returns, f: 'money' }, { l: L_.bills, get: (r) => r.bills, f: 'int' },
        { l: L_.cogs, get: (r) => r.cogs, f: 'money', miss: costMiss }, { l: L_.gprofit, get: (r) => r.gross_profit, f: 'money', miss: costMiss }, { l: L_.gp, get: (r) => r.gp_pct, f: 'pct', miss: costMiss }, { l: L_.uncosted, get: (r) => r.uncosted_pct, f: 'pct', miss: () => '' }] }] },
];

R.page({ route: 'targets', act: 'tgp', title: L_.title, tabs, range: 'days30',
  init: async (D) => {
    try { const r = await sb.rpc('sales_target_list', { p_from: R.monthStart(R.today()), p_to: R.monthStart(R.today()), p_loc: null, p_with_retired: false }); D.canTarget = !!(r && r.data && r.data.can_edit); } catch (e) { D.canTarget = false; }
    window.__tgCanEdit = D.canTarget;
    D.from = R.monthStart(R.today());
  },
  handlers: (D, api) => {
    const sheet = (o) => {
      const o2 = o || {};
      openSheet(`<h2>${esc(lab(L_.setTarget))}</h2><div class="stack"><p class="muted">${esc(lab(R.X.paperCode))}</p>
        <div><label for="tg_loc">${esc(lab(R.X.place))}</label>${R.placeSel(D, 'tg_loc', o2.loc || '', false)}</div>
        <div><label for="tg_month">${esc(lab(L_.monthF))}</label><input id="tg_month" type="month" value="${esc((o2.m || R.today()).slice(0, 7))}"></div>
        <div><label for="tg_amt">${esc(lab(L_.amount))}</label><input id="tg_amt" inputmode="decimal" autocomplete="off" value="${esc(o2.amt ?? '')}"></div>
        <div><label for="tg_gp">${esc(lab(L_.gpPct))}</label><input id="tg_gp" inputmode="decimal" autocomplete="off" value="${esc(o2.gp ?? '')}"></div>
        <div><label for="tg_note">${esc(lab(L_.noteF))}</label><input id="tg_note" maxlength="300" autocomplete="off"></div>
        <div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="primary full" data-act="tg_save">${esc(lab(R.X.save))}</button></div></div>`);
    };
    const act = async (p, ok) => { if (D.busy) return; D.busy = true; try { const r = await p; if (r.error) return toast(R.errText(r.error)); closeSheet(); toast(lab(R.X.saved)); await ok(r.data || {}); } catch (e) { fail(e); } finally { D.busy = false; } };
    return {
      tg_new: () => sheet({ m: R.today() }),
      tg_edit: (a) => { closeSheet(); setTimeout(() => sheet({ loc: a.dataset.loc, m: a.dataset.m, amt: a.dataset.amt, gp: a.dataset.gp }), 0); },
      tg_save: () => {
        const loc = Number(($('#tg_loc') || {}).value), m = ($('#tg_month') || {}).value, amt = R.nnum(($('#tg_amt') || {}).value), gpRaw = R.norm(($('#tg_gp') || {}).value), gp = gpRaw === '' ? null : R.nnum(gpRaw);
        if (!loc) return toast(lab(R.X.place) + '?'); if (!m) return toast(lab(R.ERR.bad_date)); if (!(amt >= 0)) return toast(lab(R.ERR.bad_amount)); if (gp !== null && !(gp >= 0 && gp <= 100)) return toast(lab(R.ERR.bad_gp_pct));
        return act(sb.rpc('sales_target_set', { p_loc: loc, p_month: m + '-01', p_amount: amt, p_gp_pct: gp, p_note: (($('#tg_note') || {}).value || '').trim() || null }), () => api.run());
      },
      tg_retire: (a) => {
        closeSheet(); D.retireId = a.dataset.id;
        setTimeout(() => openSheet(`<h2>${esc(lab(L_.retire))}</h2><div class="stack"><div><label for="tg_why">${esc(lab(R.X.why))}</label><input id="tg_why" maxlength="300" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="danger full" data-act="tg_rgo">${esc(lab(L_.retire))}</button></div></div>`), 0);
      },
      tg_rgo: () => { const n = (($('#tg_why') || {}).value || '').trim(); if (n.length < 3) return toast(lab(R.ERR.note_required)); return act(sb.rpc('sales_target_retire', { p_id: Number(D.retireId), p_note: n }), () => api.run()); },
      tg_snap: async (a) => {
        if (D.busy) return; D.busy = true; if (a) a.disabled = true;
        try {
          const yest = R.daysAgo(1); let f = D.from, t = D.to < yest ? D.to : yest, n = 0;
          if (t < f) { toast(lab(R.ERR.day_not_closed)); return; }
          while (f <= t) {
            const e = new Date(new Date(f + 'T12:00:00Z').getTime() + 99 * 86400000).toISOString().slice(0, 10), end = e < t ? e : t;
            const r = await sb.rpc('kpi_snapshot_take', { p_from: f, p_to: end, p_redo: false }); if (r.error) { toast(R.errText(r.error)); return; }
            n += (r.data && r.data.rows_written) || 0; f = new Date(new Date(end + 'T12:00:00Z').getTime() + 86400000).toISOString().slice(0, 10);
          }
          toast(lab(L_.snapDone) + ' (' + n + ')'); await api.run();
        } catch (e) { fail(e); } finally { D.busy = false; if (a) a.disabled = false; }
      },
    };
  } });
})();
