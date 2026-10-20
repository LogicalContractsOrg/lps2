# Glossary

*Kind: reference · Audience: users · Status: current (2026-09-29)*

This glossary contains each term of the LPS2 documents that is not ordinary
English. The terms are in groups by subject, not in alphabetical order. The
reason is that the terms in a group explain each other. An alphabetical index is
at the end.

---

## The language

**LPS** — Logic Production System. LPS is the language of Kowalski and Sadri. An
LPS program says what is true at which time, and what occurs from one time to a
different time. It also says what must be true and what must not be true.

**LPS1** — in these documents, LPS1 is the earlier implementation of LPS. The
work on LPS1 started in 2015. LPS1 is kept here in `legacy_lps1/`. **LPS2** is
this implementation.

**Fluent** — a fact that is true during an interval of time. A fluent can start
to be true and can stop being true. You write a fluent as `light(on)`. You ask
about a fluent with `light(on) at T`.

**Extensional fluent** — a fluent that the engine stores. An extensional fluent
is true because something started it and nothing stopped it after that.

**Intensional fluent** — a fluent that the engine calculates from the state each
time that you ask about it. The engine does not store an intensional fluent. An
intensional fluent never starts and never stops.

**External fluent** — a fluent that the engine finds with a call to an ordinary
Prolog predicate. The engine does not look in the state for an external fluent.

**Event** — something that occurs from one instant to a different instant. An
event comes from outside the program.

**Action** — something that occurs from one instant to a different instant. The
program itself selects to do an action.

**Composite event** — an event that is a sequence of other events. Thus one name
refers to many occurrences. A composite event is the equivalent in the language
of a subroutine. A subroutine is a part of a program that has a name, and the
other parts of the program can use the subroutine by that name.

**Causal law** — a sentence that says which fluents an event starts and which
fluents the event stops. You write a causal law with `initiates`, `terminates`
or `updates`.

**Reactive rule** — a sentence with the form *if this is true and this occurs,
then make that true*. The conclusion of the rule is a goal that stays. The
conclusion is not a trigger that operates one time only. The engine continues
to try to make the goal true until the goal succeeds or becomes impossible.

**Integrity constraint**, **denial**, **`false` sentence** — three names for
the same thing. Such a sentence says that a combination of conditions must never
occur. Sometimes the sentence refers to an action. Then the sentence prevents
that action, and the other name of the sentence is **precondition**.

**Timeless clause** — an ordinary Prolog clause in an LPS program. A timeless
clause has no relation to time. A timeless clause says what something *means*.
It does not say what occurs.

**Observation** — an event that comes into the program from outside. The program
can contain the event in a script, with `observe`. Alternatively, a program can
send the event to a running session through the network.

**Scenario** — the observations that a program writes for itself in a script.
These observations are the events, with their times, that a run receives. In
Logical English, a scenario is `scenario one is:` followed by events with times.
In the written form, a scenario is a set of `observe` facts.

**Refused** — the term for an observed event, or a *call*, that a precondition
stopped. The conditions of the precondition were true in the state when the
event came in. Thus the event did not occur. The other events that were
observed for that cycle also did not occur. The engine records the refusal:
`why_not` gives the answer `refused_by_constraint`, and the timeline shows the
event with a line through it. In a program that is a model of a contract, a
refused call is a call that reverts. Documents also use the word with its
ordinary meaning, about a translation that the system does not make. Examples
are a Logical English document with no LPS meaning, and a program with no
Solidity translation. The word also refers to an event that the system
discards because its channel cannot carry it.

**Default** — the value of a fluent for a key that has no stored value. You
declare a default with `defaults([balance(_, 0)])`, or with `; 0 by default` in
Logical English. The engine never stores the default. The default is an LPS2
declaration, and LPS1 does not have it.

**State** — the set of fluents that are true at one instant.

