# LPS2

A reimplementation of the [LPS](https://lps.doc.ic.ac.uk/) engine in SWI-Prolog:
Kowalski and Sadri's logic-and-imperative language, rebuilt around a pure core
with a small session API, and held to the old engine's own test corpus
trace-for-trace.

The plan of record is **[`docs/LPSplusLLM.md`](docs/LPSplusLLM.md)**. It defines
the milestones, and in Part II what the engine is eventually *for*: an agent in
which the symbolic half enforces what must and must not happen while an LLM
supplies perception, candidate generation and English. Parts IV and V take the
same interface in both directions — other agent languages compiled *into* LPS,
and industrial control code generated *out* of it.

```sh
./lps run examples/goat_declarative.pl     # solve the wolf/goat/cabbage puzzle
./lps ide                                  # the web IDE on :3060
```

**Where it stands: M0–M19 are done** — the engine passes the conformance gate;
the IDE, the 2D and 3D renderers, the assistant and perpetual sessions are built
and driven in a browser; PDDL and Drools programs run on the engine; and the
engine runs in a browser as WebAssembly. Milestone-by-milestone state, the known
gaps and the candidate next steps are in **one place**, [the plan's Status
section](docs/LPSplusLLM.md#status). This file does not repeat them.

New here? **[`docs/LPS2abstract.md`](docs/LPS2abstract.md)** is two pages.
**[`docs/IntroducingLPS2.md`](docs/IntroducingLPS2.md)** is the tour, with
screenshots taken from the running system;
**[`docs/lps_tutorial.md`](docs/lps_tutorial.md)** teaches the language;
**[`docs/UsingTheIDE.md`](docs/UsingTheIDE.md)** is the environment; and
**[`docs/lps_summary.md`](docs/lps_summary.md)** is the reference.

## The hard part, and why it shaped everything

A `.lpst` golden file records **the choice the 2021 engine happened to make**
wherever several were possible. Passing the corpus is therefore *trace
equivalence, not semantic equivalence*: the same actions, in the same cycles, in
terms identical up to variable renaming. Clause order is selection order; the
goal queue's discipline is observable; a precondition violated at the end of a
cycle can backtrack into event injection at its start.

99 of the 108 goldens come back exactly, and there are **no unexplained
failures**. The nine that do not are all **stale goldens**, each with a written
justification and cross-engine evidence in `conformance/adjudicated.pl` — six
recorded in 2019 before the old engine started recording an extra kind of
composite event, and three from 2017, including one whose program now declares a
shorter `maxTime` than its trace covers. `--engine cross` runs both engines and
compares their traces with each other rather than with the golden, the only
comparison that means anything once a golden is older than the behaviour it
recorded. **On all nine, the two engines agree.**

So the first deliverable was not code but
**[`docs/selection_spec.md`](docs/selection_spec.md)** — twenty numbered rules
saying where the engine chooses and what it chooses, which the original
codebase never had. SP1–SP15 came from reading the old engine; SP16–SP20 came
from building the new one and are the ones nobody could have found by reading,
because they live in the environment rather than the algorithm. The most
load-bearing:

> **SP16.** "External predicate" means *visible in the program's module*,
> built-ins included. The engine injects `holds(true,T)` into composite-event
> bodies as a time-slack device, and it resolves only because `true/0` is
> thereby an external extensional fluent that can simply be called. Scope this
> to the user's own clauses and every composite event with an implicit end time
> stops working.

## Layout

```
src/core/      the engine. No I/O, no threads, no clock, no foreign code
src/syntax/    external syntax ↔ the internal representation: LPS, PDDL, Drools
src/edges/     everything that touches the world: files, CLI, HTTP, LE, LLM, WASM
ui/            the IDE's sources; esbuild builds them into src/ide/dist/
src/ide/dist/  the built IDE, served by the HTTP endpoint (generated)
examples/      LPS2's own examples: planning, live, PDDL, Drools, agent,
               Minecraft, and twelve programs from Kowalski's book
conformance/   the harness: .lpst runner, both engine adapters, adjudications
tools/         lint, gates, benchmarks, browser tests, screenshot generation
docs/          the plan, the specs, the generated reports — see below
legacy_lps1/   READ-ONLY clone of LPS1 — the reference engine and its corpus
```

Roughly 10,400 lines in `src/`, against the old engine's ~5,000 — with the
concerns actually separated, and a good deal of that being the commentary that
explains *why* a rule is the way it is.

The Logical English front end lives in the **LogicalEnglish2** repository
(`le_lps.pl`, `le_lps_write.pl`, the LPS Monaco mode and panes); the contract
between the two is [`docs/le_lps_interface.md`](docs/le_lps_interface.md),
duplicated verbatim in both.

## The two decisions that shaped the design

**A session is a value.** Everything mutable — state, goal queue, surviving rule
instances, cycle number, event queue, trace — lives in a term the caller holds.
Printing one, diffing two, saving one and forking one are then the same
operation. That made §I.6's hypothetical worlds nearly free: `lps_session_fork/2`
is a unification, measured at ~5 µs independent of session size, and the
dual-backend state store the plan anticipated turned out to be unnecessary.

**Time is injected, never read.** The old engine calls the clock inside its
cycle, which makes traces unreproducible on different hardware — and wraps three
phases in a 0.75 s wall-clock cutoff that *discards* a phase's work on timeout.
That is why one corpus test finished anywhere between 0 and 10 of its 10 cycles
across six runs of the same sweep. LPS2 computes real time from cycle time. The
expectation was that this would cost the seventeen wall-clock-bound programs
their goldens; it cost none, because every one of them also declared a simulated
seconds-per-cycle, so its clock was already deterministic and `maxRealTime` was
already bounding simulated seconds.

## Using it

```sh
./lps run PROGRAM [--cycles N] [--trace FILE] [--observe "e1,e2@3"] [--json]
./lps step PROGRAM --cycles 3          # one CycleReport per cycle
./lps repl PROGRAM                     # step, inspect, fork, discard
./lps dump PROGRAM                     # the internal representation
./lps explain PROGRAM --ask "why_not(happened(a), 4)"
./lps timeline PROGRAM
./lps changes PROGRAM --at 2
./lps automaton PROGRAM                # the run as a state-transition diagram
./lps ide [--port N]
./lps test --engine lps2 --only goat   # the conformance harness
```

Surface syntax (`.pl`, `.lps`), Logical English (`.le`, compiled by LE2) and the
internal form (`_.P`, `.lpsw`) are all read, guessed from the extension.
Everything above is a thin layer over seven core predicates:

```prolog
lps_compile(+Source, +Syntax, +Options, -Program, -Diagnostics)
lps_session_new(+Program, +Options, -Session)
lps_session_observe(+Session0, +Events, -Session)
lps_session_step(+Session0, -Session, -CycleReport)
lps_session_run(+Session0, +StopCond, -Session, -Trace)
lps_session_state(+Session, -Fluents)
lps_session_fork(+Session, -Session2)
```

The HTTP endpoint is one POST dispatching on an `operation` field, and the IDE
is a client of it, so anything the IDE does can be done with `curl`.

## Four front ends, one internal form

LPS surface syntax, Logical English, PDDL and Drools all arrive at the same
internal representation and are run by the same engine. **PDDL**
(`src/syntax/lps_pddl.pl`) maps preconditions to denials, effects to causal laws
and the problem's goal to `achieve`; **Drools** (`src/syntax/lps_drools.pl`) maps
DRL rules to reactive rules and `modify(){}` to `updated/4`, and reports salience
and Java leaves as diagnostics rather than guessing. Each has its own oracle,
written before its transpiler: `./lps pddl domain.pddl problem.pddl` prints a plan
and validates it independently.

The second *surface* syntax is **Logical English**, and it lives on the other side of a
contract rather than inside this engine. LE2 parses a `.le` document and emits
LPS internal syntax — Prolog text plus a provenance list, one `src(File, Line,
Col, Kind)` per term. LPS2 reads the terms and runs them. LE2 knows nothing
about the cycle; LPS2 knows nothing about templates or head-noun typing. The
whole agreement is [`docs/le_lps_interface.md`](docs/le_lps_interface.md).

```sh
LPS_LE2_DIR=/path/to/LogicalEnglish2 ./lps run foo.le    # or LPS_LE2_URL=…/leapi
```

Provenance is the part that earns its keep: an engine diagnostic lands on the
line and column of the *English sentence* that caused it, not on generated text
the author never sees. It is also why Part IV of the plan is front ends rather
than forks — a PDDL domain or a Drools rule base reaches the engine through
exactly the same door, and gets explanations pointing back at its own source.

The language itself is written up in
[`docs/le_lps_surface.md`](docs/le_lps_surface.md). Reactive rules, causal laws,
integrity constraints, `achieve`, timed observations and even the prospective
form all render; §7 there states what is deliberately left out, because §I.9.6 of
the plan asks for a stated subset rather than a claim of totality.

## Explaining what happened

The engine records a derivation forest unconditionally: which rule instance
created a goal, which composite events a committed action came through, every
state change tagged with the *causal law* responsible, denials that blocked an
action, prospective constraints that rejected a state, planner exhaustion.

```
$ ./lps explain legacy_lps1/examples/goat.pl --ask "why(happened(row(south,north)), 2)"
[happened]
row(south,north) occurred from cycle 1 to 2 — committed while resolving goals in the previous cycle
  while resolving the composite event makeLoc(farmer,south) — from 1 to 1
  while resolving the composite event makeLoc(goat,north) — from 1 to 2
  from the goal created by a reactive rule (goal 2) — consequent [happens(makeLoc(goat,north),A,B)]
    rule at src(legacy_lps1/examples/goat.pl,10,0,internal) — if [holds(loc(_,south),_),_\=farmer] then ...
```

Explanations are *readings of the trace*. Nothing is re-run and nothing is
re-derived to answer a question, and where the engine recorded nothing the
answer says so rather than reconstructing something plausible — which is the
whole value, since this gets consulted after an incident.

See [`docs/ide.md`](docs/ide.md) for the question forms and the visual mapping.

## Planning is not a dialect

`examples/goat_declarative.pl` states the wolf/goat/cabbage puzzle instead of
solving it. Every line but the last is existing LPS syntax, most of it verbatim
from a corpus program; what has gone is the recursive decomposition telling the
engine *how* to ferry an object across.

```prolog
:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

One new construct and *no* new semantics for `false`: the planner consumes the
denials the reactive engine already consumes. It produces a list of action sets
and the **ordinary cycle executes them**, one per cycle, with the normal
precondition and integrity checks — so a planned program's trace is an ordinary
LPS trace and can be tested by exactly the same contract.

Note that this is not STRIPS: LPS cycles commit several actions at once, so the
search branches over *subsets*.

Two searches, and `search(auto)` picks: node-budgeted breadth-first while the
branching factor is small enough to be exhaustive, greedy best-first under a
delete-relaxation heuristic when it is not. `examples/blocks.lps` — seven blocks
in one tower, rebuilt in reverse — is the example that separates them: 0.4 s
greedy, 25.5 s breadth-first, and the gap is exponential in the number of blocks.

## Running the gates

```sh
./myswipl.sh -q -g "consult('tools/lint_core.pl')"    -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')" -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')" -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main"       -t halt

# the full corpus, ~40 min single-job; --engine legacy | lps2 | cross
./myswipl.sh -q -g "consult('conformance/runner.pl')" \
  -g "runner:main(['--engine','lps2','--variants',none,'--extended'])" -t halt
```

Requires SWI-Prolog (developed against 10.1.12; the corpus was first classified
on 10.0.0). Building the IDE needs Node; the browser tests and the documentation
screenshots additionally need Playwright with Chromium.

The known gaps are listed with the rest of the status, in
[the plan](docs/LPSplusLLM.md#known-gaps).

## Deploying it

A two-stage container: Node builds the IDE, and one SWI-Prolog process serves the
engine, `/lpsapi` and the built IDE on one port. There is no Node in the runtime
image.

```sh
docker build -t lps2 . && docker run -p 3060:3060 lps2
```

Building the IDE outside the container, once:

```sh
cd ui && npm install && npm run build      # → src/ide/dist/
```

See [`docs/deploy.md`](docs/deploy.md) for fly.io, the `LPS_TOKEN` requirement in
a public deployment, and how to run it alongside LogicalEnglish2.

## Licensing

`legacy_lps1/` is a read-only clone of the LPS1 repository, copyright Imperial
College London under 3-clause BSD. **Never write inside it** — running the old
engine on a file writes next to that file, so both engine adapters copy programs
into `build/` first.

A licence for LPS2's own code has not been chosen yet.

## The documents

Written by hand, and meant to be read:

| | |
|---|---|
| [`docs/LPSplusLLM.md`](docs/LPSplusLLM.md) | **the plan of record**, and the one place status lives. Part 0 what the old system turned out to be, Part I the engine, Part II the agent, Part III deployment surfaces, Part IV other agent languages as front ends, Part V industrial control as a back end |
| [`docs/IntroducingLPS2.md`](docs/IntroducingLPS2.md) | **the tour**: what it is, what is new relative to LPS1, and every surface — with screenshots taken from the running system |
| [`docs/lps_tutorial.md`](docs/lps_tutorial.md) | **the teaching path**, from a two-line program to live sessions |
| [`docs/UsingTheIDE.md`](docs/UsingTheIDE.md) | **the environment**: every part of the IDE, and a "how do I…" section |
| [`docs/LPS2abstract.md`](docs/LPS2abstract.md) | **two pages**, one screenshot, for deciding whether to read the rest |
| [`docs/ProfessorKsystemImpressions.md`](docs/ProfessorKsystemImpressions.md) | a teacher's wish list after a first pass through the IDE — UI work not yet done |
| [`docs/lps_summary.md`](docs/lps_summary.md) | **the language reference**: every construct, the operator table, the `display/2` properties. Inlined by the assistant |
| [`docs/selection_spec.md`](docs/selection_spec.md) | the twenty selection rules SP1–SP20, and what implementing them taught |
| [`docs/le_lps_design.md`](docs/le_lps_design.md) | M8 design: what LE2 emits, the file extensions, the editor strategy |
| [`docs/le_lps_interface.md`](docs/le_lps_interface.md) | the LE2 ↔ LPS2 contract — duplicated verbatim in both repositories |
| [`docs/le_lps_surface.md`](docs/le_lps_surface.md) | Logical English for LPS: the surface language, construct by construct |
| [`docs/ide.md`](docs/ide.md) | the IDE: the panes, the question forms, and what `display/2` supports against the old paper.js renderer |
| [`docs/deploy.md`](docs/deploy.md) | the container, fly.io, and running alongside LogicalEnglish2 |
| [`CLAUDE.md`](CLAUDE.md) | working notes: the hard rules, how to run things, where the artefacts land |

Generated, and never hand-edited:

| | |
|---|---|
| [`docs/conformance_lps2.md`](docs/conformance_lps2.md) | the corpus under LPS2 — the M4 numbers |
| [`docs/conformance_report.md`](docs/conformance_report.md) | the same corpus under the *old* engine, from M0 |
