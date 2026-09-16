# Migration ledger: honest_politician

Source: a Drools rule base (DRL) — HonestPolitician.drl
Translator: InsurLE2/migration/drools (drl_twin.pl, over LPS2's lps_drools.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 1 |
| approximated | 3 |
| residue | 2 |
| **total** | 6 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| rule "We have an honest Politician" (line 8) | rule | approximated | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | We have an honest Politician | salience 10: LPS fires every rule whose conditions hold, with no priority |
| rule "Hope Lives" (line 16) | rule | residue | a consequence in Java only | Hope Lives | kept as a residue block |
| rule "Hope is Dead" (line 24) | rule | residue | a consequence in Java only | Hope is Dead | kept as a residue block |
| rule "Corrupt the Honest" (line 31) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | Corrupt the Honest |  |
| rule "We have an honest Politician" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) | diagnostic | approximated | an LPS2 diagnostic of the reading | the program | rule "We have an honest Politician" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) |
| rule "Hope Lives" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) | diagnostic | approximated | an LPS2 diagnostic of the reading | the program | rule "Hope Lives" uses salience 10. LPS has no conflict-resolution priority: the rule is translated, the priority is recorded, and firing order may differ (§IV.2) |

## Residue

- **rule "Hope Lives" (line 16)** (rule) — a consequence in Java only; in the program: Hope Lives. kept as a residue block
- **rule "Hope is Dead" (line 24)** (rule) — a consequence in Java only; in the program: Hope is Dead. kept as a residue block

