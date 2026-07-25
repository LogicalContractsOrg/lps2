# CLAUDE.md — working notes for lps2

LPS(2): a clean-room reimplementation of the LPS engine in SWI-Prolog, plus (later) an
LLM-facing agent layer. The plan of record is **`docs/LPSplusLLM.md`** — read it before
doing anything substantial; it defines milestones M0–M11 and the conformance obligation.

## Repository layout

| Path | Role |
|---|---|
| `docs/LPSplusLLM.md` | the plan (Part I = the engine, Part II = agent, Part III = surfaces) |
| `docs/selection_spec.md` | §I.1.3 selection-strategy spec — SP1–SP15 from reading the old engine, SP16–SP20 from building the new one |
| `docs/conformance_report.md` | M0 output: the *legacy* engine against the corpus, buckets A/B/C |
| `docs/conformance_lps2.md` | M4 output: *LPS(2)* against the corpus |
| `docs/vibeCodingNotes.md` | user's running instructions to Claude |
| `src/core/` | the engine. No I/O, no threads, no clock, no foreign code |
| `src/syntax/` | external syntax ↔ the §I.3 internal representation |
| `src/edges/` | everything that touches the world: files, CLI, HTTP |
| `examples/` | LPS(2)'s own examples (`goat_declarative.pl`) |
| `conformance/` | the harness: `.lpst` runner, engine adapters, perturbations, adjudications |
| `docs/ide.md` | M9/M10: the IDE, the question forms, the visual mapping |
| `docs/le_lps_design.md` | M8 design: what LE2 emits, file extensions, the editor strategy, M8a–M8e |
| `src/ide/` | the web IDE, served by the HTTP endpoint |
| `tools/` | `lint_core.pl`, `m2_roundtrip.pl`, `trace_diff.pl`, `bench.pl`, `explain_test.pl`, `compare_engines.pl` |
| `legacy_lps1/` | **READ-ONLY** full clone of the old LPS(1) engine + example corpus |
| `/LogicalEnglish2` | the real LE2 repository (outside this tree) — see hard rule 5 |
| `build/` | scratch: work dirs, engine variants, run logs, reports (gitignored) |
| `lps` | the CLI: `./lps run examples/goat_declarative.pl` |
| `myswipl.sh` | SWI-Prolog launcher |

## Hard rules

1. **Never write inside `legacy_lps1/`.** Running the legacy engine on a file *does* write
   next to it (`foo.pl` → regenerated `foo.pl_.P`, and `make_test` → `foo…lpst`). Both
   adapters therefore copy programs into `build/` first. If `git status` ever shows a
   modified file under `legacy_lps1/`, `git checkout --` it. Regenerated goldens live in
   `conformance/goldens/`, never upstream.
2. **Clean-room boundary.** The engine is written from the plan, from
   `docs/selection_spec.md` and from observed behaviour. The user has confirmed that
   reading `legacy_lps1/engine/interpreter.P` is intended — it is their code — and §I.4
   makes the operator table and the internal vocabulary explicit interface
   specifications. What is *not* done is transliteration: the resolver is written against
   the numbered selection rules, so the accidents are inherited only where the spec says
   they are load-bearing.
3. **Core purity (§I.2.4).** Nothing in `src/core/` may reference threads, sockets, HTTP,
   `process_create`, `shell`, `get_time`, foreign predicates, randomness or file I/O.
   `tools/lint_core.pl` enforces it; run it before committing. The one deliberate
   exception is `b_setval`/`nb_setval`, confined to `src/core/lps_store.pl` — read that
   file's header for why the engine cannot be written without them.
4. Milestone gates are real: M4 (conformance) gates all later work.
5. **The LE2 repository is at `/LogicalEnglish2`** — outside this tree, a real working
   clone, not a copy. It is checked out on branch **`with-lps2`**, which is the *only*
   branch anything may be committed to. Never commit to `main` or to any other branch
   there, and never switch its branch. The LPS target module (`le_lps.pl`), the LPS
   Monaco mode and the LPS panes live there; the interface contract
   (`docs/le_lps_interface.md`) is duplicated verbatim in both repositories.

## Status

M0–M10 are done.

- **M0** harness + corpus classification: 88 bucket A, 11 bucket B, 0 bucket C.
- **M1** core skeleton: program/session split, working store, cycle, diagnostics, lint.
- **M2** legacy surface syntax; 90 of 91 corpus programs translate identically to
  psyntax's own `_.P`, the one difference adjudicated as an upstream writer bug
  (`tools/m2_roundtrip.pl`).
