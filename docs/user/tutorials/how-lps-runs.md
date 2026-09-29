# How a program runs

*Kind: tutorial · Audience: users · Status: current (2026-09-29)*

This tutorial is about the order in which LPS (Logic Production System) does
things. A program says *what* should happen. The engine, the part of LPS2 that
runs a program, decides *when*, and in what order. Readers who have finished
the first sections of [Learning LPS](lps-tutorial.md) ask the same questions
again and again. Which rule goes first? Why did this action happen a cycle
late? Why did the run fail? Why did that action happen at all, when its reason
had gone? This tutorial answers those questions with small programs that you
can run.

Every program below was run, and every trace below is what the run printed.
The reference gives the same rules in short form, in
[`lps.md` §13a](../reference/lps.md#13a-how-a-program-runs-step-by-step).
[`glossary.md`](../reference/glossary.md) defines the terms.

Four words are used throughout.

- A **fluent** is a fact that holds for a stretch of time, such as
  `waiting(ann)`.
- An **event** is something that happens from one moment to the next, and that
  comes from outside the program. An **action** is the same, except that the
  program itself chooses to do it.
- A **reactive rule** is a sentence of the form *if this holds, then bring that
  about*.
- A **goal** is what a reactive rule leaves behind when it fires: something the
  engine has taken on to bring about, and keeps working on until it is done.

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

Time in LPS is a count of **cycles**: 1, 2, 3, and so on. The initial state is
recorded at time 0, and is also the state of cycle 1.

An action that the engine chooses in cycle 2 happens **from 2 to 3**. A run's
record, the **trace**, lists that action under `events/3`, and shows its
effects under `fluents/3`. So there is always a gap of one between the cycle in
which an action is decided and the line of the trace on which the action
appears. Most confusion about "which cycle did this happen in" comes from that
gap.

## 2. One cycle, in order

In each cycle the engine does eight things, always in this order.

1. It records the actions and events that happened since the previous cycle.
2. It applies their effects to the state, using the causal laws, the sentences
   written with `initiates`, `terminates` and `updates`.
3. It fires every reactive rule whose condition is now true, once for each way
   in which the condition is true. Each firing adds a goal.
4. It records the new state.
5. It takes in the events observed from outside for the next step.
6. It works on every goal, **the goals carried over from earlier cycles
   first**. An action is chosen as soon
   as the goal reaches the action, unless a `false` sentence forbids the
   action. A forbidden action waits for a later cycle, if the goal allows a
   later cycle.
7. It checks the `false` sentences against the state that the chosen actions
   would produce, and puts off actions if one of those sentences would be
   broken.
8. It moves on to the next cycle, keeping every goal that is not yet done.

The rest of this tutorial shows each of these steps at work.

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

Ann and Bob are waiting when the run starts. The café opens between cycles 1
and 2. Carl arrives between cycles 2 and 3. The rule says: serve whoever is
waiting. The two `false` sentences are **preconditions**, sentences that forbid
an action in some circumstances. The first says: never serve while the café is
closed. The second says: never serve two people in the same cycle, since there
is only one coffee machine.

Run the program with `./lps run examples/start/cafe.lps`, or press **Run** in
the editor:

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

Here is what the engine did in each cycle.

**Cycle 1.** Ann and Bob are waiting, so the rule fires twice, once for each of
them, and the engine now has two goals: serve Ann, and serve Bob. The rule
writes the serving's times as new names, `T2` and `T3`, so the serving may
happen in any cycle. The engine tries to serve Ann now. The café is closed, so
the first precondition forbids the serving, and Ann's goal waits. Bob's goal
waits for the same reason. Nothing is chosen. The observed event `opens` is
taken in for the step from 1 to 2.

**Cycle 2.** `opens` has happened, so the café is open. The rule fires again
for Ann and for Bob. The new goals ask for exactly what the waiting goals ask
for, so one serving will satisfy both. The engine reaches Ann's goal first and
chooses `serve(ann)`. The engine then reaches Bob's goal. The second
precondition forbids a second serving in the same step, so Bob waits. Carl's
arrival is taken in for the same step, from 2 to 3. The trace line
`events/3 [arrives(carl),serve(ann)]` shows the action and the observed event
happening together.

**Cycle 3.** Bob and Carl are waiting. Bob's goal has been around since cycle 1
and Carl's goal was created just now, so Bob's goal is tried first, and Bob is
served. Carl waits.

**Cycle 4.** Carl is served. **Cycles 5 and 6.** Nobody is waiting, and
`maxTime(6)` ends the run.

You can ask the engine about any of this. In the editor, right-click the
serving of Ann on the **Timeline**, and type the question into the *why not*
box of the dialog that opens. From the command line:

```sh
./lps explain examples/start/cafe.lps --ask "why_not(happened(serve(bob)), 3)"
```

The answer names the precondition that stopped Bob's serving, and the other
action that was chosen in the same step:

```
serve(bob) did not occur at cycle 3
  a denial blocked serve(bob) — false [happens(serve(ann),2,3),happens(serve(bob),2,3),ann\=bob]
```

The 3 in the question is the time at which the serving would have *ended*, as
in the trace.

## 4. "Some time" and "now"

Change one line of the café. Replace

```prolog
then serve(P) from T2 to T3.
```

with

```prolog
then serve(P) from T to T2.
```

and run again:

```
fluents/0        [waiting(ann),waiting(bob)]
fluents/1        [waiting(ann),waiting(bob)]

failure (failure)
```

`T` is the time at which the rule's condition was true. `from T to T2`
therefore says: serve this person *in the cycle in which the rule fired*. In
cycle 1 the café is closed, so the serving is forbidden, and the serving
cannot be put off either. A goal created by a reactive rule has to be met, and this one no
longer can be, so the engine gives up and the run ends in `failure`.

Now remove the line `false serve(_), not open.` as well, and run again. The run
still fails in cycle 1. Two servings are due in cycle 1, and the other
precondition allows only one.

The lesson is worth remembering:

- **new time names in the consequent** (`from T2 to T3`) mean *as soon as
  possible*. A forbidden action waits for a later cycle;
- **the antecedent's time in the consequent** (`from T to T2`) means *now or
  never*. A forbidden action makes the run fail.

A deadline sits between the two. `then serve(P) from T2 to T3, T3 =< T + 3`
lets the serving wait, but for three cycles at most. When the deadline passes
with the goal still unmet, the run fails.

## 5. Who goes first

Goals carried over from earlier cycles go before goals created in the current
cycle. That is why Bob went before Carl in cycle 3. Beyond that one rule, the
engine uses an internal order that it inherited from LPS1, the earlier
implementation of LPS. The internal order decided between Ann and Bob in
cycle 2. Among goals carried over from several earlier cycles, the internal
order is not the order of age either. Nor does the internal order follow the
order of the rules in the file, or the order of the facts in `initially`.

The next program has three customers, each with the time at which they started
waiting, and no rule about who goes first:

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

Cat, who arrived last, was served first. Nothing in the program said otherwise,
so the engine was free to choose, and the choice is not one a reader would
guess. **If the order matters, say so in the program.** Add one more
precondition:

```prolog
false serve(P), waiting_since(P, T1), waiting_since(_, T2), T2 < T1.
```

It reads: never serve someone while somebody else has been waiting longer. Run
again:

```
events/2         [serve(ann)]
events/3         [serve(bob)]
events/4         [serve(cat)]
```

The program now says what it means, and the engine's internal order no longer
matters.

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

Both rules fire in cycle 1, so there are two goals: mop, and sweep. The
precondition allows only one of them per cycle. The engine sweeps first, even
though the mopping rule comes first in the file (see §5). Sweeping ends
`dirty`. The engine mops anyway, a cycle later.

A goal is kept until it is met or fails. The goal does not look back at the
condition that created it. If the mopping should happen only while the floor
is still dirty, the consequent has to say so, by checking the fluent again:
`then dirty at T2, mop from T2 to T3`. A condition in the consequent that does
not hold makes the goal wait until the condition holds.

The opposite also surprises people. A rule keeps firing, and keeps adding
goals, in every cycle in which its condition holds. [Learning LPS
§7](lps-tutorial.md#7-intensional-fluents) shows an alarm that sounds in every
cycle for that reason.

## 7. A choice of ways: composite events

A **composite event** is a named event defined by other events. When a
composite event has several definitions, each definition is one way of doing
it.

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

The engine tries the definitions in the order of the file. Toast is forbidden,
so the pizza is ordered, in the same cycle.

The engine does not finish one definition before starting the next. The engine
pursues all the definitions side by side, and keeps the first to finish. When a
definition takes several steps, that can mean that more than one of them has
started:

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

In cycle 1 the engine starts both ways of eating: it makes toast *and* orders a
pizza. The pizza finishes the meal first, so the toast is never buttered. If
two ways must not both start, forbid that with a precondition, as in the first
program of this section.

## 8. Looking one step ahead

A `false` sentence can talk about the state that an action would bring about.
The ending `pour to T` says "a pouring that ends at T", so the fluents in the
sentence are read in the state after the pouring.

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

In cycle 3 the engine chooses a third pouring, works out the next state,
`cups(3)`, and finds that the `false` sentence would be broken. The engine then
goes back, and puts the pouring off. The goal keeps waiting until the run ends,
and the run still ends in `success`: a goal that waits for ever is not an error.

## 9. Events from outside come first

Events observed from outside are taken in before the engine chooses its own
actions for the same step. A precondition that mentions both therefore holds
back the action, never the event.

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

In cycle 1 the power cut is already known for the step from 1 to 2, so the
machine is not started in that step. The machine starts one cycle later.

A precondition can also refuse an observed event, when the event itself is
what the precondition forbids. [`lps.md` §10](../reference/lps.md#10-constraints-and-preconditions)
describes what a refused event looks like.

## 10. The same rules in Logical English

A program written in Logical English runs in exactly the same way. One habit of
Logical English needs care. A conclusion written with no time of its own takes
the time of the conditions, which is the "now or never" of §4:

```
    if the guest is waiting
    then the guest enters.
```

If a constraint forbids the entry in the cycle in which the rule fires, the run
fails. Give the conclusion times of its own to let it wait:

```
    if the guest is waiting at a first time
    then the guest enters from a second time to a third time.
```

[`le-for-lps.md` §3.5](../reference/le-for-lps.md#35-if--then---reactive-rules)
gives both forms, and the same care for a condition that is an event.

## 11. When a run surprises you

Ask these questions, in this order.

1. **Which cycle am I looking at?** An action on the line `events/N` was chosen
   in cycle N−1, from the state on the line `fluents/N−1` (§1).
2. **Did the rule fire?** A condition about an event needs `from … to …`, not
   `at` ([Learning LPS §16](lps-tutorial.md#16-ten-mistakes-that-are-easy-to-make)).
   Ask `why_not(happened(A), T)`.
3. **Was the action forbidden?** The answer to `why_not` names the `false`
   sentence and the other actions of the same step (§3).
4. **Could the action wait?** New time names wait; the antecedent's time
   does not, and makes the run fail (§4).
5. **Did two goals compete?** Goals carried over from earlier cycles go
   before new ones. Beyond that, do not rely on
   the engine's order, and write the order you want as a precondition (§5).
6. **Is an old goal still at work?** A goal is kept after its reason has gone
   (§6).
7. **Did several ways of doing something all start?** Composite events are
   pursued side by side (§7).

The developers' account of every choice the engine makes, with the reasons, is
`docs/dev/semantics/selection-spec.md`.
