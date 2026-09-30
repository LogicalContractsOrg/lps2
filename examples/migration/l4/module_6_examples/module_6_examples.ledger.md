# Migration ledger: module_6_examples

Source: an L4 file (smucclaw/l4-ide) — module-6-examples.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 6 |
| approximated | 0 |
| residue | 0 |
| **total** | 6 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| the annual return obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the annual return obligation |  |
| the annual return obligation, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the annual return obligation |  |
| the correction period, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the correction period |  |
| #TRACE (`the annual return obligation` OF `Jersey Animal Welfare`) (line 177) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_177 |  |
| #TRACE (`the annual return obligation` OF `Suspended Charity`) (line 181) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_181 |  |
| #TRACE (`the annual return obligation` OF `Jersey Animal Welfare`) (line 184) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_184 |  |

