# Inform 7 and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Inform 7 is the most widely used language for writing interactive fiction, the
kind of game usually called a text adventure. An Inform source (`.ni`, the
`story.ni` of an Inform project) reads as English. *Assertions*, such as `The
Kitchen is a room.`, build the world. *Rules*, such as `Instead of …` or `Every
turn: …`, say what happens as the player types. LPS2 reads the assertions of an
Inform source and writes out the Logical English story those assertions
describe, built on LPS2's own library for interactive fiction
(`examples/if/world.le`) and its clock (`examples/if/turns.le`). You can then
run the story, play it, have it explain itself and fork it, as with any other
LPS (Logic Production System) program. The rules are the one part that does
not cross. LPS2 reports each rule with the line it sits on, and you write that
rule again in Logical English yourself. The door goes one way, from Inform into
LPS; nothing writes Inform back out. In the IDE (the editor you write and run
programs in) an Inform source opens through **File ▸ Open example from
server…**, in the *Inform 7* folder. On the command line the commands are
`./lps inform`, `./lps run` and `./lps play`. The stories are written in
Logical English, so LE2, the Logical English editor, must be installed beside
LPS2 (`LPS_LE2_LIB`), as it is on the hosted service.

This document is the reference for how the translation works and for the traps
it holds. For stories worked through from end to end — Inform's *IQ Test*
brought across and then finished by hand, and *Alice* forked at the bottle —
read the tutorial [LPS for Inform users](../tutorials/inform-users.md).

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
| Inform 7 into LPS | **File ▸ Open…** (a `.ni` from your computer) or **File ▸ Open example from server…**, folder *Inform 7*; `./lps inform`, `./lps run`, `./lps play` | one `.ni` source (the CLI also takes `.inform`) | a Logical English story that includes `world` and `turns`: rooms, things, kinds, properties, the map, the initial placement, and the `Test me with` script as its scenario. On the command line there is also a `.lps` companion with the descriptions. Each rule is a warning on its line. | eleven Inform programs (`tools/inform_test.sh`). Each translated story must run its script to success, and its initial state must hold the facts read by hand from the assertions. The three with no rules of their own must also produce the event sequence of the hand-written story, which is itself checked against Inform's ideal transcript. |
| LPS into Inform | — | — | not provided | — |

## How to use it

### In the IDE

1. Choose **File ▸ Open example from server…** and open the *Inform 7* folder
   under interactive fiction. The folder holds eleven Inform programs, copied
   word for word from Inform's own published files: eight of Inform's test
   cases, and three examples out of *Writing with Inform* and *The Recipe
   Book*.
2. Pick one, `IQTest` for instance. The server translates the source, and the
   editor opens the story in a tab named after the source in lower case, with
   `_ni` added (`iqtest_ni.le`). The added `_ni` stops the tab from taking the
   name of the hand-written story (`iqtest.le`).
3. The status line says how many conversion notes there were. When the test
   script uses a command the library does not have, that command becomes a
   comment at the foot of the scenario (`% not translated: …`). The status
   line also counts the other notes: one for each rule, and one for each
   sentence that matched no assertion form. To read the notes one by one, each
   with the line it came from, run `./lps inform` on the source, as described
   below.
4. **View ▸ The original this was converted from** shows the Inform source.
5. **Run** replays the test script as the scenario, and the panes show the
   run. **Play** opens the play panel and starts the story, and then you type
   commands. The Play button is available because the story includes the
   library.

If you choose a `.ni` file from your own computer with **File ▸ Open…**, the
server translates the file in the same way. The story opens as
`<name>_ni.le`, with the notes at the top, and the source is there under
**View ▸ The original this was converted from**.

### On the command line

All three commands need `LPS_LE2_LIB` to point at a copy of LE2 on the machine.

```sh
./lps inform examples/if/inform/IQTest.ni                    # print the story, then the companion
./lps inform examples/if/inform/IQTest.ni --out build/story  # write iqtest_ni.le and iqtest_ni.lps beside a copy of world.le
./lps run    examples/if/inform/IQTest.ni                    # translate and replay the Test-me script
./lps play   examples/if/inform/NegatedRP.ni                 # translate and play on the terminal
```

`./lps inform` prints every note on the error channel, standard error, one
note per line, each with the line of the source it came from:

