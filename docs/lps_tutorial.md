# Learning LPS

This is the teaching path through LPS(2) — M17b of `docs/LPSplusLLM.md`. It assumes you
can program but have never written a reactive rule, and it works up from a two-line
program to planning, explanation and sessions that never end.

Two companion documents: **`docs/lps_summary.md`** is the reference — every construct,
every declaration, the operator table — and is the right thing to keep open beside this
one. **`docs/IntroducingLPS2.md`** is the tour, for deciding whether any of this is worth
your afternoon.

Every screenshot below was taken by driving the real IDE in Chromium
(`tools/doc_shots.cjs`). Every program was run before it was pasted in.

---

## Contents

1. [Getting it running](#1-getting-it-running)
2. [The first program](#2-the-first-program)
3. [The five kinds of sentence](#3-the-five-kinds-of-sentence)
4. [Reading a run](#4-reading-a-run)
5. [Events from outside](#5-events-from-outside)
6. [Composite events](#6-composite-events)
7. [Intensional fluents](#7-intensional-fluents)
8. [Constraints that bite](#8-constraints-that-bite)
9. [Prospective constraints](#9-prospective-constraints)
10. [Planning: `achieve`](#10-planning-achieve)
11. [Prolog inside LPS](#11-prolog-inside-lps)
12. [Seeing it: `display/2` and `display3d/2`](#12-seeing-it-display2-and-display3d2)
13. [Asking why](#13-asking-why)
14. [Programs that never end](#14-programs-that-never-end)
15. [Where to go next](#15-where-to-go-next)
16. [Traps](#16-traps)

---

## 1. Getting it running

```sh
git clone …  &&  cd lps2
./lps run examples/goat_declarative.pl        # the command line
./lps ide                                     # the IDE, on :3060
```

The IDE needs building once (Node is a *build* dependency, not a runtime one — the
container that serves it has no Node in it):

```sh
cd ui && npm install && npm run build
```

Then open <http://localhost:3060>. The editor loads with the declarative goat in it.

![The IDE](images/ide-overview.png)

Left is a Monaco editor with one grammar covering LPS and the Prolog you can write inside
it. Right are seven readings of a run. Below the editor: the problem strip, the assistant,
and the live-session panel. **Ctrl/Cmd + Enter** runs.

You do not have to start from a blank file. **File ▸ Open example from server** lists all
178 programs — 158 from the old engine's corpus plus our own — each with the first line of
its own comment as a description.

![The examples browser](images/ide-examples.png)

---

## 2. The first program

```prolog
maxTime(6).

fluents  light(_).
actions  switch(_).

initially light(off).

switch(New) updates Old to New in light(Old).

if   light(off) at T1
then switch(on) from T1 to T2.
```

Run it:

```
fluents/0        [light(off)]
fluents/1        [light(off)]
events/2         [switch(on)]
fluents/2        [light(on)]
fluents/3        [light(on)]
…
success (success)
```

Five things are already visible.

**A fluent is something that is true over an interval**, not a variable. `light(off)`
holds from cycle 0 until something terminates it.

**An action is something the program does.** It is declared, and it only happens because a
rule asked for it.

**A reactive rule is not an `if` statement.** `if light(off) at T1 then switch(on) from T1
to T2` is a *goal*: whenever the condition becomes true, the engine takes on the obligation
of making the conclusion true. Nothing about it says *when* — `T2` is unbound, and the
engine chose the next cycle.

**The causal law is separate from the rule that fires the action.** `switch(New) updates
Old to New in light(Old)` says what `switch` *means*; the reactive rule says when to do it.
Splitting them is most of what makes LPS programs read the way they do — the physics of
the world is stated once, and every rule that acts inherits it.

**Time is cycles.** `maxTime(6)` bounds the run. Cycle 0 is the initial state; the switch
happens across the 1→2 boundary and is recorded at cycle 2. Actions occur *between* states.

---

## 3. The five kinds of sentence

Almost every LPS program is made of five kinds of sentence. Here they are with their real
names and the section of `docs/lps_summary.md` that has the full form.

| kind | example | means |
|---|---|---|
| **declarations** | `fluents light(_).`  `actions switch(_).`  `events badge(_).` | what sort of thing each predicate is |
| **the initial state** | `initially light(off), door(shut).` | what holds at cycle 0 |
| **reactive rules** | `if C at T1 then A from T1 to T2.` | when C, make A true |
| **causal laws** | `switch(N) initiates light(N).` / `terminates` / `updates … to … in …` | what an action or event does to the state |
| **constraints** | `false transfer(F,_,N) from T1 to _, balance(F,B) at T1, B < N.` | this must never be true |

`updates Old to New in f(Old)` is `terminates f(Old)` and `initiates f(New)` said once, and
it is almost always what you want for a fluent that has a *value*.

There are three more sentence forms, each with its own section below: composite events
(§6), intensional fluents (§7), and `achieve` (§10).

---

## 4. Reading a run

Run the goat and look at the **timeline**.

![The timeline](images/ide-timeline.png)

One lane per fluent, drawn over the interval it holds; below them, the events of each
cycle, and below those, composite events. The red dashed line is the cycle you are on; the
slider moves it, and so does clicking the picture.

The timeline is not instrumentation. It is the same `stage(fluents, Cycle, Items)` records
the conformance harness compares against upstream's goldens, which is why nothing in the
engine had to be turned on to draw it.

**State changes** answers a narrower question about one cycle: what changed, and *why*.

![State changes](images/ide-changes.png)

That last column is the part the old system did not have. `line 24` is the causal law that
fired, in the file in front of you. Everything else at that cycle is listed as *persisted*
— it did not change, and the engine knows the difference between "still true" and "made
true again".

**State transitions** is the whole run as an automaton: every distinct state once, so a
program that comes back to a state reads as a loop.

![The state-transitions diagram](images/ide-automaton.png)

That is `dining_philosophers_terse.pl`. The big box on the left is the state where all five
forks are free — reached at cycles 1 through 8, which is why it is a hub — and each box on
the right is somebody eating, with a self-loop while they carry on eating. The goat's
diagram, by contrast, is a straight chain: it never revisits a state, and the diagram tells
you so.

**Internal syntax** shows what the engine actually runs.

![Internal syntax](images/ide-internal.png)

`reactive_rule/2`, `d_pre/1`, `updated/4`, `initial_state/1`. This is the same
representation the old engine used, deliberately (§I.4), and it is worth looking at once:
it makes clear that `false X, Y, Z` is a denial, that `at`/`from`/`to` are sugar over
explicit time arguments, and that `achieve` is one more fact.

---

## 5. Events from outside

Not everything is the program's doing. `observe` injects an event the world caused:

```prolog
events   reading(_).

observe reading(31) from 2 to 3.
```

Events and actions are the same shape and differ in provenance: an *action* is something a
rule decided to do, an *event* is something that happened to you. Both are causes — both
can appear in `initiates`, `terminates` and `updates`.

In a live session (§14) `observe` is replaced by events arriving over HTTP while the
program runs.

---

## 6. Composite events

A composite event is a name for a *pattern* of other events over an interval.

```prolog
maxTime(8).

fluents  door(_), inside(_).
events   badge(_), pull(_).
actions  admit(_).

initially door(shut), inside(nobody).

observe badge(ann) from 1 to 2.
observe pull(ann)  from 2 to 3.

%  Two events in order are one thing.
entry(P) from T1 to T3 if badge(P) from T1 to T2, pull(P) from T2 to T3.

if   entry(P) from T1 to T2
then admit(P) from T2 to T3.

admit(P) updates Old to P in inside(Old).
```

```
events/2         [badge(ann)]
events/3         [pull(ann)]
composites/3     [happens(entry(ann),1,3)]
events/4         [admit(ann)]
fluents/4        [door(shut),inside(ann)]
```

`entry(ann)` is recorded as happening *from 1 to 3* — composite events have duration, and
that duration is what makes them useful. A rule can then talk about the whole pattern
without knowing how it was made.

Composite events also work the other way round, as *decompositions*: `dine(P) if
think(P), pickup_forks(...), eat(P), putdown_forks(...)` in the dining philosophers is a
way of saying "to dine, do these four things" — the same clause read as a plan.

---

## 7. Intensional fluents

Some things are true because of other things, and storing them would be a lie waiting to go
stale.

```prolog
too_hot at T if temperature(N) at T, N > 30.

if   too_hot at T1
then alarm(heat) from T1 to T2.
```

`too_hot` is never initiated and never terminated. It is re-derived every time it is asked
for, from whatever the state is at that moment. Declare it with `fluents` like any other,
give it a rule with `at T if`, and never give it a causal law.

Run that and the alarm fires *every* cycle after the temperature rises:

```
events/3         [reading(31)]
fluents/3        [temperature(31)]
events/4         [alarm(heat)]
events/5         [alarm(heat)]
events/6         [alarm(heat)]
```

This surprises everyone once. A reactive rule is a *maintenance* goal, not an edge trigger:
as long as its condition holds, it keeps being satisfied. If you want the alarm once, make
the rule terminate its own condition — that is what `alarm(heat) initiates alarmed` and
`if too_hot at T, not alarmed at T then …` is for.

---

## 8. Constraints that bite

```prolog
false transfer(From, _, N) from T1 to _, balance(From, B) at T1, B < N.
```

Read `false` as "it must never be that". This one says: never transfer more than the payer
has. Not "log a warning", not "prefer not to" — the engine will not commit an action set
that makes the denial true.

```prolog
maxTime(6).

fluents  balance(_, _).
actions  transfer(_, _, _).

initially balance(alice, 100), balance(bob, 0).

transfer(From, To, N) updates Old to New in balance(From, Old) if New is Old - N.
transfer(From, To, N) updates Old to New in balance(To,   Old) if New is Old + N.

if   balance(alice, A) at T1, A >= 30
then transfer(alice, bob, 30) from T1 to T2.

false transfer(From, _, N) from T1 to _, balance(From, B) at T1, B < N.
```

```
fluents/1        [balance(alice,100),balance(bob,0)]
events/2         [transfer(alice,bob,30)]
fluents/2        [balance(alice,70),balance(bob,30)]
events/3         [transfer(alice,bob,30)]
fluents/3        [balance(alice,40),balance(bob,60)]
events/4         [transfer(alice,bob,30)]
fluents/4        [balance(alice,10),balance(bob,90)]
fluents/5        [balance(alice,10),balance(bob,90)]
```

Three transfers and then it stops. Nothing in the program says "stop after three": the
rule's own condition (`A >= 30`) stops firing, and had it not, the constraint would have
refused the action anyway. Both are worth having — the condition is the intent, the
constraint is the guarantee.

This is the single biggest difference from a rule engine, and the reason the Kowalski book
examples that LE could not express (§I.12) fit here: **a constraint is checked by the
engine, not by the thing being constrained.**

---

## 9. Prospective constraints

An ordinary denial talks about now. A *prospective* denial talks about the state an action
would produce:

```prolog
false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

The `row(_,_) to T` is the trick: it constrains the state *at the end of* a rowing action.
So this reads "after any crossing, the goat must not be left alone with the wolf" — which
is the actual rule of the puzzle, stated once, rather than compiled by hand into six cases
of what the farmer should carry.

`examples/goat_declarative.pl` is exactly that program, and comparing it to
`examples/goat.pl` — where the same knowledge is spread through six `dealWithGoat` clauses
— is the shortest argument for the whole language.

---

## 10. Planning: `achieve`

```prolog
:- lps_engine(planning, [search(auto), horizon(10), max_concurrency(2)]).

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

`achieve` states a goal and lets the engine find the actions. It uses the same causal laws
and the same denials — nothing is written twice — and it produces a plan as a list of
*action sets*, one per cycle, so two things that can happen at once do.

`search(auto)` picks the strategy from the shape of the problem: node-budgeted breadth-first
when the branching factor is small enough to be exhaustive, greedy best-first under a
delete-relaxation heuristic when it is not. `search(bfs)`, `search(greedy)` and
`horizon(N)` override it. A plan that stops being valid — because the world moved — fails
at execution and is replanned against the state the program is actually in.

The 3D pane below is `examples/blocks3d.lps`, which is `achieve on(c,b), on(b,a)` over
three blocks:

![3D](images/ide-3d.png)

---

## 11. Prolog inside LPS

An LPS program is a Prolog file. Anything you write that is not one of the sentence forms
above is an ordinary predicate, callable from any condition:

```prolog
adjacent(fork(1), philosopher(1), fork(2)).
adjacent(fork(3), philosopher(3), fork(4)).
```

Directives work too — `:- dynamic`, `:- discontiguous`, `:- op`, and `use_module` for the
standard library:

```prolog
:- use_module(library(lists)).
```

Two engine predicates are worth knowing:

- **`state(F)`** enumerates the fluents holding at the cycle being evaluated, *one at a
  time*. It is not a list. `state(S), memberchk(f(X), S)` is a type error waiting to
  happen; `state(f(X))` is what you want.
- **`holds/2`** is internal vocabulary. It is predeclared with no clauses, so calling it
  from your own Prolog does not error — it silently fails. Use `at T` in a condition, or
  `state/1` from a `display` clause.

---

## 12. Seeing it: `display/2` and `display3d/2`

A `display/2` clause maps a fluent or an event to a picture:

```prolog
display(burning(X,Y), [type:circle, center:[CX,CY], radius:10, fillColor:yellow]) :-
	pixels(X, Y, CX, CY).

display(ignite(X,Y),  [type:star, fillColor:red, center:[CX,CY],
		       points:6, radius1:10, radius2:6, opacity:0.5]) :-
	pixels(X, Y, CX, CY).

display(timeless, [[type:rectangle, from:[0,0], to:[200,200], strokeColor:green]]).
```

![2D](images/ide-2d.png)

The origin is bottom left and y grows upward, as in the old paper.js renderer. `timeless`
is the backdrop — a list of property lists rather than one. The clause body can be any
Prolog, so the mapping from model coordinates to screen coordinates lives in the program.

`display3d/2` is a separate declaration, not a reinterpretation: `type:box`, `type:ground`,
`type:camera`, `type:light`, `type:text`, with `position` and `size` in three dimensions.
A program may have both and show different things.

There is an icon library — 134 checked-in SVGs — reachable as `[type:raster, icon:fire]`.
Use it rather than a URL: several corpus programs hotlink clipart that is no longer
reachable, and they render as holes.

**If you would rather not write any of this**, the assistant will. Press **Animate in 2D**:

![The assistant](images/ide-assistant.png)

and then *Apply to editor* and run:

![The result](images/ide-assistant-2d.png)

That is the declarative goat, animated from a program that had no visual mapping at all,
by one click. The assistant has the same tools you do — it compiles, runs, asks why, and
checks what its own clauses actually drew — and it will not finish while a fluent is still
invisible.

---

## 13. Asking why

Every run records a derivation forest, unconditionally. The **explain** pane reads it.

![Why did that happen?](images/ide-explain.png)

Five question forms:

```
why(happened(A), T)        why did this action occur?
why_not(happened(A), T)    why did it not?
why(holds(F), T)           why is this fluent true?
why(stopped(F), T)         what terminated it, and what caused that?
what_if(Events, T)         what would a different observation have changed?
```

`what_if` is the one that is not a lookup: it forks the session, replays with the different
observation and diffs the two traces. It is cheap because a session is an immutable term —
`lps_session_fork/2` is a unification, measured at about 5 µs whatever the session's size.

`why_not` is the interesting one, because there are four different answers and they are not
interchangeable:

![Why not?](images/ide-why-not.png)

*scheduled_for_another_cycle* — the plan does intend to do it, at cycle 6, as step 4.
The others are *no_goal_created* (nothing ever asked for it), *rejected_by_prospective_
constraint* (something did ask, and a denial refused it) and *no_plan_found* (asked for,
and no plan within the horizon).

The honest answer to a question the trace cannot settle is "not recorded". The pane never
reconstructs a plausible story.

From the command line:

```sh
./lps explain examples/goat_declarative.pl --ask "why_not(happened(transport(wolf,south,north)), 1)"
./lps timeline examples/goat_declarative.pl
./lps changes  examples/goat_declarative.pl --at 2
./lps automaton examples/goat_declarative.pl
```

---

## 14. Programs that never end

Drop `maxTime` and the program runs until something stops it, doing nothing at all until an
event arrives from outside. `examples/thermostat.lps` is the first program written that
way:

```prolog
fluents   temperature(_), target(_), heating(_), window_state(_).
events    temperature(_), set_target(_), window(_).
actions   heat(_), warn(_).

initially target(21), heating(off), window_state(shut), temperature(20).

temperature(T)  updates Old to T in temperature(Old).

if   temperature(T) at T1, target(Target) at T1, T < Target - 1, heating(off) at T1
then heat(on) from T1 to T2.

%  Never heat with the window open — a constraint, not advice.
false heat(on) from T1 to _, window_state(open) at T1.
```

In the IDE, open the **Live session** panel and press Start; then type an event, or say it
in English and let the assistant find the term.

![A live session](images/ide-live.png)

Two events went in — `temperature(14)` then `window(open)` — and the program answered with
`warn(window_open_while_heating)`. Note "queued for cycle 15": an event that arrives mid-cycle
is delivered at the next boundary, so a session's trace stays a trace.

The **2D** and **3D** buttons open a window that follows the running session rather than
scrubbing a finished one:

![A live 2D view](images/live-2d.png)

From the command line:

```sh
./lps live examples/thermostat.lps --cycle-ms 400
```

Live sessions take a `channels` map that says which event terms each source is allowed to
send. That is not a convenience — it is how `examples/agent/` makes an LLM structurally
unable to approve its own dangerous action.

---

## 15. Where to go next

- **`docs/lps_summary.md`** — the reference. Every construct, the operator table, the full
  `display/2` property list.
- **`examples/`** — `goat_declarative.pl` (prospective constraints and `achieve`),
  `blocks.lps` and `blocks3d.lps` (planning, 2D and 3D), `thermostat.lps` (live),
  `rkbook/` (twelve programs from *Computational Logic and Human Thinking*),
  `pddl/`, `drools/`, `agent/`, `minecraft/`.
- **`legacy_lps1/examples/`** — the old engine's corpus, all of which runs, all of it two
  clicks away in the examples browser.
- **Logical English.** If you would rather write the program in English, LE2 compiles to
  this engine: `the target language is: lps.` at the top of a `.le` file, and
  `./lps run foo.le`.
- **`docs/IntroducingLPS2.md`** — what is new relative to the old engine, and why.

---

## 16. Traps

Six things that cost real time here, collected so they cost you less.

**`updates _ to X in f(_)` uses two different anonymous variables.** Each `_` is fresh, so
the "old" value in the pattern is not the "old" value being replaced, and the update
silently does nothing useful. Name it: `updates Old to X in f(Old)`.

**A reactive rule fires as long as its condition holds.** It is a maintenance goal, not an
edge trigger (§7). If you want something to happen once, arrange for it to make its own
condition false.

**`state/1` enumerates, it does not return a list** (§11).

**`holds/2` silently fails from program Prolog** (§11).

**Actions happen between states.** An action recorded at `events/3` was decided from the
state at cycle 2 and its effects appear in `fluents/3`. Off-by-one confusion here is
usually this.

**A `display/2` clause must be callable with an unbound first argument.** Conditions go in
the body; no cuts in the head, no if-then-else deciding which clause matches. Only the
*first* solution per subject is drawn, which is upstream's behaviour and is deliberate.
