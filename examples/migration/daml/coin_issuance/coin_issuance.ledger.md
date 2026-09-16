# Migration ledger: coin_issuance

Source: a Daml project (Daml 3, Canton) — daml/CoinIssuance.daml, daml/Utilities.daml
Translator: the Daml translator
Date: 2026-09-16

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 27 |
| approximated | 10 |
| residue | 2 |
| **total** | 39 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template CoinMaster | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | coin_master |  |
| template CoinIssueProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | coin_issue_proposal |  |
| template CoinIssueAgreement | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | coin_issue_agreement |  |
| template Coin | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | coin |  |
| template LockedCoin | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | locked_coin |  |
| template TransferProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | transfer_proposal |  |
| signatory issuer of CoinMaster | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | CoinMaster |  |
| signatory coinAgreement.issuer of CoinIssueProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | CoinIssueProposal |  |
| signatory issuer of CoinIssueAgreement | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | CoinIssueAgreement |  |
| signatory owner of CoinIssueAgreement | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | CoinIssueAgreement |  |
| signatory issuer of Coin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Coin |  |
| signatory owner of Coin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Coin |  |
| signatory coin.issuer of LockedCoin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | LockedCoin |  |
| signatory coin.owner of LockedCoin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | LockedCoin |  |
| signatory coin.owner of TransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferProposal |  |
| signatory coin.issuer of TransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferProposal |  |
| observer coinAgreement.owner of CoinIssueProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | CoinIssueProposal |  |
| observer delegates of Coin | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Coin |  |
| observer locker of LockedCoin | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | LockedCoin |  |
| observer newOwner of TransferProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | TransferProposal |  |
| nonconsuming choice CoinMaster.Invite | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | invite |  |
| consuming choice CoinIssueProposal.AcceptCoinProposal | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | accept_coin_proposal |  |
| nonconsuming choice CoinIssueAgreement.Issue | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | issue |  |
| consuming choice Coin.Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer |  |
| consuming choice Coin.Lock | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | lock |  |
| consuming choice Coin.Archives | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | archives |  |
| consuming choice LockedCoin.Unlock | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | unlock |  |
| consuming choice TransferProposal.WithdrawProposal | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | withdraw_proposal |  |
| consuming choice TransferProposal.AcceptTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | accept_transfer |  |
| consuming choice TransferProposal.RejectTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | reject_transfer |  |
| consuming choice Coin.Disclose | choice | residue | a choice outside the subset | coin_disclose | `(p :: delegates)` adds to a list held in a place, which LE cannot yet say (a list is a value, not a collection a law changes) |
| consuming choice LockedCoin.Clawback | choice | residue | a choice outside the subset | locked_coin_clawback | the statement `getTime` is outside the subset (time, case, abort, a helper) |
| script fun(CoinIssuance,coinIssuance,[],app(var(script),[do([bind(list([var(issuer),var(owner),var(newOwner)]),app(var(makePartiesFrom),[list([str(Bank),str(Me),str(You)])])),expr(app(var(passTime),[app(var(days),[num(0)])])),bind(var(now),var(getTime)),bind(var(masterId),app(var(submit),[var(issuer),do([expr(app(var(createCmd),[rec(con(CoinMaster),[issuer-var(issuer)])]))])])),bind(var(coinAgmProp),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(masterId),rec(con(Invite),[owner-var(owner)])]))])])),bind(var(coinAgmId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinAgmProp),con(AcceptCoinProposal)]))])])),bind(var(coinId),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(coinAgmId),rec(con(Issue),[amount-num(100.0)])]))])])),bind(var(coinTransferPropId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinId),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),bind(var(coinId),app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(coinTransferPropId),con(AcceptTransfer)]))])])),bind(var(lockedCoinId),app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(coinId),rec(con(Lock),[maturity-app(var(addRelTime),[var(now),app(var(days),[num(2)])]),locker-var(issuer)])]))])])),expr(app(var(submitMustFail),[var(newOwner),do([expr(app(var(exerciseCmd),[var(lockedCoinId),con(Clawback)]))])])),bind(var(unlockedCoin),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(lockedCoinId),con(Unlock)]))])])),expr(app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(unlockedCoin),rec(con(Transfer),[newOwner-var(owner)])]))])]))])])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(CoinIssuance,coinIssuance,[],app(var(script),[do([bind(list([var(issuer),var(owner),var(newOwner)]),app(var(makePartiesFrom),[list([str(Bank),str(Me),str(You)])])),expr(app(var(passTime),[app(var(days),[num(0)])])),bind(var(now),var(getTime)),bind(var(masterId),app(var(submit),[var(issuer),do([expr(app(var(createCmd),[rec(con(CoinMaster),[issuer-var(issuer)])]))])])),bind(var(coinAgmProp),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(masterId),rec(con(Invite),[owner-var(owner)])]))])])),bind(var(coinAgmId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinAgmProp),con(AcceptCoinProposal)]))])])),bind(var(coinId),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(coinAgmId),rec(con(Issue),[amount-num(100.0)])]))])])),bind(var(coinTransferPropId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinId),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),bind(var(coinId),app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(coinTransferPropId),con(AcceptTransfer)]))])])),bind(var(lockedCoinId),app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(coinId),rec(con(Lock),[maturity-app(var(addRelTime),[var(now),app(var(days),[num(2)])]),locker-var(issuer)])]))])])),expr(app(var(submitMustFail),[var(newOwner),do([expr(app(var(exerciseCmd),[var(lockedCoinId),con(Clawback)]))])])),bind(var(unlockedCoin),app(var(submit),[var(issuer),do([expr(app(var(exerciseCmd),[var(lockedCoinId),con(Unlock)]))])])),expr(app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(unlockedCoin),rec(con(Transfer),[newOwner-var(owner)])]))])]))])])) |  |
| not observed (a query, an assertion, user management or time): passTime days 0 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |
| not observed (a query, an assertion, user management or time): getTime | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |
| the script uses `addRelTime now days 2`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |
| the script uses `lockedCoinId`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |
| the script uses `lockedCoinId`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |
| the script uses `unlockedCoin`, outside the subset: not observed | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | coinIssuance |  |

## Residue

- **consuming choice Coin.Disclose** (choice) — a choice outside the subset; in the program: coin_disclose. `(p :: delegates)` adds to a list held in a place, which LE cannot yet say (a list is a value, not a collection a law changes)
- **consuming choice LockedCoin.Clawback** (choice) — a choice outside the subset; in the program: locked_coin_clawback. the statement `getTime` is outside the subset (time, case, abort, a helper)