- **M3/M4** conformance — see `docs/conformance_lps2.md` for the current numbers and the
  adjudication register (`conformance/adjudicated.pl`, `conformance/regenerated.pl`).
- **M5** hypothetical worlds. §I.6's dual-backend design turned out to be unnecessary:
  because a session is an immutable term, `lps_session_fork/2` is a unification. Measured
  at ~5 µs independent of session size (`tools/bench.pl`).
- **M6** planning mode: `achieve`, static classification of `false` clauses, concurrent
  action sets, `examples/goat_declarative.pl` (which solves).
- **M7** CLI (`./lps`) and the single-endpoint HTTP API (`src/edges/lps_http.pl`).
- **M8** done, across both repositories.
  - **M8a** the joint interface: `t(Term, src(File,Line,Col,Kind))`, `/lpsapi compile`
    with a `provenance` array, decomposed `source` on every diagnostic,
    `src/edges/lps_le.pl` (HTTP or subprocess, never a guess), `docs/le_lps_interface.md`.
    Gate: `tools/m8a_test.pl`.
  - **M8b** the surface language on paper: `docs/le_lps_surface.md` and the fifteen
    programs in `/LogicalEnglish2/examples/lps/`. The prospective form — the open
    problem of `le_lps_design.md` §6 — turned out to be expressible as `… to a time`.
  - **M8c** `le_lps.pl` in LE2. All fifteen translate to internal syntax
    (`testing/lps_test.pl`, 15/15); thirteen run to success under `./lps run foo.le`.
    `foo.lps` compiles together with `foo.le` — the §7 escape hatch.
  - **M8d** the round trip: `le_lps_write.pl` and `testing/lps_roundtrip.pl`,
    13 of 15 `LE → internal → LE → internal` `variant/2`-equal, 2 excluded with a
    stated reason (a calendar date constant has no LE surface form).
  - **M8e** the editor: `editor/lps.html`, a second Monaco mode for `.lps`, two
    backends and no proxy. Driven in a real browser against both servers.
- **M9** IDE and explanations. The derivation forest of §I.10.5 is recorded
  unconditionally by the engine; `src/core/lps_explain.pl` reads it. All five
  question forms and all four `why_not` cases are covered by
  `tools/explain_test.pl`. Timeline (§I.10.2) and state-change diagram
  (§I.10.3) are derived from the same trace.
- **M10** Animation and polish: the `display/2` visual mapping, cycle
  scrubbing, `docs/ide.md`. Plus the **state-transitions diagram** (upstream's
  `godfa/1`): `lps_automaton/4`, `./lps automaton`, `/lpsapi automaton`, and a
  pane in both IDEs — every distinct state once, so a program that revisits a
  state reads as a loop. Checked against `historicalDocs/godfa-*.png`.

### Known gaps

- **Two IDEs, deliberately.** `/LogicalEnglish2/editor/lps.html` is the LE2 one
  (M8e): Monaco, two language modes, two backends. `src/ide/index.html` stays as
  a *reference* client — it is what `tools/ide_screenshots.cjs` drives, and it
  proves `/lpsapi` is sufficient with no LE2 dependency in our CI. The moment the
  only client of the API is a page in another repository, the API stops being
  independently testable. `src/ide/` should stay deliberately plain and should
  never grow a feature the panes do not need.
- **`dumplps/0`, the internal→*legacy surface* direction.** §I.3 asks for it
  alongside `dump/0`. Still not implemented, and `./lps dump --syntax legacy`
  still says so rather than approximating it. The internal→*LE* direction, which
  §I.9.5 actually gates on, **is** done: `le_lps_write.pl` in LE2, 13 of 15
  programs round-tripping.
- **lps.js syntax** is dropped, per the user's decision. `.lpsw` is *not* a
  surface syntax: `psyntax.P:237–260` treats `_.P` and `.lpsw` alike as
  generated **internal** syntax, which is why the corpus's eleven `.lpsw`
  entries run through the internal reader. Going forward `.lpsw` is the
  canonical internal extension and `.lps` the canonical external one — see
  `docs/le_lps_design.md` §2.
- **`docs/conformance_report.md`** (the M0 legacy numbers) is checked in but its
  `build/results.pl` is not, so regenerating it needs a full legacy sweep
  (~35 min).

## Running things

