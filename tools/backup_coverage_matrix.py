#!/usr/bin/env python3
"""Prints the table-by-table backup coverage matrix (Markdown) of a database that was built from the phase SQL files. READ ONLY. Python 3 + the psql client.

    python3 tools/backup_coverage_matrix.py --dsn "postgresql://postgres@/bkfull?host=/tmp&port=5544" [--out table.md]
    python3 tools/backup_coverage_matrix.py --dsn ... --check docs/BACKUP_COVERAGE.md      (exit 1 when the matrix in the file is out of date)

Per table: in the nightly backup (public._backup_tables())? in the app button "download all data" (BACKUP_TABLES in web/app.js)? why a table is left out, and a sensitivity
class. The sensitivity class is a HEURISTIC from table and column names (see classify()); the owner should read the "high" and "personal" rows once. The matrix
is computed, so it cannot drift from the schema: tests/sql builds the schema, this tool reads it.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECRET_COL = re.compile(r'(password|passwd|pin_hash|secret|token|salt|api_key|private_key)', re.I)
SECRET_OK = re.compile(r'^(tokens_(in|out)|token_[ab]|monthly_token_budget|max_output_tokens)$')
BEGIN, END = '<!-- matrix:begin -->', '<!-- matrix:end -->'

HIGH_T = re.compile(r'(salary|payroll|wage|employee|attend|shift_pay|loan|advance|benefit|(^|_)nid(_|$)|bank|pay_?req|staff_pay|(^|_)tips?(_|$))', re.I)
HIGH_C = re.compile(r'(salary|wage|(^|_)nid(_|$)|(^|_)tin(_|$)|bank_acc|bkash|nagad|account_no)', re.I)
PERS_T = re.compile(r'(customer|supplier|party|crm|inbound|web_order|message|contact|lead|birthday|loyalty|inbox|whatsapp|telegram|donor|vendor)', re.I)
PERS_C = re.compile(r'(mobile|phone|email|address|birthday|anniversary|whatsapp|full_name|customer_name|contact)', re.I)
FIN_T = re.compile(r'(sale|purchase|journal|coa|acct|cash|payment|stock|cost|price|invoice|bill|order|ledger|expense|asset|receiv|payab|tax|vat|grn|landed|refund|return|wastage|batch|recipe|production|transfer|budget|period|bank)', re.I)
CFG_T = re.compile(r'(rule|setting|form|role|grant|option|list|template|print|cfg|config|def|map|sheet|reco|policy|switch|path|brand|class|type|unit|conv|tier|category|categories|agent|provider|layout|nav|favour|threshold)', re.I)
LOG_T = re.compile(r'(audit|log|history|change|revision|corrections|attempt|run|queue|event|notif|trace|error|drill|peek)', re.I)


def classify(table, cols):
    if HIGH_T.search(table) or any(HIGH_C.search(c) for c in cols):
        return 'high (staff pay / identity)'
    if PERS_T.search(table) or any(PERS_C.search(c) for c in cols):
        return 'personal (customers, suppliers, people)'
    if FIN_T.search(table):
        return 'financial'
    if LOG_T.search(table):
        return 'log / history'
    if CFG_T.search(table):
        return 'settings'
    return 'operational'


def psql(dsn, sql, psql_cmd='psql'):
    import shlex
    p = subprocess.run(shlex.split(psql_cmd) + ['-X', '-q', '-At', '-F', '\t', '-v', 'ON_ERROR_STOP=1', '-d', dsn, '-c', sql], capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(oc.REDACT(p.stderr[:500]))
    return [ln.split('\t') for ln in p.stdout.splitlines() if ln]


def app_tables():
    with open(os.path.join(ROOT, 'web', 'app.js'), encoding='utf-8') as f:
        s = f.read()
    m = re.search(r'const BACKUP_TABLES = \[(.*?)\];', s, re.S)
    return set(re.findall(r"'([a-z0-9_]+)'", m.group(1))) if m else set()


def why_out(table, bad_cols):
    if '_secret' in table:
        return 'name contains _secret (stores a secret hash)'
    if table.startswith('ops_'):
        return 'bot-account marks (re-made after a restore; the staff manifest lists them)'
    if table in ('login_failures', 'login_attempts', 'login_throttle'):
        return 'login throttle data, re-created by use'
    if table in ('backup_runs', 'notifications', 'notification_reads'):
        return 'run-time table of the backup / notification module, re-created by the app'
    if bad_cols:
        extra = ' (the safe columns are in the staff manifest)' if table == 'attendance_devices' else ''
        return 'has secret-looking column(s): ' + ', '.join(bad_cols) + extra
    return 'not in _backup_tables() (unknown reason - look at the function)'


def build(dsn, psql_cmd='psql'):
    tabs = psql(dsn, "select c.relname, (c.relname::text = any (public._backup_tables()))::text, "
                     "(select string_agg(a.attname::text, ',' order by a.attnum) from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), "
                     "(select count(*) from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) "
                     "from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relispartition order by 1", psql_cmd)
    app = app_tables()
    rows, n_in, n_out, n_app = [], 0, 0, 0
    for name, inb, cols, ncol in tabs:
        cl = (cols or '').split(',')
        bad = [c for c in cl if SECRET_COL.search(c) and not SECRET_OK.match(c)]
        sens = classify(name, cl)
        if inb == 'true':
            n_in += 1
        else:
            n_out += 1
        inapp = name in app
        n_app += inapp
        rows.append((name, int(ncol), 'yes' if inb == 'true' else '**NO**', 'yes' if inapp else 'no',
                     '' if inb == 'true' else why_out(name, bad), 'secret' if inb != 'true' and (bad or '_secret' in name) else sens))
    head = [f'Tables in schema public: **{len(rows)}**. In the nightly backup: **{n_in}**. Left out on purpose: **{n_out}**. Also in the app button "download all data": **{n_app}** '
            f'(of {len(app)} names in its fixed list).', '',
            '| Table | Columns | Nightly backup | App button | Why left out | Sensitivity (heuristic) |', '|---|---:|---|---|---|---|']
    body = [f'| `{r[0]}` | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} |' for r in rows]
    gone = sorted(app - {r[0] for r in rows})
    tail = ['', f'Names in the app button list that are not a table of the schema (no data, the button records an error for them): {", ".join("`" + g + "`" for g in gone) or "none"}.']
    return '\n'.join(head + body + tail) + '\n', {'tables': len(rows), 'in': n_in, 'out': n_out, 'app': n_app}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--dsn', required=True)
    ap.add_argument('--out', default='')
    ap.add_argument('--check', default='')
    ap.add_argument('--psql', default=os.environ.get('BOS_PSQL', 'psql'))
    a = ap.parse_args(argv)
    md, st = build(a.dsn, a.psql)
    if a.check:
        with open(a.check, encoding='utf-8') as f:
            s = f.read()
        i, j = s.find(BEGIN), s.find(END)
        if i < 0 or j < 0:
            print('markers missing in', a.check)
            return 1
        cur = s[i + len(BEGIN):j].strip('\n')
        if cur.strip() != md.strip():
            print('the matrix in', a.check, 'is out of date: run tools/backup_coverage_matrix.py --out ... and paste it between the markers')
            return 1
        print('OK: matrix is current', st)
        return 0
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(md)
    else:
        sys.stdout.write(md)
    print(st, file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
