# Solidity twins — what each file is, and how to run it

Twins of Solidity smart contracts (programs that run on a blockchain):
OpenZeppelin's reference tokens, Circle's FiatToken (the contract behind the
USDC coin), a vault, and batch calls. Each twin has one law for each way a
function can succeed, and one constraint for each way it can fail. Its scenario
is a list of calls, and the calls the blockchain refuses, the twin refuses too.

## Start here
- [A pausable token](pausable/pausable.le): the owner may pause the token;
  nobody else may.
- [An ERC-20 token](erc20/erc20.le): the standard token, with balances and
  allowances.
- [The USDC replay](replay/usdc_window.le): the FiatToken twin run on real
  USDC transactions. [The results](replay/usdc_window.results.md): all 215
  final values agree with the blockchain.
- [The vault](vault/vault.le): a loan that needs a price from outside. Its
  borrow side is a residue (the translator could not read the price feed), so
  three of its templates are declared and never used: the editor says so.

## Try this
1. Open [the pausable token](pausable/pausable.le) and press **Run**.
2. On the **Timeline**, Bob's call to pause is crossed out in red: he is not the
   owner. So is Alice's second pause, because the token is already paused.
3. Right-click a crossed-out call. The answer is *refused_by_constraint*, and it
   names the constraint and the values it held on.
4. Choose **View ▸ Legal view**. Its questions ask, call by call, whether the
   call may be made, and what it changes.
5. Choose **View ▸ The original this was converted from** to read the contract.

## More
- [Details](DETAILS.md): every folder, what is checked, and how the related
  files use one another.
- [Solidity and LPS](/docs/user/integrations/solidity): translating a contract,
  and deploying a program as Solidity.
- [Solidity](https://docs.soliditylang.org/) and
  [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/).

## Disclaimer

A twin is written by a translator, and it is provided **"as is", without
warranty of any kind**, express or implied, including any warranty that it is
accurate, complete or fit for a particular purpose. A translation may be
wrong: check a twin against its source before relying on it. A twin is not
legal, tax, insurance, financial or other professional advice. Its authors
accept no liability for any loss or damage arising from its use. Every twin
repeats this notice in its opening comment.