```
not translated (rule): the rule register is not assertions — Before someone opening a locked thing (called the sealed chest):
```

With `--out DIR`, the command writes the story and its companion into `DIR`,
and adds a copy of `world.le` if `DIR` has none. A document looks for the files
it includes in its own folder. So if you move a story, copy `world.le` and
`turns.le` from `examples/if/` into the new folder beside it.

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

A translated story has a world but no rule register, which is to say no rules
at all. Before the story behaves like the Inform original, you write the rules
again in Logical English:

- write each `Instead`, `Before`, `Check`, `Carry out`, `After` and `Every
  turn` rule again as a causal law (`when … then …`), as a constraint
  (`it must not be true that …`) or as a reactive rule (`if … then …`). An
  every-turn rule keys on `the turn ends`.
- write each verb the story adds (`eat`, `drink`) as a command template,
  `the command is to eat *a thing*`, with the two clauses of
  `player tries to eat the thing`;
- write each order given to a character (`og, get donuts`) using the library's
  `fetches` plan, or a composite event of your own.

The tutorial does all of this for *IQ Test*, line by line
([§4](../tutorials/inform-users.md#4-worked-example-informs-iq-test)). The
hand-written stories in `examples/if/` (`iqtest.le`, `boston_cream.le`,
`mre.le`, `negated_rp.le` …) are finished versions of several of the eleven
sources.

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

The reader cuts the source into sentences. A sentence ends at a full stop
outside quotes, at a blank line, or at a closing quote followed by a capital
letter (`"…" Understand "og" as Ogg.` is two sentences). A line ending in a
colon starts a rule. Everything from that line up to the next blank line is
the rule's body, and the reader skips all of it. Text in square brackets
outside quotes is a comment, and the reader removes every comment — one
comment inside another included — before reading anything else. Square
brackets inside quotes are text substitutions, and the reader keeps those (see
[Descriptions](#descriptions)).

The reader tries each sentence against the assertion forms in a fixed order,
and the first form that matches wins.

An object's name is made of the object's words, in lower case, joined by
underscores, with the article left off: `the Donut Shop` becomes
`donut_shop`, and `some cake donuts` becomes `cake_donuts`. A later sentence
may use just the end of a name. `The donuts are edible.` finds `cake_donuts`,
because that name ends in `donuts`. The test script works the same way:
`get donuts` becomes `the command is to take cake_donuts`. `It` means the last
thing declared, and `here` means the last room declared.

### Kinds and properties

The kinds known are Inform's `room`, `thing`, `container`, `supporter`,
`door`, `person`, `man`, `woman`, `animal`, `device`, `backdrop`, `vehicle`
and `region`, in the singular or the plural, and any kind the source declares
with `A … is a kind of …` (the article may be left out: `Food is a kind of
thing.`). In the story, `man`, `woman` and `animal` all become `person`.
`device` and `backdrop` become plain things, and `vehicle` becomes
`container`. A kind the source declares becomes the kind it is based on, plus
the properties that kind carries, so `A sealed box is a kind of box which is
not openable.` gives a container that is closed and not openable. Where two
words contradict each other, the later word wins.

The reader sorts properties into three groups:

- `openable`, `lockable`, `enterable` and `fixed in place` (also `scenery`)
  are timeless facts the library reads.
- `closed` and `locked` are fluents of the library, so the story states them
  under `initially`, and they can change during play. `open`, `unlocked`,
  `portable` and `unopenable` each say that a property is absent, so they
  produce no sentence at all.
- `edible`, `transparent`, `opaque`, `lit`, `dark`, `wearable`, `male`,
  `female` and `undescribed` are not in the library. The story gives each one
  that is used a template of its own and states it as a timeless fact, ready
  for your own rules to read.

The reader applies two of Inform's defaults. A door is closed and openable
unless the source says the door is open. The player starts in the first room
declared, unless the source places the player somewhere.

### Where things are

`X is in Y`, `X is on Y`, `In Y is X`, `On Y is X`, `Y contains X and Z`,
`X is here`, `X is carried by P`, `P carries X`, `X is worn by P` and
`P wears X` all become fluents under `initially`: `… is in …`, `… is on …`,
`… carries …`, `… wears …`. A thing that holds something is taken to be a
container, and a thing that supports something is taken to be a supporter,
unless the thing is a room or the source has already stated the thing's kind.
Inform draws the same conclusions.

### The map and doors

`X is DIR of Y`, `DIR of Y is X`, `DIR is X` (from the last room), `X is DIR`
(of the last room) and `X is DIR of Y and DIR2 of Z` all become
`DIR from Y goes to X.` The library makes a stated connection run both ways,
as Inform does. `above` and `below` are read as `up` and `down`.

`DIR of Y is nowhere` (and `DIR is nowhere`, from the last room) becomes
`DIR from Y goes nowhere.`, which means that there is no way out in that
direction — not even the way the library would otherwise infer from a
connection stated the other way round. The reader makes no room called
`nowhere`. `X is nowhere` declares a thing that is not placed anywhere.

A door placed between two rooms (`It is east of the Hall and west of the
Study`) becomes `the door leads east from hall to study.` If the source states
only one side, the other side becomes a room named `beyond_` followed by the
door's name.

### Descriptions

A quoted sentence standing on its own describes the last thing declared. After
`Y contains X and Z`, a quoted sentence describes Y, so `The case contains
some donuts. "The case gleams."` describes the case and not the donuts.
`The description of X is "…"` describes X. A quoted sentence that comes before
anything has been declared is the story's title, and the reader drops it. The
descriptions go into a companion `.lps` file as `description/2` facts, which
the narrator of `./lps play` reads.

Inside the quotes, the reader writes out the substitutions that stand for a
single character or for a break just as Inform writes them: `[bracket]` and
`[close bracket]`, `[apostrophe]` and `[']`, `[quotation mark]`,
`[line break]`, `[paragraph break]`, `[no line break]`. A single quote that is
not an apostrophe inside a word becomes a double quote (`'HELLO'` becomes
`"HELLO"`). Every other substitution (`[if …]`, `[end if]`, `[a list of …]`,
`[the noun]`) has to look at the story's state before its value can be worked
out, so the reader keeps such a substitution exactly as written and reports
the sentence as `text substitutions kept as written, not evaluated`, with the
list of them. The narrator then prints them as they stand.

### The test script

`Test me with "a / b / c"` becomes the scenario, with one command per turn and
four cycles per turn. The story observes `the turn begins`, then the command,
then `the turn ends`, at cycles 1–2, 1–2 and 3–4, then at 5–6, 5–6 and 7–8,
and so on. The maximum time is four times the number of commands, plus four.
The commands the reader knows are the library's own commands and their short
forms: `look`/`l`,
`inventory`/`i`/`inv`, `wait`/`z`, directions (`n`, `go north` …),
`examine`/`x`, `take`/`get`, `drop`, `open`, `close`, `enter`,
`exit`/`out`/`leave`, `put X in/into Y`, `put X on/onto Y`,
`unlock X with Y` and `lock X with Y`. Any other command becomes a comment
line, and its turn is left empty.

### What is reported, not translated

When a sentence begins with one of Inform's rule, grammar or structure words,
the reader does not read the sentence at all and reports a warning naming its
kind. Those words are `Before`, `Instead`, `After`, `Every turn`, `Check`,
`Carry out`, `Report`, `When`, `At`, `To`, `Definition:`, `Rule for`,
persuasion rules, `Unsuccessful attempt`, `This is the`, `Understand`,
`Table of`, `Use`, `Include`, `Release along with`, and the headings
(`Volume`, `Book`, `Part`, `Chapter`, `Section`). The reader also reports
certain sentences by their shape, whatever words they use: a line ending in a
colon (a rule's preamble), `… rule is (not) listed …`, a scene (`… is a
scene`, `… begins when …`, `… ends … when …`), any other sentence with `when`
outside its quotes (a condition, which an assertion never has), new actions
(`… is an action …`), verbs (`… is a verb`), properties (`… can be …`,
`… has a …`), a value (`The hunger of Ogg is 0.`, `The maximum score is 1.`:
a sentence whose complement is a number), and kinds of value. A sentence that
matches no assertion form at all is reported as `not translated: no assertion
form matched`. Nothing is translated approximately. Every warning means that
the sentence behind it is not in the story.

## Traps

- **Only the assertions cross.** You have to write every rule again, and every
  verb the story adds, and every order given to a character. A translated story
  that has run its script "to success" has done no more than the library does
  on its own.
- **In the IDE, the notes are a comment at the top.** The status line gives
  the number of conversion notes and says "see the comments at the top". The
  comment lists the rules and the unmatched sentences, each with the line it
  sits on in the `.ni`. The same holds for a story taken from the example list
  and for a `.ni` of your own opened with **File ▸ Open…**.
- **The IDE drops the descriptions.** A story opened from the server is a
  single document. Only `./lps inform --out` writes the `description/2`
  companion file, and only `./lps run` and `./lps play` use it.
- **Text substitutions are kept, not worked out.** `"Ogg is slumped in the
  corner[if Ogg carries something] with [a list of things carried by Ogg][end if]."`
  reaches the companion file as written, and the narrator prints the brackets.
  Only the substitutions for a single character or a break are written out.
  Every sentence holding any other substitution is reported, so you know which
  descriptions to write again as `narrate/2`.
- **A sentence that looks like an assertion is read as one.** The assertion
  forms match on words, not on Inform's grammar. The reader recognises scenes,
  conditions (`when`), properties and values by their shape and reports them.
  But a phrasing that none of those shapes catches can still match an
  assertion form and put a wrong fact into the story. Read the `initially`
  section and the map that came out before you trust them.
- **Sentences starting with a rule word are taken for rules.** `To look is a
  verb` is reported as a rule, and so would be an assertion that starts with
  `At`, `When` or `To`.
- **Some things Inform understands are not read at all:** scenes
  (`Starting is a scene`, `… begins when …`), `usually` (`Food is usually
  edible`), either/or properties set on an object (`The player is hungry`),
  relations, numbers and times, tables, and `Understand` synonyms. The reader
  reports all of those. A kind given to things declared elsewhere (`The apple,
  the candy bar, and the pasta are food`) is read, but a kind of thing adds
  nothing beyond being a thing unless the declaration states the kind's
  properties with `which is …`.
- **Name clashes and short names.** The reader matches a short name to the
  first known name that ends in the same words. Where two objects fit
  (`silver key` and `brass key`), `key` picks one of the two. In
  *TakingInventory*, `Inventory` is an object, and yet the test command `inv`
  still becomes `the command is to take inventory`, which is the library's
  command rather than the object.
- **The library is small.** `world.le` covers only part of Inform's Standard
  Rules: a dozen actions, no light and darkness, no plurals, no pronouns. A
  property the library does not know (`transparent`, `lit`) is still stated in
  the story, but changes nothing until a rule of yours reads it. See the
  tutorial's
  [current limitations](../tutorials/inform-users.md#8-current-limitations).
- **The script is replayed as cycles, not typed.** Four cycles for each
  command is enough for the library's own actions. If a rule of yours takes
  longer than one turn, raise `the maximum time is` above the figure the
  translation produced. **Play** takes no notice of the scenario or of the
  maximum time.
- **Tab names.** The story takes the source's name in lower case, with every
  other character turned into an underscore and `_ni` added (`BostonCream.ni`
  gives `bostoncream_ni.le`, and `IQTest.ni` gives `iqtest_ni.le`). The added
  `_ni` keeps a converted story apart from the hand-written story of the same
  program (`iqtest.le`). The knowledge base takes its name the same way
  (`the knowledge base iqtest ni includes …`).
- **Eleven programs is a small sample.** The reader was built and tested
  against eleven Inform sources only. Longer stories will use phrasings the
  reader does not know. Expect many `no assertion form matched` warnings, and
  read every one of them.
- **Checked by events, not text.** The comparison with Inform's transcripts
  compares the sequence of events. Nothing compares what the narrator prints
  with what Inform prints.

## See also

- In this documentation:
  - [LPS for Inform users](../tutorials/inform-users.md): the two systems
    compared, [what each construct becomes](../tutorials/inform-users.md#2-what-each-inform-construct-becomes),
    [where the examples are](../tutorials/inform-users.md#3-where-the-examples-are-and-how-to-run-them),
    [*IQ Test* worked through](../tutorials/inform-users.md#4-worked-example-informs-iq-test),
    [bringing a source across](../tutorials/inform-users.md#5-bringing-an-inform-source-across)
    and [*Alice* forked at the bottle](../tutorials/inform-users.md#6-worked-example-alice-forked-at-the-bottle).
  - [Introducing LPS2, §19 Interactive fiction](../overview/introducing-lps2.md#19-interactive-fiction).
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
