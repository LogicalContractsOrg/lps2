# PDDL and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

PDDL, the Planning Domain Definition Language, is the standard language of
automated planning and of the International Planning Competition. A PDDL
program comes in two files. The *domain* file declares predicates and actions,
each action with the preconditions it needs and the effects it has. The
*problem* file names the objects, the initial state and the goal. LPS2 reads
the two files together and turns them into an ordinary LPS (Logic Production
System) program whose goal is an `achieve`, which LPS2's own planner then
solves. The door goes one way only: PDDL into LPS. Nothing writes an LPS
program back out as PDDL. The PDDL reader is part of LPS2 itself and needs
nothing else — no Logical English, and no planner from outside. In the IDE (the
editor you write and run programs in) you reach the reader through **File ▸
Open example from server…**, in the *Planning* folder, and through **File ▸
Open…**. On the command line you reach the reader through `./lps pddl`.

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
   (`examples/planning/`). It holds seven domains — `blocks`, `gripper`,
   `hanoi`, `elevator`, `rover`, `logistics`, and `lights`, which uses types,
   quantifiers, disjunctions and conditional effects — and their problems.
2. Pick a **problem** file, for example `blocks-p1.pddl`. The server finds the
   matching domain for you. The problem file says `(:domain BLOCKS)`, so the
   server uses the domain file in the same folder that says `(define (domain
   BLOCKS) …)`. The two files arrive as one LPS program, in one tab.
3. Press **Run**. The planner searches for a plan, and then LPS's ordinary
   cycle carries the plan out, one action per cycle from cycle 2 onwards. The
   Timeline pane shows the actions; the Changes pane shows what each action did.
4. **View ▸ The original this was converted from** shows both source files, one
   after the other, each under a `% ==== name ====` line.

If you pick a *domain* file on its own, the tab holds only the note and an
error: `a PDDL domain has no goal on its own`.

### Your own PDDL files

**File ▸ Open…** accepts `.pddl` files and sends them to the server to be
converted. Select the domain and its problem together, in one go. The server
tells the two files apart by what each one says (`(define (problem …` or
`(define (domain …`), not by the file names. The server then pairs each problem
with the domain that the problem names, and opens each pair as one program. If
you choose a problem without its domain, or a domain without a problem, the
file opens with an error that says what is missing.

Once the conversion is done, the tab holds an ordinary LPS program. Save the
program, edit it and run it like any other. Nothing ties the program to the
PDDL files any more.

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

The command writes the plan in PDDL's own plan format, and the simulator then
checks the plan. The command exits with status 1 when it finds no plan, or when
the plan it found is not valid. You can set the planner's options with flags:

