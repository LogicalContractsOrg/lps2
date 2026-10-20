# Inform 7 and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Inform 7 is the language that most people use to write interactive fiction.
Interactive fiction is a type of game that people usually call a text adventure. An
Inform source is written in English. The source is a `.ni` file, the `story.ni` of an
Inform project. *Assertions*, such as `The Kitchen is a room.`, make the world.
*Rules*, such as `Instead of …` or `Every turn: …`, tell what occurs when the player
types.

LPS2 reads the assertions of an Inform source. It then writes the Logical English
story that these assertions describe. The story uses the LPS2 library for interactive
fiction (`examples/if/world.le`) and its clock (`examples/if/turns.le`). You can then
run the story, play it, get explanations from it and fork it. Fork means: make a
different version from one point in the story. You can do these things as with all
other LPS (Logic Production System) programs.

The rules are the one part that LPS2 does not translate. LPS2 tells you about each
rule and its line. You must then write that rule again in Logical English yourself.
The translation goes in one direction only, from Inform into LPS. Nothing writes
Inform from LPS.

In the IDE, you open an Inform source with **File ▸ Open example from server…**, in
the *Inform 7* folder. The IDE is the editor in which you write and run programs. On
the command line, the commands are `./lps inform`, `./lps run` and `./lps play`. The
stories are in Logical English. Thus LE2, the Logical English editor, must be
installed next to LPS2 (`LPS_LE2_LIB`). The hosted service has this installation.

This document is the reference for the translation and for its traps. A trap is a
problem that is easy to miss. For full examples of stories, read the tutorial
[LPS for Inform users](../tutorials/inform-users.md). The tutorial translates the
Inform story *IQ Test* and then completes it by hand. It also forks the story *Alice*
at the bottle.

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
| Inform 7 into LPS | **File ▸ Open…** (a `.ni` from your computer) or **File ▸ Open example from server…**, folder *Inform 7*; `./lps inform`, `./lps run`, `./lps play` | one `.ni` source (the command line also accepts `.inform`) | a Logical English story that includes `world` and `turns`. The story has rooms, things, kinds, properties, the map, the initial positions, and the `Test me with` script as its scenario. On the command line, you also get a `.lps` companion file with the descriptions. Each rule is a warning on its line. | eleven Inform programs (`tools/inform_test.sh`). Each translated story must run its script to success. Its initial state must contain the facts that a person read by hand from the assertions. Three programs have no rules of their own. These three must also give the same sequence of events as the hand-written story. A test compares the hand-written story with the ideal transcript of Inform. |
| LPS into Inform | — | — | not available | — |

## How to use it

### In the IDE

Do these steps:

1. Select **File ▸ Open example from server…**.
2. Open the *Inform 7* folder below interactive fiction. The folder contains eleven
   Inform programs. We copied them exactly from the published files of Inform. Eight
   are test cases of Inform. Three are examples from *Writing with Inform* and *The
   Recipe Book*.
3. Select one program, for example `IQTest`.

The server translates the source. The editor opens the story in a new tab. The name
of the tab is the name of the source in lower case, with `_ni` added
(`iqtest_ni.le`). The added `_ni` makes sure that the tab does not get the name of
the hand-written story (`iqtest.le`).

The status line gives the number of conversion notes. Possibly the test script uses a
command that the library does not have. That command then becomes a comment at the
bottom of the scenario (`% not translated: …`). The status line also counts the other
notes: one note for each rule, and one note for each sentence that matched no
assertion form. To read the notes one at a time, each with its line in the source,
run `./lps inform` on the source. Refer to the next section.

Then you can use these items:

- **View ▸ The original this was converted from** shows the Inform source.
- **Run** runs the test script again as the scenario. The panes show the run.
- **Play** opens the play panel and starts the story. Then you type commands. The
  **Play** button is available because the story includes the library.

You can also select a `.ni` file from your computer with **File ▸ Open…**. The server
then translates the file in the same way. The story opens as `<name>_ni.le`, with the
notes at the top. The source is available with
**View ▸ The original this was converted from**.

### On the command line

All three commands need `LPS_LE2_LIB`. This setting must give the location of a copy
of LE2 on the computer.

```sh
./lps inform examples/if/inform/IQTest.ni                    # print the story, then the companion
./lps inform examples/if/inform/IQTest.ni --out build/story  # write iqtest_ni.le and iqtest_ni.lps beside a copy of world.le
./lps run    examples/if/inform/IQTest.ni                    # translate and replay the Test-me script
./lps play   examples/if/inform/NegatedRP.ni                 # translate and play on the terminal
```

