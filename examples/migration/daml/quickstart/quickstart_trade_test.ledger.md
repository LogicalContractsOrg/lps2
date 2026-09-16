# Migration ledger: quickstart

Source: a Daml project (Daml 3, Canton) — daml/Iou.daml, daml/IouTrade.daml, daml/Tests/Iou.daml, daml/Tests/Trade.daml
Translator: the Daml translator
Date: 2026-09-16

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
| the script exercises Iou.Iou_AddObserver, a residue choice (`(newObserver :: observers)` adds to a list held in a place, which LE cannot yet say (a list is a value, not a collection a law changes)): the scenario stops there | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): queryContractId alice fst newIous | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (alice === iou.owner) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (usBank === iou.issuer) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): ("USD" === iou.currency) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (110.0 === iou.amount) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): queryContractId bob snd newIous | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (bob === iou.owner) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (eurBank === iou.issuer) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): ("EUR" === iou.currency) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |
| not observed (a query, an assertion, user management or time): (100.0 === iou.amount) | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | trade_test |  |

