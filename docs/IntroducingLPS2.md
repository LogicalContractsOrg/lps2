# Introducing LPS2

A clean-room reimplementation of the LPS engine in SWI-Prolog, and what has been built on
top of it: a planner, explanations, an IDE with 2D and 3D animation, an LLM assistant,
perpetual sessions, PDDL and Drools front ends, a WebAssembly build, and agents that drive
a Minecraft bot and gate an LLM's dangerous actions.

This document is the tour. **`docs/lps_tutorial.md`** teaches the language;
**`docs/lps_summary.md`** is the reference; **`docs/LPSplusLLM.md`** is the plan of record,
including everything not yet built.

Every screenshot below was taken by driving the running system in Chromium
(`tools/doc_shots.cjs`). Every number was measured. Where something does not work, it says
so.

---

## Contents

**Part one — what it is**
1. [The short version](#1-the-short-version)
2. [What LPS is](#2-what-lps-is)
3. [Why reimplement it](#3-why-reimplement-it)
4. [The conformance contract](#4-the-conformance-contract)
5. [The architecture, and what it buys](#5-the-architecture-and-what-it-buys)

**Part two — what is new**
6. [Differences from LPS1, in one table](#6-differences-from-lps1-in-one-table)
7. [Planning that is actually a planner](#7-planning-that-is-actually-a-planner)
8. [Explanations](#8-explanations)
9. [The state-transitions diagram](#9-the-state-transitions-diagram)
10. [Hypothetical worlds](#10-hypothetical-worlds)
11. [Sessions that never end](#11-sessions-that-never-end)

**Part three — the surfaces**
12. [The IDE](#12-the-ide)
13. [Animation, 2D and 3D](#13-animation-2d-and-3d)
14. [The assistant](#14-the-assistant)
15. [The command line and the API](#15-the-command-line-and-the-api)
16. [In the browser, with no server](#16-in-the-browser-with-no-server)

**Part four — other languages, in and out**
17. [Logical English](#17-logical-english)
18. [PDDL](#18-pddl)
19. [Drools](#19-drools)
20. [Kowalski's book](#20-kowalskis-book)

**Part five — agents**
21. [An LLM that cannot authorise itself](#21-an-llm-that-cannot-authorise-itself)
22. [Minecraft](#22-minecraft)
23. [Industrial control, on paper](#23-industrial-control-on-paper)

**Part six**
24. [Deployment](#24-deployment)
24a. [How it was built, and what that cost](#24a-how-it-was-built-and-what-that-cost)
25. [What is not there](#25-what-is-not-there)
26. [Where to start](#26-where-to-start)

---

# Part one — what it is

## 1. The short version

LPS2 is about 10,000 lines of SWI-Prolog in three layers — a pure core, the syntax
translators, and the edges that touch the world — plus a browser front end.

It reproduces **99 of the old engine's 108 recorded golden traces exactly**, with the other
nine adjudicated as stale goldens, each naming its evidence. There are no unexplained
failures. It is about **2.5× faster** than the engine it replaces, on a third to a half of
the memory.

On top of that: `achieve` with a real heuristic planner; a derivation forest recorded on
every run, so the engine can answer *why* and *why not*; forking a session as a
unification, which makes "what if?" cost about five microseconds; sessions that run
forever and take events over HTTP; a Monaco IDE with seven views of a run, 2D and 3D
animation and an LLM assistant; front ends for PDDL and Drools; a WebAssembly build with
no server at all; and Logical English compiling straight down to it.

![The IDE](images/ide-overview.png)

## 2. What LPS is

LPS — Logic Production System, Kowalski and Sadri — is a language for programs that *act
over time*. A program is made of:

- **fluents**, which are true over intervals: `light(off)`, `balance(alice, 100)`;
- **events and actions**, which happen between states;
- **causal laws** saying what an event does to the state: `switch(New) initiates
  light(New)`;
- **reactive rules**, which are maintenance goals: `if C at T1 then A from T1 to T2` means
  *whenever C becomes true, make A true*;
- **constraints**, which are denials: `false execute(A), destructive(A), not approved(A)`.

The engine runs a cycle — observe, think, decide, act — and the interesting part is the
*decide*: several rules may want incompatible things, the constraints rule some out, and
what survives is committed as a set of actions for that cycle.

Two properties matter for what follows. First, the causal laws are stated once and every
rule inherits them, so the physics of the world is not spread through the code that acts.
Second, a constraint is enforced by the engine, not by the thing being constrained — which
is why the safety argument in §21 is structural rather than a matter of prompt discipline.

### A whole program, and what it does

`legacy_lps1/examples/CLOUT_workshop/bankTransfer.pl`, from the corpus, is short enough to
read in full and contains almost every construct:

```prolog
maxTime(10).
actions          transfer(From, To, Amount).
fluents          balance(Person, Amount).

initially        balance(bob, 0), balance(fariba, 100).
observe          transfer(fariba, bob, 10)        from 1 to 2.

if      transfer(fariba, bob, X)     from  T1 to T2,
        balance(bob, A) at T2, A >= 10
then    transfer(bob, fariba, 10)    from T2 to T3.

if      transfer(bob, fariba, X)     from  T1 to T2,
        balance(fariba, A) at T2, A >= 20
then    transfer(fariba, bob, 20)    from  T2 to T3.

transfer(F,T,A) updates Old to New in balance(T, Old) if New is Old + A.
transfer(F,T,A) updates Old to New in balance(F, Old) if New is Old - A.

false   transfer(From, To, Amount), balance(From, Old),  Old < Amount.
false   transfer(From, To1, Amount1), transfer(From, To2, Amount2),  To1 \=To2.
false   transfer(From1, To, Amount1), transfer(From2, To, Amount2),  From1 \= From2.
```

An outside event starts it; two reactive rules bounce the money back and forth; two causal
laws say what a transfer does to a balance; three denials say what must never happen — an
overdraft, and two transfers sharing a payer or a payee in one cycle. Running it:

```
fluents/0        [balance(bob,0),balance(fariba,100)]
fluents/1        [balance(bob,0),balance(fariba,100)]
events/2         [transfer(fariba,bob,10)]
fluents/2        [balance(bob,10),balance(fariba,90)]
events/3         [transfer(bob,fariba,10)]
fluents/3        [balance(fariba,100),balance(bob,0)]
events/4         [transfer(fariba,bob,20)]
fluents/4        [balance(bob,20),balance(fariba,80)]
…
```

Three things about that trace are the whole language in miniature. Nothing says *when* the
reply transfer happens — `T3` is unbound and the engine chose the next cycle. Nothing says
what a balance *is* — the two `updates` clauses are the only place arithmetic appears, and
both reactive rules inherit them. And the two denials about concurrency are what make an
*action set* a set: they are the reason the engine cannot commit two transfers from bob in
one cycle, and no rule had to know about the other.

### When rules disagree

The part of an LPS engine that is genuinely hard is what happens when several rules want
incompatible things. LPS1 had an answer — it is in the code — but never wrote it down,
and "reimplement LPS" is under-specified without it. `docs/selection_spec.md` is that
document: twenty numbered selection points, SP1–SP15 derived from reading the old engine
and SP16–SP20 discovered while building the new one, each stating where the engine chooses
and which rule it actually follows.

Two examples of the kind of thing it settles:

- **The cycle's phases are not what the plan first said.** Under the default (prospective)
  mode the state is *not* advanced by a single `updateFluents` step; it is advanced inside
  two later phases by `updateNextStateFluents` and `copyNextState`. The plan's own
  description was wrong, and the specification marks the correction.
- **Phase 10 is one conjunction.** Observation injection, goal resolution and the
  next-state precondition check share a single backtracking context, so a precondition
  violated at the *end* can backtrack all the way into event injection at the *start*.
  That is observable semantics, not an implementation detail.

Each selection point is also marked *load-bearing* or *incidental*. The incidental ones are
where a future canonical mode is allowed to depart from LPS1; the load-bearing ones are
what the conformance corpus is actually testing.

## 3. Why reimplement it

The original engine (`legacy_lps1/`) is about 5,000 lines: `engine/interpreter.P`,
`utils/psyntax.P`, an operator table and a small store. It works, and the corpus of
example programs that ships with it is the accumulated knowledge of what LPS is for.

What it also has is heavy interleaving. `interpreter.P` contains the cycle, the resolver,
the state update, the test harness, SWISH hooks, thread management and server plumbing in
one file. There are 48 `thread_*` references, clustered around the query-answering layer.
Program (immutable clauses) and session (mutable state) live in the same dynamically
selected module, mediated by `u_call/1` and friends.

None of that is a criticism of the code — it is what a research engine that grew a web IDE
looks like. But it is what stands between LPS and a planner, a forkable session, a WASM
build, or a second front end. Every one of those is downstream of one architectural change:
**separate the program from the session, and keep the core pure.**

The reimplementation is clean-room in a specific sense. The engine is written from the
plan, from `docs/selection_spec.md` (a numbered account of the selection strategy,
SP1–SP20) and from observed behaviour. Reading `interpreter.P` is intended — it is the
user's own code, and §I.4 of the plan makes the operator table and the internal vocabulary
explicit interface specifications. What is *not* done is transliteration: the resolver is
written against the numbered rules, so LPS1's accidents are inherited only where the
specification says they are load-bearing.

## 4. The conformance contract

This is the part that makes the rest trustworthy, and it is worth stating precisely.

A golden `.lpst` file is a set of facts: `lps_test_result(Stage, Cycle, Count)` and
`lps_test_result_item(Stage, Cycle, Term)` for `Stage ∈ {fluents, events, composites}`.
Comparison is: exact item count, then `sort/2` on both sides and `variant/2`. Order within
a cycle is free; **cycle alignment, item count and term shape up to variable renaming are
exact**.

That is trace equivalence, not semantic equivalence, and it is a much harder target than
"the examples still work". A program that reaches the same answer by a different route
fails.

| bucket | meaning | count |
|---|---|---:|
| a | invariant under every perturbation | **99** |
| b | choice-sensitive; needs a stated selection rule | 0 |
| c | diverges on an identical rerun | 0 |
| adjudicated | stale golden | 3 |
| adjudicated | stale golden, recorded 2019 | 6 |
| **baseline_fail** | **unexplained failure** | **0** |

Perturbations are part of the harness, not an afterthought: each program is also run with
its clauses reversed, its initial fluent list reversed, its goal queue prepended instead of
appended, and re-serialised unchanged as a control. A test that changes under any of these
is choice-sensitive and needs a *stated* selection rule rather than an accident. None do.

The nine adjudications each name their evidence in `conformance/adjudicated.pl`. Six are
goldens recorded in 2019 on SWI 8.1.1, before LPS1 began recording `real_date_begin/1`
as a composite event — and the legacy engine fails them today with exactly the diagnoses
LPS2 produces. One covers ten cycles of a program that now declares `maxTime(8)`. One
predates a `maxRealTime` declaration. One is `prospectiveGoat`, whose 2017 golden contains
no `composites` records at all.

There is also a finding about the old harness worth recording: **LPS1 drives its
comparison from the cycles the run actually produced**, so a run that dies half way scores
"ok". Our harness classifies on its own strict verdict and reports LPS1's alongside.
Two corpus entries pass LPS1 while leaving golden cycles uncovered.

`--engine cross` runs both engines and compares them with each other rather than with the
golden — the only meaningful comparison when a golden predates LPS1's own behaviour.

**Speed.** Median ≈0.4× the old engine's wall time, memory a third to a half
(`tools/compare_engines.pl`). One program is slower: `prospectiveGoat2`, at 2.4×, because
it re-checks prospective denials per candidate action. Closing that means restructuring the
prospective check, which wants its own conformance sweep rather than a benchmark-driven
edit, so it is open.

## 5. The architecture, and what it buys

```
src/core/     the engine. No I/O, no threads, no clock, no foreign code.   5,449 lines
src/syntax/   external syntax ↔ internal representation                    1,681 lines
src/edges/    everything that touches the world: files, CLI, HTTP          3,314 lines
```

`tools/lint_core.pl` enforces the first line: nothing in `src/core/` may reference threads,
sockets, HTTP, `process_create`, `shell`, `get_time`, foreign predicates, randomness or
file I/O. The one deliberate exception is `b_setval`/`nb_setval`, confined to one file
whose header explains why the engine cannot be written without them.

That rule was not kept for its own sake. Four things fall out of it:

**A session is an immutable term.** So `lps_session_fork/2` is a unification. §I.6 of the
plan designed a dual-backend copy-on-write scheme for hypothetical worlds; it turned out to
be unnecessary. Measured at **~5 µs, independent of session size** (`tools/bench.pl`).

**Time is injected, never read.** The engine has no notion of the wall clock. Pacing a
session at two cycles per second is an *edge* concern, and lives in one predicate in
`src/edges/lps_live.pl`. The consequence is that a live session and a batch run are the
same engine.

**The whole core compiles to WebAssembly.** §16. The go/no-go review the plan scheduled was
answered by the artefact: bundling `src/core/` and `src/syntax/` into a self-contained page
was a day's work, because the half that touches the world was already a separate half.

**Determinism is checkable.** The perturbation harness above is only possible because a run
is a function of the program, the options and the observations.

---

# Part two — what is new

## 6. Differences from LPS1, in one table

| | LPS1 | LPS2 |
|---|---|---|
| **Language** | reactive rules, causal laws, constraints, composite events, intensional fluents | the same, plus `achieve` and `display3d/2` |
| **Planning** | goal reduction; `prospectively` for lookahead | `achieve` with breadth-first, greedy best-first under a delete-relaxation heuristic, or automatic selection; concurrent action sets; replanning on failure |
| **Explanation** | — | a derivation forest recorded on every run; five question forms; four distinct `why_not` answers |
| **Hypotheticals** | — | `lps_session_fork/2`, ~5 µs; `what_if` diffs two traces |
| **Perpetual runs** | yes, with real-time options | yes, plus asynchronous event injection over HTTP, per-channel allow-lists, bounded trace, lifecycle |
| **Diagnostics** | Prolog errors | structured diagnostics with `src(File,Line,Col,Kind)` provenance, surviving translation from Logical English |
| **2D animation** | paper.js in SWISH | Konva, same `display/2` vocabulary, y flipped, offline icon library, and clickable — `lps_mousedown/3` and friends |
| **3D animation** | — | three.js, `display3d/2` |
| **State diagram** | `godfa/1`, one column | dagre layered layout, merged parallel edges, self-loops, in both IDEs and on the CLI |
| **Editor** | SWISH | Monaco: one grammar for LPS-and-Prolog generated from the operator table, in-loco diagnostics, menus, examples browser, splitter, shared zoom/pan |
| **Assistant** | — | an agentic loop with `analyse`/`run`/`explain`/`scene` as in-process tools, five providers |
| **Front ends** | LPS syntax, `.lpsw`, lps.js | LPS syntax, internal syntax, Logical English, PDDL, Drools |
| **Deployment** | SWISH server | CLI, single-endpoint HTTP API, container, WebAssembly |
| **Core purity** | interleaved | enforced by a linter |

The rest of Part two takes the interesting rows one at a time.

## 7. Planning that is actually a planner

`examples/goat_declarative.pl` states the wolf/goat/cabbage puzzle rather than solving it:

```prolog
:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

actions row(_,_), transport(_,_,_).
fluents loc(_,_).

initially loc(wolf,south), loc(goat,south), loc(cabbage,south), loc(farmer,south).

transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

%  the puzzle constraints, in the prospective form: a denial about the state
%  the crossing *would* produce
false loc(goat,L) at T, loc(wolf,L) at T,    not loc(farmer,L) at T, row(_,_) to T.
false loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T, row(_,_) to T.

false transport(farmer, _, _).
false transport(Object, L1, _) from T1 to _,  not loc(farmer, L1) at T1.
false transport(_, L1, L2)     from T1 to T2, not row(L1, L2) from T1 to T2.
false row(L1, _)               from T1 to _,  not loc(farmer, L1) at T1.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

Compare `examples/goat.pl`, where the same knowledge — that the goat cannot be left with
the wolf or the cabbage — never appears as a constraint at all. It has been compiled by
hand into six `dealWithGoat` cases. The declarative version is shorter, and the thing it
says out loud is the thing a reader wants to check.

**Two searches, chosen automatically.** `search(auto)` is the default: node-budgeted
breadth-first while the branching factor is small enough to be exhaustive, greedy
best-first under a delete-relaxation heuristic (h^add) when it is not. `examples/blocks.lps`
is the example that separates them — seven blocks in one tower, to be rebuilt in reverse:

```
./lps run examples/blocks.lps --search greedy      0.4 s
./lps run examples/blocks.lps                      5.3 s   (auto)
./lps run examples/blocks.lps --search bfs        25.5 s
```

and the gap is exponential in the number of blocks, not constant.

**Plans are action *sets*.** `max_concurrency(2)` lets two compatible actions share a
cycle, which is what the goat needs: rowing and carrying happen together.

**Plans can fail.** A plan that stops being valid — the tree is gone, someone took the log
— fails at execution and is replanned against the state the program is actually in. That
is what makes planning usable from an agent rather than only from a puzzle.

The 3D pane below is `examples/blocks3d.lps`, which is `achieve on(c,b), on(b,a)` and a
`display3d/2` clause that computes each block's height by walking the tower in the state:

![3D](images/ide-3d.png)

## 8. Explanations

Every run records a derivation forest, unconditionally — not behind a debug flag, because
a flag you have to have set in advance is no use after an incident.

**The question is asked where the thing is.** There was an explain pane once: a text field
in a tab nobody opened, which asked you to type a term you had just read off another pane.
That is backwards, because the panes are *full* of terms and every one of them is a thing
you might want explained. So each visualiser marks what it draws with the term it stands
for, and right-clicking any of them — a timeline bar, a changes row, a state box, an edge
label, a 2D shape, a 3D solid — opens the explanation for that term at that cycle.

![Why](images/ide-explain.png)

Five question forms: `why(happened(A),T)`, `why_not(happened(A),T)`, `why(holds(F),T)`,
`why(stopped(F),T)`, and `what_if(Events,T)`.

`why_not` is the one worth dwelling on, and it has its own field in the modal because you
cannot right-click something that was not drawn. "It didn't happen" has four different
causes and treating them alike is how a debugging session goes wrong:

![Why not](images/ide-why-not.png)

- **`scheduled_for_another_cycle`** — the plan does intend to, at cycle 6, as step 4.
- **`no_goal_created`** — nothing ever asked for it.
- **`rejected_by_prospective_constraint`** — something asked, and a named denial refused it.
- **`no_plan_found`** — asked for, and no plan within the horizon.

Outside those, the answer is an honest "no applicable rule". The pane never reconstructs a
plausible story: if the trace cannot settle it, it says *not recorded*. All thirteen cases
are covered by `tools/explain_test.pl`.

## 9. The state-transitions diagram

LPS1 had `godfa/1`, which drew every state in one column with edges routed as long
parallel horizontals, one edge per transition. Five `pickup` events between the same two
states drew five labels on top of each other.

![The state-transitions diagram](images/ide-automaton.png)

Same idea, three fixes: parallel edges merged into one edge carrying a list of labels;
dagre layered layout so the run reads left to right and a recurring state is visibly a loop;
bezier edges with arrowheads and haloed labels.

The picture above is the dining philosophers. The hub on the left is the state where all
five forks are free — cycles 1 through 8 — and each box on the right is somebody eating,
with a self-loop while they carry on. Every distinct state appears **once**, which is the
whole point: a program that revisits a state should read as a loop, not as a long chain.

`./lps automaton PROGRAM` prints it; `/lpsapi automaton` returns it as JSON; both IDEs have
the pane. Two toggles: *abstract numbers* (collapse states that differ only in a numeric
value) and *hide self-loops*.

## 10. Hypothetical worlds

```prolog
lps_session_fork(Session, Session2)
```

A session is an immutable term, so this is a unification. `tools/bench.pl` measures it at
about five microseconds, independent of how long the session has run.

`what_if(Events, T)` uses it: fork, replay with the different observation, and diff the two
traces the way the conformance harness compares them — stage/cycle keys, membership up to
variance — so a hypothetical reads in the same terms as a test failure.

## 11. Sessions that never end

Drop `maxTime` and the program cycles until stopped, doing nothing until an event arrives.

![A live session](images/ide-live.png)

That is `examples/thermostat.lps`. Two events went in from the panel — `temperature(14)`
then `window(open)` — and the program answered with
`warn(window_open_while_heating)`. Note the *queued for cycle N* lines: an event arriving mid-cycle
is delivered at the next boundary, so a session's trace remains a trace and not a race. The
warning repeats every cycle because a reactive rule is a maintenance goal and the window is
still open.

The pacing is a wall-clock loop in `src/edges/lps_live.pl` — the one place in the system
that reads the clock as a *rate*. The engine's own notion of when things happen is
untouched. The trace is bounded (400 cycles by default), so a session can run overnight.

**Channels.** `live_start` takes a map saying which event predicates each source may send:

```json
{ "llm":   ["task_request/2"],
  "human": ["approval/2", "task_request/2"] }
```

An event whose predicate is not on its channel's list is dropped and *reported* — not
silently, because a client that thinks it observed something needs to know it did not. This
is the mechanism §21 rests on.

The **2D** and **3D** buttons open a window that follows the running session rather than
scrubbing a finished one. They are disabled, with a reason, when the program declares no
visual mapping — an empty window is a worse answer than a button that says why.

![A live 2D view](images/live-2d.png)

**And the animation can be an interface.** A program that declares `lps_mousedown/3`,
`lps_mouseup/3` or `lps_mousedrag/3` as events receives them from that window, in its own
scene coordinates; a program that does not gets no listener at all, so a click on a picture
stays a click on a picture. The decision is the server's, taken from the program: the
`mouse` channel's allow-list *is* the set of handlers the program defines, so opening an
animation cannot become a way to fabricate a domain event.

![Clicking a program](images/live-click.png)

That is `examples/lights.lps` — four lamps, click to toggle, and a denial that will not let
you turn off the last one. It closes the one item of `legacy_lps1/swish/2dWord.md` that was
still open.

---

# Part three — the surfaces

## 12. The IDE

`./lps ide` serves it on port 3060. It is built with esbuild from `ui/` into
`src/ide/dist/`; Node is a *build* dependency, and the container that serves the result has
no Node in it.

- **Several files at once.** A tab owns its Monaco model *and* its run — session, program,
  cycle, diagnostics — so everything right of the splitter is about the file whose tab is
  lit, and switching back restores what you were looking at. Comparing two versions of a
  program is two tabs rather than two browser windows.

  ![Two files, each with its own run](images/ide-tabs.png)

- **Monaco**, with one grammar covering LPS and the Prolog you can write inside it. The
  grammar's operator table is *generated* from the engine's own (`tools/gen_monarch.pl`),
  so the editor cannot drift from the parser. Monaco's own features — the context menu,
  find and replace, folding, occurrence highlighting — are opt-in imports: the API entry
  point ships none of them, which is why an earlier version of this editor had a right-click
  that did nothing.
- **Diagnostics in the text.** A squiggle on the line, the message on hover, a mark in the
  overview ruler, F8 to walk them, and a count in the top bar that jumps to the first. There
  used to be a strip under the editor repeating all this; it spent its life saying "no
  problems" and put the message a long way from the line it was about. A syntax error is a
  diagnostic, not an exception — a program that does not parse still reports everything the
  reader could determine:

  ![Diagnostics](images/ide-diagnostics.png)

- **Six panes**: timeline, state changes, state transitions, 2D, 3D, internal syntax. All
  scrub together on one cycle slider, and all share one zoom-and-pan behaviour. (There used
  to be a seventh; see §8.)

  The timeline is one lane per fluent over the intervals it holds, with the events of each
  cycle below it. It is not instrumentation: those are the same
  `stage(fluents, Cycle, Items)` records the conformance harness compares against
  LPS1's goldens, so nothing in the engine has to be switched on to draw it.

  ![The timeline](images/ide-timeline.png)

- **Menus** — File, Edit, Misc, Help — modelled on LE2's, including API keys, the server
  token, and *Deploy as WASM*:

  ![The Misc menu](images/ide-menu.png)

- **An examples browser** over every program on the server, each with the first line of its
  own comment as a description, and a name column you can drag:

  ![Examples](images/ide-examples.png)

- **The internal syntax pane**, which is worth a look once because it shows that the sugar
  is sugar:

  ![Internal syntax](images/ide-internal.png)

The **state changes** pane answers a narrow question about one cycle — what changed, and
which causal law did it:

![State changes](images/ide-changes.png)

`line 24` is a line in the file in front of you. Everything unchanged is listed separately
as *persisted*, because the engine knows the difference between "still true" and "made true
again".

**Two IDEs, deliberately.** `/LogicalEnglish2/editor/lps.html` is LE2's, with two language
modes and two backends. `src/ide/` is ours. Both speak only `/lpsapi`, which is the
constraint that keeps the API honest: everything the editor can do is reachable with
`curl`, and testable without either editor.

## 13. Animation, 2D and 3D

`display/2` maps a fluent or an event to a shape. The vocabulary is LPS1's, from
`legacy_lps1/swish/2dWord.md`:

```prolog
display(burning(X,Y), [type:circle, center:[CX,CY], radius:10, fillColor:yellow]) :-
	pixels(X, Y, CX, CY).
display(ignite(X,Y),  [type:star, fillColor:red, center:[CX,CY],
		       points:6, radius1:10, radius2:6, opacity:0.5]) :-
	pixels(X, Y, CX, CY).
display(timeless, [[type:rectangle, from:[0,0], to:[200,200], strokeColor:green]]).
```

![2D](images/ide-2d.png)

That is `CLOUT_workshop/burning.pl` from the corpus, unmodified, at cycle 6 — a fire
spreading across a grid. Every shape in the old vocabulary renders, the origin is bottom
left with y growing upward as it was, and only the first `display/2` solution per subject
is drawn, which is also LPS1's behaviour.

**An icon library**, because several corpus programs hotlink clipart that is no longer
reachable and render as holes. 134 SVGs — OpenMoji (CC BY-SA 4.0), game-icons.net (CC BY
3.0), Material Symbols (Apache-2.0) — curated against a functor census over the corpus:
finance and contracts, legal and governance, puzzles and games, places and motion. They are
checked in and served from our own endpoint, so a deployment with no internet still
animates. `[type:raster, icon:fire]`.

`display3d/2` is a separate declaration rather than a reinterpretation of `display/2`: 2D
properties do not carry into three dimensions without lying about what the author meant,
and a program may reasonably want both at once showing different things. The types are
`box`, `sphere`, `cylinder`, `cone`, `plane`, `ground`, `line`, `arrow` and `text`, with
`camera` and `light` in the `display3d(timeless, …)` backdrop.

## 14. The assistant

An agentic loop in Prolog, after LE2's `le_assistant_light.pl`. Five providers
(OpenAI, Groq, Anthropic, Together, Gemini); the server's environment wins over whatever the
browser is carrying, so a deployment can configure a key centrally.

Its tools are the panes' own operations, called in process: `analyse` (compile, get
diagnostics), `run` (run, get the trace), `explain` (ask the same questions §8 answers), and
`scene` (what did the display clauses actually draw). A model that asks "does this compile?"
gets the same answer the problem strip shows, because it is the same call.

The model list is the providers' own: `lps_models.pl` reads each catalogue at server start,
in a thread so a slow provider does not slow `./lps ide` down, and the preferences dialog
shows the count per provider and re-reads on demand. The hand-maintained table in
`lps_llm.pl` remains the offline fallback.

Two canned prompts, **Animate in 2D** and **Animate in 3D**:

![The assistant](images/ide-assistant.png)

and one click later:

![The result](images/ide-assistant-2d.png)

That is the declarative goat — a program with no visual mapping at all — animated by
`openai/gpt-oss-120b`.

**The model does not write coordinates**, and that is the whole design. Asking it to
produced exactly what you would expect: plausible and overlapping, three animals at the
same point, a label off the edge. Models know that a goat belongs on a river bank; they are
bad at arithmetic over a canvas; and no amount of "check your work" fixes an arithmetic
problem by making the arithmetic more earnest.

So the work splits, in the shape this problem has converged on elsewhere too —
DiagrammerGPT's "diagram plan", parse-then-place, the decoupled
logical-artifact-then-renderer patent:

  **stage 1** — the model returns a *plan*: containers, the things that move between them,
  which fluent template puts a thing in a container, what each thing looks like.

  **stage 2** — `src/edges/lps_scene.pl` lays it out. Box flow, Yoga's model rather than
  Cassowary's: the plan expresses containment and order, which is what a flexbox consumes,
  and boxes that flow cannot overlap by construction. Cassowary would be right if the model
  were emitting alignment constraints; it is not, and asking it to would move the hard part
  back where it was.

What lands in the buffer is ordinary Prolog — an `lps_slot/4` table, a backdrop and one
`display/2` rule per layer — so the program stays readable and self-contained, and nothing
at run time calls back into the assistant. Every container gets the *same* grid, so a thing
keeps its column wherever it is; that is what makes the animation readable and what a
per-container packing would have destroyed.

The 3D prompt still writes clauses directly, and checks itself with the `scene` tool, which
reports per cycle what each clause drew *and which fluents nothing matched*. Before that
tool existed the same model wrote a blue rectangle labelled "river", observed that the
scene was non-empty, and finished — correctly, by the letter of its instructions.

## 15. The command line and the API

```sh
./lps run examples/goat_declarative.pl
./lps step PROGRAM --cycles 3
./lps live examples/thermostat.lps --cycle-ms 400
./lps explain PROGRAM --ask "why_not(happened(a), 4)"
./lps timeline PROGRAM
./lps changes  PROGRAM --at 2
./lps automaton PROGRAM
./lps dump PROGRAM
./lps pddl domain.pddl problem.pddl
./lps drools rules.drl
./lps ide --port 3060
```

The HTTP surface is **one endpoint**, `/lpsapi`, dispatching on an `operation` field, with
optional token auth and CORS. Thirty-odd operations: `compile`, `session_new`, `observe`,
`step`, `run`, `state`, `fork`, `trace`, `dump`, `analyse`, `explain`, `timeline`,
`changes`, `scene`, `scene3d`, `automaton`, `example`, `list_examples`, the `live_*`
family, the `assistant_*` family, `wasm_bundle`.

One endpoint rather than a REST surface is a deliberate choice: it makes the whole API
scriptable from one `curl` invocation shape, and it is what lets the two IDEs, the Minecraft
bot and the Part II demo all be clients of exactly the same thing.

## 16. In the browser, with no server

**Misc ▸ Deploy as WASM** produces a single self-contained HTML file: swipl-wasm, the whole
of `src/core/` and `src/syntax/` inlined as sources, and your program.

![WASM](images/wasm.png)

That is `CLOUT_workshop/bankTransfer.pl` running in Chromium with no server involved. The
edges — HTTP, the assistant, live sessions, the LE bridge — are not in it and could not be:
they are the half that touches the world, and the page has no world to touch. That the
other half loads at all is the entire content of the proof, and it is a property
`tools/lint_core.pl` has been enforcing since the first milestone rather than something
arranged for the occasion.

---

# Part four — other languages, in and out

## 17. Logical English

LE2 (`/LogicalEnglish2`, branch `with-lps2`) compiles Logical English to LPS internal
syntax and runs it on this engine. The interface contract is
`docs/le_lps_interface.md`, duplicated verbatim in both repositories.

![Logical English on LPS2](images/le2-lps.png)

That is LE2's own editor: an English program on the left, compiled by LE2 and run by
LPS2, with our timeline on the right. The two servers talk directly — no proxy — which is
why CORS is in the API.

Here is the bank transfer of §2, in English:

```
the target language is: lps.

the maximum time is 10.

the actions are:
    *a payer* transfers *an amount* to *a payee*; known as transfer.

the fluents are:
    the balance of *a person* is *an amount*; known as balance.

the knowledge base bank transfer includes:

initially the balance of bob is 0
    and the balance of fariba is 100.

if fariba transfers an amount to bob from a first time to a second time
    and the balance of bob is a second amount at the second time
    and the second amount >= 10
then bob transfers 10 to fariba from the second time to a third time.

when a payer transfers an amount to a payee
then the balance of the payee that is a number becomes number + amount
    and the balance of the payer that is a second number becomes second number - amount.

it must not be true that
    a payer transfers an amount to a payee from a first time to a second time
    and the balance of the payer is a second amount at the first time
    and the second amount < the amount.

scenario one is:
    fariba transfers 10 to bob from 1 to 2.
```

and here is what `le_lps.pl` makes of it — the internal syntax this engine runs:

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

Four things are worth noticing. `known as transfer` is what ties an English template to a
functor. `when … then … becomes …` is the English for a causal law, and it lands on
`updated/4` — the same `updates … to … in …` an LPS author writes. `it must not be true
that` is `false`, and lands on `d_pre/1`. And `scenario one is` is `observe`. The English
is not a veneer over a different language; it is the same language.

The load-bearing piece for using it is **provenance**. LE2 emits
`t(Term, src(File,Line,Col,Kind))`, and `/lpsapi compile` takes a parallel `provenance`
array; every diagnostic comes back with a decomposed `source`, so an error in generated
internal syntax lands on the **English** line it came from. Without that, an LE user
debugging an LPS error is reading someone else's program. `tools/m8a_test.pl` is the gate:
six cases including "a diagnostic lands on the .le line it came from" and "a `.le` file
with no LE2 configured is refused, not guessed".

Fifteen programs live in `/LogicalEnglish2/examples/lps/`, all fifteen translating to
internal syntax and thirteen running to success under `./lps run foo.le`. A `.lps` file
alongside a `.le` file compiles together with it — the escape hatch for the constructs the
English surface does not reach.

The reverse direction exists too: `le_lps_write.pl` writes internal syntax back out as
Logical English, and 13 of 15 test programs make the round trip `LE → internal → LE →
internal` `variant/2`-equal. The two exclusions are stated: a calendar date constant has no
LE surface form.

## 18. PDDL

```sh
./lps pddl examples/pddl/blocks-domain.pddl examples/pddl/blocks-p1.pddl
```

```
; plan for examples/pddl/blocks-p1.pddl (6 steps)
0: (pick-up b)
1: (stack b a)
2: (pick-up c)
3: (stack c b)
4: (pick-up d)
5: (stack d c)
; VALIDATION: valid
```

The translation is the obvious one and is the argument for LPS's shape: a PDDL
**precondition becomes a denial**, an **effect becomes a causal law**, a static predicate
becomes a timeless fact, and the problem's `:goal` becomes `achieve`. Types become
declarations. Nothing about the planner is PDDL-specific — it is the same `achieve` the
goat uses.

The rule the plan sets for every front end is **specify the oracle before writing the
transpiler**, and it was followed: `pddl_plan_valid/4` is an independent plan checker that
applies the PDDL semantics directly, written first. The test reports plan length against
the benchmark's known optimum:

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
logistics-domain       logistics-p1    …still searching…
```

Eleven of twelve solve and validate; ten of those are optimal. Hanoi is the useful one for
that claim, because 2^n − 1 is a number you compute rather than look up.

**And it opens like any other file.** `File ▸ Open` takes the domain and the problem
together, converts them, and gives you an LPS buffer with a header saying what it was
converted from and when — plus the planning directive that makes it runnable as it stands.
Open only one of the two and it says which is missing rather than producing half a program.

This is the front end that pays *inward*: benchmarks with known-optimal plan lengths are a
test of the M6 planner that no LPS program was going to provide, and the results are the
honest ones. Greedy best-first finds valid plans that are not optimal — 15 steps against a
known optimum of 11 on `gripper-p1` — which is what greedy best-first does. The logistics
domain is worse: it was still searching after forty minutes. Both are planner
findings rather than translation findings, which is exactly what a front end with an
independent oracle is for; neither would have surfaced from LPS programs alone.

## 19. Drools

```sh
./lps drools examples/drools/fire-alarm.drl
```

`src/syntax/lps_drools.pl` reads DRL — `declare` types, `when`/`then` rules, `insert`,
`retract`, `modify(){}`, `not` patterns — and produces reactive rules and causal laws.
`modify(){}` maps onto `updated/4`, which is exactly LPS's `updates … to … in …`, and is
the point at which the two languages agree most exactly.

Where they do not agree, it says so rather than guessing: `salience` is a conflict
resolution strategy LPS does not have (LPS resolves by constraint, not by priority), and a
Java expression in a consequence is a leaf this engine cannot evaluate. Both come back as
diagnostics.

`.drl` files open through `File ▸ Open` too, converted the same way and with the same
provenance header; the generated `initial_state([])` is where you put the facts.

`tools/drools_test.pl` runs eight rule bases against expected behaviour: 8/8. The three
newest — a traffic light as a state machine, insurance eligibility, and order shipping —
are there because examples earn their keep by breaking things, and shipping did: `retract(o)`
where `o` is a *pattern variable* was producing an action named after the variable that
terminated no fluent at all, so the rule fired for ever and the fact stayed.

## 20. Kowalski's book

*Computational Logic and Human Thinking* is the book LPS and Logical English both descend
from. LE2 had already catalogued **226 examples** from it and rendered the **22** that fit
Logical English. The interesting number is the other 132, and specifically *why* they were
left out: LE2's own list of what it lacked reads as a description of LPS — maintenance
goals and the observe–think–decide–act cycle, event- and situation-calculus primitives,
explicit integrity constraints and prohibitions, forward-chaining condition–action rules.

Counting mechanically, **68 of the 132 are blocked only on constructs LPS has**.

`examples/rkbook/` has twelve of them, chosen to cover the chapters whose subject *is* the
agent cycle and to put at least one program against each construct LE could not express:
the Underground Emergency Notice, the penalty sentence as an inhibitor of action, the fox
and the crow, the wood louse, the Mars explorer, the trolley problem, citizenship over
time, violations and contrary-to-duty obligations, the event calculus, plan generation.
Each has a behavioural test; `tools/rkbook_test.pl` runs 12/12.

---

# Part five — agents

## 21. An LLM that cannot authorise itself

The claim Part II of the plan rests on is that **the model is never the thing that
authorises the dangerous action** — not because it is asked nicely in a system prompt, but
because the fluent that authorises it is unreachable from the model's channel.

`examples/agent/approval.lps`:

```prolog
%  Causal laws
request_approval(A) initiates pending(A).
approval(grant, A)  initiates approved(A).
execute(A)          initiates done(A).
execute(A)          terminates approved(A).      % approval is single-use

%  The gate
if   task_request(delete, File) from _ to T1, destructive(delete_file(File))
then request_approval(delete_file(File)) from T1 to T2,
     approved(delete_file(File)) at T3,
     execute(delete_file(File)) from T3 to T4.

%  The hard constraint
false execute(A), destructive(A), not approved(A).
```

`examples/agent/demo.mjs` drives it against a live session, with the LLM channel allowed to
carry `task_request/2` and nothing else:

```
live session live6 — the llm channel may carry task_request/2 only

human:  “the application logs are stale, please delete app.log”
model:  perceived ["task_request(delete,app.log)"]
lps:    the gate fires — approval requested, execution withheld
        │ cycle 4: [request_approval(delete_file('app.log')),task_request(delete,'app.log')]

model:  now tries to approve its own request
        │ refused: ["approval(grant,delete_file('app.log'))"]
        │ REFUSED on channel llm: [approval(grant,delete_file('app.log'))]

lps:    at cycle 11 the state is ["pending(delete_file('app.log'))"]
        │ pending, never approved — the constraint is not advice

human:  approves, on the human channel
        │ cycle 12: [execute(delete_file('app.log')),approval(grant,delete_file('app.log'))]

lps:    it executed — the state is now ["done(delete_file('app.log'))"]
```

The model does the one thing only a language model can do — turn a sentence into an event
term — and nothing else. Everything downstream is the engine. Run it with a weak model, or
with a prompt telling it to lie: `approved/1` is reachable only through a causal law fired
by an `approval/2` event, `approval/2` is not on the LLM channel's allow-list, and the
constraint that blocks `execute` is checked by the engine rather than by the thing being
constrained.

That is a proof of concept, not Part II. What it establishes is that the safety property is
*structural*, which was the open question.

## 22. Minecraft

`examples/minecraft/` is an LPS agent playing Minecraft, in two tiers:

| tier | what runs there | rate |
|---|---|---|
| **controller** | mineflayer + mineflayer-pathfinder: walking, jumping, swinging, collision, path following | 20 ticks/second |
| **supervisory** | an LPS live session: maintenance goals, constraints, plans, explanations | 2 cycles/second |

The split is the point, and it is §V.4's industrial-control architecture moved from a
drilling rig into a game: the supervisory tier **can be wrong without being dangerous**,
because every action it issues is filtered by the program's constraints before the
controller tier sees it.

**Cycle alignment** is a deliberate non-choice. LPS cycles are *not* aligned to
`physicsTick`. A tick is 50 ms; deliberation does not need to happen twenty times a second,
and aligning them would make the engine's rate a property of the game rather than of the
agent. Anything that must react faster than a cycle — falling, drowning, a creeper at two
blocks — belongs in the controller tier, and some of it is there.

You need no account, no client and no purchase: **flying-squid** is a Minecraft server in
JavaScript and the bot connects in offline mode.

```sh
node world.mjs &                # a local server on :25565
node bot.mjs --program safety.lps
```

```
[bot] spawned
[lps] safety.lps running as live3, one cycle every 500 ms
[lps→bot] place_torch
[lps→bot] place_torch
```

`craft.lps` is the same bot planning instead of reacting — `achieve has(wooden_pickaxe)`
with the recipes as causal laws and the tool requirements as denials:

```
events/2         [walk_to(tree)]
events/3         [chop(tree)]
events/4         [craft(plank)]
events/5         [craft(stick)]
events/6         [craft(wooden_pickaxe)]
```

Nothing in that file says *how* to get a pickaxe. The order falls out of the search.

`prismarine-viewer` serves a browser view and draws the bot's current path as a blue line —
the supervisory tier's decision made visible, with the controller tier walking it:

![The bot, through prismarine-viewer](images/minecraft-viewer.png)

It renders map tiles server-side and therefore needs the native `canvas` module, which is a
dependency of the example rather than a footnote: on macOS, Windows and mainstream Linux
npm downloads a prebuilt binary. Where there is no prebuild it wants Cairo and Pango, and
`examples/minecraft/README.md` says which packages. The bot imports the viewer lazily
either way, so a machine without it still runs the agent — just without the picture.

## 23. Industrial control, on paper

Part V of the plan is the industrial-control direction: LPS as a supervisory layer over
existing controls, and eventually a generator targeting IEC 61131-3 Structured Text. No
code exists for it. What §V.7a now names is the tool chain a demonstration would use —
MATIEC to compile Structured Text to C, Beremiz as the IDE, OpenPLC as a soft PLC to run
the result — so that the first milestone in that direction starts from a known target
rather than a survey.

The nearest thing to shovel-ready is §V.7's **supervisory tier**: no code generation at
all, just this engine plus the container, running read-only alongside existing controls.
Live sessions were what it was waiting for.

---

# Part six

## 24. Deployment

A two-stage container: Node builds `ui/` into `src/ide/dist/`, and SWI-Prolog serves the
engine, the API and the IDE on one port. There is no Node in the runtime image.
`fly.toml` and `buildPush.sh` deploy it; `docs/deploy.md` covers running it alongside LE2,
which needs the two servers to be reachable from the same browser and therefore needs the
CORS configuration.

`LPS_TOKEN` sets the API token; `LPS_ORIGIN` narrows CORS; the five LLM provider keys are
read from the environment and take precedence over anything a browser sends.

## 24a. How it was built, and what that cost

Six practices did most of the work here, and they are the transferable part.

**Conformance first, and it gates everything.** The very first milestone was not code, it
was a harness: run the *old* engine over the whole corpus, classify each program by whether
its trace survives perturbation, and record the numbers. Nothing after M4 was allowed to
start until the new engine reproduced those traces. That ordering is uncomfortable — it
means several weeks with nothing to show — and it is why every feature since could be added
without wondering whether it broke the semantics.

**Write down what the old code chooses.** `docs/selection_spec.md` exists because a golden
trace records *the choice the 2021 engine happened to make*, and reproducing that without
naming it is cargo-culting. Twenty numbered selection points, each marked load-bearing or
incidental. Five of them (SP16–SP20) were discovered by the new engine failing a test.

**Specify the oracle before writing the transpiler.** For PDDL, an independent plan checker
was written first; for Drools, expected behaviour per rule base. A front end that is checked
only by "the output looks like PDDL" is checked by nobody.

**Enforce the architectural rule with a linter.** `tools/lint_core.pl` runs before every
commit. Core purity was not a principle anyone remembered — it was a build failure — and
that is why the WebAssembly build took a day instead of a rewrite.

**Never guess where you could report.** A `.le` file with no LE2 configured is refused, not
approximated. `./lps dump --syntax legacy` says the reverse translator does not exist
rather than emitting something plausible. `salience` in a DRL file becomes a diagnostic.
An explanation the trace cannot support is "not recorded".

**Take the screenshots from the running system.** Both this document and the tutorial are
generated against a live server by `tools/doc_shots.cjs`, and that run also fails on
console errors and HTTP 4xx. Three real UI bugs — overlapping timeline labels, a clipped
state diagram, a scene left over from the previous program — were found by photographing
the panes for this document rather than by using them.

The last one generalises: **the documentation pass is a test**. Writing §21 is what
uncovered that an unquoted `app.log` had been parsing as a compound rather than an atom, so
the Part II demo had been reporting a success it never achieved.

## 25. What is not there

- **`dumplps/0`** — the internal→*legacy surface* direction. `./lps dump --syntax legacy`
  says so rather than approximating it, because the plan makes that round trip a *test* and
  a half-working reverse translator would claim agreement it had not earned. The
  internal→*Logical English* direction, which the plan actually gates on, is done.
- **The 2D canvas follows the theme, and a corpus program does not know that.** Every shape
  renders and the y axis is flipped, but a program that assumed a white canvas —
  `fillColor:black` text, and `burning.pl` has some — is hard to read on the dark one.
  There is no per-program background property, and inventing one would be a language change
  rather than a rendering fix; switching theme is the workaround.
- **`prospectiveGoat2` is 2.4× slower than the old engine** (everything else is faster).
- **PDDL plans are not optimal** on gripper-style problems, and the logistics domain was
  still searching after forty minutes (§18). The planner is the constraint, not the
  translation, and `tools/pddl_test.pl` therefore does not finish either.
- **Front ends not attempted**: Jason, DECLARE/BPMN, behaviour trees.
- **Back ends: none.** Part V is entirely on paper.
- **Part II beyond the proof of concept**, and the MCP surface, which is probably the
  highest-leverage single thing left.
- **`docs/conformance_report.md`** (LPS1's own numbers) is checked in but its results file
  is not, so regenerating it needs a full LPS1 sweep of about 35 minutes.
- **LE2's verifier does not know about the `lps` target.** An LPS-target document is
  reported as having "only facts and no rules" and its templates as unused, because both
  checks count Prolog clauses and an LPS program asserts none. The program compiles and
  runs regardless. A two-predicate fix in `le_verifier.pl` is written and *not committed* —
  it belongs to the other repository, which this programme deliberately does not change.

## 26. Where to start

```sh
./lps run examples/goat_declarative.pl        # the language, stated not solved
cd ui && npm install && npm run build         # once
./lps ide                                     # everything else
```

Then:

- **`docs/lps_tutorial.md`** — the teaching path, from a two-line program to live sessions.
- **`docs/UsingTheIDE.md`** — the environment, feature by feature, with a "how do I…"
  section.
- **`docs/LPS2abstract.md`** — two pages, for someone deciding whether to read any of this.
- **`docs/lps_summary.md`** — the reference.
- **`docs/LPSplusLLM.md`** — the plan of record: milestones, the conformance obligation, and
  everything above stated as a requirement before it was stated as a fact.
- **`docs/selection_spec.md`** — for anyone who wants to know what the engine actually does
  when two rules want incompatible things.
- **`examples/`** and the 178-program corpus, two clicks away in the examples browser.
