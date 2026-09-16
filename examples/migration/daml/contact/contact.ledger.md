# Migration ledger: contact

Source: a Daml project (Daml 3, Canton) — daml/Contact.daml
Translator: the Daml translator
Date: 2026-09-16

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 5 |
| approximated | 5 |
| residue | 0 |
| **total** | 10 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template Contact | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | contact |  |
| signatory owner of Contact | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Contact |  |
| observer party of Contact | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Contact |  |
| consuming choice Contact.UpdateTelephone | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | update_telephone |  |
| consuming choice Contact.UpdateAddress | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | update_address |  |
| script fun(Contact,choice_test,[],do([bind(var(owner),app(var(allocateParty),[str(Alice)])),bind(var(party),app(var(allocateParty),[str(Bob)])),bind(var(contactCid),app(var(submit),[var(owner),do([expr(app(var(createCmd),[rec(con(Contact),[owner-var(owner),party-var(party),address-str(1 Bobstreet),telephone-str(012 345 6789)])]))])])),expr(app(var(submitMustFail),[var(party),do([expr(app(var(exerciseCmd),[var(contactCid),rec(con(UpdateTelephone),[newTelephone-str(098 7654 321)])]))])])),bind(var(newContactCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(contactCid),rec(con(UpdateTelephone),[newTelephone-str(098 7654 321)])]))])])),bind(con(Some,[var(newContact)]),app(var(queryContractId),[var(owner),var(newContactCid)])),expr(app(var(assert),[op(==,field(var(newContact),telephone),str(098 7654 321))])),bind(var(newContactCid),app(var(submit),[var(party),do([expr(app(var(exerciseCmd),[var(newContactCid),rec(con(UpdateAddress),[newAddress-str(1-10 Bobstreet)])]))])])),bind(con(Some,[var(newContact)]),app(var(queryContractId),[var(owner),var(newContactCid)])),expr(app(var(assert),[op(==,field(var(newContact),address),str(1-10 Bobstreet))]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Contact,choice_test,[],do([bind(var(owner),app(var(allocateParty),[str(Alice)])),bind(var(party),app(var(allocateParty),[str(Bob)])),bind(var(contactCid),app(var(submit),[var(owner),do([expr(app(var(createCmd),[rec(con(Contact),[owner-var(owner),party-var(party),address-str(1 Bobstreet),telephone-str(012 345 6789)])]))])])),expr(app(var(submitMustFail),[var(party),do([expr(app(var(exerciseCmd),[var(contactCid),rec(con(UpdateTelephone),[newTelephone-str(098 7654 321)])]))])])),bind(var(newContactCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(contactCid),rec(con(UpdateTelephone),[newTelephone-str(098 7654 321)])]))])])),bind(con(Some,[var(newContact)]),app(var(queryContractId),[var(owner),var(newContactCid)])),expr(app(var(assert),[op(==,field(var(newContact),telephone),str(098 7654 321))])),bind(var(newContactCid),app(var(submit),[var(party),do([expr(app(var(exerciseCmd),[var(newContactCid),rec(con(UpdateAddress),[newAddress-str(1-10 Bobstreet)])]))])])),bind(con(Some,[var(newContact)]),app(var(queryContractId),[var(owner),var(newContactCid)])),expr(app(var(assert),[op(==,field(var(newContact),address),str(1-10 Bobstreet))]))])) |  |
| not observed (a query, an assertion, user management or time): queryContractId owner newContactCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | choice_test |  |
| not observed (a query, an assertion, user management or time): assert (newContact.telephone == "098 7654 321") | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | choice_test |  |
| not observed (a query, an assertion, user management or time): queryContractId owner newContactCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | choice_test |  |
| not observed (a query, an assertion, user management or time): assert (newContact.address == "1-10 Bobstreet") | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | choice_test |  |

