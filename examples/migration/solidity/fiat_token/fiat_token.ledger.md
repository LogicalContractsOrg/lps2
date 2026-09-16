# Migration ledger: fiat_token

Source: Solidity — Circle stablecoin-evm contracts/v1 (FiatTokenV1, Ownable, Pausable, Blacklistable), transcribed to Solidity 0.8 in contracts/FiatTokenSubset.sol, contracts/FiatTokenSubset.sol
Translator: the Solidity translator (with solcjs)
Date: 2026-09-16
Source licence: Apache-2.0 (Circle stablecoin-evm)

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 29 |
| approximated | 12 |
| residue | 0 |
| **total** | 41 |

Fidelity: **8 of 8** source test expectation(s) reproduced (100%).

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| _owner | state variable | encoded | address -> fluent | fluent owner |  |
| pauser | state variable | encoded | address -> fluent | fluent pauser |  |
| paused | state variable | encoded | bool -> fluent | fluent paused |  |
| blacklister | state variable | encoded | address -> fluent | fluent blacklister |  |
| blacklisted | state variable | encoded | map([key(account,address)],bool) -> fluent | fluent blacklisted |  |
| masterMinter | state variable | encoded | address -> fluent | fluent master_minter |  |
| balances | state variable | encoded | map([key(account,address)],uint) -> fluent | fluent balance |  |
| allowed | state variable | encoded | map([key(owner,address),key(spender,address)],uint) -> fluent | fluent allowance |  |
| totalSupply_ | state variable | encoded | uint -> fluent | fluent total_supply |  |
| minters | state variable | encoded | map([key(minter,address)],bool) -> fluent | fluent minter |  |
| minterAllowed | state variable | encoded | map([key(minter,address)],uint) -> fluent | fluent minting_allowance |  |
| transferOwnership | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_ownership |  |
| transferOwnership | events | approximated | events OwnershipTransferred: recorded by the call itself (the action), not as separate LPS events | action transfer_ownership | replayable from the chain's logs |
| pause | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action pause |  |
| pause | events | approximated | events Pause: recorded by the call itself (the action), not as separate LPS events | action pause | replayable from the chain's logs |
| unpause | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action unpause |  |
| unpause | events | approximated | events Unpause: recorded by the call itself (the action), not as separate LPS events | action unpause | replayable from the chain's logs |
| updatePauser | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action update_pauser |  |
| blacklist | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action blacklist |  |
| blacklist | events | approximated | events Blacklisted: recorded by the call itself (the action), not as separate LPS events | action blacklist | replayable from the chain's logs |
| unBlacklist | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action unblacklist |  |
| unBlacklist | events | approximated | events UnBlacklisted: recorded by the call itself (the action), not as separate LPS events | action unblacklist | replayable from the chain's logs |
| updateBlacklister | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action update_blacklister |  |
| mint | function | encoded | 1 success path(s) -> laws, 7 revert path(s) -> constraints; modifiers and internal calls inlined | action mint |  |
| mint | events | approximated | events Mint, Transfer: recorded by the call itself (the action), not as separate LPS events | action mint | replayable from the chain's logs |
| approve | function | encoded | 1 success path(s) -> laws, 4 revert path(s) -> constraints; modifiers and internal calls inlined | action approve |  |
| approve | events | approximated | events Approval: recorded by the call itself (the action), not as separate LPS events | action approve | replayable from the chain's logs |
| transferFrom | function | encoded | 1 success path(s) -> laws, 8 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer_from |  |
| transferFrom | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer_from | replayable from the chain's logs |
| transfer | function | encoded | 1 success path(s) -> laws, 5 revert path(s) -> constraints; modifiers and internal calls inlined | action transfer |  |
| transfer | events | approximated | events Transfer: recorded by the call itself (the action), not as separate LPS events | action transfer | replayable from the chain's logs |
| configureMinter | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action configure_minter |  |
| configureMinter | events | approximated | events MinterConfigured: recorded by the call itself (the action), not as separate LPS events | action configure_minter | replayable from the chain's logs |
| removeMinter | function | encoded | 1 success path(s) -> laws, 1 revert path(s) -> constraints; modifiers and internal calls inlined | action remove_minter |  |
| removeMinter | events | approximated | events MinterRemoved: recorded by the call itself (the action), not as separate LPS events | action remove_minter | replayable from the chain's logs |
| burn | function | encoded | 1 success path(s) -> laws, 5 revert path(s) -> constraints; modifiers and internal calls inlined | action burn |  |
| burn | events | approximated | events Burn, Transfer: recorded by the call itself (the action), not as separate LPS events | action burn | replayable from the chain's logs |
| updateMasterMinter | function | encoded | 1 success path(s) -> laws, 2 revert path(s) -> constraints; modifiers and internal calls inlined | action update_master_minter |  |
| balanceOf | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| totalSupply | view function | encoded | reads a fluent: the fluent itself answers it |  |  |
| constructor | constructor | encoded | run on the instance's arguments -> initially | initially |  |

## Source tests

| Source test | Query | Result | Detail |
|---|---|---|---|
| fiat_token | total_supply(600) | pass |  |
| fiat_token | balance(bob,470) | pass |  |
| fiat_token | balance(carol,100) | pass |  |
| fiat_token | balance(eve,30) | pass |  |
| fiat_token | allowance(bob,dan,20) | pass |  |
| fiat_token | minting_allowance(m1,400) | pass |  |
| fiat_token | minter(m1) | pass |  |
| fiat_token | paused | pass |  |


## The scenario

The twin's scenario runs under LPS2 (`lps state fiat_token.le`); each row of *Source tests* above compares one fluent of the final state with the value the EVM gives for the same calls (the Solidity semantics, worked by hand in sol_migrate.pl's catalogue). Calls the scenario marks `reverts` are refused by the twin's integrity constraints: they leave no trace in the state.

Contract: FiatTokenSubset (contracts/FiatTokenSubset.sol).
