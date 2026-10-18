/* Islamia BOS · Business Memory hub: the question parser (pure functions, no DOM, no network, NO AI call).
   A person types a sentence in Bengali or English ("how much was paid for one staff member's meals in the last year", "গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত").
   The parser looks the words up in the word lists of web/data/report_registry.json (parser section) and returns WHAT it understood as separate slots:
   person · what (head) · place · period · kinds · measure.  The screen shows every slot as an editable chip, so a wrong guess is visible and one tap away from fixed.
   Rules: a slot is filled only from words that are really in the sentence; an unknown word is never "fixed" into a known one; two possible readings are returned
   as an ambiguity, not as a pick; a missing period is returned as missing (it is NEVER defaulted); the parser never produces a number - only filters.
   Loaded in the browser as window.BOS.parse and in node (module.exports) for the tests. */
(function (root) {
'use strict';

const BN_DIGITS = '০১২৩৪৫৬৭৮৯';
const pad = (n) => String(n).padStart(2, '0');
const iso = (d) => d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1) + '-' + pad(d.getUTCDate());
const parseISO = (s) => new Date(s + 'T12:00:00Z');
const addDays = (s, n) => { const d = parseISO(s); d.setUTCDate(d.getUTCDate() + n); return iso(d); };
const addMonths = (s, n) => { const d = parseISO(s); const day = d.getUTCDate(); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() + n); const last = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0, 12)).getUTCDate(); d.setUTCDate(Math.min(day, last)); return iso(d); };
const monthStart = (s) => s.slice(0, 8) + '01';
const monthEnd = (s) => { const d = parseISO(monthStart(s)); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0); return iso(d); };
const weekStart = (s, ws) => { const d = parseISO(s); const back = (d.getUTCDay() - ws + 7) % 7; d.setUTCDate(d.getUTCDate() - back); return iso(d); };

