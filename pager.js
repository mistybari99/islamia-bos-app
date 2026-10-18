/* Islamia BOS · paging helper. The server cuts every list at 1000 rows, so any query that can grow past that (items: the dictionary adds 1312) must be read in pages.
   BOS_ALL(query) takes a Supabase query that is ordered in a stable way and returns {data, error} with ALL rows. Loaded first (before app.js). */
(() => {
'use strict';
window.BOS_ALL = async (q, size = 1000) => {
  const out = [];
  for (let from = 0; from < 1000000; from += size) {
    const r = await q.range(from, from + size - 1);
    if (!r || r.error) return r && r.error ? { data: null, error: r.error } : r;
    const rows = r.data || []; out.push(...rows);
    if (rows.length < size) break;
  }
  return { data: out, error: null };
};
})();
