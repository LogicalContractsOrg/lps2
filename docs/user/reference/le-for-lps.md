# Logical English for LPS — the surface language

*Kind: reference · Audience: users, developers · Status: current (2026-09-29)*

**M8b.** This document describes the language of the programs in `examples/le/`.
These programs are part of LPS2, the second version of LPS (Logic Production
System). LE2 is Logical English, version 2. The part of LE2 that reads the language
is `le_lps.pl`. This description is kept with LPS2, together with
`docs/dev/le-lps-interface.md`. LogicalEnglish2 has links to the two documents. It
does not keep its own copies.

Each construct in this document agrees with one of the terms that the engine uses
internally. `le_lps_interface.md` §5 gives the list of these terms. A program in
`examples/le/` uses each construct.

**Contents**

- [Logical English for LPS — the surface language](#logical-english-for-lps--the-surface-language)
  - [0. Where this came from](#0-where-this-came-from)
  - [1. The shape of a document](#1-the-shape-of-a-document)
    - [1.1 `extends` — a knowledge base built on others](#11-extends--a-knowledge-base-built-on-others)
  - [2. Declarations](#2-declarations)
    - [`; known as f`](#-known-as-f)
    - [`; 0 by default`](#-0-by-default)
    - [`the constants are:`](#the-constants-are)
    - [`the functions are:`](#the-functions-are)
  - [3. Sentences](#3-sentences)
    - [3.1 Temporal suffixes](#31-temporal-suffixes)
    - [3.2 `initially`](#32-initially)
    - [3.3 Timeless facts and rules](#33-timeless-facts-and-rules)
    - [3.4 `when … then …` — causal laws](#34-when--then---causal-laws)
    - [3.5 `if … then …` — reactive rules](#35-if--then---reactive-rules)
    - [3.6 Intensional fluents and composite events](#36-intensional-fluents-and-composite-events)
    - [3.7 `it must not be true that …` — integrity constraints](#37-it-must-not-be-true-that---integrity-constraints)
    - [3.8 `the goal is that …` — planning](#38-the-goal-is-that---planning)
    - [3.9 Observations](#39-observations)
    - [3.10 Budgets, and the size of a whole number](#310-budgets-and-the-size-of-a-whole-number)
    - [3.11 `display`](#311-display)
  - [4. Conditions](#4-conditions)
  - [5. The prospective form](#5-the-prospective-form)
  - [6. The programs](#6-the-programs)
  - [7. What is out of scope, and why](#7-what-is-out-of-scope-and-why)
  - [8. What has no LPS reading is refused](#8-what-has-no-lps-reading-is-refused)

---

## 0. Where this came from

The language is not a new invention. The older files contain an earlier version of
Logical English for LPS, by the same author. They also contain three programs in
that version:

```
legacy_lps1/examples/CLOUT_workshop/RockPaperScissors-Minimal-en.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsBaseEN.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsEthereumFEn.pl
```

`docs/project/plan-of-record.md` §I.9.3 could only make assumptions. These three
programs give examples that answer those questions. The constructs in this document
come from the three programs. The difference is the way to write the constructs.

The three programs are in LE1, the first version of Logical English. In LE1, a
template is only a sequence of words. A template is the pattern of a sentence. In
LE1, `known as f` connects that sequence of words to the name that the engine uses.
LE2 is different in three ways:

- LE2 marks the arguments of a template with `*variable*` slots. A slot is a part
  of the template that can change.
- LE2 finds the kind of thing in each slot from the first noun of the slot.
- LE2 lets a template have more data after a `;`.

This document writes each sentence of the three programs again in the LE2 style.

The three programs also answer two questions that were open. The two answers are
important:

- **The two ways to write time are both in use, and each has a function.** A rule
  that says "each time that this happens" (`when … then …`) does not write the
  time. A rule that must relate two moments gives them names (`… at a first time`).
  The older way to write an LPS program, which is similar to Prolog, makes exactly
  the same distinction.
- **Words such as *first* and *second* give a name to a time.** With
  `a first time`, `the first time` and `a second time`, a sentence starts two
  different times and then refers back to each of them. LE2 already reads these
  words in that way.

`at step 3` is choice (b) of §I.9.3. None of the three programs uses it, and it is
not part of this language.

---

## 1. The shape of a document

```
the target language is: lps.

the maximum time is 5.

the events are:
    *a player* inputs *a choice* and *an amount*; known as inputs.

the actions are:
    *a player* gets *a prize*; known as pay.

the fluents are:
    *a player* has played *a choice*; known as played.
    the reward is *an amount*; known as reward.
    the game is over; known as gameOver.

the templates are:
    *a choice* beats *another choice*.

the knowledge base rock paper scissors includes:

    initially the reward is 0.

    scissors beats paper.
    …

scenario one is:
    miguel inputs rock and 1000 from 1 to 2.
```

The line `the target language is: lps.` makes a `.le` document an LPS program.
Without that line, the document is usual Logical English. You cannot use the
sentences of §3. Also, `the fluents are:` is only one more section of templates,
as in all other documents now.

The file name still ends in `.le`. The first line already tells which of the two
kinds of document this is. With one file extension, the editor needs only one name
for the language. It also needs only one set of colour rules, and one helper
program that examines the text while you type. `docs/project/plans/le_lps_design.md`
§2 gives all of the argument. It also gives the test that would make a separate
`.leps` extension correct.

### 1.1 `extends` — a knowledge base built on others

```
the knowledge base fee token extends token.

the knowledge base fee token includes:

initially the balance of alice is 100.

this law replaces law credit of token.
when a sender transfers an amount to a recipient
then the balance of the recipient that is a second amount becomes second amount + amount - 1
    and the balance of the treasury that is a third amount becomes third amount + 1.
```

A knowledge base is the set of rules and facts that a document defines. A base
knowledge base is a knowledge base that a different document extends. You give the
name of a base in the same way as the name of each other resource that a document
includes (`le_summary.md` §14). The name is one of these two:

- A path from the folder of the document, without the `.le` extension.
- A URL (a web address).

The same rule tells if the system can read a base. A base on this computer must be
in the folder of the document, or in a folder below it. A program that translates
a different system into Logical English copies the bases next to the program that
it writes. It does the same with libraries.

A document gets these items from its base: the templates, the laws, the
constraints and the timeless rules. A document never gets the `initially`
sentences, the settings, the scenarios or the queries of the base. The reason is
that these items describe one specific case, not the agreement. The bases of a
base also come with it. When the system finds a base by two different routes, it
reads the base one time.

- **Constraints add up.** A document that extends a base can add constraints. A
  document cannot remove a constraint of the base without its name.
- **To replace a law, you must give its name.** The base gives the law a label.
  The label is `rule credit:` before the `when …` sentence, or before an
  `it must not be true that …` sentence. Then the document that extends the base
  writes `this law replaces law credit of token.` (or
  `this constraint replaces constraint … of …`). This line is immediately before
  the law that replaces the old law. Here, `token` is the name of the base. It is
  the name in the `extends` line, or the name of the knowledge base of the base.
  The system then does not use the law of the base. The checker reports the
  replacement as the warning `lps_replaces`. Thus a replacement of a law is
  permitted, and the system tells you about it. A replacement that gives an
  incorrect name is an error.
- **A conflict without a label is an error.** Two laws are in conflict when a law
  of the document changes the same entry on the same action as a law of a base.
  The checker then reports `lps_extends_clash`. The two laws would both apply. The
  author of a document that writes a law again almost never wants this result.

LPS2 runs one program that contains all the bases. Each law still keeps the name of
its file and its location in that file. Thus an explanation can give the base that
a law came from. The legal view (`le_lps_legal.pl`) comes from that combined
program. It has a line that gives the names of the bases. A document that you give
as text only, with no file, has no folder in which to look for its bases. Thus,
open such a document from its file.

---

## 2. Declarations

| LE | internal |
|---|---|
| `the maximum time is *N*.` | `maxTime(N).` |
| `the maximum real time is *N*.` | `maxRealTime(N).` |
| `the minimum cycle time is *N*.` | `minCycleTime(N).` |
| `the events are: …` | `events([…]).` |
| `the actions are: …` | `actions([…]).` |
| `the fluents are: …` | `fluents([…]).` |
| `…; <value> by default` on a fluent | `defaults([…]).` (LPS2 only) |
| `the constants are: …` | One timeless fact for each constant, and its template. |
| `the functions are: …` | Templates whose value you can write without their last argument (§2.4 of the LE2 reference). |
| `the prolog events are: …` | `prolog_events([…]).` |
| `the templates are: …`, `the predicates are: …` | Nothing. These are timeless words. |

`the actions are:` and `the prolog events are:` are new sections. An author must
not omit them. LPS makes a distinction between an *action* and an *event*:

- An action is something that the program does. The engine examines the
  preconditions of an action before the action can happen.
- An event is something that comes to the program from outside.

The engine uses this distinction everywhere. You cannot find from the use of a name
which of the two the name is. All three of the older programs declare the two kinds.

### `; known as f`

This is more data after a `;` at the end of a template. It is in the same family as
`; opposite`, `; synonym` and `; prepositional`:

```
    *a player* has played *a choice*; known as played.
```

This line connects the template to `played/2`. `played/2` is the relation with the
name `played` and two arguments. LPS uses this name, not `has_played/2`. Without
the addition, LE2 would make the name `has_played/2` from the words of the
template. The addition is optional, and it has two practical reasons:

1. The generated internal form of the program uses that name as its label. The rows
   of the timeline and the state-transition diagram use it too.
2. A companion `.lps` file (§7) must use the same name for the same relation.

The arguments of the relation are in the same order as the `*slots*` of the
sentence.

### `; 0 by default`

```
    the balance of *an account* is *an amount*; known as balance; 0 by default.
    the owner of the token is *an account*; known as owner; the zero address by default.
```

A default gives the value of the **last** argument of the fluent for a key that has
no stored fact. A fluent is a fact that can change with time. The key is all the
other arguments of the fluent, together. A mapping in Solidity has the same idea of
a zero. The `default` of the action language C+ also has it. The two lines above
give `defaults([balance(_, 0), owner('the zero address')])`, a declaration of LPS2
(`le_lps_interface.md` §5, version 3). The system never writes a default into the
state. The state holds exactly what the program put in it. The system gives the
default only when something reads the state.

- **Reading.** `the balance of bob is an amount` asks about a key that is already
  known, bob. Thus the condition is true for the stored fact of bob. If there is no
  stored fact for bob, the condition is true with the amount 0. When the key is not
  yet known, the system goes through only the stored facts, one at a time. Thus a
  sum or a count of a fluent with a default uses only the stored entries. The
  checker gives a warning about such a count (`lps_default_count`).
- **A statement that a value is missing.**
  `it is not the case that the balance of bob is a thing` is never true. The reason
  is that bob always has a balance, 0 at the minimum. The checker tells you about
  this (`lps_default_absence`).
- **Writing.** Look at `the balance of the recipient that is N becomes N + amount`,
  when there is no stored entry for that recipient. This reads the default as N and
  stores the new value. Sometimes an action starts a value but does not end the old
  value. One key would then hold two values at the same time
  (`lps_default_two_values`).
- **The timeline** shows the rows of the stored entries. It also shows one more line
  for each fluent with a default: *every other: balance(…, 0)*. An explanation of a
  default value tells that it is a default:
  `balance(dan,0) holds at cycle 3 — (the default: no entry was stored)`.
- **Deploy as Solidity** writes some fluents as a usual mapping. These are the
  fluents whose default is the zero of the kind of value that they hold (0, the zero
  address, false, the empty text). Next to the mapping, there is nothing that records
  which keys are present. Deploy as Solidity refuses all other defaults.
- The legal view is a timeless program about the stated facts. The legal view and
  LPS both receive the defaults as usual facts
  (`le_lps:lps_expand_defaults/2`).

A default must be a fixed value. Only a fluent of an LPS program can have a
default. On all other templates, the system reports a default as `default_not_lps`
and ignores it.

### `the constants are:`

```
the constants are:
    the unlimited allowance is 115792089237316195423570985008687907853269984665640564039457584007913129639935.
```

A constant gives a name to a value, one line for each constant (LE2 language
reference §2.3). Each line declares the template
`the value of the unlimited allowance is *a number*`. It also states the one fact
of that template. Then you can use the name in a sentence, for example
`the second amount is different from the unlimited allowance`. Logical English then
finds the value (`the_value_of_the_unlimited_allowance_is(H), G \= H`). An
explanation shows this step as one of its reasons. The fact has no time. Thus a law
can read it at all times. The checker reports a constant that nothing uses
(`unused_constant`).

### `the functions are:`

```
the functions are:
    the price of *a cup* is *an amount*.
```

A function is a template that ends in `... is *a value*`. Where a value is
necessary, you can then write the sentence WITHOUT that last argument (LE2 language
reference §2.4). Thus a law can compare the value, and it does not have to give the
value a name first:

```
if a customer orders a cup
    and the price of the cup > 10
then the barista asks about the cup.
```

The condition that asks the function for its value goes before the condition that
uses the value. Thus the reactive rule above becomes
`reactive_rule([happens(ordered(A,B),C,D), the_price_of_is(B,E), E>10], ...)`.
A usual rule or fact gives the value of the function. In the example above, this
rule or fact has no time. But the value of a fluent operates in the same way.
`examples/le/functions.le` is the full example. `; defines global` had a similar
function before, but it is not part of the language now.

---

## 3. Sentences

### 3.1 Temporal suffixes

Each use of a template in a rule can have one of these endings:

```
    … at <time>
    … from <time> to <time>
    … from <time>
    … to <time>
```

Here, `<time>` is usually the name of a time. Such a name usually has an ordinal
word, for example `a first time` or `the second time`. Sometimes `<time>` is a
whole number.

- `at T` on a fluent → `holds(F, T)`
- `from T1 to T2` on an event or action → `happens(E, T1, T2)`
- `from T` on an event or action → `happens(E, T, _)`. The event starts at T, and
  its end has no name. An event or action that you cannot divide ends at T + 1, and
  the engine makes sure of this. The end of a composite event is open. A composite
  event is an event that other events make.
- `at T` on an event or action → the same as `from T` (the reading of the Event
  Calculus)
- `to T` on an event → `happens(E, _, T)`, the **prospective form** (§5)

(The system reads `from T` on a fluent as `at T`, and gives a warning. The system
never reads `… is different from 5` in a template as a time.)

A sentence without such an ending gets its time from its position:

- In a `when … then …` law, the sentence gets the times of the event that starts the
  law.
- In `it must not be true that …`, each condition gets the moment when the event
  starts.
- In an `if … then …` reactive rule, all the conditions have one time. Each
  conclusion starts at that same time. But when one of the conditions is an event,
  the conclusions start when that event ends (§3.5).
- In `initially`, there is no time.

Thus some sentences need no written times. A law or a constraint does not need
times when all its conditions read the state at the start of the one event. A
reactive rule does not need times when its conditions read one state and its
actions come from that state:

```
    if there is a fire in a room
        and it is not the case that an alarm is on
    then an alarm goes on.
```

This rule is exactly
`reactive_rule([holds(fire(R),T1), holds(not(alarm),T1)], [happens(alarm_goes_on,T1,T2)])`.
The engine tries the action from the state that the conditions read. The words
`… from the time` would say the same thing. The part of the program that changes
rules back into English (`le_lps_write.pl`) writes all three kinds of sentence in
that way. An example is a constraint:

```
    it must not be true that
        a sender transfers an amount to a recipient
        and the balance of the sender is a second amount
        and the second amount < the amount.
```

This constraint is exactly
`d_pre([happens(transfer(S,A,R),T1,T2), holds(balance(S,B),T1), B<A])`.
You write times only where a sentence must relate two moments.

A time is an *ending that you add to a sentence*. It is not one of the arguments of
a template. The three older programs do it in this way. Thus one fluent template
can be used for two sentences: `the reward is 0` in an `initially` sentence, and
`the reward is a number at the first time` in a condition.

**How to say that some conditions are not all true together.**
`it is not the case that` can be above more than one condition. Write each
condition on its own line, with an indentation below `it is not the case that`.
When one of the conditions is a fluent or an event, all of them together are one
negated conjunction. A negated conjunction says that the conditions are not all
true together. The system reads it at one time:

```
    a person is the first at a time if
        the person is present at the time
        and the person is ranked a number N
        and it is not the case that
            an other person is ranked a number M
            and M < N
            and the other person is present at the time.
```

→ `l_int(holds(first(A),B), [holds(present(A),B), is_ranked(A,C), holds(not([is_ranked(D,E), E<C, holds(present(D),B)]),B)])`.
The list in `not` is the LPS form of a negated conjunction. (Before 18 October
2026, the system wrote this as a Prolog `not(…)`. The run then stopped with an
error about `holds/2`.)

### 3.2 `initially`

```
    initially the reward is 0.
    initially the goat is at the north bank and the wolf is at the north bank.
```

→ `initial_state([reward(0)]).`, `initial_state([loc(goat,north), loc(wolf,north)]).`

### 3.3 Timeless facts and rules

This is a usual Logical English fact or rule. It uses the templates in
`the templates are:`:

```
    scissors beats paper.
    *a place* is across from *another place* if …
```

→ a Prolog clause. When the rule has conditions and none of them has a time, the
result is `l_timeless(Head, Conditions)`.

### 3.4 `when … then …` — causal laws

**`when` tells what an event does.** The `when` part gives exactly one event or
action. This is the trigger: the event or action that starts the law. The `when`
part can also add more conditions. The `then` part tells how the state changes.

```
    when a player inputs a choice and an amount
        and the amount > 0
    then the player has played the choice.
```
→ `initiated(happens(inputs(P,C,A), T1, T2), played(P,C), [A > 0]).`

```
    when a player inputs a choice and an amount
    then it is not the case that the player has played the choice.
```
→ `terminated(happens(inputs(P,C,A), T1, T2), played(P,C), []).`

```
    when a player inputs a choice and an amount
    then the reward that is a number becomes number + amount.
```
→ `updated(happens(inputs(P,C,A), T1, T2), reward(N), N-N2, [N2 is N + A]).`

Thus the `then` part can have three shapes:

- A fluent. The fluent starts to be true.
- A fluent after "it is not the case that". The fluent stops being true.
- `the <fluent> that is <var> becomes <expression>`. This changes a value.

You can join more than one of these shapes with `and`. That sentence then gives
more than one law. A fluent that stops can be first, or last:

```
    when a person presses a button
    then it is not the case that the button is lit
        and the button is dark.
```

When `le_lps_write.pl` writes laws back as English (in `effects/3`), it collects
some effects into one sentence. These are the effects of one event that have the
same conditions. It puts first the fluents that start to be true.

### 3.5 `if … then …` — reactive rules

**`if` tells what to do about it.**

```
    if a first player has played a first choice at a first time
        and a second player has played a second choice at the first time
        and the first player is different from the second player
        and the first choice beats the second choice
        and it is not the case that the game is over at the first time
    then initiate the game is over from the first time to a second time
        and the reward is a prize at the first time
        and the first player gets the prize from the first time to a third time.
```
→ `reactive_rule([holds(played(P1,C1),T1), holds(played(P2,C2),T1), P1 \== P2, beats(C1,C2), holds(not gameOver, T1)], [happens(initiate gameOver, T1, T2), holds(reward(Pz), T1), happens(pay(P1,Pz), T1, T3)]).`

In a `then` part, `initiate <fluent>` and `terminate <fluent>` are effects that
occur immediately. The system writes them as `happens(initiate F, …)` and
`happens(terminate F, …)`.

A conclusion after `then` can be an action to do or a condition to examine. The
declaration of the template tells which of the two it is. The position of the
conclusion does not tell this. A template that is declared as an action or an
event becomes `happens/3`. A template that is declared as a fluent becomes
`holds/2`.

**When the conclusions occur.** The engine runs a Logical English program exactly
as it runs the same program in the older form, one cycle after the other.
[`lps.md` §13a](lps.md#13a-how-a-program-runs-step-by-step) gives the order of the
steps, which goal is first, and when a run fails. One difference in how you *write*
the two forms is very important. A conclusion without its own time gets the time
of the conditions (§3.1):

```
    if the guest is waiting
    then the guest enters.
```

This rule is `reactive_rule([holds(waiting,T1)], [happens(enters,T1,T2)])`. The
guest must enter in the same cycle in which the rule fired. Sometimes a constraint
prohibits the entry in that cycle. An example is
`it must not be true that the guest enters and the door is locked`, while the door
is locked. Then the goal is not possible, and the run ends in `failure`. To let the
action wait until the constraint permits it, give the conclusion its own times:

```
    if the guest is waiting at a first time
    then the guest enters from a second time to a third time.
```

The guest then enters in the first cycle in which the door is not locked.

When a condition is an event, the conclusions move to the moment when the event
ends. Look at this rule:

```
    if the door opens
    then the guest enters.
```

The guest enters in the step after the door opens. The rule is
`reactive_rule([happens(opens,T1,T2)], [happens(enters,T2,T3)])`. The system still
reads the conditions about the state at the start of the event, in the state in
which the event happened. (Before 29 September 2026, the conclusion started when
the door *started* to open. When the engine received the event, that moment was
already in the past, and the run failed.) The same rule, with its times written,
has the same meaning:

```
    if the door opens from a first time to a second time
    then the guest enters from the second time to a third time.
```

### 3.6 Intensional fluents and composite events

This is a Logical English rule with a conclusion that has one of the time endings
of §3.1:

```
    the players are a number N at a time if
        N is the sum of each V such that
            a player has played V at the time.
```
→ `l_int(holds(num_players(N), T), [holds(findall(V, [holds(played(P,V),T)], L), T), sum_list(L, N)]).`

An aggregate is a condition that collects many answers into one value. The
aggregate is part of Logical English (`le_summary.md` §5).
`L is the list of each V such that …` keeps the values, as a list:
`holds(findall(V, …, L0), T), L0 = L`. The result and the thing that the aggregate
collects must both have names, `N` and `V` above. The condition after `such that`
goes on its own line, with an indentation.

If you write the condition on the same line as the other words, the system reads
the sentence as a usual "is", and the run fails. The same occurs if you write the
collected thing as "each a value". The aggregate collects only over the lines with
an indentation below it. Sometimes a condition is at the level of the other
conditions of the sentence (`    and N > 5`). Such a condition comes after the
aggregate, not in it. This is also true when the aggregate is the first condition,
on the `if` or `when` line.

The system calculates an aggregate at the time when its own condition reads the
state. When that condition has no time, the aggregate gets the time of the
sentence. When the condition gives a time, as `… at the first time` does, the
aggregate gets that time. Thus
`if a player has played a value at a first time and N is the sum of each V such that a second player has played V at the first time …`
gives `holds(findall(V, [holds(played(P2,V),T1)], L), T1)`.

```
    a player pays a prize from a first time to a second time if
        an account is credited with the prize at the first time
        and the account is settled from the first time to the second time.
```
→ `l_events(happens(pay(P,Pz), T1, T2), [ … ]).`

An `at` ending gives `l_int`. A `from … to …` ending gives `l_events`. The system
*examines* the ending against the declarations:

- A conclusion with a template that is declared as a fluent must use `at`.
- A conclusion with a template that is declared as an event or an action must use
  `from … to …`.

An intensional fluent is a fluent that a rule calculates from other fluents. The
system never stores it in the state. Thus the timeline does not show it. Ask about
it:

- `why(holds(F), T)` gives the rule that gives the fluent at cycle T. It also gives
  each condition, with the values that made the condition true.
- `why_not(holds(F), T)` gives each rule that could give the fluent. For each rule,
  it gives the conditions that are true and the first condition that is false.

Refer to the guide to the editor, `docs/user/guide/ide.md`, "Asking why". Before 16
October 2026, *why not* answered that nothing in the program could make such a
fluent true.

### 3.7 `it must not be true that …` — integrity constraints

```
    it must not be true that
        a player inputs a choice and an amount from a first time to a second time
        and the amount <= 0.
```
→ `d_pre([happens(inputs(P,C,A), T1, T2), A =< 0]).`

A constraint that gives no event applies to each state. Such a constraint is an
**invariant**. For example, the total supply of a token is the sum of all its
balances:

```
    it must not be true that
        the total supply is an amount T at a time
        and S is the sum of each B such that
            the balance of an account is B at the time
        and S is different from T.
```

Sometimes a call would break a constraint. The constraint can be an invariant, or a
condition that must be true before an action can happen. The system then refuses
all of the call, and it records the refusal. The IDE is the editor where you write
and run programs. The timeline in the IDE shows the refused call crossed out. The
question `why_not(happened(A), T)` gets the answer `refused_by_constraint`. The
answer gives the constraint that refused the call, and the values that made the
constraint true.

### 3.8 `the goal is that …` — planning

```
    the goal is that the goat is at the south bank and the wolf is at the south bank.
```
→ `achieve(loc(goat,south) & loc(wolf,south)).`

A document with a goal also needs the line `:- lps_engine(planning).`.
`le_lps.pl` writes that line for you. A goal is exactly the way in which a document
says that the program is a planning problem.

### 3.9 Observations

A scenario is a list of events, each with its time:

```
scenario one is:
    miguel inputs rock and 1000 from 1 to 2.
    bob inputs paper and 1000 from 1 to 2.
```
→ `observe([inputs(miguel,rock,1000)], 2).` and one more.

`observe/2` receives the *end* time. Thus `from 1 to 2` gives `2`.
`miguel inputs rock and 1000 from 1` and `… at 1` have the same meaning. The reason
is that you cannot divide an observed event or action into smaller parts. Thus it
ends one moment after it starts. A scenario sentence without a time is an error. It
is not a fact at time 0. An observation without a time has no meaning in LPS. To put
such an observation at the start of the run, without a message, would be worse than
an error.

A run observes **one** scenario. A document can have more than one scenario, to
try the same rules on different histories. Such a document runs the first scenario,
and a warning gives the names of the other scenarios. To select a different
scenario, give its name:

```
./lps run contract.le --scenario late
```

In the editor, select the scenario in the list next to **Run**. The list shows when
a document has more than one scenario. A name that the document does not have is an
error. The error gives a list of the names that the document has. (Before 29
September 2026, the system observed the events of all the scenarios together, in
one run, as one history.)

### 3.10 Budgets, and the size of a whole number

Four templates are built in for one purpose. They let a program tell the cost to run
the **contract that it becomes when you deploy it**. They also let the program tell
where its arithmetic stops. You use all four as usual conditions of a usual
`it must not be true that` sentence.

```
    it must not be true that
        the gas of transfer is an amount
        and the amount > 60000.

    it must not be true that
        the code size of the contract is an amount
        and the amount > 20000.

    it must not be true that
        the call data of transfer is an amount bytes
        and the amount > 200.
```

There, `transfer` is the name of the action. `; known as transfer` gives this name.

**The system reads the four budgets when you deploy the program, not while it
runs.** *Misc ▸ Deploy as Solidity* writes the contract and compiles it. It then
runs the scenario of the program again on an EVM. The EVM (Ethereum Virtual
Machine) is the machine that runs contracts. The system then compares each budget
with the measured value. When a budget is exceeded, the system **stops the
export**. It gives the call and the value.

A run has no contract to measure and no gas to use. Thus, when you run a program
that states a budget, the system tells you that it does not model the value. It
does not ignore the sentence without a message. The system always examines two
limits, also when the program does not state them. The reason is that these limits
are not optional:

- The limit of **EIP-170**: 24,576 bytes of deployed code. You cannot deploy a
  contract that is larger.
- The limit of **EIP-7825**: 2^24 gas for one transaction. A larger call can never
  be included.

The gas limit of a *block* is not one of these two limits. The validators vote on
that limit. Thus the system reports that limit as a value with a usual size, and
never enforces it.

The fourth template is about arithmetic:

```
    it must not be true that
        a depositor deposits an amount
        and the balance of the depositor is a second amount
        and the largest whole number is a third amount
        and second amount + amount > the third amount.
```

A whole number in Logical English has no upper limit. In a contract, the same
number is a `uint256`, which has a limit. Since Solidity 0.8, an addition that goes
above that limit does not go back to zero. Instead, the system cancels all of the
call. Without the sentence above, the program and the chain do not agree about the
result of the call. Nothing shows this difference.

With the sentence, the two agree: the program refuses the deposit, and the contract
cancels the call. The exporter knows that this limit is the same limit that
`pragma ^0.8` already enforces at that `+`. Thus the exporter does **not** write it a
second time as a separate check.

Sometimes a program does arithmetic without such a stated limit. *Deploy as
Solidity* then gives each such location in its notes. It also gives the sentence
that would close the gap. *Deploy as Solidity* never writes such a sentence into
the document.

### 3.11 `display`

```
    the balance of a person that is an amount is drawn as
        a rectangle from [*x*, 0] to [*right*, *amount*] labelled the person if …
```

This sentence is **not** part of this language. A `display/2` clause is a Prolog
term that holds a list of properties. There is no advantage when you write such a
list in English. The correct location for the drawing clauses is a companion `.lps`
file (§7). Thus `examples/le/badlight.le` has a `badlight.lps` next to it. This pair
of files is the documented answer.

---

## 4. Conditions

All the constructs that LE2 already reads operate without change in the conditions
of a rule: `and`, `or`, `it is not the case that`,
`for all cases in which … it is the case that …`, aggregates
(`is the sum of each … such that …`), comparisons, arithmetic and lists. The
conditions of a law are the same as the conditions of all other sentences:

```
    when a sender airdrops an amount to a list
        and a recipient is in the list
        and N is the count of each E such that
            E is in the list
            and E is equal to the recipient
    then the balance of the recipient that is a second amount becomes second amount + amount * N.
```

(A list is a value the same as other values, in an observation and in a rule:
`alice airdrops 5 to [bob, carol, bob] at 3`. The balance has a default. Thus bob,
who is in the list two times, makes one instance of the law, and receives 10. An
update law of a fluent with a default runs one time for each *different* answer.)

§3.1 adds the ending that gives a time. `le_lps.pl` adds a decision for each
condition separately. The decision is between `holds/2`, `happens/3` and a usual
Prolog goal:

| the condition's template was declared as | becomes |
|---|---|
| a fluent | `holds(F, T)`, or `holds(not F, T)` after a negation |
| an event, action or prolog event | `happens(E, T1, T2)` |
| a timeless template, or one of the built-in conditions of Logical English | the goal, without a time |

A fluent or an event in a rule without its own time gets the time of the rule. A
condition gets the time that the other conditions have. A sentence in a `when` law
gets the times of the event that starts the law.

---

## 5. The prospective form

`docs/project/plans/le_lps_design.md` §6 said that the prospective form was the one
real open problem. It made the prospective form the test that this language had to
pass. The example comes from `prospectiveGoat.pl`:

```prolog
false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

`row(_,_) to T` connects `T` to the state that a crossing *would make*. Thus the
constraint is about a state that does not exist yet. The action that the engine
examines describes that state.

**You can say the form in English, with the third ending of §3.1.** The sentence
is:

```
    it must not be true that
        a crossing happens to a time
        and the goat is at a place at the time
        and the wolf is at the place at the time
        and it is not the case that the farmer is at the place at the time.
```

→ `d_pre([happens(row(_,_), _, T), holds(loc(goat,L), T), holds(loc(wolf,L), T), holds(not loc(farmer,L), T)]).`

`… to a time` without `from` is exactly `row(_,_) to T`. It is an event whose end
is the moment of the constraint, and whose start has no name. Read the sentence
aloud: "it must not be true that a crossing happens *to* a time and, *at* that
time, the goat and the wolf are together without the farmer". The words tell the
meaning of the constraint.

Thus the language passes the test. The limit on scope in §I.9.6 is smaller than
`docs/project/plans/le_lps_design.md` expected. §7 gives the list of the items that
this language does *not* include.

---

## 6. The programs

The programs are in `examples/le/`, with the files of LPS2. (Until 2026-09, they
were in `examples/lps/` of LE2. LE2 still keeps their expected translations in
`testing/fixtures/lps/`.) There are fifteen programs in the list below, plus
`token.le` and `fee_token.le`. Next to each `NAME.le` there is a
`NAME.expected.lpsw`. This file holds the internal form that `le_lps.pl` must make.
The system compares the two, term by term, with `variant/2`.

| program | what it is for |
|---|---|
| `rock_paper_scissors_minimal.le` | the first example: events, actions, fluents, updates, denials |
| `rock_paper_scissors_base.le` | the second example: aggregates, initiate, ordinals |
| `rock_paper_scissors_ethereum.le` | the third example: prolog events, composite events, `l_int` |
| `goat.le` | composite events, recursive decomposition |
| `prospective_goat.le` | the prospective form, the acceptance test (§5) |
| `goat_declarative.le` | `achieve`, planning mode |
| `badlight.le` | `display/2` in a companion `.lps` (§3.11, §7) |
| `bank_transfer.le` | the standard "contract" shape |
| `dining_philosophers.le` | actions at the same time, preconditions on sets of actions |
| `fire_simple.le` | the smallest useful reactive rule |
| `map_colouring.le` | many timeless rules, little state |
| `loan_agreement.le` | real time, dates, a legal text as its source |
| `escrow.le` | more than two parties, obligations |
| `delivery_delay.le` | deadlines and the time since an event |
| `life.le` | intensional fluents on a grid, the most difficult case |
| `token.le` | `; 0 by default`, a named constant, no written times, a law with a label, an airdrop to a list |
| `fee_token.le` | `extends token`, and a law that replaces the law of the base |

All seventeen programs translate. `testing/lps_test.pl` compares each translation
with the expected translation. Fifteen of them also pass the **round trip**:
`LE → internal → LE → internal`. The round trip changes English to the internal form,
back to English, and to the internal form again. The two internal forms must be
equal, term by term, under `variant/2`. `testing/lps_roundtrip.pl` runs this check.
`le_lps_write.pl` tells what the round trip shows and what it does not show.

The two programs that do not pass are `delivery_delay.le` and `loan_agreement.le`.
They have the same reason, and the test records the reason next to them. A calendar
date is a *constant* (`2018-04-01`) in these programs. A date that is a constant has
no form in Logical English. Thus the system cannot write it back.

Fifteen programs also *run* to `success` under LPS2
(`./lps run examples/le/NAME.le` with `LPS_LE2_DIR` set). These are the two
programs that do not:

- `prospective_goat.le` ends in `failure`. The original,
  `legacy_lps1/examples/forTesting/prospectiveGoat.pl`, also ends in `failure` under
  the same engine. The purpose is to agree with the original.
- `rock_paper_scissors_minimal.le` ends in `failure`, but the original ends in
  `terminated(unknown)`. The original has one rule that this version does not have:
  `If a number is sent to some body from T1 to T2 then lps_terminate from T2 to T3`.
  `lps_terminate` is an instruction to the engine, and it has no form in English.
  This document records the difference. It does not invent a form.

---

## 6a. Turning an older program into a document

You can write an LPS program in the older syntax (similar to Prolog), a `.lps` file,
as a Logical English document. The two then have the same meaning. There are two
ways to do this:

- In the IDE, select **Misc ▸ Convert to Logical English…**. The document opens in
  a new tab with the name of the program and the extension `.le`. Save it where you
  want it.
- On the command line, run `lps le PROGRAM`. This writes the document to the
  screen, or to a file with `--out FILE`.

The older syntax has no templates. Thus the converter writes one template for each
relation in the program. It uses the words of the name of the relation. For
example, `pick_up(Who, What)` becomes `*a thing* picks up *a second thing*`. The
converter connects the template back to the name with `; known as pick_up`. The
words are a guess about English. The connection gives the meaning. Thus the
converted document runs exactly as the program did. `tools/lps_to_le_test.pl`
examines this. It runs the two and compares the results, one cycle after the other.

You can keep the two files next to each other. The first line of a document from
the converter tells this:

```
% lps-converted-from: fox_crow.lps
```

This line stops the engine from reading the older file as the companion of the
document (§7). Without the line, the engine would run each rule two times.

**The converter does not guess. It tells you what it cannot convert.** It reports
each of these items before it writes the document. Each item is a limit of this
surface language, not of the conversion:

| What | Why | What to do |
|---|---|---|
| the settings of the planning engine, `:- lps_engine(planning, [search(...), horizon(...), max_concurrency(...)])` | A document with a goal asks for the planning engine automatically (§3.8), but not with these settings. | Keep the line in a companion `.lps` file. |
| drawing rules, `display/2` and `display3d/2` | A list of shapes and coordinates (§3.11). | The same. |
| one name for two kinds of thing, for example `temperature` as an event and as a fluent | Here, the section of its template tells if a sentence is an event, an action or a fluent. One name cannot be in two sections. | Change the name of one of them, or keep the program in the older syntax. |
| a term in a term, for example `command(open(case))` | An argument of a sentence holds a name, a number, a date or a list. | Write the relation again with one argument for each part. |
| `updates` where the value that changes is not the last argument of the relation | You write an update as `... that is <the old value> becomes <the new one>`. This can change only the last argument. | Put the value that changes last. |

Five `.lps` files in `examples/le/` are not separate programs. They are the
*companions* of Logical English documents. The converter refuses these files, and
it tells you which document to read.

---

## 7. What is out of scope, and why

This document states these limits and does not go around them, as §I.9.6 asks.

- **`display/2`.** This is a list of shapes, colours and coordinates. Refer to
  §3.11. Write it in the companion file.
- **Prolog that you write directly.** Examples are `findall/3` with a goal that you
  write yourself, `is/2` on a predicate from a library, and all other text outside
  the templates. Write it in the companion file.
  `docs/project/plans/le_lps_design.md` §5 recommended this as choice (ii).
- **Priorities between rules.** `reactive_rule/3` has no form in English. None of
  the older programs uses a priority.
- **`unserializable/1`.** This is an instruction about tracing. It is not a
  statement about the subject of the program.
- **Real-time settings other than the three in §2.** The `simulatedRealTime*`
  settings are controls for test runs.
- **`lps_terminate` and the other system actions.** Each of these is an instruction
  to the engine. It is not a statement about the subject of the program. Refer to the
  note about `rock_paper_scissors_minimal.le` in §6.

Two more limits come from LE2, not from LPS. Know them before you start to write:

- **Write as a name only the values that you add or multiply.** Write
  `a total = price + tax`, not `a total = the price + the tax`. LE2 always reads
  arithmetic in this way (`examples/moreExamples/numbers.le`). Also write
  comparisons with symbols, as in `the amount >= 10`. When LE2 compares the words
  with a template, it cannot see the difference between
  `is greater than or equal to` and `is greater than`. The shorter one is selected.
- **A template must not contain a word that starts a section.** These words are
  `contract`, `knowledge`, `templates`, `fluents`, `events`, `actions`,
  `predicates`, `ontology` and `target`. LE2 reads such a word as the start of a new
  section. It then reports that the template is incomplete. Write
  `the lender calls off the loan`, not `the lender cancels the contract`.

This is the rule for companion files. The system compiles `foo.le` and `foo.lps`
together, the `.le` part first. The `.lps` part uses the usual syntax of LPS, which
is similar to Prolog. The editor treats it as a usual `.lps` file. Nothing goes
secretly through the English.

## 8. What has no LPS reading is refused

The system translates all of a document into LPS, or nothing. Sometimes one issue
is an error. The error can be a mistake in the document, or a construct that has no
meaning in LPS. Then `le_lps_module/5` writes **no LPS text**. The functions that
use it also write no LPS text: `getLps`, `le_compile` of LPS2, Deploy as Solidity,
and the exporters that read the LPS translation. The issues then tell the reason.
Each issue is attached to its sentence. An LPS program with a meaning different
from its document would be worse than no program.

The part that writes the LPS text changes some conditions into the forms of LPS.
These are the conditions that LPS can run: comparisons, arithmetic, questions about
membership of a list, and aggregates (§4). All other conditions go through without
change and without a time. LPS2 would then call such a condition as a relation of
the program. Thus the system finds all the remaining words of Logical English
before it writes text. It reports them as the error `not_lps`
(`not_lps_issues/3`):

- `for all cases in which … it is the case that …`, which says something about all
  cases together. Also all other conditions that the system could not change into
  an LPS form.
- The built-in conditions of Logical English that LPS cannot use. Examples are
  arithmetic on dates (`… days after …`), decision tables and `the minimum of …`.
  Thus, each remaining `le_` goal.
- A condition on a template that the reasoner can assume (`; unknown`), or decide
  about itself. LPS assumes nothing. Thus such a condition would always fail.
- A condition that an outside service answers (`; via service`).

All other conversions of a program into a different language refuse in the same way
(docs/dev/migration.md, "Exporting: the check before the text").