function normalize(text) {
  let t = String(text == null ? '' : text).normalize('NFC').toLowerCase();
  t = t.replace(/[০-৯]/g, (c) => String(BN_DIGITS.indexOf(c)));
  t = t.replace(/[’‘`´]/g, "'").replace(/'s\b/g, ' ').replace(/'/g, ' ');
  t = t.replace(/[।?!,;:()"“”\[\]{}]/g, ' ').replace(/(?<!\d)\.(?!\d)/g, ' ');
  return t.replace(/\s+/g, ' ').trim();
}
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const isBn = (s) => /[ঀ-৿]/.test(s);
// does the phrase occur in the (normalised) text?  English: on word edges, with an optional plural s.  Bengali: anywhere (suffixes such as "-এর", "-ে" are attached to the word).
function has(n, phrase) {
  const p = phrase.toLowerCase().trim();
  if (!p) return false;
  if (isBn(p)) return n.includes(p);
  return new RegExp('(^|[^a-z0-9])' + esc(p) + '(s|es)?($|[^a-z0-9])').test(n);
}
function find(n, list) { return (list || []).filter((p) => has(n, p)); }
const num = (s, words, lang) => { if (/^\d+$/.test(s)) return parseInt(s, 10); const w = (words[lang] || {})[s]; return w || null; };

// ---------- period ----------
// Every phrase found is returned, left to right (a compare question names two). Matched text is blanked so "last month" is not read inside "last 8 months".
function periodFrom(n, ctx, P) {
  const today = ctx.today, ws = ctx.weekStart == null ? 6 : ctx.weekStart, W = P.num_words, names = P.months;
  let s = ' ' + n + ' '; const found = [];
  const lab = (en, bn, from, to, extra) => Object.assign({ from, to, label_en: en, label_bn: bn }, extra || {});
  const take = (re, build) => { s = s.replace(re, function () { const a = Array.prototype.slice.call(arguments); const offset = a[a.length - 2]; const p = build(a); if (p) found.push({ idx: offset, p }); return ' '.repeat(a[0].length); }); };
  const unitMap = { day: 'day', days: 'day', week: 'week', weeks: 'week', month: 'month', months: 'month', year: 'year', years: 'year', 'দিন': 'day', 'সপ্তাহ': 'week', 'মাস': 'month', 'বছর': 'year' };
  // dates
  take(/(\d{4}-\d{2}-\d{2})\s*(?:to|until|till|-|–|থেকে)\s*(\d{4}-\d{2}-\d{2})/g, (a) => { const x = a[1] <= a[2] ? a[1] : a[2], y = a[1] <= a[2] ? a[2] : a[1]; return lab(x + ' to ' + y, x + ' থেকে ' + y, x, y, { kind: 'dates' }); });
  take(/(?:since|from|after)\s+(\d{4}-\d{2}-\d{2})/g, (a) => lab('since ' + a[1], a[1] + ' থেকে', a[1], today, { kind: 'since' }));
  take(/(\d{4}-\d{2}-\d{2})\s*থেকে/g, (a) => lab('since ' + a[1], a[1] + ' থেকে', a[1], today, { kind: 'since' }));
  take(/(\d{4}-\d{2}-\d{2})/g, (a) => lab(a[1], a[1], a[1], a[1], { kind: 'day', day: true }));
  // last N units
  take(/(?:last|past|previous|prev)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an)\s+(days?|weeks?|months?|years?)/g, (a) => { const k = num(a[1], W, 'en'); return k ? Object.assign(rolling(k, unitMap[a[2]], today), { kind: 'rolling', n: k, unit: unitMap[a[2]] }) : null; });
  take(/(?:গত|শেষ|বিগত|পূর্বের)\s*(\d+|এক|দুই|দু|তিন|চার|পাঁচ|ছয়|ছ|সাত|আট|নয়|দশ|এগারো|বারো)\s*(দিন|সপ্তাহ|মাস|বছর)/g, (a) => { const k = num(a[1], W, 'bn'); return k ? Object.assign(rolling(k, unitMap[a[2]], today), { kind: 'rolling', n: k, unit: unitMap[a[2]] }) : null; });
  take(/(?:^|[^a-z])past\s+(day|week|month|year)(?=$|[^a-z])/g, (a) => Object.assign(rolling(1, a[1], today), { kind: 'rolling', n: 1, unit: a[1] }));
  // fiscal year
  take(/(?:(last|previous|prev)\s+)?(?:fiscal|financial)\s+year|(গত\s*)?অর্থ\s*বছর/g, (a) => {
    const fm = ctx.fiscalStartMonth;
    if (!fm) return { kind: 'fiscal', from: null, to: null, needs_setting: true, label_en: 'fiscal year (start month is not set in Rules)', label_bn: 'অর্থবছর (শুরুর মাস নিয়মে বসানো নেই)' };
    const y = parseInt(today.slice(0, 4), 10), mo = parseInt(today.slice(5, 7), 10), start = (mo >= fm ? y : y - 1) + '-' + pad(fm) + '-01';
    if (a[1] || a[2]) { const s2 = addMonths(start, -12); return lab('last fiscal year', 'গত অর্থবছর', s2, addDays(start, -1), { kind: 'fiscal' }); }
    return lab('this fiscal year', 'এই অর্থবছর', start, today, { kind: 'fiscal' });
  });
  const ms = monthStart(today);
  take(/(?:this|current)\s+month|(?:এই|চলতি)\s*মাস/g, () => lab('this month', 'এই মাস', ms, today, { kind: 'month' }));
  take(/(?:last|previous|prev)\s+month|(?:গত|বিগত)\s*মাস/g, () => { const lm = addMonths(ms, -1); return lab('last month', 'গত মাস', lm, monthEnd(lm), { kind: 'month' }); });
  take(/(?:this|current)\s+year|(?:এই|চলতি)\s*বছর/g, () => lab('this year', 'এই বছর', today.slice(0, 4) + '-01-01', today, { kind: 'year' }));
  take(/(?:last|previous|prev)\s+year|(?:গত|বিগত)\s*বছর/g, () => { const y = String(parseInt(today.slice(0, 4), 10) - 1); return lab('last year', 'গত বছর', y + '-01-01', y + '-12-31', { kind: 'year' }); });
  take(/(?:this|current)\s+week|(?:এই|চলতি)\s*সপ্তাহ/g, () => lab('this week', 'এই সপ্তাহ', weekStart(today, ws), today, { kind: 'week' }));
  take(/(?:last|previous|prev)\s+week|(?:গত|বিগত)\s*সপ্তাহ/g, () => { const w0 = addDays(weekStart(today, ws), -7); return lab('last week', 'গত সপ্তাহ', w0, addDays(w0, 6), { kind: 'week' }); });
  take(/(^|[^a-z])yesterday($|[^a-z])|গতকাল/g, () => lab('yesterday', 'গতকাল', addDays(today, -1), addDays(today, -1), { kind: 'day', day: true }));
  take(/(^|[^a-z])today($|[^a-z])|আজ/g, () => lab('today', 'আজ', today, today, { kind: 'day', day: true }));
  // a month name, optionally with a year: "in october", "october 2025", "অক্টোবর মাসে", "অক্টোবরে"
  for (let i = 0; i < 12; i++) {
    const alts = [names.en[i]].concat(names.en[i] === 'may' ? [] : [names.en_short[i]]).map((x) => '(?:^|[^a-z])' + x + '(?:\\s+(20\\d{2}))?(?=$|[^a-z])').concat([names.bn[i] + '(?:\\s*(20\\d{2}))?']);
    if (names.bn[i] === 'মে') alts[alts.length - 1] = '(?:^|\\s)মে(?=$|\\s|র|তে|য়)(?:\\s*(20\\d{2}))?';
    if (names.en[i] === 'may') alts[0] = '(?:in|of|during)\\s+may(?:\\s+(20\\d{2}))?(?=$|[^a-z])|(?:^|[^a-z])may\\s+(20\\d{2})(?=$|[^a-z])';
    for (const re of alts) {
      take(new RegExp(re, 'g'), (a) => {
        const cy = parseInt(today.slice(0, 4), 10), cm = parseInt(today.slice(5, 7), 10), yy = a[1] ? parseInt(a[1], 10) : (i + 1 <= cm ? cy : cy - 1), st = yy + '-' + pad(i + 1) + '-01';
        return lab(names.en[i] + ' ' + yy, names.bn[i] + ' ' + yy, st, monthEnd(st), { kind: 'month_name' });
      });
    }
  }
  found.sort((x, y) => x.idx - y.idx);
  return found.map((f) => f.p);
}
function rolling(k, unit, today, lang) {
  const to = today; let from;
  if (unit === 'day') from = addDays(today, -(k - 1));
  else if (unit === 'week') from = addDays(today, -(7 * k - 1));
  else if (unit === 'month') from = addDays(addMonths(today, -k), 1);
  else from = addDays(addMonths(today, -12 * k), 1);
  const en = 'last ' + k + ' ' + unit + (k > 1 ? 's' : ''), bnUnit = { day: 'দিন', week: 'সপ্তাহ', month: 'মাস', year: 'বছর' }[unit];
  return { from, to, label_en: en, label_bn: 'গত ' + k + ' ' + bnUnit };
}

// ---------- heads, kinds ----------
function headsFrom(n, P) {
  const hits = [];
  for (const h of P.heads) {
    const words = find(n, h.en).concat(find(n, h.bn));
    if (words.length) hits.push({ h, words });
  }
  if (!hits.length) return { head: null, options: [] };
  // two heads that share an ambiguous word (a Bengali "ভাড়া" is rent or fare) are decided only by a word that belongs to one of them
  const partner = (x, y) => x !== y && x.h.ambiguous_with === y.h.key && y.h.ambiguous_with === x.h.key;
  const onlyShared = (x) => hits.some((y) => partner(x, y) && x.words.every((w) => y.words.includes(w)));
  const decided = hits.filter((x) => !onlyShared(x));
  const sharedKept = hits.filter((x) => onlyShared(x) && !decided.some((d) => partner(x, d)));
  const all = decided.concat(sharedKept);
  const distinct = [...new Set(all.map((x) => x.h.key))];
  if (distinct.length === 1) return { head: all[0], options: [] };
  return { head: null, options: all };
}

function kindsFrom(n, P) {
  const k = []; const words = [];
  for (const e of P.kinds) { const w = find(n, e.en).concat(find(n, e.bn)); if (w.length) { k.push(e); words.push(...w); } }
  return { kinds: k, words };
}

// ---------- place ----------
function placeFrom(n, ctx, P) {
  const locs = (ctx.locations || []).filter((l) => l && l.id != null);
  if (!locs.length) return { place: null, options: [], words: [] };
  const words = [], hits = new Map();
  const tokens = n.split(' ');
  const brand = new Map(); locs.forEach((l) => nameWords(l).forEach((w) => brand.set(w, (brand.get(w) || 0) + 1)));
  const common = new Set([...brand.entries()].filter(([, c]) => c >= Math.max(2, Math.ceil(locs.length / 2))).map(([w]) => w));
  const addHit = (l, why) => { hits.set(l.id, (hits.get(l.id) || []).concat([why])); };
  for (const l of locs) {
    const code = String(l.code || '').toLowerCase();
    if (code && code.length >= 3 && (has(n, code) || has(n, code.replace(/_/g, ' ')))) { addHit(l, code); words.push(code); }
    for (const w of nameWords(l)) {
      if (common.has(w) || w.length < 3) continue;
      if (has(n, w)) { addHit(l, w); words.push(w); }
    }
    const bn = String(l.name_bn || '').toLowerCase();
    for (const w of bn.split(/[\s—\-–()]+/).filter((x) => x.length >= 3 && isBn(x))) {
      if ([...locs].filter((o) => String(o.name_bn || '').includes(w)).length >= Math.max(2, Math.ceil(locs.length / 2))) continue;
      if (n.includes(w)) { addHit(l, w); words.push(w); }
    }
  }
  // "2nd branch", "branch 2", "শাখা ২", "২য় শাখা", "দ্বিতীয় শাখা"
  const ordEn = n.match(/(\d)(?:st|nd|rd|th)\s+(?:branch|outlet|shop)|(?:branch|outlet|shop)\s*(?:no\.?\s*)?(\d)\b/);
  let ordN = ordEn ? parseInt(ordEn[1] || ordEn[2], 10) : 0;
  if (!ordN) { const eb = n.match(/(\d)\s*(?:য়|র্থ|য়ের|নং)?\s*শাখা|শাখা\s*(?:নং\s*)?(\d)\b/); if (eb) ordN = parseInt(eb[1] || eb[2], 10); }
  if (!ordN) for (const w of Object.keys(P.ordinals.bn)) if (n.includes(w + ' শাখা') || n.includes(w + ' ব্রাঞ্চ')) ordN = P.ordinals.bn[w];
  if (!ordN) for (const w of Object.keys(P.ordinals.en)) if (has(n, w + ' branch')) ordN = P.ordinals.en[w];
  if (ordN) { const l = locs.find((x) => new RegExp('branch\\s*_?' + ordN + '$', 'i').test(String(x.code || ''))); if (l) { addHit(l, 'branch' + ordN); words.push('branch', String(ordN)); } }
  if (/(^|\s)main(\s|$)/.test(n) || n.includes('মেইন') || n.includes('মূল শাখা') || n.includes('প্রধান')) { const l = locs.find((x) => String(x.code || '') === 'main'); if (l) { addHit(l, 'main'); words.push('main'); } }
  if (hits.size === 1) return { place: locs.find((l) => hits.has(l.id)), options: [], words };
  if (hits.size > 1) {
    // several places named: the one that matched the most distinct words wins only when it is clearly ahead, else it is an ambiguity
    const sc = [...hits.entries()].map(([id, w]) => [id, new Set(w).size]).sort((a, b) => b[1] - a[1]);
    if (sc[0][1] > sc[1][1] + 0 && sc[0][1] >= 2) return { place: locs.find((l) => l.id === sc[0][0]), options: [], words };
    return { place: null, options: locs.filter((l) => hits.has(l.id)), words };
  }
  // generic words: factory / godown / branch -> by kind
  for (const [kind, w] of Object.entries(P.place_words)) {
    if (find(n, w.en).length || find(n, w.bn).length) {
      words.push(...find(n, w.en), ...find(n, w.bn));
      if (kind === 'branch') continue;           // "shop" alone names no place
      const ofKind = locs.filter((l) => String(l.kind || '') === kind);
      if (ofKind.length === 1) return { place: ofKind[0], options: [], words };
      if (ofKind.length > 1) return { place: null, options: ofKind, words };
    }
  }
  return { place: null, options: [], words };
}
function nameWords(l) { return String(l.name_en || '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(' ').filter((w) => w.length >= 3 && !['the', 'and', 'below', 'residence', 'closed', 'machines', 'stored', 'lane', 'beside', 'branch', 'factory', 'showroom', 'godown', 'shop', 'outlet', 'store'].includes(w)); }

// ---------- person ----------
const BN_SUFFIX = ['দের', 'ের', 'কে', 'র', 'ে'];
function personFrom(n, used, P, kindsHit, head) {
  let kind = null; const kw = [];
  for (const [k, w] of Object.entries(P.person_words)) { const f = find(n, w.en).concat(find(n, w.bn)); if (f.length) { kw.push(...f); if (!kind) kind = k; } }
  const stop = new Set((P.stopwords.en || []).concat(P.stopwords.bn || []));
  const usedWords = [...new Set(used.concat(kw).filter(Boolean))];
  const stopTok = (t) => stop.has(t) || (isBn(t) && BN_SUFFIX.some((sf) => t.endsWith(sf) && t.length - sf.length >= 2 && stop.has(t.slice(0, -sf.length))));
  const usedTok = (t) => usedWords.some((u) => {
    if (t === u) return true;
    if (isBn(u)) { if (u.length <= 2) return t.length <= u.length + 2 && t.startsWith(u) && isBn(t); return t.includes(u) || (t.length >= 3 && u.includes(t)); }
    return false;
  });
  const toks = n.split(' ').filter((t) => t && !/^\d+$/.test(t) && !/^\d{4}-\d{2}-\d{2}$/.test(t) && t.length >= 2);
  const clean = toks.filter((t) => !stopTok(t) && !usedTok(t));
  if (!clean.length) return { person: null, words: kw };
  const q = clean.join(' ');
  const alts = [q];
  if (clean.length === 1 && isBn(q)) for (const sf of BN_SUFFIX) if (q.endsWith(sf) && q.length - sf.length >= 2) { alts.push(q.slice(0, -sf.length)); break; }
  let guess = kind;
  if (!guess) {
    if (head && head.h.sensitive) guess = 'staff';
    else if (kindsHit.some((e) => e.sensitive)) guess = 'staff';
    else if (kindsHit.some((e) => e.key === 'purchase' || e.key === 'supplier_payment')) guess = 'supplier';
    else if (kindsHit.some((e) => e.key === 'refund')) guess = 'customer';
  }
  return { person: { kind: guess || 'auto', query: q, alts, has_word: !!kind }, words: kw };
}

// ---------- reports ----------
function scoreReports(n, registry, hints) {
  const toks = n.split(' ').filter((t) => t.length >= 2);
  const out = [];
  for (const r of registry.reports || []) {
    let s = 0;
    const nameT = [r.name.en, r.name.bn, r.name.mix].join(' ').toLowerCase(), qT = [r.question.en, r.question.bn].join(' ').toLowerCase();
    for (const t of toks) {
      if (nameT.includes(t)) s += 3; else if (qT.includes(t)) s += 1.5;
      if ((r.kw || []).some((k) => k.toLowerCase() === t || (isBn(k) && t.includes(k.toLowerCase())) || (k.length > 3 && k.toLowerCase().includes(t) && t.length > 3))) s += 3;
    }
    for (const h of hints || []) if ((h.reports || []).includes(r.no) && (find(n, h.en).length || find(n, h.bn).length)) s += 4;
    if (s > 0) out.push({ no: r.no, id: r.id, score: s, status: r.status });
  }
  out.sort((a, b) => b.score - a.score || (a.status === 'implemented' ? -1 : 1) - (b.status === 'implemented' ? -1 : 1) || a.no - b.no);
  return out.slice(0, 6);
}

// ---------- main ----------
function parse(text, ctx) {
  ctx = ctx || {};
  const registry = ctx.registry || { parser: {}, reports: [] };
  const P = registry.parser;
  const n = normalize(text);
  const res = { text: String(text || ''), norm: n, slots: {}, intent: 'unknown', ambiguities: [], missing: [], notes: [], understood: [], reports: [], ready: false };
  if (!n) { res.missing = ['text']; return res; }
  if (!P || !P.heads) { res.notes.push('no_word_lists'); return res; }
  const periods = periodFrom(n, ctx, P);
  const hd = headsFrom(n, P);
  const kd = kindsFrom(n, P);
  const pl = placeFrom(n, ctx, P);
  const measure = (() => { for (const k of ['happened', 'compare', 'count', 'list', 'total']) { const w = P.measures[k]; if (find(n, w.en).length || find(n, w.bn).length) return k; } return 'total'; })();
  const usedWords = [];
  [hd.head ? hd.head.words : hd.options.flatMap((o) => o.words), kd.words, pl.words].forEach((a) => usedWords.push(...a));
  periods.forEach((p) => { usedWords.push(...String(p.label_en).split(' '), ...String(p.label_bn).split(' ')); });
  for (const k of Object.keys(P.period_words)) { usedWords.push(...P.period_words[k].en, ...P.period_words[k].bn); }
  for (const k of Object.keys(P.measures)) { const w = P.measures[k]; usedWords.push(...w.en, ...w.bn); }
  usedWords.push(...P.months.en, ...P.months.en_short, ...P.months.bn.filter((m) => m.length >= 3));
  for (const w of Object.values(P.place_words)) usedWords.push(...w.en, ...w.bn);
  for (const w of Object.values(P.person_words)) usedWords.push(...w.en, ...w.bn);
  for (const a of Object.values(P.num_words)) usedWords.push(...Object.keys(a));
  const pr = personFrom(n, usedWords.filter(Boolean).flatMap((w) => String(w).split(' ')).filter(Boolean), P, kd.kinds, hd.head);
  // a person word with no name left ("staff meals last year") is just the head, never a person
  const person = pr.person;

  res.slots.period = periods[0] || null;
  if (periods.length > 1) { res.slots.period2 = periods[1]; }
  res.slots.head = hd.head ? { key: hd.head.h.key, label: hd.head.h.label, heads: hd.head.h.heads, utility: hd.head.h.utility || [], terms: termsOf(hd.head.h), sensitive: !!hd.head.h.sensitive, words: hd.head.words } : null;
  res.slots.place = pl.place ? { id: pl.place.id, label: { bn: pl.place.name_bn, en: pl.place.name_en, code: pl.place.code } } : null;
  res.slots.person = person;
  res.slots.kinds = kd.kinds.map((e) => e.key);
  res.slots.kind_list = [...new Set(kd.kinds.flatMap((e) => e.kinds))];
  res.slots.measure = measure;
  if (hd.options.length > 1) res.ambiguities.push({ slot: 'head', options: hd.options.map((o) => ({ key: o.h.key, label: o.h.label, heads: o.h.heads, utility: o.h.utility || [], terms: termsOf(o.h), sensitive: !!o.h.sensitive })) });
  if (pl.options.length > 1) res.ambiguities.push({ slot: 'place', options: pl.options.map((l) => ({ id: l.id, label: { bn: l.name_bn, en: l.name_en, code: l.code } })) });
  if (res.slots.period && res.slots.period.needs_setting) res.notes.push('fiscal_year_not_set');
  res.reports = scoreReports(n, registry, registry.intent_hints);

  const spendWord = measure === 'total' || measure === 'count' || measure === 'list';
  const moneyHint = /(paid|spent|spend|expense|cost|bill|salary|wage|advance|pay|দিয়েছি|খরচ|বিল|বেতন|অগ্রিম|পরিশোধ|ব্যয়|কত টাকা)/.test(n);
  if (measure === 'happened' && res.slots.period && res.slots.period.day) res.intent = 'day';
  else if (measure === 'compare' && res.slots.period2) res.intent = 'compare';
  else if (res.slots.head || kd.kinds.length || (person && (moneyHint || person.has_word)) || (moneyHint && spendWord && (res.slots.place || res.slots.period))) res.intent = 'spend';
  else if (res.reports.length && res.reports[0].score >= 3) res.intent = 'report';
  else res.intent = 'unknown';

  if (res.intent === 'spend' || res.intent === 'day') { if (!res.slots.period || res.slots.period.needs_setting) res.missing.push('period'); }
  if (res.intent === 'compare') { if (!res.slots.period2) res.missing.push('period2'); }
  if (person && person.kind !== 'auto' && false) res.missing.push('person');
  res.understood = chips(res, ctx);
  res.ready = (res.intent === 'spend' || res.intent === 'day' || res.intent === 'compare') && res.missing.length === 0 && res.ambiguities.length === 0 && !(person && !person.resolved);
  return res;
}
function termsOf(h) { return [...new Set((h.en || []).concat((h.bn || []).map((x) => x.trim())))].filter((t) => t.length >= 2 && t.length <= 40); }

// the "I understood" chips (the screen turns each into an editable chip)
function chips(res, ctx) {
  const S = res.slots, out = [];
  out.push({ slot: 'person', state: S.person ? 'ok' : 'any', value: S.person ? (S.person.query) : null, kind: S.person ? S.person.kind : null });
  out.push({ slot: 'head', state: S.head ? 'ok' : (res.ambiguities.some((a) => a.slot === 'head') ? 'ambiguous' : 'any'), value: S.head ? S.head.key : null });
  out.push({ slot: 'place', state: S.place ? 'ok' : (res.ambiguities.some((a) => a.slot === 'place') ? 'ambiguous' : 'any'), value: S.place ? S.place.id : null });
  out.push({ slot: 'period', state: S.period && !S.period.needs_setting ? 'ok' : 'missing', value: S.period ? S.period.label_en : null });
  return out;
}

const api = { parse, normalize, periodFrom, headsFrom, placeFrom, personFrom, scoreReports, addDays, addMonths, monthStart, monthEnd, weekStart, termsOf };
if (typeof module !== 'undefined' && module.exports) module.exports = api;
if (root) { root.BOS = root.BOS || {}; root.BOS.parse = api; }
})(typeof window !== 'undefined' ? window : null);
