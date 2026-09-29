#!/bin/bash
# vendor_lpsplus.sh — put what LPS2 uses of lpsPlus into vendor/lpsplus/, for
# the image: its two LPS2 translators, the sign-in and the licences table
# (accounts/), and the translators of other systems (migration/).
#
#   tools/vendor_lpsplus.sh [/path/to/lpsPlus]
#
# Deploy as Solidity (`lps_solidity.pl`) and the DRL front end (`lps_drools.pl`)
# are LPS2's, but they live in the private lpsPlus repository — see
# src/syntax/lps_plus.pl, which loads them, for why. A deployment that is meant
# to offer those two doors therefore needs the files *in the image*, the same
# way `.le` needs vendor/le2 (tools/vendor_le2.sh).
#
# The image looks for them at vendor/lpsplus (LPS_PLUS_DIR in the Dockerfile),
# in the same layout they have in the checkout, so nothing else has to know
# where they came from.
#
# vendor/lpsplus/ is gitignored: it is a copy of another repository, and a
# *private* one — with the licences and passwords tables in it — so it must
# not land in this repository's history, nor in the static build. An image
# built without this step is a public LPS2 — everything works except those two
# doors, which say what is missing.
set -e

cd "$(dirname "$0")/.."
PLUS="${1:-${LPS_PLUS_DIR:-../lpsPlus}}"
OUT="vendor/lpsplus"

REQUIRED="migration/solidity/lps_solidity.pl migration/drools/lps_drools.pl accounts/lc_accounts.pl"

missing=""
for f in $REQUIRED; do
    [ -f "$PLUS/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "no lpsPlus at $PLUS (missing:$missing)." >&2
    echo "usage: tools/vendor_lpsplus.sh /path/to/lpsPlus" >&2
    exit 1
fi

#  Everything under accounts/ and migration/ that git knows about or would
#  add — not the gitignored caches of fetched sources and tools (gigabytes).
#  accounts/ is the sign-in shared with Logical English's server and the
#  licences table; migration/ holds the two translators above AND the
#  translators of other systems that the vendored Logical English offers in
#  File ▸ Open (its le_plus.pl finds them here through LPS_PLUS_DIR).
echo "vendoring lpsPlus (sign-in, licences, translators) from $PLUS"
rm -rf "$OUT"
mkdir -p "$OUT"
n=0
while IFS= read -r f; do
    [ -f "$PLUS/$f" ] || continue
    mkdir -p "$OUT/$(dirname "$f")"
    cp "$PLUS/$f" "$OUT/$f"
    n=$((n+1))
done < <(git -c safe.directory='*' -C "$PLUS" ls-files --cached --others --exclude-standard -- accounts migration)
echo "  $n files, $(du -sh "$OUT" | cut -f1)"
