#!/bin/bash
# vendor_lpsplus.sh — put what LPS2 uses of the private lpsPlus repository
# into vendor/lpsplus/, for the image: the sign-in and the licences table
# (accounts/), the sector pages (docs/sales/pages/) and the unlisted examples
# (examples/private/).
#
#   tools/vendor_lpsplus.sh [/path/to/lpsPlus]
#
# No translator comes from there any more: Deploy as Solidity and the DRL
# front end are this repository's own (src/syntax/), and the translators of
# other systems are Logical English's (its migration/, which
# tools/vendor_le2.sh copies).
#
# The image looks for the copy at vendor/lpsplus (LPS_PLUS_DIR in the
# Dockerfile), in the layout the checkout has, so nothing else has to know
# where it came from.
#
# vendor/lpsplus/ is gitignored: it is a copy of another repository, and a
# *private* one — with the licences and passwords tables in it — so it must
# not land in this repository's history, nor in the static build. An image
# built without this step is a public LPS2: every visitor is anonymous, and
# everything in this repository works.
set -e

cd "$(dirname "$0")/.."
PLUS="${1:-${LPS_PLUS_DIR:-../lpsPlus}}"
OUT="vendor/lpsplus"

REQUIRED="accounts/lc_accounts.pl"

missing=""
for f in $REQUIRED; do
    [ -f "$PLUS/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "no lpsPlus at $PLUS (missing:$missing)." >&2
    echo "usage: tools/vendor_lpsplus.sh /path/to/lpsPlus" >&2
    exit 1
fi

#  Everything under those three folders that git knows about or would add.
#  accounts/ is the sign-in shared with Logical English's server and the
#  licences table. examples/private/ holds the unlisted examples, which open
#  by their exact name only (lps_api.pl, private_example_dir/1). The rest of
#  lpsPlus's examples are not copied.
echo "vendoring lpsPlus (sign-in, licences, sector pages, unlisted examples) from $PLUS"
rm -rf "$OUT"
mkdir -p "$OUT"
n=0
while IFS= read -r f; do
    [ -f "$PLUS/$f" ] || continue
    mkdir -p "$OUT/$(dirname "$f")"
    cp "$PLUS/$f" "$OUT/$f"
    n=$((n+1))
done < <(git -c safe.directory='*' -C "$PLUS" ls-files --cached --others --exclude-standard -- accounts docs/sales/pages examples/private)
echo "  $n files, $(du -sh "$OUT" | cut -f1)"
