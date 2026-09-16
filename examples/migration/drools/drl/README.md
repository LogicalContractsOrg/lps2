# Drools rule bases — DRL files LPS2 opens directly

Rule bases in DRL (discount, fire alarm, insurance, shipping, traffic light)
that LPS2 converts to LPS when it opens them (src/syntax/lps_drools.pl),
without going through Logical English; `fire-alarm.wording` says how the fire
alarm's facts and changes read in English. They are short, hand-simplified
versions of Drools examples, plus a state machine (traffic light), and
tools/drools_test.pl checks what each one fires.

The directories beside this one are the other route: the upstream Drools
examples, with their Java fact models, translated to Logical English for LPS
by InsurLE2's reader.
