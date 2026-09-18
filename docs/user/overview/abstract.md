# LPS2 — a summary in two pages

*Kind: overview · Audience: newcomers · Status: current (2026-09-16)*

LPS2 is a new implementation of the LPS engine, written in SWI-Prolog, together
with the tools needed to write and run LPS programs: a command line, a web
editor, diagrams, animation and explanations. Programs can be written in LPS's
own notation or in Logical English, and can leave it as a browser page or a
Solidity contract.

LPS — Logic Production System, of Kowalski and Sadri — is a language for
programs that act over time. A program is written in terms of

- **fluents**, facts that hold over an interval of time;
- **events** and **actions**, which occur between two time points;
- **causal laws**, which say which fluents an event starts and which it stops;
- **reactive rules**, of the form *if this happens, then do that*;
- **integrity constraints**, which say what must never be true.

LPS2 was written from a specification rather than by copying the earlier
implementation. Where a design decision was not recorded anywhere, it was
recovered by observing what the earlier engine does, and written down before
being implemented (see *Checking the two engines agree* below).

![The LPS2 editor](../images/ide-overview.png)

## Does it behave like the earlier engine?

The earlier implementation, which this document calls **LPS1**, comes with 108
recorded test runs. Each records, cycle by cycle, which fluents held, which
events occurred, and which composite events were recognised.

LPS2 reproduces **99 of those 108 recordings exactly**. For the remaining nine
the recording itself is out of date: it was made before LPS1's own behaviour
last changed. Each of the nine is documented individually, with the evidence,
in `conformance/adjudicated.pl`. Running both engines side by side on those
nine shows that they agree with each other. There is no case where the two
engines differ and the reason is unknown.

"Reproduces exactly" is a strong requirement. It means the same actions in the
same cycles, described by the same terms, differing at most in the names of
variables. It is stronger than "the examples still give sensible answers".

Every test is also run with the program's clauses reversed, with its initial
state reversed, and with the goal queue's order inverted, so that a result
depending on an accident of ordering would show. None does.

LPS2 runs in about **0.4 times** the wall-clock time of LPS1, using between a
third and a half of the memory.

## What LPS2 has that LPS1 did not

| | LPS1 | LPS2 |
|---|---|---|
| **planning** | goal reduction | `achieve`, searching either breadth-first or greedy best-first, whichever suits the problem, chosen without being told; several actions may be taken in one cycle; it plans again if a plan fails |
| **explanation** | — | every run records how each conclusion was reached; five kinds of question can be asked of it, and *why not* distinguishes six reasons, among them an observed call that a constraint refused |
| **trying something out** | — | a session can be copied and the copy run forward independently. The copy costs about 5 microseconds however large the session is |
| **running without end** | yes | and now events may arrive over the network while it runs, each channel restricted to the events it is allowed to send; the stored history is bounded; the mouse can be an input |
| **animation** | paper.js, inside SWISH | Konva in two dimensions, drawing everything LPS1 could draw; three.js in three dimensions, driven by `display3d/2`; a library of icons held locally |
| **editor** | SWISH | Monaco: several files open at once, one grammar covering both LPS and Prolog, errors shown in the text itself, explanations available where the thing being explained is |
| **assistant** | — | a language model that can read the program and answer questions about it, using the editor's own operations as its tools |
| **input languages** | LPS syntax | and Logical English, PDDL, Drools and Inform 7 |
| **ways to run it** | a SWISH server | a command line, one HTTP endpoint, a container image, WebAssembly, which needs no server at all, and — for a program that has one — a Solidity contract |

## How it is put together

About twenty thousand lines of SWI-Prolog, in three layers.

- `src/core/` is the engine.
- `src/syntax/` converts between the languages people write and the form the
  engine runs.
- `src/edges/` is everything that touches the outside world: files, the command
  line, HTTP, language models, and so on.

One rule is enforced mechanically: **nothing in `src/core/` may use threads,
sockets, the clock, files, randomness, or code written in C.** A program called
`tools/lint_core.pl` checks this and is run before every commit.

