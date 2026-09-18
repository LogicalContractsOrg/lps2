# Migration ledger: fire_alarm

Source: a Drools rule base (DRL) — Fire.drl
Translator: lpsPlus/migration/drools (drl_twin.pl, over LPS2's lps_drools.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 5 |
| approximated | 0 |
| residue | 3 |
| **total** | 8 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| rule "RaiseAlarm" (line 10) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | RaiseAlarm |  |
| rule "CancelAlarm" (line 17) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | CancelAlarm |  |
| rule "ThereIsAnAlarm" (line 26) | rule | residue | a consequence in Java only | ThereIsAnAlarm | kept as a residue block |
| rule "ThereIsNoAlarm" (line 32) | rule | residue | a consequence in Java only | ThereIsNoAlarm | kept as a residue block |
| rule "TurnSprinklerOn" (line 40) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | TurnSprinklerOn |  |
| rule "TurnSprinklerOff" (line 48) | rule | encoded | when ... then ... -> a reactive rule; its inserts, modifies and deletes -> events in the world with their causal laws | TurnSprinklerOff |  |
| rule "OK" (line 56) | rule | residue | a consequence in Java only | OK | kept as a residue block |
| every alarm has name house1, so the field tells no two of them apart: the reading leaves it out | field | encoded | a field every fact gives one same value -> left out of the fluent | the program | every alarm has name house1, so the field tells no two of them apart: the reading leaves it out |

## Residue

- **rule "ThereIsAnAlarm" (line 26)** (rule) — a consequence in Java only; in the program: ThereIsAnAlarm. kept as a residue block
- **rule "ThereIsNoAlarm" (line 32)** (rule) — a consequence in Java only; in the program: ThereIsNoAlarm. kept as a residue block
- **rule "OK" (line 56)** (rule) — a consequence in Java only; in the program: OK. kept as a residue block