```sh
./lps run examples/goat_declarative.pl        # the CLI
./lps step legacy_lps1/examples/goat.pl --cycles 3
./lps dump examples/goat_declarative.pl

./myswipl.sh -q -g "consult('tools/lint_core.pl')"    -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')" -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/bench.pl')"        -g "bench:main"     -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')" -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/m8a_test.pl')"     -g "m8a:main"       -t halt

# in /LogicalEnglish2 (branch with-lps2):
./myswipl.sh -q -g "consult('testing/lps_test.pl')"      -g "lps_test:main"      -t halt
./myswipl.sh -q -g "consult('testing/lps_roundtrip.pl')" -g "lps_roundtrip:main" -t halt

./lps ide                                     # the web IDE on :3060
./lps explain PROGRAM --ask "why(happened(A), T)"
./lps timeline PROGRAM
./lps changes  PROGRAM --at 2

./lps ide --port 3060 &                       # then, in another shell:
NODE_PATH=/usr/lib/node_modules node tools/ide_screenshots.cjs build/ide-shots 3060
```

### The conformance harness

```sh
./myswipl.sh -q -g "consult('conformance/runner.pl')" -g "runner:main([ARGS])" -t halt
```
with ARGS a list of atoms, e.g. `['--engine','lps2','--only','goat','--variants','none']`.

`--engine legacy|lps2|cross` picks what runs. `cross` runs *both* and compares their
traces with each other rather than with the golden — the only meaningful comparison when
a golden predates upstream's own behaviour, which six of the extended entries do.

Other flags: `--only Substring`, `--variants a,b,c`, `--limit N`, `--jobs N` (keep at 1:
concurrency perturbs the legacy engine's per-phase time limits), `--time-limit Seconds`,
`--extended` (adds the six slow real-time tests in `utils/moreTestResults`), `--upstream`
(cross-check our verdict against the legacy engine's own `run_test`), `--report FILE`,
`--results FILE`, `--report-only`, `--no-report`.

Per-run artefacts stay in `build/work/<slug>/<variant>/` (legacy) and
`build/work/<slug>/lps2_<variant>/` — read `engine.log` and the produced `.lpst` first
when a test misbehaves. `tools/trace_diff.pl` prints the first differing cycle.

## Running SWI-Prolog

```sh
./myswipl.sh -g "consult('src/lps.pl')" -g "main" -g halt
```
`timeout(1)` is **not** available on macOS — use SWI's `call_with_time_limit/2` inside
the child, or `process_wait/3` with a `timeout` option in the parent.

## The legacy engine, in one paragraph

`legacy_lps1/utils/psyntax.P` is the entry point; consulting it loads
`engine/interpreter.P`. A program in surface syntax (`foo.pl`, `foo.lps`, `foo.lpsw`) is
translated by `psyntax` into an internal-syntax file `foo.pl_.P` (facts: `reactive_rule/2`,
`l_events/2`, `l_int/2`, `l_timeless/2`, `d_pre/1`, `initiated/3`, `terminated/3`,
`initial_state/1`, declarations). `interpreter:go(File, Options)` runs that internal file.
`psyntax:golps(Source, Options)` does translate-then-run in one step. Golden test files are
named after the *generated* file: `foo.pl_.P.lpst`.

Options that matter: `dc` (the resolution path we reimplement), `make_test` (record a
trace), `run_test` (check against one).

## The conformance contract (§0.2 — read it)

A `.lpst` is a Prolog fact file with `lps_test_result(Stage,Cycle,Count)` and
`lps_test_result_item(Stage,Cycle,Term)` for `Stage ∈ {fluents, events, composites}`.
Comparison is: exact item count, then `sort/2` on both sides and `variant/2`. So order
within a cycle is free, but *cycle alignment, item count and term shape up to variable
renaming* are all exact. A program that is supposed to fail carries
`lps_test_result_item(end,-1,failure)`. This is **trace equivalence, not semantic
equivalence** — the main technical risk in Part I.

The harness classifies on its own **strict** verdict: upstream compares only the cycles a
run actually produced, so a run that dies half way scores "ok". Both verdicts are
recorded.

## Conventions

- Prolog source: tabs as upstream uses them; follow the local file's style. New code uses
  standard SWI module headers with explicit export lists and `%!`-style predicate docs.
- Reports are generated, not hand-edited. Hand-written analysis goes in
  `docs/selection_spec.md`.
- Prefer subprocess isolation when running *either* engine: a program may call arbitrary
  Prolog, and one entry's `halt/0` should not take the suite with it.
