# Logical English for LPS — the surface language

*Kind: reference · Audience: users, developers · Status: current (2026-09-29)*

**M8b.** This document describes the language the programs in `examples/le/`
are written in. Those programs belong to LPS2, the second version of LPS
(Logic Production System). The part of LE2 — Logical English, version 2 —
that reads the language is `le_lps.pl`. The description lives with LPS2, as
`docs/dev/le-lps-interface.md` does, and LogicalEnglish2 links to both rather
than keeping copies of its own.

Every construct described below is matched to one of the terms the engine
works with internally, listed in `le_lps_interface.md` §5, and every one of
them is used by a program in `examples/le/`.

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

Not from invention. Among the older files is an earlier attempt at Logical
English for LPS, by the same author, together with three programs written in
it:

```
legacy_lps1/examples/CLOUT_workshop/RockPaperScissors-Minimal-en.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsBaseEN.pl
legacy_lps1/examples/CLOUT_workshop/RockPaperScissorsEthereumFEn.pl
```

Those three programs settle by example what `docs/project/plan-of-record.md` §I.9.3 could
only assume. The constructs below are taken from them. What changed is the way
the constructs are written down. The three programs are in LE1, the first
version of Logical English, where a template is a plain run of words and
`known as f` ties that run of words to the name the engine uses. LE2 marks the
places of a template with `*variable*` slots, works out what kind of thing each
slot holds from the noun that leads it, and lets a template carry extra
information after a `;`. Every sentence of the three programs is written out
again here in that later style.

The three programs also settle two questions that had been open, and both
answers are worth stating outright:

- **Both ways of writing time are used, and each has a job.** A rule that says
  "whenever this happens" (`when … then …`) leaves the time out. A rule that
  has to relate two moments names them (`… at a first time`). The older,
  Prolog-like way of writing an LPS program draws exactly the same distinction.
- **Words such as *first* and *second* are how a time gets a name.** `a first
  time`, `the first time` and `a second time` are how a sentence introduces two
  different times and then refers back to each of them. LE2 already reads those
  words that way.

`at step 3` — choice (b) of §I.9.3 — appears in none of the three programs and
is not part of this language.

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

`the target language is: lps.` is the line that makes a `.le` document an LPS
program. Without that line the document is plain Logical English, none of the
sentences of §3 may be used, and `the fluents are:` is simply one more section
of templates, as it is in any other document today.

The file name still ends in `.le`. The first line already says which of the two
kinds of document this is, and one file ending means the editor needs only one
name for the language, one set of colouring rules and one helper program
checking the text as you type. `docs/project/plans/le_lps_design.md` §2 makes the argument in
full, and states the test that would make a separate `.leps` ending right
instead.

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

A base knowledge base is named in the same way as any other resource a document
includes (`le_summary.md` §14). The name is either a path leading from the
document's own folder, with the `.le` ending left off, or a URL (a web
address). The same rule decides whether a base may be read at all: a base on
this machine has to sit somewhere under the document's own folder. A program
that translates another system into Logical English copies the bases beside the
program it writes, as it does with libraries.

A document takes from its base the templates, the laws, the constraints and the
timeless rules. A document never takes the base's `initially` sentences, its
settings, its scenarios or its queries, because those describe one particular
case rather than the agreement itself. The bases of a base come along too, and
a base reached by two different routes is read once.

- **Constraints add up.** A document that extends a base may add constraints.
  A document cannot drop one of the base's constraints without naming it.
- **A law is replaced only by naming it.** The base gives the law a label:
  `rule credit:` written before the `when …` sentence, or before an `it must
  not be true that …` sentence. The document that extends the base then writes
  `this law replaces law credit of token.` (or `this constraint replaces
  constraint … of …`) immediately before the law that takes the old one's
  place. `token` there names the base, either as the `extends` line spells it
  or by the name of the base's knowledge base. The base's own law is then left
  out, and the checker reports the replacement as the warning `lps_replaces`:
  replacing a law is allowed, and said out loud. A replacement that names
  nothing is an error.
- **A clash nobody labelled is an error.** Two laws clash when a law of the
  document changes the same entry on the same action as a law of a base, and
  the checker reports `lps_extends_clash`. Both laws would apply, which is
  rarely what the author of a document that restates a law meant.