`./lps inform` prints each note on the error channel, standard error. It prints one
note on each line, with the line of the source that the note is about:

```
not translated (rule): the rule register is not assertions — Before someone opening a locked thing (called the sealed chest):
```

With `--out DIR`, the command writes the story and its companion file into `DIR`. If
`DIR` does not contain `world.le`, the command also adds a copy of `world.le`. A
document looks for the files that it includes in its own folder. Thus, if you move a
story, copy `world.le` and `turns.le` from `examples/if/` into the new folder of the
story.

### What the generated story looks like

From `examples/if/inform/IQTest.ni`:

```
The Donut Shop contains a transparent closed openable locked lockable container called a case. The case contains some cake donuts. The donuts are edible.

The matching key of the case is a silver key. The silver key is carried by Ogg.
```

the story (shortened):

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

The companion file (on the command line only):

```
description(donut_shop, "Vibrantly decorated in donut colors: pink, brown, and cream.").
description(ogg, "Ogg is slumped in the corner[if Ogg carries something] with [a list of things carried by Ogg][end if]. He wears a nametag which says \"HELLO MY NAME IS OG.\"").
description(nametag, "Sadly misspelled.").
```

### Making it play

A translated story has a world, but it has no rule register. Thus it has no rules.
To make the story operate as the Inform original does, write the rules again in
Logical English:

- Write each `Instead`, `Before`, `Check`, `Carry out`, `After` and `Every turn` rule
  again. Write it as a causal law (`when … then …`), as a constraint
  (`it must not be true that …`) or as a reactive rule (`if … then …`). A causal law
  tells what an event does to the state. A constraint tells what must never be true.
  A reactive rule tells what to do when a condition becomes true. An every-turn rule
  uses `the turn ends`.
- Write each verb that the story adds (`eat`, `drink`) as a command template,
  `the command is to eat *a thing*`, with the two clauses of
  `player tries to eat the thing`.
- Write each order to a character (`og, get donuts`) with the `fetches` plan of the
  library, or with a composite event of your own.

