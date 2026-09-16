# Migration ledger: locking

Source: a Daml project (Daml 3, Canton) — daml/LockingByChangingState.daml, daml/Utilities.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 17 |
| approximated | 3 |
| residue | 0 |
| **total** | 20 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template LockableCoin | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | lockable_coin |  |
| template TransferProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | transfer_proposal |  |
| template CoinProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | coin_proposal |  |
| signatory issuer of LockableCoin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | LockableCoin |  |
| signatory owner of LockableCoin | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | LockableCoin |  |
| signatory coin.owner of TransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferProposal |  |
| signatory coin.issuer of TransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferProposal |  |
| signatory issuer of CoinProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | CoinProposal |  |
| observer locker of LockableCoin | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | LockableCoin |  |
| observer newOwner of TransferProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | TransferProposal |  |
| observer owner of CoinProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | CoinProposal |  |
| ensure (amount > 0.0) (LockableCoin) | ensure | encoded | ensure -> an integrity constraint on every create | LockableCoin |  |
| consuming choice LockableCoin.Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer |  |
| consuming choice LockableCoin.Lock | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | lock |  |
| consuming choice LockableCoin.Unlock | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | unlock |  |
| consuming choice TransferProposal.WithdrawTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | withdraw_transfer |  |
| consuming choice TransferProposal.AcceptTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | accept_transfer |  |
| consuming choice TransferProposal.RejectTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | reject_transfer |  |
| consuming choice CoinProposal.AcceptProposal | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | accept_proposal |  |
| script fun(LockingByChangingState,locking,[],app(var(script),[do([bind(list([var(issuer),var(owner),var(newOwner),var(locker)]),app(var(makePartiesFrom),[list([str(Bank),str(Me),str(You),str(Custodian Bank)])])),bind(var(propId),app(var(submit),[var(issuer),do([expr(app(var(createCmd),[rec(con(CoinProposal),[owner-var(owner),issuer-var(issuer),amount-num(100.0)])]))])])),bind(var(coinCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(propId),con(AcceptProposal)]))])])),bind(var(lockedCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinCid),rec(con(Lock),[newLocker-var(locker)])]))])])),expr(app(var(submitMustFail),[var(owner),do([expr(app(var(exerciseCmd),[var(lockedCid),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),bind(var(unlockedCid),app(var(submit),[var(locker),do([expr(app(var(exerciseCmd),[var(lockedCid),con(Unlock)]))])])),bind(var(propId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(unlockedCid),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),expr(app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(propId),con(AcceptTransfer)]))])]))])])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(LockingByChangingState,locking,[],app(var(script),[do([bind(list([var(issuer),var(owner),var(newOwner),var(locker)]),app(var(makePartiesFrom),[list([str(Bank),str(Me),str(You),str(Custodian Bank)])])),bind(var(propId),app(var(submit),[var(issuer),do([expr(app(var(createCmd),[rec(con(CoinProposal),[owner-var(owner),issuer-var(issuer),amount-num(100.0)])]))])])),bind(var(coinCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(propId),con(AcceptProposal)]))])])),bind(var(lockedCid),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(coinCid),rec(con(Lock),[newLocker-var(locker)])]))])])),expr(app(var(submitMustFail),[var(owner),do([expr(app(var(exerciseCmd),[var(lockedCid),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),bind(var(unlockedCid),app(var(submit),[var(locker),do([expr(app(var(exerciseCmd),[var(lockedCid),con(Unlock)]))])])),bind(var(propId),app(var(submit),[var(owner),do([expr(app(var(exerciseCmd),[var(unlockedCid),rec(con(Transfer),[newOwner-var(newOwner)])]))])])),expr(app(var(submit),[var(newOwner),do([expr(app(var(exerciseCmd),[var(propId),con(AcceptTransfer)]))])]))])])) |  |

