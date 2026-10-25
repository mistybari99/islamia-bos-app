/* Islamia BOS · business context (Stage B2): which business the person is working in, and everything that follows from it.
   Source: org_tree() of phase122 (flat rows: kind 'business' units, parents, location ids) + locations.org_unit_id + report_brand_map. Nothing is written here, no business or brand name lives in this file
   except the LEGACY fallback below (the names the app has always shown) and the two placeholder names phase122 seeds, which are never shown as a brand.
   B.biz.list()       the businesses this person may see (one for everybody today -> nothing changes on screen)
   B.biz.multi()      true only when the person's scope holds more than one business: then (and only then) the drawer shows the switcher and the location lists are cut to the chosen business
   B.biz.cur()        chosen business id, or 'all' (owner master view, owner only, clearly labelled); default = the first business (the original one)
   B.ENV.locs         now the locations of the chosen business (B.ENV.locsAll = every location the app loaded); with one business, or none loaded, it is exactly the old list
   B.biz.brand()      {bn,en}: the chosen business name when the owner set one, else the legacy name. B.biz.brandFor(locationId) does the same for a document of that place
   B.biz.brandOpts(fallback, keepTail)   brand pick-list from report_brand_map for the chosen business; the fallback list is used when the table gives nothing
   B.biz.profile() / profileFor(loc) / receipt(loc) / logo(): the profile of the chosen business (phase134 business_profile_list134); the server returns ONLY the caller's own business (owner: all), so a one-business user never learns of a group, a sibling or an 'all' view.
   B.biz.otherTrade() / hasTemplate(...codes) / template(): the template of the chosen business (none = the original sweets business, food_manufacturing). ia.js uses it so screens of other trades are not offered in the sweets menu.
   Event 'bos:biz' fires when the choice changes. Offline / phase122 missing / any error = no businesses, no filter, old behaviour. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc } = A;
const L = B.L, lab = B.lab;
const ENV = B.ENV;
const LEGACY = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };
const PLACEHOLDER = ['মিষ্টি ব্যবসা', 'sweets business'];   // names phase122 seeds for the original business: a placeholder, so the legacy brand stays until the owner renames it
const BZ = { rows: new Map(), biz: [], cur: null, loaded: false, p: null, prof: new Map(), logos: new Map() };   // prof: business id -> profile row of business_profile_list134 (phase134)
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const KEY = () => 'bos_biz_' + uid();
const lget = (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } };
const lset = (k, v) => { try { localStorage.setItem(k, v); } catch (e) { /* private window: lasts until reload */ } };

// ---- locations: the raw list stays in `raw`; readers get the chosen business only when there is more than one business ----
let raw = ENV.locs, cache = null, cacheKey = '';
const filtering = () => BZ.biz.length > 1 && BZ.cur !== 'all' && BZ.cur != null;
function bizIdOfUnit(id) {
  let u = id == null ? null : BZ.rows.get(Number(id)), n = 0;
  while (u && u.kind !== 'business' && n++ < 20) u = u.parent_id == null ? null : BZ.rows.get(Number(u.parent_id));
  return u && u.kind === 'business' ? Number(u.id) : null;
}
// a location with no unit yet (created after the first paste) belongs to the original (first) business, so it never disappears
const locBizId = (l) => { const b = l && bizIdOfUnit(l.org_unit_id); return b != null ? b : (BZ.biz[0] ? BZ.biz[0].id : null); };
Object.defineProperty(ENV, 'locs', { configurable: true, enumerable: true,
  get() { if (!raw || !filtering()) return raw; const k = BZ.cur + '|' + raw.length; if (cache && cacheKey === k && cache.src === raw) return cache.v; cache = { src: raw, v: raw.filter((l) => locBizId(l) === BZ.cur) }; cacheKey = k; return cache.v; },
  set(v) { raw = v; cache = null; } });
Object.defineProperty(ENV, 'locsAll', { configurable: true, get: () => raw });