The tutorial does all of these steps for *IQ Test*, one line at a time
([§4](../tutorials/inform-users.md#4-worked-example-informs-iq-test)). The
hand-written stories in `examples/if/` (`iqtest.le`, `boston_cream.le`, `mre.le`,
`negated_rp.le` …) are completed versions of some of the eleven sources.

## How Inform 7 maps to LPS

| Inform 7 | LPS (Logical English on `world.le`) |
|---|---|
| `The Donut Shop is a room.` | `donut_shop is a room.` (timeless) |
| `Ogg is a man in the Donut Shop.` | `ogg is a person.` and, below `initially`, `ogg is in donut_shop` |
| `… a transparent closed openable locked lockable container called a case` | `case is a container.` `case is openable.` `case is lockable.` `case is transparent.`, and `case is closed`, `case is locked` below `initially` |
| `The case contains some cake donuts.` | `cake_donuts is in case` below `initially` |
| `The silver key is carried by Ogg.` / `Ogg wears a nametag.` | `ogg carries silver_key` / `ogg wears nametag` below `initially` |
| `The matching key of the case is a silver key.` | `the key of case is silver_key.` |
| `The Twisty Passage is east of the Twisted Passage.` | `east from twisted_passage goes to twisty_passage.` |
| `West of the Twisty Passage is nowhere.` | `west from twisty_passage goes nowhere.` |
| a door `east of the Hall and west of the Study` | `… leads east from hall to study.` |
| `A box is a kind of container which is closed and openable.` | no sentence of its own: each box becomes `… is a container.` with the properties of the kind |
| `The donuts are edible.` (a property that the library does not have) | a new template `*a thing* is edible.` and `cake_donuts is edible.` |
| `"Vibrantly decorated …"` after a room; `The description of X is "…"` | `description(donut_shop, "…").` in the `.lps` companion file |
| `Test me with "open case / get donuts / …".` | `scenario one is:` with four cycles for each command |
| the player (with no position) | `player is in donut_shop`, in the first room that the source declares |
| `Before …`, `Instead of …`, `Every turn: …`, `Understand …`, `Table of …`, scenes, `… when …` | a warning on the line; nothing in the story |

### Sentences and names

The reader divides the source into sentences. The reader is the part of LPS2 that
reads the Inform source. A sentence ends at a full stop outside quotes, at an empty
line, or at a closing quote followed by a capital letter. For example,
`"…" Understand "og" as Ogg.` is two sentences.

A line that ends in a colon starts a rule. The text from that line to the next empty
line is the body of the rule. The reader ignores all of that text. Text in square
brackets outside quotes is a comment. The reader removes each comment before it
reads other text. This includes a comment inside a different comment. Square brackets
inside quotes are text substitutions, and the reader keeps them (refer to
[Descriptions](#descriptions)).

The reader compares each sentence with the assertion forms, in a fixed sequence. The
first form that matches is the one that the reader uses.

The name of an object is made of the words of the object, in lower case, with
underscores between them. The article is not part of the name. Thus `the Donut Shop`
becomes `donut_shop`, and `some cake donuts` becomes `cake_donuts`. A later sentence
can use only the end of a name. `The donuts are edible.` finds `cake_donuts`, because
that name ends in `donuts`. The test script uses the same method: `get donuts`
becomes `the command is to take cake_donuts`. `It` means the last thing that the
source declared. `here` means the last room that the source declared.

### Kinds and properties

The reader knows these kinds of Inform: `room`, `thing`, `container`, `supporter`,
`door`, `person`, `man`, `woman`, `animal`, `device`, `backdrop`, `vehicle` and
`region`. It knows them in the singular or the plural. It also knows each kind that
the source declares with `A … is a kind of …`. The article can be absent:
`Food is a kind of thing.`

In the story, `man`, `woman` and `animal` all become `person`. `device` and
`backdrop` become usual things, and `vehicle` becomes `container`. A kind that the
source declares becomes the kind that it is based on, with the properties of that
kind. Thus `A sealed box is a kind of box which is not openable.` gives a container
that is closed and not openable. When two words have opposite meanings, the later
word is the one that the reader uses.

The reader puts properties into three groups:

- `openable`, `lockable`, `enterable` and `fixed in place` (also `scenery`) are
  timeless facts that the library reads.
- `closed` and `locked` are fluents of the library. A fluent is a fact that can
  change over time. Thus the story gives them below `initially`, and they can change
  during play. `open`, `unlocked`, `portable` and `unopenable` each say that a
  property is absent. Thus they give no sentence.
- `edible`, `transparent`, `opaque`, `lit`, `dark`, `wearable`, `male`, `female` and
  `undescribed` are not in the library. The story gives each of these properties
  that the source uses a template of its own. It gives the property as a timeless
  fact. Your own rules can then read it.

The reader uses two of the default values of Inform. A door is closed and openable,
unless the source says that the door is open. The player starts in the first room
that the source declares, unless the source puts the player in a different place.

### Where things are

`X is in Y`, `X is on Y`, `In Y is X`, `On Y is X`, `Y contains X and Z`,
`X is here`, `X is carried by P`, `P carries X`, `X is worn by P` and `P wears X`
all become fluents below `initially`: `… is in …`, `… is on …`, `… carries …`,
`… wears …`. A thing that holds something becomes a container. A thing that
supports something becomes a supporter. This is not true if the thing is a room, or
if the source already gave the kind of the thing. Inform makes the same conclusions.

### The map and doors

`X is DIR of Y`, `DIR of Y is X`, `DIR is X` (from the last room), `X is DIR` (of the
last room) and `X is DIR of Y and DIR2 of Z` all become `DIR from Y goes to X.` The
library makes each connection go in the two directions, as Inform does. The reader
reads `above` and `below` as `up` and `down`.

`DIR of Y is nowhere` (and `DIR is nowhere`, from the last room) becomes
`DIR from Y goes nowhere.` This means that there is no exit in that direction. The
library also does not calculate an exit from a connection in the opposite direction.
The reader does not make a room with the name `nowhere`. `X is nowhere` declares a
thing that has no position.

A door between two rooms (`It is east of the Hall and west of the Study`) becomes
`the door leads east from hall to study.` Possibly the source gives only one side.
Then the other side becomes a room with the name `beyond_` followed by the name of
the door.

### Descriptions

A quoted sentence alone describes the last thing that the source declared. After
`Y contains X and Z`, a quoted sentence describes Y. Thus
`The case contains some donuts. "The case gleams."` describes the case, not the
donuts. `The description of X is "…"` describes X. A quoted sentence before the first
declaration is the title of the story, and the reader ignores it. The descriptions go
into a companion `.lps` file as `description/2` facts. The narrator of `./lps play`
reads these facts.

Some substitutions inside the quotes are for a single character or for a break. The
reader writes these substitutions as Inform writes them: `[bracket]` and
`[close bracket]`, `[apostrophe]` and `[']`, `[quotation mark]`, `[line break]`,
`[paragraph break]`, `[no line break]`. A single quote that is not an apostrophe
inside a word becomes a double quote (`'HELLO'` becomes `"HELLO"`). All other
substitutions (`[if …]`, `[end if]`, `[a list of …]`, `[the noun]`) must read the
state of the story to get their value. Thus the reader keeps such a substitution
exactly as it is. It reports the sentence as
`text substitutions kept as written, not evaluated`, with the list of the
substitutions. The narrator then prints them as they are.

### The test script

`Test me with "a / b / c"` becomes the scenario, with one command for each turn and
four cycles for each turn. The story observes `the turn begins`, then the command,
then `the turn ends`, at cycles 1–2, 1–2 and 3–4. Then it observes them at 5–6, 5–6
and 7–8, and continues in the same way. The maximum time is four times the number of
commands, plus four.

The reader knows the commands of the library and their short forms: `look`/`l`,
`inventory`/`i`/`inv`, `wait`/`z`, directions (`n`, `go north` …), `examine`/`x`,
`take`/`get`, `drop`, `open`, `close`, `enter`, `exit`/`out`/`leave`,
`put X in/into Y`, `put X on/onto Y`, `unlock X with Y` and `lock X with Y`. Each
other command becomes a comment line, and its turn stays empty.

### What is reported, not translated

Some sentences start with a rule word, a grammar word or a structure word of Inform.
The reader does not read such a sentence. It gives a warning with the kind of the
sentence. These words are `Before`, `Instead`, `After`, `Every turn`, `Check`,
`Carry out`, `Report`, `When`, `At`, `To`, `Definition:`, `Rule for`, persuasion
rules, `Unsuccessful attempt`, `This is the`, `Understand`, `Table of`, `Use`,
`Include`, `Release along with`, and the headings (`Volume`, `Book`, `Part`,
`Chapter`, `Section`).

The reader also reports some sentences because of their shape, with any words:

- a line that ends in a colon (the preamble of a rule)
- `… rule is (not) listed …`
- a scene (`… is a scene`, `… begins when …`, `… ends … when …`)
- each other sentence with `when` outside its quotes (a condition: an assertion never
  has a condition)
- new actions (`… is an action …`)
- verbs (`… is a verb`)
- properties (`… can be …`, `… has a …`)
- a value (`The hunger of Ogg is 0.`, `The maximum score is 1.`: a sentence with a
  number as its complement)
- kinds of value.

A sentence that matches no assertion form gets the report
`not translated: no assertion form matched`. The reader never makes an approximate
translation. Each warning means that the story does not contain the related
sentence.

## Traps

- **The reader translates only the assertions.** You must write each rule again. You
  must also write again each verb that the story adds, and each order to a
  character. A translated story can run its script "to success". But then it has done
  only what the library does alone.
- **In the IDE, the notes are a comment at the top.** The status line gives the
  number of conversion notes and says "see the comments at the top". The comment
  gives the rules and the sentences that did not match. It gives each one with its
  line in the `.ni` file. This is the same for a story from the list of examples and
  for a `.ni` file of your own that you open with **File ▸ Open…**.
- **The IDE does not keep the descriptions.** A story that you open from the server
  is a single document. Only `./lps inform --out` writes the `description/2`
  companion file. Only `./lps run` and `./lps play` use that file.
- **The reader keeps text substitutions, but it does not calculate them.**
  `"Ogg is slumped in the corner[if Ogg carries something] with [a list of things carried by Ogg][end if]."`
  goes into the companion file without change, and the narrator prints the brackets.
  The reader writes only the substitutions for a single character or a break. The
  reader reports each sentence that contains a different substitution. Thus you know
  which descriptions you must write again as `narrate/2`.
- **The reader reads a sentence that looks like an assertion as an assertion.** The
  assertion forms match words. They do not use the grammar of Inform. The reader
  finds scenes, conditions (`when`), properties and values from their shape, and it
  reports them. But a sentence that none of those shapes finds can still match an
  assertion form. Then the story gets an incorrect fact. Read the `initially` section
  and the map in the result before you trust them.
- **The reader thinks that sentences that start with a rule word are rules.** The
  reader reports `To look is a verb` as a rule. It does the same for an assertion that
  starts with `At`, `When` or `To`.
- **The reader does not read some things that Inform knows.** These are: scenes
  (`Starting is a scene`, `… begins when …`), `usually` (`Food is usually edible`),
  either/or properties of an object (`The player is hungry`), relations, numbers and
  times, tables, and `Understand` synonyms. The reader reports all of these. The
  reader reads a kind that a sentence gives to things that are declared in a different
  place (`The apple, the candy bar, and the pasta are food`). But a kind of thing adds
  nothing more than a thing, unless the declaration gives the properties of the kind
  with `which is …`.
- **Names that are the same, and short names.** The reader matches a short name to
  the first known name that ends in the same words. When two objects match
  (`silver key` and `brass key`), `key` selects one of the two. In *TakingInventory*,
  `Inventory` is an object. But the test command `inv` still becomes
  `the command is to take inventory`. This is the command of the library, not the
  object.
- **The library is small.** `world.le` contains only a part of the Standard Rules of
  Inform: about twelve actions, no light and darkness, no plurals, no pronouns. The
  story still gives a property that the library does not know (`transparent`,
  `lit`). But the property has no effect until a rule of yours reads it. Refer to the
  [current limitations](../tutorials/inform-users.md#8-current-limitations) in the
  tutorial.
- **LPS2 runs the script again as cycles. Nobody types it.** Four cycles for each
  command are sufficient for the actions of the library. Possibly a rule of yours
  takes more than one turn. Then make `the maximum time is` larger than the number
  that the translation gave. **Play** ignores the scenario and the maximum time.
- **Tab names.** The story gets the name of the source in lower case. Each character
  that is not a letter or a digit becomes an underscore, and `_ni` is added.
  `BostonCream.ni` gives `bostoncream_ni.le`, and `IQTest.ni` gives `iqtest_ni.le`.
  The added `_ni` keeps a converted story separate from the hand-written story of the
  same program (`iqtest.le`). The knowledge base gets its name in the same way
  (`the knowledge base iqtest ni includes …`).
- **Eleven programs is a small sample.** We made and tested the reader with only
  eleven Inform sources. Longer stories will use sentences that the reader does not
  know. Expect many `no assertion form matched` warnings, and read each of them.
- **The tests compare events, not text.** The comparison with the transcripts of
  Inform compares the sequence of events. Nothing compares the text that the narrator
  prints with the text that Inform prints.

## See also

- In this documentation:
  - [LPS for Inform users](../tutorials/inform-users.md): a comparison of the two
    systems, [what each construct becomes](../tutorials/inform-users.md#2-what-each-inform-construct-becomes),
    [where the examples are](../tutorials/inform-users.md#3-where-the-examples-are-and-how-to-run-them),
    [*IQ Test* step by step](../tutorials/inform-users.md#4-worked-example-informs-iq-test),
    [how to translate a source](../tutorials/inform-users.md#5-bringing-an-inform-source-across)
    and [*Alice* forked at the bottle](../tutorials/inform-users.md#6-worked-example-alice-forked-at-the-bottle).
  - [Introducing LPS2, §19 Interactive fiction](../overview/introducing-lps2.md#19-interactive-fiction).
  - [Using the editor: the layout](../guide/ide.md#the-layout) (the play panel)
    and [the menus](../guide/ide.md#the-menus).
  - [Logical English for LPS](../reference/le-for-lps.md), specially
    [integrity constraints](../reference/le-for-lps.md#37-it-must-not-be-true-that---integrity-constraints)
    and [causal laws](../reference/le-for-lps.md#34-when--then---causal-laws).
    You use them to write the rules again.
  - [Integrations](index.md): all the other systems that LPS2 reads or writes.
- In the other IDE:
  - [Logical English with LPS as target](https://le2.logicalcontracts.com/docs/user/reference/lps-target).
  - [Logical English integrations](https://le2.logicalcontracts.com/docs/user/integrations/index).
- The documentation of Inform 7:
  - [The Inform 7 website](https://ganelson.github.io/inform-website/)
  - [Writing with Inform](https://ganelson.github.io/inform-website/book/WI_1_1.html)
  - [The Inform Recipe Book](https://ganelson.github.io/inform-website/book/RB_1_1.html)
  - [Inform's source, on GitHub](https://github.com/ganelson/inform) (the test
    cases of the examples are in `inform7/Tests/Test Cases/`)
