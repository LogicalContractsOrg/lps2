#!/bin/bash
# build.sh — the whole of LPS2 as a static site.
#
# What comes out of wasm/dist/ is a directory a static host serves as it is:
# the IDE, the landing page, the documentation, the SWI-Prolog WebAssembly
# runtime, and one payload file holding LPS2's Prolog, the examples and the
# corpus. There is no server in it. Deploy it to Vercel with
#
#     cd wasm/dist && vercel deploy --prod
#
# or serve it from anywhere else that serves files (docs/dev/deploy-vercel.md).
#
# The fly.io deployment is untouched by any of this: the Dockerfile, fly.toml
# and buildPush.sh are the same as they were.
#
#   ./wasm/build.sh                 the public build
#   ./wasm/build.sh --with-le       ...and the vendored Logical English, so
#                                   that .le programs compile in the page
#   ./wasm/build.sh --skip-ui       reuse src/ide/dist as it stands
#   ./wasm/build.sh --out DIR       somewhere other than wasm/dist
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/wasm/dist"
WITH_LE=0
PRIVATE=0
SKIP_UI=0
PORT=3199
SWIPL_WASM_VERSION="8.1.3"

while [ $# -gt 0 ]; do
    case "$1" in
        --with-le) WITH_LE=1 ;;
        --private) PRIVATE=1 ;;
        --skip-ui) SKIP_UI=1 ;;
        --out)     shift; OUT="$1" ;;
        --port)    shift; PORT="$1" ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

SWIPL="$ROOT/myswipl.sh"
[ -x "$SWIPL" ] || SWIPL="swipl"

#  One clean-up for the whole script, installed once: a second `trap … EXIT`
#  replaces the first, so anything registered later would otherwise be the
#  only thing that ran.
TMPNPM=""; LISTFILE=""; LOG=""; SERVER_PID=""
cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$TMPNPM" 2>/dev/null
    rm -f "$LISTFILE" "$LOG" 2>/dev/null
    return 0
}
trap cleanup EXIT

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "LPS2 → WebAssembly (out: $OUT)"
rm -rf "$OUT"
mkdir -p "$OUT/lps-wasm/swipl"

# ---------------------------------------------------------------------------
# 1. the IDE, built as it is for the server image
# ---------------------------------------------------------------------------
if [ "$SKIP_UI" = "0" ]; then
    say "1/8  Building the IDE"
    npm --prefix ui install --no-audit --no-fund
    npm --prefix ui run build
else
    say "1/8  IDE: reusing src/ide/dist (--skip-ui)"
