#!/bin/bash
# vendor_lpsplus.sh — put lpsPlus's two LPS2 translators into vendor/lpsplus/,
# for the image.
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
# *private* one, so it must not land in this repository's history. An image
# built without this step is a public LPS2 — everything works except those two
# doors, which say what is missing.
set -e

cd "$(dirname "$0")/.."
PLUS="${1:-${LPS_PLUS_DIR:-../lpsPlus}}"
OUT="vendor/lpsplus"

FILES="migration/solidity/lps_solidity.pl migration/drools/lps_drools.pl"

missing=""
for f in $FILES; do
    [ -f "$PLUS/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "no lpsPlus at $PLUS (missing:$missing)." >&2
    echo "usage: tools/vendor_lpsplus.sh /path/to/lpsPlus" >&2
    exit 1
fi

echo "vendoring the lpsPlus translators from $PLUS"
for f in $FILES; do
    mkdir -p "$OUT/$(dirname "$f")"
    cp "$PLUS/$f" "$OUT/$f"
    echo "  $f"
done
