# Checking the record of a trade's life — a post-trade workflow, checked in Logical English for LPS

After a derivatives trade is made, other events change it. A *termination*
ends it, a *partial termination* lowers its notional (the amount its payments
are worked out on), and a *novation* moves all or part of it to a new party.
On a shared ledger, each such event goes through three stages: one party
proposes it, every other party to it accepts, and the ledger applies it on
its effective date.

[trade_lifecycle_record.le](trade_lifecycle_record.le) reads a record of those
stages and keeps the state of every trade: whether it is live, who holds it,
and its notional. Each rule of the workflow is a *causal law*, a rule saying
what an event changes. Here each law records a breach, at the event that
breaks the rule. The timeline shows where a record goes wrong. The
explanation of a breach names the rule and the facts it rests on.

## The record

The record is that of **ex-cdm-swaps**, Digital Asset's public example of
interest rate swaps and credit default swaps managed with ISDA's Common Domain
Model on a Daml ledger. Its files hold 57 new trades, 9 later events (three
terminations, three partial terminations, three novations) and the master
agreements between the parties. `build.py` writes the scenario *the demo
record* from those files. Each event is dated by its own event date. The
acceptances follow the example's own account of its demonstration
(`sources/docs/demo.md`): all accepted at once, except the five acceptances
made by hand.

## The rules

| Rule | What it says |
|---|---|
| a_master_agreement | a new trade, or a novation, is between parties with a master agreement |
| proposed_by_a_party | a party that holds the trade proposes the event |
| a_live_trade | an event changes a trade that is live |
| less_than_the_notional | a partial termination takes off less than the notional |
| no_more_than_the_notional, from_a_holder | a novation moves no more than the notional, from a party that holds it |
| accepted_by_a_party | only a party to an event accepts it |
| every_party_accepts_first | the ledger applies an event after every party has accepted it |
| not_before_the_effective_date | the ledger applies an event no earlier than its effective date |
| only_once | the ledger applies an event once |

## Try this
1. Run the scenario *the demo record*. It ends with 56 live trades and no
   breach. The partial terminations and novations leave the notionals the
   event files say.
2. Run *applied too early*: the termination of BHNAFG4NEC is applied a day
   early, before CLIENT_C03 accepts it. Two breaches.
3. Run *terminated twice*: a partial termination recorded twice. Two breaches.
4. Run *dead trade*: a novation of a trade already terminated, proposed and
   accepted by parties who are not party to it. Three breaches.
5. Run *no master agreement*: a trade between two parties with no master
   agreement. One breach.

## What the check found in the real record

Nothing broken. One trade, HV5DODIZ6J, is between two accounts of the same
dealer, DEALER_D02, which the master agreements allow. The event files give the
amount a partial event takes off, not the notional left: the example's Daml
code subtracts the one from the other (`buildQuantityChangePrimitive`), and
the program does the same.

## Back to Daml

**File ▸ Export to Another System ▸ Daml** in the Logical English editor
writes the program as a Daml module, its rules as Daml functions.
[trade_lifecycle_record.daml](trade_lifecycle_record.daml) gives, in Daml, the
one comparison of dates that
[trade_lifecycle_record.lps](trade_lifecycle_record.lps) gives in Prolog.
The demo record, run as the module's script on a Canton sandbox, ends in the
state LPS2 ends with (18 October 2026).

## Sources

`sources/` holds the files of ex-cdm-swaps that the record is made from
(`examples/`: the trades, the events, the master agreements, the rate fixings
and the holiday calendars), its account of the demonstration
(`docs/demo.md`), its licence (`LICENSE`, the Apache License 2.0) and its
`NOTICES`, from https://github.com/digital-asset-archive/ex-cdm-swaps (branch
master, archived on 13 January 2025). Copyright (c) 2019, Digital Asset
(Switzerland) GmbH and/or its affiliates. The ISDA CDM code that the example
includes, under ISDA's own licence, is not copied here.

## Disclaimer

This program is an example, provided **"as is", without warranty of any
kind**. The record's dates and acceptances are a reading of the example's
files and its account of the demonstration, not a record of a real ledger.
It is not financial, legal or other professional advice.
