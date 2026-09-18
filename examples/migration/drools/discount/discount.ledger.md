# Migration ledger: discount

Source: a Drools rule base (DRL) — discount.drl
Translator: lpsPlus/migration/drools (drl_twin.pl, over LPS2's lps_drools.pl)
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
| rule "Gold customers with a large order get the best rate" (line 21) | rule | approximated | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | Gold customers with a large order get the best rate | salience 10: LPS fires every rule whose conditions hold, with no priority |
| rule "Everyone else with a large order gets the standard rate" (line 31) | rule | approximated | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | Everyone else with a large order gets the standard rate | salience 5: LPS fires every rule whose conditions hold, with no priority |

