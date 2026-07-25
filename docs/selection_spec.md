# The LPS selection-strategy specification (draft, M0)

**Status:** draft produced during M0, from reading `legacy_lps1` under the `dc` option and
from the perturbation experiment in `docs/conformance_report.md`. It is the deliverable
§I.1.3 asks for: the thing the original codebase never had, and without which "reimplement
LPS" is under-specified.

**Why it exists.** A `.lpst` records *the choice the 2021 engine happened to make* wherever
several were eligible. Passing the corpus is therefore trace equivalence, not semantic
equivalence (§0.2). Everything below is a point where the engine chooses, together with the
rule it actually follows. LPS(2) reproduces these rules in `legacy_trace` mode; `canonical`
mode may depart from the ones marked *incidental*.

Line references are to `legacy_lps1/engine/interpreter.P` unless stated otherwise, and all
of them are on the `dc` path — the only path we reimplement (§0.2).

---

## 0. Scope: what the trace actually observes

The comparison sees, per cycle: `events` (what occurred), `composites` (macro-events as
`happens(E,T1,T2)`) and `fluents` (the state). Within a cycle, item *order* is not observed
(both sides are sorted) but item *count*, *term shape up to renaming* and *cycle alignment*
are. So a selection rule matters to conformance exactly when it changes **which** actions
are committed in a cycle, or **when**.

Two consequences worth stating early:

- Rules that only permute a list which is later sorted (e.g. the order `state/1` facts are
  collected in) are unobservable *directly* — but they are observable *indirectly* whenever
  a first-solution choice downstream depends on them.
- Anything that changes cycle count changes cycle alignment and is maximally observable.

---

## 1. The cycle, as actually implemented under `dc`

From `cycle/4` (~2181–2360). This corrects §0.3 of the plan in one place, marked **[!]**.

| # | Phase | Notes |
|---|---|---|
| 1 | terminate/pause checks, `lps_terminate` | `cycle/4` clauses at 2152–2180 fire first |
| 2 | `Actions = findall(A, happens(A, T-1, T))` | what occurred since the last cycle |
| 3 | emit `events` trace record | `test(events,T,Actions)` |
| 4 | `updateFluents(T)` | **[!] only under `option(non_prospective)`.** In the default (prospective) mode the state is advanced by `updateNextStateFluents/3` + `copyNextState` inside phases 7 and 10 instead. The plan's §0.3 step 4 is therefore conditional, not unconditional |
| 5 | `dc_process(Ri,[],NRi,[],NewGi_)` | fire reactive-rule antecedents |
| 6 | `split_goals_and_events/3` | separates new goals from "interesting" composite events |
| 7 | emit `composites`; `updateNextStateFluents`; `copyNextState` | only when composites are non-empty |
| 8 | collect state fluents (+ `sample(Templates)` intensional ones) | |
| 9 | emit `fluents` trace record | |
| 10 | `updateEvents/6` then `dc_resolve_goals/2`, then the prospective `d_pre` re-check | all inside one `time_limited(resolveAndUpdate, …)` |
| 11 | recurse into the next cycle | |

Phase 10 is one conjunction: observation injection, goal resolution and the next-state
precondition check share a single backtracking context. A precondition violated at the end
can backtrack all the way into event injection at the start. That is observable semantics
(§0.3) and is **selection point SP11** below.

---

## 2. Selection points

### SP1 — Reactive-rule list order is *reversed every cycle*
`dc_process/5` accumulates surviving rules with `[Rule|AccRi]` (3386, 3392) and returns the
accumulator when the input list empties (3348). The output rule list `NRi` is therefore in
**reverse order of the input** `Ri`, every cycle. The upstream README's own sample trace
shows this (its `Old:` and `New:` rule lists are reverses of one another).

*Status:* incidental, but observable — it determines the order in which rule instances
create goals, hence goal IDs, hence resolution order (SP5, SP6).
*LPS(2):* `legacy_trace` must reproduce the alternation. `canonical` should keep a stable
order and say so.

