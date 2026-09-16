# Migration ledger: ownable

Source: Solidity — OpenZeppelin Contracts 5.0.2, access/Ownable.sol, contracts/RefOwnable.sol
Translator: the Solidity translator (with solcjs)
Date: 2026-09-16
Source licence: MIT (OpenZeppelin Contracts)

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 5 |
| approximated | 2 |
| residue | 0 |
| **total** | 7 |

Fidelity: **1 of 1** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| _owner | state variable | encoded | address -> fluent | fluent owner |  |
| renounceOwnership | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action renounce_ownership |  |
| renounceOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action renounce_ownership | replayable from the chain's logs |
| transferOwnership | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_ownership |  |
| transferOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action transfer_ownership | replayable from the chain's logs |
| owner | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| ownable | not(owner(A)) | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state ownable.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: RefOwnable (contracts/RefOwnable.sol).
