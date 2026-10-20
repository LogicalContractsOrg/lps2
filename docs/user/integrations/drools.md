# Drools and LPS

*Kind: integration guide · Audience: users · Status: current (2026-10-18)*

Drools is a production rule system for Java. A production rule system is a program
that changes a set of facts with "when … then …" rules. You write Drools rules in
DRL, the Drools Rule Language. A rule has a `when` part and a `then` part. The `when`
part matches facts in a *working memory*. The working memory is the store of facts
that Drools keeps. The `then` part is in Java, and it inserts, changes and deletes
facts.

You can bring a DRL rule base into LPS (Logic Production System) in two ways. A rule
base is a set of rules. The two ways read DRL in the same way.

**LPS2's own reader** changes a `.drl` file into an LPS program in the written form
of LPS. **File ▸ Open…** in this IDE uses the reader on a `.drl` file. The IDE
(Integrated Development Environment) is the editor where you write and run programs.
The reader does not need other software.

**The Logical English translator** changes the same file into a Logical English
program for LPS. When a rule base only inserts facts, the translator also writes a
timeless decision service. A decision service is a program that gives a decision for
each question and keeps no state between questions. The translator operates in the
Logical English editor, under **File ▸ Open…** or **File ▸ Import from Another
System…** in that editor. The translator is available only on installations that
have the Logical English Translators, for example the hosted service. The examples of
this IDE include the result of the translator for five rule bases.

The two ways go in one direction only: no part of the system writes DRL.

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
| DRL into LPS | **File ▸ Open…** in this IDE; the example list; `./lps drools` on the command line | `.drl` (with a `.wording` file next to it in the example list and on the command line; in File ▸ Open…, select the two files together) | an LPS program in the written form, with a header that tells what the reader did not translate | the rules that each rule base must fire, cycle by cycle. A person wrote these rules from the documented behaviour of the rule base. The newer rules are checked against Drools. Also the readings of nine constructs (`migration/drools/lps_drools_test.pl` in lpsPlus, 18 cases and 11 readings) |
| DRL into Logical English for LPS | **File ▸ Open…** or **File ▸ Import from Another System…** in the Logical English editor (Logical English Translators) | `.drl` | a Logical English program for LPS, a ledger, and `sources/` with the DRL | Drools: a Drools session runs on the same working memory with the same driver steps. The session must end in the same working memory as the program under LPS2 (5 of 5) |
| DRL into a decision service | the same, when the rules only insert facts | `.drl` | `<name>_decision.le`, a timeless Logical English program | the facts that Drools inserted, as the expected answers of the scenario |

## How to use it

### LPS2's own reader

**From the example list.** **File ▸ Open example from server…** and the start page
both show the folder *Drools rule bases* (`examples/migration/drools/drl/`). The
folder contains `discount.drl`, `fire-alarm.drl`, `insurance.drl`, `shipping.drl`
and `traffic-light.drl`. Select one. The file opens after conversion, in a tab with
the name `<name>.lps`. The reader reads `fire-alarm.drl` together with
`fire-alarm.wording`. That file is next to the DRL file, and it gives the names of
the facts and changes of the rule base.

**From your own file.** Do these steps:

1. Select **File ▸ Open…**.
2. Select the `.drl` file.

The server converts the file and opens the result as `<name>.lps`. The status line
tells how many conversion notes there are.

**What the header says.** Each converted program starts with a comment:

```
% Converted from fire-alarm.drl by LPS2 on 2026-09-16 15:59.
```

After that line, there is a paragraph about how the reader read the DRL. Then there
is a reminder that a rule base needs facts. Then, under `What did not carry over:`,
there is one line for each note of the reader. A note can be about a salience, a Java
statement, a field that the reader did not keep, or a rule that the reader did not
translate. The program follows. For `fire-alarm.drl`, the program is:

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

The program ends with `maxTime(8).`

