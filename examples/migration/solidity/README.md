# Solidity twins: what each file is, and how to run it

Written by the translator in `InsurLE2/migration/solidity/` (its README)
(Phase 1e of `docs/migration/roadmap.md`). Every `.le` file here is
generated — change the translator or its catalogue (`sol_migrate.pl`), not
the file — except `vault/vault_oracle.le` and `vault/vault_view.le`, which
are hand-written worked examples.

## Two kinds of program, two ways to run them

| Kind | First line | What it is | How to see it work |
|---|---|---|---|
| **Twin** (`<name>.le`) | `the target language is: lps.` | The contract, executable: one law per success path of each function, one integrity constraint per revert path, an instance (`initially`) and a scenario of calls with their times | In the Logical English editor: **Misc ▸ Run in LPS** (or the **Run in LPS** button that replaces the query bar for an LPS program) — the timeline, the state after each call, why a call was refused. Or open it in the LPS2 IDE (`LPS_LE2_LIB=/work ./lps ide`). From a shell: `LPS_LE2_DIR=/work /lps2/lps run <name>.le` |
| **Legal view** (computed, not stored) | `the target language is: prolog.` | Who may do what, when, with which effect — each action's constraints as one permission rule, each law as an effect rule, the state as the scenario | Open the twin and choose **Misc ▸ Legal View of This LPS Program** (LE editor) or **View ▸ Legal view** (LPS2 IDE): it is drawn from the twin, and from its run, each time, and opens as an ordinary LE program — pick a scenario and a query |

An LPS program has no queries: it runs in time, one call after another. So
the questions an LE user asks of a twin — *may bob transfer 500 to carol
now? what does the transfer change? what would have to change for it to be
allowed?* — are the legal view's queries. Drawn with the twin's run (the
LPS2 server runs it first), the legal view carries,
for every call of the twin's own scenario, a scenario `before_call_N` holding
the twin's state just before that call (as LPS2 computed it), a query
`may_call_N` expected to hold exactly when the twin accepted the call, a flip
query for a refused call, and effect queries for an accepted one, expected to
name the entries the call changed.

## What is checked, and where

All in `migration/solidity/test_solidity.pl`:

- each twin's final state is the EVM's for the same calls (the comment
  above the scenario lists it);
- call by call, the twin refuses exactly the calls the EVM reverts (the
  scenario marks them: `% the EVM reverts the next call (…)`);
- each twin's legal view, drawn from the twin and its run as the editors
  draw it, agrees with the twin on every call (its expectations, all run);
- the replays' laws are the FiatToken twin's, term by term; `vault_oracle.le`
  contains every law of `vault.le`.

## The directories

| Directory | Files |
|---|---|
| `erc20/`, `ownable/`, `pausable/`, `mytoken/` | the OpenZeppelin reference models: twin, ledger (`.ledger.md` / `.json`: what was translated and how), `sources/` (the contract translated). `pausable.le` extends `ownable`, `mytoken.le` extends `erc20` and `pausable`: their bases' twins are copied beside them (`pausable/ownable.le`; `mytoken/erc20.le`, `pausable.le`, `ownable.le`), because a base is found as an include is, in the program's own directory |
| `airdrop/` | batch calls over lists (Phase 1e (d)): an airdrop, a burn of a list of amounts, and an order-dependent search left as residue |
| `fiat_token/` | Circle's FiatToken logic: twin, ledger, `sources/` (the contract); two hand-reviewed legal-view scenarios, `freeze` and `ordinary`, are in the tests (`sol_migrate:legal_view_extra/3`) |
| `replay/` | the FiatToken twin replayed against USDC's mainnet history. `usdc_window.json` (and `_12`) is the chain data (`replay_fetch.js`); `usdc_window.le` is the twin **with the same laws**, bound to the chain's state before the window and with the window's logs as its scenario; `usdc_window.results.md` compares the final state LPS2 computes with the chain's (215 of 215, 849 of 849 values agree) |
| `vault/` | the external-oracle convention (E12). `vault.le` is the translated twin, `borrow` left as residue (it calls a price feed: a `% TODO` block with its source); `vault_oracle.le` extends it by hand — the price as a fluent an event of the environment sets, `borrow` as ordinary laws and a constraint; `vault_view.le` is the legal-readable side of the same borrow rule, the price an assumable question (the generated legal view of `vault.le` covers deposit only) |

### How the related files use one another

LE includes a whole document, its `initially` and scenario too; `extends`
(docs/le_lps_surface.md §1.1) takes a base's templates, laws and constraints
and leaves its instance out. So `vault_oracle.le` extends `vault.le`, and the
reference models that inherit another extend its twin. The replays do not:
a replay must also run when opened as bare text (the LPS2 IDE, **Run in
LPS**), where no base resolves, and its negative control swaps in a
deliberately wrong translation — so the replays repeat the twin's laws,
written by the same translator from the same contract, and the tests above
check that they are the twin's, term by term. Each file's header names the
files it relates to.

## Opening your own contract

**File ▸ Open** in the Logical English editor (and in the LPS2 IDE) accepts a
`.sol` file, or a `.zip` of a source tree: the most derived concrete contract
is translated the same way (`migration/solidity/sol_import.pl`), with its
ledger beside it and the contract in `sources/` (**File ▸ Show the
Original** in the LE editor, **View ▸ The original this was converted from**
in the LPS2 IDE); its legal view is **Misc ▸ Legal View of This LPS Program**
(LE editor) or **View ▸ Legal view** (LPS2 IDE). Its constructor's parameters become named
constants (`the initial owner`); a function the translator does not follow
(a loop, an external call, assembly) is kept, verbatim, in a `% TODO` block;
sources that do not compile open as a `% TODO` comment with the compiler's
reason and the source.
