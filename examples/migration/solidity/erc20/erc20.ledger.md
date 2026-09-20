# Migration ledger: erc20

Source: Solidity — OpenZeppelin Contracts 5.0.2, token/ERC20/ERC20.sol, contracts/RefERC20.sol
Translator: the Solidity translator (with solcjs)
Date: 2026-09-20
Source licence: MIT (OpenZeppelin Contracts)

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 18 |
| approximated | 5 |
| residue | 0 |
| **total** | 23 |

Fidelity: **5 of 5** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| _balances | state variable | encoded | map([key(account,address)],uint) -> fluent | fluent balance |  |
| _allowances | state variable | encoded | map([key(account,address),key(spender,address)],uint) -> fluent | fluent allowance |  |
| _totalSupply | state variable | encoded | uint -> fluent | fluent total_supply |  |
| _name | state variable | encoded | string -> fluent | fluent token_name |  |
| _symbol | state variable | encoded | string -> fluent | fluent token_symbol |  |
| transfer | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer |  |
| transfer | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer | replayable from the chain's logs |
| transfer | unchecked block | encoded | unchecked at 6727:159:2: the call's own conditions already forbid the wrap, so the plain arithmetic is exact | action transfer |  |
| transfer | unchecked block | approximated | unchecked at 7139:182:2: assumes Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256. | action transfer | the assumption is the contract's and is not checked here; the replay against chain data is what tests it |
| approve | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action approve |  |
| approve | events | approximated | events Approval: recorded by the call itself (the action), not as separate LPS events | action approve | replayable from the chain's logs |
| transferFrom | function | encoded | 2 success path(s) -> laws, 7 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_from |  |
| transferFrom | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer_from | replayable from the chain's logs |
| transferFrom | unchecked block | encoded | unchecked at 11024:100:2: the call's own conditions already forbid the wrap, so the plain arithmetic is exact | action transfer_from |  |
| transferFrom | unchecked block | encoded | unchecked at 6727:159:2: the call's own conditions already forbid the wrap, so the plain arithmetic is exact | action transfer_from |  |
| transferFrom | unchecked block | approximated | unchecked at 7139:182:2: assumes Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256. | action transfer_from | the assumption is the contract's and is not checked here; the replay against chain data is what tests it |
| name | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| symbol | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| decimals | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| totalSupply | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| balanceOf | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| allowance | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| erc20 | balance(alice,700) | pass |  |
| erc20 | balance(bob,150) | pass |  |
| erc20 | balance(carol,150) | pass |  |
| erc20 | allowance(bob,dan,50) | pass |  |
| erc20 | total_supply(1000) | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state erc20.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: RefERC20 (contracts/RefERC20.sol).

## What it costs to deploy

*Deploy as Solidity* writes this twin back as a contract; these are that contract's figures, measured with solc 0.8.26 at the cancun fork, optimiser 200 runs. Gas is what the EVM used; *intrinsic* is the 21,000 a transaction pays plus its calldata (EIP-2028); *total* is what the sender is charged.

| | Bytes | Limit | |
|---|---|---|---|
| deployed bytecode | 2759 | 24,576 (EIP-170) | 11.2% |
| creation code | 3360 | 49,152 (EIP-3860) | 6.8% |

Deployment: 686243 gas.

| Call | Gas | Intrinsic | Total | |
|---|---|---|---|---|
| `alice: transfer(bob, 300)` | 27986 | 21584 | 49570 |  |
| `bob: transfer(carol, 500)` | 699 | 21584 | 22283 | reverted |
| `bob: approve(dan, 200)` | 24444 | 21572 | 46016 |  |
| `dan: transferFrom(bob, carol, 150)` | 34797 | 21940 | 56737 |  |
| `dan: transferFrom(bob, carol, 100)` | 1169 | 21940 | 23109 | reverted |
| `carol: transfer(carol, 150)` | 6086 | 21572 | 27658 |  |

