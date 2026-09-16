# Migration ledger: compose

Source: a Daml project (Daml 3, Canton) — daml/Intro/Asset.daml, daml/Intro/Asset/Role.daml, daml/Intro/Asset/Trade.daml, daml/Test/Intro/Asset.daml, daml/Test/Intro/Asset/Role.daml, daml/Test/Intro/Asset/Trade.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 0 |
| approximated | 11 |
| residue | 0 |
| **total** | 11 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| not observed (a query, an assertion, user management or time): queryContractId bank assetCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): assert (asset == Asset with issuer = bank; owner = alice; symbol = "USD"; quantity = 100.0; observers = []) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): queryContractId alice usdCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| the script uses `usd`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): queryContractId bob usdCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| the script uses `usd`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| the script uses `tradeCid`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): queryContractId eurbank eurCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): assert (eur.owner == alice) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): queryContractId usdbank usdCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |
| not observed (a query, an assertion, user management or time): assert (usd.owner == bob) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_trade |  |

