# The LPS language: a reference

*Kind: reference · Audience: users, developers, the assistant (read by lps_assistant.pl) · Status: current (2026-09-16)*

This document describes everything you can write in an LPS program, construct by
construct. It covers the declarations, the rules, the vocabulary the engine
provides, the way a program says how it should be drawn, and what a program may
borrow from Prolog.

It describes the language as you type it into a `.lps` or `.pl` file. This is
the same language the earlier implementation accepts, so programs written for
that implementation run here unchanged.

Two words are used throughout and are worth fixing now.

- The **written form** is what you type. It is the subject of this document.
- The **internal form** is what the written form is translated into before the
  engine runs it. You do not have to write it, but you can look at it — see
  §20 — and error messages sometimes mention it.

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

The engine repeats one cycle. In each cycle it:

1. collects the events that occurred since the previous cycle;
2. applies their effects to the state, using the **causal laws** (§5);
3. finds the **reactive rules** (§6) whose conditions the new state satisfies,
   and takes their conclusions as goals to be achieved;
4. reduces those goals to candidate actions, using **composite events** (§7),
   **intensional fluents** (§8) and ordinary **Prolog clauses** (§9);
5. discards any candidate that would violate a **constraint** (§10), commits the
   rest, and treats them as the next cycle's events.

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
program**: the two compile together, the `.le` first. The `.lps` half, the
**companion file**, holds what is not English — `display/2` clauses, Prolog
helpers — in the written form of this document.

A file in the written form **is a Prolog file**. It is read by Prolog's
`read_term/3`, with the operators of §19 in scope. Every clause in it is either
an LPS construct or an ordinary Prolog clause, and the two may be mixed freely.
Comments are Prolog's: `%` to the end of the line, `/* … */` for a block.

The translator makes **one pass, in file order**. This matters. Whether a bare
`f(x)` in a rule means a fluent or an event is decided by what the file has
already said about `f/1` (§3). So declare a predicate before you use it.

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

**`unserializable`.** By default the actions of one cycle are applied one at a
time, so that two `updates` of the same fluent in one cycle build on each other.
The effects of the actions named in `unserializable` are instead computed as a
set, before any of the others are applied.

Declarations are **advisory, not obligatory**. A program that declares nothing
still runs, because the translator works out what each predicate is from the
way it is first used: `f at T` makes `f` a fluent, and `f from T1 to T2` makes
it an event. Declaring is nevertheless better. The declaration is checked, it
documents the program, and it removes the dependence on the order in which
things appear in the file.

A fluent can also be given a default value, with `defaults/1` (§3a).

## 3a. Defaults

A fluent whose last argument is a value — a balance, an owner —
can be given a default, the value it holds for any key that has no stored fact:

```prolog
fluents  balance(_, _).
defaults([balance(_, 0)]).
```

This is an LPS2 declaration; LPS1 does not have it. It is written as an
ordinary fact holding a list, one term per fluent, whose last argument is the
default. Logical English writes it as `; 0 by default`.

- With the key bound, the fluent holds its stored value, or else the default:
  `balance(carol, B) at T` gives `B = 0` for an account never mentioned. The
  default is never stored, so the state and the trace list only the stored
  entries.
- With the key unbound, only the stored entries are enumerated.
- Consequently `not balance(carol, _) at T` fails: carol has a balance.
- An `updates` law reads the default as the old value of a key with nothing
  stored, so `deposit(P, A) updates Old to New in balance(P, Old) if New is Old + A`
  credits a new account without first initiating it. Such a law's conditions
  that do not mention the old value are evaluated first, so they may bind the
  key, and each distinct key is updated once.
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
over the same fluent. Prefer it where it applies. It says that the fluent
*changes value*, rather than that one fluent disappears and an unrelated one
appears, and the planner (§14) can make use of the difference.

The conditions of a causal law are evaluated **in the state the event started
from**. A law with no conditions applies whenever its event happens.

## 6. Reactive rules

A reactive rule says: whenever this happens, bring that about.

```prolog
if   Antecedent
then Consequent.
```

The antecedent is a sequence of literals with times attached (§11) — fluents
holding, events having happened. The consequent is a sequence of actions,
composite events and fluent conditions to be brought about.

```prolog
if   light(Place, on) at T1, not location(dad, Place) at T1
then goto(dad, Place) from T2 to T3.

if   loc(Object, south) at T, Object \= farmer
then makeLoc(Object, north) from T to T2.

if   payment_due(Party, Amount) at T
then pay(Party, Amount) from T to T2, notify(Party) from T2 to T3.
```

