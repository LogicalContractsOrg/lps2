# Inform 7 and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Inform 7 is the most widely used language for writing interactive fiction (text
adventures). An Inform source (`.ni`, the `story.ni` of an Inform project) reads
as English: *assertions* such as `The Kitchen is a room.` build the world, and
*rules* such as `Instead of …` or `Every turn: …` say what happens as the player
types. LPS2 reads the assertions of an Inform source and writes the Logical
English story they describe, on LPS2's interactive-fiction library
(`examples/if/world.le`) and its clock (`examples/if/turns.le`). The story can
then be run, played, explained and forked like any other. Only the rules are
not translated. Each one is reported with its line, and you write it again in
Logical English. The direction is one way, from Inform into LPS; nothing writes
Inform back out. In the IDE an Inform source opens through **File ▸ Open example
from server…** (the *Inform 7* folder). On the command line the commands are
`./lps inform`, `./lps run` and `./lps play`. The stories are Logical English,
so LE2 must be installed beside LPS2 (`LPS_LE2_LIB`), as it is on the hosted
service.

This document is the reference for the mapping and for its traps. For worked
stories (Inform's *IQ Test* brought across and completed by hand, and *Alice*
forked at the bottle), read the tutorial
[LPS for Inform users](../tutorials/inform-users.md).

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [In the IDE](#in-the-ide)
  - [On the command line](#on-the-command-line)
  - [What the generated story looks like](#what-the-generated-story-looks-like)
  - [Making it play](#making-it-play)
- [How Inform 7 maps to LPS](#how-inform-7-maps-to-lps)
  - [Sentences and names](#sentences-and-names)
  - [Kinds and properties](#kinds-and-properties)
  - [Where things are](#where-things-are)
  - [The map and doors](#the-map-and-doors)
  - [Descriptions](#descriptions)
  - [The test script](#the-test-script)
  - [What is reported, not translated](#what-is-reported-not-translated)
- [Traps](#traps)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| Inform 7 into LPS | **File ▸ Open example from server…**, folder *Inform 7*; `./lps inform`, `./lps run`, `./lps play` | one `.ni` source (the CLI also takes `.inform`) | a Logical English story that includes `world` and `turns`: rooms, things, kinds, properties, the map, the initial placement, and the `Test me with` script as its scenario. On the command line there is also a `.lps` companion with the descriptions. Each rule is a warning on its line. | eleven Inform programs (`tools/inform_test.sh`). Each translated story must run its script to success, and its initial state must hold the facts read by hand from the assertions. The three with no rules of their own must also produce the event sequence of the hand-written story, which is itself checked against Inform's ideal transcript. |
| LPS into Inform | — | — | not provided | — |

## How to use it

### In the IDE

1. **File ▸ Open example from server…**, and open the *Inform 7* folder under
   interactive fiction. It holds eleven Inform programs, copied verbatim from
   the Inform repository: eight of its test cases and three examples of
   *Writing with Inform* and *The Recipe Book*.
2. Pick one, for instance `IQTest`. The server translates it, and the editor
   opens the story in a tab named after the source in lower case, with
   `_ni` added (`iqtest_ni.le`), so it never takes the name of the
   hand-written story (`iqtest.le`).
3. The status line says how many conversion notes there were. A command of the
   test script that the library does not have is a comment at the foot of
   the scenario (`% not translated: …`). The other notes (each rule,
   each sentence no form matched) are counted there. To read them one by one
   with their lines, run `./lps inform` on the source (below).
4. **View ▸ The original this was converted from** shows the Inform source.
5. **Run** replays the test script as the scenario, and the panes show the
   run. **Play** opens the play panel and starts the story, and you type
   commands. The button is enabled because the story includes the library.

**File ▸ Open…** of a `.ni` file from your own computer does not translate it.
The file opens as plain text. To bring your own Inform source across, use the
command line, then open the `.le` it writes.

### On the command line

All three commands need `LPS_LE2_LIB` pointing at an LE2 checkout.

```sh
./lps inform examples/if/inform/IQTest.ni                    # print the story, then the companion
./lps inform examples/if/inform/IQTest.ni --out build/story  # write iqtest_ni.le and iqtest_ni.lps beside a copy of world.le
./lps run    examples/if/inform/IQTest.ni                    # translate and replay the Test-me script
./lps play   examples/if/inform/NegatedRP.ni                 # translate and play on the terminal
```

`./lps inform` prints every note to standard error, one per line, with the
line of the source it came from:

```
not translated (rule): the rule register is not assertions — Before someone opening a locked thing (called the sealed chest):
```

With `--out DIR`, the story and its companion are written into `DIR`, together
with a copy of `world.le` if none is there. An include is resolved against the
document's own directory. If you move the story, copy `world.le` and `turns.le`
from `examples/if/` next to it.

### What the generated story looks like

From `examples/if/inform/IQTest.ni`:

```
The Donut Shop contains a transparent closed openable locked lockable container called a case. The case contains some cake donuts. The donuts are edible.

The matching key of the case is a silver key. The silver key is carried by Ogg.
```

the story (abridged):

```
the maximum time is 24.

the knowledge base iqtest ni includes these resources: world, turns.

the templates are:
    *a thing* is edible.
    *a thing* is transparent.

the knowledge base iqtest ni includes:

donut_shop is a room.
ogg is a person.
case is a container.
case is openable.
case is lockable.
case is transparent.
cake_donuts is edible.
the key of case is silver_key.

initially the turn is 0
    and cake_donuts is in case
    and case is closed
    and case is in donut_shop
    and case is locked
    and ogg carries silver_key
    and ogg is in donut_shop
    and ogg wears nametag
    and player is in donut_shop.

scenario one is:
    the turn begins from 1 to 2.
    the command is to open case from 1 to 2.
    the turn ends from 3 to 4.
    ...
    % not translated: "og, get donuts" is not a command of the library
```

The companion, on the command line only:

```
description(donut_shop, "Vibrantly decorated in donut colors: pink, brown, and cream.").
description(ogg, "Ogg is slumped in the corner[if Ogg carries something] with [a list of things carried by Ogg][end if]. He wears a nametag which says \"HELLO MY NAME IS OG.\"").
description(nametag, "Sadly misspelled.").
```

### Making it play

A translated story has a world but no rule register. Before it behaves like
the Inform original, you write the rules again in Logical English:

- each `Instead`, `Before`, `Check`, `Carry out`, `After` and `Every turn`
  rule, as a causal law (`when … then …`), a constraint
  (`it must not be true that …`) or a reactive rule (`if … then …`), keyed on
  `the turn ends` where it is an every-turn rule;
- each verb the story adds (`eat`, `drink`), as a command template
  `the command is to eat *a thing*`, with the two clauses of
  `player tries to eat the thing`;
- each order to a character (`og, get donuts`), through the library's
  `fetches` plan or a composite event of your own.

The tutorial does all of this for *IQ Test*, line by line
([§4](../tutorials/inform-users.md#4-worked-example-informs-iq-test)). The
hand-written stories in `examples/if/` (`iqtest.le`, `boston_cream.le`,
`mre.le`, `negated_rp.le` …) are the finished versions of several of the
eleven sources.

## How Inform 7 maps to LPS

| Inform 7 | LPS (Logical English on `world.le`) |
|---|---|
| `The Donut Shop is a room.` | `donut_shop is a room.` (timeless) |
| `Ogg is a man in the Donut Shop.` | `ogg is a person.` and, under `initially`, `ogg is in donut_shop` |
| `… a transparent closed openable locked lockable container called a case` | `case is a container.` `case is openable.` `case is lockable.` `case is transparent.`, and `case is closed`, `case is locked` under `initially` |
| `The case contains some cake donuts.` | `cake_donuts is in case` under `initially` |
| `The silver key is carried by Ogg.` / `Ogg wears a nametag.` | `ogg carries silver_key` / `ogg wears nametag` under `initially` |
| `The matching key of the case is a silver key.` | `the key of case is silver_key.` |
| `The Twisty Passage is east of the Twisted Passage.` | `east from twisted_passage goes to twisty_passage.` |
| `West of the Twisty Passage is nowhere.` | `west from twisty_passage goes nowhere.` |
| a door `east of the Hall and west of the Study` | `… leads east from hall to study.` |
| `A box is a kind of container which is closed and openable.` | no sentence of its own: each box becomes `… is a container.` with the kind's properties |
| `The donuts are edible.` (a property the library does not have) | a new template `*a thing* is edible.` and `cake_donuts is edible.` |
| `"Vibrantly decorated …"` after a room; `The description of X is "…"` | `description(donut_shop, "…").` in the `.lps` companion |
| `Test me with "open case / get donuts / …".` | `scenario one is:` with four cycles per command |
| the player (not placed) | `player is in donut_shop`, in the first room declared |
| `Before …`, `Instead of …`, `Every turn: …`, `Understand …`, `Table of …`, scenes, `… when …` | a warning on the line; nothing in the story |

### Sentences and names

The source is cut into sentences. A sentence ends at a full stop outside
quotes, at a blank line, or at a closing quote followed by a capital letter
(`"…" Understand "og" as Ogg.` is two sentences). A line ending in a colon
starts a rule. Everything after it, up to the next blank line, is the rule's
body, and it is skipped. Text in square brackets outside quotes is removed as
a comment (comments may nest) before anything else is read. Square brackets
inside quotes are text substitutions, and are kept (see
[Descriptions](#descriptions)).

Each sentence is tried against the assertion forms in a fixed order. The
first form that matches wins.

An object is named by its words, lower case, joined by underscores, without
its article: `the Donut Shop` is `donut_shop`, `some cake donuts` is
`cake_donuts`. Later sentences can use a shorter tail of the name. `The
donuts are edible.` finds `cake_donuts` because that name ends in `donuts`.
The same holds in the test script: `get donuts` becomes
`the command is to take cake_donuts`. `It` is the last thing declared, and
`here` is the last room declared.

### Kinds and properties

The kinds known are Inform's `room`, `thing`, `container`, `supporter`,
`door`, `person`, `man`, `woman`, `animal`, `device`, `backdrop`, `vehicle`
and `region`, in the singular or the plural, and any kind the source declares
with `A … is a kind of …` (the article may be left out: `Food is a kind of
thing.`). In the story, `man`, `woman` and `animal` become
`person`. `device` and `backdrop` become plain things, and `vehicle` becomes
`container`. A declared kind becomes its base kind plus the properties it
carries, so `A sealed box is a kind of box which is not openable.` gives a
container that is closed and not openable. A later word overrides an earlier
one it contradicts.

Properties are read in three groups:

- `openable`, `lockable`, `enterable` and `fixed in place` (also `scenery`)
  are timeless facts the library reads.
- `closed` and `locked` are fluents of the library, so they are stated under
  `initially` and can change in play. `open`, `unlocked`, `portable` and
  `unopenable` are the absence of a property, and produce no sentence.
- `edible`, `transparent`, `opaque`, `lit`, `dark`, `wearable`, `male`,
  `female` and `undescribed` are not in the library. Each one used is given a
  template of its own and stated as a timeless fact, for your rules to read.

Two of Inform's defaults are applied. A door is closed and openable unless
said to be open. The player starts in the first room declared, unless placed.

### Where things are

`X is in Y`, `X is on Y`, `In Y is X`, `On Y is X`, `Y contains X and Z`,
`X is here`, `X is carried by P`, `P carries X`, `X is worn by P` and
`P wears X` all become fluents under `initially`: `… is in …`, `… is on …`,
`… carries …`, `… wears …`. A thing that holds something is taken to be a
container, and a thing that supports something to be a supporter, unless it is
a room or its kind was stated. Inform infers the same.

### The map and doors

`X is DIR of Y`, `DIR of Y is X`, `DIR is X` (from the last room), `X is DIR`
(of the last room) and `X is DIR of Y and DIR2 of Z` all become
`DIR from Y goes to X.` The library makes a stated connection run both ways,
as Inform does. `above` and `below` are read as `up` and `down`.

`DIR of Y is nowhere` (and `DIR is nowhere`, from the last room) becomes
`DIR from Y goes nowhere.`: there is no way that way, not even the one the
library would otherwise infer from a connection stated the other way round.
No room called `nowhere` is made. `X is nowhere` declares a thing that is not
placed anywhere.

A door placed between two rooms (`It is east of the Hall and west of the
Study`) becomes `the door leads east from hall to study.` If only one side is
stated, the other side is a room named `beyond_` followed by the door's name.

### Descriptions

A quoted sentence on its own describes the last thing declared; after
`Y contains X and Z`, it describes Y (`The case contains some donuts. "The
case gleams."` describes the case, not the donuts). `The description of X is "…"` describes X.
A quoted sentence before anything is declared is the story's title, and is
dropped. The descriptions go into a `.lps` companion as `description/2` facts,
which the narrator of `./lps play` reads.

Inside the quotes, the substitutions that stand for a character or a break
are rendered as Inform renders them: `[bracket]` and `[close bracket]`,
`[apostrophe]` and `[']`, `[quotation mark]`, `[line break]`,
`[paragraph break]`, `[no line break]`; and a single quote that is not an
apostrophe inside a word becomes a double quote (`'HELLO'` is `"HELLO"`).
Every other substitution (`[if …]`, `[end if]`, `[a list of …]`,
`[the noun]`) needs the story's state to evaluate, so it is kept as written,
and the sentence is reported as `text substitutions kept as written, not
evaluated`, with the list. The narrator prints them as they are.

### The test script

`Test me with "a / b / c"` becomes the scenario, one command per turn and four
cycles per turn. `the turn begins`, the command and `the turn ends` are
observed at cycles 1–2, 1–2 and 3–4, then 5–6, 5–6 and 7–8, and so on. The
maximum time is four times the number of commands, plus four. The commands
read are the library's own and their short forms: `look`/`l`,
`inventory`/`i`/`inv`, `wait`/`z`, directions (`n`, `go north` …),
`examine`/`x`, `take`/`get`, `drop`, `open`, `close`, `enter`,
`exit`/`out`/`leave`, `put X in/into Y`, `put X on/onto Y`,
`unlock X with Y` and `lock X with Y`. Any other command becomes a comment
line, and its turn is left empty.

### What is reported, not translated

A sentence beginning with one of Inform's rule, grammar or structure words is
reported as a warning with its kind, and is not read: `Before`, `Instead`,
`After`, `Every turn`, `Check`, `Carry out`, `Report`, `When`, `At`,
`To`, `Definition:`, `Rule for`, persuasion rules, `Unsuccessful attempt`,
`This is the`, `Understand`, `Table of`, `Use`, `Include`,
`Release along with`, and the headings (`Volume`, `Book`, `Part`, `Chapter`,
`Section`). So is a sentence by its shape, whatever words it uses: a line
ending in a colon (a rule's preamble), `… rule is (not) listed …`, a scene
(`… is a scene`, `… begins when …`, `… ends … when …`), any other sentence
with `when` outside its quotes (a condition, which an assertion never has),
new actions (`… is an action …`), verbs (`… is a verb`), properties
(`… can be …`, `… has a …`), a value (`The hunger of Ogg is 0.`,
`The maximum score is 1.`: a sentence whose complement is a number), and
kinds of value. A sentence that no assertion form matches is reported as
`not translated: no assertion form matched`. Nothing is approximated. A
warning means that this sentence is not in the story.

## Traps

- **Only the assertions cross.** Every rule has to be written again, and so
  does every verb the story adds and every order to a character. A translated
  story that ran its script "to success" has done only what the library does
  on its own.
- **In the IDE, the notes are a comment at the top.** The status line gives
  the number of conversion notes and says "see the comments at the top": the
  rules and unmatched sentences are listed there, each with its line in the
  `.ni`. This holds for a story from the example list and for your own `.ni`
  opened with **File ▸ Open…**.
- **The IDE drops the descriptions.** A story opened from the server is one
  document. The `description/2` companion is written only by
  `./lps inform --out` and used only by `./lps run` and `./lps play`.
- **Text substitutions are kept, not evaluated.** `"Ogg is slumped in the
  corner[if Ogg carries something] with [a list of things carried by Ogg][end if]."`
  reaches the companion as written, and the narrator prints the brackets. Only
  the character and break substitutions are rendered. Each sentence with one
  is reported, so you know which descriptions to rewrite as `narrate/2`.
- **A sentence that looks like an assertion is read as one.** The forms match
  on words, not on Inform's grammar. Scenes, conditions (`when`), properties
  and values are recognised by their shape and reported, but a phrasing that
  none of those shapes catches can still match an assertion form and put a
  wrong fact into the story. Read the generated `initially` and the map
  before you trust them.
- **Sentences starting with a rule word are taken for rules.** `To look is a
  verb` is reported as a rule, and so would be an assertion that starts with
  `At`, `When` or `To`.
- **Some things Inform understands are not read at all:** scenes
  (`Starting is a scene`, `… begins when …`), `usually` (`Food is usually
  edible`), either/or properties set on an object (`The player is hungry`),
  relations, numbers and times, tables, and `Understand` synonyms. All of
  these are reported. A kind given to things declared elsewhere (`The apple,
  the candy bar, and the pasta are food`) is read, but a kind of thing adds
  nothing beyond being a thing unless its properties are stated with
  `which is …` in its declaration.
- **Name clashes and short names.** A short name is resolved to the first
  known name that ends in the same words. With two such objects (`silver key`
  and `brass key`), `key` picks one of them. `Inventory` in *TakingInventory*
  is an object, and the test command `inv` still becomes
  `the command is to take inventory`, which is the library's command, not the
  object.
- **The library is small.** `world.le` is a subset of Inform's Standard
  Rules: a dozen actions, no light and darkness, no plurals, no pronouns. A
  property the library does not know (`transparent`, `lit`) is stated but
  changes nothing until a rule of yours reads it. See the tutorial's
  [current limitations](../tutorials/inform-users.md#8-current-limitations).
- **The script is replayed as cycles, not typed.** Four cycles per command
  fits the library's own actions. A rule of yours that takes longer than one
  turn needs a larger `the maximum time is` than the one generated.
  **Play** ignores the scenario and the maximum time.
- **Tab names.** The story is named after the source in lower case, with any
  other character made an underscore and `_ni` added (`BostonCream.ni` gives
  `bostoncream_ni.le`, `IQTest.ni` gives `iqtest_ni.le`). The suffix keeps a
  converted story apart from the hand-written one of the same program
  (`iqtest.le`); the knowledge base is named the same way
  (`the knowledge base iqtest ni includes …`).
- **Eleven programs is a small sample.** The front end was built and tested
  against eleven Inform sources. Longer stories will use phrasings it does not
  know. Expect many `no assertion form matched` warnings, and read each one.
- **Checked by events, not text.** The comparison with Inform's transcripts
  is by event sequence. What the narrator prints is not compared with what
  Inform prints.

## See also

- In this documentation:
  - [LPS for Inform users](../tutorials/inform-users.md): the two systems
    compared, [what each construct becomes](../tutorials/inform-users.md#2-what-each-inform-construct-becomes),
    [where the examples are](../tutorials/inform-users.md#3-where-the-examples-are-and-how-to-run-them),
    [*IQ Test* worked through](../tutorials/inform-users.md#4-worked-example-informs-iq-test),
    [bringing a source across](../tutorials/inform-users.md#5-bringing-an-inform-source-across)
    and [*Alice* forked at the bottle](../tutorials/inform-users.md#6-worked-example-alice-forked-at-the-bottle).
  - [Introducing LPS2, §20a Interactive fiction](../overview/introducing-lps2.md#20a-interactive-fiction).
  - [Using the editor: the layout](../guide/ide.md#the-layout) (the play panel)
    and [the menus](../guide/ide.md#the-menus).
  - [Logical English for LPS](../reference/le-for-lps.md), in particular
    [integrity constraints](../reference/le-for-lps.md#37-it-must-not-be-true-that---integrity-constraints)
    and [causal laws](../reference/le-for-lps.md#34-when--then---causal-laws),
    which are how the rules are written again.
  - [Integrations](index.md): every other system LPS2 reads or writes.
- In the other IDE:
  - [Logical English with LPS as target](https://le2.logicalcontracts.com/docs/user/reference/lps-target).
  - [Logical English integrations](https://le2.logicalcontracts.com/docs/user/integrations/index).
- Inform 7's own documentation:
  - [The Inform 7 website](https://ganelson.github.io/inform-website/)
  - [Writing with Inform](https://ganelson.github.io/inform-website/book/WI_1_1.html)
  - [The Inform Recipe Book](https://ganelson.github.io/inform-website/book/RB_1_1.html)
  - [Inform's source, on GitHub](https://github.com/ganelson/inform) (the test
    cases the examples come from are in `inform7/Tests/Test Cases/`)
