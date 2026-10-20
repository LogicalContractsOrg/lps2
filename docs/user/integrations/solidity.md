# Solidity and LPS

*Kind: integration guide · Audience: users · Status: current (2026-09-16)*

Solidity is a programming language for smart contracts. A smart contract is a program
that runs on a blockchain. Most smart contracts on Ethereum and on the other EVM
chains are in Solidity. (EVM means Ethereum Virtual Machine, the machine that runs the
contracts.) A contract holds state: numbers, addresses, and mappings. A mapping gives
a value for each key. The public functions of a contract are the calls that all
persons can make on the contract.

Some calls fail one of the checks of the contract. Such a call *reverts*. A call that
reverts changes nothing.

The link between Solidity and LPS (Logic Production System) operates in the two
directions. **File ▸ Open…** takes a `.sol` contract. It opens the contract as a
program in Logical English for LPS. The program has one causal law for each write to
the state of the contract. A causal law tells how an action changes the state. The
program also has one integrity constraint for each revert. An integrity constraint is
a sentence that tells what must never be true.

This IDE (the editor where you write and run programs) then runs that program,
explains it and animates it. **Misc ▸ Deploy as Solidity…** operates in the other
direction. That menu item writes the LPS program in the editor as a Solidity
contract. The program can be in LPS or in Logical English for LPS. If the menu item
cannot write a contract, it tells you why. The menu item opens the contract in Remix.
Remix is the editor of the Ethereum Foundation, and it runs in the browser.

To open a contract, Logical English and the Logical English Translators must be
installed next to LPS2, as on the hosted service. To deploy a program, you need only
LPS2. You need Logical English only for a `.le` program.

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
| Solidity → LPS | **File ▸ Open…** (on installations that have Logical English and its translators, the Logical English Translators) | `.sol` (Solidity 0.8) | A program in Logical English for LPS. The state of the contract becomes fluents, its functions become actions, reverts become integrity constraints, and writes become causal laws. The parts that the translator did not translate go into a `% TODO` block. | The EVM. The scenario of each example twin, call by call, ends in the same state as the EVM for the same calls. The scenario refuses exactly the calls that the EVM reverts. The FiatToken twin, replayed against 822 USDC mainnet calls, agrees on 849 of 849 balances and on the total supply. |
| LPS → Solidity | **Misc ▸ Deploy as Solidity…** (also `lps solidity FILE` from the shell) | The program in the editor: `.lps`, `.pl` or `.le` (target language `lps`) | A Solidity contract that you can copy or open in Remix IDE. Or the list of the parts that have no direct translation, each with its line. | solc (the contracts of the twins compile with no warning) and an EVM in the same process. The scenario of the program, replayed as calls, ends in the final state of LPS2. |

## How to use it

### Opening a contract

Note: the translation needs Logical English and the Logical English Translators on the
server (`LPS_LE2_LIB`). If they are not there, the contract opens as plain text. The
status line then shows a note that tells what is missing.

Do these steps:

1. Select **File ▸ Open…**.
2. Select a `.sol` file.
3. Read the comment at the start of the document that opens.

The server compiles the contract with solc 0.8. The server also finds the files that
the OpenZeppelin imports bring in. The sources can contain many contracts. The server
translates the **most derived concrete contract**, the contract at the bottom of the
inheritance chain. The translation opens in a tab as a `.le` document. The document
has the name of the file (`Counter.sol` becomes `counter.le`).

The comment at the start of the document tells what the translator translated and
how. It also tells that the translator marked each part that it did not translate
with `TODO`. The notes of the translator are in the same comment, and the status line
counts them. The notes tell:

- how many elements the translator encoded;
- how many elements it approximated;
- how many elements it kept as residue;
- which parameters of the constructor became named constants.

Here is an example. A contract has the constructor `constructor(address initialOwner)`.
The contract opens with the parameter as a named constant, not as an invented
address:

```
initially the owner of the contract is the initial owner.
```

A contract that you open has **no scenario**. A scenario is a list of events and
facts that the program runs. You must add the calls yourself. The end of the document
gives the sentence of each action in the form that a scenario needs:

```
% To run it, add a scenario of calls (and `initially` facts for the state it starts from),
% each call a sentence of this form, with its time (`at 1`: from 1 to 2):
%   scenario one is:
%     *a caller* calls bump with by *an amount* at 1.
```

The header gives the names of the menu items of the two editors. In this editor, the
original and the legal view are both in the **View** menu.

