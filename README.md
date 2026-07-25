# LPS(2)

A reimplementation of the [LPS](https://lps.doc.ic.ac.uk/) engine in SWI-Prolog:
Kowalski and Sadri's logic-and-imperative language, rebuilt around a pure core
with a small session API, and held to the old engine's own test corpus
trace-for-trace.

The plan of record is **[`docs/LPSplusLLM.md`](docs/LPSplusLLM.md)**. It defines
milestones M0–M11 and, in Part II, what the engine is eventually *for*: an agent
in which the symbolic half enforces what must and must not happen while an LLM
supplies perception, candidate generation and English.

```sh
./lps run examples/goat_declarative.pl     # solve the wolf/goat/cabbage puzzle
./lps ide                                  # the web IDE on :3060
```

## Where it stands

M0–M7, M9 and M10 are done. **M8 (Logical English syntax) is deliberately
postponed** — it needs articulation with the Logical English project rather than
guessing at it.

| | | evidence |
|---|---|---|
| **Conformance** | 99 of 108 golden traces reproduced exactly; **0 unexplained failures** | [`docs/conformance_lps2.md`](docs/conformance_lps2.md) |
| **Surface syntax** | 90 of 91 corpus programs translate *identically* to the old translator's output | `tools/m2_roundtrip.pl` |
| **Explanations** | all five §I.10.5 question forms, all four `why_not` cases | `tools/explain_test.pl` |
| **Core purity** | no threads, sockets, HTTP, clock, foreign code or file I/O in `src/core/` | `tools/lint_core.pl` |
| **Planning** | the declarative goat solves, in the classic seven crossings | `tools/examples_test.pl` |
| **Speed / memory** | median ≈0.6× the old engine's wall time, ≈0.5× its memory | `tools/compare_engines.pl` |
| **IDE** | four panes driven and photographed in Chromium | `tools/ide_screenshots.cjs` |

The nine entries that do not reproduce their goldens are all **stale goldens**,
each with a written justification and cross-engine evidence in
`conformance/adjudicated.pl` — six recorded in 2019 before the old engine
started recording an extra kind of composite event, and three from 2017,
including one whose program now declares a shorter `maxTime` than its trace
covers. `--engine cross` runs both engines and compares their traces with each other
rather than with the golden — the only comparison that means anything once a
golden is older than the behaviour it recorded.

## The hard part, and why it shaped everything

A `.lpst` golden file records **the choice the 2021 engine happened to make**
wherever several were possible. Passing the corpus is therefore *trace
equivalence, not semantic equivalence*: the same actions, in the same cycles, in
terms identical up to variable renaming. Clause order is selection order; the
goal queue's discipline is observable; a precondition violated at the end of a
cycle can backtrack into event injection at its start.

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
src/syntax/    external syntax ↔ the internal representation
src/edges/     everything that touches the world: files, CLI, HTTP
src/ide/       the web IDE, served by the HTTP endpoint
examples/      LPS(2)'s own examples, with goldens
conformance/   the harness: .lpst runner, both engine adapters, adjudications
tools/         lint, gates, benchmarks, browser tests
legacy_lps1/   READ-ONLY clone of LPS(1) — the reference engine and its corpus
```

Roughly 6,300 lines in `src/`, against the old engine's ~5,000 — with the
concerns actually separated, and a good deal of that being the commentary that
explains *why* a rule is the way it is.

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
across six runs of the same sweep. LPS(2) computes real time from cycle time. The
expectation was that this would cost the eleven wall-clock-bound programs their
goldens; it cost none, because every one of them also declared a simulated
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
./lps ide [--port N]
./lps test --engine lps2 --only goat   # the conformance harness
```

Surface syntax (`.pl`, `.lps`) and the internal form (`_.P`) are both read,
guessed from the extension. Everything above is a thin layer over seven core
predicates:

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
on 10.0.0). The browser test additionally needs Playwright with Chromium.

## Known gaps

- **M8, Logical English syntax** — postponed pending the LE project.
- **`dumplps/0`, the internal→surface direction.** `./lps dump` produces the
  internal form; `--syntax legacy` reports that it is not implemented rather
  than approximating it, because §I.9.5 makes that round trip a *test* and a
  half-working reverse translator would claim agreement it had not earned.
- **The IDE is not the LE2 Monaco editor.** That repository is not available
  here. The server side is already LSP-shaped — diagnostics carry source
  positions, analysis is a debounced round trip — so swapping the `<textarea>`
  for Monaco is a front-end change, not a protocol one.
- **`.lpsw` and lps.js syntaxes** are dropped. The corpus's `.lpsw` entries are
  internal-syntax tests and run through the internal reader.
- **Two programs are slower than the old engine** (1.3× and 2.6×), both
  query-bound rather than resolution-bound. Two suspects are named in the
  benchmark's commit message; neither is fixed, because both want their own
  conformance sweep rather than a benchmark-driven edit.

## Licensing

`legacy_lps1/` is a read-only clone of the LPS(1) repository, copyright Imperial
College London under 3-clause BSD. **Never write inside it** — running the old
engine on a file writes next to that file, so both engine adapters copy programs
into `build/` first.

A licence for LPS(2)'s own code has not been chosen yet.

## Further reading

- [`docs/LPSplusLLM.md`](docs/LPSplusLLM.md) — the plan: the engine, the agent, the deployment surfaces
- [`docs/selection_spec.md`](docs/selection_spec.md) — the twenty selection rules, and what implementing them taught
- [`docs/conformance_lps2.md`](docs/conformance_lps2.md) — the current corpus results (generated)
- [`docs/conformance_report.md`](docs/conformance_report.md) — the same corpus under the *old* engine, from M0
- [`docs/ide.md`](docs/ide.md) — the IDE, the question forms, the visual mapping
- [`CLAUDE.md`](CLAUDE.md) — working notes: hard rules, how to run things, where the artefacts land
