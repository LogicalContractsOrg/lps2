# Migration ledger: restrictions

Source: a Daml project (Daml 3, Canton) — daml/Restrictions.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 5 |
| approximated | 11 |
| residue | 6 |
| **total** | 22 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template SimpleIou | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | simple_iou |  |
| signatory issuer of SimpleIou | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | SimpleIou |  |
| observer owner of SimpleIou | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | SimpleIou |  |
| ensure ((cash.amount > 0.0) && ((T.length cash.currency == 3) && T.isUpper cash.currency)) (SimpleIou) | ensure | encoded | ensure -> an integrity constraint on every create | SimpleIou |  |
| consuming choice SimpleIou.Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer |  |
| choice Redeem | choice | residue | inside a template, outside the subset | SimpleIou |  |
| data Face = Heads   Tails | data | residue | a module declaration outside the subset | Restrictions |  |
| data CoinGame a = CoinGame with | data | residue | a module declaration outside the subset | Restrictions |  |
| instance Functor CoinGame where | instance | residue | a module declaration outside the subset | Restrictions |  |
| instance Applicative CoinGame where | instance | residue | a module declaration outside the subset | Restrictions |  |
| instance Action CoinGame where | instance | residue | a module declaration outside the subset | Restrictions |  |
| script fun(Restrictions,test_restrictions,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(dora),app(var(allocateParty),[str(Dora)])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-neg(num(100.0)),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(0.0),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(Swiss Francs)])])]))])])),bind(var(iou),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(alice)])]))])])),bind(var(iou2),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(bob)])]))])])),expr(app(var(setTime),[app(var(time),[app(var(date),[num(2019),con(Jun),num(1)]),num(0),num(0),num(0)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(12)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(42)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(2)])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),bind(var(iou3),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(passTime),[app(var(days),[neg(num(3))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(exerciseCmd),[var(iou3),con(Redeem)]))])]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Restrictions,test_restrictions,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(dora),app(var(allocateParty),[str(Dora)])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-neg(num(100.0)),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(0.0),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(Swiss Francs)])])]))])])),bind(var(iou),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(alice)])]))])])),bind(var(iou2),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(iou),rec(con(Transfer),[newOwner-var(bob)])]))])])),expr(app(var(setTime),[app(var(time),[app(var(date),[num(2019),con(Jun),num(1)]),num(0),num(0),num(0)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(12)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(42)])])),expr(app(var(submitMustFail),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),expr(app(var(passTime),[app(var(hours),[num(2)])])),expr(app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(iou2),con(Redeem)]))])])),bind(var(iou3),app(var(submit),[var(dora),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(dora),owner-var(alice),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(passTime),[app(var(days),[neg(num(3))])])),expr(app(var(submitMustFail),[var(alice),do([expr(app(var(exerciseCmd),[var(iou3),con(Redeem)]))])]))])) |  |
| not observed (a query, an assertion, user management or time): setTime time date 2019 Jun 1 0 0 0 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| the script uses `Redeem`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| not observed (a query, an assertion, user management or time): passTime hours 12 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| the script uses `Redeem`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| not observed (a query, an assertion, user management or time): passTime hours 42 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| the script uses `Redeem`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| not observed (a query, an assertion, user management or time): passTime hours 2 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| the script uses `Redeem`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| not observed (a query, an assertion, user management or time): passTime days -3 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |
| the script uses `Redeem`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_restrictions |  |

## Residue

- **choice Redeem** (choice) — inside a template, outside the subset; in the program: SimpleIou. 
- **data Face = Heads   Tails** (data) — a module declaration outside the subset; in the program: Restrictions. 
- **data CoinGame a = CoinGame with** (data) — a module declaration outside the subset; in the program: Restrictions. 
- **instance Functor CoinGame where** (instance) — a module declaration outside the subset; in the program: Restrictions. 
- **instance Applicative CoinGame where** (instance) — a module declaration outside the subset; in the program: Restrictions. 
- **instance Action CoinGame where** (instance) — a module declaration outside the subset; in the program: Restrictions. 

