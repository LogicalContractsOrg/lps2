# How the examples in this folder were made

A translator program wrote the twins in this folder's subfolders. A
translator is a program that reads another system's program, here a Solidity
contract for the Ethereum blockchain, and writes it again in Logical English
for LPS. The contracts rest on code that people wrote (OpenZeppelin's
contracts, Circle's USDC contract); the small contracts that wrap that code
for testing, and two worked examples, were written by an AI agent: Claude, an
AI model made by Anthropic, working in the Claude Code tool at Miguel Calejo's
request. The same agent wrote the translator.

| File | Made by | How |
|---|---|---|
| `erc20/sources/RefERC20.sol`, `ownable/sources/RefOwnable.sol`, `pausable/sources/RefPausable.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | Short "reference model" contracts that use OpenZeppelin Contracts 5.0.2 (written by the OpenZeppelin authors, MIT licence) unchanged: they only give the imported contract a starting state. |
| `mytoken/sources/MyToken.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | A token in the form that OpenZeppelin's Contracts Wizard produces (OpenZeppelin's ERC-20, Ownable and Pausable). The record does not say whether the Wizard itself was run. |
| `fiat_token/sources/FiatTokenSubset.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | Transcribed from Circle's FiatTokenV1 contracts (https://github.com/circlefin/stablecoin-evm, written by Circle, Apache License 2.0) into a newer Solidity; the file's opening comment lists every change. |
| `vault/sources/Vault.sol`, `airdrop/sources/Airdrop.sol` | AI agent (Claude, in Claude Code), 2026-09-13 and 2026-09-14 | Written new, to try a contract that reads a price feed and one that loops over lists. |
| every `<twin>.le` (`erc20/erc20.le`, `ownable/ownable.le`, `pausable/pausable.le`, `mytoken/mytoken.le`, `fiat_token/fiat_token.le`, `vault/vault.le`, `airdrop/airdrop.le`), and the copies `mytoken/erc20.le`, `mytoken/ownable.le`, `mytoken/pausable.le`, `pausable/ownable.le` | Translator program, 2026-09-15 to 2026-09-20 | Written by the Solidity translator from the contract in `sources/`: one law per way a function can succeed, one constraint per way it can refuse. The copies are the twins that a twin includes. Not edited by hand. |
| every `<twin>.ledger.md` and `<twin>.ledger.json` | Translator program, same dates | The migration ledger: what each part of the twin was translated from. |
| `vault/vault_oracle.le`, `vault/vault_view.le` | AI agent (Claude, in Claude Code), 2026-09-13 | Written by the agent itself, not by the translator: the vault twin with its price-feed part filled in, and a view of it for a legal reader. |
| `replay/usdc_window.le`, `replay/usdc_window_12.le`, their `.json` and `.results.md` | Programs, 2026-09-13 | A replay of real USDC transactions: `replay_fetch.js` read a few blocks of the Ethereum blockchain on 2026-09-13, and `sol_replay.pl` wrote the scenario and compared the twin's results with the chain's. |
| `README.md`, `DETAILS.md` | Not recorded | Added on 2026-09-16 and 2026-09-23 in commits that do not say who wrote them. |

## The record

The twins were built in the InsurLE2 repository and moved here on 2026-09-16.
The translator now lives in the private lpsPlus repository.

- InsurLE2 commit `0ca7270` (2026-09-13) "Migration Phase 1c/1d/1e: … Solidity front end with ERC-20/Ownable/Pausable/FiatToken reference models, legal view, E12/E13 and a USDC mainnet replay": adds the translator, the reference contracts, the vault examples and the replay; author "Miguel Calejo (via Claude)".
- InsurLE2 commit `e1c7e6b` (2026-09-14) "Phase 1e TODO implemented: the Solidity twins with defaults, named constants, no times, extends, and loops over lists": adds the airdrop; author "Miguel Calejo (via Claude)".
- LPS2 commit `294b1bf` (2026-09-16) "update telemetry, other changes relating to examples move": moves the twins here; no agent line (a move, not a new writing).
- translator: `lpsPlus/migration/solidity/sol_migrate.pl` (the list of twins and the writer of each twin and ledger), over `sol_front.pl` (the reader of the compiler's output, `solc_ast.js`); the replay: `replay_fetch.js` and `sol_replay.pl`. The check: `lpsPlus/migration/solidity/test_solidity.pl`.