A reactive rule is a **standing goal**, not a procedure call. When a rule fires,
the engine keeps its consequent as an outstanding goal until it has been
satisfied or has become impossible. It is not a one-shot trigger. The times in
the consequent say *when the actions may happen*, not when they must.

A rule may also carry an explicit priority. That is written
`reactive_rule(Antecedent, Consequent, Priority)` in the internal form; the
written form has no notation for it.

## 7. Composite events

A composite event is a named event defined as a sequence of other events. It is
the language's equivalent of a subroutine.

```prolog
makeLoc(Object, Location) from T1 to T3
    if  loc(Object, L2) at T1,
        row(L2, Location) from T2 to T3.

dealWithGoat(L1, L2) from T1 to T2
    if  makeLoc(goat, L2) from T1 to T2.
```

The head is an event — either declared as one, or recognisable as one from its
explicit `from … to …`. The body is a sequence. Composite events may be nested.

A composite event with more than one defining clause is a genuine choice: the
engine tries the clauses in the order they appear in the file, and backtracks
into the next one if the first does not work out.

If the head's interval is left implicit, it is made the same as the body's.
That is what lets you write `makeLoc(O, L) if …` and have the composite event
span exactly as much time as its body does.

## 8. Intensional fluents

An intensional fluent is one *computed* from the state rather than stored in it.

```prolog
total_due(Party, Total) at T
    if  findall(A, owes(Party, A) at T, As),
        sum_list(As, Total).

adjacent(X, Y) at _ if next_to(X, Y).
```

The head is a fluent and the body is evaluated afresh each time the fluent is
asked about. Intensional fluents are never initiated or terminated; they follow
from whatever the stored state happens to be.

The body of an intensional fluent is read at a **single instant**: any literal
in it that does not name its own time is taken to be at the head's instant.

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

These say what things *mean*, rather than what happens or what is required.
They may be called from anywhere: the body of a rule, the condition of a causal
law, a `display/2` clause.

A program translated from Logical English writes the rules of a timeless
relation in the internal form, as `l_timeless/2`, and its facts as ordinary
Prolog facts. Such a relation is answered as the program's own relation, from
both its rules and its facts: a goal that none of them matches simply fails,
and a negated one (`it is not the case that …`) is the negation of that
answer, never a call to a Prolog predicate of the same name.

## 10. Constraints and preconditions

```prolog
false Conditions.
```

This says that the conditions must never all hold at once. There is one
construct, but it has two readings, and which one applies is decided by what
the conditions mention.

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

Read `row(_, _) to T` as "a crossing that ends at T". The state at T is the one
that crossing would bring about, so the sentence rejects the crossing before it
is made. This is how looking one step ahead is expressed in the language
itself, and the planner (§14) uses the same mechanism.

An action that a constraint forbids is not an error. The engine backtracks and
looks for another way to satisfy the goal. To find out which sentence did the
forbidding, ask:

```sh
./lps explain PROGRAM --ask "why_not(happened(A), T)"
```

**Observations are checked too.** A precondition applies to events that arrive
from outside (§13) as well as to the actions the program chooses. If the
conditions of a precondition hold in the state the observed events arrive in,
the events are **refused**: they do not happen, and neither does any other event
observed for the same cycle, because the observations of one cycle are refused
together. The refusal is recorded. `why_not(happened(E), T)` answers
`refused_by_constraint`, naming the sentence and the values it held on, and the
editor's timeline shows the refused event crossed out. In a program that
models a contract, this is a call that reverts.

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

A literal that names its own time keeps it. A literal that does not is given the
time of the clause it sits in. In a context that is read at a single instant —
the body of an intensional fluent, the conditions of a causal law, a `false`
sentence, the argument of `not` — every literal without its own time is placed
at that one instant.

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
suffixes as any other event (§11). They are ordinary actions in every respect:
preconditions apply to them, they appear in the trace, and they can be
explained.

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
events through the network interface (the `observe` operation) or through a
continuously running session's mailbox. The program itself does not change.

Observed events are subject to the program's preconditions, and are refused
when one of them holds (§10).

A continuously running session can also restrict **who may send what**. It is
started with a list of **channels**, each naming the event predicates that
channel may carry; an event whose predicate is not on its channel's list is
dropped, and the drop is reported rather than silent. The mouse events of §18b
are a channel whose list is the program's own declarations.

