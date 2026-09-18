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
| DRL into LPS | **File ▸ Open…** in this IDE; the example list; `./lps drools` on the command line | `.drl` (with a `.wording` file beside it in the example list and on the command line, or chosen with it in File ▸ Open…) | an LPS program in the written form, with a header saying what did not carry over | the rules each rule base is expected to fire, cycle by cycle, written down from its documented behaviour, the newer ones checked against Drools, and what nine constructs read as (lpsPlus's `migration/drools/lps_drools_test.pl`, 18 cases and 11 readings) |
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
(a salience, a Java statement, a field left out, a rule not translated). The
program follows. For
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
the `fluents` line (not the Java objects; see [Traps](#traps)). The header's
note shows the shape they take, with a name for each field:

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
rules were encoded, how many approximated (salience, a rule attribute, a value computed in Java) and how many left as
residue (a consequence in Java only, or a rule LPS2's reader does not
translate), and how many other approximations of the reading there are (a
type with no `declare`, an `insertLogical` read as an insert). When the rules
only insert facts, the note adds that
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
| Java in a consequence | an external action, `java_leaf(RuleName)`, in its place, with a warning | a comment on the rule; a residue block with the Java when the consequence is only Java |
| `insertLogical` | an intensional fluent | an intensional fluent |
| `accumulate` | an aggregate over the state | an aggregate sentence (`a total is the sum of each a value such that …`) |
| `not` over a pattern with a comparison | the negation of both | a residue block with the DRL (see [Traps](#traps)) |
| Rule attributes | `no-loop` a condition, `enabled false` the rule left out; the others a warning each | the same, and a comment on the rule and an *approximated* ledger entry for each attribute not translated |
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
is an intensional fluent, and that is how both doors read it. LPS2's reader
writes `hope at T1 if politician_honest(A) at T1.`, and the Logical English
translator, in `honest_politician.le`:

```
there is a hope at a time if
    the politician called a name is honest at the time.
```

The fact is then withdrawn the moment its conditions stop holding, as Drools
withdraws it. An intensional fluent cannot also be started or ended by an
event, so where a rule also inserts, modifies or deletes facts of that type,
or the working memory holds such facts from the start, `insertLogical` is
read as an ordinary insert, with a warning that the fact is not withdrawn.

**Salience** is Drools' priority for deciding which rule fires first. LPS has
no such thing: it decides by constraints, not by priority. Both doors translate
the rule, keep the salience as a comment and warn that firing order may differ.

**Rule attributes** say when a rule may fire, and most of them depend on
things LPS does not have: an agenda with groups and a focus, a calendar, a
clock, a run of the rules that begins and ends. Each was checked against
Drools itself, and each is read as follows.

- `enabled false`: Drools never fires the rule, so the program leaves it out,
  with a note (a comment in Logical English).
- `no-loop`: Drools does not activate the rule again because of its own
  change. The reading adds the condition that the change is not made
  already. For `modify( $a ) { setBalance( 100 ) }` on `Account( balance >=
  100 )` that is `B \= 100` (`the balance is different from 100`): the rule
  caps the balance once, as in Drools, where without `no-loop` both would fire
  for ever. A change computed from the old value (`setCount( $c.getCount() +
  1 )`) is never made already, so there `no-loop` is not translated, and a
  warning says so.
- `lock-on-active` also holds back activations that other rules' changes
  create during one run of the rules. It is read as `no-loop`, with a warning.
- `agenda-group` (other than `"MAIN"`) and `ruleflow-group`: Drools fires the
  rule only while Java or a process gives its group the focus, which the rule
  base alone never does. `auto-focus` gives it, in an order of its own.
  `activation-group` lets one activation of the whole group fire and cancels
  the others. `date-effective`, `date-expires` and `calendars` are windows
  of the calendar; `timer` and `duration` fire the rule later, on a clock.
  None of these is translated: the rule is read as always active, firing at
  once on every match, and there is a warning for each.
- `dialect` changes nothing in the reading, and a `salience` that is an
  expression is read as no salience, with a warning.

**Java** in a consequence is not translated. A statement LPS2's reader does
not recognise gets a warning naming the rule and the statement, and the rule
performs the external action `java_leaf(RuleName)` in its place: an action
with no causal law, which changes nothing, but shows in the run where the Java
would have run. A value inside a change is read when it is a variable, an
accessor of a bound variable (`$p.getName()`, `$p.isOn()`, `$total.intValue()`)
or arithmetic over those and numbers: `modify( $c ) { setCount( $c.getCount()
+ 1 ) }` computes the new count in the rule's conditions. Any other value
(`$p.getName().toUpperCase()`, `Math.max( a, b )`, `"Dear " + $name`) is
never written as a constant: the whole statement is Java, left out, with a
warning naming the value. In Logical English the Java is a comment on the rule, and a
rule whose whole consequence is Java (a `System.out.println`) is a residue
block:

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
  silently never fire. The header shows the shape of this rule base's own
  facts (`initially customer(Name, Tier), order(Customer, Size), …`): replace
  each capitalised name with a value.
- **A field every fact gives one value is left out.** The reader leaves out a
  field that tells no two facts apart. With no working memory it decides that
  only for a type whose facts the rules insert themselves (every alarm of
  `fire-alarm.drl` is `Alarm(yes)`, so the alarm is simply `alarm`); a field a
  condition compares with a constant (`tier == gold`) is kept for any other
  type, since its facts come from outside the rule base. Given a working
  memory (the twins, `--facts` on the command line), it decides from the
  facts: if every customer you give is gold, `tier` is left out. The header's
  `info:` lines say which fields went.
- **The wording file must be chosen with its rule file.** In **File ▸ Open…**,
  select `<name>.drl` and `<name>.wording` together; a `.drl` opened on its
  own uses the default words, and a `.wording` on its own opens nothing.
- **DRL is read as a subset, and what is left out is said.** The reader
  handles `declare`, `when`/`then`, patterns with `==`, the comparisons, `$`
  and `name :` bindings, fields of another pattern's fact (`s.room`), `not`,
  `exists`, `or` (between patterns, and `||` between constraints), `&&`,
  `accumulate` with `sum`, `count`, `min` or `max`, `insert`,
  `insertLogical`, `retract`/`delete` and `modify` blocks. A rule with any
  other condition (`eval`, `forall`, `collect`, `from` without `accumulate`,
  `average`, `not` over several patterns, the prefix form `(or …)`, a
  constraint the reader cannot read) is left out of the program, with a
  warning naming the condition; the Logical English translator keeps its DRL
  in a residue block. Of the rule attributes, `no-loop` and `enabled false`
  are translated; the others (`agenda-group`, `activation-group`, a timer, a
  calendar window, …) are a warning each, and the rule is read as if it could
  always fire (see [Truth maintenance, salience and Java](#truth-maintenance-salience-and-java)).
- **A reading LPS2 runs that Logical English for LPS does not write yet.**
  A `not` over a pattern with a comparison (`not Person( age > 65 )`) runs in
  LPS2's own reader. Logical English for LPS has no sentence for it, so the
  translator writes such a rule as a residue block with its DRL. (An
  `accumulate` is written as an aggregate sentence, and compiles back to the
  reader's own `findall`.)
- **`insertLogical` of a type that also changes otherwise** is an ordinary
  insert, with a warning: the fact is not withdrawn when its support goes.
- **A type with no `declare` has only the fields the rules mention.** Written
  against Java classes, a rule base does not say what fields its facts have.
  The reader takes them from the constraints, from other patterns' references
  (`s.room`) and from the Java of the consequences (`politician.getName()` is
  the politician's name), and warns that facts differing only in a field no
  rule mentions are read as one fact. The twins were built with the Java fact
  model; with your own file, add a `declare` for each type the warning names.
- **Java is not evaluated.** A Java statement is a warning and the action
  `java_leaf(RuleName)` (LPS2), or a comment (Logical English); it changes
  nothing when the program runs. A value the reader cannot compute
  (`$p.getName().toUpperCase()`) makes its whole change Java: the change is
  left out, with a warning, rather than made with a wrong value.
- **`no-loop` is a condition, not Drools' bookkeeping.** The rule does not
  fire while its change is made already. Drools also fires it once on a fact
  where the change is already made (a modify that changes nothing); the
  reading does not, and the state ends the same.
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
