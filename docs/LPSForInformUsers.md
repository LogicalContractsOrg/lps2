# LPS for Inform users

A practical guide for someone who writes interactive fiction in Inform 7 and wants to
know what LPS does with it. It says what maps onto what, where the examples are and
how to run them, what LPS gives you that Inform does not, and what to watch for. Two
worked examples carry the weight: Inform's own *IQ Test* recipe, and *Alice's
Adventures in Wonderland* forked at the bottle. Every picture was taken from the
running system by `tools/doc_shots.cjs`.

The reasoning behind the design — why LPS is an IF engine rather than a compiler to or
from Inform — is `docs/InformPlan.md`. This document is the how.

## 1. The two systems in one table

| | Inform 7 | LPS with Logical English |
|---|---|---|
| A story is | assertions building a world, plus rules in ~340 rulebooks | a Logical English document that includes a library and adds its world and its rules |
| The world | kinds, objects, properties, relations, compiled to predicate calculus | facts (timeless) and fluents (change over time), stated in English templates |
| State change | `now the door is open`, destructive | causal laws: `when X opens Y then it is not the case that Y is closed` — the frame axiom is the engine's |
| Time | turns, a clock, `in four turns from now`, counters for the past | explicit cycles with the full history kept; a turn is a burst of cycles; anything scheduled names a turn |
| Preconditions | `Check` rules with a message each | `it must not be true that …` constraints; the refusal message is derived from the constraint |
| Exceptions | `Instead`, `Before`, `After`, ranked by four sorting laws | every rule fires; a conflict is settled by a constraint, not by precedence |
| Characters | `every turn` rules and `try the person asked …` | reactive rules as standing goals; a plan is a composite event the engine expands |
| The parser | `Understand` lines and a kit | the story's command templates *are* the grammar; short forms (`x`, `i`, `n`) are built in |
| Output | `say` with substitutions, `report` rules | actions rendered through their templates, or a `narrate/2` clause in a companion file |
| Debugging | `actions`, `rules`, `scenes` commands | `why` and `why not` on any line of the transcript; a timeline; a state-transition diagram |
| What-if | UNDO | fork a game and diff the two |

The one difference that changes how you write: **a command is a `try`, never an
obligation.** In LPS a reactive rule's consequent is a goal the engine must satisfy,
and a refused goal ends the run. So `the command is to open X` becomes `player tries
to open X`, a composite event whose first clause is the action and whose second is a
refusal. When a precondition refuses the action, the engine backtracks into the
refusal and can say exactly why. The library does this for every standard command;
a story does it for the commands it adds (§4).

## 2. What each Inform construct becomes

| You write in Inform | You write in Logical English |
|---|---|
| `The Kitchen is a room.` | `kitchen is a room.` |
| `The oak door is a locked door. It is east of the Hall and west of the Study.` | `oak_door is a door.` `oak_door leads east from hall to study.` and, in `initially`, `oak_door is closed and oak_door is locked` |
| `Ogg is a man in the Donut Shop.` | `ogg is a person.` and `initially ogg is in donut_shop` |
| `The case contains some cake donuts.` | `initially cake_donuts is in case` |
| `The matching key of the case is a silver key.` | `the key of case is silver_key.` |
| `Carry out eating: now the player is replete.` | `when a person eats a thing then it is not the case that the person is hungry.` |
| `Check eating something when the player is not hungry: say "…"` | `it must not be true that a person eats a thing from a first time to a second time and it is not the case that the person is hungry at the first time.` — no message: the narrator derives it |
| `Every turn when the player is hungry: say "…"` | `if the turn ends from a first time to a second time and player is hungry at the second time then player complains from the second time to a third time.` |
| `Hunger resumes in the satisfaction period of the noun from now.` | a fluent naming the turn it is due, and a rule on `the turn ends` that fires when `the turn is` that number |
| `Starting ends roundly when the player carries the ball.` | `if starting is playing at a time and player carries ball at the time then terminate starting is playing … and initiate starting has ended roundly …` |
| `Before someone taking something in a closed container: try the person asked opening the container.` | a composite event: `a person fetches a thing … if the thing is in a container … and the person opens up the container … and the person takes the thing …` — the library has it |
| `Understand "photograph [someone]" as photographing.` | declare the event `the command is to photograph *a person*` — the template is the grammar |
| `say "Taken."` | nothing, or `narrate(take(player, X), "Taken.")` in the companion |
| `Test me with "n / s / e / w".` | a `scenario` of `the command is to go north from 1 to 2.` lines — or play it |

