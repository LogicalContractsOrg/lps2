# Drools and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Drools is a production rule system for Java. Its rules are written in DRL: a
rule has a `when` part that matches facts in a *working memory* and a `then`
part, in Java, that inserts, modifies and deletes facts. There are two ways to
bring a DRL rule base into LPS, and they share one reading of DRL.
**LPS2's own reader** turns a `.drl` file into an LPS program in LPS's written
form; it is what **File ▸ Open…** does with a `.drl` in this IDE, and it needs
nothing else. **The Logical English translator** turns the same file into a
Logical English program for LPS (and, for a rule base that only inserts facts,
also into a timeless decision service); it runs in the Logical English editor
(**File ▸ Open…** or **File ▸ Import from Another System…** there) on
installations with the InsurLE extensions, such as the hosted service, and its
results for five rule bases are among this IDE's examples. Both directions are
one way: nothing writes DRL.

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [LPS2's own reader](#lps2s-own-reader)
  - [The Logical English translator](#the-logical-english-translator)
  - [Which one to use](#which-one-to-use)
- [How Drools maps to LPS](#how-drools-maps-to-lps)
  - [The world, not the working memory](#the-world-not-the-working-memory)
  - [Firing once](#firing-once)
  - [Words and names: the wording table](#words-and-names-the-wording-table)
  - [Truth maintenance, salience and Java](#truth-maintenance-salience-and-java)
  - [The decision-service reading](#the-decision-service-reading)
- [Traps](#traps)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| DRL into LPS | **File ▸ Open…** in this IDE; the example list; `./lps drools` on the command line | `.drl` (with a `.wording` file beside it, from the example list or the command line) | an LPS program in the written form, with a header saying what did not carry over | the rules each rule base is expected to fire, cycle by cycle, written down from its documented behaviour (`tools/drools_test.pl`, 8 cases) |
| DRL into Logical English for LPS | **File ▸ Open…** or **File ▸ Import from Another System…** in the Logical English editor (InsurLE extensions) | `.drl` | a Logical English program for LPS, a ledger, and `sources/` with the DRL | Drools itself: a Drools session run on the same working memory and the same driver steps must end in the working memory the program ends in under LPS2 (5 of 5) |
| DRL into a decision service | the same, when the rules only insert facts | `.drl` | `<name>_decision.le`, a timeless Logical English program | the facts Drools inserted, as the scenario's expected answers |

## How to use it

### LPS2's own reader

**From the example list.** **File ▸ Open example from server…** and the start
page list the folder *Drools rule bases* (`examples/migration/drools/drl/`):
`discount.drl`, `fire-alarm.drl`, `insurance.drl`, `shipping.drl` and
`traffic-light.drl`. Choosing one opens it already converted, as a tab named
`<name>.lps`. `fire-alarm.drl` is read together with `fire-alarm.wording`,
the file beside it that says what its facts and changes are called.

**From your own file.** **File ▸ Open…** and choose the `.drl`. The server
converts it and opens the result as `<name>.lps`. The status line says how many
conversion notes there were.

**What the header says.** Every converted program starts with a comment:

```
% Converted from fire-alarm.drl by LPS2 on 2026-09-16 15:59.
```

then a paragraph on how DRL was read, a reminder that a rule base needs facts,
and, under `What did not carry over:`, one line per diagnostic of the reader
(a salience, a Java statement, a field left out). The program follows. For
`fire-alarm.drl` it is:

```
fluents sprinkler(_), sprinkler_on(_), fire(_), alarm.
actions alarm_goes_off, alarm_goes_on, sprinkler_turns_on(_).

if   fire(A) at T1, sprinkler(A) at T1, not sprinkler_on(A) at T1
then sprinkler_turns_on(A) from T1 to T2.

sprinkler_turns_on(A) from T1 to T2 initiates sprinkler_on(A).

if   fire(A) at T1, not alarm at T1
then alarm_goes_on from T1 to T2.

alarm_goes_on from T1 to T2 initiates alarm.
```

It ends with `maxTime(8).`

**Adding the facts.** A DRL file has rules and no facts, so the program does
nothing until you give it some. Add an `initially` line, using the fluents of
the `fluents` line (not the Java objects; see [Traps](#traps)):

```
initially fire(kitchen), sprinkler(kitchen).
```

Then run it. In this example the sprinkler in the kitchen turns on and the alarm
goes on at cycle 2.

**Seeing the DRL.** **View ▸ The original this was converted from** shows the
file the tab was converted from. For an example opened from the list with a
wording file, both files are shown, each under its name.

**On the command line.**

```sh
./lps drools examples/migration/drools/drl/fire-alarm.drl --facts "fire(kitchen), sprinkler(kitchen)"
```

prints the diagnostics and then the run, cycle by cycle. A `.wording` file
beside the `.drl` is used. `--max-time` changes the default of 8 cycles.

### The Logical English translator

This translator reads the DRL with LPS2's reader and writes the result as
Logical English, so a person who does not read LPS can check it. It is part of
the InsurLE extensions of the Logical English installation.

**In the Logical English editor.** **File ▸ Open…** (or **File ▸ Import from
Another System…**) and choose the `.drl`. The editor opens `<name>.le`, a
program that declares `the target language is: lps.` A note says how many
rules were encoded, how many approximated (salience) and how many left as
residue (Java only). When the rules only insert facts, the note adds that
`<name>_decision.le` beside it is the rule base's timeless reading. A ledger
(`<name>.ledger.md`) lists every rule with its verdict, and `sources/` keeps
the DRL. Run the program with **Misc ▸ Run in LPS**, which needs an LPS2
server; **File ▸ Show the Original…** shows the DRL. With no working memory
given, neither program has facts or a scenario: add an `initially` sentence
to the LPS program, or a scenario to the decision service.

**The twins among this IDE's examples.** `examples/migration/drools/` holds the
translator's output for five rule bases, one folder each (listed as *drools
twin: …*): `fire_alarm` and `honest_politician`, two examples of the Drools
distribution with their Java fact models, and `insurance`, `discount` and
`shipping`, the rule bases of `drl/` written as valid DRL. Each folder has
`<name>.le`, its ledger, and `sources/` with the DRL, the Java classes where
there are some, and the record of the Drools run (`<name>.drools.json`).
`discount` also has `discount_decision.le`. Unlike a `.drl` opened with File ▸
Open, a twin comes with the working memory Drools was run on (as `initially`)
and the steps its Java driver took between two runs of the rules (as a
scenario of events, ten cycles apart). Its last comment lists the working
memory Drools ended in.

Opening a `.le` twin in this IDE needs Logical English beside LPS2
(`LPS_LE2_LIB`); see [the editor guide](../guide/ide.md#logical-english).
`fire_alarm.le` runs to this timeline:

```
events/11   [fire_starts(kitchen),fire_starts(office)]
events/12   [sprinkler_turns_on(office),sprinkler_turns_on(kitchen),alarm_goes_on]
events/21   [fire_is_put_out(kitchen),fire_is_put_out(office)]
events/22   [sprinkler_turns_off(kitchen),sprinkler_turns_off(office),alarm_goes_off]
```

**View ▸ The original this was converted from** shows the files of the twin's
`sources/` folder. `discount_decision.le` is a timeless program
(`the target language is: prolog.`): open it in the Logical English editor to
query it.

### Which one to use

The two doors share one reading of DRL, so its limits (see [Traps](#traps))
apply to both. They differ in what they give you and where:

| | LPS2's own reader | The Logical English translator |
|---|---|---|
| Where | this IDE, the command line | the Logical English editor, with the InsurLE extensions |
| Output | LPS written form | Logical English for LPS, a ledger, and a decision service when the rules only insert |
| Words | predicate names (`alarm_goes_on`) | sentences (`an alarm goes on`) |
| A rule whose whole consequence is Java | an external action, `java_leaf(RuleName)`, with a warning | a residue block with the Java, for a person or the Contract Assistant |
| `insertLogical` | an ordinary insert | an intensional fluent |
| Salience | a comment above the rule and a warning | a comment and an *approximated* ledger entry; in the decision service, the order of an `otherwise` cascade |
| Checked against | expected firings written by hand | Drools itself |

**File ▸ Open…** of a `.drl` in this IDE always uses LPS2's own reader, even
where the translator is installed. To get the Logical English, open the file in
the Logical English editor. Use LPS2's reader to run a rule base quickly and to
work in LPS. Use the translator when the program is to be read by someone who
knows the business and not LPS, when you want a ledger of what was translated,
or when the rule base is a decision service.

## How Drools maps to LPS

| Drools | LPS (LPS2's reader) | Logical English for LPS (the translator) |
|---|---|---|
| `declare Fire room : String end`, or a Java class | a fluent over the fields that tell facts apart: `fire(_)` | `there is a fire in *a room*; known as fire.` |
| a boolean field (`Sprinkler.on`) | a fluent of its own: `sprinkler_on(_)` | `the sprinkler in *a room* is on; known as sprinkler_on.` |
| `rule "…" when P1 P2 then … end` | a reactive rule: `if P1 at T1, P2 at T1 then … from T1 to T2.` | `if … then …`, with no times |
| `not Alarm()` | `not alarm at T1` | `it is not the case that an alarm is on` |
| `exists Fire()` | `fire(A) at T1` | `there is a fire in a room` |
| `age > 25`, `!=`, `<`, `>=`, `<=` | a comparison in the conditions | the same |
| `insert(new Alarm(…))` | an event `alarm_starts` with `… initiates alarm` | `an alarm goes on` with `when an alarm goes on then an alarm is on.` |
| `retract(o)` / `delete(o)` | an event `order_ends(…)` with `… terminates order(…)` | `when … then it is not the case that …` |
| `modify(s) { setOn(true) }` | `sprinkler_turns_on(A)` with `… initiates sprinkler_on(A)` | `the sprinkler in *a room* turns on` |
| `modify(l) { colour = amber }` | `light_colour_becomes(B,amber)` with `updates green to amber in light(A,green)` | `the … of … becomes *a …*` |
| `insertLogical(new Hope())` | an ordinary insert: `hope_starts` with `… initiates hope` | an intensional fluent: `there is a hope at a time if …` |
| `salience 10` | a comment; the priority is recorded in the rule | a comment; the cascade order in the decision service |
| Java in the consequence | `java_leaf(RuleName)` and a warning | a comment on the rule, or a residue block |
| the facts in working memory | `initially …` (you add it) | `initially …` (from the Drools run, in the twins) |
| a Java driver inserting and deleting between runs | — | events in a scenario: `a fire starts in kitchen from 10 to 11.` |

The shipping rule base shows `modify` and `retract` together. Its DRL:

```
rule "an order with stock ships"
    when
        o : Order( id : id, state == placed )
        s : Stock( level == available )
    then
        insert(new Shipment(id))
        modify( o ) { state = shipped }
        modify( s ) { level = low }
end
```

is read by LPS2 as:

```
if   order(A,placed) at T1, stock(B,available) at T1
then shipment_starts(A) from T1 to T2, order_state_becomes(A,shipped) from T1 to T3, stock_level_becomes(B,low) from T1 to T4.

shipment_starts(A) from T1 to T2 initiates shipment(A).
order_state_becomes(A,shipped) from T1 to T2 updates placed to shipped in order(A,placed).
stock_level_becomes(A,low) from T1 to T2 updates available to low in stock(A,available).
```

The three events start at the same time and happen in the same cycle, as a DRL
consequence is one block.

### The world, not the working memory

In LPS an action or an event is something that happens in the world. It is not
an operation on a store. So both doors read a rule base as the world its working
memory describes. An insert of a `Fire` is a fire starting, a delete is its
ending, a `modify` that sets `on` to true is the sprinkler turning on, and a
`modify` of another field is that field becoming its new value.

A field that every fact of the rule base gives the same value tells no two
facts apart, and it is left out. In `fire-alarm.drl` every alarm is
`Alarm(yes)`, so the alarm is simply `alarm`, and the header says:

```
%   info: every alarm has active yes, so the field tells no two of them apart: the reading leaves it out
```

Drools' facts are objects, not named individuals. The reading invents no names
for them.

### Firing once

Drools fires a rule once for each match of its conditions. LPS fires a reactive
rule in every cycle in which its conditions hold. To keep the two in step, a
rule whose one change is an insert is guarded by the inserted fact not holding
yet: `not alarm at T1`, or in English `and it is not the case that an alarm is
on`. A rule that modifies or deletes what it matched stops matching by itself.

### Words and names: the wording table

A translator cannot know that an alarm "goes on". The defaults say plainly what
holds and what happens (`there is an alarm`, `an alarm starts`, `the alarm
ends`). A wording table, a file named `<name>.wording` beside the DRL, gives the
words and names a person would choose. `examples/migration/drools/drl/fire-alarm.wording`:

```
alarm: an alarm is on
alarm_starts: an alarm goes on; known as alarm_goes_on
alarm_ends: the alarm goes off; known as alarm_goes_off
```

Each line is keyed by the name the default reading gives a fluent or event,
then gives its words, with a place `*a …*` for each of its values, and
optionally `known as` the LPS name. A line with the wrong number of places, or
for something the rule base does not have, gets a warning and is ignored.
LPS2's reader uses the `known as` names; the Logical English translator uses
the words as well.

### Truth maintenance, salience and Java

**`insertLogical`** means that the fact holds as long as its support does. That
is an intensional fluent, and that is how the Logical English translator
writes it. From `honest_politician.le`:

```
there is a hope at a time if
    the politician called a name is honest at the time.
```

LPS2's own reader does not: it reads `insertLogical` as an ordinary insert
(`hope_starts from T1 to T2 initiates hope.`), so the fact stays after its
support has gone.

**Salience** is Drools' priority for deciding which rule fires first. LPS has
no such thing: it decides by constraints, not by priority. Both doors translate
the rule, keep the salience as a comment and warn that firing order may differ.

**Java** in a consequence is not translated. A statement LPS2's reader does
not recognise gets a warning naming the rule and the statement. A rule whose
whole consequence is Java (a `System.out.println`) becomes, in LPS, an external
action `java_leaf(RuleName)` with no causal law, and, in Logical English, a
residue block:

```
% RESIDUE rule_OK BEGIN: OK
% TODO: translate the fragment below by hand, or with the Contract Assistant (residue mode); it was not translated automatically
% the rule's whole consequence is Java (no working-memory change): not translated
%   java:
%   | System.out.println( "Everything is ok" );
% RESIDUE rule_OK END
```

### The decision-service reading

A rule base with no `modify` and no `delete` only concludes facts, as a
stateless decision service does. The translator then also writes a timeless
reading. The rules that insert one type become one rule, whose alternatives are
an `otherwise` cascade in salience order: the first that applies wins, which is
how salience is read in such a service. The refraction guard
(`not Discount( customer == customer )`) is left out, because a timeless rule
concludes once by itself. From `discount_decision.le`:

```
there is a discount for a customer with rate a rate if
    there is an order for the customer with size large
    and all of
        there is a customer called the customer with tier gold
        and the rate is equal to best
        otherwise it is not the case that there is a customer called the customer with tier gold
        and the rate is equal to standard.
```

Its scenario is the Drools run's working memory, and it `expects answers` the
facts Drools inserted.

## Traps

- **Facts in the reading's shape, not Drools' shape.** The facts you add must
  match the program's `fluents` line. A boolean field is a separate fluent, and
  a field left out is gone: for the fire alarm, write `sprinkler(kitchen)` for a
  sprinkler that is off, and `sprinkler(kitchen), sprinkler_on(kitchen)` for
  one that is on. `sprinkler(kitchen, false)` matches nothing, and the rules
  silently never fire. The example in the header,
  `initially customer(acme, gold), order(acme, large).`, is the same for every
  rule base; it is not written for yours.
- **A field compared with only one value may be dropped.** Without a working
  memory, the reader decides which fields tell facts apart from the constants
  the DRL itself uses. In `discount.drl` the rules only ever test `tier == gold`
  and `size == large`, so both fields are left out (the header says so in two
  `info:` lines). The second rule, meant for customers who are not gold, then
  reads `not customer(A) at T1`, which is a different rule. This happens with
  **File ▸ Open…** in both editors; the twins, built with the Drools run's
  facts, keep the fields. Read the `info:` lines, and if a field that matters
  was dropped, put it back by hand.
- **The wording file is used only from the example list and the command line.**
  **File ▸ Open…** in this IDE sends each chosen file on its own, so a
  `.wording` chosen with the `.drl` is not applied, and the defaults are used.
- **DRL is read as a subset.** The reader handles `declare`, `when`/`then`,
  patterns with `==`, the comparisons, `$` and `name :` bindings, fields of
  another pattern's fact (`s.room`), `not` and `exists`, `insert`,
  `insertLogical`, `retract`/`delete` and `modify` blocks. Other constructs
  are not all reported: `or` between patterns and `from accumulate( … )` are
  mistranslated without a warning, and rule attributes such as `no-loop` and
  `agenda-group` are ignored. Read the converted rules against the DRL.
- **`insertLogical` in LPS2's own reader.** It is read as an ordinary insert,
  without a warning: the fact is never withdrawn when its support goes, as it
  is in Drools. Use the Logical English translator, or replace the rule and its
  causal law by an intensional fluent (`hope at T if politician_honest at T.`).
- **A type with no `declare` has only the fields the rules mention.** Written
  against Java classes, a rule base does not say what fields its facts have.
  Opened on its own, `HonestPolitician.drl` gives `politician` with no
  arguments at all, because its rules never test the name (only its Java does),
  so every politician is the same fact. The twins were built with the Java fact
  model and keep the fields; with your own file, add a `declare` for each type
  before opening it.
- **Java is not evaluated.** A Java statement beside working-memory changes is
  a warning (LPS2) or a comment (Logical English) and does nothing when the
  program runs. A rule whose consequence is only Java does nothing observable.
  Values computed in Java (`new Flag(total)`) become constants.
- **Salience is not a firing order.** LPS fires every rule whose conditions
  hold in a cycle, together. A rule base whose result depends on which rule
  fires first can end in a different state. The five twins end where Drools
  ends because they do not depend on it.
- **Once per match is approximated by a condition.** The guard stops a rule
  that only inserts from firing again while what it inserted holds. If the fact
  is later deleted and the conditions still hold, the rule fires again, and a
  `println` in it would print again wherever its conditions keep holding.
- **Several rules can fire in one cycle.** In `honest_politician`, Drools
  corrupts the politicians one activation at a time; LPS corrupts all those that
  match in the same cycle. The final state is the same; the path is not.
- **Times.** A rule base has no clock. The LPS program runs for `maxTime(8)`
  cycles; the twins run for 30, with the driver's steps ten cycles apart. Raise
  the maximum time if your facts need longer.
- **The decision service needs its own check.** The `otherwise` cascade is right
  when the rules for one type start with the same conditions and differ in the
  rest. Look at the rule names listed in the comment above the cascade, in
  salience order, and at the scenario's expected answers. Opened from your own
  file, the decision service has an empty scenario: add the facts before
  running its tests.
- **Nothing goes back.** There is no export to DRL.

## See also

- In this documentation:
  - [Integrations](index.md), and [PDDL and LPS](pddl.md), the other file LPS2
    reads itself.
  - [Introducing LPS2, §19 Drools](../overview/introducing-lps2.md#19-drools).
  - [Using the editor: the menus](../guide/ide.md#the-menus) and
    [Logical English](../guide/ide.md#logical-english).
  - [Language reference: reactive rules](../reference/lps.md#6-reactive-rules),
    [causal laws](../reference/lps.md#5-causal-laws) and
    [intensional fluents](../reference/lps.md#8-intensional-fluents).
  - [Logical English for LPS: causal laws](../reference/le-for-lps.md#34-when--then---causal-laws)
    and [reactive rules](../reference/le-for-lps.md#35-if--then---reactive-rules).
  - [Glossary](../reference/glossary.md).
- In the Logical English editor:
  - [Integrations of Logical English: opening another system's file](https://le2.logicalcontracts.com/docs/user/integrations/index#opening-another-systems-file)
  - [Logical English for LPS](https://le2.logicalcontracts.com/docs/user/reference/lps-target)
  - [Using the editor](https://le2.logicalcontracts.com/docs/user/guide/editor)
- Drools:
  - [Apache KIE (Drools)](https://kie.apache.org/)
  - [DRL rule language reference](https://docs.drools.org/latest/drools-docs/drools/language-reference/index.html)
  - [Source code](https://github.com/apache/incubator-kie-drools)
