# Solidity and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Solidity is the language most smart contracts on Ethereum and the other
EVM chains are written in: a contract holds state (numbers, addresses,
mappings from keys to values), and its public functions are the calls anyone
can make on it; a call that fails a check *reverts* and changes nothing. The
integration goes both ways. **File ▸ Open…** takes a `.sol` contract and opens
it as a program in Logical English for LPS — one causal law per storage write,
one integrity constraint per revert — which this IDE runs, explains and
animates. **Misc ▸ Deploy as Solidity…** goes the other way: it writes the LPS
program in the editor (LPS, or Logical English for LPS) as a Solidity contract,
or says why it cannot, and opens the contract in Remix, the Ethereum
Foundation's browser IDE. Opening a contract needs Logical English beside LPS2
with the InsurLE extensions, as on the hosted service; deploying needs nothing
but LPS2 (and Logical English only for a `.le` program).

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [Opening a contract](#opening-a-contract)
  - [Running the program](#running-the-program)
  - [The original and the legal view](#the-original-and-the-legal-view)
  - [Deploying a program as a contract](#deploying-a-program-as-a-contract)
  - [When a program is refused](#when-a-program-is-refused)
  - [Examples to try](#examples-to-try)
- [How Solidity maps to LPS](#how-solidity-maps-to-lps)
  - [From a contract to Logical English for LPS](#from-a-contract-to-logical-english-for-lps)
  - [From an LPS program to a contract](#from-an-lps-program-to-a-contract)
- [Traps](#traps)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| Solidity → LPS | **File ▸ Open…** (on installations with Logical English and the InsurLE extensions) | `.sol` (Solidity 0.8) | a Logical English for LPS program: the contract's state as fluents, its functions as actions, reverts as integrity constraints, writes as causal laws; what was not translated as a `% TODO` block | the EVM: each example twin's scenario, call by call, ends in the state the EVM reaches for the same calls, and refuses exactly the calls the EVM reverts; the FiatToken twin replayed against 822 USDC mainnet calls agrees on 849 of 849 balances and the total supply |
| LPS → Solidity | **Misc ▸ Deploy as Solidity…** (also `lps solidity FILE` from the shell) | the program in the editor: `.lps`, `.pl` or `.le` (target language `lps`) | a Solidity contract to copy, or open in Remix IDE; or the list of what has no straight translation, each with its line | solc (the twins' contracts compile with no warning) and an in-process EVM: the program's own scenario replayed as calls ends in LPS2's final state |

## How to use it

### Opening a contract

1. **File ▸ Open…** and choose a `.sol` file. The translation needs Logical
   English with the InsurLE extensions in the server process
   (`LPS_LE2_LIB`); without them the contract opens as its own text, and the
   status line reports a note saying what is missing.
2. The contract is compiled with solc 0.8 (OpenZeppelin imports resolve) and
   the **most derived concrete contract** among the sources is translated. It
   opens in a tab as a `.le` document named after the file (`Counter.sol`
   becomes `counter.le`).
3. Read the header comment. It says what was translated and how, and that
   what was not is marked `TODO`. The translator's notes, which the status
   line counts, are a comment at the top: how many elements were encoded,
   approximated or left as residue, and which constructor parameters became
   named constants.

A contract with a constructor `constructor(address initialOwner)` opens with
the parameter as a named constant rather than an invented address:

```
initially the owner of the contract is the initial owner.
```

A freshly opened contract has **no scenario**: the calls are yours to add. The
end of the document lists each action's sentence in the form a scenario needs:

```
% To run it, add a scenario of calls (and `initially` facts for the state it starts from),
% each call a sentence of this form, with its time (`at 1`: from 1 to 2):
%   scenario one is:
%     *a caller* calls bump with by *an amount* at 1.
```

The header names the menu items of both editors: in this IDE the original and
the legal view are both in the **View** menu.

### Running the program

A Logical English for LPS program runs like any other program here: press
**Run**, or open the **Timeline**. Running it needs Logical English in the
server process, as opening it did.

- A call the contract would revert is refused by an integrity constraint. It
  is drawn on the timeline in the events strip, crossed out (`✗`), at the cycle
  it was made. Right-click it and ask **why not**: the answer names the
  constraint, its line, and the values it held on.
- The fluents' lanes show the state after each call. A fluent declared
  `0 by default` has one extra line, *every other: balance(…, 0)*, for the keys
  that hold the default.

See [Asking why](../guide/ide.md#asking-why) for the questions the panes answer.

### The original and the legal view

- **View ▸ The original this was converted from** shows the Solidity source
  of a contract you opened in this session. For a twin opened from the
  server, it shows the files of the `sources/` folder beside it.
- **View ▸ Legal view: who may do what (Logical English)** turns the program
  into a timeless Logical English program: one rule per action saying who may
  make the call (none of its integrity constraints applies), one effect rule
  per causal law, and a scenario holding the state just before each call of the
  program's own scenario. It opens in a tab of its own. Its queries (may this
  call be made now? what does it change? what would have to change for it to
  be allowed?) are answered by the Logical English editor, not by this engine.

### Deploying a program as a contract

1. Open or write an LPS program: an LPS file, or a Logical English document
   that says `the target language is: lps.`
2. **Misc ▸ Deploy as Solidity…**. The server compiles the program and
   translates it.
3. If it can be translated, a dialog shows the contract, its length, and
   notes (for instance, that a `% RESIDUE` block of the document is not in the
   contract). **Copy source** copies it. **Open in Remix IDE ↗** opens
   [Remix](https://app.remix.live/) in a new tab with the contract in a fresh
   workspace, compiled: nothing to install, no wallet.
4. In Remix, **Deploy & run ▸ Remix VM** deploys it to a chain inside the
   page, with funded test accounts. The constructor asks for an address for
   each account the program names in its initial state (`alice_` for
   `alice`). The comment at the top of the contract lists the program's own
   scenario as the calls to make, in order, with who makes each:

```
/// @custom:scenario The program's own scenario, as calls (deploy, then call in this order):
///   1. (time 2) alice: transfer(bob, 300)
///   2. (time 3) bob: transfer(carol, 500)
```

From a shell, `lps solidity FILE` prints the contract on standard output, or
the reasons it cannot on standard error with exit status 1; `--json` also
prints the Remix address.

### When a program is refused

When something in the program has no straight translation, **nothing is
written**. The dialog *Deploy as Solidity — not translatable* lists each
problem with its code, its message and a link to its line, for example:

```
reactive_rule: a reactive rule (if … then …): a contract does nothing on its own — it only answers calls.
non_integer: division with / can give a fraction, and the EVM has integers only: write // (integer division) if that is what is meant.
```

A program that does not compile is reported as such, with the compiler's
diagnostics. A program with no actions at all — a legal view, or a Logical
English program answered by queries — is refused in one sentence. The full
list of reasons is under [Traps](#traps).

### Examples to try

Open them with **File ▸ Open example from server…**; they are listed as
*solidity twin: …* (the folder `examples/migration/solidity/`). Each twin was
written by the translator from the contract in its `sources/` folder, with a
ledger (`<twin>.ledger.md`) of what was translated and how, and a scenario of
calls whose expected final state is a comment above it.

| Program | What it shows |
|---|---|
| `erc20/erc20.le` | OpenZeppelin's ERC-20: a transfer beyond the balance and a `transferFrom` beyond the allowance refused, a transfer to oneself leaving the balance unchanged. Deploys. |
| `ownable/ownable.le`, `pausable/pausable.le` | OpenZeppelin's Ownable and Pausable; `pausable` extends `ownable`. |
| `mytoken/mytoken.le` | the OpenZeppelin Wizard token (ERC-20, Ownable, Pausable, the owner mints), written as `the knowledge base my token extends erc20, pausable.` |
| `fiat_token/fiat_token.le` | Circle's FiatToken logic: minters with allowances, a blacklist, pausing. |
| `airdrop/airdrop.le` | loops over array parameters, as aggregates over a list; an order-dependent loop left as residue. Refused by Deploy as Solidity (lists). |
| `vault/vault.le`, `vault/vault_oracle.le` | a borrow that calls a price feed, left as residue; the hand-written extension that makes the price a fluent an environment event sets. The oracle version is refused by Deploy (an environment event). |
| `replay/usdc_window.le` | the FiatToken laws bound to USDC's mainnet state, with 201 logged calls as the scenario; `usdc_window.results.md` compares the final state with the chain's. |

## How Solidity maps to LPS

### From a contract to Logical English for LPS

Each public or external function that changes state is followed along every
path through it — modifiers, internal calls, `super` and overrides inlined.
A path that ends in a revert becomes a constraint; a path that succeeds
becomes one law per storage write, each carrying the path's conditions.

| Solidity | Logical English for LPS |
|---|---|
| `uint256 x` | a fluent with a default: `the total supply is *an amount*; known as total_supply; 0 by default.` |
| `mapping(address => uint256)` (nested mappings too) | a fluent with one argument per key: `the balance of *an account* is *an amount*; known as balance; 0 by default.` |
| `bool`, `mapping(address => bool)` | a proposition, initiated and terminated |
| `address`, `string` | a fluent holding one value; an address is `the zero address by default` |
| a public or external function | an action whose first argument is the caller (`msg.sender`): `*a sender* transfers *an amount* to *a recipient*; known as transfer.` Contracts outside the reviewed reference models get neutral wording: `*a caller* calls bump with by *an amount*` |
| a revert path (`require`, `revert E()`, a modifier's check) | an integrity constraint, headed by the reason: `% reverts: ERC20InsufficientBalance` then `it must not be true that a sender transfers an amount to a recipient and the balance of the sender is a second amount and the second amount < the amount.` |
| a storage write on a success path | a causal law: `when a sender transfers an amount to a recipient then the balance of the recipient that is a second amount becomes second amount + amount.` |
| `if … else …` with both sides succeeding | the branch condition on the laws of each side |
| `x / y`, `x % y` | `//` and `mod` |
| `type(uint256).max`, a `constant` | a named constant: `the unlimited allowance is 115792089237316195423570985008687907853269984665640564039457584007913129639935.` |
| a loop over one array parameter, with independent writes, a sum, or a `require` | aggregates over a list: `a number is the count of each an element such that the element is in the list` |
| `emit Event(…)` | the action itself records the call (approximated: not a separate LPS event) |
| `view` and `pure` functions | answered by the fluents themselves |
| the constructor | `initially` facts; its parameters become named constants (`the initial owner`) |
| a contract inheriting a reference model | `extends` that model's twin |
| external calls, `delegatecall`, assembly, try/catch, structs, storage arrays, other loops | a residue block, `% RESIDUE … BEGIN` … `END`, with a `% TODO` line and the function's source verbatim; the function's other paths are still translated |

**Why constraints work as reverts.** LPS checks every integrity constraint
against the whole call before any causal law fires. A refused call therefore
has no effect at all, which is what a revert means. A successful call fires
all its laws, because each carries the conditions of its path.

**Why the defaults matter.** A Solidity mapping is total: every key reads 0
until written. An LPS fluent is a relation, and an absent entry is absent.
Without `0 by default`, a transfer to an account that holds no balance fact
would debit the sender and credit nobody. With it, an absent entry reads as 0,
and an update reads 0 as its old value. See
[`; 0 by default`](../reference/le-for-lps.md#-0-by-default).

**The order of writes within a call** is LPS's: conditions are read on the
state before the call, then terminations, initiations and updates are applied,
each update reading the value the earlier ones left. Two updates of one entry
therefore compose as two EVM storage writes do, which is why a transfer to
oneself leaves the balance unchanged.

### From an LPS program to a contract

The mapping is fixed. It is the reverse of the one above.

| LPS | Solidity |
|---|---|
| a fluent with no arguments | `bool` |
| a fluent `f(K…, V)` that holds one value per key | `mapping(K… => V) public f`, with `mapping(K… => bool) public hasF` beside it |
| the same, declared with a zero default (0, the zero address, false, the empty text) | the mapping alone, with no presence flag |
| any other fluent | a set: `mapping(A… => bool)` |
| an action `a(Caller, P…)` | `function a(P…) external`, the caller being `msg.sender`; addresses first, then values |
| an integrity constraint on one action, reading the state before | a check at the start of the function: `if (…) revert(…)` |
| the same, reading the state after | the same check, after the writes |
| a constraint that names no action | an invariant checked after every call |
| causal laws | state writes, in LPS's order |
| a named constant | a Solidity `constant` |
| `initially` | the constructor, taking an address for each account named |
| the scenario (`observe`) | the comment `@custom:scenario`: the calls to make |
| a Logical English template | parameter names, and the sentence as a comment above each function, fluent and check |

A fluent is written as a mapping to one value only when the program shows it
is one: every initiation of it is guarded by the key's absence, or paired in
the same action with a termination that clears the key, and no initial state
gives a key two values. Otherwise it is a set.

Types are inferred from the values that flow into each position: an integer
gives `uint256` (`int256` when a negative number appears), a string
`string`, the caller position or the zero address `address`, any other name
`bytes32`.

The ERC-20 twin, deployed, begins:

```
    // ---- named constants ----
    uint256 public constant THE_UNLIMITED_ALLOWANCE = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // ---- the fluents ----
    /// the allowance of *an owner* for *a spender* is *an amount*
    mapping(address => mapping(address => uint256)) public allowance;
    /// the balance of *an account* is *an amount*
    mapping(address => uint256) public balance;
```

and its transfer checks:

```
        if (recipient == address(0)) revert("ERC20InvalidReceiver");
        if (balance[msg.sender] < amount) revert("ERC20InsufficientBalance");
```

## Traps

**Opening a contract**

- **Solidity 0.8 only.** Sources are compiled with solc 0.8; a 0.4–0.7
  contract does not compile, and opens as a `% TODO` comment carrying the
  compiler's errors and the source. The same happens to any source that does
  not compile.
- **Only one contract is translated**: the most derived concrete one. Its
  bases are flattened into it (or, for the reviewed reference models, written
  as `extends`).
- **Residue is not in the program.** External calls (a price oracle, a
  token's `transfer` on another contract), `delegatecall` and proxies,
  assembly, try/catch, structs, storage arrays, and loops other than the
  recognised patterns over one array parameter (a `break` or a branch in the
  loop, two arrays indexed together) are kept verbatim in `% RESIDUE` blocks.
  The program runs without those paths: a call that would take one is not
  modelled. `vault/vault_oracle.le` shows how to fill such a gap by hand.
- **Integer overflow and gas are not modelled.** Solidity 0.8 reverts on
  overflow and underflow; the program's arithmetic is unbounded. A loop's gas
  bound does not exist in LPS.
- **Events are approximated.** An `emit` is recorded by the call itself, not
  as a separate LPS event. `view` functions have no action; the fluents answer
  them.
- **Wording outside the reviewed models is mechanical** (`*a caller* calls
  credit with who *an account* with amount *an amount*`), and the ledger flags
  it for review. Renaming a template is safe; the `known as` name ties it to
  the predicate.
- **Absence reads differently with a default.** With `0 by default`,
  `it is not the case that the balance of bob is a thing` never holds: bob has
  a balance of 0 at least. An aggregate over a defaulted fluent counts or sums
  only the stored entries.
- **No scenario, no run.** A freshly opened contract has no calls. A scenario
  sentence needs its time (`from 1 to 2` or `at 1`); one without is an error,
  not a call at time 0.
- **A `.zip` of sources** is read as a source tree: the most derived concrete
  contract defined in it is translated.
- **Named constants from the constructor are names, not addresses.** `the
  initial owner` is a constant of its own; for the program to recognise a
  caller as the owner, the scenario must use that same name, or you replace
  it in `initially` with the account you use.

**Deploying a program**

- **These have no straight translation, and are refused**, each with its
  line where it has one:
  - a reactive rule (`reactive_rule`): a contract does nothing on its own, it
    only answers calls;
  - an intensional fluent or a composite event;
  - planning: `lps_engine(planning, …)` or a goal to achieve;
  - an event the environment observes rather than an action someone calls
    (`environment_event`) — model it as an action of whoever reports it;
  - a constraint over two actions happening together (`concurrency`);
  - a constraint about a state other than just before or just after the call,
    or one that reads both (write it as two constraints);
  - a causal law whose conditions read a state other than the one before the
    call;
  - a timeless rule, or a condition that calls Prolog — lists, `member`,
    `sum_list` and `length` included (so `airdrop.le` is refused); timeless
    *facts* are written, as lookups;
  - a fraction: `/` or a non-integer number (`non_integer`) — write `//`;
  - a read that would have to search a mapping, because nothing binds the
    key (`enumeration`);
  - a fluent the program lets hold two values for one key (`two_values`);
  - a position that holds both numbers and names (`mixed_types`);
  - a default that is not the zero of its type (`default_not_zero`).
- **A contract of the program, not of a standard.** Functions are named after
  the actions (`transfer`, `transferFrom`) and take addresses first, then
  values, so ERC-20's `transfer(address,uint256)` keeps its selector. But the
  getters are named after the fluents (`balance`, not `balanceOf`), events
  after the actions (`TransferFrom`), reverts carry the reason as a string
  (`revert("ERC20InsufficientBalance")`) rather than a custom error, and a
  fluent without a zero default gets a `has…` flag. A wallet or a block
  explorer will not recognise it as an ERC-20. Check before handing it to one.
- **Underflow reverts in the contract, not in the program.** A number is
  `uint256` unless a negative number appears in its position. A program that
  lets a balance go below zero runs on in LPS; the contract reverts that call.
  State the check as an integrity constraint, as the twins do.
- **Accounts are constructor parameters.** A program cannot know addresses,
  so each named account in the initial state is a constructor argument, and
  the scenario's callers are for you to map onto Remix's test accounts.
- **Residue is left out.** A `% RESIDUE` block of a Logical English document
  is a comment, so it is neither in the program nor in the contract; the
  dialog notes it.
- **Only zero defaults.** A fluent with any other default (say `; 100 by
  default`) is refused: the contract would need a per-key "initialised" flag,
  which is what the default was meant to remove.
- **Not audited.** The generated contract is checked against the program's
  own scenario on an EVM, not for reentrancy, gas, access control beyond the
  program's constraints, or upgradeability.

## See also

- In this documentation:
  - [Integrations overview](index.md)
  - [Drools and LPS](drools.md), [Daml and LPS](daml.md) — the other
    contract-shaped imports
  - [Using the editor: the menus](../guide/ide.md#the-menus) and
    [Asking why](../guide/ide.md#asking-why)
  - Logical English for LPS: [`extends`](../reference/le-for-lps.md#11-extends--a-knowledge-base-built-on-others),
    [`; 0 by default`](../reference/le-for-lps.md#-0-by-default),
    [`the constants are:`](../reference/le-for-lps.md#the-constants-are),
    [integrity constraints](../reference/le-for-lps.md#37-it-must-not-be-true-that---integrity-constraints)
  - The LPS language: [defaults](../reference/lps.md#3a-defaults) and
    [constraints and preconditions](../reference/lps.md#10-constraints-and-preconditions)
- In the Logical English editor:
  - [Opening another system's file](https://le2.logicalcontracts.com/docs/user/integrations/index#opening-another-systems-file)
    and [Show the Original](https://le2.logicalcontracts.com/docs/user/integrations/index#show-the-original)
  - [Logical English for LPS](https://le2.logicalcontracts.com/docs/user/reference/lps-target)
- Solidity's own documentation:
  - [Solidity documentation](https://docs.soliditylang.org/en/latest/)
  - [Remix IDE documentation](https://remix-ide.readthedocs.io/en/latest/) and
    [Remix IDE](https://app.remix.live/)
  - [OpenZeppelin Contracts 5.x](https://docs.openzeppelin.com/contracts/5.x/)
  - [Circle's stablecoin-evm (FiatToken)](https://github.com/circlefin/stablecoin-evm)
