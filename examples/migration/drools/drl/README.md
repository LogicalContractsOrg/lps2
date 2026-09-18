# Drools rule bases — DRL files LPS2 opens directly

Rule bases in DRL (discount, fire alarm, insurance, shipping, traffic light)
that LPS2 converts to LPS when it opens them, without going through Logical
English; `fire-alarm.wording` says how the fire alarm's facts and changes read
in English. They are short, hand-simplified versions of Drools examples, plus
a state machine (traffic light), and lpsPlus's `migration/drools/lps_drools_test.pl`
checks what each one fires.

The reader itself (`lps_drools.pl`) is one of the two translators LPS2 loads
from the private lpsPlus repository — `src/syntax/lps_plus.pl` says where it
looks. Without a checkout these files stay what they are: a `.drl` is then not
offered in File ▸ Open, and opening one says so.

The directories beside this one are the other route: the upstream Drools
examples, with their Java fact models, translated to Logical English for LPS
by lpsPlus's reader.
