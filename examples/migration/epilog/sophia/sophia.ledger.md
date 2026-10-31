# Migration ledger: sophia

Source: an Epilog game (Stanford Epilog, Games page) — sophia.hrf
Translator: lpsPlus/migration/epilog (epilog_twin.pl)
Date: 2026-10-31

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 6 |
| approximated | 0 |
| residue | 3 |
| **total** | 9 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| play/8 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | play |  |
| goal/2 | view | encoded | a view over the state -> an intensional fluent | goal |  |
| terminal/0 | view | encoded | a view over the state -> an intensional fluent | terminal |  |
| role | game declaration | encoded | the roles: the values of the goal and control places (no sentence of their own) | the program |  |
| init | game declaration | encoded | the initial state (`initially`), init evaluated | the program |  |
| solution/8: a sentence that calls the function rem/2 | function_call | residue | rem/2 is defined with := in the program, and Logical English has no user-defined functions in expressions | function_call_1 |  |
| the function definition rem/2 (:=) | function_definition | residue | Logical English has no user-defined functions in expressions: the relations that call this function are residue too; restate it as a relation (`the F of X is Y if ...`) and call that | function_definition_1 |  |
| the function definition quo/2 (:=) | function_definition | residue | Logical English has no user-defined functions in expressions: the relations that call this function are residue too; restate it as a relation (`the F of X is Y if ...`) and call that | function_definition_2 |  |
| digit/1 | facts | encoded | facts only the game declarations read (base, action, init, a legal move that is always legal): LPS states those as templates, the initial state and no constraint, so the facts are not written |  |  |

## Residue

- **solution/8: a sentence that calls the function rem/2** (function_call) — rem/2 is defined with := in the program, and Logical English has no user-defined functions in expressions; in the program: function_call_1. 
- **the function definition rem/2 (:=)** (function_definition) — Logical English has no user-defined functions in expressions: the relations that call this function are residue too; restate it as a relation (`the F of X is Y if ...`) and call that; in the program: function_definition_1. 
- **the function definition quo/2 (:=)** (function_definition) — Logical English has no user-defined functions in expressions: the relations that call this function are residue too; restate it as a relation (`the F of X is Y if ...`) and call that; in the program: function_definition_2. 

