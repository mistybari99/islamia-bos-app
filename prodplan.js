/* Islamia BOS · Production plan, orders and run capture (#/prodplan), package RPT-B4 / R3. Digital entry screens (the paper form code is to be given by the owner). Three tabs:
   Runs: every finished production run with what is captured for it; tap a run to type the REAL use of ingredients (blind: the recipe quantity is shown only after you saved yours), reject / rework with a reason,
   the labour hours of the crew, the line it was made on, and the plan / order it belongs to · Plans: a plan line per day, place and item · Orders: an order for a product with its due day, made so far and balance.
   Server: supabase/phase404.sql, phase405.sql (prod_plan_add / cancel, prod_order_add / close / cancel, prod_run_link, prod_actual_issue_set, prod_loss_add / void, prod_run_detail, prod_runs_recent)
   and phase412.sql (prod_labour_add / void / list, prod_run_line, production_line_list). Every right is checked on the server (the owner, or the grant stock_production); a hidden button is also a refused request.
   Nothing here posts stock or money: the production screen booked the recipe quantity; this screen records what really happened. The actual yield is typed on the production screen itself (#/recipes).
   Routes: #/prodplan, #/prodplan/plans, #/prodplan/orders, #/prodplan/run/<run id> (opens the run sheet). Built on web/rb4common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!B || !B.rb4) return;
const { sb, esc, toast, fail, openSheet, closeSheet, nm, S } = A;
const R = B.rb4, L = R.L, lab = R.lab;
const $ = (s, el = document) => el.querySelector(s);
const L_ = {
  title: L('উৎপাদন: পরিকল্পনা, অর্ডার ও রান', 'Production: plan, orders & runs', 'Production: plan, order ও run'), tRuns: L('রান', 'Runs', 'Runs'), tPlans: L('পরিকল্পনা', 'Plans', 'Plans'), tOrders: L('অর্ডার', 'Orders', 'Orders'),
  item: L('পণ্য', 'Item', 'Item'), place: L('জায়গা', 'Place', 'Place'), day: L('দিন', 'Day', 'Day'), output: L('উৎপাদন', 'Output', 'Output'), batches: L('ব্যাচ', 'Batches', 'Batches'), qty: L('পরিমাণ (বেস একক)', 'Quantity (base unit)', 'Qty (base unit)'),
  realUse: L('আসল ব্যবহার', 'Real use', 'Real use'), loss: L('বাতিল / পুনঃকাজ', 'Reject / rework', 'Reject / rework'), labour: L('শ্রম-ঘণ্টা', 'Labour hours', 'Labour hours'), line: L('লাইন', 'Line', 'Line'), linked: L('পরিকল্পনা / অর্ডারের সাথে যুক্ত', 'Linked to a plan / order', 'Plan / order-এ linked'),
  fRealUse: L('আসল ব্যবহার', 'real use of ingredients', 'real use'), fLoss: L('বাতিল ও পুনঃকাজ', 'reject and rework', 'reject ও rework'), fLabour: L('শ্রম-ঘণ্টা', 'labour hours', 'labour hours'),
  l_recorded: L('লেখা আছে', 'recorded', 'recorded'), l_none: L('পরীক্ষা করে নেই', 'checked, none', 'checked, none'), lines: L('লাইন', 'lines', 'lines'),
  note: L('নোট', 'Note', 'Note'), cancel: L('বাতিল করুন', 'Cancel it', 'Cancel করুন'), plan: L('পরিকল্পনা', 'Plan', 'Plan'),
  addPlan: L('নতুন পরিকল্পনা', 'Add a plan', 'Add plan'), addOrder: L('নতুন অর্ডার', 'Add an order', 'Add order'), planDate: L('পরিকল্পনার দিন', 'Plan day', 'Plan day'), orderDate: L('অর্ডারের দিন', 'Order day', 'Order day'), due: L('দেওয়ার দিন (ঐচ্ছিক)', 'Due day (optional)', 'Due day (optional)'),
  forPlace: L('কোন শাখার জন্য (ঐচ্ছিক)', 'For outlet (optional)', 'For outlet (optional)'), forStock: L('— স্টকের জন্য —', '— for stock —', '— for stock —'), prodPlace: L('কোথায় তৈরি হবে', 'Made at', 'Made at'),
  orBatches: L('ব্যাচ সংখ্যা (বা নিচের পরিমাণ)', 'Number of batches (or the quantity below)', 'Batch সংখ্যা (বা quantity)'), orQty: L('পরিমাণ (বেস এককে)', 'Quantity (in the base unit)', 'Quantity (base unit)'),
  s_planned: L('পরিকল্পিত', 'planned', 'planned'), s_cancelled: L('বাতিল', 'cancelled', 'cancelled'), planBn: L('পরিকল্পিত ব্যাচ', 'Planned batches', 'Planned batch'), planQ: L('পরিকল্পিত পরিমাণ', 'Planned quantity', 'Planned qty'), fPlanB: L('পরিকল্পিত ব্যাচ', 'planned batches', 'planned batches'), fPlanQ: L('পরিকল্পিত পরিমাণ', 'planned quantity', 'planned qty'),
  orderNo: L('অর্ডার', 'Order', 'Order'), status: L('অবস্থা', 'Status', 'Status'), ordered: L('অর্ডার', 'Ordered', 'Ordered'), made: L('তৈরি', 'Made', 'Made'), balance: L('বাকি', 'Balance', 'Balance'), overdue: L('দিন দেরি', 'Days overdue', 'Days overdue'), fDue: L('দেওয়ার দিন', 'due day', 'due day'),
  st_overdue: L('দেরি হয়েছে', 'overdue', 'overdue'), st_not_started: L('শুরু হয়নি', 'not started', 'not started'), st_partly_made: L('আংশিক তৈরি', 'partly made', 'partly made'), st_made_not_closed: L('তৈরি, বন্ধ হয়নি', 'made, not closed', 'made, not closed'), st_closed: L('বন্ধ', 'closed', 'closed'), st_cancelled: L('বাতিল', 'cancelled', 'cancelled'),
  closeOrder: L('অর্ডার বন্ধ করুন', 'Close the order', 'Order বন্ধ করুন'), cancelOrder: L('অর্ডার বাতিল', 'Cancel the order', 'Order cancel'), cancelPlan: L('পরিকল্পনা বাতিল', 'Cancel the plan', 'Plan cancel'), reasonNeeded: L('কারণ (কম তৈরি হলে অবশ্যই)', 'Reason (needed if less was made)', 'Reason (কম made হলে লাগবে)'),
  // run sheet
  runTitle: L('রান', 'Run', 'Run'), stdOut: L('রেসিপির ফলন', 'Standard output', 'Standard output'), actOut: L('আসল ফলন', 'Actual yield', 'Actual yield'), actOutNote: L('আসল ফলন উৎপাদনের পাতায় (রেসিপি ও উৎপাদন) লেখা হয়', 'The actual yield is typed on the production screen (Recipes & production)', 'Actual yield production screen-এ লেখা হয়'),
  ruH: L('কাঁচামালের আসল ব্যবহার', 'Real use of ingredients', 'Real use of ingredients'), ruHint: L('আগে আপনার মাপা পরিমাণ লিখুন; রেসিপির পরিমাণ সংরক্ষণের পর দেখা যাবে।', 'Type what you measured first; the recipe quantity is shown after you save.', 'আগে আপনার মাপা quantity লিখুন; recipe quantity save-এর পর দেখা যাবে।'),
  ruReal: L('আসল', 'Real', 'Real'), ruBooked: L('রেসিপি', 'Recipe', 'Recipe'), ruDiff: L('পার্থক্য', 'Difference', 'Difference'), ruChange: L('বদলাতে নতুন পরিমাণ', 'New value to change', 'বদলাতে new value'), ruSave: L('আসল ব্যবহার সংরক্ষণ', 'Save real use', 'Real use save'),
  ruExtra: L('রেসিপিতে নেই এমন কাঁচামাল (ঐচ্ছিক)', 'An ingredient not in the recipe (optional)', 'Recipe-এ নেই এমন ingredient (optional)'), ruNone: L('কিছু লেখার নেই', 'Nothing to save', 'Save করার কিছু নেই'), ruExtraList: L('রেসিপির বাইরে', 'Outside the recipe', 'Outside recipe'),
  lossH: L('বাতিল ও পুনঃকাজ', 'Reject & rework', 'Reject ও rework'), kind: L('ধরন', 'Kind', 'Kind'), k_reject: L('বাতিল', 'Reject', 'Reject'), k_rework: L('পুনঃকাজ', 'Rework', 'Rework'), reason: L('কারণ', 'Reason', 'Reason'), pickReason: L('— কারণ বেছে নিন —', '— pick a reason —', '— reason বেছে নিন —'),
  addLoss: L('যোগ করুন', 'Add', 'Add'), lossNone: L('পরীক্ষা করেছি: বাতিল বা পুনঃকাজ নেই', 'Checked: no reject or rework', 'Checked: reject/rework নেই'), voidIt: L('বাতিল', 'Void', 'Void'), reasonNotListed: L('কারণ তালিকায় নেই? তালিকায় যোগ করুন', 'Reason not in the list? Add it in Lists', 'Reason list-এ নেই? Lists-এ যোগ করুন'),
  labH: L('শ্রম-ঘণ্টা', 'Labour hours', 'Labour hours'), people: L('কতজন', 'People', 'People'), hoursEach: L('প্রত্যেকে কত ঘণ্টা', 'Hours each', 'Hours each'), addLab: L('শ্রম যোগ', 'Add crew', 'Crew add'), total: L('মোট শ্রম-ঘণ্টা', 'Total labour hours', 'Total labour hours'),
  linkH: L('কোন পরিকল্পনা / অর্ডার / লাইন', 'Plan / order / line', 'Plan / order / line'), noChange: L('— (বদল নয়)', '— (no change)', '— (no change)'), clearIt: L('× যুক্ততা তুলে নিন', '× remove the link', '× link সরান'), saveLink: L('সংরক্ষণ', 'Save', 'Save'),
  readOnly: L('এই রান আপনি শুধু দেখতে পারেন', 'You can only view this run', 'এই run আপনি শুধু দেখতে পারেন'), paper: R.X.paperCode, nrow: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
};
const unitOf = (r) => r.base_unit;
const qtxt = (n, u) => R.q4(n) + (u ? ' ' + R.unitL(u) : '');
const reasonRows = () => (((B.ENV && B.ENV.lists && B.ENV.lists.wastage_reasons) || []).filter((r) => r.active !== false));
const reasonLab = (r) => lab({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined });
const reasonOf = (code, rows) => { const r = (rows || reasonRows()).find((x) => x.value_code === code); return r ? reasonLab(r) : code || ''; };
const baseOf = (D, id) => { const i = D.items.find((x) => x.id === id); return i ? i.base_unit || i.unit : ''; };

R.page({ route: 'prodplan', act: 'pp', title: L_.title, range: 'days30',
  tabs: [
    { id: 'runs', label: L_.tRuns, filters: ['date', 'loc'], csvKey: 'production_runs', csvName: 'production-runs',
      load: async (D) => {
        const args = { p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null };
        const a = await sb.rpc('prod_runs_recent', args); if (a.error) throw a.error;
        const b = await sb.rpc('prod_labour_list', args);
        const lab_ = new Map(((b && b.data) || []).map((x) => [x.run_id, x]));
        return { rows: ((a.data && a.data.rows) || []).map((r) => Object.assign({}, r, { labour: lab_.get(r.run_id) || null })), truncated: false };
      },
      top: (d, D) => `<p class="muted">${esc(lab(R.X.paperCode))}</p>`,
      blocks: [{ title: null, rows: (d) => d.rows, empty: L_.nrow, open: (r) => { window.__ppOpenRun(r.run_id); },
        cols: [{ l: L_.item, get: (r) => R.itemName(r), w: 't' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, { l: L_.place, get: (r) => R.locName(r), w: 's' }, { l: L_.output, get: (r) => r.output, f: 'q4', unit: unitOf },
          { l: L_.realUse, get: (r) => (r.actual_issue_lines > 0 ? r.actual_issue_lines + ' ' + lab(L_.lines) : null), nc: L_.fRealUse },
          { l: L_.loss, get: (r) => (r.loss_state === 'recorded' ? lab(L_.l_recorded) : r.loss_state === 'none' ? lab(L_.l_none) : null), nc: L_.fLoss },
          { l: L_.labour, get: (r) => (r.labour && r.labour.labour_hours !== null && r.labour.labour_hours !== undefined ? r.labour.labour_hours : null), f: 'q4', nc: L_.fLabour },
          { l: L_.line, get: (r) => (r.labour && r.labour.line_id ? (S.lang === 'en' ? r.labour.line_en || r.labour.line_bn : r.labour.line_bn || r.labour.line_en) : null) },
          { l: L_.linked, get: (r) => r.linked, f: 'bool' }] }] },
    { id: 'plans', label: L_.tPlans, filters: ['date', 'loc'], csvKey: 'plan_vs_actual', csvName: 'production-plans',
      load: async (D) => {
        let q = sb.from('production_plans').select('id,plan_date,location_id,item_id,planned_batches,planned_qty,note,status,cancel_note,created_staff').gte('plan_date', D.from).lte('plan_date', D.to).order('plan_date', { ascending: false }).limit(500);
        if (D.loc) q = q.eq('location_id', Number(D.loc));
        const r = await q; if (r.error) throw r.error;
        const rows = (r.data || []).map((p) => { const it = D.items.find((i) => i.id === p.item_id) || {}, lo = D.locs.find((l) => l.id === p.location_id) || {}; return Object.assign({}, p, { code: it.code, name_bn: it.name_bn, name_en: it.name_en, base_unit: it.base_unit || it.unit, location: lo.name_bn, location_en: lo.name_en }); });
        return { rows, truncated: rows.length >= 500 };
      },
      top: (d, D) => `<button type="button" class="primary full" data-act="pp_newplan">${esc(lab(L_.addPlan))}</button><p class="muted">${esc(lab(R.X.paperCode))}</p>`,
      blocks: [{ title: null, rows: (d) => d.rows, status: { planned: L_.s_planned, cancelled: L_.s_cancelled }, warn: (r) => r.status === 'cancelled',
        detail: (r) => (r.status === 'planned' ? `<button type="button" class="mini" data-act="pp_cancelplan" data-id="${r.id}">${esc(lab(L_.cancelPlan))}</button>` : r.cancel_note ? `<div class="muted">${esc(r.cancel_note)}</div>` : ''),
        cols: [{ l: L_.item, get: (r) => R.itemName(r), w: 't' }, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.planDate, get: (r) => r.plan_date, f: 'date', w: 's' }, { l: L_.place, get: (r) => R.locName(r), w: 's' },
          { l: L_.planBn, get: (r) => r.planned_batches, f: 'q4', nc: L_.fPlanB }, { l: L_.planQ, get: (r) => r.planned_qty, f: 'q4', unit: unitOf, nc: L_.fPlanQ }, { l: L_.note, get: (r) => r.note }] }] },
    { id: 'orders', label: L_.tOrders, filters: ['date', 'loc'], rpc: 'rb4_order_status', args: (D) => ({ p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null, p_status: null }), csvKey: 'order_status', csvName: 'production-orders',
      top: (d, D) => `<button type="button" class="primary full" data-act="pp_neworder">${esc(lab(L_.addOrder))}</button><p class="muted">${esc(lab(R.X.paperCode))}</p>`,
      blocks: [{ title: null, rows: (d) => d.rows, status: Object.fromEntries(['overdue', 'not_started', 'partly_made', 'made_not_closed', 'closed', 'cancelled'].map((k) => [k, L_['st_' + k]])), warn: (r) => r.state === 'overdue',
        detail: (r) => (r.status === 'open' ? `<div class="row wrap"><button type="button" class="mini" data-act="pp_closeorder" data-id="${r.order_no}">${esc(lab(L_.closeOrder))}</button><button type="button" class="mini" data-act="pp_cancelorder" data-id="${r.order_no}">${esc(lab(L_.cancelOrder))}</button></div>` : r.close_note ? `<div class="muted">${esc(r.close_note)}</div>` : ''),
        links: (r) => (r.run_ids && r.run_ids[0] ? [{ label: L('রান খুলুন', 'Open the run', 'Run খুলুন'), hash: '#/prodplan/run/' + r.run_ids[0] }] : []),
        cols: [{ l: L_.orderNo, get: (r) => '#' + r.order_no, w: 't' }, { l: L_.status, get: (r) => r.state, f: 'status', w: 'c' }, { l: L_.item, get: (r) => R.itemName(r), w: 's' }, { l: L_.place, get: (r) => R.locName(r) + (r.for_location_id ? ' → ' + R.locName(r, 'for_location') : ''), w: 's' },
          { l: L_.orderDate, get: (r) => r.order_date, f: 'date' }, { l: L_.due, get: (r) => r.due_date, f: 'date', nc: L_.fDue }, { l: L_.ordered, get: (r) => r.qty, f: 'q4', unit: unitOf }, { l: L_.made, get: (r) => r.made, f: 'q4', unit: unitOf },
          { l: L_.balance, get: (r) => r.balance, f: 'q4', unit: unitOf }, { l: L_.overdue, get: (r) => r.days_overdue, f: 'int' }] }] },
  ],
  init: async (D) => {
    D.canEnter = !!S.ctx.is_owner;
    if (!D.canEnter && B.s2 && B.s2.grant) { try { D.canEnter = !!(await B.s2.grant('stock_production', null)); } catch (e) { D.canEnter = false; } }
    const h = location.hash.replace(/^#\/?/, '').split('/');
    if (h[1] === 'plans') D.tab = 'plans'; else if (h[1] === 'orders') D.tab = 'orders'; else D.tab = 'runs';
  },
  view: async (D, api, base) => {
    await base();
    const h = location.hash.replace(/^#\/?/, '').split('/');
    if (h[1] === 'run' && h[2]) window.__ppOpenRun(h[2]);
  },
  handlers: (D, api) => {
    const busyWrap = async (fn) => { if (D.busy) return; D.busy = true; try { return await fn(); } catch (e) { fail(e); } finally { D.busy = false; } };
    const call = async (fn, args) => { const r = await sb.rpc(fn, args); if (r.error) { toast(R.errText(r.error)); return null; } return r.data || {}; };
    const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
    const placeOpts = (sel) => D.locs.map((l) => `<option value="${l.id}" ${String(sel) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('');

    // ----- plan / order sheets -----
    const planSheet = () => openSheet(`<h2>${esc(lab(L_.addPlan))}</h2><div class="stack"><p class="muted">${esc(lab(R.X.paperCode))}</p>
      <div><label for="pp_p_loc">${esc(lab(L_.prodPlace))}</label><select id="pp_p_loc"><option value="">—</option>${placeOpts(D.loc)}</select></div>
      <div><label for="pp_p_date">${esc(lab(L_.planDate))}</label><input id="pp_p_date" type="date" value="${esc(R.today())}"></div>
      ${R.itemFld(D, 'pp_p_item')}
      <div><label for="pp_p_b">${esc(lab(L_.orBatches))}</label><input id="pp_p_b" inputmode="decimal" autocomplete="off"></div>
      <div><label for="pp_p_q">${esc(lab(L_.orQty))}</label><input id="pp_p_q" inputmode="decimal" autocomplete="off"></div>
      <div><label for="pp_p_n">${esc(lab(L_.note))}</label><input id="pp_p_n" maxlength="300" autocomplete="off"></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="primary full" data-act="pp_plansave">${esc(lab(R.X.save))}</button></div></div>`);
    const orderSheet = () => openSheet(`<h2>${esc(lab(L_.addOrder))}</h2><div class="stack"><p class="muted">${esc(lab(R.X.paperCode))}</p>
      <div><label for="pp_o_loc">${esc(lab(L_.prodPlace))}</label><select id="pp_o_loc"><option value="">—</option>${placeOpts(D.loc)}</select></div>
      <div><label for="pp_o_for">${esc(lab(L_.forPlace))}</label><select id="pp_o_for"><option value="">${esc(lab(L_.forStock))}</option>${placeOpts('')}</select></div>
      <div class="row"><div style="flex:1"><label for="pp_o_date">${esc(lab(L_.orderDate))}</label><input id="pp_o_date" type="date" value="${esc(R.today())}"></div><div style="flex:1"><label for="pp_o_due">${esc(lab(L_.due))}</label><input id="pp_o_due" type="date"></div></div>
      ${R.itemFld(D, 'pp_o_item')}
      <div><label for="pp_o_q">${esc(lab(L_.orQty))}</label><input id="pp_o_q" inputmode="decimal" autocomplete="off"></div>
      <div><label for="pp_o_n">${esc(lab(L_.note))}</label><input id="pp_o_n" maxlength="300" autocomplete="off"></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="primary full" data-act="pp_ordersave">${esc(lab(R.X.save))}</button></div></div>`);
    const noteSheet = (title, goAct, id, danger, hint) => openSheet(`<h2>${esc(lab(title))}</h2><div class="stack"><div><label for="pp_why">${esc(lab(hint || R.X.why))}</label><input id="pp_why" maxlength="300" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="${danger ? 'danger' : 'primary'} full" data-act="${goAct}" data-id="${id}">${esc(lab(title))}</button></div></div>`);

    // ----- the run sheet -----
    async function openRun(id) {
      const d = await call('prod_run_detail', { p_run: id }); if (!d) return;
      const lab2 = await call('prod_labour_list', { p_from: d.day, p_to: d.day, p_loc: d.location_id });
      const lrow = Array.isArray(lab2) ? lab2.find((x) => x.run_id === id) : null;
      const lines = await call('production_line_list', { p_loc: d.location_id, p_with_retired: false });
      D.run = { id, d, lrow, lines: Array.isArray(lines) ? lines : [] };
      drawRun();
    }
    function drawRun() {
      const { id, d, lrow, lines } = D.run, edit = !!d.can_edit, reasons = reasonRows();
      const u = d.base_unit;
      const ru = (d.issue_lines || []).map((l) => `<div class="card"><div><b>${esc(l.code + ' · ' + nm(l))}</b> <span class="muted">${esc(R.unitL(l.base_unit))}</span></div>
        ${l.actual_qty !== null && l.actual_qty !== undefined ? `<div>${esc(lab(L_.ruReal))} <b>${R.q4(l.actual_qty)}</b> · ${esc(lab(L_.ruBooked))} ${R.q4(l.booked_qty)} · ${esc(lab(L_.ruDiff))} <b>${l.diff > 0 ? '+' : ''}${R.q4(l.diff)}</b></div>` : ''}
        ${edit ? `<input class="pp_ru" data-item="${l.item_id}" inputmode="decimal" autocomplete="off" aria-label="${esc(l.code)}" placeholder="${esc(lab(l.actual_qty !== null && l.actual_qty !== undefined ? L_.ruChange : L_.ruReal))}">` : ''}</div>`).join('');
      const extra = (d.extra_lines || []).map((l) => `<div class="muted">${esc(lab(L_.ruExtraList))}: ${esc(l.code + ' · ' + nm(l))} <b>${R.q4(l.actual_qty)}</b> ${esc(R.unitL(l.base_unit))}</div>`).join('');
      const losses = (d.losses || []).map((x) => `<div class="row between"><span>${esc(x.kind === 'none' ? lab(L_.l_none) : lab(L_['k_' + x.kind]) + ' ' + R.q4(x.qty) + ' ' + R.unitL(u) + ' · ' + reasonOf(x.reason_code, reasons))}${x.note ? ` <span class="muted">${esc(x.note)}</span>` : ''}</span>${edit ? `<button type="button" class="mini" data-act="pp_lossvoid" data-id="${x.id}">${esc(lab(L_.voidIt))}</button>` : ''}</div>`).join('');
      const labs = ((lrow && lrow.entries) || []).map((x) => `<div class="row between"><span>${x.people} × ${R.q4(x.hours_each)} h = <b>${R.q4(x.people * x.hours_each)}</b> h${x.note ? ` <span class="muted">${esc(x.note)}</span>` : ''}</span>${edit ? `<button type="button" class="mini" data-act="pp_labvoid" data-id="${x.id}">${esc(lab(L_.voidIt))}</button>` : ''}</div>`).join('');
      const link = d.link || {};
      openSheet(`<h2>${esc(d.code + ' · ' + nm(d))}</h2><div class="muted">${esc(R.d10(d.day))} · ${esc(R.locName(d))} · ${esc(lab(L_.output))} ${R.q4(d.output)} ${esc(R.unitL(u))} · ${esc(lab(L_.batches))} ${R.q4(d.batches)}</div>
        <div class="muted">${esc(lab(L_.stdOut))} ${R.q4(d.yield_std)} · ${esc(lab(L_.actOut))} ${d.yield_actual === null || d.yield_actual === undefined ? esc(R.T('nc')) : R.q4(d.yield_actual)} <span>(${esc(lab(L_.actOutNote))})</span></div>
        ${edit ? '' : `<div class="notice warn">${esc(lab(L_.readOnly))}</div>`}
        <div class="stack"><h3>${esc(lab(L_.ruH))}</h3>${edit ? `<p class="muted">${esc(lab(L_.ruHint))}</p>` : ''}${ru || B.ui.state('empty', lab(L_.nrow))}${extra}
          ${edit ? `<div class="card"><b>${esc(lab(L_.ruExtra))}</b>${R.itemFld(D, 'pp_ru_xitem')}<input id="pp_ru_xq" inputmode="decimal" autocomplete="off" aria-label="${esc(lab(L_.ruReal))}" placeholder="${esc(lab(L_.ruReal))}"></div><button class="primary full" data-act="pp_rusave">${esc(lab(L_.ruSave))}</button>` : ''}
          <h3>${esc(lab(L_.lossH))}</h3>${losses || `<p class="muted">${esc(R.NC(L_.fLoss))}</p>`}
          ${edit ? `<div class="card"><div class="row"><div style="flex:1"><label for="pp_l_kind">${esc(lab(L_.kind))}</label><select id="pp_l_kind"><option value="reject">${esc(lab(L_.k_reject))}</option><option value="rework">${esc(lab(L_.k_rework))}</option></select></div><div style="flex:1"><label for="pp_l_q">${esc(lab(R.X.unit))}: ${esc(R.unitL(u))}</label><input id="pp_l_q" inputmode="decimal" autocomplete="off"></div></div>
            <div><label for="pp_l_r">${esc(lab(L_.reason))}</label><select id="pp_l_r"><option value="">${esc(lab(L_.pickReason))}</option>${reasons.map((r) => `<option value="${esc(r.value_code)}">${esc(reasonLab(r))}</option>`).join('')}</select><div class="muted">${R.go('#/lists', lab(L_.reasonNotListed))}</div></div>
            <div><label for="pp_l_n">${esc(lab(L_.note))}</label><input id="pp_l_n" maxlength="300" autocomplete="off"></div>
            <div class="row"><button class="primary" data-act="pp_lossadd">${esc(lab(L_.addLoss))}</button>${(d.losses || []).length ? '' : `<button data-act="pp_lossnone">${esc(lab(L_.lossNone))}</button>`}</div></div>` : ''}
          <h3>${esc(lab(L_.labH))}</h3>${labs || `<p class="muted">${esc(R.NC(L_.fLabour))}</p>`}${lrow && lrow.labour_hours !== null && lrow.labour_hours !== undefined ? `<div><b>${esc(lab(L_.total))}: ${R.q4(lrow.labour_hours)}</b></div>` : ''}
          ${edit ? `<div class="card"><div class="row"><div style="flex:1"><label for="pp_b_p">${esc(lab(L_.people))}</label><input id="pp_b_p" inputmode="numeric" autocomplete="off"></div><div style="flex:1"><label for="pp_b_h">${esc(lab(L_.hoursEach))}</label><input id="pp_b_h" inputmode="decimal" autocomplete="off"></div></div><button class="primary full" data-act="pp_labadd">${esc(lab(L_.addLab))}</button></div>` : ''}
          ${edit ? `<h3>${esc(lab(L_.linkH))}</h3><div class="card">
            <div><label for="pp_k_plan">${esc(lab(L_.plan))}</label><select id="pp_k_plan"><option value="">${esc(lab(L_.noChange))}</option>${(d.candidate_plans || []).map((p) => `<option value="${p.id}" ${link.plan_id === p.id ? 'selected' : ''}>${esc(R.d10(p.plan_date) + ' · ' + (p.planned_qty !== null && p.planned_qty !== undefined ? R.q4(p.planned_qty) : R.NC(L_.fPlanQ)))}</option>`).join('')}${link.plan_id ? `<option value="__clear">${esc(lab(L_.clearIt))}</option>` : ''}</select></div>
            <div><label for="pp_k_order">${esc(lab(L_.orderNo))}</label><select id="pp_k_order"><option value="">${esc(lab(L_.noChange))}</option>${(d.open_orders || []).map((o) => `<option value="${o.id}" ${String(link.order_id) === String(o.id) ? 'selected' : ''}>#${o.id} · ${esc(R.q4(o.made) + ' / ' + R.q4(o.qty))}</option>`).join('')}${link.order_id ? `<option value="__clear">${esc(lab(L_.clearIt))}</option>` : ''}</select></div>
            <div><label for="pp_k_line">${esc(lab(L_.line))}</label><select id="pp_k_line"><option value="">${esc(lab(L_.noChange))}</option>${lines.map((l) => `<option value="${l.id}" ${lrow && lrow.line_id === l.id ? 'selected' : ''}>${esc(S.lang === 'en' ? l.name_en || l.name_bn : l.name_bn || l.name_en)}</option>`).join('')}${lrow && lrow.line_id ? `<option value="__clear">${esc(lab(L_.clearIt))}</option>` : ''}</select></div>
            <button class="primary full" data-act="pp_linksave">${esc(lab(L_.saveLink))}</button></div>` : ''}
          <button class="full" data-act="closesheet">${esc(lab(R.X.close))}</button></div>`);
    }
    window.__ppOpenRun = (id) => busyWrap(() => openRun(id));
    const done = async (data) => { if (data) { toast(lab(R.X.saved)); await openRun(D.run.id); if (D.tab === 'runs') api.run(); } };
    const runId = () => D.run && D.run.id;

    return {
      pp_newplan: planSheet, pp_neworder: orderSheet,
      pp_plansave: () => busyWrap(async () => {
        const loc = Number(($('#pp_p_loc') || {}).value), it = R.itemFrom(D, ($('#pp_p_item') || {}).value), b = R.nnum(($('#pp_p_b') || {}).value), q = R.nnum(($('#pp_p_q') || {}).value), date = ($('#pp_p_date') || {}).value;
        if (!loc) return toast(lab(L_.prodPlace) + '?'); if (!it) return toast(lab(L_.item) + '?'); if (Number.isNaN(b) && Number.isNaN(q)) return toast(lab(R.ERR.plan_needs_batches_or_qty));
        const r = await call('prod_plan_add', { p_date: date, p_loc: loc, p_item: it.id, p_batches: Number.isNaN(b) ? null : b, p_qty: Number.isNaN(q) ? null : q, p_unit: null, p_recipe: null, p_note: (($('#pp_p_n') || {}).value || '').trim() || null, p_client: rid() });
        if (r) { closeSheet(); toast(lab(R.X.saved)); D.tab = 'plans'; api.frame(); }
      }),
      pp_ordersave: () => busyWrap(async () => {
        const loc = Number(($('#pp_o_loc') || {}).value), fl = ($('#pp_o_for') || {}).value, it = R.itemFrom(D, ($('#pp_o_item') || {}).value), q = R.nnum(($('#pp_o_q') || {}).value);
        if (!loc) return toast(lab(L_.prodPlace) + '?'); if (!it) return toast(lab(L_.item) + '?'); if (!(q > 0)) return toast(lab(R.ERR.bad_qty));
        const r = await call('prod_order_add', { p_date: ($('#pp_o_date') || {}).value, p_due: ($('#pp_o_due') || {}).value || null, p_loc: loc, p_for_loc: fl ? Number(fl) : null, p_item: it.id, p_qty: q, p_unit: null, p_note: (($('#pp_o_n') || {}).value || '').trim() || null, p_client: rid() });
        if (r) { closeSheet(); toast(lab(R.X.saved)); D.tab = 'orders'; api.frame(); }
      }),
      pp_cancelplan: (a) => { closeSheet(); setTimeout(() => noteSheet(L_.cancelPlan, 'pp_cancelplango', a.dataset.id, true), 0); },
      pp_cancelplango: (a) => busyWrap(async () => { const n = (($('#pp_why') || {}).value || '').trim(); if (n.length < 3) return toast(lab(R.ERR.note_required)); const r = await call('prod_plan_cancel', { p_id: a.dataset.id, p_note: n }); if (r) { closeSheet(); toast(lab(R.X.saved)); api.run(); } }),
      pp_closeorder: (a) => { closeSheet(); setTimeout(() => noteSheet(L_.closeOrder, 'pp_closeordergo', a.dataset.id, false, L_.reasonNeeded), 0); },
      pp_closeordergo: (a) => busyWrap(async () => { const r = await call('prod_order_close', { p_id: Number(a.dataset.id), p_note: (($('#pp_why') || {}).value || '').trim() || null }); if (r) { closeSheet(); toast(lab(R.X.saved)); api.run(); } }),
      pp_cancelorder: (a) => { closeSheet(); setTimeout(() => noteSheet(L_.cancelOrder, 'pp_cancelordergo', a.dataset.id, true), 0); },
      pp_cancelordergo: (a) => busyWrap(async () => { const n = (($('#pp_why') || {}).value || '').trim(); if (n.length < 3) return toast(lab(R.ERR.note_required)); const r = await call('prod_order_cancel', { p_id: Number(a.dataset.id), p_note: n }); if (r) { closeSheet(); toast(lab(R.X.saved)); api.run(); } }),
      // run sheet
      pp_rusave: () => busyWrap(async () => {
        const lines = []; document.querySelectorAll('.pp_ru').forEach((el) => { const v = R.nnum(el.value); if (el.value.trim() !== '') lines.push({ item_id: el.dataset.item, qty: v }); });
        const xi = R.itemFrom(D, ($('#pp_ru_xitem') || {}).value), xq = R.nnum(($('#pp_ru_xq') || {}).value);
        if (xi && !Number.isNaN(xq)) lines.push({ item_id: xi.id, qty: xq });
        if (!lines.length) return toast(lab(L_.ruNone)); if (lines.some((l) => Number.isNaN(l.qty) || l.qty < 0)) return toast(lab(R.ERR.bad_qty));
        done(await call('prod_actual_issue_set', { p_run: runId(), p_lines: lines, p_note: null }));
      }),
      pp_lossadd: () => busyWrap(async () => {
        const kind = ($('#pp_l_kind') || {}).value, q = R.nnum(($('#pp_l_q') || {}).value), reason = ($('#pp_l_r') || {}).value;
        if (!(q > 0)) return toast(lab(R.ERR.bad_qty)); if (!reason) return toast(lab(R.ERR.reason_required));
        done(await call('prod_loss_add', { p_run: runId(), p_kind: kind, p_qty: q, p_unit: null, p_reason: reason, p_note: (($('#pp_l_n') || {}).value || '').trim() || null, p_client: rid() }));
      }),
      pp_lossnone: () => busyWrap(async () => done(await call('prod_loss_add', { p_run: runId(), p_kind: 'none', p_qty: null, p_unit: null, p_reason: null, p_note: null, p_client: rid() }))),
      pp_lossvoid: (a) => { D.voidKind = 'loss'; D.voidId = a.dataset.id; noteSheet(L_.voidIt, 'pp_voidgo', a.dataset.id, true); },
      pp_labvoid: (a) => { D.voidKind = 'labour'; D.voidId = a.dataset.id; noteSheet(L_.voidIt, 'pp_voidgo', a.dataset.id, true); },
      pp_voidgo: () => busyWrap(async () => {
        const n = (($('#pp_why') || {}).value || '').trim(); if (n.length < 3) return toast(lab(R.ERR.note_required));
        const r = D.voidKind === 'loss' ? await call('prod_loss_void', { p_id: D.voidId, p_note: n }) : await call('prod_labour_void', { p_id: Number(D.voidId), p_note: n });
        if (r) { closeSheet(); toast(lab(R.X.saved)); await openRun(D.run.id); if (D.tab === 'runs') api.run(); }
      }),
      pp_labadd: () => busyWrap(async () => {
        const p = R.nnum(($('#pp_b_p') || {}).value), h = R.nnum(($('#pp_b_h') || {}).value);
        if (!(p >= 1)) return toast(lab(R.ERR.bad_people)); if (!(h > 0 && h <= 24)) return toast(lab(R.ERR.bad_hours));
        done(await call('prod_labour_add', { p_run: runId(), p_people: Math.round(p), p_hours: h, p_note: null, p_client: rid() }));
      }),
      pp_linksave: () => busyWrap(async () => {
        const plan = ($('#pp_k_plan') || {}).value, order = ($('#pp_k_order') || {}).value, line = ($('#pp_k_line') || {}).value; let ok = true, did = false;
        if (plan || order) {
          const r = await call('prod_run_link', { p_run: runId(), p_plan: plan && plan !== '__clear' ? plan : null, p_order: order && order !== '__clear' ? Number(order) : null, p_clear_plan: plan === '__clear', p_clear_order: order === '__clear' });
          ok = !!r; did = true;
        }
        if (ok && line) { const r = await call('prod_run_line', { p_run: runId(), p_line: line === '__clear' ? null : Number(line) }); ok = !!r; did = true; }
        if (ok && did) done({});
      }),
    };
  } });
})();