### Running the program

A program in Logical English for LPS runs as all other programs do here. Click
**Run**, or open the **Timeline**. To run the program, Logical English must be on the
server, as for the opening of the contract.

- An integrity constraint refuses each call that the contract would revert. The
  timeline shows the refused call in the events strip, crossed out (`✗`). The call is
  at the cycle where it occurred. Right-click the call and ask **why not**. The answer
  gives the name of the constraint, the line of the constraint, and the values that
  the constraint used.
- The lanes of the fluents show the state after each call. A fluent is a fact that
  can change with time. A fluent that is declared `0 by default` has one more line,
  *every other: balance(…, 0)*. That line is for the keys that have the default
  value.

Refer to [Asking why](../guide/ide.md#asking-why) for the questions that the panes
answer.

### The original and the legal view

- **View ▸ The original this was converted from** shows the Solidity source of a
  contract that you opened in this session. For a twin that you opened from the
  server, the menu item shows the files in the `sources/` folder next to the twin. (A
  twin is a translation of a program from another system.)
- **View ▸ Legal view: who may do what (Logical English)** changes the program into a
  Logical English program without time. The legal view has one rule for each action.
  The rule tells who may make that call. That means that none of the integrity
  constraints of the action applies. The legal view also has one effect rule for each
  causal law. It also has a scenario with the state immediately before each call of
  the scenario of the program. The legal view opens in a tab of its own.
  The Logical English editor answers the questions of the legal view, not the engine
  here. Examples of these questions are: Can a person make this call now? What does
  the call change? What must change to let the call occur?

### Deploying a program as a contract

Do these steps:

1. Open or write an LPS program. The program can be an LPS file, or a Logical English
   document that has the sentence `the target language is: lps.`
2. Select **Misc ▸ Deploy as Solidity…**.
3. If a window shows the contract, click **Copy source** to copy the contract.
4. Click **Open in Remix IDE ↗** to open [Remix](https://app.remix.live/) in a new tab.
5. In Remix, select **Deploy & run ▸ Remix VM**.

After step 2, the server compiles the program and translates it. If the server can
translate the program, a window shows the contract, its length, and all notes. For
example, a note can tell that a `% RESIDUE` block of the document is not in the
contract.

After step 4, the contract is already compiled in a new workspace in Remix. You do not
have to install software, and you do not need a wallet.

After step 5, Remix puts the contract on a chain inside the page. The chain has test
accounts that already have funds. The constructor asks for an address for each
account that the program names in its initial state (`alice_` for `alice`). The
comment at the top of the contract gives the scenario of the program as the calls to
make, in sequence. The comment also tells who makes each call:

```
/// @custom:scenario The program's own scenario, as calls (deploy, then call in this order):
///   1. (time 2) alice: transfer(bob, 300)
///   2. (time 3) bob: transfer(carol, 500)
```

At the command line, `lps solidity FILE` writes the contract on the usual output
channel, standard output. Sometimes the command cannot write a contract. Then it
writes the reasons on the error channel, standard error, and it stops with status 1.
If you add `--json`, the command also writes the Remix address.

### What it will cost, before you deploy it

`lps solidity FILE --cost` measures the contract that it wrote. It does not estimate
the cost. The command compiles the contract with solc. Then it replays the scenario
of the program on an EVM. Then it gives these values:

- The size of the **deployed bytecode** and of the **creation code**. The command
  compares each size with its limit: 24,576 bytes (EIP-170) and 49,152 bytes
  (EIP-3860). If a size is more than its limit, you cannot deploy the contract. Thus
  the export is **refused**. It is not only a note.
- The **deployment gas**. (Gas is the unit of the cost of work on the chain.)
- For each call of the scenario: the **gas it used**, and the **intrinsic and
  calldata** gas that a transaction also pays (21,000 plus 4 and 16 for each byte, as
  in EIP-2028). Also the total, and if the call reverted.
- The functions for which solc could not find a cost limit from the code. Solc says
  "infinite" for these functions. This word means *the analysis of solc found no
  limit*. It does not mean *expensive*.
- The **fork** and the **solc version** of the values. The command writes them with
  each value. `--fork NAME` calculates the cost for a different hardfork (the default
  is Cancun). `--optimizer-runs N` compiles the contract with a different optimiser
  setting. Each of the two options changes all the numbers. Thus the report gives
  both.

A typical report, of the ERC-20 twin:

```
info: code_size: the deployed bytecode: 2759 bytes of the EIP-170 limit of 24576 (11.2%).
info: cost_deploy: deployment: 686243 gas of execution, 74576 intrinsic and calldata, 760819 in all.
info: cost_call: alice: transfer(bob, 300): 27986 gas of execution, 21584 intrinsic and calldata, 49570 in all.
info: cost_call: bob: transfer(carol, 500): 699 gas of execution, 21584 intrinsic and calldata, 22283 in all — it reverted, and on chain the intrinsic is paid anyway.
```

A program can **state a budget**, for example
`it must not be true that the gas of transfer is an amount and the amount > 60000.`
(refer to Logical English for LPS §3.10). Then the command measures the contract also
when you do not give `--cost`. If the contract breaks a budget, the command refuses
the export, and the message gives the value. If a call comes within 20% of its
budget, the command gives a warning. The same values show as notes in **Misc ▸ Deploy
as Solidity**. They also show in the ledger of a twin that came from a contract,
below *What it costs to deploy*.

### What the contract refuses and the program does not

The contract says `pragma ^0.8`. Thus each `+ - *` in the contract reverts when the
number becomes larger than the largest number that the EVM can hold (Panic 0x11).
Each `/ %` reverts when the divisor is zero (Panic 0x12). But whole numbers in the
program have no maximum. Sometimes the program does not already forbid a thing that
the contract would refuse. Then the export gives the location and the sentence that
closes the gap. The export never writes that sentence into the document for you:

```
info: unbounded_arithmetic (erc20.le:49): the contract reverts if an addition goes past
  the largest whole number (Panic 0x11) in a call of transfer, and the program does not
  forbid it: the balance + the second thing the call is given. … To forbid it, write an
  integrity constraint about this call … with `and the largest whole number is an amount
  and the balance + the second thing the call is given > the amount.` added to it.
```

When you write the sentence, the program refuses the same call that the chain would
revert. The writer then knows that your sentence is the same limit that Solidity
applies at that `+`. Thus the writer does *not* put the limit into the contract a
second time as a separate revert.

### When a program is refused

Sometimes a part of the program has no direct translation. Then the export **writes
nothing**. The window *Deploy as Solidity — not translatable* gives a list of the
problems. For each problem, the list gives its code, its message and a link to its
line. For example:

```
reactive_rule: a reactive rule (if … then …): a contract does nothing on its own — it only answers calls.
non_integer: division with / can give a fraction, and the EVM has integers only: write // (integer division) if that is what is meant.
```

If a program does not compile, the window tells you so, and it gives the messages of
the compiler. Some programs have no actions. Examples are a legal view, and a Logical
English program that only answers questions. The export refuses such a program in one
sentence. [Traps](#traps) gives the full list of reasons.

### Examples to try

Open the examples with **File ▸ Open example from server…**. The list shows them as
*solidity twin: …* (the folder is `examples/migration/solidity/`). The translator
wrote each twin from the contract in the `sources/` folder of that twin. Each twin has
a ledger (`<twin>.ledger.md`). The ledger tells what the translator translated and
how. Each twin also has a scenario of calls. A comment above the scenario gives the
final state that those calls must reach.

| Program | What it shows |
|---|---|
| `erc20/erc20.le` | The ERC-20 of OpenZeppelin. It refuses a transfer that is more than the balance, and a `transferFrom` that is more than the allowance. A transfer to the same account does not change the balance. You can deploy it. |
| `ownable/ownable.le`, `pausable/pausable.le` | Ownable and Pausable of OpenZeppelin. `pausable` extends `ownable`. |
| `mytoken/mytoken.le` | The OpenZeppelin Wizard token (ERC-20, Ownable, Pausable; the owner mints). It is written as `the knowledge base my token extends erc20, pausable.` |
| `fiat_token/fiat_token.le` | The FiatToken logic of Circle: minters with allowances, a blacklist, and a pause. |
| `airdrop/airdrop.le` | Loops over array parameters, as aggregates over a list. A loop that depends on the sequence stays as residue. Deploy as Solidity refuses this program (lists). |
| `vault/vault.le`, `vault/vault_oracle.le` | A borrow that calls a price feed, kept as residue. The extension, written by hand, makes the price a fluent that an environment event sets. Deploy refuses the oracle version (an environment event). |
| `replay/usdc_window.le` | The FiatToken laws on the mainnet state of USDC, with 201 logged calls as the scenario. `usdc_window.results.md` compares the final state with the state of the chain. |

## How Solidity maps to LPS

### From a contract to Logical English for LPS

The translator follows each public or external function that changes the state. It
follows each path through that function. As it goes, it puts the modifiers, the
internal calls, `super` and the overrides in their place. A path that ends in a revert
becomes a constraint. A path that succeeds becomes one law for each write to the
state. Each of those laws has the conditions of its path.

| Solidity | Logical English for LPS |
|---|---|
| `uint256 x` | A fluent with a default: `the total supply is *an amount*; known as total_supply; 0 by default.` |
| `mapping(address => uint256)` (also nested mappings) | A fluent with one argument for each key: `the balance of *an account* is *an amount*; known as balance; 0 by default.` |
| `bool`, `mapping(address => bool)` | A proposition that the program initiates and terminates. |
| `address`, `string` | A fluent that holds one value. An address is `the zero address by default`. |
| A public or external function | An action. Its first argument is the caller (`msg.sender`): `*a sender* transfers *an amount* to *a recipient*; known as transfer.` Contracts that are not reviewed reference models get neutral words: `*a caller* calls bump with by *an amount*` |
| A revert path (`require`, `revert E()`, the check of a modifier) | An integrity constraint, with the reason above it: `% reverts: ERC20InsufficientBalance` then `it must not be true that a sender transfers an amount to a recipient and the balance of the sender is a second amount and the second amount < the amount.` |
| A storage write on a success path | A causal law: `when a sender transfers an amount to a recipient then the balance of the recipient that is a second amount becomes second amount + amount.` |
| `if … else …` where the two sides succeed | The branch condition on the laws of each side. |
| `x / y`, `x % y` | `//` and `mod` |
| `type(uint256).max`, a `constant` | A named constant: `the unlimited allowance is 115792089237316195423570985008687907853269984665640564039457584007913129639935.` |
| A loop over one array parameter, with independent writes, a sum, or a `require` | Aggregates over a list: `a number is the count of each an element such that the element is in the list` |
| `emit Event(…)` | The action itself records the call (approximated: it is not a separate LPS event). |
| `view` and `pure` functions | The fluents give the answers. |
| The constructor | `initially` facts. Its parameters become named constants (`the initial owner`). |
| A contract that inherits from a reference model | `extends` the twin of that model. |
| External calls, `delegatecall`, assembly, try/catch, structs, storage arrays, other loops | A residue block, `% RESIDUE … BEGIN` … `END`, with a `% TODO` line and the exact source of the function. The translator still translates the other paths of the function. |

**Why constraints operate as reverts.** LPS checks each integrity constraint against
the full call before a causal law starts. Thus a refused call has no effect. That is
the meaning of a revert. A successful call starts all its laws, because each law has
the conditions of its path.

**Why the defaults are important.** A Solidity mapping gives a value for each key. A
key that nobody wrote to has the value 0. An LPS fluent is a relation. Thus an entry
that is not there does not exist. Without `0 by default`, a problem occurs with a
transfer to an account that has no balance fact. The transfer takes the money from
the sender and gives it to nobody. With `0 by default`, a missing entry has the value
0, and an update uses 0 as the old value. Refer to
[`; 0 by default`](../reference/le-for-lps.md#-0-by-default).

**The sequence of writes in a call** is the sequence of LPS. The program reads the
conditions on the state before the call. Then it applies the terminations, the
initiations and the updates. Each update reads the value that the earlier updates
left. Thus two updates of one entry operate as two EVM storage writes do. For this
reason, a transfer to the same account does not change the balance.

**Arithmetic that reverts, and `unchecked`.** Since Solidity 0.8, a checked `+ - *`
reverts when the number goes out of range. A checked `/ %` reverts when the divisor
is zero. Each of these reverts is a revert path of the function, as the other revert
paths are. Each one becomes an integrity constraint:

```
% reverts: Panic 0x11 (arithmetic overflow or underflow)
it must not be true that
    a minter mints an amount for a recipient
    and the total supply is a second amount
    and second amount + amount > the largest amount.
```

Most such paths cannot occur. For example, a function refuses the call when
`fromBalance < value`. Then the function cannot go below zero at
`fromBalance - value`. The translator does not include such paths. It first checks
that the conditions of the path agree with each other. Then it removes a constraint
that the path already makes impossible. For this reason, the OpenZeppelin twins are
the same as before this check existed. The FiatToken of Circle has fewer guards, and
it gets four constraints.

Inside `unchecked { … }`, the EVM wraps around and does not revert. Thus there is no
constraint. The ledger records what the twin does in that case, one row for each such
block:

| what the block says | the twin |
|---|---|
| The path itself forbids the wrap. | The plain arithmetic, `encoded`. |
| A comment gives the invariant (the comments of OpenZeppelin do). | The plain arithmetic, `approximated`, with `unchecked at …: assumes <the comment>`. The assumption is that of the contract, and the chain replay tests it. |
| Nothing. | The wrap as it occurs, `mod 2^256`. The ledger tells that the contract did not explain it. |

### From an LPS program to a contract

The translation is fixed. It is the reverse of the translation above.

| LPS | Solidity |
|---|---|
| A fluent with no arguments | `bool` |
| A fluent `f(K…, V)` that holds one value for each key | `mapping(K… => V) public f`, with `mapping(K… => bool) public hasF` next to it |
| The same, declared with a zero default (0, the zero address, false, the empty text) | Only the mapping, with no presence flag |
| All other fluents | A set: `mapping(A… => bool)` |
| An action `a(Caller, P…)` | `function a(P…) external`. The caller is `msg.sender`. Addresses come first, then values. |
| An integrity constraint on one action, that reads the state before | A check at the start of the function: `if (…) revert(…)` |
| The same, that reads the state after | The same check, after the writes |
| A constraint that names no action | An invariant that the contract checks after each call |
| Causal laws | State writes, in the sequence of LPS |
| A named constant | A Solidity `constant` |
| `initially` | The constructor. It takes an address for each account that the program names. |
| The scenario (`observe`) | The comment `@custom:scenario`: the calls to make |
| A Logical English template | Parameter names, and the sentence as a comment above each function, fluent and check |

A fluent becomes a mapping to one value only when the program shows that the fluent
holds one value for each key. For this, these conditions must be true:

- Each initiation of the fluent has a guard that the key is absent, or the same
  action also has a termination that clears the key.
- No initial state gives two values to a key.

All other fluents become sets.

The writer finds the types from the values that go to each position. A whole number
gives `uint256`, or `int256` when a negative number occurs. Text gives `string`. The
position of the caller, and the zero address, give `address`. All other names give
`bytes32`.

The deployed ERC-20 twin starts with these lines:

```
    // ---- named constants ----
    uint256 public constant THE_UNLIMITED_ALLOWANCE = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // ---- the fluents ----
    /// the allowance of *an owner* for *a spender* is *an amount*
    mapping(address => mapping(address => uint256)) public allowance;
    /// the balance of *an account* is *an amount*
    mapping(address => uint256) public balance;
```

These are the checks of its transfer:

```
        if (recipient == address(0)) revert("ERC20InvalidReceiver");
        if (balance[msg.sender] < amount) revert("ERC20InsufficientBalance");
```

## Traps

**Opening a contract**

- **Solidity 0.8 only.** The server compiles sources with solc 0.8. A contract for
  versions 0.4 to 0.7 does not compile. It opens as a `% TODO` comment with the errors
  of the compiler and the source itself. The server does the same with all other
  sources that do not compile.
- **The translator translates only one contract**: the most derived concrete
  contract. The contracts that it inherits from are written inside it. For the
  reviewed reference models, they are written as `extends`.
- **Residue is not in the program.** The translator keeps some parts of a contract
  word for word in `% RESIDUE` blocks. These parts are:
  - calls to other contracts (a price oracle, a `transfer` of a token on a different
    contract);
  - `delegatecall` and proxies;
  - assembly, try/catch, structs and storage arrays;
  - all loops that are not the known patterns over one array parameter (for example,
    a loop with a `break` or a branch, or two arrays with the same index).

  The program runs without those paths. Thus the program does not model a call that
  would use one of them. `vault/vault_oracle.le` shows how to fill such a gap by hand.
- **The program does not model numbers out of range or gas.** Solidity 0.8 reverts
  when a number becomes too large or goes below zero. The arithmetic of the program
  has no such limits. LPS has no gas limit for a loop.
- **Events are approximated.** The call itself records an `emit`. There is no
  separate LPS event for it. `view` functions have no action of their own, because
  the fluents give their answers.
- **The words outside the reviewed models are mechanical**
  (`*a caller* calls credit with who *an account* with amount *an amount*`). The
  ledger marks such words for review. You can safely change the name of a template,
  because the `known as` name connects the template to the predicate.
- **A default changes how absence reads.** With `0 by default`,
  `it is not the case that the balance of bob is a thing` is never true, because bob
  has a balance of 0 at a minimum. An aggregate over a fluent that has a default
  counts or adds only the entries that are stored.
- **No scenario, no run.** A contract that you open has no calls. A scenario sentence
  needs its time (`from 1 to 2` or `at 1`). A sentence without a time is an error. It
  is not a call at time 0.
- **A `.zip` of sources** is read as a folder of sources. The translator translates
  the most derived concrete contract that is defined anywhere in it.
- **Named constants from the constructor are names, not addresses.**
  `the initial owner` is a constant of its own. The program must know that a caller
  is the owner. For this, the scenario must use the same name. Or you must replace
  the name in `initially` with the account that you use.

**Deploying a program**

- **These parts have no direct translation, and the export refuses them.** The
  export gives the line of each part, when it has one:
  - a reactive rule (`reactive_rule`): a contract does nothing by itself, it only
    answers calls;
  - an intensional fluent or a composite event;
  - planning: `lps_engine(planning, …)` or a goal to achieve;
  - an event that the environment observes, not an action that a person calls
    (`environment_event`). Model it as an action of the person who reports it;
  - a constraint over two actions that occur at the same time (`concurrency`);
  - a constraint about a state that is not immediately before or immediately after
    the call, or a constraint that reads the two states (write it as two
    constraints);
  - a causal law with conditions that read a state that is not the state before the
    call;
  - a rule without time, or a condition that calls Prolog, including lists, `member`,
    `sum_list` and `length` (thus the export refuses `airdrop.le`). The export writes
    *facts* without time as lookups;
  - a fraction: `/` or a number that is not a whole number (`non_integer`). Write
    `//`;
  - a read that must search a mapping, because nothing gives a value to the key
    (`enumeration`);
  - a fluent that the program lets hold two values for one key (`two_values`);
  - a position that holds both numbers and names (`mixed_types`);
  - a default that is not the zero of its type (`default_not_zero`).
- **The contract is a contract of the program, not of a standard.** The functions
  have the names of the actions (`transfer`, `transferFrom`). They take addresses
  first and values after. Thus `transfer(address,uint256)` of ERC-20 keeps its
  selector. The other parts do not follow the standard:
  - The getters have the names of the fluents (`balance`, not `balanceOf`).
  - The events have the names of the actions (`TransferFrom`).
  - A revert gives its reason as text (`revert("ERC20InsufficientBalance")`), not as
    a custom error.
  - A fluent without a zero default gets a `has…` flag next to it.

  Thus a wallet or a block explorer will not know that the contract is an ERC-20.
  Examine this before you give the contract to a wallet or a block explorer.
- **Underflow reverts in the contract, not in the program.** Underflow is when a
  number goes below zero. A number is `uint256` if no negative number occurs in its
  position. Some programs let a balance go below zero. Such a program continues in
  LPS, but the contract reverts that call. Write the check as an integrity
  constraint, as the twins do.
- **Accounts are constructor parameters.** A program cannot know addresses. Thus each
  account that the initial state names becomes an argument of the constructor. You
  must match the callers of the scenario to the test accounts of Remix.
- **The export does not include residue.** A `% RESIDUE` block of a Logical English
  document is a comment. Thus the block is not in the program and not in the
  contract. The window tells this in a note.
- **Only zero defaults.** The export refuses a fluent with a different default (for
  example `; 100 by default`). For such a default, the contract would need a flag for
  each key, to tell if a value was set for that key. But the purpose of the default
  was to remove that flag.
- **Not audited.** The export checks the contract against the scenario of the program
  on an EVM. Nobody checked the contract for reentrancy, for gas, for access control
  other than the constraints of the program, or for upgrades.

## See also

- In this documentation:
  - [Integrations overview](index.md)
  - [Drools and LPS](drools.md), [Daml and LPS](daml.md): the other imports of
    systems that are similar to contracts
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
- The documentation of Solidity:
  - [Solidity documentation](https://docs.soliditylang.org/en/latest/)
  - [Remix IDE documentation](https://remix-ide.readthedocs.io/en/latest/) and
    [Remix IDE](https://app.remix.live/)
  - [OpenZeppelin Contracts 5.x](https://docs.openzeppelin.com/contracts/5.x/)
  - [Circle's stablecoin-evm (FiatToken)](https://github.com/circlefin/stablecoin-evm)
