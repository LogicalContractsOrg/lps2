# Drools rule bases — DRL files LPS2 opens directly

Short, simplified Drools rule files (DRL, the Drools Rule Language): a
discount, a fire alarm, insurance, shipping, and a traffic light. LPS2 turns
a DRL file into an LPS program when it opens it, without Logical English.
These five files were written for LPS2. They are not Drools' own examples, and
Drools does not accept them as they are: their values have no quotation marks.
The discount, insurance and shipping rule bases, written as DRL that Drools
accepts, are under `sources/` in the twin folders beside this one.
[fire-alarm.wording](fire-alarm.wording) says how the fire alarm's facts and
changes read in English.

The reader of DRL files is part of this repository (`src/syntax/lps_drools.pl`),
and it is open source. `tools/drools_test.pl` checks what each of these files
fires. On the hosted server, sign in before you open a DRL file; the sign-in is
free.

## Start here
- [Fire alarm](fire-alarm.drl): sprinklers and an alarm that follow fires.
- [Traffic light](traffic-light.drl): a state machine.

## Try this
1. Open [the fire alarm](fire-alarm.drl). The editor shows the LPS program
   written from it.
2. Press **Run** and look at the **Timeline**: the sprinklers and the alarm
   follow the fires.
3. Choose **View ▸ The original this was converted from** to read the DRL.
4. Compare with [the Drools twin](../fire_alarm/fire_alarm.le), which goes
   through Logical English.

## More
- [Drools and LPS](/docs/user/integrations/drools): how the two routes differ.

## Disclaimer

A program translated from another system is provided **"as is", without
warranty of any kind**, express or implied, including any warranty that it is
accurate, complete or fit for a particular purpose. A translation may be
wrong: check it against its source before relying on it. It is not legal,
tax, insurance, financial or other professional advice. Its authors accept no
liability for any loss or damage arising from its use.
