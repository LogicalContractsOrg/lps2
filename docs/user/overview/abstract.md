# LPS2 — a summary in two pages

*Kind: overview · Audience: newcomers · Status: current (2026-09-16)*

LPS2 is a new version of the engine for programs in LPS (Logic Production System).
The engine is the part of the system that runs a program. LPS2 is written in
SWI-Prolog. SWI-Prolog is a frequently used system for the Prolog language. LPS2 has
the tools that are necessary to write and run LPS programs: a command line, an editor
that runs in a web browser, diagrams, animation and explanations. You can write a
program in the notation of LPS or in Logical English. Logical English is ordinary
English that you write in a fixed pattern.

A finished program can also go out of the system in two forms. The first form is a
page that you open in a browser. The second form is a Solidity contract. A Solidity
contract is a smart contract, of the kind that runs on a blockchain.

LPS (Logic Production System, by Kowalski and Sadri) is a language for programs that
act over time. You write a program with five kinds of thing:

- **fluents**: facts that are true for an interval of time;
- **events** and **actions**: things that occur between two time points;
- **causal laws**: laws that say which fluents an event starts and which fluents
  it stops;
- **reactive rules**: rules of the form *if this occurs, then do that*;
- **integrity constraints**: constraints that say what must never be true.

The developers built LPS2 from a written description of what the language must do.
They did not copy the earlier program line by line. Some decisions of the earlier
engine were not written in any document. The developers found each of these decisions
when they watched what the earlier engine does. They wrote each decision down before
anybody put it into the new engine (refer to *Checking the two engines agree* below).

![The LPS2 editor](../images/ide-overview.png)

## Does it behave like the earlier engine?

This document calls the earlier version of the engine **LPS1**. LPS1 has 108 recorded
test runs. Each recording gives a list for each cycle. The list shows which fluents
were true, which events occurred, and which composite events the engine recognised. A
cycle is one round of the work of the engine. In a cycle, the engine receives what
occurred, calculates what follows, decides, and acts.

LPS2 gives the same result as **99 of those 108 recordings exactly**. For the other
nine, the recording itself is out of date. Somebody made each of these recordings
before the last change to the behaviour of LPS1. A separate report for each of the
nine, with the evidence, is in `conformance/adjudicated.pl`. When you run the two
engines side by side on these nine, the two engines agree. There is no case where the
two engines are different and the reason is unknown.

"The same result exactly" is a high standard. LPS2 must do the same actions in the
same cycles. The same terms must describe these actions. A term is one piece of
Prolog, for example `transfer(bob, fariba, 10)`. Only the names of the variables can
be different. This standard is much higher than "the examples still give sensible
answers".

The developers also run each test three more times, with a change that they make on
purpose. In the first run, the rules and facts of the program are in reverse order.
In the second run, the facts that the program starts with are in reverse order. In
the third run, the engine takes new goals from the front of the waiting list, not
from the back. Possibly a result depends on an accidental order. One of these three
changes will then show the problem. No result shows such a problem.

LPS2 completes a run in approximately **0.4 times** the clock time of LPS1. LPS2 uses
between one third and one half of the memory.

## What LPS2 has that LPS1 did not

| | LPS1 | LPS2 |
|---|---|---|
| **planning** | goal reduction | `achieve`, with one of two searches: breadth-first (each short plan before a longer plan) or greedy best-first (always the step that looks best). The engine selects the search that is better for the problem, without an instruction. The engine can do more than one action in one cycle. When a plan fails, the engine makes a new plan |
| **explanation** | — | each run keeps a record of how the engine found each conclusion. You can ask five kinds of question about this record. *Why not* finds the difference between six reasons. One of these reasons is a request that a constraint refused |
| **trying something out** | — | you can copy a session, and the copy then continues separately. A session is one run of a program, with all the things that occurred in it until now. The copy takes approximately 5 microseconds, for a session of any size |
| **running without end** | yes | and now events can come over the network while the program runs. Each channel can send only some events. The engine keeps only a limited quantity of history. A click of the mouse can be an event |
| **animation** | paper.js, inside SWISH | Konva in two dimensions, which draws all the things that LPS1 could draw; three.js in three dimensions, controlled by `display3d/2`; a library of small pictures on the same machine |
| **editor** | SWISH | Monaco: you can open more than one file at a time. One set of colour rules is for LPS and also for Prolog. The editor shows errors in the text itself. The editor gives explanations at the location of the thing that they explain |
| **assistant** | — | a language model, which can read the program and answer questions about it. A language model is a type of program that answers questions in ordinary English. The assistant uses the operations of the editor as its tools |
| **input languages** | LPS syntax | and Logical English, PDDL, Drools and Inform 7 |
| **ways to run it** | a SWISH server | a command line; one web address that other programs can call; a packaged image that is ready to run on a server; WebAssembly, which does not need a server; and a Solidity contract, for a program that has one |