| Flag | Default | Meaning |
|---|---|---|
| `--horizon N` | 20 | the longest plan, in cycles |
| `--search bfs\|greedy\|auto` | `auto` | the search; see [Planning](../reference/lps.md#14-planning) |
| `--max-time N` | horizon + 4 | the program's `maxTime` |

Before the plan, the command prints a warning for each part of the PDDL it did
not translate. The warnings go to the error channel, standard error, and not
into the plan itself.

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

The translator adds the last two lines so that the program runs as it stands,
because `achieve` is an error unless the program is in planning mode.

When something in the PDDL was not translated, the note at the top of the
program gains a section headed `% What did not carry over:`, with one line for
each warning.

The program you see is in LPS's written form, not in the internal form the
translator produces. The writer checks its own work: the writer reads back the
sentences it has just written and compares them with what it was given. If the
two do not match, the tab shows the internal form instead, under a comment
saying so, together with the warning
`shown in internal syntax: the surface rendering did not round-trip`.

## How PDDL maps to LPS

| PDDL | LPS | Example (from `blocks` and `gripper`) |
|---|---|---|
| `(:action a :parameters …)` | an action declaration | `actions 'pick-up'(_), 'put-down'(_), stack(_,_), unstack(_,_).` |
| a predicate that some effect changes | a fluent declaration | `fluents handempty, clear(_), holding(_), ontable(_), on(_,_).` |
| a positive literal in `:effect` | a causal law with `initiates` | `'pick-up'(A) from T1 to T2 initiates holding(A).` |
| `(not L)` in `:effect` | a causal law with `terminates` | `'pick-up'(A) from T1 to T2 terminates ontable(A).` |
| a positive literal in `:precondition` | a denial: the action may not happen when the literal is false at its start | `false 'pick-up'(A) from T1 to T2, not clear(A) at T1.` |
| `(not L)` in `:precondition` | a denial: the action may not happen when the literal is true at its start | schematically, `false a(X) from T1 to T2, p(X) at T1.` |
| `(or A B)` in `:precondition` | one denial over both negations: the action may not happen when neither holds | `false go(A,B) from T1 to T2, not door(A,B), not door(B,A).` |
| `(= ?x ?y)` | a comparison of the two names, not a state | `false go(A,B) from T1 to T2, A==B.` |
| `(exists (?l - lamp) P)` | a variable generated by its type; under a denial, a negation over the conjunction | `false flip(A,B) from T1 to T2, not [of_type(C,lamp),wired(A,C)] at T1.` |
| `(forall (?l - lamp) P)`, `(imply A B)` | `(not (exists (?l - lamp) (not P)))`, `(or (not A) B)` | `false 'tidy-up'(A) from T1 to T2, of_type(B,lamp), B in A, on(B) at T1, broken(B).` |
| `(when C E)`, `(forall (?v) E)` in `:effect` | a causal law with conditions (one per alternative of C), evaluated in the state the action starts from | `flip(A,B) from T1 to T2 initiates on(C) if of_type(C,lamp), wired(A,C), not broken(C).` |
| a typed parameter `?x - room` | a denial: the action may not happen with an argument of another type (left out when every object has the type) | `false go(A,B) from T1 to T2, not of_type(A,room).` |
| `:types`, `:objects` and `:constants` with types | a timeless fact per object and type, supertypes included, for the types the program asks about | `of_type(hall, room).` |
| a predicate no effect changes, true in `:init` | timeless facts | `room(rooma).` |
| a precondition on such a predicate | a denial calling the fact, with no time | `false move(A,B) from T1 to T2, not room(A).` |
| the rest of `:init` | `initially` | `initially 'at-robby'(rooma), free(left), free(right), …` |
| `(:goal (and …))` | `achieve` | `achieve on(d,c), on(c,b), on(b,a).` |
| `(not L)` in the `:goal` | `not L` in `achieve` | `achieve at(kitchen), not on('strip-light').` |
| any other `:goal` (`or`, `exists`, `forall`) | an intensional fluent, one clause per alternative, and `achieve` of it | `goal_reached at T1 if tidy(kitchen) at T1, not on('ceiling-lamp') at T1.` |
| a PDDL name | a lower-case Prolog atom, quoted when it contains a hyphen | `(PICK-UP B)` becomes `'pick-up'(b)` |
| `?x` | a variable, shared across all the sentences of one action | `stack(A,B) … initiates on(A,B).` |

### Preconditions are denials

A PDDL precondition is a condition that an action needs before the action can
happen. LPS has no separate idea of a guard. What LPS has instead is
constraints (`false …`), which say what must never happen. Each literal of a
precondition becomes a denial of its own, about the state the action *starts*
from (`at T1`). An LPS author writing preconditions by hand uses exactly the
same mechanism ([Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)),
so a translated program explains a refused action the way any other LPS program
does.

### Static predicates are timeless facts

Many PDDL domains write types as predicates, as gripper does with `(room ?r)`,
`(ball ?b)` and `(gripper ?g)`. A predicate that appears in `:init` but in no
action's effect never changes. Such a predicate becomes a set of timeless facts
rather than a fluent, and a precondition that mentions the predicate calls the
fact directly. Because the predicate is not a fluent, the predicate stays out
of every state the planner builds.

### The goal and the planner

The goal becomes `achieve`, and the translator puts the program into planning
mode with `search(auto)`, a horizon of 20 cycles, and one action per cycle
(`max_concurrency(1)`, which matches PDDL's one-action-at-a-time plans). The
planner is the one every LPS program uses, and nothing in the planner is
special to PDDL. `auto` begins with breadth-first search, which finds a
shortest plan. When breadth-first search has explored as many states as its
budget allows, `auto` switches to greedy best-first search, which finds a plan
quickly but not always a shortest one. See
[Planning](../reference/lps.md#14-planning) for the options.

### How plans are checked

The simulator that judges a plan reads the PDDL files and applies the PDDL
definitions directly. Every action's precondition must hold in the state the
action starts from, and the goal must hold at the end. The simulator and the
translation are built separately and share no code, so a mistake in the
translation cannot hide inside the check. The simulator does not judge whether
a plan is the shortest one. Instead, the test of this integration reports each
plan's length beside the shortest length known for that benchmark.

The simulator works out the truth of PDDL's formulas itself: `and`, `or`,
`not`, `imply`, `exists` and `forall` over the objects of the problem, `=`, the
types of an action's arguments, and conditional and universal effects.

Here are the results over `examples/planning/` as things stand. Thirteen of the
fourteen problems are solved with a valid plan, and twelve of those plans are
the shortest known.
`gripper-p1` gets a valid plan of 15 steps where 11 steps are possible, because
the search switched to greedy. `logistics-p1` never finishes: the planner is
still searching long after any reasonable wait, more than forty minutes.

## Traps

- **The domain and the problem must be chosen together.** If you open them one
  after the other in **File ▸ Open…**, you get two tabs and two errors: `a PDDL
  domain has no goal on its own` and `a PDDL problem has no actions on its
  own`.
- **No numeric fluents, durative actions, axioms or trajectory constraints.**
  The translator refuses five whole sections with a warning and then ignores
  them: `:functions`, `:durative-action`, `:derived` and `:constraints` in the
  domain, and `:metric` (as well as `:constraints`) in the problem. Inside an
  action, inside the init or inside the goal, each piece of arithmetic gets a
  warning of its own that names it. A numeric effect
  (`(increase (total-cost) 1)`) is ignored. A numeric condition
  (`(> (fuel) 0)`) is read as already satisfied. A numeric value in `:init`
  (`(= (fuel) 3)`) is left out. A domain whose plans depend on numbers
  therefore gets plans that ignore the numbers, so read the warnings.
- **Quantifiers range over the objects of the problem and of `:constants`.**
  A variable without a type ranges over all of those objects. The translator
  expands each quantifier into denials and conditions, rewriting the formula as
  a list of alternatives (disjunctive normal form), so one large nested formula
  turns into many sentences.
- **A goal that is not a conjunction of literals** becomes `goal_reached`, an
  intensional fluent. Greedy search measures the distance to `goal_reached` as
  a single goal, so the measurement guides the search less well than a list of
  separate literals would.
- **Types are checked on arguments, not on facts.** A typed parameter gives a
  denial on the action. Nothing here stops `:init` from stating
  `(at wall-switch)` for a switch that is not a room, and PDDL itself does not
  stop `:init` from doing so either.
- **The translation takes the name `of_type` for itself.** The type facts are
  written `of_type(Object, Type)`. When the domain already has a predicate of
  that name, the translation uses `pddl_of_type` instead. The goal fluent works
  the same way: normally `goal_reached`, but `pddl_goal_reached` when the
  domain already uses the name.
- **Names are lower-cased.** PDDL does not care about capital letters; LPS
  does. `BLOCKS` and `C` become `blocks` and `c`. A name with a hyphen becomes
  a quoted atom, `'pick-up'`, which you must keep quoted when you edit the
  program.
- **`at` is an LPS operator.** The converted program writes a PDDL predicate
  called `at`, as in gripper's `(at ?b ?r)`, as `ball1 at rooma` and `_ at _`.
  The predicate is still the fluent `at/2` and not a time; the predicate only
  reads like a time.
- **The horizon may be too short.** The converted program plans at most 20
  cycles ahead, with `maxTime(24)`. If a problem's shortest plan is longer than
  that, the planner finds no plan until you raise `horizon(…)` in the
  `lps_engine` directive and raise `maxTime` with it (`maxTime` must be greater
  than the plan's length). The test runs `gripper-p2` with a horizon of 30.
- **Plans are sequential.** `max_concurrency(1)` gives one action per cycle, as
  in PDDL. LPS can take several actions in one cycle. Raising `max_concurrency`
  can make a run shorter, but the plan then becomes a list of sets of actions,
  and a list of sets is no longer a PDDL plan.
- **Large problems are slow.** Breadth-first search grows explosively as plans
  get longer, and greedy search is not guaranteed to be quick either;
  `logistics-p1` never finishes. Try `search(greedy)` when `auto` spends its
  time in breadth-first search, and expect plans that are valid but not
  shortest.
- **The conversion is a copy, not a link.** Editing the converted program does
  not change the PDDL, and to take up a change to the PDDL you must open the
  PDDL again.
- **The problem file identifies itself by its text.** The server takes a file
  to be a problem when the word `problem` follows the word `define` within a
  few characters, anywhere in the file, comments included. A domain that
  happens to contain such a comment is mistaken for a problem.

## See also

- In this documentation:
  - [Other systems and LPS](index.md), the overview of the integrations.
  - [Planning](../reference/lps.md#14-planning) and
    [Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)
    in the language reference.
  - [Planning: `achieve`](../tutorials/lps-tutorial.md#10-planning-achieve) in the tutorial.
  - [The menus](../guide/ide.md#the-menus) in the editor guide.
  - [PDDL, inside](../overview/introducing-lps2-technical.md#12-pddl-inside) in
    *LPS2 in detail*, for how this door was built and tested.
- PDDL's own world:
  - The International Planning Competition, where the benchmark domains come
    from: <https://www.icaps-conference.org/competitions/>
  - VAL, the plan validator used by the planning community:
    <https://github.com/KCL-Planning/VAL>
