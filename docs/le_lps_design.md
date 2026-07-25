# Logical English for LPS, and the editor strategy

Design note for **M8**. Options, evidence, and a recommendation for each of the
four questions on the table. Nothing here is implemented yet; §I.9 of
[`LPSplusLLM.md`](LPSplusLLM.md) is updated to point at this document, and the
milestone is restructured into gated pieces at the end.

The four questions, in the form they were asked:

1. What should the LE2 parser generate — our internal form?
2. File extensions: `.le`, `.pl`, `.lpsw`, and one for our non-LE external
   syntax; and does `.le` cover extended LE or do we add another?
3. A Monaco editor for the external form and one for the LE form — same or
   separate?
4. Both repositories can change. What is the joint strategy?

---

## 0. The finding that reorders this

**The corpus already contains a Logical-English-for-LPS prototype, by the same
author, with known failure modes recorded in its own comments.** Three files
carry an `en("…")` block:

```
legacy_lps1/examples/CLOUT_workshop/RockPaperScissors-Minimal-en.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsBaseEN.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsEthereumFEn.pl
legacy_lps1/examples/forTesting/testNLPhook.pl        (a stub)
```

None has a generated `_.P` and none has a `.lpst`, so they are outside the
conformance corpus and nothing constrains them. But they are not sketches:
`RockPaperScissors-Minimal-en.pl` carries comments like

```
<!-- buggy, generating l_timeless instead of l_int: … -->
<!-- buggy, missing time variable binding: … -->
```

which means a translator existed, was run, and produced wrong internal terms in
identifiable ways. This is prior art with a bug list attached.

**What the specimens already answer.** §I.9.3 called temporal reference in
English "the hard part" and marked the resolution `[assumption]`. The specimens
settle it empirically — both forms are used, and each has a job:

| form | specimen | maps to |
|---|---|---|
| time elided | `When a player inputs a choice and a value then the player has played the choice.` | `reactive_rule/2`, times generated |
| time as an LE variable | `If a first player has played a first choice at a first time and …` | `at T1` with `T1` a real variable |
| explicit interval | `the first player gets the prize from the first time to a second time` | `from T1 to T2` |

Option (b) of §I.9.3 — ordinal steps, `at step 3` — appears nowhere. Drop it.
The distinct-variable mechanism is LE's ordinal determiners (`a first time` /
`the first time` / `a second time`), which LE2 already has.

**The construct inventory the specimens establish**, which is close to complete
for LPS:

```
the maximum time is 5.                            → maxTime/1
the events are: …                                 → events/1
the actions are: …                                → actions/1        ← LE2 lacks this
the prolog events are: …                          → prolog_events/1
the fluents are: … known as reward, …             → fluents/1 + functor binding
initially: the reward is 0.                       → initial_state/1
the observations are: X from 1 to 2, …            → observe/2
scissors beats paper.                             → l_timeless/2 (a bare fact)
When … then …                                     → reactive_rule/2
If … at a first time … then …                     → reactive_rule/2, explicit time
then initiate the game is over from … to …        → initiated/3
the reward that is a number becomes the number plus the value
                                                  → updated/4
It must not be true that …                        → d_pre/1 (and the false form)
the reward is a number, known as reward, at a time if …
                                                  → l_int/2
a player pays a prize, known as pay, from a first time to a second time if …
                                                  → l_events/2
the number at the time is the sum of all …        → aggregate
lps_terminate from … to …                         → system action
```

Two caveats before anyone treats these as a specification.

- **They are LE1-flavoured.** `known as reward` binds a template to a functor;
  LE2 uses `the templates are:` with `*variable*` slots and head-noun typing.
  The *constructs* transfer; the *notation* must be re-expressed in LE2's idiom.
- **`RockPaperScissors-Minimal-en.pl` mixes LE and formal LPS in one file**, with
  a comment saying so ("LPS explicit clauses to complement the above"). That is
  the author's own answer to §I.9.6's scope limit, and it is a design input, not
  an accident. See §5.

