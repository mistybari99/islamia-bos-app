/* Islamia BOS · Landed cost: GRN picker + shipment hint (step Q4, bos107). NEW file; landed.js only gets a slot (#q4_grn) in its bill picker sheet.
   Server (already there, supabase/phase97.sql): landed_resolve_docs(p_docs [{type:'grn', id}]) -> [{type, doc_id, bill_id}]. A GRN has no prices, so it is turned into the posted purchase bill it is linked to;
   the bill ids join the same ticked list as the bills (D.pick of landed.js) and the normal "Continue" opens the editor. Several bills / GRNs ticked together = one shipment (per_shipment mode).
   GRN list = entries of form 04-1 (submitted / approved), read through the normal RLS. Nothing is guessed: a GRN with no linked bill says so. Handlers are prefixed q4_. Loaded after landed.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B || !B.landed) return;
const { sb, esc, toast } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const cssq = (v) => (window.CSS && typeof CSS.escape === 'function') ? CSS.escape(String(v)) : String(v).replace(/["\\\]]/g, '\\$&');   // bos111 (L8): ids go into a selector as escaped text
const X = {
  head: L('GRN থেকে বিল যোগ', 'Add from a GRN', 'GRN থেকে bill যোগ'),
  load: L('GRN-এর তালিকা দেখুন', 'Show GRNs', 'GRN list দেখুন'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  none: L('কোনো GRN পাওয়া যায়নি', 'No GRNs found', 'কোনো GRN পাওয়া যায়নি'),
  hint: L('GRN-এ প্রাইস থাকে না; তার সাথে যুক্ত ক্রয় বিলটি যোগ হবে।', 'A GRN has no prices; the purchase bill linked to it is added.', 'GRN-এ price থাকে না; তার সাথে linked purchase bill যোগ হবে।'),
  add: L('টিক দেওয়া GRN-এর বিল যোগ', 'Add the bills of the ticked GRNs', 'Ticked GRN-এর bill যোগ'),
  tickFirst: L('আগে একটি GRN টিক দিন', 'Tick a GRN first', 'আগে একটি GRN টিক দিন'),
  added: L('বিল যোগ হয়েছে', 'Bill added', 'Bill যোগ হয়েছে'),
  notLinked: L('এই GRN-এর সাথে কোনো ক্রয় বিল যুক্ত নেই — আগে যুক্ত করুন', 'This GRN is not linked to a purchase bill - link it first', 'এই GRN-এর সাথে কোনো purchase bill linked নেই — আগে link করুন'),
  noBill: L('এই GRN থেকে পোস্ট করা বিল পাওয়া গেল না', 'No posted bill found for this GRN', 'এই GRN থেকে posted bill পাওয়া গেল না'),
  noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  noFn: L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part for this is not installed yet', 'এই অংশের database চালু হয়নি'),
  shipHint: L('একটি চালানের একাধিক বিল / GRN একসাথে টিক দিন — সব মিলে একটি landed cost হবে।', 'Tick several bills / GRNs of one shipment together - they get one landed cost.', 'একটি shipment-এর একাধিক bill / GRN একসাথে tick করুন — সব মিলে একটি landed cost হবে।'),
  billHint: L('এই পদ্ধতিতে একটি landed cost = একটি বিল।', 'In this mode one landed cost covers one bill.', 'এই mode-এ একটি landed cost = একটি bill।'),
  status: L('অবস্থা', 'Status', 'Status'),
};
const T = (k) => lab(X[k]);
const st = () => { try { return B.landed._state(); } catch (e) { return null; } };
const errTxt = (e) => { const m = String((e && e.message) || e || ''); return /grn_not_linked/.test(m) ? T('notLinked') : /bill_not_found/.test(m) ? T('noBill') : /not allowed/.test(m) ? T('noperm') : /does not exist|schema cache|Could not find/i.test(m) ? T('noFn') : m.slice(0, 140); };

function modeHint() {
  const D = st(), mode = D && D.info && D.info.mode;
  return mode === 'per_shipment' ? `<div class="hint" id="q4_mh">${esc(T('shipHint'))}</div>` : mode === 'per_bill' ? `<div class="hint" id="q4_mh">${esc(T('billHint'))}</div>` : '';
}
function mount() {
  const box = $('#q4_grn'); if (!box) return;
  box.innerHTML = `${modeHint()}<div class="card stack" style="margin-top:10px"><b>${esc(T('head'))}</b><div class="hint">${esc(T('hint'))}</div><div id="q4_grnlist"><button type="button" data-act="q4_grnload">${esc(T('load'))}</button></div></div>`;
}
async function loadList() {
  const box = $('#q4_grnlist'); if (!box) return;
  box.innerHTML = `<p class="muted center">${esc(T('loading'))}</p>`;
  let rows = [];
  try {
    const r = await sb.from('entries').select('id,serial,entry_date,status,location_id').eq('form_code', '04-1').in('status', ['submitted', 'approved']).order('entry_date', { ascending: false }).order('serial', { ascending: false }).limit(60);
    if (r && r.error) throw r.error; rows = (r && r.data) || [];
  } catch (e) { box.innerHTML = `<div class="notice bad">${esc(errTxt(e))}</div>`; return; }
  box.innerHTML = rows.length ? `<div class="stack">${rows.map((g) => `<label class="row between lc-pk"><span class="row"><input type="checkbox" data-q4g="${esc(g.id)}"><span>GRN ${esc(g.serial == null ? '' : g.serial)}<span class="hint"> ${esc(g.entry_date || '')} · ${esc(T('status'))}: ${esc(g.status || '')}</span></span></span></label>`).join('')}</div>
    <button type="button" class="primary full" data-act="q4_grnadd" style="margin-top:8px">${esc(T('add'))}</button><div id="q4_grnmsg" class="hint" aria-live="polite"></div>` : `<p class="muted center">${esc(T('none'))}</p>`;
}
async function addTicked(btn) {
  const D = st(); if (!D) return;
  const ids = [...document.querySelectorAll('#q4_grnlist input[data-q4g]')].filter((x) => x.checked).map((x) => x.getAttribute('data-q4g'));
  const msg = $('#q4_grnmsg');
  if (!ids.length) { toast(T('tickFirst')); return; }
  if (btn) btn.disabled = true;
  const lines = [];
  try {
    for (const id of ids) {
      try {
        const r = await sb.rpc('landed_resolve_docs', { p_docs: [{ type: 'grn', id }] });
        if (r.error) throw r.error;
        (r.data || []).forEach((d) => {
          if (!d.bill_id) return;
          if (!D.pick.includes(d.bill_id)) D.pick.push(d.bill_id);
          const cb = document.querySelector(`[data-lcpk="${cssq(d.bill_id)}"]`); if (cb) cb.checked = true;
          lines.push('✓ ' + T('added') + ' (' + String(d.bill_id).slice(0, 8) + ')');
        });
        const cb2 = document.querySelector(`#q4_grnlist input[data-q4g="${cssq(id)}"]`); if (cb2) cb2.checked = false;
      } catch (e) { lines.push('! ' + errTxt(e)); }
    }
  } finally { if (btn) btn.disabled = false; }
  if (msg) msg.textContent = lines.join(' · ');
}
Object.assign(H, {
  q4_grnload: () => loadList(),
  q4_grnadd: (a) => addTicked(a),
});
B.landedQ4 = { X, T, mount, loadList, addTicked, errTxt };
})();
