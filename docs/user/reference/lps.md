# The LPS language: a reference

*Kind: reference · Audience: users, developers, the assistant (read by lps_assistant.pl) · Status: current (2026-09-29)*

This document describes all the things that you can write in an LPS (Logic
Production Systems) program, one construct at a time. The document tells you
about the declarations and the rules. It also tells you about the vocabulary
that the engine gives, how a program says how to draw it, and what a program
can use from Prolog.

This document describes the language as you type it into a `.lps` file or a
`.pl` file. The earlier implementation of LPS accepts the same language. Thus
programs for that implementation run here with no change.

This document uses two words frequently. Know their meaning before you start.

- The **written form** is the text that you type. This document is about the
  written form.
- The **internal form** is the form into which the system changes the written
  form before the engine runs the program. You never have to write the internal
  form yourself. But you can look at it (refer to §20), and error messages
  sometimes refer to it.

Related documents:

- [`lps-tutorial.md`](../tutorials/lps-tutorial.md) shows full programs, step by step.
- [`glossary.md`](glossary.md) defines the terms of this document and of the
  other documents.
- [`le-for-lps.md`](le-for-lps.md) describes Logical
  English. Logical English is a different written form, and the system changes
  it into the same internal form.
- [`ide.md`](../guide/ide.md) describes the editor.

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

An LPS program describes something whose behaviour is a sequence of **states**,
with **events** between the states. Examples are an agent, a simulated world, a
contract and a machine.

The engine does one cycle again and again. In each cycle, the engine does these
steps:

1. It collects the events that occurred after the previous cycle.
2. It applies the effects of those events to the state. It uses the **causal
   laws** (§5) for this step.
3. It finds the **reactive rules** (§6) whose conditions are true in the new
   state. It adds the conclusions of these rules to the goals that it already
   has.
4. It works on each goal, and it starts with the goals from earlier cycles. It
   changes each goal into actions through **composite events** (§7),
   **intensional fluents** (§8) and ordinary **Prolog clauses** (§9).
5. It selects each action at the moment when it gets to the action. The
   exception is when a **constraint** (§10) prevents the action. A prevented
   action waits for a later cycle, if its time lets it. The selected actions
   become the events of the next cycle.

§13a describes the full cycle, with an example. It gives the order of the steps,
which goal is first, when an action waits, and when the run fails.

Time is a cycle counter: 1, 2, 3, and so on. A **fluent** is true *at* an
instant. An **event** or an **action** occurs *from* one instant *to* a
different instant. Almost all of this document is about how to say which
fluents are true at which time, and which events occur from which time to which
time.

This is a full program:

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

To run the program, use `./lps run tiny.lps`.

## 2. Files and forms

| Extension | What it contains | Read by |
|---|---|---|
| `.lps` | the written form that this document describes | the translator |
| `.pl` | the same written form; the examples of LPS1 use it | the translator |
| `.le` | Logical English — refer to [`le-for-lps.md`](le-for-lps.md) | LE2, which makes the internal form |
| `_.P` | the internal form, as the translator of LPS1 makes it | read directly |
| `.lpsw` | the internal form; from now on, the preferred extension for it | read directly |
| `.ni`, `.inform` | Inform 7 statements, changed into a Logical English story | `src/syntax/lps_inform.pl`, then LE2 |

A `.le` document and a `.lps` file with the same name next to it are **one
program**. The system translates the two files together, and the `.le` document
first. The `.lps` part is the **companion file**. It contains the parts that are
not English, in the written form of this document: `display/2` clauses and
Prolog helpers.

A file in the written form **is a Prolog file**. The Prolog predicate
`read_term/3` reads it, with the operators of §19 available. Each clause in the
file is an LPS construct or an ordinary Prolog clause. You can mix the two kinds
of clause as you like. Comments are Prolog comments: `%` to the end of the line,
or `/* … */` for a block.

The translator reads the file **one time, from top to bottom**. The order of
the file is important. A bare `f(x)` in a rule can be a fluent or an event. What
the file said about `f/1` before that rule decides which one it is (§3). Thus
declare a predicate before you use it.

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
| `fluents F1, F2, …` | these are fluents: they *are true at* instants, and causal laws change them |
| `events E1, …` | these occur, and they come from outside the program (§13); the program does not select them |
| `actions A1, …` | these occur, and the program *selects* them when it changes goals into actions |
| `prolog_events E1, …` | events whose occurrence a call to Prolog decides; the engine does not decide it |
| `unserializable A1, …` | actions whose effects the engine calculates together, all from the state before it applied the actions of the cycle (refer to the text below) |

The arguments in a declaration are placeholders. `fluents loc(_, _)` declares
`loc/2`. The underscores have no specific meaning. You can put many templates in
one declaration, with commas between them. The same declaration can occur more
than one time.

**`unserializable`.** By default, the engine applies the actions of one cycle
one at a time. Thus two `updates` of the same fluent in one cycle use each
other's results. For the actions in `unserializable`, the engine calculates all
their effects together. It does this before it applies the other actions.

Declarations are **advisory, not obligatory**. A program with no declarations
still runs. The reason is that the translator finds the kind of each predicate
from the first use of the predicate in the program. `f at T` makes `f` a fluent,
and `f from T1 to T2` makes `f` an event. But it is better to declare. The
translator checks the declaration. The declaration tells a reader the meaning of
the program. And with declarations, the program does not depend on the order of
the parts of the file.

You can also give a default value to a fluent, with `defaults/1` (§3a).

## 3a. Defaults

Some fluents have a value as their last argument, for example a balance or an
owner. You can give such a fluent a default. The default is the value of the
fluent for each key that has no stored fact:

```prolog
fluents  balance(_, _).
defaults([balance(_, 0)]).
```

`defaults/1` is an LPS2 declaration, and LPS1 does not have it. You write it as
an ordinary fact that contains a list, with one term for each fluent. The last
argument of each term is the default of that fluent. In Logical English, you
write the same thing as `; 0 by default`.

- When the key has a value, the fluent has its stored value. If there is no
  stored value, the fluent has the default. For an account that the program
  never refers to, `balance(carol, B) at T` gives `B = 0`. The engine never
  stores the default. Thus the state and the trace show only the stored
  entries.
- When the key has no value, the engine shows only the stored entries.
- Thus `not balance(carol, _) at T` fails, because carol has a balance.
- An `updates` law uses the default as the old value of a key that has no stored
  value. Thus `deposit(P, A) updates Old to New in balance(P, Old) if New is Old + A`
  adds money to a new account, and the account does not have to be initiated
  first. In such a law, the engine first does the conditions that do not refer
  to the old value. Thus those conditions can decide which key is meant. The
  engine updates each different key one time.
