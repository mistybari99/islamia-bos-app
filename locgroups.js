/* Islamia BOS · location groups (UI only: no data is changed, no table is added).
   Four groups, in this order: Main Showroom, Branch, Production House, Warehouse. A place that fits none of them is
   listed under Unclassified, and is never guessed. The group comes from fields that already exist:
     kind = showroom and hub_functions = true  -> Main Showroom
     kind = showroom, hub_functions = false    -> Branch (without the flag: unit_kind branch or site)
     kind = factory                            -> Production House
     kind = godown                             -> Warehouse
     kind = hub | online | other | none        -> Unclassified
   The four English group names are the owner's. The Bangla group names are proposals: to review by the owner.
   Used by the location picker (attendance, attendance register), the Locations list and the places of a business. */
(function () {
  'use strict';
  const B = (window.BOS = window.BOS || {});
  const GROUPS = [
    { key: 'main', en: 'Main Showroom', bn: 'মেইন শোরুম' },
    { key: 'branch', en: 'Branch', bn: 'শাখা' },
    { key: 'production', en: 'Production House', bn: 'প্রোডাকশন হাউস' },
    { key: 'warehouse', en: 'Warehouse', bn: 'ওয়্যারহাউস' },
    { key: 'unclassified', en: 'Unclassified', bn: 'শ্রেণি ঠিক হয়নি' },
  ];
  const classify = (l) => {
    if (!l || typeof l !== 'object') return 'unclassified';
    if (l.kind === 'showroom') {
      if (l.hub_functions === true) return 'main';
      if (l.hub_functions === false) return 'branch';
      return l.unit_kind === 'branch' || l.unit_kind === 'site' ? 'branch' : 'unclassified'; // a place list without the hub flag
    }
    if (l.kind === 'factory') return 'production';
    if (l.kind === 'godown') return 'warehouse';
    return 'unclassified';
  };
  // groups in order; a group with no place is left out (Unclassified only when it has a place)
  const grouped = (locs) => GROUPS.map((g) => ({ key: g.key, en: g.en, bn: g.bn, items: (locs || []).filter((l) => classify(l) === g.key) }))
    .filter((g) => g.items.length > 0);
  const title = (g) => (B.L && B.lab ? B.lab(B.L(g.bn, g.en)) : g.en);
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  // <option>s with one <optgroup> per group. The option values are the place ids, as before.
  const optionsHTML = (locs, selected, nameOf, allLabel) => {
    const name = typeof nameOf === 'function' ? nameOf : (l) => l.name_en || l.name_bn || l.code || String(l.id);
    const head = allLabel === undefined ? '' : `<option value="">${esc(allLabel)}</option>`;
    return head + grouped(locs).map((g) => `<optgroup label="${esc(title(g))}">${g.items.map((l) =>
      `<option value="${esc(l.id)}" ${String(l.id) === String(selected) ? 'selected' : ''}>${esc(name(l))}</option>`).join('')}</optgroup>`).join('');
  };
  // a list of location cards with a heading per group; cardOf(l) returns the HTML of one place
  const listHTML = (locs, cardOf) => grouped(locs).map((g) =>
    `<section class="lg-group" data-group="${esc(g.key)}"><h3 class="lg-h">${esc(title(g))} <span class="muted">${g.items.length}</span></h3>${g.items.map(cardOf).join('')}</section>`).join('');
  B.locGroups = { GROUPS, classify, grouped, title, optionsHTML, listHTML };
  try { // headings of the groups (small, both themes: colours come from the theme tokens)
    if (!document.getElementById('lg-css')) {
      const st = document.createElement('style'); st.id = 'lg-css';
      st.textContent = '.lg-group{margin-top:6px}.lg-h{font-size:.95rem;margin:12px 0 6px;color:var(--muted,#5b6070);overflow-wrap:anywhere}';
      document.head.appendChild(st);
    }
  } catch (e) { /* no document (tests in node): nothing to style */ }
})();
