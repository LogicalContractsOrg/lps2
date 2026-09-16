# Migration ledger: simple_iou

Source: a Daml project (Daml 3, Canton) — daml/SimpleIou.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 4 |
| approximated | 1 |
| residue | 0 |
| **total** | 5 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template SimpleIou | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | simple_iou |  |
| signatory issuer of SimpleIou | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | SimpleIou |  |
| observer owner of SimpleIou | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | SimpleIou |  |
| consuming choice SimpleIou.Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer |  |
| script fun(SimpleIou,test_iou,[],app(var(script),[do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(charlie),app(var(allocateParty),[str(Charlie)])),bind(var(dora),app(var(allocateParty),[str(Dora)])),bind(var(iou),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),bind(var(iou2),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(bob)])]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),rec(con(Transfer),[newOwner-var(charlie)])]))])]))])])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(SimpleIou,test_iou,[],app(var(script),[do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(charlie),app(var(allocateParty),[str(Charlie)])),bind(var(dora),app(var(allocateParty),[str(Dora)])),bind(var(iou),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),bind(var(iou2),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(bob)])]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),rec(con(Transfer),[newOwner-var(charlie)])]))])]))])])) |  |

