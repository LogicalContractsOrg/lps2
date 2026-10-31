# Migration ledger: alquerque

Source: an Epilog game (Stanford Epilog, Games page) — alquerque.hrf
Translator: lpsPlus/migration/epilog (epilog_twin.pl)
Date: 2026-10-31

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 10 |
| approximated | 0 |
| residue | 3 |
| **total** | 13 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| jump/6 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | jump |  |
| move/4 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | move |  |
| goal/2 | view | encoded | a view over the state -> an intensional fluent | goal |  |
| terminal/0 | view | encoded | a view over the state -> an intensional fluent | terminal |  |
| role | game declaration | encoded | the roles: the values of the goal and control places (no sentence of their own) | the program |  |
| base | game declaration | encoded | the base relations: the fluents (their templates) | the program |  |
| action | game declaration | encoded | the moves: the actions (their templates name the places) | the program |  |
| legal | game declaration | encoded | the legal moves: an intensional fluent per move, and a constraint: a move that is not legal does not happen | the program |  |
| init | game declaration | encoded | the initial state (`initially`), init evaluated | the program |  |
| goodmove/1: a sentence with the functional term move(U,V,X,Y) | functional_term | residue | a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource | functional_term_1 |  |
| goodmove/1: a sentence with the functional term jump(U,V,W,X,Y,Z) | functional_term | residue | a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource | functional_term_2 |  |
| goodmove/1: a sentence with the functional term jump(U,V,W,X,Y,Z) | functional_term | residue | a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource | functional_term_3 |  |
| mark/1 | facts | encoded | facts only the game declarations read (base, action, init, a legal move that is always legal): LPS states those as templates, the initial state and no constraint, so the facts are not written |  |  |

## Residue

- **goodmove/1: a sentence with the functional term move(U,V,X,Y)** (functional_term) — a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource; in the program: functional_term_1. 
- **goodmove/1: a sentence with the functional term jump(U,V,W,X,Y,Z)** (functional_term) — a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource; in the program: functional_term_2. 
- **goodmove/1: a sentence with the functional term jump(U,V,W,X,Y,Z)** (functional_term) — a Logical English place holds a constant, not a term (such as not(X), and(P,Q) or cell(a,1)): restate the term as a relation, or write it in an included Prolog resource; in the program: functional_term_3. 