- `why(holds(balance(carol, 0)), T)` gives the answer *(the default: no entry was
  stored)*. The timeline of the editor shows one *every other: …* line for each
  default.

A program without `defaults/1` runs exactly as before.

## 4. The initial state

```prolog
initially loc(wolf, south), loc(goat, south), loc(farmer, south).
```

The initial state is a list of the fluents that are true at time 1, with commas
between them. A fluent that is not in the list is not true. The engine treats
the state as complete. Thus a fluent that the program does not say is true is
false.

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
on the same fluent. Use `updates` where you can. The one sentence says that the
fluent *changes its value*. It does not say that one fluent disappears and a
different fluent appears. The planner (§14) can use this difference.

The engine examines the conditions of a causal law **in the state from which
the event started**. A law with no conditions applies each time that its event
occurs.

## 6. Reactive rules

A reactive rule says: each time that this occurs, make that true.

```prolog
if   Antecedent
then Consequent.
```

The antecedent is the part after `if`. It is a sequence of literals. A literal
is one statement with a time (§11): a fluent that is true, or an event that
occurred. The consequent is the part after `then`. It is a sequence of actions,
composite events and fluent conditions that the engine must make true.

```prolog
if   light(Place, on) at T1, not location(dad, Place) at T1
then goto(dad, Place) from T2 to T3.

if   loc(Object, south) at T, Object \= farmer
then makeLoc(Object, north) from T to T2.

if   payment_due(Party, Amount) at T
then pay(Party, Amount) from T to T2, notify(Party) from T2 to T3.
```

A reactive rule is a **standing goal**. It is not an instruction that runs one
time and is then complete. When a rule starts, the engine keeps the consequent
of the rule as an open goal. The goal stays open until it is true or becomes
impossible. A reactive rule is not a trigger that operates one time only. The
times in the consequent say *when the actions can occur*. They do not say when
the actions must occur.

There are two ways to write the time of the consequent, and their behaviour is
very different. In `then a from T2 to T3`, the times are new names. Thus the
action can occur in any cycle, and the engine does it in the first cycle that
lets it. In `then a from T to T2`, `T` is the time of the antecedent. Thus the
action must occur in the same cycle in which the rule started. If a constraint
prevents the action in that cycle, the goal cannot be true and the run fails.
§13a shows the two ways.

A rule starts again in each cycle in which its antecedent is true. After the
engine makes a goal, it works on the goal also when the antecedent stops being
true.

A rule can also have an explicit priority. In the internal form, you write the
priority as `reactive_rule(Antecedent, Consequent, Priority)`. The written form
has no notation for a priority.

## 7. Composite events

A composite event is an event with a name, defined as a sequence of other
events. Thus one name refers to many occurrences. This method to name a
sequence is the equivalent in the language of a subroutine. A subroutine is a
part of a program that has a name. The other parts of the program can then use
the subroutine by that name.

```prolog
makeLoc(Object, Location) from T1 to T3
    if  loc(Object, L2) at T1,
        row(L2, Location) from T2 to T3.

dealWithGoat(L1, L2) from T1 to T2
    if  makeLoc(goat, L2) from T1 to T2.
```

The head is the part before `if`. The head is an event. Either a declaration
says that it is an event, or its explicit `from … to …` shows that it is an
event. The body is the part after `if`, and it is a sequence. You can define a
composite event with a different composite event.

A composite event with more than one defining clause is a real choice. The
engine tries the clauses in their order in the file. If the first clause does
not succeed, the engine goes back and tries the next clause.

If you do not write the interval of the head, the engine makes it the same as
the interval of the body. Thus you can write `makeLoc(O, L) if …`, and the
composite event takes exactly as much time as its body.

## 8. Intensional fluents

An intensional fluent is a fluent that the engine *calculates* from the state.
The engine does not store it in the state.

```prolog
total_due(Party, Total) at T
    if  findall(A, owes(Party, A) at T, As),
        sum_list(As, Total).

adjacent(X, Y) at _ if next_to(X, Y).
```

The head is a fluent. The engine calculates the body again each time that
something asks about the fluent. Intensional fluents are never initiated or
terminated. They follow from the stored state, whatever it is.

The engine reads the body of an intensional fluent at **one instant**. A literal
in the body that does not give its own time is at the instant of the head.

## 9. Timeless clauses

A timeless clause is an ordinary Prolog clause. It has no relation to time.

```prolog
locationXY(livingroom, 0, 0).
locationXY(kitchen, 150, 0).

destructive(delete_file(_)).
beats(rock, scissors).
beats(scissors, paper).

pixels(X, Y, CX, CY) :- CX is X * 20 + 10, CY is Y * 20 + 10.
```

Timeless clauses say what things *mean*. They do not say what occurs or what is
necessary. You can call a timeless clause from all locations: from the body of a
rule, from the condition of a causal law, and from a `display/2` clause.

A program that the system translated from Logical English writes the rules of a
timeless relation in the internal form, as `l_timeless/2`. It writes the facts
of the relation as ordinary Prolog facts. The engine answers such a relation as
a part of the program, from its rules and from its facts. A question that the
rules and the facts do not match fails. A negated question
(`it is not the case that …`) is the negation of that answer. The engine never
calls a Prolog predicate that has the same name.

## 10. Constraints and preconditions

```prolog
false Conditions.
```

A `false` sentence says that its conditions must never all be true at the same
time. There is one construct, but it has two meanings. The things that the
conditions refer to decide which meaning applies.

**A constraint on states.** The sentence does not refer to an action. Thus the
sentence is a constraint on states.

```prolog
false balance(Account, B) at _, B < 0.
```

**A precondition.** The sentence refers to an action. Thus the sentence prevents
that action in those conditions.

```prolog
false goto(dad, Place1), goto(dad, Place2), Place1 \= Place2.
false pay(P, A), not has_funds(P, A).
```

**A constraint on the result of an action.** Here the engine reads the fluents
at the *end* time of the action. Thus the constraint is about the state that
the action will make. It is not about the state from which the action starts.

```prolog
false loc(goat, L) at T, loc(wolf, L) at T, not loc(farmer, L) at T, row(_, _) to T.
```

`row(_, _) to T` means "a crossing that ends at T". The state at T is the state
that the crossing will make. Thus the sentence rejects the crossing before the
crossing occurs. This is how the language itself says "look one step ahead".
The planner (§14) uses the same method.

