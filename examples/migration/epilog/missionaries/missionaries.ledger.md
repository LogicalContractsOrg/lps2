# Migration ledger: missionaries

Source: an Epilog game (Stanford Epilog, Games page) — missionaries.hrf
Translator: lpsPlus/migration/epilog (epilog_twin.pl)
Date: 2026-10-31

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 15 |
| approximated | 2 |
| residue | 0 |
| **total** | 17 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| left/1 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | left |  |
| left/2 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | left |  |
| right/1 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | right |  |
| right/2 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | right |  |
| goal/2 | view | encoded | a view over the state -> an intensional fluent | goal |  |
| legal_left/1 | view | encoded | a view over the state -> an intensional fluent | legal_left |  |
| legal_left/2 | view | encoded | a view over the state -> an intensional fluent | legal_left |  |
| legal_right/1 | view | encoded | a view over the state -> an intensional fluent | legal_right |  |
| legal_right/2 | view | encoded | a view over the state -> an intensional fluent | legal_right |  |
| terminal/0 | view | encoded | a view over the state -> an intensional fluent | terminal |  |
| role | game declaration | encoded | the roles: the values of the goal and control places (no sentence of their own) | the program |  |
| base | game declaration | encoded | the base relations: the fluents (their templates) | the program |  |
| action | game declaration | encoded | the moves: the actions (their templates name the places) | the program |  |
| init | game declaration | encoded | the initial state (`initially`), init evaluated | the program |  |
| symleq in legal_left/2 | built-in | approximated | symleq (a symbol order, to list a pair once) has no LE form: dropped, the view lists both orders | legal_left |  |
| symleq in legal_right/2 | built-in | approximated | symleq (a symbol order, to list a pair once) has no LE form: dropped, the view lists both orders | legal_right |  |
| step/1 | facts | encoded | facts only the game declarations read (base, action, init, a legal move that is always legal): LPS states those as templates, the initial state and no constraint, so the facts are not written |  |  |

