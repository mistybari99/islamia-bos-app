/* Islamia BOS · Artisan-wise recipe book (#/recipebook): artisan register (owner), recipe list with artisan + approval, method steps editor, recipe book (print / share).
   Server: supabase/phase73.sql (artisan_list / artisan_register / artisan_save / artisan_set_active / recipe_set_artisan / recipe_unassigned / recipe_steps_save /
   recipe_labour_suggest / recipe_approve / recipe_book). The artisan NAME is shown only inside the owner's register tab - the book, the pickers and the print show the
   artisan id (artisan-N) + post only. Cost columns appear only when the server returns them (cost right). Minutes x people is a SUGGESTION, never a cost.
   Loaded after recipes.js. Handlers are prefixed rb_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
// owner approving his own change: the server (phase87) allows it and returns a NON-blocking suggestion to ask another approver
const selfHint = (d) => (d && d.suggestion ? ' · ' + lab({ bn: d.suggestion_bn, mix: d.suggestion_mix, en: d.suggestion_en }) : '');
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q2 = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const owner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  title: L('কারিগরের রেসিপি বই', 'Artisan recipe book', 'Artisan-এর recipe book'),
  tBook: L('রেসিপি বই', 'Recipe book', 'Recipe book'), tAll: L('সব রেসিপি', 'All recipes', 'সব recipe'), tUn: L('কারিগর নির্ধারিত নয়', 'No artisan set', 'কারিগর নির্ধারিত নয়'), tReg: L('কারিগর রেজিস্টার', 'Artisan register', 'Artisan register'),
  pick: L('কারিগর বাছুন', 'Choose an artisan', 'Artisan বাছুন'), show: L('বই দেখান', 'Show the book', 'Book দেখান'), withCost: L('খরচসহ', 'with cost', 'cost সহ'), print: L('প্রিন্ট', 'Print', 'Print'), share: L('শেয়ার', 'Share', 'Share'),
  copied: L('লেখা কপি হয়েছে', 'Text copied', 'Text copy হয়েছে'), none: L('কিছু নেই ✓', 'Nothing ✓', 'কিছু নেই ✓'), noRecipes: L('এই কারিগরের কোনো চালু রেসিপি নেই', 'This artisan has no active recipe', 'এই artisan-এর active recipe নেই'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), noperm: L('অনুমতি নেই — রেসিপি দেখার অনুমতি (recipe_view) লাগবে', 'Not allowed — the recipe_view permission is needed', 'অনুমতি নেই — recipe_view লাগবে'),
  version: L('ভার্সন', 'Version', 'Version'), approvedOn: L('অ্যাপ্রুভড', 'Approved', 'Approved'), notApproved: L('অ্যাপ্রুভ বাকি', 'Not approved yet', 'Approve বাকি'), yield: L('একবারে তৈরি', 'Yield', 'Yield'),
  ing: L('উপকরণ', 'Ingredients', 'Ingredients'), qty: L('Qty', 'Qty', 'Qty'), waste: L('অপচয় %', 'Waste %', 'Waste %'), needData: L('তথ্য দরকার', 'Data needed', 'Data দরকার'),
  steps: L('বানানোর ধাপ', 'Method steps', 'Method steps'), min: L('মিনিট', 'min', 'min'), ppl: L('জন', 'people', 'people'), fuel: L('জ্বালানি', 'Fuel', 'Fuel'), flame: L('আঁচ / তাপমাত্রা', 'Flame / temperature', 'Flame / temp'),
  equip: L('যন্ত্র', 'Equipment', 'Equipment'), qc: L('মান পরীক্ষা', 'Quality check', 'Quality check'), who: L('দায়িত্বে', 'In charge', 'In charge'), formRef: L('প্রিন্ট রেসিপি কার্ড নং', 'Printed recipe card no.', 'Printed recipe card no.'),
  suggest: L('অনুমান: শ্রম-ঘণ্টা', 'Suggested labour hours', 'অনুমান: labour hours'), suggestNote: L('শুধু অনুমান — কস্টে যোগ হয় না', 'only a suggestion — not added to any cost', 'শুধু suggestion — cost-এ যোগ হয় না'),
  incomplete: L('অসম্পূর্ণ', 'Incomplete', 'অসম্পূর্ণ'), costHead: L('কস্ট (গোপন)', 'Cost (confidential)', 'Cost (গোপন)'), batchCost: L('ব্যাচ কস্ট', 'Batch cost', 'Batch cost'), unitCost: L('প্রতি একক', 'Per unit', 'Per unit'),
  open: L('খুলুন', 'Open', 'Open'), artisan: L('কারিগর', 'Artisan', 'Artisan'), blank: L('— নির্ধারিত নয় —', '— not set —', '— set নয় —'), addNew: L('☐ অন্য: নতুন কারিগর যোগ', '☐ Other: add a new artisan', '☐ অন্য: নতুন artisan যোগ'),
  ownerAdds: L('নতুন কারিগর মালিক যোগ করবেন', 'The owner adds a new artisan', 'নতুন artisan owner যোগ করবেন'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), save: L('সেভ', 'Save', 'Save'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'),
  addStep: L('ধাপ যোগ করো', 'Add a step', 'ধাপ যোগ করো'), step: L('ধাপ', 'Step', 'Step'), stepName: L('ধাপের নাম', 'Step name', 'Step name'), desc: L('বিবরণ (নিজের ভাষায় লিখুন)', 'Description (free text)', 'বিবরণ (free text)'),
  mins: L('সময় (মিনিট)', 'Time (minutes)', 'Time (minutes)'), people: L('কতজন লাগে', 'People needed', 'People needed'), up: L('উপরে', 'Up', 'Up'), down: L('নিচে', 'Down', 'Down'), rm: L('সরান', 'Remove', 'Remove'),
  gas: L('গ্যাস', 'Gas', 'Gas'), electric: L('বিদ্যুৎ', 'Electric', 'Electric'), fuelOther: L('☐ অন্য: ______', '☐ Other: ______', '☐ অন্য: ______'), fuelNone: L('— জ্বালানি —', '— fuel —', '— fuel —'),
  approve: L('অ্যাপ্রুভ করুন', 'Approve', 'Approve'), approved: L('অ্যাপ্রুভড', 'Approved', 'Approved'), frozen: L('অ্যাপ্রুভড — বদলাতে নতুন ভার্সন বানান', 'Approved — make a new version to change it', 'Approved — বদলাতে নতুন version'),
  history: L('বদলের ইতিহাস', 'Change history', 'বদলের history'), kind: L('ধরন', 'Kind', 'Kind'), when: L('কখন', 'When', 'When'), unassigned: L('কারিগর নির্ধারিত নয়', 'No artisan set', 'কারিগর নির্ধারিত নয়'),
  rNew: L('নতুন কারিগর', 'New artisan', 'নতুন artisan'), post: L('পদ', 'Post', 'Post'), work: L('কাজের ধরন', 'Work type', 'Work type'), place: L('জায়গা', 'Place', 'Place'), name: L('নাম (শুধু এই রেজিস্টারে)', 'Name (only in this register)', 'নাম (শুধু এই register-এ)'),
  otherTxt: L('অন্য — লিখুন', 'Other — write it', 'অন্য — লিখুন'), login: L('লগইন (ঐচ্ছিক)', 'Login (optional)', 'Login (optional)'), retire: L('অবসর', 'Retire', 'Retire'), reactivate: L('আবার চালু', 'Re-activate', 'আবার চালু'),
  why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), retired: L('অবসরে', 'Retired', 'Retired'), nRec: L('রেসিপি', 'recipes', 'recipes'), nameNote: L('নাম শুধু এখানে; অন্য কোথাও কারিগরের আইডি ও পদ দেখায়।', 'The name is shown only here; elsewhere only the artisan id and post.', 'নাম শুধু এখানে; অন্যত্র id ও post।'),
  needName: L('নাম লিখুন', 'Write the name', 'নাম লিখুন'), needStepName: L('প্রতিটি ধাপের নাম লিখুন', 'Every step needs a name', 'প্রতিটি step-এর নাম'),
  sqlMissing: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase73)', 'The database part is not installed yet (phase73)', 'Database অংশ চালু হয়নি (phase73)'),
};
const POST = { karigor: L('কারিগর', 'Artisan', 'কারিগর'), chef: L('শেফ', 'Chef', 'শেফ'), asst_karigor: L('সহকারী কারিগর', 'Assistant artisan', 'সহকারী কারিগর'), other: L('☐ অন্য', '☐ Other', '☐ অন্য') };
const WORK = { mishti: L('মিষ্টি', 'Sweets', 'মিষ্টি'), doi: L('দই', 'Curd', 'দই'), jilapi: L('জিলাপি', 'Jilapi', 'জিলাপি'), cake: L('কেক', 'Cake', 'কেক'), bakery: L('বেকারি', 'Bakery', 'বেকারি'), other: L('☐ অন্য', '☐ Other', '☐ অন্য') };
const T = (k) => lab(X[k]);
const ERRS = { recipe_approved: L('অ্যাপ্রুভড ভার্সন বদলানো যায় না', 'An approved version cannot be changed', 'Approved version বদলানো যায় না'),
  self_approve_refused: L('যে বদলেছে সে অ্যাপ্রুভ করতে পারবে না — অন্য অনুমোদনকারী লাগবে', 'The person who changed it cannot approve it', 'যে বদলেছে সে approve করতে পারবে না'),
  recipe_not_approved: L('রেসিপি অ্যাপ্রুভড নয়', 'The recipe is not approved', 'Recipe approved নয়'), step_name_needed: L('প্রতিটি ধাপের নাম লাগবে', 'Every step needs a name', 'প্রতিটি step-এর নাম'),
  fuel_other_needed: L('অন্য জ্বালানির নাম লিখুন', 'Write the other fuel', 'অন্য fuel লিখুন'), post_other_needed: L('অন্য পদ লিখুন', 'Write the other post', 'অন্য post লিখুন'), work_other_needed: L('অন্য কাজের ধরন লিখুন', 'Write the other work type', 'অন্য work type লিখুন'),
  artisan_not_found: L('কারিগর পাওয়া যায়নি বা অবসরে', 'Artisan not found or retired', 'Artisan নেই বা retired') };
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERRS)) if (m.indexOf(k) >= 0) return toast(lab(ERRS[k])); if (/function .* does not exist|schema cache/i.test(m)) return toast(T('sqlMissing')); return fail(e); };
const aLabel = (a) => `${a.code} · ${a.post === 'other' ? (a.post_other || lab(POST.other)) : lab(POST[a.post] || POST.other)} · ${a.work_type === 'other' ? (a.work_other || lab(WORK.other)) : lab(WORK[a.work_type] || WORK.other)}${a.location_id && D.locs[a.location_id] ? ' · ' + D.locs[a.location_id] : ''}${a.active === false ? ' (' + T('retired') + ')' : ''}`;
const fuelName = (s) => (s.fuel === 'gas' ? T('gas') : s.fuel === 'electric' ? T('electric') : s.fuel === 'other' ? (s.fuel_other || T('fuelOther')) : '');
const D = { tab: 'book', artisans: [], items: {}, locs: {}, recipes: [], reg: [], un: [], book: null, aid: null, withCost: false, canReg: false, canCost: false, st: null, users: [] };

/* ---------- loading ---------- */
async function loadBase() {
  const [al, it, lo] = await Promise.all([sb.rpc('artisan_list', { p_include_retired: true }), sb.from('items').select('id,code,name_bn,name_en').eq('item_type', 'finished_good'), sb.from('locations').select('id,name_bn,name_en').order('id')]);
  if (al.error) throw al.error;
  D.artisans = al.data || [];
  D.items = Object.fromEntries((it.data || []).map((x) => [x.id, x]));
  D.locs = Object.fromEntries((lo.data || []).map((l) => [l.id, lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn })]));
  D.canReg = owner(); D.canCost = owner();
  try { if (!D.canReg) D.canReg = !!(await A.hasAnyGrant(['artisan_manage'])); } catch (e) { /* keep false */ }
  try { if (!D.canCost) D.canCost = !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { /* keep false */ }
}
async function loadAll() {
  const r = await sb.from('recipes').select('id,item_id,version,active,approved_at,artisan_id,yield_qty,used_at,form_ref').order('item_id').order('version', { ascending: false });
  if (r.error) throw r.error; D.recipes = r.data || [];
}
const itemName = (id) => { const i = D.items[id]; return i ? i.code + ' · ' + lab({ bn: i.name_bn, mix: i.name_bn, en: i.name_en || i.name_bn }) : '—'; };

