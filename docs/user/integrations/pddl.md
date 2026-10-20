# PDDL and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

PDDL is the Planning Domain Definition Language. PDDL is the standard language of
automated planning and of the International Planning Competition. A PDDL program has
two files. The *domain* file declares predicates and actions. For each action, it
gives the preconditions that the action needs and the effects that the action has.
The *problem* file gives the objects, the initial state and the goal.

LPS2 reads the two files together. It changes them into a usual LPS (Logic Production
System) program. The goal of that program is an `achieve`. The planner of LPS2 then
finds a solution. The translation goes in one direction only: from PDDL into LPS.
Nothing writes an LPS program as PDDL. The PDDL reader is part of LPS2 itself, and it
needs nothing more. It does not need Logical English or a planner from outside.

In the IDE, you get to the reader with **File ▸ Open example from server…**, in the
*Planning* folder. You can also use **File ▸ Open…**. The IDE is the editor in which
you write and run programs. On the command line, you get to the reader with
`./lps pddl`.

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
| PDDL into LPS | **File ▸ Open example from server…** (folder *Planning*); **File ▸ Open…** (refer to the trap about how to open two files) | a domain `.pddl` and a problem `.pddl` | an LPS program in the written form, with the name of the problem (`blocks-p1.lps`). A note tells the origin of the program. You can run the program with the planner immediately. | a separate PDDL plan simulator. The simulator reads the PDDL files, not the translation. It tells if the plan is correct and gets to the goal. A test also compares the plan lengths with the known shortest plans of the benchmarks |
| PDDL into a plan | command line: `./lps pddl DOMAIN PROBLEM` | the same two files | the plan in the plan format of PDDL, followed by the verdict of the simulator | the same simulator |

## How to use it

### From the examples on the server

Do these steps:

1. Select **File ▸ Open example from server…**.
2. Open the *Planning* folder (`examples/planning/`). The folder contains seven
   domains and their problems. The domains are `blocks`, `gripper`, `hanoi`,
   `elevator`, `rover`, `logistics` and `lights`. `lights` uses types, quantifiers,
   disjunctions and conditional effects.
3. Select a **problem** file, for example `blocks-p1.pddl`.

The server finds the related domain for you. The problem file says
`(:domain BLOCKS)`. Thus the server uses the domain file in the same folder that says
`(define (domain BLOCKS) …)`. The two files become one LPS program, in one tab.

Then do these steps:

1. Click **Run**.
2. Look at the **Timeline** pane. It shows the actions.
3. Look at the **Changes** pane. It shows what each action did.

The planner looks for a plan. Then the usual cycle of LPS does the plan, one action
in each cycle, from cycle 2. **View ▸ The original this was converted from** shows
the two source files, one after the other. Each file is below a `% ==== name ====`
line.

If you select a *domain* file alone, the tab contains only the note and an error:
`a PDDL domain has no goal on its own`.

### Your own PDDL files

**File ▸ Open…** accepts `.pddl` files. It sends them to the server for conversion.
Select the domain and its problem together, at the same time. The server finds which
file is which from the text in each file (`(define (problem …` or
`(define (domain …`), not from the file names. The server then puts each problem
together with the domain that the problem names. It opens each pair as one program.
Possibly you select a problem without its domain, or a domain without a problem.
Then the file opens with an error that tells what is missing.

After the conversion, the tab contains a usual LPS program. You can save, edit and
run the program, as all other programs. The program has no connection to the PDDL
files after the conversion.

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

The command writes the plan in the plan format of PDDL. The simulator then examines
the plan. The command stops with status 1 when it finds no plan. It also stops with
status 1 when the plan that it found is not correct. You can set the options of the
planner with flags:

