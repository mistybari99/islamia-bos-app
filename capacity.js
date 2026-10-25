/* Islamia BOS · Capacity and labour (#/capacity), package RPT-B4 / R8. Three tabs:
   output per labour hour (#48) · capacity utilization (#51) · set-up of production lines and rated capacity (owner, or the grant capacity_manage).
   Labour hours of a run are typed on the run (#/prodplan, "Labour" part of the run sheet); this screen reads them.
   Server: supabase/phase412.sql (production_lines, capacity_ratings, production_labour and their functions), phase413.sql (rb4_labour_productivity, rb4_capacity_utilization), phase416.sql (rb4_log_export).
   A missing figure is "data not captured: <field>" (a run with no labour record, a place with no rating), never 0. The capacity of a day = rated batches per day x working days per week / 7, from the rating in force that day.
   Paper form code of the set-up entries: to be given by owner. Built on web/rb4common.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!B || !B.rb4) return;
const { sb, esc, toast, fail, openSheet, closeSheet, nm, S } = A;
const R = B.rb4, L = R.L, lab = R.lab;
const $ = (s, el = document) => el.querySelector(s);
const L_ = {
  title: L('শ্রম ও ক্ষমতা', 'Labour & capacity', 'Labour ও capacity'), tLab: L('শ্রম-ঘণ্টায় উৎপাদন', 'Output per labour hour', 'Output per labour hour'), tCap: L('ক্ষমতা ব্যবহার', 'Capacity utilization', 'Capacity utilization'), tSet: L('লাইন ও রেটেড ক্ষমতা', 'Lines & rated capacity', 'Lines ও rated capacity'),
  item: L('পণ্য', 'Item', 'Item'), place: L('জায়গা', 'Place', 'Place'), line: L('লাইন', 'Line', 'Line'), day: L('দিন', 'Day', 'Day'), runs: L('রান', 'Runs', 'Runs'), measured: L('মাপা রান', 'Runs measured', 'Runs measured'), nc: L('শ্রম লেখা নেই এমন রান', 'Runs with no labour', 'Runs no labour'),
  output: L('উৎপাদন', 'Output', 'Output'), hours: L('শ্রম-ঘণ্টা', 'Labour hours', 'Labour hours'), people: L('লোক', 'People', 'People'), crews: L('দল', 'Crews', 'Crews'), perHour: L('ঘণ্টায় উৎপাদন', 'Output per hour', 'Output per hour'), hpu: L('প্রতি একক ঘণ্টা', 'Hours per unit', 'Hours per unit'),
  batches: L('ব্যাচ', 'Batches', 'Batches'), bph: L('ঘণ্টায় ব্যাচ', 'Batches per hour', 'Batches per hour'), status: L('অবস্থা', 'Status', 'Status'), perItem: L('পণ্য অনুযায়ী', 'Per item', 'Per item'), perPlace: L('জায়গা অনুযায়ী', 'Per place', 'Per place'), perRun: L('রান অনুযায়ী', 'Per run', 'Per run'),
  s_measured: L('মাপা', 'measured', 'measured'), s_labour_not_captured: L('শ্রম লেখা নেই', 'labour not captured', 'labour লেখা নেই'), fLabour: L('শ্রম-ঘণ্টা', 'labour hours', 'labour hours'), fRating: L('রেটেড ক্ষমতা', 'rated capacity', 'rated capacity'),
  days: L('দিন', 'Days', 'Days'), daysRated: L('রেটিং আছে এমন দিন', 'Days rated', 'Days rated'), daysNot: L('রেটিং নেই এমন দিন', 'Days not rated', 'Days not rated'), cap: L('ক্ষমতা (ব্যাচ)', 'Capacity (batches)', 'Capacity (batches)'), made: L('তৈরি ব্যাচ', 'Batches made', 'Batches made'),
  madeRated: L('রেটিংয়ের দিনে তৈরি', 'Made on rated days', 'Made on rated days'), madeNot: L('রেটিং ছাড়া দিনে তৈরি (বিচার হয়নি)', 'Made on days not rated (not judged)', 'Made on unrated days'), util: L('ব্যবহার %', 'Utilization %', 'Utilization %'),
  bpd: L('রেটেড ব্যাচ প্রতিদিন', 'Rated batches a day', 'Rated batches/day'), dpw: L('সপ্তাহে কাজের দিন', 'Working days a week', 'Working days/week'), s_rated: L('রেটিং আছে', 'rated', 'rated'), s_partly_rated: L('আংশিক রেটিং', 'partly rated', 'partly rated'), s_rated_capacity_not_captured: L('রেটেড ক্ষমতা লেখা নেই', 'rated capacity not captured', 'rated capacity লেখা নেই'),
  whole: L('পুরো জায়গা', 'Whole place', 'Whole place'),
  // set-up
  lines: L('লাইন', 'Lines', 'Lines'), ratings: L('রেটেড ক্ষমতা', 'Rated capacity', 'Rated capacity'), addLine: L('নতুন লাইন', 'Add a line', 'Add line'), addRating: L('ক্ষমতা ঠিক করুন', 'Set rated capacity', 'Rated capacity ঠিক করুন'), nameBn: L('নাম (বাংলা)', 'Name (Bangla)', 'Name (বাংলা)'),
  nameEn: L('নাম (ইংরেজি, ঐচ্ছিক)', 'Name (English, optional)', 'Name (English, optional)'), whole2: L('— পুরো জায়গা —', '— whole place —', '— whole place —'), from: L('কবে থেকে', 'From', 'From'), retire: L('বন্ধ করুন', 'Retire', 'Retire'), rename: L('বদলান', 'Edit', 'Edit'),
  active: L('চালু', 'active', 'active'), retired: L('বন্ধ', 'retired', 'retired'), ownerOnly: L('লাইন ও ক্ষমতা শুধু মালিক বা অনুমতিপ্রাপ্ত ঠিক করেন', 'Lines and capacity are set by the owner or a holder of the right', 'Line ও capacity owner বা permission-holder ঠিক করেন'),
  effFrom: L('কার্যকর', 'In force from', 'In force from'), note: L('নোট', 'Note', 'Note'), saveMsg: L('সংরক্ষিত', 'Saved', 'Saved'),
};
const base = (r) => r.base_unit;
const filt = (D) => ({ p_from: D.from, p_to: D.to, p_loc: D.loc ? Number(D.loc) : null });
const filtI = (D) => Object.assign(filt(D), { p_item: D.item || null });
const runLink = (r) => (r.run_id ? [{ label: L('রান খুলুন', 'Open the run', 'Run খুলুন'), hash: '#/prodplan/run/' + r.run_id }] : []);
const lineName = (r) => (S.lang === 'en' ? r.line_en || r.line_bn : r.line_bn || r.line_en) || '';
const lineOwn = (r) => (S.lang === 'en' ? r.name_en || r.name_bn : r.name_bn || r.name_en) || '';
const item = { l: L_.item, get: (r) => R.itemName(r), w: 't' };
const placeS = { l: L_.place, get: (r) => R.locName(r), w: 's' };

const tabs = [
  { id: 'lab', label: L_.tLab, rpc: 'rb4_labour_productivity', args: filtI, csvKey: 'labour_productivity', csvName: 'output-per-labour-hour',
    blocks: [
      { title: L_.perItem, rows: (d) => d.by_item, cols: [item, { l: L_.runs, get: (r) => r.runs, f: 'int', w: 'c' }, { l: L_.measured, get: (r) => r.measured, f: 'int' }, { l: L_.nc, get: (r) => r.labour_not_captured, f: 'int' },
        { l: L_.output, get: (r) => r.output_measured, f: 'q4', unit: base, nc: L_.fLabour }, { l: L_.hours, get: (r) => r.labour_hours, f: 'q4', nc: L_.fLabour }, { l: L_.perHour, get: (r) => r.output_per_hour, f: 'q4', unit: base, nc: L_.fLabour }] },
      { title: L_.perPlace, rows: (d) => d.by_place, cols: [{ l: L_.place, get: (r) => R.locName(r), w: 't' }, { l: L_.runs, get: (r) => r.runs, f: 'int', w: 'c' }, { l: L_.measured, get: (r) => r.measured, f: 'int' }, { l: L_.nc, get: (r) => r.labour_not_captured, f: 'int' },
        { l: L_.hours, get: (r) => r.labour_hours, f: 'q4', nc: L_.fLabour }, { l: L_.batches, get: (r) => r.batches_measured, f: 'q4', nc: L_.fLabour }, { l: L_.bph, get: (r) => r.batches_per_hour, f: 'q4', nc: L_.fLabour }] },
      { title: L_.perRun, rows: (d) => d.rows, status: { measured: L_.s_measured, labour_not_captured: L_.s_labour_not_captured }, warn: (r) => r.status !== 'measured', links: runLink,
        cols: [item, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.day, get: (r) => r.day, f: 'date', w: 's' }, placeS, { l: L_.line, get: (r) => lineName(r) || null }, { l: L_.output, get: (r) => r.output, f: 'q4', unit: base },
          { l: L_.hours, get: (r) => r.labour_hours, f: 'q4', nc: L_.fLabour }, { l: L_.people, get: (r) => r.people, f: 'int' }, { l: L_.crews, get: (r) => r.crews, f: 'int' }, { l: L_.perHour, get: (r) => r.output_per_hour, f: 'q4', unit: base, nc: L_.fLabour }, { l: L_.hpu, get: (r) => r.hours_per_unit, f: 'q4' }] }] },
  { id: 'cap', label: L_.tCap, rpc: 'rb4_capacity_utilization', args: filt, filters: ['date', 'loc'], csvKey: 'capacity', csvName: 'capacity-utilization',
    blocks: [{ title: null, rows: (d) => d.rows, status: { rated: L_.s_rated, partly_rated: L_.s_partly_rated, rated_capacity_not_captured: L_.s_rated_capacity_not_captured }, warn: (r) => r.status !== 'rated',
      cols: [{ l: L_.place, get: (r) => R.locName(r) + (r.line_id ? ' · ' + lineName(r) : ' · ' + lab(L_.whole)), w: 't' }, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' },
        { l: L_.days, get: (r) => r.days, f: 'int' }, { l: L_.daysRated, get: (r) => r.days_rated, f: 'int' }, { l: L_.daysNot, get: (r) => r.days_not_rated, f: 'int' }, { l: L_.cap, get: (r) => r.capacity_batches, f: 'q4', nc: L_.fRating },
        { l: L_.made, get: (r) => r.batches_made, f: 'q4' }, { l: L_.madeRated, get: (r) => r.batches_made_on_rated_days, f: 'q4', nc: L_.fRating }, { l: L_.madeNot, get: (r) => r.batches_made_on_days_not_rated, f: 'q4' },
        { l: L_.util, get: (r) => r.utilization_pct, f: 'pct', nc: L_.fRating }, { l: L_.bpd, get: (r) => r.rated_batches_per_day, f: 'q4', nc: L_.fRating }, { l: L_.dpw, get: (r) => r.rated_days_per_week, f: 'q4', nc: L_.fRating }] }] },
  { id: 'set', label: L_.tSet, filters: ['loc'], csvKey: 'capacity_ratings', csvName: 'capacity-ratings',
    load: async (D) => {
      const a = await sb.rpc('capacity_rating_list', { p_loc: D.loc ? Number(D.loc) : null, p_with_retired: true }); if (a.error) throw a.error;
      const b = await sb.rpc('production_line_list', { p_loc: D.loc ? Number(D.loc) : null, p_with_retired: true }); if (b.error) throw b.error;
      D.lines = b.data || []; return { ratings: a.data || [], lines: D.lines };
    },
    top: (d, D) => (D.canEdit ? `<div class="row wrap"><button type="button" class="primary" data-act="cap_newline">${esc(lab(L_.addLine))}</button><button type="button" class="primary" data-act="cap_newrate">${esc(lab(L_.addRating))}</button></div><p class="muted">${esc(lab(R.X.paperCode))}</p>` : `<p class="muted">${esc(lab(L_.ownerOnly))}</p>`),
    blocks: [
      { title: L_.lines, rows: (d) => d.lines, status: { true: L_.active, false: L_.retired }, warn: (r) => !r.active,
        detail: (r) => (r.can_edit && r.active ? `<div class="row wrap"><button type="button" class="mini" data-act="cap_editline" data-id="${r.id}">${esc(lab(L_.rename))}</button><button type="button" class="mini" data-act="cap_retline" data-id="${r.id}">${esc(lab(L_.retire))}</button></div>` : ''),
        cols: [{ l: L_.line, get: (r) => lineOwn(r), w: 't' }, { l: L_.status, get: (r) => String(r.active), f: 'status', w: 'c' }, placeS, { l: L_.note, get: (r) => r.retired_note }] },
      { title: L_.ratings, rows: (d) => d.ratings, status: { active: L_.active, retired: L_.retired }, warn: (r) => r.status !== 'active',
        detail: (r) => (r.can_edit && r.status === 'active' ? `<button type="button" class="mini" data-act="cap_retrate" data-id="${r.id}">${esc(lab(L_.retire))}</button>` : ''),
        cols: [{ l: L_.place, get: (r) => R.locName(r) + ' · ' + (r.line_id ? lineName(r) : lab(L_.whole)), w: 't' }, { l: L_.status, get: (r) => r.status, f: 'status', w: 'c' }, { l: L_.bpd, get: (r) => r.batches_per_day, f: 'q4' }, { l: L_.dpw, get: (r) => r.days_per_week, f: 'q4' },
          { l: L_.effFrom, get: (r) => r.effective_from, f: 'date' }, { l: L_.note, get: (r) => r.note || r.retired_note }] }] },
];

R.page({ route: 'capacity', act: 'cap', title: L_.title, tabs, range: 'days30',
  init: async (D) => {
    D.canEdit = !!S.ctx.is_owner;
    if (!D.canEdit && B.s2 && B.s2.grant) { try { D.canEdit = !!(await B.s2.grant('capacity_manage', null)); } catch (e) { D.canEdit = false; } }
  },
  handlers: (D, api) => {
    const act = async (p, ok) => { if (D.busy) return; D.busy = true; try { const r = await p; if (r.error) return toast(R.errText(r.error)); closeSheet(); toast(lab(L_.saveMsg)); await ok(r.data || {}); } catch (e) { fail(e); } finally { D.busy = false; } };
    const lineSheet = (ln) => openSheet(`<h2>${esc(lab(ln ? L_.rename : L_.addLine))}</h2><div class="stack"><p class="muted">${esc(lab(R.X.paperCode))}</p>
      ${ln ? '' : `<div><label for="cap_l_loc">${esc(lab(L_.place))}</label>${R.placeSel(D, 'cap_l_loc', D.loc, false)}</div>`}
      <div><label for="cap_l_bn">${esc(lab(L_.nameBn))}</label><input id="cap_l_bn" maxlength="80" autocomplete="off" value="${esc(ln ? ln.name_bn : '')}"></div>
      <div><label for="cap_l_en">${esc(lab(L_.nameEn))}</label><input id="cap_l_en" maxlength="80" autocomplete="off" value="${esc(ln ? ln.name_en || '' : '')}"></div>
      <div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="primary full" data-act="cap_linesave" data-id="${ln ? ln.id : ''}">${esc(lab(R.X.save))}</button></div></div>`);
    const reasonSheet = (kind, id) => { D.reason = { kind, id }; openSheet(`<h2>${esc(lab(L_.retire))}</h2><div class="stack"><div><label for="cap_why">${esc(lab(R.X.why))}</label><input id="cap_why" maxlength="300" autocomplete="off"></div><div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="danger full" data-act="cap_rgo">${esc(lab(L_.retire))}</button></div></div>`); };
    const setData = () => (D.data.set || {});
    return {
      cap_newline: () => lineSheet(null),
      cap_editline: (a) => { const ln = (setData().lines || []).find((x) => String(x.id) === a.dataset.id); closeSheet(); if (ln) setTimeout(() => lineSheet(ln), 0); },
      cap_linesave: (a) => {
        const id = a.dataset.id ? Number(a.dataset.id) : null, bn = (($('#cap_l_bn') || {}).value || '').trim(), en = (($('#cap_l_en') || {}).value || '').trim(), loc = id ? null : Number(($('#cap_l_loc') || {}).value);
        if (!bn) return toast(lab(R.ERR.bad_name)); if (!id && !loc) return toast(lab(L_.place) + '?');
        return act(sb.rpc('production_line_set', { p_id: id, p_loc: loc, p_name_bn: bn, p_name_en: en || null, p_active: true, p_note: null }), () => api.run());
      },
      cap_retline: (a) => { closeSheet(); setTimeout(() => reasonSheet('line', a.dataset.id), 0); },
      cap_newrate: () => {
        const lines = (setData().lines || []).filter((l) => l.active);
        openSheet(`<h2>${esc(lab(L_.addRating))}</h2><div class="stack"><p class="muted">${esc(lab(R.X.paperCode))}</p>
          <div><label for="cap_r_loc">${esc(lab(L_.place))}</label>${R.placeSel(D, 'cap_r_loc', D.loc, false)}</div>
          <div><label for="cap_r_line">${esc(lab(L_.line))}</label><select id="cap_r_line"><option value="">${esc(lab(L_.whole2))}</option>${lines.map((l) => `<option value="${l.id}" data-loc="${l.location_id}">${esc(R.locName(l) + ' · ' + lineOwn(l))}</option>`).join('')}</select></div>
          <div class="row"><div style="flex:1"><label for="cap_r_bpd">${esc(lab(L_.bpd))}</label><input id="cap_r_bpd" inputmode="decimal" autocomplete="off"></div><div style="flex:1"><label for="cap_r_dpw">${esc(lab(L_.dpw))}</label><input id="cap_r_dpw" inputmode="decimal" autocomplete="off"></div></div>
          <div><label for="cap_r_from">${esc(lab(L_.from))}</label><input id="cap_r_from" type="date" value="${esc(R.today())}"></div>
          <div><label for="cap_r_note">${esc(lab(L_.note))}</label><input id="cap_r_note" maxlength="300" autocomplete="off"></div>
          <div class="row"><button class="full" data-act="closesheet">${esc(lab(R.X.cancel))}</button><button class="primary full" data-act="cap_ratesave">${esc(lab(R.X.save))}</button></div></div>`);
      },
      cap_ratesave: () => {
        const loc = Number(($('#cap_r_loc') || {}).value), line = ($('#cap_r_line') || {}).value, bpd = R.nnum(($('#cap_r_bpd') || {}).value), dpw = R.nnum(($('#cap_r_dpw') || {}).value), from = ($('#cap_r_from') || {}).value;
        if (!loc) return toast(lab(L_.place) + '?'); if (!(bpd > 0)) return toast(lab(R.ERR.bad_capacity)); if (!(dpw > 0 && dpw <= 7)) return toast(lab(R.ERR.bad_days)); if (!from) return toast(lab(R.ERR.bad_date));
        return act(sb.rpc('capacity_rating_set', { p_loc: loc, p_line: line ? Number(line) : null, p_batches_per_day: bpd, p_days_per_week: dpw, p_from: from, p_note: (($('#cap_r_note') || {}).value || '').trim() || null }), () => api.run());
      },
      cap_retrate: (a) => { closeSheet(); setTimeout(() => reasonSheet('rating', a.dataset.id), 0); },
      cap_rgo: () => {
        const n = (($('#cap_why') || {}).value || '').trim(); if (n.length < 3) return toast(lab(R.ERR.note_required)); const s = D.reason;
        if (s.kind === 'rating') return act(sb.rpc('capacity_rating_retire', { p_id: Number(s.id), p_note: n }), () => api.run());
        return act(sb.rpc('production_line_set', { p_id: Number(s.id), p_loc: null, p_name_bn: ((setData().lines || []).find((x) => String(x.id) === String(s.id)) || {}).name_bn, p_name_en: ((setData().lines || []).find((x) => String(x.id) === String(s.id)) || {}).name_en || null, p_active: false, p_note: n }), () => api.run());
      },
    };
  } });
})();
