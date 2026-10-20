# How a program runs

*Kind: tutorial · Audience: users · Status: current (2026-09-29)*

This tutorial is about the order in which LPS (Logic Production System) does
things. A program says *what* must happen. The engine is the part of LPS2 that runs a
program. The engine decides *when* each thing happens, and in which order. Readers
who completed the first sections of [Learning LPS](lps-tutorial.md) frequently ask
the same questions. Which rule goes first? Why did an action occur one cycle late?
Why did the run fail? Why did an action occur when its reason was gone? This
tutorial answers these questions with small programs that you can run.

We ran each program in this tutorial, and each trace is the text that the run
printed. The reference gives the same rules in a short form, in
[`lps.md` §13a](../reference/lps.md#13a-how-a-program-runs-step-by-step).
[`glossary.md`](../reference/glossary.md) gives the definitions of the terms.

This tutorial uses four words frequently.

- A **fluent** is a fact that is true for a period of time. An example is
  `waiting(ann)`.
- An **event** is something that occurs from one moment to the next moment. An
  event comes from outside the program. An **action** is the same as an event,
  but the program itself selects the action.
- A **reactive rule** is a sentence of the form *if this is true, then make that
  occur*.
- A **goal** is the result of a reactive rule when the rule fires. A goal is
  something that the engine must make occur. The engine continues to work on the
  goal until the goal is complete.

---

## Contents

1. [The clock](#1-the-clock)
2. [One cycle, in order](#2-one-cycle-in-order)
3. [Serving coffee, cycle by cycle](#3-serving-coffee-cycle-by-cycle)
4. ["Some time" and "now"](#4-some-time-and-now)
5. [Who goes first](#5-who-goes-first)
6. [A goal outlives its reason](#6-a-goal-outlives-its-reason)
7. [A choice of ways: composite events](#7-a-choice-of-ways-composite-events)
8. [Looking one step ahead](#8-looking-one-step-ahead)
9. [Events from outside come first](#9-events-from-outside-come-first)
10. [The same rules in Logical English](#10-the-same-rules-in-logical-english)
11. [When a run surprises you](#11-when-a-run-surprises-you)

---

## 1. The clock

In LPS, time is a count of **cycles**: 1, 2, 3, and more. The engine records the
initial state at time 0. The initial state is also the state of cycle 1.

The engine can select an action in cycle 2. That action then occurs **from 2 to
3**. The **trace** is the record of a run. The trace shows that action below
`events/3`, and it shows the effects of the action below `fluents/3`. Thus there is
always a difference of one between two numbers. The first number is the cycle in
which the engine selects the action. The second number is the line of the trace
that shows the action. This difference is the usual cause of confusion about "the
cycle in which an action occurred".

## 2. One cycle, in order

In each cycle, the engine does eight things, always in this order.

1. The engine records the actions and events that occurred after the previous
   cycle.
2. The engine applies their effects to the state. For this, it uses the causal
   laws. The causal laws are the sentences with `initiates`, `terminates` and
   `updates`.
3. The engine fires each reactive rule whose condition is now true. A rule fires
   one time for each way in which its condition is true. Each firing adds a goal.
4. The engine records the new state.
5. The engine receives the events from outside that it observed for the next step.
6. The engine works on each goal. **The goals from earlier cycles come first.** The
   engine selects an action when the goal gets to the action. But a `false`
   sentence can prohibit the action. A prohibited action waits for a later cycle,
   if the goal lets the action occur in a later cycle.
7. The engine examines the state that the selected actions would make. It compares
   that state with the `false` sentences. If the state would break one of those
   sentences, the engine moves some actions to a later cycle.
8. The engine moves to the next cycle. It keeps each goal that is not complete.

The remaining sections of this tutorial show each of these steps.

## 3. Serving coffee, cycle by cycle

Open `examples/start/cafe.lps`, or type the program below into a new file.

```prolog
maxTime(6).

fluents  waiting(_), open.
events   arrives(_), opens.
actions  serve(_).

initially waiting(ann), waiting(bob).

observe opens from 1 to 2.
observe arrives(carl) from 2 to 3.

opens      initiates  open.
arrives(P) initiates  waiting(P).
serve(P)   terminates waiting(P).

if   waiting(P) at T
then serve(P) from T2 to T3.

false serve(_), not open.
false serve(P1), serve(P2), P1 \= P2.
```

When the run starts, Ann and Bob wait. The café opens between cycles 1 and 2. Carl
arrives between cycles 2 and 3. The rule says: serve each person who waits. The two
`false` sentences are **preconditions**. A precondition is a sentence that
prohibits an action in some conditions. The first precondition says: do not serve
when the café is closed. The second precondition says: do not serve two persons in
the same cycle. The reason is that there is only one coffee machine.

Run the program with `./lps run examples/start/cafe.lps`, or click **Run** in the
editor:

```
fluents/0        [waiting(ann),waiting(bob)]
fluents/1        [waiting(ann),waiting(bob)]
events/2         [opens]
fluents/2        [waiting(ann),waiting(bob),open]
events/3         [arrives(carl),serve(ann)]
fluents/3        [waiting(bob),open,waiting(carl)]
events/4         [serve(bob)]
fluents/4        [open,waiting(carl)]
events/5         [serve(carl)]
fluents/5        [open]
fluents/6        [open]

success (success)
```

This is what the engine did in each cycle.

**Cycle 1.** Ann and Bob wait. Thus the rule fires two times, one time for each of
them. The engine now has two goals: serve Ann, and serve Bob. The rule gives new
names, `T2` and `T3`, to the times of the serving. Thus the serving can occur in
any cycle. The engine tries to serve Ann now. The café is closed, thus the first
precondition prohibits the serving, and the goal for Ann waits. The goal for Bob
waits for the same reason. The engine selects no action. The engine receives the
observed event `opens` for the step from 1 to 2.

**Cycle 2.** `opens` occurred, thus the café is open. The rule fires again for Ann
and for Bob. The new goals ask for the same things as the goals that wait. Thus one
serving will satisfy two goals. The engine gets to the goal for Ann first and
selects `serve(ann)`. Then the engine gets to the goal for Bob. The second
precondition prohibits a second serving in the same step, thus Bob waits. The
engine receives the arrival of Carl for the same step, from 2 to 3. The trace line
`events/3 [arrives(carl),serve(ann)]` shows that the action and the observed event
occur together.

**Cycle 3.** Bob and Carl wait. The goal for Bob exists from cycle 1. The engine
made the goal for Carl in this cycle. Thus the engine tries the goal for Bob first,
and it serves Bob. Carl waits.

**Cycle 4.** The engine serves Carl. **Cycles 5 and 6.** No person waits, and
`maxTime(6)` stops the run.

You can ask the engine about each of these things. Do these steps in the editor:

1. On the **Timeline**, right-click the serving of Ann.
2. In the dialog that opens, type the question into the *why not* box.

You can also ask the question from the command line:

```sh
./lps explain examples/start/cafe.lps --ask "why_not(happened(serve(bob)), 3)"
```

The answer gives the name of the precondition that stopped the serving of Bob. The
answer also gives the other action that the engine selected in the same step:

```
serve(bob) did not occur at cycle 3
  a denial blocked serve(bob) — false [happens(serve(ann),2,3),happens(serve(bob),2,3),ann\=bob]
```

In the question, the number 3 is the time at which the serving would *end*. This is
the same number as in the trace.

## 4. "Some time" and "now"

Change one line of the café program. Replace this line:

```prolog
then serve(P) from T2 to T3.
```

with this line:

```prolog
then serve(P) from T to T2.
```

Then run the program again:

```
fluents/0        [waiting(ann),waiting(bob)]
fluents/1        [waiting(ann),waiting(bob)]

failure (failure)
```

`T` is the time at which the condition of the rule was true. Thus `from T to T2`
says: serve this person *in the cycle in which the rule fired*. In cycle 1, the café
is closed. Thus the precondition prohibits the serving, and the serving cannot move
to a later cycle. The engine must complete each goal that a reactive rule makes. The
engine cannot complete this goal now. Thus the engine stops, and the run ends with
`failure`.

Now also remove the line `false serve(_), not open.`, and run the program again.
The run fails in cycle 1 again. In cycle 1, two servings are necessary, and the
other precondition lets only one serving occur.

Remember this lesson:

- **New time names in the consequent** (`from T2 to T3`) mean *as soon as
  possible*. The consequent is the "then" part of the rule. A prohibited action
  waits for a later cycle.
- **The time of the antecedent in the consequent** (`from T to T2`) means *now or
  never*. The antecedent is the "if" part of the rule. A prohibited action makes the
  run fail.

A deadline is between these two forms. `then serve(P) from T2 to T3, T3 =< T + 3`
lets the serving wait, but for a maximum of three cycles. If the deadline passes and
the goal is not complete, the run fails.

## 5. Who goes first

Goals from earlier cycles go before goals that the engine made in the current
cycle. For this reason, Bob went before Carl in cycle 3. Apart from this one rule,
the engine uses an internal order. The engine got this order from LPS1, the earlier
implementation of LPS. The internal order decided between Ann and Bob in cycle 2.
The goals from earlier cycles can come from different cycles. For these goals, the
internal order is also not the order of age. The internal order does not follow the
order of the rules in the file. It also does not follow the order of the facts in
`initially`.

The next program has three customers. For each customer, the program gives the time
at which the customer started to wait. The program has no rule about who goes first:

```prolog
maxTime(4).

fluents  waiting_since(_, _).
actions  serve(_).

initially waiting_since(ann, 1), waiting_since(bob, 2), waiting_since(cat, 3).

serve(P) terminates waiting_since(P, _).

if   waiting_since(P, _) at T
then serve(P) from T2 to T3.

false serve(P1), serve(P2), P1 \= P2.
```

```
events/2         [serve(cat)]
events/3         [serve(ann)]
events/4         [serve(bob)]
```

Cat arrived last, but the engine served Cat first. The program did not say a
different thing. Thus the engine was free to select, and a reader cannot easily
predict its selection. **If the order is important, write the order in the
program.** Add one more precondition:

```prolog
false serve(P), waiting_since(P, T1), waiting_since(_, T2), T2 < T1.
```

This precondition means: do not serve a person if a different person waits for a
longer time. Run the program again:

```
events/2         [serve(ann)]
events/3         [serve(bob)]
events/4         [serve(cat)]
```

The program now says what it means. The internal order of the engine is now not
important.

## 6. A goal outlives its reason

```prolog
maxTime(5).

fluents  dirty.
actions  mop, sweep.

initially dirty.

mop   terminates dirty.
sweep terminates dirty.

if dirty at T then mop   from T2 to T3.
if dirty at T then sweep from T2 to T3.

false mop, sweep.
```

```
fluents/0        [dirty]
fluents/1        [dirty]
events/2         [sweep]
events/3         [mop]
```

The two rules fire in cycle 1. Thus there are two goals: mop, and sweep. The
precondition lets only one of them occur in each cycle. The engine sweeps first,
but the rule for the mopping is first in the file (refer to §5). The sweeping ends
`dirty`. But the engine also mops, one cycle later.

The engine keeps a goal until the goal is complete or fails. The goal does not
examine again the condition that made it. Possibly, the mopping must occur only when
the floor is dirty. Then the consequent must say so, and examine the fluent again:
`then dirty at T2, mop from T2 to T3`. A condition in the consequent can be false.
Then the goal waits until the condition is true.

The opposite also surprises people. A rule fires in each cycle in which its
condition is true, and it adds goals each time. [Learning LPS
§7](lps-tutorial.md#7-intensional-fluents) shows an alarm that sounds in each cycle
for this reason.

## 7. A choice of ways: composite events

A **composite event** is an event with a name, which other events define. A
composite event can have more than one definition. Each definition is one way to do
the composite event.

```prolog
maxTime(4).

fluents  hungry, no_bread.
actions  make_toast, order_pizza.

initially hungry, no_bread.

eat from T1 to T2 if make_toast from T1 to T2.
eat from T1 to T2 if order_pizza from T1 to T2.

make_toast  terminates hungry.
order_pizza terminates hungry.

if hungry at T then eat from T2 to T3.

false make_toast, no_bread.
```

```
fluents/0        [hungry,no_bread]
fluents/1        [hungry,no_bread]
events/2         [order_pizza]
composites/2     [happens(eat,1,2)]
fluents/2        [no_bread]
```

The engine tries the definitions in the order of the file. The precondition
prohibits the toast. Thus the engine orders the pizza, in the same cycle.

The engine does not complete one definition before it starts the next definition.
The engine works on all the definitions at the same time, and it keeps the first
definition that completes. A definition can have more than one step. Then more than
one definition can start:

```prolog
maxTime(4).

actions  make_toast, butter_toast, order_pizza.

eat from T1 to T3 if make_toast from T1 to T2, butter_toast from T2 to T3.
eat from T1 to T2 if order_pizza from T1 to T2.

if true at 1 then eat from T2 to T3.
```

```
events/2         [make_toast,order_pizza]
composites/2     [happens(eat,1,2)]
```

In cycle 1, the engine starts the two ways to eat. It makes toast, *and* it orders a
pizza. The pizza completes the meal first. Thus the engine does not butter the
toast. Possibly, two ways must not start together. Then prohibit this with a
precondition, as in the first program of this section.

## 8. Looking one step ahead

A `false` sentence can be about the state that an action would make. The ending
`pour to T` means "a pouring that ends at T". Thus the engine reads the fluents in
the sentence in the state after the pouring.

```prolog
maxTime(6).

fluents  cups(_).
actions  pour.

initially cups(0).

pour updates Old to New in cups(Old) if New is Old + 1.

if cups(N) at T, N < 5 then pour from T2 to T3.

false cups(N) at T, N > 2, pour to T.
```

```
fluents/1        [cups(0)]
events/2         [pour]
fluents/2        [cups(1)]
events/3         [pour]
fluents/3        [cups(2)]
fluents/4        [cups(2)]
fluents/5        [cups(2)]
fluents/6        [cups(2)]
```

In cycle 3, the engine selects a third pouring. It calculates the next state,
`cups(3)`. It finds that this state would break the `false` sentence. Thus the
engine goes back, and moves the pouring to a later cycle. The goal waits until the
run ends. The run ends with `success` all the same: a goal that waits for all time
is not an error.

## 9. Events from outside come first

The engine receives the events from outside before it selects its own actions for
the same step. A precondition can be about an event and an action together. Such a
precondition stops the action, and never the event.

```prolog
maxTime(4).

fluents  needed.
events   power_cut.
actions  start_machine.

initially needed.

observe power_cut from 1 to 2.

start_machine terminates needed.

if needed at T then start_machine from T2 to T3.

false start_machine, power_cut.
```

```
fluents/1        [needed]
events/2         [power_cut]
fluents/2        [needed]
events/3         [start_machine]
```

In cycle 1, the engine already knows about the power cut for the step from 1 to 2.
Thus the engine does not start the machine in that step. The machine starts one
cycle later.

A precondition can also refuse an observed event, if the precondition prohibits
that event itself. [`lps.md` §10](../reference/lps.md#10-constraints-and-preconditions)
tells you how a refused event looks.

## 10. The same rules in Logical English

A program in Logical English runs in exactly the same way. But be careful with one
habit of Logical English. A conclusion can have no time of its own. Then the
conclusion gets the time of the conditions. This is the "now or never" of §4:

```
    if the guest is waiting
    then the guest enters.
```

A constraint can prohibit the entry in the cycle in which the rule fires. Then the
run fails. To let the conclusion wait, give the conclusion its own times:

```
    if the guest is waiting at a first time
    then the guest enters from a second time to a third time.
```

[`le-for-lps.md` §3.5](../reference/le-for-lps.md#35-if--then---reactive-rules)
gives the two forms. It also tells you when the conclusions start if a condition is
an event: at the moment when the event ends.

## 11. When a run surprises you

Ask these questions, in this order.

1. **Which cycle do I examine?** The engine selected an action on the line
   `events/N` in cycle N−1. It used the state on the line `fluents/N−1` (§1).
2. **Did the rule fire?** A condition about an event needs `from … to …`, not
   `at` ([Learning LPS §16](lps-tutorial.md#16-ten-mistakes-that-are-easy-to-make)).
   Ask `why_not(happened(A), T)`.
3. **Did a precondition prohibit the action?** The answer to `why_not` gives the
   name of the `false` sentence. It also gives the other actions of the same step
   (§3).
4. **Could the action wait?** New time names can wait. The time of the antecedent
   cannot wait, and it makes the run fail (§4).
5. **Did two goals compete?** Goals from earlier cycles go before new goals. Apart
   from this rule, do not trust the order of the engine. Write the order that you
   want as a precondition (§5).
6. **Does an old goal continue to work?** The engine keeps a goal after its reason
   is gone (§6).
7. **Did more than one way to do something start?** The engine works on the
   definitions of a composite event at the same time (§7).

The document for developers tells about each selection of the engine, with the
reasons. This document is `docs/dev/semantics/selection-spec.md`.