## 14. Planning

```prolog
:- lps_engine(planning, [horizon(10), max_concurrency(2)]).

achieve loc(wolf, north), loc(goat, north), loc(cabbage, north), loc(farmer, north).
```

`achieve` names a group of fluents that are to be brought about together.

The planner searches over **sets of actions taken in the same cycle**, not over
single actions, because LPS commits several actions per cycle. It uses the same
causal laws and the same `false` sentences that the engine uses when it is not
planning. There is no separate planning dialect, and no construct means anything
different under the planner.

A plan is a list of action sets. It is carried out one set per cycle by the
ordinary cycle, with the ordinary checks on preconditions and constraints. The
trace of a planned run is an ordinary LPS trace.

| Option | Default | Meaning |
|---|---|---|
| `horizon(N)` | 12 | the longest plan, in cycles |
| `max_concurrency(N)` | 3 | the most actions in one cycle |
| `search(S)` | `auto` | `bfs`, `greedy` or `auto` — see below |
| `nodes(N)` | 250 | how many states `auto` lets breadth-first search visit before switching |
| `on_plan_failure(P)` | `replan` | `replan` or `reactive`, when the plan stops matching what happens |

**There are two searches.**

`bfs` is breadth-first search. It always finds a plan if one exists within the
horizon, and the plan it finds is **the shortest**. That is worth having when
the shortest plan is the interesting answer: the seven crossings of the wolf,
goat and cabbage puzzle are *the* solution, not merely a solution. Breadth-first
search is also exponential, and stops being practical somewhere around a dozen
steps.

`greedy` is greedy best-first search. It scores a state by solving an easier
version of the problem: one in which no action ever undoes anything. It then
counts how many rounds that easier problem needs to reach each goal. The score
is not exact, so the plan is not guaranteed to be the shortest, but the search
is very much faster when there are many states. It also recognises dead ends: if
even the easier problem cannot be solved from some state, the real one cannot be
either, so that state is abandoned rather than merely ranked low.

`auto`, the default, starts with breadth-first search, gives it the node budget,
and switches to greedy if the budget runs out. `examples/start/blocks.lps` compares
the two on the same problem: seven blocks and seven moves, in 0.4 seconds and in
25 seconds respectively.

The options can also be given on the command line, where they override the
directive in the file:

```sh
./lps run examples/start/blocks.lps --search bfs --horizon 14 --nodes 1000
```

Under the default `lps_engine(reactive)`, writing `achieve` is an error. This is
deliberate: no existing program can start behaving like a planning program
because someone added a line to it.

## 15. Settings

These are written as ordinary facts. If a value has to be calculated, write a
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
machine's clock during a cycle. This is what makes a run give the same answer on
any machine:

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
| `lps_terminate`, `lps_terminate(Reason)` | end the run. It can be used as an action or sent in from outside |
| `real_date_begin(Date)`, `real_date_end(Date)` | the start and end of a calendar day, as composite events |
| `end_of_day(Date)` | the boundary between two days |

**Predicates from outside the program.** Any predicate that the program's Prolog
module can see, including Prolog's own built-ins, may appear in the body of a
rule, and is simply called.

Two special cases have names. An **external action** is an action that has no
causal laws, and whose effect is a Prolog call. An **external fluent** is a
fluent answered by a Prolog predicate rather than by the stored state. This is
the mechanism LPS1 used for input and output.

It is also why `holds(true, T)` succeeds. `true/0` is visible to the program's
module, so it counts as an external fluent, and it holds trivially. The engine
relies on this when it gives a composite event an implicit end time.

## 17. Access to Prolog

An LPS file is a Prolog file, and the engine loads all of it into a private
Prolog module, one module per program. Consequently:

- **Ordinary clauses** (§9) are available everywhere in the program.
- **Built-in predicates** are available: arithmetic, `format/2`, `sort/2`,
  `between/3`, comparison, and the predicates for atoms and strings.
- **Library modules** can be imported with an ordinary directive, which applies
  to the program's own module:

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

- **Directives** other than `lps_engine/1,2` are run as ordinary Prolog
  directives when the file is loaded, and are otherwise ignored by the
  translator.