Two conventions of Logical English that Inform does not have:

- **One condition per line, `and` first.** A conjunction on one line is read as a
  single sentence. This is the mistake everyone makes once.
- **Names are single words.** `oak_door`, `silver_key`, `cake_donuts`. The player types
  `door`, `key`, `donuts`; the narrator prints "the oak door".

## 3. Where the examples are, and how to run them

Everything is under `examples/if/`:

| file | what |
|---|---|
| `world.le` | the library: Inform's physical world model, a dozen actions with preconditions and effects, scenes, the clock, a fetch plan |
| `implicit_connections.le`, `nothing_as_term.le`, `negated_rp.le`, `npc_going.le`, `regarding.le`, `scene.le` | six of Inform's own test cases, each with its `Test me with` script |
| `iqtest.le`, `boston_cream.le`, `mre.le` | three Recipe Book examples: goal-seeking characters and future events |
| `doors.le` | a door, hand-written from *Writing with Inform* §3.12 |
| `alice.le`, `alice.lps`, `alice_garden.le` | Alice, chapters I and II, and the path the book's Alice never takes |
| `inform/*.ni` | eleven Inform sources, verbatim, for the front end of §5 |
| `expected/` | the event sequences the stories are checked against, read from Inform's ideal transcripts |

You need LE2 (the Logical English compiler) beside this repository; every command
below assumes `LPS_LE2_LIB=/LogicalEnglish2`.

```sh
./lps play examples/if/iqtest.le           # play it on the terminal: type; `why`; `fork`; `diff`; `quit`
./lps run  examples/if/iqtest.le           # replay its Test-me script and print the trace
./lps ide                                  # then open the story in the browser and press Play
```

The checks that keep the stories honest:

```sh
./myswipl.sh -q -g "consult('tools/if_test.pl')"   -g "if_test:main"   -t halt   # 12 stories replay to Inform's transcripts
./myswipl.sh -q -g "consult('tools/play_test.pl')" -g "play_test:main" -t halt   # 16 things a player does
tools/inform_test.sh                                                              # 11 Inform sources translate and run
```

In the IDE, **File ▸ Open example** lists them under *interactive fiction* and
*Inform 7*. Open one, press **Play** in the top bar, and type.

**How do you know what to type?** The verbs are the story's command templates:
the library's dozen (`look`, `examine X`, `inventory`, `wait`, `take X`, `drop X`,
`put X in Y`, `put X on Y`, `open X`, `close X`, `lock X with Y`, `unlock X with Y`,
`go north` or `n`, `enter X`, `exit`), an order to a character (`og, get donuts`),
and whatever the story declares (`drink`, `eat`, `wave` in Alice). Press
**Commands** in the panel, or type `commands` on the terminal, and the player lists
*what would work from here*: every command that succeeds when tried on a copy of
the game, in the words you would type, and a click on one does it. It is as
contextual as the story's own constraints — in the hall, `take the golden key` is
offered while Alice is her own size and `unlock the small door with the golden key`
only once she carries the key and is small. Inform has nothing like it, because
Inform cannot try an action without doing it. (It is fast: a player's command is
judged by evaluating the story's preconditions against the state, and only an
order to a character, whose plan is more than one step, is tried on a copy of the
game.) Tick **each turn**, beside Commands, and the list comes after every turn. And a line
the parser does not understand is not the end of it: with an API key set (Misc ▸
API keys), the panel shows the line and the commands the story could take to the
model, which picks the one you meant — *I take that as: go west* — or none, in
which case it says *I really don't understand that*. The parser stays
deterministic; the model only ever chooses among the parser's own sentences.

