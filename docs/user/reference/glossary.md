# Glossary

*Kind: reference · Audience: users · Status: current (2026-09-16)*

Every term used in the LPS2 documents that is not ordinary English, in one
place. Terms are grouped by what they are about rather than alphabetically,
because the groups explain each other; there is an alphabetical index at the
end.

---

## The language

**LPS** — Logic Production System, the language of Kowalski and Sadri. A program
says what holds when, what happens between when and when, and what must and must
not be the case.

**LPS1** — in these documents, the earlier implementation of LPS, written from
2015 onwards and kept here in `legacy_lps1/`. **LPS2** is this implementation.

**Fluent** — a fact that holds over an interval of time, and can start and stop
holding. Written `light(on)`, and asked about with `light(on) at T`.

**Extensional fluent** — a fluent that is stored: it holds because something
started it and nothing has stopped it since.

**Intensional fluent** — a fluent that is calculated from the state each time it
is asked about, rather than stored. An intensional fluent is never started or
stopped.

**External fluent** — a fluent answered by calling an ordinary Prolog predicate
rather than by consulting the state.

**Event** — something that happens between one instant and another, and that
arrives from outside the program.

**Action** — something that happens between one instant and another, and that
the program itself chooses to do.

**Composite event** — an event defined as a sequence of other events, so that
one name stands for several happenings. The language's equivalent of a
subroutine, a named piece of a program that the rest of the program can use by
name.

**Causal law** — a sentence saying which fluents an event starts and which it
stops. Written with `initiates`, `terminates` or `updates`.

**Reactive rule** — a sentence of the form *if this holds and this happens, then
bring that about*. The rule's conclusion is a standing goal, not a one-shot
trigger: the engine keeps trying to satisfy the goal until the goal succeeds or
becomes impossible.

**Integrity constraint**, **denial**, **`false` sentence** — three names for the
same thing: a sentence saying that some combination of circumstances must never
arise. If the sentence mentions an action, the sentence forbids that action, and
is then also called a **precondition**.

**Timeless clause** — an ordinary Prolog clause in an LPS program, with no
reading in time. A timeless clause says what something *means* rather than what
happens.

**Observation** — an event supplied to the program from outside, either scripted
in the program with `observe`, or sent to a running session over the network.

**Scenario** — the observations a program scripts for itself: the events, with
their times, that a run is given. In Logical English, `scenario one is:`
followed by timed events; in the written form, `observe` facts.

**Refused** — said of an observed event, or a *call*, that a precondition
stopped. The precondition's conditions held in the state the event arrived in,
so the event did not happen, and neither did the other events observed for that
cycle. The engine records the refusal: `why_not` answers
`refused_by_constraint`, and the timeline shows the event crossed out. In a
program that models a contract, a refused call is a call that reverts. The word
is also used, in its ordinary sense, of a translation that is not made — a
Logical English document with no LPS reading, a program with no Solidity
translation — and of an event dropped because its channel may not carry it.

**Default** — the value a fluent holds for a key with nothing stored, declared
with `defaults([balance(_, 0)])`, or `; 0 by default` in Logical English. The
default is never stored; it is an LPS2 declaration that LPS1 does not have.

**State** — the set of fluents that hold at one instant.

**Cycle** — one turn of the engine's loop: take in events, apply their effects,
fire the rules whose conditions now hold, reduce the resulting goals to actions,
reject the actions a constraint forbids, commit the rest.

**Instant**, **time** — a cycle number. Time in LPS is 1, 2, 3, and so on.

**Trace** — the record of a run: which fluents held in which cycles, which events
occurred, which composite events were recognised.

---

## Ways of writing an LPS program

**Written form** (elsewhere sometimes called the *external syntax* or the
*surface syntax*) — what you type into a `.lps` or `.pl` file. Such a file is a
Prolog file, read with the LPS operators in scope.

**Internal form** (elsewhere the *internal syntax*) — what the written form is
translated into before the engine runs the program. The internal form is a set
of Prolog facts: `reactive_rule/2`, `initiated/3`, `l_events/2`, `l_int/2`,
`l_timeless/2` and so on. Files holding the internal form end in `_.P` or
`.lpsw`.

**Translator** — the program that turns the written form into the internal form.
LPS1's is called `psyntax`; LPS2's lives in `src/syntax/`.

**Logical English** — a controlled English notation, which is to say English
restricted to a fixed set of sentence patterns, developed in a separate project,
and translatable into the same internal form. Files end in `.le`. **LE2** is the
implementation of Logical English that LPS2 talks to.

**PDDL** — the Planning Domain Definition Language, used by the international
planning competitions. LPS2 can translate PDDL and run it.