**The sandbox.** A server that runs programs sent to it checks their Prolog
when it compiles them, with SWI-Prolog's `library(sandbox)`: arithmetic,
`findall/3`, `format/2`, `assert`/`retract`, printing and the like are allowed;
anything that reaches the machine — files, processes, the shell — is refused,
and so is a call built at run time that the check cannot follow. The program
is then not run, and the message names the goal. The HTTP server checks unless
it is started with `LPS_SANDBOX=0`; the command line does not check unless
given `--sandbox` or `LPS_SANDBOX=1`. The sandbox is not a limit on time: a
program can still loop inside one cycle.

Two cautions.

Keep side effects out of the bodies of rules. A body may be called several times
in one cycle, and under the planner it is called against states that are being
considered but may never come about. Put effects in actions instead.

If one of your predicates has the same name and arity as a predicate of the
engine's internal vocabulary — `holds/2`, `happens/3`, `initiated/3` and so on —
yours will not be seen. Rename it.

## 18. Saying how a program should be drawn: `display/2`

A program can say how its fluents and events should be drawn. The editor then
plays the run back as a picture. This is the same declaration LPS1's renderer
used, so existing `display/2` clauses work unchanged.

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
A colour is a name, a `'#rrggbb'` string, or a list `[R, G, B]` of numbers
between 0 and 1. LPS1's `id`, `sendToBack` and `bringToFront` are accepted and
have no effect.

**Coordinates.** The origin is at the **bottom left** and y increases upwards,
as in LPS1's renderer. Sizes and positions are in pixels. The view is scaled to
fit whatever the scene turns out to occupy.

**Four rules to observe**, all inherited from LPS1's renderer:

- a `display/2` clause must work when its first argument is unbound, so do not
  put a cut, or an if-then-else, in the head position — put the conditions in
  the body;
- once the fluent or event has matched, the list of properties must contain no
  unbound variables;
- only the **first** solution for a given subject is drawn;
- `display/2` is *called*, so a clause with a side effect will perform it once
  for every scene drawn.

**The icon library.** `[type:raster, icon:NAME]` draws one of 134 pictures held
by this server, so a machine with no connection to the internet can still show
an animation. *Help ▸ About the icons, fills and objects* lists every name, with
its picture and its licence. Prefer this to `source:` with a URL. Several of
LPS1's examples refer to clipart on sites that no longer serve it, and those
pictures now come out as holes.

**The fill library.** `pattern:NAME` fills a shape's surface with one of
nineteen tiles — `hatch`, `crosshatch`, `dots`, `grid`, `checker`, `bricks`,
`waves`, `zigzag`, `stripes`, `scales`, `honeycomb`, `noise`, … — listed in the
same dialog. A fill says what a surface is *like* where an icon says what a
thing *is*, and it is the one distinction a scene of flat rectangles cannot
otherwise make: hatched for unavailable, bricks for built, waves for water. The
tile takes the shape's own colour and inks itself to contrast with it, so one
name works on every colour in the scene; `patternColor` overrides the ink and
`patternScale` the tile size. The tiles are drawn by this repository — no
licence, no attribution, nothing fetched.

**Composite events are subjects too.** A composite event (§7) is recorded with
its own interval, and the scene offers it to `display/2` as
`happens(Event, Start, End)` — so a clause can draw an *act* as a bar computed
from its own beginning and end:

```prolog
display(happens(deal_with_goat(_, To), S, E),
        [ type:rectangle, from:[X0, 40], to:[X1, 54], fillColor:'#4c6ef5', label:To ])
    :- X0 is S * 24, X1 is max(E * 24, X0 + 8).
```

An act that has begun stays in the picture, so the lanes read as a history of
what the run did rather than as a flash at the cycle it finished.

**Having the drawing written for you.** The editor's *Animate in 2D* and
*Animate in 3D* buttons ask a language model for a **plan**, and then work out
the geometry from the plan themselves. The model never writes a coordinate,
which is why the result never overlaps. One plan serves both the two- and the
three-dimensional picture.

A plan says one or more of five things about the program's fluents, and it must
cover **everything that changes**: before the model plans, the program is run and
it is told which fluents come and go, and a plan that leaves one of them out is
handed back with their names.

- **Containers and members**, for a fluent that says *where a thing is*, when
  the place is not itself one of the things — `loc(Object, Where)`,
  `at(Robot, Room)`, `in(Parcel, Van)`. The containers are the values the place
  argument takes; the members are the things that move between them. Every
  container is given the same grid, so a thing keeps its column wherever it is.
- **Stacks**, for a fluent that says what a thing is standing on, when the
  support is *another thing of the same kind* — `on(Block, Support)`. You can
  recognise this case because the same names appear on both sides: `on(a, b)`
  and `on(b, c)` make `b` both a thing and a place.
