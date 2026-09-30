# Migration ledger: deontic_example

Source: an L4 file (smucclaw/l4-ide) — deontic-example.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 32 |
| approximated | 0 |
| residue | 0 |
| **total** | 32 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| simple delivery obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | simple delivery obligation |  |
| delivery within days, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | delivery within days |  |
| sale contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | sale contract |  |
| mutual obligations, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | mutual obligations |  |
| mutual obligations, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | mutual obligations |  |
| flexible delivery, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | flexible delivery |  |
| flexible delivery, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | flexible delivery |  |
| conditional delivery, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | conditional delivery |  |
| conditional delivery, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | conditional delivery |  |
| minimum payment contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | minimum payment contract |  |
| exact payment required, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | exact payment required |  |
| create order contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | create order contract |  |
| create order contract, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | create order contract |  |
| sale contract, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | sale contract |  |
| create order contract, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | create order contract |  |
| create order contract, obligation 4 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | create order contract |  |
| #TRACE `simple delivery obligation` (line 170) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_170 |  |
| #TRACE `simple delivery obligation` (line 174) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_174 |  |
| #TRACE (`delivery within days` OF 7) (line 178) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_178 |  |
| #TRACE (`sale contract` OF 500) (line 182) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_182 |  |
| #TRACE `mutual obligations` (line 187) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_187 |  |
| #TRACE `flexible delivery` (line 192) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_192 |  |
| #TRACE `flexible delivery` (line 196) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_196 |  |
| #TRACE (`conditional delivery` OF `TRUE`) (line 200) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_200 |  |
| #TRACE (`conditional delivery` OF `FALSE`) (line 204) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_204 |  |
| #TRACE `minimum payment contract` (line 222) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_222 |  |
| #TRACE `minimum payment contract` (line 226) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_226 |  |
| #TRACE (`exact payment required` OF 500) (line 245) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_245 |  |
| #TRACE (`exact payment required` OF 500) (line 249) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_249 |  |
| #TRACE `simple delivery obligation` (line 259) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_259 |  |
| #TRACE (`create order contract` OF "express", 200) (line 299) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_299 |  |
| #TRACE (`create order contract` OF "standard", 200) (line 304) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_304 |  |