/* ---------- tabs ---------- */
function tabsHTML() {
  const t = [['book', 'tBook'], ['all', 'tAll'], ['un', 'tUn']].concat(D.canReg ? [['reg', 'tReg']] : []);
  return `<div class="tabs rb-noprint" style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:8px">${t.map((x) => `<button type="button" data-act="rb_tab" data-v="${x[0]}" class="${D.tab === x[0] ? 'on' : ''}" style="min-width:0;flex:1 1 40%">${esc(T(x[1]))}</button>`).join('')}</div>`;
}
function draw() {
  const el = $('#rb_body'); if (!el) return;
  el.innerHTML = tabsHTML() + `<div id="rb_pane">${D.tab === 'book' ? paneBook() : D.tab === 'all' ? paneAll() : D.tab === 'un' ? paneUn() : paneReg()}</div>`;
}
const css = () => { if ($('#rb_css')) return; const s = document.createElement('style'); s.id = 'rb_css';
  s.textContent = '.rb-doc{background:var(--card,#fff);border:1px solid var(--line,#ddd);border-radius:12px;padding:12px;margin:10px 0}.rb-doc table{width:100%;border-collapse:collapse;font-size:.9rem}.rb-doc td,.rb-doc th{border-bottom:1px solid var(--line,#ddd);padding:4px 6px;text-align:left;vertical-align:top;word-break:break-word}.rb-step{border-left:3px solid var(--gold,#b8913c);padding:2px 0 2px 8px;margin:6px 0}.rb-stepcard{border:1px solid var(--line,#ddd);border-radius:12px;padding:10px;margin:8px 0}.rb-stepcard input,.rb-stepcard select,.rb-stepcard textarea{width:100%;box-sizing:border-box;margin:3px 0}#rb_print{display:none}@media print{html body>#rb_print{display:block!important;color:#000;background:#fff}#rb_print .rb-doc{border:0;break-inside:avoid;background:#fff}#rb_print .rb-noprint{display:none!important}}';
  document.head.appendChild(s); };

