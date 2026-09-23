# Solidity and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Solidity is the language in which most smart contracts on Ethereum and the
other EVM chains are written. A contract holds state: numbers, addresses, and
mappings that give a value for each key. A contract's public functions are the
calls that anyone can make on the contract. A call that fails one of the
contract's checks *reverts*, which is to say that the call changes nothing at
all.

The link between Solidity and LPS (Logic Production System) goes both ways.
**File ▸ Open…** takes a `.sol` contract and opens the contract as a program
in Logical English for LPS: one causal law for each write to the contract's
state, and one integrity constraint for each revert. This IDE (the editor you
write and run programs in) then runs that program, explains it and animates
it. **Misc ▸ Deploy as Solidity…** goes the other way. That menu item writes
the LPS program in the editor — written either in LPS or in Logical English
for LPS — out as a Solidity contract, or says why it cannot, and opens the
contract in Remix, the Ethereum Foundation's editor in the browser. Opening a
contract needs Logical English installed beside LPS2 with the InsurLE
extensions, as on the hosted service. Deploying needs nothing but LPS2, and
needs Logical English only for a `.le` program.

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [Opening a contract](#opening-a-contract)
  - [Running the program](#running-the-program)
  - [The original and the legal view](#the-original-and-the-legal-view)
  - [Deploying a program as a contract](#deploying-a-program-as-a-contract)
  - [What it will cost, before you deploy it](#what-it-will-cost-before-you-deploy-it)
  - [What the contract refuses and the program does not](#what-the-contract-refuses-and-the-program-does-not)
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

1. Choose **File ▸ Open…** and pick a `.sol` file. The translation needs
   Logical English with the InsurLE extensions running on the server
   (`LPS_LE2_LIB`). Without them the contract opens as its own plain text, and
   the status line reports a note saying what is missing.
2. The server compiles the contract with solc 0.8, and finds the files that
   OpenZeppelin imports bring in. Of all the contracts in the sources, the
   server translates the **most derived concrete contract**, the one at the
   foot of the inheritance chain. The translation opens in a tab as a `.le`
   document named after the file (`Counter.sol` becomes `counter.le`).
3. Read the comment at the head of the document. The comment says what was
   translated and how, and says that anything not translated is marked
   `TODO`. The translator's notes, which the status line counts, sit in that
   same comment: how many elements were encoded, how many approximated, how
   many left as residue, and which of the constructor's parameters became
   named constants.

A contract with a constructor `constructor(address initialOwner)` opens with
the parameter as a named constant rather than an invented address:

```
initially the owner of the contract is the initial owner.
```

A freshly opened contract has **no scenario**, so the calls are yours to add.
The end of the document lists each action's sentence in the form a scenario
needs:

```
% To run it, add a scenario of calls (and `initially` facts for the state it starts from),
% each call a sentence of this form, with its time (`at 1`: from 1 to 2):
%   scenario one is:
%     *a caller* calls bump with by *an amount* at 1.
```

The header names the menu items of both editors. In this editor, the original
and the legal view are both in the **View** menu.

### Running the program

A Logical English for LPS program runs like any other program here: press
**Run**, or open the **Timeline**. Running the program needs Logical English
on the server, just as opening the contract did.

- An integrity constraint refuses any call the contract would revert. The
  timeline draws the refused call in the events strip, crossed out (`✗`), at
  the cycle where the call was made. Right-click the call and ask **why not**.
  The answer names the constraint, gives the line the constraint sits on, and
  gives the values the constraint held on.
- The fluents' lanes show the state after each call. A fluent declared
  `0 by default` has one extra line, *every other: balance(…, 0)*, for the keys
  that hold the default.

See [Asking why](../guide/ide.md#asking-why) for the questions the panes answer.

### The original and the legal view

- **View ▸ The original this was converted from** shows the Solidity source
  of a contract you opened in this session. For a twin opened from the
  server, the menu item shows the files in the `sources/` folder that sits
  beside the twin.
- **View ▸ Legal view: who may do what (Logical English)** turns the program
  into a timeless Logical English program. The legal view holds one rule for
  each action, saying who may make that call, which means that none of the
  action's integrity constraints applies. The legal view also holds one effect
  rule for each causal law, and a scenario holding the state just before each
  call of the program's own scenario. The legal view opens in a tab of its
  own. Its questions — may this call be made now? what does the call change?
  what would have to change for the call to be allowed? — are answered by the
  Logical English editor, and not by the engine here.

### Deploying a program as a contract

1. Open or write an LPS program: an LPS file, or a Logical English document
   that says `the target language is: lps.`
2. Choose **Misc ▸ Deploy as Solidity…**. The server compiles the program and
   translates it.
3. If the program can be translated, a window shows the contract, its length,
   and any notes — for instance, a note saying that a `% RESIDUE` block of the
   document is not in the contract. **Copy source** copies the contract.
   **Open in Remix IDE ↗** opens [Remix](https://app.remix.live/) in a new
   tab, with the contract already compiled in a fresh workspace: nothing to
   install, and no wallet needed.
4. In Remix, **Deploy & run ▸ Remix VM** puts the contract on a chain inside
   the page, with test accounts that already hold funds. The constructor asks
   for an address for each account the program names in its initial state
   (`alice_` for `alice`). The comment at the top of the contract lists the
   program's own scenario as the calls to make, in order, and says who makes
   each call:

```
/// @custom:scenario The program's own scenario, as calls (deploy, then call in this order):
///   1. (time 2) alice: transfer(bob, 300)
///   2. (time 3) bob: transfer(carol, 500)
```

At the command line, `lps solidity FILE` prints the contract on the ordinary
output channel, standard output. When the command cannot write a contract, it
prints the reasons on the error channel, standard error, and exits with status
1. Adding `--json` makes the command print the Remix address as well.

### What it will cost, before you deploy it

`lps solidity FILE --cost` measures the contract it has just written, rather
than estimating the cost. The command compiles the contract with solc, replays
the program's own scenario on an EVM, and then reports

- the size of the **deployed bytecode** and of the **creation code**, each
  against its limit — EIP-170's 24,576 bytes and EIP-3860's 49,152. Above
  either limit there is no contract to deploy at all, so the export is
  **refused**, not merely noted;
- the **deployment gas**;
- for each call of the scenario, the **gas it used**, the **intrinsic and
  calldata** a transaction also pays (21,000 plus EIP-2028's 4 and 16 a byte),
  the total, and whether it reverted;
- the functions whose cost solc could not put a limit on by reading the code.
  Solc says "infinite" for those, which means *solc's analysis found no
  limit*, not *expensive*;
- the **fork** and the **solc version** that the figures belong to, printed
  with every figure. `--fork NAME` prices the contract at another hardfork
  (Cancun is the default), and `--optimizer-runs N` compiles the contract with
  another optimiser setting. Each of the two changes every number, which is
  why the report prints both.

A typical report, of the ERC-20 twin:

```
info: code_size: the deployed bytecode: 2759 bytes of the EIP-170 limit of 24576 (11.2%).
info: cost_deploy: deployment: 686243 gas of execution, 74576 intrinsic and calldata, 760819 in all.
info: cost_call: alice: transfer(bob, 300): 27986 gas of execution, 21584 intrinsic and calldata, 49570 in all.
info: cost_call: bob: transfer(carol, 500): 699 gas of execution, 21584 intrinsic and calldata, 22283 in all — it reverted, and on chain the intrinsic is paid anyway.
```

When a program **states a budget** (`it must not be true that the gas of
transfer is an amount and the amount > 60000.` — Logical English for LPS
§3.10), the command measures the contract whether or not you give `--cost`. A
budget that is broken refuses the export, and the message carries the figure.
A call that comes within 20% of its budget raises a warning. The same figures
appear as notes on **Misc ▸ Deploy as Solidity**, and in the ledger of a twin
that came from a contract, under *What it costs to deploy*.

### What the contract refuses and the program does not

The contract says `pragma ^0.8`, so every `+ - *` in the contract reverts when
the number grows past the largest one the EVM can hold (Panic 0x11), and every
`/ %` reverts when the divisor is zero (Panic 0x12). Whole numbers in the
program, by contrast, have no ceiling. Where the program does not already
forbid what the contract would refuse, the export names the place and offers
the sentence that would close the gap. The export never writes that sentence
into the document for you:

```
info: unbounded_arithmetic (erc20.le:49): the contract reverts if an addition goes past
  the largest whole number (Panic 0x11) in a call of transfer, and the program does not
  forbid it: the balance + the second thing the call is given. … To forbid it, write an
  integrity constraint about this call … with `and the largest whole number is an amount
  and the balance + the second thing the call is given > the amount.` added to it.
```

Once you have written the sentence, the program refuses the very call the
chain would revert. The writer then recognises your sentence as the same limit
Solidity enforces at that `+`, so the writer does *not* put the limit into the
contract a second time as a revert of its own.

### When a program is refused

When something in the program has no straight translation, **nothing is
written at all**. The window *Deploy as Solidity — not translatable* lists
each problem with its code, its message and a link to the line it sits on. For
example:

```
reactive_rule: a reactive rule (if … then …): a contract does nothing on its own — it only answers calls.
non_integer: division with / can give a fraction, and the EVM has integers only: write // (integer division) if that is what is meant.
```

A program that does not compile is reported as such, together with the
compiler's own messages. A program with no actions at all — a legal view, or a
Logical English program that only answers questions — is refused in a single
sentence. [Traps](#traps) gives the full list of reasons.

### Examples to try

Open them with **File ▸ Open example from server…**, where they are listed as
*solidity twin: …* (the folder is `examples/migration/solidity/`). The
translator wrote each twin from the contract in that twin's own `sources/`
folder. Each twin comes with a ledger (`<twin>.ledger.md`) saying what was
translated and how, and with a scenario of calls; a comment above the scenario
gives the final state those calls should reach.

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

The translator follows every public or external function that changes state
along every path through that function, writing modifiers, internal calls,
`super` and overrides out in place as it goes. A path that ends in a revert
becomes a constraint. A path that succeeds becomes one law for each write to
state, and each of those laws carries the conditions of the path it came from.

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

**Why the defaults matter.** A Solidity mapping answers for every key: a key
nobody has written to reads as 0. An LPS fluent is a relation, so an entry
that is not there is simply not there. Without `0 by default`, a transfer to
an account that holds no balance fact would take the money from the sender and
credit nobody. With `0 by default`, a missing entry reads as 0, and an update
takes 0 as the old value. See
[`; 0 by default`](../reference/le-for-lps.md#-0-by-default).

**The order of writes within a call** is LPS's own order. The conditions are
read on the state as it stood before the call. Then the terminations, the
initiations and the updates are applied, and each update reads the value the
earlier ones left behind. Two updates of one entry therefore build on each
other exactly as two EVM storage writes do, which is why a transfer to oneself
leaves the balance unchanged.

**Arithmetic that reverts, and `unchecked`.** Since Solidity 0.8 a checked
`+ - *` reverts when the number goes out of range, and a checked `/ %` reverts
when the divisor is zero. Each of those is a revert path of the function like
any other, and each becomes an integrity constraint:

```
% reverts: Panic 0x11 (arithmetic overflow or underflow)
it must not be true that
    a minter mints an amount for a recipient
    and the total supply is a second amount
    and second amount + amount > the largest amount.
```

Most such paths cannot happen. A function that has already refused the call
when `fromBalance < value` cannot then fall below zero at
`fromBalance - value`. The translator leaves those paths out: it first checks
the path's own conditions for consistency, and drops a constraint that the
path already makes impossible. That is why the OpenZeppelin twins read exactly
as they read before any of this existed, and why Circle's FiatToken, which
guards less, gains four constraints.

Inside `unchecked { … }` the EVM wraps around instead of reverting, so there
is no constraint. What the twin does in that case is recorded in the ledger,
one row for each such block:

| what the block says | the twin |
|---|---|
| the path itself forbids the wrap | the plain arithmetic, `encoded` |
| a comment gives the invariant (OpenZeppelin's do) | the plain arithmetic, `approximated`, with `unchecked at …: assumes <the comment>` — the assumption is the contract's and the chain replay is what tests it |
| nothing | the wrap as it happens, `mod 2^256`, and the ledger says the contract never explained it |

### From an LPS program to a contract

The translation is fixed, and it reverses the translation above.

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

A fluent becomes a mapping to one value only when the program shows that the
fluent holds one value for each key. That means every initiation of the fluent
is guarded by the key being absent, or is paired in the same action with a
termination that clears the key, and that no initial state gives a key two
values. Any other fluent becomes a set.

The writer works the types out from the values that reach each position. A
whole number gives `uint256`, or `int256` when a negative number appears.
Text gives `string`. The caller's position, and the zero address, give
`address`. Any other name gives `bytes32`.

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

- **Solidity 0.8 only.** The server compiles sources with solc 0.8. A contract
  written for 0.4 to 0.7 does not compile, and opens as a `% TODO` comment
  carrying the compiler's errors and the source itself. Any other source that
  fails to compile is treated the same way.
- **Only one contract is translated**: the most derived concrete one. The
  contracts it inherits from are written out inside it, or, for the reference
  models that have been reviewed, written as `extends`.
- **Residue is not in the program.** Some parts of a contract are kept word
  for word in `% RESIDUE` blocks: calls out to other contracts (a price
  oracle, a token's `transfer` on another contract), `delegatecall` and
  proxies, assembly, try/catch, structs, storage arrays, and any loop other
  than the recognised patterns over one array parameter (a `break` or a branch
  inside the loop, or two arrays indexed together). The program runs without
  those paths, so a call that would take one of them is not modelled at all.
  `vault/vault_oracle.le` shows how to fill such a gap by hand.
- **Numbers out of range and gas are not modelled.** Solidity 0.8 reverts when
  a number grows too large or falls below zero, while the program's arithmetic
  has no such limits. A loop's gas limit does not exist in LPS at all.
- **Events are approximated.** The call itself records an `emit`, rather than
  a separate LPS event standing for it. `view` functions have no action of
  their own, because the fluents answer them.
- **Wording outside the reviewed models is mechanical** (`*a caller* calls
  credit with who *an account* with amount *an amount*`), and the ledger marks
  such wording for review. Renaming a template is safe, because the `known as`
  name is what ties the template to the predicate.
- **Absence reads differently with a default.** With `0 by default`,
  `it is not the case that the balance of bob is a thing` never holds, because
  bob has a balance of 0 at the very least. An aggregate over a fluent that
  has a default counts or sums only the entries actually stored.
- **No scenario, no run.** A freshly opened contract has no calls. A scenario
  sentence needs its time (`from 1 to 2` or `at 1`). A sentence without a time
  is an error, not a call at time 0.
- **A `.zip` of sources** is read as a folder of sources, and the most derived
  concrete contract defined anywhere in it is the one translated.
- **Named constants from the constructor are names, not addresses.** `the
  initial owner` is a constant of its own. For the program to recognise a
  caller as the owner, the scenario must use that same name — or you must
  replace the name in `initially` with the account you are using.

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
- **A contract of the program, not of a standard.** The functions are named
  after the actions (`transfer`, `transferFrom`) and take addresses first and
  values afterwards, so ERC-20's `transfer(address,uint256)` keeps its
  selector. The rest does not follow the standard. The getters are named after
  the fluents (`balance`, not `balanceOf`). The events are named after the
  actions (`TransferFrom`). A revert carries its reason as a piece of text
  (`revert("ERC20InsufficientBalance")`) rather than as a custom error. And a
  fluent without a zero default gets a `has…` flag beside it. A wallet or a
  block explorer will therefore not recognise the contract as an ERC-20. Check
  that before you hand the contract to either.
- **Underflow reverts in the contract, not in the program.** Underflow is a
  number falling below zero. A number is `uint256` unless a negative number
  appears in its position. A program that lets a balance fall below zero
  simply carries on in LPS, while the contract reverts that call. State the
  check as an integrity constraint, as the twins do.
- **Accounts are constructor parameters.** A program cannot know addresses, so
  each account named in the initial state becomes an argument of the
  constructor, and it is for you to match the scenario's callers to Remix's
  test accounts.
- **Residue is left out.** A `% RESIDUE` block of a Logical English document
  is a comment, so the block is in neither the program nor the contract. The
  window says so in a note.
- **Only zero defaults.** A fluent with any other default (say `; 100 by
  default`) is refused. The contract would then need a flag for each key
  saying whether that key had been set, and removing exactly that flag is what
  the default was for.
- **Not audited.** The contract that comes out is checked against the
  program's own scenario on an EVM. Nobody has checked it for reentrancy, for
  gas, for access control beyond the program's own constraints, or for whether
  it can be upgraded.

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
