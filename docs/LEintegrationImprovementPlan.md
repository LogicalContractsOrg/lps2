# Logical English in the LPS2 IDE — an improvement plan

**Done, 2026-08-04 — M8f.** Phases 0–4 are complete; the status entry is in
`docs/LPSplusLLM.md` §Status and the contract is at version 2 in both repositories.
This file stays as the design and the reasoning, which the contract does not carry.

The three open questions at the end were answered: the CLI defaults to in-process,
`/LogicalEnglish2` may be changed here (its owner commits), and `nl_to_le` is wanted —
which is why `llm/le_llm.pl` exists, brokering LE2's LLM calls so an embedder can
supply its own client. A fourth requirement arrived with those answers and shaped the
work: **LPS2 must build and run with no LE2 at all**, with its absence breaking Logical
English and nothing else.

## The decision

One IDE, ours. **LE2 stays self-sufficient for Logical English** — it owns the grammar,
the template dictionary, the i18n lexicon and the LE→internal emitter, and nothing of
that moves. What changes is how LPS2 reaches it: LE2 also **exposes a Prolog library
that LPS2 loads into its own image**, so translating a document is a predicate call
rather than an HTTP round trip or a subprocess. `editor/lps.html` in LE2 is no longer
used regularly; it is frozen, not extended.

The expensive half is already built. M8a froze the contract, every generated term
carries `src(File,Line,Col,le)` provenance, and `src/edges/lps_le.pl` already speaks
two transports. Once a `.le` file can be *edited* here, run, timeline, automaton,
scenes, `why` and the assistant work unchanged, and LPS diagnostics already land on the
right LE line. Editing is the only missing piece.

Three principles carry over from the contract and are not up for renegotiation:

- **LE source is the only source of truth.** The internal syntax is a read-only
  compiler-output view. No two-way sync; `dump_le` stays a test (§I.9.5), not a feature.
- **What crosses the boundary for editing is data, not code.** The keyword tables and
  templates are served as terms from LE2, never copied into `ui/`. LE2's
  `src/generated/i18nData.ts` is 6,800 generated lines over `i18n/keywords.csv`;
  forking it would turn a documentation-duplication discipline into a code-duplication
  problem.
- **Never a guess.** With no LE2 configured, a `.le` tab opens read-only and names the
  variable to set, exactly as `./lps run foo.le` refuses today.

## Why in-process is safe enough

The stated reason for the subprocess (interface §3.3) was that a `.le` document can
pull in arbitrary Prolog. That hazard is already mitigated inside LE2, which is what
makes this plan possible: `le_kbs:load_prolog_resource/4` is **assert-only, never
consult** — it honours only `dynamic/1`, `discontiguous/1` and
`use_module(library(Lib))` for atomic library names, strips `module/2` with a warning,
and skips `initialization/1` and every other goal, precisely so a remote `.pl` cannot
execute at load time. Runtime `prolog` bodies pass `library(sandbox)`'s `safe_goal/1`
in the reasoner. So loading a document is parsing and asserting, not running.

What was checked and is *not* a problem:

| Worry | Finding |
|---|---|
| Operator clashes | LE2 declares operators only in `le_scasp.pl`, which is not on the `le_lps` path. Its one shared declaration, `op(900, fy, not)`, is identical to ours. |
| Module-name clashes | LE2 is `le_*`, `tokenizer`, `reasoner`; LPS2 is `lps_*`. No overlap. |
| Finding its own data | `le_i18n:i18n_dir/1` derives from `module_property(le_i18n, file(F))`, so the CSVs resolve from wherever the module was loaded. Nothing to configure. |
| Re-compiling on every keystroke | `le_kbs:load_text/2` is content-addressed (`m<sha1 of text>`), mutex-guarded, and reuses an error-free KB module. Unchanged text is free. |
| Threads at load time | The session reaper starts only when `start_session_reaper/0` is called. We never call it. |

What remains, and is handled below: the **load footprint** (`le_lps` → `le_grammar`,
`le_i18n`, `le_kbs` → `reasoner`, `le_verifier`, `http_open`, `pcre`, `uuid` — about
8k lines), **KB module accumulation** across an editing session, and **outbound network
fetches** for URL-valued resources (`le_kbs:fetch_url/2`) happening inside our server.

## LE2 side — the refactoring

R1 and R2 are needed; R3 is the second phase; R4 is a judgement call taken after
measurement, not before.

- **R1 — a narrow entry module.** `le_service.pl`: the one thing LPS2 loads, exporting
  the §2 payload predicates (`le_lps_text/4`, `le_lps_file/4`, `le_lps_module/5`,
  `le_lps_dict/4`) plus R2 and R3 below. Its job is to be the documented surface, so
  LPS2 never reaches into `le_kbs` or `le_grammar` internals and LE2 stays free to move
  them.