---

## 1. What should the LE2 parser generate?

### The options

**A. LE2 emits LPS internal syntax.** A third target language beside `prolog`
and `taxlog`: `the target language is: lps.` A new `le_lps.pl` sits where
`le_scasp.pl` sits, consuming the parsed LE structures and emitting
`reactive_rule/2`, `l_int/2`, `l_events/2`, `l_timeless/2`, `initiated/3`,
`terminated/3`, `updated/4`, `d_pre/1`, `initial_state/1`, `observe/2` and the
declarations.

**B. LE2 emits a neutral AST that LPS(2) maps to internal.** A third
representation, jointly owned.

**C. LE2 emits LPS *external* syntax as text**, which LPS(2) then parses.

**D. LPS(2) forks the LE grammar** and owns the whole LE-for-LPS pipeline.

### Evaluation

**C is out on evidence.** It requires the internal→surface writer that §I.3 asks
for and that we deliberately have not built (`dumplps/0`; see the README's known
gaps), it parses the program twice, and text is a lossy interface — the source
positions needed for editor diagnostics do not survive it.

**D is out on the editor.** LE2's editor extracts templates in a browser Web
Worker to drive semantic tokens, completions and hover. If the LPS constructs
live in a grammar the editor cannot see, every LPS sentence in an `.le` document
is mis-highlighted and uncompletable. The grammar has to be where the editor is.
It is also the wrong answer to "we can change both repos": forking is what you do
when you *cannot*.

**B is a middle layer for its own sake.** The neutral AST would be defined by
what the target needs, so it would end up isomorphic to the internal form — but
with two mappings to write, two to test, and two places for a construct to go
missing. There is a real argument for B, which is that it decouples LE2 from
LPS's internal vocabulary. It does not survive contact with the fact that *the
internal vocabulary is already frozen*: it is the 2016-era `_.P` format, §I.4
makes it an explicit interface specification, and 108 golden traces pin its
meaning. A newly invented neutral AST would be the less stable of the two.

**A is the recommendation**, and it has a property the others do not: the
interface already exists on our side. `lps_compile/5` already accepts

```prolog
lps_compile(terms([t(maxTime(6), 2), t(actions([row(_,_)]), 3), …]),
            internal, [dc], Program, Diagnostics)
```

— a list of terms with source lines. `tools/explain_test.pl` uses exactly this
today to build a program with no file behind it.

### The concrete contract

What crosses the repository boundary, for one document:

```
  foo.le   (the target language is: lps.)
     │
     │   LE2:  le_grammar.pl  →  le_lps.pl
     ▼
  { "internal":    "<internal-syntax Prolog text>",
    "provenance":  [ {"index": 3, "line": 12, "col": 4, "kind": "le",
                      "le_ref": "…"} , … ],
    "diagnostics": [ … LE-side diagnostics … ] }
     │
     │   LPS(2):  lps_compile(internal(Text, Provenance), …)
     ▼
  lps_prog(…)  →  session  →  trace  →  timeline / changes / scene / explain
```

**Internal syntax as text, not as JSON-encoded terms.** It is Prolog, LE2
already writes Prolog, and a text blob is diffable, pasteable into `./lps run`,
and inspectable when something goes wrong. JSON-encoding Prolog terms would
require both sides to agree on an encoding of variables, operators and
`'$VAR'`, which is work with no payoff.

**The symmetry that makes this feel right.** `psyntax` already compiles
`foo.lps` → `foo.lps_.lpsw`. Under this design `foo.le` → `foo.le_.lpsw` by the
same rule. Three surface syntaxes, one internal form, one engine — and the
build artefact of an LE document is a first-class file you can run directly.

**Provenance is the only new thing.** LPS(2) diagnostics carry
`src(File, Line, Col, Kind)` (§I.2.5) so that the editor can place a marker.
For an LE-sourced program those positions must point into the `.le` file, not
into generated internal text. The change on our side is two lines in
`lps_program.pl`:

