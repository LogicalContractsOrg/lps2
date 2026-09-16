# PDDL and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

PDDL, the Planning Domain Definition Language, is the standard language of
automated planning and of the International Planning Competition. A PDDL
program comes in two files: a *domain*, which declares predicates and actions
with their preconditions and effects, and a *problem*, which names the objects,
the initial state and the goal. LPS2 reads the two together and turns them into
an ordinary LPS program whose goal is an `achieve`, solved by LPS2's own
planner. The direction is one way: PDDL into LPS. Nothing writes LPS back out
as PDDL. It is part of LPS2 itself and needs nothing else: no Logical English,
no external planner. In the IDE it is reached through **File ▸ Open example
from server…** (the *Planning* folder) and **File ▸ Open…**; on the command
line through `./lps pddl`.

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [From the examples on the server](#from-the-examples-on-the-server)
  - [Your own PDDL files](#your-own-pddl-files)
  - [On the command line](#on-the-command-line)
  - [What the converted program looks like](#what-the-converted-program-looks-like)
- [How PDDL maps to LPS](#how-pddl-maps-to-lps)
  - [Preconditions are denials](#preconditions-are-denials)
  - [Static predicates are timeless facts](#static-predicates-are-timeless-facts)
  - [The goal and the planner](#the-goal-and-the-planner)
  - [How plans are checked](#how-plans-are-checked)
- [Traps](#traps)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| PDDL into LPS | **File ▸ Open example from server…** (folder *Planning*); **File ▸ Open…** (see the trap about opening two files) | a domain `.pddl` and a problem `.pddl` | an LPS program in the written form, named after the problem (`blocks-p1.lps`), with a note saying what it came from, ready to run with the planner | an independent PDDL plan simulator that reads the PDDL files, not the translation, and says whether the plan found is legal and reaches the goal; plan lengths against the benchmarks' known shortest plans |
| PDDL into a plan | command line: `./lps pddl DOMAIN PROBLEM` | the same two files | the plan in PDDL's plan format, followed by the simulator's verdict | the same simulator |

## How to use it

### From the examples on the server

1. **File ▸ Open example from server…**, and open the *Planning* folder
   (`examples/planning/`). It holds six domains — `blocks`, `gripper`,
   `hanoi`, `elevator`, `rover`, `logistics` — and their problems.
2. Pick a **problem** file, for example `blocks-p1.pddl`. The server finds its
   domain for you: the problem says `(:domain BLOCKS)`, and the domain file in
   the same folder that says `(define (domain BLOCKS) …)` is the one used. The
   two arrive as one LPS program in one tab.
3. Press **Run**. The planner searches for a plan and the ordinary cycle carries
   it out, one action per cycle from cycle 2 on. The Timeline pane shows the
   actions; the Changes pane shows what each did.
4. **View ▸ The original this was converted from** shows both source files, one
   after the other, each under a `% ==== name ====` line.

Picking a *domain* file on its own gives a tab containing only the note and an
error: `a PDDL domain has no goal on its own`.

### Your own PDDL files

**File ▸ Open…** accepts `.pddl` files and sends them to the server to be
converted. The conversion needs the domain and the problem in the same request;
the server tells them apart by what they say (`(define (problem …` or
`(define (domain …`), not by their names. See the first trap below: the IDE
currently sends each selected file on its own, so for your own files the
command line is the dependable way today.

Once converted, the tab is an ordinary LPS program. Save it, edit it, and run
it like any other; nothing ties it to the PDDL any more.

### On the command line

```sh
./lps pddl examples/planning/blocks-domain.pddl examples/planning/blocks-p1.pddl
```

```
; plan for examples/planning/blocks-p1.pddl (6 steps)
0: (pick-up b)
1: (stack b a)
2: (pick-up c)
3: (stack c b)
4: (pick-up d)
5: (stack d c)
; VALIDATION: valid
```

The plan is written in PDDL's own plan format, then checked by the simulator.
The command exits with status 1 when no plan is found or the plan is not
valid. The planner options can be given as flags:

| Flag | Default | Meaning |
|---|---|---|
| `--horizon N` | 20 | the longest plan, in cycles |
| `--search bfs\|greedy\|auto` | `auto` | the search; see [Planning](../reference/lps.md#14-planning) |
| `--max-time N` | horizon + 4 | the program's `maxTime` |

Warnings about parts of the PDDL that were not translated are printed on
standard error before the plan.

### What the converted program looks like

The start of `blocks-p1.lps`, as the IDE shows it:

```prolog
% Converted from blocks-domain.pddl + blocks-p1.pddl by LPS2 on 2026-09-16 15:59.
%
% PDDL: preconditions became denials, effects became causal laws, and the
% problem's :goal became `achieve`. The planner is the one every other LPS
% program uses.

actions 'pick-up'(_), 'put-down'(_), stack(_,_), unstack(_,_).
fluents handempty, clear(_), holding(_), ontable(_), on(_,_).

initially clear(c), clear(a), clear(b), clear(d), ontable(c), ontable(a), ontable(b), ontable(d), handempty.
```

and its end:

```prolog
achieve on(d,c), on(c,b), on(b,a).

:- lps_engine(planning,[search(auto),horizon(20),max_concurrency(1)]).
maxTime(24).
```

The last two lines are added so that the program runs as it stands: `achieve`
is an error unless the program is in planning mode.

When something in the PDDL was not translated, the note gains a section
`% What did not carry over:` with one line per warning.

The program is written in LPS's written form, not the internal form the
translator produces. The writer checks itself: it reads back what it wrote and
compares it with what it was given. If the two differ, the tab shows the
internal form instead, under a comment saying so, and a warning
`shown in internal syntax: the surface rendering did not round-trip` is added.

## How PDDL maps to LPS

| PDDL | LPS | Example (from `blocks` and `gripper`) |
|---|---|---|
| `(:action a :parameters …)` | an action declaration | `actions 'pick-up'(_), 'put-down'(_), stack(_,_), unstack(_,_).` |
| a predicate that some effect changes | a fluent declaration | `fluents handempty, clear(_), holding(_), ontable(_), on(_,_).` |
| a positive literal in `:effect` | a causal law with `initiates` | `'pick-up'(A) from T1 to T2 initiates holding(A).` |
| `(not L)` in `:effect` | a causal law with `terminates` | `'pick-up'(A) from T1 to T2 terminates ontable(A).` |
| a positive literal in `:precondition` | a denial: the action may not happen when the literal is false at its start | `false 'pick-up'(A) from T1 to T2, not clear(A) at T1.` |
| `(not L)` in `:precondition` | a denial: the action may not happen when the literal is true at its start | schematically, `false a(X) from T1 to T2, p(X) at T1.` (no example domain uses one) |
| a predicate no effect changes, true in `:init` | timeless facts | `room(rooma).` |
| a precondition on such a predicate | a denial calling the fact, with no time | `false move(A,B) from T1 to T2, not room(A).` |
| the rest of `:init` | `initially` | `initially 'at-robby'(rooma), free(left), free(right), …` |
| `(:goal (and …))` | `achieve` | `achieve on(d,c), on(c,b), on(b,a).` |
| a PDDL name | a lower-case Prolog atom, quoted when it contains a hyphen | `(PICK-UP B)` becomes `'pick-up'(b)` |
| `?x` | a variable, shared across all the sentences of one action | `stack(A,B) … initiates on(A,B).` |

### Preconditions are denials

A PDDL precondition is a condition an action needs. LPS has no separate notion
of a guard; it has constraints (`false …`), which say what must never happen.
Each literal of a precondition becomes its own denial about the state the action
*starts* from (`at T1`). This is the same mechanism an LPS author uses for
preconditions ([Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)),
so the translated program explains a refused action the way any other LPS
program does.

### Static predicates are timeless facts

Many PDDL domains write types as predicates: gripper's `(room ?r)`,
`(ball ?b)` and `(gripper ?g)`. A predicate that appears in `:init` but in no
action's effect never changes, so it becomes a set of timeless facts rather
than a fluent, and a precondition on it calls the fact directly. This keeps it
out of every state the planner builds.

### The goal and the planner

The goal becomes `achieve`, and the program is put into planning mode with
`search(auto)`, a horizon of 20 cycles and one action per cycle
(`max_concurrency(1)`, which matches PDDL's sequential plans). The planner is
the one every LPS program uses; nothing about it is specific to PDDL. `auto`
starts with breadth-first search, which finds a shortest plan, and switches to
greedy best-first search when a node budget runs out, which finds a plan
quickly but not always a shortest one. See
[Planning](../reference/lps.md#14-planning) for the options.

### How plans are checked

The simulator that judges a plan reads the PDDL files and applies the PDDL
definitions directly: every action's precondition must hold in the state it
starts from, and the goal must hold at the end. It shares no code with the
translation, so a mistake in the translation cannot hide in the check. It does
not judge whether a plan is the shortest; the test of this integration reports
plan lengths beside the benchmarks' known shortest instead.

The current results over `examples/planning/`: eleven of the twelve problems
are solved with a valid plan, and ten of those plans are the shortest known.
`gripper-p1` gets a valid plan of 15 steps where 11 is possible, because the
search switched to greedy. `logistics-p1` does not finish: the planner is still
searching long after any reasonable wait (more than forty minutes).

## Traps

- **Opening a domain and a problem together with File ▸ Open… does not
  currently work.** The IDE converts each selected file separately, so the
  domain arrives with the error `a PDDL domain has no goal on its own` and the
  problem with `a PDDL problem has no actions on its own`, in two tabs. The
  example picker pairs them correctly, and so does `./lps pddl`.
- **The subset is STRIPS with negative preconditions.** Four whole sections
  are refused with a warning and ignored: `:functions`, `:durative-action`,
  `:derived` and `:constraints`.
- **Other constructs are not reported, and the program comes out wrong.**
  Inside an action or a goal, the following are not recognised, and there is no
  warning:
  - `or`, `forall`, `exists` in a precondition: the whole condition is dropped,
    so the action is allowed where PDDL would forbid it;
  - `when` (conditional effects) in an effect: dropped;
  - numeric effects such as `(increase (cost) 1)`: turned into a meaningless
    fluent;
  - equality, `(not (= ?x ?y))`: written as a condition on the state,
    `A=B at T1`, rather than as a comparison of the two parameters;
  - `(not …)` in the `:goal`: produces an `achieve` that does not compile.

  Stick to conjunctions of literals, or check the converted program by eye.
- **Types are not enforced.** `:types` and the types of `:parameters` and
  `:objects` produce nothing. A parameter is constrained only by the
  preconditions that mention it. Domains that write their types as static
  predicates (gripper's `(room ?r)`) are unaffected; a typed domain whose
  types matter only through `- type` annotations may get plans that use
  objects of the wrong type.
- **Names are lower-cased.** PDDL is case-insensitive; LPS is not. `BLOCKS` and
  `C` become `blocks` and `c`. A name with a hyphen becomes a quoted atom,
  `'pick-up'`, which you must keep quoted when you edit the program.
- **`at` is an LPS operator.** A PDDL predicate called `at`, as in gripper's
  `(at ?b ?r)`, is written `ball1 at rooma` and `_ at _` in the converted
  program. It is still the fluent `at/2`, not a time; it only reads like one.
- **The horizon may be too short.** The converted program plans at most 20
  cycles ahead, with `maxTime(24)`. A problem whose shortest plan is longer
  finds no plan until you raise `horizon(…)` in the `lps_engine` directive and
  `maxTime` with it (`maxTime` must exceed the plan's length). The test runs
  `gripper-p2` with a horizon of 30.
- **Plans are sequential.** `max_concurrency(1)` gives one action per cycle, as
  in PDDL. LPS can take several actions in one cycle; raising
  `max_concurrency` can give shorter runs, but the plan is then a list of sets
  of actions, which is no longer a PDDL plan.
- **Large problems are slow.** Breadth-first search is exponential and greedy
  search is not guaranteed to be quick; `logistics-p1` does not finish. Try
  `search(greedy)` when `auto` spends its time in breadth-first search, and
  expect plans that are valid but not shortest.
- **The conversion is a copy, not a link.** Editing the converted program does
  not change the PDDL, and editing the PDDL means opening it again.
- **The problem file identifies itself by its text.** A file is taken as a
  problem when the word `problem` follows the word `define` within a few
  characters anywhere in it, comments included. A domain with such a comment
  is mistaken for a problem.

## See also

- In this documentation:
  - [Other systems and LPS](index.md), the overview of the integrations.
  - [Planning](../reference/lps.md#14-planning) and
    [Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)
    in the language reference.
  - [Planning: `achieve`](../tutorials/lps-tutorial.md#10-planning-achieve) in the tutorial.
  - [The menus](../guide/ide.md#the-menus) in the editor guide.
  - [PDDL](../overview/introducing-lps2.md#18-pddl) in *Introducing LPS2*, for
    how this door was built and tested.
- PDDL's own world:
  - The International Planning Competition, where the benchmark domains come
    from: <https://www.icaps-conference.org/competitions/>
  - VAL, the plan validator used by the planning community:
    <https://github.com/KCL-Planning/VAL>
