/* Islamia BOS · Production reports (#/prodreports), package RPT-B4 / R4. One screen, eight tabs, all read only:
   plan vs actual (#40) · order status and pending (#52) · made-sent-received-in transit-short (#53) · standard vs actual cost with the price / usage / yield split (#33 #43 #55) ·
   real use against the recipe (#44) · run-level yield (#45) · reject / rework (#49) · wastage with the batch and run dimension (#50).
   Server: supabase/phase406.sql .. phase408.sql (rb4_plan_vs_actual, rb4_order_status, rb4_dispatch_recon, rb4_cost_variance, rb4_consumption_vs_recipe, rb4_run_yield, rb4_losses, rb4_wastage_dim)
   and phase416.sql (rb4_log_export for the CSV). The figures come from the server; a missing one is "data not captured: <field>", never 0. Money only for the cost right.
   Every row opens its detail with links to the run / order / plan screen (#/prodplan). Built on web/rb4common.js. */
(() => {
'use strict';
const B = window.BOS;
if (!B || !B.rb4) return;
const R = B.rb4, L = R.L, lab = R.lab;
const cols = {
  item: { l: R.X.item, get: (r) => R.itemName(r), w: 't' },
  place: { l: R.X.place, get: (r) => R.locName(r), w: 's' },
};
const L_ = {
  title: L('উৎপাদন রিপোর্ট', 'Production reports', 'Production report'),
  tPlan: L('পরিকল্পনা বনাম আসল', 'Plan vs actual', 'Plan vs actual'), tOrder: L('অর্ডারের অবস্থা', 'Order status', 'Order status'), tRecon: L('উৎপাদন → পাঠানো', 'Made → sent', 'Made → sent'),
  tCost: L('খরচের পার্থক্য', 'Cost variance', 'Cost variance'), tUse: L('আসল ব্যবহার', 'Real use', 'Real use vs recipe'), tYield: L('ফলন', 'Yield', 'Yield'), tLoss: L('বাতিল ও পুনঃকাজ', 'Reject & rework', 'Reject ও rework'), tWaste: L('নষ্ট (ব্যাচ অনুযায়ী)', 'Wastage by batch', 'Wastage by batch'),
  status: L('অবস্থা', 'Status', 'Status'), planDate: L('পরিকল্পনার দিন', 'Plan day', 'Plan day'), planned: L('পরিকল্পিত', 'Planned', 'Planned'), plannedB: L('পরিকল্পিত ব্যাচ', 'Planned batches', 'Planned batch'), plannedQ: L('পরিকল্পিত পরিমাণ', 'Planned quantity', 'Planned qty'),
  actualB: L('আসল ব্যাচ', 'Made batches', 'Made batch'), actualQ: L('আসল পরিমাণ', 'Made quantity', 'Made qty'), ach: L('অর্জন', 'Achievement', 'Achievement'), runs: L('রান', 'Runs', 'Runs'), day: L('দিন', 'Day', 'Day'),
  unplanned: L('পরিকল্পনা ছাড়া তৈরি', 'Made with no plan', 'Plan ছাড়া made'), batches: L('ব্যাচ', 'Batches', 'Batches'), qty: L('পরিমাণ', 'Quantity', 'Quantity'),
  s_not_due_yet: L('এখনও সময় হয়নি', 'not due yet', 'not due yet'), s_not_made: L('তৈরি হয়নি', 'not made', 'not made'), s_short: L('কম', 'short', 'short'), s_met: L('পূরণ', 'met', 'met'), s_over: L('বেশি', 'over', 'over'), s_qty_not_captured: L('পরিমাণ লেখা নেই', 'quantity not captured', 'qty লেখা নেই'),
  orderNo: L('অর্ডার', 'Order', 'Order'), forPlace: L('কোন শাখার জন্য', 'For outlet', 'For outlet'), orderDate: L('অর্ডারের দিন', 'Order day', 'Order day'), due: L('দেওয়ার দিন', 'Due day', 'Due day'), ordered: L('অর্ডার', 'Ordered', 'Ordered'), made: L('তৈরি', 'Made', 'Made'),
  balance: L('বাকি', 'Balance', 'Balance'), overdue: L('দিন দেরি', 'Days overdue', 'Days overdue'), stateAll: L('সব অবস্থা', 'Any status', 'Any status'),
  st_overdue: L('দেরি হয়েছে', 'overdue', 'overdue'), st_not_started: L('শুরু হয়নি', 'not started', 'not started'), st_partly_made: L('আংশিক তৈরি', 'partly made', 'partly made'), st_made_not_closed: L('তৈরি, বন্ধ হয়নি', 'made, not closed', 'made, not closed'),
  st_closed: L('বন্ধ', 'closed', 'closed'), st_cancelled: L('বাতিল', 'cancelled', 'cancelled'), fDue: L('দেওয়ার দিন', 'due day', 'due day'), pending: L('অপেক্ষায়', 'Pending', 'Pending'),
  sent: L('পাঠানো', 'Sent', 'Sent'), received: L('গ্রহণ', 'Received', 'Received'), transit: L('পথে', 'In transit', 'In transit'), short: L('কম পৌঁছেছে', 'Short', 'Short'), cancelled: L('বাতিল পাঠানো', 'Cancelled', 'Cancelled'), notSent: L('তৈরি − পাঠানো', 'Made − sent', 'Made − sent'),
  onHand: L('এখন মজুত', 'On hand now', 'On hand now'), tie: L('হিসাব মেলে', 'Ties', 'Ties'), perItem: L('পণ্য অনুযায়ী', 'Per item', 'Per item'), perDay: L('দিন অনুযায়ী', 'Per day', 'Per day'),
  measured: L('মাপা রান', 'Measured runs', 'Measured runs'), partly: L('আংশিক', 'Partly', 'Partly'), notMeasured: L('মাপা হয়নি', 'Not measured', 'Not measured'), priceV: L('দামের পার্থক্য', 'Price variance', 'Price variance'), usageV: L('ব্যবহারের পার্থক্য', 'Usage variance', 'Usage variance'),
  yieldV: L('ফলনের পার্থক্য', 'Yield variance', 'Yield variance'), totalV: L('মোট পার্থক্য', 'Total variance', 'Total variance'), totalPct: L('মোট %', 'Total %', 'Total %'), stdForReal: L('আসল উৎপাদনের স্ট্যান্ডার্ড খরচ', 'Standard cost of the real output', 'Real output-এর standard cost'),
  realMat: L('আসল কাঁচামাল খরচ', 'Real material cost', 'Real material cost'), yieldQ: L('ফলন কম (পরিমাণ)', 'Yield short (qty)', 'Yield short (qty)'), missing: L('যা লেখা নেই', 'Missing', 'Missing'), perRun: L('রান অনুযায়ী', 'Per run', 'Per run'),
  s_measured: L('পুরো মাপা', 'measured', 'measured'), s_partly: L('আংশিক', 'partly', 'partly'), s_not_measured: L('মাপা হয়নি', 'not measured', 'not measured'), conv: L('রূপান্তর খরচ (ধরা আছে, ভাগ হয়নি)', 'Conversion cost (booked, not split)', 'Conversion cost (booked, split নয়)'),
  m_real: L('ব্যবহারের আসল পরিমাণ', 'real use of ingredients', 'real use of ingredients'), m_stdprice: L('স্ট্যান্ডার্ড দাম (দামের তালিকা)', 'standard price (price list)', 'standard price (price list)'), m_yield: L('আসল ফলন', 'actual yield', 'actual yield'), m_cost: L('ধরা খরচ', 'booked cost', 'booked cost'), m_ing: L('কাঁচামালের হিসাব', 'booked ingredients', 'booked ingredients'),
  ingredient: L('কাঁচামাল', 'Ingredient', 'Ingredient'), product: L('তৈরি পণ্য', 'Product', 'Product'), stdQ: L('রেসিপির পরিমাণ', 'Recipe quantity', 'Recipe qty'), realQ: L('আসল পরিমাণ', 'Real quantity', 'Real qty'), diff: L('পার্থক্য', 'Difference', 'Difference'), diffPct: L('পার্থক্য %', 'Difference %', 'Diff %'),
  runsIssued: L('যত রানে লেগেছে', 'Runs that used it', 'Runs'), runsMeasured: L('মাপা রান', 'Runs measured', 'Runs measured'), runsNc: L('লেখা নেই এমন রান', 'Runs not captured', 'Runs not captured'),
  s_not_captured: L('লেখা নেই', 'not captured', 'not captured'), s_not_in_recipe: L('রেসিপিতে নেই', 'not in the recipe', 'not in recipe'), s_standard_not_captured: L('স্ট্যান্ডার্ড লেখা নেই', 'standard not captured', 'standard লেখা নেই'),
  yStd: L('রেসিপির ফলন', 'Standard yield', 'Standard yield'), yAct: L('আসল ফলন', 'Actual yield', 'Actual yield'), yBook: L('স্টকে তোলা', 'Booked output', 'Booked output'), yVar: L('পার্থক্য', 'Difference', 'Difference'), yVarPct: L('পার্থক্য %', 'Difference %', 'Difference %'), over: L('সীমার বেশি', 'Over the limit', 'Over limit'),
  fActualYield: L('আসল ফলন', 'actual yield', 'actual yield'), limit: L('মালিকের সীমা', 'Owner limit', 'Owner limit'),
  output: L('উৎপাদন', 'Output', 'Output'), reject: L('বাতিল', 'Reject', 'Reject'), rework: L('পুনঃকাজ', 'Rework', 'Rework'), rejectPct: L('বাতিল %', 'Reject %', 'Reject %'), reworkPct: L('পুনঃকাজ %', 'Rework %', 'Rework %'), reason: L('কারণ', 'Reason', 'Reason'),
  rejectN: L('বাতিল (বার)', 'Rejects (n)', 'Rejects (n)'), reworkN: L('পুনঃকাজ (বার)', 'Reworks (n)', 'Reworks (n)'), perReason: L('কারণ অনুযায়ী', 'Per reason', 'Per reason'), runsKnown: L('জানা রান', 'Runs known', 'Runs known'),
  st_recorded: L('লেখা আছে', 'recorded', 'recorded'), st_none: L('পরীক্ষা করে নেই', 'checked, none', 'checked, none'), fLoss: L('বাতিল ও পুনঃকাজ', 'reject and rework', 'reject ও rework'),
  records: L('এন্ট্রি', 'Records', 'Records'), value: L('দাম', 'Value', 'Value'), valueNk: L('দাম অজানা', 'Value not known', 'Value not known'), batch: L('ব্যাচ', 'Batch', 'Batch'), perBatch: L('ব্যাচ অনুযায়ী', 'Per batch', 'Per batch'), run: L('উৎপাদন রান', 'Production run', 'Production run'),
  bs_from_run: L('রানের ব্যাচ', 'from a run', 'from a run'), bs_not_from_a_run: L('রানের ব্যাচ নয়', 'not from a run', 'not from a run'), bs_batch_not_captured: L('ব্যাচ লেখা নেই', 'batch not captured', 'batch লেখা নেই'), fCost: L('খরচ', 'cost', 'cost'),
  openRun: L('রান খুলুন', 'Open the run', 'Run খুলুন'), openOrders: L('অর্ডার ও পরিকল্পনা', 'Orders & plans', 'Order ও plan'), made1: L('তৈরি', 'Made', 'Made'),
};
const st = (...keys) => Object.fromEntries(keys.map((k) => [k, L_['s_' + k]]));
const base = (r) => r.base_unit;
const runLink = (r) => { const id = r.run_id || (r.run_ids && r.run_ids[0]); return id ? [{ label: L_.openRun, hash: '#/prodplan/run/' + id }] : []; };
const MISS = { 'real use of ingredients': L_.m_real, 'standard price (price list)': L_.m_stdprice, 'actual yield': L_.m_yield, 'booked cost': L_.m_cost, 'booked ingredients': L_.m_ing };
const reasonOf = (r) => (window.BOS_APP.S.lang === 'en' ? r.reason || r.reason_code : r.reason_bn || r.reason || r.reason_code) || '';
const filt = (D) => ({ p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null });
const filtI = (D) => Object.assign(filt(D), { p_item: D.item || null });
const mk = (extra) => Object.assign({ l: null, get: null }, extra);

const tabs = [
  { id: 'plan', label: L_.tPlan, rpc: 'rb4_plan_vs_actual', args: filt, filters: ['date', 'loc'], csvKey: 'plan_vs_actual', csvName: 'plan-vs-actual',
    top: (d) => `<div class="card">${esc2(L_.planned)}: <b>${d.summary.plans}</b> · ${esc2(L_.s_met)}: <b>${d.summary.rows_met}</b> · ${esc2(L_.s_short)}: <b>${d.summary.rows_short}</b> · ${esc2(L_.s_not_made)}: <b>${d.summary.rows_not_made}</b> · ${esc2(L_.unplanned)}: <b>${d.summary.unplanned_runs}</b></div>`,
    blocks: [
      { title: null, rows: (d) => d.rows, status: st('not_due_yet', 'not_made', 'short', 'met', 'over', 'qty_not_captured'), warn: (r) => ['short', 'not_made', 'qty_not_captured'].includes(r.status), links: (r) => runLink(r).concat([{ label: L_.openOrders, hash: '#/prodplan/plans' }]),
        cols: [cols.item, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.planDate, get: (r) => r.plan_date, f: 'date', w: 's' }, cols.place,
          { l: L_.plannedB, get: (r) => r.planned_batches, f: 'q4', nc: L_.plannedB }, { l: L_.plannedQ, get: (r) => r.planned_qty, f: 'q4', unit: base, nc: L_.plannedQ },
          { l: L_.actualB, get: (r) => r.actual_batches, f: 'q4' }, { l: L_.actualQ, get: (r) => r.actual_qty, f: 'q4', unit: base }, { l: L_.ach, get: (r) => r.achievement_pct, f: 'pct' }, { l: L_.runs, get: (r) => r.runs_n, f: 'int' }] },
      { title: L_.unplanned, rows: (d) => d.unplanned, links: runLink, cols: [cols.item, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place, { l: L_.runs, get: (r) => r.runs_n, f: 'int' }, { l: L_.batches, get: (r) => r.batches, f: 'q4' }, { l: L_.qty, get: (r) => r.qty, f: 'q4', unit: base }] },
    ] },
  { id: 'order', label: L_.tOrder, rpc: 'rb4_order_status', args: (D) => Object.assign(filt(D), { p_status: D.status || null }), filters: ['date', 'loc'], csvKey: 'order_status', csvName: 'order-status',
    intro: (D) => `<div><select id="prr_status"><option value="">${esc2(L_.stateAll)}</option>${['open', 'overdue', 'closed', 'cancelled'].map((s) => `<option value="${s}" ${D.status === s ? 'selected' : ''}>${esc2(L_['st_' + s] || L_.pending)}</option>`).join('')}</select></div>`,
    top: (d) => `<div class="card">${esc2(L_.orderNo)}: <b>${d.summary.orders}</b> · ${esc2(L_.pending)}: <b>${d.summary.open}</b> · ${esc2(L_.st_overdue)}: <b>${d.summary.overdue}</b> · ${esc2(L_.st_not_started)}: <b>${d.summary.not_started}</b> · ${esc2(L_.st_made_not_closed)}: <b>${d.summary.made_not_closed}</b></div>`,
    blocks: [{ title: null, rows: (d) => d.rows, status: Object.fromEntries(['overdue', 'not_started', 'partly_made', 'made_not_closed', 'closed', 'cancelled'].map((k) => [k, L_['st_' + k]])), warn: (r) => r.state === 'overdue', links: (r) => runLink(r).concat([{ label: L_.openOrders, hash: '#/prodplan/orders' }]),
      cols: [{ l: L_.orderNo, get: (r) => '#' + r.order_no, w: 't' }, { l: L_.status, get: (r) => r.state, f: 'status', w: 'c' }, cols.item, cols.place, { l: L_.forPlace, get: (r) => R.locName(r, 'for_location') || null, w: 's' },
        { l: L_.orderDate, get: (r) => r.order_date, f: 'date' }, { l: L_.due, get: (r) => r.due_date, f: 'date', nc: L_.fDue }, { l: L_.ordered, get: (r) => r.qty, f: 'q4', unit: base }, { l: L_.made, get: (r) => r.made, f: 'q4', unit: base },
        { l: L_.balance, get: (r) => r.balance, f: 'q4', unit: base }, { l: L_.overdue, get: (r) => r.days_overdue, f: 'int' }] }] },
  { id: 'recon', label: L_.tRecon, rpc: 'rb4_dispatch_recon', args: filt, filters: ['date', 'loc'], csvKey: 'dispatch_recon', csvName: 'made-sent-received',
    blocks: [
      { title: L_.perItem, rows: (d) => d.summary, warn: (r, c) => c && c.l === L_.tie && !r.tie_ok,
        cols: [cols.item, cols.place, { l: L_.made, get: (r) => r.made, f: 'q4', unit: base }, { l: L_.sent, get: (r) => r.sent, f: 'q4', unit: base }, { l: L_.received, get: (r) => r.received, f: 'q4', unit: base }, { l: L_.transit, get: (r) => r.in_transit, f: 'q4', unit: base },
          { l: L_.short, get: (r) => r.short, f: 'q4', unit: base }, { l: L_.notSent, get: (r) => r.made_not_sent, f: 'q4', unit: base }, { l: L_.onHand, get: (r) => r.on_hand_now, f: 'q4', unit: base, nc: L_.onHand }, { l: L_.tie, get: (r) => r.tie_ok, f: 'bool' }] },
      { title: L_.perDay, rows: (d) => d.rows,
        cols: [cols.item, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place, { l: L_.made, get: (r) => r.made, f: 'q4', unit: base }, { l: L_.sent, get: (r) => r.sent, f: 'q4', unit: base }, { l: L_.received, get: (r) => r.received, f: 'q4', unit: base },
          { l: L_.transit, get: (r) => r.in_transit, f: 'q4', unit: base }, { l: L_.short, get: (r) => r.short, f: 'q4', unit: base }, { l: L_.cancelled, get: (r) => r.cancelled, f: 'q4', unit: base }] }] },
  { id: 'cost', label: L_.tCost, rpc: 'rb4_cost_variance', args: filtI, csvKey: 'cost_variance', csvName: 'cost-variance',
    blocks: [
      { title: L_.perItem, rows: (d) => d.summary,
        cols: [cols.item, { l: L_.runs, get: (r) => r.runs, f: 'int', w: 'c' }, { l: L_.measured, get: (r) => r.runs_measured, f: 'int' }, { l: L_.partly, get: (r) => r.runs_partly, f: 'int' }, { l: L_.notMeasured, get: (r) => r.runs_not_measured, f: 'int' },
          { l: L_.priceV, get: (r) => r.price_var, f: 'money', money: true, nc: L_.priceV }, { l: L_.usageV, get: (r) => r.usage_var, f: 'money', money: true, nc: L_.usageV }, { l: L_.yieldV, get: (r) => r.yield_var, f: 'money', money: true, nc: L_.yieldV },
          { l: L_.totalV, get: (r) => r.total_var, f: 'money', money: true, nc: L_.totalV }, { l: L_.totalPct, get: (r) => r.total_var_pct, f: 'pct', money: true }] },
      { title: L_.perRun, rows: (d) => d.rows, status: st('measured', 'partly', 'not_measured'), warn: (r) => r.status === 'not_measured', links: runLink,
        detail: (r) => `<h4>${esc2(L_.ingredient)}</h4>` + R.tbl([lab(L_.ingredient), lab(L_.stdQ), lab(L_.realQ), lab(L_.priceV), lab(L_.usageV)], (r.lines || []).map((l) => `<tr><td>${esc2(R.itemName(l))}</td><td>${R.q4(l.std_qty)}</td><td>${l.actual_qty === null || l.actual_qty === undefined ? esc2(R.NC(L_.m_real)) : R.q4(l.actual_qty)}</td><td>${R.money(l.price_var)}</td><td>${R.money(l.usage_var)}</td></tr>`)),
        cols: [cols.item, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place,
          { l: L_.yieldQ, get: (r) => r.yield_var_qty, f: 'q4', unit: base, nc: L_.fActualYield }, { l: L_.realMat, get: (r) => r.real_material_cost, f: 'money', money: true }, { l: L_.stdForReal, get: (r) => r.std_cost_for_real_output, f: 'money', money: true },
          { l: L_.priceV, get: (r) => r.price_var, f: 'money', money: true }, { l: L_.usageV, get: (r) => r.usage_var, f: 'money', money: true }, { l: L_.yieldV, get: (r) => r.yield_var, f: 'money', money: true }, { l: L_.totalV, get: (r) => r.total_var, f: 'money', money: true },
          { l: L_.conv, get: (r) => r.conversion_cost, f: 'money', money: true },
          { l: L_.missing, get: (r) => (r.missing && r.missing.length ? r.missing.map((m) => (MISS[m] ? lab(MISS[m]) : m)).join(', ') : null) }] }] },
  { id: 'use', label: L_.tUse, rpc: 'rb4_consumption_vs_recipe', args: filtI, csvKey: 'consumption', csvName: 'real-use-vs-recipe',
    blocks: [
      { title: L_.perItem, rows: (d) => d.summary,
        cols: [{ l: L_.ingredient, get: (r) => R.itemName(r), w: 't' }, { l: L_.runsIssued, get: (r) => r.runs_issued, f: 'int', w: 'c' }, { l: L_.runsMeasured, get: (r) => r.runs_measured, f: 'int' }, { l: L_.runsNc, get: (r) => r.runs_not_captured, f: 'int' },
          { l: L_.stdQ, get: (r) => r.std_qty_measured, f: 'q4', unit: base, nc: L_.m_real }, { l: L_.realQ, get: (r) => r.actual_qty_measured, f: 'q4', unit: base, nc: L_.m_real }, { l: L_.diff, get: (r) => r.diff, f: 'q4', unit: base }, { l: L_.diffPct, get: (r) => r.diff_pct, f: 'pct' }] },
      { title: L_.perRun, rows: (d) => d.rows, status: st('measured', 'not_captured', 'not_in_recipe'), warn: (r) => r.status !== 'measured', links: runLink,
        cols: [{ l: L_.ingredient, get: (r) => R.itemName(r), w: 't' }, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, { l: L_.product, get: (r) => (r.fg_code ? r.fg_code + ' · ' : '') + (window.BOS_APP.S.lang === 'en' ? r.fg_name_en || r.fg_name_bn : r.fg_name_bn || r.fg_name_en), w: 's' },
          { l: L_.stdQ, get: (r) => r.std_qty, f: 'q4', unit: base }, { l: L_.realQ, get: (r) => r.actual_qty, f: 'q4', unit: base, nc: L_.m_real }, { l: L_.diff, get: (r) => r.diff, f: 'q4', unit: base }, { l: L_.diffPct, get: (r) => r.diff_pct, f: 'pct' }] }] },
  { id: 'yield', label: L_.tYield, rpc: 'rb4_run_yield', args: filtI,  csvKey: 'run_yield', csvName: 'run-yield',
    top: (d) => `<div class="card">${esc2(L_.limit)}: <b>${d.limit_pct === null || d.limit_pct === undefined ? esc2(R.NC('yield_variance_warn_pct')) : R.pct(d.limit_pct)}</b></div>`,
    blocks: [
      { title: L_.perItem, rows: (d) => d.summary, cols: [cols.item, { l: L_.runs, get: (r) => r.runs, f: 'int', w: 'c' }, { l: L_.measured, get: (r) => r.measured, f: 'int' }, { l: L_.runsNc, get: (r) => r.not_captured, f: 'int' },
        { l: L_.yStd, get: (r) => r.std_qty_measured, f: 'q4', unit: base, nc: L_.fActualYield }, { l: L_.yAct, get: (r) => r.actual_qty_measured, f: 'q4', unit: base, nc: L_.fActualYield }, { l: L_.yVarPct, get: (r) => r.var_pct, f: 'pct' }, { l: L_.over, get: (r) => r.over_limit_runs, f: 'int' }] },
      { title: L_.perRun, rows: (d) => d.rows, status: st('measured', 'not_captured', 'standard_not_captured'), warn: (r) => r.over_limit === true || r.status !== 'measured', links: runLink,
        cols: [cols.item, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place, { l: L_.yStd, get: (r) => r.yield_std, f: 'q4', unit: base }, { l: L_.yAct, get: (r) => r.yield_actual, f: 'q4', unit: base, nc: L_.fActualYield },
          { l: L_.yBook, get: (r) => r.booked_output, f: 'q4', unit: base }, { l: L_.yVar, get: (r) => r.var_qty, f: 'q4', unit: base }, { l: L_.yVarPct, get: (r) => r.var_pct, f: 'pct' }, { l: L_.over, get: (r) => r.over_limit, f: 'bool' }] }] },
  { id: 'loss', label: L_.tLoss, rpc: 'rb4_losses', args: filtI, csvKey: 'losses', csvName: 'reject-rework',
    blocks: [
      { title: L_.perItem, rows: (d) => d.by_item, cols: [cols.item, { l: L_.runsKnown, get: (r) => r.runs_known, f: 'int', w: 'c' }, { l: L_.runsNc, get: (r) => r.runs_not_captured, f: 'int' }, { l: L_.output, get: (r) => r.output_known, f: 'q4', unit: base, nc: L_.fLoss },
        { l: L_.reject, get: (r) => r.reject_qty, f: 'q4', unit: base }, { l: L_.rejectPct, get: (r) => r.reject_pct, f: 'pct' }, { l: L_.rework, get: (r) => r.rework_qty, f: 'q4', unit: base }, { l: L_.reworkPct, get: (r) => r.rework_pct, f: 'pct' }] },
      { title: L_.perReason, rows: (d) => d.by_reason, cols: [{ l: L_.reason, get: (r) => reasonOf(r), w: 't' }, { l: L_.rejectN, get: (r) => r.reject_n, f: 'int' }, { l: L_.reworkN, get: (r) => r.rework_n, f: 'int' }] },
      { title: L_.perRun, rows: (d) => d.rows, status: Object.fromEntries([['recorded', L_.st_recorded], ['none', L_.st_none], ['not_captured', L_.s_not_captured]]), warn: (r) => r.state === 'not_captured', links: runLink,
        detail: (r) => R.tbl([lab(L_.reason), lab(L_.qty), lab(L_.status)], (r.lines || []).map((l) => `<tr><td>${esc2(reasonOf(l))}</td><td>${R.q4(l.qty)}</td><td>${esc2(l.kind)}</td></tr>`)),
        cols: [cols.item, { l: L_.status, get: (r) => r.state, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place, { l: L_.output, get: (r) => r.output, f: 'q4', unit: base },
          { l: L_.reject, get: (r) => r.reject_qty, f: 'q4', unit: base, nc: L_.fLoss }, { l: L_.rejectPct, get: (r) => r.reject_pct, f: 'pct' }, { l: L_.rework, get: (r) => r.rework_qty, f: 'q4', unit: base, nc: L_.fLoss }, { l: L_.reworkPct, get: (r) => r.rework_pct, f: 'pct' }] }] },
  { id: 'waste', label: L_.tWaste, rpc: 'rb4_wastage_dim', args: filtI, csvKey: 'wastage_dim', csvName: 'wastage-by-batch',
    blocks: [
      { title: L_.perReason, rows: (d) => d.by_reason, cols: [{ l: L_.reason, get: (r) => reasonOf(r), w: 't' }, { l: L_.records, get: (r) => r.records, f: 'int', w: 'c' }, { l: L_.value, get: (r) => r.value, f: 'money', money: true, nc: L_.fCost }, { l: L_.valueNk, get: (r) => r.value_not_known_n, f: 'int', money: true }] },
      { title: L_.perItem, rows: (d) => d.by_item, cols: [cols.item, { l: L_.records, get: (r) => r.records, f: 'int', w: 'c' }, { l: L_.qty, get: (r) => r.qty, f: 'q4', unit: base }, { l: L_.value, get: (r) => r.value, f: 'money', money: true, nc: L_.fCost }, { l: L_.valueNk, get: (r) => r.value_not_known_n, f: 'int', money: true }] },
      { title: L_.perBatch, rows: (d) => d.by_batch, links: runLink, cols: [{ l: L_.batch, get: (r) => '#' + r.batch_id, w: 't' }, cols.item, { l: L_.run, get: (r) => (r.run_id ? String(r.run_id).slice(0, 8) : null), w: 's' }, { l: L_.records, get: (r) => r.records, f: 'int' }, { l: L_.qty, get: (r) => r.qty, f: 'q4', unit: base }, { l: L_.value, get: (r) => r.value, f: 'money', money: true, nc: L_.fCost }] },
      { title: L_.tWaste, rows: (d) => d.rows, status: st('from_run', 'not_from_a_run', 'batch_not_captured'), links: runLink, warn: (r) => r.batch_state === 'batch_not_captured',
        cols: [cols.item, { l: L_.batch, get: (r) => r.batch_state, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, cols.place, { l: L_.qty, get: (r) => r.qty, f: 'q4', unit: base }, { l: L_.reason, get: (r) => reasonOf(r) },
          { l: L_.value, get: (r) => r.value, f: 'money', money: true, nc: L_.fCost }] }] },
];
// the batch-state map uses its own texts
tabs[7].blocks[3].status = { from_run: L_.bs_from_run, not_from_a_run: L_.bs_not_from_a_run, batch_not_captured: L_.bs_batch_not_captured };
function esc2(v) { return window.BOS_APP.esc(typeof v === 'string' ? v : lab(v)); }

R.page({ route: 'prodreports', act: 'prr', title: L_.title, tabs });
})();
