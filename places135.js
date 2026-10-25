/* Islamia BOS · Places of a business (phase 135), used inside #/organization (web/org122.js draws the buttons through window.BOS_PLACES135).
   Server (supabase/phase135.sql): business_place_create135(p_business, p_kind, p_code, p_name_bn, p_name_en, p_org_branch, p_client) -> jsonb {dup,id,code,...},
   business_places_list135(p_business) -> rows, business_place_move135(p_location, p_business, p_reason, p_dry, p_force, p_client, p_org_branch) -> jsonb (owner only; dry-run first),
   plus org_unit_save (phase122/134) for the legal entity / business / branch units of the guided "New business" flow.
   Screens (all sheets): Add place (kind, names bn / en, code, branch), Places of a business (+ Move place for the owner: check first, then move), New business (owner only):
   step 1 name + template (a template that is not built yet is labelled and needs a tick), step 2 the places (1..10), step 3 summary + a "what to do next" checklist.
   Every create carries its own client key, so a retry after an error never makes a second business / branch / place. No business or brand name is written in this file. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10));
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const X = {
  addPlace: L('জায়গা যোগ', 'Add place', 'Place যোগ'), places: L('জায়গাগুলো', 'Places', 'Places'), move: L('অন্য ব্যবসায় সরান', 'Move to another business', 'অন্য business-এ সরান'),
  newBiz: L('নতুন ব্যবসা', 'New business', 'নতুন business'), kind: L('ধরন', 'Kind', 'ধরন'), nbn: L('নাম (বাংলা)', 'Name (Bangla)', 'নাম (বাংলা)'), nen: L('নাম (ইংরেজি)', 'Name (English)', 'নাম (English)'),
  code: L('কোড (ইচ্ছামতো, ইংরেজি ছোট অক্ষর/সংখ্যা)', 'Code (optional, lower-case letters / digits)', 'Code (ইচ্ছামতো, English ছোট অক্ষর/সংখ্যা)'),
  codeHint: L('আসল কোডের শুরুতে ব্যবসার কোড বসবে:', 'The stored code starts with the business code:', 'আসল code-এর শুরুতে business code বসবে:'),
  branch: L('শাখা (ইচ্ছামতো)', 'Branch (optional)', 'Branch (ইচ্ছামতো)'), noBranch: L('সরাসরি ব্যবসার অধীনে', 'Directly under the business', 'সরাসরি business-এর অধীনে'),
  save: L('সেভ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ', 'Close', 'Close'), saved: L('জায়গা তৈরি হয়েছে', 'Place created', 'Place তৈরি হয়েছে'),
  none: L('এখনো কোনো জায়গা নেই।', 'No places yet.', 'এখনো কোনো place নেই।'), inBranch: L('শাখা', 'Branch', 'Branch'),
  reason: L('কারণ (কমপক্ষে ৩ অক্ষর)', 'Reason (at least 3 characters)', 'কারণ (কমপক্ষে ৩ অক্ষর)'), target: L('কোন ব্যবসায়', 'Into which business', 'কোন business-এ'),
  check: L('আগে যাচাই করুন', 'Check first', 'আগে check করুন'), doMove: L('এখন সরান', 'Move now', 'এখন সরান'), moved: L('সরানো হয়েছে', 'Moved', 'সরানো হয়েছে'),
  force: L('আমি বুঝেছি: এই জায়গার পুরনো লেনদেনও নতুন ব্যবসার হিসাবে চলে যাবে', 'I understand: the old transactions of this place move to the other business too', 'আমি বুঝেছি: এই place-এর পুরনো লেনদেনও নতুন business-এ চলে যাবে'),
  impact: L('যা জড়িত', 'What is involved', 'যা জড়িত'), stock: L('স্টকে আইটেম', 'Items in stock', 'Stock-এ item'), tx: L('লেনদেনের সারি', 'Transaction rows', 'লেনদেনের row'),
  people: L('জায়গায় নিযুক্ত মানুষ', 'People assigned', 'Place-এ নিযুক্ত মানুষ'), open: L('খোলা কাগজ', 'Open documents', 'খোলা document'), canMove: L('সরানো যাবে', 'Can be moved', 'সরানো যাবে'),
  ownerOnly: L('এটি শুধু মালিক করতে পারেন', 'Only the owner can do this', 'এটি শুধু owner করতে পারেন'), noOther: L('সরানোর মতো অন্য কোনো ব্যবসা নেই।', 'There is no other business to move it to.', 'সরানোর মতো অন্য business নেই।'),
  step: L('ধাপ', 'Step', 'Step'), next: L('পরের ধাপ', 'Next', 'Next'), back: L('পিছনে', 'Back', 'Back'), bname: L('ব্যবসার নাম', 'Business name', 'Business-এর নাম'),
  bcode: L('ব্যবসার কোড (ইংরেজি বড় অক্ষর/সংখ্যা)', 'Business code (capital letters / digits)', 'Business code (English বড় অক্ষর/সংখ্যা)'), tpl: L('ব্যবসার ধরন (টেমপ্লেট)', 'Business type (template)', 'Business type (template)'),
  le: L('আইনি প্রতিষ্ঠান', 'Legal entity', 'Legal entity'), leNew: L('নতুন আইনি প্রতিষ্ঠান (আলাদা হিসাব)', 'New legal entity (own books)', 'নতুন legal entity (আলাদা হিসাব)'),
  ack: L('আমি বুঝেছি: এই টেমপ্লেটের নিজস্ব স্ক্রিন এখনো তৈরি হয়নি; শুধু কাঠামো, জায়গা, স্টক ও বিক্রির সাধারণ অংশ পাওয়া যাবে', 'I understand: this template has no screens of its own yet; I get the structure, places, stock and the general sales part only', 'আমি বুঝেছি: এই template-এর নিজস্ব screen এখনো তৈরি হয়নি; structure, place, stock ও সাধারণ sales অংশ পাওয়া যাবে'),
  bcodeBad: L('ব্যবসার কোড ঠিক নয় (ইংরেজি বড় অক্ষর/সংখ্যা/-/_, ২-২৪)', 'The business code is not valid (capital letters / digits / - / _, 2-24)', 'Business code ঠিক নয় (English বড় অক্ষর/সংখ্যা/-/_, ২-২৪)'),
  tplNo: L('এখনো তৈরি হয়নি', 'Not built yet', 'এখনো তৈরি হয়নি'), tplOk: L('পাওয়া যায়', 'Available', 'Available'),
  placesN: L('জায়গা (১ থেকে ১০টি)', 'Places (1 to 10)', 'Places (১ থেকে ১০টি)'), addRow: L('আরেকটি জায়গা', 'One more place', 'আরেকটি place'), rm: L('বাদ', 'Remove', 'বাদ'),
  asBranch: L('প্রতিটি জায়গার জন্য একটি শাখা-ইউনিট বানান', 'Make one branch unit for each place', 'প্রতিটি place-এর জন্য একটি branch unit বানান'),
  create: L('তৈরি করুন', 'Create now', 'এখনই তৈরি করুন'), working: L('তৈরি হচ্ছে…', 'Creating…', 'তৈরি হচ্ছে…'), retry: L('আবার চেষ্টা (দ্বিতীয়বার কিছু তৈরি হবে না)', 'Try again (nothing is made twice)', 'আবার চেষ্টা (দ্বিতীয়বার কিছু তৈরি হবে না)'),
  done: L('তৈরি হয়ে গেছে', 'Created', 'তৈরি হয়ে গেছে'), todo: L('এরপর কী করবেন', 'What to do next', 'এরপর কী করবেন'), failed: L('হয়নি', 'Failed', 'হয়নি'),
  c1: L('প্রতিটি জায়গা চালু করুন (জায়গার পাতায় "চালু করুন")', 'Set each place live (Locations screen, "Start")', 'প্রতিটি place চালু করুন (Locations পাতায় "Start")'),
  c2: L('মানুষদের জায়গা দিন (স্টাফ পাতা): যার যে ব্যবসার জায়গা, সে শুধু সেটাই দেখবে', 'Give each person a place (Staff screen): a person sees only the business of his place', 'মানুষদের place দিন (Staff পাতা): যার যে business-এর place, সে শুধু সেটাই দেখবে'),
  c3: L('ব্যবসার প্রোফাইল ভরুন: নাম, ঠিকানা, রসিদের লেখা', 'Fill the business profile: name, address, receipt text', 'Business profile ভরুন: নাম, ঠিকানা, receipt-এর লেখা'),
  c4: L('আলাদা ডেটা-সীমা চালু করুন (সুইচবোর্ডে "org_scope_on"): আগে যাচাই (preflight) চালান, তারপর চালু করুন। এর আগে দুই ব্যবসার জায়গা একে অপরের তালিকায় দেখা যেতে পারে', 'Turn on the separate data scope (Switchboard, "org_scope_on"): run the preflight first, then switch it on. Before that the places of both businesses can still show in each other\'s lists', 'আলাদা data-scope চালু করুন (Switchboard-এ "org_scope_on"): আগে preflight চালান, তারপর on করুন। তার আগে দুই business-এর place একে অপরের list-এ দেখা যেতে পারে'),
  c5: L('টেমপ্লেটের সুইচগুলো দেখুন ও দরকারমতো চালু করুন (সুইচবোর্ড)', 'Review the template switches and turn on what you need (Switchboard)', 'Template-এর switch দেখুন ও দরকারমতো on করুন (Switchboard)'),
  c6: L('এই ব্যবসার আইটেম ও মূল্য তালিকা যোগ করুন', 'Add the items and the price list of this business', 'এই business-এর item ও price list যোগ করুন'),
  gLoc: L('জায়গার পাতা', 'Locations', 'Locations'), gStaff: L('স্টাফ', 'Staff', 'Staff'), gProf: L('প্রোফাইল', 'Profile', 'Profile'), gSw: L('সুইচবোর্ড', 'Switchboard', 'Switchboard'),
};
const T = (k) => lab(X[k]);
const KINDS = [['showroom', L('শোরুম / দোকান / শাখা', 'Showroom / shop / branch', 'Showroom / shop / branch')], ['godown', L('গুদাম', 'Warehouse / godown', 'গুদাম / warehouse')],
  ['factory', L('কারখানা', 'Factory', 'Factory')], ['hub', L('হাব', 'Hub', 'Hub')], ['online', L('অনলাইন', 'Online', 'Online')], ['other', L('অন্যান্য', 'Other', 'অন্যান্য')]];
const kindName = (k) => { const r = KINDS.find((x) => x[0] === k); return r ? lab(r[1]) : String(k || ''); };
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), 'not allowed': L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), client_id_needed: L('আবার চেষ্টা করুন', 'Please try again', 'আবার চেষ্টা করুন'), client_id_taken: L('আবার চেষ্টা করুন', 'Please try again', 'আবার চেষ্টা করুন'),
  bad_kind: L('জায়গার ধরন ঠিক নয়', 'The kind of place is not valid', 'Place-এর ধরন ঠিক নয়'), name_required: L('একটি নাম লিখুন', 'Enter a name', 'একটি নাম লিখুন'), too_long: L('নাম খুব বড় (১২০ অক্ষর)', 'The name is too long (120 characters)', 'নাম খুব বড় (১২০ অক্ষর)'),
  bad_code: L('কোড ঠিক নয় (ইংরেজি ছোট অক্ষর/সংখ্যা/_, অক্ষর দিয়ে শুরু)', 'The code is not valid (lower-case letters / digits / _, must start with a letter)', 'Code ঠিক নয় (English ছোট অক্ষর/সংখ্যা/_, অক্ষর দিয়ে শুরু)'),
  code_in_use: L('এই কোড আগেই আছে', 'This code is already used', 'এই code আগেই আছে'), code_too_long: L('কোড খুব বড়; ব্যবসার কোড আগে বসে, তাই ছোট করুন', 'The code is too long; the business code goes in front, so shorten it', 'Code খুব বড়; business code আগে বসে, তাই ছোট করুন'),
  name_in_use: L('এই ব্যবসায় এই নামের জায়গা আগেই আছে', 'This business already has a place with this name', 'এই business-এ এই নামের place আগেই আছে'), bad_branch: L('শাখাটি এই ব্যবসার ভেতরের নয়', 'That branch is not inside this business', 'Branch-টি এই business-এর ভেতরের নয়'),
  unknown_business: L('ব্যবসা পাওয়া যায়নি', 'Business not found', 'Business পাওয়া যায়নি'), business_inactive: L('ব্যবসাটি বন্ধ', 'The business is inactive', 'Business-টি বন্ধ'), unknown_location: L('জায়গা পাওয়া যায়নি', 'Place not found', 'Place পাওয়া যায়নি'),
  place_has_transactions: L('এই জায়গায় লেনদেন আছে; সরাতে হলে নিচের টিক দিয়ে নিশ্চিত করুন', 'This place has transactions; tick the box below to confirm the move', 'এই place-এ লেনদেন আছে; সরাতে হলে নিচের tick দিয়ে নিশ্চিত করুন'),
  place_has_users: L('এই জায়গায় মানুষ নিযুক্ত আছে; আগে স্টাফ পাতা থেকে তাদের সরান', 'People are assigned to this place; remove them in the Staff screen first', 'এই place-এ মানুষ নিযুক্ত আছে; আগে Staff পাতা থেকে সরান'),
  open_documents: L('খোলা কাগজ আছে (খসড়া এন্ট্রি, পথের ট্রান্সফার, খসড়া ক্রয়); আগে শেষ করুন বা বাতিল করুন', 'There are open documents (draft entries, transfers on the way, draft purchases); finish or cancel them first', 'খোলা document আছে (draft entry, পথের transfer, draft purchase); আগে শেষ বা বাতিল করুন'),
  supply_link: L('সরবরাহ সম্পর্ক অন্য ব্যবসার সাথে জড়িত; আগে জায়গার পাতায় সরবরাহ বদলান', 'The supply link would cross the business border; change the supply first in Locations', 'সরবরাহ সম্পর্ক অন্য business-এর সাথে জড়িত; আগে Locations-এ supply বদলান'),
  reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'কারণ লিখুন (কমপক্ষে ৩ অক্ষর)'), bad_reason: L('কারণ খুব বড়', 'The reason is too long', 'কারণ খুব বড়'),
  code_taken: L('এই কোড আগেই আছে', 'This code is already used', 'এই code আগেই আছে'), bad_name: L('নাম ঠিক নয় (১-১২০ অক্ষর)', 'Name is not valid (1-120 characters)', 'নাম ঠিক নয় (১-১২০ অক্ষর)'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).sort((x, y) => y.length - x.length).find((x) => m.includes(x)); return k ? lab(ERR[k]) : m || 'error'; };
const nm = (u) => lab(L(u.name_bn || u.name_en || u.code || '', u.name_en || u.name_bn || u.code || '', u.name_en || u.name_bn || u.code || ''));
const O = () => window.BOS_ORG122 || { flat: () => new Map(), tpl: () => [], refresh: async () => {} };
const bizOfUnit = (id) => { const f = O().flat(); let u = f.get(String(id)), n = 0; while (u && u.kind !== 'business' && n++ < 20) u = u.parent_id == null ? null : f.get(String(u.parent_id)); return u && u.kind === 'business' ? u : null; };
const branchesOf = (bizId) => [...O().flat().values()].filter((u) => (u.kind === 'branch' || u.kind === 'site') && u.status !== 'inactive' && bizOfUnit(u.id) && String(bizOfUnit(u.id).id) === String(bizId));
const activeBiz = () => [...O().flat().values()].filter((u) => u.kind === 'business' && u.status !== 'inactive');
const err = (m) => { const e = $('#pl_err'); if (e) e.textContent = m; else toast(m); };
async function refreshEnv() {   // the pick-lists of the whole app follow the new place: reload the locations and the business context
  try { if (B.ENV) B.ENV.locs = null; if (B.biz && B.biz.reload) await B.biz.reload(); else if (B.loadStatic) await B.loadStatic(); } catch (e) { /* the next page load fetches them */ }
  try { await O().refresh(); } catch (e) { /* tree redraws on the next visit */ }
}
const sel = (id, opts, cur, extra) => `<select id="${id}" ${extra || ''}>${opts.map(([v, l, dis]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''} ${dis ? 'disabled' : ''}>${esc(l)}</option>`).join('')}</select>`;
const btn = (act, label, attrs, cls) => `<button class="full ${cls || ''}" style="min-height:40px" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`;

// ---------- buttons drawn by org122.js ----------
function cardHTML(n) {
  if (!n || n.kind !== 'business' || (n.status && n.status !== 'active')) return '';
  return `<div class="row" style="flex-wrap:wrap;gap:6px"><button class="mini" style="min-height:40px" data-act="pl_add" data-v="${esc(n.id)}">+ ${esc(T('addPlace'))}</button>
    <button class="mini" style="min-height:40px" data-act="pl_list" data-v="${esc(n.id)}">${esc(T('places'))}</button></div>`;
}
const topHTML = () => (isOwner() ? `<div class="row" style="flex-wrap:wrap;gap:6px"><button class="full primary" style="min-height:40px" data-act="nb_start" id="nb_open">+ ${esc(T('newBiz'))}</button></div>` : '');

// ---------- add a place ----------
function addSheet(bizId, preset) {
  const biz = O().flat().get(String(bizId)); if (!biz) return;
  const br = branchesOf(bizId); const p = preset || {};
  openSheet(`<h3>${esc(T('addPlace'))} · ${esc(nm(biz))}</h3><div class="stack" id="pl_form">
    <div><label for="pl_kind">${esc(T('kind'))}</label>${sel('pl_kind', KINDS.map(([v, l]) => [v, lab(l)]), p.kind || 'showroom')}</div>
    <div><label for="pl_nbn">${esc(T('nbn'))}</label><input id="pl_nbn" autocomplete="off" maxlength="120" value="${esc(p.bn || '')}"></div>
    <div><label for="pl_nen">${esc(T('nen'))}</label><input id="pl_nen" autocomplete="off" maxlength="120" value="${esc(p.en || '')}"></div>
    <div><label for="pl_code">${esc(T('code'))}</label><input id="pl_code" autocomplete="off" maxlength="24" value="${esc(p.code || '')}"><div class="muted">${esc(T('codeHint'))} <b>${esc(String(biz.code || '').toLowerCase())}_</b></div></div>
    ${br.length ? `<div><label for="pl_br">${esc(T('branch'))}</label>${sel('pl_br', [['', T('noBranch')], ...br.map((u) => [u.id, nm(u)])], '')}</div>` : ''}
    <div id="pl_err" class="muted" role="alert"></div>
    <div class="row">${btn('closesheet', T('cancel'))}${btn('pl_save', T('save'), `data-biz="${esc(bizId)}"`, 'primary')}</div></div>`);
  D.client = rid();
}
const D = { client: null, move: null, nb: null };
const CODE_RE = /^[a-z][a-z0-9_]{1,29}$/;
async function createPlace(biz, v, client) {
  return sb.rpc('business_place_create135', { p_business: Number(biz), p_kind: v.kind, p_code: v.code || null, p_name_bn: v.bn || v.en, p_name_en: v.en || null, p_org_branch: v.branch ? Number(v.branch) : null, p_client: client });
}

// ---------- list + move ----------
async function listSheet(bizId) {
  const biz = O().flat().get(String(bizId)); if (!biz) return;
  const r = await sb.rpc('business_places_list135', { p_business: Number(bizId) });
  if (r.error) return toast(eText(r.error));
  const rows = r.data || [];
  openSheet(`<h3>${esc(T('places'))} · ${esc(nm(biz))}</h3><div class="stack" id="pl_rows">${rows.length ? B.locGroups.listHTML(rows, (x) => `<div class="card" style="word-break:break-word;overflow-wrap:anywhere" data-loc="${esc(x.id)}">
      <div class="row" style="flex-wrap:wrap;gap:6px;align-items:center"><b>${esc(lab(L(x.name_bn, x.name_en || x.name_bn, x.name_en || x.name_bn)))}</b><span class="muted">${esc(x.code)}</span><span class="chip">${esc(kindName(x.kind))}</span><span class="chip muted">${esc(x.status)}</span></div>
      ${x.unit_kind === 'branch' || x.unit_kind === 'site' ? `<div class="muted">${esc(T('inBranch'))}: ${esc(lab(L(x.unit_name_bn, x.unit_name_en || x.unit_name_bn, x.unit_name_en || x.unit_name_bn)))}</div>` : ''}
      ${isOwner() ? `<button class="mini" style="min-height:40px" data-act="pl_move" data-v="${esc(x.id)}" data-biz="${esc(bizId)}" data-nm="${esc(x.name_en || x.name_bn)}">${esc(T('move'))}</button>` : ''}</div>`) : `<p class="muted">${esc(T('none'))}</p>`}
    <div class="row">${btn('closesheet', T('close'))}${btn('pl_add', T('addPlace'), `data-v="${esc(bizId)}"`, 'primary')}</div></div>`);
}
function moveSheet(loc, fromBiz, name) {
  const others = activeBiz().filter((b) => String(b.id) !== String(fromBiz));
  D.move = { loc: Number(loc), from: fromBiz, name, client: rid() };
  if (!others.length) return openSheet(`<h3>${esc(T('move'))} · ${esc(name)}</h3><p class="muted">${esc(T('noOther'))}</p>${btn('closesheet', T('close'))}`);
  openSheet(`<h3>${esc(T('move'))} · ${esc(name)}</h3><div class="stack" id="pl_form">
    <div><label for="mv_biz">${esc(T('target'))}</label>${sel('mv_biz', others.map((b) => [b.id, nm(b)]), others[0].id)}</div>
    <div><label for="mv_why">${esc(T('reason'))}</label><input id="mv_why" autocomplete="off" maxlength="200"></div>
    <div id="mv_imp"></div><div id="pl_err" class="muted" role="alert"></div>
    <div class="row">${btn('closesheet', T('cancel'))}${btn('pl_check', T('check'), '', '')}</div></div>`);
}
const IMP_ERR = ['place_has_users', 'open_documents', 'supply_link', 'place_has_transactions'];
async function checkMove() {
  const m = D.move; if (!m) return; const biz = Number(($('#mv_biz') || {}).value);
  const r = await sb.rpc('business_place_move135', { p_location: m.loc, p_business: biz, p_reason: null, p_dry: true, p_force: false });
  if (r.error) return err(eText(r.error));
  const d = r.data || {}, bl = d.blockers || [];
  const hard = bl.filter((x) => x !== 'place_has_transactions');
  const lines = `<div class="card"><b>${esc(T('impact'))}</b><div class="muted">${esc(T('stock'))}: ${esc(d.stock_items)} · ${esc(T('tx'))}: ${esc(d.tx_total)} · ${esc(T('people'))}: ${esc(d.users)} · ${esc(T('open'))}: ${esc(d.open_documents)}</div>
    ${bl.map((x) => `<div class="muted" style="color:var(--bad,#b3261e)">${esc(lab(ERR[x] || L(x, x, x)))}</div>`).join('')}
    ${hard.length ? '' : `<div class="ok">${esc(T('canMove'))}</div>`}
    ${!hard.length && d.needs_force ? `<label class="row" style="gap:8px;align-items:flex-start"><input type="checkbox" id="mv_force" style="min-width:24px;min-height:24px"><span>${esc(T('force'))}</span></label>` : ''}</div>
    ${!hard.length ? btn('pl_domove', T('doMove'), `data-biz="${esc(biz)}"`, 'primary') : ''}`;
  $('#mv_imp').innerHTML = lines;
}
async function doMove(biz) {
  const m = D.move; if (!m) return; const why = (($('#mv_why') || {}).value || '').trim(); if (why.length < 3) return err(lab(ERR.reason_required));
  const force = !!($('#mv_force') && $('#mv_force').checked);
  const r = await sb.rpc('business_place_move135', { p_location: m.loc, p_business: Number(biz), p_reason: why, p_dry: false, p_force: force, p_client: m.client });
  if (r.error) return err(eText(r.error));
  closeSheet(); toast(T('moved')); await refreshEnv(); await listSheet(m.from);
}

// ---------- New business (owner only) ----------
const tplStatus = (c) => { const t = O().tpl().find((x) => x.code === c); return t ? t.status : ''; };
const tplLabel = (t) => lab(L(t.name_bn || t.name_en || t.code, t.name_en || t.name_bn || t.code, t.name_en || t.name_bn || t.code)) + ' · ' + (t.status === 'not_implemented' ? T('tplNo') : (t.status === 'available' || t.status === 'configured') ? T('tplOk') : t.status);
const defaultRows = (tpl) => (tpl === 'dealership' ? [1, 2] : [1]).map(() => ({ kind: 'showroom', pbn: '', pen: '', key: rid(), bkey: rid() }));
function nbStart() {
  if (!isOwner()) return toast(T('ownerOnly'));
  D.nb = { step: 1, nbn: '', nen: '', code: '', tpl: '', le: 'new', ack: false, asBranch: true, rows: defaultRows(''), keys: { le: rid(), biz: rid() }, res: null };
  nbDraw();
}
function nbCapture() {
  const w = D.nb; if (!w) return;
  const g = (id) => { const e = $('#' + id); return e ? e.value : undefined; };
  if (w.step === 1) {
    w.nbn = (g('nb_bn') ?? w.nbn).trim(); w.nen = (g('nb_en') ?? w.nen).trim(); w.code = (g('nb_code') ?? w.code).trim().toUpperCase();
    const t = g('nb_tpl'); if (t !== undefined) { if (t !== w.tpl && !w.rowsTouched) w.rows = defaultRows(t); w.tpl = t; }
    const l = g('nb_le'); if (l !== undefined) w.le = l; const a = $('#nb_ack'); w.ack = a ? a.checked : false;
  } else if (w.step === 2) {
    w.rows.forEach((r, i) => { r.kind = g('nb_k' + i) ?? r.kind; r.pbn = (g('nb_pb' + i) ?? r.pbn).trim(); r.pen = (g('nb_pe' + i) ?? r.pen).trim(); });
    const c = $('#nb_asb'); if (c) w.asBranch = c.checked;
  }
}
function nbDraw() {
  const w = D.nb; if (!w) return;
  const head = `<h3>${esc(T('newBiz'))} · ${esc(T('step'))} ${w.step}/3</h3>`;
  if (w.step === 1) {
    const tpls = O().tpl(); const les = [...O().flat().values()].filter((u) => u.kind === 'legal_entity' && u.status !== 'inactive');
    const st = tplStatus(w.tpl);
    openSheet(`${head}<div class="stack" id="pl_form">
      <div><label for="nb_bn">${esc(T('nbn'))}</label><input id="nb_bn" autocomplete="off" maxlength="120" value="${esc(w.nbn)}"></div>
      <div><label for="nb_en">${esc(T('nen'))}</label><input id="nb_en" autocomplete="off" maxlength="120" value="${esc(w.nen)}"></div>
      <div><label for="nb_code">${esc(T('bcode'))}</label><input id="nb_code" autocomplete="off" maxlength="24" value="${esc(w.code)}"></div>
      <div><label for="nb_tpl">${esc(T('tpl'))}</label>${sel('nb_tpl', [['', lab(L('কোনোটি নয়', 'None', 'কোনোটি নয়'))], ...tpls.map((t) => [t.code, tplLabel(t)])], w.tpl)}</div>
      ${st === 'not_implemented' ? `<label class="row" style="gap:8px;align-items:flex-start"><input type="checkbox" id="nb_ack" ${w.ack ? 'checked' : ''} style="min-width:24px;min-height:24px"><span>${esc(T('ack'))}</span></label>` : ''}
      <div><label for="nb_le">${esc(T('le'))}</label>${sel('nb_le', [['new', T('leNew')], ...les.map((u) => [u.id, nm(u)])], w.le)}</div>
      <div id="pl_err" class="muted" role="alert"></div>
      <div class="row">${btn('closesheet', T('cancel'))}${btn('nb_next', T('next'), '', 'primary')}</div></div>`);
  } else if (w.step === 2) {
    openSheet(`${head}<div class="stack" id="pl_form"><b>${esc(T('placesN'))}</b>
      ${w.rows.map((r, i) => `<div class="card" data-row="${i}"><div><label for="nb_k${i}">${esc(T('kind'))}</label>${sel('nb_k' + i, KINDS.map(([v, l]) => [v, lab(l)]), r.kind)}</div>
        <div><label for="nb_pb${i}">${esc(T('nbn'))}</label><input id="nb_pb${i}" autocomplete="off" maxlength="120" value="${esc(r.pbn)}"></div>
        <div><label for="nb_pe${i}">${esc(T('nen'))}</label><input id="nb_pe${i}" autocomplete="off" maxlength="120" value="${esc(r.pen)}"></div>
        ${w.rows.length > 1 ? `<button class="mini" style="min-height:40px" data-act="nb_rm" data-v="${i}">${esc(T('rm'))}</button>` : ''}</div>`).join('')}
      ${w.rows.length < 10 ? btn('nb_addrow', '+ ' + T('addRow')) : ''}
      <label class="row" style="gap:8px;align-items:flex-start"><input type="checkbox" id="nb_asb" ${w.asBranch ? 'checked' : ''} style="min-width:24px;min-height:24px"><span>${esc(T('asBranch'))}</span></label>
      <div id="pl_err" class="muted" role="alert"></div>
      <div class="row">${btn('nb_back', T('back'))}${btn('nb_run', T('create'), '', 'primary')}</div></div>`);
  } else {
    const rs = w.res || [];
    const bad = rs.filter((x) => !x.ok);
    openSheet(`${head}<div class="stack" id="pl_form"><div id="nb_sum">${rs.map((x) => `<div class="${x.ok ? 'ok' : 'muted'}" style="${x.ok ? '' : 'color:var(--bad,#b3261e)'};word-break:break-word">${x.ok ? '✓' : '✗'} ${esc(x.label)}${x.ok ? '' : ' · ' + esc(x.msg)}</div>`).join('')}</div>
      ${bad.length ? `<div id="pl_err" class="muted" role="alert">${esc(T('failed'))}: ${bad.length}</div>${btn('nb_run', T('retry'), '', 'primary')}` : `<div class="card" id="nb_todo"><b>${esc(T('todo'))}</b>
        <ol style="padding-left:18px;margin:6px 0">${['c1', 'c2', 'c3', 'c4', 'c5', 'c6'].map((k) => `<li>${esc(T(k))}</li>`).join('')}</ol>
        <div class="row" style="flex-wrap:wrap;gap:6px"><button class="mini" style="min-height:40px" data-act="nb_go" data-v="locations">${esc(T('gLoc'))}</button><button class="mini" style="min-height:40px" data-act="nb_go" data-v="staff">${esc(T('gStaff'))}</button>
        <button class="mini" style="min-height:40px" data-act="nb_go" data-v="profile">${esc(T('gProf'))}</button><button class="mini" style="min-height:40px" data-act="nb_go" data-v="switchboard">${esc(T('gSw'))}</button></div></div>`}
      <div class="row">${btn('closesheet', T('close'))}</div></div>`);
  }
}
function nbNext() {
  nbCapture(); const w = D.nb;
  if (!w.nbn && !w.nen) return err(lab(ERR.name_required));
  if (!/^[A-Z0-9][A-Z0-9_-]{1,23}$/.test(w.code)) return err(lab(X.bcodeBad));
  if (tplStatus(w.tpl) === 'not_implemented' && !w.ack) return err(lab(X.ack));
  w.step = 2; nbDraw();
}
async function nbRun() {
  nbCapture(); const w = D.nb;
  if (!w.rows.every((r) => r.pbn || r.pen)) return err(lab(ERR.name_required));
  const old = $('#nb_run'); if (old) { old.disabled = true; old.textContent = T('working'); }
  const res = []; w.res = res; const ok = (label) => res.push({ ok: true, label }); const bad = (label, e) => res.push({ ok: false, label, msg: eText(e) });
  const owner = lab(L(w.nbn || w.nen, w.nen || w.nbn, w.nen || w.nbn));
  const save = (parent, kind, code, bn, en, tpl, key) => sb.rpc('org_unit_save', { p_id: null, p_parent: parent, p_kind: kind, p_code: code, p_name_bn: bn, p_name_en: en || null, p_template: tpl || null, p_attrs: {}, p_client: key });
  let leId = w.le !== 'new' ? Number(w.le) : null;
  if (leId == null) {
    const g = [...O().flat().values()].find((u) => u.kind === 'group');
    if (!g) { bad(T('le'), { message: 'bad_parent' }); w.step = 3; return nbDraw(); }
    const r = await save(g.id, 'legal_entity', 'LE-' + w.code, w.nbn || w.nen, w.nen, null, w.keys.le);
    if (r.error) { bad(T('le') + ' LE-' + w.code, r.error); w.step = 3; return nbDraw(); }
    leId = r.data.id; w.leId = leId;
  }
  const rb = await save(leId, 'business', w.code, w.nbn || w.nen, w.nen, w.tpl, w.keys.biz);
  if (rb.error) { bad(T('newBiz') + ' ' + owner, rb.error); w.step = 3; return nbDraw(); }
  const bizId = rb.data.id; ok(T('newBiz') + ' · ' + owner + ' (' + rb.data.code + ')');
  let i = 0;
  for (const r of w.rows) {
    i += 1; let unit = null; const label = kindName(r.kind) + ' · ' + (r.pen || r.pbn);
    if (w.asBranch) {
      const ub = await save(bizId, 'branch', w.code + '-B' + i, r.pbn || r.pen, r.pen, null, r.bkey);
      if (ub.error) { bad(T('inBranch') + ' · ' + (r.pen || r.pbn), ub.error); continue; }
      unit = ub.data.id;
    }
    const pr = await createPlace(bizId, { kind: r.kind, bn: r.pbn, en: r.pen, code: '', branch: unit }, r.key);
    if (pr.error) bad(label, pr.error); else ok(label + ' (' + (pr.data && pr.data.code) + ')');
  }
  await refreshEnv();
  w.step = 3; nbDraw();
}

Object.assign(H, {
  pl_add: (a) => addSheet(a.dataset.v),
  pl_list: (a) => listSheet(a.dataset.v),
  pl_save: async (a) => {
    const kind = ($('#pl_kind') || {}).value, bn = (($('#pl_nbn') || {}).value || '').trim(), en = (($('#pl_nen') || {}).value || '').trim(), code = (($('#pl_code') || {}).value || '').trim().toLowerCase(), br = ($('#pl_br') || {}).value || '';
    if (!bn && !en) return err(lab(ERR.name_required));
    if (code && !CODE_RE.test(code)) return err(lab(ERR.bad_code));
    const r = await createPlace(a.dataset.biz, { kind, bn, en, code, branch: br }, D.client);
    if (r.error) return err(eText(r.error));
    closeSheet(); toast(T('saved')); await refreshEnv(); await listSheet(a.dataset.biz);
  },
  pl_move: (a) => moveSheet(a.dataset.v, a.dataset.biz, a.dataset.nm),
  pl_check: () => checkMove(),
  pl_domove: (a) => doMove(a.dataset.biz),
  nb_start: () => nbStart(),
  nb_next: () => nbNext(),
  nb_back: () => { nbCapture(); D.nb.step = 1; nbDraw(); },
  nb_addrow: () => { nbCapture(); D.nb.rowsTouched = true; if (D.nb.rows.length < 10) D.nb.rows.push({ kind: 'showroom', pbn: '', pen: '', key: rid(), bkey: rid() }); nbDraw(); },
  nb_rm: (a) => { nbCapture(); D.nb.rowsTouched = true; D.nb.rows.splice(Number(a.dataset.v), 1); nbDraw(); },
  nb_run: () => nbRun(),
  nb_go: (a) => { closeSheet(); location.hash = '#/' + a.dataset.v; },
});
document.addEventListener('change', (e) => { if (D.nb && D.nb.step === 1 && e.target && e.target.id === 'nb_tpl') { nbCapture(); nbDraw(); } });
window.BOS_PLACES135 = { cardHTML, topHTML };
})();
