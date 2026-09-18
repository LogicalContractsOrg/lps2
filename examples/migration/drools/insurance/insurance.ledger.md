# Migration ledger: insurance

Source: a Drools rule base (DRL) — insurance.drl
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
| rule "young drivers are high risk" (line 16) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | young drivers are high risk |  |
| rule "a clean record over thirty is low risk" (line 24) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | a clean record over thirty is low risk |  |
| rule "a claim moves a low band to standard" (line 32) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | a claim moves a low band to standard |  |