/* ---------- book tab ---------- */
function paneBook() {
  const opts = D.artisans.map((a) => `<option value="${a.id}" ${String(D.aid) === String(a.id) ? 'selected' : ''}>${esc(aLabel(a))}</option>`).join('');
  return `<div class="card stack rb-noprint"><label>${esc(T('pick'))}<select id="rb_art"><option value="">—</option>${opts}</select></label>
    ${D.canCost ? `<label class="row"><input type="checkbox" id="rb_cost" ${D.withCost ? 'checked' : ''}> ${esc(T('withCost'))}</label>` : ''}
    <button type="button" class="btn primary full" data-act="rb_show">${esc(T('show'))}</button></div>${D.book ? bookHTML(D.book) : ''}`;
}
function stepHTML(s) {
  const bits = [s.minutes === null || s.minutes === undefined ? '' : q2(s.minutes) + ' ' + T('min'), s.people === null || s.people === undefined ? '' : q2(s.people) + ' ' + T('ppl'), fuelName(s) ? T('fuel') + ': ' + fuelName(s) : '',
    s.flame_note ? T('flame') + ': ' + s.flame_note : '', s.equipment ? T('equip') + ': ' + s.equipment : '', s.qc_note ? T('qc') + ': ' + s.qc_note : '',
    s.resp_post ? T('who') + ': ' + (s.resp_post === 'other' ? (s.resp_other || lab(POST.other)) : lab(POST[s.resp_post])) : ''].filter(Boolean);
  return `<div class="rb-step"><b>${esc(T('step'))} ${s.step_no}: ${esc(s.step_name)}</b>${s.description ? `<div>${esc(s.description)}</div>` : ''}<div class="muted" style="font-size:.85rem">${esc(bits.join(' · '))}</div></div>`;
}
function recipeDoc(r, withCost) {
  const lines = (r.lines || []).map((l) => `<tr><td>${esc(l.code)} ${esc(lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }))}</td><td>${q2(l.qty)} ${esc(l.unit || '')}</td><td>${l.waste_pct === null || l.waste_pct === undefined ? `<span class="chip warn">${esc(T('needData'))}</span>` : q2(l.waste_pct) + '%'}</td></tr>`).join('');
  const lab_ = r.labour || {};
  const cost = withCost && r.cost ? `<div class="card"><b>${esc(T('costHead'))}</b><div>${r.cost.error ? esc(r.cost.error) : `${esc(T('batchCost'))}: ${money(r.cost.batch_cost)} · ${esc(T('unitCost'))}: ${money(r.cost.unit_cost)}${r.cost.complete === false ? ` <span class="chip warn">${esc(T('incomplete'))}</span>` : ''}`}</div></div>` : '';
  return `<div class="rb-doc"><div class="row between wrap"><b>${esc(r.code)} · ${esc(lab({ bn: r.name_bn, mix: r.name_bn, en: r.name_en || r.name_bn }))}</b>
      <span class="chip ${r.approved ? 'ok' : 'warn'}">${esc(r.approved ? T('approvedOn') + ' ' + String(r.approved_at || '').slice(0, 10) : T('notApproved'))}</span></div>
    <div class="muted">${esc(T('version'))} ${r.version} · ${esc(T('yield'))}: ${q2(r.yield_qty)} ${esc(r.yield_unit || '')}${r.form_ref ? ' · ' + esc(T('formRef')) + ': ' + esc(r.form_ref) : ''}</div>
    <h4>${esc(T('ing'))}</h4><table><tr><th></th><th>${esc(T('qty'))}</th><th>${esc(T('waste'))}</th></tr>${lines}</table>
    <h4>${esc(T('steps'))}</h4>${(r.steps || []).length ? r.steps.map(stepHTML).join('') : `<div class="muted">${esc(T('incomplete'))}</div>`}
    ${(r.steps || []).length ? `<div class="muted">${esc(T('suggest'))}: ${q2(lab_.suggested_labour_hours)}${lab_.incomplete ? ` <span class="chip warn">${esc(T('incomplete'))}</span>` : ''} · ${esc(T('suggestNote'))}</div>` : ''}${cost}</div>`;
}
function bookHTML(b) {
  const a = b.artisan;
  return `<div id="rb_doc"><div class="row between wrap"><h3 style="margin:6px 0">${esc(aLabel(a))}</h3><div class="row rb-noprint"><button type="button" class="mini" data-act="rb_print">${esc(T('print'))}</button><button type="button" class="mini" data-act="rb_share">${esc(T('share'))}</button></div></div>
    ${b.recipes.length ? b.recipes.map((r) => recipeDoc(r, b.with_cost)).join('') : `<p class="muted">${esc(T('noRecipes'))}</p>`}</div>`;
}
function bookText(b) {
  const out = [aLabel(b.artisan)];
  (b.recipes || []).forEach((r) => {
    out.push('', `${r.code} ${r.name_bn || ''} — ${T('version')} ${r.version} — ${r.approved ? T('approvedOn') + ' ' + String(r.approved_at || '').slice(0, 10) : T('notApproved')}`, `${T('yield')}: ${q2(r.yield_qty)} ${r.yield_unit || ''}`);
    (r.lines || []).forEach((l) => out.push(`  - ${l.code} ${l.name_bn || ''}: ${q2(l.qty)} ${l.unit || ''}${l.waste_pct === null || l.waste_pct === undefined ? '' : ' (' + q2(l.waste_pct) + '%)'}`));
    (r.steps || []).forEach((s) => out.push(`  ${s.step_no}. ${s.step_name}${s.description ? ' — ' + s.description : ''}`));
    if (b.with_cost && r.cost && !r.cost.error) out.push(`  ${T('batchCost')}: ${money(r.cost.batch_cost)}`);
  });
  return out.join('\n');
}

