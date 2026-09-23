# LPS2 — a summary in two pages

*Kind: overview · Audience: newcomers · Status: current (2026-09-16)*

LPS2 is a new version of the engine that runs programs written in LPS (Logic
Production Systems) — the engine being the part that actually carries a program
out. LPS2 is written in SWI-Prolog, a widely used system for the Prolog
language, and it comes with the tools needed to write and run LPS programs: a
command line, an editor that runs in a web browser, diagrams, animation and
explanations. You can write a program in LPS's own notation or in Logical
English, which is ordinary English written to a fixed pattern. A finished
program can also leave the system, either as a page you open in a browser or as
a Solidity contract — a smart contract, of the kind that runs on a blockchain.

LPS — Logic Production System, of Kowalski and Sadri — is a language for
programs that act over time. A program is written in terms of five kinds of
thing:

- **fluents**, facts that hold over an interval of time;
- **events** and **actions**, which occur between two time points;
- **causal laws**, which say which fluents an event starts and which it stops;
- **reactive rules**, of the form *if this happens, then do that*;
- **integrity constraints**, which say what must never be true.

LPS2 was built from a written description of what the language should do,
rather than by copying the earlier program line by line. Some of the decisions
the earlier engine makes had never been written down anywhere. Each of those
decisions was recovered by watching what the earlier engine does, and each one
was written down before anybody put it into the new engine (see *Checking the
two engines agree* below).

![The LPS2 editor](../images/ide-overview.png)

## Does it behave like the earlier engine?

The earlier version of the engine, which this document calls **LPS1**, comes
with 108 recorded test runs. Each recording lists, cycle by cycle, which
fluents held, which events occurred, and which composite events the engine
recognised. A cycle is one round of the engine's work: it takes in what has
happened, works out what follows, decides, and acts.

LPS2 reproduces **99 of those 108 recordings exactly**. For the remaining nine,
the recording itself is out of date, because somebody made the recording before
LPS1's own behaviour last changed. Each of the nine is written up separately,
with the evidence, in `conformance/adjudicated.pl`. Running both engines side
by side on those nine shows that the two engines agree with each other. There
is no case where the two engines differ and the reason is unknown.

"Reproduces exactly" sets a high bar. LPS2 must take the same actions in the
same cycles, described by the same terms — a term being one piece of Prolog,
such as `transfer(bob, fariba, 10)` — differing at most in the names of the
variables. That bar is a good deal higher than "the examples still give
sensible answers".

Every test is also run three more times, with something deliberately disturbed.
The rules and facts of the program are put in reverse order; the facts the
program starts with are put in reverse order; and new goals are taken from the
front of the waiting list instead of the back. A result that depended on an
accident of ordering would show up under one of those three changes. None does.

LPS2 finishes a run in about **0.4 times** the time LPS1 takes on a clock,
using between a third and a half of the memory.

## What LPS2 has that LPS1 did not

| | LPS1 | LPS2 |
|---|---|---|
| **planning** | goal reduction | `achieve`, searching either breadth-first (every short plan before any longer one) or greedy best-first (always following the step that looks most promising), whichever suits the problem, and choosing between them without being told; several actions may be taken in one cycle; the engine plans again if a plan fails |
| **explanation** | — | every run records how the engine reached each conclusion; five kinds of question can be asked of that record, and *why not* tells six reasons apart, among them a request that a constraint refused |
| **trying something out** | — | a session — one run of a program, with everything that has happened in it so far — can be copied, and the copy carried on independently. Making the copy takes about 5 microseconds, however large the session is |
| **running without end** | yes | and now events may arrive over the network while the program runs, with each channel allowed to send only certain events; only so much history is kept; a click of the mouse can be an event |
| **animation** | paper.js, inside SWISH | Konva in two dimensions, drawing everything LPS1 could draw; three.js in three dimensions, driven by `display3d/2`; a library of small pictures kept on the same machine |
| **editor** | SWISH | Monaco: several files open at once, one set of colouring rules covering both LPS and Prolog, errors shown in the text itself, and explanations offered where the thing being explained is |
| **assistant** | — | a language model — the kind of program that answers questions in ordinary English — which can read the program and answer questions about it, using the editor's own operations as its tools |
| **input languages** | LPS syntax | and Logical English, PDDL, Drools and Inform 7 |
| **ways to run it** | a SWISH server | a command line, one web address that other programs can call, a packaged image ready to run on a server, WebAssembly, which needs no server at all, and — for a program that has one — a Solidity contract |

## How it is put together

About twenty thousand lines of SWI-Prolog, in three layers.

- `src/core/` is the engine, the part that actually runs a program.
- `src/syntax/` converts between the languages people write and the form the
  engine runs.
- `src/edges/` is everything that touches the outside world: files, the command
  line, requests over the web, language models, and so on.

One rule is checked by machine rather than left to memory: **nothing in
`src/core/` may do two things at once, open a connection to another machine,
read the clock, read or write a file, use randomness, or call code written in
the C language.** A program called `tools/lint_core.pl` checks that rule, and
it runs before every change is recorded.

That one rule brings three benefits, each of which would have been hard to
arrange on purpose. Copying a session costs nothing, because a session is an
ordinary piece of Prolog that nothing ever alters. A run can be repeated and
come out the same, because the engine works out the time from the cycle number
instead of asking the computer's own clock. And the whole engine can be turned
into WebAssembly — a form a web browser can run — and so runs inside a browser,
because the engine asks for nothing a browser cannot give it.

## Checking the two engines agree

Before anybody wrote a line of the new engine, the choices LPS1 makes were
written down as twenty numbered rules, in `docs/dev/semantics/selection-spec.md`. Each rule
names a point where the engine has more than one option, and says which option
the engine takes — for instance, in what order the engine tries the actions it
is considering.