```prolog
partition_term(Origin, t(Term, Loc), A0, A) :-
	(   Loc = src(_,_,_,_)          % LE2 supplies a full position
	->  Src = Loc
	;   Src = src(Origin, Loc, 0, internal)
	),
	partition_term_(Term, Src, A0, A).
```

Everything downstream — `p_term_src/3`, the diagnostics, the explanation
forest, the IDE's marker placement — then works unchanged on LE positions.

**Diagnostics compose rather than merge.** LE2 reports what it can see
(unparseable sentence, template mismatch, undeclared word); LPS(2) reports what
it can see (`achieve` without planning mode, undeclared fluent, a `false` clause
that can never fire). Neither needs the other's rule set. The editor
concatenates two lists of positioned diagnostics.

---

## 2. File extensions

### The evidence

The proposed scheme is not an invention — it is what `psyntax` already does.
From `legacy_lps1/utils/psyntax.P:237–260`:

```prolog
% [46,108,112,115,119] .lpsw
% [95,46,80] _.P
% [46,108,112,115] .lps
generate_file(F) :-
	(sub_atom(F,_,Nchars,0,'_.P') ; sub_atom(F,_,Nchars,0,'.lpsw')), !,
	sub_atom(F,0,_,Nchars,Source),
	(sub_atom(Source,_,_,0,'.lps'); sub_atom(Source,_,_,0,'.pl')),
	…
```

`_.P` and `.lpsw` are both **generated internal syntax**; `.lps` and `.pl` are
both **external syntax**. So `.lpsw` = internal is upstream's own convention,
and `.lps` = external is too. (This corrects a phrasing in `CLAUDE.md`, which
calls `.lpsw` a dropped *surface* syntax. The eleven `.lpsw` corpus entries run
through the internal reader precisely because `.lpsw` *is* internal syntax.)

### Recommendation

| extension | meaning | read by |
|---|---|---|
| `.le` | Logical English — plain, or LPS via `the target language is: lps.` | LE2 |
| `.lps` | LPS external syntax, non-LE | LPS(2) |
| `.lpsw` | LPS internal syntax (canonical) | LPS(2) |
| `_.P` | LPS internal syntax (legacy alias, corpus only) | LPS(2) |
| `.pl` | Prolog — and legacy LPS external, accepted for the corpus | both |
| `.lpst` | conformance trace, unchanged | the harness |

`.lps` for the external syntax, because it already exists upstream and needs no
argument. That frees `.pl` to mean Prolog, which resolves a live confusion: 88
of the corpus's programs are `.pl` files that are not Prolog programs. `.pl`
stays *accepted* — the corpus cannot be renamed, hard rule 1 — but stops being
canonical.

### `.le` for extended LE, not a new extension

This is the one where I would most welcome disagreement, so here is the argument
in full.

**For a single `.le`:**

- LE2 already owns an in-band mechanism for exactly this distinction — `the
  target language is:` — and uses it for `prolog` versus `taxlog`. A second
  extension encodes the same fact twice and creates the possibility of the two
  disagreeing (`.leps` declaring `prolog`, `.le` declaring `lps`).
- One extension means one Monaco language id, one Monarch grammar, one LSP
  server, one set of themes, one Playwright suite.
- A plain-LE document can *grow into* an LPS program by adding a declaration and
  some rules, without being renamed. Renaming a file to change its meaning is the
  kind of friction that gets in the way of exactly the exploratory authoring this
  is for.
- The LPS constructs are additive keywords (`When … then`, `initially:`, `It
  must not be true that`, `the actions are:`). Highlighting them in a plain-LE
  document is harmless: they read as ordinary template instances.

**Against, honestly:** LE2's own test suite runs every `.le` under `examples/`
through the plain-LE pipeline; a single extension forces that suite to dispatch
on the declared target. That is a real cost, but it is the *right* cost — it
makes target dispatch a first-class, tested thing rather than a filename
convention.

