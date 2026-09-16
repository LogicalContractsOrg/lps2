# Migration ledger: parties

Source: a Daml project (Daml 3, Canton) — daml/Parties.daml
Translator: InsurLE2/migration/daml (daml_twin.pl)
Date: 2026-09-15

## Summary

| Verdict | Source elements |
|---|---|
| encoded | 24 |
| approximated | 7 |
| residue | 0 |
| **total** | 31 |

Fidelity: 0 source test(s) translated to scenarios; not run.

A source element is **encoded** when a documented mapping rule translated it with its meaning unchanged, **approximated** when the mapping changes its meaning in a documented way (see the note), and **residue** when it was not translated: it is marked in the program (`% RESIDUE <id> BEGIN ... END`) for the LE Contract Assistant or a person.

## Source elements

| Source element | Kind | Verdict | Mapping | In the program | Note |
|---|---|---|---|---|---|
| template SimpleIou | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | simple_iou |  |
| template Iou | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | iou |  |
| template IouProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | iou_proposal |  |
| template IouTransferProposal | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | iou_transfer_proposal |  |
| template IouSender | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | iou_sender |  |
| template NonTransitive | template | encoded | template -> a fluent keyed by the contract id; create -> an action (initiates it) | non_transitive |  |
| signatory issuer of SimpleIou | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | SimpleIou |  |
| signatory issuer of Iou | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Iou |  |
| signatory owner of Iou | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | Iou |  |
| signatory iou.issuer of IouProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | IouProposal |  |
| signatory signatory iou of IouTransferProposal | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | IouTransferProposal |  |
| signatory receiver of IouSender | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | IouSender |  |
| signatory partyA of NonTransitive | signatory | encoded | signatory -> the submitter of a create must be it (an integrity constraint) | NonTransitive |  |
| observer iou.owner of IouProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | IouProposal |  |
| observer observer iou of IouTransferProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | IouTransferProposal |  |
| observer newOwner of IouTransferProposal | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | IouTransferProposal |  |
| observer sender of IouSender | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | IouSender |  |
| observer partyB of NonTransitive | observer | approximated | observer -> not in the twin: who sees a contract is Daml's privacy model, not its state | NonTransitive |  |
| consuming choice Iou.Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | transfer |  |
| consuming choice Iou.ProposeTransfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | propose_transfer |  |
| consuming choice Iou.Mutual_Transfer | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | mutual_transfer |  |
| consuming choice IouProposal.IouProposal_Accept | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | iou_proposal_accept |  |
| consuming choice IouTransferProposal.IouTransferProposal_Cancel | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | iou_transfer_proposal_cancel |  |
| consuming choice IouTransferProposal.IouTransferProposal_Reject | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | iou_transfer_proposal_reject |  |
| consuming choice IouTransferProposal.IouTransferProposal_Accept | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | iou_transfer_proposal_accept |  |
| nonconsuming choice IouSender.Send_Iou | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | send_iou |  |
| consuming choice NonTransitive.TryA | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | try_a |  |
| consuming choice NonTransitive.TryB | choice | encoded | choice -> an action of its controller: laws for its creates and archives, constraints for its controller, the active contract and its assertions | try_b |  |
| script fun(Parties,simple_iou_test,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(iou),app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(alice),owner-var(bob),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(passTime),[app(var(days),[num(1)])])),expr(app(var(passTime),[app(var(minutes),[num(10)])])),expr(app(var(submit),[var(alice),do([expr(app(var(archiveCmd),[var(iou)]))])]))])) | script | encoded | a Daml Script -> a scenario (its commands observed one per cycle) | fun(Parties,simple_iou_test,[],do([bind(var(alice),app(var(allocateParty),[str(Alice)])),bind(var(bob),app(var(allocateParty),[str(Bob)])),bind(var(iou),app(var(submit),[var(alice),do([expr(app(var(createCmd),[rec(con(SimpleIou),[issuer-var(alice),owner-var(bob),cash-rec(con(Cash),[amount-num(100.0),currency-str(USD)])])]))])])),expr(app(var(passTime),[app(var(days),[num(1)])])),expr(app(var(passTime),[app(var(minutes),[num(10)])])),expr(app(var(submit),[var(alice),do([expr(app(var(archiveCmd),[var(iou)]))])]))])) |  |
| not observed (a query, an assertion, user management or time): passTime days 1 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | simple_iou_test |  |
| not observed (a query, an assertion, user management or time): passTime minutes 10 | script_statement | approximated | a statement with nothing to observe (a query, an assertion, user management, time) | simple_iou_test |  |

