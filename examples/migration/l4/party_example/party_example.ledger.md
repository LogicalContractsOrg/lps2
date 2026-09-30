# Migration ledger: party_example

Source: an L4 file (smucclaw/l4-ide) — party-example.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 17 |
| approximated | 0 |
| residue | 0 |
| **total** | 17 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| payment obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | payment obligation |  |
| early termination right, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | early termination right |  |
| confidentiality obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | confidentiality obligation |  |
| payment with penalty clause, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | payment with penalty clause |  |
| purchase and delivery contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | purchase and delivery contract |  |
| service agreement, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | service agreement |  |
| payment with penalty clause, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | payment with penalty clause |  |
| purchase and delivery contract, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | purchase and delivery contract |  |
| service agreement, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | service agreement |  |
| service agreement, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | service agreement |  |
| #TRACE `payment obligation` (line 112) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_112 |  |
| #TRACE `payment obligation` (line 116) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_116 |  |
| #TRACE `early termination right` (line 119) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_119 |  |
| #TRACE `confidentiality obligation` (line 123) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_123 |  |
| #TRACE `payment with penalty clause` (line 126) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_126 |  |
| #TRACE `purchase and delivery contract` (line 130) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_130 |  |
| #TRACE `service agreement` (line 135) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_135 |  |

