# Migration ledger: vault

Source: Solidity — contracts/Vault.sol: a collateral vault reading a price feed (the E12 worked example), contracts/Vault.sol
Translator: the Solidity translator (with solcjs)
Date: 2026-09-20
Source licence: MIT

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 4 |
| approximated | 0 |
| residue | 1 |
| **total** | 5 |

Fidelity: **1 of 1** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| feed | state variable | encoded | address -> fluent | fluent feed | wording generated from the identifier: to review |
| collateral | state variable | encoded | map([key(account,address)],uint) -> fluent | fluent collateral | wording generated from the identifier: to review |
| debt | state variable | encoded | map([key(account,address)],uint) -> fluent | fluent debt | wording generated from the identifier: to review |
| deposit | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action call_deposit | wording generated from the identifiers: to review |
| borrow | function | residue | 0 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action call_borrow | external_call at 845:18:0; wording generated from the identifiers: to review |

## Residue

- **borrow** (function) — 0 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined; in the program: action call_borrow. external_call at 845:18:0; wording generated from the identifiers: to review

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| vault | collateral(alice,150) | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state vault.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: Vault (contracts/Vault.sol).

## What it costs to deploy

*Deploy as Solidity* writes this twin back as a contract; these are that contract's figures, measured with solc 0.8.26 at the cancun fork, optimiser 200 runs. Gas is what the EVM used; *intrinsic* is the 21,000 a transaction pays plus its calldata (EIP-2028); *total* is what the sender is charged.

| | Bytes | Limit | |
|---|---|---|---|
| deployed bytecode | 616 | 24,576 (EIP-170) | 2.5% |
| creation code | 644 | 49,152 (EIP-3860) | 1.3% |

Deployment: 123369 gas.

| Call | Gas | Intrinsic | Total | |
|---|---|---|---|---|
| `alice: callDeposit(100)` | 24250 | 21204 | 45454 |  |
| `alice: callDeposit(50)` | 5150 | 21204 | 26354 |  |