**Drools** — a business-rules language. LPS2 can translate a useful part of it.

**Door** — a way in for a program written in another notation, such as a PDDL
domain and problem or a Drools rule file. LPS2 translates such a program into
the internal form when the program is opened, and the program then runs, and is
explained, like any other.
`examples/planning/` holds the PDDL examples and `examples/migration/drools/drl/` the Drools ones.

**Companion file** — the `.lps` file of the same name beside a `.le` document
(`badlight.le` and `badlight.lps`). The two are one program and are translated
together, the `.le` document first. The companion holds what is not English:
`display/2` clauses and Prolog helpers.

**LE2 ↔ LPS2 interface** — the written agreement between the two projects on
what crosses between them: internal-form text plus a list saying which sentence
each term came from. The agreement carries a version number; version 3 added
`defaults/1`. The agreement lives in
[`docs/dev/le-lps-interface.md`](../../dev/le-lps-interface.md).

**Twin**, or **migration twin** — a program of another system (a Solidity
contract, a Daml template, a set of Drools rules) rewritten as a Logical English
for LPS program by one of the translators of lpsPlus, so that it runs, and can
be explained, here. The twins are in `examples/migration/`, one directory per
source system, each with the originals it was translated from in `sources/`.

**Legal view** — a timeless Logical English program computed from a Logical
English for LPS document and from its run: one rule per action saying who may
perform that action, and when, and one rule per causal law saying what that law
changes, with a scenario for the state before each call of the document's
scenario. LE2's editor answers the view's questions, not this engine.
*View ▸ Legal view* in the editor.

**Interactive fiction** — a text adventure: a world that takes a typed command
each turn. On LPS, a work of interactive fiction is a Logical English program
that includes the library in `examples/if/`.

**Story** — a Logical English document that includes the interactive-fiction
library (`includes these resources: world`). A story can be played.

---

## Checking that LPS2 behaves like LPS1

**Recorded run**, elsewhere called a **golden** or a **golden trace** — a file
recording what LPS1 did on one program, cycle by cycle. There are 108 such
files, and their names end in `.lpst`.

**Reproduces exactly** — LPS2 produces the same fluents, events and composite
events, in the same cycles, described by the same terms, differing at most in
the names of variables. Order within a cycle does not matter; everything else
does.

**Trace equivalence** — the property just described. Trace equivalence is weaker
than proving that the two engines mean the same thing, and much stronger than
checking that the examples still give sensible answers.

**Out-of-date recording**, elsewhere called a **stale golden** — a recorded run
made before LPS1's own behaviour last changed, so that LPS1 no longer reproduces
the recording either. Nine of the 108 are in that state, and
`conformance/adjudicated.pl` documents each one individually.

**Running the engines side by side** (`--engine cross`) — running LPS1 and LPS2
on the same program and comparing the two with each other instead of with the
recording. Comparing the engines directly is the only comparison that means
anything once a recording is older than the behaviour it recorded.

**Perturbation** — a deliberate change to something that ought not to matter:
reversing the order of the clauses, reversing the initial state, or inverting
the order in which the engine takes goals off its queue. Every test is run under
each perturbation. If a program's answer depended on an accident, one of the
perturbations would find it.

**The harness** — the program in `conformance/` that runs all this.

---

## How this implementation is organised

**`src/core/`** — the engine. Nothing in the engine may use threads (several
things running at once), network connections, the clock, files, randomness, or
code written in C. `tools/lint_core.pl` checks that nothing does.

**`src/syntax/`** — translation between the written forms and the internal form.

**`src/edges/`** — everything that touches the outside world: files, the command
line, HTTP, language models, continuously running sessions.

**Session** — one run of one program, held as an ordinary Prolog term that is
never modified. Because nothing ever modifies a session, copying one is a single
step and costs the same whatever the session's size, which is what makes it
cheap to ask "what would have happened if".

**Milestone**, written **M0** to **M19** — a numbered unit of work in the
development plan, `docs/project/plan-of-record.md`. The numbers appear in comments in the
source and in the plan; they are a filing system and nothing more.

**§I.3**, **§II.4**, and similar — a section of that same plan. Roman numeral,
then section number.

---

## Running and drawing

**Continuously running session**, elsewhere called a **perpetual session** or a
**live session** — a run that does not stop at `maxTime`, cycles in real time,
and accepts events while it runs. Started with `./lps live` or from the editor's
*Live* panel.

**Channel** — a name under which events arrive at a continuously running
session, together with the list of event predicates that channel may carry. The
session drops an event that is not on its channel's list, and reports the drop.

