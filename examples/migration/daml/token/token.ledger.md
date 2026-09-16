# Migration ledger: token

Source: a Daml project (Daml 3, Canton) — daml/Token_Test.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 3 |
| approximated | 0 |
| residue | 0 |
| **total** | 3 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template Token | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | token |  |
| signatory owner of Token | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Token |  |
| script fun(Token_Test,token_test,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),expr(app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(alice)])]))])])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(bobToken),app(var(submit),[var(bob),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(bob)])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(bob)])]))])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(alice)])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(archiveCmd),[var(bobToken)]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(archiveCmd),[var(bobToken)]))])]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Token_Test,token_test,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),expr(app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(alice)])]))])])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(bobToken),app(var(submit),[var(bob),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(bob)])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(bob)])]))])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(createCmd),[rec(con(Token),[owner-var(alice)])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(archiveCmd),[var(bobToken)]))])])),expr(app(var(submit),[var(bob),do([expr(app(var(archiveCmd),[var(bobToken)]))])]))])) |  |

