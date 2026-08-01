# LPS + LLM — a multi-part plan

**Status:** Part I is a working plan. Part II is a design draft to be revised once Part I lands. Part III is preliminary.

This supersedes the earlier memo (archived as `LPSplusLLM_v1_memo.md`). The architectural argument is retained in condensed form as Appendix A; the body is a build plan.

Before writing this I read the actual sources rather than working from memory: the `lps_corner` engine (via the `logicmoo/logicmoo_lps` GitHub mirror, since Bitbucket blocks automated access), its `examples/` corpus and `.lpst` test files, and the Logical English 2 repository with its `docs/`. Findings that changed the plan are marked **[verified]**; things I could not check are marked **[assumption]**.

---

## Table of contents

- [Part 0 — What I found in the existing system](#part-0--what-i-found-in-the-existing-system-and-why-it-reshapes-the-plan)
  - [0.1 The engine is smaller than its reputation](#01-the-engine-is-smaller-than-its-reputation)
  - [0.2 The conformance contract is stricter than "implement KELPS correctly"](#02-the-conformance-contract-is-stricter-than-implement-kelps-correctly)
  - [0.3 The cycle, as actually implemented](#03-the-cycle-as-actually-implemented)
  - [0.4 Logical English 2 gives us more scaffolding than expected](#04-logical-english-2-gives-us-more-scaffolding-than-expected)
  - [0.5 The goat examples, and what is actually missing](#05-the-goat-examples-and-what-is-actually-missing)
- [Part I — Reimplementing LPS in SWI-Prolog](#part-i--reimplementing-lps-in-swi-prolog)
  - [I.0 Objectives and non-goals](#i0-objectives-and-non-goals)
  - [I.1 Managing the conformance obligation](#i1-managing-the-conformance-obligation)
  - [I.2 Architecture](#i2-architecture)
  - [I.3 The internal representation](#i3-the-internal-representation)
  - [I.4 External syntax 1 — legacy LPS](#i4-external-syntax-1--legacy-lps)
  - [I.5 The cycle engine](#i5-the-cycle-engine)
  - [I.6 The state store and hypothetical worlds](#i6-the-state-store-and-hypothetical-worlds)
  - [I.7 Declarative planning mode](#i7-declarative-planning-mode)
  - [I.8 CLI and web endpoint](#i8-cli-and-web-endpoint)
  - [I.9 External syntax 2 — Logical English for LPS](#i9-external-syntax-2--logical-english-for-lps)
  - [I.10 IDE and tooling](#i10-ide-and-tooling)
  - [I.11 Milestones](#i11-milestones)
- [Part II — The agent](#part-ii--the-agent-draft-to-be-revised-after-part-i)
  - [II.1 What Part I changes](#ii1-what-part-i-changes)
  - [II.2 Revised LLM interface](#ii2-revised-llm-interface)
  - [II.3 Safety properties](#ii3-safety-properties-unchanged-now-enforceable)
  - [II.4 Open questions for after Part I](#ii4-open-questions-for-after-part-i)
- [Part III — Deployment surfaces](#part-iii--deployment-surfaces-preliminary)
- [Part IV — Supporting other agent languages](#part-iv--supporting-other-agent-languages-preliminary)
  - [IV.0 The interface already exists](#iv0-the-interface-already-exists--part-iv-is-front-ends-not-engine-work)
  - [IV.1 The universal caveat: procedural leaves](#iv1-the-universal-caveat-procedural-leaves)
  - [IV.2 The five targets](#iv2-the-five-targets)
  - [IV.3 Deliberately excluded](#iv3-deliberately-excluded)
  - [IV.4 Sequencing](#iv4-sequencing)
  - [IV.5 Risks and open questions](#iv5-risks-and-open-questions)
- [Part V — Supporting industrial applications](#part-v--supporting-industrial-applications-preliminary)
  - [V.0 Why industrial control is the right target](#v0-why-industrial-control-is-the-right-target)
  - [V.1 Targets](#v1-targets)
  - [V.2 The mapping](#v2-the-mapping)
  - [V.3 The generatable subset](#v3-the-generatable-subset)
  - [V.4 The two-tier architecture](#v4-the-two-tier-architecture)
  - [V.5 The correctness argument](#v5-the-correctness-argument)
  - [V.6 Certification — the commercial case and its price](#v6-certification--the-commercial-case-and-its-price)
  - [V.7 Drilling as the beachhead](#v7-drilling-as-the-beachhead)
  - [V.8 Milestones](#v8-milestones)
  - [V.9 Risks](#v9-risks)
- [Appendix A — The architectural argument, condensed](#appendix-a--the-architectural-argument-condensed)
- [Appendix B — The re-instrumented cycle](#appendix-b--the-re-instrumented-cycle)
- [Appendix C — Worked example: approval gate](#appendix-c--worked-example-approval-gate-on-destructive-actions)
- [Appendix D — Sources consulted](#appendix-d--sources-consulted)

---

## Part 0 — What I found in the existing system, and why it reshapes the plan

### 0.1 The engine is smaller than its reputation

**[verified]** The core we must replace is roughly:

| File | LOC | Role |
|---|---|---|
| `engine/interpreter.P` | 3,544 | cycle, resolution, state update, test harness, server hooks |
| `utils/psyntax.P` | 904 | external↔internal syntax translation, `dump/0` |
| `prolog/dialect/lps.pl` | 357 | `expects_dialect(lps)` operator table and term expansion |
| `engine/db.P` | ~200 | state storage |

~5k lines of Prolog. The risk is not volume, it is *behavioural fidelity* (§0.2) plus the fact that concerns are heavily interleaved — `interpreter.P` contains SWISH hooks, thread management, server plumbing and the test harness all inline.

**[verified]** Thread usage: 48 `thread_*` references, but clustered around lines ~2650–2700 and the background-execution paths — the *server/query-answering layer*, not the cycle. `nb_setval`/`b_setval`: zero. Tabling: 3 occurrences. So the core cycle is already essentially single-threaded and side-effect-light. That makes the pure-core architecture of §I.2 a disentangling job rather than a rewrite, and it is what keeps the WASM option cheap to preserve (§I.0, note 2).

**[verified]** There is a module-indirection layer (`u_call/1`, `u_call_lps/2`, `uassert`, `uretractall`) that lets one engine serve multiple program modules under SWISH. It is the ancestor of the multi-program/multi-session requirement, but it conflates *program* (immutable clauses) with *session* (mutable state) — both live in the same dynamically-selected module. Splitting these is the highest-leverage architectural change in Part I (§I.2.1).

### 0.2 The conformance contract is stricter than "implement KELPS correctly"

This finding most affects the plan, so it gets its own section.

**[verified]** A `.lpst` file is a Prolog fact file:

```prolog
:- dynamic lps_test_result/3, lps_test_result_item/3,
           lps_test_action_ancestor/3, lps_test_options/1.

lps_test_options([dc]).

% lps_test_result(Stage, Cycle, Count)
lps_test_result(fluents, 0, 4).
lps_test_result(events, 2, 2).
lps_test_result(composites, 2, 5).

% lps_test_result_item(Stage, Cycle, Term)
lps_test_result_item(fluents, 0, loc(wolf,south)).
lps_test_result_item(events, 2, row(south,north)).
lps_test_result_item(composites, 2, happens(dealWithGoat(south,north),1,2)).
```

Three stages are recorded and checked: `fluents` (including cycle 0, the initial state), `events` (what occurred from the previous cycle to this one), and `composites` (macro-events as `happens(E,T1,T2)`). `lps_test_action_ancestor/3` is *recorded but explicitly not used for testing* — note this, it matters in §I.10.5.

**[verified]** The comparison is:

```prolog
test_items_ok(Actual, Test) :- sort(Actual, A), sort(Test, T), variant(A, T).
```

preceded by a `length(Term, N)` check against the recorded count. Consequences, precisely:

- **Order within a cycle is free** — both sides are sorted.
- **The item count must match exactly** — `length/2` runs on the unsorted actual list against the recorded `N`.
- **Terms must match up to variable renaming only** (`variant/2`) — not unification, not subsumption. A different but semantically equivalent term fails.
- **Cycle alignment is exact.** Stage/Cycle is the lookup key; producing the right actions one cycle late is a failure.
- **Escape hatch:** items with term size > 1000 are stored as `lps_gigantic(Size)` and matched on recomputed size only. A few tests are therefore weakly checked.
- **Failure is itself recorded:** a failed program carries `lps_test_result_item(end,-1,failure)`, and `run_test` checks the success/failure status agrees. Programs that are *supposed* to fail must fail.

**The implication.** For any program with genuine nondeterminism — several actions equally eligible, several clauses able to reduce a goal — the `.lpst` records *the choice the 2021-era engine happened to make*. Passing requires reproducing that choice: source clause order, `findall/3` solution order, the goal-queue discipline (**[verified]**: `append(Gi, NewGi, NGi)  % Puts new goals at the end of the queue`), and the `tried/3` bookkeeping that suppresses retries.

This is **trace equivalence, not semantic equivalence** — a much stronger obligation, and the main technical risk in Part I. §I.1 manages it rather than being surprised by it.

**[verified]** Scale: the GitHub mirror carries 109 `.lpst` files and 161 example `.pl` files, with 63 dedicated cases under `examples/forTesting/`. Upstream Bitbucket may carry more. Tests run via `interpreter:test_examples_dc` — i.e. **with the `dc` option**, which selects the alternative resolution implementation (`dc_process/5`, `dc_resolve_goals/2`). **[verified]** `dc` is also a prerequisite for prospective/next-state features (`'prospective option requires dc'`). Conclusion: *the `dc` path is the only path worth reimplementing.* The legacy non-`dc` resolution can be dropped.

### 0.3 The cycle, as actually implemented

**[verified]** From `cycle/4` (~lines 2232–2360), one cycle at time `T`:

1. Optional pause / cycle-hook / external observations gathered.
2. `Actions = findall(A, happens(A, T-1, T))` — what actually occurred.
3. **`test(events, T, Actions)`**
4. `updateFluents(T)` — apply event effects to state.
5. `dc_process(Ri, [], NRi, [], NewGi_)` — fire reactive-rule antecedents, producing new goals.
6. `split_goals_and_events(NewGi_, NewGi, CompositeEvents)`.
7. **`test(composites, T, CompositeEvents)`** (when non-empty), then `updateNextStateFluents`, `copyNextState`.
8. Collect state fluents (plus `sample(Templates)` intensional fluents if requested).
9. **`test(fluents, T, Fluents)`**
10. `resolveAndUpdate` — resolve goals depth-first, select candidate actions, check preconditions (`d_pre`), commit.
11. `updateEvents(T, T+1, ...)` — post committed actions as next cycle's events; integrity violations reject events and *backtrack into Prolog choicepoints*.

Note that precondition violations at step 10 can backtrack all the way into step 11's event insertion. That cross-phase backtracking is observable semantics and must be preserved.

### 0.4 Logical English 2 gives us more scaffolding than expected

**[verified]** LE2 already parses `the fluents are:` and `the events are:` sections (`le_grammar.pl:158–159, 327–334, 1532–1533`) — they declare templates into dedicated dictionaries. But there is **no** reactive-rule syntax, no `initiates`/`terminates`, no temporal integrity constraints, no notion of a cycle. So the LPS/LE syntax is genuinely new work landing on existing scaffolding: templates with typed `*variable*` slots, synonyms, `opposite`, prepositional chaining, abducibles (`; unknown`), scenarios with expectations, ontology/taxonomy, aggregates.

**[verified]** The LE2 editor is Monaco plus an LSP server running in a browser-side Web Worker (`editor/src/client.ts`, `server.ts`, `le-language.ts`, `tokenizer.ts`), talking to a SWI-Prolog HTTP backend (`classic_web_api.pl`) exposing a **single POST `/leapi`** dispatching on an `operation` field, token auth, port 3050. It already has semantic-token highlighting driven by extracted templates, folding, completions, hover, and quick fixes. Content changes are debounced 1500 ms before triggering a server-side module reload — a pattern we inherit (§I.10.1).

**[verified]** `docs/api.md` documents a `load` operation creating "a fresh session module", an `explain` operation returning explanation-tree nodes, `is_a_hierarchy`, `graph`, and MCP/REST tool endpoints. `docs/sCASP_plan.md` anticipates `swipl-wasm` with an engine toggle — useful precedent if and when we revisit WASM.

### 0.5 The goat examples, and what is actually missing

**[verified]** `examples/goat.pl` encodes wolf/goat/cabbage as hand-written case analysis: six `dealWithGoat/2` clauses enumerating which item to ferry when, plus `makeLoc` macro-events sequencing `row` and `transport`. The declarative content — that the goat cannot be left with the wolf or the cabbage — never appears as a constraint; it has been *compiled by hand* into the case analysis.

**[verified] But the corpus already contains a much more declarative version.** `examples/forTesting/prospectiveGoat.pl` (with its own `.lpst`, so it is in the conformance corpus) drops the `dealWithGoat` case analysis entirely and states the puzzle constraints directly, in **existing** LPS syntax:

```prolog
false loc(goat,L) at T, loc(wolf,L) at T,    not loc(farmer,L) at T, row(_,_) to T.
false loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

The `row(_,_) to T` literal anchors `T` to the state *resulting from* a crossing — this is the prospective feature, and it is why prospective requires `dc`. It also uses the concise `updates L1 to L2 in loc(...)` form for causal laws instead of `initiates`/`terminates` pairs.

**This substantially narrows what §I.7 must add.** State constraints, including next-state ones, are already expressible. Preconditions are already denials (`d_pre/1` is literally documented as *"action preconditions (as denials)"*). What remains imperative in `prospectiveGoat.pl` is only the recursive `makeLoc` decomposition — three generic clauses describing *how* to get an object across. That residue, and only that, is what a planner replaces. See §I.7.

---

## Part I — Reimplementing LPS in SWI-Prolog

### I.0 Objectives and non-goals

**Objectives.**

1. A clean-room LPS engine in SWI-Prolog passing the existing `.lpst` corpus.
2. A **pure core**: all computation in a side-effect-free layer, with I/O only at the edges. This is justified independently by testability, deterministic replay, session forking and multi-session support. As a by-product it keeps the core close to WASM-loadable — a property we preserve cheaply now and cash in later if we choose (see *WASM* below).
3. Usable from the Prolog CLI and from a simple HTTP endpoint supporting multiple programs and sessions.
4. Two external syntaxes — legacy LPS (directly Prolog-readable, as today) and a new Logical-English-based one — over one internal representation.
5. Optional hypothetical/lookahead states, enabling a declarative planning mode.
6. A Monaco-based IDE with timeline and state-change visualisation, animation, and explanations improving on `why/1`.

**WASM — deferred, not designed for.** WASM is treated as **one deployment alternative among several, revisited after M9**, not as an architectural constraint. Concretely: the HTTP layer and other edges may use threads freely; no milestone before M11 carries a WASM gate; and no design decision is justified by WASM alone. What we *do* keep is a cheap guard — a CI assertion that the core package declares no thread, socket, HTTP or foreign dependencies (§I.2.4). That is roughly one line of configuration and is ~90% just good layering. The reason to keep it rather than "make it WASM-compatible later" is that the retrofit cost is an order of magnitude higher once something has crept in, and the guard costs nothing now.

**Non-goals (explicitly dropped).** SWISH dependency; the Ethereum/smart-contract experiments; the old multi-session server; the non-`dc` resolution path; the old 2D animation prototype (superseded by §I.10.4); `lps.js` compatibility.

**Ordering constraint from the brief.** The system must run with legacy external syntax + internal syntax *before* Logical English is started. LE work is gated behind Milestone M4.

**Zero LLM involvement in Part I.** Nothing here calls a model. The LE parser is a grammar, not a model.

### I.1 Managing the conformance obligation

Given §0.2, conformance must be engineered deliberately.

**I.1.1 Build the harness before the engine.** M0 is a test runner *independent of both engines*: reads a `.lpst`, runs a program through an engine adapter, compares using exactly the upstream semantics (count check, `sort`+`variant`, `lps_gigantic` size-only check, `end/-1/failure` status). Adapters for (a) the legacy engine and (b) the new one. This gives a comparable pass/fail number from day one and prevents the classic failure of discovering trace divergence at 80% completion.

**I.1.2 Classify the corpus.** Run every example under the legacy engine with perturbations that *should* be semantically neutral but expose choice-sensitivity: reorder source clauses; reverse `findall` order at selection points; permute the goal queue. Each test lands in a bucket:

- **Bucket A — semantically forced.** Invariant under all perturbations. Conformance here is real correctness. Expect the majority.
- **Bucket B — choice-sensitive but strategy-determined.** Output changes under perturbation but is predictable from a stated selection rule. Conformance requires implementing that rule.
- **Bucket C — genuinely arbitrary.** Depends on incidental details (standard order of terms, hash iteration, historical accident). Needs a compatibility shim or a decision to regenerate.

**I.1.3 Publish a selection-strategy specification.** Bucket B forces us to write down, for the first time: clause-selection order for `l_int/2`, `l_events/2` and reactive rules; goal-queue discipline (append-at-end, **[verified]**); the `tried/3` suppression rule; action-commitment order within a cycle; and the backtracking discipline when a precondition or integrity constraint fails. This spec is a deliverable in its own right — it is what the original codebase never had, and what makes any future reimplementation (in another language, say) possible.

**I.1.4 Two conformance modes.** `legacy_trace` reproduces bucket-B choices exactly; `canonical` uses a cleaner documented strategy that may diverge on B/C. Default for the suite: `legacy_trace`. Default for new programs: `canonical`. It's a language directive, not a build flag, so a legacy file can carry `:- lps_compat(legacy_trace).`

**I.1.5 Acceptance gate.** M4 = 100% of buckets A and B pass in `legacy_trace`; every bucket-C test either passes or has a written, reviewed justification and a regenerated `.lpst`. If C exceeds ~5% of the corpus, that signals the selection spec needs rework rather than mass regeneration.

**Risk.** If C is large, the schedule slips substantially. Mitigation: I.1.2 runs in M0, *before any engine code*, so the number is known early.

### I.2 Architecture

Organising principle: a **pure core with I/O only at the edges** — what testability, deterministic replay, multi-session and hypothetical worlds all require, and incidentally what keeps the WASM option open.

```
┌──────────────────────────────────────────────────────────┐
│ Edges (I/O, threads, HTTP, clock — all permitted here)   │
│  lps_cli.pl · lps_http.pl · lps_lsp.pl · adapters        │
└───────────────────────┬──────────────────────────────────┘
                        │  session API (pure terms)
┌───────────────────────▼──────────────────────────────────┐
│ Core (no I/O, no threads, no clock, no foreign)          │
│  ┌────────────┐  ┌────────────┐  ┌───────────────────┐   │
│  │ syntax     │  │ program    │  │ session           │   │
│  │  legacy ─┐ │  │ (immutable)│  │ (mutable state)   │   │
│  │  LE     ─┴─┼─►│  compiled  │◄─┤ state · goals ·   │   │
│  │            │  │  clauses   │  │ cycle · trace     │   │
│  └────────────┘  └────────────┘  └───────────────────┘   │
│  ┌──────────────────────────────────────────────────┐    │
│  │ cycle engine · resolution · state store · planner│    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

**I.2.1 Program/session split.** The decisive change. A *program* is the compiled immutable result of parsing — reactive rules, intensional-fluent clauses, composite-event clauses, timeless clauses, causal laws, declarations — compiled once into a module (`lps_prog_<hash>`) and shared freely. A *session* is a first-class term holding everything mutable: current state, goal queue, reactive-rule instances, cycle number, event queue, trace. Many sessions may share one program.

This buys, in one move: multi-session on CLI and web; cheap session forking (the basis of hypothetical worlds, §I.6); deterministic replay; and testability — a session is a value you can print, diff, and save.

**I.2.2 The core API.** Everything above the core is expressed in terms of:

```prolog
lps_compile(+Source, +Syntax, +Options, -Program, -Diagnostics)
lps_session_new(+Program, +Options, -Session)
lps_session_observe(+Session0, +Events, -Session)     % inject external events
lps_session_step(+Session0, -Session, -CycleReport)   % exactly one cycle
lps_session_run(+Session0, +StopCond, -Session, -Trace)
lps_session_state(+Session, -Fluents)
lps_session_fork(+Session, -Session2)                 % O(1); §I.6
lps_session_explain(+Session, +Item, -Explanation)    % §I.10.5
```

`lps_session_step/3` is the heart: one cycle, no I/O, fully deterministic given session and injected events. The CLI, HTTP endpoint, IDE, planner, and eventually the agent's control loop are all just callers of this function.

**I.2.3 Time is injected, never read.** The current engine consults the system clock (`get_time/1`, `simulatedRealTimeBeginning`) inside the cycle. In the new core, wall-clock time enters only as a caller-supplied event.

The primary justification is conformance, not portability: §0.2 demands exact cycle alignment against a golden trace, and an engine that reads the clock inside the cycle cannot be deterministically replayed. Secondary benefits: testability, and lookahead (a hypothetical world has no wall-clock).

**I.2.4 Core purity, enforced mechanically.** The core is a package with a CI lint failing the build on references to `thread_*`, `message_queue_*`, `mutex_*`, HTTP libraries, sockets, `process_create`, `shell`, `get_time`, or foreign predicates. **[verified]** the current engine core is already free of `nb_setval`/`b_setval` and nearly free of tabling, so this is enforceable rather than aspirational.

Note this is a rule about the *core package only*. Edges may use anything: the HTTP server may be threaded, the CLI may read the clock, adapters may call foreign libraries. The lint exists to keep the boundary honest — and, as a side effect, to keep the WASM option alive at zero ongoing cost.

**I.2.5 Error and diagnostic model.** Compile-time diagnostics are structured terms (`diag(Severity, Code, Position, Message, Fixes)`), not printed text — the LSP needs positions and quick-fixes, the CLI needs to render them. A deliberate departure from the current `print_error/2` style, designed in from M1 rather than retrofitted.

### I.3 The internal representation

**[verified]** The existing internal vocabulary, which we keep (the brief says internal syntax stays as-is, cf. `dump/0`):

| Predicate | Meaning |
|---|---|
| `reactive_rule(Antecedent, Consequent)` / `/3` | maintenance goals |
| `l_int(Fluent, Body)` | intensional (derived) fluent definitions |
| `l_events(happens(E,T1,T2), Body)` | composite event / macro-action definitions |
| `l_timeless(Head, Body)` | ordinary timeless clauses |
| `d_pre(Conditions)` | action preconditions (as denials) |
| `initiated(...)`, `terminated(...)` | causal laws |
| `happens(Event, T1, T2)` | event occurrence |
| `state(Fluent)`, `next_state(Fluent)` | current / next state |
| `fluent/1`, `action_/1`, `event_/1`, `intensional/1`, `macroaction/1`, `d_event/1` | declarations |
| `observe(Events, Time)` | scheduled observations |

**[verified]** `dump/0` is `psyntax:dumploaded(false, lps2p)`; `dumplps/0` dumps surface syntax. Keep both; add `dump_le/0` once §I.9 exists — the three-way round-trip (legacy ↔ internal ↔ LE) is itself a strong test.

**Changes.** Only two, both additive, both required later:

1. **Provenance on every clause.** Each internal clause carries `src(FileOrBuffer, Line, Col, SyntaxKind)`. Needed by the LSP (jump-to-definition, diagnostics), by explanations (§I.10.5), and by the LE round-trip. Stored in a side table keyed by clause ID, so `dump/0` output is unchanged.
2. **State handles.** `state/1` becomes relative to a world handle (§I.6). For the trunk world its behaviour is preserved exactly, so `dump/0` and all legacy paths see no difference.

### I.4 External syntax 1 — legacy LPS

**Requirement:** unchanged, and parseable directly by Prolog as today.

**[verified]** The mechanism is `:- expects_dialect(lps)` plus an operator table and term expansion in `prolog/dialect/lps.pl`. The operators carry the surface syntax: `at`, `from`/`to`, `if`/`then`, `initiates`/`terminates`/`updates`, `initially`, `false`, `observe`, `fluents`, `actions`, `events`, `maxTime`.

**Approach.** Re-derive the operator table from the legacy dialect file, then write a fresh term-expansion layer producing the §I.3 internal form with provenance. This is deliberately *not* clean-room — the operator table is an interface specification, and diverging from it breaks the requirement. The clean-room boundary is the engine, not the operator declarations.

**Subtleties to handle explicitly** — each a known divergence source:

- **External extensional fluents / external basic actions.** **[verified from the upstream wiki]** if `F at T` has no fluent declaration but `F` is a defined Prolog predicate, it is treated as an *external extensional fluent*; likewise `A from T1 to T2` becomes an *external basic action*. Always called via `findall`, so multiple bindings spawn parallel goals. Easy to miss; several tests depend on it.
- **Composite events in post-conditions** (`examples/compositeEventsInPostConditions.pl`).
- **Fluent change inside an antecedent** (`examples/changingFluentInAntecedent.pl`) — a known ordering trap.
- **`observe` scheduling** and its interaction with integrity-constraint rejection.
- **The prospective/next-state form** — `false ... at T, Action to T` (§0.5), which requires `dc` and is load-bearing for §I.7.
- **The `updates X to Y in Fluent` form** for causal laws, used by `prospectiveGoat.pl`.

Each gets a dedicated conformance test *before* the corresponding engine feature is written.

### I.5 The cycle engine

Implement §0.3's phase order exactly. Where the new implementation should differ internally while preserving observable behaviour:

**I.5.1 Explicit phase functions.** Each phase becomes a pure `Session0 → Session`, with the cycle a fold over the phase list. The current implementation is one large clause with test hooks inline; separating phases makes each independently testable and makes the `CycleReport` (what the IDE and agent consume) a natural by-product rather than a side channel.

**I.5.2 Test hooks become trace emission.** Rather than calling `test/3` inline, each phase emits typed trace records into the session; the conformance harness compares the trace against the `.lpst`. Same information, but the engine no longer knows what a test is, and the trace is available for the timeline UI, explanations and the agent's audit log at no extra cost. Strictly better than the current design, where the trace exists only when `make_test`/`run_test` is on.

**I.5.3 Resolution.** Port the `dc` strategy (`dc_process/5`, `dc_resolve_goals/2`): depth-first resolution of the goal tree, suspension on unresolved composite events (`l_events_disjunction`) and intensional fluents (`l_ints_disjunction`), action selection with precondition checks, commitment. Preserve goal-queue append-at-end **[verified]**, `tried/3` suppression, and the cross-phase backtracking of §0.3. This is where bucket-B fidelity is won or lost, and it should be written *against the selection spec from §I.1.3* rather than by transliterating the old code — otherwise we inherit the accidents along with the essentials.

**I.5.4 Integrity constraints.** `false C1, ..., Cn` is general: its conditions may mention actions, fluents at the current state, or fluents at the *next* state via the prospective form (§0.5). All of this semantics is preserved unchanged. §I.7 adds **no new constraint construct** — the planner consumes the same `false` clauses the reactive engine does.

**I.5.5 Termination and `maxTime`.** Preserve `lps_terminate(Cause)` handling and the "future killers" optimisation (conditions doomed to fail on temporal grounds) — the latter affects how many cycles run, hence trace length.

### I.6 The state store and hypothetical worlds

**The problem.** The current store is destructive: `state/1` and `next_state/1` with `copyNextState`. Efficient, fine for one timeline, useless for lookahead — there is exactly one present.

Note that LPS already has *one-step* lookahead: prospective constraints (§0.5) reject an action because of the state it would produce. §I.6 generalises that from one step to *n*.

**The design.** Replace the flat dynamic predicate with an addressable, persistent store.

- A **world** is an immutable value: a persistent map from fluent key (functor/arity) to a sorted set of ground fluent terms. Implementation: `library(rbtrees)` or a hand-rolled trie. Updates are O(log n) and *share structure* with the parent, so forking is O(1) and a lookahead tree of depth *d*, branching *b* costs O(b·d·log n) rather than O(b^d·n).
- A **session** holds a current world handle plus its parent chain.
- `lps_session_fork/2` becomes trivially cheap, which is what makes §I.7 viable.

**The performance objection, and the answer.** Dynamic-predicate lookup with first-argument indexing is hard to beat on the hot path (`holds/2` on the trunk); persistent maps will be slower per query. Mitigation: a **materialised trunk** — the committed linear timeline keeps the fast destructive representation exactly as today, while hypothetical branches use the persistent one. One interface, two backends, switching on fork. Legacy programs never fork, so they pay nothing, which also protects conformance timings.

**[assumption]** I have not benchmarked this. The crossover where persistent-everywhere would be simpler than a dual design is unknown and worth measuring at M5. If the persistent backend lands within ~2× on the corpus, drop the dual backend for simplicity.

**Semantics to pin down.** What does observing an external event mean in a hypothetical world? Answer: it doesn't — hypothetical worlds are closed. Only the trunk accepts external observations; lookahead assumes no exogenous events unless the program declares expected ones. This must be documented, because it is the standard place where lookahead silently lies.

### I.7 Declarative planning mode

**Goal.** Let `goat.pl`-class problems be written as constraints plus a goal, with the search performed by the engine.

**I.7.1 What is actually missing — a much smaller gap than it first appears.**

Per §0.5, the corpus already shows that *state constraints* and *preconditions* are expressible in existing LPS syntax. `prospectiveGoat.pl` states the puzzle constraints as ordinary `false` clauses over fluents at the resulting state. And `d_pre/1` is documented as *"action preconditions (as denials)"* — denials **are** the precondition mechanism; there is nothing to add.

What remains imperative in `prospectiveGoat.pl` is the recursive `makeLoc` decomposition: three clauses telling the engine *how* to get an object across. That is goal reduction by hand-written composite events. Replacing it with search is the entire content of this section.

**I.7.2 One new construct, not three.**

An earlier draft of this plan proposed `constraint false ...` (state constraints) and `precondition A if C` alongside `achieve`. Both are dropped:

- **`constraint` — dropped as redundant.** Existing `false` already expresses state constraints, including next-state ones via the prospective form. `prospectiveGoat.pl` is the proof, and it is in the conformance corpus. The planner *consumes* these clauses rather than needing a new form.
- **`precondition` — dropped as a construct.** It is sugar for `false A, not C`. Worth keeping as **pure surface sugar with a desugaring rule** (chiefly for LE, where *"rowing from a place to another place is possible if the farmer is at the place"* is the natural sentence), with zero engine support and no new semantics.
- **`achieve Conjunction` — kept.** The one genuine addition: reduce this fluent conjunction by searching the action theory, rather than by `l_events` clauses written by hand. Under `lps_engine(reactive)` (the default) it is a compile error, so legacy programs cannot accidentally acquire planner semantics.

**This is a significant simplification, and it improves conformance rather than threatening it.** The earlier draft worried that reinterpreting `false` would change legacy meaning. With the planner merely consuming existing `false` clauses, there is no reinterpretation and no risk. The consequence worth stating plainly:

> **Planning is not a dialect. It is a search strategy over unchanged LPS.** Same program, same constraints, same causal laws — the only difference is whether an unreducible goal falls through to hand-written decomposition or to the planner.

**[design decision: we keep 'achieve']** `achieve` could itself be eliminated: write `if true then loc(wolf,north) at T, ...` and have the engine invoke the planner whenever it meets a fluent goal it cannot reduce via `l_events`. That would mean *zero* new syntax. The cost is diagnostics — a mistyped fluent name would silently trigger a planner search instead of raising "no clause for this goal". My inclination is to keep `achieve` purely for that error-reporting value, but it is a judgement call, not a semantic necessity.

**I.7.3 The declarative goat.** Every line except the last is existing syntax; most are verbatim from `prospectiveGoat.pl`.

```prolog
:- lps_engine(planning, [search(bfs), horizon(10)]).

maxTime(10).
actions row(_,_), transport(_,_,_).
fluents loc(_,_).

initially loc(wolf,south), loc(goat,south), loc(cabbage,south), loc(farmer,south).

% causal laws — verbatim from prospectiveGoat.pl
transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

% action interference — verbatim
false transport(O1, L1, L2), transport(O2, L1, L2), O1 \= O2.
false row(south, north), row(north, south).

% puzzle constraints — verbatim (prospective form)
false loc(goat,L) at T, loc(wolf,L) at T,    not loc(farmer,L) at T, row(_,_) to T.
false loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T, row(_,_) to T.

% applicability, replacing the makeLoc decomposition — ordinary denials
false transport(Object, L1, _) from T1 to _,  not loc(farmer, L1) at T1.
false transport(_, L1, L2)     from T1 to T2, not row(L1, L2) from T1 to T2.

% the one new construct
achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

The `makeLoc` machinery is gone, replaced by two denials and one `achieve`.

**[assumption]** I have not run this. The exact form of the two applicability denials — in particular `not row(L1,L2) from T1 to T2` inside a denial — needs checking against the engine's handling of negated action literals. This is the first thing to validate in M6.

**I.7.4 The planner.** Deterministic, fully-observable forward state-space search over the action theory derived from `initiates`/`terminates`/`updates`, with applicability and legality derived from `false` clauses.

*Static classification of `false` clauses* is required, and is the main new analysis work:

| Clause shape | Planner use |
|---|---|
| actions only | prune candidate action *sets* (interference) |
| one action + current-state fluents | applicability test — generate only applicable actions |
| fluents at result state (prospective) | prune successor states |
| mixed / other | fall back to test-and-reject after successor generation |

Getting the second row right is what makes search tractable: generatively filtering applicable actions instead of enumerating all ground instances and rejecting. The fourth row is the correctness backstop — anything the analysis cannot classify is still checked, just less efficiently.

The non-obvious complication: **LPS cycles allow several actions concurrently.** **[verified]** the goat `.lpst` shows `events,2` containing both `row(south,north)` and `transport(goat,south,north)`. So this is not STRIPS. Each search step chooses a *set* of actions that is individually applicable, jointly non-interfering, not excluded by an action-level `false`, and whose resulting state satisfies all prospective constraints. Branching is over subsets, not actions.

Staged approach:

- **Stage 1:** BFS/IDA* over action sets, subset enumeration bounded by a declared maximum concurrency (default unbounded but interference-pruned). Adequate for puzzle scale — which is what the examples are. BFS is complete and optimal in plan length.
- **Stage 2:** add a relaxed-plan heuristic (h^add / h^FF on the delete-relaxation) with greedy best-first, for larger problems. Keep BFS for optimality.
- **Stage 3 (optional):** compile to an external solver. LE2 already contemplates s(CASP) **[verified]**; ASP is a natural target for this problem class and would sharpen the constraint semantics. With WASM deferred (§I.0), a foreign solver dependency is no longer a packaging problem, which makes this materially more attractive than it was.

**I.7.5 Integration with the cycle — the key decision.** The planner does **not** replace the cycle. It runs where `achieve` is reduced, produces an action sequence (a list of action sets, one per cycle), and that sequence is then *executed by the ordinary cycle*, one set per cycle, with normal preconditions and integrity checks applied.

Three benefits: the resulting trace is an ordinary LPS trace, so `.lpst` testing works unchanged for planned programs; execution-time failures (a precondition no longer holds because reality diverged) surface normally and can trigger replanning; and the planner stays a *component*, not a fork of the language.

**I.7.6 Replanning.** Under `lps_engine(planning)`, if a planned action's precondition fails at execution time, the default is to replan from the current state for the remaining `achieve` goals. Directive-controlled: `on_plan_failure(replan | fail | reactive)`. This is what makes the mode useful for the agent in Part II, where the world does diverge.

**I.7.7 Conformance safety.** Both `goat.pl` and `prospectiveGoat.pl` keep their existing `.lpst` files and must keep passing under `lps_engine(reactive)`. The declarative version is a *new* example (`goat_declarative.pl`) with its own generated test. Since this section introduces no new semantics for `false` and no changes to denial handling, the blast radius is limited to programs that use `achieve` — i.e. none of the legacy corpus.

### I.8 CLI and web endpoint

**I.8.1 CLI.** A thin layer over the core API:

```
lps run prog.pl --max-time 20 --trace trace.json
lps test examples/ --mode legacy_trace      # the conformance harness
lps repl prog.pl                            # step, inspect, fork, explain
lps dump prog.pl --syntax internal|legacy|le
```

The REPL is where §I.6 pays off interactively: `fork`, explore, `discard`, return to the trunk.

**I.8.2 HTTP endpoint.** Follow the LE2 pattern **[verified]**: one POST endpoint dispatching on an `operation` field, token auth. Operations:

| Operation | Meaning |
|---|---|
| `compile` | source + syntax → program id + diagnostics |
| `session_new` | program id → session id |
| `observe` | inject events into a session |
| `step` / `run` | advance one/several cycles, return `CycleReport`s |
| `state` | current fluents |
| `fork` / `discard` | hypothetical branches |
| `explain` | explanation tree for an item (§I.10.5) |
| `trace` | full trace for the timeline UI |
| `dump` | any of the three syntaxes |

Sessions are values in a server-side registry keyed by id, with an idle TTL. The server layer is an edge and **may use threads** — background execution for long runs, per-session worker threads, timeouts. The core contract stays synchronous (`lps_session_step/3`), so a single-threaded deployment remains possible without code changes. Cross-session isolation is structural (separate session terms, shared immutable program), not module-based as today.

**I.8.3 Explicitly not rebuilt.** The old server's Ethereum integration and its session model. Per the brief, rebuilt from scratch — and the program/session split (§I.2.1) *is* that rebuild.

### I.9 External syntax 2 — Logical English for LPS

**Gated behind M4.** Started only once the engine passes conformance with legacy syntax.

> **The design for this section is now [`le_lps_design.md`](le_lps_design.md)**, written
> after reading the LE2 repository and after finding that the corpus already contains a
> Logical-English-for-LPS prototype (`RockPaperScissors-Minimal-en.pl`,
> `RockPaperScissorsBaseEN.pl`, `RockPaperScissorsEthereumFEn.pl`, each an `en("…")`
> block, none with a generated `_.P` and none in the conformance corpus). That document
> supersedes I.9.1–I.9.3 on three points and splits M8 into M8a–M8e:
>
> - **What LE2 emits: LPS internal syntax**, as a third target language beside `prolog`
>   and `taxlog` — text plus a provenance list, consumed by `lps_compile/5`'s existing
>   `terms(…)` form. `foo.le` → `foo.le_.lpsw`, exactly as `foo.lps` → `foo.lps_.lpsw`.
> - **I.9.3 is settled by the specimens.** Both elided time (`When a player inputs a
>   choice … then …`) and LE-variable time (`… at a first time`, `from the first time to
>   a second time`) are needed; ordinal steps (`at step 3`) are used nowhere and are
>   dropped. The prospective form remains the one open problem and is the acceptance
>   test for the surface language.
> - **Extensions:** `.le` covers extended LE, selected by `the target language is: lps.`;
>   `.lps` is our non-LE external syntax; `.lpsw` is internal — all three following
>   `psyntax.P:237–260`, which already treats `_.P`/`.lpsw` as internal and `.lps`/`.pl`
>   as external.
>
> The method of I.9.4 and the round-trip test of I.9.5 stand unchanged, and I.9.6's
> scope limit gains a concrete mechanism: a companion `.lps` file rather than an escape
> block, which is what the specimen already does.

**I.9.1 What exists to build on.** **[verified]** LE2 supplies templates with typed `*variable*` slots and head-noun typing; the `; synonym`, `; opposite`, `; prepositional`, `; unknown` (abducible), `; undefined` additions; sections for knowledge base, scenario, query, ontology, templates, **fluents**, **events**, target language; aggregates; taxonomy; scenario expectations (`expects answers [...] and unknowns [...]`); `%` and `/* */` comments.

**I.9.2 What must be added** — the temporal and reactive layer, which LE2 lacks entirely:

- **Reactive rules**, the core construct, in the shape of
  `when a person requests a deletion of a file, then approval for the file is requested and then the file is deleted.`
  with explicit ordering words (`then`, `at the same time`, `within N steps`) mapping onto `from T1 to T2` intervals.
- **Causal laws.** `transporting an object from a place to another place initiates that the object is at the other place.` / `... terminates that ...` / the `updates ... to ... in ...` form.
- **Preconditions** (as sugar, §I.7.2). `rowing from a place to another place is possible if the farmer is at the place.`
- **Integrity constraints.** `it is never the case that the goat is at a place and the wolf is at the place and the farmer is not at the place.` — mapping to plain `false`, including the prospective form, which needs a natural rendering of "at the resulting state".
- **Goals.** `the goal is that the wolf is at north and the goat is at north and ...` → `achieve`.
- **Initial state.** `initially, the wolf is at south and ...`
- **Observations/scenarios.** Reuse LE2's scenario machinery, extended with timing: `at step 3, it rains.`

**I.9.3 The hard part: temporal reference in English.** LPS's `at T` and `from T1 to T2` are explicit; English elides them. The design must decide per construct whether time is (a) implicit, inferred from position in a `then`-chain, (b) named by ordinal (`at step 3`), or (c) named by an LE variable (`at a time`). The prospective form (`... at T, row(_,_) to T`) is the hardest case, since it references a state defined by the action under consideration.

**[assumption]** I expect (a) covers most rules and (c) is needed for genuine temporal constraints — but this needs prototyping against a dozen real examples before the grammar is fixed. Getting it wrong yields a syntax that reads beautifully on tutorial examples and cannot express the corpus.

**I.9.4 Method.** Take ~15 representative programs from `examples/` — including `prospectiveGoat.pl`, precisely because its prospective constraints are the awkward case — hand-write the LE version of each *first*, iterate the surface language with a reader who does not know LPS, and only then write the grammar. The failure mode to avoid is designing upward from the internal representation, which yields English-shaped Prolog.

**I.9.5 Round-trip as the test.** `LE → internal → LE` and `legacy → internal → LE → internal` must be semantically identical (internal-form equality up to variable renaming — the same `variant/2` criterion the `.lpst` harness uses). Every legacy example expressible in LE gets a round-trip test. Strong, cheap correctness signal.

**I.9.6 Scope limit.** Not every legacy program need be expressible in LE — some use Prolog escapes and external predicates. Define and document the expressible subset rather than pretending to totality.

### I.10 IDE and tooling

**I.10.1 Base.** Extend the LE2 Monaco editor **[verified]**: `client.ts` (UI), `server.ts` (LSP in a Web Worker), `le-language.ts` (Monarch), `tokenizer.ts`. Add an LPS language mode alongside the LE mode.

> **Editor strategy: see [`le_lps_design.md`](le_lps_design.md) §3.** One editor shell,
> two language modes (`le` extended with the LPS constructs; a new `lps` Monarch grammar
> for the external syntax, which is Prolog lexis plus the §I.4 operator table). One LSP
> worker dispatching on `languageId`. Two backends and no proxy: the editor holds both
> `/leapi` and `/lpsapi` base URLs and picks by mode and declared target.
>
> `src/ide/` is **kept**, as a reference implementation rather than a second product. It
> is what `tools/ide_screenshots.cjs` drives, and it is the only thing that keeps
> `/lpsapi` independently testable once the primary client lives in another repository.
> It should stay deliberately plain.

With WASM deferred (§I.0), the LSP worker cannot run the compiler locally; analysis is a server round-trip. LE2 already handles this with a 1500 ms debounce before triggering a server-side reload **[verified]**, so we inherit a working pattern. The cost is that authoring requires a live server — bounded and familiar. Making the analysis local is the single clearest payoff if WASM is revisited at M11.

**I.10.2 Timeline view.** The `.lpst` structure is already a timeline: stage × cycle × items. **[verified]** the old system had a Gantt chart via `go(T)` and a state-transition graph via `godfa(Graph)`. The replacement: a scrubbable timeline with one lane per fluent (intervals during which it holds), one lane for events/actions, one for composite events, and a cycle cursor. Fed directly by the §I.5.2 trace records — no separate instrumentation.

**I.10.3 State-change diagram.** Per cycle: what was initiated, what terminated, what persisted, and *which causal law fired* for each change. The view the old system most conspicuously lacked, and nearly free once trace records carry the responsible clause id.

**I.10.4 Animation.** Time-scrubbing with interpolated rendering of a user-declared visual mapping (`display/2` exists in the current engine and is the natural hook). Replaces the old Electron/LPS-Studio prototype with something in-browser. Lower priority than diagnostics — schedule after M9.

**I.10.5 Explanations — the substantive improvement.** The current `why/1` walks the derivation for a fluent. It is weak in three ways: it explains fluents but not *actions*; it cannot explain *absence*; and it has no notion of the reactive rule that drove everything.

The new design records, per cycle, a **derivation forest** linking each committed action → the goal-tree path that produced it → the reactive rule instance that created that goal → the observation or state change that fired the antecedent; plus, for each state change, the causal law and triggering event.

**[verified]** The infrastructure is half-present: `lps_test_action_ancestor/3` is recorded during `make_test` and explicitly *not used for testing* — action-ancestry data collected and thrown away. Promote it to a first-class, always-on trace record.

Question forms to support:

- *Why did action A happen at cycle T?* → the rule/goal chain above.
- *Why does fluent F hold at T?* → last initiating event, or the intensional derivation, or persistence since T′.
- *Why did F stop holding?* → terminating event and its cause.
- *Why did A **not** happen?* → the hard one, and the most useful. Answerable in four cases: no rule instance ever created the goal; the goal existed but a denial blocked the action (name the clause); the goal existed but a prospective constraint rejected the resulting state (name it); under planning mode, no plan was found within the horizon. Otherwise report "no applicable rule", honestly.
- *What would have happened if…?* → fork the session (§I.6), replay, diff traces. A genuinely new capability, falling out of the hypothetical-worlds work for almost nothing.

**[verified]** LE2 already has an explanation-tree node format and an `explain` API operation. Reuse that format so LPS explanations render in the same component and, in LE mode, read as English.

### I.11 Milestones

| # | Milestone | Contents | Gate |
|---|---|---|---|
| **M0** | Harness & corpus classification | `.lpst` runner with upstream comparison semantics; legacy-engine adapter; buckets A/B/C measured; selection spec drafted (§I.1) | Bucket sizes known; C < ~5% or plan revised |
| **M1** | Core skeleton | Program/session split; state store (trunk backend); internal representation with provenance; diagnostics model; core-purity lint | `lps_session_step/3` runs a trivial program |
| **M2** | Legacy syntax | Operator table, term expansion, declarations, §I.4 subtleties incl. prospective and `updates` forms | `legacy → internal → dump` matches upstream `dump/0` |
| **M3** | Cycle engine | All phases; `dc` resolution; causal laws; composite events; integrity constraints; termination | Bucket A passes |
| **M4** | **Conformance** | Bucket B via `legacy_trace`; bucket C adjudicated | **100% A+B; C justified. Gates all later work.** |
| **M5** | Hypothetical worlds | Persistent backend; fork/discard; benchmark vs trunk (§I.6) | Fork O(1); corpus timing regression < 10% |
| **M6** | Planning mode | `achieve`; static classification of `false` clauses; concurrent-action search; `goat_declarative.pl` | Declarative goat solves; legacy tests unaffected |
| **M7** | CLI + web endpoint | Full CLI; single-endpoint API; session registry | Multi-program, multi-session |
| **M8a** | LE↔LPS interface | `t(Term, src(…))`; `/lpsapi compile` from internal text + provenance; `.lps`/`.lpsw`; the shared interface doc | A program handed over as internal text + provenance runs, and an LPS diagnostic lands on an `.le` line and column |
| **M8b** | The surface language, on paper | ~15 hand-written LE programs, from the three `en("…")` specimens outward; reviewed by a non-LPS reader | Every construct has a written internal-form mapping; the prospective form is rendered or declared out of scope |
| **M8c** | The grammar, in LE2 | `le_lps.pl` as a third target; `the actions are:`; `initially:`; timed observations; `When…then`; `It must not be true that` | The 15 parse, `variant/2`-equal to the hand-written expectation |
| **M8d** | Round trip and corpus | The LE writer; `LE → internal → LE`; `legacy → internal → LE → internal` (§I.9.5) | A stated subset round-trips; the excluded set is listed with reasons |
| **M8e** | Editors | `lps` Monaco mode; the four LPS panes in LE2's editor; two-backend wiring | Playwright drives both modes and both backends, no console errors |
| **M9** | IDE | LSP against the server; timeline; state-change diagram; explanations | All explanation question forms covered |
| **M10** | Animation & polish | Visual mapping; scrubbing; docs | — |
| **M11** | *WASM (conditional)* | Browser-embeddable core; local LSP analysis; in-process game/browser hosts | **Go/no-go review held at M9**, not committed now |

**Critical path:** M0 → M1 → M2 → M3 → M4. Everything after is parallelisable; M5/M6 and
M8 are independent; M9 depends on M7 for the API but not on M8. Within M8, M8a is worth
doing first and alone: it is small, almost entirely on the LPS(2) side, and it lets LE2
start emitting LPS before any of the grammar is settled. M8e depends on M9/M10, which are
done — the panes exist and are driven by the API M8e wires up.

**[assumption]** No calendar estimates on purpose. The dominant unknown is the bucket-C fraction from M0, which can swing M4 by a factor of two or more. Estimate after M0, not before.

**Principal risks.**

1. **Bucket C is large.** Mitigated by measuring first (M0). Fallback: regenerate `.lpst` for adjudicated cases, treating the legacy engine as reference only for buckets A and B.
2. **Persistent state store too slow.** Mitigated by the dual-backend design and a measured go/no-go at M5.
3. **LE temporal syntax doesn't scale past tutorial examples**, especially the prospective form. Mitigated by hand-writing 15 real examples before the grammar (§I.9.4).
4. **Concurrent-action planning blows up.** Subset branching is exponential in concurrency. Mitigated by declared concurrency bounds, the static classification of §I.7.4, and staged heuristics.
5. **Core purity erodes**, foreclosing the WASM option and — more importantly — the testability and forking that depend on it. Mitigated by mechanical CI lint (§I.2.4), not by discipline.

---

## Part II — The agent (draft; to be revised after Part I)

The earlier memo's design stands, but Part I changes four things materially. Rather than restate it, here is what is now different, and why.

### II.1 What Part I changes

**Consequence-checking becomes real — and has an ancestor.** The earlier "simulate the candidate on a copy of the state" was hand-waving over a destructively-updated database. With §I.6 it is `lps_session_fork/2` plus `lps_session_run/4` — O(1) fork, real lookahead, and a diff of two traces. Better still, this is not a bolt-on: LPS's prospective constraints (§0.5) are already one-step consequence-checking, rejecting an action because of the state it would produce. The agent's lookahead is the *n*-step generalisation of a mechanism the language already has.

**The agent's control loop *is* the LPS cycle.** Previously I described an agent loop wrapping an LPS engine. With the program/session split, the agent is simply a session plus edge adapters: perception writes events via `lps_session_observe/3`; actuation reads committed actions from the `CycleReport`. There is no second loop to keep in sync with the engine's, which removes an entire class of bug.

**Explanations come free.** §I.10.5's derivation forest is exactly the audit trail the agent needs — including the "why not?" form, which is what an operator actually asks after an incident.

**The LLM should emit Logical English, not JSON — for rules.** A genuine revision. I previously proposed a JSON fact schema for everything the model produces. Now I would split it:

- **Facts and events** (high frequency, machine-consumed): JSON against the declared schema, as before; validation is type/arity checking.
- **Rules** (low frequency, human-reviewed): Logical English. Three reasons. It is far closer to the model's training distribution than internal LPS or raw Prolog, so generation is more reliable. It is reviewable by a domain expert who does not read Prolog — which is the entire point of a human in the loop. And LE's template mechanism type-checks it: a model cannot invent a predicate without also proposing a template, which makes ontology drift (risk 3 in the original memo) visible and gateable rather than silent.

That last point resolves the ontology-management worry more cleanly than anything in the earlier draft.

**Planning replaces greedy tool-calling on the deliberative path.** §I.7 gives the agent a real planner for goals expressible as `achieve` plus constraints. The earlier draft had the LLM propose candidate plans with the engine only *checking* them. Now the planner generates where the action theory is known, and the LLM proposes only where it isn't. Better division of labour — search is what symbolic systems are good at — and it removes the model from the loop precisely where its plans were least reliable.

### II.2 Revised LLM interface

Four operations, revised contracts:

1. **`perceive(raw) → [event]`** — JSON, schema-validated, restricted predicate set; cannot emit privileged events (II.3). Unchanged.
2. **`propose_rules(goal, context) → LE text`** — *new form.* Emits Logical English, parsed by §I.9, type-checked against templates, shown to a human for approval, and only then compiled into the program. Rule changes are program changes and are reviewed; they are not per-cycle decisions.
3. **`propose_actions(goal, state) → [candidate]`** — only for goals the planner cannot reduce (no action theory, or open-world). Candidates go through the same fork-simulate-filter path as planned actions.
4. **`rank(candidates, projections) → ordering`** — advisory only, over survivors of the constraint filter, with fork-diffs as input.

### II.3 Safety properties (unchanged, now enforceable)

The three invariants survive intact, and Part I makes two of them structural rather than procedural:

- **(a)** No atom over an undeclared predicate enters the state. *Now enforced by compiler declaration checking (§I.4) and LE templates (§I.9), not an ad-hoc validator.*
- **(b)** No privileged event (approval and similar) is ever sourced from the LLM channel. *Enforced by per-channel predicate allow-lists at `lps_session_observe/3`.*
- **(c)** No destructive/irreversible action executes unless the constraint checker confirms the authorising fluent holds. *Enforced by ordinary LPS integrity constraints — the mechanism the approval-gate example already uses.*

The approval-gate example from the earlier memo carries over unchanged; its LE rendering becomes the worked example for §I.9. It is reproduced in Appendix C.

### II.4 Open questions for after Part I

- How accurate must the symbolic action theory be before fork-based lookahead is trustworthy in real (non-puzzle) domains? `goat` is exact by construction; a filesystem or API is not. Needs an empirical answer, possibly a confidence annotation on causal laws.
- Fuzzy constraints ("don't be rude") still resist crisp antecedents. Current thinking: a classifier emits a boolean fluent and the constraint is crisp over that fluent — relocating the soft link to a named, testable place rather than eliminating it. Whether that is honest enough is a judgement to make with real examples in hand.
- Replanning cadence: §I.7.6 gives per-failure replanning, but an agent in a drifting world may need periodic replanning even absent failure. Needs a policy.

---

## Part III — Deployment surfaces (preliminary)

The ambition is pervasiveness. The architecture that gets there is the one chosen in Part I: a pure core with a small session API, everything else an adapter. An adapter does only three things — map world observations to LPS events, map committed LPS actions to effects, hold a session handle.

**Deployment model, given WASM is deferred.** Every surface below is a client of the §I.8.2 endpoint, or an in-process SWI-Prolog embedding where the host permits it. That is a "run a server (or a sidecar) and connect" story, not an "embed the engine anywhere" story. It is perfectly adequate for developer, web, chat and MCP surfaces; it is the constraint that bites for in-process game hosts and browser extensions.

This is the main reason M11 exists. If Part III's ambition turns out to be distribution-friction-limited — which I suspect it will be, since pervasiveness is largely a packaging story — then WASM stops being a nice-to-have and becomes the enabling piece. That judgement should be made at M9 with real surfaces in hand, not now.

**Candidate surfaces, roughly by leverage:**

- **CLI and REPL** (M7) — the developer surface; also the first agent host.
- **Web IDE** (M9) — the authoring surface; doubles as the demo.
- **MCP server** — exposes sessions as tools to any MCP-speaking assistant. LE2 already has MCP endpoints **[verified]**, so the pattern exists. Probably the highest-leverage single surface for reach, and it is unaffected by the WASM deferral since it is a server surface by nature.
- **Editor extension (VS Code)** — reuses the M9 LSP nearly unchanged.
- **Chat surfaces (Slack/Discord)** — a session per channel; the approval gate maps naturally onto message-button interactions.
- **Browser extension** — page observations as events, DOM actions as actions. *Materially harder without WASM*: needs a native-messaging host or a remote endpoint. Candidate for M11.
- **Games — Minecraft first.** Two routes: (i) a Mineflayer JS bot talking to the LPS endpoint over IPC or HTTP — the pragmatic path now; (ii) a Fabric/Forge mod for server-side integration and better world access. Start with (i), accepting the sidecar. The in-process variant of (i) is one of the strongest arguments for M11. The mapping is unusually clean: blocks and entities are fluents; bot capabilities are actions; the world's rules are the action theory; build/puzzle goals are exactly `achieve` plus constraints. Minecraft is also an honest stress test for §I.6 — a large, fast-changing state where lookahead is expensive and the action theory is only approximately right.
- **Robotics / IoT simulation** — later; same shape, harder timing.

**What is genuinely uncertain.** Whether the state store (§I.6) survives contact with a domain like Minecraft, where fluent counts are orders of magnitude larger than anything in the corpus. My guess is it requires a *scoped* state — only fluents within a region of interest tracked — which is a real design problem, not a tuning problem. Prototype before committing to games as a headline surface.

**Ordering.** Nothing in Part III starts before M7. The MCP surface and the Minecraft bot are the two worth prototyping early, because they stress opposite ends of the design: breadth of integration versus depth of state. Their findings are also the main input to the M11 go/no-go.

---

## Part IV — Supporting other agent languages (preliminary)

LPS is a general agent language, which makes it a plausible *target* for transpilation from more established ones. Strategically this is the strongest adoption path available: nobody switches agent languages, but a team will happily let a verifier consume what they have already written.

Two things drive the ranking below — raw impact, and **semantic fit**. A high-impact language with a poor fit yields a transpiler nobody trusts, which is worse than no transpiler. For each target I also state what LPS gives *the source language*, because without that the exercise is a party trick.

**[assessment]** Unlike Parts 0–I, the fits below are design judgements from familiarity with these languages, not findings verified against current specifications in the way the LPS and LE2 claims were. Each needs a short spike against the real grammar before it is committed to a milestone.

### IV.0 The interface already exists — Part IV is front ends, not engine work

The single most useful consequence of the §I.9 rework is that the transpiler contract is already designed. LE2 emits **LPS internal syntax** as a target language beside `prolog` and `taxlog`: text plus a provenance list, consumed by `lps_compile/5`'s existing `terms(…)` form, over `/lpsapi compile`. That is precisely what a transpiler needs, and it is already scheduled as **M8a**.

So the framing for this Part is:

> **LE2 is not a special case. It is the first transpiler.** Every language below is another front end producing internal text plus provenance against the same contract.

Consequences worth stating explicitly:

- **No new architecture.** Part IV adds front ends. The engine, the session API, the planner and the constraint machinery are untouched.
- **Provenance is the payoff.** `t(Term, src(…))` means a diagnostic — or, more importantly, an *explanation* (§I.10.5) — lands on a line of the **source** language: a PDDL action, a Jason plan, a Drools rule. "This action was blocked by the constraint on line 34 of your BPMN" is usable by someone who never learned LPS. That is the whole value proposition, and it comes free from M8a.
- **The file convention extends.** `foo.pddl` → `foo.pddl_.lpsw`, exactly as `foo.le` → `foo.le_.lpsw`, following `psyntax.P:237–260`.
- **The acceptance test extends.** M8a's gate — a program handed over as internal text plus provenance runs, and a diagnostic lands on the right line and column — is the acceptance test for every transpiler in this Part.

**Recommendation, and it is nearly free if done now:** write M8a's shared interface document as a **language-neutral front-end contract**, not an "LE↔LPS interface". Naming it generically costs nothing this week and avoids a rename plus a compatibility story later.

### IV.1 The universal caveat: procedural leaves

Every candidate except PDDL has procedural leaves — Jason plan bodies, Drools right-hand-side Java, BPMN service tasks, behavior-tree action nodes. The honest scope is to transpile the **declarative control skeleton** and leave the leaves as *external basic actions*, which §I.4 already supports (an undeclared `A from T1 to T2` backed by a defined predicate).

This must be a **stated design boundary, not a discovered one**. A transpiler that claims more will be caught out on the first real rule base, and the credibility loss is disproportionate. The compensating argument is straightforward and should be made in the same breath: the skeleton is exactly where the constraints, the reachability and the explanations live, so verifying it is worth doing even when the leaves stay opaque.

### IV.2 The five targets

| # | Language | Domain | Impact | Fit | What LPS adds |
|---|---|---|---|---|---|
| 1 | **PDDL** | academic planning | high (academic) | near-exact | execution, monitoring, replanning |
| 2 | **AgentSpeak(L) / Jason** | BDI multi-agent research | high (academic) | good, with a named gap | invariants, lookahead, "why not" |
| 3 | **Drools** | enterprise rules | high (industrial) | designed-for | declarative reading, verification |
| 4 | **BPMN + DMN / DECLARE** | business process | highest (industrial) | moderate | conformance checking, explanation |
| 5 | **Behavior trees** | robotics, game AI | high (both) | good | constraints, consequence-checking |

**1. PDDL.** Dominant in academic planning, with the IPC benchmark suites as a large public corpus. The fit is near-exact once §I.7 exists: `:precondition`/`:effect` → causal laws plus denials, `:init` → `initially`, `:goal` → `achieve`. Durative actions map unusually well onto LPS's `from T1 to T2` intervals — a better correspondence than most planning formalisms get, and a direct consequence of LPS being interval-based rather than instantaneous.

Note the value flows *toward* LPS here as much as outward: transpiling PDDL hands the M6 planner thousands of benchmark problems with known-optimal plan lengths, which is a validation corpus we would otherwise have to invent. What it gives PDDL users is execution — classical planners are offline, and LPS supplies monitoring, integrity constraints *during* execution, and replanning on divergence (§I.7.6). Cheapest to build, highest immediate engineering payoff, and the only target with no procedural leaves.

**2. AgentSpeak(L) / Jason.** The reference BDI language and the one MAS research is taught in; Bordini and Hübner's book plus the JaCaMo stack make it the academic default. Structural fit is good: triggering event plus context condition → reactive-rule antecedent; plan body → composite-event goal reduction; belief base → fluents.

What LPS adds is precisely what Jason lacks: integrity constraints (Jason has no notion of an invariant the agent must maintain), lookahead, and explanation — including *why a plan did not fire*, which in Jason means reading intention stacks by hand.

The mismatch is real and should be named rather than papered over: Jason's plan selection, intention management and failure handling (`-!g`) are procedural. A faithful transpilation must either model the intention stack explicitly as fluents or accept a documented semantic gap. That gap is itself a publishable result, and it is the most academically interesting item in this Part.

**3. Drools, and production rules generally.** The heavyweight industrially — banking, insurance, healthcare — and the *designed* correspondence, since KELPS was explicitly framed as reconciling production systems with logic programming. Kowalski and Sadri's argument is that LPS gives production rules the declarative reading they never had, so this is the transpilation the theory was written for. `when…then` → reactive rules; working memory → fluents.

The industrial pain point is live and well known: large Drools rule bases become unverifiable, and conflict resolution by salience is an operational device rather than a semantic one. LPS offers constraint checking over the rule base and an actual explanation of a firing. The obstacle is equally well known — Drools right-hand sides are arbitrary Java, so IV.1 applies in full force.

**4. BPMN, with DMN alongside.** The largest industrial footprint of anything here; every BPM suite implements it. Fit is only moderate: sequence flows and gateways map to composite events, but boundary events, compensation and multi-instance activities are genuinely awkward.

It still ranks because the audience is unusually receptive. Declarative process modelling (the DECLARE/LTL line) and conformance checking in process mining are established communities asking exactly the question LPS answers: did this trace comply, and if not, which constraint did it violate. It also connects directly to the Logical Contracts lineage the codebase already carries.

**If you want a narrower and much better-fitting first target here, take DECLARE rather than BPMN itself** — its constraint templates are close to `false` clauses, and success there is a credible bridgehead into the BPMN world without fighting compensation semantics on day one.

**5. Behavior trees.** Dominant in robotics (BehaviorTree.CPP, ROS 2's Nav2) and in game AI (Unreal, Unity). Sequence, fallback, parallel and decorator nodes map cleanly onto composite-event definitions, and the tick maps onto the cycle.

It also ranks on strategic alignment: Part III's Minecraft ambition and BT-based game AI are the same problem, so this transpiler and that deployment surface reinforce each other. BTs have no concept of an invariant and no lookahead — they are pure reactive control — which makes the value-add unusually legible to their users: keep your tree, gain constraints, consequence-checking and explanation.

### IV.3 Deliberately excluded

- **Golog / IndiGolog.** Arguably the *best* intellectual fit — both are logic-based action theories and the correspondence would be elegant — but the active user base is small enough that impact does not justify the effort. Worth a paper, not a milestone.
- **Event Calculus.** Near-identity with LPS's underlying semantics, so it is a benchmark source rather than a transpilation target.
- **ASP.** Belongs on the *other* side of the system: a planner backend (§I.7.4 stage 3), not a source language. Note that IV.2's PDDL work and the ASP backend option share machinery, which is an argument for doing them near each other.
- **LangGraph, AutoGen, CrewAI and the current LLM-agent frameworks.** The most mindshare by a wide margin and the worst fit: Python orchestration with no formal semantics. You could transpile a state graph's skeleton, but the nodes are arbitrary code and model calls, so you would verify the control flow and nothing else. Revisit when Part II is real, as a *wrapping* story — an LPS session supervising a framework agent — rather than transpilation.

### IV.4 Sequencing

| # | Target | Depends on | Rationale |
|---|---|---|---|
| **M12a** | PDDL | M6, M8a | Validates the planner against IPC; cheapest; no procedural leaves |
| **M12b** | AgentSpeak / Jason | M8a | Academic credibility; the intention-stack gap is the research contribution |
| **M12c** | DECLARE, then BPMN | M7, M8a | Industrial reach; needs a service, not a Prolog CLI |
| **M12d** | Drools | M7, M8a | Industrial reach; the correspondence KELPS was written for |
| **M12e** | Behavior trees | M7, Part III games prototype | Co-develop with the Minecraft surface |

PDDL should be done during or immediately after M6, because it validates the planner rather than merely consuming it. Everything else waits on M8a for the front-end contract, and the two industrial targets additionally want the M7 endpoint, since their users will expect a service.

### IV.5 Risks and open questions

- **Trace-conformance has no analogue here.** Part I's `.lpst` corpus gives an objective correctness criterion. Transpilers have none by default. Each needs its own oracle: for PDDL, plan validity checked by VAL and optimal length from IPC records; for Jason, side-by-side execution against the Jason interpreter on the same scenario; for Drools, agreement on which rules fire in which order. **Do not start a transpiler before its oracle is specified** — this is the same lesson as §I.1.1, and it will be tempting to skip.
- **Round-tripping is mostly not available.** §I.9.5 gets a strong test from `LE → internal → LE`. Most targets here are lossy in one direction, so that lever is missing and the oracles above have to carry the weight.
- **Semantic gaps must be reported, not silently accepted.** Where a construct cannot be faithfully rendered (Jason intention stacks, BPMN compensation), the transpiler should emit a diagnostic against the source line rather than approximate. The M8a provenance channel already makes this possible; the discipline is to use it.
- **Scope creep into a language zoo.** Five transpilers is already ambitious for a project whose critical path is M0→M4. The realistic commitment is PDDL plus one other, chosen by whichever audience the project actually needs — academic (Jason) or industrial (DECLARE/Drools). The rest should be documented as a roadmap and left there until the first two have users.

---

## Part V — Supporting industrial applications (preliminary)

Part IV transpiles *into* LPS: other languages become front ends, and LPS is where the reasoning happens. This Part runs the other way. A **tested** LPS program is the source, and a platform-specific implementation is generated from it — LPS as specification, the target as deployed artifact.

The naming matters and should be kept straight in conversation as well as in this document: **Part IV is front ends, Part V is back ends.** Calling both "transpilation" will confuse readers, because the trust argument runs in opposite directions. In Part IV we inherit someone else's program and must not over-claim what we preserve. Here we *emit* the program, and must justify why the emitted artifact means what the source meant.

**[scope]** Blockchain targets (Solidity and similar) were assessed and are deliberately out of scope. The industrial case is stronger on both fit and commercial justification, and mixing them weakens the argument for each.

### V.0 Why industrial control is the right target

The decisive property is that **a PLC scan cycle *is* the LPS cycle**. Read inputs, evaluate logic, write outputs, repeat — that is `lps_session_step/3` with no impedance mismatch: no external clock to synthesise, no keeper process to drive execution, no partial-execution hazard within a scan. The correspondence is close enough that the generator's job is largely mapping constructs, not reconciling execution models.

Three further alignments, each of which is a capability Part I builds anyway:

- **Safety interlocks are integrity constraints, literally.** "The drawworks must not hoist while the slips are set" is a `false` clause. Safety instrumented functions are exactly the maintenance-goal pattern — and unlike most domains, these constraints are *already written down*, already reviewed, and already legally required to be traceable.
- **Incident investigation asks LPS's hardest question.** After an event, the question is "why did the system not prevent this?" That is §I.10.5's *why did A **not** happen?* — the form the old `why/1` could not answer, and the one the new derivation forest is designed for.
- **Certification wants exactly the artifact we produce.** Functional-safety regimes demand evidence that the implementation corresponds to a verified specification. A generated implementation with mechanical traceability back to a tested spec is that evidence.

**[assessment]** The standards landscape below (IEC 61131-3, IEC 61499, IEC 61508/61511, and the tool-qualification regime) is stated from working familiarity, not verified against current published texts in the way Part 0's LPS and LE2 findings were. Every claim here needs checking against the actual standard before it appears in anything client-facing.

### V.1 Targets

| Target | Nature | Fit | Notes |
|---|---|---|---|
| **IEC 61131-3 Structured Text** | scan-cycle PLC language | **excellent** | The primary target. Text output, widely supported, human-readable for review |
| **IEC 61131-3 Function Block Diagram** | graphical | good | Reviewers in this domain often prefer graphical; generation is harder but the audience is real |
| **IEC 61499** | distributed, event-driven function blocks | good | Closer to LPS's event model than 61131; the right target for distributed control |
| **Ladder Diagram** | graphical, legacy-dominant | poor as a *generation* target | Enormously deployed, but generated ladder is unreadable and readability is the whole point for this audience |

Structured Text is the one to build. It is text (so the M8a provenance channel works unchanged), it is reviewable, and it is portable across vendors in principle — though **[assumption]** vendor dialect divergence is real and a per-vendor back end will probably be needed in practice. Confirm early with whichever platform the first user actually runs.

### V.2 The mapping

| LPS construct | Structured Text | Fit |
|---|---|---|
| `false C1,…,Cn` | interlock evaluation → trip / inhibit output | **excellent** — the core of the value |
| `initiates` / `terminates` / `updates` | state variable assignment | good |
| Reactive rule with event antecedent | conditional block within the scan | good |
| `l_int` intensional fluent | derived signal, computed each scan | good |
| Fluent | retained variable | good |
| `l_timeless` | function / constant table | good |
| `findall` over state | bounded loop over a declared array | **restricted** — see V.3 |
| Composite events / goal reduction | sequence step (SFC-like) | partial |
| The §I.7 planner | *not generated* — supervisory layer | see V.4 |

The interlock mapping is the heart of it. In current practice, interlocks are coded imperatively and scattered through the logic; there is no construct that says "this is an invariant" as distinct from "this is control flow", and no tooling that can answer which invariant blocked an action. Generating interlocks from `false` clauses makes them a first-class, separately reviewable artifact, and preserves the link from a trip back to the constraint that caused it.

### V.3 The generatable subset

Structurally the same move as §I.9.6's expressible subset, but the binding constraint is different: **hard real-time requires bounded, predictable scan time.** A PLC that occasionally takes twice as long to scan is a fault, not a slow program. So the subset is defined by worst-case-execution-time analysability:

- **No unbounded iteration.** `findall` over state is admissible only over a declared, statically bounded collection — the analogue of a fixed-size array. Unbounded aggregation is rejected at generation time with a diagnostic, not silently emitted.
- **No unbounded recursion.** Recursive `l_timeless` clauses need a declared depth bound or they are rejected.
- **No dynamic allocation**, and no construct whose cost depends on run-time state size.
- **No search.** Goal reduction that requires backtracking is not generated (see V.4).

This must be a **checked, reported property**, not a documented convention. The generator statically classifies every clause and refuses anything it cannot bound, exactly as §I.7.4 statically classifies `false` clauses for the planner. The two analyses share machinery and should be built together.

### V.4 The two-tier architecture

The planner and the deliberative machinery do not belong on a PLC, and trying to put them there would be the main way to get this wrong. The natural split follows the automation hierarchy:

- **Controller tier (hard real-time).** Generated Structured Text: interlocks, causal laws, reactive rules, derived signals. Deterministic, bounded scan, no search. This is the safety-relevant artifact.
- **Supervisory tier (soft real-time).** The actual LPS engine from Part I, running as a session against the §I.8.2 endpoint: planning (§I.7), lookahead over hypothetical worlds (§I.6), explanation (§I.10.5), and — when Part II is real — the LLM-facing perception and rule-proposal layer. It issues setpoints and goals downward; it never bypasses the generated interlocks.

The property that makes this defensible: **the supervisory tier can be wrong without being dangerous**, because every command it issues is still subject to the generated constraints at the controller tier. That is the same argument as §II.3's invariant (c) — the deliberative component is never the thing that authorises the hazardous action — instantiated in hardware rather than in a session. It is also the cleanest possible answer to "why should I let a planner, let alone a language model, near my rig."

### V.5 The correctness argument

Part I gives an unusual asset here: a tested LPS program has a recorded execution trace in `.lpst` form. That yields a mechanical correctness argument for the *translation*, distinct from any argument about the source program:

1. Run the LPS program under the Part I engine → trace (stage × cycle × items).
2. Generate Structured Text from the same program.
3. Run the generated code in a PLC simulator, driven by the same input events.
4. Compare the resulting state per scan against the trace, using the §0.2 comparison semantics.

This is differential testing between specification and implementation, with the oracle supplied by the conformance corpus rather than invented. It is the strongest single argument the generator can make, and it addresses IV.5's complaint that back ends lack an oracle — here, uniquely, we have one.

**[assumption]** This presumes a simulator with scriptable I/O and state inspection. Vendor simulators vary; an open target (an IEC 61131-3 runtime such as a soft-PLC) is the pragmatic first choice, with vendor platforms following once the approach is proven.

### V.6 Certification — the commercial case and its price

The reason this is a business and not just a technique: functional-safety certification demands documented correspondence between specification and implementation, and producing that correspondence is currently expensive manual work. What we can offer is a generated implementation with per-construct traceability (the M8a provenance channel, running in the emit direction), a machine-checkable differential test (V.5), and an explanation facility for incident analysis (§I.10.5).

The price is proportionate and must be stated up front: **the generator itself becomes a tool requiring qualification.** Under functional-safety regimes an offline tool that can introduce an error into the safety-related system without detection carries qualification obligations. Qualifying a code generator is a serious, expensive undertaking involving its own specification, verification evidence and version control discipline.

Two implications for planning. First, this is not a side project — a half-qualified generator has no value, because the buyer cannot use its output without redoing the work. Second, once done it is a genuine moat, for exactly the same reason.

**[assessment]** The tool-classification details, and whether a "generated code is reviewed as source" route avoids the heavier obligations, need a specialist opinion before committing. That question materially changes the cost, and it should be answered before M13 starts rather than during it.

### V.7 Drilling as the beachhead

Drilling automation is a good first domain, for reasons that are specific rather than generic:

- **High-consequence, constraint-shaped control.** Hoisting and slips interlocks, pressure envelopes in managed-pressure drilling, blowout-preventer control logic — all naturally expressed as invariants over state, which is precisely the `false` form.
- **Investigation culture.** Incidents are formally investigated, and the investigation asks the "why did it not prevent this" question. An explanation facility that answers it from a recorded trace has immediate, legible value.
- **Existing written constraints.** The rules already exist in procedures and safety cases; the work is formalisation, not elicitation, which is a far easier sell than asking a customer to invent a specification.

**[assumption]** The specifics above are stated from general familiarity with the domain, not from the relevant API/IADC/NORSOK texts. A domain expert should confirm the framing before it is used with a customer — the argument's shape is right, the terminology may not be.

The realistic entry point is not the safety-instrumented system itself, which is the most conservative part of any rig, but the **supervisory tier**: monitoring, constraint checking against the live state, and explanation, running alongside existing controls without authority to actuate. That delivers the explanation and lookahead value with no certification burden, and it earns the right to talk about generating controller code later.

### V.8 Milestones

| # | Milestone | Contents | Gate |
|---|---|---|---|
| **M13a** | Generatable-subset analysis | Static classification of clauses for WCET-boundedness; diagnostics for rejected constructs; shares machinery with §I.7.4 | Every corpus example is classified generatable / not, with reasons |
| **M13b** | Structured Text back end | ST emission for the subset; provenance in the emit direction; readable, reviewable output | A worked control program generates and compiles on a soft-PLC |
| **M13c** | Differential testing | Simulator harness; `.lpst` trace vs. per-scan PLC state (§V.5) | Trace equivalence on the generatable subset of the corpus |
| **M13d** | Supervisory tier | LPS session alongside a live controller; constraint monitoring; explanation UI | Read-only deployment against a simulated rig; "why did it not…" answered from real traces |
| **M13e** | *Certification track (conditional)* | Tool qualification; evidence artifacts; per-vendor back ends | **Specialist opinion obtained first (§V.6)**, not committed now |

Dependencies: M13a needs M6 (shares the static-analysis machinery) and M13c needs M4 (the trace semantics). M13d needs M7 for the endpoint and M9/M10 for the explanation UI, and is the one that can be shown to a customer earliest.

**Sequencing note.** M13d is deliberately placed so it can run *before* M13b if commercial urgency demands. The supervisory tier needs no code generation at all — it is the Part I engine plus the Part III deployment pattern — so it is by far the cheapest thing to put in front of a real user, and its findings should shape the generator rather than the reverse.

### V.9 Risks

- **Tool qualification is underestimated.** The single largest risk. Mitigated by getting a specialist opinion before M13 rather than during, and by the M13d-first sequencing, which produces value on a path that does not require qualification at all.
- **Generated code is not reviewable.** This audience reads the code, and a reviewer who cannot follow the output will not trust it regardless of the proof behind it. Readability is a hard requirement on the back end, not a nicety — and it is why Ladder is excluded as a target despite its deployment share.
- **Vendor dialect fragmentation.** "IEC 61131-3 Structured Text" is less portable in practice than on paper. Mitigated by picking the first user's platform early and treating portability as a later generalisation rather than a design goal.
- **Hand-editing the generated artifact.** The classic model-driven-engineering failure: the output gets patched in the field and drifts from the source. There is no clean technical fix; the mitigations are generating a whole compilation unit rather than fragments, marking it as generated, and making regeneration cheap enough that editing the source is the path of least resistance.
- **Scope pressure from Part IV.** Parts IV and V together are far more than a project whose critical path is still M0→M4 can absorb. They should be understood as a roadmap from which one or two items are actually chosen — and V.7's supervisory tier is the item with the best ratio of demonstrable value to prerequisite work.

---

## Appendix A — The architectural argument, condensed

Kowalski's cycle — observe → forward-reason to maintenance goals → backward-reason to candidate actions → forward-reason to consequences → decide → act, with a reactive shortcut from observation straight to decision — got the *control flow* of agency right decades early. Every modern agent harness (ReAct, OpenClaw's heartbeat, Claude Code's loop) reinvented it. What inverted is the substrate: those arrows were sound, inspectable inference over declarative representations; in an LLM agent they collapse into one opaque forward pass, trading guarantees for open-world competence.

The traditions have complementary failures. Logic nailed control flow, reactive shortcuts, enforced constraints and consequence-evaluation, and was crippled by brittle representations. Neural agents nailed representation and inherited exactly the deliberation and verification weaknesses logic had already solved. Maintenance goals survive in current tools only as natural-language wishes — system prompts, `CLAUDE.md`, tool policies — that a model may ignore, which is the direct cause of the agent-overreach incidents now accumulating. `SKILL.md` files are the stimulus–response shortcut, rediscovered as Markdown.

LPS is the operationalisation of the diagram: reactive rules as maintenance goals, belief clauses as backward reasoning, a timestamped fact database as state, and — from its legal-contracts lineage — the constitutive/regulatory distinction cleanly separating what things *mean* from what the agent *must and must not do*. That is the spine. The LLM supplies perception, candidate generation where the rules run out, and English. Neither half suffices; the combination is the point.

## Appendix B — The re-instrumented cycle

Same loop as Kowalski's diagram, with the mechanism on each arrow. **[LLM]** = neural, **[LPS]** = symbolic, **[world]** = tools/state.

| Arrow | Owner | Mechanism |
|---|---|---|
| Observe (world → facts) | **[LLM]** | Parse raw input into *typed* events; schema-validated before assertion. The one thing pure LPS cannot do. |
| Forward reasoning (facts → goals) | **[LPS]** | Reactive rules fire deterministically. Constraints are non-bypassable because the checker is not the thing being constrained. |
| Backward reasoning (goal → candidates) | **[LPS]** + **[LLM]** | Belief clauses reduce where rules exist; planner (§I.7) searches where the action theory is known; LLM proposes only in the open-world gap. |
| Forward reasoning (candidates → consequences) | **[LPS]** | Fork the session (§I.6), simulate, check every constraint. The *n*-step generalisation of prospective constraints. |
| Decide (consequences → action) | **[LPS]**, then **[LLM]**/human | Symbolic filter first (non-negotiable), then ranking. Decisions are over *consequences*, never over actions blindly. |
| Act (decision → world) | **[world]** | Execute; assert effects back as facts — the next Observe. The trace is the audit trail. |
| Reactive shortcut | **[LPS]**/skills | Observation pattern bound directly to action. Validated slow-path plans can be *promoted* into the fast path — habits by compilation. |

## Appendix C — Worked example: approval gate on destructive actions

Maintenance goal: no destructive action executes without prior human approval.

```prolog
maxTime(20).
events  task_request/3, approval/2.     % asserted at Observe
actions request_approval/1, execute/1.  % performed at Act
fluents pending/1, approved/1.

% Beliefs (constitutive — what the world MEANS)
destructive(delete_file(_)).
destructive(overwrite(_)).
reversible(move_to_trash(_)).

% Causal laws
request_approval(A) initiates pending(A).
approval(grant, A)  initiates approved(A).
approval(grant, A)  terminates pending(A).
approval(deny,  A)  terminates pending(A).
execute(A)          terminates approved(A).   % approval is single-use

% Maintenance goal (regulatory — the gate)
if   task_request(delete, File, _Reason) at T1,
     destructive(delete_file(File))
then request_approval(delete_file(File)) from T1 to T2,
     approved(delete_file(File)) at T3,
     execute(delete_file(File)) from T3 to T4.

% Reversible requests skip the gate
if   task_request(delete, File, _Reason) at T1,
     reversible(move_to_trash(File))
then execute(move_to_trash(File)) from T1 to T2.

% Hard constraint (non-bypassable)
false execute(A), destructive(A), not approved(A).
```

At Observe, the LLM emits only:

```json
{ "assert_event": "task_request",
  "args": ["delete", "/var/log/app/*.log", "user says logs are stale"],
  "time": 7, "confidence": 0.91, "schema_version": "1.0" }
```

**The load-bearing property is what the LLM cannot emit.** Its allowed-predicate set excludes `approval/2`. Since `approved/1` is reachable only via the causal law fired by a real `approval(grant, A)` event, and only the human channel may emit that event, a confused or jailbroken model cannot fabricate approval. It can propose the deletion all day; the constraint makes unapproved execution unreachable, so the candidate is filtered symbolically at Decide. The model is never the thing that authorises the dangerous action.

## Appendix D — Sources consulted

- `logicmoo/logicmoo_lps` (GitHub mirror of `lpsmasters/lps_corner`): `engine/interpreter.P`, `engine/db.P`, `utils/psyntax.P`, `prolog/dialect/lps.pl`, `examples/` including `goat.pl`, `goat.pl_.P.lpst`, `forTesting/prospectiveGoat.pl` and `forTesting/prospectiveGoat2.pl`.
- `LogicalContracts/LogicalEnglish2`: `le_grammar.pl`, `docs/le_summary.md`, `docs/editorSummary.md`, `docs/api.md`, `docs/sCASP_plan.md`.
- SWI-Prolog pack page for `lps_corner` (wiki: `lps.swi Reference.md`) — external-fluent/external-action rules, `make_test`/`run_test` workflow.
- Kowalski & Sadri, *Reactive Computing as Model Generation*, New Generation Computing 33(1), 2015; Kowalski, *Computational Logic and Human Thinking*, CUP, 2011.