## How it is put together

LPS2 has approximately twenty thousand lines of SWI-Prolog, in three layers.

- `src/core/` is the engine, the part that runs a program.
- `src/syntax/` changes the languages that people write into the form that the
  engine runs, and back again.
- `src/edges/` contains all the parts that touch the outside world: files, the
  command line, requests over the web, language models, and other parts.

A machine checks one rule, so that nobody must remember it: **nothing in
`src/core/` may do two things at the same time, open a connection to another
machine, read the clock, read or write a file, use random values, or call code
in the C language.** A program, `tools/lint_core.pl`, checks this rule. The program
runs before the system records each change.

This one rule gives three benefits. It would be difficult to get each of these
benefits on purpose. The first benefit: a copy of a session costs nothing. A session
is an ordinary piece of Prolog, and nothing changes it. The second benefit: when you
run a program again, the result is the same. The engine calculates the time from the
cycle number. It does not ask the clock of the computer. The third benefit: you can
change the full engine into WebAssembly, and the engine then runs in a browser.
WebAssembly is a form of program that a web browser can run. This is possible
because the engine asks for nothing that a browser cannot give.

## Checking the two engines agree

Before anybody wrote a line of the new engine, the developers wrote the choices of
LPS1 as twenty numbered rules, in `docs/dev/semantics/selection-spec.md`. Each rule
identifies a point where the engine has more than one option. The rule says which
option the engine selects. For example, one rule gives the order in which the engine
tries the actions that it examines.

LPS1 did not record these twenty rules in any location. The developers found fifteen
of them in the code of LPS1. They found the other five only when they built LPS2 and
LPS2 behaved differently. These five rules come from the Prolog system under LPS1,
not from the method itself.

## Programs written in other languages

**Logical English** is the second way to write a program. Some documents declare
`the target language is: lps.` Such a document reads as ordinary English: *when a
sender transfers an amount to a recipient then …*, *it must not be true that
…*, *scenario one is: …*. The document changes into the same internal form as the
notation of LPS. The internal form is the shape that the engine runs. Nobody writes
the internal form by hand.

The program that reads the English, and finds what each sentence says, is part of a
separate project, LogicalEnglish2 (LE2). LPS2 loads LE2 and runs it inside itself. A
written agreement controls what the two projects send to each other. The agreement
is now at version 3 ([`le-lps-interface.md`](../../dev/le-lps-interface.md)).
[`le-for-lps.md`](../reference/le-for-lps.md) describes the language, one construct
at a time. Each term keeps a record of the sentence that it came from. Thus errors and
explanations point to the English. If a document has no LPS meaning, the system
refuses the full document. It does not translate half of the document. When a
document translates, the editor also makes a **legal view**. A legal view shows who
can do what, and with which effect. The legal view is a Logical English program with
no time in it.

**Interactive fiction.** A text adventure is a game that you play when you type
commands. A text adventure is a session that continues without a stop. The player
sends events through a channel that only the player uses. `examples/if/` contains a
Logical English library of rooms, things, doors and people. It also contains stories
that use this library. These stories are the test cases of Inform 7, checked against
the transcripts that Inform makes, and *Alice in Wonderland*. A command from the
player is a *try*, not an order. When a precondition refuses the command, the reason
of the engine for the refusal becomes the message on the screen. You can copy a game
in the middle, and compare the two copies.