An action that a constraint prevents is not an error. The engine goes back and
looks for a different way to make the goal true. The different way can be a
different definition of a composite event. It can also be the same action in a
later cycle, if the times of the goal let a later cycle occur. When there is no
other way, the goal fails. A goal from a reactive rule then makes the full run
fail (§13a). To find which sentence prevented the action, ask:

```sh
./lps explain PROGRAM --ask "why_not(happened(A), T)"
```

**The engine also checks observations.** A precondition applies to events that
come from outside (§13), and to the actions that the program selects. Possibly
the conditions of a precondition are true in the state in which the observed
events come in. Then the engine **refuses** those events, and the events do not
occur. The other events observed for the same cycle also do not occur, because
the engine refuses all the observations of one cycle together. The engine
records the refusal. `why_not(happened(E), T)` gives the answer
`refused_by_constraint`, with the sentence and the values that made it true. The
timeline of the editor shows the refused event with a line through it. In a
program that is a model of a contract, a refused event is a call that reverts.

```prolog
false withdraw(P, A), balance(P, B), A > B.

observe withdraw(alice, 10) from 1 to 2.    % refused if alice holds less than 10
```

## 11. Literals and their times

Each literal in the body of a rule has a time. You write the time, or the
literal takes the time from its position.

| Written | Meaning | Internal form |
|---|---|---|
| `F at T` | fluent `F` is true at instant `T` | `holds(F, T)` |
| `F` (a declared fluent) | is true at the instant of the clause around it | `holds(F, T)` |
| `E from T1 to T2` | event `E` occupies that interval | `happens(E, T1, T2)` |
| `E to T2` | … ends at `T2`, the start has no limit | `happens(E, _, T2)` |
| `E from T1` | … starts at `T1` | `happens(E, T1, _)` |
| `E during [T1, T2]` | … at some time in that interval | `happens(E, T1, T2)` |
| `E` (a declared event or action) | occupies the interval of the clause around it | `happens(E, T1, T2)` |
| `not F at T` | `F` is not true at `T` | `holds(not F, T)` |
| `not (Sequence)` | the sequence cannot be true | `holds(not …, T)` |
| `findall(X, Conds, L)` | collect values from the state at one instant | `holds(findall(…), T)` |
| `if C then A else B` | a condition with two alternatives in a body | `(C -> A ; B)` |

A literal that gives its own time keeps that time. A literal that gives no time
takes the time of the clause that contains it. The engine reads some parts at
one instant: the body of an intensional fluent, the conditions of a causal law,
a `false` sentence, and the argument of `not`. In those parts, each literal
without its own time is at that one instant.

You can calculate times: `T2 is T1 + 3`, `T1 < T2`, and the usual comparisons,
all as in Prolog.

## 12. Changing the state directly

Sometimes there is no event that is worth a name, and the program only wants to
change the state. The engine gives three actions for that purpose.

```prolog
if   emergency at T
then initiate alarm(on) from T to T2.

if   cleared at T
then terminate alarm(on) from T to T2.

if   sale(Amount) at T
then update B1 to B2 in balance(shop, B1) from T to T2.
```

`initiate F`, `terminate F` and `update Old to New in F` accept the same time
endings as all other events (§11). The three are ordinary actions in all
aspects. Preconditions apply to them, they are in the trace, and the engine can
explain them.

## 13. Observations

An observation is an event that comes from outside the program. You can write
observations in the program itself. This is how you write a test scenario as a
script.

```prolog
observe payment(alice, 100) from 2 to 3.
observe request(bob) to 5.
observe tick, tock from 4 to 5.
```

An observation is the only way for a predicate declared with `events` to come
into a run. The program selects its `actions`, and the world gives its `events`.

Some programs get their events from the real world, not from a script. Such a
program receives the same events through the network (the `observe` operation),
or through the mailbox of a continuously running session. The program itself
does not change.

The preconditions of the program apply to observed events. The engine refuses
an observed event when one of those preconditions is true (§10).

A continuously running session can also control **who can send which events**.
You start the session with a list of **channels**. Each channel gives the event
predicates that it can carry. The session discards an event whose predicate is
not on the list of its channel. The session tells you about each discarded
event. It does not discard an event silently. The mouse events of §18b come on a
channel whose list is the declarations of the program itself.

## 13a. How a program runs, step by step

This section answers the questions that §1 does not answer. It tells you the
order of the work of the engine in a cycle, and which goal the engine works on
first. It also tells you when the engine selects an action, when an action
waits, and when a run fails. We ran the programs of this section to check all
of the statements below. The tutorial
[How a program runs](../tutorials/how-lps-runs.md) teaches the same subjects
more slowly, with exercises.

### Time, and where a run's records go

The engine records the **initial state** at time 0. The initial state is the
state of cycle 1. The engine then runs cycle 1, cycle 2, and so on, until
`maxTime`.

An action that the engine selects in cycle `T` occurs **from `T` to `T+1`**.
The trace shows the action below `events/T+1`, and the effects of the action
are in `fluents/T+1`. Thus the line `events/3 [serve(ann)]` means that the
engine selected `serve(ann)` in cycle 2.

The trace shows an observed event `observe e from 2 to 3` below `events/3` in
the same way, and the event has its effect in `fluents/3`. An event that the
program receives and an action that the program selects can both occur from 2
to 3. Then they occur together, as one step.

### The steps of one cycle

In cycle `T`, the engine does these steps, in this order:

1. **It records what occurred from `T-1` to `T`.** These are the actions that
   it selected in the previous cycle, and the events observed for that step.
2. **It updates the state.** The causal laws (§5) of those events and actions
   give the state at `T`. The engine reads the conditions of a causal law in the
   state from which the event started. The engine applies the effects of many
   actions one action after the other. Thus two `updates` of the same fluent in
   one step use each other's results (§3, `unserializable`).
3. **It starts the reactive rules.** Each reactive rule whose antecedent is true
   at `T` starts one time for each way in which the antecedent is true. For
   example, `if waiting(P) at T` with two persons waiting gives two **rule
   instances**. Each rule instance adds one **goal** to the goals that the
   engine already has. The goal is the consequent of the rule, with the values
   that the engine found. An antecedent that refers to an event is true in the
   cycle in which the event *ends*. Some antecedents continue through many
   cycles (`badge from T1 to T2, pull from T3 to T4`). The engine follows such
   an antecedent from cycle to cycle. The rule starts in the cycle in which its
   last condition becomes true.
4. **It records the state at `T`** (`fluents/T`).
5. **It takes in the observations for the step from `T` to `T+1`.** If a
   precondition prevents those events, the engine refuses all of them (§10).
   Observed events come before the actions of the program. For example, take a
   precondition such as `false a, e`. When the event `e` is observed for the
   same step, the action `a` waits.