fi
[ -f src/ide/dist/index.html ] || { echo "src/ide/dist is missing: build the IDE first" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. the SWI-Prolog WebAssembly runtime
#
# ui/static/swipl/ already carries a copy (M11's "Deploy as WASM" pages load
# it), so that is the first place to look: one version in the repository, used
# by both.
# ---------------------------------------------------------------------------
say "2/8  SWI-Prolog runtime (WebAssembly)"
if [ -f ui/static/swipl/swipl-web.wasm ]; then
    echo "  vendored: ui/static/swipl"
    cp ui/static/swipl/swipl-web.* "$OUT/lps-wasm/swipl/"
else
    TMPNPM="$(mktemp -d)"
    ( cd "$TMPNPM" && npm install --silent --no-audit --no-fund "swipl-wasm@$SWIPL_WASM_VERSION" >/dev/null )
    cp "$TMPNPM/node_modules/swipl-wasm/dist/swipl/swipl-web.js" \
       "$TMPNPM/node_modules/swipl-wasm/dist/swipl/swipl-web.wasm" \
       "$TMPNPM/node_modules/swipl-wasm/dist/swipl/swipl-web.data" "$OUT/lps-wasm/swipl/"
    echo "  swipl-wasm@$SWIPL_WASM_VERSION from npm"
fi

# ---------------------------------------------------------------------------
# 3. the payload: what the worker's file system will hold
# ---------------------------------------------------------------------------
say "3/8  Payload"
#  The shims' autoload index: a predicate called without an explicit import is
#  found by the autoloader, and the autoloader only looks in library
#  directories that have an INDEX.pl. Generated here rather than committed, so
#  it cannot fall behind the shims.
"$SWIPL" -q -g "make_library_index('wasm/shims'), make_library_index('wasm/shims/http'), halt." 2>/dev/null || true
LE_OPT=""
if [ "$WITH_LE" = "1" ]; then
    if [ ! -f vendor/le2/le_service.pl ]; then
        echo "--with-le, but vendor/le2 holds no le_service.pl." >&2
        echo "  run  tools/vendor_le2.sh /path/to/LogicalEnglish2  first." >&2
        exit 1
    fi
    #  vendor/le2 is a copy of another repository, made from whatever checkout
    #  was to hand. If that one had the private grammar extensions linked in,
    #  they were copied too — and this build is about to be published.
    PRIVATE_IN_VENDOR=""
    for f in le_extensions.pl le_importers.pl; do
        [ -f "vendor/le2/$f" ] && PRIVATE_IN_VENDOR="$PRIVATE_IN_VENDOR $f"
    done
    if [ -n "$PRIVATE_IN_VENDOR" ] && [ "$PRIVATE" = "0" ]; then
        echo "vendor/le2 contains private Logical English files:$PRIVATE_IN_VENDOR" >&2
        echo "  These come from a checkout with the proprietary extensions linked in," >&2
        echo "  and this build is a public static site. Re-vendor from a checkout" >&2
        echo "  without them, delete those files from vendor/le2/, or pass --private" >&2
        echo "  if this deployment is not public." >&2
        exit 1
    fi
    [ -n "$PRIVATE_IN_VENDOR" ] && echo "  ⚠ --private: publishing$PRIVATE_IN_VENDOR. Do NOT deploy this publicly."
    LE_OPT="[le(true)]"
    echo "  including the vendored Logical English"
fi
LISTFILE="$(mktemp)"
if [ -n "$LE_OPT" ]; then
    "$SWIPL" -q -g "use_module('wasm/pack'), print_payload_files($LE_OPT), halt." 2>/dev/null > "$LISTFILE"
else
    "$SWIPL" -q -g "use_module('wasm/pack'), print_payload_files, halt." 2>/dev/null > "$LISTFILE"
fi
[ -s "$LISTFILE" ] || { echo "wasm/pack.pl listed no files" >&2; exit 1; }
node wasm/runtime/mkpayload.mjs "$LISTFILE" "$ROOT" "$OUT/lps-wasm/payload.bin"

# ---------------------------------------------------------------------------
# 4. the pages the server renders, fetched from the server that renders them
#
# The landing page and the documentation shells are Prolog (lps_http.pl).
# Rather than write them a second time in HTML, the build starts the real
# server and saves what it answers — so the example tree on the landing page
# is the one this build actually carries.
# ---------------------------------------------------------------------------
say "4/8  Server-rendered pages"
LOG="$(mktemp)"
"$SWIPL" -q -g "consult('src/lps.pl')" -g "lps_cli:main(['ide','--port','$PORT'])" -t halt > "$LOG" 2>&1 &
SERVER_PID=$!

for i in $(seq 1 60); do
    if curl -fsS -m 2 "http://localhost:$PORT/lpsapi/status" >/dev/null 2>&1; then break; fi
    sleep 1
done
curl -fsS -m 30 "http://localhost:$PORT/lpsapi/status" >/dev/null || {
    echo "the export server did not start; its output:" >&2; tail -20 "$LOG" >&2; exit 1; }

curl -fsS -m 60 "http://localhost:$PORT/" -o "$OUT/index.html"
echo "  / → index.html"

#  One shell per document: each carries its own `window.LPS_DOC`, which is
#  what tells the viewer which Markdown to fetch.
DOCS=0
while read -r MD; do
    NAME="${MD#docs/}"; NAME="${NAME%.md}"
    DEST="$OUT/docs/$NAME.html"
    mkdir -p "$(dirname "$DEST")"
    if curl -fsS -m 30 "http://localhost:$PORT/docs/$NAME" -o "$DEST"; then DOCS=$((DOCS+1)); fi
done < <(cd "$ROOT" && find docs/user -name '*.md' | sort)
#  …and the search page, which is a shell like the others but is not a
#  document: it searches the documents client-side, out of nav.json and
#  /docs-raw/ (ui/static/docs-extras.js), so it needs no server either.
if curl -fsS -m 30 "http://localhost:$PORT/docs/search" -o "$OUT/docs/search.html"; then DOCS=$((DOCS+1)); fi
echo "  $DOCS documentation pages"
kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

# ---------------------------------------------------------------------------
# 5. the IDE's own files, and the documents they fetch
# ---------------------------------------------------------------------------
say "5/8  Pages and assets"

#  copy_tree <src> <dest> [tar options...]
#
#  Copies a directory, and never follows a symbolic link out of it. Nothing
#  copied below is linked today; the guard is here because the equivalent
#  build in the Logical English repository would publish 576 kB of a private
#  repository through one (`web_extras/insurML2browse`), and the failure mode
#  is not one to leave to vigilance. It says which links it skipped.
copy_tree() {
    local src="$1" dest="$2"; shift 2
    local excludes=() link
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        excludes+=( --exclude="${link#./}" )
        echo "  skipped symbolic link: $src/${link#./}"
    done < <(cd "$src" && find . -name node_modules -prune -o -type l -print 2>/dev/null)
    mkdir -p "$dest"
    tar -C "$src" -cf - "${excludes[@]}" "$@" . | tar -C "$dest" -xf -
}
#  Flat, as the server serves them — the IDE's index.html asks for `./app.js`,
#  and at /ide that resolves to the site root. `swipl/` is left out: the same
#  three files are already under /lps-wasm/, and vercel.json points /swipl/ at
#  them rather than shipping 4 MB twice.
#
#  Two index.html files want the same name, so they do not get it: the landing
#  page keeps it (a visitor arrives at /), and the IDE's becomes ide.html,
#  which /ide rewrites to.
LANDING="$(mktemp)"
mv "$OUT/index.html" "$LANDING"
copy_tree src/ide/dist "$OUT" --exclude=./swipl
mv "$OUT/index.html" "$OUT/ide.html"
mv "$LANDING" "$OUT/index.html"
chmod 644 "$OUT/index.html"

#  The documents themselves, which the shells fetch from /docs-raw/…
mkdir -p "$OUT/docs-raw"
copy_tree docs/user "$OUT/docs-raw/user"
#  …and everything in docs/user that is *not* a document: the table of
#  contents the Help menu reads, and the pictures, which a document's own
#  `![…](../images/x.png)` resolves under /docs/user/. They are real files, so
#  the host serves them before it reaches the rewrite that turns a name into a
#  shell page.
copy_tree docs/user "$OUT/docs/user" --exclude='*.md'

#  /telemetry.js is a script the server renders (Sentry, when it is
#  configured). There is no server here and nothing to report to: an empty
#  file keeps the pages' <script src="/telemetry.js"> from 404ing.
printf '/* no telemetry in the WebAssembly build */\n' > "$OUT/telemetry.js"

# ---------------------------------------------------------------------------
# 6. the browser runtime and the deployment's own settings
# ---------------------------------------------------------------------------
say "6/8  Browser runtime"
cp wasm/runtime/boot.js wasm/runtime/worker.js "$OUT/lps-wasm/"

#  `-c safe.directory`: in a container the checkout is often owned by another
#  user, and git then refuses to read it — which would stamp every build
#  "unknown@unknown" rather than the revision it came from.
GIT="git -C $ROOT -c safe.directory=$ROOT"
GIT_HASH=$($GIT rev-parse --short HEAD 2>/dev/null || echo unknown)
GIT_BRANCH=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
BUILD_INFO="${GIT_BRANCH}@${GIT_HASH} (WebAssembly, $(date -u +%Y-%m-%dT%H:%M:%SZ))"
LE_FLAG=false
[ "$WITH_LE" = "1" ] && LE_FLAG=true
cat > "$OUT/lps-wasm/config.js" <<EOF
/* The deployment's own settings. Edited in place — it is the one file here
 * that is not a build artefact in spirit, so that a proxy can be turned on or
 * off without rebuilding the pages. */
window.LPS_WASM_CONFIG = {
    base: '/lps-wasm/',
    build: '${BUILD_INFO}',
    /* Whether the payload carries a Logical English: the IDE asks, and does
     * not offer to open a .le when the answer is no. */
    le: ${LE_FLAG},
    /* A same-origin address that will forward a request this page may not
     * make itself — a model's endpoint, say. Vercel deployments get one at
     * /api/proxy (wasm/api/proxy.js); '' turns the outbound half off. */
    proxy: '/api/proxy',
    banner: true
};
EOF

node wasm/runtime/inject.mjs "$OUT"

# ---------------------------------------------------------------------------
# 7. the host's own configuration
# ---------------------------------------------------------------------------
say "7/8  Host configuration"
#  The redirects a document's old address needs (doc_moved/2 in lps_http.pl):
#  a link printed a year ago still has to land somewhere, and on the server
#  that is a 301. Asked of the Prolog rather than listed here, so the two
#  cannot disagree.
"$SWIPL" -q -g "consult('src/lps.pl'), forall(lps_http:doc_moved(O,N), format('~w ~w~n',[O,N])), halt." \
    2>/dev/null > "$OUT/.doc-redirects" || true
node wasm/runtime/mkvercel.mjs "$OUT"
rm -f "$OUT/.doc-redirects"
mkdir -p "$OUT/api"
cp wasm/api/*.js "$OUT/api/" 2>/dev/null || true

say "8/8  Done"
SIZE=$(du -sh "$OUT" | cut -f1)
cat <<EOF
  $OUT ($SIZE)
  Try it locally:   node wasm/runtime/serve.mjs "$OUT" 8080   →  http://localhost:8080/ide.html
  Deploy to Vercel: (cd "$OUT" && vercel deploy --prod)
  The instructions, in full:  docs/dev/deploy-vercel.md
EOF