**The escape hatch, with a stated test.** If the LPS layer turns out to need a
different *document structure* rather than extra constructs, a separate
extension becomes right. The test: does an LPS-LE document still have `the
knowledge base includes:`, `scenario`, and `query`? On the specimen evidence,
yes — knowledge base and scenario carry over directly (scenarios become timed
observations), and only `query` loses centrality. So the structure holds, and
one extension is right. If M8b (below) finds otherwise, `.leps` is a one-line
change made before any tooling exists.

---

## 3. One Monaco editor, or two?

### Recommendation: one editor shell, two language modes.

- **`le`** — LE2's existing mode, extended with the LPS constructs. No new mode.
- **`lps`** — a new Monarch grammar for the external syntax: Prolog lexis plus
  the §I.4 operator table as keywords (`if`, `then`, `initiates`, `terminates`,
  `updates`, `from`, `to`, `at`, `during`, `false`, `initially`, `fluents`,
  `actions`, `events`, `observe`, `achieve`).

**Two modes rather than one**, because the two languages share no lexis. LE is
English with indentation-significant structure; the external syntax is Prolog
with an operator table. One Monarch grammar covering both would be a
mode-switching monster, and the LSP features differ in kind — template
extraction is meaningless for `.lps`, operator completion is meaningless for
`.le`.

**One shell rather than two**, because everything above the tokenizer is
language-agnostic. The LSP client, the 1500 ms debounce, the diagnostic markers,
and all four visualisation panes (timeline, state changes, animation, explain)
operate on *a compiled program and its trace*, never on source text. Duplicating
that to get a different tokenizer would be indefensible.

**One LSP worker**, dispatching on `languageId`. Shared: folding, diagnostics
from the backend, hover. Mode-specific: template extraction (`le`), operator and
declaration completion (`lps`).

### Where the editor lives

§I.10.1 says to extend LE2's Monaco editor; that repository was not available,
so `src/ide/index.html` was built instead — self-contained, same round-trip
pattern, same operations an LSP worker would call.

**Recommendation: the LE2 editor becomes the single front end, and LPS(2) keeps
`src/ide/` as a reference implementation.**

LE2's editor is by far the more developed artefact — LSP worker, semantic
tokens, three themes, several HTML surfaces, a Playwright suite. LPS(2)
contributes the `lps` language mode and the four panes as self-contained
components driven by our HTTP API.

Keeping `src/ide/` is not sentiment. It is what `tools/ide_screenshots.cjs`
drives, and it proves the API is sufficient *with no LE2 dependency in our CI*.
The moment the only client of `/lpsapi` is a page in another repository, the API
stops being independently testable and starts drifting toward whatever that page
happens to need. Two clients keep it honest. `src/ide/` should stay deliberately
plain, and should never grow a feature the panes do not need.

**Two backends, and no proxy.** LE2's editor talks to `/leapi` on :3050; ours
talks to `/lpsapi` on :3060. For an LE document with target `lps` the editor
needs both: LE2 to parse, LPS(2) to run. The editor holds two base URLs and
picks by language mode and declared target. Do not proxy LPS operations through
`/leapi` — it couples the deployments and puts LE2 in the business of forwarding
a growing operation set it does not understand.

The flow for one keystroke-settled edit of an LPS-LE document:

```
editor ──POST /leapi  {operation:"load", …}──▶ LE2
       ◀── { internal, provenance, diagnostics } ──
editor ──POST /lpsapi {operation:"compile", syntax:"internal",
                       source: internal, provenance}──▶ LPS(2)
       ◀── { ok, diagnostics } ──
       … then "run", "timeline", "changes", "scene", "explain" as today
```

---

## 4. Concrete changes, by repository

### In LE2

1. **`le_lps.pl`** — the LPS target module, beside `le_scasp.pl`. Consumes the
   parsed structures, emits internal-syntax text plus a provenance list.
