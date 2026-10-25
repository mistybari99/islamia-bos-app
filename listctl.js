/* Islamia BOS · shared list control (W3). One way to pick from an editable list (option_lists) everywhere:
     - search box when the list is long (rule list_search_min, default 8)
     - "+ Add new" that follows the list's add rule (list_defs.add_rule): open = adds at once, approval = a request the owner decides, owner = only the owner / list manager
     - "Other" = a write-in that is saved to the Other queue (the owner turns it into an option, merges it or rejects it); never a free-text field
     - a retired value that an old record still holds stays visible (marked, not pickable again)
   The SERVER enforces the rule (option_add / option_other_log in supabase/phase15.sql); this file only guides the screen.
   If phase15 is not installed (list_defs missing) every helper falls back to the plain old behaviour.
   API (window.BOS.listctl, plus B.listPick):
     B.listPick(code, opts)  -> { id, html, value(), other(), set(v) }   opts: id, cur, fallback, otherValue, otherBlank, ctx, onChange(value, info), cls
     B.listctl.opts(code, fallback)  -> () => [[value,label]...] (+ the two special choices) for entry.js SEL fields (forms 11-1, 17-1 ...)
     B.listctl.enhance(selectOrSelector, code, cfg)  adds the special choices + behaviour to a <select> that a screen already drew
     B.listctl.pairs(code, pairs, cfg)  adds the special choices to an [[value,label]] array before it is turned into <option>s
   The special choices are the values "__add__:<code>" and "__other__:<code>"; one capturing change listener handles them for every select, so a screen only has
   to offer them and read select.value afterwards (an Other write-in gives cfg.otherValue, '' when cfg.otherBlank, else "other:<text>"; the text is in select.dataset.lpOther). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  add: L('＋ নতুন যোগ', '＋ Add new', '＋ নতুন Add'), req: L('＋ নতুন যোগের অনুরোধ', '＋ Request a new one', '＋ নতুন যোগের Request'), ownerOnly: L('＋ নতুন যোগ (শুধু মালিক)', '＋ Add new (owner only)', '＋ নতুন Add (শুধু Owner)'),
  other: L('অন্যান্য…', 'Other…', 'অন্যান্য…'), search: L('খুঁজুন', 'Search', 'Search'), retired: L('বন্ধ', 'retired', 'retired'),
  nBn: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), nEn: L('ইংরেজি নাম (ঐচ্ছিক)', 'English name (optional)', 'English নাম (ঐচ্ছিক)'),
  otherPh: L('কী লিখবেন?', 'What is it?', 'কী লিখবেন?'), ok: L('ঠিক আছে', 'OK', 'OK'), cancel: L('ক্যান্সেল', 'Cancel', 'Cancel'), send: L('অনুরোধ পাঠান', 'Send request', 'Request পাঠান'),
  addgo: L('যোগ করুন', 'Add', 'Add'), simTitle: L('একই রকম আগে থেকেই আছে', 'A similar one already exists', 'একই রকম আগে থেকেই আছে'), use: L('এটাই নিন', 'Use this', 'এটাই নিন'), anyway: L('তবু নতুন যোগ করুন', 'Add anyway', 'তবু নতুন Add'),
  inactiveMark: L('(বন্ধ)', '(retired)', '(retired)'),
  added: L('তালিকায় যোগ হয়েছে', 'Added to the list', 'List-এ যোগ হয়েছে'), requested: L('অনুরোধ গেছে, মালিক দেখবেন। এর মধ্যে "অন্যান্য" ব্যবহার করুন।', 'Request sent for approval. Meanwhile use "Other".', 'Request গেছে, Owner দেখবেন। এর মধ্যে "Other" ব্যবহার করুন।'),
  exists: L('এটি আগে থেকেই আছে', 'It already exists', 'এটি আগে থেকেই আছে'), existsOff: L('এটি আছে কিন্তু বন্ধ করা — মালিককে জানান', 'It exists but is retired — ask the owner', 'এটি আছে কিন্তু retired — Owner-কে জানান'),
  ownerMsg: L('এই তালিকায় শুধু মালিক নতুন যোগ করতে পারেন। "অন্যান্য" লিখে রাখুন।', 'Only the owner adds to this list. Use "Other".', 'এই list-এ শুধু Owner নতুন Add করতে পারে। "Other" লিখুন।'),
  otherSaved: L('"অন্যান্য" তালিকায় জমা হয়েছে', 'Saved to the Other queue', '"Other" queue-তে জমা হয়েছে'), otherQueued: L('অফলাইন — পরে জমা হবে', 'Offline — will be sent later', 'Offline — পরে জমা হবে'),
  noOther: L('এই তালিকায় "অন্যান্য" বন্ধ', '"Other" is switched off for this list', 'এই list-এ "Other" বন্ধ'), locked: L('তালিকা লক', 'This list is locked', 'List locked'), inactive: L('তালিকা বন্ধ', 'This list is switched off', 'List বন্ধ'),
  queueFull: L('অনেক "অন্যান্য" লেখা অপেক্ষায় — মালিকের সিদ্ধান্ত পর্যন্ত নতুন নেওয়া যাবে না', 'Too many "Other" entries are waiting — wait for the owner to decide some', 'অনেক "Other" লেখা অপেক্ষায় — Owner-এর সিদ্ধান্ত পর্যন্ত নতুন নেওয়া যাবে না'),
  needName: L('নাম লিখুন', 'Enter a name', 'নাম লিখুন'), unavailable: L('এই সুবিধা এখনো চালু হয়নি (নতুন SQL লাগবে)', 'Not available yet (the new SQL must be run)', 'এখনো চালু হয়নি (নতুন SQL লাগবে)'),
};
const T = (k) => lab(X[k]);
const ERR = { owner_only: 'ownerMsg', other_not_allowed: 'noOther', list_locked: 'locked', list_inactive: 'inactive', name_required: 'needName', other_queue_full: 'queueFull' };
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const rowL = (r) => ({ bn: r.label_bn, mix: r.label_mix || undefined, en: r.label_en || undefined });
const rows = (code) => (B.ENV && B.ENV.lists && B.ENV.lists[code]) || [];

// ---------- list settings (list_defs) + who may manage ----------
const ST = { defs: null, loaded: false, missing: false, mgr: new Set(), allMgr: false, p: null, cfg: {}, others: {}, prev: new WeakMap() };
// only "the table / function does not exist" counts as missing (Postgres 42P01 / 42883, REST 404 / PGRST20x); a network error never does
function isMissing(e) {
  if (!e) return false; const m = String(e.message || e), c = String(e.code || '');
  if (/failed to fetch|network|timeout|load failed|fetch/i.test(m) && !/does not exist|could not find/i.test(m)) return false;
  return c === '42P01' || c === '42883' || c === 'PGRST202' || c === 'PGRST205' || e.status === 404 || /does not exist|could not find the (table|function)/i.test(m);
}
const isNet = (e) => !!e && !isMissing(e) && /failed to fetch|network|timeout|load failed|fetch|offline/i.test(String((e && e.message) || e));
function load(force) {
  if (ST.p && !force) return ST.p;
  ST.p = (async () => {
    try {
      const r = await sb.from('list_defs').select('*');
      if (!r || r.error) {
        if (isMissing(r && r.error)) { ST.missing = true; ST.defs = {}; ST.loaded = true; reconcile(); return; }
        ST.defs = ST.defs || {}; ST.p = null; return;                     // network trouble: not "missing"; try again later (online / next screen)
      }
      ST.missing = false; ST.defs = {}; (r.data || []).forEach((d) => { ST.defs[d.list_code] = d; });
      ST.allMgr = !!(S.ctx && S.ctx.is_owner);
      if (!ST.allMgr) {
        try { const g = await sb.rpc('has_grant', { p_code: 'list_manage' }); ST.allMgr = !!(g && !g.error && g.data === true); } catch (e) { /* not a manager */ }
        try { const m = await sb.from('list_managers').select('list_code,active'); ST.mgr = new Set(((m && m.data) || []).filter((x) => x.active !== false).map((x) => x.list_code)); } catch (e) { /* none */ }
      }
    } catch (e) { if (isMissing(e)) { ST.missing = true; ST.defs = {}; } else { ST.defs = ST.defs || {}; ST.p = null; return; } }
    ST.loaded = true;
    reconcile();
    flushOther();
  })();
  return ST.p;
}
const def = (code) => (ST.defs && ST.defs[code]) || { list_code: code, add_rule: 'approval', allow_other: true, active: true, locked: false, hidden: false };
const isMgr = (code) => ST.allMgr || ST.mgr.has(code);
// 'add' (adds at once), 'request' (owner decides), 'owner' (message only), 'none' (list locked / switched off)
function mode(code) {
  const d = def(code); if (d.locked || !d.active) return 'none';
  if (d.add_rule === 'open') return 'add';
  if (d.add_rule === 'owner') return isMgr(code) ? 'add' : 'owner';
  return S.ctx && S.ctx.is_owner && B.rule('owner_self_approve', true) !== false ? 'add' : 'request';
}
const available = () => !(ST.loaded && ST.missing);
const showOther = (code) => available() && def(code).allow_other !== false && def(code).active !== false;
const showAdd = (code) => available() && mode(code) !== 'none';
const addLabel = (code) => { const m = mode(code); return m === 'request' ? T('req') : m === 'owner' ? T('ownerOnly') : T('add'); };
function specials(code, cfg) {
  const out = [];
  if (showAdd(code) && !(cfg && cfg.noAdd)) out.push(['__add__:' + code, addLabel(code)]);
  if (showOther(code) && !(cfg && cfg.noOther)) out.push(['__other__:' + code, T('other')]);
  return out;
}