6. **It works on the goals**, one after the other. The goals from earlier
   cycles are first (refer to *Which goal goes first* below). The engine takes each goal from left to
   right. It continues with the goal as far as the goal can go in this cycle:
   - The engine checks a fluent condition against the state at `T`. The goal
     waits there in two conditions: the condition gives a later time, or the
     condition is not true yet and its time is free.
   - The engine replaces a composite event (§7) with its definitions. When there
     are many definitions, the engine works on all of them at the same time, in
     the order of the file. The engine keeps the first definition that is
     complete, and it stops the other definitions. The engine does not cancel an
     action that a stopped definition already selected. For example, with
     `job if a1, a2` and `job if b`, `a1` and `b` both occur in the first cycle,
     and then `b` completes `job`.
   - The engine **selects** an action whose start can be `T`, immediately. The
     exception is when a precondition prevents the action (refer to the text
     below). An action whose start is later waits.
7. **It checks the constraints on the next state.** From the selected actions
   and the observed events, the engine calculates the state at `T+1`. Then it
   checks each `false` sentence against that state. This includes the sentences
   about the result of an action (§10). If a sentence is not obeyed, the engine
   goes back through its selections in step 6. It then delays some actions until
   a later cycle. Possibly no action can be delayed, because the related actions
   have fixed times. Then the run fails.
8. **It moves to cycle `T+1`**. It keeps each goal that is not complete.

### When an action is chosen, and when it waits

The engine selects an action **as early as the times of the action let it**.
Thus the engine acts on a goal with free times in the cycle in which it made the
goal.

The engine checks a precondition at the moment when it gets to the action. It
checks the precondition against the state at `T`, the events observed for the
step, and the actions that it already selected for the same step. If the
precondition prevents the action, the next result depends on the times of the
action:

- **The times are free** (`then serve(P) from T2 to T3`): the goal waits. The
  engine tries again in the next cycle, and in each cycle after that.
- **The start is fixed** (`then serve(P) from T to T2`, where `T` is the time of
  the antecedent): the action cannot occur later. Thus the goal fails.

A goal that waits for all of the run is not an error. The run still ends in `success`
when it gets to `maxTime`.

### When a run fails

A goal that a reactive rule made must become true. If such a goal cannot become
true any more, the engine stops the cycle, and the full run ends in `failure`.
A goal cannot become true any more in these conditions:

- Its action has a fixed time, and a precondition prevents the action at that
  time.
- A deadline in the consequent is past. For example, `then a from T2 to T3,
  T3 =< 3` fails in cycle 4 if `a` did not occur before that cycle.
- Each definition of a composite event that it needs failed.

Thus a rule whose consequent must occur immediately is a promise that the action
will be permitted. When the engine cannot keep that promise, write the times as
free, or add a condition to the antecedent.

### Which goal goes first

Sometimes many goals need the same cycle. An example is when a precondition
permits only one of two actions. The engine uses the order in which it works on
the goals to decide:

- The goals from earlier cycles come **before** the goals made in this cycle.
- In the goals made in the same cycle, and in the goals from earlier cycles, the
  order is an internal detail. This detail comes from LPS1, the earlier
  implementation. The engine does not keep the goals from earlier cycles in the
  order of their age. Thus a goal that waited longer is not always tried first.
  The order is fixed for a given program. But it does not follow the order of
  the rules in the file or of the facts in the state, and it can change from
  one cycle to the next. `docs/dev/semantics/selection-spec.md` (SP1, SP4 to
  SP6) describes the order for developers.

Do not write a program whose meaning depends on that internal order. If one
goal must go before a different goal, say so in the program. For example, the
precondition
`false serve(P), waiting_since(P, T1), waiting_since(_, T2), T2 < T1` makes the
customer who waited longest go first, whatever the order of the engine is. The
tutorial runs a program with that precondition and without it.

### Goals are kept, and are not repeated

After the engine makes a goal, it works on the goal until the goal is true or
fails. It does this also when the antecedent that made the goal stops being
true. In the program below, the two rules start in cycle 1. The precondition
permits only one of the two actions in each cycle. The engine does `second`
first, and `second` ends `go`. The engine still does `first`, one cycle later:

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

A rule whose antecedent stays true starts again in each cycle, and adds a goal
each time. A goal that asks for exactly the same thing as an earlier goal adds
no new action: one action makes the two goals true.

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

| cycle | the state | the rule starts for | the goals, in the order tried | selected | why |
|---|---|---|---|---|---|
| 1 | Ann and Bob wait; the café is closed | Ann, Bob | Ann, Bob | nothing | `false serve(_), not open` prevents the two actions. Their times are free, thus the two goals wait. `opens` is observed for the step from 1 to 2 |
| 2 | Ann and Bob wait; the café is open | Ann, Bob (the same goals again) | Ann, Bob | `serve(ann)` | the café is open. The internal order of the engine gets to the goal of Ann first, and the engine selects `serve(ann)`. Then `false serve(P1), serve(P2), P1 \= P2` prevents `serve(bob)`, which waits. `arrives(carl)` is observed for the same step |
| 3 | Bob and Carl wait | Bob, Carl | Bob, then Carl | `serve(bob)` | the goal of Bob is older than the goal of Carl. Thus the engine tries the goal of Bob first, and the service of Carl is prevented |
| 4 | Carl waits | Carl | Carl | `serve(carl)` | no other goal needs the cycle |
| 5, 6 | nobody waits | — | — | nothing | `maxTime(6)` ends the run |

You can ask the engine about each row:

```sh
./lps explain examples/start/cafe.lps --ask "why_not(happened(serve(bob)), 3)"
# a denial blocked serve(bob) — false [happens(serve(ann),2,3),happens(serve(bob),2,3),ann\=bob]
```

The time in the question is the time at which the action would have *ended*.
Bob did not get his service in cycle 2. Thus the question uses
`happened(serve(bob)), 3`.

Now change the consequent of the rule from `serve(P) from T2 to T3` to
`serve(P) from T to T2`. The run ends in `failure` in cycle 1. The reason is
that each service must now occur in the cycle in which its rule started, and
the closed café prevents that. Then also remove the first precondition. The run
still fails in cycle 1. Two services must occur in cycle 1, and the second
precondition permits only one.

## 14. Planning

```prolog
:- lps_engine(planning, [horizon(10), max_concurrency(2)]).

achieve loc(wolf, north), loc(goat, north), loc(cabbage, north), loc(farmer, north).
```

`achieve` gives a group of fluents that the engine must make true together.

