# Migration ledger: module_5_examples

Source: an L4 file (smucclaw/l4-ide) — module-5-examples.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 15 |
| approximated | 0 |
| residue | 0 |
| **total** | 15 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| the delivery obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the delivery obligation |  |
| the complete sale contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the complete sale contract |  |
| the payment with late fee, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the payment with late fee |  |
| the wedding ceremony, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the wedding ceremony |  |
| the fidelity clause, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the fidelity clause |  |
| the complete sale contract, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the complete sale contract |  |
| the complete sale contract, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the complete sale contract |  |
| the payment with late fee, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the payment with late fee |  |
| the wedding ceremony, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | the wedding ceremony |  |
| #TRACE `the delivery obligation` (line 128) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_128 |  |
| #TRACE `the delivery obligation` (line 132) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_132 |  |
| #TRACE `the complete sale contract` (line 136) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_136 |  |
| #TRACE `the payment with late fee` (line 141) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_141 |  |
| #TRACE `the wedding ceremony` (line 145) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_145 |  |
| #TRACE `the fidelity clause` (line 150) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_150 |  |