// the list settings arrive after a form was drawn: bring the special choices of every select on the screen in line with them
function reconcile() {
  try {
    document.querySelectorAll('select').forEach((sel) => {
      const sp = Array.from(sel.options).filter((o) => o.value.startsWith('__add__:') || o.value.startsWith('__other__:')); if (!sp.length) return;
      const code = sp[0].value.slice(sp[0].value.indexOf(':') + 1), cfg = (sel.dataset.lpid && ST.cfg[sel.dataset.lpid]) || {};
      sp.forEach((o) => o.remove());
      specials(code, cfg).forEach(([v, l]) => { const o = document.createElement('option'); o.value = v; o.textContent = l; sel.appendChild(o); });
    });
  } catch (e) { /* the screen is gone */ }
}

// ---------- Other write-ins that could not be sent (offline) stay on this phone and go later ----------
const OQ = 'bos_other_q';
const myId = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
function qGet() { try { const a = JSON.parse(localStorage.getItem(OQ) || '[]'); return Array.isArray(a) ? a : []; } catch (e) { return []; } }
function qSet(a) { try { localStorage.setItem(OQ, JSON.stringify(a)); } catch (e) { /* storage blocked */ } }
function qPush(it) { const q = qGet(); q.push(Object.assign({ qid: rid(), uid: myId() }, it)); qSet(q); }       // read-modify-write at the moment of writing
const qDrop = (ids) => qSet(qGet().filter((x) => !ids.has(x.qid)));                                           // remove only what was sent
let flushing = false;
async function flushOther() {
  if (flushing || ST.missing) return; flushing = true;
  try {
    const mine = qGet().filter((x) => x.uid === myId()), done = new Set();
    for (const it of mine) {
      try { const r = await sb.rpc('option_other_log', { p_list: it.list, p_text: it.text, p_ctx: it.ctx }); if (r && r.error) { if (isNet(r.error)) break; } done.add(it.qid); } catch (e) { break; }   // a business refusal is final: drop it, a network error: keep and stop
    }
    if (done.size) qDrop(done);
  } finally { flushing = false; }
}
window.addEventListener('online', () => { try { if (!ST.loaded || !ST.defs || ST.p === null) load(true); flushOther(); } catch (e) { /* later */ } });

