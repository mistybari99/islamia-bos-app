#!/bin/bash
# usage: run.sh <mode> <db> files...
MODE=$1; DB=$2; shift 2
cd "$(dirname "$0")"
cat 00_common.sql "$@" > /tmp/e2e_run_$DB.sql
psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -d $DB -v mode=$MODE -qAt -f /tmp/e2e_run_$DB.sql 2>&1