- **Gauges**, for a fluent that says *what value something has* — `heating(on)`,
  `temperature(14)`, `balance(alice, 100)`. Nothing moves. Each gets a labelled
  box showing what it currently says.
- **Lamps**, for a fluent that is simply true or false — `alerted`, `stopped`,
  `in_station`. A gauge with its `value_var` left out is a lamp: the box is
  there while the fluent holds and gone while it does not, over an **empty
  socket** — a dim outline, with the caption — that stays, so that off looks
  like off rather than like a picture that failed to draw. A program whose state
  is a handful of flags — the London Underground notice is one — has no other
  shape it can be drawn with.

A gauge or a lamp may be **keyed**: `balance(Who, Amount)`, `available(Fork)`,
`fire(Room)` say something about *one of several things*, and each of those
things gets a socket of its own, captioned by which one it is. Without a key
only the first would ever be drawn — `display/2` gives one solution per subject
— so five free forks would be one box with four ghosts underneath it. Which
argument the key is, and which values it takes, are settled against the **run**
rather than taken on trust: a fluent that holds of several of its instances at
the same cycle is a set of things and gets a box each, and one that never does
is a value and gets one box (`temperature(14)` and `temperature(15)` are two
cycles, not two boxes).
- **Spans**, for a **composite event** — `deal_with_goat(From, To) from T1 to
  T2 if …`. Each gets a lane of its own and one bar per occurrence, drawn from
  the act's own start to its own end. This is the only *narrative* shape a
  program can state, and the bars accumulate into a chart of what the run did.
  A lane is for things that **take time**: an act whose start is its end is
  drawn as a tick rather than a bar, and a bar too narrow for its own label is
  drawn without one. (The timeline lists every occurrence, whatever its width.)

**A plan that nearly says a shape is drawn as that shape.** A layer whose
template names a particular thing (`loc(wolf, Where)`), or whose `member_var` is
not one of its template's variables, has no two arguments to be a container and
a member with: it is drawn as the shape it nearly says — a gauge of what that
one thing is doing, or a lamp per thing where the run shows several — and a note
says what happened. What is *reported* back is then what was actually drawn:
the count of containers and things in the summary, and the check that hands an
uncovered fluent back to the model, are both measured on the generated scene and
not on the plan.

**What the plan is not asked.** Two things the *program* already knows are read
off it rather than asked for: which of its fluents are **intensional** (§8) —
those are drawn as outlines, because no event sets one and a reader who takes it
for a stored fluent goes looking for one — and the order its **rules** mention
its fluents in, which is the order they are laid out in, so that two fluents
appearing in one rule are drawn side by side. A member of a plan may also carry
a `pattern` (a fill, above) and a `model` (a named 3D object, §18a).

**A stack is not a container.** If a blocks-world program is drawn as containers
and members, the result is one box per block, each holding one small square,
every block drawn twice — once as a container and once as a thing — and no tower
anywhere. A plan that makes containers out of things it also puts *inside*
containers is therefore treated as a stack instead, and a note says so.

A stack has no table of positions, because how high a block is drawn depends on
how many blocks are underneath it, and that changes from cycle to cycle. What is
generated instead is a short recursion over the state — `lps_pile_top/2` and
`lps_pile_x/2`, which call `state/1`. This is the same shape that
`examples/start/blocks3d.lps` writes out by hand. The drawing layer points `state/1`
at the cycle being drawn, so the tower in the picture is the tower as it stands
at that cycle, and blocks move in and out of it as the program moves them.

**How much of this document the assistant is given.** A question you type gets
all of it. The two *Animate* buttons get only the sections that help in reading
a program — §§1, 3, 4, 5, 8 and 11 — taken from this file by section number, so
there is no second copy to fall out of step with it. That is about 1,500 tokens
rather than 9,000.

The difference has a practical cause. With a program and the icon catalogue
added, the whole reference took a request past 12,000 tokens, and a model whose
limit is 8,192 tokens refused it. The space reserved for the answer is likewise
worked out from the size of the program rather than fixed, for the same reason.
Where a provider says how large a model's context is — Groq does; OpenAI and
Anthropic do not — the editor marks the models that are too small, and refuses
to send before sending, naming one that would fit.

