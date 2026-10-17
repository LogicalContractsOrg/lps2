# The interest rate reset — the CDM Smart Contract Task Force's reset, in Logical English for LPS

A *reset* fixes the floating rate of a swap's next payment: it observes a rate
such as SOFR (the Secured Overnight Financing Rate) on the right dates and
works out the rate to pay. The Common Domain Model (CDM), the open model of
derivatives trades published by FINOS (the Fintech Open Source Foundation),
writes the reset as eight steps. Its Smart Contract Task Force calls this an
*instruction composition*: each step adds its output to a record of the
reset, and the next step reads that record.

[interest_rate_reset.le](interest_rate_reset.le) is those eight steps in
Logical English for LPS. Each step is an *action*, something the program does;
the record is a set of *fluents*, facts that hold from one moment until
something changes them. The market data arrives as *events*, things that
happen to the program from outside. The timeline of a run is then the
history of the reset: which step ran when, and what it added.

## What the program adds to the CDM

The CDM declares the function that chooses the next step,
`ResetInstructionNextStep`, and leaves its body empty. Here it has one: the
next step is the first step whose output is missing. A step that needs data
from outside waits for it. Step 5 waits for the index's entry in the ISDA
floating rate option matrix, and step 7 waits for a rate for every day
observed (the scenario *late rate*).

## The scenarios, and the CDM tests they come from

| Scenario | Reset value | What it shows | CDM test |
| --- | --- | --- | --- |
| term rate | 0.055555555 | one observation, two business days before the reset date, over a holiday | `Create_AdjustObservationDatesInstructionTest` |
| compounded | 0.0550084 | SOFR compounded over three days | `Create_CalculateResetValueInstructionTest` |
| late rate | 0.0550084 | the same, with the last rate a few cycles late |  |
| weekend | 0.0562632 | Saturday and Sunday observed at Friday's rate | both of the above |
| lookback | 0.052015 | a lookback of two business days | `Create_AdjustObservationDatesInstructionTest` |
| compounded index | 0.0580645 | an index going from 1000 to 1005 over January | `Create_CalculateResetValueInstructionTest` |
| month end | 0.0525 on 30 March | Modified Following, which stays in the month | `Create_AdjustDateInstructionTest` |
| overnight without method | none | step 5 refused at every cycle, as the CDM refuses it, and the reset waits there; *why not* names the condition | `Create_DetermineUnadjustedObservationDatesInstructionTest` |

Each value was also worked out separately, with the formulas of the CDM's
tests. `tools/finance_examples_test.pl` checks them all.

## Limits

The program follows the CDM's own scope (the opening comment of
`event-instructioncomposition-reset-func.rosetta`): Following, Preceding and
Modified Following, fixing offsets, lookbacks, and three ways of calculating.
Like the CDM, it leaves out observation period shifts, lockouts, averaging,
caps and floors. It rounds only to the nearest seventh decimal, the CDM's
default. Each trade has one holiday calendar where the CDM allows three. The
calculation period is a fact of the trade, because the CDM's
`CalculationPeriod` is code outside the model.

## Sources

`sources/` holds the CDM's reset (`rosetta/`, in Rune, the CDM's language),
the functions the steps call (`rosetta/helper-functions.rosetta`), and the Java
tests (`tests/`). They come from FINOS `common-domain-model`, branch master at
commit 830b53b (16 October 2026, version 8.0.0-dev.11),
https://github.com/finos/common-domain-model. The CDM is published under the
Community Specification License 1.0 (`sources/LICENSE.md`), which asks that a
derived work name the material, its version and its source, as this paragraph
does.

## Disclaimer

This program is an example, provided **"as is", without warranty of any
kind**. It may differ from the CDM: check it against the CDM before relying on
it. It is not financial, legal or other professional advice.