// ---- loading ----
async function loadBiz() {
  BZ.rows = new Map(); BZ.biz = [];
  try {
    const r = await sb.rpc('org_tree');
    const rows = r && !r.error && Array.isArray(r.data) ? r.data : [];
    rows.forEach((x) => BZ.rows.set(Number(x.id), x));
    BZ.biz = rows.filter((x) => x.kind === 'business' && x.status !== 'inactive').map((x) => ({ id: Number(x.id), code: x.code, name_bn: x.name_bn, name_en: x.name_en, template_code: x.template_code })).sort((a, b) => a.id - b.id);
  } catch (e) { BZ.biz = []; }
  BZ.prof = new Map();
  try {   // phase134: the profile of each business (name, logo, address, receipt text). The server returns the caller's own business only (the owner: all). Missing function = old behaviour.
    const pr = await sb.rpc('business_profile_list134');
    (pr && !pr.error && Array.isArray(pr.data) ? pr.data : []).forEach((x) => BZ.prof.set(Number(x.org_unit_id), x));
    BZ.biz.forEach((b) => { const x = BZ.prof.get(b.id); if (x && x.display_name_bn) { b.name_bn = x.display_name_bn; b.name_en = x.display_name_en || x.display_name_bn; } });
  } catch (e) { BZ.prof = new Map(); }
  try {
    const m = await sb.from('report_brand_map').select('*');
    ENV.brandMap = m && !m.error && Array.isArray(m.data) ? m.data : [];
  } catch (e) { ENV.brandMap = []; }
  const saved = lget(KEY());
  const ok = (v) => (v === 'all' ? isOwner() && BZ.biz.length > 1 : BZ.biz.some((b) => String(b.id) === String(v)));
  BZ.cur = ok(saved) ? (saved === 'all' ? 'all' : Number(saved)) : (BZ.biz[0] ? BZ.biz[0].id : null);
  BZ.loaded = true; cache = null; applyTitle();
}
const origLoad = B.loadStatic;
B.loadStatic = function () { return origLoad.apply(this, arguments).then(() => (BZ.loaded ? null : (BZ.p || (BZ.p = loadBiz().finally(() => { BZ.p = null; }))))); };

// ---- brand ----
function brandOfBiz(b) {
  if (!b) return LEGACY;
  const bn = String(b.name_bn || '').trim(), en = String(b.name_en || '').trim();
  const ph = (s) => !s || PLACEHOLDER.includes(s.toLowerCase());
  if (ph(bn) && ph(en)) return LEGACY;
  return { bn: bn || en, en: en || bn, custom: true };
}
const bizById = (id) => BZ.biz.find((b) => b.id === Number(id));
function brand() { return brandOfBiz(BZ.cur === 'all' || BZ.cur == null ? BZ.biz[0] : bizById(BZ.cur)); }
function profFor(locId) { const l = (raw || []).find((x) => x.id === locId); return l ? profOf(bizById(locBizId(l)) && bizById(locBizId(l)).id) : curProf(); }
function brandFor(locId) {
  const l = (raw || []).find((x) => x.id === locId);
  return l ? brandOfBiz(bizById(locBizId(l))) : brand();
}
const profOf = (id) => (id == null ? null : BZ.prof.get(Number(id)) || null);
function curProf() { return profOf(BZ.cur === 'all' || BZ.cur == null ? (BZ.biz[0] && BZ.biz[0].id) : BZ.cur); }
// signed URL of the business logo (private bucket); cached, drawn into the drawer head when it arrives
function logoSrc(p) {
  const path = p && p.logo_path; if (!path) return null;
  if (BZ.logos.has(path)) return BZ.logos.get(path) || null;
  BZ.logos.set(path, '');
  try { sb.storage.from('photos').createSignedUrl(path, 3600).then((r) => { if (r && r.data && r.data.signedUrl) { BZ.logos.set(path, r.data.signedUrl); applyTitle(); } }).catch(() => {}); } catch (e) { /* no logo */ }
  return null;
}
function applyTitle() {
  try {
    const b = brand(); if (b.custom) document.title = b.bn + ' · ' + b.en;
    const pf = curProf(); const tc = pf && pf.theme_color; if (tc) { const m = document.querySelector('meta[name=theme-color]'); if (m) m.setAttribute('content', tc); }
    const lg = logoSrc(pf); if (lg) document.querySelectorAll('.dr-head img').forEach((i) => { if (i.getAttribute('src') !== lg) i.setAttribute('src', lg); });
    document.querySelectorAll('h1.brandh').forEach((h) => { h.innerHTML = `<span class="bn">${esc(b.bn)}</span><span class="lat">${esc(b.en)}</span>`; });   // a header drawn before the businesses arrived
  } catch (e) { /* keep the static title */ }
}

// ---- brand pick-list (forms): DB brands of the chosen business; fallback keeps the old list and its stored codes ----
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9ঀ-৿]/g, '');
function brandOpts(fallback, tailCodes) {
  const fb = fallback || [], tail = fb.filter((x) => (tailCodes || []).includes(x[0]));
  const map = (ENV.brandMap || []).filter((m) => !filtering() || (ENV.locs || []).some((l) => l.id === m.location_id));
  const seen = new Map(); map.forEach((m) => { if (!seen.has(m.brand_code)) seen.set(m.brand_code, m); });
  if (!seen.size) return fb;
  const head = [...seen.values()].map((m) => {
    const old = fb.find((x) => !(tailCodes || []).includes(x[0]) && x[1] && x[1].en && norm(x[1].en) === norm(m.brand_en));   // same brand as the old list: keep its stored code
    return [old ? old[0] : m.brand_code, L(m.brand_bn, m.brand_en || m.brand_bn, m.brand_en || m.brand_bn)];
  });
  return [...head, ...tail];
}