### SP2 — Antecedent literals are consumed leftmost-first, depth-first
`Rule =.. [F,[E|Ls],C]` takes the leftmost literal `E`; each matching clause body is
*prepended* to the remaining literals (`append(Body,Ls,Antecedent)`), and the resulting new
rules are placed *before* the remaining rules (`append(NewRules,Rs,RulesToProcess)`, 3403).
So antecedent evaluation is depth-first, left-to-right, in source order.

*Status:* essential. Bucket-B tests depend on it directly.

### SP3 — Clause selection is source order, via `findall/3`
Alternatives always come from `findall/3` over the program's clauses (`lpsClause/2` at 3401,
`l_events/2` at 388, `l_int/2`, `l_timeless/2` at 458). Prolog clause order = source order =
selection order. Nothing re-orders or prioritises.

*Status:* essential. This is why the `rev_clauses` perturbation is the single biggest
discriminator between buckets A and B in the M0 measurement.

### SP4 — New goals are accumulated in reverse rule order; IDs are assigned in firing order
`dc_process/5` prepends each new goal (`[goal(ID,…)|AccG]`, 3352), while `goal_ID_inc/1`
hands out increasing IDs in the order rules actually fire. So `NewGi` is ordered by
*descending* goal ID.

*Status:* incidental but observable through SP6.

### SP5 — The goal queue appends at the end
`append(Gi, NewGi, NGi), % Puts new goals at the end of the queue.` (2242). Older unsolved
goals are always attempted before newly created ones.

*Status:* essential — it is the engine's fairness/priority rule. Perturbing it
(`queue_prepend`) is one of the M0 perturbations; the number of tests it changes is reported
in `docs/conformance_report.md`.

### SP6 — Goals are resolved head-first; suspended goals go to the back
`dc_resolve_goals/3` walks the goal list from the head. A goal that suspends (`later(G,A)`)
is re-appended at the **end** of the already-resolved list
(`append(NewGoals_,[goal(…,Continuation)],NewGoals)`, ~709–714), with a fresh child goal ID.

*Status:* essential.

### SP7 — Variant goals are merged, keeping the first
`simplify_goal_variants/2` (~619) drops any later goal that is a `variant/2` of an earlier
one (comparing discarder, failure marks, ancestor *variables* and the goal itself). The
first occurrence survives.

*Status:* essential — it is what stops duplicate rule instances from multiplying actions.

### SP8 — Action commitment: first eligible solution, committed immediately, undone on backtracking
`resolveUntilAction(happens(E,T1,T2),…)` at 423–436: require `T1 == current_time`, `\+
happens(E,T1,T2)` (no duplicate), `action_(E)`, then `uassertz(happens(E,T1,T2))`
*immediately*, then reject-and-retract if a `d_pre(current,…)` denial holds. The last clause
line leaves a choicepoint that retracts the action on backtracking.

So: actions are committed **in goal-resolution order**, one at a time, each checked against
current-state denials at the moment of commitment; the *set* of actions in a cycle is
whatever survives to the end of phase 10.

*Status:* essential, and the single most conformance-critical rule.

### SP9 — Composite events: single alternative inlined, several suspended as a disjunction
`resolveUntilAction/4` at 386–397: `findall` over `l_events/2` in clause order; if exactly
one alternative it is expanded in place, otherwise the goal suspends as
`l_events_disjunction(…)` and the alternatives are explored in clause order, with the
first success discarding its siblings (`Discard == yes`, ~666).

*Status:* essential.

### SP10 — Intensional fluents and timeless goals: same shape
`l_ints_disjunction` (~804) for `l_int/2`; `disjunction/3` (458) for `l_timeless/2` and
plain Prolog goals — `findall` first, single answer inlined, several answers suspended and
tried in order.

Note the documented asymmetry: `happens/3` external events deliberately do **not** get this
treatment (comment at 398–404: doing so breaks
`SzaboLanguage_insurance_irrelevant_events.pl`).

*Status:* essential, including the asymmetry.

### SP11 — Failure and backtracking discipline
`dc_resolve_goals_handle_failed/2` (592) picks the **first** failed goal (`select/3`) and:

