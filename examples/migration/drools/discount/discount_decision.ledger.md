# Migration ledger: discount

Source: a Drools rule base (DRL), as a decision service — discount.drl
Translator: InsurLE2/migration/drools (drl_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 2 |
| approximated | 2 |
| residue | 0 |
| **total** | 4 |

Fidelity: **1 of 1** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| rule "Gold customers with a large order get the best rate" (line 21) | rule | encoded | an insert -> a rule concluding the inserted fact; salience -> the order of an otherwise cascade | Gold customers with a large order get the best rate | salience 10 |
| rule "Everyone else with a large order gets the standard rate" (line 31) | rule | encoded | an insert -> a rule concluding the inserted fact; salience -> the order of an otherwise cascade | Everyone else with a large order gets the standard rate | salience 5 |
| rule "Gold customers with a large order get the best rate" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) | diagnostic | approximated | an LPS2 diagnostic of the reading | the program | rule "Gold customers with a large order get the best rate" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) |
| rule "Everyone else with a large order gets the standard rate" uses salience 5. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) | diagnostic | approximated | an LPS2 diagnostic of the reading | the program | rule "Everyone else with a large order gets the standard rate" uses salience 5. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| drools_run | discount | pass |  |

