# Inform and LPS — an evaluation and a plan

**Written 2026-09-04; phase 0 done the same day** — see §7a for what it found and what
it changed. What exists is a shallow clone of the Inform repository in
`build/inform/inform/` (gitignored) and the phase-0 spikes in `examples/if/phase0/`,
with a check script. Everything marked **[verified]**
was checked against the clone, against LE2, or by running the engine; everything marked
**[assessment]** is a judgement and should be re-checked at the moment work starts. Web
sources are listed in §9.

This document follows the house rule: it is the reasoning. If the plan is adopted, its
milestones go into `docs/LPSplusLLM.md` and its status lives there and nowhere else.

---

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

The plan (§7) is four phases: a library, a player, a story, and only then — optionally —
an Inform *assertion* front end for importing existing worlds. The Logical English
extensions the creator anticipates are examined in §6: the timestamp one is already
done, the existential one is real but not needed until phase 3, and there is a third he
did not name (text) that matters more.

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
  not on its channel's allow-list. `examples/agent/demo.mjs` already has an LLM turning
  an English sentence into an event term on a restricted channel (`live_translate`).
  A player is a channel that may carry `command/N` and nothing else.
- **The world is the causal theory.** `take(P, X) initiates carries(P, X)` and
  `take(P, X) terminates in(X, _)` are Inform's carry-out rules with the frame axiom
  supplied by the engine rather than by the author.
- **Characters are reactive rules.** `examples/rkbook/fox_crow.lps` is already a story
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
- **The English surface exists.** `docs/le_lps_surface.md` gives events, actions,
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
hundreds of maps and object sets in front of the LPS library of §7. That is phase 4.
The rule register is Part IV §IV.1's caveat at its strongest and should not be
promised.

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

`docs/le_lps_surface.md` §3.1: a temporal suffix (`at a time`, `from a first time to a
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

**Deferred to phase 3**, where Alice needs it. Phases 1 and 2 name their objects, as
Inform does.

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
one, for the same reason `examples/agent/` is safe: the model narrates, it does not
decide.

---

## 7. The plan — "M20: interactive fiction", four phases and two optional ones

Everything below is edge and library work. `src/core/` is not touched, the conformance
gate is not affected, and `tools/lint_core.pl` should stay green throughout.

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

### Phase 1 — the library: `examples/if/world.le` + `world.lps`

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

### Phase 2 — the player: a channel, a parser, a transcript

- **The channel.** `player` may carry `command/N` and nothing else. This is one line of
  configuration in `live_start`, and it is the safety property of `examples/agent/`
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

### Phase 3 — the story: `examples/if/alice.le`

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

Gate: `docs/IntroducingLPS2.md` gains a section with screenshots from
`tools/doc_shots.cjs`; the two scenarios are behavioural tests in `tools/if_test.pl`.

### Phase 4 (optional) — an Inform *assertion* front end

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
  contents are imperative.
- The full Inform 7 language as a front end (§5.1).
- A new file extension or a new register in LE. Text goes in the companion.
- Any change to `src/core/`.

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
- **Scope.** Four phases before the showcase is the honest count. Phases 1 and 2 are
  where the weeks go; phase 3 is the one that makes the case; nothing before phase 3
  should be shown as "LPS does IF".
- **Toolchain.** Running Inform itself, to regenerate transcripts or to test phase 4,
  needs a C build on the user's machine (`scripts/first.sh` with `inweb` and `intest`
  as siblings). The checked-in transcripts make this unnecessary for phases 0–3.

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
