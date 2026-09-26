# Introducing LPS2

*Kind: overview · Audience: newcomers, with or without a background in programming · Status: current (2026-09-26)*

LPS (Logic Production Systems) is a language for describing how the world
changes over time, and what an agent — a person, a program or a machine that
acts — should do about it. LPS2 is a new version of the system that runs LPS
programs. Around that system sits everything that has since been built on top of
it: a planner that works out a sequence of actions by itself, explanations of
why anything happened, an editor that runs in a web browser and draws a program
as it runs, an assistant driven by a language model (the kind of program that
answers questions in ordinary English), and ways of writing programs in English
and in the languages of several other systems.

This document is a tour of what LPS2 does, shown from the running system. It
leaves out how the software is built. That detail is in a companion document,
[LPS2 in detail](introducing-lps2-technical.md), written for programmers and for
readers who know the original LPS system. Where a section of this tour has more
behind it, the section says where to find it.

Three other documents go further in other directions.
[Learning LPS](../tutorials/lps-tutorial.md) teaches the language, step by step.
The [language reference](../reference/lps.md) describes every construct. The
[glossary](../reference/glossary.md) defines every term used here.

Every picture below was taken by working the running system in a browser. Every
number below was measured. Where something does not work, this document says
so.

---

## Contents

**Part one — what it is**
1. [The short version](#1-the-short-version)
2. [What LPS is](#2-what-lps-is)
3. [Why a new version](#3-why-a-new-version)
4. [How we know it behaves like the original](#4-how-we-know-it-behaves-like-the-original)

**Part two — what is new**
5. [Planning](#5-planning)
6. [Explanations](#6-explanations)
7. [The state-transition diagram](#7-the-state-transition-diagram)
8. [Asking what would have happened](#8-asking-what-would-have-happened)
9. [Sessions that do not stop](#9-sessions-that-do-not-stop)

**Part three — the ways of using it**
10. [The editor](#10-the-editor)
11. [Animation, in two dimensions and three](#11-animation-in-two-dimensions-and-three)
12. [The assistant](#12-the-assistant)
13. [The command line](#13-the-command-line)
14. [In a browser, with no server](#14-in-a-browser-with-no-server)

**Part four — other languages, in and out**
15. [Logical English](#15-logical-english)
16. [PDDL](#16-pddl)
17. [Drools](#17-drools)
18. [Kowalski's book](#18-kowalskis-book)
19. [Interactive fiction](#19-interactive-fiction)

**Part five — agents**
20. [A language model that cannot authorise itself](#20-a-language-model-that-cannot-authorise-itself)
21. [Minecraft](#21-minecraft)
22. [Industrial control, still on paper](#22-industrial-control-still-on-paper)

**Part six — where things stand**
23. [What is not there yet](#23-what-is-not-there-yet)
24. [Where to start](#24-where-to-start)

---

# Part one — what it is

## 1. The short version

LPS2 runs LPS programs the way the original system did. The original system is
called LPS1 in these documents. LPS1 comes with 108 recorded runs of its example
programs, and LPS2 reproduces **99 of the 108 exactly**. The other nine
recordings are out of date, and LPS1 itself no longer reproduces them. LPS2
finishes a run in well under half the time LPS1 takes.

On top of that, LPS2 adds:

- **planning**: state the goal, and the system works out the actions;
- **explanations**: ask *why* something happened, or *why not*, about any
  moment of a run;
- **"what if?"**: run the same program again with something different, and
  compare;
- **sessions that do not stop**, which take in events as they arrive;
- **an editor in the browser**, with six ways of looking at a run, animation in
  two and three dimensions, and an assistant;
- **other languages**: programs written in Logical English, and programs brought
  in from other systems;
- **a version that runs inside a browser**, with no server behind it.

![The editor](../images/ide-overview.png)

## 2. What LPS is

LPS — Logic Production System, of Kowalski and Sadri — is a language for programs
that *act over time*. A program is made of five kinds of thing:

- **fluents**, which stay true over a stretch of time: `light(off)`,
  `balance(alice, 100)`;
- **events and actions**, which happen between one state of the world and the
  next;
- **causal laws**, saying what an event does to the state:
  `switch(New) initiates light(New)`;
- **reactive rules**, which set standing goals: `if C at T1 then A from T1 to T2`
  means *whenever C becomes true, bring A about*;
- **constraints**, which forbid: `false execute(A), destructive(A), not
  approved(A)`.

The engine — the part of the system that actually carries a program out — goes
round the same cycle again and again: observe, think, decide, act. The
interesting part of the cycle is *decide*. Several rules may want things that
cannot all happen at once. The constraints rule some of those things out, and
whatever survives becomes the set of actions the engine commits to for that
cycle.

Two properties of the language matter for everything that follows.

First, the causal laws are stated once, and every rule gets the benefit of
them. How the world works is therefore written in one place, instead of being
spread through the parts of the program that act.

Second, the engine enforces a constraint, rather than the thing being
constrained enforcing it on itself. Because the engine does the enforcing, the
safety argument in §20 is a fact about how the parts are wired together, and not
a matter of how carefully somebody instructed a language model.

### A whole program, and what it does

Here is a program from LPS1's collection of examples. It is short enough to read
in full, and it contains almost every construct:

```prolog
maxTime(10).
actions          transfer(From, To, Amount).
fluents          balance(Person, Amount).

initially        balance(bob, 0), balance(fariba, 100).
observe          transfer(fariba, bob, 10)        from 1 to 2.

if      transfer(fariba, bob, X)     from  T1 to T2,
        balance(bob, A) at T2, A >= 10
then    transfer(bob, fariba, 10)    from T2 to T3.

if      transfer(bob, fariba, X)     from  T1 to T2,
        balance(fariba, A) at T2, A >= 20
then    transfer(fariba, bob, 20)    from  T2 to T3.

transfer(F,T,A) updates Old to New in balance(T, Old) if New is Old + A.
transfer(F,T,A) updates Old to New in balance(F, Old) if New is Old - A.

false   transfer(From, To, Amount), balance(From, Old),  Old < Amount.
false   transfer(From, To1, Amount1), transfer(From, To2, Amount2),  To1 \=To2.
false   transfer(From1, To, Amount1), transfer(From2, To, Amount2),  From1 \= From2.
```

An event from outside sets the program going: fariba sends bob 10. Two reactive
rules send money back and forth. Two causal laws say what a transfer does to a
balance. Three constraints say what must never happen: an overdraft, and two
transfers in one cycle sharing a payer or sharing a payee. Running the program
gives this record, cycle by cycle:

```
fluents/0        [balance(bob,0),balance(fariba,100)]
fluents/1        [balance(bob,0),balance(fariba,100)]
events/2         [transfer(fariba,bob,10)]
fluents/2        [balance(bob,10),balance(fariba,90)]
events/3         [transfer(bob,fariba,10)]
fluents/3        [balance(fariba,100),balance(bob,0)]
events/4         [transfer(fariba,bob,20)]
fluents/4        [balance(bob,20),balance(fariba,80)]
…
```

Three things about that record are the whole language in miniature.

The program never mentions a clock time, yet every action lands in a definite
cycle. The first reactive rule reacts to a transfer that ends at time `T2`, and
says the reply starts at that same `T2`. Every action takes one cycle, so the
reply ends at `T3`, which is `T2 + 1`. The record shows exactly that: fariba's
transfer ends at time 2, and bob's reply runs from time 2 to time 3.

Nothing in the program says what a balance *is*. The two `updates` lines are
the only place where any arithmetic appears, and both reactive rules get the
benefit of those two lines.

And the two constraints about doing things at the same time are what make a set
of actions a *set*. Those two constraints are the reason the engine cannot
commit two transfers from bob in one cycle, and neither of the two rules had to
know that the other one existed.

### When rules disagree

The hard part of building an LPS engine is deciding what happens when several
rules want things that cannot all happen. LPS1 had an answer, built into its
code, but nobody had ever written the answer down. Writing it down was the first
job of LPS2: a document of twenty numbered points at which the engine has a
choice to make, each saying which way the engine goes. The companion describes
that document, with two examples
([LPS2 in detail, §1](introducing-lps2-technical.md#1-when-rules-disagree-the-selection-specification)).

## 3. Why a new version

LPS1 works, and its collection of example programs is the accumulated knowledge
of what LPS is for. But in LPS1, the engine is tangled up with the web system
through which LPS1 was used, called SWISH. The part that decides what a program
does and the part that talks to the web share the same code.

That tangle is what stood in the way of the new features: a planner, a copy of
a running session, a version that runs in a browser, a second way of writing a
program. So LPS2 separates the two. The engine touches nothing outside itself:
it reads no files, uses no network, and never looks at a clock. Everything that
deals with the outside world sits around the engine, in a layer of its own, and
a program checks every change to make sure the separation stays.

Nearly every new feature below follows from that one decision
([LPS2 in detail, §2 and §4](introducing-lps2-technical.md#2-why-implement-it-again)).

## 4. How we know it behaves like the original

A recorded run lists, for every cycle, which fluents held and which events
happened. For LPS2 to pass, its run must match the recording exactly: the same
things, in the same cycles, the same number of them. A program that reaches the
same answer by a different route, in different cycles, fails.

LPS2 reproduces **99 of LPS1's 108 recorded runs**. The other nine recordings
were made years ago, before LPS1 itself changed. LPS1 no longer reproduces them
either, and each of the nine is written up with the evidence. There is no case
where the two engines differ and the reason is unknown.

The testing also disturbs each program on purpose: the rules in reverse order,
the starting facts in reverse order, new goals put first rather than last. A
program whose result changed under a disturbance would be relying on an accident
of order. None of the 99 changes.

LPS2 finishes a run in about **0.4 times** the time LPS1 takes, using between a
third and a half of the memory. One program is slower; the companion says which,
and why
([LPS2 in detail, §3](introducing-lps2-technical.md#3-what-behaves-like-lps1-is-taken-to-mean)).

---

# Part two — what is new

## 5. Planning

`examples/start/goat_declarative.pl` states the wolf, goat and cabbage puzzle rather
than solving it. A farmer must row a wolf, a goat and a cabbage across a river,
one at a time, without ever leaving the goat alone with the wolf or with the
cabbage:

```prolog
:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

actions row(_,_), transport(_,_,_).
fluents loc(_,_).

initially loc(wolf,south), loc(goat,south), loc(cabbage,south), loc(farmer,south).

transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

%  the rules of the puzzle, written as constraints on the state a crossing
%  *would* produce
false loc(goat,L) at T, loc(wolf,L) at T,    not loc(farmer,L) at T, row(_,_) to T.
false loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T, row(_,_) to T.

false transport(farmer, _, _).
false transport(Object, L1, _) from T1 to _,  not loc(farmer, L1) at T1.
false transport(_, L1, L2)     from T1 to T2, not row(L1, L2) from T1 to T2.
false row(L1, _)               from T1 to _,  not loc(farmer, L1) at T1.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

The last line, `achieve`, states the goal. Nothing in the program says how to
reach it: the engine searches for a sequence of actions that gets there without
breaking a constraint.

Compare `examples/goat.pl`, the older version of the same puzzle, where the
knowledge that the goat cannot be left with the wolf or the cabbage never
appears as a constraint at all. Whoever wrote that program worked the knowledge
out by hand into six separate cases. The version above is shorter, and what it
says out loud is exactly the thing a reader wants to check.

**Two ways of searching.** The engine first tries a search that is sure to find
the shortest plan, but can be slow. If that search takes too long, the engine
changes to a faster search, which finds a good plan but not always the shortest.
On a puzzle of seven blocks to be restacked, the fast search takes 0.4 seconds
and the thorough one 25 seconds, and the gap grows quickly as the puzzle grows.

**A plan is a sequence of *sets* of actions.** Two actions that do not conflict
may share a cycle, which is what the goat puzzle needs: rowing and carrying
happen together.

**A plan can fail.** If the world moves on — the tree is gone, somebody took the
log — the plan stops being valid, carrying it out fails, and the engine plans
again from the state the program is actually in. Planning again is what makes
planning useful to an agent, rather than only to a puzzle.

The picture below is a program that asks for block c on block b and b on a, and
says how to draw each block in three dimensions:

![Three dimensions](../images/ide-3d.png)

## 6. Explanations

Every run records how the engine reached each of its conclusions, always. There
is no switch to set in advance, because a switch you had to remember is no use
after something has gone wrong.

**You ask the question where the thing itself is.** Each pane of the editor
labels what it draws with what that thing stands for. Right-click any of them —
a bar on the timeline, a row of the changes table, a state, the label on an
arrow, a shape in two dimensions, a solid in three — and the explanation for
that thing at that cycle opens.

![Why](../images/ide-explain.png)

There are five questions you can ask: why did this happen, why did it not
happen, why is this true, why did this stop being true, and what would have
happened if something else had been observed.

*Why not* is the one worth dwelling on. It has a box of its own, because you
cannot right-click something that was never drawn at all. "It did not happen"
has four different causes, and treating those four alike is how an afternoon of
hunting for a fault goes wrong:

![Why not](../images/ide-why-not.png)

- **scheduled for another cycle** — the plan does intend it, later;
- **no goal created** — nothing ever asked for it;
- **rejected by a constraint** — something did ask, and a named constraint
  refused it;
- **no plan found** — it was asked for, and no plan was found in time.

The explanation never puts together a plausible-sounding story. Where the record
cannot settle the question, the answer is *not recorded*.

## 7. The state-transition diagram

A state-transition diagram draws every distinct state a run passes through as a
box, and every change from one state to another as an arrow.

![The state-transition diagram](../images/ide-automaton.png)

The picture above is the dining philosophers: five people round a table, with
one fork between each pair, and each person needs both neighbouring forks to
eat. The box on the left that everything meets at is the state in which all five
forks are free. Each box on the right is somebody eating, with a loop back to
itself for as long as that person carries on. Every distinct state appears
**once**, which is the point: a program that returns to a state it has been in
before should read as a loop, not as a long chain.

LPS1 drew a diagram of the same kind, but put every state in one column, and
drew five events between the same two states as five labels on top of one
another. LPS2 merges those into one arrow with a list of labels, lays the states
out from left to right, and draws a return to an earlier state as a visible
loop. Two switches simplify the diagram further: *abstract numbers*, which
merges states that differ only in a number, and *hide self-loops*.

## 8. Asking what would have happened

LPS2 can copy a running session in a single step, however long it has been
running — in about five millionths of a second. That makes "what if?" cheap to
ask.

The *what if* question takes a copy of the session, runs the copy on with a
different observation, and compares the two runs cycle by cycle. The answer
says what happened in one run and not in the other.

## 9. Sessions that do not stop

Leave `maxTime` out, and the program goes round its cycle until somebody stops
it, doing nothing until an event arrives.

![A session that does not stop](../images/ide-live.png)

That is `examples/start/thermostat.lps`. Two events went in from the panel —
`temperature(14)`, then `window(open)` — and the program answered with
`warn(window_open_while_heating)`.

Notice the lines reading *queued for cycle N*. An event that arrives part-way
through a cycle waits, and the engine delivers it at the start of the next
cycle. The record of a session therefore stays an orderly sequence, instead of
depending on the exact moment at which each thing arrived. The warning repeats
in every cycle because a reactive rule sets a standing goal and the window is
still open. Only the last 400 cycles are kept, unless you ask for more, so a
session can be left running overnight.

**Channels.** Events can come from different sources — a person, another
program, a language model — and each source is given a channel. When a session
starts, each channel is told which kinds of event it may send. An event of a
kind its channel may not send is refused, and the refusal is *reported*, never
silent: a sender that believes its event was taken in needs to be told when it
was not. §20 rests on that arrangement.

The **Pop out 2D** and **Pop out 3D** buttons open a window that follows the
running session as it goes. The two buttons appear only for a program that says
how it should be drawn.

![A live 2D view](../images/live-2d.png)

**The animation can be a way in, not only a way of looking.** A program can
declare mouse clicks as events, and then a click on the picture becomes an event
the program reacts to. A program that declares no mouse events receives none.

![Clicking on a program](../images/live-click.png)

That is `examples/start/lights.lps` — four lamps, click to toggle one, and a
constraint that will not let you turn off the last one that is on.

---

# Part three — the ways of using it

## 10. The editor

The editor runs in a web browser. Its first page is a **start page**, which
lists every example as a tree of folders you can open and close, and puts the
documents beside them. Every entry on the start page opens the editor with that
program already loaded.

![The start page](../images/landing.png)

**One row of controls.** Everything that acts on the program sits in the bar
along the top: the menus, then `maxTime` and Run, then how the last run ended,
then the button that opens the live panel. A closed panel takes up no space and
shows no controls at all.

**Several files at once.** Each tab keeps its own text *and* its own run. So
everything on the right is about the file whose tab is lit, and coming back to a
tab restores what you were looking at. Comparing two versions of a program takes
two tabs.

![Two files, each with its own run](../images/ide-tabs.png)

**Errors in the text.** A wavy underline on the line, the message when you hover
over it, a mark on the edge of the scrollbar, F8 to step through the errors one
by one, and a count in the top bar that takes you to the first. When the system
cannot make sense of a program, it does not simply stop. It reports what is
wrong, and still shows everything it did manage to work out:

![Errors](../images/ide-diagnostics.png)

**Fluents, events and actions are coloured according to what was declared** —
LPS1's own colours, a pale blue background for a fluent and amber for an event
or an action.

**Six panes**: Timeline, Changes, Automaton, 2D, 3D, Internal. Five of them move
together on one cycle slider, and all of them zoom and pan the same way.

The **timeline** gives each fluent a row of its own, drawn across the stretches
of time in which that fluent holds, with the events of each cycle below.

![The timeline](../images/ide-timeline.png)

The **Changes** pane answers one narrow question about a single cycle: what
changed, and which causal law made the change.

![Changes](../images/ide-changes.png)

`line 24` is a line in the file in front of you. Everything that did not change
is listed separately as having *persisted*, because the engine knows the
difference between "still true" and "made true again".

The **Internal** pane shows the program in the form the engine actually runs. It
is worth a look once, because it shows how much of the written form is a
convenience:

![The internal form](../images/ide-internal.png)

**Menus** — File, Edit, View, Misc, Help. The Misc menu holds the settings for
the language models the assistant uses (§12), and *Deploy as WASM* (§14):

![The Misc menu](../images/ide-menu.png)

**A list of every example program**, each with the first line of its own comment
as a description:

![Examples](../images/ide-examples.png)

The editor has a manual of its own, with a "how do I …" section:
[Using the editor](../guide/ide.md).

## 11. Animation, in two dimensions and three

A program can say how its fluents and events should be drawn. `display/2` gives
the drawing for two dimensions, in LPS1's own vocabulary:

```prolog
display(burning(X,Y), [type:circle, center:[CX,CY], radius:10, fillColor:yellow]) :-
	pixels(X, Y, CX, CY).
display(ignite(X,Y),  [type:star, fillColor:red, center:[CX,CY],
		       points:6, radius1:10, radius2:6, opacity:0.5]) :-
	pixels(X, Y, CX, CY).
display(timeless, [[type:rectangle, from:[0,0], to:[200,200], strokeColor:green]]).
```

![Two dimensions](../images/ide-2d.png)

That is one of LPS1's examples, unchanged, at cycle 6: a fire spreading across
a grid. LPS2 draws every shape in LPS1's vocabulary.

**A library of pictures.** Several of LPS1's examples point at pictures on web
sites that no longer serve them, and so come out full of holes. LPS2 carries 134
pictures of its own — fire, money, a judge's gavel, a boat and the rest — chosen by
counting what the examples actually draw. They are kept with the system, so an
animation works with no connection to the internet. Ask for one by writing
`[type:raster, icon:fire]`.

**Fills and objects.** A fill such as `pattern:hatch` or bricks or waves covers
the surface of a shape, and says what the surface is *like*. In three
dimensions, `[type:model, model:tree]` puts one of thirty-four named things on
the floor — a person, a tree, a house, a truck, a coin, a key, a flag.

`display3d/2` gives the drawing for three dimensions: boxes, spheres, cylinders,
cones, lines, arrows and text, with a camera and a light. A program may have
both drawings at once, each showing something different
([LPS2 in detail, §7](introducing-lps2-technical.md#7-the-editor-inside)).

## 12. The assistant

The assistant is a panel in the editor where you can ask a language model for
help with the program in front of you. Open it with **View ▸ Assistant panel**.

**What you need first.** The assistant uses a language model from one of five
companies that offer them: OpenAI, Anthropic, Google (whose models are called
Gemini), Groq and Together. Using a company's models needs an API key — a code,
rather like a password, that the company gives its customers so that a program
can use its models. There are two ways to have one:

- the person who runs the server sets a key up once, for everybody who uses that
  server; or
- you type in your own key, in **Misc ▸ API keys, models & Assistant settings**.
  Your key is kept in your own browser.

With no key at all, the panel says so, and offers the button that opens that
dialog. The same dialog lists the models each company currently offers, read
from the companies themselves, and you choose the one you want. You can also
change the model for a single question, at the top of the panel.

**What the assistant can do.** The assistant can do what you can do in the
editor. It can check the program for mistakes, run it, ask the engine why
something happened, and look at what a drawing of the program shows. Because the
assistant uses the editor's own operations, when the assistant says "the program
has no mistakes", it is the same check the editor makes.

So you can ask it to change the program — *add a rule so that the heating
switches off when the window opens* — or ask how to do something, in LPS or in
the editor. For a question about how to do something, the assistant searches
this documentation and ends its answer with links to the sections that say
more.

**Two buttons ask a question that is already written**: **Animate in 2D** and
**Animate in 3D**. They give a drawing to a program that has none.

![The assistant](../images/ide-assistant.png)

and one click later:

![The result](../images/ide-assistant-2d.png)

That is the wolf and goat program — which said nothing at all about how it
should be drawn — animated by one of the models. The model decides what to draw
and what each thing looks like. The editor itself works out where everything
goes, so nothing overlaps. Nothing is put into your file until you press
**Apply to editor**, and one undo takes it back out. Why the work is divided
that way is told in
[LPS2 in detail, §8](introducing-lps2-technical.md#8-the-assistant-inside).

**A run can also be drawn as a strip.** *Split into scenes*, beside those two
buttons, draws the whole run instead of one cycle of it: one picture for each
moment at which the picture changed, in order, saying what moved the story on
between one frame and the next. Click a frame and the full scene at that moment
opens. The strip answers the question "what happened?", where a single picture
answers "what is true now?".

## 13. The command line

Everything the editor does can also be done by typing commands:

```sh
./lps run examples/start/goat_declarative.pl
./lps step PROGRAM --cycles 3
./lps live examples/start/thermostat.lps --cycle-ms 400
./lps explain PROGRAM --ask "why_not(happened(a), 4)"
./lps timeline PROGRAM
./lps changes  PROGRAM --at 2
./lps automaton PROGRAM
./lps dump PROGRAM
./lps pddl domain.pddl problem.pddl
./lps drools rules.drl
./lps ide
```

The last command starts the editor. Other programs can use LPS2 over the web,
through a single address; the companion describes it
([LPS2 in detail, §9](introducing-lps2-technical.md#9-the-web-interface)).

## 14. In a browser, with no server

**Misc ▸ Deploy as WASM** produces a single web page with the engine and your
program inside it. WASM is short for WebAssembly, a form of program that a web
browser can run by itself. The page needs no server: it can be put on any web
site.

![WebAssembly](../images/wasm.png)

That is the bank transfer program of §2, running in a browser with no server
involved at all. The parts that deal with the outside world — the assistant,
sessions that keep running, Logical English — are not in that page. The page is
possible at all only because the engine was kept separate from those parts from
the start (§3).

---

# Part four — other languages, in and out

## 15. Logical English

Logical English is a way of writing programs as English sentences, developed by
Robert Kowalski and colleagues; LE2 is the current version of its system. The
English is still exact: each sentence follows a template that the document
itself declares, so the computer reads it with no guessing. LE2 translates a
Logical English document into the form LPS2 runs, so a program written in
English runs just like one written in LPS.

![Logical English in the LPS2 editor](../images/ide-le.png)

Here is the bank transfer program of §2, in English, shortened to one reactive
rule and one constraint:

```
the target language is: lps.

the maximum time is 10.

the actions are:
    *a payer* transfers *an amount* to *a payee*; known as transfer.

the fluents are:
    the balance of *a person* is *an amount*; known as balance.

the knowledge base bank transfer includes:

initially the balance of bob is 0
    and the balance of fariba is 100.

if fariba transfers an amount to bob from a first time to a second time
    and the balance of bob is a second amount at the second time
    and the second amount >= 10
then bob transfers 10 to fariba from the second time to a third time.

when a payer transfers an amount to a payee
then the balance of the payee that is a number becomes number + amount
    and the balance of the payer that is a second number becomes second number - amount.

it must not be true that
    a payer transfers an amount to a payee from a first time to a second time
    and the balance of the payer is a second amount at the first time
    and the second amount < the amount.

scenario one is:
    fariba transfers 10 to bob from 1 to 2.
```

Each part of that document is a part of LPS, in English. The lines under *the
actions are* and *the fluents are* declare the templates. `if … then …` is a
reactive rule. `when … then … becomes …` is a causal law. `it must not be true
that` is a constraint. And the scenario is the event observed from outside. The
English is not a thin covering over a different language: it is the same
language.

When a program written in English has a mistake, the error is reported against
the **English** line that caused it, not against the translation. A person who
writes in English never has to read a program they did not write.

**Trying it.** Logical English needs LE2 to be installed alongside LPS2, which
is a job for whoever runs the server. Where it is installed:

1. Open the start page, choose the folder of Logical English examples, and open
   *the bank transfer*.
2. Press **Run**. The timeline shows the balances moving, exactly as for the
   program of §2.
3. Change a number in the scenario — make fariba send 5 instead of 10 — and run
   it again. The first reactive rule no longer fires, because bob's balance
   never reaches 10.

**Say it in English.** A Logical English sentence has to fit one of the
document's templates, and finding the right wording is not always easy.
**Edit ▸ Say it in English…** helps. Type an ordinary sentence, such as *alice
has 50 in her account*, and choose whether it is a fact for a scenario or a
question. The editor asks a language model to rewrite the sentence using only
the document's own templates — here, the answer should be *the balance of
alice is 50* — and then checks the rewritten sentence against the document. You see the result, with
anything the check could not settle, and nothing goes into the document until
you press **Insert at the cursor**. Like the assistant, *Say it in English*
needs an API key (§12).

**And the other way.** **Misc ▸ Convert to Logical English** turns an LPS
program into a Logical English document, in a new tab, so a program written in
LPS can be read as English.

How the two systems are connected, and how the translation is checked, is in
[LPS2 in detail, §11](introducing-lps2-technical.md#11-logical-english-inside).
The full description of Logical English for LPS is
[its own reference](../reference/le-for-lps.md).

## 16. PDDL

PDDL, the Planning Domain Definition Language, is the language in which planning
problems are usually written by researchers. A PDDL problem comes in two files:
the *domain*, which says what actions exist and what each one needs and does,
and the *problem*, which says where things start and what the goal is. LPS2
solves such problems with its own planner:

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

The translation is the obvious one, and the ease of it is an argument for the
shape of LPS. What an action needs becomes a constraint. What an action does
becomes a causal law. The goal becomes `achieve`. Nothing in the planner is
particular to PDDL: this is the same `achieve` that the goat puzzle uses.

Every plan is checked by a separate program that applies PDDL's own meaning.
Thirteen of the fourteen test problems are solved and checked, and twelve of
those thirteen plans are the shortest possible. The fourteenth is too large for
the planner as it stands (§23).

**A PDDL file opens like any other file.** File ▸ Open takes the domain and the
problem together, and gives you an LPS program with a note at the top saying
what it was translated from.

More in [PDDL and LPS](../integrations/pddl.md), and in
[LPS2 in detail, §12](introducing-lps2-technical.md#12-pddl-inside).

## 17. Drools

Drools is a widely used business rules system: a program holds a collection of
facts, and each rule says what to do when certain facts are present. LPS2 reads
Drools's rules and turns them into LPS.

```sh
./lps drools examples/migration/drools/drl/fire-alarm.drl
```

In LPS, an action or an event is something that happens in the world. So the
translation reads each Drools rule as a statement about the world. A rule that
adds the fact *there is a fire* becomes the event *a fire starts*. A rule that
switches a sprinkler on becomes the event *the sprinkler turns on*. A small
companion file can supply the words a person would actually choose:

```
if   fire(A) at T1, not alarm at T1
then alarm_goes_on from T1 to T2.
alarm_goes_on from T1 to T2 initiates alarm.
```

Where Drools and LPS do not agree, the translator says so rather than guessing.
Drools, for example, can give one rule priority over another. LPS has nothing of
the kind — LPS decides by constraint, not by priority — so the translator warns
about it, rather than pretending.

Drools files open through File ▸ Open as well. More in
[Drools and LPS](../integrations/drools.md), and in
[LPS2 in detail, §13](introducing-lps2-technical.md#13-drools-inside).

## 18. Kowalski's book

*Computational Logic and Human Thinking* is the book that both LPS and Logical
English descend from. LE2 had already catalogued **226 examples** from the book,
and had written out the **22** of them that fit Logical English.

The interesting number is the other 132, and particularly *why* those were left
out. LE2's own list of what it could not express reads like a description of
LPS: standing goals and the observe-think-decide-act cycle, the basic notions of
the event calculus and the situation calculus, constraints and prohibitions
stated out loud, and condition-action rules that work forwards from what is
already true. Counting by machine, **68 of those 132 are held up only by
constructs that LPS has**.

`examples/collections/kowalski-book/` has twelve of them, chosen to cover the
chapters whose subject *is* the agent cycle, and to put at least one program
against each construct Logical English could not express: the Underground
Emergency Notice, the penalty sentence as something that discourages an action,
the fox and the crow, the wood louse, the Mars explorer, the trolley problem,
citizenship over time, violations and obligations that arise from breaking
other obligations, the event calculus, and generating a plan. Each of the twelve
has a test of its behaviour, and all twelve pass.

## 19. Interactive fiction

A text adventure is a game in which the player types commands — *open the
door*, *go north*, *take the key* — and the game describes what happens. Behind
the game is a model of a world, and rules that say what the world and the people
in it do about each command. That is an LPS session that does not stop, with the
player sending events. So LPS2 can *be* an engine for such games, and it borrows
from Inform 7, the language in which most of them are written: its model of a
world, its vocabulary of actions, and its collection of test games with their
ideal transcripts, against which the games here are checked.

The world model is a library written in Logical English: rooms, things,
containers, doors, people, the map, and a dozen actions. Thirteen stories use
the library, among them seven of Inform's own test cases and *Alice's Adventures
in Wonderland*, chapters I and II.

Three things about the way the games work are worth knowing, because those three
are what LPS brings and the other systems for such games do not have.

**A command is an attempt, never an obligation.** When you type *open the case*,
the game tries to open it. If a precondition forbids the action, the game
explains the refusal with the engine's own reason: *You can't open the case: the
case is locked.* Inform's authors write messages like that by hand, one for
every check; here nobody wrote them at all.

**The story's own templates decide what the player can type.** A Logical English
story declares a template for every command it understands, for instance

```
the command is to take *a thing*.
```

What the player types is matched against those templates: *take the key* fits
the template above, with *the key* in the place of *a thing*. So a story that
adds the line `the command is to drink *a thing*.` has, merely by saying so,
taught the game the new command *drink the bottle*. No language model is needed
to understand the player. A language model is used only when a typed line fits
none of the templates, and there is a key: the model is then asked which of the
story's commands the player most probably meant.

**A game can be copied in mid-play.** The copy is the same game under a second
name, and the two games part company according to what is typed into each. Take
Alice at the bottle: drink, and the key on the glass table is out of reach, the
cake makes you nine feet tall, you cry a pool and end chapter II swimming in it.
Or copy the game first, take the key, then drink, and walk into the garden,
which the Alice of the book never does. *Diff* says what happened in one game
and not in the other, in the words of the story.

![Alice, played in the editor and forked at the bottle](../images/ide-play-alice.png)

*Why?* in the play panel asks the engine why the last turn went as it did. More
in [LPS for Inform users](../tutorials/inform-users.md).

---

# Part five — agents

## 20. A language model that cannot authorise itself

Language models are increasingly asked to act, not only to talk: to send an
email, move money, delete a file. The danger is a model that talks itself into
something harmful. The claim of this section is that, with LPS, **the model is
never the thing that authorises the dangerous action** — and not because
anybody asked the model nicely, but because the permission cannot be reached
from the model's channel (§9).

`examples/agents/llm/approval.lps`:

```prolog
%  Causal laws
request_approval(A) initiates pending(A).
approval(grant, A)  initiates approved(A).
execute(A)          initiates done(A).
execute(A)          terminates approved(A).      % approval is good for one use

%  The gate
if   task_request(delete, File) from _ to T1, destructive(delete_file(File))
then request_approval(delete_file(File)) from T1 to T2,
     approved(delete_file(File)) at T3,
     execute(delete_file(File)) from T3 to T4.

%  The constraint
false execute(A), destructive(A), not approved(A).
```

A demonstration drives that program with a model whose channel may carry task
requests and nothing else:

```
live session live6 — the llm channel may carry task_request/2 only

human:  “the application logs are stale, please delete app.log”
model:  perceived ["task_request(delete,app.log)"]
lps:    the gate fires — approval requested, execution withheld
        │ cycle 4: [request_approval(delete_file('app.log')),task_request(delete,'app.log')]

model:  now tries to approve its own request
        │ refused: ["approval(grant,delete_file('app.log'))"]
        │ REFUSED on channel llm: [approval(grant,delete_file('app.log'))]

lps:    at cycle 11 the state is ["pending(delete_file('app.log'))"]
        │ pending, never approved — the constraint is not advice

human:  approves, on the human channel
        │ cycle 12: [execute(delete_file('app.log')),approval(grant,delete_file('app.log'))]

lps:    it executed — the state is now ["done(delete_file('app.log'))"]
```

The model does the one thing only a language model can do — turn a sentence into
an event — and nothing else. Everything after that is the engine.

Run the demonstration with a weak model, or with instructions telling the model
to lie, and the outcome is the same. The file can be deleted only once it is
approved. It becomes approved only through an approval event. The model's
channel may not send approval events. And the engine, not the model, checks the
constraint. The safety comes from the way the parts are connected, and that was
the open question.

Other programs can use the same arrangement through the Model Context Protocol,
an agreed way of offering tools to a language model:
[LPS over MCP](../api/mcp.md).

## 21. Minecraft

Minecraft is a popular video game. The player walks through a world made of
blocks, cuts down trees, digs for stone, and crafts tools from what they
gather: planks from wood, sticks from planks, a pickaxe from planks and sticks.
The game is a convenient stand-in for the real world, because it has
everything a robot faces — places to go, things to fetch, dangers — without any
risk.

`examples/agents/minecraft/` is an LPS program playing Minecraft, through a
character in the game — a *bot* — that a program moves instead of a person.
The work is split between two layers:

- the **controller** handles the body, many times a second: walking, jumping,
  finding a path around obstacles, not bumping into things. This is ordinary
  software for Minecraft, written by others;
- the **supervisor** handles the decisions, twice a second: what to do next,
  which goal to pursue, what is forbidden. The supervisor is an LPS session.

A person driving a car is a fair comparison. The driver decides where to go and
what is unsafe; the reflexes keep the car in its lane. The driver does not think
about each turn of the steering wheel, and the reflexes do not choose the
destination.

The split into two layers is the point. The supervisor **can be wrong without
being dangerous**, because the program's constraints sift every action the
supervisor issues before the controller ever sees it. Anything that has to
happen faster than the supervisor can think — falling, drowning, a monster two
blocks away — belongs to the controller.

No account, no copy of the game and nothing to buy is needed: the example comes
with a small Minecraft server of its own.

The first program, `safety.lps`, reacts: it flees a threat, eats when hungry,
and places a torch when night falls. The
second, `craft.lps`, plans. It says only `achieve has(wooden_pickaxe)`, with the
recipes as causal laws and the need for the right tool as constraints. The
engine works out the rest:

```
events/2         [walk_to(tree)]
events/3         [chop(tree)]
events/4         [craft(plank)]
events/5         [craft(stick)]
events/6         [craft(wooden_pickaxe)]
```

Nothing in that file says *how* to get a pickaxe. The order comes out of the
search.

A viewer shows the game in a browser, and draws the path the bot is following as
a blue line — the supervisor's decision made visible, with the controller
walking it:

![The bot, through prismarine-viewer](../images/minecraft-viewer.png)

How to run the example is in
[LPS2 in detail, §14](introducing-lps2-technical.md#14-minecraft-running-the-example).

## 22. Industrial control, still on paper

Factories, pipelines and power plants are run by small dedicated computers
called programmable logic controllers. A controller of that kind is the
equivalent of the Minecraft controller: it reads its sensors and moves its
valves and motors many times a second, keeping a pressure steady or a motor at
speed. Controllers of that kind are well understood, and nobody wants to replace
them.

What the plan proposes is the equivalent of the Minecraft supervisor: an LPS
program running alongside the existing controllers, deciding what should happen
next and refusing, by constraint, the commands that must never be given — for
instance, never open this valve while that pump is running. The supervisor
changes nothing about the controllers themselves.

No code exists for that yet. The nearest thing to ready is exactly that
supervisor, since it needs nothing that LPS2 does not already have: sessions
that do not stop, and channels that limit who may send what. Further off, the
plan is to write LPS programs out in the language such controllers are
programmed in, and the tools for a first demonstration have been chosen
([LPS2 in detail, §15](introducing-lps2-technical.md#15-industrial-control-the-named-tools)).

---

# Part six — where things stand

## 23. What is not there yet

- **The planner is not always quick, nor always shortest.** On one of the
  standard PDDL test problems, the search was still going after forty minutes,
  and on another the fast search finds a plan of 15 steps where 11 would do. The
  planner is the limitation, not the translation.
- **Old drawings on a dark background.** The editor has a dark theme, and some
  of LPS1's examples draw black text that assumed a white page. Switching to the
  light theme is the way round the problem.
- **One of LPS1's examples runs slower on LPS2**, by a factor of 2.4. Everything
  else runs faster.
- **Industrial control** is still on paper (§22).
- **Some other systems' languages are not read yet**: Jason (a language for
  agents), DECLARE and BPMN (languages for business processes), and behaviour
  trees (used for robots and game characters).

The companion lists the remaining technical gaps
([LPS2 in detail, §18](introducing-lps2-technical.md#18-known-gaps-in-detail)).

## 24. Where to start

The quickest way is the editor. Open the start page, choose an example from the
folder of starting examples, and press **Run**. The wolf, goat and cabbage
puzzle is a good first choice: it is the puzzle stated rather than solved (§5).

Then:

- **[Learning LPS](../tutorials/lps-tutorial.md)** — how to write LPS programs,
  from a two-line one to sessions that do not stop.
- **[Using the editor](../guide/ide.md)** — the editor, part by part, with a
  "how do I …" section.
- **[Glossary](../reference/glossary.md)** — every term used in these documents.
- **[A summary in two pages](abstract.md)** — for someone deciding whether to
  read any of this.
- **[Language reference](../reference/lps.md)** — every construct.
- **[Logical English for LPS](../reference/le-for-lps.md)** — LPS programs
  written in English.
- **[LPS2 in detail](introducing-lps2-technical.md)** — the technical companion
  to this tour.
