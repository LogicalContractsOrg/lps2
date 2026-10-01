# Logical English — LPS programs written in English

LPS programs written in Logical English. Each document starts with
`the target language is: lps.` and states its actions, events, fluents (facts
that hold for a while) and reactive rules as sentences. Most of them are
programs of the older LPS collection written again in English. Five have a
companion `.lps` file for what the English does not say, such as drawings.

## Start here
- [The wolf, the goat and the cabbage](goat.le): the puzzle, in English.
- [Bad light](badlight.le): two people who disagree about the lights, drawn
  in 2D from [its companion](badlight.lps).
- [A loan agreement](loan_agreement.le): real dates, and a legal text behind
  every rule.
- [Escrow](escrow.le): a buyer, a seller and an escrow agent, with their
  obligations.

## Try this
1. Open [the wolf, the goat and the cabbage](goat.le) and press **Run**. The
   **Timeline** shows the crossings, one cycle at a time.
2. Open the older version, [goat_declarative.pl](../start/goat_declarative.pl),
   in a second tab and run it. Switch between the tabs and compare the two
   programs.
3. Open [Bad light](badlight.le), press **Run**, then choose the **2D** pane and
   press ▶. The lamps go on and off as the two people switch them.
4. Right-click a lamp in the picture. The explanation says which event
   switched it, and which rule.
5. Open [the bank transfer](bank_transfer.le) and choose **View ▸ Legal
   view**. It opens a Logical English program without time, which says who
   may do what: *a payer may transfer an amount to a payee* if the payer's
   balance is at least that amount.

## Two runs that end in failure, on purpose

[prospective_goat.le](prospective_goat.le) and
[rock_paper_scissors_minimal.le](rock_paper_scissors_minimal.le) end with
*failure after N cycles*. That is the expected result, and the same one
the LPS1 programs they come from give: each shows a constraint refusing
something, and says so in its first lines.

## More
- [Logical English for LPS](/docs/user/reference/le-for-lps): the language,
  with a table of these programs and what each one shows.
- [Using the editor: Logical English](/docs/user/guide/ide#logical-english).
