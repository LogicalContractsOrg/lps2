# Learning LPS

*Kind: tutorial · Audience: users · Status: current (2026-09-29)*

This tutorial is an introduction to LPS2. LPS stands for Logic Production System.
The tutorial is for a person who can write programs, but who has never written a
reactive rule. A reactive rule tells the program what to do when a condition becomes
true. The tutorial starts with a program of two lines. Then it goes step by step to
planning, explanations, and sessions that do not stop.

Use two documents together with this tutorial. [`lps.md`](../reference/lps.md) is the
reference. The reference gives each construct, each declaration and the operator
table. Keep the reference open next to this tutorial.
[`glossary.md`](../reference/glossary.md) defines the terms.
[How a program runs](how-lps-runs.md) is the companion tutorial. The companion
tutorial tells you the order in which the engine does things. It tells you which goal
goes first, when an action waits, and why a run fails. Read the companion tutorial
after §8 below.

Each picture below came from the real editor, which a program operated in a browser.
We ran each program below before we copied it into this tutorial.

---

## Contents

1. [Getting it running](#1-getting-it-running)
2. [The first program](#2-the-first-program)
3. [The five kinds of sentence](#3-the-five-kinds-of-sentence)
4. [Reading a run](#4-reading-a-run)
5. [Events from outside](#5-events-from-outside)
6. [Composite events](#6-composite-events)
7. [Intensional fluents](#7-intensional-fluents)
8. [Constraints](#8-constraints)
9. [Constraints about what an action would bring about](#9-constraints-about-what-an-action-would-bring-about)
10. [Planning: `achieve`](#10-planning-achieve)
11. [Prolog inside LPS](#11-prolog-inside-lps)
12. [Drawing a program: `display/2` and `display3d/2`](#12-drawing-a-program-display2-and-display3d2)
13. [Asking why](#13-asking-why)
14. [Programs that do not stop](#14-programs-that-do-not-stop)
15. [Where to go next](#15-where-to-go-next)
16. [Ten mistakes that are easy to make](#16-ten-mistakes-that-are-easy-to-make)

---

## 1. Getting it running

```sh
git clone …  &&  cd lps2
./lps run examples/start/goat_declarative.pl        # from the command line
./lps ide                                     # the editor, in a browser
```

You must build the editor one time, before you use it for the first time. To build
the editor, you need Node. Node is a program that runs JavaScript outside a browser.
After the build, the editor does not need Node. The packaged copy of the system that
runs on a server does not contain Node.

```sh
cd ui && npm install && npm run build
```

Then open <http://localhost:3060>. That address is the **start page**. The start page
shows the documents and a list of all the example programs on the server. The list
puts each program below the name of its folder. Click a program, and the editor opens
with that program in it. To go directly to the editor, open
<http://localhost:3060/ide>.

![The editor](../images/ide-overview.png)

The screen has three parts.

**At the top** is the only row of controls. The menus are on the left. On the right
are `maxTime` and **Run**, then the result of the last run, and then **Live** and
**Play**. The **Live** and **Play** buttons open panels below the editor. The last
three items of the **View** menu also open these panels. The panels are the
assistant, the live session and the play panel. The play panel is for an
interactive-fiction story. At the start, the panels are closed. A closed panel shows
nothing.

**On the left** is the text of your program. The editor on the left knows LPS, and it
also knows the Prolog that you can write inside an LPS program. You can open
different files at the same time, each file in its own tab. Each tab has its own run.
Thus you can keep two programs open and go from one to the other. You do not lose the
result of either program.

**On the right** are six different views of a run. These views show the run of the
file in *this* tab. Before your first run, the right side of the screen tells you
what to do.

**Ctrl/Cmd + Enter** runs the program.

The editor shows each mistake on the line that contains the mistake. It puts a wavy
line below the mistake. Put the mouse pointer on the wavy line, and the editor shows
the message. The top bar shows the number of mistakes. Click that number, and the
editor goes to the first mistake.

[`ide.md`](../guide/ide.md) describes all of the editor. It also has a "how do I …"
section.

You do not have to start with an empty file. **File ▸ Open example from server**
shows a list of all 310 programs. 158 of the programs are from LPS1, and the other
programs are from this project. The list shows the first line of the comment of each
program as its description.

![The list of examples](../images/ide-examples.png)

---

## 2. The first program

```prolog
maxTime(6).

fluents  light(_).
actions  switch(_).

initially light(off).

switch(New) updates Old to New in light(Old).

if   light(off) at T1
then switch(on) from T1 to T2.
```

When you run the program, it prints this text:

```
fluents/0        [light(off)]
fluents/1        [light(off)]
events/2         [switch(on)]
fluents/2        [light(on)]
fluents/3        [light(on)]
…
success (success)
```

This small program already shows five things.

**A fluent is something that is true for a period of time.** A fluent is not a
variable that holds a value. `light(off)` is true from cycle 0 until something stops
it.

**An action is something that the program does.** You declare each action. An action
occurs only when a rule asks for it.

**A reactive rule is not an `if` statement.** Read
`if light(off) at T1 then switch(on) from T1 to T2` as a goal. Each time the
condition becomes true, the engine must make the conclusion true. This rule also
says when. The switch action starts at `T1`, the cycle in which the light was off.
An action always takes one step. Thus `T2` is the next cycle. Possibly the rule says
`from T2 to T3`, with new names for the two times. Then the engine can select the
cycle, and it selects the earliest permitted cycle.
[How a program runs §4](how-lps-runs.md#4-some-time-and-now) shows why this
difference is important.

**The causal law is separate from the rule that causes the action.** A causal law
tells what an action or an event does to the state.
`switch(New) updates Old to New in light(Old)` tells what `switch` *means*. The
reactive rule tells when to do the switch action. LPS programs have their shape
mainly because the causal law and the reactive rule are separate. You write how the
world operates one time only. Each rule that does an action then uses that
description, with no more work.

**The unit of time is the cycle.** `maxTime(6)` tells when to stop. Cycle 0 is the
initial state. The switch action occurs between cycles 1 and 2. The engine records
the action at cycle 2, because actions occur *between* states.

---

## 3. The five kinds of sentence

Almost all LPS programs contain five kinds of sentence. The table below gives the five
kinds with their correct names. It also gives the section of
[`lps.md`](../reference/lps.md) that shows the full form of each kind.

| kind | example | meaning |
|---|---|---|
| **declarations** | `fluents light(_).`  `actions switch(_).`  `events badge(_).` | the type of thing that each predicate is |
| **the initial state** | `initially light(off), door(shut).` | what is true at cycle 0 |
| **reactive rules** | `if C at T1 then A from T1 to T2.` | when C is true, make A occur |
| **causal laws** | `switch(N) initiates light(N).`, and also `terminates` and `updates … to … in …` | what an action or event does to the state |
| **constraints** | `false transfer(F,_,N) from T1 to _, balance(F,B) at T1, B < N.` | this must never be true |

`updates Old to New in f(Old)` has the same meaning as `terminates f(Old)` and
`initiates f(New)`, in one sentence. For a fluent that has a *value*, this form is
almost always the correct one.

Three more kinds of sentence have their own sections below: composite events (§6),
intensional fluents (§7), and `achieve` (§10).

---

## 4. Reading a run

Run the wolf, goat and cabbage program. Then look at the **Timeline**.

![The timeline](../images/ide-timeline.png)

The timeline has one row for each fluent. Each row shows a bar for the period of time
in which the fluent is true. Below the fluents are the events of each cycle. Below the
events are the composite events. The red dashed line shows the cycle that you look at.
The slider moves the red line. You can also click on the picture to move the red
line.

The timeline is not an additional mechanism that the engine needs only to show
things. The engine writes records to compare its results with LPS1. The editor makes
the timeline from these same records. Thus you do not have to switch on a part of the
engine to get the picture.

**Changes** gives the answer to a smaller question about one cycle: what changed, and
why.

![Changes](../images/ide-changes.png)

LPS1 did not have the last column. `line 24` is the causal law that operated, in the
file that you see. The table shows all the other fluents at that cycle as
*persisted*. A persisted fluent did not change. Thus the engine knows the difference
between "still true" and "made true again".

**Automaton** shows all of the run as a state machine. A state machine is a diagram
with one box for each situation of the program, and arrows for the changes between
the situations. Each different state shows one time only. Thus, when a program goes
back to an earlier state, the diagram shows a loop.

![The state-transition diagram](../images/ide-automaton.png)

The diagram above is `dining_philosophers_terse.pl`. The large box on the left is the
state in which all five forks are free. The run gets to that state at cycles 1 to 8.
For this reason, many arrows go to that box. Each box on the right is a person who
eats. Each of these boxes has a loop back to itself, for the time that the person
continues to eat. The diagram of the wolf-and-goat program is different: it is a
straight chain. That program never goes back to an earlier state, and the diagram
shows this.

**Internal** shows the form that the engine really runs.

![The internal form](../images/ide-internal.png)

`reactive_rule/2`, `d_pre/1`, `updated/4`, `initial_state/1`. The internal form is
the same form that LPS1 used. We kept that form on purpose. Look at the internal form
one time, because it makes three things clear. First, `false X, Y, Z` is a
constraint. Second, `at`, `from` and `to` are an easy way to write explicit time
arguments. Third, `achieve` is a fact, the same as other facts.

---

## 5. Events from outside

The program does not cause all events. `observe` gives an event that the world
caused:

```prolog
events   reading(_).

observe reading(31) from 2 to 3.
```

Events and actions have the same shape. They are different only in their origin. An
*action* is something that a rule decided to do. An *event* is something that
occurred to you. Actions and events are both causes. Each of them can be in
`initiates`, `terminates` and `updates`.

In a session that does not stop (§14), events come in through the network while the
program runs. These events replace `observe`.

---

## 6. Composite events

A composite event is a name for a *pattern* of other events during an interval.

```prolog
maxTime(8).

fluents  door(_), inside(_).
events   badge(_), pull(_).
actions  admit(_).

initially door(shut), inside(nobody).

observe badge(ann) from 1 to 2.
observe pull(ann)  from 2 to 3.

%  Two events, in that order, are one thing.
entry(P) from T1 to T3 if badge(P) from T1 to T2, pull(P) from T2 to T3.

if   entry(P) from T1 to T2
then admit(P) from T2 to T3.

admit(P) updates Old to P in inside(Old).
```

```
events/2         [badge(ann)]
events/3         [pull(ann)]
composites/3     [happens(entry(ann),1,3)]
events/4         [admit(ann)]
fluents/4        [door(shut),inside(ann)]
```

The engine records that `entry(ann)` occurs *from 1 to 3*. A composite event
continues for a period of time. This duration makes composite events useful. A rule
can refer to the full pattern, and it does not have to know the events in the
pattern.

Composite events also operate in the opposite direction, as decompositions. A
decomposition divides one thing into its parts. In the dining philosophers program,
`dine(P) if think(P), pickup_forks(…), eat(P), putdown_forks(…)` means "to dine, do
these four things". The sentence has the same shape as before. But you read it as a
plan, not as a pattern.

---

## 7. Intensional fluents

Some things are true because other things are true. If you keep such a thing
separately, you must keep two copies of the same fact in agreement.

```prolog
too_hot at T if temperature(N) at T, N > 30.

if   too_hot at T1
then alarm(heat) from T1 to T2.
```

No action initiates or terminates `too_hot`. Each time that something asks about
`too_hot`, the engine calculates it again from the state at that time. Declare
`too_hot` with `fluents`, the same as other fluents. Give it a rule with `at T if`.
Never give it a causal law.

When you run that program, the alarm operates in *each* cycle after the temperature
increases:

```
events/3         [reading(31)]
fluents/3        [temperature(31)]
events/4         [alarm(heat)]
events/5         [alarm(heat)]
events/6         [alarm(heat)]
```

The repeated alarm surprises all new users one time. A reactive rule gives the
engine a goal. The engine tries to satisfy that goal for all the time that the
condition is true. The rule does not operate only at the time when the condition
becomes true.

If you want the alarm to operate one time only, make the alarm change its own
condition to false. A pair of sentences such as `alarm(heat) initiates alarmed` and
`if too_hot at T, not alarmed at T then …` does exactly that.

---

## 8. Constraints

```prolog
false transfer(From, _, N) from T1 to _, balance(From, B) at T1, B < N.
```

Read `false` as "it must never be true that". The sentence above means: never
transfer more money than the payer has. It does not mean "write a warning in a log".
It does not mean "possibly do not do this". The engine will not accept a set of
actions that makes the sentence true.

```prolog
maxTime(6).

fluents  balance(_, _).
actions  transfer(_, _, _).

initially balance(alice, 100), balance(bob, 0).

transfer(From, To, N) updates Old to New in balance(From, Old) if New is Old - N.
transfer(From, To, N) updates Old to New in balance(To,   Old) if New is Old + N.

if   balance(alice, A) at T1, A >= 30
then transfer(alice, bob, 30) from T1 to T2.

false transfer(From, _, N) from T1 to _, balance(From, B) at T1, B < N.
```

```
fluents/1        [balance(alice,100),balance(bob,0)]
events/2         [transfer(alice,bob,30)]
fluents/2        [balance(alice,70),balance(bob,30)]
events/3         [transfer(alice,bob,30)]
fluents/3        [balance(alice,40),balance(bob,60)]
events/4         [transfer(alice,bob,30)]
fluents/4        [balance(alice,10),balance(bob,90)]
fluents/5        [balance(alice,10),balance(bob,90)]
```

The program does three transfers, and then it stops. No part of the program says
"stop after three". The condition of the rule, `A >= 30`, stops being true. Possibly
the condition stays true, for example if you change it to `A >= 0`. Then the
constraint refuses a fourth transfer. The rule connects each transfer to the cycle in
which its condition was true (`from T1 to T2`). Thus, after the refusal, the program
has a goal that it can never satisfy. The run ends in `failure` in cycle 4. With new
names for the times, `from T2 to T3`, the fourth transfer only waits. Then the run
ends in `success`. [How a program runs](how-lps-runs.md) explains this difference. It
also explains the order of all the other things that the engine does.

The condition and the constraint are both useful. The condition tells what the
program tries to do. The constraint makes sure that the program does not do a
different thing.

This is the largest difference between LPS and a rule engine: **the engine examines
a constraint. The thing that the constraint controls does not examine it.** For the
same reason, the examples from Kowalski's book *Computational Logic and Human
Thinking* are a very good fit for LPS.

---

## 9. Constraints about what an action would bring about

A usual constraint refers to the current state. But a constraint can also refer to
the state that an action *will* make.

```prolog
false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

The last condition, `row(_,_) to T`, makes the difference. That condition says that T
is the time at which a row action *ends*. Thus the engine reads the fluents in the
state that the crossing of the river will make. The full sentence thus means: after
each crossing, the goat must not stay alone with the wolf.

That is the real rule of the puzzle, and you write it one time only. The alternative
is to calculate by hand what the farmer must carry in each of six cases. Then you
must write those six cases in the program.

`examples/start/goat_declarative.pl` is exactly the program above.
`legacy_lps1/examples/goat.pl` is the same puzzle. In that file, the same knowledge
is in six different `dealWithGoat` clauses. Compare the two programs. This comparison
is the shortest argument for the language.

---

## 10. Planning: `achieve`

```prolog
:- lps_engine(planning, [search(auto), horizon(10), max_concurrency(2)]).

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

`achieve` gives a goal. The engine then finds the actions that get to the goal. The
engine uses the same causal laws and the same constraints as the other parts of the
program. Thus you write nothing two times. The result of the engine is a plan. A plan
is a list of *sets* of actions, with one set for each cycle. Thus two things that
can occur at the same time do occur at the same time.

`search(auto)` selects a search method from the shape of the problem. The engine
starts with a breadth-first search. A breadth-first search tries all short plans
before it tries a longer plan. Thus it finds the shortest plan. The engine gives that
search a fixed maximum number of states to visit. If the search gets to that maximum,
the engine changes to a greedy best-first search. A greedy best-first search is much
faster, but it possibly does not find the shortest plan. `search(bfs)`,
`search(greedy)` and `horizon(N)` replace the selection of the engine.

Possibly the world changes and the plan is not correct any more. Then the plan fails
when the engine does it. The engine then makes a new plan from the real state of the
program.

The picture below is `examples/start/blocks3d.lps`. That program is
`achieve on(c,b), on(b,a)` with three blocks:

![Three dimensions](../images/ide-3d.png)

---

## 11. Prolog inside LPS

An LPS program is a Prolog file. All text that is not one of the sentence forms above
is a usual Prolog predicate. Each condition can call that predicate:

```prolog
adjacent(fork(1), philosopher(1), fork(2)).
adjacent(fork(3), philosopher(3), fork(4)).
```

Directives also operate: `:- dynamic`, `:- discontiguous` and `:- op`. You can also
import from the standard library:

```prolog
:- use_module(library(lists)).
```

It is useful to know about two predicates of the engine.

- **`state(F)`** gives the fluents that are true at the current cycle of the engine,
  *one at a time*. `state/1` does not give a list. Thus
  `state(S), memberchk(f(X), S)` does not operate. Write `state(f(X))`.
- **`holds/2`** is part of the internal vocabulary of the engine. The engine declares
  `holds/2` with no clauses. Thus, when your Prolog calls `holds/2`, you do not get
  an error. The call fails with no message, and that is worse. Use `at T` in a
  condition, or use `state/1` inside a `display` clause.

---

## 12. Drawing a program: `display/2` and `display3d/2`

A `display/2` clause tells how to draw a fluent or an event:

```prolog
display(burning(X,Y), [type:circle, center:[CX,CY], radius:10, fillColor:yellow]) :-
	pixels(X, Y, CX, CY).

display(ignite(X,Y),  [type:star, fillColor:red, center:[CX,CY],
		       points:6, radius1:10, radius2:6, opacity:0.5]) :-
	pixels(X, Y, CX, CY).

display(timeless, [[type:rectangle, from:[0,0], to:[200,200], strokeColor:green]]).
```

![Two dimensions](../images/ide-2d.png)

The origin is at the bottom left, and y increases upwards. The part of LPS1 that made
the pictures used the same method. `timeless` is the background. It takes a list of
property lists, not one property list. The body of the clause can be any Prolog. Thus
the arithmetic that changes the coordinates of the program into screen coordinates
is in the program.

`display3d/2` is a separate declaration. It is not a second meaning of the same
declaration. It has `type:box`, `type:ground`, `type:camera`, `type:light` and
`type:text`, with `position` and `size` in three dimensions. A program can have the
two declarations, and it can show different things in each.

The server has a library of 134 pictures. You get a picture with
`[type:raster, icon:fire]`. Use that library, not a URL (a web address). Some of the
LPS1 examples refer to pictures on web sites that do not give these pictures now.
Thus those pictures show as empty holes.

**If you do not want to write drawing clauses yourself**, the assistant can write them
for you. Do these steps:

1. Open the *Assistant* panel from the **View** menu.
2. Click **Animate in 2D**:

![The assistant](../images/ide-assistant.png)

3. Click *Apply to editor*.
4. Run the program:

![The result](../images/ide-assistant-2d.png)

The picture above is the wolf-and-goat program. The assistant animated it in one
step. Before that step, the program contained nothing about how to draw it.

The request to the language model is the interesting part. A language model is a
computer program that writes text. The model does *not* write coordinates. Language
models know well that a goat goes on a river bank. But they are bad at arithmetic
on a drawing area. When we asked a model for the two things together, the result put
three animals in the same place. Thus the server asks the model for a **plan**. The
plan tells which containers there are and which things move between the containers.
It tells which fluent puts a thing in a container, and how each thing looks. From
that plan, the server calculates the position of each shape.

The result in your file is usual Prolog. It is a table of positions (`lps_slot/4`),
a background, and one `display/2` rule. If you move a position in the table, all
things that go to that position move with it.

---

## 13. Asking why

In each run, the engine records how it got each of its conclusions. It does this
also when nobody will ask. **Right-click any item that the panes show.** The item can
be a bar on the timeline, an event, a row of the changes table, a state, the label on
an arrow, a shape in two dimensions or a solid in three dimensions. Then you ask about
that term at that cycle.

![Why did that happen?](../images/ide-explain.png)

There are five forms of question. The dialog box makes them for you:

```
why(happened(A), T)        why did this action occur?
why_not(happened(A), T)    why did it not?
why(holds(F), T)           why is this fluent true?
why(stopped(F), T)         what stopped it, and what caused that?
what_if(Events, T)         what would a different observation have changed?
```

`what_if` is the only question that needs more than the records. `what_if` copies the
session, runs the copy again with the different observation, and compares the two
runs. A copy costs little, because a session is a Prolog term that never changes.
Thus a copy of a session takes one unification. Unification is the one step that
Prolog uses to match two terms. It takes about 5 microseconds, for a session of any
size.

`why_not` needs its own field in the dialog box. The reason is that you cannot click
on a thing that the panes never showed:

![Why not?](../images/ide-why-not.png)

There are four different answers, and each answer has a different meaning:

- `scheduled_for_another_cycle`: the plan will do the action, at cycle 6, as step 4.
- `no_goal_created`: nothing asked for the action.
- `rejected_by_prospective_constraint`: something asked for the action, but a
  constraint with a name refused it.
- `no_plan_found`: something asked for the action, but the engine found no plan
  within the horizon.

When the records cannot give the answer, the answer is "not recorded". The pane never
makes a story that only seems correct.

You can also ask the same questions from the command line:

```sh
./lps explain examples/start/goat_declarative.pl --ask "why_not(happened(transport(wolf,south,north)), 1)"
./lps timeline examples/start/goat_declarative.pl
./lps changes  examples/start/goat_declarative.pl --at 2
./lps automaton examples/start/goat_declarative.pl
```

---

## 14. Programs that do not stop

If a program does not have `maxTime`, the program runs until something stops it. It
does nothing until an event comes from outside. `examples/start/thermostat.lps` is
the first program of this type:

```prolog
fluents   temperature(_), target(_), heating(_), window_state(_).
events    temperature(_), set_target(_), window(_).
actions   heat(_), warn(_).

initially target(21), heating(off), window_state(shut), temperature(20).

temperature(T)  updates Old to T in temperature(Old).

if   temperature(T) at T1, target(Target) at T1, T < Target - 1, heating(off) at T1
then heat(on) from T1 to T2.

%  Never heat with the window open. This is a constraint, not advice.
false heat(on) from T1 to _, window_state(open) at T1.
```

In the editor, do these steps:

1. Click **Live** in the top bar.
2. Click **Start**.
3. Type an event. Or, write the event in English, and the assistant finds the term.

![A session that does not stop](../images/ide-live.png)

Two events went in: `temperature(14)`, then `window(open)`. The program gave the
answer `warn(window_open_while_heating)`.

Look at the lines *queued for cycle N*. Possibly an event comes during a cycle. The
engine then gives that event to the program at the start of the next cycle. Thus the
record of a session stays in a correct sequence. The record does not depend on the
exact time at which each event came.

Also look at the warning: it occurs again in each cycle. A reactive rule gives a goal
that stays (§7), and the window is still open.

The **Pop out 2D** and **Pop out 3D** buttons open a window that follows the session
while it runs. This window is not a picture that you move forward and back yourself:

![A live 2D view](../images/live-2d.png)

From the command line:

```sh
./lps live examples/start/thermostat.lps --cycle-ms 400
```

For a session of this type, you can give a list of the event terms that each source
can send. The list has a more important function than convenience. With this list,
`examples/agents/llm/` makes sure that a language model cannot approve its own
dangerous action. The event that approves the action is not on the list of the
model. Thus the model can never make that event, however much a person tries to
persuade the model.

### An animation you can click on

A program can **declare `lps_mousedown/3`, `lps_mouseup/3` or `lps_mousedrag/3` as
events**. Such a program receives these events from the separate window, in the
coordinates of the program:

```prolog
events lps_mousedown(_, _, _).

%  The reverse of the drawing — a scene and the test for what was clicked have
%  to agree, and the only way to be sure of that is to write them side by side.
lamp_at(X, N) :- N0 is X // 70, N is N0 + 1, N >= 1, N =< 4.

if   lps_mousedown(X, _, _) from _ to T1, lamp_at(X, N), not only_one_on(N) at T1
then toggle(N) from T1 to T2.

false toggle(N) from T1 to _, only_one_on(N) at T1.
```

![Clicking on a program](../images/live-click.png)

The picture above is `examples/start/lights.lps`. It has four lamps. Click a lamp to
switch it on or off. You cannot switch off the last lamp that is on. The program says
this two times: one time as a condition of the rule, and one time as a constraint
below the rule. The condition tells the intention, and it can be incorrect. The
constraint is the guarantee. The engine examines the constraint for each action,
from any origin.

If a program does not declare those events, nothing in the program watches for
clicks. Thus a click on its picture has no effect.

---

## 15. Where to go next

- **[`lps.md`](../reference/lps.md)**: the reference. It gives each construct, the
  operator table, and the full list of drawing properties.
- **[`glossary.md`](../reference/glossary.md)**: the terms that this tutorial and
  other documents use.
- **`examples/`**: in `start/`, `goat_declarative.pl` (constraints about what an
  action will make, and `achieve`), `blocks.lps` and `blocks3d.lps` (planning, in two
  dimensions and in three dimensions), and `thermostat.lps` (a session that does not
  stop). Also `collections/kowalski-book/` (twelve programs from *Computational Logic
  and Human Thinking*), and `planning/`, `agents/llm/`, `agents/minecraft/`, `le/`,
  `if/` and `migration/`.
- **`legacy_lps1/examples/`**: the examples of LPS1. All of them run here. You can
  open each of them with two clicks in the list of examples.
- **Logical English.** Possibly you want to write the program in English. LE2 is the
  compiler for LE (Logical English). LE2 changes a document into the form that this
  engine runs. Put `the target language is: lps.` at the top of a `.le` file. Then run
  `LPS_LE2_LIB=/path/to/LogicalEnglish2 ./lps run foo.le`.
- **[`introducing-lps2.md`](../overview/introducing-lps2.md)**: what is new since
  LPS1, and why.

---

## 16. Ten mistakes that are easy to make

**`updates _ to X in f(_)` uses two different anonymous variables.** Each `_` is a
separate new variable. Thus the "old" value in the pattern is not the "old" value
that the update replaces. The update then does nothing useful, and you get no
message. Give the variable a name: `updates Old to X in f(Old)`.

**A reactive rule continues to operate for all the time that its condition is
true.** The rule gives a goal that stays. The rule does not operate only at the time
when the condition becomes true (§7). If you want something to occur one time only,
make that thing change its own condition to false.

**An event in the condition of a rule needs `from … to …`, not `at`.** An event is
something that occurred during a period of time. `at T` asks the *state* about the
event. The state has no data about the event. Thus the rule never operates, and you
get no message. Write
`if task_request(delete, F) from _ to T1 then …`, not
`if task_request(delete, F) at T1 then …`.

**An atom with a full stop in it and with no quotes is not an atom.** In SWI-Prolog 7,
the system reads `app.log` as the compound term `'.'(app, log)`. The compound term
prints as `app.log`, but it matches nothing. Write `'app.log'`. The engine reads the
text of events from the network with a setting that permits the full stop. Thus a
person who types into the Live panel does not have this problem. But a term in your
own program has the problem.

**`state/1` gives you fluents one at a time; it does not return a list** (§11).

**`holds/2` quietly fails when called from your own Prolog** (§11).

**Actions occur between states.** The engine records an action at `events/3`. The
engine selected that action from the state at cycle 2. The effects of that action
show in `fluents/3`. When people are not sure about the cycle of a thing, the cause
is usually this gap.

**An action that is connected to the time of its rule cannot wait.** In
`if C at T then a from T to T2`, the action must occur in the cycle in which the rule
operated. If a constraint prohibits the action in that cycle, the run ends in
`failure`. Write `then a from T2 to T3` for "as soon as permitted"
([How a program runs §4](how-lps-runs.md#4-some-time-and-now)).

**A goal does not examine its reason again.** After a rule operates, the engine
continues to try to get to the goal. It continues also when the condition of the rule
is not true any more. Possibly the action is correct only while the condition is
true. Then examine the condition again in the consequent:
`then dirty at T2, mop from T2 to T3`
([How a program runs §6](how-lps-runs.md#6-a-goal-outlives-its-reason)).

**A `display/2` clause must operate when its first argument has no value yet.** Put
the conditions in the body. Do not put cuts in the head. Do not use if-then-else to
select the clause that matches. The editor draws only the *first* solution for each
subject. LPS1 did the same, and we keep this on purpose.
