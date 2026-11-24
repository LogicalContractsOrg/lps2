# Inform and LPS — an evaluation and a plan

*Kind: plan · Status: implemented (phases 0–4) → see docs/user/tutorials/inform-users.md*

**Written 2026-09-04; phases 0 to 4 done the same day** — see §7a to §7e for what
they found and what they changed. What exists is a shallow clone of the Inform
repository in `build/inform/inform/` (gitignored), the phase-0 spikes in
`examples/if/phase0/` with a check script, the phase-1 library and ten stories in
`examples/if/` with their gate `tools/if_test.pl`, and the phase-2 player —
`src/edges/lps_play.pl`, `./lps play`, five `/lpsapi` operations and the IDE's Play
panel — with its gate `tools/play_test.pl`. Everything marked **[verified]**
was checked against the clone, against LE2, or by running the engine; everything marked
**[assessment]** is a judgement and should be re-checked at the moment work starts. Web
sources are listed in §9.

This document follows the house rule: it is the reasoning. If the plan is adopted, its
milestones go into `docs/project/plan-of-record.md` and its status lives there and nowhere else.

---

## Contents

- [0. The recommendation, in one page](#0-the-recommendation-in-one-page)
- [1. What Inform is](#1-what-inform-is)
  - [1.1 The project](#11-the-project-verified)
  - [1.2 The pipeline, and why Inter is not a target](#12-the-pipeline-and-why-inter-is-not-a-target-verified)
  - [1.3 The language, in the terms that matter here](#13-the-language-in-the-terms-that-matter-here-verified)
  - [1.4 The corpus — an oracle exists](#14-the-corpus-an-oracle-exists-verified)
  - [1.5 The neighbours](#15-the-neighbours-assessment-from-the-web)
- [2. LPS, re-read for this purpose](#2-lps-re-read-for-this-purpose)
- [3. The spike](#3-the-spike-verified)
- [4. What each side has that the other lacks](#4-what-each-side-has-that-the-other-lacks)
- [5. Integration scenarios](#5-integration-scenarios)
  - [5.1 Inform → LPS: a front end in the Part IV sense](#51-inform-lps-a-front-end-in-the-part-iv-sense)
  - [5.2 Inform ← LPS: compile LPS to Inform 7 (the TextWorld route)](#52-inform-lps-compile-lps-to-inform-7-the-textworld-route)
  - [5.3 LPS as the engine, Logical English as the language — recommended](#53-lps-as-the-engine-logical-english-as-the-language-recommended)
  - [5.4 The one semantic mismatch worth naming now — settled by phase 0](#54-the-one-semantic-mismatch-worth-naming-now-settled-by-phase-0-verified)
- [6. The Logical English question, checked](#6-the-logical-english-question-checked)
  - [6.1 Timestamps — already hidden](#61-timestamps-already-hidden-verified)
  - [6.2 Existentials — real, deferred](#62-existentials-real-deferred-verified)
  - [6.3 Text — the extension he did not name](#63-text-the-extension-he-did-not-name-assessment)
- [7. The plan — "M20: interactive fiction", four phases and one optional one](#7-the-plan-m20-interactive-fiction-four-phases-and-one-optional-one)
  - [Phase 0 — three spikes — done 2026-09-04](#phase-0-three-spikes-done-2026-09-04)
  - [Phase 1 — the library: `examples/if/world.le` — done 2026-09-04](#phase-1-the-library-examplesifworldle-done-2026-09-04)
  - [Phase 2 — the player: a channel, a parser, a transcript — done 2026-09-04](#phase-2-the-player-a-channel-a-parser-a-transcript-done-2026-09-04)
  - [Phase 3 — the story: `examples/if/alice.le` — done 2026-09-04](#phase-3-the-story-examplesifalicele-done-2026-09-04)
  - [Phase 4 — an Inform *assertion* front end — done 2026-09-04](#phase-4-an-inform-assertion-front-end-done-2026-09-04)
  - [Phase 5 (optional) — export](#phase-5-optional-export)
  - [What is deliberately not in the plan](#what-is-deliberately-not-in-the-plan)
- [7a. What phase 0 found](#7a-what-phase-0-found-verified)
- [7b. What phase 1 found](#7b-what-phase-1-found-verified)
- [7c. What phase 2 found](#7c-what-phase-2-found-verified)
- [7d. What phase 3 found](#7d-what-phase-3-found-verified)
- [7e. What phase 4 found](#7e-what-phase-4-found-verified)
- [8. Risks](#8-risks)
- [9. Sources](#9-sources)

## 0. The recommendation, in one page

**Do not compile Inform to LPS, and do not compile LPS to Inform. Build interactive
fiction on LPS directly, in Logical English, and treat Inform as three things: a
vocabulary to borrow, a design to learn from, and a corpus to test against.**

The reasons, each argued below:

1. **The creator's instinct is right and already runs.** A live LPS session (M18) is an
   IF turn loop: the player's typed command is an event on a channel, the causal theory
   is the world, the reactive rules are the characters. A one-hour hand translation of an
   Inform scene test produces the same story as Inform's own ideal transcript (§3).
2. **Inform's language is mostly the wrong register to translate.** Its world-model
   *assertions* are declarative and map well; its *rules* are imperative phrases
   (`say`, `now`, `let`, `repeat through`), and its rule *selection* is a four-law
   specificity order that Plotkin describes as something "nobody understands". A
   translator would inherit Part IV's procedural-leaf caveat in its severest form, and
   its correctness criterion would be the wording of printed text (§5).
3. **The other direction loses everything LPS is for.** Compiling LPS to Inform 7 would
   throw away time intervals, standing goals, constraints, `why`, the timeline, forking,
   and live sessions, and re-implement the cycle in Inform phrases. Microsoft's TextWorld
   did the generator half of this and its worlds are, in Emily Short's words,
   "depressingly basic" (§5).
4. **What LPS adds is exactly what IF authors have been asking for.** Plotkin wanted a
   world "made of hooks" with rules and no precedence schema; Martens argued a game is
   "interactive proof search"; Evans and Short built Versu because Inform could not
   model characters with goals; Dialog proved authors will write a Prolog-family IF
   language. None of them has a causal theory with a frame axiom, explicit time,
   integrity constraints, hypothetical worlds *and* an English surface. LPS has all five
   (§4).
5. **There is an oracle.** The Inform repository ships about 700 scripted programs each
   with an ideal transcript. They cannot check a *translator* cheaply, but they are a
   fine source of behavioural tests for an LPS IF library written by hand (§2.4).

The plan (§7) is four phases: a library, a player, a story, and only then an Inform
*assertion* front end for importing existing worlds. **All four are built** (§7a–§7e);
what remains is the optional export of phase 5, argued against in §5.2. The Logical
English extensions the creator anticipates are examined in §6: the timestamp one is
already done, the existential one turned out not to be needed by any story with a named
cast (§7d), and there is a third he did not name (text) that mattered more.

---

## 1. What Inform is

### 1.1 The project **[verified]**

`https://github.com/ganelson/inform` — Graham Nelson's Inform 7, open-sourced in April
2022 under the Artistic License 2.0. The last formal release is **10.1.2 (August
2022)**; `master` is "10.2.0-beta" and has been for over a year, with the most recent
commit on 2026-06-24. It is alive but slow-moving, and larger changes go through a
separate proposal repository, `inform-evolution`.

The toolchain is five programs — `inbuild` (build manager and stage 1), `inform7`
(stages 2–5, the compiler proper), `inter` (stages 6–7, the intermediate
representation and code generation), `inform6` (the classic compiler, used as a
back end) and `inblorb` (packaging) — all written as literate-programming webs in
Nelson's `inweb`, tangled to C. **There is no library API and no WebAssembly build of
the compiler**: `inform7` is a batch executable, and the browser IDE Borogove compiles
on a server. Building it needs a C toolchain, which this container does not have; the
user's machine does.

### 1.2 The pipeline, and why Inter is not a target **[verified]**

Inform 7 source → (assertions become a world model of kinds, instances, properties and
relations; rules and phrases are type-checked) → **Inter**, a tree-shaped intermediate
representation → a pipeline of transformations, linking in precompiled *kits* → output
as Inform 6 source (then Z-machine or Glulx story files) or as ANSI C.

Inter is documented (a textual form, `.intert`, with a manual in `inter/Manual/`) and
versioned, but its own manual says its purpose "is to assist testing and debugging of
the Inform tool-chain". More to the point, by the time a program is Inter the
declarative content is gone: a rulebook is a function, `now the door is open` is a
property write, and the world model is arrays. Inter is post-semantic. **If any
translation from Inform is ever done, it is from the source text, not from Inter.**

### 1.3 The language, in the terms that matter here **[verified]**

Inform 7 source has two registers, and the distinction is the whole story of this
document:

**Assertions** — declarative, evaluated at compile time, building the *initial* world:

```
The Kitchen is a room. The oak door is a locked door.
It is east of the Hall and west of the Study.
A white rabbit is an animal in the Hall. The rabbit carries a pocket watch.
Loving relates various people to one person. The verb to love means the loving relation.
Alice loves the White Rabbit.
```

Internally the compiler turns each sentence into a predicate-calculus proposition
(the `calculus-module`: terms, unary predicates for kinds and adjectives, binary
predicates for relations, quantifiers) and compiles it three ways — as an assertion
(create the state), as a condition (`if the door is open`) or as a change (`now the
door is open`). That is the part of Inform that *is* logic programming, and it maps
onto `initially`, timeless clauses and fluents almost one to one.

**Rules** — imperative, run at play time, organised into about 340 *rulebooks*:

```
Instead of examining the apple during Looking At Things:
    say "Instead of examining the apple during Looking At Things.";
    continue the action.
Every turn when the location is the Orchard, say "The summer breeze shakes the apple-blossom."
At the time when the egg-timer clucks: say "Cluck! Cluck! Cluck!"
Starting ends roundly when the player carries the ball.
```

An action (`actor + action + noun + second noun`) runs through
`before → instead → check → carry out → after → report`. *Check* rules are
preconditions; *carry out* rules are effects; *report* rules print; *instead*,
*before* and *after* are the exceptions an author writes. Rule bodies are phrases:
`say` with text substitutions, `now`, `let`, `if`, `repeat through a table`, `try
another action`. Which rule of a rulebook wins is decided by the **Laws for Sorting
Rulebooks**: four laws with sub-laws comparing how many aspects a rule constrains,
whether it names a region or a room, the second noun before the first, and so on;
ties fall back to source order.

**Time** is a sequence of *turns* — one per command, though `GET ALL` fires several
actions in one turn. A clock advances one minute per turn; `every turn` rules run at the
end of each; future events are scheduled (`the egg-timer clucks in four turns from
now`). **Scenes** are intervals defined by state conditions (`begins when`, `ends
when`), deliberately with no way to force one to begin, so that "each action falls
entirely inside, or entirely outside, of any given scene". Past-tense conditions (`if
the player has been in the Kitchen`, `for the third time`) are implemented by counters,
not by a history — a documented limitation.

**The parser** is a separate kit (`CommandParserKit`) driven by `Understand` lines:
`Understand "photograph [someone]" as photographing.` It handles articles, plurals,
pronouns, disambiguation questions and `ALL`.

**Basic Inform** (`inform7 -basic`) is Inform without the world model and the parser:
kinds, phrases, rulebooks, tables and text, compilable to C for use inside game
engines. It is the *imperative* half of the language, which is the half we want least.

### 1.4 The corpus — an oracle exists **[verified]**

| where | what | count |
|---|---|---|
| `resources/Documentation/Examples/` | the worked examples of *Writing with Inform* and *The Recipe Book* | 486 programs, **467 with an ideal transcript**, 416 scripted with `Test me with "…"` |
| `inform7/Tests/Test Cases/` | the compiler's own behavioural tests | 568 programs with ideal transcripts, 274 scripted |
| `inform7/Tests/Test Basic/` | Basic Inform (no world model) | 272 files |
| `inform7/Tests/Test Problems/` | expected compile-time errors | ~2,000 files |

A scripted program plus its `--I.txt` transcript is a complete behavioural
specification: the source, the commands typed, the text printed. Beyond the repository
the I7-Examples organisation keeps full games compiling under version 10 (*Bronze*,
*Counterfeit Monkey*, *Blue Lacuna*), and the Recipe Book's chapters on characters —
*Reactive Characters*, *Goal-Seeking Characters*, *Characters Following a Script*,
*The Passage of Time*, *Scripted Scenes* — are the ones an LPS treatment should read
first, because they are the ones Inform handles least declaratively.

The manual itself is 26,000 lines of Markdown (`Writing with Inform.md`), which is a
fair measure of the language's surface area and the first argument against
translating all of it.

### 1.5 The neighbours **[assessment, from the web]**

**Dialog** (Linus Åkesson, 2018; community fork at version 1c) is the precedent that
matters: "a rule-based language in the logic programming family", named after Prolog,
in which the whole IF library — world model, parser, actions, scenes — is ordinary
library code, objects are thin atoms, all properties are relations, and state is four
shapes of dynamic predicate updated with `(now)`. *The Impossible Bottle* tied first
in IFComp 2020 and won three XYZZY awards; reviewers cited its robustness. Dialog is
the existence proof that authors will write IF in a Prolog-descended language. What it
is not: it has no fluents or events as such, no time beyond a tick counter, no frame
axiom (updates are destructive), no constraints, and rule selection is first-match in
source order.

**TextWorld** (Microsoft, 2018) writes its world as "a multiset of logical atoms" with
linear-logic transition rules — `open/c :: $at(P, r) & $at(c, r) & closed(c) ->
open(c)`, the `$` marking a premise that is not consumed — which is `initiates` and
`terminates` with a frame axiom in other clothes. It then *emits Inform 7 source* to
borrow Inform's parser and story-file format. **Ceptre** (Martens, 2015) is the same
linear-logic idea as a language, with an `act`/`react` stage pair and a quiescence
token that is, structurally, the LPS cycle. **Versu** (Evans and Short, 2012–14)
modelled characters with goals in an exclusion logic because Inform could not.
Nobody has used the event calculus or LPS for parser IF; the nearest is Martens and
Dabral's event-calculus narrative planner in clingo (2020), which is an authoring
tool rather than a runtime.

Alice in Wonderland has been adapted several times (Magnetic Scrolls' *Wonderland*,
1990; Gareth Rees's one-room Inform 6 *Through the Looking Glass*, 1995, with public
source) but **there is no Inform 7 or Dialog Alice**, so a showcase would not be
competing with an established implementation.

---

## 2. LPS, re-read for this purpose

Nothing in the engine needs to change for IF, and it is worth being precise about why.

- **The turn loop exists.** `src/edges/lps_live.pl` runs a program with no `maxTime`
  until stopped, takes events between cycles, and refuses an event whose predicate is
  not on its channel's allow-list. `examples/agents/llm/demo.mjs` already has an LLM turning
  an English sentence into an event term on a restricted channel (`live_translate`).
  A player is a channel that may carry `command/N` and nothing else.
- **The world is the causal theory.** `take(P, X) initiates carries(P, X)` and
  `take(P, X) terminates in(X, _)` are Inform's carry-out rules with the frame axiom
  supplied by the engine rather than by the author.
- **Characters are reactive rules.** `examples/collections/kowalski-book/fox_crow.lps` is already a story
  with two agents' goals in one program; `mars_explorer.lps` is condition–action rules
  over a world model; `louse.lps` resolves a rule conflict by a constraint where a
  production system used priority — which is exactly the question Inform's sorting laws
  answer procedurally.
- **Inform's "map of time" is the state-transitions diagram.** The scene index Nelson
  describes as showing "the map of time" is what `./lps automaton` draws; the timeline
  pane is the plot; `why(happened(…), T)` is a question no IF system can answer today.
- **Forking is a branching story.** `lps_session_fork/2` is a unification. "What if
  Alice had not drunk from the bottle" is a fork and a different observation, and the
  two timelines can be diffed. This is the one capability that has no analogue at all
  in Inform, Dialog or TextWorld.
- **The English surface exists.** `docs/user/reference/le-for-lps.md` gives events, actions,
  fluents, `when … then …` causal laws, `if … then …` reactive rules, `it must not be
  true that …` constraints, timeless templates and scenarios. Section 3.9's scenario
  block is precisely a `Test me with` script.
- **What LE lacks for this** is in §6.

---

## 3. The spike **[verified]**

Inform's test `C9SceneEndSequence` is twelve lines: a room, a cube and a ball, a scene
*Starting* that ends "roundly" when the player carries the ball and "squarely" when
they carry the cube, a scene *Ending* that begins when *Starting* ends and says which
way it ended. The script is `scenes / take ball`; the ideal transcript ends

```
>[2] take ball
Taken.

[Scene 'Starting' ends]
[Scene 'Starting' ends roundly]
[Scene 'Ending' begins]
Roundly.
```

In LPS, written by hand in a few minutes (`build/inform/spike/scene.lps`):

```prolog
fluents  in(_, _), carries(_, _), playing(_), ended(_, _), said(_).
events   command(_, _).                 % what the player typed
actions  take(_, _), say(_).            % what the world does about it

initially in(cube, home), in(ball, home), in(player, home), playing(starting).

%  Inform's check + carry out rulebooks for taking
if   command(take, X) from T1 to T2, in(X, R) at T2, in(player, R) at T2
then take(player, X) from T2 to T3.
take(P, X) initiates carries(P, X).
take(P, X) terminates in(X, _).
false take(P, X), carries(P, X).        % can't take what you already carry

%  scenes are fluents; "ends roundly when" is a reactive rule
if   playing(starting) at T, carries(player, ball) at T
then terminate playing(starting) from T to T2, initiate ended(starting, roundly) from T to T2.
if   playing(starting) at T, carries(player, cube) at T
then terminate playing(starting) from T to T2, initiate ended(starting, squarely) from T to T2.
if   ended(starting, How) at T, not playing(ending) at T
then initiate playing(ending) from T to T2, say(How) from T to T2.

observe command(take, ball) from 2 to 3.
```

`./lps run` gives:

```
events/3   [command(take,ball)]
events/4   [take(player,ball)]
events/5   [terminate(playing(starting)), initiate(ended(starting,roundly))]
events/6   [initiate(playing(ending)), say(roundly)]
fluents/6  [in(cube,home), in(player,home), carries(player,ball),
            ended(starting,roundly), playing(ending), said(roundly)]
```

Same story, same order, and `say(roundly)` is the transcript. Three things are learned:

1. **The mapping is direct and the program is shorter than the Inform.** Check rules are
   constraints, carry-out rules are causal laws, scene conditions are reactive rules,
   scenes are fluents. Nothing had to be invented.
2. **An Inform turn is several LPS cycles.** Inform does all of the above inside one
   turn; LPS took cycles 3 to 6. This is the one design decision the plan has to make,
   and the answer is Ceptre's: **a turn is a run of cycles to quiescence** — the edge
   steps the session until a cycle produces no new actions and no state change, then
   prints what was said and waits for the next command. It is a driver policy in
   `lps_live.pl`, not an engine change, and it keeps the conformance corpus untouched.
   The alternative — packing Inform's rulebook chain into one cycle with composite
   events — is possible but fights the language. *Refined by phase 0 (§7a): two
   bursts per turn, with an `end_turn` event between them.*
3. **Printing is an action.** `say/1` is an ordinary action whose argument is text, and
   the transcript is the sequence of `say` actions. That is also how Dialog does it,
   and it means `why(happened(say(roundly)), 6)` explains a line of the story.

---

## 4. What each side has that the other lacks

| | Inform 7 | Dialog | LPS + LE |
|---|---|---|---|
| English surface | yes, the best there is; two registers | no (Prolog-like) | yes (LE), one register, template-driven |
| World model as relations | yes, compiled to predicate calculus | yes, thin atoms | yes, fluents and timeless clauses |
| State change | `now …`, destructive | `(now) …`, destructive | causal laws with a frame axiom |
| Time | turns, a clock, scheduled events, counters for the past | ticks | explicit intervals, full history, `at T` in the past |
| Rule selection | four sorting laws, specificity | first match in source order | every rule fires; conflicts by constraints |
| Preconditions | check rules | `(prevent …)` | `false …` clauses, and *prospective* ones |
| Characters with goals | every-turn rules, hand-written | tick hooks | reactive rules as standing goals; composite events as plans |
| Explanation | none | none | `why`, `why_not`, the derivation forest |
| Branching / what-if | UNDO only | UNDO only | `lps_session_fork/2`, trace diff |
| Parser | mature, `Understand` grammar, disambiguation | mature, in the library | **missing** — an LLM on a channel, or to be written |
| Text output | `say` with substitutions, adaptive prose | text in rule bodies | **missing** — `say/1` over Prolog-formatted text |
| Standard library | 120 actions, 340 rulebooks, 8,000 lines | one file, readable | **missing** |
| Distribution | Z-machine/Glulx, every interpreter, Parchment in a browser | Z-machine, Å-machine | the IDE, `./lps live`, WASM (M11) |
| Corpus and community | 700 scripted examples, thirty years of games | 35 games | twelve rkbook programs |

The bottom three rows of the LPS column are the work. The top rows are the argument
for doing it.

---

## 5. Integration scenarios

### 5.1 Inform → LPS: a front end in the Part IV sense

*What it would be.* `src/syntax/lps_inform.pl`, reading Inform 7 source and emitting
internal syntax with provenance, like `lps_pddl.pl` and `lps_drools.pl`.

*Fit.* Split by register:

| Inform | LPS | fit |
|---|---|---|
| assertions: rooms, things, kinds, properties, map, relations, initial placement | `initially`, timeless clauses, declarations | **good** — the calculus module already makes these propositions |
| `check` rules | `false` preconditions | good, when the body is a condition and a refusal |
| `carry out` rules | causal laws | good, when the body is `now …` |
| `instead`, `before`, `after` | reactive rules and constraints | moderate — the *override* semantics has no LPS analogue (see §5.4) |
| `every turn`, `at the time when` | reactive rules with times | good |
| scenes | fluents plus reactive rules | good (§3) |
| `Understand` lines | a grammar table for the parser | good, if we have a parser to feed |
| `say` with substitutions, `report` rules | `say/1` with a Prolog leaf | **procedural leaf** — Part IV §IV.1 |
| phrases (`To …:`), `let`, loops, tables, `decide` | Prolog | procedural leaf |
| rule sorting laws | nothing | must be reported as a diagnostic, not approximated |

*Oracle.* The transcripts in §1.4 — but they compare printed text, and text is the
procedural half. A translator could be judged on the *state* sequence only by adding
`showme`-style commands, which the corpus does not carry. So the oracle is weaker than
PDDL's plan validator, and the translator would validate the declarative half against a
criterion written by us.

*Verdict.* **Not first, and never the whole language.** The assertion register alone is
a small, well-fitting front end — an "import an Inform world" feature that would put
hundreds of maps and object sets in front of the LPS library of §7. That is phase 4,
and it was built as exactly that (§7e): `src/syntax/lps_inform.pl` takes the assertion
register and reports the rule register sentence by sentence, and the oracle turned out
stronger than feared — for a program with no rules of its own, the generated story
reproduces the events the hand-written stories were checked against Inform's
transcripts with. The rule register is Part IV §IV.1's caveat at its strongest and is
not promised.

### 5.2 Inform ← LPS: compile LPS to Inform 7 (the TextWorld route)

*What it would be.* Emit Inform 7 source from an LPS program, then use Inform's parser,
its interpreters and its distribution channels.

*Why it is tempting.* The parser, the 120-action standard library and Parchment come
for free; the game file runs anywhere.

*Why it is wrong.* The LPS cycle, standing goals, backtracking over composite events,
time intervals and constraints would all have to be re-implemented in Inform phrases —
a second engine, with none of the conformance work behind it — and `why`, the
timeline, forking and live sessions do not survive the trip. TextWorld did this for
worlds with `at`, `in`, `open` and `locked`, and it worked because those worlds are
"depressingly basic". **Rejected as an architecture.** It survives only as a possible
*export* (phase 5, optional), and even then Dialog or Twine might be the better target.

### 5.3 LPS as the engine, Logical English as the language — recommended

*What it would be.* An IF library written in LE with an LPS companion, a player
channel, a turn driver, a transcript, and a story. Inform is borrowed from, not
translated: its world-model vocabulary (rooms, containers, supporters, doors, carrying,
wearing, the map directions), its action set reduced to the dozen that matter, its
scene design, and its corpus as a source of behavioural tests to hand-write against.

*Why this and not the others.* Every distinctive thing in §4's LPS column is kept, and
the three missing rows are additive edge work. The creator's Alice example — "if she
does not, then we need to invent an alternative path through the story" — is a fork,
and only this route has one.

*The cost.* A parser and a text layer. §7 sizes them.

### 5.4 The one semantic mismatch worth naming now — settled by phase 0 **[verified]**

Inform's `instead` rule *overrides*: the most specific rule that applies runs and the
action stops. LPS has no rule precedence; every reactive rule whose antecedent holds
fires. Two idioms were tried in phase 0 (§7a), and the second is the one to use:

- **The `instead` idiom** (`examples/if/phase0/lps/iqtest.lps`): the refusal is a
  `false` clause, the *message* is a reactive rule on the refusing condition, and the
  rule that performs the action carries the negation. It works and it reads well, but
  `why_not` cannot explain the refusal, because the action was never attempted.
- **The `try` idiom** (`iqtest_c.lps`): the command's goal is `try(A)`, a composite
  event whose first clause is the action and whose second is `refuse(A)`. The
  constraint blocks the first clause, the engine backtracks into the second, and
  `why_not(happened(A), T)` names the denial and the fluent that made it hold
  (`locked(case)`; `not reachable(player, donuts)`). **The refusal message is derived
  from the explanation**, not written by hand — Inform's check-rule messages come free.

The idiom is not optional. A player's command written as a plain reactive rule is an
*obligation*, and a refused obligation ends the run with `failure` at that cycle
(`iqtest_obligation.lps`, kept as evidence). Inform authors will find `try` natural: it
is Inform's own `try the person asked opening the shut chest`.

---

## 6. The Logical English question, checked

The creator anticipates two LE extensions. One is done, one is real, and there is a
third.

### 6.1 Timestamps — already hidden **[verified]**

`docs/user/reference/le-for-lps.md` §3.1: a temporal suffix (`at a time`, `from a first time to a
second time`) is optional on any sentence, and an unsuffixed literal inherits its time
from context. `le_lps_write.pl` puts it back only where it was. The logical point he
makes is right — a timestamp is an existential witness, like a skolem constant — and
the surface already treats it that way. **Nothing to do.**

### 6.2 Existentials — real, deferred **[verified]**

Running LE2 on

```
    a rabbit runs down a hole.
    an animal is white.
```

produces `single_variable_fact: Fact 'an animal is white' introduces a variable rather
than naming an individual, so it holds for everything`. An indefinite in a fact is
*universal* in LE, and LE2 warns exactly because authors mean the other thing. So "a
white rabbit appears" has no LE reading today.

Inform's answer is instructive: **assertions name things**. `A white rabbit is an
animal in the Hall` creates an object *called* "white rabbit"; anonymous things come
only from kinds (`Two rabbits are in the Hall`) and are referred to by their kind. For
the *initial* world, then, naming is what an author does anyway, and LE's `initially the
white rabbit is at the hall` needs no extension.

The gap is **run-time creation**: an event whose effect brings a new individual into
being (the White Rabbit *appears*; a caucus race produces prizes). That needs a
consequent that introduces a fresh constant, and a writer that prints the constant by
its type — `rabbit_1` shown as "a white rabbit", then "the white rabbit" once
salient. Two notes for whoever designs it:

- LE2's variable reader already distinguishes `a`/`an`/`some` as indefinite from `the`
  as definite (`le_grammar.pl`, `allow_var_name(indefinite, …)`), so the determiner
  machinery is there; what is missing is the *meaning* of an indefinite in a
  consequent or an `initially`. A determiner such as `a new …` in a `when … then …`
  consequent is the smallest proposal; the exact word is the LE owner's call.
- The engine side should be small **[assessment, not yet tried]**: a fresh constant
  minted in the causal law's condition list (a counter fluent, or a companion-file
  predicate — `src/core/` has no `gensym` and must not grow one that is not pure),
  and a question of what the constant is called and how the writer prints it.

**Deferred**: phase 3 did not need it after all (§7d) — the White Rabbit begins
offstage and runs on, as Inform's would — and every story so far names its cast.

### 6.3 Text — the extension he did not name **[assessment]**

The bigger gap is *output*. Inform's authors spend most of their lines on `say` and its
substitutions (`"[The noun] is [if the noun is open]open[otherwise]closed[end if]."`),
and Dialog's readability comes from text sitting inside rule bodies. LE has no
sentence form for "print this text with these values in it", and should not grow one
that tries to be Inform's: the companion-file rule (`le_lps_surface.md` §7) already
says Prolog leaves go in `foo.lps`. The proposal is therefore small: a `say` action
whose argument is text, written in LE as `then say "…"` for a literal, and *described*
in the companion for anything with substitutions — `describe(Room, Text) :- …` as
ordinary Prolog, called from a timeless template. The LLM assistant (M16) is the
obvious author of that Prolog, and an LLM is also a plausible *renderer*: hand it the
fluents that changed this turn and let it write the paragraph, with the logic never
depending on what it writes. That is Ian Bicking's *Intra* design and it is the safe
one, for the same reason `examples/agents/llm/` is safe: the model narrates, it does not
decide.

---

## 7. The plan — "M20: interactive fiction", four phases and one optional one

**Status (2026-09-04): phases 0 to 4 are done and committed** (`inform-phase0` to
`inform-phase4`); phase 5 is optional and unstarted. Each phase's entry below says what
was built and names its gate; §7a–§7e say what each found and what it changed. The
plan of record's status row is `docs/project/plan-of-record.md`, milestone M20.

Everything below is edge and library work. `src/core/` was not touched, the conformance
gate is not affected, and `tools/lint_core.pl` stayed green throughout.

### Phase 0 — three spikes — **done 2026-09-04**

Three Inform programs, hand-translated, each as LPS *and* as LE with a companion, each
checked against Inform's ideal transcript: `examples/if/phase0/`, gate
`examples/if/phase0/check.sh`, 8 of 8.

| Inform case | stresses |
|---|---|
| test case `C9SceneEndSequence` | scenes as fluents; a turn is several cycles |
| Recipe Book *IQ Test* (Goal-Seeking Characters) | a character's plan as a composite event; the `try` idiom |
| Recipe Book *MRE* (Future events) | story time as a fluent; the end of a turn as an event |

The turn-as-quiescence policy was **replaced by evidence**: see §7a. The `instead`
idiom was written down and then superseded by `try` (§5.4).

### Phase 1 — the library: `examples/if/world.le` — **done 2026-09-04**

Built as described below, with the adjustments of §7b. Ten stories play their
Inform scripts to the transcript's event sequence and final state:
`tools/if_test.pl`, 10 of 10. `examples/if/README.md` is the index.

The Standard Rules' *Physical World Model* section, reduced: kinds as timeless
templates (a room, a thing, a container, a supporter, a door, a person, the player);
containment, support, carrying, wearing, the map with the eight directions and a door
between rooms; light and openness; `can reach` as an intensional fluent (phase 0 has
the three-clause version). The dozen actions that make a game — look, examine,
inventory, take, drop, put in, put on, open, close, go, enter, exit — each as: a
`try` composite from a command event (§5.4), preconditions as `it must not be true
that …`, effects as `when … then …`. **No message rules**: a refusal is narrated from
`why_not`. Scenes as in §3. The turn structure of §7a: a `turn` fluent the command
advances, `end_turn` as the event `every turn` rules and timed events key on, and
scheduled events as `due` fluents naming a turn.

Vocabulary notes from phase 0: nested command terms have no LE form, so commands are
flat templates (`the command is to open *a thing*`, `*a person* is asked to get *a
thing*`); LE2 warns `redefined_system_template` for every `*a thing* is <adjective>`
fluent (`is closed`, `is locked`, `is hungry`, `is dead`) — a heuristic in
`le_verifier.pl` that matches on word shape, harmless but noisy, and worth raising
with the LE owner before a library with fifty such fluents is written; and a `.le`
beside a same-named `.lps` *is* its companion, so the library's LPS-only programs
must not share a basename with an LE one.

Gate: an LE program that *includes* the library (LE2's `include` mechanism, or
concatenation at the edge — to be decided in phase 0) and adds four rooms and six
things plays the Inform test scripts `Test me with "take all / open box / go north"`
to the same state sequence. About ten of the 274 scripted test cases, hand-selected,
as `tools/if_test.pl`, in the style of `tools/rkbook_test.pl`.

### Phase 2 — the player: a channel, a parser, a transcript — **done 2026-09-04**

Built as described below, with the adjustments of §7c: `src/edges/lps_play.pl`, the
CLI's `play`, the `play_*` operations of `/lpsapi`, and the Play panel of the IDE.
Gate `tools/play_test.pl`, 16 of 16, plus a Play pass in `tools/ide_check.cjs`.

The Play panel, as built (2026-09-04): **Commands** lists what would work from here
— the story's own commands, each tried against the denials on the current state in
place, orders to characters on a copy — and a click on one does it, or a checkbox
lists it after every turn; a line the parser does not understand goes to a model
that picks among those commands (`play_guess/3`, when a key is there); the panes follow
the game (the game's session is the IDE's after every turn, so the Timeline, Changes,
Automaton and the 2D and 3D panes show it and the slider scrubs it); and the
transcript keeps track of turns, each typed line wearing its turn and its cycles, so
the slider marks the turn its cycle fell in, a turn's line moves the slider to its
end, and a click on a thing in a scene pane marks the turn of that thing's last
state change as of the slider's cycle (`play_last_change` in `lps_play.pl`, one
operation of `/lpsapi`).

- **The channel.** `player` may carry `command/N` and nothing else. This is one line of
  configuration in `live_start`, and it is the safety property of `examples/agents/llm/`
  applied to a game: the player cannot inject `carries(player, key)`.
- **The turn driver.** A `turn` command in `lps_live.pl`, doing what the phase-0
  scripts did by hand (§7a): inject the command, step until a cycle produces no
  action, inject `end_turn`, step to quiescence again, return the actions of the whole
  burst. Bounded by a cycle cap so a runaway rule cannot hang the turn. This is
  Inform's own turn — action, every-turn rules, timed events, prompt — and Ceptre's
  `act`/`react` stages.
- **The narrator.** The transcript is the burst's actions rendered through the
  companion's narration table (`narrate/2`, as in `examples/if/phase0/le/iqtest.lps`),
  and a `refuse(A)` is rendered by asking `why_not(happened(A), T)` and phrasing the
  fluent the denial names. The narrator is an edge concern; the program never says
  anything but what happened.
- **Two parsers, one contract.** (a) A deterministic one for `verb noun [preposition
  noun]` built *from the program's own templates* — `le_service:le_templates/3` already
  exposes each template's surface and slot roles (M8f), so "take the lamp" can be
  matched against `*a person* takes *a thing*` with the player as the actor and the
  noun resolved against what is in scope. No key needed; this is what makes the thing a
  game rather than a demo. (b) `live_translate` (M16) as the fallback for anything the
  grammar does not take, prompted with the same templates. Both produce `command/N`
  terms on the same channel.
- **Surfaces.** `./lps play foo.le` as a REPL, and a *Play* pane in the IDE: a live
  session, a transcript and an input line, beside the 2D scene, the timeline and
  *why*. The right-click explanation already exists for every drawn term; a transcript
  line that explains itself is the demo.

Gate: the phase-1 world is playable end to end from the CLI with no LLM key, and from
the IDE; `why(happened(say(…)), T)` answers on a transcript line; the `player` channel
refuses a fluent.

### Phase 3 — the story: `examples/if/alice.le` — **done 2026-09-04**

Built as described below, with the adjustments of §7d: `examples/if/alice.le` with
its companion `alice.lps`, `alice_garden.le` for the other path, forking in the
player (`play_fork/2`, `play_diff/3`; `fork`, `switch`, `diff` on the terminal; a game
picker whose last item forks, and Diff, in the panel), and §20a of `docs/user/overview/introducing-lps2.md` with a
picture from the running system. Gates: both paths in `tools/if_test.pl` (12 of 12),
three Alice checks in `tools/play_test.pl` (13 of 13).

Chapters 1 and 2 of *Alice's Adventures in Wonderland* (public domain): the hall of
doors, the bottle labelled DRINK ME and the cake labelled EAT ME, size as a fluent that
the doors and the key test, the White Rabbit as an NPC with a goal (reach the garden,
consult the watch), the pool of tears as a consequence of size, a scene per chapter.

This is where §6.2 is needed (the rabbit *appears*) and where the showcase claims are
made good:

- **the same choices as the book** — a scenario reproduces Carroll's plot as a
  transcript;
- **different choices** — a fork at the bottle, and the two timelines side by side in
  the IDE, which no IF system can show;
- **why** — "why did Alice shrink" names the causal law and the drink;
- **the map of time** — the scenes as the state-transitions diagram.

Gate: `docs/user/overview/introducing-lps2.md` gains a section with screenshots from
`tools/doc_shots.cjs`; the two scenarios are behavioural tests in `tools/if_test.pl`.

### Phase 4 — an Inform *assertion* front end — **done 2026-09-04**

Built as described below, with the adjustments of §7e: `src/syntax/lps_inform.pl`,
`./lps inform STORY.ni [--out DIR]`, and `.ni` as a syntax `./lps run` and `./lps
play` take and the examples browser opens (`examples/if/inform/`, eleven of Inform's
programs with a licence notice). Gate `tools/inform_test.sh` (one program per process — see §7e): 11 of 11 programs translate,
run their `Test me with` script, hold the initial state read by hand from their
assertions, and — for the three with no rules of their own — reproduce the events the
hand-written stories were checked against Inform's transcripts with.

`src/syntax/lps_inform.pl` for the assertion register only (§5.1): rooms, kinds,
properties, map connections, relations and initial placement → `initially` and
timeless clauses against the phase-1 library's vocabulary. Every rule-register
sentence is reported as a diagnostic on its line, exactly as Drools' Java leaves are.
Oracle: the initial state of the corpus programs, checked by hand-written expectations
for a sample of twenty, per Part IV §IV.5's rule — *specify the oracle before writing
the transpiler*. Value: hundreds of ready-made worlds for the library; and an answer to
"can it read my Inform?" that is honest about which half.

### Phase 5 (optional) — export

Emit Dialog or Inform 7 from an LPS story for distribution as a story file. Only if a
real author asks; the argument against it in §5.2 stands.

### What is deliberately not in the plan

- Inform's parser, kits or Inter, in any form. There is no API to them and their
  contents are imperative. Phase 4 reads the source text, not Inter (§1.2).
- The full Inform 7 language as a front end (§5.1). Phase 4 takes the assertion
  register and *reports* the rule register; it does not approximate it.
- A new register in LE. Text goes in the companion. (A new file *extension* did
  arrive with phase 4 — `.ni`, an Inform source — but it names Inform's format, not
  a new form of Logical English.)
- Any change to `src/core/`. None was made.

---

## 7a. What phase 0 found **[verified]**

All three programs reproduce Inform's ideal transcript, event for event, in LPS and in
Logical English (`examples/if/phase0/check.sh`, 8 of 8, the LE half through LE2
in-process). None needed anything the languages do not have. Five things were learned,
and three of them changed the plan.

**1. A player's command is not an obligation** — the finding that matters most. A
reactive rule's consequent is a standing goal, and when the goal is impossible the run
*fails*: the IQ Test with `if command(open(X)) … then open(player, X)` ends in
`failure` at cycle 2, because the case is locked. Inform's refused action is the
ordinary case in IF, so every command must be a `try` (§5.4). This was not foreseen,
and it is the reason the plan says "no message rules": the `try`/`refuse` pair puts
the refusal into the trace, where `why_not` explains it.

**2. Refusal messages come from the explanation layer.** With `try`, `why_not` returns
`blocked_by_denial` with the constraint and the fluent that made it hold. Inform writes
those messages by hand, one per check rule; here the narrator phrases `locked(case)`
once and every refusal for that reason is covered.

**3. Story time is a fluent, and a turn has an end.** Inform's clock advances once per
turn, and a turn is a burst of cycles here (the IQ Test's third command is four
cycles), so `in three minutes from now` cannot be `T + 3`. `turn(N)` is a fluent the
command advances; a scheduled event is a fluent `due(What, N)`. And Inform's turn has
an order — action, every-turn rules, timed events — that the first MRE attempt got
wrong: keyed on the command, the every-turn rule read the state *before* the eat and
complained on the turn the player ate. An explicit `end_turn` event, injected by the
driver at quiescence, is what the every-turn rules and the timed events key on. With
it the complaints fall on turns 4, 11, 12 and 13 and the death on 13, as in the
transcript. **The turn-as-quiescence policy of §3 is therefore refined, not replaced**:
a turn is *two* quiescent bursts with `end_turn` between them.

**4. Goal-seeking characters are composite events.** Inform's two `Before someone …`
rules, which *try* implicit actions and `stop the action` if they failed, became one
composite event with two clauses (`get`: take, or open-then-take; `open_up`: open, or
unlock-then-open), and the engine found Ogg's three-step plan. This is the clearest
case of LPS being the better language for the thing, and the Recipe Book's *Goal-Seeking
Characters* chapter is the place to draw the next examples from.

**5. Logical English carried everything.** Composite events, intensional fluents,
constraints with negation, `initiate`/`terminate` in consequents, arithmetic on turns,
and the `try` idiom all have surface forms already. What was needed was flattening —
`command(ask(ogg, get(donuts)))` has no LE form, `ogg is asked to get donuts` does —
and the verifier's system-template warning is noise to be dealt with. No LE extension
was needed for phase 0, which confirms §6: the existential (§6.2) waits for Alice.

Two smaller things: explanations on a transcript line work today (`why(happened(say(…)),
T)` names the rule that said it); and the companion-file rule bit once — a `.le` next
to the LPS spike of the same name compiled both, doubling the state — which is why the
spikes live in `lps/` and `le/` subdirectories.

**Adjustments made to the plan**: §5.4 rewritten around `try`; phase 1 loses its
message rules and gains the turn structure and the vocabulary notes; phase 2's driver
injects `end_turn` and its narrator asks `why_not`. Phases 3–5 are unchanged.

---

## 7b. What phase 1 found **[verified]**

The library is 620 lines of Logical English: 30 events, 26 actions, 13 fluents, 12
timeless templates, and 125 rules — 17 intensional-fluent clauses (the map, the room
that holds a thing, accessibility, reach), 25 causal laws, 42 preconditions, 15 command
rules, and 26 composite-event clauses (the `try` pairs and the fetch plan). Ten stories
include it and play their Inform scripts to the transcript (`tools/if_test.pl`, 10 of
10). Six things were learned; four needed a change somewhere.

**1. Logical English wants one condition per line.** Every antecedent written as
`X and Y` on one line was read as a single sentence with the whole conjunction as one
argument. Phase 0 had followed the convention by accident. It is now stated in the
library's header and in `examples/if/README.md`, and it cost an afternoon to find,
because the symptom looked like the include mechanism failing.

**2. Includes work, and needed two fixes.** `the knowledge base S includes these
resources: world.` merges the library's declaration sections — events, actions,
fluents, templates — with the story's, and `known as` names carry over. But (a) LE2's
emitter located every diagnostic by slicing the *main* document's text at the
diagnostic's offset, and an offset from inside the included library is past the end of
a short story, so the slice failed and took the whole translation with it; a four-line
guard in LE2's `le_lps.pl` (`offset_line_col/4`) returns the contract's "unknown
position" instead. **That change is in the LE2 working tree, uncommitted, for its
owner** — LE2's own gate still passes 15 of 15. And (b) our edge handed LE2 only the
document's text, so a relative resource resolved against the working directory; the
in-process transport now passes the file's directory as `base` (`lps_le.pl`,
`le_lib_dict/3`), which LE2 already accepted. Provenance for included rules is still
by offset into the wrong file; a per-resource file name in LE2's source table is the
proper fix and is the LE owner's.

**3. A declared template with no facts must be false, not an error.** A story with no
doors never states `X leads D from R1 to R2`, and the engine raised an existence error
the first time the map rules asked. The in-process path now declares every timeless
template that has no clauses `:- dynamic` (which `lps_program` already honoured),
appended after the emitted text so provenance is untouched. Fourteen lines in
`lps_le.pl`; the transport-agreement gate (`tools/m8a_test.pl`) still passes.

**4. An action must not be named like a SWI-Prolog built-in.** The action for
"closes" was `close/2`, and the engine called the system predicate — a type error from
`close/2` in the middle of a story. The library says `known as shut`. This is a gap in
the engine's vocabulary shielding (`lps_program:make_dynamic/3` cannot redefine an ISO
built-in) and is recorded in `docs/project/plan-of-record.md` as such; the LE emitter could also
refuse a `known as` that names a system predicate.

**5. The burst length matters, and the script cannot know it.** The stories inject
`end_turn` two cycles after the command. Ogg's fetch through a locked case is three
steps, so in `iqtest` the case opens in the same cycle as `end_turn`; the transcript
is still right, but a real driver must wait for quiescence rather than count. That is
phase 2's driver, as planned.

**6. Inform's assertion shapes survive.** `kitchen is a room`, `case is openable`,
`north from temple goes to approach`, `oak_door leads east from hall to garden` all
parse as timeless facts, and a stated connection runs both ways by default as in
Inform. Two actions in one turn (`drop all`) are two commands in one cycle and two
concurrent drops. Locking a case from inside it works because reachability is
computed from the room that ultimately holds a thing, which is what Inform computes
too.

**Adjustments made to the plan**: phase 2's driver waits for quiescence twice per
turn (before and after `end_turn`); the narrator's table is per story, in the
companion, as phase 0 had it; the engine gap in (4) goes to the plan of record.
Phases 3–5 are unchanged.

---

## 7c. What phase 2 found **[verified]**

The player is one edge module (`src/edges/lps_play.pl`, 700 lines), a CLI command, five
endpoint operations and a panel. Ten checks in `tools/play_test.pl` play four of the
stories from typed English with no LLM key, and the browser check plays the door story
from the editor. Six things were learned.

**1. The templates are the grammar.** A command template's surface — `the command is
to put *a thing* into *a container*` — is a pattern, `put <thing> into <container>`,
and the event is its `known as` name with the slots in argument order. A story that
adds `the command is to eat *a thing*` has extended the parser without touching it.
The only English the parser owns is Inform's short forms (`x`, `i`, `z`, `get`, the
compass letters, `put … in`), a dozen lines. A noun phrase resolves to a program
constant by the words of its name, `door` finding `oak_door`; several matches prefer
what is in scope, and if that does not settle it the player is asked which. An order
to a character is `og, get donuts`: the `*a person* is asked to …` templates, with
`og` a prefix of a name.

**2. The turn is two quiescent bursts.** `begin_turn` goes in with the commands, the
session steps until a cycle in which nothing happened, `end_turn` goes in, and it
steps to quiescence again. A cycle report's `Events` field is what happened by that
cycle and its last field what is committed for the next; the story is read from the
first. Ogg's three-step fetch, which the phase-1 script had to squeeze into two
cycles, takes as long as it takes.

**3. The refusal message is the explanation.** A `refuse_*` action in the trace is
narrated by finding the `action_blocked` record for the action it refused and
rendering the denial's last condition through its template: *You can't open the case:
the case is locked* — *You can't take the donuts: you cannot reach the donuts* — *You
can't go east: it is not the case that east from the hall leads to anything*. The
first two read as Inform's own messages; the third says what the constraint says.
Nobody wrote any of them. A story's companion can still override with `narrate/2`.

**4. Playing is not running the script.** A story carries its `Test me with` scenario
and a `maximum time` for the gate; a play drops both (`script_term/1`) and runs
unbounded. And LE2's template list names a template by its derived functor, so the
`known as` alias (`le_lps_functor/2` in the knowledge base) is applied on the way
out — without it the parser injected `the_command_is_to_go(east)` and nothing fired.

**5. A story's own command must be a `try` too.** The IQ Test story's `eat` was a
plain obligation; typed when not carrying the donuts, it ended the run with `failure`
— the phase-0 lesson again, this time from the keyboard. `examples/if/iqtest.le` now
has `tries to eat` and `cannot eat`, and the parser gate checks the refusal.

**6. What the IDE knows about a tab.** A tab opened from the examples browser is
named by its basename (`doors.le`), so a relative include has no directory to resolve
against. The LE edge now looks for the document one level down in `examples/`
(`include_base/2`), which is a convenience with a stated limit: a story with the same
basename in two example directories would resolve to the first. The proper answer is
a tab that carries its path, which is the IDE's to give.

Also found: Node's `cpSync` leaves an untouchable empty file on a virtiofs mount, so
`ui/build.mjs` copies the static files with `copyFileSync`; and the assistant fallback
of phase 2(b) was first wired as a translator (`llm_parse/4`, offered the channel's
events and nothing else) and then replaced by a chooser: `play_guess/3` shows the
model the line and the commands the story could take now, numbered, and the model
answers with one number or 0, so what it picks is always a sentence the parser
accepts. The panel and the terminal call it when a turn comes back not understood.
It is not exercised by any gate, since none runs with a key.

**Adjustments made to the plan**: none to phases 3–5. Phase 3 can begin: the Alice
story needs the existential of §6.2 the moment the White Rabbit *appears*, and the
Play panel is where the fork of §7 phase 3 will be shown.

---

## 7d. What phase 3 found **[verified]**

Alice's chapters I and II are 330 lines of Logical English and 60 of narration:
five rooms, the door fifteen inches high with the key on the glass table, the
bottle, the cake, the fan, a size with three values, the pool of tears as a room that
comes into being, the White Rabbit on a route with a return for the fan, and two
chapters as scenes. The book's path ends in the pool; the other, in the garden. Both
play from the keyboard and both replay as scripts. Five things were learned.

**1. The existential was not needed — and Inform never needed it either.** §6.2
expected the White Rabbit's *appearing* to call for a fresh constant. It does not:
the Rabbit is a named individual that begins *offstage* and runs on-stage, which is
exactly how Inform does it (`now the White Rabbit is in the Hall`); Inform has no
run-time creation of objects at all. The gap in §6.2 is real for a story that
manufactures individuals — a caucus-race that hands out prizes — and stays deferred,
with that precedent noted: a named cast and a room called `offstage` cover the
classics.

**2. `becomes` needs a value slot that follows "that is".** `the size of the person
that is a size becomes small` was read with "the person that" as the person, because
the update form of `le_lps_surface.md` §3.4 is written for templates whose value
slot is last and whose subject is fixed. A terminate-and-initiate pair says the same
thing in two laws; the surface document should say which templates `becomes` fits.

**3. A story's words for a move come before the place.** A `narrate/2` clause for
`go(player, down)` had replaced the room description; the narrator now appends the
look after a narrated move. And `narrate(A, none)` is how a story says an action
is not told — the Rabbit drops the gloves in the same breath as the fan.

**4. A fork is the same term under a second name.** `lps_session_fork/2` makes a
*hypothetical* session, which refuses observations; a second game needs a second
trunk, and since a session is an immutable term that is a dictionary copy. `Diff`
is `trace_diff/3` rendered through the templates: *only in play2, cycle 19: You
take the golden key* — the §I.6 machinery, in the words of the story.

**5. A second scenario is a second document that includes the first.** An included
document's scenarios do not travel (LE2 drops them, rightly), so `alice_garden.le`
includes `alice.le` and adds its own script, and the gate replays both. That is
also how a story is versioned: the world in one file, each path in another.

Also found: the `Exits:` line lists `up` in the rabbit hole, because the library
makes a stated connection two-way and the story forbids the climb with a
precondition rather than a one-way map fact; a `one way` template in the library
would be the honest fix. And the documentation screenshots regenerate with the Play
button in the top bar, as `CLAUDE.md` asks after a UI change.

**Adjustments made to the plan**: §6.2 loses its "needed by Alice"; phase 4 stands.

---

## 7e. What phase 4 found **[verified]**

The front end is 600 lines: a sentence splitter that knows Inform's quoting and rule
preambles, a dozen assertion forms as regular expressions over the sentence, a small
world (rooms, kinds, properties, placement, the map, doors, keys, descriptions, the
script), and an emitter that writes a Logical English story on the library. Its output
is a `.le` and a companion; the CLI writes them beside a copy of the library, since an
include resolves against the document's own directory and nowhere else. The rule
register is reported sentence by sentence, as §5.1 required. Six things were learned.

**1. The assertion register really is separable.** Of the eleven programs, every
sentence is either an assertion the front end takes or a rule it reports; nothing
had to be approximated. The forms that carry most of the corpus are few: `X is a
room`, `X is a [props] KIND [in Y]`, `X contains Y and Z`, `X is DIR of Y`, `It is
…`, `The matching key of X is Y`, `Test me with "…"`. Kinds declared by the source
(`A sealed box is a kind of box which is not openable`) fold into the library's, with
their defaults, and a later property cancels an earlier one it contradicts.

**2. Inform's own defaults must be reproduced or the story is wrong.** A door is
closed unless said; the player starts in the first room mentioned; a stated
connection runs both ways; `It` is the last thing declared and `here` the last room.
Each of these was a wrong initial state until it was put in.

**3. The script translates through the same short forms the player uses.** `n`,
`get banana`, `x case`, `put banana in box` become `the command is to …` sentences;
`og, get donuts`, `get all` and a story's own verbs (`eat`) become comments with a
diagnostic, because the library has no such command. The three programs with no
rules of their own — ImplicitConnections, NothingAsTerm, NegatedRP — then reproduce,
from the generated story, the very event sequences the hand-written stories were
checked against Inform's transcripts with. That is the oracle §IV.5 asked for,
obtained without running Inform.

**4. What a story loses.** Text substitutions inside descriptions (`[if Ogg carries
something]…[end if]`) are stripped with the comments; a description of a thing
travels only on the command line, since the IDE opens one document; `Understand "og"
as Ogg` has no home, so the player types `ogg`. And the story's rules — Ogg's
persuasion, the thief's every-turn walk, the hunger clock — are exactly the sentences
reported, so an imported Inform world is a world to *write rules for*, in Logical
English, not a game. That was the plan's claim and it holds.

**5. The gate runs one program per process.** Eleven translations through LE2 in
one SWI-Prolog process grew past what a six-gigabyte container allows, and a
container that kills the gate looks like a gate that hangs. `tools/inform_test.sh`
runs `inform_test:one/1` per program; the one-process `main/0` remains for a
machine with the memory. Each program's translation takes a few seconds, most of it
LE2 reading the library again — a cache keyed on the library's text would remove
it, and is LE2's to add.

**6. A generated story plays.** `./lps play examples/if/inform/NegatedRP.ni` opens
the jewel box, refuses the broken one with *the broken box is not openable*, and asks
which box you mean. Nothing in the player knows the story came from Inform.

**Adjustments made to the plan**: none. Phase 5 (export) stays optional and
unstarted; §5.2's argument against it stands. Six things were learned, not five.

---

## 7f. Turns as a layer **[verified, 2026-09-08]**

A reader of §7a's point 3 asked whether the turn — two quiescent bursts with
`end_turn` between them — is something interactive fiction on LPS *needs*, or
whether live mode, which has no turns, would do. The answer was tested rather
than argued.

**The clock is now a resource of its own.** `examples/if/turns.le` declares `the
turn begins`, `the turn ends` and `the turn is N` and the one law that counts;
`world.le` no longer mentions a turn. A story includes both (`world, turns`) or
the library alone, and the driver (`lps_play.pl`) injects the markers only for a
story that declares them (`uses_turns/1`); for the others a command goes in and
the session runs to quiescence, which is live mode's shape with the prompt as
the only clock.

**`alice_pure_lps.le` is Alice without it.** Same world, same commands, same
constraints and chapters; the three rules alice.le keys on `the turn ends` are
written as what caused them: the Rabbit runs on when Alice reaches the room it
is in (Carroll's own mechanism — she follows, it keeps ahead), a huge Alice in
the hall cries because she is huge and in the hall, a small one with a pool in
the room falls in. `tools/if_test.pl` records the same fluent transitions in the
same order — Rabbit offstage, riverbank, hole, hall, garden, hall, garden; Alice
normal, small, huge, small; the pool; both chapters — and `tools/play_test.pl`
plays it to the same end, with no `turn(` in the state and no marker in the
events. Played, it reads as the book does; the pacing differs (the Rabbit's first
two runs happen in the opening, and everything the cake causes happens in one
burst).

**So the reader is right about the logic and §7a is right about the script.** A
story's rules do not need a turn: a causal formulation exists for everything
alice.le schedules by one. What needs the turn is (a) a *scripted* replay, which
must know where one command's consequences end — the pure story's scenario
leaves gaps between commands, which is what phase 0 found a script cannot know
in general; and (b) rules that *count* commands — Inform's `every turn` and `in
three turns from now` (the MRE story), which are turn-based by definition. A
story with neither includes `world` alone. The transcript's turn numbers in the
Play panel are the driver's count of typed lines and stay either way.

## 8. Risks

- **Performance.** A cycle re-evaluates every reactive rule against the state; a
  hundred-object world with thirty rules is larger than anything in the corpus. The
  bench (`tools/bench.pl`) should get an IF entry in phase 1, before the library grows.
  Quiescence stepping multiplies the cost per turn by the burst length.
- **The parser is the product.** Inform's is thirty years old and still the thing
  players judge a game by. Phase 2(a) is deliberately narrow — verb, noun, preposition,
  noun — and the LLM fallback covers the rest at the price of a key. That is a
  respectable first version, not a competitor.
- **Text in a logic language** is a known sore point (Dialog's HN reception: the
  logic is admired, "Inform's English reads better"). §6.3's answer is to keep text out
  of the English and, where possible, out of the program.
- **The `instead` idiom** (§5.4) may read as a burden to Inform authors. The
  counter-argument — that it makes exceptions visible — should be made with a worked
  example, early.
- **Scope.** Four phases before the showcase was the honest count, and it held: all
  four were built in one day, phase 3 is the one that makes the case, and nothing
  before it was shown as "LPS does IF". What that day did not buy is polish — a
  narrator that lists `up` as an exit the story then forbids (§7d), text
  substitutions stripped from imported descriptions (§7e) — and the risks below it
  are the ones still standing.
- **Toolchain.** Running Inform itself, to regenerate transcripts or to check a
  translation against Inform rather than against the checked-in transcripts, needs a
  C build on the user's machine (`scripts/first.sh` with `inweb` and `intest` as
  siblings). No phase needed it: the transcripts in the repository carried phases 0–3,
  and phase 4's oracle is the hand-read initial state plus those same transcripts.
- **Memory.** The phase-4 gate exhausted a six-gigabyte container twice before it was
  made one-program-per-process (§7e). Anything that translates many Logical English
  documents in one process will meet the same wall until LE2 caches a library it has
  read before.

---

## 9. Sources

Repository, read in `build/inform/inform/` at commit `5c7ba42` (2026-06-24):
`README.md`; `inter/Manual/Textual Inter.w`; `inform7/Internal/Extensions/Graham
Nelson/Standard Rules.i7xd/Source/Sections/{Physical World Model, Actions, Variables and
Rulebooks}.w`; `resources/Documentation/{Writing with Inform, The Recipe Book}.md`
(§§ *How actions are processed*, *Every turn*, *Future events*, *Why are scenes designed
this way?*, *The Laws for Sorting Rulebooks*); `inform7/Tests/Test Cases/`
(`C9SceneEndSequence`, `C12RuleSorting1` and their `--I.txt`).

Web, September 2026: <https://ganelson.github.io/inform/> (the woven tools, kits,
extensions, `inter` manual); <https://github.com/ganelson/inform/releases>;
<https://github.com/ganelson/inform-evolution>; Nelson, *Natural Language, Semantic
Analysis and Interactive Fiction* (2005/6); Plotkin, *Rule-Based Programming in
Interactive Fiction* (2009), <https://eblong.com/zarf/essays/rule-based-if/>; Martens,
*Ceptre* (AIIDE 2015) and *Logic Programming for Interactive Fiction* (2011); Côté et
al., *TextWorld* (2018), <https://github.com/microsoft/TextWorld>; Short, *TextWorld,
Inform 7, Machine Learning* (2018) and *World Models Rendered in Text* (2018); Evans
and Short, *Versu*; Åkesson, *Dialog*, <https://linusakesson.net/dialog/> and
<https://github.com/Dialog-IF/dialog>; Bicking, *Intra* (2025); Story2Game (2025) and
Text2World (2025) on LLM-generated precondition/effect theories; IFDB search for Alice
adaptations. Full citations are in the two research transcripts of the session that
produced this document; the claims above that rest on them are marked
**[assessment]**.