**PDDL** and **Drools** come in through the same door. PDDL (Planning Domain
Definition Language) is the usual language for planning problems. A PDDL
precondition becomes a constraint, an effect becomes a causal law, and the goal
becomes `achieve`. Drools is a frequently used business rules system. A Drools rule
becomes a reactive rule. A change to the facts in Drools becomes an event together
with its causal law. Drools has some things that LPS does not have, for example
`salience`, or a condition in Java. For these things, the translator tells you about
the difference. It does not guess.

**Migration twins.** `examples/migration/` contains programs for other systems:
Solidity contracts (OpenZeppelin's ERC-20, Ownable and Pausable, Circle's
FiatToken), Daml templates and Drools examples. The translators of the lpsPlus
project wrote each of these programs again as Logical English for LPS. Each original
is next to its new version. The new programs run here, explain themselves, and have
legal views.

**And out again.** *Deploy as Solidity* writes a program as a smart contract. Fluents
become the stored state of the contract. Actions become its functions. Preconditions
become the checks that refuse a transaction. You can open the result in the Remix
editor. Some programs do not have a direct translation, for example a program with a
reactive rule. The system refuses such a program, and gives the reasons. The
contracts from the Solidity twins compile. The developers ran each contract again
with the scenario of its program on an Ethereum virtual machine (EVM). The EVM is the
machine that such contracts run on. Each contract stops in the same state as the run
of LPS2.

## Using LPS as the safe part of an agent

An agent is a program that decides by itself what to do next. When a language model
decides, an agent can do things that its designer did not intend. Part II of the plan
asks a question: can an LPS program be the part of such an agent that decides what is
permitted? The language model then does only the jobs where you can correct a
mistake.

`examples/agents/llm/` is a demonstration that operates. The model has only one job:
to understand what a person said. The model reads an English sentence and changes it
into an event. Only a causal law can start the fluent that authorises a destructive
action. Only an event that the model cannot send can start that causal law. The
engine, not the model, checks the constraint that stops the action.

The demonstration stays correct with a model that is weak on purpose, and with a
model that has an instruction to lie. The limit is in the connections between the
parts.

`examples/agents/minecraft/` uses the same arrangement in a game. An ordinary
software library plays Minecraft at twenty steps each second. An LPS session sits
above that library, and runs at two cycles each second. The session decides what to
do. The system checks each instruction from the session against the constraints of
the program before the library receives it.

## Deploying it

One running copy of SWI-Prolog serves the engine, the editor and, when LE2 is loaded,
Logical English. All of these use one port. A port is one numbered door on the
machine. The packaged image that contains the full system does not contain Node.js.
You need Node.js to build the editor, not to run it. Some servers run programs from
unknown persons. Such a server checks their Prolog in a sandbox. A sandbox is a
closed area where a program cannot cause damage. A server that is open to the public
must also ask callers for a token. A token is a secret word. `docs/dev/deploy.md`
tells you how to run the system on fly.io.

## Where to start

```sh
./lps run examples/start/goat_declarative.pl     # the wolf, goat and cabbage puzzle
cd ui && npm install && npm run build      # build the editor, once
./lps ide                                  # start the server on port 3060
                                           #   /      the examples and the documents
                                           #   /ide   the editor
```

- **[`glossary.md`](../reference/glossary.md)**: the definition of each term in these
  documents.
- **[`lps-tutorial.md`](../tutorials/lps-tutorial.md)**: how to write LPS programs. It
  starts with a program of two lines.
- **[`ide.md`](../guide/ide.md)**: how to use the editor. It has a "how do I …"
  section.
- **[`introducing-lps2.md`](introducing-lps2.md)**: a longer tour, with pictures from
  the running system.
- **[`lps.md`](../reference/lps.md)**: the reference, with each construct of the
  language. **[`le-for-lps.md`](../reference/le-for-lps.md)**: the same reference, in
  Logical English.
- **[`inform-users.md`](../tutorials/inform-users.md)**: interactive fiction on LPS.
- **[`plan-of-record.md`](../../project/plan-of-record.md)**: the development plan.
  It is the one place where the state of the project is recorded.
