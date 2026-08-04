# CLAUDE.md — working notes for lps2

LPS2: a clean-room reimplementation of the LPS engine in SWI-Prolog, plus (later) an
LLM-facing agent layer.

**Three files, three jobs, no overlap.** The plan of record is
**`docs/LPSplusLLM.md`** — read it before doing anything substantial; it defines the
milestones and the conformance obligation, and its **Status** section is the *single*
place project status lives (what is done, the known gaps, the candidate next steps).
`README.md` says what the system is and why it is shaped this way, and indexes the
documents. **This file** is how to work on it: the hard rules, how to run things, and the
two things worth having in your head before touching the engine — how the legacy engine is
organised, and what the conformance contract actually compares. Status belongs to the plan
alone — not to this file, not to the README.

## Repository layout

| Path | Role |
|---|---|
| `src/core/` | the engine. No I/O, no threads, no clock, no foreign code |
| `src/syntax/` | external syntax ↔ the §I.3 internal representation: LPS, PDDL, Drools |
| `src/edges/` | everything that touches the world: files, CLI, HTTP, LE2, LLM, live sessions, WASM |
| `ui/` | the IDE's sources. `npm run build` → `src/ide/dist/`, which is gitignored |
| `src/ide/dist/` | the built IDE, served by the HTTP endpoint (generated — never edit) |
| `examples/` | LPS2's own examples: planning, live, `pddl/`, `drools/`, `agent/`, `minecraft/`, `rkbook/` |
| `conformance/` | the harness: `.lpst` runner, engine adapters, perturbations, adjudications |
| `tools/` | gates and instruments: `lint_core.pl`, `m2_roundtrip.pl`, `examples_test.pl`, `explain_test.pl`, `m8a_test.pl`, `pddl_test.pl`, `drools_test.pl`, `rkbook_test.pl`, `surface_test.pl`, `gen_monarch.pl`, `doc_shots.cjs`, `ide_check.cjs`, `bench.pl`, `compare_engines.pl`, `trace_diff.pl` |
| `docs/` | the plan, the specs, the generated reports — indexed in `README.md` |
| `legacy_lps1/` | **READ-ONLY** full clone of the old LPS1 engine + example corpus |
| `/LogicalEnglish2` | the real LE2 repository (outside this tree) — see hard rule 5 |
| `build/` | scratch: work dirs, engine variants, run logs, reports (gitignored) |
| `vendor/` | copies of other repositories, for the image. `vendor/le2/` is a minimal Logical English put there by `tools/vendor_le2.sh`; gitignored, and an image built without it simply has no LE |
| `lps` | the CLI: `./lps run examples/goat_declarative.pl` |
| `myswipl.sh` | SWI-Prolog launcher |
| `Dockerfile`, `fly.toml`, `buildPush.sh` | deployment — `docs/deploy.md`. `buildPush.sh` vendors LE2 first, so a deployed image compiles `.le` in its own process |

`docs/vibeCodingNotes.md` is the user's private notebook — see hard rule 6.

## Hard rules

1. **Never write inside `legacy_lps1/`.** Running the legacy engine on a file *does* write
   next to it (`foo.pl` → regenerated `foo.pl_.P`, and `make_test` → `foo…lpst`). Both
   adapters therefore copy programs into `build/` first. If `git status` ever shows a
   modified file under `legacy_lps1/`, `git checkout --` it. Regenerated goldens live in
   `conformance/goldens/`, never LPS1.
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
   clone, not a copy. The LPS target modules (`le_lps.pl`, `le_lps_write.pl`), the LPS
   Monaco mode and the LPS panes live there; the interface contract
   (`docs/le_lps_interface.md`) and the surface-language spec (`docs/le_lps_surface.md`)
   are duplicated verbatim in both repositories — change one and copy it to the other in
   the same commit, or the version stamp is a lie.

   **M8f loads LE2 into our image.** `LPS_LE2_LIB=<checkout>` makes
   `src/edges/lps_le.pl` load `le_service.pl` with `load_files/2` at first use —
   never a `use_module` directive, because LE2 is optional and a directive would
   make a missing checkout a load error for a file on the CLI's path.
   `LPS_LE2_DIR` now also means in-process; `LPS_LE2_SUBPROCESS=1` brings the old
   subprocess back.

   The M8 work was done on branch **`with-lps2`** and has since been merged: as of
   2026-08-03 that clone sits on **`main`**, `with-lps2` is fully contained in it, and
   `main` is fifteen commits further on. So: **run `git -C /LogicalEnglish2 branch
   --show-current` before touching anything there, never switch its branch, and ask
   before committing** — the original rule named `with-lps2` as the only committable
   branch, and whether that now means `main` is the user's call, not yours.
