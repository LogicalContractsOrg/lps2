# Finance — the life of a trade after it is made

Two programs about what happens to a derivatives trade after it is made,
written in Logical English for LPS (LPS: Logic Production Systems, a language
for programs that react to events as time passes). A *derivative* is a
contract whose payments depend on something else, such as an interest rate.
Both programs follow public material, named in each folder.

## Start here
- [The interest rate reset](interest_rate_reset/interest_rate_reset.le): the
  eight steps by which the Common Domain Model (CDM) fixes the floating rate of
  a swap's next payment.
- [Checking the record of a trade's life](trade_lifecycle_record/trade_lifecycle_record.le):
  57 trades and their terminations and novations, checked against the rules
  of the workflow that produced them.

## Try this
1. Open [the interest rate reset](interest_rate_reset/interest_rate_reset.le),
   choose the scenario *compounded* and press **Run**. The **Timeline** shows
   the eight steps, one per cycle, and the rate they arrive at: 0.0550084.
2. Choose the scenario *late rate* and run it again. Step 7 waits until the
   missing rate is published, then runs.
3. Open [the record](trade_lifecycle_record/trade_lifecycle_record.le) and run
   the scenario *the demo record*. No breach is recorded.
4. Run the scenario *applied too early*. Two breaches appear at the cycle in
   which the ledger applied the termination. Right-click one: the explanation
   names the rule and the facts it rests on.

## More
- Each folder's README says where its material comes from, and how far the
  program follows it: [interest_rate_reset/](interest_rate_reset/) and
  [trade_lifecycle_record/](trade_lifecycle_record/). The original files are
  in each folder's `sources/`.
- [Logical English for LPS](/docs/user/reference/le-for-lps): the language.

## Disclaimer

These programs are examples, provided **"as is", without warranty of any
kind**. They are not financial, legal or other professional advice, and they
are not a replacement for the systems or documents they follow.
