# Migration ledger: must_example

Source: an L4 file (smucclaw/l4-ide) — must-example.l4
Translator: the L4 translator
Date: 2026-09-29

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 28 |
| approximated | 0 |
| residue | 0 |
| **total** | 28 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| monthly loan payment, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | monthly loan payment |  |
| purchase and delivery agreement, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | purchase and delivery agreement |  |
| payment with late fee, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | payment with late fee |  |
| staged service contract, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | staged service contract |  |
| construction contract workflow, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | construction contract workflow |  |
| lease termination and deposit return, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | lease termination and deposit return |  |
| landlord repair obligation, obligation 1 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | landlord repair obligation |  |
| purchase and delivery agreement, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | purchase and delivery agreement |  |
| payment with late fee, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | payment with late fee |  |
| staged service contract, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | staged service contract |  |
| construction contract workflow, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | construction contract workflow |  |
| lease termination and deposit return, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | lease termination and deposit return |  |
| landlord repair obligation, obligation 2 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | landlord repair obligation |  |
| staged service contract, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | staged service contract |  |
| construction contract workflow, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | construction contract workflow |  |
| lease termination and deposit return, obligation 3 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | lease termination and deposit return |  |
| construction contract workflow, obligation 4 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | construction contract workflow |  |
| lease termination and deposit return, obligation 4 | obligation | encoded | an obligation -> a fluent; met -> a law of its action; missed -> a law of any later event | lease termination and deposit return |  |
| #TRACE `monthly loan payment` (line 147) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_147 |  |
| #TRACE `monthly loan payment` (line 151) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_151 |  |
| #TRACE `purchase and delivery agreement` (line 154) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_154 |  |
| #TRACE `payment with late fee` (line 159) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_159 |  |
| #TRACE `payment with late fee` (line 163) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_163 |  |
| #TRACE `staged service contract` (line 166) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_166 |  |
| #TRACE `construction contract workflow` (line 172) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_172 |  |
| #TRACE `lease termination and deposit return` (line 179) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_179 |  |
| #TRACE `landlord repair obligation` (line 185) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_185 |  |
| #TRACE `landlord repair obligation` (line 189) | trace | encoded | a #TRACE -> a scenario (its events one per cycle) | trace_189 |  |