The planner searches through **sets of actions in the same cycle**, not
through single actions. The reason is that LPS selects many actions in each
cycle. The planner uses the same causal laws and the same `false` sentences
that the engine uses when it does not plan. There is no separate language for
planning. No construct has a different meaning in the planner.

A plan is a list of sets of actions. The ordinary cycle does the plan, one set
in each cycle, with the ordinary checks of preconditions and constraints. The
trace of a run with a plan is an ordinary LPS trace.

| Option | Default | Meaning |
|---|---|---|
| `horizon(N)` | 12 | the longest plan, in cycles |
| `max_concurrency(N)` | 3 | the maximum number of actions in one cycle |
| `search(S)` | `auto` | `bfs`, `greedy` or `auto` — refer to the text below |
| `nodes(N)` | 250 | the number of states that breadth-first search can examine before `auto` changes the search |
| `on_plan_failure(P)` | `replan` | `replan` or `reactive`, for when the plan stops agreeing with what occurs |

**There are two searches.**

`bfs` is breadth-first search. The planner tries each plan of one cycle, then
each plan of two cycles, and so on. If a plan exists within the horizon,
breadth-first search always finds a plan. The plan that it finds is
**the shortest**. A shortest plan is useful when the shortest plan is the
interesting answer. For example, the seven crossings of the wolf, goat and
cabbage puzzle are *the* solution, not only one solution. But the work of
breadth-first search increases very quickly when plans become longer. At
approximately twelve steps, the search is no longer practical.

`greedy` is greedy best-first search. Greedy search gives a score to a state.
To get the score, it solves an easier version of the problem, where no action
ever cancels anything. Then it counts how many rounds that easier problem needs
to get to each goal. The score is not exact. Thus the plan is possibly not the
shortest. But the search is much faster when there are many states. Greedy
search also finds dead ends. If the easier problem has no solution from a
state, the real problem also has no solution from that state. Thus the search
stops work on that state. It does not only give the state a low rank.

`auto` is the default. It starts with breadth-first search, and it gives that
search the number of states that `nodes(N)` sets. If breadth-first search uses
all those states, `auto` changes to greedy search.
`examples/start/blocks.lps` compares the two searches on the same problem:
seven blocks and seven moves. One search takes 0.4 seconds and the other takes
25 seconds.

You can also give the options on the command line. There, they replace the
directive in the file:

```sh
./lps run examples/start/blocks.lps --search bfs --horizon 14 --nodes 1000
```

With the default `lps_engine(reactive)`, `achieve` is an error. This error is
intentional. A program cannot start to behave as a planning program only
because someone added a line to it.

## 15. Settings

Write these settings as ordinary facts. If it is necessary to calculate a value,
write a rule.

| Setting | Meaning |
|---|---|
| `maxTime(N)` | stop after N cycles. Without this setting, a run does not stop by itself |
| `maxRealTime(Seconds)` | stop after that number of seconds of *simulated* time |
| `simulatedRealTimePerCycle(Seconds)` | the number of seconds of simulated time for one cycle |
| `simulatedRealTimeBeginning(Stamp)` | the instant that agrees with cycle 1 |
| `minCycleTime(Seconds)` | in a continuously running session, the real time that a cycle must take |

**There are two clocks, and they are independent.**
`simulatedRealTimePerCycle` says what a cycle *means*.
`minCycleTime` says how long a cycle must *take* on the computer. It is
important only for a continuously running session (§13, and
[`ide.md`](../guide/ide.md)).

LPS2 calculates the simulated time from the cycle number. It does not read the
clock of the computer during a cycle. Thus a run gives the same answer on each
computer:

```
real_time(T) = simulatedRealTimeBeginning + T × simulatedRealTimePerCycle
```

## 16. Vocabulary the engine provides

**Fluents that are always available.** You never declare these fluents:

| Fluent | Meaning |
|---|---|
| `real_time(Seconds)` | the simulated time of the current instant |
| `lps_user(User)`, `lps_user(User, Info)` | the person who runs the program, when the software that runs it gives a name |

**Events and actions that are always available:**

| Term | Meaning |
|---|---|
| `lps_terminate`, `lps_terminate(Reason)` | stop the run. You can use it as an action, or send it from outside |
| `real_date_begin(Date)`, `real_date_end(Date)` | the start and the end of a calendar day, as composite events |
| `end_of_day(Date)` | the limit between two days |

**Predicates from outside the program.** The program has its own Prolog module.
The module is the private space into which the system loads the program (§17).
A rule body can contain each predicate that this module can see, with the
built-in predicates of Prolog. The engine calls such a predicate.

Two special cases have names. An **external action** is an action that has no
causal laws. Its effect is a call to Prolog. An **external fluent** is a fluent
that a Prolog predicate answers. The engine does not use the stored state for
an external fluent. LPS1 used external actions and external fluents for input
and output.

External fluents are also the reason that `holds(true, T)` succeeds. The module
of the program can see `true/0`. Thus `true/0` is an external fluent, and it is
always true. The engine uses this when it gives an implicit end time to a
composite event.

## 17. Access to Prolog

An LPS file is a Prolog file. The engine loads all of the file into a private
Prolog module. A module is a separate space, and each program has its own
module. Thus:

- **Ordinary clauses** (§9) are available in all parts of the program.
- **Built-in predicates** are available: arithmetic, `format/2`, `sort/2`,
  `between/3`, comparison, and the predicates for names and text.
- **Library modules**: you can load them with an ordinary directive. The
  directive applies to the module of the program:

  ```prolog
  :- use_module(library(lists)).
  :- use_module(library(apply)).
  :- use_module(library(clpfd)).
  ```

- **Other files**: you can include them:

  ```prolog
  :- include(system('date_utils.pl')).      % a helper from the LPS1 tree
  :- include('my_helpers.pl').
  ```

- **Directives**: all directives other than `lps_engine/1,2` run as ordinary
  Prolog directives when the system loads the file. The translator ignores them
  in all other ways.

**The sandbox.** A server receives programs and runs them. While the server
translates such a program, it checks the Prolog of the program with the
`library(sandbox)` of SWI-Prolog. The check permits arithmetic, `findall/3`,
`format/2`, `assert`/`retract`, printing and similar operations. The check
refuses each thing that can get access to the computer: files, other programs
and the shell. The check also refuses a call that the program builds while it
runs, because the check cannot follow such a call. The server does not run a
refused program. The message gives the goal that the check refused. The HTTP
server (the web server) does the check, unless you start it with
`LPS_SANDBOX=0`. The command line does not do the check, unless you give it
`--sandbox` or `LPS_SANDBOX=1`. The check is not a time limit. A program can
still do a loop that does not stop in one cycle.