That one rule has three consequences that would each have been hard to arrange
deliberately. A session is an ordinary Prolog term that is never modified, so
copying one is free. Runs are repeatable, because the engine works out the time
from the cycle number instead of asking the operating system. And the whole
engine compiles to WebAssembly and runs inside a browser, because there is
nothing in it that a browser cannot provide.

## Checking the two engines agree

Before any engine code was written, the choices LPS1 makes were written down as
twenty numbered rules, in `docs/dev/semantics/selection-spec.md`. Each rule says where the
engine has more than one option and which one it takes — for instance, in what
order candidate actions are tried.

LPS1 never recorded these rules. Fifteen were found by reading it; the other
five only by building LPS2 and seeing where it diverged, because they are
properties of the Prolog environment rather than of the algorithm.

## Programs written in other languages

**Logical English** is the second way of writing a program. A document that
declares `the target language is: lps.` reads as English — *when a sender
transfers an amount to a recipient then …*, *it must not be true that …*,
*scenario one is: …* — and compiles to the same internal form as LPS's own
notation. The parser is the separate LogicalEnglish2 project (LE2), which LPS2
loads into its own process; what crosses between the two is a written
agreement, now at version 3 ([`le-lps-interface.md`](../../dev/le-lps-interface.md)), and the
language is described construct by construct in
[`le-for-lps.md`](../reference/le-for-lps.md). Each term remembers its
sentence, so errors and explanations point at the English. A document with no
LPS reading is refused whole rather than half translated. For one that
translates, the editor also computes a **legal view**: who may do what, and with which
effect, as a timeless Logical English program.

**Interactive fiction.** A text adventure is a live session with the player on
a channel. `examples/if/` holds a Logical English library of rooms, things,
doors and people, and stories built on it — Inform 7's own test cases, checked
against Inform's transcripts, and *Alice in Wonderland*. A command is a *try*:
when a precondition refuses it, the engine's own reason is the message. A game
can be forked and the two compared.

**PDDL** and **Drools** come in through the same door. A PDDL precondition
becomes a constraint, an effect a causal law, the goal `achieve`. A Drools rule
becomes a reactive rule, and a change to working memory an event with its
causal law; salience and Java conditions are reported, not guessed at.

**Migration twins.** `examples/migration/` holds programs of other systems —
Solidity contracts (OpenZeppelin's ERC-20, Ownable and Pausable, Circle's
FiatToken), Daml templates, Drools examples — rewritten as Logical English for
LPS by the translators of lpsPlus, with their originals beside them. They run,
explain themselves and have legal views here.

**And out again.** *Deploy as Solidity* writes a program as a smart contract —
fluents as state, actions as functions, preconditions as reverts — ready to
open in Remix. A program with no straight translation, such as one with a reactive
rule, is refused with the reasons. For the Solidity twins the contracts compile,
and replayed on an EVM with the program's scenario they end in the state LPS2's
run ends in.

## Using LPS as the safe part of an agent

An agent built on a language model can do things its designer did not intend.
Part II of the plan asks whether an LPS program can be the part of such an
agent that decides what is permitted, with the model confined to the parts
where a mistake is recoverable.

`examples/agents/llm/` is a working demonstration. The model's only job is
perception: it turns an English sentence into an event term. The fluent that
authorises a destructive action can only be started by a causal law, and that
law is triggered by an event the model is not permitted to send. The constraint
that stops the action is checked by the engine, not by the model.

The demonstration holds with a deliberately weak model, and with one
instructed to lie: the restriction is in how the parts are connected.

`examples/agents/minecraft/` puts the same arrangement in a game: a conventional
library plays Minecraft at twenty steps a second, and an LPS session above it,
at two cycles a second, decides what should be done, every instruction checked
against the program's constraints first.

## Deploying it

One SWI-Prolog process serves the engine, the editor and, when LE2 is loaded,
Logical English, on one port; the container image has no Node in it. A server
that runs programs from strangers checks their Prolog in a sandbox, and a
public one should also require a token. `docs/dev/deploy.md` covers fly.io.

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
