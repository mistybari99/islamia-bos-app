#!/bin/bash
# NOTE (23 Oct 2026): the header below describes the 20 Oct plan (live state = phases up to 103). The union merge is done and the chain on Main-Img runs to phase 546;
# the script is a lost-tag check from the canonical-order point 'phase103 pasted' to the last phase (split fixed 23 Oct, see below). The live project is being replaced by a new clean project (docs/NEW_PROJECT_SETUP.md).
# Tag-loss check for the pending phases: build the owner's live state (everything in paste_order.env up to phase103), then paste the later phases one by one in canonical order,
# snapshot md5(pg_get_functiondef) + bosNN tags of every public function after each phase (tests/sql/fn_snapshot.sh) and report lost tags (tools/tag_loss.py).
# usage: bash tests/sql/tag_loss_check.sh [outdir]      exit 0 = no tag lost between the phase103 baseline and the last phase
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}; OUT=${1:-$(mktemp -d)}; mkdir -p "$OUT"
. "$HERE/paste_order.env"
# Split the CANONICAL order (paste_order.env) at phase103: BASE = everything up to and including phase103 in that order, LATER = the rest, in that order.
# (23 Oct 2026 fix: the old split was by phase NUMBER, but the merged order pastes 506..525 before 100..103, so every later phase hit its own
#  "needs phases 72..103 first" guard and the run reported 8 tags as lost that the real chain keeps.)
BASE=""; LATER=""; SEEN103=0; for f in $FOUNDATION $NEW; do [ -f "$REPO/supabase/$f.sql" ] || continue; n=${f#phase}; if [ $SEEN103 -eq 0 ]; then BASE="$BASE $f"; [ "$f" = "phase103" ] && SEEN103=1; else LATER="$LATER $n"; fi; done
DB=tl_$$; bash "$HERE/final_build.sh" $DB "$(echo $BASE)" > "$OUT/build.log" 2>&1; grep -qx "built $DB" "$OUT/build.log" || { echo "build failed, see $OUT/build.log"; exit 2; }
bash "$HERE/fn_snapshot.sh" $DB "$OUT/s103.tsv"; STAGES="103"
for n in $LATER; do
  psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -d $DB -q -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase$n.sql" 2>&1 | grep -E "ERROR" ; bash "$HERE/fn_snapshot.sh" $DB "$OUT/s$n.tsv"; STAGES="$STAGES $n"
done
psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -q -c "drop database $DB" 2>/dev/null
python3 "$REPO/tools/tag_loss.py" "$OUT" $STAGES | tee "$OUT/report.txt"; exit ${PIPESTATUS[0]}
