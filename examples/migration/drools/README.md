# Drools twins (Phase 2e)

Twins of the Drools examples. Drools is a rule engine: rules fire when facts
are added to its working memory. In the twin, adding, changing or removing a
fact is an event in a world, with the change it causes. Each rule base has one
folder: the twin, a ledger that says what was translated and how, and under
`sources/` the Drools rules, the Java classes they are written against, and
what Drools did when it ran them. The twins are generated: change the
translator, not the files.

## Start here
- [Fire alarm](fire_alarm/fire_alarm.le): fires start, sprinklers turn on and
  the alarm sounds, then the fires are put out.
- [Discount](discount/discount.le): customer discounts. Its
  [timeless reading](discount/discount_decision.le) is a decision with no time.
- [Shipping](shipping/shipping.le) and [insurance](insurance/insurance.le):
  rules that price an order and a policy.
- [DRL files](drl/): Drools rule files that LPS2 opens directly.

## Try this
1. Open [the fire alarm](fire_alarm/fire_alarm.le) and press **Run**.
2. On the **Timeline**, fires start at cycle 11. At cycle 12 the sprinklers
   turn on and the alarm goes on; at cycle 22, after the fires are put out,
   they turn off.
3. Right-click the alarm's event and read which rule made it happen.
4. Read the comment above the scenario: the working memory Drools ended with.
   It is the twin's last state.

## More
- [Drools and LPS](/docs/user/integrations/drools): the two ways a DRL file
  comes into LPS2, and what each reads.
- [Drools](https://www.drools.org/), the rule engine.

## Disclaimer

A twin is written by a translator, and it is provided **"as is", without
warranty of any kind**, express or implied, including any warranty that it is
accurate, complete or fit for a particular purpose. A translation may be
wrong: check a twin against its source before relying on it. A twin is not
legal, tax, insurance, financial or other professional advice. Its authors
accept no liability for any loss or damage arising from its use. Every twin
repeats this notice in its opening comment.
