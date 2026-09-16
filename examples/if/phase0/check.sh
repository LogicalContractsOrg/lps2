#!/bin/sh
# Phase 0 gate (docs/project/plans/InformPlan.md §10): every spike runs, and its event
# sequence is the one read by hand from Inform's ideal transcript.
#   examples/if/phase0/check.sh            # needs LPS_LE2_LIB for the .le half
cd "$(dirname "$0")/../../.." || exit 1
fail=0
run() {  # $1 = program, $2 = expected events file
  out=$(./lps run "$1" 2>&1 | grep '^events\|^success\|^failure' \
        | grep -v '\[command(wait)\]$\|\[end_turn\]$\|\[cmd_wait\]$')
  if [ "$out" = "$(cat "$2")" ]; then echo "ok    $1"; else echo "FAIL  $1"; echo "$out" | diff "$2" - ; fail=1; fi
}
for p in scene iqtest iqtest_c mre; do run examples/if/phase0/lps/$p.lps examples/if/phase0/expected/$p.events; done
if ./lps run examples/if/phase0/lps/iqtest_obligation.lps 2>&1 | grep -q '^failure'; then echo "ok    examples/if/phase0/lps/iqtest_obligation.lps (fails, as it must)"; else echo "FAIL  iqtest_obligation.lps should fail"; fail=1; fi
if [ -n "$LPS_LE2_LIB" ]; then
  for p in scene iqtest mre; do run examples/if/phase0/le/$p.le examples/if/phase0/expected/le_$p.events; done
else echo "skip  the Logical English half: set LPS_LE2_LIB"; fi
exit $fail
