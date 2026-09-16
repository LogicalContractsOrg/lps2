# Migration ledger: compose

Source: a Daml project (Daml 3, Canton) — daml/Intro/Asset.daml, daml/Intro/Asset/Role.daml, daml/Intro/Asset/Trade.daml, daml/Test/Intro/Asset.daml, daml/Test/Intro/Asset/Role.daml, daml/Test/Intro/Asset/Trade.daml
Translator: the Daml translator
Date: 2026-09-16

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 0 |
| approximated | 2 |
| residue | 0 |
| **total** | 2 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| not observed (a query, an assertion, user management or time): queryContractId bank assetCid | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_issuance |  |
| not observed (a query, an assertion, user management or time): assert (asset == Asset with issuer = bank; owner = alice; symbol = "USD"; quantity = 100.0; observers = []) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | test_issuance |  |

