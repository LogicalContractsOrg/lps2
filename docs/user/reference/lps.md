# The LPS language: a reference

*Kind: reference · Audience: users, developers, the assistant (read by lps_assistant.pl) · Status: current (2026-09-29)*

This document describes everything you can write in an LPS (Logic Production
Systems) program, construct by construct. The document covers the declarations,
the rules, the vocabulary the engine provides, the way a program says how it
should be drawn, and what a program may borrow from Prolog.

The language described here is the language as you type it into a `.lps` or
`.pl` file. The earlier implementation of LPS accepts the same language, so
programs written for that implementation run here unchanged.

Two words are used throughout and are worth fixing now.

- The **written form** is what you type, and is the subject of this document.
- The **internal form** is what the written form is turned into before the
  engine runs the program. You never have to write the internal form yourself,
  but you can look at it — see §20 — and error messages sometimes mention it.

Related documents: [`lps-tutorial.md`](../tutorials/lps-tutorial.md) works through whole
programs step by step; [`glossary.md`](glossary.md) defines the terms used here
and elsewhere; [`le-for-lps.md`](le-for-lps.md) describes Logical
English, an alternative written form that translates to the same internal form;
[`ide.md`](../guide/ide.md) describes the editor.

---

## Table of contents

- [1. What a program is](#1-what-a-program-is)
- [2. Files and forms](#2-files-and-forms)
- [3. Declarations](#3-declarations)
- [3a. Defaults](#3a-defaults)
- [4. The initial state](#4-the-initial-state)
- [5. Causal laws](#5-causal-laws)
- [6. Reactive rules](#6-reactive-rules)
- [7. Composite events](#7-composite-events)
- [8. Intensional fluents](#8-intensional-fluents)
- [9. Timeless clauses](#9-timeless-clauses)
- [10. Constraints and preconditions](#10-constraints-and-preconditions)
- [11. Literals and their times](#11-literals-and-their-times)
- [12. Changing the state directly](#12-changing-the-state-directly)
- [13. Observations](#13-observations)
- [13a. How a program runs, step by step](#13a-how-a-program-runs-step-by-step)
- [14. Planning](#14-planning)
- [15. Settings](#15-settings)
- [16. Vocabulary the engine provides](#16-vocabulary-the-engine-provides)
- [17. Access to Prolog](#17-access-to-prolog)
- [18. Saying how a program should be drawn: `display/2`](#18-saying-how-a-program-should-be-drawn-display2)
- [18a. Three dimensions: `display3d/2`](#18a-three-dimensions-display3d2)
- [18b. The mouse as an input](#18b-the-mouse-as-an-input)
- [19. The operator table](#19-the-operator-table)
- [20. Running a program](#20-running-a-program)
- [21. Further reading](#21-further-reading)

---

## 1. What a program is

An LPS program describes something whose behaviour is a sequence of **states**
separated by **events**: an agent, a simulated world, a contract, a machine.

The engine repeats one cycle. In each cycle the engine:

1. collects the events that occurred since the previous cycle;
2. applies the effects of those events to the state, using the **causal laws**
   (§5);
3. finds the **reactive rules** (§6) whose conditions the new state satisfies,
   and adds their conclusions to the goals it is already pursuing;
4. works on every goal, those carried over from earlier cycles first, reducing
   each one to actions by way of **composite events** (§7), **intensional
   fluents** (§8) and ordinary **Prolog clauses** (§9);
5. chooses each action at the moment it reaches it, unless a **constraint**
   (§10) forbids the action; a forbidden action waits for a later cycle if its
   time allows, and the actions chosen become the next cycle's events.

§13a describes the cycle in full: the order of the steps, which goal goes
first, when an action waits and when the run fails, with a worked example.

Time is a cycle counter: 1, 2, 3, and so on. A **fluent** holds *at* an instant.
An **event** or an **action** happens *from* one instant *to* another. Almost
everything in this document is a way of saying which fluents hold when, and
which events happen between when and when.

Here is a complete program.

```prolog
maxTime(6).

fluents  light(_).
actions  switch(_).

initially light(off).

switch(New) initiates light(New).
switch(_)   terminates light(Old) if light(Old) at _.

if   light(off) at T
then switch(on) from T to T2.
```

Run it with `./lps run tiny.lps`.

## 2. Files and forms

| Extension | What it holds | Read by |
|---|---|---|
| `.lps` | the written form described in this document | the translator |
| `.pl` | the same written form; LPS1's examples use it | the translator |
| `.le` | Logical English — see [`le-for-lps.md`](le-for-lps.md) | LE2, which produces the internal form |
| `_.P` | the internal form, as produced by LPS1's translator | read directly |
| `.lpsw` | the internal form; the preferred extension for it from now on | read directly |
| `.ni`, `.inform` | Inform 7 assertions, converted to a Logical English story | `src/syntax/lps_inform.pl`, then LE2 |

A `.le` document and a `.lps` file of the same name beside it are **one
program**: the two are translated together, the `.le` document first. The `.lps`
half, the **companion file**, holds what is not English — `display/2` clauses,
Prolog helpers — in the written form of this document.

A file in the written form **is a Prolog file**. Prolog's `read_term/3` reads
it, with the operators of §19 in scope. Every clause in the file is either an
LPS construct or an ordinary Prolog clause, and the two may be mixed freely.
Comments are Prolog's: `%` to the end of the line, `/* … */` for a block.

The translator reads the file **once, from top to bottom**. Reading in file
order matters. What a bare `f(x)` in a rule means — a fluent or an event — is
decided by what the file has already said about `f/1` (§3). So declare a
predicate before you use it.

## 3. Declarations

```prolog
fluents        loc(_, _), balance(_, _).
events         payment(_, _).
actions        row(_, _), transport(_, _, _).
prolog_events  tick(_).
unserializable send(_, _).
```

| Declaration | Meaning |
|---|---|
| `fluents F1, F2, …` | these are fluents: they *hold at* instants, and causal laws change them |
| `events E1, …` | these happen, and they arrive from outside the program (§13) rather than being chosen by it |
| `actions A1, …` | these happen, and the program *chooses* them, by reducing goals |
| `prolog_events E1, …` | events whose occurrence is decided by calling Prolog rather than by the engine |
| `unserializable A1, …` | actions whose effects are worked out together, all against the state before the cycle's actions were applied (see below) |

The arguments in a declaration are placeholders. `fluents loc(_, _)` declares
`loc/2`; the underscores stand for nothing in particular. Several templates may
be listed in one declaration, separated by commas, and the same declaration may
appear more than once.

**`unserializable`.** By default the engine applies the actions of one cycle one
at a time, so that two `updates` of the same fluent in one cycle build on each
other. For the actions named in `unserializable` the engine instead works out
all their effects together, before it applies any of the other actions.

Declarations are **advisory, not obligatory**. A program that declares nothing
still runs, because the translator works out what each predicate is from the
way the program first uses it: `f at T` makes `f` a fluent, and `f from T1 to T2`
makes `f` an event. Declaring is nevertheless better. The translator checks the
declaration, the declaration tells a reader what the program means, and
declaring frees the program from depending on the order in which things appear
in the file.

A fluent can also be given a default value, with `defaults/1` (§3a).

## 3a. Defaults

A fluent whose last argument is a value — a balance, an owner —
can be given a default, the value it holds for any key that has no stored fact:

```prolog
fluents  balance(_, _).
defaults([balance(_, 0)]).
```

`defaults/1` is an LPS2 declaration; LPS1 does not have it. You write it as an
ordinary fact holding a list, with one term per fluent, and the last argument of
each term is that fluent's default. Logical English writes the same thing as
`; 0 by default`.

- When the key is filled in, the fluent holds its stored value, or else the
  default: `balance(carol, B) at T` gives `B = 0` for an account never
  mentioned. The engine never stores the default, so the state and the trace
  list only the stored entries.
- When the key is left open, the engine lists only the stored entries.
- Consequently `not balance(carol, _) at T` fails: carol has a balance.
- An `updates` law reads the default as the old value of a key with nothing
  stored, so `deposit(P, A) updates Old to New in balance(P, Old) if New is Old + A`
  credits a new account without first initiating it. The engine takes such a
  law's conditions that do not mention the old value first, so those conditions
  can settle which key is meant, and each distinct key is updated once.
- `why(holds(balance(carol, 0)), T)` answers *(the default: no entry was
  stored)*, and the editor's timeline draws one *every other: …* line for each
  default.

A program without `defaults/1` runs exactly as before.

## 4. The initial state

```prolog
initially loc(wolf, south), loc(goat, south), loc(farmer, south).
```

A list of the fluents that hold at time 1, separated by commas. Anything not
listed does not hold: the state is treated as complete, so a fluent that has
not been said to hold is taken not to hold.

## 5. Causal laws

A causal law says what an event does to the state.

```prolog
Event initiates Fluent.
Event terminates Fluent.
Event updates Old to New in Fluent.

Event initiates Fluent if Conditions.
Event terminates Fluent if Conditions.
Event updates Old to New in Fluent if Conditions.
```

For example:

```prolog
switch(Person, Place, New) initiates light(Place, New).
switch(Person, Place, New) terminates light(Place, Old) if light(Place, Old) at _.

transfer(From, To, Amount) updates B1 to B2 in balance(From, B1)
    if B2 is B1 - Amount.

row(L1, L2) updates L1 to L2 in loc(farmer, L1).
```

`updates Old to New in F` does the work of a `terminates` and an `initiates`
over the same fluent. Prefer `updates` where it applies. The one sentence says
that the fluent *changes value*, rather than that one fluent disappears and an
unrelated one appears, and the planner (§14) can make use of the difference.

The engine evaluates the conditions of a causal law **in the state the event
started from**. A law with no conditions applies whenever its event happens.

## 6. Reactive rules

A reactive rule says: whenever this happens, bring that about.

```prolog
if   Antecedent
then Consequent.
```

The antecedent — the part after `if` — is a sequence of literals, single
statements with times attached (§11): fluents holding, events having happened.
The consequent, the part after `then`, is a sequence of actions, composite
events and fluent conditions to be brought about.

```prolog
if   light(Place, on) at T1, not location(dad, Place) at T1
then goto(dad, Place) from T2 to T3.

if   loc(Object, south) at T, Object \= farmer
then makeLoc(Object, north) from T to T2.

if   payment_due(Party, Amount) at T
then pay(Party, Amount) from T to T2, notify(Party) from T2 to T3.
```

A reactive rule is a **standing goal**, not an instruction that runs once and is
finished with. When a rule fires, the engine keeps the rule's consequent as an
outstanding goal until the goal has been satisfied or has become impossible. A
reactive rule is not a one-shot trigger. The times in the consequent say *when
the actions may happen*, not when they must.

Two ways of writing the consequent's time behave very differently. In
`then a from T2 to T3`, the times are new names, so the action may happen in
any cycle, and the engine does it in the first cycle that allows it. In
`then a from T to T2`, where `T` is the time of the antecedent, the action must
happen in the very cycle the rule fired. If a constraint forbids it in that
cycle, the goal cannot be met and the run fails. §13a shows both.

A rule fires again in every cycle in which its antecedent holds. A goal, once
created, is pursued even if the antecedent stops holding afterwards.

A rule may also carry an explicit priority. The priority is written as
`reactive_rule(Antecedent, Consequent, Priority)` in the internal form; the
written form has no notation for a priority.

## 7. Composite events

A composite event is a named event defined as a sequence of other events, so
that one name stands for several happenings. Naming a sequence this way is the
language's equivalent of a subroutine, a named piece of a program that the rest
of the program can then use by name.

```prolog
makeLoc(Object, Location) from T1 to T3
    if  loc(Object, L2) at T1,
        row(L2, Location) from T2 to T3.

dealWithGoat(L1, L2) from T1 to T2
    if  makeLoc(goat, L2) from T1 to T2.
```

The head — the part before `if` — is an event, either declared as one, or
recognisable as one from its explicit `from … to …`. The body, the part after
`if`, is a sequence. One composite event may be defined in terms of another.

A composite event with more than one defining clause is a genuine choice: the
engine tries the clauses in the order they appear in the file, and goes back and
tries the next one if the first does not work out.

If you leave the head's interval unwritten, the engine makes it the same as the
body's interval. Leaving the interval unwritten is what lets you write
`makeLoc(O, L) if …` and have the composite event span exactly as much time as
its body does.

## 8. Intensional fluents

An intensional fluent is one *computed* from the state rather than stored in it.

```prolog
total_due(Party, Total) at T
    if  findall(A, owes(Party, A) at T, As),
        sum_list(As, Total).

adjacent(X, Y) at _ if next_to(X, Y).
```

The head is a fluent, and the engine works the body out afresh each time
something asks about the fluent. Intensional fluents are never initiated or
terminated; they follow from whatever the stored state happens to be.

The engine reads the body of an intensional fluent at a **single instant**: any
literal in the body that does not name its own time is taken to be at the head's
instant.

## 9. Timeless clauses

An ordinary Prolog clause, with no reading in time at all.

```prolog
locationXY(livingroom, 0, 0).
locationXY(kitchen, 150, 0).

destructive(delete_file(_)).
beats(rock, scissors).
beats(scissors, paper).

pixels(X, Y, CX, CY) :- CX is X * 20 + 10, CY is Y * 20 + 10.
```

Timeless clauses say what things *mean*, rather than what happens or what is
required. You may call a timeless clause from anywhere: from the body of a rule,
from the condition of a causal law, from a `display/2` clause.

A program translated from Logical English writes the rules of a timeless
relation in the internal form, as `l_timeless/2`, and writes its facts as
ordinary Prolog facts. The engine answers such a relation as the program's own,
from both its rules and its facts. A question that neither the rules nor the
facts match simply fails, and a negated question (`it is not the case that …`)
is the negation of that answer. The engine never calls a Prolog predicate of
the same name.

## 10. Constraints and preconditions

```prolog
false Conditions.
```

A `false` sentence says that its conditions must never all hold at once. There
is one construct, but the construct has two readings, and what the conditions
mention decides which reading applies.

**A constraint on states.** No action is mentioned, so the sentence constrains
states.

```prolog
false balance(Account, B) at _, B < 0.
```

**A precondition.** An action is mentioned, so the sentence forbids that action
in those circumstances.

```prolog
false goto(dad, Place1), goto(dad, Place2), Place1 \= Place2.
false pay(P, A), not has_funds(P, A).
```

**A constraint on what an action would bring about.** Here the action's *end*
time is the time at which the fluents are read, so the constraint is about the
state the action would produce rather than the state it starts from.

```prolog
false loc(goat, L) at T, loc(wolf, L) at T, not loc(farmer, L) at T, row(_, _) to T.
```

Read `row(_, _) to T` as "a crossing that ends at T". The state at T is the
state that crossing would bring about, so the sentence rejects the crossing
before the crossing is made. Looking one step ahead is expressed in the language
itself in exactly this way, and the planner (§14) uses the same device.

An action that a constraint forbids is not an error. The engine goes back and
looks for another way to satisfy the goal: another definition of a composite
event, or the same action in a later cycle, if the goal's times allow a later
cycle. When no other way is left, the goal fails, and a goal that came from a
reactive rule makes the whole run fail (§13a). To find out which sentence did
the forbidding, ask:

```sh
./lps explain PROGRAM --ask "why_not(happened(A), T)"
```

**Observations are checked too.** A precondition applies to events that arrive
from outside (§13) as well as to the actions the program chooses. If the
conditions of a precondition hold in the state the observed events arrive in,
the engine **refuses** those events: the events do not happen, and neither does
any other event observed for the same cycle, because the engine refuses the
observations of one cycle together. The engine records the refusal.
`why_not(happened(E), T)` answers `refused_by_constraint`, naming the sentence
and the values it held on, and the editor's timeline shows the refused event
crossed out. In a program that models a contract, a refused event is a call
that reverts.

```prolog
false withdraw(P, A), balance(P, B), A > B.

observe withdraw(alice, 10) from 1 to 2.    % refused if alice holds less than 10
```

## 11. Literals and their times

Every literal in the body of a rule carries a time, either written out or taken
from its position.

| Written | Means | Internal form |
|---|---|---|
| `F at T` | fluent `F` holds at instant `T` | `holds(F, T)` |
| `F` (a declared fluent) | holds at the surrounding instant | `holds(F, T)` |
| `E from T1 to T2` | event `E` occupies that interval | `happens(E, T1, T2)` |
| `E to T2` | … ending at `T2`, start unconstrained | `happens(E, _, T2)` |
| `E from T1` | … starting at `T1` | `happens(E, T1, _)` |
| `E during [T1, T2]` | … somewhere within that interval | `happens(E, T1, T2)` |
| `E` (a declared event or action) | occupies the surrounding interval | `happens(E, T1, T2)` |
| `not F at T` | `F` does not hold at `T` | `holds(not F, T)` |
| `not (Sequence)` | the sequence cannot be satisfied | `holds(not …, T)` |
| `findall(X, Conds, L)` | collect over the state at one instant | `holds(findall(…), T)` |
| `if C then A else B` | a conditional inside a body | `(C -> A ; B)` |

A literal that names its own time keeps that time. A literal that names no time
takes the time of the clause it sits in. Some contexts are read at a single
instant — the body of an intensional fluent, the conditions of a causal law, a
`false` sentence, the argument of `not` — and in those, every literal without a
time of its own is placed at that one instant.

Times may be calculated: `T2 is T1 + 3`, `T1 < T2`, and the usual comparisons,
all as in Prolog.

## 12. Changing the state directly

Sometimes there is no event worth naming, and the program simply wants to change
the state. The engine provides three actions for that.

```prolog
if   emergency at T
then initiate alarm(on) from T to T2.

if   cleared at T
then terminate alarm(on) from T to T2.

if   sale(Amount) at T
then update B1 to B2 in balance(shop, B1) from T to T2.
```

`initiate F`, `terminate F` and `update Old to New in F` take the same time
endings as any other event (§11). The three are ordinary actions in every
respect: preconditions apply to them, they appear in the trace, and the engine
can explain them.

## 13. Observations

An observation is an event that arrives from outside the program. Observations
can be written into the program itself, which is how a test scenario is
scripted.

```prolog
observe payment(alice, 100) from 2 to 3.
observe request(bob) to 5.
observe tick, tock from 4 to 5.
```

An observation is the only way a predicate declared with `events` can enter a
run. The program chooses its `actions`; the world supplies its `events`.

A program driven by a real world rather than by a script receives the same
events over the network (the `observe` operation), or through the mailbox of a
continuously running session. The program itself does not change.

The program's preconditions apply to observed events, and the engine refuses an
observed event when one of those preconditions holds (§10).

A continuously running session can also restrict **who may send what**. You
start the session with a list of **channels**, and each channel names the event
predicates that channel may carry. The session drops an event whose predicate is
not on its channel's list, and reports the drop rather than dropping it
silently. The mouse events of §18b travel on a channel whose list is the
program's own declarations.

## 13a. How a program runs, step by step

This section answers the questions §1 leaves open: in what order the engine
does things within a cycle, which goal it works on first, when an action is
chosen, when an action waits, and when a run fails. Everything below was
checked by running the programs shown. The tutorial
[How a program runs](../tutorials/how-lps-runs.md) teaches the same material
more slowly, with exercises.

### Time, and where a run's records go

The **initial state** is recorded at time 0 and is the state of cycle 1. The
engine then runs cycle 1, cycle 2, and so on, up to `maxTime`.

An action decided in cycle `T` happens **from `T` to `T+1`**. The trace lists
the action under `events/T+1`, and the action's effects appear in
`fluents/T+1`. So the line `events/3 [serve(ann)]` means that the engine chose
`serve(ann)` in cycle 2.

An observed event `observe e from 2 to 3` is listed under `events/3` in the same
way, and takes effect in `fluents/3`. An event that is given to the program and
an action that the program chooses, when both happen from 2 to 3, happen
together, as one step.

### The steps of one cycle

In cycle `T` the engine does the following, in this order.

1. **It records what happened from `T-1` to `T`**: the actions it chose in
   the previous cycle, and the events observed for that step.
2. **It brings the state up to date.** The causal laws (§5) of those events
   and actions give the state at `T`. The conditions of a causal law are read
   in the state the event started from. The effects of several actions are
   applied one action after another, so two `updates` of the same fluent in one
   step build on each other (§3, `unserializable`).
3. **It fires the reactive rules.** Every reactive rule whose antecedent is
   true at `T` fires once for each way the antecedent is true: `if waiting(P)
   at T` with two people waiting gives two **rule instances**. Each rule
   instance adds one **goal** — the rule's consequent, with the values found —
   to the goals the engine is already pursuing. An antecedent that mentions an
   event is true in the cycle in which the event *ends*. An antecedent that
   spans several cycles (`badge from T1 to T2, pull from T3 to T4`) is followed
   from cycle to cycle, and the rule fires in the cycle its last condition
   becomes true.
4. **It records the state at `T`** (`fluents/T`).
5. **It takes in the observations for the step from `T` to `T+1`.** A
   precondition that forbids those events refuses them all (§10). Observed
   events come before the program's own actions: a precondition such as
   `false a, e` makes the action `a` wait when the event `e` is observed for the
   same step.
6. **It works on the goals**, one after another, the goals carried over from
   earlier cycles first (see *Which goal goes first* below). The engine takes each goal from left to
   right and goes as far as the goal can go in this cycle:
   - a fluent condition is checked against the state at `T`; if the condition
     names a later time, or does not hold yet and its time is free, the goal
     waits there;
   - a composite event (§7) is replaced by its definitions. When there are
     several, the engine pursues them side by side, in file order. The first
     definition to finish is kept, and the others are abandoned. An action
     that an abandoned definition has already chosen is not undone: with
     `job if a1, a2` and `job if b`, both `a1` and `b` happen in the first
     cycle, and `job` is then finished by `b`;
   - an action whose start can be `T` is **chosen** there and then, unless a
     precondition forbids it (see below). An action whose start is later waits.
7. **It checks the constraints on the next state.** With the chosen actions and
   observed events, the engine works out the state at `T+1` and checks every
   `false` sentence against it, including the sentences about what an action
   would bring about (§10). If one is broken, the engine goes back over its
   choices in step 6 and puts some actions off until a later cycle. If no
   action can be put off, because the actions concerned have fixed times, the
   run fails.
8. **It moves on to cycle `T+1`**, carrying every goal that is not finished.

### When an action is chosen, and when it waits

The engine chooses an action **as early as the action's times allow**, so a
goal whose times are free is acted on in the cycle the goal was created.

A precondition is checked at the moment the engine reaches the action, against
the state at `T`, the events observed for the step, and the actions already
chosen for the same step. If the precondition forbids the action, what happens
next depends on the action's times:

- **the times are free** (`then serve(P) from T2 to T3`): the goal waits, and
  the engine tries again in the next cycle, and in every cycle after that;
- **the start is fixed** (`then serve(P) from T to T2`, with `T` the time of
  the antecedent): the action cannot happen later, so the goal fails.

A goal that waits for ever is not an error. The run still ends in `success`
when `maxTime` is reached.

### When a run fails

A goal created by a reactive rule has to be met. If such a goal can no longer
be met, the engine abandons the cycle, and the whole run ends in `failure`.
A goal can no longer be met when:

- its action has a fixed time, and a precondition forbids the action at that
  time;
- a deadline in the consequent has passed. For example, `then a from T2 to T3,
  T3 =< 3` fails in cycle 4 if `a` has not happened by then;
- every definition of a composite event it needs has failed.

A rule whose consequent must happen at once is therefore a promise that the
action will be allowed. When that promise cannot be kept, write the times as
free, or add a condition to the antecedent.

### Which goal goes first

Several goals can compete for the same cycle, for example when a precondition
allows only one of two actions. The engine settles the competition by the order
in which it works on the goals:

- goals carried over from earlier cycles come **before** goals created in this
  cycle;
- among the goals created in the same cycle, and among the goals carried over,
  the order is an internal detail inherited from LPS1, the earlier
  implementation. The goals carried over are not kept in order of age: a goal
  that has waited longer is not necessarily tried first.
  The order is fixed for a given program, but it does not follow the order of
  the rules in the file or of the facts in the state, and it can change from
  one cycle to the next. `docs/dev/semantics/selection-spec.md` (SP1, SP4 to
  SP6) describes the order for developers.

Do not write a program whose meaning depends on that internal order. If one
goal must go before another, say so in the program. A precondition such as
`false serve(P), waiting_since(P, T1), waiting_since(_, T2), T2 < T1` makes the
customer who has waited longest go first, whatever the engine's order. The
tutorial runs a program with and without that precondition.

### Goals are kept, and are not repeated

A goal, once created, is pursued until the goal is met or fails, even if the
antecedent that created the goal stops holding. In the program below, both rules
fire in cycle 1. The precondition allows only one of the two actions per cycle.
`second` is done first, and it ends `go`. `first` is still done, a cycle later:

```prolog
maxTime(5).
fluents  go.
actions  first, second.
initially go.
first  terminates go.
second terminates go.
if go at T then first  from T2 to T3.
if go at T then second from T2 to T3.
false first, second.
```

```
events/2         [second]
events/3         [first]
```

A rule whose antecedent keeps holding fires again in every cycle, and adds a
goal each time. A goal that asks for exactly what an earlier goal asks for adds
no new action: one action satisfies both.

### A worked example: `examples/start/cafe.lps`

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

| cycle | the state | the rule fires for | the goals, in the order tried | chosen | why |
|---|---|---|---|---|---|
| 1 | Ann and Bob waiting; closed | Ann, Bob | Ann, Bob | nothing | `false serve(_), not open` forbids both. Their times are free, so both goals wait. `opens` is observed for the step from 1 to 2 |
| 2 | Ann and Bob waiting; open | Ann, Bob (the same goals again) | Ann, Bob | `serve(ann)` | the café is open. Ann's goal is reached first, by the engine's internal order, and `serve(ann)` is chosen. `false serve(P1), serve(P2), P1 \= P2` then forbids `serve(bob)`, which waits. `arrives(carl)` is observed for the same step |
| 3 | Bob and Carl waiting | Bob, Carl | Bob, then Carl | `serve(bob)` | Bob's goal is older than Carl's, so Bob's goal is tried first, and Carl's serving is forbidden |
| 4 | Carl waiting | Carl | Carl | `serve(carl)` | nothing competes |
| 5, 6 | nobody waiting | — | — | nothing | `maxTime(6)` ends the run |

Ask the engine about any row:

```sh
./lps explain examples/start/cafe.lps --ask "why_not(happened(serve(bob)), 3)"
# a denial blocked serve(bob) — false [happens(serve(ann),2,3),happens(serve(bob),2,3),ann\=bob]
```

The time in the question is the time the action would have *ended*: the
serving Bob did not get in cycle 2 is `happened(serve(bob)), 3`.

Now change the rule's consequent from `serve(P) from T2 to T3` to
`serve(P) from T to T2`. The run ends in `failure` in cycle 1: each serving
must now happen in the cycle its rule fired, and the closed café forbids that.
Remove the first precondition as well, and the run still fails in cycle 1:
two servings are due in cycle 1, and the second precondition allows only one.

## 14. Planning

```prolog
:- lps_engine(planning, [horizon(10), max_concurrency(2)]).

achieve loc(wolf, north), loc(goat, north), loc(cabbage, north), loc(farmer, north).
```

`achieve` names a group of fluents that are to be brought about together.

The planner searches over **sets of actions taken in the same cycle**, not over
single actions, because LPS commits several actions per cycle. The planner uses
the same causal laws and the same `false` sentences that the engine uses when it
is not planning. There is no separate language for planning, and no construct
means anything different under the planner.

A plan is a list of sets of actions. The ordinary cycle carries the plan out one
set per cycle, with the ordinary checks on preconditions and constraints. The
trace of a planned run is an ordinary LPS trace.

| Option | Default | Meaning |
|---|---|---|
| `horizon(N)` | 12 | the longest plan, in cycles |
| `max_concurrency(N)` | 3 | the most actions in one cycle |
| `search(S)` | `auto` | `bfs`, `greedy` or `auto` — see below |
| `nodes(N)` | 250 | how many states `auto` lets breadth-first search visit before switching |
| `on_plan_failure(P)` | `replan` | `replan` or `reactive`, when the plan stops matching what happens |

**There are two searches.**

`bfs` is breadth-first search: the planner tries every plan of one cycle, then
every plan of two cycles, and so on. Breadth-first search always finds a plan if
a plan exists within the horizon, and the plan it finds is **the shortest**. A
shortest plan is worth having when the shortest plan is the interesting answer:
the seven crossings of the wolf, goat and cabbage puzzle are *the* solution, not
merely a solution. The work breadth-first search does also grows explosively as
plans get longer, and the search stops being practical somewhere around a dozen
steps.

`greedy` is greedy best-first search. Greedy search scores a state by solving an
easier version of the problem, one in which no action ever undoes anything, and
then counts how many rounds that easier problem needs to reach each goal. The
score is not exact, so the plan is not guaranteed to be the shortest, but the
search is very much faster when there are many states. Greedy search also
recognises dead ends: if even the easier problem cannot be solved from some
state, the real problem cannot be solved from that state either, so the search
abandons the state rather than merely ranking it low.

`auto`, the default, starts with breadth-first search, gives it the allowance of
states set by `nodes(N)`, and switches to greedy search if that allowance runs
out. `examples/start/blocks.lps` compares the two on the same problem: seven
blocks and seven moves, in 0.4 seconds and in 25 seconds respectively.

You can also give the options on the command line, where they override the
directive in the file:

```sh
./lps run examples/start/blocks.lps --search bfs --horizon 14 --nodes 1000
```

Under the default `lps_engine(reactive)`, writing `achieve` is an error. The
error is deliberate: no existing program can start behaving like a planning
program because someone added a line to it.

## 15. Settings

Write these settings as ordinary facts. If a value has to be calculated, write a
rule instead.

| Setting | Meaning |
|---|---|
| `maxTime(N)` | stop after N cycles. Without it, a run does not stop by itself |
| `maxRealTime(Seconds)` | stop after that many seconds of *simulated* time |
| `simulatedRealTimePerCycle(Seconds)` | how many seconds of simulated time one cycle stands for |
| `simulatedRealTimeBeginning(Stamp)` | the instant that cycle 1 corresponds to |
| `minCycleTime(Seconds)` | in a continuously running session, how long a cycle should actually take |

**There are two clocks, and they are independent.**
`simulatedRealTimePerCycle` says what a cycle *means*. `minCycleTime` says how
long a cycle should *take* on the machine, and matters only to a continuously
running session (§13, and [`ide.md`](../guide/ide.md)).

LPS2 calculates simulated time from the cycle number instead of reading the
machine's clock during a cycle. Calculating from the cycle number is what makes
a run give the same answer on any machine:

```
real_time(T) = simulatedRealTimeBeginning + T × simulatedRealTimePerCycle
```

## 16. Vocabulary the engine provides

**Fluents that are always available**, and are never declared:

| Fluent | Meaning |
|---|---|
| `real_time(Seconds)` | the simulated time of the current instant |
| `lps_user(User)`, `lps_user(User, Info)` | who is running the program, where whatever is running it supplies a name |

**Events and actions that are always available:**

| Term | Meaning |
|---|---|
| `lps_terminate`, `lps_terminate(Reason)` | end the run. You can use it as an action, or send it in from outside |
| `real_date_begin(Date)`, `real_date_end(Date)` | the start and end of a calendar day, as composite events |
| `end_of_day(Date)` | the boundary between two days |

**Predicates from outside the program.** Any predicate that the program's own
Prolog module — the private space the program is loaded into, §17 — can see,
including Prolog's own built-in predicates, may appear in the body of a rule,
and the engine simply calls it.

Two special cases have names. An **external action** is an action that has no
causal laws, and whose effect is a call to Prolog. An **external fluent** is a
fluent answered by a Prolog predicate rather than by the stored state. External
actions and external fluents are the mechanism LPS1 used for input and output.

External fluents are also why `holds(true, T)` succeeds. The program's module
can see `true/0`, so `true/0` counts as an external fluent, and it holds
trivially. The engine relies on that when it gives a composite event an implicit
end time.

## 17. Access to Prolog

An LPS file is a Prolog file, and the engine loads all of it into a private
Prolog module — a space of its own, one per program. Consequently:

- **Ordinary clauses** (§9) are available everywhere in the program.
- **Built-in predicates** are available: arithmetic, `format/2`, `sort/2`,
  `between/3`, comparison, and the predicates for names and text.
- **Library modules** can be brought in with an ordinary directive, which
  applies to the program's own module:

  ```prolog
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  :- use_module(library(clpfd)).
  ```

- **Other files** can be included:

  ```prolog
  :- include(system('date_utils.pl')).      % a helper from the LPS1 tree
  :- include('my_helpers.pl').
  ```

- **Directives** other than `lps_engine/1,2` run as ordinary Prolog directives
  when the file is loaded, and the translator otherwise ignores them.

**The sandbox.** A server that runs programs sent to it checks their Prolog as
it translates them, using SWI-Prolog's `library(sandbox)`. The check allows
arithmetic, `findall/3`, `format/2`, `assert`/`retract`, printing and the like.
The check refuses anything that reaches the machine — files, other programs, the
shell — and refuses a call put together while the program runs, because the
check cannot follow such a call. A refused program is not run, and the message
names the goal that was refused. The HTTP server — the web server — checks
unless it is started with `LPS_SANDBOX=0`; the command line does not check
unless you give it `--sandbox` or `LPS_SANDBOX=1`. The check is not a limit on
time: a program can still loop inside one cycle.

Two cautions.

Keep side effects — anything a rule does besides giving an answer, such as
printing or writing a file — out of the bodies of rules. The engine may call a
body several times in one cycle, and under the planner it calls a body against
states that are only being considered and may never come about. Put effects in
actions instead.

If one of your predicates has the same name and the same number of arguments as
a predicate of the engine's internal vocabulary — `holds/2`, `happens/3`,
`initiated/3` and so on — the engine will not see yours. Rename your predicate.

## 18. Saying how a program should be drawn: `display/2`

A program can say how its fluents and events should be drawn. The editor then
plays the run back as a picture. `display/2` is the same declaration LPS1 used
for drawing, so existing `display/2` clauses work unchanged.

```prolog
display(light(Place, on),
        [ type:raster, scale:0.2, source:'https://…/light-bulb.png', position:[X, Y] ])
    :- locationXY(Place, RX, RY), X is RX + 75, Y is RY + 120.

display(location(P, L),
        [ type:ellipse, label:P, point:[PX, PY], size:[20, 40], fillColor:green ])
    :- locationXY(L, X, Y), PY is Y + 10,
       (P = dad -> PX is X + 25 ; PX is X + 50).

display(timeless, Divisions)
    :- findall([type:rectangle, label:D, from:[X, Y], to:[TX, TY], strokeColor:black],
               ( locationXY(D, X, Y), TX is X + 150, TY is Y + 150 ),
               Divisions).
```

The first argument is a fluent or an event. The second is either **one list of
properties**, or **a list of such lists**, one for each object to be drawn.
`display(timeless, …)` describes the background: the objects that do not depend
on time.

**Shapes:**

| `type:` | Properties |
|---|---|
| `rectangle` | `from` and `to`, or `point` and `size`; `radius` rounds the corners |
| `circle` | `point` / `position` / `center`, and `radius` |
| `ellipse` | a position, and `size` |
| `arc` | a position, `radius` (or `radius1` and `radius2`), `angle`, `rotation` |
| `line` | `from`, `to` |
| `path` | `segments:[[X,Y], …]`, optionally `tension`; or `data`, an SVG path string |
| `star` | `center`, `points`, `radius1`, `radius2` |
| `regularPolygon` | `center`, `sides`, `radius` |
| `text` / `pointtext` | `point`, `content` |
| `raster` / `image` | `position`, `source` (a URL), `scale` |
| `arrow` | `from`, `to`, `biDirectional` |

**Properties any shape may have:** `label`, `fillColor`, `strokeColor`,
`strokeWidth`, `opacity`, `shadowColor`, `shadowOffset`, `fontSize`, `scale`,
`pattern` (with `patternColor` and `patternScale`).
A colour is a name, a `'#rrggbb'` code in quotes, or a list `[R, G, B]` of
numbers between 0 and 1. LPS1's `id`, `sendToBack` and `bringToFront` are
accepted and have no effect.

**Coordinates.** The origin is at the **bottom left** and y increases upwards,
as it did when LPS1 drew a scene. Sizes and positions are in pixels. The editor
scales the view to fit whatever the scene turns out to occupy.

**Four rules to observe**, all inherited from the way LPS1 drew a scene:

- a `display/2` clause must work when its first argument is not yet filled in,
  so do not put a cut, or an if-then-else, in the head position — put the
  conditions in the body;
- once the fluent or event has matched, every variable in the list of properties
  must have a value;
- the editor draws only the **first** solution for a given subject;
- the engine *calls* `display/2`, so a clause with a side effect performs that
  effect once for every scene drawn.

**The icon library.** `[type:raster, icon:NAME]` draws one of 134 pictures held
by this server, so a machine with no connection to the internet can still show
an animation. *Help ▸ About the icons, fills and objects* lists every name, with
its picture and its licence. Prefer an icon to `source:` with a URL (a web
address). Several of LPS1's examples point at clipart on sites that no longer
serve it, and those pictures now come out as holes.

**The fill library.** `pattern:NAME` fills a shape's surface with one of
nineteen tiles — `hatch`, `crosshatch`, `dots`, `grid`, `checker`, `bricks`,
`waves`, `zigzag`, `stripes`, `scales`, `honeycomb`, `noise`, … — listed in the
same dialog. A fill says what a surface is *like* where an icon says what a
thing *is*, and a fill makes the one distinction that a scene of flat rectangles
cannot otherwise make: hatched for unavailable, bricks for built, waves for
water. The tile takes the shape's own colour and inks itself to contrast with
that colour, so one name works on every colour in the scene; `patternColor`
overrides the ink and `patternScale` the tile size. This project draws the tiles
itself — no licence, no attribution, nothing fetched from elsewhere.

**Composite events are subjects too.** The engine records a composite event (§7)
with an interval of its own, and the scene offers the event to `display/2` as
`happens(Event, Start, End)`. A clause can therefore draw an *act* as a bar
worked out from the act's own beginning and end:

```prolog
display(happens(deal_with_goat(_, To), S, E),
        [ type:rectangle, from:[X0, 40], to:[X1, 54], fillColor:'#4c6ef5', label:To ])
    :- X0 is S * 24, X1 is max(E * 24, X0 + 8).
```

An act that has begun stays in the picture, so the lanes read as a history of
what the run did rather than as a flash at the cycle it finished.

**Having the drawing written for you.** The editor's *Animate in 2D* and
*Animate in 3D* buttons ask a language model for a **plan**, and the editor then
works out the positions and sizes from the plan itself. The model never writes a
coordinate, which is why the result never overlaps. One plan serves both the
two- and the three-dimensional picture.

A plan says one or more of five things about the program's fluents, and the plan
must cover **everything that changes**. Before the model plans, the editor runs
the program and tells the model which fluents come and go. A plan that leaves
one of those fluents out is handed back to the model with the missing names.

- **Containers and members**, for a fluent that says *where a thing is*, when
  the place is not itself one of the things — `loc(Object, Where)`,
  `at(Robot, Room)`, `in(Parcel, Van)`. The containers are the values the place
  argument takes; the members are the things that move from one container to
  another. Every container gets the same grid, so a thing keeps its column
  wherever it is.
- **Stacks**, for a fluent that says what a thing is standing on, when the
  support is *another thing of the same kind* — `on(Block, Support)`. You can
  recognise this case because the same names appear on both sides: `on(a, b)`
  and `on(b, c)` make `b` both a thing and a place.
- **Gauges**, for a fluent that says *what value something has* — `heating(on)`,
  `temperature(14)`, `balance(alice, 100)`. Nothing moves. Each gets a labelled
  box showing what it currently says.
- **Lamps**, for a fluent that is simply true or false — `alerted`, `stopped`,
  `in_station`. A gauge with its `value_var` left out is a lamp. The box is
  there while the fluent holds and gone while the fluent does not hold.
  Underneath the box sits an **empty socket** — a dim outline, with the
  caption — which stays, so that off looks like off rather than like a picture
  that failed to draw. A program whose state is a handful of flags — the London
  Underground notice is one — has no other shape it can be drawn with.

A gauge or a lamp may be **keyed**: `balance(Who, Amount)`, `available(Fork)`,
`fire(Room)` say something about *one of several things*, and each of those
things gets a socket of its own, captioned by which one it is. Without a key
only the first would ever be drawn — `display/2` gives one solution per subject
— so five free forks would be one box with four ghosts underneath it. The editor
settles which argument the key is, and which values that key takes, against the
**run** rather than taking the plan's word for it. A fluent that holds of
several of its instances in the same cycle is a set of things and gets a box
each; a fluent that never does is a value and gets one box (`temperature(14)`
and `temperature(15)` are two cycles, not two boxes).
- **Spans**, for a **composite event** — `deal_with_goat(From, To) from T1 to
  T2 if …`. Each composite event gets a lane of its own and one bar per
  occurrence, drawn from the act's own start to its own end. A span is the only
  *narrative* shape a program can state, and the bars build up into a chart of
  what the run did. A lane is for things that **take time**: an act whose start
  is its end is drawn as a tick rather than a bar, and a bar too narrow for its
  own label is drawn without one. (The timeline lists every occurrence, whatever
  its width.)

**A plan that nearly says a shape is drawn as that shape.** A layer whose
template names a particular thing (`loc(wolf, Where)`), or whose `member_var` is
not one of its template's variables, has no two arguments to be a container and
a member with. The editor draws such a layer as the shape it nearly says — a
gauge of what that one thing is doing, or a lamp per thing where the run shows
several — and a note says what happened. What is *reported* back is then what
was actually drawn: the editor measures both the count of containers and things
in the summary, and the check that hands an uncovered fluent back to the model,
on the scene it generated and not on the plan.

**What the plan is not asked.** Two things the *program* already knows are read
off the program rather than asked of the model. The first is which of its
fluents are **intensional** (§8); the editor draws those as outlines, because no
event sets an intensional fluent, and a reader who takes one for a stored fluent
goes looking for the event that set it. The second is the order in which the
program's **rules** mention its fluents, which is the order the editor lays them
out in, so that two fluents appearing in one rule are drawn side by side. A
member of a plan may also carry a `pattern` (a fill, above) and a `model` (a
named 3D object, §18a).

**A stack is not a container.** If the editor draws a blocks-world program as
containers and members, the result is one box per block, each holding one small
square, every block drawn twice — once as a container and once as a thing — and
no tower anywhere. The editor therefore treats a plan that makes containers out
of things it also puts *inside* containers as a stack instead, and a note says
so.

A stack has no table of positions, because how high a block is drawn depends on
how many blocks are underneath it, and the number underneath changes from cycle
to cycle. The editor generates instead two short rules that work their way down
the state — `lps_pile_top/2` and `lps_pile_x/2`, which call `state/1`.
`examples/start/blocks3d.lps` writes the same thing out by hand. The drawing
layer points `state/1` at the cycle being drawn, so the tower in the picture is
the tower as it stands at that cycle, and blocks move in and out of the tower as
the program moves them.

**How much of this document the assistant is given.** A question you type gets
the whole document. The two *Animate* buttons get only the sections that help in
reading a program — §§1, 3, 4, 5, 8 and 11 — taken from this file by section
number, so there is no second copy to fall out of step with the original. Those
sections come to about 1,500 tokens rather than 9,000, a token being the unit in
which a language model measures text, roughly three-quarters of a word.

The difference has a practical cause. With a program and the icon catalogue
added, the whole reference took a request past 12,000 tokens, and a model whose
limit is 8,192 tokens refused the request. The editor likewise works out the
space it reserves for the answer from the size of the program, rather than
fixing that space, for the same reason. Some providers say how much text a model
can be given at once — Groq does; OpenAI and Anthropic do not — and where a
provider says so, the editor marks the models that are too small and refuses
beforehand to send the request, naming a model that would fit.

What ends up in your file is ordinary Prolog: a table of positions (`lps_slot/4`
for containers, `lps_cell/6` for the gauges' and lamps' cells, or `lps_column/2`
plus the two rules that work down a stack), a
background, and one `display/2` rule for each layer, stack, gauge and lamp. The
three-dimensional versions carry a `3` in their names — `lps_slot3/4`,
`lps_cell3/5`, `lps_column3/2`, `lps_pile_top3/2` — so that one program can hold
both pictures at once. The two pictures share `lps_look/3`, because what a thing
looks like is the same fact in two dimensions and in three.

## 18a. Three dimensions: `display3d/2`

`display3d/2` is a separate declaration, not a re-reading of `display/2`.
Two-dimensional properties do not carry over into three dimensions without
misrepresenting what the author meant, and a program may reasonably want both
pictures at once, showing different things.

```prolog
display3d(on(Block, Support), [ type:box, position:[X, Y, 0], size:[1.6, 1.6, 1.6],
                                color:Colour, label:Block ]) :-
    block_colour(Block, Colour), x_of(Block, X),
    height_of(Support, H), Y is H + 0.8.

display3d(timeless, [ [type:ground, size:[24, 24], color:'#23262e'],
                      [type:camera, position:[7, 5, 10], lookAt:[0, 1.6, 0]],
                      [type:light,  position:[6, 12, 8], intensity:1.2] ]).
```

| `type:` | Properties |
|---|---|
| `box` | `position`, `size:[W,H,D]` |
| `sphere` | `position`, `radius` |
| `cylinder` | `position`, `radius`, `radius2`, `height` |
| `cone` | `position`, `radius`, `height` |
| `plane` | `position`, `size:[W,H]` |
| `ground` | `size:[W,H]` — a plane at y = 0 |
| `line` | `from:[X,Y,Z]`, `to:[X,Y,Z]` |
| `arrow` | `from`, `to` |
| `text` | `position`, `label`, `scale` |
| `model` | `position`, `model:NAME`, `scale` — a named object from the catalogue |
| `camera` | `position`, `lookAt` — only inside `timeless` |
| `light` | `position`, `intensity`, `color` — only inside `timeless` |

Properties any object may have: `color`, `opacity`, `rotation:[Rx,Ry,Rz]` in
degrees, `label`, `labelScale`, `pattern` (the same fill library as §18, used
here as the material's texture).

**The object catalogue.** `[type:model, model:tree]` — or simply `model:tree`
on any object — draws one of thirty-four named things: `person`, `robot`,
`animal`, `tree`, `house`, `bank`, `hospital`, `factory`, `car`, `truck`,
`train`, `boat`, `plane`, `box`, `crate`, `barrel`, `bag`, `coin`, `key`,
`door`, `flag`, `sign`, `table`, `chair`, `bed`, `cup`, `book`, `rock`,
`cloud`, `fire`, `bulb`, `tower`, `arrow`, `bird`. *Help ▸ About the icons,
fills and objects* lists them with what each is for. The catalogue is to a
three-dimensional scene what the icon library is to a two-dimensional one: a
floor plan of boxes becomes a scene of things.

The editor **builds** each object out of simple shapes, in the object's own
`color`, so the object appears instantly, grows and shrinks with `scale`, and
cannot go missing the way a ready-made shape fetched from elsewhere can. The
editor ignores a `model:` name the catalogue does not have and draws the
object's own `type:` instead, so naming a model is always safe. (The CC0
libraries of ready-made shapes — [Kenney](https://kenney.nl/assets),
[Quaternius](https://quaternius.com), [Poly Pizza](https://poly.pizza) — are the
route if photoreal objects are ever wanted. The cost is megabytes, a piece of
software to read them, and a download while the editor is built, for things a
scene shows at the size of a thumb.)

**Coordinates** are right-handed with **y upwards**. Upward y is three.js's own
convention, and unlike the two-dimensional case there are no existing programs
with an opinion about which way is up.

**Animate in 3D uses the same plan as Animate in 2D** (§18). The grid of
containers becomes a floor plan — what is (x, y) in two dimensions is (x, z) in
three — things stand up out of their slab, a stack becomes a tower, and the
editor works the ground, the camera and the light out for itself rather than
remembering them. A member of the plan that names a `model` stands there as that
object; a member that does not is a box, as before.

**A declared camera is a starting camera.** The editor obeys a declared camera
when it first draws the scene and not afterwards, so moving the cycle slider
does not undo a zoom. The ⤢ button returns to the declared camera.

**Labels take their colour from the current theme** and are outlined in the
background colour, so they stay legible on a light background and where they
cross a solid object. `color:` overrides the colour of the text; the outline
stays.

## 18b. The mouse as an input

An animation can be something you act on, rather than only a picture. A program
that **declares `lps_mousedown/3`, `lps_mouseup/3` or `lps_mousedrag/3` as
events** receives those events from a two- or three-dimensional window that is
following a continuously running session. Each such event carries the position
of the pointer, in the program's own coordinates, and which button was used.

```prolog
events lps_mousedown(_, _, _).

%  The reverse of the drawing below — a scene and its hit test have to agree.
lamp_at(X, N) :- N0 is X // 70, N is N0 + 1, N >= 1, N =< 4.

if   lps_mousedown(X, _, _) from _ to T1, lamp_at(X, N)
then toggle(N) from T1 to T2.
```

A program that does not declare those events receives nothing, and the window
watches for nothing at all: a click on the picture stays a click on a picture.
The server makes the decision, from the program itself. The set of mouse events
the program is allowed to receive **is** the set of rules it writes for dealing
with them, so opening an animation cannot become a way of manufacturing an event
the program did not ask for.

In three dimensions, the window reports the position at which a straight line
from the pointer into the scene meets the ground plane, given as `(x, z)`.
`examples/start/lights.lps` is a worked example.

## 19. The operator table

These operator declarations are what let Prolog read the written form: they tell
Prolog how the words of a sentence group together. `src/core/lps_ops.pl`
declares them, and any program that reads LPS terms needs them in scope.

| Priority | Type | Operators |
|---:|---|---|
| 1200 | `xfx` | `then` |
| 1190 | `xfx` | `if` |
| 1185 | `fx` | `if` |
| 1100 | `xfy` | `else` |
| 1050 | `xfx` | `initiates`, `terminates`, `updates` |
| 1050 | `fx` | `observe`, `false`, `initially`, `fluents`, `events`, `prolog_events`, `actions`, `unserializable`, `achieve` |
| 1050 | `xfy` | `::` |
| 999 | `fx` | `update`, `initiate`, `terminate` |
| 997 | `xfx` | `in` |
| 995 | `xfx` | `at`, `during`, `from` |
| 994 | `xfx` | `to` |
| 900 | `fy` | `not` |

`from` binds less tightly than `to`, so Prolog reads `E from T1 to T2` as
`from(E, to(T1, T2))`.

## 20. Running a program

```sh
./lps run prog.lps                     # run to maxTime, printing the trace
./lps run prog.lps --cycles 5 --json
./lps step prog.lps --cycles 3         # one report per cycle
./lps state prog.lps                   # the fluents at the end
./lps dump prog.lps                    # the internal form, then the program's own Prolog
./lps explain prog.lps --ask "why(happened(row(south,north)), 2)"
./lps explain prog.lps --ask "why_not(happened(pay(bob,10)), 4)"
./lps timeline prog.lps
./lps changes prog.lps --at 2
./lps automaton prog.lps
./lps live prog.lps --cycle-ms 400     # a session that does not stop; type events
./lps solidity prog.lps                # the program as a Solidity contract, or why not
./lps ide                              # the editor, in a browser, on port 3060

./lps pddl domain.pddl problem.pddl    # a PDDL problem, planned
./lps drools rules.drl                 # a Drools rule file, run
./lps play story.le                    # an interactive-fiction story (needs LE2)
./lps inform story.ni --out DIR        # an Inform 7 source, as a Logical English story
```

Everything the command line and the editor do goes through a single web request,
`POST /lpsapi`, which carries an `operation` field saying what is wanted. You
can therefore do anything the editor can do with `curl`, the command-line tool
for making web requests. See [`ide.md`](../guide/ide.md).

**Deploying as Solidity.** `./lps solidity` (and the editor's *Misc ▸ Deploy as
Solidity*) writes a program as a smart contract, a program that runs on a
blockchain: fluents become state, each action a function, each precondition a
`revert`, each causal law a state write, `initially` the constructor. Only
programs with a straight translation are written. Reactive rules, intensional
fluents, composite events, planning, events that the environment observes rather
than actions someone calls, the program's own Prolog, timeless rules, a read
that would have to search a fluent, non-integer arithmetic and constraints over
two actions are each refused, with the line they come from, and nothing is
written. A fluent with a default (§3) is written as a plain mapping when its
default is the zero of its type; any other default is refused.

## 21. Further reading

**The language and the theory behind it**

- Robert Kowalski and Fariba Sadri, *Reactive Computing as Model Generation*,
  New Generation Computing 33(1), 2015 — the declarative and operational
  semantics of LPS.
  <http://www.doc.ic.ac.uk/~rak/papers/LPS%20revision.pdf>
- Robert Kowalski, *Computational Logic and Human Thinking: How to be
  Artificially Intelligent*, Cambridge University Press, 2011 — the thinking
  underneath, and the source of the programs in `examples/collections/kowalski-book/`.
- The KELPS kernel, on the RuleML wiki:
  <http://wiki.ruleml.org/index.php/KELPS>
- The LPS group at Imperial College: <https://lps.doc.ic.ac.uk>
- The RuleML 2017 LPS tutorial and the CLOUT 2017 workshop slides, in
  `legacy_lps1/doc/`.
- `docs/project/historical/Combining Logic Programming and Imperative Programming in
  LPS`.

**This implementation**

- [`glossary.md`](glossary.md) — the terms used in these documents.
- [`plan-of-record.md`](../../project/plan-of-record.md) — the development plan: the engine, the
  agent, the other input languages.
- [`selection-spec.md`](../../dev/semantics/selection-spec.md) — the twenty rules saying where the
  engine has a choice and which way it goes.
- [`conformance_lps2.md`](../../dev/conformance/conformance_lps2.md) — LPS2 measured against LPS1's
  own test recordings.
- [`le-for-lps.md`](le-for-lps.md) — Logical English, for the same
  language.
