/* Islamia BOS · Chat-order parser (X3). Rule-based, offline, no AI, no network.
   Reads ONE pasted customer message (Bangla, English or Banglish) and suggests the fields of an online order DRAFT:
   customer name, mobile, address, items with quantity and unit, delivery day and time, and an enquiry kind.
   It NEVER creates or confirms an order. A person reviews every suggestion in the inbox before anything is saved (online_order_save2 with the draft flag).
   Every guess says how sure it is: 'matched' / 'low' / 'none'. An unknown item is flagged, never guessed to be another item.
   Pure functions only: parse(text, items, opts) returns a plain object. Tested by tests/web/order_parser_test.js (node). */
(() => {
'use strict';

const BN_DIGITS = '০১২৩৪৫৬৭৮৯';
const WORD_NUM = { 'এক': 1, 'একটি': 1, 'একটা': 1, 'ek': 1, 'eka': 1, 'একটু': null,
  'দুই': 2, 'দুটি': 2, 'দুটো': 2, 'dui': 2, 'দুইটি': 2, 'তিন': 3, 'তিনটি': 3, 'তিনটা': 3, 'tin': 3,
  'চার': 4, 'চারটি': 4, 'চারটা': 4, 'char': 4, 'পাঁচ': 5, 'পাচ': 5, 'পাঁচটি': 5, 'pach': 5, 'paach': 5,
  'ছয়': 6, 'ছয়টি': 6, 'choy': 6, 'সাত': 7, 'sat': 7, 'আট': 8, 'আটটি': 8, 'noy': 9, 'নয়': 9, 'দশ': 10, 'dosh': 10 };
const UNIT_MAP = [
  [/^(kg|kilo|kilogram|কেজি|কেজি)$/i, 'kg'], [/^(gm|g|gram|গ্রাম|gram)$/i, 'gm'],
  [/^(pc|pcs|piece|pieces|পিস|টি|টা|ti|ta|খানা)$/i, 'pc'], [/^(dozen|doz|ডজন)$/i, 'dozen'], [/^(box|বক্স|box)$/i, 'box'],
];
const UNIT_RX = 'kg|kilo|kilogram|কেজি|gm|gram|গ্রাম|g|pcs|pc|piece|pieces|পিস|টি|টা|ti|ta|খানা|dozen|doz|ডজন|box|বক্স';

/* ---------- text helpers (exported for tests) ---------- */
function normText(s) {
  let t = String(s == null ? '' : s).replace(/[​-‏﻿]/g, '');
  t = t.replace(/[০-৯]/g, (c) => String(BN_DIGITS.indexOf(c)));
  return t.toLowerCase().replace(/\s+/g, ' ').trim();
}
function unitOf(u) {
  if (!u) return null;
  for (const [rx, code] of UNIT_MAP) if (rx.test(u)) return code;
  return null;
}
/* Bangladeshi mobile: 01XXXXXXXXX, 8801XXXXXXXXX, +8801XXXXXXXXX (spaces and dashes allowed) */
function findPhone(text) {
  const d = normText(text).replace(/[\s\-()]/g, '');
  const m = d.match(/(?:\+?880|0)(1[3-9]\d{8})(?!\d)/);
  return m ? '0' + m[1] : null;
}
// a time word ends at a space, punctuation or the end (\b does not work next to Bangla letters)
const TIME_RX = '(\\d{1,2})(?::(\\d{2}))?\\s*(?:টা|টায়|am|pm|ta|baje|বাজে|বাজেন|বাজ[েে])(?=$|[\\s,.;।!?])';
// "5টায়", "5pm", "5 baje" are always a time. A bare "5টা" / "5 ta" is a time only when the message says when (morning, evening, delivery ...)
const TIME_CTX = /(সকাল|সন্ধ্যা|সন্ধ্যে|বিকেল|বিকাল|দুপুর|রাত|বেলা|morning|evening|night|afternoon|sokal|shokal|bikel|bikal|shondha|dupur|raat|bela|deliver|delivery|পৌঁছ|পৌছ|আসবেন|আনবেন|pathan)/i;
const TIME_STRONG = '(\\d{1,2})(?::(\\d{2}))?\\s*(?:টায়|am|pm|baje|বাজে|বাজেন|বাজ[েে])(?=$|[\\s,.;।!?])';
const TIME_WEAK = '(\\d{1,2})\\s*(?:টা|ta)(?=$|[\\s,.;।!?])';
function stripPhoneAndTime(text, timeCtx) {
  let t = normText(text)
    .replace(/(?:\+?880[\s-]?|0)1[3-9][\d\s-]{8,10}/g, ' ')
    .replace(new RegExp('(?:^|[\\s])' + TIME_STRONG, 'gi'), ' ');
  if (timeCtx) t = t.replace(new RegExp('(?:^|[\\s])' + TIME_WEAK, 'gi'), ' ');
  return t.replace(/\d+(?:\.\d+)?\s*(?:taka|টাকা|টাকায়|tk)(?=$|[\s,.;।!?])/gi, ' ');
}

/* ---------- delivery day and time ---------- */
const WB = (w) => new RegExp('(?:^|[\\s,.;।!?])(?:' + w + ')(?=$|[\\s,.;।!?])', 'i');
function findDay(text) {
  const t = normText(text);
  if (WB('পরশু|parshu|porshu|poroshu|day after tomorrow').test(t)) return { offset: 2, confidence: 'matched', word: 'পরশু' };
  if (WB('আগামীকাল|আগামী কাল|tomorrow').test(t)) return { offset: 1, confidence: 'matched', word: 'আগামী কাল' };
  if (WB('কাল|kal').test(t)) {
    // "kal" means yesterday or tomorrow; in an order it is read as tomorrow, so the confidence is low
    return { offset: 1, confidence: 'low', word: 'কাল' };
  }
  if (WB('আজ|aaj|today').test(t)) return { offset: 0, confidence: 'matched', word: 'আজ' };
  return null;
}
function findTime(text) {
  const t = normText(text);
  let m = t.match(new RegExp(TIME_STRONG, 'i'));
  if (!m && TIME_CTX.test(t)) m = t.match(new RegExp(TIME_WEAK, 'i'));
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = m[2] ? parseInt(m[2], 10) : 0;
  if (h > 23 || min > 59) return null;
  const pmWord = /(বিকেল|বিকাল|সন্ধ্যা|রাত|evening|night|pm|bikel|shondha|raat)/i.test(t);
  const amWord = /(সকাল|morning|am|shokal|sokal)/i.test(t);
  let confidence = 'matched';
  if (pmWord && h < 12) h += 12;
  else if (!pmWord && !amWord && h >= 1 && h <= 7) confidence = 'low';   // "5 ta" alone: could be morning or evening
  return { hour: h, minute: min, confidence };
}
function isoDay(offset, todayIso) {
  if (offset == null || !todayIso) return null;
  const d = new Date(todayIso + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
}

/* ---------- name, address, enquiry kind ---------- */
function labelled(text, labels) {
  const lines = String(text || '').split(/\r?\n/);
  for (const ln of lines) {
    const m = ln.match(new RegExp('^\\s*(?:' + labels + ')\\s*[:：\\-]\\s*(.+)$', 'i'));
    if (m) return m[1].trim();
  }
  return null;
}
const ADDR_WORDS = /(রোড|road|রোড|সড়ক|বাড়ি|বাসা|বাড়ী|flat|ফ্ল্যাট|গ্রাম|থানা|thana|upazila|উপজেলা|ঢাকা|dhaka|মহল্লা|block|ব্লক|সেক্টর|sector|house|হাউস)/i;

// keyword lists. An English word must stand alone ("late" is not inside "chocolate"); Bangla words match as they are written.
const termRx = (terms) => new RegExp(terms.map((w) => (/^[a-z ?]+$/i.test(w)
  ? '(?<![a-z])' + w.replace(/[?]/g, '\\?').replace(/\s+/g, '\\s+') + '(?![a-z])'
  : w.replace(/\s+/g, '\\s+'))).join('|'), 'i');
const KINDS = [
  ['complaint', termRx(['অভিযোগ', 'নষ্ট', 'খারাপ', 'ভালো না', 'ভাল না', 'ভুল', 'পচা', 'bad', 'complain', 'complaint', 'damaged', 'wrong', 'rotten', 'late']), 'high'],
  ['custom_cake', termRx(['কাস্টম', 'custom', 'ডিজাইন', 'design', 'নাম লিখে', 'লিখে দিন', 'photo cake', 'ছবি দিয়ে', 'theme', 'fondant', 'ফন্ডেন্ট']), 'high'],
  ['order', termRx(['অর্ডার', 'order', 'লাগবে', 'লাগবো', 'চাই', 'দরকার', 'দিবেন', 'পাঠান', 'pathan', 'pathaben', 'dibo', 'lagbe', 'lagbo', 'chai', 'need', 'দিয়েন', 'নিয়ে আসবেন']), 'high'],
  ['availability', termRx(['আছে কি', 'আছে কিনা', 'আছে?', 'পাওয়া যাবে', 'পাওয়া যায়', 'available', 'stock', 'ache ki', 'achhe ki', 'ache?']), 'high'],
  ['price', termRx(['দাম', 'কত টাকা', 'কত', 'price', 'rate', 'koto', 'koto taka', 'দর', 'মূল্য', 'cost']), 'high'],
];

function classify(text, hasItems, hasQty) {
  const t = normText(text);
  const hits = [];
  let kind = 'other';
  let conf = 'none';
  for (const [k, rx, strength] of KINDS) {
    if (rx.test(t)) hits.push(k);
  }
  if (hits.length) {
    kind = hits[0];
    conf = hits.length === 1 ? 'high' : 'low';          // two different signals at once = not sure
    if (kind === 'price' && hasItems && hits.indexOf('order') >= 0) { kind = 'order'; conf = 'low'; }
    if (kind === 'price' && hasItems && !hasQty) conf = 'high';
    if (kind === 'availability' && hasQty && hits.indexOf('order') >= 0) { kind = 'order'; conf = 'low'; }
  } else if (hasItems && hasQty) {
    kind = 'order'; conf = 'low';                        // an item with a number and no words: probably an order
  }
  return { kind, confidence: conf, signals: hits };
}

/* ---------- items ---------- */
function aliasesOf(item) {
  const list = [item.name_bn, item.name_en].concat(Array.isArray(item.aliases) ? item.aliases : []);
  return list.map((a) => normText(a)).filter((a) => a && a.length >= 3);
}
function matchItem(clause, items) {
  let best = null;
  for (const it of items || []) {
    for (const a of aliasesOf(it)) {
      if (a.length < 3) continue;
      const i = clause.indexOf(a);
      if (i >= 0 && (!best || a.length > best.len)) best = { item: it, len: a.length, alias: a };
    }
  }
  return best;
}

/* ---------- main ---------- */
function parse(text, items, opts) {
  const o = opts || {};
  const raw = String(text == null ? '' : text);
  const flags = [];
  const mobile = findPhone(raw);
  const name = labelled(raw, 'name|নাম|customer|গ্রাহক');
  const address = labelled(raw, 'address|addr|ঠিকানা|thikana') || null;
  // lines first (a label is one line), then commas, dandas and bars; each piece is normalised on its own
  const clausesRaw = raw.split(/\r?\n|[।,;|]+/).map((c) => normText(c)).filter(Boolean);
  const lines = [];
  let addrLine = null;
  const timeCtx = TIME_CTX.test(normText(raw));
  for (const c0 of clausesRaw) {
    if (/^(name|নাম|customer|গ্রাহক|address|addr|ঠিকানা|thikana|phone|mobile|মোবাইল|ফোন)\s*[:：\-]/.test(c0)) continue;
    // "আর", "and", "ও" join two items in one clause: each part is read on its own
    const parts = stripPhoneAndTime(c0, timeCtx).split(/\s(?:আর|and|&|ও|সাথে|with)\s/).map((x) => x.trim()).filter(Boolean);
    for (const part of parts) {
    let c = part;
    // word numbers become digits when they are standing alone
    c = c.split(' ').map((w) => (WORD_NUM[w] != null ? String(WORD_NUM[w]) : w)).join(' ');
    const m = matchItem(c, items);
    const q = c.match(new RegExp('(\\d+(?:\\.\\d+)?)\\s*(' + UNIT_RX + ')?', 'i'));
    if (ADDR_WORDS.test(c) && !m) { if (!addrLine) addrLine = c0; continue; }
    if (m) {
      let qty = q ? parseFloat(q[1]) : null;
      let unit = q ? unitOf(q[2]) : null;
      let conf = 'matched';
      if (qty == null) { qty = 1; conf = 'low'; flags.push('qty_missing'); }
      if (unit === 'gm') { qty = Math.round((qty / 1000) * 1000) / 1000; unit = 'kg'; }
      if (q && !q[2]) { conf = conf === 'matched' ? 'low' : conf; }
      lines.push({ raw: c0, item_id: m.item.id, item_name: m.item.name_bn || m.item.name_en, qty, unit: unit || (m.item.unit || null), confidence: conf, qty_typed: !!q });
      if (!unit && q) flags.push('unit_unclear');
    } else if (q && /[a-zঀ-৿]/i.test(c.replace(q[0], ''))) {
      // a quantity and words, but no approved item matches: flag it, never guess
      lines.push({ raw: c0, item_id: null, item_name: null, qty: parseFloat(q[1]), unit: unitOf(q[2]), confidence: 'none' });
      flags.push('unknown_item');
    }
    }
  }
  const day = findDay(raw);
  const time = findTime(raw);
  if (!day) flags.push('day_missing');
  if (!mobile) flags.push('phone_missing');
  const addr = address || addrLine;
  if (address == null && addr) flags.push('address_guessed');
  if (!addr) flags.push('address_missing');
  const hasItems = lines.some((l) => l.item_id);
  const hasQty = lines.some((l) => l.item_id && l.qty_typed);
  const kind = classify(raw, hasItems, hasQty);
  if (kind.kind !== 'order') flags.push('not_an_order');
  if (lines.some((l) => !l.item_id)) flags.push('unknown_item');
  return {
    kind: kind.kind, kind_confidence: kind.confidence, kind_signals: kind.signals,
    name: name || null, mobile, address: addr,
    day: day ? { offset: day.offset, word: day.word, confidence: day.confidence, iso: isoDay(day.offset, o.todayIso) } : null,
    time: time ? { hour: time.hour, minute: time.minute, confidence: time.confidence } : null,
    lines, flags: Array.from(new Set(flags)),
    note: 'draft suggestion only: a person checks and saves it; nothing is ordered until then',
  };
}

const api = { parse, normText, findPhone, findDay, findTime, unitOf, matchItem, classify, isoDay, stripPhoneAndTime };
if (typeof window !== 'undefined') { window.BOS = window.BOS || {}; window.BOS.orderParser = api; }
if (typeof module !== 'undefined' && module.exports) module.exports = api;
})();
