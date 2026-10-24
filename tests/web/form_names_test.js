// Form names and printed codes (no browser). The clean sequence (docs/FORM_SEQUENCE.md, owner decision 21 Oct 2026):
//   1. the printed codes are NN-1 (01-1 .. 41-1) plus the fixed 0-1; they equal the NEW codes in tools/numbering_map.json;
//   2. the database seed (supabase/schema.sql, frozen) still holds the OLD code of each form; old -> new is the map;
//   3. every printed form has a Bangla and an English name in the seed, and a form-kit title in web/forms*.js;
//   4. the form-kit title of each form is its short name (Bangla and English) from the map, marked 'to review';
//   5. docs/FORM_SEQUENCE.md maps each of the 41 sorted forms once, in short-name order, to NN-1.
// Run: node form_names_test.js <abs tests/web dir>
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const { REPO_DIR, WEB_DIR } = _P;

const MAP = JSON.parse(fs.readFileSync(path.join(REPO_DIR, 'tools', 'numbering_map.json'), 'utf8'));
const ROWS = MAP.form_codes.filter((r) => r.sort !== null);            // the 41 sorted forms
const FIXED = MAP.form_codes.find((r) => r.sort === null);            // 0-1
const OLD_TO_NEW = Object.fromEntries(MAP.form_codes.map((r) => [r.old, r.new]));
const NEW_CODES = ROWS.map((r) => r.new).concat([FIXED.new]).sort();

let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL: ' + m); } else console.log('PASS: ' + m); };

// 1. the printed codes are the new sequence
ok(ROWS.length === 41 && FIXED.old === '0-1' && FIXED.new === '0-1', 'the map has 41 sorted forms and the fixed 0-1');
ok(ROWS.every((r, i) => r.new === String(i + 1).padStart(2, '0') + '-1'), 'new codes are 01-1 .. 41-1 in sort order');
ok(new Set(NEW_CODES).size === 42, 'the 42 new printed codes are unique');

// 2. the database seed (frozen SQL) holds the old codes; each maps to a new code, 42 in all
const schema = fs.readFileSync(path.join(REPO_DIR, 'supabase', 'schema.sql'), 'utf8');
const i0 = schema.indexOf('insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values');
const seedEnd = schema.indexOf(';', i0);
const seedRows = [...schema.slice(i0, seedEnd).matchAll(/\('([^']+)','([^']+)','([^']*)','([^']*)','([^']*)','([^']*)',(\d+)\)/g)]
  .map((m) => ({ code: m[1], bn: m[3], mix: m[4], en: m[5] }));
const printed = seedRows.filter((r) => /^\d{2}-\d$|^0-\d$/.test(r.code));
const seedNew = printed.map((r) => OLD_TO_NEW[r.code] || r.code).sort();
ok(printed.length === 42, 'the seed has 42 printed forms (old codes)');
ok(JSON.stringify(seedNew) === JSON.stringify(NEW_CODES), 'the seed codes, mapped old -> new, are the 42 new printed codes');

// 3. names: every printed form has a Bangla and an English name in the seed, and a form-kit title
const noName = printed.filter((r) => !r.bn.trim() || !r.en.trim()).map((r) => r.code);
ok(noName.length === 0, 'every printed form has a Bangla and an English name' + (noName.length ? ' (missing: ' + noName.join(' ') + ')' : ''));
const kitSrc = fs.readdirSync(WEB_DIR).filter((f) => /^forms.*\.js$/.test(f) || f === 'formscreens.js')
  .map((f) => fs.readFileSync(path.join(WEB_DIR, f), 'utf8')).join('\n');
const kitCodes = new Set([...kitSrc.matchAll(/B\.forms\['([^']+)'\]\s*=\s*\{\s*title:/g)].map((m) => m[1]));
const noKit = ROWS.map((r) => r.new).filter((c) => !kitCodes.has(c));
ok(noKit.length === 0, 'every NN-1 form has a form-kit title' + (noKit.length ? ' (missing: ' + noKit.join(' ') + ')' : ''));

// 4. the kit title is the short name from the map (Bangla and English), to review
const titleOf = (code) => {
  const m = kitSrc.match(new RegExp("B\\.forms\\['" + code + "'\\]\\s*=\\s*\\{\\s*title:\\s*L\\(('(?:[^'\\\\]|\\\\.)*'),\\s*('(?:[^'\\\\]|\\\\.)*')(?:,\\s*'(?:[^'\\\\]|\\\\.)*')?\\)"));
  if (!m) return null;
  const unq = (q) => q.slice(1, -1).replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  return { bn: unq(m[1]), en: unq(m[2]) };
};
const wrong = ROWS.filter((r) => { const t = titleOf(r.new); return !t || t.bn !== r.bn || t.en !== r.en; }).map((r) => r.new);
ok(wrong.length === 0, 'every form-kit title is the map short name (Bangla + English)' + (wrong.length ? ' (differs: ' + wrong.join(' ') + ')' : ''));
ok(ROWS.every((r) => r.status === 'to review'), 'every short name is marked to review (owner checks the Bangla names later)');

// 5. docs/FORM_SEQUENCE.md: the mapping table (the rule file) in short-name order
const seq = fs.readFileSync(path.join(REPO_DIR, 'docs', 'FORM_SEQUENCE.md'), 'utf8');
const rows = seq.split('\n').map((l) => l.match(/^\| (\d+) \| ([^|]+?) \| ([^|]+?) \| (\d{2}-\d) \| (\d{2}-\d) \|$/))
  .filter(Boolean).map((m) => ({ no: Number(m[1]), en: m[2].trim(), bn: m[3].trim(), old: m[4], neu: m[5] }));
ok(rows.length === 41, 'mapping table has 41 sorted rows (found ' + rows.length + ')');
ok(rows.every((r, i) => r.no === i + 1), 'sort numbers run 1..41 in order');
ok(rows.every((r, i) => i === 0 || rows[i - 1].en.toLowerCase() <= r.en.toLowerCase()), 'rows are in A-Z order by English short name');
ok(rows.every((r) => OLD_TO_NEW[r.old] === r.neu), 'the table agrees with the map (old -> new)');
ok(rows.every((r) => ROWS.find((x) => x.old === r.old && x.en === r.en && x.bn === r.bn)), 'the table names agree with the map');

console.log('assert failures: ' + fails);
process.exit(fails ? 1 : 0);