**The panes follow the game.** After each turn the Timeline, Changes, Automaton and
the 2D and 3D panes show the game so far, and the slider scrubs it. The transcript
keeps track of turns: each typed line wears its turn number and the cycles the turn
took. A click in the Timeline marks the turn that cycle fell in, in the transcript;
a click on a turn's line takes the panes to the end of that turn; and a click on a
thing in the 2D or 3D picture marks the turn in which that thing last changed, as
of the slider's cycle, and says which fluents changed — the object's history, one
click per step back.

**A note on `; known as`,** which you will see after some templates in the stories
below (`*a person* eats *a thing*; known as eat`). It is not a synonym — Logical
English has `; synonym` for that. It fixes the Prolog name the template compiles
to, `eat/2` here, instead of the one LE2 would derive from the words (`eats/2`, or
`the_command_is_to_eat/1` for a command). You never have to write it: a story
plays, its Commands list works and its refusals are explained and told, all
without it. It matters only where something outside the English names the
predicate — a companion `.lps` file of narration and pictures (`alice.lps` is
keyed on terms like `take(player, golden_key)`), and the labels on the Timeline
and the Automaton, which print the Prolog name. A story's commands, its `tries
to` composites and its refusals never need one: the player pairs a refusal with
the action it refused through the composite, not through the name. The library
declares it for everything it defines, so a story inherits those names and
writes it only for its own verbs — those a companion speaks for, or where a
short label on the Timeline is worth having.

## 4. Worked example: Inform's *IQ Test*

The Recipe Book's *IQ Test* introduces Ogg, "a person who will unlock and open a
container when the player tells him to get something inside". Inform's source:

```
The Donut Shop is a room. Ogg is a man in the Donut Shop.
The Donut Shop contains a transparent closed openable locked lockable container
called a case. The case contains some cake donuts. The donuts are edible.
The matching key of the case is a silver key. The silver key is carried by Ogg.

A persuasion rule for asking someone to try doing something: persuasion succeeds.

Before someone opening a locked thing (called the sealed chest):
    if the person asked is carrying the matching key of the sealed chest,
        try the person asked unlocking the sealed chest with the matching key;
    if the sealed chest is locked, stop the action.

Before someone taking something which is in a closed container (called the shut chest):
    try the person asked opening the shut chest;
    if the shut chest is closed, stop the action.

Test me with "open case / get donuts / og, get donuts / og, give me the donuts / eat donuts".
```

The same story as `examples/if/iqtest.le`. The world is nine lines; the two
`Before someone` rules are not there at all, because the library's fetch plan is what
they were doing by hand:

```
the knowledge base iq test includes these resources: world.

the events are:
    the command is to eat *a thing*.
    *a person* tries to eat *a thing*.
    *a person* is asked to get *a thing*.
    *a person* is asked to give *a thing* to *a second person*.

the actions are:
    *a person* gives *a thing* to *a second person*.
    *a person* eats *a thing*.
    *a person* cannot eat *a thing*.

the templates are:
    *a thing* is edible.

the knowledge base iq test includes:

shop is a room.
ogg is a person.
case is a container.
case is openable.
case is lockable.
the key of case is silver_key.
donuts is edible.

initially the turn is 0
    and player is in shop
    and ogg is in shop
    and case is in shop
    and case is closed
    and case is locked
    and donuts is in case
    and ogg carries silver_key.

when a person gives a thing to a second person
then it is not the case that the person carries the thing.

when a person gives a thing to a second person
then the second person carries the thing.

when a person eats a thing
then it is not the case that the person carries the thing.

it must not be true that
    a person eats a thing from a first time to a second time
    and it is not the case that the person carries the thing at the first time.

if a person is asked to get a thing from a first time to a second time
then the person fetches the thing from the second time to a third time.

if a person is asked to give a thing to a second person from a first time to a second time
    and the person carries the thing at the second time
then the person gives the thing to the second person from the second time to a third time.

if the command is to eat a thing from a first time to a second time
then player tries to eat the thing from the second time to a third time.

a person tries to eat a thing from a first time to a second time if
    the person eats the thing from the first time to the second time.

a person tries to eat a thing from a first time to a second time if
    the person cannot eat the thing from the first time to the second time.
