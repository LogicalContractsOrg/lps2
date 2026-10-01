# The history of LPS2

[`README.md`](README.md) describes what LPS2 does today. This document tells
where LPS2 came from, what was hardest about building it, and the decisions
that shaped it.

## LPS1, the earlier implementation

LPS, the Logic Production System, was designed by Robert Kowalski and Fariba
Sadri at Imperial College London ([lps.doc.ic.ac.uk](https://lps.doc.ic.ac.uk/)).
The earlier implementation of LPS, called **LPS1** throughout these documents,
was also written in SWI-Prolog, and ran in SWISH, the web notebook of
SWI-Prolog. A read-only copy of LPS1 is kept in `legacy_lps1/`, with its own
README.

LPS2 is a new implementation, not a revision of LPS1. LPS2 is built around a
small engine that has no dependence on the outside world: no input or output,
no threads and no clock. Around that engine, LPS2 adds the tools that LPS1 did
not have: the editor with its timeline and scenes, explanations, planning, the
other ways of writing a program, and the connection to language models.

The engine is about 20,500 lines in `src/`, against LPS1's 5,000 or so. The
difference is partly that the concerns are kept apart, and partly that much of
the code is commentary explaining why a rule is the way it is. It was written by Claude Code supervised by Miguel Calejo.

## The hard part: behaving exactly like LPS1

LPS1 comes with 108 recorded runs. Each recording says, cycle by cycle, what its
program did.

A recording captures **the choice LPS1 happened to make** wherever more than
one choice was available. Reproducing the recordings therefore demands *the
same behaviour*, not merely *correct* behaviour: the same actions, in the same
cycles, described by the same terms, differing at most in the names of
variables. The order in which the rules of a program are written is the order
in which they are tried. The order in which goals are taken from the queue can
be observed from outside. A precondition broken at the end of a cycle can send
the engine back to the handling of events at the start of that cycle.

**99 of the 108 recordings come back exactly, and there is no case where the two
engines differ for a reason nobody knows.** The other nine recordings are out of
date: each was made before LPS1's own behaviour last changed, so LPS1 no longer
reproduces them either. Six were recorded in 2019, before LPS1 began recording
an extra kind of composite event. Three date from 2017, and one of those three
is for a program that now declares a shorter `maxTime` than its own recording
covers. Each of the nine is documented, with the evidence, in
`conformance/adjudicated.pl`.

For those nine there is a better comparison than the recording. `--engine cross`
runs both engines on the same program and compares the two runs. **On all nine,
the two engines agree.**

## Writing down the choices first

Because of all this, the first thing written was not code but
[`docs/dev/semantics/selection-spec.md`](docs/dev/semantics/selection-spec.md):
twenty numbered rules saying where the engine has a choice and which way it
goes. LPS1 never wrote these rules down, and without them "reimplement LPS"
does not say enough to be carried out.

Rules SP1 to SP15 were found by reading LPS1. Rules SP16 to SP20 were found only
by building LPS2 and watching where it diverged. Nobody could have found them
by reading, because they are facts about the Prolog environment the engine runs
in, rather than about the method the engine follows. The rule that carries the
most weight:

> **SP16.** "External predicate" means *visible in the program's Prolog module*,
> and that includes Prolog's own built-ins. The engine inserts `holds(true, T)`
> into the bodies of composite events as a way of leaving the end time open, and
> that resolves only because `true/0` is thereby an external fluent that can
> simply be called. Restrict the meaning to the user's own clauses and every
> composite event with an implicit end time stops working.

## The two decisions that shaped the design

**A session is a value.** Everything that changes — the state, the goal queue,
the surviving rule instances, the cycle number, the queue of events, the record
of the run — lives in a single Prolog term that the caller holds. Printing a
session, comparing two, saving one and copying one are then all the same kind
of operation. That made reasoning about "what if" nearly free:
`lps_session_fork/2`, which copies a session, takes about 5 microseconds however
large the session is. The two-part store for the state that the plan had
expected turned out not to be needed.

**Time is supplied to the engine, never read by it.** LPS1 asks the operating
system for the time inside its cycle, which makes a run unrepeatable on
different hardware. LPS1 also gives three phases of the cycle a 0.75-second
limit, and *throws away* the work of a phase when its limit expires. That is
why one of LPS1's own tests finished anywhere between 0 and 10 of its 10 cycles
across six runs of the same test.

LPS2 works out the time from the cycle number instead. The expectation was that
this would cost the recordings of the seventeen programs that depend on the
clock. It cost none of them, because every one of those programs also declares
how many simulated seconds a cycle stands for. Their clocks were already
predictable, and `maxRealTime` was already limiting simulated seconds rather
than real ones.

## Planning without a separate dialect

`examples/start/goat_declarative.pl` states the wolf, goat and cabbage puzzle
instead of solving it. Every line but the last is existing LPS syntax, most of
it copied word for word from one of LPS1's examples. What has gone is the step
by step recipe that told LPS1 *how* to ferry each object across. The one new
construct is `achieve`, and `false` means exactly what it meant before.

This is not STRIPS, the classic way of describing planning problems. An LPS
cycle carries out several actions at once, so the search considers *sets* of
actions at each step.

There are two searches, and `search(auto)` chooses between them. It starts with
breadth-first search, which finds the shortest plan, and gives that search a
fixed number of states to visit. If the number runs out, it switches to greedy
best-first search, which scores a state by solving an easier version of the
problem in which no action ever undoes anything. `examples/start/blocks.lps`,
seven blocks in one tower rebuilt in reverse order, shows the difference: 0.4
seconds for the greedy search against 25.5 seconds for the breadth-first one,
and the gap grows very quickly with the number of blocks.

## Logical English as a partner, not a part

Logical English lives in a separate repository, LogicalEnglish2 (LE2). LE2
reads a `.le` document and produces the LPS internal form, plus a list saying
where each term came from. LPS2 reads the terms and runs them. LE2 knows nothing
about the cycle, and LPS2 knows nothing about templates. The whole agreement is
[`docs/dev/le-lps-interface.md`](docs/dev/le-lps-interface.md).

Recording where each term came from is what lets an error found by the engine
be reported against the English sentence that caused it. It is also why other
languages became front ends rather than separate versions of the engine: a PDDL
domain or a set of Drools rules comes in through the same door, and gets
explanations that point back at its own source.

## The plan of record

The work was planned in [`docs/project/plan-of-record.md`](docs/project/plan-of-record.md),
which is also the one place where the project's status is kept. The plan has
five parts:

- **Part I**, the engine.
- **Part II**, what the engine is for in the end: an agent in which the logical
  half enforces what must and must not happen, while a language model supplies
  perception, suggestions and English.
- **Part III**, ways of deploying the engine.
- **Part IV**, other agent languages compiled *into* LPS, as front ends.
- **Part V**, industrial control code generated *out of* LPS, as a back end.

All the numbered milestones, M0 to M19, are done.

## The project's documents

These documents, in `docs/project/` and `docs/dev/`, record how LPS2 came to be:

| | |
|---|---|
| [`plan-of-record.md`](docs/project/plan-of-record.md) | **the plan of record**, and its Status section. Part 0 is what LPS1 turned out to be |
| [`plans/le_lps_design.md`](docs/project/plans/le_lps_design.md) | the design of the Logical English work: what LE2 produces, the file extensions, the plan for the editors |
| [`plans/InformPlan.md`](docs/project/plans/InformPlan.md) | interactive fiction: why LPS should be a game engine rather than compile to or from Inform 7, and the four phases that built one |
| [`reviews/ProfessorKsystemImpressions.md`](docs/project/reviews/ProfessorKsystemImpressions.md) | a teacher's wish list after a first pass through the editor — since carried out |
| [`reviews/ProfessorKsecondPass.md`](docs/project/reviews/ProfessorKsecondPass.md) | two comments on the documents and the editor, and what was done about them |
| [`videos/introducingIFonLPSscript.md`](docs/project/videos/introducingIFonLPSscript.md) | the plan and narration of the five-minute demonstration video, produced by `tools/if_demo.cjs` |
| [`semantics/selection-spec.md`](docs/dev/semantics/selection-spec.md) | the twenty rules SP1–SP20, and what implementing them taught |
| [`ide-design.md`](docs/dev/ide-design.md) | the editor's design record, as of 2026-08-20, compared with LPS1's drawings shape by shape |
| [`conformance/conformance_lps2.md`](docs/dev/conformance/conformance_lps2.md) | LPS1's recordings, run under LPS2 (generated) |
| [`conformance/conformance_report.md`](docs/dev/conformance/conformance_report.md) | the same recordings, run under LPS1 itself (generated) |
| [`overview/introducing-lps2-technical.md`](docs/user/overview/introducing-lps2-technical.md) | LPS2 in detail: the conformance testing, the architecture, and how each feature works inside |
