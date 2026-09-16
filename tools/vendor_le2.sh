#!/bin/bash
# vendor_le2.sh — put a *minimal* Logical English into vendor/le2/, for the image.
#
#   tools/vendor_le2.sh [/path/to/LogicalEnglish2]
#
# Since M8f, LPS2 compiles Logical English by loading LE2's `le_service.pl` into
# its own process (docs/le_lps_interface.md §3.5). A deployment that is meant to
# run `.le` programs therefore needs those sources *in the image* — and only
# those: not the LE2 editor, not its web API, not its own examples corpus.
#
# What "minimal" means is not a list somebody maintains here. The script loads
# `le_service.pl` in a throw-away SWI-Prolog and asks it which files it actually
# consulted, so the set cannot go stale when LE2 moves a module. To that it adds
# the data those modules read at run time — `i18n/*.csv`, the keyword tables —
# and LE2's seventeen `examples/lps/*.le`, which are the Logical English entries in
# the IDE's example list.
#
# vendor/le2/ is gitignored: it is a copy of another repository, and copies of
# other repositories do not belong in this one's history. Re-run the script when
# the LE2 checkout moves.
set -e

cd "$(dirname "$0")/.."
LE2="${1:-${LPS_LE2_LIB:-${LPS_LE2_DIR:-/LogicalEnglish2}}}"
OUT="vendor/le2"

if [ ! -f "$LE2/le_service.pl" ]; then
    echo "no LE2 at $LE2 (looking for le_service.pl)." >&2
    echo "usage: tools/vendor_le2.sh /path/to/LogicalEnglish2" >&2
    exit 1
fi

echo "vendoring Logical English from $LE2"

#  Which files loading le_service.pl actually needs, asked of the loader.
FILES=$(./myswipl.sh -q \
    -g "load_files('$LE2/le_service.pl',[if(not_loaded),silent(true)])" \
    -g "forall(( source_file(F), atom_concat('$LE2/', R, F) ), format('~w~n',[R]))" \
    -t halt 2>/dev/null | sort -u)

if [ -z "$FILES" ]; then
    echo "loading le_service.pl produced no file list — is $LE2 a working checkout?" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

for f in $FILES; do
    mkdir -p "$OUT/$(dirname "$f")"
    cp "$LE2/$f" "$OUT/$f"
done

#  The data the modules read at run time, and the LE examples the IDE lists.
cp -r "$LE2/i18n" "$OUT/i18n"
if [ -d "$LE2/examples/lps" ]; then
    mkdir -p "$OUT/examples"
    cp -r "$LE2/examples/lps" "$OUT/examples/lps"
fi

#  Where it came from, for whoever finds this directory in an image.
{
    echo "Logical English, vendored for LPS2 (docs/le_lps_interface.md §3.5)."
    echo "Source: $LE2"
    if git -C "$LE2" rev-parse --short HEAD >/dev/null 2>&1; then
        echo "Revision: $(git -C "$LE2" rev-parse --short HEAD) on $(git -C "$LE2" rev-parse --abbrev-ref HEAD)"
    fi
    echo "Vendored: $(date -u +%Y-%m-%dT%H:%M:%SZ) by tools/vendor_le2.sh"
    echo
    echo "This is a subset: the language service and its data, not LE2's editor"
    echo "or web API. Do not edit it here — edit the checkout and re-run the"
    echo "script."
} > "$OUT/VENDORED.txt"

#  It has to load from *this* directory, which is the thing that goes wrong:
#  LE2 used to resolve two paths against the working directory.
if ./myswipl.sh -q -g "load_files('$OUT/le_service.pl',[if(not_loaded),silent(true)])" \
       -g "le_service:le_service_version(V), format('le_service ~w~n',[V])" \
       -t halt 2>/dev/null | grep -q le_service; then
    echo "vendored $(echo "$FILES" | wc -l | tr -d ' ') sources + i18n into $OUT/ — it loads"
else
    echo "WARNING: $OUT/le_service.pl did not load" >&2
    exit 1
fi

du -sh "$OUT"