// ---------- option lists as [[value, label]] ----------
function activePairs(code, fallback) {
  const rs = rows(code);
  return rs.length ? rs.filter((r) => r.active).map((r) => [r.value_code, rowL(r)]) : (fallback || []);
}
const sessionOthers = (code) => (ST.others[code] || []).map((tx) => ['other:' + tx, { bn: 'অন্যান্য: ' + tx, en: 'Other: ' + tx }]);
// for entry.js SEL fields: a function, evaluated at each draw
function opts(code, fallback) {
  return () => {
    if (!ST.p && S.ctx) load();
    const base = activePairs(code, fallback);
    return [...base, ...sessionOthers(code), ...specials(code)];
  };
}
function pairs(code, list, cfg) { if (!ST.p && S.ctx) load(); return [...(list || []), ...specials(code, cfg)]; }
const optHTML = (v, l, cur, extra) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''} ${extra || ''}>${esc(typeof l === 'string' ? l : lab(l))}</option>`;

// ---------- inline panels (a sheet may already be open, so nothing here opens another sheet) ----------
const anchorOf = (sel) => (sel.closest && sel.closest('.p2-inl')) || sel;
function panelFor(sel) {
  const an = anchorOf(sel), key = sel.id || '';
  let p = an.parentNode.querySelector(':scope > .lp-pn[data-for="' + key + '"]');
  if (!p || !key) { if (p) p.remove(); p = document.createElement('div'); p.className = 'lp-pn'; p.dataset.for = key; p.style.cssText = 'margin-top:6px'; an.insertAdjacentElement('afterend', p); }
  return p;
}
const closePanel = (sel) => { const an = anchorOf(sel), p = an.parentNode && an.parentNode.querySelector(':scope > .lp-pn[data-for="' + (sel.id || '') + '"]'); if (p) p.remove(); };
function restore(sel) { const v = ST.prev.get(sel); sel.value = v === undefined ? '' : v; if (sel.value !== (v === undefined ? '' : v)) sel.value = ''; }
function setValue(sel, v, label, info) {
  if (v && !Array.from(sel.options).some((o) => o.value === v)) {
    const o = document.createElement('option'); o.value = v; o.textContent = label || v; const first = Array.from(sel.options).find((x) => x.value.startsWith('__'));
    sel.insertBefore(o, first || null);
  }
  sel.value = v; ST.prev.set(sel, v); sel.dataset.lpOther = info && info.other ? info.other : '';
  const ev = new Event('change', { bubbles: true }); ev.__lp = true; sel.dispatchEvent(ev);
  const c = sel.dataset.lpid && ST.cfg[sel.dataset.lpid]; if (c && c.onChange) c.onChange(v, info || {});
}
const msgOf = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? T(ERR[k]) : null; };

async function openAdd(sel, code, cfg) {
  await load();
  if (!available()) { restore(sel); return toast(T('unavailable')); }
  const m = mode(code);
  if (m === 'none') { restore(sel); return toast(def(code).locked ? T('locked') : T('inactive')); }
  if (m === 'owner') { restore(sel); return toast(T('ownerMsg')); }
  restore(sel);
  const p = panelFor(sel), id = 'lp' + rid().slice(0, 8);
  const draw = (sim) => {
    p.innerHTML = `<div class="card stack" style="padding:10px"><div><label>${esc(T('nBn'))}</label><input id="${id}_bn" autocomplete="off" value="${esc(p.dataset.bn || '')}"></div>
      <div><label>${esc(T('nEn'))}</label><input id="${id}_en" autocomplete="off" value="${esc(p.dataset.en || '')}"></div>
      ${sim && sim.length ? `<div class="notice bad"><b>${esc(T('simTitle'))}</b>${sim.map((s) => `<div class="row between" style="margin-top:6px"><span>${esc(lab({ bn: s.label_bn, en: s.label_en || s.label_bn }))}${s.active ? '' : ' ' + esc(T('inactiveMark'))}</span>${s.active ? `<button type="button" class="mini" data-lp-use="${esc(s.value_code)}">${esc(T('use'))}</button>` : ''}</div>`).join('')}
        <button type="button" class="full" style="margin-top:8px" data-lp-force="1">${esc(T('anyway'))}</button></div>` : ''}
      <div class="row"><button type="button" class="full" data-lp-cancel="1">${esc(T('cancel'))}</button><button type="button" class="primary full" data-lp-go="1">${esc(m === 'request' ? T('send') : T('addgo'))}</button></div></div>`;
    const go = async (force) => {
      const bn = ($('#' + id + '_bn', p).value || '').trim(), en = ($('#' + id + '_en', p).value || '').trim(); p.dataset.bn = bn; p.dataset.en = en;
      if (!bn) return toast(T('needName'));
      let r; try { r = await sb.rpc('option_add', { p_list: code, p_bn: bn, p_en: en || null, p_mix: null, p_extra: {}, p_force: !!force, p_client: p.dataset.client || (p.dataset.client = rid()) }); } catch (e) { return fail(e); }
      if (r.error) { const mm = msgOf(r.error); return mm ? toast(mm) : fail(r.error); }
      const d = r.data || {};
      if (d.status === 'similar') return draw(d.similar || []);
      if (d.status === 'exists') { await B.reloadLists(); const o = rows(code).find((x) => x.value_code === d.value_code); if (o && !o.active) { toast(T('existsOff')); return closePanel(sel); } toast(T('exists')); closePanel(sel); return setValue(sel, d.value_code, o ? lab(rowL(o)) : d.value_code, { existing: true }); }
      if (d.status === 'added') { await B.reloadLists(); toast(T('added')); closePanel(sel); return setValue(sel, d.value_code, bn, { added: true }); }
      if (d.status === 'requested') { toast(T('requested')); closePanel(sel); }
    };
    p.onclick = (e) => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.lpCancel) closePanel(sel); else if (b.dataset.lpGo) go(false); else if (b.dataset.lpForce) go(true);
      else if (b.dataset.lpUse) { closePanel(sel); setValue(sel, b.dataset.lpUse, null, { existing: true }); }
    };
  };
  draw();
}
async function openOther(sel, code, cfg) {
  await load();
  if (!available()) { restore(sel); return toast(T('unavailable')); }
  if (!showOther(code)) { restore(sel); return toast(T('noOther')); }
  restore(sel);
  const p = panelFor(sel), id = 'lo' + rid().slice(0, 8);
  p.innerHTML = `<div class="card stack" style="padding:10px"><div><label>${esc(T('other').replace('…', ''))}</label><input id="${id}" autocomplete="off" placeholder="${esc(T('otherPh'))}" maxlength="200"></div>
    <div class="row"><button type="button" class="full" data-lp-cancel="1">${esc(T('cancel'))}</button><button type="button" class="primary full" data-lp-ok="1">${esc(T('ok'))}</button></div></div>`;
  const input = $('#' + id, p); if (input) { try { input.focus(); } catch (e) { /* no focus */ } }
  let client = rid();
  p.onclick = async (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.lpCancel) return closePanel(sel);
    if (!b.dataset.lpOk) return;
    const tx = (input.value || '').trim(); if (!tx) return toast(T('needName'));
    const cx = cfg && cfg.ctx ? (typeof cfg.ctx === 'function' ? cfg.ctx(sel) : cfg.ctx) : {};
    const ctx = Object.assign({ client_id: client }, cx || {}, sel.dataset.lpform ? { form_code: sel.dataset.lpform } : {});
    let note = T('otherSaved'), existing = null;
    try {
      const r = await sb.rpc('option_other_log', { p_list: code, p_text: tx, p_ctx: ctx });
      if (r.error) { if (isNet(r.error)) { qPush({ list: code, text: tx, ctx }); note = T('otherQueued'); } else { const mm = msgOf(r.error); return mm ? toast(mm) : fail(r.error); } }
      else if (r.data && r.data.status === 'exists') existing = r.data.value_code;
    } catch (er) { qPush({ list: code, text: tx, ctx }); note = T('otherQueued'); }
    closePanel(sel);
    if (existing) { toast(T('exists')); return setValue(sel, existing, null, { existing: true }); }
    toast(note);
    (ST.others[code] = ST.others[code] || []).push(tx);
    const c = cfg || {};
    if (c.keepPrev) { const pv = ST.prev.get(sel); return setValue(sel, pv === undefined ? '' : pv, null, { other: tx }); }          // the old value stays; the words travel in the screen's own note
    if (c.otherValue !== undefined && c.otherValue !== null) return setValue(sel, c.otherValue, null, { other: tx });
    if (c.otherBlank) return setValue(sel, '', null, { other: tx });
    setValue(sel, 'other:' + tx, lab({ bn: 'অন্যান্য: ' + tx, en: 'Other: ' + tx }), { other: tx });
  };
}

// ---------- one capturing listener for every select ----------
document.addEventListener('change', (e) => {
  const sel = e.target; if (!sel || sel.tagName !== 'SELECT' || e.__lp) return;
  const v = sel.value || '';
  if (v.startsWith('__add__:') || v.startsWith('__other__:')) {
    e.stopImmediatePropagation(); e.stopPropagation();
    const isAdd = v.startsWith('__add__:'), code = v.slice(v.indexOf(':') + 1), cfg = (sel.dataset.lpid && ST.cfg[sel.dataset.lpid]) || {};
    if (isAdd) openAdd(sel, code, cfg); else openOther(sel, code, cfg);
    return;
  }
  ST.prev.set(sel, v);
  if (sel.dataset.lpid) { const c = ST.cfg[sel.dataset.lpid]; sel.dataset.lpOther = ''; if (c && c.onChange) c.onChange(v, {}); }
}, true);
// remember the value a select started with (so Cancel can put it back)
document.addEventListener('focusin', (e) => { const s = e.target; if (s && s.tagName === 'SELECT' && !ST.prev.has(s) && !(s.value || '').startsWith('__')) ST.prev.set(s, s.value); }, true);
document.addEventListener('input', (e) => {
  const q = e.target; if (!q || !q.classList || !q.classList.contains('lp-q')) return;
  const sel = document.getElementById(q.dataset.lpq); if (!sel) return; fillSelect(sel, q.value);
});

// ---------- B.listPick: the full control ----------
function buildOptions(code, cur, query, o) {
  const rs = rows(code), qq = String(query || '').trim().toLowerCase();
  let list = rs.length ? rs.filter((r) => r.active).map((r) => [r.value_code, rowL(r)]) : ((o && o.fallback) || []);
  if (qq) list = list.filter(([v, l]) => (typeof l === 'string' ? l : [l.bn, l.en, l.mix].filter(Boolean).join(' ')).toLowerCase().includes(qq) || String(v).toLowerCase().includes(qq));
  let html = `<option value=""></option>` + list.map(([v, l]) => optHTML(v, l, cur)).join('');
  if (cur && !list.some(([v]) => v === cur)) {
    const old = rs.find((r) => r.value_code === cur);
    if (old) html += `<option value="${esc(cur)}" selected disabled>${esc(lab(rowL(old)))} ${esc(old.active ? '' : T('inactiveMark'))}</option>`;
    else if (String(cur).startsWith('other:')) html += `<option value="${esc(cur)}" selected>${esc(lab({ bn: 'অন্যান্য: ' + cur.slice(6), en: 'Other: ' + cur.slice(6) }))}</option>`;
    else if (!qq) html += `<option value="${esc(cur)}" selected>${esc(cur)}</option>`;
  }
  html += (ST.others[code] || []).map((tx) => optHTML('other:' + tx, { bn: 'অন্যান্য: ' + tx, en: 'Other: ' + tx }, cur)).join('');
  html += specials(code, o).map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join('');
  return html;
}
function fillSelect(sel, query) {
  const cfg = ST.cfg[sel.dataset.lpid] || {}, cur = sel.value && !sel.value.startsWith('__') ? sel.value : (ST.prev.get(sel) || '');
  sel.innerHTML = buildOptions(sel.dataset.lcode, cur, query, cfg); if (!query) sel.value = cur;
}
function listPick(code, o) {
  o = o || {}; if (!ST.p && S.ctx) load();
  const id = o.id || 'lp_' + code + '_' + rid().slice(0, 6), n = rows(code).filter((r) => r.active).length || (o.fallback || []).length;
  ST.cfg[id] = o;
  const withSearch = n > Number(B.rule('list_search_min', 8));
  const html = `<div class="lp ${esc(o.cls || '')}">${withSearch ? `<input class="lp-q" data-lpq="${esc(id)}" placeholder="${esc(T('search'))}" autocomplete="off" style="margin-bottom:6px">` : ''}
    <select id="${esc(id)}" class="lp-sel" data-lpid="${esc(id)}" data-lcode="${esc(code)}" ${o.attrs || ''}>${buildOptions(code, o.cur || '', '', o)}</select></div>`;
  if (o.cur) setTimeout(() => { const s = document.getElementById(id); if (s) ST.prev.set(s, o.cur); }, 0);
  return { id, html, value: () => { const s = document.getElementById(id); return s ? s.value : ''; }, other: () => { const s = document.getElementById(id); return s ? s.dataset.lpOther || '' : ''; },
    set: (v) => { const s = document.getElementById(id); if (s) { s.value = v; ST.prev.set(s, v); } } };
}
// a screen that already drew its own <select>
function enhance(target, code, cfg) {
  const sel = typeof target === 'string' ? $(target) : target; if (!sel) return null;
  if (!ST.p && S.ctx) load();
  cfg = cfg || {}; const id = sel.id || ('lpe_' + rid().slice(0, 6)); if (!sel.id) sel.id = id;
  sel.dataset.lpid = id; sel.dataset.lcode = code; ST.cfg[id] = cfg; ST.prev.set(sel, sel.value);
  if (cfg.form) sel.dataset.lpform = cfg.form;
  Array.from(sel.querySelectorAll('option[value^="__"]')).forEach((o) => o.remove());
  specials(code, cfg).forEach(([v, l]) => { const o = document.createElement('option'); o.value = v; o.textContent = l; sel.appendChild(o); });
  // the lists may load after the screen was drawn: add the choices again when they are ready
  if (!ST.loaded) load().then(() => { if (document.body.contains(sel)) { Array.from(sel.querySelectorAll('option[value^="__"]')).forEach((o) => o.remove()); specials(code, cfg).forEach(([v, l]) => { const o = document.createElement('option'); o.value = v; o.textContent = l; sel.appendChild(o); }); } });
  return sel;
}

B.listctl = { reconcile, load, def, mode, isMgr, opts, pairs, enhance, specials, state: ST, available, reloadDefs: () => { ST.p = null; return load(true); }, flush: flushOther, T, X };
B.listPick = listPick;
// start loading the list settings as soon as somebody is signed in
let tries = 0; const kick = () => { if (S.ctx) load(); else if (tries++ < 60) setTimeout(kick, 1000); };
setTimeout(kick, 300);
window.addEventListener('hashchange', () => { if (S.ctx && !ST.p) load(); });
})();