Obey these two cautions:

Do not put side effects in the bodies of rules. A side effect is a thing that a
rule does in addition to an answer, for example printing or writing a file. The
engine can call a body many times in one cycle. In the planner, the engine
calls a body for states that it only examines, and these states possibly never
occur. Put effects in actions.

Possibly one of your predicates has the same name and the same number of
arguments as a predicate of the internal vocabulary of the engine. Examples are
`holds/2`, `happens/3`, `initiated/3` and others. Then the engine does not see
your predicate. Give your predicate a different name.

## 18. Saying how a program should be drawn: `display/2`

A program can say how to draw its fluents and events. The editor then shows the
run again as a picture. `display/2` is the same declaration that LPS1 used for
drawings. Thus `display/2` clauses that exist now operate with no change.

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

The first argument is a fluent or an event. The second argument is **one list
of properties**, or **a list of such lists**, with one list for each object to
draw. `display(timeless, …)` describes the background: the objects that do not
change with time.

**Shapes:**

| `type:` | Properties |
|---|---|
| `rectangle` | `from` and `to`, or `point` and `size`; `radius` makes the corners round |
| `circle` | `point` / `position` / `center`, and `radius` |
| `ellipse` | a position, and `size` |
| `arc` | a position, `radius` (or `radius1` and `radius2`), `angle`, `rotation` |
| `line` | `from`, `to` |
| `path` | `segments:[[X,Y], …]`, and possibly `tension`; or `data`, an SVG path string |
| `star` | `center`, `points`, `radius1`, `radius2` |
| `regularPolygon` | `center`, `sides`, `radius` |
| `text` / `pointtext` | `point`, `content` |
| `raster` / `image` | `position`, `source` (a URL), `scale` |
| `arrow` | `from`, `to`, `biDirectional` |

**Properties that all shapes can have:** `label`, `fillColor`, `strokeColor`,
`strokeWidth`, `opacity`, `shadowColor`, `shadowOffset`, `fontSize`, `scale`,
`pattern` (with `patternColor` and `patternScale`).
A colour is a name, a `'#rrggbb'` code in quotes, or a list `[R, G, B]` of
numbers from 0 to 1. The editor accepts `id`, `sendToBack` and `bringToFront`
of LPS1, but they have no effect.

**Coordinates.** The origin is at the **bottom left**, and y increases upwards,
as in the drawings of LPS1. Sizes and positions are in pixels. The editor
changes the scale of the view to show all of the space that the scene uses.

**Obey these four rules.** They all come from the method that LPS1 used to draw
a scene:

- A `display/2` clause must operate when its first argument does not have a
  value yet. Thus do not put a cut, or an if-then-else, in the head position.
  Put the conditions in the body.
- After the fluent or event matches, each variable in the list of properties
  must have a value.
- The editor draws only the **first** solution for a given subject.
- The engine *calls* `display/2`. Thus a clause with a side effect does that
  effect one time for each scene that the editor draws.

**The icon library.** `[type:raster, icon:NAME]` draws one of 134 pictures that
this server keeps. Thus a computer with no connection to the internet can still
show an animation. *Help ▸ About the icons, fills and objects* shows each name,
with its picture and its licence. Use an icon, not `source:` with a URL (a web
address). Many examples of LPS1 refer to clipart on web sites that do not give
the clipart now. Those pictures now show as holes.

**The fill library.** `pattern:NAME` fills the surface of a shape with one of
nineteen tiles: `hatch`, `crosshatch`, `dots`, `grid`, `checker`, `bricks`,
`waves`, `zigzag`, `stripes`, `scales`, `honeycomb`, `noise`, … The same dialog
shows the list. A fill says what a surface is *like*. An icon says what a thing
*is*. A scene of flat rectangles cannot otherwise show one difference, and a
fill shows it: hatched for not available, bricks for built, waves for water.
The tile takes the colour of the shape. It then gives itself an ink that is
different from that colour. Thus one name operates on all the colours of the
scene. `patternColor` changes the ink, and `patternScale` changes the size of
the tile. This project draws the tiles itself. Thus there is no licence, no
attribution, and nothing that the editor gets from a different location.

**Composite events are subjects too.** The engine records a composite event (§7)
with its own interval. The scene gives the event to `display/2` as
`happens(Event, Start, End)`. Thus a clause can draw an *act* as a bar,
calculated from the start and the end of that act:

```prolog
display(happens(deal_with_goat(_, To), S, E),
        [ type:rectangle, from:[X0, 40], to:[X1, 54], fillColor:'#4c6ef5', label:To ])
    :- X0 is S * 24, X1 is max(E * 24, X0 + 8).
```

An act that started stays in the picture. Thus the lanes show a history of what
the run did. They do not show a short flash in the cycle where the act ended.

**Let the editor write the drawing.** The editor has the buttons *Animate in 2D*
and *Animate in 3D*. These buttons ask a language model for a **plan**. The
editor then calculates the positions and the sizes from the plan itself. The
model never writes a coordinate. Thus the parts of the result never overlap.
One plan is sufficient for the two-dimensional picture and for the
three-dimensional picture.

A plan says one or more of six things about the fluents of the program. The plan
must include **all the fluents that change**. Before the model makes a plan, the
editor runs the program. Then it tells the model which fluents start and stop.
If a plan does not include one of those fluents, the editor sends the plan back
to the model with the names that are missing.

- **Containers and members**, for a fluent that says *where a thing is*, when
  the place is not one of the things. Examples are `loc(Object, Where)`,
  `at(Robot, Room)` and `in(Parcel, Van)`. The containers are the values of the
  place argument. The members are the things that move from one container to a
  different container. All containers have the same grid. Thus a thing keeps its
  column in all containers.
- **Stacks**, for a fluent that says on what a thing stands, when the support is
  *a different thing of the same kind*. An example is `on(Block, Support)`. You
  can identify this case because the same names are on the two sides: `on(a, b)`
  and `on(b, c)` make `b` a thing and also a place.
- **Gauges**, for a fluent that says *what value something has*. Examples are
  `heating(on)`, `temperature(14)` and `balance(alice, 100)`. Nothing moves.
  Each gauge has a box with a label, and the box shows the current value.
- **Lamps**, for a fluent that is only true or false. Examples are `alerted`,
  `stopped` and `in_station`. A gauge without its `value_var` is a lamp. The box
  is there while the fluent is true, and it is not there while the fluent is not
  true. Below the box there is an **empty socket**. The empty socket is a dim
  outline with the caption, and it stays. Thus off looks like off, not like a
  picture that the editor could not draw. Some programs have a state that is
  only a small number of flags, for example the London Underground notice. Such
  a program has no other shape that the editor can draw it with.

