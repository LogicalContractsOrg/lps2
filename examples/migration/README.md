# Migration twins — other systems' programs in Logical English for LPS

Programs of other systems, translated into Logical English for LPS by
translators (programs that rewrite another system's program). Each translation
is called a *twin*. Each twin has one folder, with its migration ledger (what
was translated, and how) and the original files under `sources/`. The twins
that do not need time (Blawx, LegalRuleML, Miniscript, s(CASP), OIPA) are in
[Logical English 2's examples](https://github.com/LogicalContractsOrg/LogicalEnglish2/tree/main/examples/migration).

## Start here
- [Daml](daml/): contracts of the Daml SDK's own templates.
- [Drools](drools/): the Drools examples, as events in a world.
- [L4](l4/): contracts of the L4 language — obligations with deadlines, and
  what follows when they are met or missed.
- [Solidity](solidity/): OpenZeppelin and Circle token contracts, and a
  replay of real USDC transactions.

## Try this
1. Open [the pausable token](solidity/pausable/pausable.le) and press **Run**.
   On the **Timeline**, two calls are crossed out in red: the blockchain
   refused them too.
2. Right-click a crossed-out call. The answer is *refused_by_constraint*, and it
   names the rule that refused it.
3. Choose **View ▸ Legal view**: who may pause the token, and when.
4. Choose **View ▸ The original this was converted from** to read the Solidity
   contract beside the twin.

## More
- [Other systems](/docs/user/integrations/index): how LPS2 reads and writes
  other systems' programs.

## Disclaimer

A twin is written by a translator, and it is provided **"as is", without
warranty of any kind**, express or implied, including any warranty that it is
accurate, complete or fit for a particular purpose. A translation may be
wrong: check a twin against its source before relying on it. A twin is not
legal, tax, insurance, financial or other professional advice. Its authors
accept no liability for any loss or damage arising from its use. Every twin
repeats this notice in its opening comment; the translators write it there
themselves (`twin_disclaimer` in Logical English 2's `i18n/writer_words.csv`).
