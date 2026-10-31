# Migration ledger: grapheditor

Source: an Epilog game (Stanford Epilog, Games page) — grapheditor.rules
Translator: lpsPlus/migration/epilog (epilog_twin.pl)
Date: 2026-10-31

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 2 |
| approximated | 1 |
| residue | 1 |
| **total** | 4 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| copy/2 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | copy |  |
| insert/2 | operation | approximated | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined; the effects of calls deeper than five are not (deep_operations_1) | insert |  |
| invert/1 | operation | encoded | an operation definition -> causal laws (initiates / terminates), the operations it calls inlined | invert |  |
| insert/2: deeper calls | operation | residue | operations are inlined into the move's causal laws to a depth of five calls: the effects reached through deeper calls (or a recursive operation) have no law; state them as laws by hand | deep_operations_1 |  |

## Residue

- **insert/2: deeper calls** (operation) — operations are inlined into the move's causal laws to a depth of five calls: the effects reached through deeper calls (or a recursive operation) have no law; state them as laws by hand; in the program: deep_operations_1. 

