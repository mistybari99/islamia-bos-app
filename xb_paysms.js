/* Islamia BOS · XB payment SMS paste reader (bKash / Nagad / Rocket confirmation text -> Trx-ID, sender, amount, time).
   Pure function, no network, no storage. The counter pastes the SMS, reads the suggestion, and CONFIRMS it; nothing is saved from here.
   Formats: the layouts below are written from the common wording of these SMS. They are UNVERIFIED against real messages from the owner's
   phone; every field is shown to the person for confirmation, and an unmatched layout returns ok:false instead of a guess. */
(function (root) {
  'use strict';
  const BN = '০১২৩৪৫৬৭৮৯';
  const toAscii = (s) => String(s || '').replace(/[০-৯]/g, (c) => String(BN.indexOf(c)));
  const PROVIDERS = [['bkash', /bkash|বিকাশ/i], ['nagad', /nagad|নগদ/i], ['rocket', /rocket|রকেট/i]];
  const IN_RE = /(receive|received|you have received|money received|পেয়েছেন|জমা হয়েছে|cash in)/i;
  const OUT_RE = /(\bsent\b|send money|paid to|payment to|cash out|পাঠিয়েছেন|পরিশোধ|payment of)/i;
  const NOISE_BEFORE = /(balance|bal\b|fee|charge|ব্যালেন্স|ফি|চার্জ|offer|cashback)/i;

  function parseMobilePaySms(raw) {
    const text = toAscii(raw).replace(/\s+/g, ' ').trim();
    const reasons = [];
    if (!text) return { ok: false, reasons: ['empty'] };
    let provider = null;
    for (const [p, re] of PROVIDERS) { if (re.test(text)) { provider = p; break; } }
    if (!provider) reasons.push('provider_not_recognised');

    let trx = null;
    const TRX = /(?:trx\s*id|trxid|txn\s*id|txnid|transaction\s*id|ট্রানজেকশন\s*আইডি|ট্রানজ্যাকশন\s*আইডি)\s*[:\-#]?\s*([A-Za-z0-9]{6,20})\b/gi;
    const trxAll = [];
    let tm;
    while ((tm = TRX.exec(text)) !== null) trxAll.push(tm[1].toUpperCase());
    if (trxAll.length) trx = trxAll[0]; else reasons.push('trx_id_not_found');
    if (trxAll.length > 1) reasons.push('several_messages_pasted');

    let amount = null;
    const NUM = '([0-9][0-9,]*(?:\\.[0-9]{1,2})?)';
    const KEY = new RegExp('(?:receive[d]?|পেয়েছেন|জমা হয়েছে|cash\\s*in|payment of|sent)[^0-9]{0,12}?(?:tk\\.?|৳|taka|টাকা)\\s*' + NUM, 'i');
    const pm = text.match(KEY);
    if (pm) amount = Number(pm[1].replace(/,/g, ''));
    const re = /(tk\.?|৳|taka|টাকা)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/gi;
    let m;
    while (amount === null && (m = re.exec(text)) !== null) {
      const before = text.slice(Math.max(0, m.index - 20), m.index);
      if (NOISE_BEFORE.test(before)) continue;
      amount = Number(m[2].replace(/,/g, ''));
      break;
    }
    if (amount === null) {
      const am = text.match(/(?:amount|পরিমাণ)\s*[:\-]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i);
      if (am) amount = Number(am[1].replace(/,/g, ''));
    }
    if (amount === null || !(amount > 0)) { amount = null; reasons.push('amount_not_found'); }

    let kind = null;
    if (IN_RE.test(text) && !OUT_RE.test(text.replace(/money received/i, ''))) kind = 'in';
    else if (OUT_RE.test(text)) kind = 'out';
    if (kind === 'out') reasons.push('outgoing_money_not_a_receipt');
    if (kind === null) reasons.push('direction_unknown');

    let sender = null;
    const sm = text.match(/(?:from|sender|প্রেরক|থেকে|sent by)\s*[:\-]?\s*(01[3-9][0-9]{8})\b/i);
    if (sm) sender = sm[1]; else reasons.push('sender_not_found');

    let date = null, time = null;
    const dm = text.match(/(\d{1,2}[\/.-]\d{1,2}[\/.-]\d{4})(?:\s+(\d{1,2}:\d{2}(?::\d{2})?))?/);
    if (dm) { date = dm[1]; time = dm[2] || null; } else reasons.push('time_not_found');

    const ok = !!(trx && amount !== null && provider && kind === 'in' && trxAll.length === 1);
    return { ok, provider, trx, amount, sender, date, time, kind, reasons };
  }

  const api = { parseMobilePaySms, toAscii };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.BOS = root.BOS || {};
  root.BOS.xbPaySms = api;
})(typeof window !== 'undefined' ? window : globalThis);
