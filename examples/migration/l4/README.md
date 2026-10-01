# L4 twins — contracts of the L4 language in Logical English for LPS

L4 is a language for writing laws and contracts as programs, made at the
Centre for Computational Law of Singapore Management University and now
developed by Legalese (`smucclaw/l4-ide`, under the Apache 2.0 licence). In
L4, a contract says who must, may or must not do something, by when, and
what follows: `PARTY … MUST … WITHIN … HENCE … LEST …`. L4 tests a contract
with a `#TRACE`: a list of events, each on a day, and the result is how the
contract stands after them — fulfilled, breached by someone, or what is
still owed.

Each folder here is the twin of one L4 file: its contracts, translated by
the L4 translator (lpsPlus `migration/l4`) into Logical English for LPS. A
twin is a translation that runs; its original L4 file is in the folder's
`sources/`. Every `#TRACE` of the file is a scenario of the twin, and the
comment above the scenario is L4's own result for it. The translator checks
each scenario against L4's evaluator.

## How a twin reads

- Each obligation, permission or prohibition is a fluent (a fact that holds
  for a while): `sale contract obliges the seller to deliver goods by day 14
  as its first obligation`. The fluent holds while the obligation is open.
- L4's events are events here, with L4's day as their last place: `the
  seller does deliver goods on day 10`. One event happens per cycle, in L4's
  order.
- A law says what meets an obligation, and what follows when it is met.
  Another law says what follows when its deadline is missed.
- As in L4, a missed deadline is noticed only when something next happens.
  That event starts what follows, and does not count towards it. `the clock
  reaches day 20` is L4's `WAIT UNTIL 20`: time passing, with nothing done.

## Start here

- [The sale contract](sale_contract/) of L4's foundation course: deliver,
  then pay.
- [The promissory note](promissory_note/): a loan repaid in twelve
  instalments, where each payment starts the obligation again for what is
  still owed.
- [Obligations](must_example/), [permissions](may_example/) and
  [prohibitions](shant_example/): the examples of L4's reference manual.

## Try this

1. Open [the sale contract](sale_contract/sale_contract.le).
2. Pick one of its scenarios and press **Run**.
3. On the **Timeline**, watch the obligation to deliver start, end when the
   seller delivers, and the obligation to pay start in its place.

## One file left out

L4's `ny-environmental-7.3.l4` (a New York environmental regulation) is in
the corpus the translator is checked on, but its twin is not published
here: the regulation is records and dates rather than obligations, and the
twin the translator writes for it is mostly facts nothing reads, under
names no reader would choose. It will return when the translator reads
records as well as it reads contracts.

## The same contracts, read over a finished history

The Logical English repository has a second twin of each file,
`<name>_history.le`, in its `examples/migration/l4/<name>/`: the same
obligations, read over events that have already happened. That twin answers
"given these events, who owes what, and why", with an explanation. See
[Other systems](/docs/user/integrations/index).

The disclaimer of [the migration twins](../README.md#disclaimer) applies to
every twin here.