A gauge or a lamp can have a **key**. For example, `balance(Who, Amount)`,
`available(Fork)` and `fire(Room)` say something about *one of many things*.
Each of those things has its own socket, with a caption that says which thing it
is. Without a key, the editor draws only the first thing, because `display/2`
gives one solution for each subject. Thus five free forks become one box with
four empty sockets below it. The editor decides which argument is the key, and
which values that key has, from the **run**. It does not accept the plan as the
only source for these data. Some fluents are true for many of their instances
in the same cycle. Such a fluent is a set of things, and each thing gets a box.
A fluent that is never true for many instances in the same cycle is a value,
and it gets one box. (`temperature(14)` and `temperature(15)` are two cycles,
not two boxes.)
- **Grids**, for a fluent that says where a thing is with **coordinates**, not
  with the name of a place. Examples are `location(Car, 2-1, Heading)` and
  `at(Robot, X, Y)`. The plan gives the argument for the thing, and the position.
  The position is one argument that is a pair such as `2-1`, or two arguments
  that are numbers. The editor draws a map with north at the top. It puts each
  thing in the cell that its coordinates give. The run decides the size of the
  map, and which cells the editor draws as roads. The map includes each position
  that something got to, with one cell of margin. The cells that something
  visited are shaded. The editor draws a grid in two dimensions only.
  *Animate in 3D* does not draw it, and tells you so.
- **Spans**, for a **composite event**, for example `deal_with_goat(From, To) from T1 to
  T2 if …`. Each composite event has its own lane, with one bar for each
  occurrence. A bar goes from the start of the act to the end of the act. A span
  is the only shape that tells a *story* about a program. The bars together make
  a chart of what the run did. A lane is for things that **take time**. The
  editor draws an act whose start is the same as its end as a tick, not as a
  bar. If a bar is too narrow for its label, the editor draws the bar without
  the label. (The timeline shows each occurrence, whatever its width.)

**The editor draws a plan that almost gives a shape as that shape.** Possibly
the "containers" of a layer of containers are all coordinates in the run, for
example `2-1`, `2-2` and `6-5`. Then the editor draws the layer as a grid. The
reason is that a box for each coordinate shows one car in each box and no
streets.

Some layers have a template that names one specific thing (`loc(wolf, Where)`).
Other layers have a `member_var` that is not one of the variables of their
template. Such a layer does not have two arguments for a container and a member.
The editor draws such a layer as the shape that it almost gives. This is a gauge
of what that one thing does, or a lamp for each thing where the run shows many
things. A note tells you what occurred. The editor then reports what it really
drew. It measures these values on the scene that it made, not on the plan: the
number of containers and things in the summary, and the check that sends a
fluent that is not included back to the model.

**What the editor does not ask in the plan.** The *program* already knows two
things. The editor reads these two things from the program, and does not ask the
model for them. The first thing is which fluents are **intensional** (§8). The
editor draws them as outlines, because no event sets an intensional fluent. If
a reader thinks that it is a stored fluent, the reader looks for the event that
set it. The second thing is the order in which the **rules** of the program
refer to its fluents. The editor puts the fluents in that order. Thus two
fluents that are in one rule are next to each other in the drawing. A member of
a plan can also have a `pattern` (a fill, refer to the text above) and a `model`
(a 3D object with a name, §18a).

**A stack is not a container.** Possibly the editor draws a blocks-world program
as containers and members. Then the result is one box for each block, and each
box contains one small square. Each block shows two times, one time as a
container and one time as a thing, and there is no tower. Thus, if a plan makes
containers from things that it also puts *in* containers, the editor treats the
plan as a stack. A note tells you so.

A stack has no table of positions. The height of a block in the drawing depends
on the number of blocks below it, and that number changes from cycle to cycle.
Thus the editor makes two short rules that go down through the state:
`lps_pile_top/2` and `lps_pile_x/2`, which call `state/1`.
`examples/start/blocks3d.lps` writes the same rules by hand. The drawing layer
connects `state/1` to the cycle that it draws. Thus the tower in the picture is
the tower at that cycle. Blocks move into the tower and out of the tower when
the program moves them.

**How much of this document the assistant is given.** A question that you type
receives all of this document. The two *Animate* buttons receive only the
sections that help to read a program: §§1, 3, 4, 5, 8 and 11. The editor takes
these sections from this file by section number. Thus there is no second copy
that can become different from the original. Those sections are approximately
1,500 tokens, not 9,000. A token is the unit that a language model uses to
measure text. A token is approximately three-quarters of a word.

There is a practical cause for this difference. With a program and the icon
catalogue, all of this reference made a request of more than 12,000 tokens. A
model whose limit is 8,192 tokens refused the request. For the same reason, the
editor calculates the space for the answer from the size of the program. It
does not use a fixed space. Some providers say how much text a model can receive
at one time. Groq says it, but OpenAI and Anthropic do not. Where a provider
says it, the editor marks the models that are too small. The editor then refuses
to send the request before it sends it, and it gives the name of a model that
is sufficiently large.

The result in your file is ordinary Prolog. It contains a table of positions
(`lps_slot/4`
for containers, `lps_cell/6` for the cells of the gauges and the lamps, or
`lps_column/2` with the two rules that go down a stack). It also contains a
background, and one `display/2` rule for each layer, stack, gauge and lamp. The
names of the three-dimensional versions contain a `3`: `lps_slot3/4`,
`lps_cell3/5`, `lps_column3/2`, `lps_pile_top3/2`. Thus one program can contain
the two pictures at the same time. The two pictures share `lps_look/3`, because
the appearance of a thing is the same fact in two dimensions and in three.

## 18a. Three dimensions: `display3d/2`

`display3d/2` is a separate declaration. It is not a different reading of
`display/2`. Two-dimensional properties do not change correctly into three
dimensions, because the result can show a meaning that the author did not
intend. Also, a program can have a good reason to have the two pictures at the
same time, with different things in them.

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
| `model` | `position`, `model:NAME`, `scale` — an object with a name, from the catalogue |
| `camera` | `position`, `lookAt` — only in `timeless` |
| `light` | `position`, `intensity`, `color` — only in `timeless` |

Properties that all objects can have: `color`, `opacity`, `rotation:[Rx,Ry,Rz]`
in degrees, `label`, `labelScale`, and `pattern` (the same fill library as in
§18, used here as the texture of the material).