6. **`docs/vibeCodingNotes.md` is private.** It is the user's own notebook. Do not read
   it, do not edit it, and do not quote or paraphrase it into any document, commit
   message or reply. If something in it matters to the work, the user will say so
   directly.

## Status — elsewhere

Which milestone is where, what the known gaps are, what the plausible next steps are:
**`docs/LPSplusLLM.md`, section Status**. Nothing about state is repeated here. Keep it
that way — the copies this file and `README.md` each used to carry had drifted apart by
a whole milestone before they were removed.

## Running things

```sh
./lps run examples/goat_declarative.pl        # the CLI
./lps step legacy_lps1/examples/goat.pl --cycles 3
./lps dump examples/goat_declarative.pl

./myswipl.sh -q -g "consult('tools/lint_core.pl')"     -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')"  -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main"        -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')"  -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/m8a_test.pl')"      -g "m8a:main"       -t halt
./myswipl.sh -q -g "consult('tools/bench.pl')"         -g "bench:main"     -t halt
./myswipl.sh -q -g "consult('tools/drools_test.pl')"   -g "drools_test:main" -t halt
./myswipl.sh -q -g "consult('tools/surface_test.pl')"  -g "st:main"         -t halt
./myswipl.sh -q -g "consult('tools/rkbook_test.pl')"   -g "rkbook_test:main" -t halt
# slow, and does not finish: the logistics domain was still searching after 40
# minutes. A planner limit, not a translation one — see IntroducingLPS2.md §18.
./myswipl.sh -q -g "consult('tools/pddl_test.pl')"     -g "pddl_test:main" -t halt

# in /LogicalEnglish2 — check its branch first, see hard rule 5:
./myswipl.sh -q -g "consult('testing/lps_test.pl')"      -g "lps_test:main"      -t halt
./myswipl.sh -q -g "consult('testing/lps_roundtrip.pl')" -g "lps_roundtrip:main" -t halt

./lps ide                                     # on :3060 — `/` the start page, `/ide` the editor
LPS_LE2_LIB=/LogicalEnglish2 ./lps ide        # …and Logical English editing, in-process
./lps explain PROGRAM --ask "why(happened(A), T)"
./lps timeline PROGRAM
./lps changes  PROGRAM --at 2
./lps automaton PROGRAM

./lps live examples/thermostat.lps --cycle-ms 400   # a session that does not end
./lps pddl examples/pddl/blocks-domain.pddl examples/pddl/blocks-p1.pddl
./lps drools examples/drools/fire-alarm.drl

cd ui && npm install && npm run build          # the IDE → src/ide/dist/ (once)

./lps ide --port 3060 &                        # then, in another shell:
NODE_PATH=/usr/lib/node_modules node tools/ide_check.cjs 3060
```

**The documentation screenshots.** `docs/lps_tutorial.md` and
`docs/IntroducingLPS2.md` illustrate themselves from the running system; nothing in
them is drawn by hand. Regenerate after any UI change — the same run fails on console
errors and HTTP 4xx, so it doubles as a browser test:

```sh
./lps ide --port 3060 &                        # with an LLM key set, for the assistant shots
(cd /LogicalEnglish2 && ./myswipl.sh -q -g "use_module(classic_web_api), \
   start_api_server(3050)" -g "thread_get_message(_)" &)     # optional
NODE_PATH=/usr/lib/node_modules node tools/doc_shots.cjs docs/images 3060 3050
```

### The conformance harness

```sh
./myswipl.sh -q -g "consult('conformance/runner.pl')" -g "runner:main([ARGS])" -t halt
```
with ARGS a list of atoms, e.g. `['--engine','lps2','--only','goat','--variants','none']`.

`--engine legacy|lps2|cross` picks what runs. `cross` runs *both* and compares their
traces with each other rather than with the golden — the only meaningful comparison when
a golden predates LPS1's own behaviour, which six of the extended entries do.

Other flags: `--only Substring`, `--variants a,b,c`, `--limit N`, `--jobs N` (keep at 1:
concurrency perturbs the legacy engine's per-phase time limits), `--time-limit Seconds`,
`--extended` (adds the six slow real-time tests in `utils/moreTestResults`), `--LPS1`
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

The harness classifies on its own **strict** verdict: LPS1 compares only the cycles a
run actually produced, so a run that dies half way scores "ok". Both verdicts are
recorded.

## Conventions

- Prolog source: tabs as LPS1 uses them; follow the local file's style. New code uses
  standard SWI module headers with explicit export lists and `%!`-style predicate docs.
- Reports are generated, not hand-edited. Hand-written analysis goes in
  `docs/selection_spec.md`.
- Prefer subprocess isolation when running *either* engine: a program may call arbitrary
  Prolog, and one entry's `halt/0` should not take the suite with it.