2. **`the target language is: lps.`** accepted, and dispatching.
3. **`the actions are:`** — a new declaration section. LE2 has `the fluents
   are:` and `the event predicates are:`, but LPS distinguishes *actions* (which
   the agent performs, and whose preconditions are checked) from *events* (which
   happen to it). This distinction is load-bearing in the engine and cannot be
   inferred. The specimens already use `the actions are:`.
4. **`the prolog events are:`** — likewise, for polled Prolog-defined events.
5. **`initially:`** — the initial state.
6. **Timed observations.** Reuse the scenario machinery with an interval:
   `miguel inputs rock and 1000 from 1 to 2.`
7. **Reactive rules**: `When … then …` and `If … then …`.
8. **Causal laws**: `initiate …` / `terminate …` in a consequent, and the
   `… that is a number becomes …` update form.
9. **Integrity constraints**: `It must not be true that …`, including the
   prospective form, which is the one construct with no specimen and no
   obvious English rendering (§6).
10. **Goals**: `the goal is that …` → `achieve`.
11. **An LE writer** for the round trip (§I.9.5). LE2 owns the template
    dictionary, so it owns the only invertible mapping; `dump_le` has to live
    there.
12. **Editor**: a `lps` language mode; two-backend wiring; the four LPS panes.

### In LPS(2)

1. **`t(Term, src(File,Line,Col,Kind))`** accepted alongside `t(Term, Line)` —
   the two-line change in §1.
2. **`/lpsapi` `compile`** accepts `syntax: "internal"` with a `provenance`
   list.
3. **`.lps`** recognised as the canonical external extension; `.lpsw` as the
   canonical internal one. `.pl` and `_.P` stay accepted.
4. **`./lps run foo.le`** — reads the declaration, and either shells out to a
   configured LE2 endpoint or refuses with a clear message. It must not
   silently guess.
5. **A `docs/le_lps_interface.md`** in both repositories, version-stamped,
   listing the internal term set and the provenance schema. This is the
   contract; it should be short enough to read in one sitting and changed only
   deliberately.
6. **`src/ide/` gains a `lps`-mode reference**, and stays minimal.

---

## 5. The escape hatch: mixed documents

`RockPaperScissors-Minimal-en.pl` puts formal LPS clauses *after* the `en("…")`
block, with a comment explaining that they complement it. Two constructs there —
an aggregate and a time-variable binding — were commented out as buggy in
English and written in Prolog instead.

That is §I.9.6's scope limit made concrete, and it should be designed for rather
than tolerated. Two options:

- **(i) An LE section that carries formal LPS**, e.g. `the LPS clauses are:`
  followed by an indented block passed through verbatim. Keeps one file.
- **(ii) A companion file.** `foo.le` plus `foo.lps`, compiled together.

**Recommendation: (ii), and only (ii) initially.** LE2 already has to sandbox
embedded Prolog goals (`library(sandbox)`); an escape block that can introduce
arbitrary clauses is a larger surface than that, and it makes the document's
meaning depend on a syntax the LE editor cannot check. A companion file gets the
right editor mode, the right diagnostics, and an obvious place to put the
Prolog escapes that §I.9.6 says will exist. Revisit (i) only if authors turn out
to resent the second file.

---

## 6. The one genuinely open problem

**The prospective form.** From `prospectiveGoat.pl`:

```prolog
false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

`row(_,_) to T` anchors `T` to the state *resulting from* a crossing, so the
constraint is about a state that does not exist yet and is defined by the action
under consideration. No specimen renders this, and it does not obviously fall
out of any of the constructs above.

Candidate renderings, none yet endorsed:

```
It must never be the case, after a crossing, that
    the goat is at a place and the wolf is at the place
    and the farmer is not at the place.

Crossing from a place to another place is not allowed if it would result in
    the goat being at a place and the wolf being at the place and …