**Fork** — a copy of a session, run forward independently of the original.
Because a session is never modified, a fork costs the same whatever the
session's size.

**Play** — running a story as a game: `./lps play`, or the editor's *Play*
panel. The engine matches what you type against the story's command templates;
*why* asks the engine why the last turn went as it did; you can fork a game, and
*diff* says what happened in one game and not in the other.

**`display/2`** — the declaration by which a program says how its fluents and
events should be drawn. `display3d/2` is the same idea in three dimensions.

**Timeline** — the diagram showing which fluents held in which cycles and which
events occurred, as horizontal bars and dots.

**State-transition diagram**, shown in the editor as **Automaton** — the diagram
of the states a program passed through and the events that took the program from
one state to the next. LPS1 produced the same picture with `godfa/1`.

**Explanation** — the answer to *why did this happen* or *why did this not
happen*, derived from the record the engine keeps of how it reached each
conclusion.

---

## Software terms used in these documents

**Monaco** — the piece of software that provides the text editor in the browser;
Visual Studio Code uses the same one.

**Konva** — the software library that draws the two-dimensional animation.

**three.js** — the software library that draws the three-dimensional animation.

**esbuild** — the tool that gathers the editor's source files into the few files
the server sends to the browser.

**WebAssembly**, abbreviated **WASM** — a form in which a program can be
packaged so that it runs inside a browser. LPS2's engine is compiled into
WebAssembly, so a program can be run with no server at all.

**Deploy as WASM** — the editor's *Misc ▸ Deploy as WASM*: one self-contained
HTML page (HTML being the language of web pages), the **WASM bundle** or
**standalone page**, carrying the program and the engine's sources, which runs
the program in a browser and prints its trace with no LPS2 server. The page
fetches SWI-Prolog's WebAssembly runtime — the software that runs Prolog inside
a browser — from wherever the page itself is served. The page holds only the
engine and the translator of the written form: no live sessions, no assistant,
no Logical English.

**Deploy as Solidity** — the editor's *Misc ▸ Deploy as Solidity*, and
`./lps solidity`: the program written as a Solidity smart contract, with fluents
as state, actions as functions and preconditions as reverts, and opened in
**Remix IDE**, the Ethereum Foundation's IDE (integrated development
environment: an editor and its tools together) that runs in a browser, so that
the contract can be put on a test chain. A program with no straight translation
(a reactive rule, planning, its own Prolog…) is refused, with the reasons,
rather than approximated.

**Export to another system** — the editor's *Misc ▸ Export to another system*:
a Logical English document written in another system's format by one of the
exporters of the Logical English installation.

**Sandbox** — the check a server applies to the Prolog in a program sent to it,
refusing anything in that Prolog which could reach the machine. On by default on
the server, off on the command line.

**Container image** — a packaged copy of the whole system, including SWI-Prolog,
that can be run on another machine without installing anything.

**Endpoint** — a single web address that accepts requests. LPS2 has one,
`POST /lpsapi`; every operation is a field in the request rather than a separate
address.

**Assistant** — the editor's panel in which a language model answers questions
about the program, and changes the program, using the editor's own operations as
its tools.

**Language model**, sometimes **LLM** — a system such as Claude or GPT that
produces text in response to text. In LPS2 one is used only where a mistake is
recoverable: answering questions about a program, translating an English
sentence into an event term, and proposing how a program should be drawn.

**Token** — the unit in which a language model measures text, roughly
three-quarters of a word. A model's **context window** is how many tokens it can
be given at once.

---

## Alphabetical index

Action · Assistant · Automaton · Causal law · Channel · Companion file ·
Composite event · Container image · Context window · Continuously running
session · Cycle · Default · Denial · Deploy as Solidity · Deploy as WASM ·
`display/2` · Door · Drools · Endpoint · esbuild · Event · Explanation · Export
to another system · Extensional fluent · External fluent · `false` sentence ·
Fluent · Fork · Golden · Harness · Instant · Integrity constraint · Intensional
fluent · Interactive fiction · Internal form · Konva · Language model · LE2 ·
LE2 ↔ LPS2 interface · Legal view · Live session · Logical English · LPS · LPS1
· LPS2 · Migration twin · Milestone · Monaco · Observation · PDDL · Perpetual
session · Perturbation · Play · Precondition · Reactive rule · Recorded run ·
Refused · Remix IDE · Sandbox · Scenario · Session · Stale golden · Standalone page · State ·
State-transition diagram · Story · three.js · Time · Timeless clause · Timeline
· Token · Trace · Trace equivalence · Translator · Twin · WASM · WASM bundle ·
WebAssembly · Written form
