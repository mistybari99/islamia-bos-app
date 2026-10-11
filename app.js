/* Islamia BOS · Phase 1 · plain JavaScript, no build step. */
(() => {
'use strict';
const C = window.BOS_CONFIG, T = window.BOS_T;
const sb = window.supabase.createClient(C.url, C.key, { auth: { persistSession: true, autoRefreshToken: true } });

// ---------- tiny helpers ----------
const store = {
  get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } },
};
// the brand name is fixed in every language: never translated, never re-spelled
const BRAND = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };
window.BOS = Object.assign(window.BOS || {}, { BRAND: { hub: { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' }, bari: { bn: 'মিষ্টি বাড়ি', en: 'MISTY BARI' }, cakiz: { bn: 'AL-CAKIZ', en: 'AL-CAKIZ' } } });
const S = { ctx: null, lang: store.get('bos_lang') || 'bn', items: [], itemQ: '', itemCat: '', matrixRole: null, logTable: '' };
const $ = (s, el = document) => el.querySelector(s);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const t = (k) => (T[k] && (T[k][S.lang] || T[k].bn)) || k;
const nm = (o) => !o ? '' : (S.lang === 'en' ? (o.name_en || o.name_bn) : S.lang === 'mix' ? (o.name_mix || o.name_bn) : o.name_bn);
const fmt = (n) => (n === null || n === undefined) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const AREAS = ['master', 'showroom', 'cash', 'stock', 'purchase', 'factory', 'sales', 'staff', 'assets', 'owner', 'settings'];
const CAT = {
  sweet_kg: { bn: 'মিষ্টি (কেজি)', mix: 'মিষ্টি (KG)', en: 'Sweets (KG)' },
  sweet_pc: { bn: 'মিষ্টি (পিস)', mix: 'মিষ্টি (Piece)', en: 'Sweets (Piece)' },
  doi: { bn: 'দই', mix: 'Doi (দই)', en: 'Doi (Curd)' },
  cake_lb: { bn: 'কেক (পাউন্ড)', mix: 'Cake (Pound)', en: 'Cake (Pound)' },
  cake_pc: { bn: 'কেক (পিস)', mix: 'Cake (Piece)', en: 'Cake (Piece)' },
};
const UNIT = { kg: { bn: 'কেজি', mix: 'KG', en: 'KG' }, pc: { bn: 'পিস', mix: 'Piece', en: 'Piece' }, lb: { bn: 'পাউন্ড', mix: 'Pound', en: 'Pound' } };
const catName = (it) => (CAT[it.category] && CAT[it.category][S.lang]) || it.category_bn || it.category || '';
const unitName = (u) => (UNIT[u] && UNIT[u][S.lang]) || u || '';

let toastTimer;
function toast(msg) {
  const el = $('#toast'); el.textContent = msg; el.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('show'), 2600);
}
function fail(e) {
  console.error(e);
  const m = (e && e.message) || '';
  if (/at least one active owner/.test(m)) return toast('কমপক্ষে একজন সক্রিয় মালিক থাকতে হবে / At least one active owner is required');
  if (/entries_paper_no_uq/.test(m)) return toast('এই ছাপা নম্বর আগেই নেওয়া হয়েছে / This printed number was already entered');
  if (/permission|row-level|denied/i.test(m)) return toast(t('err_perm'));
  toast(t('err_generic') + (m ? ' · ' + m.slice(0, 80) : ''));
}
function langBar() {
  return '<div class="lang">' + ['bn', 'mix', 'en'].map((l) =>
    `<button data-act="lang" data-v="${l}" class="${S.lang === l ? 'on' : ''}">${esc(T['lang_' + l][l])}</button>`).join('') + '</div>';
}
function shell(title, body, back) {
  const lead = back ? `<button data-act="go" data-v="${typeof back === 'string' ? back : 'home'}" aria-label="${esc(t('back'))}">←</button>` : '<img class="brand" src="mark.svg" alt="">';
  const h1 = title === t('app') ? `<span class="bn">${esc(BRAND.bn)}</span><span class="lat">${esc(BRAND.en)}</span>` : esc(title);
  $('#app').innerHTML = `<header class="top">${lead}<h1 class="${title === t('app') ? 'brandh' : ''}">${h1}</h1>${langBar()}</header>${body}`;
}
function openSheet(html) {
  closeSheet();
  const d = document.createElement('div'); d.className = 'sheet-bg'; d.id = 'sheet';
  d.innerHTML = `<div class="sheet">${html}</div>`;
  d.addEventListener('click', (e) => { if (e.target === d) closeSheet(); });
  document.body.appendChild(d);
}
function closeSheet() { const d = $('#sheet'); if (d) d.remove(); }
const tog = (on, act, attrs = '', label) => `<button class="tog ${on ? 'on' : ''}" data-act="${act}" ${attrs}>${esc(label || (on ? t('on') : t('off')))}</button>`;

const ICON = {
  dues: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="16" cy="11" r="5"/><path d="M6 27c1-6 5-9 10-9s9 3 10 9"/><path d="M22 6h5M24.5 3.5v5" stroke-width="2"/></svg>',
  numaudit: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8h6M20 8h6M6 16h4M14 16h4M22 16h4M6 24h6M20 24h6"/></svg>',
  biz: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 27h24"/><rect x="6" y="16" width="5" height="8" rx="1"/><rect x="14" y="10" width="5" height="14" rx="1"/><rect x="22" y="4" width="5" height="20" rx="1"/></svg>',
  pos: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="3" width="20" height="26" rx="3"/><path d="M10 9h12M10 15h3M16 15h3M22 15h0M10 21h3M16 21h3M22 21h0"/></svg>',
  items: '<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="11" fill="none" stroke="currentColor" stroke-width="2.6"/><circle cx="16" cy="16" r="4.6" fill="currentColor"/></svg>',
  itemreq: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 11h20l-5-5M27 21H7l5 5"/></svg>',
  staff: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><circle cx="12" cy="11" r="5"/><circle cx="23" cy="13" r="3.4"/><path d="M3 27c0-5 4-8 9-8s9 3 9 8M21 20c4 0 8 2 8 7"/></svg>',
  matrix: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="currentColor"><rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="12.5" y="4" width="7" height="7" rx="1.5" opacity=".45"/><rect x="21" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="12.5" width="7" height="7" rx="1.5" opacity=".45"/><rect x="12.5" y="12.5" width="7" height="7" rx="1.5"/><rect x="21" y="12.5" width="7" height="7" rx="1.5" opacity=".45"/><rect x="4" y="21" width="7" height="7" rx="1.5"/><rect x="12.5" y="21" width="7" height="7" rx="1.5" opacity=".45"/><rect x="21" y="21" width="7" height="7" rx="1.5"/></svg>',
  rules: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="24" height="24" rx="4"/><path d="M10 16.5l4 4 8-9"/></svg>',
  settings: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M4 9h24M4 16h24M4 23h24"/><circle cx="11" cy="9" r="3.2" fill="var(--ink)"/><circle cx="21" cy="16" r="3.2" fill="var(--ink)"/><circle cx="13" cy="23" r="3.2" fill="var(--ink)"/></svg>',
  logs: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M10 8h18M10 16h18M10 24h18"/><circle cx="4.5" cy="8" r="1.4" fill="currentColor"/><circle cx="4.5" cy="16" r="1.4" fill="currentColor"/><circle cx="4.5" cy="24" r="1.4" fill="currentColor"/></svg>',
  exceptions: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4l13 23H3z"/><path d="M16 13v7M16 24h.01"/></svg>',
  releases: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 11-3"/></svg>',
  locset: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M16 29s9-8 9-15a9 9 0 0 0-18 0c0 7 9 15 9 15z"/><circle cx="16" cy="14" r="3.2"/></svg>',
  backup: '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4v16M9 14l7 7 7-7M5 27h22"/></svg>',
};
const TONE = { dues: 't-gold', numaudit: 't-ink', biz: 't-gold', pos: 't-ruby', items: 't-gold', itemreq: 't-gold', staff: 't-ruby', matrix: 't-ruby', rules: '', settings: 't-ink', logs: 't-ink', backup: 't-ink', exceptions: 't-ruby', releases: 't-gold', locset: 't-ink' };
const MARK = '<svg viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="14" fill="#14173a"/><circle cx="32" cy="29" r="16.5" fill="none" stroke="#f2a900" stroke-width="3"/><circle cx="32" cy="29" r="8.8" fill="#f2a900"/><path d="M12 51h40" stroke="#f7eedc" stroke-width="3.2" stroke-linecap="round"/></svg>';

// ---------- auth ----------
const emailOf = (sid) => `${sid.toLowerCase()}@${C.emailDomain}`;
const pwOf = (pin) => `${pin}-bos`;            // lets a 4-digit PIN meet Supabase's minimum password length
const SID_RE = /^[a-z0-9]{3,20}$/i, PIN_RE = /^\d{4,6}$/;

function authErr(msg) {
  let el = $('#a_err');
  if (!el) { el = document.createElement('div'); el.id = 'a_err'; el.className = 'notice bad'; const c = $('.card'); c.parentNode.insertBefore(el, c); }
  el.textContent = msg;
}
function viewAuth(mode = 'login', msg = '') {
  const reg = mode === 'register';
  shell(t('app'), `
    <img class="login-logo" src="logo.webp" alt="${esc(t('app'))}"><p class="muted center" style="margin:0 0 4px">${esc(t('login_sub'))}</p>
    <div class="tabs">
      <button data-act="authmode" data-v="login" class="${reg ? '' : 'on'}">${esc(t('login'))}</button>
      <button data-act="authmode" data-v="register" class="${reg ? 'on' : ''}">${esc(t('register'))}</button>
    </div>
    ${msg ? `<div class="notice bad" id="a_err">${esc(msg)}</div>` : ''}
    <div class="card panel stack">
      ${reg ? `<div><label>${esc(t('full_name'))}</label><input id="a_name" autocomplete="name"></div>` : ''}
      <div><label>${esc(t('staff_id'))}</label><input id="a_sid" autocapitalize="none" autocomplete="username" inputmode="latin"><div class="muted" style="font-size:.8rem">${esc(t('staff_id_hint'))}</div></div>
      <div><label>${esc(t('pin'))}</label><input id="a_pin" type="password" inputmode="numeric" maxlength="6" autocomplete="${reg ? 'new-password' : 'current-password'}"></div>
      <button class="primary full" data-act="${reg ? 'doregister' : 'dologin'}">${esc(reg ? t('register') : t('login'))}</button>
    </div>`);
}
const val = (id) => ($(id) ? $(id).value.trim() : '');

async function doLogin() {
  const sid = val('#a_sid'), pin = val('#a_pin');
  if (!SID_RE.test(sid)) return authErr(t('err_staff_id'));
  if (!PIN_RE.test(pin)) return authErr(t('err_pin'));
  const pre = await sb.rpc('login_precheck', { p_staff: sid });
  if (pre.data && pre.data.locked) return authErr(t('err_locked'));
  const { error } = await sb.auth.signInWithPassword({ email: emailOf(sid), password: pwOf(pin) });
  if (error) { await sb.rpc('login_failed', { p_staff: sid }); return authErr(t('err_login')); }
  await sb.rpc('login_success');
  await start();
}
async function doRegister() {
  const sid = val('#a_sid'), pin = val('#a_pin'), name = val('#a_name');
  if (!name) return authErr(t('err_name'));
  if (!SID_RE.test(sid)) return authErr(t('err_staff_id'));
  if (!PIN_RE.test(pin)) return authErr(t('err_pin'));
  const { data, error } = await sb.auth.signUp({ email: emailOf(sid), password: pwOf(pin), options: { data: { full_name: name } } });
  if (error) return authErr(/already|registered/i.test(error.message) ? t('err_exists') : t('err_generic') + ' · ' + error.message);
  if (!data.session) return authErr(t('err_confirm'));
  await start();
}
async function logout() { await sb.auth.signOut(); S.ctx = null; location.hash = ''; viewAuth(); }

async function loadCtx() {
  const { data, error } = await sb.rpc('my_context');
  if (error) throw error;
  S.ctx = data;
  if (data && data.profile && !store.get('bos_lang')) S.lang = data.profile.lang || 'bn';
}
async function start() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return viewAuth();
  try { await loadCtx(); } catch (e) { fail(e); return viewAuth(); }
  if (!S.ctx) { await sb.auth.signOut(); return viewAuth(); }
  route();
}

// ---------- routing ----------
const OWNER_ONLY = new Set(['staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'releases', 'locset']);
function go(p) { location.hash = '#/' + p; }
function route() {
  if (!S.ctx) return viewAuth();
  const st = S.ctx.profile.status;
  if (st === 'pending') return viewPending();
  if (st === 'disabled') { sb.auth.signOut(); S.ctx = null; return viewAuth('login', t('err_disabled')); }
  const page = (location.hash.replace(/^#\/?/, '') || 'home').split('/')[0];
  if (OWNER_ONLY.has(page) && !S.ctx.is_owner) return viewHome();
  const local = { home: viewHome, items: viewItems, staff: viewStaff, matrix: viewMatrix, rules: viewRules,
     settings: viewSettings, logs: viewLogs, backup: viewBackup, itemreq: viewItemReq };
  const extra = window.BOS_PAGES || {};
  if ((page === 'exceptions' || page === 'releases' || page === 'locset') && !S.ctx.is_owner && !(page === 'exceptions' && Object.values(S.ctx.perms).some((p) => p.approve))) return viewHome();
  (local[page] || extra[page] || viewHome)();
}
window.addEventListener('hashchange', route);
window.BOS_APP = { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store, H: null };

function viewPending() {
  shell(t('app'), `<div class="card stack center"><h2>${esc(t('pending_title'))}</h2>
    <p>${esc(t('pending_text'))}</p>
    <button class="primary full" data-act="recheck">${esc(t('check_again'))}</button>
    <button class="full" data-act="logout">${esc(t('logout'))}</button></div>`);
}

// ---------- home ----------
async function viewHome() {
  const p = S.ctx.profile, perms = S.ctx.perms || {}, owner = S.ctx.is_owner;
  shell(t('app'), `<div class="banner"><div class="roundel"><img src="mark.svg" alt=""></div><div><div class="bn-t">${esc(t('hello'))}, <b>${esc(p.full_name || p.staff_id)}</b></div><div class="bn-s"><span class="since">Since 1988</span> <span class="sid">${esc(p.staff_id)}</span></div></div></div><div id="home"><p class="muted">${esc(t('loading'))}</p></div>
    <button class="full" style="margin-top:18px" data-act="logout">${esc(t('logout'))}</button>`);
  const canDecide = owner || (perms.ITEMS && perms.ITEMS.approve);
  const anyApprove = owner || Object.values(perms).some((p) => p.approve);
  const [forms, pend, itemPending, exOpen, relPend] = await Promise.all([
    sb.from('forms').select('code,area,name_bn,name_mix,name_en,sort,enabled').order('sort'),
    owner ? sb.from('profiles').select('id', { count: 'exact', head: true }).eq('status', 'pending') : Promise.resolve({ count: 0 }),
    canDecide ? sb.from('item_changes').select('id', { count: 'exact', head: true }).eq('status', 'pending') : Promise.resolve({ count: 0 }),
    anyApprove ? sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open') : Promise.resolve({ count: 0 }),
    owner ? sb.from('release_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending') : Promise.resolve({ count: 0 }),
  ]);
  if (forms.error) return fail(forms.error);
  const tiles = [];
  if (owner || (perms.POS && (perms.POS.enter || perms.POS.view))) tiles.push(['pos', t('pos'), ''], ['dues', t('dues'), '']);
  if (owner || (perms.POS && perms.POS.approve)) tiles.push(['biz', t('biz'), '']);
  if (perms.ITEMS && perms.ITEMS.view) tiles.push(['items', t('items'), '']);
  if (perms.ITEMS && (perms.ITEMS.enter || perms.ITEMS.approve)) tiles.push(['itemreq', t('item_req'), itemPending.count ? `<span class="badge">${itemPending.count}</span>` : '']);
  if (anyApprove) tiles.push(['exceptions', t('exceptions'), exOpen.count ? `<span class="badge">${exOpen.count}</span>` : ''], ['numaudit', t('numaudit'), '']);
  if (owner) {
    tiles.push(['releases', t('releases'), relPend.count ? `<span class="badge">${relPend.count}</span>` : '']);
    tiles.push(['staff', t('staff'), pend.count ? `<span class="badge">${pend.count}</span>` : '']);
    tiles.push(['matrix', t('matrix'), ''], ['rules', t('rules'), ''], ['locset', t('locset'), ''], ['settings', t('settings'), ''], ['logs', t('logs'), ''], ['backup', t('backup'), '']);
  }
  const mine = forms.data.filter((f) => f.area !== 'master' && f.code !== 'POS' && perms[f.code] && perms[f.code].view);
  const byArea = AREAS.map((a) => [a, mine.filter((f) => f.area === a)]).filter(([, l]) => l.length);
  $('#home').innerHTML = `<div id="dash"></div><div class="grid">${tiles.map(([go_, label, badge]) =>
      `<button class="tile ${TONE[go_] || ''}" data-act="go" data-v="${go_}">${ICON[go_] || ''}<span>${esc(label)}</span>${badge}</button>`).join('')}</div>
    <div class="orn">${esc(t('forms_title'))}</div>
    ${byArea.length ? byArea.map(([a, l]) => `<div class="card panel"><h3>${esc(t('area_' + a))}</h3>${l.map((f) => {
      const pr = perms[f.code], live = f.code === '0-1' ? owner : (window.BOS && window.BOS.forms && window.BOS.forms[f.code]);
      return `<div class="perm"><div class="row between" ${live ? `data-act="openform" data-v="${f.code}" style="cursor:pointer;min-height:44px"` : 'style="opacity:.6"'}><span><b>${esc(f.code)}</b> · ${esc(nm(f))}</span><span class="row">${
        live ? '' : `<span class="chip">${esc(t('soon'))}</span>`}${pr.enter ? `<span class="chip ok">${esc(t('can_enter'))}</span>` : `<span class="chip">${esc(t('can_view'))}</span>`}${
        pr.approve ? `<span class="chip warn">${esc(t('can_approve'))}</span>` : ''}</span></div></div>`; }).join('')}</div>`).join('')
      : `<p class="muted">${esc(t('no_forms'))}</p>`}`;
  if (window.BOS && window.BOS.dash) window.BOS.dash.render().catch(() => {});
}

// ---------- items ----------
async function viewItems() {
  const can = S.ctx.perms.ITEMS || {};
  shell(t('items'), `<div class="notice ok">${esc(t('price_note'))}</div>
    <div class="row"><input id="i_q" placeholder="${esc(t('search'))}" value="${esc(S.itemQ)}">${can.enter ? `<button class="primary" data-act="itemnew">＋</button>` : ''}</div>
    <div id="i_cats" class="row wrap" style="margin:10px 0"></div><div id="i_list"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  await loadItems(); drawItems();
}
const canCostView = () => !!(S.ctx.perms.ITEM_COST && S.ctx.perms.ITEM_COST.view);
const canCostEnter = () => !!(S.ctx.perms.ITEM_COST && S.ctx.perms.ITEM_COST.enter);
async function loadItems() {
  const [it, co] = await Promise.all([sb.from('items').select('*').order('code'), canCostView() ? sb.from('item_costs').select('*') : Promise.resolve({ data: [] })]);
  if (it.error) return fail(it.error);
  if (co.error) return fail(co.error);
  const cm = new Map((co.data || []).map((c) => [c.item_id, c.cost_price]));
  S.items = it.data.map((i) => ({ ...i, cost_price: canCostView() ? (cm.has(i.id) ? cm.get(i.id) : null) : undefined }));
}
function drawItems() {
  const can = S.ctx.perms.ITEMS || {};
  const cats = [...new Set(S.items.map((i) => i.category).filter(Boolean))];
  const q = S.itemQ.toLowerCase();
  const list = S.items.filter((i) => (!S.itemCat || i.category === S.itemCat) &&
    (!q || [i.name_bn, i.name_en, i.name_mix, i.code].some((x) => (x || '').toLowerCase().includes(q))));
  $('#i_cats').innerHTML = [['', t('all')], ...cats.map((c) => [c, catName(S.items.find((i) => i.category === c))])].map(([c, l]) =>
    `<button class="tog ${S.itemCat === c ? 'on' : ''}" data-act="itemcat" data-v="${esc(c)}">${esc(l)}</button>`).join('');
  $('#i_list').innerHTML = list.map((i) => {
    const loss = i.cost_price != null && i.sell_price != null && Number(i.cost_price) >= Number(i.sell_price);
    return `<div class="card item" ${can.enter ? `data-act="itemedit" data-v="${i.id}"` : ''}>
      <div><div class="nm">${esc(nm(i))} ${i.is_active ? '' : `<span class="chip bad">${esc(t('inactive'))}</span>`}</div>
        <div class="muted" style="font-size:.85rem">${esc(i.code)} · ${esc(catName(i))} · ${esc(unitName(i.unit))}</div>
        ${loss ? `<div class="chip warn" style="margin-top:4px">${esc(t('loss_warn'))}</div>` : ''}</div>
      <div class="pr"><div><b>৳ ${fmt(i.sell_price)}</b></div>${i.cost_price === undefined ? '' : `<div class="muted" style="font-size:.85rem">${fmt(i.cost_price)}</div>`}</div></div>`;
  }).join('') || `<p class="muted center">—</p>`;
}
function itemSheet(it) {
  const cats = [...new Set(S.items.map((i) => i.category).filter(Boolean))];
  const opt = (v, cur, label) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(label)}</option>`;
  const f = it || { name_bn: '', name_en: '', name_mix: '', category: cats[0] || '', unit: 'kg', sell_price: '', cost_price: '', is_active: true };
  openSheet(`<h2>${esc(it ? t('edit_item') : t('add_item'))}${it ? ' · ' + esc(it.code) : ''}</h2><div class="stack">
    <div><label>${esc(t('name_bn'))}</label><input id="f_bn" value="${esc(f.name_bn)}"></div>
    <div><label>${esc(t('name_en'))}</label><input id="f_en" value="${esc(f.name_en)}"></div>
    <div><label>${esc(t('name_mix'))}</label><input id="f_mix" value="${esc(f.name_mix)}"></div>
    <div class="row"><div style="flex:1"><label>${esc(t('category'))}</label><select id="f_cat">${cats.map((c) => opt(c, f.category, catName(S.items.find((i) => i.category === c)))).join('')}</select></div>
      <div style="flex:1"><label>${esc(t('unit'))}</label><select id="f_unit">${Object.keys(UNIT).map((u) => opt(u, f.unit, unitName(u))).join('')}</select></div></div>
    <div class="row"><div style="flex:1"><label>${esc(t('sell_price'))}</label><input id="f_sell" inputmode="decimal" value="${esc(f.sell_price)}"></div>
      ${canCostView() ? `<div style="flex:1"><label>${esc(t('cost_price'))}</label><input id="f_cost" inputmode="decimal" value="${esc(f.cost_price)}" ${canCostEnter() ? '' : 'readonly'}></div>` : ''}</div>
    <div class="row between"><span>${esc(t('active'))}</span>${tog(f.is_active, 'sheettog', 'id="f_act"')}</div>
    ${S.ctx.is_owner ? '' : `<div class="notice warn">${esc(t('needs_approval'))}</div>`}
    <div><label>${esc(t('reason_note'))}</label><input id="f_note"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button>
      <button class="primary full" data-act="itemsave" data-v="${it ? it.id : ''}">${esc(t('save'))}</button></div></div>`);
}
async function saveItem(id) {
  const num = (v) => (v === '' ? null : Number(v));
  const cur = id ? S.items.find((i) => i.id === id) : null;
  const next = { name_bn: val('#f_bn'), name_en: val('#f_en') || null, name_mix: val('#f_mix') || null,
    category: val('#f_cat') || null, unit: val('#f_unit') || null, sell_price: num(val('#f_sell')),
    is_active: $('#f_act').classList.contains('on') };
  if ($('#f_cost') && canCostEnter()) next.cost_price = num(val('#f_cost'));
  if (!next.name_bn) return toast(t('err_item_name'));
  for (const k of ['sell_price', 'cost_price']) if (k in next && next[k] !== null && (!Number.isFinite(next[k]) || next[k] < 0)) return toast(t('err_price'));
  const cat = S.items.find((i) => i.category === next.category);
  if (cat) next.category_bn = cat.category_bn;
  const same = (a, b) => (a ?? null) === (b ?? null) || (typeof a === 'number' || typeof b === 'number') && Number(a) === Number(b);
  const patch = {};
  for (const k of Object.keys(next)) if (!cur || !same(cur[k], next[k])) patch[k] = next[k];
  if (cur && !Object.keys(patch).length) return closeSheet();
  const { data, error } = await sb.rpc('submit_item_change', { p_item: id || null, p_patch: patch, p_note: val('#f_note') || null });
  if (error) return fail(error);
  closeSheet();
  toast(data && data.status === 'applied' ? t('saved') : t('sent_for_approval'));
  await loadItems(); drawItems();
}

// ---------- item change requests ----------
async function viewItemReq() {
  shell(t('item_req'), `<div id="ir_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const [ch] = await Promise.all([sb.from('item_changes').select('*').order('id', { ascending: false }).limit(60), loadItems()]);
  if (ch.error) return fail(ch.error);
  const canDecide = S.ctx.is_owner || (S.ctx.perms.ITEMS && S.ctx.perms.ITEMS.approve);
  const label = { name_bn: t('name_bn'), name_en: t('name_en'), name_mix: t('name_mix'), category: t('category'), unit: t('unit'),
    sell_price: t('sell_price'), cost_price: t('cost_price'), is_active: t('active'), category_bn: null };
  const showVal = (k, v) => (v === null || v === undefined ? '—' : k === 'is_active' ? (v ? t('yes') : t('no')) : v);
  const body = ch.data.map((c) => {
    const it = c.item_id ? S.items.find((i) => i.id === c.item_id) : null;
    const rows = Object.entries(c.patch).filter(([k]) => label[k]).map(([k, v]) => {
      const was = it ? (k === 'cost_price' && it.cost_price === undefined ? '' : showVal(k, it[k])) : null;
      return `<div class="row between"><span class="muted">${esc(label[k])}</span><span>${was === null || was === '' ? '' : esc(was) + ' → '}<b>${esc(showVal(k, v))}</b></span></div>`; }).join('');
    const cls = c.status === 'approved' ? 'ok' : c.status === 'rejected' ? 'bad' : 'warn';
    return `<div class="card stack"><div class="row between"><b>${esc(it ? nm(it) + ' · ' + it.code : t('add_item') + ' · ' + (c.patch.name_bn || ''))}</b><span class="chip ${cls}">${esc(t('req_' + c.status))}</span></div>
      ${rows}<div class="muted" style="font-size:.82rem">${esc(c.requested_staff || '')} · ${esc(new Date(c.requested_at).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }))}${c.note ? ' · ' + esc(c.note) : ''}</div>
      ${c.status !== 'pending' ? `<div class="muted" style="font-size:.82rem">${esc(c.decided_staff || '')}${c.decision_note ? ' · ' + esc(c.decision_note) : ''}</div>` : ''}
      ${c.status === 'pending' && canDecide ? `<input id="dn_${c.id}" placeholder="${esc(t('reason_note'))}"><div class="row"><button class="danger full" data-act="itemdecide" data-v="${c.id}" data-ok="0">${esc(t('reject'))}</button><button class="primary full" data-act="itemdecide" data-v="${c.id}" data-ok="1">${esc(t('approve'))}</button></div>` : ''}</div>`;
  }).join('');
  $('#ir_body').innerHTML = body || `<p class="muted center">${esc(t('no_requests'))}</p>`;
}

// ---------- staff (owner) ----------
async function viewStaff() {
  shell(t('staff'), `<div id="s_list"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  await drawStaff();
}
async function staffData() {
  const [p, ur, ul, r, l, lf] = await Promise.all([
    sb.from('profiles').select('*').order('created_at'), sb.from('user_roles').select('*'), sb.from('user_locations').select('*'),
    sb.from('roles').select('*').order('sort'), sb.from('locations').select('*').order('sort'), sb.from('login_failures').select('*')]);
  for (const x of [p, ur, ul, r, l, lf]) if (x.error) throw x.error;
  return { profiles: p.data, ur: ur.data, ul: ul.data, roles: r.data, locs: l.data, locked: new Set(lf.data.filter((x) => x.locked).map((x) => x.staff_id)) };
}
async function drawStaff() {
  let d; try { d = await staffData(); } catch (e) { return fail(e); }
  S.staff = d;
  const order = { pending: 0, active: 1, disabled: 2 };
  const list = [...d.profiles].sort((a, b) => order[a.status] - order[b.status]);
  $('#s_list').innerHTML = list.map((p) => {
    const rs = d.ur.filter((x) => x.user_id === p.id).map((x) => nm(d.roles.find((r) => r.code === x.role_code)));
    const cls = p.status === 'active' ? 'ok' : p.status === 'pending' ? 'warn' : 'bad';
    return `<div class="card item" data-act="staffopen" data-v="${p.id}"><div><div class="nm">${esc(p.full_name || p.staff_id)}</div>
      <div class="muted" style="font-size:.85rem">${esc(p.staff_id)}${rs.length ? ' · ' + esc(rs.join(', ')) : ''}</div></div>
      <div><span class="chip ${cls}">${esc(t('status_' + p.status))}</span>${d.locked.has(p.staff_id) ? ' <span class="chip bad">🔒</span>' : ''}</div></div>`;
  }).join('');
  if ($('#sheet') && S.staffOpen) staffSheet(S.staffOpen);
}
function staffSheet(id) {
  S.staffOpen = id;
  const d = S.staff, p = d.profiles.find((x) => x.id === id); if (!p) return closeSheet();
  const myRoles = new Set(d.ur.filter((x) => x.user_id === id).map((x) => x.role_code));
  const myLocs = new Set(d.ul.filter((x) => x.user_id === id).map((x) => x.location_id));
  openSheet(`<h2>${esc(p.full_name || p.staff_id)} <span class="muted">· ${esc(p.staff_id)}</span></h2>
    <div class="row wrap">${p.status !== 'active' ? `<button class="primary" data-act="setstatus" data-v="${id}" data-s="active">${esc(p.status === 'pending' ? t('approve') : t('enable'))}</button>` : ''}
      ${p.status === 'active' ? `<button class="danger" data-act="setstatus" data-v="${id}" data-s="disabled">${esc(t('disable'))}</button>` : ''}
      ${d.locked.has(p.staff_id) ? `<button data-act="unlock" data-v="${esc(p.staff_id)}">🔒 ${esc(t('unlock'))}</button>` : ''}</div>
    <h2>${esc(t('roles'))}</h2>${d.roles.map((r) => `<div class="row between perm"><span>${esc(nm(r))}</span>${tog(myRoles.has(r.code), 'userrole', `data-u="${id}" data-r="${r.code}"`)}</div>`).join('')}
    <h2>${esc(t('locations'))}</h2>${d.locs.map((l) => `<div class="row between perm"><span>${esc(nm(l))}</span>${tog(myLocs.has(l.id), 'userloc', `data-u="${id}" data-l="${l.id}"`)}</div>`).join('')}
    <button class="full" style="margin-top:14px" data-act="closesheet">${esc(t('done'))}</button>`);
}

// ---------- role x form matrix (owner) ----------
async function viewMatrix() {
  shell(t('matrix'), `<div id="m_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const [r, f, p] = await Promise.all([sb.from('roles').select('*').order('sort'), sb.from('forms').select('*').order('sort'), sb.from('role_form_perms').select('*')]);
  for (const x of [r, f, p]) if (x.error) return fail(x.error);
  S.m = { roles: r.data.filter((x) => x.code !== 'owner'), forms: f.data, perms: p.data };
  if (!S.matrixRole || !S.m.roles.find((x) => x.code === S.matrixRole)) S.matrixRole = S.m.roles[0].code;
  drawMatrix();
}
function drawMatrix() {
  const { roles, forms, perms } = S.m, role = roles.find((x) => x.code === S.matrixRole);
  const get = (fc) => perms.find((x) => x.role_code === role.code && x.form_code === fc) || { can_view: false, can_enter: false, can_approve: false };
  $('#m_body').innerHTML = `<div class="notice warn">${esc(t('hint_defaults'))}</div><div class="notice ok">${esc(t('owner_note'))}</div>
    <div class="row wrap">${roles.map((x) => `<button class="tog ${x.code === role.code ? 'on' : ''}" data-act="mrole" data-v="${x.code}">${esc(nm(x))}</button>`).join('')}</div>
    <div class="card"><div class="row between"><div><b>${esc(t('self_approve'))}</b><div class="muted" style="font-size:.8rem">${esc(t('self_approve_hint'))}</div></div>
      ${tog(role.allow_self_approve, 'selfapprove', `data-v="${role.code}"`)}</div></div>
    <p class="muted">${esc(t('hint_matrix'))}</p>
    ${AREAS.map((a) => [a, forms.filter((f) => f.area === a)]).filter(([, l]) => l.length).map(([a, l]) => `<div class="card"><b>${esc(t('area_' + a))}</b>${l.map((f) => {
      const g = get(f.code);
      return `<div class="perm"><div class="nm">${esc(f.code === 'ITEMS' ? '' : f.code + ' · ')}${esc(nm(f))}</div><div class="row wrap">
        ${tog(g.can_view, 'perm', `data-f="${f.code}" data-k="view"`, t('can_view'))}${tog(g.can_enter, 'perm', `data-f="${f.code}" data-k="enter"`, t('can_enter'))}${tog(g.can_approve, 'perm', `data-f="${f.code}" data-k="approve"`, t('can_approve'))}</div></div>`; }).join('')}</div>`).join('')}`;
}
async function togglePerm(fc, k) {
  const role = S.matrixRole, cur = S.m.perms.find((x) => x.role_code === role && x.form_code === fc) || { can_view: false, can_enter: false, can_approve: false };
  const n = { view: cur.can_view, enter: cur.can_enter, approve: cur.can_approve }; n[k] = !n[k];
  if (k === 'view' && !n.view) { n.enter = false; n.approve = false; }   // no viewing -> no entering or approving
  else if (n.enter || n.approve) n.view = true;                         // entering or approving needs viewing
  const row = { role_code: role, form_code: fc, can_view: n.view, can_enter: n.enter, can_approve: n.approve };
  const { error } = await sb.from('role_form_perms').upsert(row, { onConflict: 'role_code,form_code' });
  if (error) return fail(error);
  const i = S.m.perms.findIndex((x) => x.role_code === role && x.form_code === fc);
  if (i >= 0) S.m.perms[i] = row; else S.m.perms.push(row);
  drawMatrix();
}

// ---------- form rules (owner) ----------
async function viewRules() {
  shell(t('rules'), `<div id="r_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const { data, error } = await sb.from('forms').select('*').order('sort'); if (error) return fail(error);
  S.rules = data.filter((f) => f.code !== 'ITEMS'); drawRules();
}
function drawRules() {
  $('#r_body').innerHTML = AREAS.map((a) => [a, S.rules.filter((f) => f.area === a)]).filter(([, l]) => l.length).map(([a, l]) => `<div class="card"><b>${esc(t('area_' + a))}</b>${l.map((f) =>
    `<div class="perm"><div class="nm">${esc(f.code)} · ${esc(nm(f))}</div><div class="row wrap">
      ${tog(f.count_first, 'rule', `data-f="${f.code}" data-k="count_first"`, t('rule_count_first'))}${tog(f.red_block, 'rule', `data-f="${f.code}" data-k="red_block"`, t('rule_red_block'))}${tog(f.enabled, 'rule', `data-f="${f.code}" data-k="enabled"`, t('rule_enabled'))}</div></div>`).join('')}</div>`).join('');
}
async function toggleRule(fc, k) {
  const f = S.rules.find((x) => x.code === fc), v = !f[k];
  const { error } = await sb.from('forms').update({ [k]: v }).eq('code', fc); if (error) return fail(error);
  f[k] = v; drawRules();
}

// ---------- settings (owner) ----------
async function viewSettings() {
  shell(t('settings'), `<div id="st_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const { data, error } = await sb.from('settings').select('*').order('key'); if (error) return fail(error);
  const label = (s) => (S.lang === 'en' ? s.label_en : S.lang === 'mix' ? s.label_mix : s.label_bn) || s.label_bn || s.key;
  $('#st_body').innerHTML = data.map((s) => `<div class="card stack"><div class="row between"><b>${esc(label(s))}</b>${s.value === null ? `<span class="chip warn">${esc(t('need_data'))}</span>` : ''}</div>
    <div class="row"><input id="sv_${esc(s.key)}" value="${esc(s.value === null ? '' : (typeof s.value === 'string' ? s.value : JSON.stringify(s.value)))}">
    <button class="primary" data-act="setsave" data-v="${esc(s.key)}">${esc(t('save'))}</button></div></div>`).join('');
}
async function saveSetting(key) {
  let raw = val('#sv_' + key), v;
  if (raw === '') v = null; else if (/^-?\d+(\.\d+)?$/.test(raw)) v = Number(raw); else if (raw === 'true' || raw === 'false') v = raw === 'true'; else v = raw;
  const { error } = await sb.from('settings').update({ value: v, updated_at: new Date().toISOString(), updated_by: S.ctx.profile.id }).eq('key', key);
  if (error) return fail(error); toast(t('saved'));
}

// ---------- change log (owner) ----------
async function viewLogs() {
  shell(t('logs'), `<div class="row"><select id="l_t"><option value="">${esc(t('all_tables'))}</option>${['items', 'profiles', 'user_roles', 'user_locations', 'role_form_perms', 'roles', 'forms', 'locations', 'settings'].map((x) => `<option ${S.logTable === x ? 'selected' : ''}>${x}</option>`).join('')}</select></div>
    <div id="l_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  let q = sb.from('audit_log').select('*').order('id', { ascending: false }).limit(100);
  if (S.logTable) q = q.eq('table_name', S.logTable);
  const { data, error } = await q; if (error) return fail(error);
  const when = (x) => new Date(x).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', hour12: true });
  const short = (o) => { const s = JSON.stringify(o); return s.length > 260 ? s.slice(0, 260) + '…' : s; };
  $('#l_body').innerHTML = data.map((r) => {
    const d = r.detail || {};
    const body = r.action === 'update' ? `${short(d.old)}\n→ ${short(d.new)}` : short(d.new || d.old);
    return `<div class="card log"><div class="row between"><b>${esc(r.table_name)} · ${esc(r.action)}</b><span class="k">${esc(when(r.at))}</span></div>
      <div class="k">${esc(r.staff_id || 'system')} · ${esc(r.record_id || '')}</div><pre class="diff">${esc(body)}</pre></div>`;
  }).join('') || `<p class="muted center">${esc(t('logs_empty'))}</p>`;
}

// ---------- backup (owner) ----------
const BACKUP_TABLES = ['profiles', 'roles', 'user_roles', 'locations', 'user_locations', 'forms', 'role_form_perms', 'items', 'item_price_history', 'settings', 'audit_log', 'corrections'];
function viewBackup() {
  shell(t('backup'), `<div class="card stack"><p>${esc(t('backup_text'))}</p>
    <button class="primary full" data-act="bk_all">${esc(t('backup_all'))}</button>
    <button class="full" data-act="bk_items">${esc(t('backup_items'))}</button></div>`, true);
}
async function fetchAll(table) {
  const out = []; for (let from = 0; ; from += 1000) {
    const { data, error } = await sb.from(table).select('*').range(from, from + 999); if (error) throw error;
    out.push(...data); if (data.length < 1000) break; }
  return out;
}
function download(name, text, type) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name;
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
async function backupAll() {
  try { const o = { exported_at: new Date().toISOString(), tables: {} };
    for (const tb of BACKUP_TABLES) o.tables[tb] = await fetchAll(tb);
    download(`bos-backup-${today()}.json`, JSON.stringify(o, null, 1), 'application/json'); toast(t('done'));
  } catch (e) { fail(e); }
}
async function backupItems() {
  try { const rows = await fetchAll('items'); const cols = ['code', 'name_bn', 'name_en', 'name_mix', 'category', 'unit', 'sell_price', 'cost_price', 'is_active'];
    const q = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    download(`bos-items-${today()}.csv`, '﻿' + [cols.join(','), ...rows.map((r) => cols.map((c) => q(r[c])).join(','))].join('\n'), 'text/csv'); toast(t('done'));
  } catch (e) { fail(e); }
}

// ---------- events ----------
async function setLang(l) {
  S.lang = l; store.set('bos_lang', l);
  if (S.ctx) sb.rpc('set_my_lang', { p_lang: l });
  closeSheet(); route();
}
const H = {
  lang: (a) => setLang(a.dataset.v),
  go: (a) => go(a.dataset.v),
  authmode: (a) => viewAuth(a.dataset.v),
  dologin: doLogin, doregister: doRegister, logout,
  recheck: async () => { await loadCtx(); route(); },
  closesheet: closeSheet,
  sheettog: (a) => a.classList.toggle('on'),
  itemcat: (a) => { S.itemCat = a.dataset.v; drawItems(); },
  itemnew: () => itemSheet(null),
  itemedit: (a) => itemSheet(S.items.find((i) => i.id === a.dataset.v)),
  itemsave: (a) => saveItem(a.dataset.v),
  itemdecide: async (a) => { const id = Number(a.dataset.v), ok = a.dataset.ok === '1';
    const { error } = await sb.rpc('decide_item_change', { p_id: id, p_approve: ok, p_note: val('#dn_' + id) || null });
    if (error) return /own request/.test(error.message) ? toast(t('err_own_request')) : fail(error); toast(t('saved')); viewItemReq(); },
  staffopen: (a) => staffSheet(a.dataset.v),
  setstatus: async (a) => { const { error } = await sb.from('profiles').update({ status: a.dataset.s }).eq('id', a.dataset.v); if (error) return fail(error); toast(t('saved')); await drawStaff(); },
  unlock: async (a) => { const { error } = await sb.rpc('unlock_staff', { p_staff: a.dataset.v }); if (error) return fail(error); toast(t('saved')); await drawStaff(); },
  userrole: async (a) => { const on = a.classList.contains('on'), u = a.dataset.u, r = a.dataset.r;
    const { error } = on ? await sb.from('user_roles').delete().eq('user_id', u).eq('role_code', r) : await sb.from('user_roles').insert({ user_id: u, role_code: r });
    if (error) return fail(error); await drawStaff(); },
  userloc: async (a) => { const on = a.classList.contains('on'), u = a.dataset.u, l = Number(a.dataset.l);
    const { error } = on ? await sb.from('user_locations').delete().eq('user_id', u).eq('location_id', l) : await sb.from('user_locations').insert({ user_id: u, location_id: l });
    if (error) return fail(error); await drawStaff(); },
  mrole: (a) => { S.matrixRole = a.dataset.v; drawMatrix(); },
  selfapprove: async (a) => { const role = S.m.roles.find((x) => x.code === a.dataset.v), v = !role.allow_self_approve;
    const { error } = await sb.from('roles').update({ allow_self_approve: v }).eq('code', role.code); if (error) return fail(error); role.allow_self_approve = v; drawMatrix(); },
  perm: (a) => togglePerm(a.dataset.f, a.dataset.k),
  rule: (a) => toggleRule(a.dataset.f, a.dataset.k),
  setsave: (a) => saveSetting(a.dataset.v),
  bk_all: backupAll, bk_items: backupItems,
};
window.BOS_APP.H = H;
document.addEventListener('click', (e) => {
  const a = e.target.closest('[data-act]'); if (!a || !H[a.dataset.act]) return;
  Promise.resolve(H[a.dataset.act](a)).catch(fail);
});
document.addEventListener('input', (e) => { if (e.target.id === 'i_q') { S.itemQ = e.target.value; drawItems(); } });
document.addEventListener('change', (e) => { if (e.target.id === 'l_t') { S.logTable = e.target.value; viewLogs(); } });

// start after every script (forms.js, entry.js) has loaded
const boot = () => start().catch(fail);
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
