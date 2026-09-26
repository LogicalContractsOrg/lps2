# LPS2 in detail

*Kind: overview (technical companion) · Audience: programmers, and readers who know LPS1 · Status: current (2026-09-26)*

[Introducing LPS2](introducing-lps2.md) is the tour for newcomers: what LPS2
does, shown from the running system. This document is its companion. It holds
the detail the tour leaves out: how the engine was checked against LPS1, how the
system is arranged, how each feature works inside, and what building the system
taught. Each section here says which section of the tour it expands.

The terms are defined in the [glossary](../reference/glossary.md). The
development plan, including everything not yet built, is the
[plan of record](../../project/plan-of-record.md).

---

## Contents

1. [When rules disagree: the selection specification](#1-when-rules-disagree-the-selection-specification)
2. [Why implement it again](#2-why-implement-it-again)
3. [What "behaves like LPS1" is taken to mean](#3-what-behaves-like-lps1-is-taken-to-mean)
4. [How the system is arranged, and what that buys](#4-how-the-system-is-arranged-and-what-that-buys)
5. [Differences from LPS1, in one table](#5-differences-from-lps1-in-one-table)
6. [Planning, explanations and sessions, inside](#6-planning-explanations-and-sessions-inside)
7. [The editor, inside](#7-the-editor-inside)
8. [The assistant, inside](#8-the-assistant-inside)
9. [The web interface](#9-the-web-interface)
10. [WebAssembly](#10-webassembly)
11. [Logical English, inside](#11-logical-english-inside)
12. [PDDL, inside](#12-pddl-inside)
13. [Drools, inside](#13-drools-inside)
14. [Minecraft: running the example](#14-minecraft-running-the-example)
15. [Industrial control: the named tools](#15-industrial-control-the-named-tools)
16. [Deploying it](#16-deploying-it)
17. [How it was built, and what that cost](#17-how-it-was-built-and-what-that-cost)
18. [Known gaps, in detail](#18-known-gaps-in-detail)

---

## 1. When rules disagree: the selection specification

*Expands the tour's §2.*

The genuinely hard part of an LPS engine is what happens when several rules want
things that cannot all happen. LPS1 had an answer, and the answer sits in LPS1's
own code, but nobody ever wrote the answer down. Without it, the instruction
"reimplement LPS" does not say enough for anybody to carry it out.

[`selection-spec.md`](../../dev/semantics/selection-spec.md) is that missing
document: twenty numbered points at which the engine has a choice to make.
Points SP1 to SP15 were worked out by reading LPS1; points SP16 to SP20 came to
light while LPS2 was being built. Each point says which way the engine actually
goes.

Here are two examples of the kind of question the document settles. Both are
about the order of the steps inside one cycle of LPS1's engine, which the
specification numbers as phases.

**The step that looks as though it moves the state forward does not.** LPS1 has
a step called `updateFluents`, but in LPS1's default mode that step is skipped.
The state moves forward in two later steps instead, `updateNextStateFluents` and
`copyNextState`. The plan's first description of the cycle said otherwise, and
the specification records the correction.

**Phase 10 is one step rather than three.** Taking in what has been observed,
working out the goals, and checking the preconditions of the actions chosen —
the constraints that say when an action may not happen — all happen together.
The engine may go back and try a different way through any part of that phase.
So an action whose precondition fails at the *end* of the phase can send the
engine back as far as the *start* of the phase, where the observed events come
in. That behaviour is part of what the language means (selection point SP11),
and not a detail of how the engine happens to be built.

Each of the twenty points is also marked either *load-bearing* or *incidental*.
The incidental points mark the places where a future engine is free to differ
from LPS1. The load-bearing points are what the recorded runs are really
testing.

## 2. Why implement it again

*Expands the tour's §3.*

LPS1 is about 5,000 lines: `engine/interpreter.P`, `utils/psyntax.P`, a table of
the symbols the notation uses, and a small store. LPS1 works, and the collection
of example programs that comes with it is the accumulated knowledge of what LPS
is for.

What LPS1 also has is everything in the same place. One file, `interpreter.P`,
holds the cycle, the part that works out goals, the part that updates the state,
the tests, the connections into SWISH — the web system through which LPS1 was
used — the handling of work done in parallel, and the machinery of the server.
That one file mentions threads, which are strands of work running at the same
time as one another, 48 times, most of them around the layer that answers
questions. The program, which does not change, and the session, which does, both
live in the same Prolog module, a module chosen while the system is running and
reached through `u_call/1` and its relatives.

None of that is a criticism. A research engine that later grew a web interface
looks exactly like that. But that same arrangement is what stands between LPS and
a planner, a session that can be copied, a version that runs in a browser, or a
second way of writing a program. Every one of those four follows from one change:
**separate the program from the session, and keep the engine free of everything
else.**

LPS2 was written from the plan, from `selection-spec.md`, and from watching what
LPS1 does. Reading `interpreter.P` was always intended — `interpreter.P` is the
user's own code, and the plan treats the table of symbols and the internal
vocabulary as stated parts of the agreement between the two engines. What nobody
did was copy LPS1 line by line into the new engine. The part that works out goals
was written against the twenty numbered rules, so LPS1's accidents are carried
over only where the specification says they matter.

## 3. What "behaves like LPS1" is taken to mean

*Expands the tour's §4.*

A recorded run is a file of Prolog facts: `lps_test_result(Stage, Cycle, Count)`
and `lps_test_result_item(Stage, Cycle, Term)`, where the stage is `fluents`,
`events` or `composites`. For two runs to count as the same, the number of
items must match exactly. The two sets of items are then sorted and compared,
and only the names of the variables are allowed to differ.

So the order of items *within* a cycle does not matter. **Which cycle something
belongs to, how many items there are, and the shape of each term all matter
exactly.**

Those three requirements make a much harder target than "the examples still give
sensible answers". A program that reaches the same answer by a different route
fails the test.

| result | meaning | count |
|---|---|---:|
| a | the same under every deliberate disturbance | **99** |
| b | sensitive to a choice; needs a stated rule | 0 |
| c | differs when run again unchanged | 0 |
| documented | the recording is out of date | 3 |
| documented | out of date, recorded in 2019 | 6 |
| **unexplained failure** | | **0** |

The deliberate disturbances were built into the testing from the start, rather
than added as an afterthought. Each program is run again four more ways: with
its rules and facts in reverse order; with the list of fluents it starts from
reversed; with new goals put at the front of the waiting list instead of the
back; and — as a check on the check itself — written out again unchanged. A
test whose result changes under any of those four depends on a choice, and a
choice like that has to be *stated* rather than left as an accident. No test
changes.

Each of the nine documented cases names its evidence in
`conformance/adjudicated.pl`. Six of the nine are recordings made in 2019 on
SWI-Prolog 8.1.1, before LPS1 began recording `real_date_begin/1` as a composite
event; LPS1 itself fails those six today, and gives exactly the diagnosis LPS2
gives. One covers ten cycles of a program that now declares `maxTime(8)`. One
was recorded before a `maxRealTime` declaration was added. The last is
`prospectiveGoat`, whose 2017 recording contains no `composites` records at all.

One further finding is worth recording, about the way LPS1 runs its own tests.
**LPS1 compares only the cycles the run actually produced**, so a run that dies
half way through is scored as a pass. The testing described here makes its own
strict judgement, and reports LPS1's verdict beside it. Two of LPS1's own tests
pass under LPS1 while leaving recorded cycles untouched.

`--engine cross` runs both engines and compares them with each other rather than
with the recording. Comparing the two engines directly is the only comparison
that means anything once a recording is older than the behaviour it recorded.

**Speed.** Taking the middle program of the collection, LPS2 uses about 0.4
times the time LPS1 takes on a clock, and a third to a half of the memory
(`tools/compare_engines.pl`). One program is slower: `prospectiveGoat2` takes
2.4 times as long, because it checks the look-ahead constraints again for every
action it considers. Making that faster means rearranging the check, and a
change of that size needs a run of the whole test suite of its own, rather than
an edit chased by a stopwatch, so the matter is left open.

## 4. How the system is arranged, and what that buys

*Expands the tour's §3.*

LPS2 is about 10,000 lines of SWI-Prolog in three layers, together with the
editor that runs in the browser:

```
src/core/     the engine. No input or output, no threads, no clock, no C.  5,449 lines
src/syntax/   between the written forms and the internal form              1,681 lines
src/edges/    everything that touches the world: files, CLI, HTTP          3,314 lines
```

`tools/lint_core.pl` is the program that enforces the first of those three
lines. Nothing in `src/core/` may mention threads, sockets — connections to
other machines — HTTP, which is how requests travel over the web,
`process_create`, `shell`, `get_time`, predicates written in the C language,
randomness, or the reading and writing of files. There is one deliberate
exception, `b_setval` and `nb_setval`, kept to a single file whose opening
comment explains why the engine cannot be written without those two.

That rule was not kept for its own sake. Four good things follow from it.

**A session is a term that nothing ever alters.** So `lps_session_fork/2` makes
a copy in one step: the copy and the original are the same term under two
names. The plan had designed a store in two halves, which would copy the state
only when something wrote to it; that store turned out not to be needed. Making
a copy was measured at **about 5 microseconds, whatever the size of the
session** (`tools/bench.pl`).

**Something outside tells the engine the time; the engine never reads a clock.**
Setting the pace of a session at two cycles a second is a job for the outer edge
of the system, and that job lives in one predicate in `src/edges/lps_live.pl`.
So a session running in real time and an ordinary run are the same engine doing
the same work.

**The whole engine can be turned into WebAssembly** (§10), which is a form a web
browser can run. Gathering `src/core/` and `src/syntax/` into one page that needs
nothing else took a day, because the half of the system that touches the world
was already a separate half.

**A run can be checked for repeatability.** The disturbances described in §3 are
only possible because a run depends on the program, the options and the
observations, and on nothing else at all.

## 5. Differences from LPS1, in one table

| | LPS1 | LPS2 |
|---|---|---|
| **Language** | reactive rules, causal laws, constraints, composite events, intensional fluents | the same, plus `achieve` and `display3d/2` |
| **Planning** | goal reduction; `prospectively` for looking ahead | `achieve`, searching breadth-first or greedy best-first, or choosing between the two by itself; a set of actions in each cycle; planning again when a plan fails |
| **Explanation** | — | a record of how the engine reached each conclusion, kept on every run; five forms of question; four different answers to *why not* |
| **What if** | — | `lps_session_fork/2`, about 5 microseconds; `what_if` compares two runs |
| **Running without end** | yes, with real-time options | yes, and events may now arrive over the network while the program runs, with each channel allowed to send only certain events; only so much history is kept |
| **Errors** | Prolog errors | orderly reports carrying `src(File,Line,Col,Kind)`, which survive the translation from Logical English |
| **2D animation** | paper.js, inside SWISH | Konva, the same `display/2` vocabulary, the y axis the right way up, a library of pictures kept on the same machine, and shapes you can click |
| **3D animation** | — | three.js, driven by `display3d/2` |
| **State diagram** | `godfa/1`, one column | arranged in layers, arrows that run side by side merged into one, a return to an earlier state drawn as a loop, in the editor and on the command line |
| **Editor** | SWISH | Monaco: one set of colouring rules for both LPS and Prolog, generated from the engine's own table of symbols; errors shown on the line they are on; menus; a list of examples; every panel resizable |
| **Assistant** | — | a language model, from any of five suppliers, whose tools are the editor's own operations |
| **Ways in** | LPS syntax, `.lpsw`, lps.js | LPS syntax (LPS1's own), the internal form, Logical English, PDDL, Drools, Inform 7; not lps.js's syntax |
| **Ways to run it** | a SWISH server | command line, one web address, a packaged image ready to run on a server, WebAssembly |
| **Keeping the engine self-contained** | not attempted | checked by machine |

## 6. Planning, explanations and sessions, inside

*Expands the tour's §5 to §9.*

**Explanations.** `tools/explain_test.pl` covers thirteen cases of the five forms
of question: `why(happened(A),T)`, `why_not(happened(A),T)`, `why(holds(F),T)`,
`why(stopped(F),T)`, and `what_if(Events,T)`. The four answers to `why_not` are
`scheduled_for_another_cycle`, `no_goal_created`,
`rejected_by_prospective_constraint` and `no_plan_found`; outside those four the
answer is "no applicable rule", and where the record cannot settle the question,
the answer is *not recorded*.

**What if.** `what_if(Events, T)` takes a copy of the session with
`lps_session_fork/2`, runs the copy on with the different observation, and
compares the two records in the way the tests compare a run against a recording
— matched by stage and by cycle, with only the names of the variables allowed to
differ. So the answer to "what would have happened?" reads in the same terms as
a failing test.

**The state-transition diagram.** `./lps automaton PROGRAM` prints the diagram.
The `automaton` operation of the web interface hands it back as JSON, which is
JavaScript Object Notation, a plain-text way of writing data down so that
another program can read it.

**Sessions that do not stop.** The pace is set by a loop that watches the clock,
in `src/edges/lps_live.pl` — the one place in the whole system that reads the
clock in order to keep to a *rate*. The engine's own idea of when things happen
is left untouched. Starting a session takes a list saying which kinds of event,
named as predicates, each source is allowed to send:

```json
{ "llm":   ["task_request/2"],
  "human": ["approval/2", "task_request/2"] }
```

The mouse events a live picture may send — `lps_mousedown/3`, `lps_mouseup/3`,
`lps_mousedrag/3` — are decided by the server from the program itself: exactly
the ones the program declares as events, so opening an animation can never
become a way of manufacturing an event.

## 7. The editor, inside

*Expands the tour's §10 and §11.*

`./lps ide` serves the editor on port 3060 unless told otherwise
(`--port`). A tool called esbuild builds the editor from the files in `ui/` and
puts the result in `src/ide/dist/`. Node.js is needed to build the editor, and
not to run it: the packaged image that serves the finished editor has no Node.js
in it.

**One set of colouring rules** covers LPS and the Prolog you can write inside an
LPS program. The table of symbols those rules work from is *generated* from the
engine's own table (`tools/gen_monarch.pl`), so the editor cannot drift away
from the part of the system that reads a program. Fluents, events and actions
are coloured from the program's declarations, by the same examination of the
program that offers completions as you type: `loc(wolf,north)` and
`row(south,north)` have exactly the same shape, and only the declarations say
which is a fluent.

The editor component, Monaco, brings features of its own — the right-click menu,
find and replace, folding a passage away, marking the other places a name
appears — but each of those features has to be asked for separately. The
simplest way of putting Monaco on a page gives you none of them, which is why
an earlier version of this editor had a right-click menu that did nothing.

The timeline draws from the records `stage(fluents, Cycle, Items)`, the very
records the tests compare against LPS1's recordings, so nothing in the engine
has to be switched on for the timeline to be drawn.

**There are two editors, deliberately.** `/LogicalEnglish2/editor/lps.html` is
the editor of LE2, the Logical English system, which offers two languages and
has two servers behind it. `src/ide/` is this project's own editor. Both editors
talk only to `/lpsapi`, the single web address described in §9, and that is
what keeps the arrangement honest: everything either editor can do can also be
done with `curl`, the ordinary command-line tool for sending a request to a web
address, and can therefore be tested with no editor at all.

**The libraries for drawing.** There are 134 pictures — from OpenMoji
(CC BY-SA 4.0), game-icons.net (CC BY 3.0) and Material Symbols (Apache-2.0) —
chosen by counting which predicates the examples actually use. The nineteen
fills and thirty-four three-dimensional objects were made in this project: no
licence, no attribution, nothing that can rot away.

`display3d/2` is a declaration of its own, rather than a second reading of
`display/2`. Properties that make sense in two dimensions cannot be carried over
into three without misrepresenting what the author meant, and a program may
quite reasonably want both at once, each showing something different. The types
are `box`, `sphere`, `cylinder`, `cone`, `plane`, `ground`, `line`, `arrow` and
`text`, with `camera` and `light` in the `display3d(timeless, …)` background.

## 8. The assistant, inside

*Expands the tour's §12.*

The assistant is a loop written in Prolog, modelled on LE2's own. Where the
server itself holds a key, that key is used in preference to any key the browser
is carrying, so one key can be set up centrally for everybody.

The assistant's tools are the editor's own operations, called inside the same
running program rather than fetched from anywhere else: `analyse` (translate the
program from its written form into the internal form the engine runs, and report
the errors), `run` (run it and get the record back), `explain` (the questions of
the tour's §6), and `scene` (what the drawing clauses actually produced). A model
that asks "does this program translate?" gets exactly the answer the editor
shows, because the model and the editor make the same call.

The list of models comes from the suppliers themselves. When the server starts,
`lps_models.pl` reads each supplier's catalogue of models, and does that work
alongside everything else so that one slow supplier cannot hold `./lps ide` up.
The table kept by hand in `lps_llm.pl` stays as a fall-back for when there is no
connection.

**The model does not write coordinates**, and that is the whole design of
*Animate in 2D* and *Animate in 3D*. Asking the model to write them produced
exactly what you would expect: positions that look plausible and overlap each
other, three animals in the same place, a label off the edge of the picture.
Models know that a goat belongs on a river bank. Models are bad at arithmetic
over a picture. And telling a model to check its own work does not make it
better at arithmetic.

So the work is split in two.

  **First**, the model returns a *plan*: which containers there are, which things
  move between them, which fluent puts a thing in a container, and what each
  thing looks like.

  **Second**, `src/edges/lps_scene.pl` works out where everything goes. That
  program lays the plan out by flowing boxes one after another, the way a web
  browser lays out a row of items on a page, and boxes laid out that way cannot
  overlap. A constraint solver — a program that finds an arrangement meeting a
  list of requirements — would be the right tool if the model were producing
  requirements about how things line up. The model is not producing those, and
  asking it to would put the hard part straight back where it was.

Several other systems have arrived at the same split for putting diagrams
together: describe the arrangement first, and work the positions out separately.

What ends up in your file is ordinary Prolog: a table of positions
(`lps_slot/4`), a background, and one `display/2` rule for each layer. So the
program stays readable and stands on its own, and nothing calls back to the
assistant while the program runs. Every container is given the *same* grid, so a
thing keeps its column wherever it goes. That grid is what makes the animation
readable, and packing each container separately would have destroyed it.

*Animate in 3D* used to ask the model for `display3d/2` clauses with coordinates
in them — the one job the plan exists to take away from the model, handed back
with an extra axis to get wrong. The results were everything at the origin, or a
camera inside a wall. Now both buttons ask for a single plan, and `lps_scene.pl`
draws that plan twice.

**Nobody asks the model what the engine already knows.** Before the model plans
anything, the program is *run*. Three things are then read off the record of
that run (`lps_scene_focus/3`): which fluents tell the run's states apart, which
cycles are worth a picture, and which states the run comes back to. The question
put to the model carries all three, together with the rule that the plan must
cover every one of them; a plan that leaves one out is handed back with the
missing one named. Which fluents are *derived*, and the order in which the rules
mention things, are read off the program in the same way. What is left to the
model is the part that needs a model: which fluent is drawn as which shape, and
what each thing looks like.

In three dimensions, the frames of *Split into scenes* are photographs, taken by
one drawing engine used again for each frame.

## 9. The web interface

*Expands the tour's §13.*

The web interface is **a single address**, `/lpsapi`. Every request carries an
`operation` field, and that field says which piece of work the server is to do.
A token may be demanded, and requests that come from a page served by another
site are accepted. There are about thirty operations: `compile`, `session_new`,
`observe`, `step`, `run`, `state`, `fork`, `trace`, `dump`, `analyse`, `explain`,
`timeline`, `changes`, `scene`, `scene3d`, `automaton`, `example`,
`list_examples`, the `live_*` family, the `assistant_*` family, and
`wasm_bundle`.

One address rather than many is a deliberate choice. A single address means the
whole interface can be driven from one shape of `curl` command, and a single
address is what lets the two editors, the Minecraft bot and the demonstration in
the tour's §20 all talk to exactly the same thing.

The Model Context Protocol, an agreed way of offering tools to a language model,
has its own document: [LPS over MCP](../api/mcp.md).

## 10. WebAssembly

*Expands the tour's §14.*

**Misc ▸ Deploy as WASM** produces a single page with swipl-wasm — SWI-Prolog
compiled to WebAssembly — the whole of `src/core/` and `src/syntax/` as Prolog
text, and your program. The parts that touch the world — requests over the web,
the assistant, sessions that keep running, the connection to LE2 — are not in
that page, and could not be.

The whole content of the demonstration is that the other half loads at all. It
loads because `tools/lint_core.pl` has been enforcing that separation since the
very first milestone, and not because anything was arranged specially for the
occasion. The whole editor can also be built as a static site, with no server:
[deploy-vercel.md](../../dev/deploy-vercel.md).

## 11. Logical English, inside

*Expands the tour's §15.*

The LogicalEnglish2 project translates Logical English into the LPS internal
form and runs the result on this engine. What the two projects agree on is
written down in [`le-lps-interface.md`](../../dev/le-lps-interface.md), which
LE2 links to rather than copying.

![Logical English on LPS2](../images/le2-lps.png)

That is LE2's own editor: an English program on the left, translated by LE2 and
run by LPS2, with this project's timeline on the right. The two servers talk to
each other directly, with nothing in between, which is why the web interface has
to accept requests that come from a page served by another site.

**LE2 loaded into LPS2.** LE2 offers a single module, `le_service.pl`, and LPS2
loads that module into itself (`LPS_LE2_LIB=/path/to/LogicalEnglish2`).
Translating a document then costs no more than an ordinary call inside the
running program — about 0.2 seconds — rather than the cost of starting a second
program up. That difference is the difference between translating a `.le` file
when somebody asks for it and translating it on every key you press. Nothing in
LPS2 loads LE2 when the system is built, so LE2 stays optional: with LE2 absent,
opening a `.le` file says which setting to fill in.

The colouring for a `.le` tab is built when the editor starts, from LE2's own
tables of keywords rather than from a copy of them. A copy would go wrong for
every language except English as soon as either side changed. The completions
offered come from the document's own templates, each one labelled with the part
it plays.

Nobody has to hope the result is the same whether LE2 runs inside LPS2 or as a
separate program, because it is checked. `tools/m8a_test.pl` runs the programs
in `examples/le/*.le` both ways, and demands that the terms come out equal,
allowing only the names of the variables to differ, with the same information
about where each term came from and the same complaints.

**The internal form.** Here is what LE2 makes of the bank transfer of the
tour's §15:

```prolog
maxTime(10).
fluents([balance(A,B)]).
actions([transfer(A,B,C)]).
initial_state([balance(bob,0),balance(fariba,100)]).
observe([transfer(fariba,10,bob)],2).
updated(happens(transfer(A,B,C),D,E), balance(C,F), F-G, [G is F+B]).
updated(happens(transfer(A,B,C),D,E), balance(A,F), F-G, [G is F-B]).
reactive_rule([happens(transfer(fariba,A,bob),B,C), holds(balance(bob,D),C), D>=10],
              [happens(transfer(bob,10,fariba),C,E)]).
d_pre([happens(transfer(A,B,C),D,E), holds(balance(A,F),D), F<B]).
```

`known as transfer` ties the English template to the name of the predicate.
`when … then … becomes …` lands on `updated/4` — the very thing an LPS author
writes as `updates … to … in …`. `it must not be true that` lands on `d_pre/1`.
And `scenario one is` is `observe`.

**Every term remembers where it came from.** LE2 produces
`t(Term, src(File,Line,Col,Kind))`, and the `compile` operation takes a matching
list of sources. Every error comes back with the file, the line and the column
set out separately, so an error found in the generated internal form is reported
against the English line that produced it. `tools/m8a_test.pl` checks the point
in six cases, among them "an error lands on the `.le` line it came from" and "a
`.le` file with no LE2 set up is refused, not guessed at".

Put a `.lps` file beside a `.le` file and the two are translated together, which
is the way round those constructs the English does not reach.

**The other direction.** `le_lps_write.pl` writes the internal form back out as
Logical English, and 13 of the 15 test programs survive the round trip —
English, internal form, English again, internal form again — unchanged, with
only the names of the variables allowed to differ. The two that do not survive
are named: a fixed calendar date has no form in the English. *Say it in
English* is LE2's `nl_to_le`, reached through this project's own connection to
the language models, so the keys and the choice of model are the ones already
set for the assistant.

## 12. PDDL, inside

*Expands the tour's §16.*

The rule the plan sets for every way in is **write the checker before writing the
translator**, and that rule was followed here. `pddl_plan_valid/4` is a separate
checker, which applies the meaning of PDDL directly, and it was written first.
The test reports the length of each plan beside the shortest length known for
that problem:

```
domain                 problem         steps   opt     validation
blocks-domain          blocks-p1       6       6       valid
blocks-domain          blocks-p2       10      10      valid
blocks-domain          blocks-p3       6       6       valid
gripper-domain         gripper-p1      15      11      valid
gripper-domain         gripper-p2      23      -       valid
hanoi-domain           hanoi-p2        3       3       valid
hanoi-domain           hanoi-p1        7       7       valid
elevator-domain        elevator-p1     7       7       valid
elevator-domain        elevator-p2     4       4       valid
rover-domain           rover-p1        3       3       valid
rover-domain           rover-p2        7       7       valid
lights-domain          lights-p1       6       6       valid
lights-domain          lights-p2       3       3       valid
logistics-domain       logistics-p1    …still searching…
```

Thirteen of the fourteen problems are solved and checked, and twelve of those
thirteen plans are the shortest possible. (`lights`, added later, exercises
negative and disjunctive goals, quantifiers, conditional effects and types; see
[PDDL and LPS](../integrations/pddl.md).) Hanoi is the useful one for that
claim, because 2ⁿ − 1 is a number you can work out for yourself rather than look
up.

Greedy best-first search finds valid plans that are not the shortest — 15 steps
against a known shortest of 11 on `gripper-p1` — which is exactly what greedy
best-first search does. The logistics domain is worse: the search was still
going after forty minutes. Both of those are findings about the planner rather
than about the translation, which is exactly what a way in with an independent
checker is for. Neither would have come to light from LPS programs alone.

**The written form.** File ▸ Open gives the written form of LPS, not the
internal form the translator produces:

```prolog
'pick-up'(A) from T1 to T2 terminates ontable(A).
false 'pick-up'(A) from T1 to T2, not clear(A) at T1.
```

`src/syntax/lps_surface_write.pl` runs the ordinary translation backwards, and
checks itself every time it is called. The program reads back what it has just
written, puts that text through the same reader the rest of the system uses, and
compares the result term by term, allowing only the names of the variables to
differ. If the round trip fails, whoever asked keeps the internal form and is
told why. A translated program that no longer means what the translator said
would be worse than an ugly one.

`tools/surface_test.pl` runs that check over every translated example: 17 of 17.
The check found two real defects on the way, one of them a fluent in
`gripper-domain.pddl` called `at/2`, which is also the name of an operator.

## 13. Drools, inside

*Expands the tour's §17.*

`lps_drools.pl` is one of the two translators the server loads from the private
lpsPlus project (`src/syntax/lps_plus.pl`). The translator reads DRL, the
language in which Drools rules are written — `declare` types, `when`/`then`
rules, `insert`, `retract`, `modify(){}` and `not` patterns — and produces
reactive rules and causal laws.

In LPS, an action or an event is something that happens in the world, and not an
operation on a store of facts. So the reading is about the world that Drools's
working memory, the facts Drools is holding at that moment, describes. An insert
of a Fire is a fire starting (`fire_starts(Room)`), and a delete is that fire
ending. `modify(s) { setOn(true) }` is the sprinkler turning on
(`sprinkler_turns_on(Room)`: a field that is only ever true or false counts as a
state of its own). A change to any other field is that field becoming its new
value (`order_state_becomes(Id, shipped)`, which is `updated/4`, exactly LPS's
`updates … to … in …`). A rule that only inserts is guarded by a condition
saying that the inserted fact does not hold yet, because Drools fires such a
rule once where LPS would fire it in every cycle. A field to which every fact
gives the same value, such as an alarm's name, is left out. A
`fire-alarm.wording` file beside the DRL file supplies the words and names a
person would actually choose (`alarm_goes_on`).

Where Drools and LPS do not agree, the translator says so rather than guessing.
`salience` is Drools's way of deciding which rule wins, and LPS has nothing of
the kind: LPS decides by constraint, not by priority. A Java expression in the
conclusion of a rule is something this engine cannot work out, so the rule
performs the external action `java_leaf(Rule)` in its place. (A plain reader of
a field, such as `$p.getName()`, and arithmetic over values of that sort, are
worked out; anything else leaves its change out altogether, and never puts a
made-up constant in its place.) The translator reports both of those as
warnings, and reports in the same way any rule attribute LPS has nothing for,
such as `agenda-group` or a timer, while `no-loop` becomes a condition and
`enabled false` leaves its rule out. A condition the translator cannot translate
(`eval`, `forall`, `collect`) leaves its rule out, with a warning, rather than
being read as something it is not. What LPS does have is read as itself. `or`
between patterns becomes one rule for each alternative, just as Drools makes one
subrule for each alternative. `accumulate` becomes an aggregate over the state,
such as a total or a count. And `insertLogical`, a fact that holds only for as
long as whatever supports it holds, becomes an intensional fluent.

lpsPlus's `migration/drools/lps_drools_test.pl` runs eighteen sets of rules
against the behaviour expected of them, and all eighteen pass; the same test
also checks what eleven of the readings come out as. Eight of the eighteen are
the example rule bases, and the other ten exercise one construct each. Among the
examples, the three newest — a traffic light as a state machine, insurance
eligibility, and order shipping — are there because an example earns its place
by breaking something, and order shipping did. `retract(o)`, where `o` is a
variable that a pattern has given a value to, was producing an action named
after the variable itself, and an action of that name stopped no fluent at all.
So the rule fired for ever and the fact stayed where it was.

## 14. Minecraft: running the example

*Expands the tour's §21.*

**The two rates are deliberately not aligned.** The game world moves in steps of
50 milliseconds, twenty a second; the LPS session runs two cycles a second.
Tying the two rates together would make the engine's rate a property of the game
rather than of the agent. Anything that has to react faster than one cycle —
falling, drowning, a creeper two blocks away — belongs in the controlling layer,
and some of it is there.

| layer | what runs there | rate |
|---|---|---|
| **controller** | mineflayer and its path-finder: walking, jumping, swinging, collisions, following a path | 20 steps a second |
| **supervisor** | an LPS session: standing goals, constraints, plans, explanations | 2 cycles a second |

**flying-squid** is a Minecraft server written in JavaScript, and the bot
connects to that server without signing in anywhere:

```sh
cd examples/agents/minecraft
node world.mjs &                # a local server on port 25565
node bot.mjs --program safety.lps
```

```
[bot] spawned
[lps] safety.lps running as live3, one cycle every 500 ms
[lps→bot] place_torch
[lps→bot] place_torch
```

`prismarine-viewer` draws the map on the server rather than in the browser, and
so it needs the `canvas` module, which is written in the C language. On macOS,
Windows and mainstream Linux, npm downloads a ready-built copy. Where no
ready-built copy exists, the module wants Cairo and Pango, and
`examples/agents/minecraft/DETAILS.md` says which packages to install. The bot
loads the viewer only when somebody asks for it, so a machine without the viewer
still runs the agent — only without the picture.

## 15. Industrial control: the named tools

*Expands the tour's §22.*

Part V of the plan names the tools a demonstration would use: IEC 61131-3
Structured Text as the language to write out, MATIEC to turn Structured Text
into C, Beremiz as the editor, and OpenPLC — a programmable logic controller made
of software rather than hardware — to run the result. Naming those tools means
the first piece of work in that direction starts from a known target rather than
from a survey. No code exists for any of it yet.

## 16. Deploying it

The packaged image is built in two stages. First Node.js builds the editor from
`ui/` into `src/ide/dist/`. Then SWI-Prolog serves the engine, the web interface
and the editor on one port. The image that actually runs has no Node.js in it.

`fly.toml` and `buildPush.sh` put the image on a server.
[`deploy.md`](../../dev/deploy.md) covers running LPS2 alongside LE2. One
browser has to be able to reach both servers, so the settings that let a page
from one site call the other have to be right.

`LPS_TOKEN` sets the token, the secret word, that the web interface demands.
`LPS_ORIGIN` limits which other sites may call the web interface. The server
reads the five suppliers' keys from its own settings, and a key set there takes
precedence over anything a browser sends.

## 17. How it was built, and what that cost

Six practices did most of the work, and those six are the part of this project
that would carry over to another one.

**Check against the old engine first, and let nothing past until it passes.** The
very first piece of work was not code but the testing: run *LPS1* over all of its
own examples, sort each example according to whether its recorded run survives
being disturbed, and write the numbers down. Nothing else was allowed to begin
until the new engine reproduced those runs.

That order of work is uncomfortable, and it means several weeks with nothing to
show. That order is also why every feature added since could go in without
anybody wondering whether it had broken the meaning of the language.

**Write down what the old code chooses.** `selection-spec.md` exists because a
recorded run captures *the choice the 2021 engine happened to make*, and
reproducing that choice without naming it is imitation without understanding.
Twenty numbered points, each marked load-bearing or incidental. Five of them,
SP16 to SP20, came to light when the new engine failed a test.

**Write the checker before the translator.** For PDDL, a separate plan checker
was written first. For Drools, the behaviour expected of each set of rules was
written first. A translator checked only by "the result looks like PDDL" is
checked by nobody.

**Let a machine enforce the rule about how the system is arranged.**
`tools/lint_core.pl` runs before every change is recorded. Keeping the engine
free of everything else was not a principle anybody had to remember: breaking it
stopped the build. Keeping to that rule is why turning the engine into
WebAssembly took a day rather than a rewrite.

**Never guess where you could report.** A `.le` file with no LE2 set up is
refused, not approximated. `salience` in a Drools file becomes a warning.
An explanation the record cannot support is "not recorded".

**Take the pictures from the running system.** `tools/doc_shots.cjs` illustrates
both the tour and the tutorial from a running server, and that run fails if the
browser reports an error or if any request fails. Photographing the panes for
the tour, rather than merely using them, turned up three real defects in the
interface: overlapping labels on the timeline, a state diagram cut off at the
edge, and a scene left over from the previous program.

The last of the six generalises: **writing the documentation is a test**. Writing
the tour's §20 is what uncovered that `app.log`, written without quotation marks
around it, was being read as a compound term rather than as a plain name, so the
demonstration had been reporting a success it never achieved.

## 18. Known gaps, in detail

*Expands the tour's §23.*

- **The 2D canvas follows the theme, and LPS1's programs do not know that.**
  A program that assumed a white background — black text set with
  `fillColor:black`, as `burning.pl` does — is hard to read on the dark one. A
  program has no way of stating its own background, and inventing one would be
  a change to the language rather than a repair to the drawing. Switching theme
  is the way round the problem.
- **`prospectiveGoat2` is 2.4 times slower than LPS1** (§3). Everything else is
  faster.
- **PDDL plans are not always the shortest** on gripper-style problems, and the
  logistics domain was still searching after forty minutes (§12). The planner is
  the limitation, not the translation, and `tools/pddl_test.pl` therefore does
  not finish either.
- **Ways in not attempted**: Jason, DECLARE/BPMN, behaviour trees.
- **Industrial control** is entirely on paper (§15).
- **`conformance_report.md`** — LPS1's own numbers — is kept with the project,
  but the file of results it was made from is not, so making it again needs a
  complete LPS1 run of about 35 minutes.
- **LE2's own verifier does not know about the `lps` target.** A document aimed
  at LPS is reported as having "only facts and no rules", and its templates are
  reported as unused, because both of those checks count Prolog clauses and an
  LPS program asserts none. The program still translates and runs. A fix of two
  predicates in `le_verifier.pl` has been written and deliberately *not*
  committed: the fix belongs to the other project, which this work does not
  change.
