# Migration ledger: shipping

Source: a Drools rule base (DRL) — shipping.drl
Translator: lpsPlus/migration/drools (drl_twin.pl, over LPS2's lps_drools.pl)
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
| rule "an order with stock ships" (line 19) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | an order with stock ships |  |
| rule "a shipped order is no longer pending" (line 29) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | a shipped order is no longer pending |  |
| every stock has item widget, so the field tells no two of them apart: the reading leaves it out | field | encoded | a field every fact gives one same value -> left out of the fluent | the program | every stock has item widget, so the field tells no two of them apart: the reading leaves it out |

