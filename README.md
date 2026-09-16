# LPS2

A new implementation of the [LPS](https://lps.doc.ic.ac.uk/) engine in
SWI-Prolog, with the tools needed to write and run LPS programs.

LPS — Logic Production System, of Kowalski and Sadri — is a language for
programs that act over time. A program says what holds when, what happens
between when and when, and what must and must not be the case. This
implementation is built around a small engine with no dependence on the outside
world, and it is checked against the earlier implementation's own test
recordings, run for run.

```sh
./lps run examples/start/goat_declarative.pl     # solve the wolf, goat and cabbage puzzle
./lps ide                                  # the start page and the editor, on port 3060
```

**New here?** [`docs/LPS2abstract.md`](docs/LPS2abstract.md) is two pages.
[`docs/lps_tutorial.md`](docs/lps_tutorial.md) teaches the language.
[`docs/glossary.md`](docs/glossary.md) defines the terms used in all of these
documents. [`docs/UsingTheIDE.md`](docs/UsingTheIDE.md) describes the editor,
and [`docs/lps_summary.md`](docs/lps_summary.md) is the language reference.

**Where the project stands** — which pieces are built, what is known to be
missing, and what might be done next — is recorded in **one** place, [the plan's
Status section](docs/LPSplusLLM.md#status). This file does not repeat it. All
the numbered milestones, M0 to M19, are done.

The plan of record is [`docs/LPSplusLLM.md`](docs/LPSplusLLM.md). It sets out
the work in five parts. Part I is the engine. Part II is what the engine is
eventually *for*: an agent in which the logical half enforces what must and must
not happen, while a language model supplies perception, suggestions and English.
Parts IV and V use the same interface in both directions — other agent languages
compiled *into* LPS, and industrial control code generated *out* of it.

## The hard part, and how it shaped everything else

The earlier implementation — called **LPS1** throughout these documents — comes
with 108 recorded runs. Each records, cycle by cycle, what its program did.

The difficulty is that a recording captures **the choice LPS1 happened to make**
wherever more than one was available. Reproducing them is therefore a demand for
*the same behaviour*, not merely for *correct* behaviour: the same actions, in
the same cycles, described by the same terms, differing at most in the names of
variables. The order in which clauses appear is the order in which they are
tried. The discipline of the goal queue can be observed from outside. A
precondition violated at the end of a cycle can send the engine back into the
handling of events at its start.

**99 of the 108 recordings come back exactly, and there is no case where the two
engines differ for a reason nobody knows.** The other nine recordings are out of
date: each was made before LPS1's own behaviour last changed, so LPS1 no longer
reproduces them either. Six were recorded in 2019, before LPS1 began recording an
extra kind of composite event; three date from 2017, one of them for a program
that now declares a shorter `maxTime` than its own recording covers. Each of the
nine is documented individually, with the evidence, in
`conformance/adjudicated.pl`.

For those nine there is a better comparison than the recording. `--engine cross`
runs both engines on the same program and compares them with each other. **On
all nine, the two engines agree.**

Because of all this, the first thing written was not code but
[`docs/selection_spec.md`](docs/selection_spec.md): twenty numbered rules saying
where the engine has a choice and which way it goes. LPS1 never wrote them down,
and without them "reimplement LPS" does not say enough to be carried out.

Rules SP1 to SP15 were found by reading LPS1. SP16 to SP20 were found only by
building LPS2 and watching where it diverged. Nobody could have found them by
reading, because they are facts about the Prolog environment the engine runs in
rather than about the algorithm it implements. The one that carries the most
weight:

> **SP16.** "External predicate" means *visible in the program's Prolog module*,
> and that includes Prolog's own built-ins. The engine inserts `holds(true, T)`
> into the bodies of composite events as a way of leaving the end time open, and
> that resolves only because `true/0` is thereby an external fluent that can
> simply be called. Restrict the meaning to the user's own clauses and every
> composite event with an implicit end time stops working.

## How the source is arranged

```
src/core/      the engine. No input or output, no threads, no clock, no C
src/syntax/    between the written forms and the internal form: LPS, PDDL, Drools
src/edges/     everything that touches the world: files, CLI, HTTP, LE, LLM, WASM
ui/            the editor's sources; esbuild builds them into src/ide/dist/
src/ide/dist/  the built editor, served by the HTTP endpoint (generated)
examples/      LPS2's own examples: planning, live, PDDL, Drools, agent,
               Minecraft, and twelve programs from Kowalski's book
conformance/   the test harness: the runner, both engine adapters, the nine
               documented out-of-date recordings
tools/         checks, benchmarks, browser tests, screenshot generation
docs/          the plan, the specifications, the generated reports — see below
legacy_lps1/   a read-only copy of LPS1: the reference engine and its examples
```

That is about 10,400 lines in `src/`, against LPS1's 5,000 or so. The difference
is partly that the concerns are actually kept apart, and partly that a good deal
of it is commentary explaining why a rule is the way it is.

The Logical English front end lives in a separate repository,
**LogicalEnglish2**: `le_lps.pl`, `le_lps_write.pl`, the grammar and the
dictionary. The agreement between the two projects is written down in
[`docs/le_lps_interface.md`](docs/le_lps_interface.md), which is kept identical
in both. LE2 also offers `le_service.pl`, which LPS2 loads into its own process,
so with `LPS_LE2_LIB=/path/to/LogicalEnglish2` you can write and run Logical
English in this editor with no second server. LE2 is optional: without it, `.le`
files are the only thing that stops working.

## The two decisions that shaped the design

**A session is a value.** Everything that changes — the state, the goal queue,
the surviving rule instances, the cycle number, the queue of events, the record
of the run — lives in a single Prolog term that the caller holds. Printing one,
comparing two, saving one and copying one are then all the same kind of
operation. That made hypothetical reasoning nearly free: `lps_session_fork/2` is
a unification, measured at about 5 microseconds however large the session is.
The two-part state store the plan had anticipated turned out not to be needed.

**Time is supplied to the engine, never read by it.** LPS1 asks the operating
system for the time inside its cycle, which makes a run unrepeatable on
different hardware. It also wraps three phases of the cycle in a 0.75-second
cutoff that *throws away* that phase's work when it expires. That is why one of
LPS1's own tests finished anywhere between 0 and 10 of its 10 cycles across six
runs of the same sweep.

LPS2 works out the time from the cycle number instead. The expectation was that
this would cost the seventeen programs that depend on wall-clock time their
recordings. It cost none of them, because every one of those programs also
declares how many simulated seconds a cycle stands for. Their clocks were
already predictable, and `maxRealTime` was already bounding simulated seconds
rather than real ones.

## Using it

```sh
./lps run PROGRAM [--cycles N] [--trace FILE] [--observe "e1,e2@3"] [--json]
./lps step PROGRAM --cycles 3          # one report per cycle
./lps repl PROGRAM                     # step, inspect, copy, discard
./lps dump PROGRAM                     # the internal form
./lps explain PROGRAM --ask "why_not(happened(a), 4)"
./lps timeline PROGRAM
./lps changes PROGRAM --at 2
./lps automaton PROGRAM                # the run as a state-transition diagram
./lps ide [--port N]
./lps test --engine lps2 --only goat   # the test harness
```

The written form (`.pl`, `.lps`), Logical English (`.le`, compiled by LE2) and
the internal form (`_.P`, `.lpsw`) are all read, and which is which is taken from
the extension.

Everything above is a thin layer over seven predicates:

```prolog
lps_compile(+Source, +Syntax, +Options, -Program, -Diagnostics)
lps_session_new(+Program, +Options, -Session)
lps_session_observe(+Session0, +Events, -Session)
lps_session_step(+Session0, -Session, -CycleReport)
lps_session_run(+Session0, +StopCond, -Session, -Trace)
lps_session_state(+Session, -Fluents)
lps_session_fork(+Session, -Session2)
```

The web interface is a single POST that chooses what to do from an `operation`
field, and the editor is a client of it. Anything the editor does can be done
with `curl`.

## Four ways in, one internal form

The LPS written form, Logical English, PDDL and Drools all arrive at the same
internal form and are run by the same engine.

**PDDL** (`src/syntax/lps_pddl.pl`) turns preconditions into constraints,
effects into causal laws, and the problem's goal into `achieve`.

**Drools** (`src/syntax/lps_drools.pl`) turns its rules into reactive rules,
and reads the working memory as the world it describes: a fact is a state
(`fire(Room)`, a boolean field a state of its own: `sprinkler_on(Room)`), and
an insert, delete or modify is an event in the world (`fire_starts`,
`alarm_goes_on`, `sprinkler_turns_on`) with its causal law, worded by a
`<name>.wording` file beside the DRL if there is one. Rule priorities
(`salience`) and conditions written in Java have no LPS equivalent, and are
reported rather than translated by guesswork.

Each has a checker written independently, and before, the translator:
`./lps pddl domain.pddl problem.pddl` prints a plan and then validates it by a
separate route.

**Logical English** is the second way of *writing* a program, and it lives on the
other side of an agreement rather than inside this engine. LE2 parses a `.le`
document and produces the LPS internal form: Prolog text, plus a list saying
where each term came from — one `src(File, Line, Col, Kind)` per term. LPS2
reads the terms and runs them. LE2 knows nothing about the cycle; LPS2 knows
nothing about templates or about how LE2 types its nouns. The whole agreement is
[`docs/le_lps_interface.md`](docs/le_lps_interface.md).

```sh
LPS_LE2_DIR=/path/to/LogicalEnglish2 ./lps run foo.le    # or LPS_LE2_URL=…/leapi
```

Recording where each term came from is what earns its keep here. An error found
by the engine is reported at the line and column of the *English sentence* that
caused it, and not against generated text the author never sees. It is also why
Part IV of the plan is about front ends rather than about separate versions of
the engine: a PDDL domain or a set of Drools rules comes in through the same
door, and gets explanations that point back at its own source.

The language itself is written up in
[`docs/le_lps_surface.md`](docs/le_lps_surface.md). Reactive rules, causal laws,
constraints, `achieve`, timed observations and constraints about what an action
would bring about can all be written in it. Section 7 there says what is
deliberately left out.

## Explaining what happened

Every run records how the engine reached each conclusion, whether or not anyone
is going to ask: which rule created which goal, which composite events a
committed action came through, every state change tagged with the causal law
responsible, every constraint that blocked an action, every state a
look-ahead constraint rejected, and every point at which the planner ran out of
options.

```
$ ./lps explain legacy_lps1/examples/goat.pl --ask "why(happened(row(south,north)), 2)"
[happened]
row(south,north) occurred from cycle 1 to 2 — committed while resolving goals in the previous cycle
  while resolving the composite event makeLoc(farmer,south) — from 1 to 1
  while resolving the composite event makeLoc(goat,north) — from 1 to 2
  from the goal created by a reactive rule (goal 2) — consequent [happens(makeLoc(goat,north),A,B)]
    rule at src(legacy_lps1/examples/goat.pl,10,0,internal) — if [holds(loc(_,south),_),_\=farmer] then ...
```

An explanation is a *reading of the record*. Nothing is re-run and nothing is
worked out afresh in order to answer a question, and where the engine recorded
nothing, the answer says so rather than assembling a plausible story. That
restraint is the whole value of the feature, because it is consulted after
something has gone wrong.

See [`docs/ide.md`](docs/ide.md) for the forms of question and for how a program
says it should be drawn.

## Planning is not a separate dialect

`examples/start/goat_declarative.pl` states the wolf, goat and cabbage puzzle instead
of solving it. Every line but the last is existing LPS syntax, most of it copied
word for word from one of LPS1's examples. What has gone is the recursive
decomposition that told the engine *how* to ferry an object across.

```prolog
:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

One new construct, and `false` means exactly what it meant before: the planner
uses the same constraints the engine already uses. What it produces is a list of
sets of actions, and **the ordinary cycle carries them out**, one set per cycle,
with the ordinary checks on preconditions and constraints. The record of a
planned run is therefore an ordinary LPS record, and can be tested in exactly
the same way as any other.

Note that this is not STRIPS. An LPS cycle commits several actions at once, so
the search branches over *subsets* of the available actions.

There are two searches, and `search(auto)` chooses. It starts with breadth-first
search, which finds the shortest plan, and gives it a fixed budget of states to
visit. If the budget runs out it switches to greedy best-first search, which
scores a state by solving a version of the problem in which no action ever
undoes anything.

`examples/start/blocks.lps` — seven blocks in one tower, rebuilt in reverse order — is
the example that separates them: 0.4 seconds for the greedy search against 25.5
seconds for the breadth-first one, and the gap grows exponentially with the
number of blocks.

## Running the checks

```sh
./myswipl.sh -q -g "consult('tools/lint_core.pl')"    -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')" -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')" -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main"       -t halt

# all 108 recordings; about 40 minutes with one job at a time.
# --engine takes legacy, lps2 or cross
./myswipl.sh -q -g "consult('conformance/runner.pl')" \
  -g "runner:main(['--engine','lps2','--variants',none,'--extended'])" -t halt
```

SWI-Prolog is required; this was developed against 10.1.12, and LPS1's examples
were first classified on 10.0.0. Building the editor needs Node. The browser
tests and the screenshots in the documents additionally need Playwright with
Chromium.

What is known to be missing is listed with the rest of the status, in
[the plan](docs/LPSplusLLM.md#known-gaps).

## Deploying it

The container image is built in two stages. Node builds the editor, and then one
SWI-Prolog process serves the engine, the web interface and the built editor on
one port. There is no Node in the image that runs.

```sh
docker build -t lps2 . && docker run -p 3060:3060 lps2
```

To build the editor outside the container, once:

```sh
cd ui && npm install && npm run build      # produces src/ide/dist/
```

See [`docs/deploy.md`](docs/deploy.md) for fly.io, for why a public deployment
must set `LPS_TOKEN`, and for how to run this alongside LogicalEnglish2.

## Licensing

`legacy_lps1/` is a read-only copy of the LPS1 repository, copyright Imperial
College London, under the 3-clause BSD licence. **Never write inside it.**
Running the old engine on a file writes new files next to that file, so both
engine adapters copy programs into `build/` before running them.

A licence for LPS2's own code has not been chosen yet.

## The documents

Written by hand, and meant to be read:

| | |
|---|---|
| [`docs/LPSplusLLM.md`](docs/LPSplusLLM.md) | **the plan of record**, and the one place the project's status lives. Part 0 is what LPS1 turned out to be; Part I the engine; Part II the agent; Part III ways of deploying it; Part IV other agent languages as front ends; Part V industrial control as a back end |
| [`docs/LPS2abstract.md`](docs/LPS2abstract.md) | **two pages** and one picture, for deciding whether to read the rest |
| [`docs/lps_tutorial.md`](docs/lps_tutorial.md) | **how to write LPS programs**, from a two-line one to sessions that do not stop |
| [`docs/glossary.md`](docs/glossary.md) | **every term** used in these documents, defined |
| [`docs/UsingTheIDE.md`](docs/UsingTheIDE.md) | **the environment**: every part of the editor, and a "how do I…" section |
| [`docs/IntroducingLPS2.md`](docs/IntroducingLPS2.md) | **the longer tour**: what it is, what is new since LPS1, and every way in — illustrated from the running system |
| [`docs/lps_summary.md`](docs/lps_summary.md) | **the language reference**: every construct, the operator table, the drawing properties |
| [`docs/ProfessorKsystemImpressions.md`](docs/ProfessorKsystemImpressions.md) | a teacher's wish list after a first pass through the editor — since implemented |
| [`docs/ProfessorKsecondPass.md`](docs/ProfessorKsecondPass.md) | two comments on the documents and the interface, and what was done about them |
| [`docs/selection_spec.md`](docs/selection_spec.md) | the twenty rules SP1–SP20 saying where the engine has a choice, and what implementing them taught |
| [`docs/le_lps_design.md`](docs/le_lps_design.md) | the design of the Logical English work: what LE2 produces, the file extensions, the plan for the editors |
| [`docs/le_lps_interface.md`](docs/le_lps_interface.md) | the agreement between LE2 and LPS2 — kept identical in both repositories |
| [`docs/le_lps_surface.md`](docs/le_lps_surface.md) | Logical English for LPS, construct by construct |
| [`docs/InformPlan.md`](docs/InformPlan.md) | interactive fiction: what Inform 7 is, why LPS should be an IF engine rather than compile to or from it, and the four phases that built one — with what each found |
| [`docs/LPSForInformUsers.md`](docs/LPSForInformUsers.md) | **for Inform authors**: what maps onto what, where the stories are, Inform's IQ Test and Alice worked through with pictures, where the two systems differ in capability, current limitations |
| [`docs/introducingIFonLPSscript.md`](docs/introducingIFonLPSscript.md) | **the five-minute demo**'s plan and narration: the principles, Alice and the IQ Test played in the IDE with the panes, the model guessing a command. `tools/if_demo.cjs` produces the video (`introducingIFonLPS.mp4`, not kept in the repository: it needs an ElevenLabs key to narrate) |
| [`docs/ide.md`](docs/ide.md) | the editor: the panes, the forms of question, and what `display/2` supports compared with LPS1's renderer |
| [`docs/deploy.md`](docs/deploy.md) | the container, fly.io, and running alongside LogicalEnglish2 |
| [`docs/telemetry.md`](docs/telemetry.md) | error reports (Sentry, with a feedback form) and web analytics (Cloudflare): off unless configured, and configured only on the deployed server; how to set up both and the fly secrets |
| [`CLAUDE.md`](CLAUDE.md) | working notes: the rules that must not be broken, how to run things, where the output lands |

Generated, and never edited by hand:

| | |
|---|---|
| [`docs/conformance_lps2.md`](docs/conformance_lps2.md) | LPS1's recordings, under LPS2 |
| [`docs/conformance_report.md`](docs/conformance_report.md) | the same recordings, under LPS1 itself |
