# Daml and LPS

*Kind: integration guide · Audience: users · Status: current (2026-10-18)*

Daml is the smart-contract language of Canton. A smart contract is a contract that a
computer program does. Canton is a network of ledgers that Digital Asset made for
financial institutions. A ledger is a shared record of contracts. A Daml program is a
set of *templates*. Each template describes a kind of contract, for example an IOU
(a written promise to pay a debt) or an asset. The template also gives the fields of
that contract.

Each template also tells who must sign the contract (`signatory`) and who can see the
contract (`observer`). It also tells which *choices* a named party (the
`controller`) can exercise on the contract. A choice can archive the contract and
make new contracts. Daml Scripts are the tests of a project. A Daml Script is a
sequence of commands that parties send to a ledger.

The connection between Daml and LPS (Logic Production System) operates in the two
directions:

- **File ▸ Open…** changes Daml source into a program in Logical English for LPS. It
  uses the first Daml Script of the project as the scenario of that program. A
  scenario is the sequence of events that the program receives. LPS2 then runs the
  program.
- **Misc ▸ Export to another system…** operates in the opposite direction. It writes
  a Logical English for LPS program as a Daml module with a Daml Script.

The two directions use translators that are part of the Logical English
installation. Thus the two directions need LE2, the Logical English editor, next to
LPS2 (`LPS_LE2_LIB`, refer to [Logical English](../guide/ide.md#logical-english)).
They also need the Logical English Translators. The hosted service has this
installation. Without those translators, a `.daml` file opens as plain text. The
export menu item then says that nothing can write the document.

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [The twins among the examples](#the-twins-among-the-examples)
  - [Opening your own Daml](#opening-your-own-daml)
  - [Running a twin](#running-a-twin)
  - [Exporting to Daml](#exporting-to-daml)
- [How Daml maps to LPS](#how-daml-maps-to-lps)
  - [Contract ids are named by the scenario](#contract-ids-are-named-by-the-scenario)
  - [Authorisation is a set of constraints](#authorisation-is-a-set-of-constraints)
  - [Scripts are scenarios](#scripts-are-scenarios)
  - [The way back: one State contract](#the-way-back-one-state-contract)
- [Traps](#traps)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| Daml into LPS | **File ▸ Open…**; the twins with **File ▸ Open example from server…** | `.daml` source (Daml 3) | a Logical English for LPS program, the *twin*. Templates become fluents. Creates and choices become actions. The rules about who can act become integrity constraints. The first Daml Script becomes the scenario. | Daml itself. We ran each script on a local Canton sandbox. We compared its final active contracts with the final state of the twin in LPS2. 18 of 22 scripts end in the same state. The other 4 are different for known reasons (refer to [Traps](#traps)) |
| LPS into Daml | **Misc ▸ Export to another system…** (on a `.le` document), then *Daml (Canton)* | a Logical English for LPS program | `Main.daml`: one `State` contract, one choice for each action, and the scenario of the program as a Daml Script. You can copy or save the result. | Canton again. We built the exported module and ran its script on a sandbox. We compared the final `State` with the final state in LPS2. They agree for all 22 twins and for the two token programs in the Logical English examples of LPS2 |

## How to use it

### The twins among the examples

We translated all the sample projects of the Daml SDK (software development kit).
The translations are the *twins*. They are in `examples/migration/daml/`, with one
folder for each project:

| Folder | Daml project | What it shows |
|---|---|---|
| `skeleton` | the skeleton of the SDK | an asset that its owner gives to a different party |
| `token` | Daml intro, Daml Scripts | tokens that a party can issue only to itself; `submitMustFail` |
| `simple_iou`, `contact` | Daml intro, choices | consuming and nonconsuming choices |
| `restrictions` | Daml intro, constraints | `ensure`, `assert`; time, as residue |
| `parties` | Daml intro, parties | signatories and controllers |
| `quickstart` | the quickstart IOU | issue, transfer, split, merge, and a delivery-versus-payment trade |
| `compose` | Daml intro, composing choices | nested exercises, one program for each script |
| `coin_issuance`, `locking`, `multiparty` | `daml-patterns` | locking, delegation, agreement of more than one party |

Open a twin with **File ▸ Open example from server…**. The list shows the folders as
*daml twin: skeleton*, *daml twin: token*, and so on. A project with more than one
script gives one program for each script. The first program is `<project>.le`. Each
other script gives `<project>_<script>.le`. That program
[extends](../reference/le-for-lps.md#11-extends--a-knowledge-base-built-on-others)
the first program and has its own scenario. For example,
`quickstart_trade_test.le` starts with this line:

```
the knowledge base quickstart_trade_test extends quickstart.
```

The folder of each twin also contains these files:

- `sources/`. This folder contains the Daml files from which we made the twin,
  without change, with the notice of Digital Asset and the Apache 2.0 licence.
  **View ▸ The original this was converted from** shows those files, one after the
  other, each below its name.
- `<twin>.ledger.md` (and `.json`), the *ledger*. The ledger gives each element of
  the Daml source with its verdict. *Encoded* means translated with no change of
  meaning. *Approximated* means translated with a change of meaning that the ledger
  records. *Residue* means not translated. The dialog of examples does not show the
  ledgers. Read a ledger in the files of the project.

Good first programs are `skeleton/skeleton.le` (three commands), `token/token.le`
(commands that Daml refuses), and `quickstart/quickstart_trade_test.le` (a trade
made from nested exercises).

### Opening your own Daml

Do these steps:

1. Select **File ▸ Open…**.
2. Select a `.daml` file.

The server gives the file to the Daml translator. The status line says *converted*,
or it gives the number of conversion notes. The notes are in a comment at the top of
the document. They are the counts of the ledger, for example
*main: 4 source elements encoded, 1 approximated, 0 residue.*

A new tab opens, with the name of the module (`Main.daml` becomes `main.le`). The
comment at the top tells what the program is and how contract ids operate.
**View ▸ The original this was converted from** shows the Daml that you opened.

All parts that the translator did not translate stay in the program between
markers. The markers also give the reason and the original Daml text:

```
% RESIDUE simple_iou_choice_1 BEGIN: choice
% TODO: translate the fragment below by hand, or with the Contract Assistant (residue mode); it was not translated automatically
% inside the template, outside the subset (a key, an interface instance, a choice the reader did not parse)
%   daml:
%   | choice Redeem
% RESIDUE simple_iou_choice_1 END
```

The file dialog also accepts a `.zip` file. With a `.zip` file, you can open all of a
Daml project at one time. The translator reads all the modules of the project
together. Thus a script in `Test.daml` becomes the scenario of the templates in
`Main.daml`.

### Running a twin

A twin is a usual Logical English for LPS document. Click **Run**, go through the
cycles one step at a time, and ask why, as with all programs (refer to
[the editor guide](../guide/ide.md#running-a-program)). Each command of the script is
one action in one cycle. A command that Daml refuses, for example a
`submitMustFail`, is an action that LPS2 refuses. The timeline shows the refused
action with a red line through it. When you ask why (refer to
[Asking why](../guide/ide.md#asking-why)), the answer gives the constraint that
refused the action.

The comment of the scenario gives the contracts that are still active in Daml at the
end. Thus you can compare those contracts with the final state of the twin:

```
% Daml (the script run on a Canton sandbox) ends with these active contracts (their payloads;
% the ids are the ledger's):
%   - asset(alice,alice,"TV")
```

To see who can do what, open **View ▸ Legal view: who may do what (Logical
English)**. The legal view changes the integrity constraints of each action into one
permission rule. It changes each causal law into an effect. The result is a timeless
Logical English program in its own tab. You ask questions about that program in the
LE2 editor.

### Exporting to Daml

Do these steps:

1. Open a Logical English document with the target language `lps`. This can be a
   twin, or a document of your own.
2. Select **Misc ▸ Export to another system…**.
3. Possibly more than one writer can translate the document. LegalRuleML is
   frequently also available. In that case, select *Daml (Canton): the program as
   one State contract, each action a choice, with its scenario as a Daml Script
   (.daml)*.

If the program can be written correctly, a window with the title
*Exported as Daml (Canton)…* shows `Main.daml`. The window has the buttons **Copy**
and **Save…**. The note of the window tells how to run the module:

- Put the module in a Daml package.
- Run `dpm build`.
- Run `dpm sandbox`.
- Run `dpm script` with `--script-name Main:scenario`.

The script gives the final `State`. Daml has no public sandbox in the browser. Thus
the window gives no link to open.

If the program cannot be written correctly, the writer writes nothing. A window with
the title *Export as Daml (Canton)… — not translatable* gives each problem. For each
problem, the window shows its line as a link, the words of the program at that line,
and the reason. For example, LPS2 refuses `examples/le/bank_transfer.le` because of
its reactive rules and two constraints:

```
line 19 — a reactive rule (if ... then the program acts on its own) whose condition is an event, or whose conclusion is not a list of actions: Daml has no agent watching events — a Daml trigger would be one
line 38 — a constraint relating two actions at once: Daml submits one command at a time
```

`examples/le/token.le` and `examples/le/fee_token.le` export without change. The two
finance examples, `examples/finance/interest_rate_reset/` and
`examples/finance/trade_lifecycle_record/`, also export, with their Daml companions
(below).

## How Daml maps to LPS

| Daml | Logical English for LPS |
|---|---|
| `template Asset with issuer, owner, name` | a fluent with the contract id as its key, and the fields as its other places: `*an asset* is an asset with issuer *an issuer*, owner *an owner* and name *a name*` (a record field becomes flat: `iou : Iou` gives `iou issuer`, `iou owner`, …) |
| `create` | an action of the party that sends the command. The action initiates the fluent: `*a party* creates the asset *an asset* with issuer *an issuer*, owner *an owner* and name *a name*` |
| `choice Give with newOwner controller owner do …` | an action of the party that exercises the choice on a contract id: `*a party* exercises give on the asset *an asset* with new owner *a new owner* creating *a second asset*` |
| a consuming choice; `archive`; the implicit `Archive` choice | a causal law that terminates the fluent of the contract: `then it is not the case that the asset is an asset with …` |
| `create this with owner = newOwner` in a choice | the same law initiates the new contract: `then the second asset is an asset with issuer the issuer, owner the owner and name the name` |
| `fetch` | a condition that the contract is active |
| a nested `exercise` | put into the outer choice. A contract that the same transaction creates and consumes never gets to the state, as in Daml |
| `signatory` | a constraint. The party that sends a create, or the authorisers of the choice, must include all signatories: `and the party is different from the issuer` refuses the create |
| `controller` | a constraint that the party that exercises the choice is the controller |
| an archived contract that a party exercises again | a constraint that the contract is active: `and it is not the case that the asset is an asset with issuer a thing, …` |
| `ensure`, `assert`, `assertMsg`, `===` | constraints, one for each conjunct: `ensure name /= ""` becomes `and the name is equal to ""` |
| `observer` | not in the twin (approximated). Who can *see* a contract is part of the privacy model of Daml. It is not part of the state of the ledger |
| a Daml Script | a scenario with one command for each cycle, and parties as constants. `submitMustFail` is a command that LPS2 refuses. The scenario does not observe queries, `allocateParty`, user management and time (approximated) |
| other scripts of the project | separate programs that extend the first program |

### Contract ids are named by the scenario

In Daml, the ledger gives the contract ids. Each id is a long calculated code, a
hash. LPS cannot make new ids itself. Thus, for each contract that a command makes,
the twin changes the id of the contract into a *place of the action*. The scenario
gives the id, with the name that the script gave the contract:

```
scenario setup is:
    % the Daml Script setup
    alice creates the asset alice_tv with issuer alice, owner alice and name "TV" from 1 to 2.
    alice exercises give on the asset alice_tv with new owner bob creating bob_tv from 2 to 3.
    bob exercises give on the asset bob_tv with new owner alice creating c1 from 3 to 4.
```

A constraint refuses a create with an id that is already in use. When you write such
commands yourself, give each new contract a new name.

### Authorisation is a set of constraints

In Daml, the rules about who can do what are in different places: `signatory`,
`controller`, `ensure` and the ledger model. The twin gives each of those rules as
an `it must not be true that` sentence. Each such sentence gives again the command
that the rule controls:

```
it must not be true that
    a party exercises give on the asset an asset with new owner an owner creating a second asset
    and the asset is an asset with issuer an issuer, owner a second owner and name a name
    and the party is different from the second owner.
```

Thus a twin is frequently two or three times longer than its Daml source. The legal
view puts the constraints together again into one permission for each command.

### Scripts are scenarios

The commands of a script become observations, one command for each cycle. The
scenario does not observe some parts of a script. These parts are: the parts that
only look at the ledger (`query`, `queryContractId`), the checks, the user
management, and time. The ledger records each of those parts as approximated. A
command that Daml refuses has a comment:

```
    % Daml refuses the next command (submitMustFail): the twin's integrity constraints refuse it
```

### The way back: one State contract

Daml 3 has no contract keys. Thus nothing can find a Daml contract from the values of
an LPS fluent. For this reason, the writer puts all of the LPS state into **one**
contract:

- `template State` has an `operator` party as its signatory, and all the parties of
  the program as observers. Each fluent is a list of records. A fluent with no
  places is a `Bool`, a value that can only be true or false.
- Each action is a choice of `State`. The controller of the choice is the party that
  does the action. That party is the first place of the action. If that place
  contains something that is not a party, the controller is the operator.
- An integrity constraint on an action is an `assertMsg` before the update. A
  constraint on states is an `assertMsg` on the new state.
- The causal laws make the update. The module calculates the terminations and the
  old values from the state before the action. Then it adds the initiations. Then it
  removes the duplicates (`dedup`), because a fluent is a set.
- `initially` is the `State` that the script makes. The scenario sends each observed
  action with `trySubmit`. Thus a refused action does not change the state, as in
  LPS2. The script gives the final `State`.
- The **rules** of the program become Daml **functions**. A rule is a sentence that
  is true when its conditions are true. An example is "the preceding business day
  for a trade of a date is a second date". Daml has no rules, but it has functions.
  When you ask a rule with some of its places known, the rule is a function. The
  function goes from those places to the list of the other places. Thus the rule
  above, asked with the trade and the date, becomes a function. The function takes
  the trade and the date, and gives the business day. The writer makes one function
  for each method that the program uses to ask a rule. Intensional fluents (fluents
  that a rule defines) and the tables of facts of the program become functions in
  the same way.
- A **reactive rule** ("if the next step of a trade is a step that is ready, then the
  trade performs the step") becomes a choice with the name `ReactiveCycle`. The
  operator exercises the choice. The choice does each action that the reactive rules
  ask for and that the constraints permit. The script exercises the choice one time
  for each cycle of LPS. The writer still refuses a reactive rule that waits for an
  event, not for a state. Such a rule needs a Daml *trigger*, a program that watches
  the ledger. The writer does not write triggers.

**The Daml companion.** Some programs give a small number of predicates to Prolog,
in a companion `.lps` file. These predicates are usually calendar arithmetic, for
example "the day before a date". The writer cannot translate Prolog. Write the same
predicates in Daml. Put them in a file with the name of the knowledge base and the
extension `.daml`, next to the program. For example, use `interest_rate_reset.daml`
for "the knowledge base interest rate reset". Possibly the file is missing, or a
function is not in it. Then the writer refuses the export. The message gives each
function that you must write, with its Daml type, for example
`dayBefore_fb : Date -> [Date]` ("the day before a date": `b` for the place that the
program knows, `f` for the place that it asks for).
`examples/finance/interest_rate_reset/interest_rate_reset.daml` is an example.

Record fields and choice arguments get their names from the places of the Logical
English templates (`issuer : Party`, `observersPartyList : [Party]`). The general
names `a1`, `a2`, … occur only for a relation that has no template.

The writer finds the types from the program itself. A place that holds a party that
does an action becomes a `Party`. A place that shares a variable with such a party
also becomes a `Party`. A number becomes a `Decimal`. A place that a law compares or
uses in a calculation also becomes a `Decimal`. A list becomes `[Party]` when one of
its members is a party. A list also becomes `[Party]` when the name of the place is a
list of parties (`*a party list*`). All other places become `Text`. A party that a
law names (`the treasury`) becomes a field of `State` that the script allocates. The
reason is that Daml cannot write the name of a party directly. A default value
(`0 by default`) is the value that the module uses when no record holds a value.

## Traps

- **The translator does not translate time.** `getTime`, `passTime`, `addRelTime`
  and a choice that uses the time of the ledger are all residue. `coin_issuance`
  does not have the lock that needs a maturity date. `restrictions` keeps IOUs that
  Daml redeems. We ran the scripts that set the time on the ledger of Daml Script
  itself, the ledger that it keeps in memory. We did not run them on Canton. The
  comment of the scenario tells which ledger gave the answer.
- **Four of the 22 scripts end differently in the twin. We expect this:**
  - `restrictions`: time, a `case`, and the text functions `T.length` and
    `T.isUpper` in an `ensure`.
  - `compose_test_trade`: the script gives a value that it read from the ledger
    (`queryContractId`) to a create.
  - `coin_issuance`: time.
  - `multiparty`: `Sign` uses `elem` on a helper function, and `Finalize` compares
    sorted lists. Thus the twin ends with the `Pending` contract. Daml changes that
    contract into an `Agreement`.

  The comments of the scenarios of those four scripts still give the final state of
  Daml. Thus you can see the difference yourself.
- **Residue** is the parts that stay in the program with a marker. The translator
  never removes them without a message. Residue includes contract keys, interfaces
  and `implements`, `case`, type classes and `instance` declarations, data types that
  are not records, and helper functions that choices call. It also includes choices
  that add to a list in a field (`newObserver :: observers`). The ledger gives the
  reason for each one.
- **The translator cannot translate Daml Finance.** The Daml Finance templates use
  interfaces that come as built packages, not as source. Thus the translator can see
  the calls, but it cannot see what the calls do.
- **The twin does not keep the observers.** The twin does not show who can see a
  contract. The legal view and the constraints are about who can *act*.
- **A `.daml` file alone has no scenario, unless it contains a script.** The
  `Main.daml` of the skeleton alone gives the fluents, laws and constraints. But the
  script of the skeleton is in `Test.daml`. You can select more than one `.daml`
  file at the same time in **File ▸ Open…**. But the server still converts each file
  separately, not as one project. To open a project with more than one module, put
  the project in a zip file, and open the `.zip` file.
- **Export refusals.** The writer writes nothing for a program that has one of these
  items:
  - a reactive rule that waits for an event (a Daml trigger can do this).
  - a reactive rule that does an action of a party (in Daml, only that party can do
    the action, not the cycle of the operator).
  - composite events.
  - a constraint that connects two actions.
  - a goal to achieve (Daml has no planner).
  - a place that holds a party in one sentence and a list in a different sentence.
  - a predicate that the program gives to Prolog, with no Daml companion.
  - an error in the LPS reading of the program.

  The writer still refuses most of the Logical English examples of LPS2. The usual
  reasons are reactive rules that wait for events, and composite events. Of the 19
  examples in `examples/le/`, 2 export. The two finance examples export.
- **The cycle does the actions of one cycle one after the other.** LPS does the
  actions of one cycle together, each on the state before the cycle. The
  `ReactiveCycle` of the module does them one at a time. Each action uses the state
  that the action before it made. The two methods give different results only when
  actions of the same cycle have an effect on each other.
- **The exported module shows that the translation in the two directions operates.
  The module is not the Daml that you put into service.** One contract holds all the
  fluents. All parties see all data. Each choice consumes that one contract and makes
  it again. Thus commands that come at the same time compete for the contract. Long
  `assertMsg` expressions check the choices. A Daml author writes choices
  differently.
- **A list is `[Party]` only when the program says so.** A list gets the type
  `[Party]` when the program puts a party into the list. It also gets this type when
  the program puts a member of the list in the place of a party. It also gets this
  type when the name of the place is a list of parties
  (`*an observers party list*`, the name that a twin gives to a Daml `[Party]` field).
  All other lists get `[Text]`. This includes a list whose members the program never
  shows.
- **Contract ids are `Text` in the direction back to Daml.** The ids of a twin
  (`alice_tv`) become text fields of the records, not Daml `ContractId`s. The reason
  is that the exported program has only one contract.
- **Numbers are `Decimal`.** The Daml `Decimal` keeps a fixed number of decimal
  places, ten. LPS numbers have no such limit. Thus a program that needs exact
  fractions or very large whole numbers can end in a different state.

## See also

- In this documentation:
  - [Other systems: the overview](index.md)
  - [Solidity and LPS](solidity.md), the other smart-contract language, with
    **Misc ▸ Deploy as Solidity…**
  - [Drools and LPS](drools.md)
  - [Logical English for LPS](../reference/le-for-lps.md), specially
    [integrity constraints](../reference/le-for-lps.md#37-it-must-not-be-true-that---integrity-constraints),
    [observations](../reference/le-for-lps.md#39-observations) and
    [what has no LPS reading](../reference/le-for-lps.md#8-what-has-no-lps-reading-is-refused)
  - [Using the editor: the menus](../guide/ide.md#the-menus) and
    [Logical English](../guide/ide.md#logical-english)
  - [Glossary](../reference/glossary.md)
- In the Logical English IDE:
  - [Other systems: importing and exporting](https://le2.logicalcontracts.com/docs/user/integrations/index),
    specially [what could not be translated](https://le2.logicalcontracts.com/docs/user/integrations/index#what-could-not-be-translated)
    and [when an export is refused](https://le2.logicalcontracts.com/docs/user/integrations/index#when-an-export-is-refused)
  - [Logical English for LPS](https://le2.logicalcontracts.com/docs/user/reference/lps-target)
- The documentation of Daml:
  - [The Daml repository](https://github.com/digital-asset/daml) (Apache 2.0)
  - [Daml documentation](https://docs.daml.com/)
  - [The Canton repository](https://github.com/digital-asset/canton)
  - [Canton Network](https://canton.network/)
