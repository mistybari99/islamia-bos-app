#!/bin/bash
# usage: PGPORT=5777 bash tests/sql/readiness/run.sh <def|rec> <dbname> [template_db]
# Builds a clone of an already-built full-chain database (TEMPLATE, default rd_base built by: PGPORT=.. ORDER=all bash tests/sql/build_fresh_db.sh rd_base)
MODE=$1; DB=$2; TPL=${3:-rd_base}; PGP=${PGPORT:-5544}
cd "$(dirname "$0")"
psql -h /tmp -p $PGP -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $TPL" 2>&1 | grep -v NOTICE
psql -h /tmp -p $PGP -U postgres -d $DB -v mode=$MODE -qAt -f rd_scenario.sql 2>&1