// ---- business template gate (owner decision: the sweets business, template food_manufacturing, sees only sweets-relevant screens) ----
// A business with no template is the original (sweets) business. The screens of other trades stay registered (routes keep working by link) but are offered in menus / Home / search only when a business in the person's current view has a template other than the sweets one.
const SWEETS_TPL = 'food_manufacturing';
function tplCodes() {
  const bs = BZ.cur === 'all' || BZ.cur == null ? BZ.biz : [bizById(BZ.cur)].filter(Boolean);
  return bs.map((b) => b.template_code || SWEETS_TPL);
}
const hasTemplate = (...codes) => tplCodes().some((c) => codes.includes(c));
const otherTrade = () => tplCodes().some((c) => c !== SWEETS_TPL);
const curTemplate = () => tplCodes().join(',');

// ---- switcher ----
const T = {
  biz: L('ব্যবসা', 'Business', 'Business'), all: L('সব ব্যবসা (মালিকের মাস্টার ভিউ)', 'All businesses (owner master view)', 'সব business (owner master view)'),
  allnote: L('এখন সব ব্যবসার হিসাব একসাথে দেখা হচ্ছে।', 'You are looking at all businesses together.', 'এখন সব business একসাথে দেখা হচ্ছে।'),
};
// the group name exists only in the OWNER's tree (the server never sends it to anybody else); shown on the owner-only master view
function groupName() { if (!isOwner()) return ''; for (const r of BZ.rows.values()) if (r.kind === 'group') return String(S.lang === 'en' ? (r.name_en || r.name_bn) : (r.name_bn || r.name_en)) || ''; return ''; }
function switcherHTML() {
  if (BZ.biz.length < 2) return '';
  const name = (b) => lab(L(b.name_bn || b.name_en || b.code, b.name_en || b.name_bn || b.code, b.name_en || b.name_bn || b.code));
  const opts = BZ.biz.map((b) => `<option value="${b.id}" ${BZ.cur === b.id ? 'selected' : ''}>${esc(name(b))}</option>`).join('') + (isOwner() ? `<option value="all" ${BZ.cur === 'all' ? 'selected' : ''}>${esc(lab(T.all))}</option>` : '');
  return `<div class="dr-biz" id="nav_bizbox" style="padding:6px 12px"><label for="nav_biz" style="font-size:.85rem;color:var(--muted)">${esc(lab(T.biz))}</label>
    <select id="nav_biz" aria-label="${esc(lab(T.biz))}" style="width:100%;min-height:44px">${opts}</select>${BZ.cur === 'all' ? `<div class="chip warn" style="margin-top:4px;white-space:normal">${esc(lab(T.allnote))}${groupName() ? ' · ' + esc(groupName()) : ''}</div>` : ''}</div>`;
}
function setCur(v) {
  if (v === 'all' ? !(isOwner() && BZ.biz.length > 1) : !bizById(v)) return false;
  BZ.cur = v === 'all' ? 'all' : Number(v); cache = null; lset(KEY(), String(BZ.cur)); applyTitle();
  try { window.dispatchEvent(new CustomEvent('bos:biz', { detail: { id: BZ.cur } })); } catch (e) { /* old browser */ }
  return true;
}
document.addEventListener('change', (e) => {
  if (!e.target || e.target.id !== 'nav_biz') return;
  if (setCur(e.target.value === 'all' ? 'all' : Number(e.target.value))) {
    try { window.BOS_NAV && window.BOS_NAV.afterBiz && window.BOS_NAV.afterBiz(); } catch (x) { /* screen redraws on the next visit */ }
  }
});

B.biz = {
  load: () => B.loadStatic(), list: () => BZ.biz.slice(), multi: () => BZ.biz.length > 1, cur: () => BZ.cur, isAll: () => BZ.cur === 'all', setCur, brand, brandFor, brandOpts, switcherHTML, locBizId, hasTemplate, otherTrade, template: curTemplate,
  sig: () => (BZ.biz.length > 1 ? String(BZ.cur) : '') + '|' + curTemplate() + '|' + (brand().custom ? brand().en : '') + '|' + ((curProf() || {}).logo_path || ''),
  groupName, profile: () => curProf(), profileFor: profFor, logo: () => logoSrc(curProf()), reload: () => { BZ.loaded = false; return B.loadStatic(); },
  receipt: (locId) => { const p = locId ? profFor(locId) : curProf(); return p ? { header: p.receipt_header || '', footer: p.receipt_footer || '', address: p.address || '', phone: p.phone || '' } : { header: '', footer: '', address: '', phone: '' }; }, legacy: LEGACY, text: (b) => (S.lang === 'en' ? (b || brand()).en : (b || brand()).bn),
};
})();