- **R2 — lifecycle and containment.** A `le_kb_dispose/1` so an editing session does not
  accumulate `m<sha1>` modules; and a flag that makes URL-valued resources refuse rather
  than fetch, so an IDE server does not make outbound requests on an author's behalf
  without being told to.
- **R3 — the editor-facing query.** The data a Monaco mode needs, as terms:
  `le_lexicon(+Lang, -Keywords)` from the `i18n/*.csv` tables already in memory, and
  `le_templates(+KB, -Templates)` giving each template's surface form, slot positions
  and types, and its **role** (`fluent | event | action | prolog_event | timeless`) —
  which `le_lps_role/2` already records. Plus the extents of the templates and scenario
  blocks. This is the single-sourcing that keeps the lexicon out of `ui/`.
- **R4 — splitting `le_kbs`.** Separating parse-and-assert from sessions, the reaper and
  HTTP would cut the load footprint substantially. Do it **only if Phase 0 measures a
  cost worth paying for**; it is the most invasive change here and the plan does not
  depend on it.

### The LE2 surface, as built

R1–R3 are in place; R4 is not, and the measurement below says it need not be. What
`le_service.pl` exports, beyond the re-exported payload:

| predicate | gives |
|---|---|
| `le_kb_of_text(+Text, +Options, -KB)` | the KB module for a buffer; `base(Dir)` resolves its resource includes |
| `le_kb_dispose(+KB)` | reclaims it, if no session or reader still holds it |
| `set_le_network_allowed(+Bool)` | whether a document's URL resources may be fetched at all |
| `le_lexicon(+Lang, -Lexicon)` | every keyword with its category and synonyms, longest phrase first, English-fallback filled |
| `le_languages(-Languages)` | the language registry: code, autonym, opener, separators |
| `le_templates(+KB, +Text, -Templates)` | `le_template(F/A, Role, Surface, Slots, Position, Flags)` |
| `le_blocks(+KB, +Text, -Blocks)` | `le_block(Kind, Detail, Name, Position)` in source order |
| `le_analyse(+Text, +Options, -Analysis)` | language, target, templates, blocks and issues in one call |
| `le_lexicon_dict/2`, `le_analyse_dict/3` | the same, shaped for `json_write_dict/2` |

Three details worth knowing before Phase 3 builds against them:

- **R2's disposal already existed.** `le_kbs:maybe_destroy_kb/1` had exactly the right
  semantics — it refuses to abolish a module a session or a concurrent reader still
  references — and only needed exporting. Calling it on a live KB is a no-op, not a
  corruption, so the IDE can dispose speculatively when a tab closes.
- **A template's surface is reconstructed, not sliced.** le_grammar records a template's
  offsets on the *parent* declaration, and its `opposite:` and synonym forms inherit
  them, so slicing the source at `Position` would give every derived form the parent's
  text and lose exactly the alternate phrasings completion wants. The reconstruction is
  faithful in word order and slot position; it renders a slot from its head-noun type,
  so `*a first person*` comes back `*a person*`. The verbatim declaration is a slice at
  `Position` whenever the caller wants it.
- **Declaration sections have no extents of their own.** `the fluents are:` and its
  siblings keep offsets per template, not per section, so `le_blocks/3` reports the
  sections that do record them (knowledge bases, scenarios, queries, the ontology) plus
  every template, sentence and rule individually. Aggregating a section extent from its
  templates would be a guess. If the IDE turns out to want section folding, the honest
  fix is offsets in `le_grammar`, not arithmetic here.

**Phase 0's measurement, taken early because it was cheap:** loading `le_service` into a
bare SWI-Prolog costs **~1.5 s wall and ~10 MB RSS**, once, at server start — against
0.24 s and 8.7 MB for the interpreter alone. That is the whole of the `reasoner` +
`le_verifier` + `http_open` footprint R4 would have gone after, and it is not worth an
invasive split of `le_kbs`. **R4 stays a possible later cleanup, not a prerequisite.**

Hard rule 5 applies throughout: `/LogicalEnglish2` is a real clone, currently on `main`;
check the branch, never switch it, and ask before committing.

## LPS2 side

- **`src/edges/lps_le.pl` gains a third transport, `lib(Dir)`**, selected by
  `LPS_LE2_LIB` and preferred over `LPS_LE2_URL` and `LPS_LE2_DIR`. All three produce
  the identical §2 payload; the existing `le_reply/5` shaping is reused untouched. The
  subprocess path stays, and stays the default for CI and for `./lps run` in a shell
  where isolation is worth more than latency. Core purity is untouched — this is an edge.
- **No mutex around LE calls** — the earlier draft of this plan assumed one would be
  needed because our HTTP server is threaded. It is not: LE2's active language lives in
  a global variable (thread-local in SWI), `le_include_base/1` is declared
  `thread_local`, and `load_text/2` takes a per-module mutex. Analysing a Portuguese and
  an English document on two threads at once gives the same answers as either alone.