| Flag | Default | Meaning |
|---|---|---|
| `--horizon N` | 20 | the longest plan, in cycles |
| `--search bfs\|greedy\|auto` | `auto` | the search method; refer to [Planning](../reference/lps.md#14-planning) |
| `--max-time N` | horizon + 4 | the `maxTime` of the program |

Before the plan, the command prints a warning for each part of the PDDL that it did
not translate. The warnings go to the error channel, standard error. They do not go
into the plan.

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

The translator adds the last two lines. With these lines, the program runs without
changes. The reason is that `achieve` is an error when the program is not in
planning mode.

Possibly the translator did not translate a part of the PDDL. Then the note at the
top of the program gets a section with the heading `% What did not carry over:`. The
section has one line for each warning.

The program that you see is in the written form of LPS. It is not in the internal
form that the translator makes. The writer examines its own work. It reads the
sentences that it wrote, and compares them with the data that it received. If the
two do not agree, the tab shows the internal form. A comment above the internal form
tells this. The tab also shows the warning
`shown in internal syntax: the surface rendering did not round-trip`.

## How PDDL maps to LPS

| PDDL | LPS | Example (from `blocks` and `gripper`) |
|---|---|---|
| `(:action a :parameters …)` | an action declaration | `actions 'pick-up'(_), 'put-down'(_), stack(_,_), unstack(_,_).` |
| a predicate that an effect changes | a fluent declaration | `fluents handempty, clear(_), holding(_), ontable(_), on(_,_).` |
| a positive literal in `:effect` | a causal law with `initiates` | `'pick-up'(A) from T1 to T2 initiates holding(A).` |
| `(not L)` in `:effect` | a causal law with `terminates` | `'pick-up'(A) from T1 to T2 terminates ontable(A).` |
| a positive literal in `:precondition` | a denial: the action cannot occur when the literal is false at its start | `false 'pick-up'(A) from T1 to T2, not clear(A) at T1.` |
| `(not L)` in `:precondition` | a denial: the action cannot occur when the literal is true at its start | in a general form, `false a(X) from T1 to T2, p(X) at T1.` |
| `(or A B)` in `:precondition` | one denial for the two negations: the action cannot occur when A and B are both false | `false go(A,B) from T1 to T2, not door(A,B), not door(B,A).` |
| `(= ?x ?y)` | a comparison of the two names, not a state | `false go(A,B) from T1 to T2, A==B.` |
| `(exists (?l - lamp) P)` | a variable that its type generates; in a denial, a negation of the conjunction | `false flip(A,B) from T1 to T2, not [of_type(C,lamp),wired(A,C)] at T1.` |
| `(forall (?l - lamp) P)`, `(imply A B)` | `(not (exists (?l - lamp) (not P)))`, `(or (not A) B)` | `false 'tidy-up'(A) from T1 to T2, of_type(B,lamp), B in A, on(B) at T1, broken(B).` |
| `(when C E)`, `(forall (?v) E)` in `:effect` | a causal law with conditions (one for each alternative of C), calculated in the state at the start of the action | `flip(A,B) from T1 to T2 initiates on(C) if of_type(C,lamp), wired(A,C), not broken(C).` |
| a typed parameter `?x - room` | a denial: the action cannot occur with an argument of a different type (not added when all objects have the type) | `false go(A,B) from T1 to T2, not of_type(A,room).` |
| `:types`, `:objects` and `:constants` with types | a timeless fact for each object and type, also for the supertypes, for the types that the program asks about | `of_type(hall, room).` |
| a predicate that no effect changes, true in `:init` | timeless facts | `room(rooma).` |
| a precondition on such a predicate | a denial that calls the fact, with no time | `false move(A,B) from T1 to T2, not room(A).` |
| the remaining part of `:init` | `initially` | `initially 'at-robby'(rooma), free(left), free(right), …` |
| `(:goal (and …))` | `achieve` | `achieve on(d,c), on(c,b), on(b,a).` |
| `(not L)` in the `:goal` | `not L` in `achieve` | `achieve at(kitchen), not on('strip-light').` |
| all other forms of `:goal` (`or`, `exists`, `forall`) | an intensional fluent, with one clause for each alternative, and `achieve` of that fluent | `goal_reached at T1 if tidy(kitchen) at T1, not on('ceiling-lamp') at T1.` |
| a PDDL name | a Prolog atom in lower case, with quotes when it contains a hyphen | `(PICK-UP B)` becomes `'pick-up'(b)` |
| `?x` | a variable, the same in all the sentences of one action | `stack(A,B) … initiates on(A,B).` |

### Preconditions are denials

A PDDL precondition is a condition that an action needs before the action can occur.
LPS does not have a separate idea of a guard. A guard is a condition that must be
true before an action can occur. LPS has constraints (`false …`) instead. A
constraint tells what must never occur. Each literal of a precondition becomes a
separate denial. A denial is a constraint that says that a combination must never be
true. The denial is about the state at the *start* of the action (`at T1`). An LPS
author who writes preconditions by hand uses exactly the same mechanism
([Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)).
Thus a translated program explains a refused action in the same way as all other
LPS programs.

### Static predicates are timeless facts

Many PDDL domains write types as predicates. For example, gripper has `(room ?r)`,
`(ball ?b)` and `(gripper ?g)`. Possibly a predicate is in `:init`, but it is not in
the effect of an action. Then the predicate never changes. Such a predicate becomes
a set of timeless facts, not a fluent. A precondition that refers to the predicate
calls the fact directly. Because the predicate is not a fluent, it is not in the
states that the planner makes.

### The goal and the planner

The goal becomes `achieve`. The translator puts the program into planning mode with
`search(auto)`, a horizon of 20 cycles, and one action in each cycle
(`max_concurrency(1)`). One action in each cycle agrees with PDDL plans, which do one
action at a time. All LPS programs use the same planner. No part of the planner is
special for PDDL.

`auto` starts with a breadth-first search, which finds a shortest plan. The
breadth-first search can visit only a fixed maximum number of states. When it gets
to that maximum, `auto` changes to a greedy best-first search. A greedy best-first
search finds a plan quickly, but the plan is possibly not a shortest plan. Refer to
[Planning](../reference/lps.md#14-planning) for the options.

### How plans are checked

The simulator that examines a plan reads the PDDL files. It uses the PDDL definitions
directly. The precondition of each action must be true in the state at the start of
the action. The goal must be true at the end. The simulator and the translation are
separate, and they have no code in common. Thus a mistake in the translation cannot
hide inside the check. The simulator does not tell if a plan is the shortest plan.
But the test of this integration gives the length of each plan next to the shortest
known length for that benchmark.

The simulator itself calculates the truth of the PDDL formulas. It knows `and`, `or`,
`not`, `imply`, `exists` and `forall` over the objects of the problem. It also knows
`=`, the types of the arguments of an action, and conditional and universal effects.

These are the current results for `examples/planning/`. The planner finds a correct
plan for thirteen of the fourteen problems. Twelve of those plans are the shortest
known plans. For `gripper-p1`, the plan is correct and has 15 steps, but 11 steps
are possible. The reason is that the search changed to greedy. `logistics-p1` never
ends. After more than forty minutes, the planner still looks for a plan. This is
much longer than a reasonable wait.

## Traps

- **You must select the domain and the problem together.** If you open them one
  after the other in **File ▸ Open…**, you get two tabs and two errors:
  `a PDDL domain has no goal on its own` and `a PDDL problem has no actions on its own`.
- **The translator does not accept numeric fluents, durative actions, axioms or
  trajectory constraints.** The translator refuses five full sections with a warning,
  and then ignores them. These sections are `:functions`, `:durative-action`,
  `:derived` and `:constraints` in the domain, and `:metric` (and also
  `:constraints`) in the problem. Inside an action, the init or the goal, each part
  of arithmetic gets its own warning with its name. The translator ignores a numeric
  effect (`(increase (total-cost) 1)`). It reads a numeric condition
  (`(> (fuel) 0)`) as already true. It does not include a numeric value in `:init`
  (`(= (fuel) 3)`). Thus a domain whose plans depend on numbers gets plans that
  ignore the numbers. Read the warnings.
- **Quantifiers are about the objects of the problem and of `:constants`.** A
  variable without a type is about all of those objects. The translator expands
  each quantifier into denials and conditions. It writes the formula again as a list
  of alternatives (disjunctive normal form). Thus one large nested formula becomes
  many sentences.
- **A goal that is not a conjunction of literals** becomes `goal_reached`, an
  intensional fluent. An intensional fluent is a fluent that a rule defines. The
  greedy search measures the distance to `goal_reached` as one goal. Thus the
  measurement helps the search less than a list of separate literals.
- **The translator examines the types of arguments, not of facts.** A typed
  parameter gives a denial on the action. Nothing here prevents `:init` from saying
  `(at wall-switch)` for a switch that is not a room. PDDL itself also does not
  prevent this.
- **The translation uses the name `of_type` for itself.** The type facts have the
  form `of_type(Object, Type)`. When the domain already has a predicate with that
  name, the translation uses `pddl_of_type` instead. The goal fluent uses the same
  method. Usually its name is `goal_reached`. But its name is `pddl_goal_reached`
  when the domain already uses the name.
- **Names change to lower case.** For PDDL, capital letters have no effect. For LPS,
  they have an effect. `BLOCKS` and `C` become `blocks` and `c`. A name with a hyphen
  becomes an atom with quotes, `'pick-up'`. When you edit the program, you must keep
  the quotes.
- **`at` is an LPS operator.** Possibly a PDDL predicate has the name `at`, as
  `(at ?b ?r)` in gripper. The converted program writes it as `ball1 at rooma` and
  `_ at _`. The predicate is still the fluent `at/2`, not a time. It only looks like
  a time.
- **The horizon can be too short.** The converted program plans a maximum of 20
  cycles forward, with `maxTime(24)`. Possibly the shortest plan of a problem is
  longer than that. Then the planner finds no plan. To correct this, make
  `horizon(…)` larger in the `lps_engine` directive. Make `maxTime` larger at the
  same time (`maxTime` must be larger than the length of the plan). The test runs
  `gripper-p2` with a horizon of 30.
- **Plans are sequential.** `max_concurrency(1)` gives one action in each cycle, as
  in PDDL. LPS can do more than one action in one cycle. A larger `max_concurrency`
  can make a run shorter. But then the plan becomes a list of sets of actions. A list
  of sets is not a PDDL plan.
- **Large problems are slow.** The breadth-first search becomes very much larger
  when plans become longer. The greedy search is also possibly not quick.
  `logistics-p1` never ends. When `auto` uses its time in the breadth-first search,
  try `search(greedy)`. Then expect plans that are correct but possibly not
  shortest.
- **The conversion is a copy, not a link.** When you edit the converted program, the
  PDDL does not change. To use a change in the PDDL, you must open the PDDL again.
- **The server finds the problem file from its text.** The server thinks that a file
  is a problem when the word `problem` comes a few characters after the word
  `define`. This can be at any position in the file, also in comments. Thus a domain
  that contains such a comment by accident looks like a problem to the server.

## See also

- In this documentation:
  - [Other systems and LPS](index.md), the overview of the integrations.
  - [Planning](../reference/lps.md#14-planning) and
    [Constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)
    in the language reference.
  - [Planning: `achieve`](../tutorials/lps-tutorial.md#10-planning-achieve) in the tutorial.
  - [The menus](../guide/ide.md#the-menus) in the editor guide.
  - [PDDL, inside](../overview/introducing-lps2-technical.md#12-pddl-inside) in
    *LPS2 in detail*. This document tells how we made and tested this translation.
- Other PDDL resources:
  - The International Planning Competition, the origin of the benchmark domains:
    <https://www.icaps-conference.org/competitions/>
  - VAL, the plan validator that the planning community uses:
    <https://github.com/KCL-Planning/VAL>
