# Drools and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Drools is a production rule system for Java. Drools rules are written in DRL.
A rule has a `when` part, which matches facts held in a *working memory*, and
a `then` part, written in Java, which inserts, changes and deletes facts.
There are two ways to bring a DRL rule base into LPS (Logic Production
System), and both read DRL in the same way.

**LPS2's own reader** turns a `.drl` file into an LPS program in LPS's written
form. The reader is what **File ▸ Open…** uses on a `.drl` in this IDE (the
editor you write and run programs in), and the reader needs nothing else
installed.

**The Logical English translator** turns the same file into a Logical English
program for LPS. When a rule base only inserts facts, the translator also
writes a timeless decision service. The translator runs in the Logical English
editor, under **File ▸ Open…** or **File ▸ Import from Another System…**
there, on installations that have the InsurLE extensions, such as the hosted
service. What the translator made of five rule bases is among this IDE's own
examples.

Both doors go one way only: nothing writes DRL back out.

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
| DRL into LPS | **File ▸ Open…** in this IDE; the example list; `./lps drools` on the command line | `.drl` (with a `.wording` file beside it in the example list and on the command line, or chosen with it in File ▸ Open…) | an LPS program in the written form, with a header saying what did not carry over | the rules each rule base is expected to fire, cycle by cycle, written down from its documented behaviour, the newer ones checked against Drools, and what nine constructs read as (lpsPlus's `migration/drools/lps_drools_test.pl`, 18 cases and 11 readings) |
| DRL into Logical English for LPS | **File ▸ Open…** or **File ▸ Import from Another System…** in the Logical English editor (InsurLE extensions) | `.drl` | a Logical English program for LPS, a ledger, and `sources/` with the DRL | Drools itself: a Drools session run on the same working memory and the same driver steps must end in the working memory the program ends in under LPS2 (5 of 5) |
| DRL into a decision service | the same, when the rules only insert facts | `.drl` | `<name>_decision.le`, a timeless Logical English program | the facts Drools inserted, as the scenario's expected answers |

## How to use it

### LPS2's own reader

**From the example list.** **File ▸ Open example from server…** and the start
page both list the folder *Drools rule bases*
(`examples/migration/drools/drl/`): `discount.drl`, `fire-alarm.drl`,
`insurance.drl`, `shipping.drl` and `traffic-light.drl`. Choose one and it
opens already converted, in a tab named `<name>.lps`. `fire-alarm.drl` is read
together with `fire-alarm.wording`, the file beside it that says what the rule
base's facts and changes are called.

**From your own file.** Choose **File ▸ Open…** and pick the `.drl`. The
server converts the file and opens the result as `<name>.lps`. The status line
says how many conversion notes there were.

**What the header says.** Every converted program starts with a comment:

```
% Converted from fire-alarm.drl by LPS2 on 2026-09-16 15:59.
```

After that line comes a paragraph on how the DRL was read, then a reminder
that a rule base needs facts, and then, under `What did not carry over:`, one
line for each note the reader made: a salience, a Java statement, a field left
out, a rule not translated. The program itself follows. For `fire-alarm.drl`
the program is:

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
nothing until you give it some. Add an `initially` line, and write it with the
fluents from the program's `fluents` line, not with the Java objects (see
[Traps](#traps)). The note in the header shows the shape those fluents take,
with a name for each field:

```
initially fire(kitchen), sprinkler(kitchen).
```

Then run the program. In this example the sprinkler in the kitchen turns on
and the alarm goes on, both at cycle 2.

**Seeing the DRL.** **View ▸ The original this was converted from** shows the
file the tab was converted from. For an example opened from the list together
with a wording file, the menu item shows both files, each under its own name.

**On the command line.**

```sh
./lps drools examples/migration/drools/drl/fire-alarm.drl --facts "fire(kitchen), sprinkler(kitchen)"
```

The command prints its notes first, then the run, cycle by cycle. The command
uses a `.wording` file when one sits beside the `.drl`. `--max-time` changes
the default of 8 cycles.

### The Logical English translator

This translator reads the DRL with LPS2's own reader and then writes the
result out as Logical English, so that someone who does not read LPS can still
check it. The translator is part of the InsurLE extensions of the Logical
English installation.

**In the Logical English editor.** Choose **File ▸ Open…**, or **File ▸
Import from Another System…**, and pick the `.drl`. The editor opens
`<name>.le`, a program that declares `the target language is: lps.` A note
says how many rules were encoded, how many were approximated (salience, a rule
attribute, a value computed in Java) and how many were left as residue (a
consequence written only in Java, or a rule LPS2's reader does not translate).
The note also says how many other approximations the reading made (a type with
no `declare`, an `insertLogical` read as a plain insert). When the rules only
insert facts, the note adds that `<name>_decision.le`, beside the program, is
the rule base's timeless reading. A ledger (`<name>.ledger.md`) lists every
rule with the verdict it was given, and `sources/` keeps the DRL. Run the
program with **Misc ▸ Run in LPS**, which needs an LPS2 server, and see the
DRL with **File ▸ Show the Original…**. When you give no working memory,
neither program has facts or a scenario, so add an `initially` sentence to the
LPS program, or a scenario to the decision service.

**The twins among this IDE's examples.** `examples/migration/drools/` holds
what the translator made of five rule bases, one folder for each, listed as
*drools twin: …*. `fire_alarm` and `honest_politician` are two examples from
the Drools distribution, with their Java fact models. `insurance`, `discount`
and `shipping` are the rule bases of `drl/`, written as valid DRL. Each folder
holds `<name>.le`, its ledger, and `sources/` with the DRL, the Java classes
where there are any, and the record of the Drools run
(`<name>.drools.json`). `discount` also has `discount_decision.le`. A twin
brings more with it than a `.drl` opened with File ▸ Open does: the working
memory Drools was run on, written as `initially`, and the steps the Java
driver took between two runs of the rules, written as a scenario of events ten
cycles apart. The twin's last comment lists the working memory Drools ended
in.

Opening a `.le` twin in this IDE needs Logical English beside LPS2
(`LPS_LE2_LIB`); see [the editor guide](../guide/ide.md#logical-english).
`fire_alarm.le` runs to this timeline:

```
events/11   [fire_starts(kitchen),fire_starts(office)]
events/12   [sprinkler_turns_on(office),sprinkler_turns_on(kitchen),alarm_goes_on]
events/21   [fire_is_put_out(kitchen),fire_is_put_out(office)]
events/22   [sprinkler_turns_off(kitchen),sprinkler_turns_off(office),alarm_goes_off]
```

**View ▸ The original this was converted from** shows the files in the twin's
`sources/` folder. `discount_decision.le` is a timeless program
(`the target language is: prolog.`), so open it in the Logical English editor
to put questions to it.

### Which one to use

Both doors read DRL in the same way, so the limits of that reading (see
[Traps](#traps)) apply to both. The doors differ in what they give you, and in
where they run:

| | LPS2's own reader | The Logical English translator |
|---|---|---|
| Where | this IDE, the command line | the Logical English editor, with the InsurLE extensions |
| Output | LPS written form | Logical English for LPS, a ledger, and a decision service when the rules only insert |
| Words | predicate names (`alarm_goes_on`) | sentences (`an alarm goes on`) |
| Java in a consequence | an external action, `java_leaf(RuleName)`, in its place, with a warning | a comment on the rule; a residue block with the Java when the consequence is only Java |
| `insertLogical` | an intensional fluent | an intensional fluent |
| `accumulate` | an aggregate over the state | an aggregate sentence (`a total is the sum of each a value such that …`) |
| `not` over a pattern with a comparison | the negation of both | a residue block with the DRL (see [Traps](#traps)) |
| Rule attributes | `no-loop` a condition, `enabled false` the rule left out; the others a warning each | the same, and a comment on the rule and an *approximated* ledger entry for each attribute not translated |
| Salience | a comment above the rule and a warning | a comment and an *approximated* ledger entry; in the decision service, the order of an `otherwise` cascade |
| Checked against | expected firings written by hand | Drools itself |

In this IDE, **File ▸ Open…** on a `.drl` always uses LPS2's own reader, even
where the translator is installed. To get the Logical English, open the file
in the Logical English editor instead. Use LPS2's reader to run a rule base
quickly and to work in LPS. Use the translator when the program has to be read
by someone who knows the business but not LPS, when you want a ledger of what
was translated, or when the rule base is a decision service.

## How Drools maps to LPS

| Drools | LPS (LPS2's reader) | Logical English for LPS (the translator) |
|---|---|---|
| `declare Fire room : String end`, or a Java class | a fluent over the fields that tell facts apart: `fire(_)` | `there is a fire in *a room*; known as fire.` |
| a boolean field (`Sprinkler.on`) | a fluent of its own: `sprinkler_on(_)` | `the sprinkler in *a room* is on; known as sprinkler_on.` |
| `rule "…" when P1 P2 then … end` | a reactive rule: `if P1 at T1, P2 at T1 then … from T1 to T2.` | `if … then …`, with no times |
| `not Alarm()` | `not alarm at T1` | `it is not the case that an alarm is on` |
| `not Person( age > 65 )` | `not [person(A,B) at T1, B>65] at T1` | a residue block |
| `A() or B()`; `not( A() or B() )`; `age < 18 \|\| age > 65` | one rule for each alternative, as Drools makes one subrule for each; `not A` and `not B` | the same |
| `$t : Number( intValue > 100 ) from accumulate( Order( $v : value ), sum( $v ) )`, or `accumulate( …; $t : sum( $v ); $t > 100 )` | `findall(V, [holds(order(_,V), T1)], L) at T1, sum_list(L, T), T > 100` (`sum`, `count`, `min`, `max`) | `a total is the sum of each a value such that there is an order with id an id and value the value and the total > 100` |
| `exists Fire()` | `fire(A) at T1` | `there is a fire in a room` |
| `age > 25`, `!=`, `<`, `>=`, `<=` | a comparison in the conditions | the same |
| `insert(new Alarm(…))` | an event `alarm_starts` with `… initiates alarm` | `an alarm goes on` with `when an alarm goes on then an alarm is on.` |
| `retract(o)` / `delete(o)` | an event `order_ends(…)` with `… terminates order(…)` | `when … then it is not the case that …` |
| `modify(s) { setOn(true) }` | `sprinkler_turns_on(A)` with `… initiates sprinkler_on(A)` | `the sprinkler in *a room* turns on` |
| `modify(l) { colour = amber }` | `light_colour_becomes(B,amber)` with `updates green to amber in light(A,green)` | `the … of … becomes *a …*` |
| a value computed in Java: `new Big( $total.intValue() )`, `setCount( $c.getCount() + 1 )`, `new Label( $p.getName() )` | the variable, or a goal computing it in the conditions: `B is A+1` | `a second count = count + 1` |
| a value the reader cannot compute (`$p.getName().toUpperCase()`, `Math.max(…)`, a string concatenation) | the change is left out: `java_leaf(RuleName)` and a warning | a comment on the rule, or a residue block |
| `no-loop` | the condition that the rule's change is not made already: `B \= 100` for `setBalance( 100 )` | `and the balance is different from 100` |
| `enabled false` | the rule is left out, with a note | a comment saying so |
| `lock-on-active`; `agenda-group`, `activation-group`, `ruleflow-group`, `auto-focus`; `date-effective`, `date-expires`, `calendars`; `timer`, `duration` | read as `no-loop`; the rest ignored: the rule is read as always active, at once, on every match; a warning each | the same, named in the rule's comment and in its ledger entry |
| `insertLogical(new Hope())` | an intensional fluent: `hope at T1 if politician_honest(A) at T1.` | an intensional fluent: `there is a hope at a time if …` |
| `salience 10` | a comment; the priority is recorded in the rule | a comment; the cascade order in the decision service |
| Java in the consequence | the action `java_leaf(RuleName)` beside the rule's events, and a warning | a comment on the rule, or a residue block |
| `eval`, `forall`, `collect`, `from`, `average`, a constraint the reader does not know | the rule is left out, with a warning | a residue block with the DRL and the reason |
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

In LPS an action or an event is something that happens in the world, and not
an operation on a store of facts. Both doors therefore read a rule base as the
world its working memory describes. Inserting a `Fire` is a fire starting.
Deleting the `Fire` is the fire ending. A `modify` that sets `on` to true is
the sprinkler turning on, and a `modify` of any other field is that field
taking its new value.

A field that every fact of the rule base gives the same value tells no two
facts apart, so the reading leaves that field out. In `fire-alarm.drl` every
alarm is `Alarm(yes)`, so the alarm is simply `alarm`, and the header says:

```
%   info: every alarm has active yes, so the field tells no two of them apart: the reading leaves it out
```

Drools' facts are objects rather than named individuals, and the reading
invents no names for them.

### Firing once

Drools fires a rule once for each match of the rule's conditions. LPS fires a
reactive rule in every cycle where the rule's conditions hold. To keep the two
in step, the reading guards a rule whose only change is an insert with the
condition that the inserted fact does not hold yet: `not alarm at T1`, or in
English `and it is not the case that an alarm is on`. A rule that modifies or
deletes what it matched stops matching of its own accord.

### Words and names: the wording table

A translator cannot know that an alarm "goes on". The default words simply say
what holds and what happens (`there is an alarm`, `an alarm starts`, `the
alarm ends`). A wording table — a file named `<name>.wording` sitting beside
the DRL — supplies the words and the names a person would choose instead. Here
is `examples/migration/drools/drl/fire-alarm.wording`:

```
alarm: an alarm is on
alarm_starts: an alarm goes on; known as alarm_goes_on
alarm_ends: the alarm goes off; known as alarm_goes_off
```

Each line starts with the name the default reading gives a fluent or an event.
Then come the words for that fluent or event, with a place `*a …*` for each of
its values, and, if you wish, `known as` followed by the LPS name. A line with
the wrong number of places, or a line for something the rule base does not
have, gets a warning and is then ignored. LPS2's reader uses only the `known
as` names; the Logical English translator uses the words as well.

### Truth maintenance, salience and Java

**`insertLogical`** means that the fact holds for as long as whatever supports
it holds. An intensional fluent says exactly that, and an intensional fluent
is how both doors read `insertLogical`. LPS2's reader writes `hope at T1 if
politician_honest(A) at T1.`, and the Logical English translator writes this,
in `honest_politician.le`:

```
there is a hope at a time if
    the politician called a name is honest at the time.
```

The fact then goes the moment its conditions stop holding, just as Drools
withdraws it. An intensional fluent cannot also be started or ended by an
event. So where another rule inserts, modifies or deletes facts of that type,
or where the working memory holds such facts from the start, the reading
treats `insertLogical` as an ordinary insert, and warns that the fact will not
be withdrawn.

**Salience** is the priority Drools uses to decide which rule fires first. LPS
has nothing of the kind, because LPS decides by constraints rather than by
priority. Both doors translate the rule, keep the salience as a comment, and
warn that the order of firing may differ.

**Rule attributes** say when a rule may fire. Most of them depend on things
LPS does not have: an agenda with groups and a focus, a calendar, a clock, and
a run of the rules that begins and ends. Each attribute was checked against
Drools itself, and each is read as follows.

- `enabled false`: Drools never fires the rule, so the program leaves it out,
  with a note (a comment in Logical English).
- `no-loop`: Drools does not activate the rule again because of the rule's own
  change. The reading adds the condition that the change has not been made
  already. For `modify( $a ) { setBalance( 100 ) }` on `Account( balance >=
  100 )` that condition is `B \= 100` (`the balance is different from 100`),
  so the rule caps the balance once, as it does in Drools — where, without
  `no-loop`, the two would fire for ever. A change worked out from the old
  value (`setCount( $c.getCount() + 1 )`) has never been made already, so
  there the reading does not translate `no-loop`, and a warning says so.
- `lock-on-active` also holds back activations that other rules' changes
  create during one run of the rules. The reading treats `lock-on-active` as
  `no-loop`, with a warning.
- `agenda-group` (other than `"MAIN"`) and `ruleflow-group`: Drools fires the
  rule only while Java, or a process, gives the rule's group the focus, and
  the rule base on its own never does that. `auto-focus` gives the focus, in
  an order of its own. `activation-group` lets one activation of the whole
  group fire and cancels the rest. `date-effective`, `date-expires` and
  `calendars` are windows in the calendar; `timer` and `duration` fire the
  rule later, on a clock. None of these is translated. The rule is read as
  always active, firing at once on every match, and each of them gets a
  warning of its own.
- `dialect` changes nothing in the reading, and a `salience` that is an
  expression is read as no salience, with a warning.

**Java** in a consequence is not translated. When LPS2's reader does not
recognise a statement, the reader gives a warning naming the rule and the
statement, and the rule performs the external action `java_leaf(RuleName)` in
that statement's place. The action has no causal law and changes nothing, but
it shows in the run where the Java would have run. The reader does read a
value inside a change when the value is a variable, when it fetches a field of
a bound variable (`$p.getName()`, `$p.isOn()`, `$total.intValue()`), or when
it is arithmetic over those and over numbers. So `modify( $c ) { setCount(
$c.getCount() + 1 ) }` works the new count out in the rule's conditions. The
reader never turns any other value (`$p.getName().toUpperCase()`, `Math.max(
a, b )`, `"Dear " + $name`) into a fixed value. It treats the whole statement
as Java, leaves the statement out, and warns, naming the value. In Logical
English the Java becomes a comment on the rule, and a rule whose whole
consequence is Java — a `System.out.println`, say — becomes a residue block:

```
% RESIDUE rule_OK BEGIN: OK
% TODO: translate the fragment below by hand, or with the Contract Assistant (residue mode); it was not translated automatically
% the rule's whole consequence is Java (no working-memory change): not translated
%   java:
%   | System.out.println( "Everything is ok" );
% RESIDUE rule_OK END
```

### The decision-service reading

A rule base with no `modify` and no `delete` only draws conclusions, which is
what a decision service does — a decision service being one that keeps no
state between questions. For such a rule base the translator also writes a
timeless reading. All the rules that insert facts of one type become a single
rule, and their alternatives become an `otherwise` cascade in salience order:
the first alternative that applies wins, which is how salience is read in a
service of that kind. The guard against firing twice
(`not Discount( customer == customer )`) is left out, because a timeless rule
draws its conclusion once in any case. From `discount_decision.le`:

```
there is a discount for a customer with rate a rate if
    there is an order for the customer with size large
    and all of
        there is a customer called the customer with tier gold
        and the rate is equal to best
        otherwise it is not the case that there is a customer called the customer with tier gold
        and the rate is equal to standard.
```

The program's scenario is the working memory of the Drools run, and the
program `expects answers` the facts Drools inserted.

## Traps

- **Facts in the reading's shape, not Drools' shape.** The facts you add must
  match the program's `fluents` line. A true-or-false field becomes a fluent
  of its own, and a field that was left out is simply gone. For the fire
  alarm, write `sprinkler(kitchen)` for a sprinkler that is off, and
  `sprinkler(kitchen), sprinkler_on(kitchen)` for one that is on.
  `sprinkler(kitchen, false)` matches nothing at all, and the rules then never
  fire, with nothing said about it. The header shows the shape of this rule
  base's own facts (`initially customer(Name, Tier), order(Customer, Size),
  …`), so replace each capitalised name there with a value.
- **A field every fact gives one value is left out.** The reader leaves out a
  field that tells no two facts apart. When you give no working memory, the
  reader decides that only for a type whose facts the rules insert themselves
  (every alarm of `fire-alarm.drl` is `Alarm(yes)`, so the alarm is simply
  `alarm`). For any other type the reader keeps a field that a condition
  compares with a fixed value (`tier == gold`), because that type's facts come
  from outside the rule base. When you do give a working memory — in the
  twins, or with `--facts` on the command line — the reader decides from the
  facts themselves: if every customer you give is gold, `tier` goes. The
  header's `info:` lines say which fields went.
- **The wording file must be chosen with its rule file.** In **File ▸ Open…**,
  select `<name>.drl` and `<name>.wording` together. A `.drl` opened on its
  own uses the default words, and a `.wording` opened on its own opens
  nothing.
- **DRL is read as a subset, and what is left out is said.** The reader
  handles `declare`, `when`/`then`, patterns with `==`, the comparisons, `$`
  and `name :` bindings, fields of another pattern's fact (`s.room`), `not`,
  `exists`, `or` (between patterns, and `||` between constraints), `&&`,
  `accumulate` with `sum`, `count`, `min` or `max`, `insert`,
  `insertLogical`, `retract`/`delete` and `modify` blocks. The reader leaves
  out of the program any rule with another kind of condition (`eval`,
  `forall`, `collect`, `from` without `accumulate`, `average`, `not` over
  several patterns, the prefix form `(or …)`, a constraint the reader cannot
  read), and gives a warning naming that condition; the Logical English
  translator keeps such a rule's DRL in a residue block. Of the rule
  attributes, the reader translates `no-loop` and `enabled false`. The others
  (`agenda-group`, `activation-group`, a timer, a calendar window, …) each get
  a warning, and the rule is read as if it could always fire (see
  [Truth maintenance, salience and Java](#truth-maintenance-salience-and-java)).
- **A reading LPS2 runs that Logical English for LPS does not write yet.**
  A `not` over a pattern with a comparison (`not Person( age > 65 )`) runs in
  LPS2's own reader. Logical English for LPS has no sentence for such a
  condition, so the translator writes that rule as a residue block holding its
  DRL. (An `accumulate`, by contrast, is written as an aggregate sentence, and
  compiles back to the reader's own `findall`.)
- **`insertLogical` of a type that also changes otherwise** becomes an
  ordinary insert, with a warning, and the fact is then not withdrawn when
  what supported it goes.
- **A type with no `declare` has only the fields the rules mention.** A rule
  base written against Java classes does not say what fields its facts have.
  The reader takes the fields from the constraints, from references in other
  patterns (`s.room`) and from the Java in the consequences
  (`politician.getName()` is the politician's name). The reader then warns
  that two facts differing only in a field no rule mentions are read as one
  fact. The twins were built with the Java fact model beside them; with a file
  of your own, add a `declare` for each type the warning names.
- **Java is not carried out.** A Java statement becomes a warning plus the
  action `java_leaf(RuleName)` in LPS2, or a comment in Logical English, and
  changes nothing when the program runs. A value the reader cannot work out
  (`$p.getName().toUpperCase()`) makes its whole change Java: the reading
  leaves that change out, with a warning, rather than make it with a wrong
  value.
- **`no-loop` becomes a condition, not Drools' own record-keeping.** The rule
  does not fire while its change has already been made. Drools does fire such
  a rule once on a fact where the change is already made, a modify that
  changes nothing; the reading does not fire it, and the state ends the same
  either way.
- **Salience is not a firing order.** LPS fires every rule whose conditions
  hold in a cycle, and fires them together. A rule base whose result depends
  on which rule fires first can therefore end in a different state. The five
  twins end where Drools ends, because none of them depends on the order.
- **Firing once per match is approximated by a condition.** The guard stops a
  rule that only inserts from firing again while what it inserted still holds.
  If that fact is later deleted and the rule's conditions still hold, the rule
  fires again, and a `println` inside the rule would print again wherever the
  conditions keep holding.
- **Several rules can fire in one cycle.** In `honest_politician`, Drools
  corrupts the politicians one activation at a time, while LPS corrupts every
  politician that matches, all in the same cycle. The final state is the same;
  the path to it is not.
- **Times.** A rule base has no clock. The LPS program runs for `maxTime(8)`
  cycles, and the twins run for 30, with the driver's steps ten cycles apart.
  Raise the maximum time when your facts need longer.
- **The decision service needs its own check.** The `otherwise` cascade is
  right when the rules for one type begin with the same conditions and differ
  only afterwards. Look at the rule names listed in the comment above the
  cascade, in salience order, and at the answers the scenario expects. When
  you open a decision service made from a file of your own, its scenario is
  empty, so add the facts before running its tests.
- **Nothing goes back.** There is no export to DRL.

## See also

- In this documentation:
  - [Integrations](index.md), and [PDDL and LPS](pddl.md), the other file LPS2
    reads itself.
  - [Introducing LPS2, §17 Drools](../overview/introducing-lps2.md#17-drools).
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