- fails — i.e. backtracks into phase 10, possibly as far as event injection — if the goal is
  `non_discardable` **or** no other goal shares its last ancestor;
- otherwise drops it and continues.

Combined with SP8's retract-on-backtracking and `updateEvents/6`'s choicepoints over
rejected external events, this is the cross-phase backtracking the plan flags in §0.3.

*Status:* essential.

### SP12 — "Future killers"
`has_no_future/3` (~679) marks a goal failed when its remaining temporal conditions cannot
be satisfied any more. This changes *how many cycles run*, so it changes cycle alignment.

*Status:* essential (§I.5.5).

### SP13 — Observation injection order
`updateEvents/6` (2382) collects `observe(Evs,Next)` in clause order, then real-time
observations, then `prolog_events` (capped at 500 solutions, `findnsols/4`), and injects
them in that order. Denial-violating observation sets are retracted wholesale, with a
warning, and the choicepoint left behind is what SP11 can backtrack into.

*Status:* essential.

### SP14 — `tried/3` plays no part on the `dc` path
`tried/3` appears only in `resolve_tree/3` and friends (2960–3150) — the **deprecated
non-`dc` resolver** — plus a blanket `uretractall` in the cycle (2244). Under `dc`,
re-attempt suppression is done entirely by `Discard`/`MyFailure` marks and
`simplify_goal_variants/2` (SP7).

*This corrects §I.5.3 of the plan*, which lists "the `tried/3` suppression rule" as
something to preserve. There is nothing to preserve; the mechanism to preserve is SP7.

### SP15 — Phase time limits make the engine machine-speed sensitive
`time_limited/3` (~2130) wraps `updateFluents`, `dc_process` and `resolveAndUpdate` in
`call_with_time_limit/2` with a default of **0.75 s per phase**, and on timeout *discards
that phase's work* (`NRi=Ri, NewGi=[]`) rather than failing. A slow or loaded machine
therefore produces a different trace from a fast one.

*Status:* an environmental hazard, not a selection rule. It is the main mechanism by which a
test lands in bucket C, and the reason the M0 harness runs single-job by default. LPS(2)
must not put a wall-clock timeout inside the cycle (§I.2.3); a deterministic budget
(inference count, or cycle-local step count) is the replacement if one is wanted at all.

---

## 2b. What the M0 measurement showed

Numbers from `docs/conformance_report.md` (102 golden traces, six variants each, legacy
engine, SWI-Prolog 10.0.0):

| bucket | count | |
|---|---:|---|
| A — invariant under every perturbation | 88 | 86.3% |
| B — choice-sensitive | 11 | 10.8% |
| C — unstable on an identical rerun | **0** | 0.0% |
| baseline failures | 3 | 2.9% |

Classification uses the harness's **strict** verdict, not upstream's. Upstream compares only
the cycles the run actually produced, so a run that dies half way through scores "ok"; for
LPS(2) a truncated trace is not a pass. Upstream's verdict is reported alongside, and the
two agree everywhere except where a run truncated (see the report).