**Adding the facts.** A DRL file has rules but no facts. Thus the program does
nothing until you give it facts. Add an `initially` line. Write the line with the
fluents from the `fluents` line of the program, not with the Java objects (refer to
[Traps](#traps)). A fluent is a fact that can change with time. The note in the
header shows the form of these fluents, with a name for each field:

```
initially fire(kitchen), sprinkler(kitchen).
```

Then run the program. In this example, the sprinkler in the kitchen turns on and the
alarm goes on. The two events occur at cycle 2.

**Seeing the DRL.** **View ▸ The original this was converted from** shows the file
that the reader converted for the tab. Sometimes you open an example from the list
together with a wording file. Then the menu item shows the two files, each under its
own name.

**On the command line.**

```sh
./lps drools examples/migration/drools/drl/fire-alarm.drl --facts "fire(kitchen), sprinkler(kitchen)"
```

The command first prints its notes. Then it prints the run, cycle by cycle. The
command uses a `.wording` file when that file is next to the `.drl` file.
`--max-time` changes the default of 8 cycles.

### The Logical English translator

This translator reads the DRL with the reader of LPS2. Then it writes the result as
Logical English. Thus a person who cannot read LPS can still examine the result. The
translator is part of the Logical English Translators. The Logical English
installation must have the Logical English Translators.

**In the Logical English editor.** Do these steps:

1. Select **File ▸ Open…** or **File ▸ Import from Another System…**.
2. Select the `.drl` file.

The editor opens `<name>.le`. This program declares
`the target language is: lps.` A note tells these numbers:

- How many rules the translator encoded.
- How many rules it approximated (a salience, a rule attribute, a value that Java
  calculates).
- How many rules it kept as residue. Residue is a part that the translator did not
  translate: a consequence that is only in Java, or a rule that the reader of LPS2
  does not translate.
- How many other approximations the reading made (a type with no `declare`, an
  `insertLogical` read as a plain insert).

When the rules only insert facts, the note also tells you about
`<name>_decision.le`. That file is next to the program, and it is the timeless
reading of the rule base. A ledger (`<name>.ledger.md`) gives each rule with its
verdict. The folder `sources/` keeps the DRL. To run the program, select **Misc ▸ Run
in LPS**. This command needs an LPS2 server. To see the DRL, select **File ▸ Show the
Original…**. When you give no working memory, the two programs have no facts and no
scenario. Thus add an `initially` sentence to the LPS program, or a scenario to the
decision service.

**The twins among this IDE's examples.** A twin is the result of the translator for
one rule base. The folder `examples/migration/drools/` contains the twins of five rule
bases, one folder for each twin. The example list shows them as *drools twin: …*.
`fire_alarm` and `honest_politician` are two examples from the Drools distribution,
with their Java fact models. `insurance`, `discount` and `shipping` are the rule bases
of `drl/`, written as valid DRL. Each folder contains `<name>.le`, its ledger, and
`sources/`. The `sources/` folder contains the DRL, the Java classes (if there are
Java classes), and the record of the Drools run (`<name>.drools.json`). `discount`
also has `discount_decision.le`.

A twin contains more than a `.drl` file that you open with File ▸ Open. It contains
the working memory of the Drools run, written as `initially`. It also contains the
steps of the Java driver between two runs of the rules. These steps are a scenario of
events, ten cycles apart. The last comment of the twin gives the working memory at
the end of the Drools run.

To open a `.le` twin in this IDE, you need Logical English next to LPS2
(`LPS_LE2_LIB`). Refer to [the editor guide](../guide/ide.md#logical-english).
`fire_alarm.le` runs to this timeline:

```
events/11   [fire_starts(kitchen),fire_starts(office)]
events/12   [sprinkler_turns_on(office),sprinkler_turns_on(kitchen),alarm_goes_on]
events/21   [fire_is_put_out(kitchen),fire_is_put_out(office)]
events/22   [sprinkler_turns_off(kitchen),sprinkler_turns_off(office),alarm_goes_off]
```

**View ▸ The original this was converted from** shows the files in the `sources/`
folder of the twin. `discount_decision.le` is a timeless program
(`the target language is: prolog.`). To ask questions of this program, open it in the
Logical English editor.

### Which one to use

The two ways read DRL in the same way. Thus the limits of that reading (refer to
[Traps](#traps)) apply to the two ways. The two ways are different in what they give
you, and in where they operate:

| | LPS2's own reader | The Logical English translator |
|---|---|---|
| Where | this IDE, the command line | the Logical English editor, with the Logical English Translators |
| Output | the written form of LPS | Logical English for LPS, a ledger, and a decision service when the rules only insert |
| Words | predicate names (`alarm_goes_on`) | sentences (`an alarm goes on`) |
| Java in a consequence | an external action, `java_leaf(RuleName)`, in place of the Java, with a warning | a comment on the rule; a residue block with the Java when the consequence is only Java |
| `insertLogical` | an intensional fluent | an intensional fluent |
| `accumulate` | an aggregate over the state | an aggregate sentence (`a total is the sum of each a value such that …`) |
| `not` over a pattern with a comparison | the negation of the pattern and the comparison | a residue block with the DRL (refer to [Traps](#traps)) |
| Rule attributes | `no-loop` becomes a condition; with `enabled false`, the reader does not keep the rule; each other attribute gets a warning | the same; also a comment on the rule and an *approximated* ledger entry for each attribute that the translator does not translate |
| Salience | a comment above the rule, and a warning | a comment and an *approximated* ledger entry; in the decision service, the order of the rules, and the conditions that a rule of lower salience leaves to a rule of higher salience |
| Checked against | expected firings that a person wrote | Drools |

In this IDE, **File ▸ Open…** on a `.drl` file always uses the reader of LPS2, also
where the translator is installed. To get the Logical English, open the file in the
Logical English editor. Use the reader of LPS2 to run a rule base quickly and to work
in LPS. Use the translator in these conditions:

- A person who knows the business, but does not know LPS, must read the program.
- You want a ledger of what the translator translated.
- The rule base is a decision service.

## How Drools maps to LPS

| Drools | LPS (LPS2's reader) | Logical English for LPS (the translator) |
|---|---|---|
| `declare Fire room : String end`, or a Java class | a fluent over the fields that make facts different: `fire(_)` | `there is a fire in *a room*; known as fire.` |
| a boolean field (`Sprinkler.on`) | a separate fluent: `sprinkler_on(_)` | `the sprinkler in *a room* is on; known as sprinkler_on.` |
| `rule "…" when P1 P2 then … end` | a reactive rule: `if P1 at T1, P2 at T1 then … from T1 to T2.` | `if … then …`, with no times |
| `not Alarm()` | `not alarm at T1` | `it is not the case that an alarm is on` |
| `not Person( age > 65 )` | `not [person(A,B) at T1, B>65] at T1` | a residue block |
| `A() or B()`; `not( A() or B() )`; `age < 18 \|\| age > 65` | one rule for each alternative, because Drools makes one subrule for each alternative; `not A` and `not B` | the same |
| `$t : Number( intValue > 100 ) from accumulate( Order( $v : value ), sum( $v ) )`, or `accumulate( …; $t : sum( $v ); $t > 100 )` | `findall(V, [holds(order(_,V), T1)], L) at T1, sum_list(L, T), T > 100` (`sum`, `count`, `min`, `max`) | `a total is the sum of each a value such that there is an order with id an id and value the value and the total > 100` |
| `exists Fire()` | `fire(A) at T1` | `there is a fire in a room` |
| `age > 25`, `!=`, `<`, `>=`, `<=` | a comparison in the conditions | the same |
| `insert(new Alarm(…))` | an event `alarm_starts` with `… initiates alarm` | `an alarm goes on` with `when an alarm goes on then an alarm is on.` |
| `retract(o)` / `delete(o)` | an event `order_ends(…)` with `… terminates order(…)` | `when … then it is not the case that …` |
| `modify(s) { setOn(true) }` | `sprinkler_turns_on(A)` with `… initiates sprinkler_on(A)` | `the sprinkler in *a room* turns on` |
| `modify(l) { colour = amber }` | `light_colour_becomes(B,amber)` with `updates green to amber in light(A,green)` | `the … of … becomes *a …*` |
| a value that Java calculates: `new Big( $total.intValue() )`, `setCount( $c.getCount() + 1 )`, `new Label( $p.getName() )` | the variable, or a goal in the conditions that calculates the value: `B is A+1` | `a second count = count + 1` |
| a value that the reader cannot calculate (`$p.getName().toUpperCase()`, `Math.max(…)`, a string concatenation) | the reader does not keep the change: `java_leaf(RuleName)` and a warning | a comment on the rule, or a residue block |
| `no-loop` | the condition that the change of the rule is not already done: `B \= 100` for `setBalance( 100 )` | `and the balance is different from 100` |
| `enabled false` | the reader does not keep the rule, and writes a note | a comment that tells this |
| `lock-on-active`; `agenda-group`, `activation-group`, `ruleflow-group`, `auto-focus`; `date-effective`, `date-expires`, `calendars`; `timer`, `duration` | read as `no-loop`; the reader ignores the others: it reads the rule as always active, immediately, on each match; a warning for each | the same, named in the comment of the rule and in its ledger entry |
| `insertLogical(new Hope())` | an intensional fluent: `hope at T1 if politician_honest(A) at T1.` | an intensional fluent: `there is a hope at a time if …` |
| `salience 10` | a comment; the rule records the priority | a comment; the order of the rules in the decision service |
| Java in the consequence | the action `java_leaf(RuleName)` next to the events of the rule, and a warning | a comment on the rule, or a residue block |
| `eval`, `forall`, `collect`, `from`, `average`, a constraint that the reader does not know | the reader does not keep the rule, and gives a warning | a residue block with the DRL and the reason |
| the facts in working memory | `initially …` (you add it) | `initially …` (from the Drools run, in the twins) |
| a Java driver that inserts and deletes between runs | — | events in a scenario: `a fire starts in kitchen from 10 to 11.` |

The shipping rule base shows `modify` and `retract` together. This is its DRL:

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

LPS2 reads that DRL as:

```
if   order(A,placed) at T1, stock(B,available) at T1
then shipment_starts(A) from T1 to T2, order_state_becomes(A,shipped) from T1 to T3, stock_level_becomes(B,low) from T1 to T4.

shipment_starts(A) from T1 to T2 initiates shipment(A).
order_state_becomes(A,shipped) from T1 to T2 updates placed to shipped in order(A,placed).
stock_level_becomes(A,low) from T1 to T2 updates available to low in stock(A,available).
```

The three events start at the same time and occur in the same cycle, because a DRL
consequence is one block.

### The world, not the working memory

In LPS, an action or an event is a thing that occurs in the world. It is not an
operation on a store of facts. Thus the two ways read a rule base as the world that
its working memory describes. The insertion of a `Fire` is the start of a fire. The
deletion of the `Fire` is the end of the fire. A `modify` that sets `on` to true is
the sprinkler that turns on. A `modify` of a different field is the change of that
field to its new value.

Sometimes each fact of the rule base gives the same value to a field. That field does
not make two facts different. Thus the reading does not keep that field. In
`fire-alarm.drl`, each alarm is `Alarm(yes)`. Thus the alarm is only `alarm`, and the
header says:

```
%   info: every alarm has active yes, so the field tells no two of them apart: the reading leaves it out
```

The facts of Drools are objects, not named individuals. The reading does not make
names for them.

### Firing once

Drools fires a rule one time for each match of the conditions of the rule. LPS fires a
reactive rule in each cycle where the conditions of the rule are true. A reactive rule
is a rule that does an action when its conditions are true. To keep the two systems
in agreement, the reading adds a condition to a rule whose only change is an insert.
The condition is that the inserted fact is not true yet: `not alarm at T1`, or in
English `and it is not the case that an alarm is on`. A rule that changes or deletes
the fact that it matched stops matching without help.

### Words and names: the wording table

A translator cannot know that an alarm "goes on". The default words only tell what is
true and what occurs (`there is an alarm`, `an alarm starts`, `the alarm ends`). A
wording table gives the words and the names that a person would select. The wording
table is a file with the name `<name>.wording`, next to the DRL file. This is
`examples/migration/drools/drl/fire-alarm.wording`:

```
alarm: an alarm is on
alarm_starts: an alarm goes on; known as alarm_goes_on
alarm_ends: the alarm goes off; known as alarm_goes_off
```

Each line starts with the name that the default reading gives to a fluent or an
event. Then come the words for that fluent or event, with a place `*a …*` for each of
its values. If you want, you can then write `known as` and the LPS name. Some lines
have an incorrect number of places, or refer to a thing that the rule base does not
have. Such a line gets a warning, and the reader then ignores it. The reader of LPS2
uses only the `known as` names. The Logical English translator also uses the words.

### Truth maintenance, salience and Java

**`insertLogical`** means that the fact is true while the facts that support it are
true. An intensional fluent says exactly that. An intensional fluent is a fluent that
rules define from other fluents. The two ways read `insertLogical` as an intensional
fluent. The reader of LPS2 writes `hope at T1 if politician_honest(A) at T1.` The
Logical English translator writes this text, in `honest_politician.le`:

```
there is a hope at a time if
    the politician called a name is honest at the time.
```

The fact then stops immediately when its conditions stop, as Drools removes it. An
event cannot start or end an intensional fluent. Thus, in some conditions, the
reading reads `insertLogical` as a usual insert. These conditions are: another rule
inserts, changes or deletes facts of that type, or the working memory contains such
facts at the start. In these conditions, the reading gives a warning that it will not
remove the fact.

**Salience** is the priority that Drools uses to select the rule that fires first.
LPS has no salience, because LPS decides by constraints, not by priority. The two
ways translate the rule and keep the salience as a comment. They give a warning that
the order of firing can be different.

**Rule attributes** tell when a rule can fire. Most of them depend on things that LPS
does not have: an agenda with groups and a focus, a calendar, a clock, and a run of
the rules that starts and ends. Each attribute was checked against Drools. The reading
of each attribute is as follows.

- `enabled false`: Drools never fires the rule. Thus the program does not keep the
  rule, and gives a note (a comment in Logical English).
- `no-loop`: Drools does not activate the rule again because of the change of the
  rule itself. The reading adds the condition that the change is not already done.
  An example is `modify( $a ) { setBalance( 100 ) }` on `Account( balance >= 100 )`.
  For this rule, the condition is `B \= 100` (`the balance is different from 100`).
  Thus the rule sets the maximum balance one time, as in Drools. In Drools, without
  `no-loop`, the two would fire with no end. A change that the rule calculates from
  the old value (`setCount( $c.getCount() + 1 )`) is never already done. Thus, in
  that case, the reading does not translate `no-loop`, and a warning tells you this.
- `lock-on-active` also stops activations that the changes of other rules make during
  one run of the rules. The reading reads `lock-on-active` as `no-loop`, with a
  warning.
- `agenda-group` (other than `"MAIN"`) and `ruleflow-group`: Drools fires the rule
  only while Java, or a process, gives the focus to the group of the rule. The rule
  base alone never does that. `auto-focus` gives the focus, in a different order.
  `activation-group` lets one activation of the full group fire, and cancels the
  other activations. `date-effective`, `date-expires` and `calendars` are periods in
  the calendar. `timer` and `duration` fire the rule later, on a clock. The reading
  does not translate these attributes. It reads the rule as always active, and the
  rule fires immediately on each match. Each of these attributes gets its own
  warning.
- `dialect` does not change the reading. A `salience` that is an expression is read
  as no salience, with a warning.

**Java** in a consequence is not translated. Sometimes the reader of LPS2 does not
recognise a statement. Then the reader gives a warning with the name of the rule and
the statement. The rule then does the external action `java_leaf(RuleName)` in place
of that statement. The action has no causal law and changes nothing. But the run
shows the action at the point where the Java would run. The reader can read a value
in a change in these conditions:

- The value is a variable.
- The value comes from a field of a bound variable (`$p.getName()`, `$p.isOn()`,
  `$total.intValue()`).
- The value is arithmetic on such values and on numbers.

Thus, for `modify( $c ) { setCount( $c.getCount() + 1 ) }`, the reader calculates the
new count in the conditions of the rule. The reader never changes a different value
(`$p.getName().toUpperCase()`, `Math.max( a, b )`, `"Dear " + $name`) into a fixed
value. It reads the full statement as Java, does not keep the statement, and gives a
warning with the name of the value. In Logical English, the Java becomes a comment on
the rule. Sometimes the full consequence of a rule is Java, for example a
`System.out.println`. That rule becomes a residue block:

```
% RESIDUE rule_OK BEGIN: OK
% TODO: translate the fragment below by hand, or with the Contract Assistant (residue mode); it was not translated automatically
% the rule's whole consequence is Java (no working-memory change): not translated
%   java:
%   | System.out.println( "Everything is ok" );
% RESIDUE rule_OK END
```

### The decision-service reading

A rule base with no `modify` and no `delete` only makes conclusions. A decision
service does the same. (A decision service keeps no state between questions.) For
such a rule base, the translator also writes a timeless reading. Each Drools rule
becomes one Logical English rule, in the order of salience. A comment above the rule
gives the name and the salience of the rule.

Drools fires only the first rule, by salience, that matches a case. Sometimes the
conditions of a rule do not already exclude the conditions of a rule of higher
salience. Then the translator adds `it is not the case that` with the conditions of
that rule. In `discount.drl`, the second rule already says
`not Customer( … tier == "gold" )`. Thus the translator does not add a condition.
The translator does not keep the condition that stops a second firing
(`not Discount( customer == $customer )`). A timeless rule makes its conclusion one
time in all cases. From `discount_decision.le`:

```
% Rule "Gold customers with a large order get the best rate" (salience 10)
there is a discount for a customer with rate a rate if
    there is an order for the customer with size large
    and there is a customer called the customer with tier gold
    and the rate is equal to best.

% Rule "Everyone else with a large order gets the standard rate" (salience 5)
there is a discount for a customer with rate a rate if
    there is an order for the customer with size large
    and it is not the case that there is a customer called the customer with tier gold
    and the rate is equal to standard.
```

The scenario of the program is the working memory of the Drools run. The program
`expects answers` the facts that Drools inserted.

## Traps

- **Facts in the reading's shape, not Drools' shape.** The facts that you add must
  agree with the `fluents` line of the program. A field that is true or false becomes
  a separate fluent. A field that the reader did not keep is not there. For the fire
  alarm, write `sprinkler(kitchen)` for a sprinkler that is off. Write
  `sprinkler(kitchen), sprinkler_on(kitchen)` for a sprinkler that is on.
  `sprinkler(kitchen, false)` matches nothing. The rules then never fire, and the
  system gives no message. The header shows the form of the facts of this rule base
  (`initially customer(Name, Tier), order(Customer, Size), …`). Replace each name
  with a capital letter in that line with a value.
- **A field every fact gives one value is left out.** The reader does not keep a
  field that does not make two facts different. When you give no working memory, the
  reader removes such a field only for a type whose facts the rules insert. (Each
  alarm of `fire-alarm.drl` is `Alarm(yes)`, thus the alarm is only `alarm`.) For
  other types, the reader keeps a field that a condition compares with a fixed value
  (`tier == gold`). The reason is that the facts of that type come from outside the
  rule base. When you give a working memory (in the twins, or with `--facts` on the
  command line), the reader decides from the facts. If each customer that you give is
  gold, the reader removes `tier`. The `info:` lines of the header tell which fields
  the reader removed.
- **The wording file must be chosen with its rule file.** In **File ▸ Open…**, select
  `<name>.drl` and `<name>.wording` together. A `.drl` file that you open alone uses
  the default words. A `.wording` file that you open alone opens nothing.
- **DRL is read as a subset, and what is left out is said.** The reader reads
  `declare`, `when`/`then`, patterns with `==`, the comparisons, `$` and `name :`
  bindings, and fields of the fact of a different pattern (`s.room`). It also reads
  `not`, `exists`, `or` (between patterns, and `||` between constraints), `&&`,
  `accumulate` with `sum`, `count`, `min` or `max`, `insert`, `insertLogical`,
  `retract`/`delete` and `modify` blocks. Some rules have a different kind of
  condition: `eval`, `forall`, `collect`, `from` without `accumulate`, `average`,
  `not` over more than one pattern, the prefix form `(or …)`, or a constraint that
  the reader cannot read. The reader does not keep such a rule in the program, and
  gives a warning with the name of that condition. The Logical English translator
  keeps the DRL of such a rule in a residue block. Of the rule attributes, the reader
  translates `no-loop` and `enabled false`. Each of the other attributes
  (`agenda-group`, `activation-group`, a timer, a calendar period, …) gets a warning.
  The reader reads the rule as if it can always fire (refer to
  [Truth maintenance, salience and Java](#truth-maintenance-salience-and-java)).
- **A reading LPS2 runs that Logical English for LPS does not write yet.** A `not`
  over a pattern with a comparison (`not Person( age > 65 )`) runs in the reader of
  LPS2. Logical English for LPS has no sentence for such a condition. Thus the
  translator writes that rule as a residue block that contains its DRL. (But the
  translator writes an `accumulate` as an aggregate sentence, and that sentence
  compiles back to the `findall` of the reader.)
- **`insertLogical` of a type that also changes otherwise** becomes a usual insert,
  with a warning. Then the system does not remove the fact when its support stops.
- **A type with no `declare` has only the fields the rules mention.** A rule base that
  uses Java classes does not tell which fields its facts have. The reader gets the
  fields from the constraints, from references in other patterns (`s.room`) and from
  the Java in the consequences (`politician.getName()` is the name of the
  politician). The reader then gives a warning: two facts that are different only in
  a field that no rule mentions become one fact. The twins were made with the Java
  fact model next to them. With your own file, add a `declare` for each type that the
  warning names.
- **Java is not carried out.** In LPS2, a Java statement becomes a warning and the
  action `java_leaf(RuleName)`. In Logical English, it becomes a comment. In the two
  cases, it changes nothing when the program runs. Sometimes the reader cannot
  calculate a value (`$p.getName().toUpperCase()`). Then the full change becomes
  Java. The reading does not keep that change, and gives a warning. The reading does
  not make the change with an incorrect value.
- **`no-loop` becomes a condition, not Drools' own record-keeping.** The rule does not
  fire while its change is already done. Drools fires such a rule one time on a fact
  where the change is already done: a modify that changes nothing. The reading does
  not fire the rule. The state at the end is the same in the two cases.
- **Salience is not a firing order.** LPS fires all the rules whose conditions are
  true in a cycle, and fires them together. Sometimes the result of a rule base
  depends on the rule that fires first. Then the final state can be different. The
  five twins end in the same state as Drools, because none of them depends on the
  order.
- **Firing once per match is approximated by a condition.** The added condition stops
  a rule that only inserts. The rule does not fire again while the inserted fact is
  true. If a rule later deletes that fact, and the conditions of the rule are still
  true, the rule fires again. A `println` in the rule would then print again at each
  point where the conditions stay true.
- **Several rules can fire in one cycle.** In `honest_politician`, Drools corrupts the
  politicians one activation at a time. LPS corrupts all the politicians that match,
  in the same cycle. The final state is the same, but the steps to it are different.
- **Times.** A rule base has no clock. The LPS program runs for `maxTime(8)` cycles.
  The twins run for 30 cycles, with the steps of the driver ten cycles apart. When
  your facts need more time, increase the maximum time.
- **The decision service needs its own check.** Salience decides which rule applies
  to a case. The translator writes that selection as `it is not the case that` in
  the rules of lower salience. Read the rules in the order of salience, with the
  names in the comments above them. Compare them with the answers that the scenario
  expects. Sometimes you open a decision service that the translator made from your
  own file. Its scenario is then empty. Add the facts before you run its tests.
- **Nothing goes back.** There is no export to DRL.

## See also

- In this documentation:
  - [Integrations](index.md), and [PDDL and LPS](pddl.md). PDDL is the other file
    type that LPS2 reads itself.
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
