# LPS2

LPS2 is a system for writing and running programs in **LPS**, the Logic
Production System of Robert Kowalski and Fariba Sadri. An LPS program describes
a world that changes over time. The program says which facts hold at each
moment, which events change those facts, how the program should react to what
happens, and what must never be the case. LPS2 runs such a program cycle by
cycle, shows what happened, and explains why.

LPS2 is written in SWI-Prolog. LPS2 is a new implementation that succeeds the
original one from Imperial College London, called **LPS1** in these documents,
and runs LPS1's programs the same way. [`History.md`](History.md) tells how
LPS2 was built.

## Try it in your browser

The public demonstration server is
**[lps2.logicalcontracts.com](https://lps2.logicalcontracts.com)**. Nothing
needs installing, and no account is needed.

- [Open the editor](https://lps2.logicalcontracts.com/ide) and choose an
  example from the **Examples** menu.
- [Open the wolf, goat and cabbage puzzle](https://lps2.logicalcontracts.com/ide?example=start/goat_declarative)
  and press **Run**. The puzzle is stated, not solved: LPS2 finds the crossings
  itself.
- The **Help** menu holds the tutorial, the guide to the editor and the
  language reference. Documentation is fully searchable.

**Logical English**, the language most of the examples are written in, has
its own editor and repository:
[LogicalContractsOrg/LogicalEnglish2](https://github.com/LogicalContractsOrg/LogicalEnglish2),
live at [le2.logicalcontracts.com](https://le2.logicalcontracts.com).

Programs of other systems — Solidity, Daml, Drools, L4, Epilog — open here as
Logical English for LPS through the
[Logical English Translators](https://logicalcontracts.com/logical-english-extensions/),
a licensed product; the translations of their published examples are in
[`examples/migration/`](./examples/migration/). The PDDL and Inform 7 readers
are part of this repository.

[The privacy notice](docs/user/privacy.md) says what the hosted site keeps
about you: nothing, unless you sign in and hold a licence or a password
account.

## What LPS2 does

**Write in English, or in LPS.** A program is written in:

- **Logical English** (`.le`), a controlled form of English that reads like a
  rule book, compiled by the companion LogicalEnglish2 system;
- or LPS's own written form (`.pl` or `.lps`), which also opens the programs of
  LPS1 unchanged.

Or you can convert an existing program from another system: **PDDL** (the
Planning Domain Definition Language), **Drools** rules, an **Inform 7** story,
a **Solidity** or **Daml** contract, **L4**, **Epilog**, and, as timeless
Logical English rules, Bitcoin Miniscript, s(CASP), Blawx, Oracle Intelligent
Advisor, Socotra and OIPA. **File ▸ Open…** converts the file as it opens it,
and says what it could not carry over. In the other direction, a program can be
written out as a Solidity or Daml contract, or as LegalRuleML norms.
[Other systems and LPS](docs/user/integrations/index.md) is the map of every
conversion, and which ones need the
[Logical English Translators](https://logicalcontracts.com/logical-english-extensions/).

Whatever the source, the program arrives at the same internal form and is run by
the same engine. An error is reported at the line the author wrote, including
the English sentence when the program is in Logical English.

**An editor that shows the run.** The editor is a web page. Beside the program,
it shows:

- a **timeline** of which fact held when, and which events happened in each
  cycle;
- the **changes** made in any one cycle;
- the run drawn as an **automaton**, a diagram of states and the steps between
  them;
- a **2D** and a **3D** scene, drawn from the program's own drawing rules;
- a **live** panel, for programs that keep running and wait for events you send;
- a **play** panel, for interactive-fiction stories;
- an **assistant**: a language model that can write, run and explain programs,
  and animate a run in 2D or 3D.

[`docs/user/guide/ide.md`](docs/user/guide/ide.md) describes every part.

**Explanations.** Right-click a fact or an event to ask *why* it happened, or
*why not*. Every run records how the engine reached each conclusion: which rule
created which goal, which rule changed which fact, and which constraint blocked
which action. An explanation is read from that record. Nothing is re-run to
answer a question, and where the engine recorded nothing, the answer says so.

**Planning in the same language.** A program can state a goal with `achieve`
and leave the engine to find the actions:

```prolog
:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).
```

The planner obeys the same constraints (the `false` lines) as the rest of the
engine. The plan is then carried out by the ordinary cycle, so a planned run can
be explained and tested like any other.

**Language models as agents.** Through the Model Context Protocol, a standard
way for language models to use tools, a language model can open a program as a
*world* and ask whether an action is allowed **before** taking it. The answer
comes from the program's constraints, and names the constraint and the line it
is written on. [`docs/user/api/mcp.md`](docs/user/api/mcp.md) is the reference.

**A browser-only version.** The whole editor can also run with no server, the
engine compiled to WebAssembly (a way of running compiled programs inside a web
page) in the visitor's own browser tab.

## Running it yourself

You need [SWI-Prolog](https://www.swi-prolog.org/) (developed against 10.1.12).
Building the editor needs Node.

```sh
cd ui && npm install && npm run build   # build the editor, once
cd .. && ./lps ide                      # the editor, at http://localhost:3060/
```

To run Logical English programs, point LPS2 at a copy of LogicalEnglish2:
`LPS_LE2_LIB=/path/to/LogicalEnglish2 ./lps ide`. Without it, only `.le` files
stop working.

Everything the editor does can also be done from the command line:

```sh
./lps run PROGRAM [--cycles N] [--trace FILE] [--observe "e1,e2@3"] [--json]
./lps step PROGRAM --cycles 3          # one report per cycle
./lps repl PROGRAM                     # step, inspect, copy, discard
./lps explain PROGRAM --ask "why_not(happened(a), 4)"
./lps timeline PROGRAM
./lps changes PROGRAM --at 2
./lps automaton PROGRAM                # the run as a diagram of states
./lps live PROGRAM                     # a session that does not stop
./lps dump PROGRAM                     # the internal form
./lps solidity PROGRAM                 # the program as a Solidity contract, or why not
./lps pddl DOMAIN PROBLEM              # plan a PDDL problem
./lps drools FILE.drl                  # run a Drools rule file
./lps play STORY.le                    # play an interactive-fiction story (needs LE2)
./lps inform STORY.ni [--out DIR]      # an Inform 7 source, as a Logical English story
./lps mcp                              # the Model Context Protocol server, on stdin/stdout
./lps test --engine lps2 --only goat   # the test harness
```

The kind of a file is taken from its extension. An explanation from the command
line looks like this:

```
$ ./lps explain legacy_lps1/examples/goat.pl --ask "why(happened(row(south,north)), 2)"
[happened]
row(south,north) occurred from cycle 1 to 2 — committed while resolving goals in the previous cycle
  while resolving the composite event makeLoc(farmer,south) — from 1 to 1
  while resolving the composite event makeLoc(goat,north) — from 1 to 2
  ...
```

### From Prolog, or over the web

The command line is a thin layer over seven Prolog predicates:

```prolog
lps_compile(+Source, +Syntax, +Options, -Program, -Diagnostics)
lps_session_new(+Program, +Options, -Session)
lps_session_observe(+Session0, +Events, -Session)
lps_session_step(+Session0, -Session, -CycleReport)
lps_session_run(+Session0, +StopCond, -Session, -Trace)
lps_session_state(+Session, -Fluents)
lps_session_fork(+Session, -Session2)
```

A session is a single Prolog value, so copying one to try something out
(`lps_session_fork/2`) costs almost nothing. The web interface is a single
`POST` whose `operation` field says what to do. The editor is a client of that
interface, so anything the editor does can be done with `curl`.

### Deploying

```sh
docker build -t lps2 . && docker run -p 3060:3060 lps2      # one container, one port
./wasm/build.sh && node wasm/runtime/serve.mjs wasm/dist 8080  # the browser-only version
```

[`docs/dev/deploy.md`](docs/dev/deploy.md) covers the container, fly.io, and
why a public server must set `LPS_TOKEN`.
[`docs/dev/deploy-vercel.md`](docs/dev/deploy-vercel.md) covers the
browser-only version, and what it cannot do: no assistant, no live sessions, no
Model Context Protocol endpoint.

### Running the checks

```sh
./myswipl.sh -q -g "consult('tools/lint_core.pl')"     -g "lint_core:main" -t halt
./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')"  -g "m2:main"        -t halt
./myswipl.sh -q -g "consult('tools/explain_test.pl')"  -g "xt:main"        -t halt
./myswipl.sh -q -g "consult('tools/examples_test.pl')" -g "ex:main"        -t halt

# LPS1's 108 recorded runs, replayed (about 40 minutes); --engine takes legacy, lps2 or cross
./myswipl.sh -q -g "consult('conformance/runner.pl')" \
  -g "runner:main(['--engine','lps2','--variants',none,'--extended'])" -t halt
```

The browser tests and the screenshots in the documents also need Playwright
with Chromium. [`CLAUDE.md`](CLAUDE.md) holds the working notes for developers:
the rules that must not be broken, how to run things, and where the output
lands.

## How the source is arranged

```
src/core/      the engine: no input or output, no threads, no clock
src/syntax/    the written forms in (LPS, PDDL, Drools, Inform 7) and out (Solidity)
src/edges/     everything that touches the world: files, command line, web, LE, language models, WebAssembly
ui/            the editor's sources, built into src/ide/dist/
examples/      the examples, by purpose (examples/README.md)
conformance/   the harness that replays LPS1's recorded runs
tools/         checks, benchmarks, browser tests, screenshot generation
wasm/          the browser-only build
docs/          the documents (docs/README.md)
legacy_lps1/   a read-only copy of LPS1, the reference for the conformance checks
```

The Logical English front end lives in the LogicalEnglish2 repository. The
agreement between the two systems is
[`docs/dev/le-lps-interface.md`](docs/dev/le-lps-interface.md).

## The documents

[`docs/README.md`](docs/README.md) is the index. The documents for users are
also in the editor's **Help** menu.

| | |
|---|---|
| [`overview/abstract.md`](docs/user/overview/abstract.md) | **two pages** and one picture, for deciding whether to read the rest |
| [`overview/introducing-lps2.md`](docs/user/overview/introducing-lps2.md) | **the longer tour**: what LPS2 is, and every way in, illustrated from the running system |
| [`tutorials/lps-tutorial.md`](docs/user/tutorials/lps-tutorial.md) | **how to write LPS programs**, from a two-line one to sessions that do not stop |
| [`tutorials/how-lps-runs.md`](docs/user/tutorials/how-lps-runs.md) | **how a program runs**, cycle by cycle |
| [`tutorials/inform-users.md`](docs/user/tutorials/inform-users.md) | **for Inform authors**: what maps onto what, with worked stories |
| [`guide/ide.md`](docs/user/guide/ide.md) | **the editor**: every part, and a "how do I…" section |
| [`reference/lps.md`](docs/user/reference/lps.md) | **the language reference**: every construct |
| [`reference/le-for-lps.md`](docs/user/reference/le-for-lps.md) | Logical English for LPS, construct by construct |
| [`reference/glossary.md`](docs/user/reference/glossary.md) | **every term** used in these documents, defined |
| [`api/mcp.md`](docs/user/api/mcp.md) | the Model Context Protocol server |
| [`integrations/`](docs/user/integrations/index.md) | PDDL, Drools, Inform 7, Solidity, Daml and L4 |

What is built, what is known to be missing, and what might come next are
recorded in one place: the Status section of
[the plan of record](docs/project/plan-of-record.md#status).

## Licensing

LPS2 is copyright 2026 Miguel Calejo, and licensed under the
[Apache License, Version 2.0](LICENSE). The [NOTICE](NOTICE) file lists the
parts written by others, which keep their own copyright and licence: the LPS1
copy, the icons, SWI-Prolog for the browser, and the programs of other systems
among the examples.

`legacy_lps1/` is a read-only copy of the LPS1 repository, copyright Imperial
College London, under the 3-clause BSD licence. **Never write inside it.**
Running the old engine on a file writes new files next to that file, so both
engine adapters copy programs into `build/` before running them.
