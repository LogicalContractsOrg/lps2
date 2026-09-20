# Migration ledger: airdrop

Source: Solidity — contracts/Airdrop.sol: batch calls, the loops over arrays of Phase 1e (d), contracts/Airdrop.sol
Translator: the Solidity translator (with solcjs)
Date: 2026-09-20
Source licence: MIT

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 5 |
| approximated | 0 |
| residue | 1 |
| **total** | 6 |

Fidelity: **4 of 4** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| balances | state variable | encoded | map([key(none,address)],uint) -> fluent | fluent balance |  |
| totalSupply | state variable | encoded | uint -> fluent | fluent total_supply |  |
| airdrop | function | encoded | 1 success path(s) -> laws, 3 revert path(s) -> constraints; modifiers and internal calls inlined | action airdrop |  |
| burnEach | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action burn_each |  |
| payFirstEmpty | function | residue | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action call_pay_first_empty | Break at 1761:5:0; wording generated from the identifiers: to review |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |

## Residue

- **payFirstEmpty** (function) — 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined; in the program: action call_pay_first_empty. Break at 1761:5:0; wording generated from the identifiers: to review

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| airdrop | balance(alice,985) | pass |  |
| airdrop | balance(bob,3) | pass |  |
| airdrop | balance(carol,5) | pass |  |
| airdrop | total_supply(993) | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state airdrop.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: Airdrop (contracts/Airdrop.sol).

## What it costs to deploy

Not measured: this twin is not translated back to Solidity: a condition calls member(F,C), which is Prolog, not state the contract holds.
