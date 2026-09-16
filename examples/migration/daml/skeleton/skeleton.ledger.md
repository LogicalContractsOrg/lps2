# Migration ledger: skeleton

Source: a Daml project (Daml 3, Canton) — main/daml/Main.daml, test/daml/Test.daml
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
| template Asset | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | asset |  |
| signatory issuer of Asset | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Asset |  |
| observer owner of Asset | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Asset |  |
| ensure (name /= "") (Asset) | ensure | encoded | ensure -> an integrity constraint on every create | Asset |  |
| consuming choice Asset.Give | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | give |  |
| script fun(Test,setup,[],app(var(script),[do([bind(var(alice),app(var(allocatePartyByHint),[app(con(PartyIdHint),[str(Alice)])])),bind(var(bob),app(var(allocatePartyByHint),[app(con(PartyIdHint),[str(Bob)])])),bind(var(aliceId),app(var(validateUserId),[str(alice)])),bind(var(bobId),app(var(validateUserId),[str(bob)])),expr(app(var(createUser),[app(con(User),[var(aliceId),app(con(Some),[var(alice)])]),list([app(con(CanActAs),[var(alice)])])])),expr(app(var(createUser),[app(con(User),[var(bobId),app(con(Some),[var(bob)])]),list([app(con(CanActAs),[var(bob)])])])),bind(var(aliceTV),app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(Asset),[issuer-var(alice),owner-var(alice),name-str(TV)])]))])])),bind(var(bobTV),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(aliceTV),rec(con(Give),[newOwner-var(bob)])]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(bobTV),rec(con(Give),[newOwner-var(alice)])]))])]))])])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Test,setup,[],app(var(script),[do([bind(var(alice),app(var(allocatePartyByHint),[app(con(PartyIdHint),[str(Alice)])])),bind(var(bob),app(var(allocatePartyByHint),[app(con(PartyIdHint),[str(Bob)])])),bind(var(aliceId),app(var(validateUserId),[str(alice)])),bind(var(bobId),app(var(validateUserId),[str(bob)])),expr(app(var(createUser),[app(con(User),[var(aliceId),app(con(Some),[var(alice)])]),list([app(con(CanActAs),[var(alice)])])])),expr(app(var(createUser),[app(con(User),[var(bobId),app(con(Some),[var(bob)])]),list([app(con(CanActAs),[var(bob)])])])),bind(var(aliceTV),app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(Asset),[issuer-var(alice),owner-var(alice),name-str(TV)])]))])])),bind(var(bobTV),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(aliceTV),rec(con(Give),[newOwner-var(bob)])]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(bobTV),rec(con(Give),[newOwner-var(alice)])]))])]))])])) |  |
| not observed (a query, an assertion, user management or time): validateUserId "alice" | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | setup |  |
| not observed (a query, an assertion, user management or time): validateUserId "bob" | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | setup |  |
| not observed (a query, an assertion, user management or time): createUser User aliceId Some alice [CanActAs alice] | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | setup |  |
| not observed (a query, an assertion, user management or time): createUser User bobId Some bob [CanActAs bob] | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | setup |  |

