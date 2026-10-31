# Migration ledger: hunter

Source: an Epilog game (Stanford Epilog, Games page) — hunter.hrf
Translator: lpsPlus/migration/epilog (epilog_twin.pl)
Date: 2026-10-31

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
| move/4 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | move |  |
| goal/2 | view | encoded | a view over the state -> an intensional fluent | goal |  |
| legal_move/4 | view | encoded | a view over the state -> an intensional fluent | legal_move |  |
| terminal/0 | view | encoded | a view over the state -> an intensional fluent | terminal |  |
| role | game declaration | encoded | the roles: the values of the goal and control places (no sentence of their own) | the program |  |
| base | game declaration | encoded | the base relations: the fluents (their templates) | the program |  |
| action | game declaration | encoded | the moves: the actions (their templates name the places) | the program |  |
| init | game declaration | encoded | the initial state (`initially`), init evaluated | the program |  |
| col/1, piece/1, row/1 | facts | encoded | facts only the game declarations read (base, action, init, a legal move that is always legal): LPS states those as templates, the initial state and no constraint, so the facts are not written |  |  |

