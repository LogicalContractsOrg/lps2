# Migration ledger: pausable

Source: Solidity — OpenZeppelin Contracts 5.0.2, utils/Pausable.sol with access/Ownable.sol, contracts/RefPausable.sol
Translator: InsurLE2/migration/solidity (sol_front.pl, solcjs)
Date: 2026-09-14
Source licence: MIT (OpenZeppelin Contracts)

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 10 |
| approximated | 4 |
| residue | 0 |
| **total** | 14 |

Fidelity: **2 of 2** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| _owner | state variable | encoded | address -> fluent | fluent owner |  |
| _paused | state variable | encoded | bool -> fluent | fluent paused |  |
| pause | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action pause |  |
| pause | events | approximated | events Paused: recorded by the call itself (the action), not as separate LPS events | action pause | replayable from the chain's logs |
| unpause | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action unpause |  |
| unpause | events | approximated | events Unpaused: recorded by the call itself (the action), not as separate LPS events | action unpause | replayable from the chain's logs |
| renounceOwnership | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action renounce_ownership |  |
| renounceOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action renounce_ownership | replayable from the chain's logs |
| transferOwnership | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_ownership |  |
| transferOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action transfer_ownership | replayable from the chain's logs |
| paused | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| owner | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |
| extends | inheritance | encoded | the laws, constraints and templates of ownable: theirs, by `extends`; this twin is what the contract adds | extends([ownable]) |  |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| pausable | owner(alice) | pass |  |
| pausable | paused | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state pausable.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: RefPausable (contracts/RefPausable.sol).