/* ---------- all recipes / unassigned ---------- */
function artSelect(cur, rowId) {
  const opts = D.artisans.filter((a) => a.active || String(a.id) === String(cur)).map((a) => `<option value="${a.id}" ${String(cur) === String(a.id) ? 'selected' : ''}>${esc(aLabel(a))}</option>`).join('');
  return `<select data-rb-art="${esc(rowId)}"><option value="">${esc(T('blank'))}</option>${opts}<option value="__new">${esc(T('addNew'))}</option></select>`;
}
function paneAll() {
  if (!D.recipes.length) return `<p class="muted">${esc(T('none'))}</p>`;
  return D.recipes.map((r) => { const a = D.artisans.find((x) => x.id === r.artisan_id);
    return `<div class="card stack"><div class="row between wrap"><b>${esc(itemName(r.item_id))} · v${r.version}${r.active ? '' : ' (off)'}</b><span class="chip ${r.approved_at ? 'ok' : 'warn'}">${esc(r.approved_at ? T('approved') : T('notApproved'))}</span></div>
      <div class="muted">${esc(T('artisan'))}: ${a ? esc(aLabel(a)) : `<span class="chip warn">${esc(T('unassigned'))}</span>`}</div>
      <button type="button" class="btn" data-act="rb_open" data-id="${esc(r.id)}">${esc(T('open'))}</button></div>`; }).join('');
}
function paneUn() {
  if (!D.un.length) return `<p class="muted">${esc(T('none'))}</p>`;
  return D.un.map((r) => `<div class="card stack"><b>${esc(r.code)} · ${esc(lab({ bn: r.name_bn, mix: r.name_bn, en: r.name_en || r.name_bn }))} · v${r.version}</b>${artSelect('', r.recipe_id)}</div>`).join('');
}