**Cycle** — one turn of the loop of the engine. In each cycle the engine does
these steps. It takes in the events and applies their effects. It starts the
rules whose conditions are now true. It works on each goal, and it starts with
the goals from earlier cycles. It selects the actions that no constraint
prevents, and it delays the other actions. An action that the engine selects in
cycle T occurs from T to T+1. The order of the steps is in
[`lps.md` §13a](lps.md#13a-how-a-program-runs-step-by-step).

**Rule instance** — one way in which the antecedent of a reactive rule is true.
The antecedent is the "if" part of the rule. For example, take the rule
`if waiting(P) at T then …`, with two persons waiting. This rule has two rule
instances in that cycle, and each rule instance makes its own goal.

**Goal** — something that the engine must make true. A goal is the consequent of
a rule instance, with the values that the antecedent found. The consequent is
the "then" part of the rule. The engine keeps a goal from cycle to cycle until
the goal is true or fails. The engine keeps the goal also when the antecedent
of the rule stops being true. The engine works on the goals from earlier cycles
before the goals that it made in the current cycle.

**Waiting goal** — a goal that cannot continue in this cycle. There are three
possible causes. The next condition of the goal is not true yet. Or the next
action of the goal starts later. Or a constraint prevents the next action now,
and the times of the goal let the action occur in a later cycle. The engine
tries a waiting goal again in each cycle. A goal that is still waiting at the
end of the run is not an error.

**Choosing an action** (developers say *committing*) — the moment when the
engine decides that an action will occur from this cycle to the next cycle. The
engine selects an action immediately when the times of the action let it. The
exception is when a precondition prevents the action. The precondition uses
the state, the observed events, and the actions that the engine selected
before for the same step.

**Failure** (of a run) — the end of a run where the engine could not make a
goal true any more. A reactive rule made the goal. There are three possible
causes. The action of the goal had a fixed time, and a constraint prevented it.
Or the deadline of the goal passed. Or each method to make the goal true
failed. The editor and the command line show `failure`.

**Instant**, **time** — a cycle number. Time in LPS is 1, 2, 3, and so on.

**Trace** — the record of a run. The trace shows which fluents were true in
which cycles and which events occurred. It also shows which composite events
the engine found.

---

## Ways of writing an LPS program

**Written form** — the text that you type into a `.lps` file or a `.pl` file.
Other documents sometimes use the names *external syntax* or *surface syntax*.
Such a file is a Prolog file. The system reads the file with the LPS operators
available.

**Internal form** — the form into which the system changes the written form
before the engine runs the program. Other documents sometimes use the name
*internal syntax*. The internal form is a set of Prolog facts: `reactive_rule/2`,
`initiated/3`, `l_events/2`, `l_int/2`,
`l_timeless/2` and others. The names of files that contain the internal form end
in `_.P` or `.lpsw`.

**Translator** — the program that changes the written form into the internal
form. The translator of LPS1 has the name `psyntax`. The translator of LPS2 is
in `src/syntax/`.

**Logical English** — a controlled English notation. "Controlled" means that
the English uses only a fixed set of sentence patterns. A different project
makes Logical English. The system can change Logical English into the same
internal form. The names of Logical English files end in `.le`. **LE2** is the
implementation of Logical English that LPS2 communicates with.

**PDDL** — the Planning Domain Definition Language. The international planning
competitions use PDDL. LPS2 can translate PDDL and run it.

**Drools** — a language for business rules. LPS2 can translate a useful part of
Drools.

**Door** — a way in for a program that is in a different notation. Examples are
a PDDL domain and problem, or a Drools rule file. When you open such a program,
LPS2 translates it into the internal form. Then the program runs like each
other program, and the engine explains it in the same way.
`examples/planning/` contains the PDDL examples and `examples/migration/drools/drl/` contains the Drools examples.

**Companion file** — the `.lps` file with the same name, next to a `.le`
document (for example `badlight.le` and `badlight.lps`). The two files are one
program. The system translates them together, and the `.le` document first. The
companion file contains the parts that are not English: `display/2` clauses and
Prolog helpers.

**LE2 ↔ LPS2 interface** — the written agreement between the two projects. The
agreement says what goes from one project to the other: text in the internal
form, and a list that says which sentence each term came from. The agreement has
a version number. Version 3 added
`defaults/1`. The agreement is in
[`docs/dev/le-lps-interface.md`](../../dev/le-lps-interface.md).

**Twin**, or **migration twin** — a program of a different system, written again
as a Logical English for LPS program. Examples are a Solidity contract, a Daml
template, and a set of Drools rules. One of the translators of lpsPlus writes
the twin. Thus the program runs here, and the engine can explain it here. The
twins are in `examples/migration/`, in one directory for each source system.
Each directory contains, in `sources/`, the original programs that the
translator used.

**Legal view** — a timeless Logical English program that the system calculates
from a Logical English for LPS document and from its run. The legal view has one
rule for each action. That rule says who can do that action, and when. The legal
view also has one rule for each causal law. That rule says what the law
changes. The legal view also has a scenario for the state before each call of
the scenario of the document. The editor of LE2 answers the questions of the
view, not this engine. In the editor, select *View ▸ Legal view*.

**Interactive fiction** — a text adventure. A text adventure is a world that
receives a typed command at each turn. On LPS, a work of interactive fiction is
a Logical English program that includes the library in `examples/if/`.

**Story** — a Logical English document that includes the interactive-fiction
library (`includes these resources: world`). You can play a story.

---

## Checking that LPS2 behaves like LPS1

**Recorded run** — a file that records what LPS1 did on one program, cycle by
cycle. Other documents call a recorded run a **golden** or a **golden trace**.
There are 108 such files, and their names end in `.lpst`.

**Reproduces exactly** — this term means these conditions. LPS2 makes the same
fluents, events and composite events as the recorded run. They occur in the same
cycles, and the same terms describe them. Only the names of variables can be
different. The order in a cycle is not important. Each other difference is
important.

**Trace equivalence** — the property that the previous entry describes. Trace
equivalence is less strong than a proof that the two engines have the same
meaning. But trace equivalence is much stronger than a check that the examples
still give sensible answers.

**Out-of-date recording** — a recorded run that was made before the last change
to the behaviour of LPS1. Thus LPS1 also does not give the same result as the
recording now. Other documents call it a **stale golden**. Nine of the 108
recordings are out of date. `conformance/adjudicated.pl` gives the documentation
for each of them separately.

**Running the engines side by side** (`--engine cross`) — run LPS1 and LPS2 on
the same program, and compare the results of the two engines with each other,
not with the recording. When a recording is older than the behaviour that it
recorded, only this direct comparison of the engines has a meaning.

**Perturbation** — a change, made on purpose, to something that must not change
the result. There are three perturbations. One reverses the order of the
clauses. One reverses the initial state. One reverses the order in which the
engine takes goals from its queue. The harness runs each test with each
perturbation. Possibly the answer of a program depends on an accident. Then one
of the perturbations finds that accident.

**The harness** — the program in `conformance/` that runs all of these checks.

---

## How this implementation is organised

**`src/core/`** — the engine. Nothing in the engine can use threads (many
things that run at the same time), network connections, the clock, files,
random values, or code in the C language. `tools/lint_core.pl` makes sure that
nothing in the engine uses these things.

**`src/syntax/`** — the translation between the written forms and the internal
form.

**`src/edges/`** — all the parts that communicate with the outside world: files,
the command line, HTTP, language models, and sessions that run continuously.

**Session** — one run of one program. A session is an ordinary Prolog term, and
nothing changes it. Because nothing changes a session, a copy of a session is
one step. The cost of a copy is the same for each size of session. Thus it is
cheap to ask "what will occur if".

**Milestone**, written **M0** to **M19** — a work item with a number in the
development plan, `docs/project/plan-of-record.md`. The numbers are in comments in the
source and in the plan. The numbers are only a filing system.

**§I.3**, **§II.4**, and similar — a section of the same plan. The Roman numeral
comes first, then the section number.

---

## Running and drawing

**Continuously running session** — a run that does not stop at `maxTime`. It
does its cycles in real time and accepts events while it runs. Other documents
call it a **perpetual session** or a **live session**. You start it with
`./lps live` or from the *Live* panel of the editor.

**Channel** — a name for the events that come into a continuously running
session. A channel has a list of the event predicates that it can carry. The
session discards an event that is not on the list of its channel, and it tells
you about the discarded event.

**Fork** — a copy of a session that runs forward separately from the original.
Nothing changes a session. Thus the cost of a fork is the same for each size of
session.

**Play** — run a story as a game, with `./lps play` or with the *Play* panel of
the editor. The engine compares the text that you type with the command
templates of the story. *why* asks the engine why the last turn had its result.
You can fork a game. *diff* tells you what occurred in one game and not in the
other game.

**`display/2`** — the declaration where a program says how the system must draw
its fluents and events. `display3d/2` is the same idea in three dimensions.

**Timeline** — the diagram that shows which fluents were true in which cycles,
and which events occurred. The diagram shows them as horizontal bars and dots.

**State-transition diagram** — the diagram of the states that a program went
through, and of the events that moved the program from one state to the next.
The editor shows it as **Automaton**. LPS1 made the same picture with `godfa/1`.

**Explanation** — the answer to *why did this occur* or *why did this not
occur*. The engine makes the explanation from the record that it keeps of how it
found each conclusion.

---

## Software terms used in these documents

**Monaco** — the software that gives the text editor in the browser. Visual
Studio Code uses the same software.

**Konva** — the software library that draws the two-dimensional animation.

**three.js** — the software library that draws the three-dimensional animation.

**esbuild** — the tool that collects the source files of the editor into a small
number of files. The server sends these files to the browser.

**WebAssembly**, abbreviated **WASM** — a form for a program that lets the
program run in a browser. The engine of LPS2 is compiled into WebAssembly. Thus
a program can run with no server.

**Deploy as WASM** — the menu item *Misc ▸ Deploy as WASM* of the editor. It
makes one HTML page that contains all that it needs. HTML is the language of
web pages. The other names of the page are the **WASM bundle** and the
**standalone page**. The page contains the program and the sources of the
engine. The page runs the program in a browser and shows its trace, with no
LPS2 server. The page gets the WebAssembly runtime of SWI-Prolog from the same
location as the page itself. The runtime is the software that runs Prolog in a
browser. The page contains only the engine and the translator of the written
form. It has no live sessions, no assistant and no Logical English.

**Deploy as Solidity** — the menu item *Misc ▸ Deploy as Solidity* of the
editor, and the command `./lps solidity`. It writes the program as a Solidity
smart contract. The fluents become state, the actions become functions, and the
preconditions become reverts. Then it opens the contract in **Remix IDE**.
Remix IDE is the IDE of the Ethereum Foundation, and it runs in a browser. IDE
means integrated development environment: an editor and its tools together. In
Remix IDE you can put the contract on a test chain. Some programs have no
direct translation, for example a program with a reactive rule, with planning,
or with its own Prolog. The system refuses such a program and gives the
reasons. It does not make an approximate translation.

**Export to another system** — the menu item *Misc ▸ Export to another system*
of the editor. It writes a Logical English document in the format of a
different system. One of the exporters of the Logical English installation
does the work.

**Sandbox** — the check that a server does on the Prolog in a program that it
receives. The sandbox refuses each part of that Prolog that can get access to
the computer. The sandbox is on by default on the server, and off on the command
line.

**Container image** — a packaged copy of the full system, with SWI-Prolog. You
can run a container image on a different computer, and you do not have to
install anything.

**Endpoint** — one web address that accepts requests. LPS2 has one endpoint,
`POST /lpsapi`. Each operation is a field in the request, not a separate
address.

**Assistant** — the panel of the editor where a language model answers
questions about the program. The language model can also change the program. It
uses the operations of the editor as its tools.

**Language model**, sometimes **LLM** (large language model) — a system, such as
Claude or GPT, that makes text as a response to text. LPS2 uses a language model
only where you can recover from a mistake. These uses are: answers to questions
about a program, the translation of an English sentence into an event term, and
proposals about how to draw a program.

**Token** — the unit that a language model uses to measure text. A token is
approximately three-quarters of a word. The **context window** of a model is the
number of tokens that it can receive at one time.

---

## Alphabetical index

Action · Assistant · Automaton · Causal law · Channel · Choosing an action · Companion file ·
Composite event · Container image · Context window · Continuously running
session · Cycle · Default · Denial · Deploy as Solidity · Deploy as WASM ·
`display/2` · Door · Drools · Endpoint · esbuild · Event · Explanation · Export
to another system · Extensional fluent · External fluent · `false` sentence · Failure ·
Fluent · Fork · Goal · Golden · Harness · Instant · Integrity constraint · Intensional
fluent · Interactive fiction · Internal form · Konva · Language model · LE2 ·
LE2 ↔ LPS2 interface · Legal view · Live session · Logical English · LPS · LPS1
· LPS2 · Migration twin · Milestone · Monaco · Observation · PDDL · Perpetual
session · Perturbation · Play · Precondition · Reactive rule · Recorded run ·
Refused · Remix IDE · Rule instance · Sandbox · Scenario · Session · Stale golden · Standalone page · State ·
State-transition diagram · Story · three.js · Time · Timeless clause · Timeline
· Token · Trace · Trace equivalence · Translator · Twin · Waiting goal · WASM · WASM bundle ·
WebAssembly · Written form
