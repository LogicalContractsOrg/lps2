#!/bin/sh
# The phase-4 gate (tools/inform_test.pl), one Inform program per process:
# eleven translations through LE2 in one SWI-Prolog process want more memory
# than a small container has, and each program is independent anyway.
#   LPS_LE2_LIB=/LogicalEnglish2 tools/inform_test.sh
cd "$(dirname "$0")/.." || exit 1
fail=0; n=0; ok=0
# the sentence-by-sentence regressions first
reg=$(./myswipl.sh -q -g "consult('tools/inform_test.pl')" -g "inform_test:regressions" -t halt 2>&1 \
  | grep "  ok  \|  FAIL\|regression checks")
echo "$reg"
if echo "$reg" | grep -q "  FAIL" || ! echo "$reg" | grep -q "regression checks"; then fail=1; fi
for name in ImplicitConnections NothingAsTerm NegatedRP NPCGoingTwistily Regarding \
            GoingSouthIn TakingInventory C9SceneEndSequence IQTest BostonCream MRE; do
  n=$((n+1))
  if ./myswipl.sh -q -g "consult('tools/inform_test.pl')" -g "inform_test:one('$name')" -t halt 2>&1 \
       | grep -v "redefined_system_template\|unused_template\|unconsumed_facts\|^Warning" | grep "  ok  \|  FAIL"; then
    ok=$((ok+1))
  else
    echo "  FAIL  $name (did not report)"; fail=1
  fi
done
echo "=== $ok/$n Inform programs translate, run and hold their assertions ==="
[ $ok -eq $n ] || fail=1
exit $fail