/* ---------- artisan register (owner) ---------- */
function paneReg() {
  return `<div class="card stack"><div class="muted">${esc(T('nameNote'))}</div><button type="button" class="btn primary full" data-act="rb_anew">${esc(T('rNew'))}</button></div>` +
    D.reg.map((a) => `<div class="card stack" style="${a.active ? '' : 'opacity:.6'}"><div class="row between wrap"><b>${esc(a.code)} · ${esc(a.name)}</b><span class="chip">${a.recipes} ${esc(T('nRec'))}</span></div>
      <div class="muted">${esc(aLabel(a))}</div>
      <div class="row wrap"><button type="button" class="mini" data-act="rb_aedit" data-id="${a.id}">${esc(T('open'))}</button>
      <button type="button" class="mini" data-act="rb_aact" data-id="${a.id}" data-on="${a.active ? 0 : 1}">${esc(a.active ? T('retire') : T('reactivate'))}</button></div></div>`).join('');
}
async function loadReg() { const r = await sb.rpc('artisan_register'); if (r.error) throw r.error; D.reg = r.data || []; }
async function loadUsers() { if (D.users.length) return; const r = await sb.from('profiles').select('id,full_name,staff_id').order('staff_id'); D.users = r.data || []; }
async function artisanSheet(a) {
  try { await loadUsers(); } catch (e) { /* optional */ }
  const post = a ? a.post : 'karigor', wt = a ? a.work_type : 'mishti';
  const sel = (id, map, cur) => `<select id="${id}">${Object.keys(map).map((k) => `<option value="${k}" ${k === cur ? 'selected' : ''}>${esc(lab(map[k]))}</option>`).join('')}</select>`;
  openSheet(`<h3>${esc(a ? a.code : T('rNew'))}</h3><div class="stack">
    <label>${esc(T('name'))}<input id="ra_name" maxlength="80" value="${esc(a ? a.name : '')}"></label>
    <label>${esc(T('post'))}${sel('ra_post', POST, post)}</label><input id="ra_post_o" maxlength="60" placeholder="${esc(T('otherTxt'))}" value="${esc(a ? a.post_other || '' : '')}">
    <label>${esc(T('work'))}${sel('ra_work', WORK, wt)}</label><input id="ra_work_o" maxlength="60" placeholder="${esc(T('otherTxt'))}" value="${esc(a ? a.work_other || '' : '')}">
    <label>${esc(T('place'))}<select id="ra_loc"><option value="">—</option>${Object.keys(D.locs).map((k) => `<option value="${k}" ${a && String(a.location_id) === k ? 'selected' : ''}>${esc(D.locs[k])}</option>`).join('')}</select></label>
    <label>${esc(T('login'))}<select id="ra_user"><option value="">—</option>${D.users.map((u) => `<option value="${u.id}" ${a && a.user_id === u.id ? 'selected' : ''}>${esc(u.staff_id || u.full_name || u.id.slice(0, 8))}</option>`).join('')}</select></label>
    <button type="button" class="btn primary full" data-act="rb_asave" data-id="${a ? a.id : ''}">${esc(T('save'))}</button></div>`);
}

