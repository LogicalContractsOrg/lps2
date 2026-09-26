# CLAUDE.md — working notes for lps2

LPS2: a clean-room reimplementation of the LPS engine in SWI-Prolog, plus (later) an
LLM-facing agent layer.

**Three files, three jobs, no overlap.** The plan of record is
**`docs/project/plan-of-record.md`** — read it before doing anything substantial; it defines the
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
| `src/syntax/` | external syntax ↔ the §I.3 internal representation: LPS, PDDL, Drools, Inform 7 assertions (to Logical English), and `lps_to_le.pl`, which writes a program of the older syntax as a Logical English document (`lps le PROGRAM`, Misc ▸ Convert to Logical English; gate `tools/lps_to_le_test.pl`). Two of them are **not here**: `lps_solidity.pl` (Deploy as Solidity) and `lps_drools.pl` (the DRL reader) live in the private lpsPlus repository and are loaded from it by `lps_plus.pl`, which also says what a server without one answers; their gates moved with them (`lpsPlus/migration/{solidity,drools}/lps_*_test.pl`) |
| `src/edges/` | everything that touches the world: files, CLI, HTTP, LE2, LLM, live sessions, WASM |
| `ui/` | the IDE's sources. `npm run build` → `src/ide/dist/`, which is gitignored |
| `src/ide/dist/` | the built IDE, served by the HTTP endpoint (generated — never edit) |
| `src/pages/` | the sector pages: one self-contained HTML file per market (`insurance.html` → `/insurance`), what a printed leaflet's QR code opens. `lps_http:sector_page/2` serves them; the drawing in each is written by lpsPlus's `docs/sales/leaflets/build.cjs --landing`, never by hand; `tools/sector_page_test.pl` checks the route and every link into this server |
| `examples/` | LPS2's own examples, by purpose (`examples/README.md`): `start/` (the five the docs walk through), `collections/kowalski-book/`, `agents/` (`llm/`, `minecraft/`), `planning/` (PDDL), `le/` (Logical English for LPS, formerly LE2's examples/lps), `if/` (interactive fiction: the library and Inform's stories), `migration/` (the LE-for-LPS twins of Daml, Drools and Solidity programs written by lpsPlus's translators). The IDE labels each folder from its README title; a moved example keeps its old name through `example_alias/2` in `lps_http.pl` |
| `conformance/` | the harness: `.lpst` runner, engine adapters, perturbations, adjudications |
| `tools/` | gates and instruments: `lint_core.pl`, `m2_roundtrip.pl`, `examples_test.pl`, `explain_test.pl`, `lps_to_le_test.pl` (every `.lps` example converted to Logical English, both run, the two runs compared), `m8a_test.pl`, `pddl_test.pl`, `rkbook_test.pl`, `scene_test.pl` (what is worth drawing, and what gets drawn), `surface_test.pl`, `sandbox_test.pl`, `assistant_docs_test.pl` (the assistant's documentation search), `mcp_test.pl` (the Model Context Protocol surface), `open_test.pl` (File ▸ Open of other systems' files), `example_alias_test.pl`, `gen_monarch.pl`, `doc_shots.cjs`, `ide_check.cjs`, `linediff_test.mjs` (the assistant's "Show the change"), `if_demo.cjs` (the narrated video, needs an ElevenLabs key in the environment), `bench.pl`, `compare_engines.pl`, `trace_diff.pl` |
| `docs/` | the plan, the specs, the generated reports — indexed in `README.md` |
| `legacy_lps1/` | **READ-ONLY** full clone of the old LPS1 engine + example corpus |
| `/LogicalEnglish2` | the real LE2 repository (outside this tree) — see hard rule 5. In some containers it is mounted elsewhere (e.g. `/work`): `LPS_LE2_LIB`/`LPS_LE2_DIR` name it |
| `build/` | scratch: work dirs, engine variants, run logs, reports (gitignored) |
| `vendor/` | copies of other repositories, for the image. `vendor/le2/` is a minimal Logical English put there by `tools/vendor_le2.sh`; gitignored, and an image built without it simply has no LE |
| `lps` | the CLI: `./lps run examples/start/goat_declarative.pl` |
| `myswipl.sh` | SWI-Prolog launcher |
| `Dockerfile`, `fly.toml`, `buildPush.sh` | deployment — `docs/dev/deploy.md`. `buildPush.sh` vendors LE2 first, so a deployed image compiles `.le` in its own process |
| `wasm/` | the *other* deployment — `docs/dev/deploy-vercel.md`: `wasm/build.sh` turns the IDE into a static site with the engine compiled to WebAssembly, for Vercel or any file host. It calls the same operations as the server (`src/edges/lps_api.pl`), and changes nothing about the image |

`docs/vibeCodingNotes.md` is the user's private notebook — see hard rule 6.

## Hard rules

1. **Never write inside `legacy_lps1/`.** Running the legacy engine on a file *does* write
   next to it (`foo.pl` → regenerated `foo.pl_.P`, and `make_test` → `foo…lpst`). Both
   adapters therefore copy programs into `build/` first. If `git status` ever shows a
   modified file under `legacy_lps1/`, `git checkout --` it. Regenerated goldens live in
   `conformance/goldens/`, never LPS1.
2. **Clean-room boundary.** The engine is written from the plan, from
   `docs/dev/semantics/selection-spec.md` and from observed behaviour. The user has confirmed that
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
   (`docs/dev/le-lps-interface.md`) and the surface-language spec (`docs/user/reference/le-for-lps.md`)
   live here only (LE2 links to them) — change them together with the code of both
   repositories, or the version stamp is a lie.

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
**`docs/project/plan-of-record.md`, section Status**. Nothing about state is repeated here. Keep it
that way — the copies this file and `README.md` each used to carry had drifted apart by
a whole milestone before they were removed.

## Running things

```sh
./lps run examples/start/goat_declarative.pl        # the CLI
./lps step legacy_lps1/examples/goat.pl --cycles 3
./lps dump examples/start/goat_declarative.pl

./myswipl.sh -q -g "consult('tools/lint_core.pl')"     -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')"  -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main"        -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')"  -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/m8a_test.pl')"      -g "m8a:main"       -t halt
./myswipl.sh -q -g "consult('tools/bench.pl')"         -g "bench:main"     -t halt
./myswipl.sh -q -g "consult('tools/surface_test.pl')"  -g "st:main"         -t halt
./myswipl.sh -q -g "consult('tools/sandbox_test.pl')"  -g "sb:main"         -t halt
./myswipl.sh -q -g "consult('tools/mcp_test.pl')"      -g "mcp_test:main"   -t halt  # the MCP surface (two cases need LPS_LE2_LIB)
./myswipl.sh -q -g "consult('tools/assistant_docs_test.pl')" -g "asdocs:main" -t halt  # the assistant's documentation search, with a stub model
./myswipl.sh -q -g "consult('tools/telemetry_test.pl')" -g "tel:main"       -t halt  # Sentry/Cloudflare Web Analytics, off unless LPS_SENTRY_DSN/LPS_CLOUDFLARE_ANALYTICS_TOKEN (docs/dev/telemetry.md)
./myswipl.sh -q -g "consult('tools/sector_page_test.pl')" -g "sector_test:main" -t halt  # the sector pages (/insurance): route, drawing, links
./myswipl.sh -q -g "consult('tools/rkbook_test.pl')"   -g "rkbook_test:main" -t halt
./myswipl.sh -q -g "consult('tools/scene_test.pl')"    -g "scene_test:main"  -t halt  # the pictures: the focus (§5), spans/derived/order (§6), the scene strip (§7), the fill and object libraries

# The two gates that moved to lpsPlus with the translators they test (run from
# *that* checkout; each sets LPS_PLUS_DIR to itself, so it tests its own files
# through this repository's src/syntax/lps_plus.pl):
#   swipl -q -g "consult('migration/drools/lps_drools_test.pl')" -g "drools_test:main" -t halt
#   LPS_LE2_LIB=/LogicalEnglish2 swipl -q -g "consult('migration/solidity/lps_solidity_test.pl')" -g "solt:main" -t halt
# An LPS2 with no lpsPlus is tested by LPS_PLUS_DIR=none, which loads neither
# whatever is on the machine: surface_test and open_test then skip their DRL
# halves and say so.
LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/if_test.pl')" -g "if_test:main" -t halt
LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/play_test.pl')" -g "play_test:main" -t halt
LPS_LE2_LIB=/LogicalEnglish2 tools/inform_test.sh    # one Inform program per process; slow, each goes through LE2
# slow, and does not finish: the logistics domain was still searching after 40
# minutes. A planner limit, not a translation one — see docs/user/overview/introducing-lps2-technical.md §12.
./myswipl.sh -q -g "consult('tools/pddl_test.pl')"     -g "pddl_test:main" -t halt

# in /LogicalEnglish2 — check its branch first, see hard rule 5:
./myswipl.sh -q -g "consult('testing/lps_test.pl')"      -g "lps_test:main"      -t halt
./myswipl.sh -q -g "consult('testing/lps_roundtrip.pl')" -g "lps_roundtrip:main" -t halt

./lps mcp                                     # the MCP server on stdin/stdout (docs/user/api/mcp.md)
./lps ide                                     # on :3060 — `/` the start page, `/ide` the editor; MCP at POST /mcp
LPS_LE2_LIB=/LogicalEnglish2 ./lps ide        # …and Logical English editing, in-process
./lps explain PROGRAM --ask "why(happened(A), T)"
./lps timeline PROGRAM
./lps changes  PROGRAM --at 2
./lps automaton PROGRAM

./lps live examples/start/thermostat.lps --cycle-ms 400   # a session that does not end
LPS_LE2_LIB=/LogicalEnglish2 ./lps play examples/if/doors.le   # interactive fiction: type what a player types; `why`
LPS_LE2_LIB=/LogicalEnglish2 ./lps inform examples/if/inform/IQTest.ni --out build/story   # an Inform 7 source as a story
./lps pddl examples/planning/blocks-domain.pddl examples/planning/blocks-p1.pddl
./lps drools examples/migration/drools/drl/fire-alarm.drl

cd ui && npm install && npm run build          # the IDE → src/ide/dist/ (once)

./wasm/build.sh --skip-ui                      # the static/WebAssembly deployment → wasm/dist/
node wasm/runtime/serve.mjs wasm/dist 8090 &   # serve it with the deployment's own routing
NODE_PATH=/usr/lib/node_modules node tools/ide_check.cjs build/ide-shots-wasm 8090

./lps ide --port 3060 &                        # then, in another shell:
NODE_PATH=/usr/lib/node_modules node tools/ide_check.cjs 3060
```

**The documentation screenshots.** `docs/user/tutorials/lps-tutorial.md` and
`docs/user/overview/introducing-lps2.md` illustrate themselves from the running system; nothing in
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
  `docs/dev/semantics/selection-spec.md`.
- Documents, and every piece of text the software shows a reader (menu tips, the
  `explain` narration, the assistant's replies), are written for a reader with no
  technical training: name the thing rather than writing *it*/*this*/*they*, keep
  computing jargon out or explain it in the same sentence, one idea per sentence,
  spell out an abbreviation at first use. The rule in full is the "How documents are
  written" section of `docs/README.md`, kept identical in LE2 and LPS2. LPS's own
  vocabulary — fluent, event, action, reactive rule — is what the documents teach:
  use it, and define each term at first use or in the glossary.
- Prefer subprocess isolation when running *either* engine: a program may call arbitrary
  Prolog, and one entry's `halt/0` should not take the suite with it.
