# Daml and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Daml is the smart-contract language of Canton, a network of ledgers that
Digital Asset built for financial institutions. A Daml program is a set of
*templates*. Each template describes a kind of contract, such as an IOU or an
asset, and lists the fields that contract holds. Each template also says who
must sign the contract (`signatory`), who may see the contract (`observer`),
and which *choices* a named party (the `controller`) may exercise on the
contract. A choice can archive the contract and create new ones. Daml Scripts
are the tests of a project: sequences of commands that parties submit to a
ledger.

The link between Daml and LPS (Logic Production System) works both ways.
**File ▸ Open…** turns Daml source into a program in Logical English for LPS,
takes the project's first Daml Script as that program's scenario, and LPS2 then
runs the program. **Misc ▸ Export to another system…** goes the other way, and
writes a Logical English for LPS program out as a Daml module with a Daml
Script. Both directions use translators belonging to the Logical English
installation, so both need LE2, the Logical English editor, to sit beside LPS2
(`LPS_LE2_LIB`, see [Logical English](../guide/ide.md#logical-english)) with
the InsurLE extensions, as on the hosted service. Without those translators a
`.daml` file opens as plain text, and the export menu item says that nothing
can write the document out.

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
| Daml into LPS | **File ▸ Open…**; the twins through **File ▸ Open example from server…** | `.daml` source (Daml 3) | a Logical English for LPS program, the *twin*: templates as fluents, creates and choices as actions, who may act as integrity constraints, the first Daml Script as the scenario | Daml itself: each script run on a local Canton sandbox, and its final active contracts compared with the twin's final state under LPS2. 18 of 22 scripts end in the same state. The other 4 differ for stated reasons (see [Traps](#traps)) |
| LPS into Daml | **Misc ▸ Export to another system…** (on a `.le` document), then *Daml (Canton)* | a Logical English for LPS program | `Main.daml`: one `State` contract, one choice per action, and the program's scenario as a Daml Script, shown to copy or save | Canton again. The exported module is built and its script run on a sandbox, and the final `State` is compared with LPS2's final state. This holds for all 22 twins and for the two token programs among LPS2's Logical English examples |

## How to use it

### The twins among the examples

The Daml SDK's own sample projects have all been translated. The translations
are called the *twins*, and they live in `examples/migration/daml/`, one folder
per project:

| Folder | Daml project | What it shows |
|---|---|---|
| `skeleton` | the SDK's skeleton | an asset its owner gives away |
| `token` | Daml intro, Daml Scripts | tokens a party may only issue to itself; `submitMustFail` |
| `simple_iou`, `contact` | Daml intro, choices | consuming and nonconsuming choices |
| `restrictions` | Daml intro, constraints | `ensure`, `assert`; time, as residue |
| `parties` | Daml intro, parties | signatories and controllers |
| `quickstart` | the quickstart IOU | issue, transfer, split, merge, and a delivery-versus-payment trade |
| `compose` | Daml intro, composing choices | nested exercises, one program per script |
| `coin_issuance`, `locking`, `multiparty` | `daml-patterns` | locking, delegation, multi-party agreement |

Open a twin with **File ▸ Open example from server…**. The folders are listed
as *daml twin: skeleton*, *daml twin: token* and so on. A project with several
scripts gives one program per script. The first program is `<project>.le`. Each
further script gives `<project>_<script>.le`, a program that
[extends](../reference/le-for-lps.md#11-extends--a-knowledge-base-built-on-others)
the first and has its own scenario. For example,
`quickstart_trade_test.le` starts:

```
the knowledge base quickstart_trade_test extends quickstart.
```

Each twin's folder also holds:

- `sources/`, holding the Daml files the twin was made from, unchanged, with
  Digital Asset's notice and the Apache 2.0 licence. **View ▸ The original this
  was converted from** shows those files, one after another, each under its
  name.
- `<twin>.ledger.md` (and `.json`), the *ledger*, which lists every element of
  the Daml source with the verdict it was given. *Encoded* means translated
  with its meaning unchanged. *Approximated* means translated with a change of
  meaning that is written down. *Residue* means not translated at all. The
  dialog of examples does not list the ledgers; read a ledger among the
  project's own files instead.

Good first programs: `skeleton/skeleton.le` (three commands),
`token/token.le` (commands Daml refuses), and
`quickstart/quickstart_trade_test.le` (a trade built from nested exercises).

### Opening your own Daml

1. **File ▸ Open…** and choose a `.daml` file.
2. The server hands the file to the Daml translator. The status line either
   says *converted* or gives the number of conversion notes. The notes
   themselves sit in a comment at the top of the document, and they are the
   ledger's counts, such as
   *main: 4 source elements encoded, 1 approximated, 0 residue.*
3. A new tab opens, named after the module (`Main.daml` becomes `main.le`).
   The header comment says what the program is and how contract ids work.
4. **View ▸ The original this was converted from** shows the Daml you opened.

Whatever did not translate stays in the program between markers, together with
the reason and the original Daml text:

```
% RESIDUE simple_iou_choice_1 BEGIN: choice
% TODO: translate the fragment below by hand, or with the Contract Assistant (residue mode); it was not translated automatically
% inside the template, outside the subset (a key, an interface instance, a choice the reader did not parse)
%   daml:
%   | choice Redeem
% RESIDUE simple_iou_choice_1 END
```

The file dialog also takes a `.zip`, which is how you open a whole Daml project
at once. The translator reads the project's modules together, so a script in
`Test.daml` becomes the scenario of the templates in `Main.daml`.

### Running a twin

A twin is an ordinary Logical English for LPS document. Press **Run**, step
through the cycles and ask why, as with any program (see
[the editor guide](../guide/ide.md#running-a-program)). Each command of the
script is one action in one cycle. A command that Daml rejects, such as a
`submitMustFail`, is an action that LPS2 refuses. The timeline shows the
refused action crossed out in red, and asking why (see
[Asking why](../guide/ide.md#asking-why)) names the constraint that refused the
action. The scenario's comment lists the contracts Daml still holds active at
the end, so you can compare those contracts with the twin's final state:

```
% Daml (the script run on a Canton sandbox) ends with these active contracts (their payloads;
% the ids are the ledger's):
%   - asset(alice,alice,"TV")
```

To see who may do what, open **View ▸ Legal view: who may do what (Logical
English)**. The legal view turns each action's integrity constraints into a
single permission rule, and each causal law into an effect. The result is a
timeless Logical English program in a tab of its own, and the LE2 editor is
where you put questions to that program.

### Exporting to Daml

1. Open a Logical English document whose target language is `lps`: a twin,
   or one of your own.
2. Choose **Misc ▸ Export to another system…**. If more than one writer can
   handle the document — LegalRuleML is often offered too — pick *Daml
   (Canton): the program as one State contract, each action a choice, with its
   scenario as a Daml Script (.daml)*.
3. If the program can be written faithfully, a window titled *Exported as
   Daml (Canton)…* shows `Main.daml`, with **Copy** and **Save…** buttons. The
   window's note says how to run the module: put the module in a Daml package,
   then `dpm build`, then `dpm sandbox`, then `dpm script` with
   `--script-name Main:scenario`. The script gives back the final `State`.
   Daml has no public sandbox in the browser, so the window offers no link to
   open.
4. If the program cannot be written faithfully, nothing is written at all. A
   window titled *Export as Daml (Canton)… — not translatable* lists every
   problem. Each problem shows its line as a link, the program's words at that
   line, and the reason. For example, LPS2 refuses
   `examples/le/bank_transfer.le` for its reactive rules and for two
   constraints:

   ```
   line 19 — a reactive rule (if ... then the program acts on its own): Daml has no agent acting on its own — a Daml trigger would be one
   line 38 — a constraint relating two actions at once: Daml submits one command at a time
   ```

   `examples/le/token.le` and `examples/le/fee_token.le` export as they are.

## How Daml maps to LPS

| Daml | Logical English for LPS |
|---|---|
| `template Asset with issuer, owner, name` | a fluent keyed by the contract id, with the fields as its other places: `*an asset* is an asset with issuer *an issuer*, owner *an owner* and name *a name*` (a record field is flattened: `iou : Iou` gives `iou issuer`, `iou owner`, …) |
| `create` | an action of the submitting party that initiates the fluent: `*a party* creates the asset *an asset* with issuer *an issuer*, owner *an owner* and name *a name*` |
| `choice Give with newOwner controller owner do …` | an action of the exerciser on a contract id: `*a party* exercises give on the asset *an asset* with new owner *a new owner* creating *a second asset*` |
| a consuming choice; `archive`; the implicit `Archive` choice | a causal law that terminates the contract's fluent: `then it is not the case that the asset is an asset with …` |
| `create this with owner = newOwner` in a choice | the same law initiates the new contract: `then the second asset is an asset with issuer the issuer, owner the owner and name the name` |
| `fetch` | a condition that the contract is active |
| a nested `exercise` | inlined into the outer choice. A contract created and consumed in the same transaction never reaches the state, as in Daml |
| `signatory` | a constraint. The submitter of a create, or the choice's authorisers, must include every signatory: `and the party is different from the issuer` refuses the create |
| `controller` | a constraint that the exerciser is the controller |
| an archived contract exercised again | a constraint that the contract is active: `and it is not the case that the asset is an asset with issuer a thing, …` |
| `ensure`, `assert`, `assertMsg`, `===` | constraints, one per conjunct: `ensure name /= ""` becomes `and the name is equal to ""` |
| `observer` | not in the twin (approximated): who may *see* a contract is Daml's privacy model, not part of the ledger's state |
| a Daml Script | a scenario with one command per cycle and parties as constants. `submitMustFail` is a command LPS2 refuses. Queries, `allocateParty`, user management and time are not observed (approximated) |
| further scripts of the project | programs of their own that extend the first |

### Contract ids are named by the scenario

In Daml, the ledger hands out contract ids, and each id is a long computed
code, called a hash. LPS has no way of inventing fresh ids. So, for every
contract that a command creates, the twin turns the contract's id into a
*place of the action*, and the scenario supplies the id, using the name the
script gave the contract:

```
scenario setup is:
    % the Daml Script setup
    alice creates the asset alice_tv with issuer alice, owner alice and name "TV" from 1 to 2.
    alice exercises give on the asset alice_tv with new owner bob creating bob_tv from 2 to 3.
    bob exercises give on the asset bob_tv with new owner alice creating c1 from 3 to 4.
```

A constraint refuses a create whose id is already in use. When you write such
calls by hand, give each new contract a new name.

### Authorisation is a set of constraints

In Daml, the rules about who may do what are spread across `signatory`,
`controller`, `ensure` and the ledger model. The twin states each of those
rules as an `it must not be true that` sentence, and each such sentence
restates the command the rule guards:

```
it must not be true that
    a party exercises give on the asset an asset with new owner an owner creating a second asset
    and the asset is an asset with issuer an issuer, owner a second owner and name a name
    and the party is different from the second owner.
```

A twin is therefore often two or three times longer than the Daml it came
from. The legal view gathers the constraints back together into one permission
for each command.

### Scripts are scenarios

A script's commands become observations, one command per cycle. Some parts of
a script are not observed at all: what the script only looks at (`query`,
`queryContractId`), its checks, its user management, and time. The ledger
marks each of those parts as approximated. A command that Daml refuses carries
a comment:

```
    % Daml refuses the next command (submitMustFail): the twin's integrity constraints refuse it
```

### The way back: one State contract

Daml 3 has no contract keys, so nothing can look a Daml contract up by the
values of an LPS fluent. The writer therefore puts the whole LPS state into
**one** contract:

- `template State` has an `operator` party as its signatory and every party
  of the program as an observer. Each fluent is a list of records, and a
  fluent with no places is a `Bool`, a value that is only ever true or false.
- Each action is a choice of `State`. The choice's controller is the acting
  party, which is the action's first place, or the operator when that place
  holds something other than a party.
- An integrity constraint on an action is an `assertMsg` before the update.
  A constraint on states is an `assertMsg` on the new state.
- The causal laws make up the update. The module works out the terminations
  and the old values from the state as it stood before the action, then adds
  the initiations, then removes duplicates (`dedup`), because a fluent is a
  set.
- `initially` is the `State` the script creates. The scenario submits each
  observed action with `trySubmit`, so a refused action leaves the state as
  it was, as in LPS2. The script returns the final `State`.

Record fields and choice arguments take their names from the places of the
Logical English templates (`issuer : Party`, `observersPartyList : [Party]`). The
generic names `a1`, `a2`, … appear only for a relation with no template.

The writer works the types out from the program itself. A place that holds an
acting party, or that shares a variable with an acting party, becomes a
`Party`. A number, or a place that a law compares or computes with, becomes a
`Decimal`. A list becomes `[Party]` when one of the list's members is a party,
or when the place is called a list of parties (`*a party list*`). Anything
else becomes `Text`. A party named in a law (`the treasury`) becomes a field
of `State` that the script allocates, because Daml has no way to write a
party's name down directly. A default (`0 by default`) is the value used when
no record holds one.

## Traps

- **Time is not translated.** `getTime`, `passTime`, `addRelTime` and a
  choice that branches on the ledger's time are all residue. `coin_issuance`
  skips the lock that needs a maturity date, and `restrictions` keeps IOUs
  that Daml redeems. Scripts that set the time were run on Daml Script's own
  ledger, the one it keeps in memory, rather than on Canton, and the scenario
  comment says which ledger gave the answer.
- **Four of the 22 scripts end differently in the twin, as expected:**
  - `restrictions`: time, a `case`, and the text functions `T.length` and
    `T.isUpper` in an `ensure`;
  - `compose_test_trade`: the script passes a value it read from the ledger
    (`queryContractId`) into a create;
  - `coin_issuance`: time;
  - `multiparty`: `Sign` uses `elem` on a helper function and `Finalize`
    compares sorted lists, so the twin ends with the `Pending` contract that
    Daml finalises into an `Agreement`.

  The scenario comments of those four still give Daml's final state, so you
  can see the difference for yourself.
- **Residue** — the parts left in the program with a marker on them, never
  dropped in silence — covers contract keys, interfaces and `implements`,
  `case`, type classes and `instance` declarations, data types that are not
  records, helper functions called inside choices, and choices that add to a
  list held in a field (`newObserver :: observers`). The ledger gives the
  reason for each one.
- **Daml Finance is out of reach.** The Daml Finance templates are written
  against interfaces that arrive as ready-built packages rather than as
  source, so the translator can see the calls but not what the calls do.
- **Observers disappear on the way in.** The twin does not model who can see
  a contract. The legal view and the constraints are about who may *act*.
- **A lone `.daml` file has no scenario unless it holds a script.** The
  skeleton's `Main.daml` on its own gives the fluents, laws and constraints,
  but the skeleton's script sits in `Test.daml`. Even when you choose several
  `.daml` files at once in **File ▸ Open…**, the server still converts each
  file on its own rather than as one project. To open a project spread over
  several modules, zip the project and open the `.zip`.
- **Export refusals.** Nothing is written for a program with any of these:
  reactive rules (Daml has no agent that acts on its own; a Daml trigger
  would be one), intensional fluents, composite events, a constraint that
  relates two actions, a goal to achieve (Daml has no planner), a timeless
  rule that a law or constraint reads (Daml has only the facts a choice looks
  up), a place that holds a party in one sentence and a list in another, or
  any error in the program's LPS reading. Most of LPS2's Logical English
  examples are refused, mainly for reactive rules. Of the 17 in
  `examples/le/`, 2 export.
- **The exported module proves that the round trip works; the module is not
  the Daml you would put into service.** One contract holds every fluent.
  Every party sees everything, and every choice consumes that one contract
  and creates it again, so commands arriving at the same time compete for it.
  Choices are checked with long `assertMsg` expressions, rather than written
  the way a Daml author would write them.
- **A list is `[Party]` only when the program says so.** A list gets the type
  `[Party]` when the program puts a party into the list, takes a member of
  the list to a party's place, or calls the place a list of parties (`*an
  observers party list*`, which is how a twin names a Daml `[Party]` field).
  Any other list, one whose members the program never shows, gets `[Text]`.
- **Contract ids are `Text` on the way back.** A twin's ids (`alice_tv`)
  become text fields of the records, rather than Daml `ContractId`s, because
  the exported program has only one contract.
- **Numbers are `Decimal`.** Daml's `Decimal` keeps a fixed number of decimal
  places, ten of them, and LPS numbers have no such limit. A program that
  depends on exact fractions or on very large whole numbers can therefore end
  in a different state.

## See also

- In this documentation:
  - [Other systems: the overview](index.md)
  - [Solidity and LPS](solidity.md), the other smart-contract language, with
    **Misc ▸ Deploy as Solidity…**
  - [Drools and LPS](drools.md)
  - [Logical English for LPS](../reference/le-for-lps.md), in particular
    [integrity constraints](../reference/le-for-lps.md#37-it-must-not-be-true-that---integrity-constraints),
    [observations](../reference/le-for-lps.md#39-observations) and
    [what has no LPS reading](../reference/le-for-lps.md#8-what-has-no-lps-reading-is-refused)
  - [Using the editor: the menus](../guide/ide.md#the-menus) and
    [Logical English](../guide/ide.md#logical-english)
  - [Glossary](../reference/glossary.md)
- In the Logical English IDE:
  - [Other systems: importing and exporting](https://le2.logicalcontracts.com/docs/user/integrations/index),
    in particular [what could not be translated](https://le2.logicalcontracts.com/docs/user/integrations/index#what-could-not-be-translated)
    and [when an export is refused](https://le2.logicalcontracts.com/docs/user/integrations/index#when-an-export-is-refused)
  - [Logical English for LPS](https://le2.logicalcontracts.com/docs/user/reference/lps-target)
- Daml's own documentation:
  - [The Daml repository](https://github.com/digital-asset/daml) (Apache 2.0)
  - [Daml documentation](https://docs.daml.com/)
  - [The Canton repository](https://github.com/digital-asset/canton)
  - [Canton Network](https://canton.network/)