/* ---------- recipe detail sheet: artisan, steps, approval, history ---------- */
function stepCard(s, i, n, ro) {
  const dis = ro ? 'disabled' : '';
  const sel = (k, map, cur, blank) => `<select data-rb-f="${k}" ${dis}>${blank ? `<option value="">${esc(blank)}</option>` : ''}${Object.keys(map).map((m) => `<option value="${m}" ${m === cur ? 'selected' : ''}>${esc(lab(map[m]))}</option>`).join('')}</select>`;
  return `<div class="rb-stepcard" data-i="${i}"><div class="row between"><b>${esc(T('step'))} ${i + 1}</b>${ro ? '' : `<span class="row"><button type="button" class="mini" data-act="rb_sup" data-i="${i}" ${i === 0 ? 'disabled' : ''} aria-label="${esc(T('up'))}">↑</button><button type="button" class="mini" data-act="rb_sdown" data-i="${i}" ${i === n - 1 ? 'disabled' : ''} aria-label="${esc(T('down'))}">↓</button><button type="button" class="mini" data-act="rb_srm" data-i="${i}">✕</button></span>`}</div>
    <input data-rb-f="step_name" ${dis} maxlength="120" placeholder="${esc(T('stepName'))}" value="${esc(s.step_name || '')}">
    <textarea data-rb-f="description" ${dis} rows="3" maxlength="2000" placeholder="${esc(T('desc'))}">${esc(s.description || '')}</textarea>
    <div class="row"><input data-rb-f="minutes" ${dis} inputmode="decimal" placeholder="${esc(T('mins'))}" value="${esc(s.minutes ?? '')}"><input data-rb-f="people" ${dis} inputmode="numeric" placeholder="${esc(T('people'))}" value="${esc(s.people ?? '')}"></div>
    ${sel('fuel', { gas: X.gas, electric: X.electric, other: X.fuelOther }, s.fuel || '', T('fuelNone'))}${s.fuel === 'other' ? `<input data-rb-f="fuel_other" ${dis} maxlength="60" placeholder="${esc(T('otherTxt'))}" value="${esc(s.fuel_other || '')}">` : ''}
    <input data-rb-f="flame_note" ${dis} maxlength="200" placeholder="${esc(T('flame'))}" value="${esc(s.flame_note || '')}"><input data-rb-f="equipment" ${dis} maxlength="200" placeholder="${esc(T('equip'))}" value="${esc(s.equipment || '')}">
    <input data-rb-f="qc_note" ${dis} maxlength="300" placeholder="${esc(T('qc'))}" value="${esc(s.qc_note || '')}">
    ${sel('resp_post', POST, s.resp_post || '', T('who'))}${s.resp_post === 'other' ? `<input data-rb-f="resp_other" ${dis} maxlength="60" placeholder="${esc(T('otherTxt'))}" value="${esc(s.resp_other || '')}">` : ''}</div>`;
}
const readSteps = () => { const out = []; document.querySelectorAll('#rb_steps .rb-stepcard').forEach((c) => { const o = {}; c.querySelectorAll('[data-rb-f]').forEach((f) => { o[f.dataset.rbF] = f.value; }); out.push(o); }); return out; };
const suggestLine = (steps) => { let t = 0, miss = 0; steps.forEach((s) => { const m = nnum(s.minutes), p = nnum(s.people); if (m === null || p === null || Number.isNaN(m) || Number.isNaN(p)) miss++; else t += m * p; }); return `${T('suggest')}: ${q2(Math.round(t / 60 * 100) / 100)}${miss ? ' · ' + T('incomplete') + ' ×' + miss : ''} — ${T('suggestNote')}`; };
function drawSteps() {
  const ro = !!(D.st && D.st.approved); const el = $('#rb_steps'); if (!el) return;
  el.innerHTML = D.st.steps.map((s, i) => stepCard(s, i, D.st.steps.length, ro)).join('') + (ro ? '' : `<button type="button" class="btn full" data-act="rb_sadd">${esc(T('addStep'))}</button>`);
  const sg = $('#rb_sug'); if (sg) sg.textContent = suggestLine(D.st.steps);
}
async function openRecipe(id) {
  const r = D.recipes.find((x) => x.id === id); if (!r) return;
  const [st, hist] = await Promise.all([sb.from('recipe_steps').select('*').eq('recipe_id', id).eq('active', true).order('step_no'), sb.from('recipe_versions').select('seq,kind,changed_at,summary').eq('recipe_id', id).order('seq', { ascending: false }).limit(15)]);
  D.st = { id, approved: !!r.approved_at, steps: (st.data || []).map((s) => ({ ...s })) };
  openSheet(`<h3>${esc(itemName(r.item_id))} · v${r.version}</h3><div class="stack">
    <label>${esc(T('artisan'))}${artSelect(r.artisan_id || '', id)}</label>
    <div class="row between wrap"><span class="chip ${r.approved_at ? 'ok' : 'warn'}">${esc(r.approved_at ? T('approved') : T('notApproved'))}</span>${r.approved_at ? '' : `<button type="button" class="mini" data-act="rb_approve" data-id="${esc(id)}">${esc(T('approve'))}</button>`}</div>
    ${r.approved_at ? `<div class="muted">${esc(T('frozen'))}</div>` : ''}
    <h4>${esc(T('steps'))}</h4><div class="muted" id="rb_sug"></div><div id="rb_steps"></div>
    ${r.approved_at ? '' : `<button type="button" class="btn primary full" data-act="rb_ssave" data-id="${esc(id)}">${esc(T('save'))}</button>`}
    <h4>${esc(T('history'))}</h4>${(hist.data || []).map((h) => `<div class="muted">#${h.seq} · ${esc(h.kind)} · ${esc(String(h.changed_at).slice(0, 16).replace('T', ' '))}${h.summary ? ' · ' + esc(h.summary) : ''}</div>`).join('') || `<div class="muted">${esc(T('none'))}</div>`}</div>`);
  drawSteps();
}

/* ---------- handlers ---------- */
async function refresh() { await loadAll(); const u = await sb.rpc('recipe_unassigned'); D.un = u.error ? [] : (u.data || []); if (D.canReg) { try { await loadReg(); } catch (e) { D.reg = []; } } draw(); }
const syncSteps = () => { if (D.st && $('#rb_steps')) D.st.steps = readSteps().map((s, i) => ({ ...D.st.steps[i], ...s })); };
Object.assign(H, {
  rb_tab: async (a) => { D.tab = a.dataset.v; if (D.tab === 'reg') { try { await loadReg(); } catch (e) { return fail(e); } } draw(); },
  rb_show: async () => {
    const id = Number(($('#rb_art') || {}).value); if (!id) return toast(T('pick'));
    D.aid = id; D.withCost = !!($('#rb_cost') && $('#rb_cost').checked);
    const r = await sb.rpc('recipe_book', { p_artisan: id, p_with_cost: D.withCost, p_loc: null });
    if (r.error) { if (/not allowed/.test(r.error.message || '')) { D.book = null; draw(); return toast(T('noperm')); } return errMsg(r.error); }
    D.book = r.data; draw();
  },
  rb_print: () => {
    const src = $('#rb_doc'); if (!src) return; const old = $('#rb_print'); if (old) old.remove();
    const d = document.createElement('div'); d.id = 'rb_print'; d.innerHTML = src.innerHTML; document.body.appendChild(d);
    const clean = () => { const e = $('#rb_print'); if (e) e.remove(); window.removeEventListener('afterprint', clean); };
    window.addEventListener('afterprint', clean); window.print();
  },
  rb_share: async () => { if (!D.book) return; const txt = bookText(D.book);
    try { if (navigator.share) { await navigator.share({ title: T('title'), text: txt }); return; } } catch (e) { return; }
    try { await navigator.clipboard.writeText(txt); toast(T('copied')); } catch (e) { toast(txt.slice(0, 80)); } },
  rb_open: (a) => openRecipe(a.dataset.id).catch(errMsg),
  rb_sadd: () => { syncSteps(); D.st.steps.push({ step_name: '' }); drawSteps(); },
  rb_srm: (a) => { syncSteps(); D.st.steps.splice(Number(a.dataset.i), 1); drawSteps(); },
  rb_sup: (a) => { syncSteps(); const i = Number(a.dataset.i); if (i > 0) { const t = D.st.steps[i]; D.st.steps[i] = D.st.steps[i - 1]; D.st.steps[i - 1] = t; } drawSteps(); },
  rb_sdown: (a) => { syncSteps(); const i = Number(a.dataset.i); if (i < D.st.steps.length - 1) { const t = D.st.steps[i]; D.st.steps[i] = D.st.steps[i + 1]; D.st.steps[i + 1] = t; } drawSteps(); },
  rb_ssave: async (a) => {
    syncSteps(); const steps = D.st.steps.map((s) => ({ step_name: s.step_name, description: s.description, minutes: s.minutes === '' || s.minutes == null ? null : norm(s.minutes), people: s.people === '' || s.people == null ? null : norm(s.people),
      fuel: s.fuel || null, fuel_other: s.fuel_other || null, flame_note: s.flame_note, equipment: s.equipment, qc_note: s.qc_note, resp_post: s.resp_post || null, resp_other: s.resp_other || null }));
    if (steps.some((s) => !String(s.step_name || '').trim())) return toast(T('needStepName'));
    const r = await sb.rpc('recipe_steps_save', { p_recipe: a.dataset.id, p_steps: steps, p_client: rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await refresh();
  },
  rb_approve: async (a) => { const r = await sb.rpc('recipe_approve', { p_recipe: a.dataset.id, p_note: null }); if (r.error) return errMsg(r.error); toast(T('approved') + selfHint(r.data)); closeSheet(); await refresh(); },
  rb_anew: () => artisanSheet(null),
  rb_aedit: (a) => artisanSheet(D.reg.find((x) => String(x.id) === a.dataset.id)),
  rb_asave: async (a) => {
    const name = ($('#ra_name') || {}).value || ''; if (name.trim().length < 2) return toast(T('needName'));
    const id = a.dataset.id ? Number(a.dataset.id) : null;
    const r = await sb.rpc('artisan_save', { p_id: id, p_post: $('#ra_post').value, p_post_other: $('#ra_post_o').value || null, p_name: name, p_work_type: $('#ra_work').value, p_work_other: $('#ra_work_o').value || null,
      p_location: $('#ra_loc').value ? Number($('#ra_loc').value) : null, p_user: $('#ra_user').value || null, p_note: null, p_client: id ? null : rid() });
    if (r.error) return errMsg(r.error); toast(T('saved')); closeSheet(); await loadBase(); await loadReg(); draw();
  },
  rb_aact: async (a) => {
    const on = a.dataset.on === '1'; let why = null;
    if (!on) { why = window.prompt(T('why')); if (!why) return; }
    const r = await sb.rpc('artisan_set_active', { p_id: Number(a.dataset.id), p_active: on, p_reason: why }); if (r.error) return errMsg(r.error);
    await loadBase(); await loadReg(); draw();
  },
});
document.addEventListener('change', async (e) => {
  const t = e.target; if (!t || !t.dataset) return;
  if (t.dataset.rbArt !== undefined) {
    const recipe = t.dataset.rbArt;
    if (t.value === '__new') { t.value = ''; if (!D.canReg) return toast(T('ownerAdds')); return artisanSheet(null); }
    const r = await sb.rpc('recipe_set_artisan', { p_recipe: recipe, p_artisan: t.value ? Number(t.value) : null, p_note: null });
    if (r.error) return errMsg(r.error); toast(T('saved')); await refresh();
  }
  if (t.dataset.rbF === 'fuel' || t.dataset.rbF === 'resp_post') { syncSteps(); drawSteps(); }
  if (t.dataset.rbF === 'minutes' || t.dataset.rbF === 'people') { syncSteps(); const sg = $('#rb_sug'); if (sg) sg.textContent = suggestLine(D.st.steps); }
});

async function view() {
  css(); shell(T('title'), `<div id="rb_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  try { await loadBase(); await refresh(); } catch (e) { if (/not allowed/.test((e && e.message) || '')) { const b = $('#rb_body'); if (b) b.innerHTML = `<p class="muted">${esc(T('noperm'))}</p>`; return; } errMsg(e); }
}
B.recipebook = { bookText, suggestLine };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { recipebook: view });
})();