The program LPS2 runs is the one with every base folded into it. Each law
still remembers which file it came from and where in that file, so an
explanation can cite the base a law came from. The legal view
(`le_lps_legal.pl`) is taken from the folded-together program, and carries a
line naming the bases. A document handed over as bare text, with no file of its
own, has no folder in which to look for its bases, so open such a document from
its file.

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
| `the constants are: …` | a timeless fact per constant, and its template |
| `the functions are: …` | templates whose value may be written without their last place (§2.3 of LE2's reference) |
| `the prolog events are: …` | `prolog_events([…]).` |
| `the templates are: …`, `the predicates are: …` | nothing — timeless vocabulary |

`the actions are:` and `the prolog events are:` are new sections, and neither
is a convenience an author may skip. LPS draws a line between an *action*,
which the program itself performs and whose preconditions are checked before it
may happen, and an *event*, which happens to the program from outside. The
engine leans on that line all through, and no amount of looking at how a name
is used tells you which of the two the name is. All three of the older programs
declare both kinds.

### `; known as f`

Extra information written after a `;` at the end of a template, in the same
family as `; opposite`, `; synonym` and `; prepositional`:

```
    *a player* has played *a choice*; known as played.
```

ties the template to `played/2` — the relation called `played` with two places
— which is the name LPS uses, instead of `has_played/2`, the name LE2 would
otherwise make up from the words of the template. The addition is optional, and
it is there for two practical reasons. First, the generated internal form of
the program, the rows of the timeline and the state-transitions diagram are all
labelled with that name. Second, a companion `.lps` file (§7) has to call the
same relation by the same name.

The places of the relation follow the order in which the `*slots*` appear in
the sentence.

### `; 0 by default`

```
    the balance of *an account* is *an amount*; known as balance; 0 by default.
    the owner of the token is *an account*; known as owner; the zero address by default.
```

A default says what value the fluent's **last** place holds for a key that no
fact has been stored for; the key is the fluent's other places, taken
together. A mapping in
Solidity has the same idea of a zero, and so has the `default` of the action
language C+. The two lines above give
`defaults([balance(_, 0), owner('the zero address')])`, a declaration of LPS2
(`le_lps_interface.md` §5, version 3). A default is never written down
anywhere: the state holds exactly what the program put in it, and the default
is supplied on the way out.

- **Reading.** `the balance of bob is an amount` asks after a key that is
  already known, bob, so the condition holds for bob's stored fact, or, where
  no fact was stored for bob, with the amount 0. Where the key is not yet known, only the
  stored facts are run through one by one, so adding up or counting a fluent
  with a default adds up or counts the stored entries alone. The checker warns
  about a count of that kind (`lps_default_count`).
- **Saying a value is missing.** `it is not the case that the balance of bob is
  a thing` never succeeds, because bob has a balance whatever happens — 0 at
  the least. The checker points that out (`lps_default_absence`).
- **Writing.** `the balance of the recipient that is N becomes N + amount`,
  where no entry has been stored for that recipient, reads the default as N and
  stores the new value. Starting a value without ending the old one in the same
  action would leave one key holding two values at once
  (`lps_default_two_values`).
- **The timeline** shows the stored entries' lanes and one more line per
  defaulted fluent: *every other: balance(…, 0)*. An explanation of a value
  held by default says so: `balance(dan,0) holds at cycle 3 — (the default:
  no entry was stored)`.
- **Deploy as Solidity** writes a fluent whose default is the zero of the kind
  of value it holds (0, the zero address, false, the empty text) as a plain
  mapping, with nothing beside it to record which keys are present. Any other
  default is refused.
- The legal view — a timeless program over the facts that have been stated —
  and LPS itself are both given the defaults spelled out as ordinary facts
  (`le_lps:lps_expand_defaults/2`).

A default has to be a fixed value, and only a fluent of an LPS program may
have one. On any other template a default is reported as `default_not_lps` and
ignored.

### `the constants are:`

```
the constants are:
    the unlimited allowance is 115792089237316195423570985008687907853269984665640564039457584007913129639935.
```

A constant gives a value a name, one line for each (LE2's language reference
§2.2). Each line declares the template `the value of the unlimited allowance is
*a number*` and states the single fact that goes with it. Wherever the name is
then used — `the second amount is different from the unlimited allowance` —
Logical English looks the value up
(`the_value_of_the_unlimited_allowance_is(H), G \= H`), and an explanation
shows the lookup as one of its reasons. The fact has no time attached to it, so
a law may read it at any moment. The checker reports a constant that nothing
uses (`unused_constant`).

### `the functions are:`

```
the functions are:
    the price of *a cup* is *an amount*.
```

A function is a template that ends in `... is *a value*`. Wherever a value is
expected, the sentence may then be written WITHOUT that last place (LE2's
language reference §2.3), so a law can compare the value without giving it a
name first:

```
if a customer orders a cup
    and the price of the cup > 10
then the barista asks about the cup.
```

The condition that asks the function for its value is put before the condition
that uses the value, so the reactive rule above becomes
`reactive_rule([happens(ordered(A,B),C,D), the_price_of_is(B,E), E>10], ...)`.
What gives the function its value is an ordinary rule or fact — one with no
time attached in the example above, though the value of a fluent works just the
same way. `examples/le/functions.le` is the worked example. `; defines global`,
which used to say something like this, is no longer part of the language.

---

## 3. Sentences

### 3.1 Temporal suffixes

Any template instance in a rule may carry one of

```
    … at <time>
    … from <time> to <time>
    … from <time>
    … to <time>
```

where `<time>` is either a name for a time — usually one written with an
ordinal word, as in `a first time` or `the second time` — or, now and then, a
plain whole number.

- `at T` on a fluent → `holds(F, T)`
- `from T1 to T2` on an event or action → `happens(E, T1, T2)`
- `from T` on an event or action → `happens(E, T, _)`: the event starts at T
  and its end is not named. An event or action that cannot be broken down ends
  at T + 1, and the engine holds it to that; the end of a composite event —
  one made of other events — is left open
- `at T` on an event or action → the same as `from T` (the Event Calculus
  reading)
- `to T` on an event → `happens(E, _, T)`, the **prospective form** (§5)

(`from T` on a fluent is read as `at T`, with a warning. A template's own
`… is different from 5` is never taken for a time.)

A sentence written with no such ending takes its time from where it stands.
Inside a `when … then …` law the sentence takes the times of the event that
triggers the law. Inside `it must not be true that …` every condition takes the
moment the event starts. Inside an `if … then …` reactive rule all the
conditions share one time, and every conclusion starts at that same time.
Inside `initially` there is no time at all. So a law or a constraint whose
conditions all read the state as the single event begins needs no times
written, and neither does a reactive rule whose conditions read one state and
whose actions follow from that state:

```
    if there is a fire in a room
        and it is not the case that an alarm is on
    then an alarm goes on.
```

is exactly `reactive_rule([holds(fire(R),T1), holds(not(alarm),T1)],
[happens(alarm_goes_on,T1,T2)])`. The action is attempted from the state the
conditions read, which is what `… from the time` would have said in so many
words. The part of the program that turns rules back into English
(`le_lps_write.pl`) writes all three kinds of sentence that way. A constraint,
for instance:

```
    it must not be true that
        a sender transfers an amount to a recipient
        and the balance of the sender is a second amount
        and the second amount < the amount.
```

is exactly `d_pre([happens(transfer(S,A,R),T1,T2), holds(balance(S,B),T1), B<A])`.
Times are written down only where a sentence has to relate two moments.

A time is an *ending added to a sentence*, not one of the places of a template.
The three older programs do it that way, and doing it that way is why a single
fluent template serves both `the reward is 0` in an `initially` sentence and
`the reward is a number at the first time` in a condition.

### 3.2 `initially`

```
    initially the reward is 0.
    initially the goat is at the north bank and the wolf is at the north bank.
```

→ `initial_state([reward(0)]).`, `initial_state([loc(goat,north), loc(wolf,north)]).`

### 3.3 Timeless facts and rules

An ordinary Logical English fact or rule, written over the templates declared
in `the templates are:`:

```
    scissors beats paper.
    *a place* is across from *another place* if …
```

→ a Prolog clause, or `l_timeless(Head, Conditions)` where the rule has
conditions and none of them mentions a time.

### 3.4 `when … then …` — causal laws

**`when` says what an event does.** The `when` half names exactly one event or
action — the trigger — and may add any number of further conditions. The `then`
half says how the state changes.

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

So the `then` half may take three shapes: a fluent, which starts holding; a
fluent said not to be the case, which stops holding; and `the <fluent> that is
<var> becomes <expression>`, which changes a value. Several of the three may be
joined with `and`, and one such sentence then gives several laws. A fluent that
stops holding may come first as well as last:

```
    when a person presses a button
    then it is not the case that the button is lit
        and the button is dark.
```

When writing laws back out as English, `le_lps_write.pl` (in `effects/3`)
gathers the effects of one event that share the same conditions into one
sentence, putting the fluents that start holding first.

### 3.5 `if … then …` — reactive rules

**`if` says what to do about it.**

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
→ `reactive_rule([holds(played(P1,C1),T1), holds(played(P2,C2),T1), P1 \== P2,
   beats(C1,C2), holds(not gameOver, T1)],
   [happens(initiate gameOver, T1, T2), holds(reward(Pz), T1),
    happens(pay(P1,Pz), T1, T3)]).`

`initiate <fluent>` and `terminate <fluent>` in a `then` half are effects that
take place at once, written `happens(initiate F, …)` and
`happens(terminate F, …)`.

Whether a conclusion after `then` is an action to perform or a condition to
check is settled by how the template was declared, not by where the conclusion
stands. A template declared an action or an event becomes `happens/3`; a
template declared a fluent becomes `holds/2`.

**When the conclusions happen.** The engine runs a Logical English program
exactly as it runs the same program written in the older form, cycle by cycle:
[`lps.md` §13a](lps.md#13a-how-a-program-runs-step-by-step) gives the order of
the steps, which goal goes first, and when a run fails. One difference in how
the two forms are *written* matters a great deal, because a conclusion with no
time of its own takes the time of the conditions (§3.1):

```
    if the guest is waiting
    then the guest enters.
```

is `reactive_rule([holds(waiting,T1)], [happens(enters,T1,T2)])`. The guest
must enter in the very cycle in which the rule fired. If a constraint forbids
the entry in that cycle — say, `it must not be true that the guest enters and
the door is locked`, while the door is locked — the goal cannot be met, and the
run ends in `failure`. To let the action wait until the constraint allows the
action, give the conclusion times of its own:

```
    if the guest is waiting at a first time
    then the guest enters from a second time to a third time.
```

The guest then enters in the first cycle in which the door is not locked.

A condition that is an event needs its times written as well. In

```
    if the door opens
    then the guest enters.
```

the conclusion starts when the door *starts* opening, which is a cycle that
has already passed by the time the engine learns that the door opened, so the
run fails. Write instead:

```
    if the door opens from a first time to a second time
    then the guest enters from the second time to a third time.
```

The guest then enters in the step after the door opens.

### 3.6 Intensional fluents and composite events

A Logical English rule whose conclusion carries one of the time endings of
§3.1:

```
    the players are a number N at a time if
        N is the sum of each V such that
            a player has played V at the time.
```
→ `l_int(holds(num_players(N), T), [holds(findall(V, [holds(played(P,V),T)], L), T), sum_list(L, N)]).`

The aggregate — a condition that gathers many answers into a single value — is
Logical English's own (`le_summary.md` §5). The result and the thing being
gathered are both given names, `N` and `V` above, and the condition after
`such that` goes on a line of its own, indented. Written on the same line as
the rest, or with the gathered thing written as "each a value", the sentence is
read as a plain "is" and the run fails. What the aggregate gathers over is the
lines indented under it and nothing more, so a condition written back at the
level of the sentence's other conditions (`    and N > 5`) comes after the
aggregate rather than inside it — and that holds when the aggregate is the
first condition, on the `if` or `when` line, as much as anywhere else.

An aggregate is worked out at the time at which its own condition reads the
state. Where that condition carries no time, the aggregate takes the sentence's
time. Where the condition names a time, as `… at the first time` does, the
aggregate takes the time named. So `if a player has played a value at a first
time and N is the sum of each V such that a second player has played V at the
first time …` gives `holds(findall(V, [holds(played(P2,V),T1)], L), T1)`.

```
    a player pays a prize from a first time to a second time if
        an account is credited with the prize at the first time
        and the account is settled from the first time to the second time.
```
→ `l_events(happens(pay(P,Pz), T1, T2), [ … ]).`

An `at` ending gives `l_int`; a `from … to …` ending gives `l_events`. The
ending is *checked* against the declarations: a conclusion whose template was
declared a fluent has to use `at`, and a conclusion whose template was declared
an event or an action has to use `from … to …`.

### 3.7 `it must not be true that …` — integrity constraints

```
    it must not be true that
        a player inputs a choice and an amount from a first time to a second time
        and the amount <= 0.
```
→ `d_pre([happens(inputs(P,C,A), T1, T2), A =< 0]).`

A constraint that names no event constrains every state, and is called an
**invariant**. The total supply of a token, for instance, is the sum of all its
balances:

```
    it must not be true that
        the total supply is an amount T at a time
        and S is the sum of each B such that
            the balance of an account is B at the time
        and S is different from T.
```

A call that would break a constraint — an invariant, or a condition that has to
hold before an action may happen — is refused entirely, and the refusal is
recorded. The timeline in the IDE, the editor where programs are written and
run, shows the refused call crossed out. Asking `why_not(happened(A), T)`
answers `refused_by_constraint`, and names both the constraint that refused the
call and the values it held on.

### 3.8 `the goal is that …` — planning

```
    the goal is that the goat is at the south bank and the wolf is at the south bank.
```
→ `achieve(loc(goat,south) & loc(wolf,south)).`

A document with a goal also needs the line `:- lps_engine(planning).`, and
`le_lps.pl` writes that line for you. Stating a goal is precisely how a
document says that the program is a planning problem.

### 3.9 Observations

A scenario is a list of events, each with its time:

```
scenario one is:
    miguel inputs rock and 1000 from 1 to 2.
    bob inputs paper and 1000 from 1 to 2.
```
→ `observe([inputs(miguel,rock,1000)], 2).` and one more.

`observe/2` is given the *end* time, which is why `from 1 to 2` produces `2`.
`miguel inputs rock and 1000 from 1` and `… at 1` say the same thing, because
an observed event or action cannot be broken into smaller ones and so ends one
moment after it starts. A scenario sentence with no time on it is an error, not
a fact at time 0. An observation with no time means nothing in LPS, and quietly
placing one at the start of the run would be worse than saying so.

### 3.10 Budgets, and the size of a whole number

Four templates are built in for one purpose: to let a program say what the
**contract it is deployed as** may cost to run, and where its arithmetic stops.
All four are used as ordinary conditions of an ordinary `it must not be true
that` sentence.

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

`transfer` there is the action's own name — the one `; known as transfer`
gives it.

**The four budgets are read when the program is deployed, not while it runs.**
*Misc ▸ Deploy as Solidity* writes the contract, compiles it, and replays the
program's own scenario on an EVM — the Ethereum Virtual Machine, the machine
that runs contracts. Each budget is then compared with what was measured, and a
budget that is exceeded **stops the export**, naming the call and the figure. A
run has no contract to measure and no gas to spend, so running a program that
states a budget says that the figure is not modelled rather than letting the
sentence go by in silence. Two limits are checked whether the program states
them or not, because neither is a matter of preference: **EIP-170**'s 24,576
bytes of deployed code, above which a contract cannot be deployed at all, and
**EIP-7825**'s limit of 2^24 gas for a single transaction, above which a call
can never be included. The gas limit of a *block* is not one of those two,
because the validators vote on it, so that limit is reported as a figure with a
usual value and never enforced.

The fourth template is about arithmetic:

```
    it must not be true that
        a depositor deposits an amount
        and the balance of the depositor is a second amount
        and the largest whole number is a third amount
        and second amount + amount > the third amount.
```

A whole number in Logical English has no upper limit. In a contract the same
number is a `uint256`, which does have one, and since Solidity 0.8 an addition
that passes that limit no longer wraps round to zero: the whole call is undone
instead. Without the sentence above, the program and the chain disagree about
what the call does, and nothing points the disagreement out. With the sentence
in place the two agree: the program refuses the deposit and the contract undoes
the call. The exporter recognises the bound as the very one `pragma ^0.8`
already enforces at that `+`, and so does **not** write it out a second time as
a check of its own.

Where a program does arithmetic with no such bound stated, *Deploy as Solidity*
lists every place in its notes and offers the sentence that would close the
gap. *Deploy as Solidity* never writes such a sentence into the document
itself.

### 3.11 `display`

```
    the balance of a person that is an amount is drawn as
        a rectangle from [*x*, 0] to [*right*, *amount*] labelled the person if …
```

is **not** part of this language. A `display/2` clause is a Prolog term holding
a list of properties. Writing such a list out in English gains nothing, and a
companion `.lps` file (§7) is the right home for the drawing clauses.
`examples/le/badlight.le` therefore has a `badlight.lps` beside it, and that
pairing is the documented answer.

---

## 4. Conditions

Everything LE2 already reads works unchanged among the conditions of a rule:
`and`, `or`, `it is not the case that`, `for all cases in which … it is the
case that …`, aggregates (`is the sum of each … such that …`), comparisons,
arithmetic and lists. A law's conditions are no different from any other
sentence's:

```
    when a sender airdrops an amount to a list
        and a recipient is in the list
        and N is the count of each E such that
            E is in the list
            and E is equal to the recipient
    then the balance of the recipient that is a second amount becomes second amount + amount * N.
```

(A list is a value like any other, in an observation as much as in a rule:
`alice airdrops 5 to [bob, carol, bob] at 3`. Because the balance has a
default, bob — who appears in the list twice — makes one instance of the law
and is credited 10: an update law of a fluent with a default runs once for each
*distinct* answer.) What §3.1 adds to all this is the ending that names a time.
What `le_lps.pl` adds is a decision, taken for each condition on its own,
between `holds/2`, `happens/3` and a plain Prolog goal:

| the condition's template was declared as | becomes |
|---|---|
| a fluent | `holds(F, T)` — or `holds(not F, T)` under a negation |
| an event, action or prolog event | `happens(E, T1, T2)` |
| a timeless template, or one of Logical English's own built-in conditions | the goal itself, with no time |

A fluent or an event written inside a rule with no time of its own takes the
rule's time: a condition takes the time its fellow conditions share, and a
sentence in a `when` law takes the times of the triggering event.

---

## 5. The prospective form

`docs/project/plans/le_lps_design.md` §6 called the prospective form the one genuinely open
problem, and made writing it the test this language had to pass. The example
comes from `prospectiveGoat.pl`:

```prolog
false loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T, row(_,_) to T.
```

`row(_,_) to T` pins `T` to the state that a crossing would *leave behind*. The
constraint is therefore about a state that does not exist yet, and that is
described by the action being considered.

**The form can be said in English, using the third of §3.1's endings.** The
sentence is:

```
    it must not be true that
        a crossing happens to a time
        and the goat is at a place at the time
        and the wolf is at the place at the time
        and it is not the case that the farmer is at the place at the time.
```

→ `d_pre([happens(row(_,_), _, T), holds(loc(goat,L), T), holds(loc(wolf,L), T),
   holds(not loc(farmer,L), T)]).`

`… to a time` with no `from` is exactly `row(_,_) to T`: an event whose end is
the moment being constrained and whose start goes unmentioned. Read the
sentence aloud — "it must not be true that a crossing happens *to* a time and,
*at* that time, the goat and the wolf are together without the farmer" — and
the reading says what the constraint means.

The test is therefore passed, and the limit on scope set in §I.9.6 is narrower
than `docs/project/plans/le_lps_design.md` feared. What this language does *not* cover is
listed in §7.

---

## 6. The programs

The programs live in `examples/le/`, among LPS2's own files (until 2026-09 they
were LE2's `examples/lps/`, and LE2 still keeps the translations they are
expected to produce in `testing/fixtures/lps/`). There are the fifteen listed
below, plus `token.le` and `fee_token.le`. Beside each `NAME.le` sits a
`NAME.expected.lpsw`, holding the internal form `le_lps.pl` has to produce; the
two are compared term by term with `variant/2`.

| program | what it is for |
|---|---|
| `rock_paper_scissors_minimal.le` | the first specimen: events, actions, fluents, updates, denials |
| `rock_paper_scissors_base.le` | the second specimen: aggregates, initiate, ordinals |
| `rock_paper_scissors_ethereum.le` | the third specimen: prolog events, composite events, `l_int` |
| `goat.le` | composite events, recursive decomposition |
| `prospective_goat.le` | the prospective form — the acceptance test (§5) |
| `goat_declarative.le` | `achieve`, planning mode |
| `badlight.le` | `display/2` via a companion `.lps` (§3.11, §7) |
| `bank_transfer.le` | the canonical "contract" shape |
| `dining_philosophers.le` | concurrent actions, preconditions over action sets |
| `fire_simple.le` | the smallest interesting reactive rule |
| `map_colouring.le` | timeless-heavy, little state |
| `loan_agreement.le` | real-time, dates, a legal text behind it |
| `escrow.le` | multi-party, obligations |
| `delivery_delay.le` | deadlines and elapsed time |
| `life.le` | intensional fluents over a grid — the stress case |
| `token.le` | `; 0 by default`, a named constant, times left out, a labelled law, an airdrop over a list |
| `fee_token.le` | `extends token`, and a law that replaces the base's |

All seventeen programs translate, and `testing/lps_test.pl` checks each
translation against what was expected. Fifteen of them also survive the **round
trip** — `LE → internal → LE → internal`, English to the internal form, back
to English, and into the internal form once more, with the two internal forms
equal term by term under `variant/2` (`testing/lps_roundtrip.pl` runs the
check, and `le_lps_write.pl` says what the round trip does and does not
claim). The two that do not survive
it are `delivery_delay.le` and `loan_agreement.le`, both for the same reason,
which the test records beside them: a calendar date appears as a *constant*
(`2018-04-01`), and a date written as a constant has no form of its own in
Logical English, so it cannot be written back out.
 Fifteen also *run* to `success` under LPS2
(`./lps run examples/le/NAME.le` with `LPS_LE2_DIR` set). The two that do not:

- `prospective_goat.le` ends in `failure`, and so does the original,
  `legacy_lps1/examples/forTesting/prospectiveGoat.pl`, under the same engine.
  Agreeing with the original is the point.
- `rock_paper_scissors_minimal.le` ends in `failure` where the original ends in
  `terminated(unknown)`. The original has one rule this version lacks —
  `If a number is sent to some body from T1 to T2 then lps_terminate from T2 to
  T3` — and `lps_terminate` is an instruction to the engine with no form in
  English. Rather than invent one, the difference is recorded here.

---

## 6a. Turning an older program into a document

An LPS program written in the older, Prolog-like syntax — a `.lps` file — can
be written out as a Logical English document, and the two then say the same
thing. Two ways to ask for it:

- in the IDE, **Misc ▸ Convert to Logical English…**, which opens the document
  in a new tab named after the program, ending in `.le`. Save it where you
  want it;
- at the command line, `lps le PROGRAM`, which writes the document to the
  screen, or to a file with `--out FILE`.

The older syntax has no templates, so the converter writes one for every
relation the program mentions, taking the words from the relation's own name:
`pick_up(Who, What)` becomes `*a thing* picks up *a second thing*`, and the
template is tied back to the name with `; known as pick_up`. The words are a
guess about English; the tie is what carries the meaning. That is why the
converted document runs exactly as the program did, and `tools/lps_to_le_test.pl`
checks it by running both and comparing what happened, cycle by cycle.

You can keep both files side by side. A document written by the converter says
so on its first line:

```
% lps-converted-from: fox_crow.lps
```

and that line is what stops the engine from reading the older file as the
document's companion (§7) and running every rule twice.

**What the converter cannot carry over, and says so rather than guessing.**
Each of these is reported before the document is written, and is a limit of
this surface language rather than of the conversion:

| What | Why | What to do |
|---|---|---|
| the planning engine's settings, `:- lps_engine(planning, [search(...), horizon(...), max_concurrency(...)])` | a document with a goal asks for the planning engine by itself (§3.8), but not with these settings | keep the line in a companion `.lps` file |
| drawing rules, `display/2` and `display3d/2` | a list of shapes and coordinates (§3.11) | the same |
| one name used for two kinds of thing — `temperature` as both an event and a fluent | here, a sentence is an event, an action or a fluent because of the section its template stands in, and one name cannot stand in two sections | rename one of them, or keep the program in the older syntax |
| a term inside a term, such as `command(open(case))` | a place of a sentence holds a name, a number, a date or a list | rewrite the relation with one place per part |
| `updates` where the value that changes is not the relation's last place | an update is said as `... that is <the old value> becomes <the new one>`, which can only change the last place | put the changing value last |

Five `.lps` files in `examples/le/` are the *companions* of Logical English
documents rather than programs of their own. The converter refuses those and
says which document to read instead.

---

## 7. What is out of scope, and why

These limits are stated rather than worked around, as §I.9.6 asks.

- **`display/2`.** A list of shapes, colours and coordinates. See §3.11. Write
  it in the companion file.
- **Prolog written out directly.** `findall/3` with a goal written by hand,
  `is/2` over a predicate from a library, anything at all that reaches outside
  the templates. Write it in the companion file, which is the course
  `docs/project/plans/le_lps_design.md` §5 recommended as choice (ii).
- **Priorities among rules.** `reactive_rule/3` has no form in English, and
  none of the older programs uses a priority.
- **`unserializable/1`.** An instruction about tracing, not a statement about
  the subject the program is written about.
- **Real-time settings other than the three in §2.** The `simulatedRealTime*`
  settings are controls for running tests.
- **`lps_terminate` and the other system actions.** Each one is an instruction
  to the engine rather than a statement about the subject the program is
  written about. See the note on `rock_paper_scissors_minimal.le` in §6.

Two further limits come from LE2 rather than from LPS, and both are worth
knowing before you start writing:

- **What you add up or multiply has to be written as a bare name.** Write
  `a total = price + tax`, not `a total = the price + the tax`. That is how LE2
  has always read arithmetic (`examples/moreExamples/numbers.le`). Write
  comparisons with symbols as well, as in `the amount >= 10`. Spelled out,
  `is greater than or equal to` cannot be told apart from `is greater than`
  when LE2 matches the words of a template, and the shorter one wins.
- **A template may not contain a word that starts a section** — `contract`,
  `knowledge`, `templates`, `fluents`, `events`, `actions`, `predicates`,
  `ontology`, `target` — because LE2 takes such a word for the start of a new
  section and then reports the template as cut short. Write `the lender calls
  off the loan`, not `the lender cancels the contract`.

The rule for companion files is this. `foo.le` and `foo.lps` are compiled
together, the `.le` half first. The `.lps` half is written in the ordinary,
Prolog-like syntax of LPS, and the editor treats it as an ordinary `.lps` file.
Nothing is smuggled through the English.

## 8. What has no LPS reading is refused

A document is translated into LPS whole, or not at all. As soon as one issue is
an error — a mistake of the document's own, or a construct with no reading in
LPS — `le_lps_module/5` writes **no LPS text** at all, and nor do the things
that call it: `getLps`, LPS2's `le_compile`, Deploy as Solidity and the
exporters that read the LPS translation. The issues then say why, each one
attached to the sentence it belongs to. An LPS program that meant something
other than its document would be worse than no program at all.

The part that writes the LPS text turns the conditions LPS can run —
comparisons, arithmetic, asking whether something is in a list, aggregates
(§4) — into LPS's own forms. Any other condition is passed through untouched
and with no time, and LPS2 would then call that condition as a relation of the
program. So whatever is left of Logical English's own vocabulary is caught
before any text is written, and reported as the error `not_lps`
(`not_lps_issues/3`):

- `for all cases in which … it is the case that …`, which says something about
  every case at once, and any other condition that could not be turned into an
  LPS form;
- the built-in conditions of Logical English that LPS has nothing to match:
  arithmetic on dates (`… days after …`), decision tables and
  `the minimum of …` — in short, any `le_` goal still left standing;
- a condition on a template the reader may assume (`; unknown`) or judge for
  itself: LPS assumes nothing, so such a condition would simply fail;
- a condition answered by an outside service (`; via service`).

Every other conversion of a program into another language refuses in the same
way (docs/dev/migration.md, "Exporting: the check before the text").