```

This is exactly why §I.9.4 says to hand-write the examples before the grammar,
and why `prospectiveGoat.pl` is named there. It stays the acceptance test for
the surface language: **if the prospective form has no natural English
rendering, the LE layer covers a strictly smaller language than LPS, and we say
so in §I.9.6 rather than inventing something unreadable.**

---

## 7. Milestones

M8 as a single milestone is too big to gate. Split:

| | what | gate |
|---|---|---|
| **M8a** | The joint interface. `t(Term, Src)`; `/lpsapi compile` from internal text + provenance; `.lps`/`.lpsw` extensions; `docs/le_lps_interface.md` in both repos. No grammar work. | LPS(2) runs a program handed to it as internal text + provenance, and reports a diagnostic at an `.le` line and column |
| **M8b** | The surface language, on paper. Hand-write ~15 LE programs, starting from the three specimens re-expressed in LE2 idiom. Reviewed by someone who does not know LPS. | Every construct in the 15 has a written internal-form mapping; the prospective form is either rendered or declared out of scope |
| **M8c** | The grammar, in LE2. `le_lps.pl`; `the actions are:`; `initially:`; timed observations; `When…then`; `It must not be true that`. | The 15 parse, and their internal form is `variant/2`-equal to the hand-written expectation |
| **M8d** | Round trip and corpus. The LE writer; `LE → internal → LE` and `legacy → internal → LE → internal`; the documented expressible subset. | A stated set of corpus programs round-trips; the excluded set is listed with reasons |
| **M8e** | Editors. The `lps` Monaco mode; the four LPS panes in LE2's editor; two-backend wiring. | Playwright drives both modes and both backends, with no console errors — the same bar `tools/ide_screenshots.cjs` sets today |

M8a is worth doing first and separately: it is small, it is entirely on our side
of the fence except for one document, and it unblocks LE2 from being able to
*try* emitting LPS before any of the grammar is settled.

The 15 for M8b, chosen for construct coverage rather than size — the first three
already exist in English:

```
RockPaperScissors-Minimal-en   the specimen: events, actions, fluents, updates, denials
RockPaperScissorsBaseEN        the specimen: aggregates, initiate, ordinals
RockPaperScissorsEthereumFEn   the specimen: prolog events, composite events, l_int
goat.pl                        composite events, recursive decomposition
prospectiveGoat.pl             the prospective form — the acceptance test
goat_declarative.pl            achieve, planning mode
badlight.pl                    display/2, a visual mapping
bankTransfer.pl                the canonical "contract" shape
diningPhilosophers.pl          concurrent actions, preconditions over action sets
fireSimple.pl                  the smallest interesting reactive rule
mapColouring.pl                timeless-heavy, little state
loanAgreementPostConditions.pl real-time, dates, a legal text behind it
Escrow.pl                      multi-party, obligations
deliveryDelay.pl               deadlines and elapsed time
life.pl                        intensional fluents over a grid — the stress case
```

---

## 8. What I have not verified

- **LE2's actual output terms.** I read `docs/le_summary.md`, `docs/api.md`,
  `docs/le_syntax.md` and `docs/editorSummary.md` from GitHub, not
  `le_grammar.pl` itself. The term shapes named there — `le_dict/1`,
  `le_source_element/3`, `le_source_info/4`, `scenario/2`, `query_info/3` —
  are what a target module would consume, but I have not confirmed their
  arguments or that they are the right seam for `le_lps.pl` to attach to.
- **Whether `le_scasp.pl` is genuinely a target module** in the sense §1
  assumes, or something more entangled. The recommendation to model `le_lps.pl`
  on it rests on the file's name and the documented `the target language is:`
  mechanism.
- **What the abandoned LE1→LPS translator was**, and whether any of it survives
  anywhere. The specimens' bug comments imply it ran; nothing in
  `legacy_lps1/` reads `en/1`, so it was in the SWISH layer or an external
  service.
- **The editor's build.** Whether adding a second Monaco language mode is as
  local a change as `editor/src/le-language.ts` being one file suggests.

The first two are the ones that could move the recommendation, and both are
answered by half an hour in the LE2 repository once I have it.