LPS1 never recorded those twenty rules anywhere. Fifteen of them came to light
by reading LPS1's own code. The other five came to light only when LPS2 was
built and behaved differently, because those five follow from the Prolog system
LPS1 runs on rather than from the method itself.

## Programs written in other languages

**Logical English** is the second way of writing a program. A document that
declares `the target language is: lps.` reads as ordinary English — *when a
sender transfers an amount to a recipient then …*, *it must not be true that
…*, *scenario one is: …* — and turns into the same internal form that LPS's own
notation turns into. (The internal form is the shape the engine actually runs.
Nobody writes it by hand.) The program that reads the English, working out what
each sentence says, belongs to a separate project, LogicalEnglish2 or LE2,
which LPS2 loads and runs inside itself. What the two projects send each other
is fixed by a written agreement, now at version 3
([`le-lps-interface.md`](../../dev/le-lps-interface.md)), and the language is
described one construct at a time in
[`le-for-lps.md`](../reference/le-for-lps.md). Each term remembers which
sentence it came from, so errors and explanations point at the English. A
document that has no LPS reading is refused as a whole, rather than half
translated. When a document does translate, the editor also works out a **legal
view**: who may do what, and with which effect, written as a Logical English
program with no time in it.

**Interactive fiction.** A text adventure — a game you play by typing — is a
session that runs on without stopping, with the player sending events down a
channel of their own. `examples/if/` holds a Logical English library of rooms,
things, doors and people, and stories built on that library: Inform 7's own
test cases, checked against the transcripts Inform produces, and *Alice in
Wonderland*. A command the player types is a *try* rather than an order. When a
precondition refuses the command, the engine's own reason for refusing becomes
the message on the screen. A game can be copied part way through, and the two
copies compared.

**PDDL** and **Drools** come in through the same door. PDDL, the Planning
Domain Definition Language, is how planning problems are usually written: a
PDDL precondition becomes a constraint, an effect becomes a causal law, and the
stated goal becomes `achieve`. Drools is a widely used business rules system: a
Drools rule becomes a reactive rule, and a change to the facts Drools is
holding becomes an event together with its causal law. Where Drools has
something LPS does not — `salience`, or a condition written in Java — the
translator says so rather than guessing.

**Migration twins.** `examples/migration/` holds programs written for other
systems: Solidity contracts (OpenZeppelin's ERC-20, Ownable and Pausable,
Circle's FiatToken), Daml templates and Drools examples. The translators of the
lpsPlus project rewrote each of those programs as Logical English for LPS, and
each original sits beside its rewrite. The rewritten programs run here, explain
themselves, and have legal views.

**And out again.** *Deploy as Solidity* writes a program out as a smart
contract — fluents become the contract's stored state, actions become its
functions, preconditions become the checks that refuse a transaction — ready to
open in the Remix editor. A program that has no straight translation, such as
one with a reactive rule in it, is refused, with the reasons given. The
contracts written from the Solidity twins do compile. Run again with the
program's own scenario on an Ethereum virtual machine (EVM), the machine such
contracts run on, they finish in the same state LPS2's own run finishes in.

## Using LPS as the safe part of an agent

An agent — a program that decides for itself what to do next — can do things
its designer never intended when a language model is what decides. Part II of
the plan asks whether an LPS program can be the part of such an agent that
decides what is permitted, leaving the language model only those jobs where a
mistake can be put right.

`examples/agents/llm/` is a working demonstration. The model has one job only,
which is to understand what was said: the model reads an English sentence and
turns it into an event. Only a causal law can start the fluent that authorises
a destructive action, and only an event the model is not allowed to send can
set that law off. The engine, not the model, checks the constraint that stops
the action.

The demonstration still holds with a deliberately weak model, and with a model
told to lie. The restriction lies in the way the parts are connected together.

`examples/agents/minecraft/` puts the same arrangement in a game. An ordinary
software library plays Minecraft at twenty steps a second. Above that library
sits an LPS session, running at two cycles a second, which decides what should
be done; every instruction it issues is checked against the program's
constraints before the library sees it.

## Deploying it

One running copy of SWI-Prolog serves the engine, the editor and — when LE2 is
loaded — Logical English, all on one port, which is one numbered door on the
machine. The packaged image that ships the whole system has no Node.js in it;
Node.js is needed to build the editor, not to run it. A server that runs
programs sent by strangers checks their Prolog in a sandbox, a confined area
where a program can do no harm, and a server open to the public should also ask
callers for a token, a secret word. `docs/dev/deploy.md` covers running the
system on fly.io.

## Where to start

```sh
./lps run examples/start/goat_declarative.pl     # the wolf, goat and cabbage puzzle
cd ui && npm install && npm run build      # build the editor, once
./lps ide                                  # start the server on port 3060
                                           #   /      the examples and the documents
                                           #   /ide   the editor
```

- **[`glossary.md`](../reference/glossary.md)** — every term used in these documents, defined.
- **[`lps-tutorial.md`](../tutorials/lps-tutorial.md)** — how to write LPS programs, starting
  from a two-line one.
- **[`ide.md`](../guide/ide.md)** — how to use the editor, with a
  "how do I …" section.
- **[`introducing-lps2.md`](introducing-lps2.md)** — a longer tour, illustrated
  with pictures taken from the running system.
- **[`lps.md`](../reference/lps.md)** — the reference: every construct of the
  language; **[`le-for-lps.md`](../reference/le-for-lps.md)** — the same, in Logical English.
- **[`inform-users.md`](../tutorials/inform-users.md)** — interactive fiction on LPS.
- **[`plan-of-record.md`](../../project/plan-of-record.md)** — the development plan, and the one place
  where the state of the project is recorded.