```

Read the last three rules again: that is the `try` pattern of §1, written out for the
one command the library lacks. Everything else — opening, taking, giving orders,
the plan Ogg follows — is the library's.

Play it and type Inform's own test script:

```
> open case
You can't open the case: the case is locked.
> get donuts
You can't take the donuts: you cannot reach the donuts.
> og, get donuts
Ogg unlocks the case with the silver key.
Ogg opens the case.
Ogg takes the donuts.
> og, give donuts to me
Ogg gives the donuts to you.
> eat donuts
You eat the donuts.
```

Nobody wrote the two refusal messages. When the constraint refuses `open`, the
engine backtracks into the refusal, and the narrator asks the engine *why not*: the
denial names `the case is locked`, and that is the message. Ogg's three actions are
the library's fetch plan being expanded: the case is closed, so open it first; it is
locked, so unlock it first; he carries the key, so he can. **Why?** asks the engine
about the last turn:

![IQ Test in the Play panel](images/guide-iqtest-play.png)

The answer names the rule, the composite event it was resolving, and the sentence of
the story it came from. Right-clicking anything in the Timeline or the Changes pane
asks the same question of a scripted run.

**Asking on the terminal.** The same questions can be put to the story's own scripted
run, without playing it, with `./lps explain`. The refused `open` at the first turn:

```sh
./lps explain examples/if/iqtest.le --ask "why_not(happened(open(player, case)), 3)"
```
```
[blocked_by_denial]
open(player,case) did not occur at cycle 3
  a denial blocked open(player,case) — false [happens(open(player,case),2,3),holds(locked(case),2)]
```

That is the constraint from the library, with the fluent that made it hold: the case
was locked at cycle 2. It is the whole of the refusal message's provenance. The
refused `get donuts` at the second turn:

```sh
./lps explain examples/if/iqtest.le --ask "why_not(happened(take(player, donuts)), 7)"
```
```
[blocked_by_denial]
take(player,donuts) did not occur at cycle 7
  a denial blocked take(player,donuts) — false [happens(take(player,donuts),6,7),holds(not(reachable(player,donuts)),6)]
```

`reachable` is the library's intensional fluent: the donuts are in a closed case, so
nothing in the room can reach them. And why Ogg unlocked the case at the third turn,
which nobody told him to do:

```sh
./lps explain examples/if/iqtest.le --ask "why(happened(unlock(ogg, case, silver_key)), 11)"
```
```
[happened]
unlock(ogg,case,silver_key) occurred from cycle 10 to 11 — committed while resolving goals in the previous cycle
  while resolving the composite event open_up(ogg,case) — from 10 to 12
  while resolving the composite event fetch(ogg,donuts) — from 10 to 13
  from the goal created by a reactive rule (goal 7) — consequent [happens(fetch(ogg,donuts),10,A)]
    rule at src(examples/if/iqtest.le,59,0,le) — if [happens(ask_get(_,_),_,_)] then ...
```

Read from the bottom up: the order to get the donuts created a goal, `fetch` is the
library's plan for getting something, opening a locked case is `open_up`, and unlocking
is the first step of that. The line number is the story's sentence `if a person is
asked to get a thing … then the person fetches the thing …`. In Inform the same
question is answered by reading the `Before someone` rules and running `rules on`.

## 5. Bringing an Inform source across

`./lps inform` reads an Inform 7 source and writes the Logical English story its
*assertions* make. Its *rules* are reported, sentence by sentence, as diagnostics;
they are not approximated.

```sh
./lps inform examples/if/inform/IQTest.ni                    # print the story
./lps inform examples/if/inform/IQTest.ni --out build/story  # write it beside a copy of the library
./lps play   examples/if/inform/NegatedRP.ni                 # or play the source directly
```

In the IDE the same happens when you open a `.ni` file:

![An Inform source, opened as a story](images/guide-inform-import.png)

What crossed: the room, Ogg, the case with its properties and its key, the donuts,
the initial placement, and the first two commands of the test script. What did not,
and says so in the comments at the bottom and in the diagnostics: `og, get donuts`
(no such command in the library), `eat donuts` (a verb the story must add), and the
two `Before someone` rules, the persuasion rule and the unlisted block-giving rule.
The imported story is a *world to write rules for*: add the eleven lines of §4 that
say what `og, get donuts` means, and it plays.

The front end takes rooms, kinds (built in or declared with `is a kind of`),
properties, `contains`, `in`/`on`, `here`, `carried by`, the map in all its phrasings,
doors with two sides, matching keys, descriptions, and `Test me with`. It applies
Inform's defaults: a door is closed unless said, the player starts in the first room,
a connection runs both ways, `It` is the last thing declared. Eleven of Inform's
programs go through it in `tools/inform_test.sh`, checked against the initial state
read by hand from each and, for the ones with no rules of their own, against the
transcripts.

## 6. Worked example: Alice, forked at the bottle

`examples/if/alice.le` is chapters I and II: the riverbank, the rabbit hole, the hall
of doors with the golden key on the glass table and the garden behind a door
fifteen inches high; a size with three values; a pool of tears that comes into being;
the White Rabbit on a route, with a return for the fan; and two chapters as scenes.
Carroll's words are in `alice.lps`, the companion.

Three things in it are worth reading as models.

**A character with a route.** The Rabbit's timetable is four facts and one rule:

```
the rabbit runs from offstage to riverbank.
the rabbit runs from riverbank to rabbit_hole.
the rabbit runs from rabbit_hole to hall.
the rabbit runs from hall to garden.

