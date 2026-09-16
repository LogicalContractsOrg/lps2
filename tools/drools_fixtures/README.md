# Drools reader fixtures

Rule bases that `tools/drools_test.pl` runs through `src/syntax/lps_drools.pl`
and that are not examples: each exercises one construct of DRL (`or`,
`accumulate`, `insertLogical`, a comparison under `not`, Java beside a
change, a type with no `declare`, conditions the reader does not translate,
rule attributes, values computed in Java). `attributes.drl` and `values.drl`
say in their header what Drools 10 does with them.
