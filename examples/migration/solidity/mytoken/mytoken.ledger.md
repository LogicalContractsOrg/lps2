# Migration ledger: mytoken

Source: Solidity — an OpenZeppelin Wizard token: ERC20 + Ownable + Pausable (OpenZeppelin Contracts 5.0.2), contracts/MyToken.sol
Translator: InsurLE2/migration/solidity (sol_front.pl, solcjs)
Date: 2026-09-14
Source licence: MIT (OpenZeppelin Contracts)

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 25 |
| approximated | 8 |
| residue | 0 |
| **total** | 33 |

Fidelity: **4 of 4** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| _balances | state variable | encoded | map([key(account,address)],uint) -> fluent | fluent balance |  |
| _allowances | state variable | encoded | map([key(account,address),key(spender,address)],uint) -> fluent | fluent allowance |  |
| _totalSupply | state variable | encoded | uint -> fluent | fluent total_supply |  |
| _name | state variable | encoded | string -> fluent | fluent token_name |  |
| _symbol | state variable | encoded | string -> fluent | fluent token_symbol |  |
| _owner | state variable | encoded | address -> fluent | fluent owner |  |
| _paused | state variable | encoded | bool -> fluent | fluent paused |  |
| pause | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action pause |  |
| pause | events | approximated | events Paused: recorded by the call itself (the action), not as separate LPS events | action pause | replayable from the chain's logs |
| unpause | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action unpause |  |
| unpause | events | approximated | events Unpaused: recorded by the call itself (the action), not as separate LPS events | action unpause | replayable from the chain's logs |
| mint | function | encoded | 1 success path(s) -> laws, 3 revert path(s) -> constraints; modifiers and internal calls inlined | action mint |  |
| mint | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action mint | replayable from the chain's logs |
| renounceOwnership | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action renounce_ownership |  |
| renounceOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action renounce_ownership | replayable from the chain's logs |
| transferOwnership | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_ownership |  |
| transferOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action transfer_ownership | replayable from the chain's logs |
| transfer | function | encoded | 1 success path(s) -> laws, 3 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer |  |
| transfer | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer | replayable from the chain's logs |
| approve | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action approve |  |
| approve | events | approximated | events Approval: recorded by the call itself (the action), not as separate LPS events | action approve | replayable from the chain's logs |
| transferFrom | function | encoded | 2 success path(s) -> laws, 9 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_from |  |
| transferFrom | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer_from | replayable from the chain's logs |
| paused | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| owner | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| name | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| symbol | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| decimals | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| totalSupply | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| balanceOf | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| allowance | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |
| extends | inheritance | encoded | the laws, constraints and templates of erc20, pausable: theirs, by `extends`; this twin is what the contract adds | extends([erc20,pausable]) |  |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| mytoken | total_supply(1000) | pass |  |
| mytoken | balance(bob,700) | pass |  |
| mytoken | balance(carol,300) | pass |  |
| mytoken | owner(alice) | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state mytoken.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: MyToken (contracts/MyToken.sol).
