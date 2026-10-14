/* Islamia BOS · Step W: form-vs-screen screens for step E-b (supabase/phase83.sql). Four pages, no change to any existing file:
   #/unmatched    forms skipped because "the screen is the record" but with NO screen record (unmatched_forms, unmatched_forms_sync)
   #/formguard    form 05-1 mode, transit shortage mode, transit alert hours, offline soft stock - each switch next to the system's recommendation (form_guard_recommendations, owner only)
   #/expenselink  10-2 vouchers: does a quick expense already count this money? (suggest_expense_link, expense_link_apply)
   #/transitshort transfers still on the way (transit_open_list) and short receipts not yet booked (transit_short_open, transit_short_resolve)
   Recommendations never block and never change anything by themselves. Handlers are prefixed wfg_. English mode has no Bangla letters. Loaded after stepw_common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.w) return;
const { sb, S, esc, toast, shell, openSheet, closeSheet } = A;
const L = B.L, lab = B.lab, W = B.w;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  tUn: L('স্ক্রিন-রেকর্ডহীন ফর্ম', 'Forms with no screen record', 'Screen record ছাড়া form'),
  tFg: L('ফর্ম ও স্ক্রিনের নিয়ম', 'Form and screen rules', 'Form ও screen-এর rule'),
  tEl: L('খরচ দুবার গোনা', 'Expense counted twice', 'Expense দুবার গোনা'),
  tTr: L('ট্রানজিটে মাল ও ঘাটতি', 'Goods in transit and shortages', 'Transit-এ মাল ও ঘাটতি'),
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখুন', 'Show', 'Show'),
  unIntro: L('এই লাইনগুলোর ফর্ম অনুমোদিত, কিন্তু স্ক্রিনকে রেকর্ড ধরে ফর্ম থেকে stock বাদ গেছে — আর একই দিনে একই পণ্যের স্ক্রিন-রেকর্ড পাওয়া যায়নি।',
    'These form lines are approved but were skipped because the screen is the record - and no screen record for the same item, place and day was found.',
    'এই form line approved, কিন্তু screen-কে record ধরে stock বাদ গেছে — আর একই দিনে একই item-এর screen record পাওয়া যায়নি।'),
  unNote: L('নোট: গোনার স্লিপে গণনা আর খাতার অঙ্ক সমান হলে স্ক্রিনেও কোনো ledger সারি হয় না, তাই সেটা এখানে থাকলেও ভুল নয়।',
    'Note: a count slip whose counted figure equals the book figure creates no ledger row on the screen either, so it can show here without being wrong.',
    'Note: count slip-এ গণনা ও book সমান হলে screen-এও ledger row হয় না, তাই এখানে থাকলেও ভুল নয়।'),
  checked: L('লাইন যাচাই', 'Lines checked', 'Line যাচাই'), unm: L('মিলেনি', 'Unmatched', 'মিলেনি'),
  sync: L('মিলে যাওয়া লিংক নিশ্চিত করুন', 'Confirm links that now match', 'মিলে যাওয়া link confirm করুন'), synced: L('নিশ্চিত হয়েছে', 'Confirmed', 'Confirmed'),
  form: L('ফর্ম', 'Form', 'Form'), line: L('লাইন', 'Line', 'Line'), qty: L('পরিমাণ', 'Qty', 'Qty'), linked: L('লিংক আছে', 'link exists', 'link আছে'),
  toRules: L('নিয়ম ও পরামর্শ', 'Rules and recommendations', 'Rule ও পরামর্শ'),
  fgIntro: L('প্রতিটি সুইচের পাশে সিস্টেমের পরামর্শ আছে। পরামর্শ মানা বাধ্যতামূলক নয়।', 'Each switch shows the system recommendation next to it. Following it is optional.', 'প্রতিটি switch-এর পাশে system-এর পরামর্শ আছে। মানা বাধ্যতামূলক নয়।'),
  k_form_051_mode: L('ফর্ম 05-1 stock-এ গেলে', 'When form 05-1 posts to stock', 'Form 05-1 stock-এ গেলে'),
  k_transit_short_mode: L('কম পৌঁছানো মাল', 'Goods that arrive short', 'কম পৌঁছানো মাল'),
  k_transit_open_hours: L('ট্রানজিট কত ঘণ্টা খোলা থাকলে সতর্কতা', 'Hours in transit before an alert', 'Transit কত ঘণ্টা খোলা থাকলে alert'),
  k_offline_soft_stock: L('অফলাইন sale-এ stock কম হলেও গ্রহণ', 'Accept an offline sale even if stock is short', 'Offline sale-এ stock কম হলেও গ্রহণ'),
  c_reference: L('শুধু রেফারেন্স (আগের মতো)', 'Reference only (as before)', 'Reference only (আগের মতো)'), c_post: L('উপকরণ বাদ দিয়ে পোস্ট', 'Post (ingredients go out)', 'Post (ingredient বাদ)'), c_refuse: L('আটকান', 'Refuse', 'Refuse'),
  c_keep: L('ট্রানজিটেই রাখুন (আগের মতো)', 'Keep in transit (as before)', 'Transit-এই রাখুন (আগের মতো)'), c_loss: L('লস ধরুন', 'Book as loss', 'Loss ধরুন'),
  hours: L('ঘণ্টা', 'hours', 'ঘণ্টা'),
  elIntro: L('অনুমোদনের সময় দেখুন: একই দিনের quick খরচ কি এই ভাউচারের টাকা আগেই গুনেছে? সব লাইন মিললে ভাউচার "লক করা কপি" হয়, দিনের খাতায় টাকা একবার গোনা হয়।',
    'Check before approval: did a same-day quick expense already count this money? When every line matches, the voucher becomes the locked copy and the day book counts it once.',
    'Approval-এর সময় দেখুন: একই দিনের quick expense কি এই voucher-এর টাকা আগেই গুনেছে? সব line মিললে voucher "locked copy" হয়, day book-এ টাকা একবার গোনা হয়।'),
  check: L('মিলিয়ে দেখুন', 'Check', 'Check'), link: L('লিংক করুন (একবার গোনা)', 'Link (count once)', 'Link করুন (একবার গোনা)'), noteL: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'),
  matched: L('মিলেছে', 'matched', 'matched'), head: L('খাত', 'Head', 'Head'), amount: L('টাকা', 'Amount', 'Amount'), quick: L('quick খরচ', 'quick expense', 'quick expense'),
  recLink: L('পরামর্শ: লিংক করুন — প্রতিটি লাইনের জন্য মিলে যাওয়া quick খরচ আছে।', 'Recommendation: link - every line has a matching quick expense.', 'পরামর্শ: link করুন — প্রতিটি line-এর জন্য matching quick expense আছে।'),
  recNo: L('পরামর্শ: লিংক করবেন না — কিছু লাইনের মিলে যাওয়া quick খরচ নেই (সার্ভার এটা মানবে না)।', 'Recommendation: do not link - some lines have no matching quick expense (the server will refuse).', 'পরামর্শ: link করবেন না — কিছু line-এর matching quick expense নেই (server মানবে না)।'),
  recDone: L('আগেই লিংক করা আছে — আর কিছু করার নেই।', 'Already linked - nothing more to do.', 'আগেই link করা আছে — আর কিছু করার নেই।'),
  linkedOk: L('লিংক হয়েছে', 'Linked', 'Linked'), noVouchers: L('অপেক্ষমাণ কোনো 10-2 ভাউচার নেই', 'No 10-2 vouchers waiting', 'অপেক্ষমাণ কোনো 10-2 voucher নেই'),
  trOpen: L('এখনও পথে', 'Still on the way', 'এখনও পথে'), trShort: L('কম পৌঁছেছে — এখনও খাতায় তোলা হয়নি', 'Received short - not booked yet', 'কম পৌঁছেছে — এখনও book হয়নি'),
  sent: L('পাঠানো', 'Sent', 'Sent'), recv: L('পেয়েছে', 'Received', 'Received'), short: L('কম', 'Short', 'Short'), value: L('মূল্য', 'Value', 'Value'), hrs: L('ঘণ্টা', 'Hours', 'Hours'),
  over: L('সীমা ছাড়িয়েছে', 'over the limit', 'সীমা ছাড়িয়েছে'), limit: L('সীমা', 'Limit', 'Limit'), noLimit: L('সীমা বসানো নেই — সতর্কতা বন্ধ', 'No limit set - no alert', 'Limit বসানো নেই — alert বন্ধ'),
  fromTo: L('থেকে →', 'From →', 'From →'), resolve: L('লস হিসেবে তুলুন', 'Book as loss', 'Loss হিসেবে তুলুন'), why: L('কারণ লিখুন (বাধ্যতামূলক)', 'Reason (required)', 'কারণ লিখুন (required)'),
  trHint: L('ঘাটতি তুললে ট্রান্সফারের খরচে stock-এ loss সারি যায়; একবারই হয়।', 'Booking writes a loss row at the transfer cost; it can happen once only.', 'Book করলে transfer-এর cost-এ loss row যায়; একবারই হয়।'),
  booked: L('লস তোলা হয়েছে', 'Loss booked', 'Loss book হয়েছে'), dup: L('আগেই তোলা আছে', 'Already booked', 'আগেই book আছে'),
  ownerOnly: L('শুধু মালিক দেখতে পারেন', 'Owner only', 'শুধু owner দেখতে পারেন'),
};
const T = (k) => lab(X[k]);
const pick = (o, k) => lab({ bn: o[k + '_bn'], mix: o[k + '_mix'] || o[k + '_bn'], en: o[k + '_en'] || o[k + '_bn'] });
const WARN = (m) => `<div class="notice warn">${esc(m)}</div>`;
const fail = (e) => W.err(e);
const nav = () => W.links([['formguard', X.tFg], ['unmatched', X.tUn], ['expenselink', X.tEl], ['transitshort', X.tTr]]);
const D = { from: null, to: null, loc: '' };

// ---------------- #/unmatched ----------------
async function viewUnmatched() {
  await W.locs();
  D.from = D.from || new Date(Date.now() + 6 * 3600e3 - 30 * 864e5).toISOString().slice(0, 10); D.to = D.to || W.today();
  shell(T('tUn'), `${nav()}<p class="muted">${esc(T('unIntro'))}</p>
    <div class="row wrap"><label>${esc(T('from'))}<input type="date" id="wfg_f" value="${esc(D.from)}"></label><label>${esc(T('to'))}<input type="date" id="wfg_t" value="${esc(D.to)}"></label>
    <select id="wfg_l">${W.locOpts(D.loc, true)}</select></div>
    <div class="row"><button class="primary full" data-act="wfg_un_go">${esc(T('show'))}</button>${W.own() ? `<button class="full" data-act="wfg_sync">${esc(T('sync'))}</button>` : ''}</div>
    <div id="wfg_body"><p class="muted">${esc(W.T('loading'))}</p></div>`, true);
  return drawUnmatched();
}
async function drawUnmatched() {
  const el = $('#wfg_body'); if (!el) return;
  const { data, error } = await sb.rpc('unmatched_forms', { p_from: D.from, p_to: D.to, p_loc: D.loc === '' ? null : Number(D.loc) });
  if (error) { el.innerHTML = WARN(W.errText(error) || error.message); return; }
  const d = data || {}, rows = d.rows || [];
  el.innerHTML = `<div class="card"><b>${esc(T('unm'))}: ${esc(String(d.lines_unmatched ?? 0))}</b> <span class="muted">/ ${esc(T('checked'))}: ${esc(String(d.lines_checked ?? 0))}</span></div>
    ${rows.length ? rows.map((r) => `<div class="card"><div><b>${esc(r.form_code)}</b> #${esc(String(r.serial))} · ${esc(W.day(r.entry_date))} · ${esc(W.locName(r.location_id))}</div>
      <div>${esc(T('line'))} ${esc(String(r.line_no))}: ${esc(r.item_code)} · ${esc(T('qty'))} ${esc(W.q(r.qty))}${r.link_id ? ` <span class="muted">(${esc(T('linked'))})</span>` : ''}</div></div>`).join('') : `<p class="muted center pad">${esc(W.T('none'))}</p>`}
    <p class="muted">${esc(T('unNote'))}</p>`;
}

// ---------------- #/formguard ----------------
const CH = {
  form_051_mode: [{ v: 'reference', l: X.c_reference }, { v: 'post', l: X.c_post }, { v: 'refuse', l: X.c_refuse }],
  transit_short_mode: [{ v: 'keep_in_transit', l: X.c_keep }, { v: 'loss', l: X.c_loss }],
};
const KIND = { form_051_mode: 'choice', transit_short_mode: 'choice', transit_open_hours: 'number', offline_soft_stock: 'switch' };
function recCards(recs, only) {
  return (recs || []).filter((r) => !only || only.indexOf(r.key) >= 0).map((r) => W.recCard({ key: r.key, kind: KIND[r.key] || 'switch', label: X['k_' + r.key] ? T('k_' + r.key) : r.key, current: r.current, recommended: r.recommended,
    reason: pick(r, 'reason'), choices: CH[r.key], unit: r.key === 'transit_open_hours' ? T('hours') : '' })).join('');
}
async function viewGuard() {
  shell(T('tFg'), `${nav()}<div id="wfg_body"><p class="muted">${esc(W.T('loading'))}</p></div>`, true);
  W.setRedraw(drawGuard); return drawGuard();
}
async function drawGuard() {
  const el = $('#wfg_body'); if (!el) return;
  if (!W.own()) { el.innerHTML = WARN(T('ownerOnly')); return; }
  const { data, error } = await sb.rpc('form_guard_recommendations');
  if (error) { el.innerHTML = WARN(W.errText(error) || error.message); return; }
  el.innerHTML = `<p class="muted">${esc(T('fgIntro'))}</p>${recCards(data)}`;
}

// ---------------- #/expenselink ----------------
async function viewLink() {
  shell(T('tEl'), `${nav()}<p class="muted">${esc(T('elIntro'))}</p><div id="wfg_body"><p class="muted">${esc(W.T('loading'))}</p></div>`, true);
  await W.locs();
  const el = $('#wfg_body'); if (!el) return;
  const { data, error } = await sb.from('entries').select('id,serial,entry_date,location_id,status').eq('form_code', '10-2').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).limit(40);
  if (error) { el.innerHTML = WARN(W.errText(error) || error.message); return; }
  const rows = data || [];
  el.innerHTML = rows.length ? rows.map((r) => `<div class="card"><div><b>10-2</b> #${esc(String(r.serial))} · ${esc(W.day(r.entry_date))} · ${esc(W.locName(r.location_id))} · <span class="muted">${esc(r.status)}</span></div>
    <button class="full" data-act="wfg_el_check" data-v="${esc(r.id)}">${esc(T('check'))}</button><div id="wfg_r_${esc(r.id)}"></div></div>`).join('') : `<p class="muted center pad">${esc(T('noVouchers'))}</p>`;
}
async function elCheck(id) {
  const box = $('#wfg_r_' + id); if (!box) return;
  const { data, error } = await sb.rpc('suggest_expense_link', { p_entry: id });
  if (error) { box.innerHTML = WARN(W.errText(error) || error.message); return; }
  const adv = data.is_shadow ? T('recDone') : data.fully_covered ? T('recLink') : T('recNo');
  box.innerHTML = `<div class="notice info">${esc(adv)}</div>
    ${(data.lines || []).map((l) => `<div class="row between"><span>${esc(T('head'))}: ${esc(l.head)} · ${esc(W.q(l.amount))}</span><span class="${l.quick_id ? '' : 'muted'}">${l.quick_id ? '✓ ' + esc(T('quick')) : '✗'}</span></div>`).join('')}
    <div class="muted">${esc(T('matched'))}: ${esc(String(data.matched))} / ${esc(String((data.lines || []).length))}</div>
    ${data.is_shadow ? '' : `<label>${esc(T('noteL'))}</label><input id="wfg_n_${esc(id)}" maxlength="200"><button class="primary full" data-act="wfg_el_apply" data-v="${esc(id)}">${esc(T('link'))}</button>`}`;
}
async function elApply(id) {
  const note = (($('#wfg_n_' + id) || {}).value || '').trim() || null;
  const { data, error } = await sb.rpc('expense_link_apply', { p_entry: id, p_note: note });
  if (error) return fail(error);
  toast(data && data.noop ? T('recDone') : T('linkedOk') + (data && data.linked ? ' (' + data.linked + ')' : ''));
  return elCheck(id);
}

// ---------------- #/transitshort ----------------
async function viewTransit() {
  shell(T('tTr'), `${nav()}<div id="wfg_rec"></div><div id="wfg_body"><p class="muted">${esc(W.T('loading'))}</p></div>`, true);
  W.setRedraw(viewTransit); await W.locs();
  const el = $('#wfg_body'); if (!el) return;
  if (W.own()) { const r = await sb.rpc('form_guard_recommendations'); if (!r.error && $('#wfg_rec')) $('#wfg_rec').innerHTML = recCards(r.data, ['transit_short_mode', 'transit_open_hours']); }
  const [o, s] = await Promise.all([sb.rpc('transit_open_list', { p_loc: null }), sb.rpc('transit_short_open', { p_loc: null })]);
  if (o.error && s.error) { el.innerHTML = WARN(W.errText(o.error) || o.error.message); return; }
  const open = (o.data && o.data.rows) || [], lim = o.data ? o.data.limit_hours : null, sh = s.data || [];
  el.innerHTML = `<h3>${esc(T('trOpen'))}</h3><p class="muted">${esc(T('limit'))}: ${lim === null || lim === undefined ? esc(T('noLimit')) : esc(String(lim)) + ' ' + esc(T('hours'))}</p>
    ${open.length ? open.map((r) => `<div class="card ${r.over_limit ? 'bad' : ''}"><div><b>${esc(W.nmItem(r))}</b> · ${esc(W.q(r.qty))}</div>
      <div class="muted">${esc(W.locName(r.from_location_id))} → ${esc(W.locName(r.to_location_id))} · ${esc(T('hrs'))}: ${esc(String(r.hours))}${r.over_limit ? ' · <b>' + esc(T('over')) + '</b>' : ''}</div></div>`).join('') : `<p class="muted">${esc(W.T('none'))}</p>`}
    <h3>${esc(T('trShort'))}</h3><p class="muted">${esc(T('trHint'))}</p>
    ${sh.length ? sh.map((r) => `<div class="card"><div><b>${esc(W.nmItem(r))}</b></div>
      <div>${esc(T('sent'))} ${esc(W.q(r.sent))} · ${esc(T('recv'))} ${esc(W.q(r.received))} · <b>${esc(T('short'))} ${esc(W.q(r.short))}</b>${r.value === null || r.value === undefined ? '' : ' · ' + esc(T('value')) + ' ' + esc(W.q(r.value))}</div>
      <div class="muted">${esc(W.locName(r.from_location_id))} → ${esc(W.locName(r.to_location_id))} · ${esc(W.day(r.received_at))}</div>
      <button class="full" data-act="wfg_tr_resolve" data-v="${esc(r.transfer_id)}">${esc(T('resolve'))}</button></div>`).join('') : `<p class="muted">${esc(W.T('none'))}</p>`}`;
}
function trResolve(id) {
  openSheet(`<h2>${esc(T('resolve'))}</h2><p class="muted">${esc(T('trHint'))}</p><label>${esc(T('why'))}</label><textarea id="wfg_why" rows="3"></textarea>
    <div class="row" style="margin-top:10px"><button class="full" data-act="closesheet">${esc(W.T('close'))}</button><button class="primary full" data-act="wfg_tr_go" data-v="${esc(id)}">${esc(T('resolve'))}</button></div>`);
}
async function trGo(id) {
  const note = (($('#wfg_why') || {}).value || '').trim();
  if (note.length < 3) return toast(W.errText({ message: 'note_needed' }));
  const { data, error } = await sb.rpc('transit_short_resolve', { p_id: id, p_note: note });
  if (error) return fail(error);
  closeSheet(); toast(data && data.dup ? T('dup') : T('booked')); return viewTransit();
}

A.H = A.H || {};
Object.assign(A.H, {
  wfg_un_go: () => { D.from = ($('#wfg_f') || {}).value || D.from; D.to = ($('#wfg_t') || {}).value || D.to; D.loc = ($('#wfg_l') || {}).value || ''; return drawUnmatched(); },
  wfg_sync: async () => { const { data, error } = await sb.rpc('unmatched_forms_sync'); if (error) return fail(error); toast(T('synced') + ': ' + (data ? data.confirmed : 0)); return drawUnmatched(); },
  wfg_el_check: (a) => elCheck(a.dataset.v), wfg_el_apply: (a) => elApply(a.dataset.v),
  wfg_tr_resolve: (a) => trResolve(a.dataset.v), wfg_tr_go: (a) => trGo(a.dataset.v),
});
B.formscreens = { X, T, recCards, CH, KIND };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { unmatched: viewUnmatched, formguard: viewGuard, expenselink: viewLink, transitshort: viewTransit });
})();
