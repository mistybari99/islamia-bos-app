#!/usr/bin/env bash
# Repeatable public web bundle builder for islamia-bos-app (GitHub Pages, root = repo root).
# Usage: make_bundle.sh [SRC_WEB_DIR] [DEST_REPO]      (defaults below)
# Never pushes. Never touches main: refuses to run unless DEST is on a non-main branch.
# Safe to run any number of times (idempotent): same source => same output bytes.
set -euo pipefail
SRC="${1:-/home/user/wt-int/web}"
DEST="${2:-/home/user/islamia-bos-app}"
SRC_REPO="$(git -C "$SRC" rev-parse --show-toplevel)"
SRC_COMMIT="$(git -C "$SRC_REPO" rev-parse --short HEAD)"
SRC_BRANCH="$(git -C "$SRC_REPO" rev-parse --abbrev-ref HEAD)"
BR="$(git -C "$DEST" rev-parse --abbrev-ref HEAD)"
[ "$BR" != "main" ] && [ "$BR" != "master" ] || { echo "ABORT: $DEST is on $BR; checkout a pages/* branch first"; exit 2; }
[ -z "$(git -C "$SRC_REPO" status --porcelain -- web)" ] || { echo "ABORT: source web/ has uncommitted changes"; exit 2; }

# 1) config.js guard: the public repo keeps its own config.js; it must be identical to the source one.
cmp -s "$SRC/config.js" "$DEST/config.js" || { echo "ABORT: config.js differs between source and public repo. Not copying. Review by hand."; diff "$SRC/config.js" "$DEST/config.js" | sed 's/eyJ[A-Za-z0-9._-]*/eyJ…/g' | head -20; exit 3; }

# 2) public-only files that must survive and are never taken from source
PROTECT_RE='^(setup-[^/]*\.html|audit-a\.html|PUBLISH_NOTES\.md|DEPLOY_CHECKLIST\.md|CNAME|\.nojekyll|\.git(/.*)?|config\.js)$'
# source files that are never published (tests, screenshots, node scripts, docs)
SKIP_RE='(^|/)(.*_test\.js|.*\.test\.js|smoke\.js|stub\.js|.*_common\.js|.*\.(png|jpg|jpeg|gif|md|sh|sql|map))$'

# 3) list publishable source files (relative paths)
LIST="$(mktemp)"; trap 'rm -f "$LIST" "$LIST.dest"' EXIT
( cd "$SRC" && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) | grep -vE "$SKIP_RE" > "$LIST" || true
# stepw_common.js is a real web file (loaded by index.html) -> allow it despite the *_common.js skip rule
grep -qx 'stepw_common.js' "$LIST" || { [ -f "$SRC/stepw_common.js" ] && echo stepw_common.js >> "$LIST"; LC_ALL=C sort -o "$LIST" "$LIST"; }
# any other .html besides index.html is not part of the app
sed -i -E '/\.html$/{/^index\.html$/!d}' "$LIST"
# node scripts must never be shipped
# (a browser file may carry the guarded UMD line "if (typeof module !== 'undefined' && module.exports) module.exports = api" for its node test: that line is not node-style)
if ( cd "$SRC" && for f in $(grep -E '\.js$' "$LIST"); do grep -vE "typeof module *!==? *['\"]undefined['\"]" "$f" | grep -qE "require\(['\"](fs|path|http|child_process)['\"]\)|^#!/usr/bin/env node|module\.exports *=" && echo "$f"; done | grep . ); then echo "ABORT: node-style file(s) in the publish list (above)"; exit 4; fi

# 4) sync: copy changed/new, remove files that vanished from source (never the protected ones)
ADD=0; CHG=0; DEL=0; SAME=0
while IFS= read -r f; do
  [ "$f" = "config.js" ] && continue
  mkdir -p "$DEST/$(dirname "$f")"
  if [ ! -e "$DEST/$f" ]; then ADD=$((ADD+1)); cp -p "$SRC/$f" "$DEST/$f"
  elif cmp -s "$SRC/$f" "$DEST/$f"; then SAME=$((SAME+1))
  else CHG=$((CHG+1)); cp -p "$SRC/$f" "$DEST/$f"; fi
done < "$LIST"
( cd "$DEST" && find . -type f -not -path './.git/*' | sed 's|^\./||' | LC_ALL=C sort ) > "$LIST.dest"
while IFS= read -r f; do
  echo "$f" | grep -qE "$PROTECT_RE" && continue
  grep -qxF "$f" "$LIST" && continue
  rm -f "$DEST/$f"; DEL=$((DEL+1)); echo "removed (gone from source): $f"
done < "$LIST.dest"

# 5) cache safety. Build id = hash of the published content (config.js excluded from rewrites, included in hash).
#    a) every local <script src> / stylesheet <link href> in index.html gets ?v=BUILD  -> old cached JS can never pair with the new index.html
#    b) sw.js VERSION = bos-sw-BUILD -> the service worker file changes, browsers install it, activate drops every older bos-sw-* cache.
BUILD="$(cd "$SRC" && while IFS= read -r f; do cat "$f"; done < "$LIST" | sha256sum | cut -c1-10)"
python3 - "$DEST" "$BUILD" <<'PY'
import re,sys
d,b=sys.argv[1:3]
p=d+'/index.html'; s=open(p,encoding='utf-8').read()
s=re.sub(r'\?v=[0-9a-f]{10}(?=")','',s)           # idempotent: strip an older stamp first
def sc(m):
    u=m.group(2)
    return m.group(0) if re.match(r'(https?:)?//',u) else '%s%s?v=%s"'%(m.group(1),u,b)
