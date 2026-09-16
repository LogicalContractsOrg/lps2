# Migration ledger: multiparty

Source: a Daml project (Daml 3, Canton) — daml/MultiplePartyAgreement.daml, daml/Utilities.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 7 |
| approximated | 7 |
| residue | 2 |
| **total** | 16 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template Agreement | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | agreement |  |
| template Pending | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | pending |  |
| signatory signatories of Agreement | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Agreement |  |
| signatory alreadySigned of Pending | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Pending |  |
| observer finalContract.signatories of Pending | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Pending |  |
| ensure unique signatories (Agreement) | ensure | encoded | ensure -> an integrity constraint on every create | Agreement |  |
| ensure unique alreadySigned (Pending) | ensure | encoded | ensure -> an integrity constraint on every create | Pending |  |
| consuming choice Pending.Sign | choice | residue | a choice outside the subset | pending_sign | the condition `elem signer toSign this` has no LE form here |
| consuming choice Pending.Finalize | choice | residue | a choice outside the subset | pending_finalize | `sort alreadySigned` is outside the subset |
| script fun(MultiplePartyAgreement,multiplePartyAgreementTest,[],do([bind(parties as list([var(person1),var(person2),var(person3),var(person4)]),app(var(makePartiesFrom),[list([str(Alice),str(Bob),str(Clare),str(Dave)])])),let([finalContract-rec(con(Agreement),[signatories-var(parties)])]),bind(var(initialFailTest),app(var(submitMustFail),[var(person1),do([expr(app(var(createCmd),[rec(con(Pending),[finalContract-var(finalContract),alreadySigned-list([var(person1),var(person2)])])]))])])),bind(var(pending),app(var(submit),[var(person1),do([expr(app(var(createCmd),[rec(con(Pending),[finalContract-var(finalContract),alreadySigned-list([var(person1)])])]))])])),bind(var(pending),app(var(submit),[var(person2),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person2)])]))])])),bind(var(pending),app(var(submit),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person3)])]))])])),bind(var(pending),app(var(submit),[var(person4),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person4)])]))])])),bind(var(pendingFailTest),app(var(submitMustFail),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person3)])]))])])),bind(var(pendingFailTest),app(var(submitMustFail),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person4)])]))])])),expr(app(var(submit),[var(person1),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Finalize),[signer-var(person1)])]))])]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(MultiplePartyAgreement,multiplePartyAgreementTest,[],do([bind(parties as list([var(person1),var(person2),var(person3),var(person4)]),app(var(makePartiesFrom),[list([str(Alice),str(Bob),str(Clare),str(Dave)])])),let([finalContract-rec(con(Agreement),[signatories-var(parties)])]),bind(var(initialFailTest),app(var(submitMustFail),[var(person1),do([expr(app(var(createCmd),[rec(con(Pending),[finalContract-var(finalContract),alreadySigned-list([var(person1),var(person2)])])]))])])),bind(var(pending),app(var(submit),[var(person1),do([expr(app(var(createCmd),[rec(con(Pending),[finalContract-var(finalContract),alreadySigned-list([var(person1)])])]))])])),bind(var(pending),app(var(submit),[var(person2),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person2)])]))])])),bind(var(pending),app(var(submit),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person3)])]))])])),bind(var(pending),app(var(submit),[var(person4),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person4)])]))])])),bind(var(pendingFailTest),app(var(submitMustFail),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person3)])]))])])),bind(var(pendingFailTest),app(var(submitMustFail),[var(person3),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Sign),[signer-var(person4)])]))])])),expr(app(var(submit),[var(person1),do([expr(app(var(exerciseCmd),[var(pending),rec(con(Finalize),[signer-var(person1)])]))])]))])) |  |
| the script exercises Pending.Sign, a residue choice (the condition `elem signer toSign this` has no LE form here): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |
| the script exercises Pending.Sign, a residue choice (the condition `elem signer toSign this` has no LE form here): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |
| the script exercises Pending.Sign, a residue choice (the condition `elem signer toSign this` has no LE form here): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |
| the script exercises Pending.Sign, a residue choice (the condition `elem signer toSign this` has no LE form here): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |
| the script exercises Pending.Sign, a residue choice (the condition `elem signer toSign this` has no LE form here): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |
| the script exercises Pending.Finalize, a residue choice (`sort alreadySigned` is outside the subset): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | multiplePartyAgreementTest |  |

## Residue

- **consuming choice Pending.Sign** (choice) — a choice outside the subset; in the program: pending_sign. the condition `elem signer toSign this` has no LE form here
- **consuming choice Pending.Finalize** (choice) — a choice outside the subset; in the program: pending_finalize. `sort alreadySigned` is outside the subset