if the turn ends from a first time to a second time
    and white_rabbit is in a room at the second time
    and the rabbit runs from the room to a second room
then white_rabbit runs from the room to the second room from the second time to a third time.
```

The Rabbit *appears* by running from `offstage` to the riverbank. That is how Inform
does it too — `now the White Rabbit is in the Hall` — and it is why no new kind of
sentence was needed for a character who is not there yet.

**A pool that comes into being.** A room is reachable only once a fluent holds:

```
down from hall leads to pool_of_tears at a time if
    the pool of tears exists at the time.
```

That is a clause added to the library's own `leads` fluent. A story extends the map
the way it extends anything else: with a sentence.

**A constraint instead of an `Instead`.** The door is fifteen inches high:

```
it must not be true that
    a person goes south from a first time to a second time
    and the person is in hall at the first time
    and it is not the case that the size of the person is small at the first time.
```

Inform would write `Instead of going south in the Hall when the player is not small:
say "…"`. Here there is no message and no precedence: the constraint refuses, the
narrator says why, and the same constraint applies to the Rabbit.

Now the part Inform cannot do. Play to the hall, then choose **Fork this game…**,
the last item of the games picker. In the fork,
take the key first, then drink, unlock, open, and go south — the path the book's
Alice never takes. **Diff** says what happened in this game and not in the other,
in the words of the story:

![Alice forked at the bottle](images/guide-alice-fork.png)

A session is an immutable term, so a fork costs nothing and the two games diverge
with what is typed into each. In the original, type `drink bottle` and then `take
key`: *You cannot possibly reach it: the key is on the table, far above your head* —
that one is Carroll's, from the companion, overriding the narrator's derived line.

Run the story's own scenario with **Run** and the panes show the plot rather than the
prose. The Timeline is the book's path, fluent by fluent and turn by turn:

![Alice on the timeline](images/guide-alice-timeline.png)

And the state-transition diagram is what Inform's Scenes index calls "the map of
time", drawn from the run rather than from the declarations:

![Alice as a state-transition diagram](images/guide-alice-automaton.png)

## 6a. Seeing the world, in two dimensions and three

An LPS program can say how its state should be drawn — `display/2` for a 2D canvas,
`display3d/2` for a three.js scene — and the IDE's 2D and 3D panes play the run back
as a picture, with the cycle slider to scrub it and a right-click on anything drawn
to ask why it is there. Inform has no counterpart; its world is prose.

Nobody has to write those clauses. The assistant's **Animate in 2D** and **Animate
in 3D** buttons ask a language model for them, from the program's declarations and
initial state, and offer to put the result in the companion file. That is how the
drawings below came about: the same request, made through LPS2's LLM client to
`openai/gpt-oss-120b` on Groq, validated by running the story and counting what was
drawn, and written into `alice.lps` and `iqtest.lps` with a header saying so.

**A disclaimer that matters.** A model's drawing is not deterministic and not
authoritative. Ask again and you get a different layout, different colours, other
choices of what is worth drawing; the IQ Test drawing below puts the case outside
the shop, which is the model's geometry and nobody else's. What you see is one
answer among many, kept because it was good enough to illustrate the story. The
logic is untouched: `display/2` reads the state and never changes it, and the gates
that check the stories against Inform's transcripts do not look at the pictures at
all. Edit the clauses by hand, or regenerate them, as freely as you like.

Alice at cycle 40 of the book's path, small in the hall, the key on the table out of
reach, the Rabbit in the garden:

![Alice, drawn in 2D](images/guide-alice-2d.png)

The same cycle in three dimensions: the rooms as slabs, everything standing on the
slab of the room that holds it, `carries` as a line:

![Alice, drawn in 3D](images/guide-alice-3d.png)

The IQ Test at cycle 12, just after Ogg has unlocked and opened the case on the
player's order:

![The IQ Test, drawn in 2D](images/guide-iqtest-2d.png)

![The IQ Test, drawn in 3D](images/guide-iqtest-3d.png)

The pictures regenerate from the clauses in the companions; the clauses themselves
regenerate from the model, differently each time. `docs/UsingTheIDE.md` says what the
panes can do, and `docs/lps_summary.md` §18 and §18a say what the clauses may say.

## 7. What LPS gives you that Inform does not

- **Explanations.** `why` on the terminal, **Why?** in the panel, `./lps explain` on
  a scripted run, or a right-click in a pane: which rule, which composite event, which
  sentence. `why not` for what did not happen, including which constraint refused it
  and what fluent made it hold (§4).
- **Pictures.** A 2D canvas and a 3D scene of the state, scrubbed by cycle, drawn
  from clauses a model can write for you (§6a).
- **What would work now.** The list of commands that would succeed from here,
  computed by trying each on a copy of the game (§3). A fork is free, so asking
  "what could I do?" costs a burst per candidate and nothing else.
- **Refusals for free.** Every `check` message in an Inform story is a sentence
  somebody wrote. Here it is the constraint, rendered.
- **Forking.** What-if, at any turn, with a diff.
- **Time as data.** The full history is kept: `at the first time` in a rule is a real
  query, not a counter. A scheduled event is a fact about a future turn.
- **Plans.** A character's goal is a composite event; the engine finds the steps.
  Ogg's fetch is the library's; the plan for a character is the sentences that say
  what it wants.
- **The same story, scripted and played.** A `scenario` is a `Test me with`; the gate
  replays every story against Inform's transcripts, and you play the same file.
- **A live session.** A story is a program that waits for events, which is also what
  a thermostat and a Minecraft bot are here; the Play panel is one client of it.

## 8. What to watch for

- **One condition per line.** Said above; it will bite once.
- **Your own commands need the `try` pair.** A story that declares `the command is
  to eat *a thing*` must also give `player tries to eat the thing` its two clauses
  (§4), or the first refused `eat` ends the run.
- **Property changes are two laws.** `becomes` fits `the reward is *an amount*`; for
  `the size of *a person* is *a size*`, terminate the old value and initiate the new.
- **No `Understand` synonyms for nouns yet.** The parser finds `door` for
  `oak_door` and `og` for `ogg` by the words of the name; a name that shares no word
  is not found.
- **No listing of contents in `look`** beyond what is directly in the room, no light
  and darkness, no plurals, no pronouns. The library is a sliver of the Standard
  Rules on purpose; `docs/InformPlan.md` §7b says what it has.
- **Exits list both ways.** A stated connection runs both ways, as in Inform; a story
  that forbids the return trip with a constraint (Alice cannot climb back up) still
  shows `up` as an exit.
- **An action must not be named like a Prolog built-in.** The library says `closes … ;
  known as shut` for that reason.
- **The rule register of an imported Inform story is yours to write.** The front end
  is honest about it: what it reports, it did not translate.

## 9. Where to go next

- `examples/if/README.md` — every story, how it is driven, the conventions.
- `docs/InformPlan.md` — the evaluation, the plan, and what each phase found, with
  the numbers.
- `docs/UsingTheIDE.md` — the Play panel among the rest of the editor.
- `docs/lps_tutorial.md` and `docs/le_lps_surface.md` — the language, and Logical
  English for it, construct by construct.
