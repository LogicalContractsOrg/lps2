# Migration ledger: module_a1_regulatory_examples

Source: an L4 file (smucclaw/l4-ide) — module-a1-regulatory-examples.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 9 |
| approximated | 0 |
| residue | 0 |
| **total** | 9 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| annual return obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | annual return obligation |  |
| governor reporting obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | governor reporting obligation |  |
| Commissioner may issue notice, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | Commissioner may issue notice |  |
| commissioner may suspend, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | commissioner may suspend |  |
| charity must comply with notice, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | charity must comply with notice |  |
| #TRACE (`annual return obligation` OF `Acme Animal Shelter`) (line 379) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_379 |  |
| #TRACE (`annual return obligation` OF `Acme Animal Shelter`) (line 383) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_383 |  |
| #TRACE (`governor reporting obligation` OF `John Smith`, `bankruptcy matter`) (line 388) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_388 |  |
| #TRACE (`governor reporting obligation` OF `John Smith`, `bankruptcy matter`) (line 392) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_392 |  |

