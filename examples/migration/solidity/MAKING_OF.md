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
| `erc20/sources/RefERC20.sol`, `ownable/sources/RefOwnable.sol`, `pausable/sources/RefPausable.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | Short "reference model" contracts that use OpenZeppelin Contracts 5.0.2 (written by the OpenZeppelin authors, MIT licence) unchanged: they only give the imported contract a starting state. The files of OpenZeppelin are not copied here: the package manager npm downloads them when the translator is installed. The twins translate those files, so the licence of OpenZeppelin Contracts is in `LICENSE-OpenZeppelin.txt`. |
| `mytoken/sources/MyToken.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | A token like those of the OpenZeppelin Contracts Wizard (OpenZeppelin's ERC-20, Ownable and Pausable; the owner mints). It is not the output of the Wizard: the Wizard writes a pausable token with OpenZeppelin's `ERC20Pausable`, and this contract uses `Pausable` and puts `whenNotPaused` on `_update` itself. |
| `fiat_token/sources/FiatTokenSubset.sol` | AI agent (Claude, in Claude Code), 2026-09-13 | Transcribed from four files of Circle's stablecoin-evm (https://github.com/circlefin/stablecoin-evm, `contracts/v1/`) into a newer Solidity. `FiatTokenV1.sol` and `Blacklistable.sol` are Circle's, under the Apache License 2.0. `Ownable.sol` and `Pausable.sol` are Circle's forks of OpenZeppelin's files, under the MIT licence. The opening comment of the file carries the notices of the four files and lists the changes. Circle did not review the file. |
| `LICENSE-OpenZeppelin.txt` | OpenZeppelin (zOS Global Limited and contributors) | The licence file of OpenZeppelin Contracts 5.0.2 (https://github.com/OpenZeppelin/openzeppelin-contracts, tag `v5.0.2`), copied unchanged on 2026-11-24. It applies to the OpenZeppelin code that the twins `erc20`, `ownable`, `pausable` and `mytoken` translate. |
| `vault/sources/Vault.sol`, `airdrop/sources/Airdrop.sol` | AI agent (Claude, in Claude Code), 2026-09-13 and 2026-09-14 | Written new, to try a contract that reads a price feed and one that loops over lists. |
| every `<twin>.le` (`erc20/erc20.le`, `ownable/ownable.le`, `pausable/pausable.le`, `mytoken/mytoken.le`, `fiat_token/fiat_token.le`, `vault/vault.le`, `airdrop/airdrop.le`), and the copies `mytoken/erc20.le`, `mytoken/ownable.le`, `mytoken/pausable.le`, `pausable/ownable.le` | Translator program, 2026-09-15 to 2026-09-20 | Written by the Solidity translator from the contract in `sources/`: one law per way a function can succeed, one constraint per way it can refuse. The copies are the twins that a twin includes. Not edited by hand. |
| every `<twin>.ledger.md` and `<twin>.ledger.json` | Translator program, same dates | The migration ledger: what each part of the twin was translated from. |
| `vault/vault_oracle.le`, `vault/vault_view.le` | AI agent (Claude, in Claude Code), 2026-09-13 | Written by the agent itself, not by the translator: the vault twin with its price-feed part filled in, and a view of it for a legal reader. |
| `replay/usdc_window.le`, `replay/usdc_window_12.le`, their `.json` and `.results.md` | Programs, 2026-09-13 | A replay of real USDC transactions: `replay_fetch.js` read a few blocks of the Ethereum blockchain on 2026-09-13, through the public endpoint `ethereum-rpc.publicnode.com`, without a key, and `sol_replay.pl` wrote the scenario and compared the twin's results with the chain's. The data is public: the addresses and the amounts are those that the blockchain shows to everyone. |
| `README.md`, `DETAILS.md` | Not recorded | Added on 2026-09-16 and 2026-09-23 in commits that do not say who wrote them. |

## The record

The twins were built in the InsurLE2 repository and moved here on 2026-09-16.
The translator is open source since November 2026: it is in the Logical English 2 repository, in `migration/`.

- InsurLE2 commit `0ca7270` (2026-09-13) "Migration Phase 1c/1d/1e: … Solidity front end with ERC-20/Ownable/Pausable/FiatToken reference models, legal view, E12/E13 and a USDC mainnet replay": adds the translator, the reference contracts, the vault examples and the replay; author "Miguel Calejo (via Claude)".
- InsurLE2 commit `e1c7e6b` (2026-09-14) "Phase 1e TODO implemented: the Solidity twins with defaults, named constants, no times, extends, and loops over lists": adds the airdrop; author "Miguel Calejo (via Claude)".
- LPS2 commit `294b1bf` (2026-09-16) "update telemetry, other changes relating to examples move": moves the twins here; no agent line (a move, not a new writing).
- translator: LE2's `migration/solidity/sol_migrate.pl` (the list of twins and the writer of each twin and ledger), over `sol_front.pl` (the reader of the compiler's output, `solc_ast.js`); the replay: `replay_fetch.js` and `sol_replay.pl`. The check: LE2's `migration/solidity/test_solidity.pl`.