- **New `/lpsapi` operations**, thin wrappers over the library: `le_compile` (document
  text → §2 payload, plus our own diagnostics), `le_lexicon`, `le_templates`. Everything
  goes through our own server on one origin — no CORS, no second base URL in the UI, and
  the IDE behaves identically whichever transport is configured.
- **The IDE**: a `.le` file type and tab; a Monarch mode built at runtime from
  `le_lexicon`; completion from `le_templates`, role-aware; markers from LE issues and
  LPS diagnostics concatenated, never merged (§2); and a read-only **generated internal
  syntax** pane beside the source, with linked highlighting in both directions — the
  provenance array already indexes term to sentence, so click-a-term/highlight-a-sentence
  is nearly free and is the most convincing thing in the whole feature.
- **Examples**: LE2's fifteen `examples/lps/*.le` become the LE entries in the IDE's
  example list, and the regression corpus.

## Gates

- **Transport equivalence.** Extend `tools/m8a_test.pl`: the fifteen programs through
  `lib`, `dir` and (when a server is up) `url` must yield §2 payloads equal under
  `variant/2`, term for term, with identical provenance and issues. This is the sharpest
  test available and it is cheap.
- **The existing gates stay green**: `tools/lint_core.pl`, LE2's `testing/lps_test.pl`
  (15/15) and `testing/lps_roundtrip.pl` (13/15).
- **Browser**: `tools/ide_check.cjs` grows an LE pass — open a `.le` example, edit,
  compile, place a marker, follow a provenance link — and fails on console errors as it
  does today. Then `tools/doc_shots.cjs` for the documentation.

## Order of work

| Phase | Work | Done when |
|---|---|---|
| **0** | Spike: load the LE stack into a stock `swipl`, translate `goat.le`, measure — **done, see above**; R4 is not needed | The number that decides R4 exists |
| **1** | R1, R2; `lib(Dir)` transport; transport-equivalence gate | `./lps run foo.le` in-process, byte-identical payload |
| **2** | `/lpsapi le_compile`; `.le` tab; diagnostics; the linked internal-syntax pane | An LE program is edited and run here, end to end |
| **3** | R3; the Monarch mode and template completion | Editing LE here is better than `editor/index.html` for LPS programs |
| **4** | Freeze `editor/lps.html`; interface-doc version bump in both repos; docs, screenshots, Status entry | The two copies of `le_lps_interface.md` agree and say so |

Phase 2 is where this becomes usable; phases 0 and 1 exist so that phase 2 rests on a
transport we have proved equal to the one the goldens were made with.

## Contract changes

Adding a transport and adding editor-facing operations are both changes to
`docs/le_lps_interface.md` — a new §3.5 (Prolog, in-process, from LPS2) and a new
section for the lexicon and template queries, with a version bump. It is duplicated
verbatim in both repositories: change one, copy it to the other, in the same commit.

Proposed milestone name: **M8f — LE editing in the LPS2 IDE**, the mirror of M8e. The
entry goes in `docs/LPSplusLLM.md`, which is the only place status lives.

## Open questions — answered

1. **The CLI defaults to in-process.** `LPS_LE2_DIR` now means "a checkout", loaded into
   the image; `LPS_LE2_SUBPROCESS=1` brings the old isolation back for anyone who wants
   it. The measurement that justified it is Phase 0's: the load is 1.5 s once, against a
   process start per document.
2. **Yes**, `/LogicalEnglish2` may be changed. What M8f changed there: `le_service.pl`,
   `llm/le_llm.pl`, a file-search path in `le_kbs.pl` so LE2 loads from any working
   directory, and a switch so it does not *print* issues an embedder already has as data.
   Committing is its owner's.
3. **`nl_to_le` is in.** It needed `llm_client`, and LPS2 has `lps_llm` — the same
   interface under another name — so the refactoring is a broker: `llm/le_llm.pl` holds
   the choice, LE2 defaults to its own client, and LPS2 registers `lps_llm` when the
   library loads. `predicateAt`/`predicateOccurrences` were *not* lifted out of
   `classic_web_api.pl`: the data R3 already exposes — every template's surface, role
   and position — is enough for the IDE to do go-to-definition itself, and moving 250
   lines of literal-level navigation out of a working HTTP handler is a refactor with
   real risk and no user visible in it.

## The original open questions

1. Does the CLI default to in-process too, or keep the subprocess for isolation? The
   plan keeps both and lets the environment choose; a default can be picked after
   phase 1 measures the difference.
2. Is `main` a committable branch in `/LogicalEnglish2`? Hard rule 5 says ask, and the
   answer is the user's.
3. Do we want LE2's `nl_to_le` and `predicateAt`/`predicateOccurrences` as well? Both
   become plain predicate calls once the library loads — natural-language authoring and
   go-to-definition for nearly nothing — but neither is on the critical path.