What ends up in your file is ordinary Prolog: a table of positions (`lps_slot/4`
for containers, `lps_cell/6` for the gauges' and lamps' cells, or `lps_column/2`
plus the two recursions for stacks), a
background, and one `display/2` rule for each layer, stack, gauge and lamp. The
three-dimensional versions carry a `3` in their names — `lps_slot3/4`,
`lps_cell3/5`, `lps_column3/2`, `lps_pile_top3/2` — so that one program can hold
both pictures at once. `lps_look/3` is shared between them, because what a thing looks like is
the same fact in both.

## 18a. Three dimensions: `display3d/2`

This is a separate declaration, not a re-reading of `display/2`. Two-dimensional
properties do not carry over into three dimensions without misrepresenting what
the author meant, and a program may reasonably want both pictures at once,
showing different things.

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
fills and objects* lists them with what each is for. They are what the icon
library is to a 2D scene: a floor plan of boxes becomes a scene of things.

Each is **built** from primitives, in the object's own `color`, so it loads
instantly, scales with `scale`, and cannot rot the way a fetched mesh can. A
`model:` name the catalogue does not have is ignored and the object's own
`type:` is drawn instead, so naming one is always safe. (The CC0 mesh libraries
— [Kenney](https://kenney.nl/assets), [Quaternius](https://quaternius.com),
[Poly Pizza](https://poly.pizza) — are the route if photoreal objects are ever
wanted; what they cost is megabytes, a loader and a fetch at build time, for
things a scene shows at the size of a thumb.)

**Coordinates** are right-handed with **y upwards**. That is three.js's own
convention, and unlike the two-dimensional case there are no existing programs
with an opinion about it.

**Animate in 3D uses the same plan as Animate in 2D** (§18). The grid of
containers becomes a floor plan — what is (x, y) in two dimensions is (x, z) in
three — things stand up out of their slab, a stack becomes a tower, and the
ground, the camera and the light are worked out rather than remembered. A
member of the plan that names a `model` stands there as that object; one that
does not is a box, as before.

**A declared camera is a starting camera.** It is obeyed when the scene is first
drawn and not afterwards, so moving the cycle slider does not undo a zoom. The
⤢ button returns to it.

**Labels take their colour from the current theme** and are outlined in the
background colour, so they stay legible on a light background and where they
cross a solid object. `color:` overrides the colour of the text; the outline
stays.

## 18b. The mouse as an input

An animation can be an interface rather than only a picture. A program that
**declares `lps_mousedown/3`, `lps_mouseup/3` or `lps_mousedrag/3` as events**
receives them from a two- or three-dimensional window that is following a
continuously running session. Each carries the position of the pointer, in the
program's own coordinates, and which button was used.

```prolog
events lps_mousedown(_, _, _).

%  The reverse of the drawing below — a scene and its hit test have to agree.
lamp_at(X, N) :- N0 is X // 70, N is N0 + 1, N >= 1, N =< 4.

if   lps_mousedown(X, _, _) from _ to T1, lamp_at(X, N)
then toggle(N) from T1 to T2.
```

A program that does not declare them receives nothing, and no listener is
attached at all: a click on the picture stays a click on a picture. The decision
is made by the server, from the program itself. The set of mouse events the
program is allowed to receive **is** the set of handlers it defines, so opening
an animation cannot become a way of manufacturing an event the program did not
ask for.

In three dimensions, the position reported is where the ray under the pointer
meets the ground plane, given as `(x, z)`. `examples/start/lights.lps` is a worked
example.

## 19. The operator table

These are the operator declarations that make the written form parse as Prolog.
They are what `src/core/lps_ops.pl` declares, and any program that reads LPS
terms needs them in scope.

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

`from` binds less tightly than `to`, so `E from T1 to T2` parses as
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

Everything the command line and the editor do goes through a single network
request, `POST /lpsapi`, carrying an `operation` field. Anything the editor can
do can therefore also be done with `curl`. See [`ide.md`](../guide/ide.md).

**Deploying as Solidity.** `./lps solidity` (and the editor's *Misc ▸ Deploy as
Solidity*) writes a program as a smart contract: fluents become state, each
action a function, each precondition a `revert`, each causal law a state
write, `initially` the constructor. Only programs with a straight translation
are written. Reactive rules, intensional fluents, composite events, planning,
events that the environment observes rather than actions someone calls, the
program's own Prolog, timeless rules, a read that would have to search a
fluent, non-integer arithmetic and constraints over two actions are each
refused, with the line they come from, and nothing is written. A fluent with a
default (§3) is written as a plain mapping when its default is the zero of its
type; any other default is refused.

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
