# Daml twins

Twins of the Daml SDK's own templates. Daml is a language for contracts
between parties on a shared ledger (a record every party agrees on). Each
project has one folder: its twin in Logical English for LPS, one more program
for each of its further Daml scripts, a ledger that says what was translated
and how, and the Daml sources, unchanged, under `sources/`. The twins are
generated: change the translator, not the files.

## Start here
- [A simple IOU](simple_iou/simple_iou.le): an IOU (a promise to pay) passed
  from owner to owner.
- [Quickstart](quickstart/quickstart.le): the Daml quickstart, with IOUs and
  a trade.
- [Tokens](token/token.le): a token, with three test scripts beside it.

## Try this
1. Open [the simple IOU](simple_iou/simple_iou.le) and press **Run**. On the
   **Timeline**, Dora creates the IOU, then Alice and Bob each pass it on.
2. Read the comment above the scenario: the contracts Daml itself ends with.
   Compare it with the last cycle of the run: Charlie owns the IOU.
3. Choose **View ▸ Legal view**: who may create or transfer an IOU, as a
   Logical English program without time.
4. Choose **View ▸ The original this was converted from** to read the Daml
   source beside the twin.

## More
- [Daml and LPS](/docs/user/integrations/daml): the mapping, the checks, and
  the four scripts that end differently.
- [Daml documentation](https://docs.digitalasset.com/), by Digital Asset.

## Disclaimer

A twin is written by a translator, and it is provided **"as is", without
warranty of any kind**, express or implied, including any warranty that it is
accurate, complete or fit for a particular purpose. A translation may be
wrong: check a twin against its source before relying on it. A twin is not
legal, tax, insurance, financial or other professional advice. Its authors
accept no liability for any loss or damage arising from its use. Every twin
repeats this notice in its opening comment.
