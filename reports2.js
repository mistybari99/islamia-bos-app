/* Islamia BOS · Reports hub, second engine (phase21.sql): 12 more reports.
   The server owns the list (report_catalog2) and the data (report_run2 / log_report_export2). The hub (reports.js) merges the two
   catalogues and sends a report key to the function that owns it, through B.reports2. If phase21 is not installed the catalogue is
   simply empty and nothing else changes. Nothing here is a business number. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb } = A;
let KEYS = new Set(), MISSING = false;

async function catalog() {
  if (MISSING) return [];
  let r; try { r = await sb.rpc('report_catalog2'); } catch (e) { return []; }
  if (!r || r.error || !Array.isArray(r.data)) {
    // function not installed (phase21 not pasted yet): stay quiet for this session; a real error (login lost, offline) is retried
    const m = (r && r.error && (r.error.message || '')) || '';
    if (/could not find|does not exist|schema cache|404/i.test(m + ((r && r.error && r.error.code) || ''))) MISSING = true;
    return [];
  }
  KEYS = new Set(r.data.map((x) => x.key));
  return r.data;
}
const owns = (key) => KEYS.has(key);
const run = (key, flt, group, sort, page) => sb.rpc('report_run2', { p_key: key, p_filters: flt || {}, p_group: group || null, p_sort: sort || null, p_page: page || 1 });
const log = (key, kind, flt, n) => sb.rpc('log_report_export2', { p_key: key, p_kind: kind, p_filters: flt || {}, p_rows: n });

B.reports2 = { catalog, owns, run, log };
})();