**Bucket C, in the plan's sense, is empty.** No test's outcome depended on an incidental
detail — standard order of terms, hash iteration, historical accident. Every divergence
observed is explained either by a numbered rule above (bucket B) or by SP15, the 0.75 s
per-phase wall-clock cutoff. That is the answer the M0 gate wanted ("C < ~5% or revise the
plan"), and the plan's principal risk 1 does not materialise.

The SP15 caveat is real, though, and worth stating plainly: `CLOUT_workshop/life.pl` passed
in one sweep and failed in the next, finishing anywhere between 0 and 10 of its 10 cycles
depending on machine load. It is not nondeterministic *logic*; it is a wall-clock timeout
inside the cycle. LPS(2) does not reproduce SP15 (§I.2.3), so these tests become
deterministic — but their *current* goldens were recorded on 2021 hardware and may not
survive the change.

That is a stronger result than it looks, because the goldens are *not* uniform: they were
generated between 2017 and 2021 on SWI-Prolog 7.3 through 8.1 — and five of them on **XSB
Prolog**. 100 of 102 still reproduce exactly on SWI 10. The contract is real and stable.

**The 11 bucket-B tests**, with what breaks them:

| test | sensitive to |
|---|---|
| `goat.pl`, `CLOUT_workshop/goat.pl` | clause order, initial-state order, queue discipline |
| `forTesting/prospectiveGoat2.pl` | clause order, initial-state order, queue discipline |
| `CLOUT_workshop/badlight.pl`, `forTesting/badlight2.pl` | initial-state order, queue discipline |
| `CLOUT_workshop/diningPhilosophers.pl`, `dining_philosophers_terse.pl` | clause order |
| `CLOUT_workshop/fireSimple.pl`, `fireRecurrent.pl` | clause order |
| `CLOUT_workshop/turingTest.pl` | clause order |
| `forTesting/serializedDice.pl` | clause order |

Which maps cleanly onto the rules above: `rev_clauses` → SP3, `queue_prepend` → SP5,
`rev_initial` → SP14-adjacent (state-fact order feeding `holds/2` solution order, hence SP8's
first-eligible choice). Every bucket-B test is explained by a rule in §2; none needed an
"incidental detail" explanation. That is the evidence that this spec is complete enough to
build against.

**The three baseline failures**, none of them an engine regression:

- `forTesting/prospectiveGoat.pl` — **a stale golden.** Generated in 2017 on SWI 7.5.8 from a
  differently-named source (`prospectiveGoat.lps_.P`), and it contains **no `composites`
  records at all** — a stage the engine has emitted since. The trace is out of date, not
  violated. This one matters more than its weight: it is the example §I.7 builds the
  declarative planner on. It needs a regenerated golden before M6, reviewed rather than
  rubber-stamped.
- `CLOUT_workshop/life.pl` — **SP15.** Ten cycles expected; this sweep produced 0, 0, 0, 0, 6
  and 8 across the six variants. Nothing to do with LPS semantics.
- `forTesting/realTimeObservations.pl` — **wall-clock scheduling.** `maxRealTime(5)` with
  observations pinned to absolute dates (`observe payment1 at '2015-06-02'`); which cycle a
  given date lands on depends on how fast the machine gets there. Its golden expects 2286
  cycles.

A fourth, `CLOUT_workshop/loanAgreementPostConditionsRT.pl`, failed only against the
harness's own per-run timeout: it needs ~115 s of wall clock (2930 cycles) by construction.
With the limit raised it passes and is bucket A.

So of 102 tests, exactly **one** is a corpus defect and **two** are hostages to SP15 — out of
11 wall-clock-bound programs in the corpus.

## 3. What this means for LPS(2)

1. `legacy_trace` mode must implement SP1–SP14. None of them is expensive; the cost is that
   they must be *decided deliberately*, which is what this document is for.
2. `canonical` mode may fix SP1 (rule-order alternation) and SP4 (reverse goal
   accumulation), which are pure accidents of accumulator-style coding. Everything else is
   load-bearing.
3. SP15 must not be reproduced at all. Determinism is a Part I objective (§I.2.3); a
   wall-clock cutoff inside the cycle contradicts it.
4. The plan's §I.5.3 should be amended per SP14.

## 4. Open questions

- **Does the prospective `d_pre` re-check (phase 10) run for *all* preconditions or only
  `both`-mode ones?** The code comment says it deliberately checks all, "to support one more
  check, after the accumulated changes over the microstates in serializable actions". The
  consequences for action sets of size > 1 need a dedicated experiment at M3.
- **`parallelizable_conjunction/3` and the `conjunction(...)` suspension** (296, 736) are a
  whole sub-strategy for concurrent branches that this draft does not yet cover; it needs
  the same treatment before M3.
- **`observe` at cycle 0** throws `no_events_admissible_in_cycle_zero`, and external
  observations are refused in the first cycle "for no particular reason other than to
  simplify the logic". Keep or drop? It is observable, so `legacy_trace` keeps it.

---

## 5. What implementing it taught us (added at M3/M4)

The spec above was written from reading `interpreter.P`. Building an engine against
it surfaced a further set of behaviours that are just as load-bearing and were not
visible from the resolution code, because they live in the *environment* the engine
runs in rather than in its algorithm. Each of these silently breaks a large slice of
the corpus if you get it wrong, and each is now implemented deliberately.

### SP16 — "external predicate" means *visible in the program's module*, built-ins included

`external_predicate_for_lps/1` is `current_predicate/1` inside the program module,
with no `built_in` filter. So `true/0`, `member/2`, `append/3` and every autoloaded
library predicate is an external extensional fluent and an external basic action.

This is not a curiosity. `resolveUntilAction/4` injects `holds(true,T)` into
composite-event bodies as a time-slack device, and that literal resolves *only*
because `true` is thereby an external fluent that can simply be called. An engine
that scopes externals to the user's own clauses parses and loads every corpus
program and then fails to reduce any composite event with an implicit end time.

Two corollaries worth stating: a fluent or action whose name collides with a visible
predicate is shadowed by it (upstream's `check_syntax/2` warns about exactly this);
and in SWI a module with no predicates of its own does not exist as far as
`current_predicate/1` is concerned, so a program with no Prolog clauses needs its
module brought into being explicitly.

### SP17 — every program predicate is callable, because the whole file is loaded

Upstream loads the entire `_.P` into `db`, so `maxTime/1`, `initial_state/1`,
`observe/2`, `l_int/2` and the rest are ordinary predicates the program can call.
`forTesting/fluentAfterEvent.pl` does:

```prolog
valid_contract at T if maxTime(Max), between(1,Max,T).
```

Reading declarations into a compiler-side structure and nowhere else leaves that goal
undefined. The program structure and the program module have to be two views of the
same clauses.

### SP18 — declarations and observations may be rules, not just facts

Because of SP17 they are reached by *calling*, so a rule is as good as a fact:

```prolog
simulatedRealTimePerCycle(RTPC) :- minCycleTime(RTPC).        % loanAgreementPostConditionsRT
observe(L, 2) :- findall(time_to_eat(P), adjacent(_,P,_), L). % dining_philosophers_terse
```

Both occur in the corpus. `dining_philosophers_terse.pl` generates its whole initial
observation set this way, and `loanAgreementPostConditionsRT.pl` derives its
simulated clock from its own cycle time — get this wrong and the program runs with no
simulated clock at all, which moves every date-driven event.

### SP19 — the engine's own predicates are part of the program's namespace

`db` holds `current_time/1`, `state/1`, `happens/3` alongside the program's clauses,
and `callprolog/1` runs built-in goals inside `interpreter`, where `system_fluent/1`,
`intensional/1` and `macroaction/1` live. Programs use both:

```prolog
new_lustrum(N) :- current_time(T), 0 is T mod 5, N is T/5.   % simulateExternalEvent
uberFuent(F) at T if holds(F,T), not system_fluent(F).        % meta
```

LPS(2) puts these in `src/core/lps_builtins.pl` and imports that module into every
program module. The one deliberate improvement: a program's *own* predicates resolve
in its own module first, so `not myPredicate(X)` works here and raises an existence
error upstream.

### SP20 — system fluents are read from the engine's clock at the moment of evaluation

`real_time/1` is computed by a goal that reads `current_time/1` when it runs, not
when its caller decided to update the state. Phase 10 rebuilds the next state for
cycle T+1 while `current_time` is still T, so the `real_time` that lands in the next
state is **T's**, not T+1's. One cycle out is exactly enough to move `end_of_day`
into the wrong cycle, and from there every dated obligation in a contract program
shifts.

### A note on the store

Two implementation facts turn out to be forced rather than chosen, and both are
consequences of rules in §2:

- The event set must be **backtrackable** and the state must **not** be. SP8 commits
  an action the moment it is selected and expects it gone if resolution later fails;
  SP11 backtracks across whole phases. The state, by contrast, is rebuilt by
  failure-driven loops whose intermediate results have to survive the driving
  failures.
- Anything iterating over a backtrackable structure must not use `forall/2`, which is
  `\+ (Cond, \+ Action)` and therefore undoes what the action just did. Three
  separate bugs in the first working engine had this one cause.