**The object catalogue.** `[type:model, model:tree]`, or only `model:tree`
on any object, draws one of thirty-four things with names: `person`, `robot`,
`animal`, `tree`, `house`, `bank`, `hospital`, `factory`, `car`, `truck`,
`train`, `boat`, `plane`, `box`, `crate`, `barrel`, `bag`, `coin`, `key`,
`door`, `flag`, `sign`, `table`, `chair`, `bed`, `cup`, `book`, `rock`,
`cloud`, `fire`, `bulb`, `tower`, `arrow`, `bird`. *Help ▸ About the icons,
fills and objects* shows them, with the purpose of each one. The catalogue is
for a three-dimensional scene what the icon library is for a two-dimensional
scene. With the catalogue, a floor plan of boxes becomes a scene of things.

The editor **builds** each object from simple shapes, in the `color` of the
object. Thus the object shows immediately, it becomes larger and smaller with
`scale`, and it cannot be lost. A ready-made shape that the editor gets from a
different location can be lost. If the catalogue does not have a `model:` name,
the editor ignores the name and draws the `type:` of the object. Thus it is
always safe to give the name of a model. (There are CC0 libraries of
ready-made shapes: [Kenney](https://kenney.nl/assets),
[Quaternius](https://quaternius.com) and [Poly Pizza](https://poly.pizza). These
libraries are the solution if photoreal objects become necessary. The cost is
megabytes, software to read the shapes, and a download while the editor is
built. And a scene shows these things only at the size of a thumb.)

**Coordinates** are right-handed, with **y upwards**. Upward y is the usual
method of three.js. In three dimensions, no programs exist that already expect
a different direction for up. This is different from two dimensions.

**Animate in 3D uses the same plan as Animate in 2D** (§18). The grid of
containers becomes a floor plan. The point (x, y) in two dimensions is (x, z)
in three dimensions. Things stand up from their slab, and a stack becomes a
tower. The editor calculates the ground, the camera and the light itself. It
does not keep them from an earlier drawing. A member of the plan that gives a
`model` shows as that object. A member that does not give a model is a box, as
before.

**A declared camera is a starting camera.** The editor obeys a declared camera
when it first draws the scene, and not after that. Thus when you move the cycle
slider, the zoom does not change. The ⤢ button goes back to the declared
camera.

**Labels take their colour from the current theme.** The labels have an outline
in the background colour. Thus you can read them on a light background, and
where they go across a solid object. `color:` changes the colour of the text,
but the outline stays.

## 18b. The mouse as an input

An animation can be something that you act on, not only a picture. A program
can **declare `lps_mousedown/3`, `lps_mouseup/3` or `lps_mousedrag/3` as
events**. Such a program receives those events from a two-dimensional or
three-dimensional window that follows a continuously running session. Each such
event gives the position of the mouse pointer, in the coordinates of the
program, and the mouse button that you used.

```prolog
events lps_mousedown(_, _, _).

%  The reverse of the drawing below — a scene and its hit test have to agree.
lamp_at(X, N) :- N0 is X // 70, N is N0 + 1, N >= 1, N =< 4.

if   lps_mousedown(X, _, _) from _ to T1, lamp_at(X, N)
then toggle(N) from T1 to T2.
```

A program that does not declare those events receives nothing. The window then
does not monitor the mouse: a click on the picture is only a click on a
picture. The server makes this decision, from the program itself. The set of
mouse events that the program can receive **is** the set of rules that the
program writes for those events. Thus it is not possible to use an animation to
make an event that the program did not ask for.

In three dimensions, the window gives the position where a straight line from
the mouse pointer into the scene touches the ground plane. The window gives
this position as `(x, z)`.
`examples/start/lights.lps` is a full example.

## 19. The operator table

These operator declarations let Prolog read the written form. They tell Prolog
how the words of a sentence go together in groups. `src/core/lps_ops.pl`
declares them. Each program that reads LPS terms must have them available.

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

`from` binds less tightly than `to`. Thus Prolog reads `E from T1 to T2` as
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

All the work of the command line and of the editor goes through one web
request, `POST /lpsapi`. The request has an `operation` field that says what
you want. Thus you can do all that the editor does with `curl`. `curl` is the
command-line tool that sends web requests. Refer to [`ide.md`](../guide/ide.md).

**Deploying as Solidity.** `./lps solidity` (and *Misc ▸ Deploy as
Solidity* in the editor) writes a program as a smart contract. A smart contract
is a program that runs on a blockchain. The fluents become state, each action
becomes a function, and each precondition becomes a `revert`. Each causal law
becomes a write to the state, and `initially` becomes the constructor. The
command writes only programs with a direct translation. The command refuses
each of these items, with the line that it comes from, and it writes nothing:

- reactive rules,
- intensional fluents,
- composite events,
- planning,
- events that the environment observes (not actions that someone calls),
- the own Prolog of the program,
- timeless rules,
- a read that must search a fluent,
- arithmetic that does not use integers,
- constraints on two actions.

The command writes a fluent with a default (§3) as a plain mapping when its
default is the zero of its type. The command refuses each other default.

## 21. Further reading

**The language and the theory behind it**

- Robert Kowalski and Fariba Sadri, *Reactive Computing as Model Generation*,
  New Generation Computing 33(1), 2015. This paper gives the declarative and
  operational semantics of LPS.
  <http://www.doc.ic.ac.uk/~rak/papers/LPS%20revision.pdf>
- Robert Kowalski, *Computational Logic and Human Thinking: How to be
  Artificially Intelligent*, Cambridge University Press, 2011. This book gives
  the ideas below LPS. It is the source of the programs in `examples/collections/kowalski-book/`.
- The KELPS kernel, on the RuleML wiki:
  <http://wiki.ruleml.org/index.php/KELPS>
- The LPS group at Imperial College: <https://lps.doc.ic.ac.uk>
- The RuleML 2017 LPS tutorial and the CLOUT 2017 workshop slides, in
  `legacy_lps1/doc/`.
- `docs/project/historical/Combining Logic Programming and Imperative Programming in
  LPS`.

**This implementation**

- [`glossary.md`](glossary.md) — the terms of these documents.
- [`plan-of-record.md`](../../project/plan-of-record.md) — the development plan: the engine, the
  agent, and the other input languages.
- [`selection-spec.md`](../../dev/semantics/selection-spec.md) — the twenty rules that say where
  the engine has a choice, and which choice it makes.
- [`conformance_lps2.md`](../../dev/conformance/conformance_lps2.md) — LPS2 measured against the
  test recordings of LPS1.
- [`le-for-lps.md`](le-for-lps.md) — Logical English, for the same
  language.