s=re.sub(r'(<script[^>]*\ssrc=")([^"]+)"',sc,s)
s=re.sub(r'(<link[^>]*rel="stylesheet"[^>]*\shref=")([^"]+)"',sc,s)
s=re.sub(r'<!-- bos-build [0-9a-f]{10} -->\n?','',s)
s=s.replace('</head>','<!-- bos-build %s -->\n</head>'%b,1)
open(p,'w',encoding='utf-8').write(s)
p=d+'/sw.js'; s=open(p,encoding='utf-8').read()
s2=re.sub(r"const VERSION = '[^']*';","const VERSION = 'bos-sw-%s';"%b,s,count=1)
assert s2!=s or ("bos-sw-%s'"%b) in s, 'sw.js VERSION line not found'
open(p,'w',encoding='utf-8').write(s2)
PY

# 6) static checks (all must pass)
FAIL=0; bad(){ echo "FAIL: $*"; FAIL=1; }
cd "$DEST"
# 6a) every local src/href in index.html exists; no duplicate script tags
python3 - <<'PY' || FAIL=1
import re,os,sys,collections
s=open('index.html',encoding='utf-8').read(); bad=0
refs=re.findall(r'<script[^>]*\ssrc="([^"]+)"',s)+re.findall(r'<link[^>]*\shref="([^"]+)"',s)
for r in refs:
    if re.match(r'(https?:)?//',r): continue
    f=r.split('?')[0]
    if not os.path.isfile(f): print('FAIL: index.html references missing file',f); bad=1
sc=[r.split('?')[0] for r in re.findall(r'<script[^>]*\ssrc="([^"]+)"',s)]
for k,v in collections.Counter(sc).items():
    if v>1: print('FAIL: duplicate <script src>',k); bad=1
print('index.html refs: %d scripts/links checked, %d scripts'%(len(refs),len(sc)))
sys.exit(bad)
PY
# 6b) syntax of every js (sw.js too); no conflict markers anywhere
for f in $(git ls-files -co --exclude-standard | grep -E '\.js$' | sort -u); do [ -f "$f" ] || continue; node --check "$f" 2>/dev/null || bad "node --check $f"; done
if grep -rnE '^(<<<<<<< |=======$|>>>>>>> )' --include='*' --exclude-dir=.git . | grep -v 'vendor/'; then bad "conflict markers (above)"; fi
# 6c) secrets. sb_publishable_ in config.js is public by design. Keyword MENTIONS in comments/docs are listed as INFO; real-looking values fail.
grep -rnIoE 'service_role|sb_secret' --exclude-dir=.git --exclude='setup-*.html' --exclude=audit-a.html --exclude=PUBLISH_NOTES.md --exclude=DEPLOY_CHECKLIST.md . | sort | uniq -c | sed 's/^/INFO keyword mention: /' || true
if grep -rnIE 'sb_secret_[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|sk_live_[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY|bot[0-9]{6,}:[A-Za-z0-9_-]{30,}' --exclude-dir=.git . | cut -c1-120; then bad "secret value (above)"; fi
if grep -rnIlE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' --exclude-dir=.git . | grep -vE '^\./(setup-|audit-a)'; then bad "JWT-like token (files above)"; fi
# any sb_publishable_ outside config.js?
grep -rnIl 'sb_publishable_' --exclude-dir=.git . | grep -v '^./config.js$' | sed 's/^/INFO publishable key also in: /' || true
# 6d) config.js still identical to source
cmp -s config.js "$SRC/config.js" || bad "config.js differs from source"

# 7) DEPLOY_CHECKLIST.md (regenerated each run; notes only)
TPL="$(dirname "$(readlink -f "$0")")/DEPLOY_CHECKLIST.tpl.md"
if [ -f "$TPL" ]; then sed -e "s/@@BUILD@@/$BUILD/g" -e "s/@@SRC_COMMIT@@/$SRC_COMMIT/g" -e "s|@@SRC_BRANCH@@|$SRC_BRANCH|g" "$TPL" > DEPLOY_CHECKLIST.md; fi

# 8) PUBLISH_NOTES.md: keep intact; insert one pointer section ONCE, right after the first line (not at the end: other branches append at the end, this avoids merge conflicts)
if ! grep -q '^## Web bundle (pages/web-bundle)' PUBLISH_NOTES.md; then
python3 - <<'PY'
s=open('PUBLISH_NOTES.md',encoding='utf-8').read()
sec="""
## Web bundle (pages/web-bundle)

The web app files at the repo root (js, css, index.html, sw.js) were refreshed from My-tools `web/` by a script that never touches `config.js`, `setup-*.html`, `audit-a.html` or this file. `index.html` loads each script and style with `?v=<build id>` and `sw.js` has a matching VERSION, so phones never mix old and new files. Details, database phase table and rollback are in `DEPLOY_CHECKLIST.md`.
"""
a,b=s.split('\n',1)
open('PUBLISH_NOTES.md','w',encoding='utf-8').write(a+'\n'+sec+b)
PY
fi

echo "source: $SRC_BRANCH @ $SRC_COMMIT   build: $BUILD"
echo "added=$ADD changed=$CHG unchanged=$SAME removed=$DEL   (config.js untouched, protected files kept)"
[ "$FAIL" = 0 ] && echo "STATIC CHECKS: PASS" || { echo "STATIC CHECKS: FAIL"; exit 5; }
