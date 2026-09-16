# Migration ledger: compose

Source: a Daml project (Daml 3, Canton) — daml/Intro/Asset.daml, daml/Intro/Asset/Role.daml, daml/Intro/Asset/Trade.daml, daml/Test/Intro/Asset.daml, daml/Test/Intro/Asset/Role.daml, daml/Test/Intro/Asset/Trade.daml
Translator: the Daml translator
Date: 2026-09-16

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 33 |
| approximated | 6 |
| residue | 0 |
| **total** | 39 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template Asset | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | asset |  |
| template TransferProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | transfer_proposal |  |
| template TransferApproval | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | transfer_approval |  |
| template AssetHolderInvite | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | asset_holder_invite |  |
| template AssetHolder | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | asset_holder |  |
| template Trade | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | trade |  |
| signatory issuer of Asset | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Asset |  |
| signatory owner of Asset | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Asset |  |
| signatory signatory asset of TransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferProposal |  |
| signatory asset.issuer of TransferApproval | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | TransferApproval |  |
| signatory issuer of AssetHolderInvite | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | AssetHolderInvite |  |
| signatory issuer of AssetHolder | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | AssetHolder |  |
| signatory owner of AssetHolder | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | AssetHolder |  |
| signatory baseAsset.owner of Trade | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Trade |  |
| observer observers of Asset | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Asset |  |
| observer newOwner of TransferProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | TransferProposal |  |
| observer asset.owner of TransferApproval | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | TransferApproval |  |
| observer newOwner of TransferApproval | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | TransferApproval |  |
| observer owner of AssetHolderInvite | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | AssetHolderInvite |  |
| observer quoteAsset.owner of Trade | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | Trade |  |
| ensure (quantity > 0.0) (Asset) | ensure | encoded | ensure -> an integrity constraint on every create | Asset |  |
| consuming choice Asset.Split | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | split |  |
| consuming choice Asset.Merge | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | merge |  |
| consuming choice Asset.ProposeTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | propose_transfer |  |
| consuming choice Asset.SetObservers | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | set_observers |  |
| consuming choice TransferProposal.TransferProposal_Accept | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_proposal_accept |  |
| consuming choice TransferProposal.TransferProposal_Cancel | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_proposal_cancel |  |
| consuming choice TransferProposal.TransferProposal_Reject | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_proposal_reject |  |
| consuming choice TransferApproval.TransferApproval_Cancel | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_approval_cancel |  |
| consuming choice TransferApproval.TransferApproval_Reject | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_approval_reject |  |
| consuming choice TransferApproval.TransferApproval_Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer_approval_transfer |  |
| consuming choice AssetHolderInvite.AssetHolderInvite_Accept | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | asset_holder_invite_accept |  |
| nonconsuming choice AssetHolder.Issue_Asset | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | issue_asset |  |
| nonconsuming choice AssetHolder.Accept_Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | accept_transfer |  |
| nonconsuming choice AssetHolder.Preapprove_Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | preapprove_transfer |  |
| consuming choice Trade.Trade_Cancel | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | trade_cancel |  |
| consuming choice Trade.Trade_Reject | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | trade_reject |  |
| consuming choice Trade.Trade_Settle | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | trade_settle |  |
| script fun(Test.Intro.Asset.Role,setupRoles,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(usdbank),app(var(allocateParty),[str(USD_Bank)])),bind(var(ahia),app(var(submit),[var(usdbank),do([expr(app(var(createCmd),[rec(con(AssetHolderInvite),[issuer-var(usdbank),owner-var(alice)])]))])])),bind(var(ahib),app(var(submit),[var(usdbank),do([expr(app(var(createCmd),[rec(con(AssetHolderInvite),[issuer-var(usdbank),owner-var(bob)])]))])])),bind(var(aha),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(ahia),con(AssetHolderInvite_Accept)]))])])),bind(var(ahb),app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(ahib),con(AssetHolderInvite_Accept)]))])])),expr(app(var(return),[tuple([var(alice),var(bob),var(usdbank),var(aha),var(ahb)])]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Test.Intro.Asset.Role,setupRoles,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(usdbank),app(var(allocateParty),[str(USD_Bank)])),bind(var(ahia),app(var(submit),[var(usdbank),do([expr(app(var(createCmd),[rec(con(AssetHolderInvite),[issuer-var(usdbank),owner-var(alice)])]))])])),bind(var(ahib),app(var(submit),[var(usdbank),do([expr(app(var(createCmd),[rec(con(AssetHolderInvite),[issuer-var(usdbank),owner-var(bob)])]))])])),bind(var(aha),app(var(submit),[var(alice),do([expr(app(var(exerciseCmd),[var(ahia),con(AssetHolderInvite_Accept)]))])])),bind(var(ahb),app(var(submit),[var(bob),do([expr(app(var(exerciseCmd),[var(ahib),con(AssetHolderInvite_Accept)]))])])),expr(app(var(return),[tuple([var(alice),var(bob),var(usdbank),var(aha),var(ahb)])]))])) |  |

