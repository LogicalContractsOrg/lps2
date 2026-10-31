# Epilog twins — the games and programs of the Epilog site, in Logical English for LPS

Epilog is the logic programming language of Stanford's Epilog site
(http://epilog.stanford.edu). The Epilog translator rewrote the programs of
that site in Logical English. The translator is a program: nothing in a twin
was written by hand. Such a rewrite is a **twin**.

This folder holds the twins that need LPS to run: 71 games of the Games page,
and 2 programs with operations of the Examples page (`triples` and
`grapheditor`). In each of them, the moves are actions, the effect of each move
is a causal law, and the legal moves, the goal and the end of the game are
fluents. The scenario `play` is a play that EpilogJS, the Epilog interpreter of
Stanford, made. The last comment of the twin gives the state at the end of that
play in EpilogJS. LPS ends the play in the same state.

The rulesets of the Examples page (no actions, so plain Logical English) are
among the examples of Logical English, in its `examples/migration/epilog/`
folder. **The README of that folder is the full list**: every program of the
Epilog site, which programs need LPS, which programs are different from
EpilogJS and why, and how to check a new Epilog program against EpilogJS:
[Logical English 2's Epilog examples](https://github.com/LogicalContractsOrg/LogicalEnglish2/tree/main/examples/migration/epilog).

## Try this
1. Open [tic-tac-toe](tictactoe/tictactoe.le) and press **Run**. On the
   timeline, the board fills in move by move.
2. Compare the last state on the timeline with the comment at the end of the
   program: it is the state at the end of the same play in EpilogJS.
3. Choose **View ▸ The original this was converted from** to read the Epilog
   game library, and the record of the play by EpilogJS.
4. Open [triples](triples/triples.le): one table of students becomes three
   relations, and then one table again.

Each twin has its migration ledger (`<name>.ledger.md`): what each part of the
Epilog program became, what was approximated, and what was kept as residue (a
sentence that the translator could not translate, kept in a comment).

**Disclaimer.** A twin is written by a translator, and it is provided "as is",
without warranty of any kind, express or implied, including any warranty that
it is accurate, complete or fit for a particular purpose. A translation may be
wrong: check a twin against its source before relying on it. A twin is not
legal, tax, insurance, financial or other professional advice. Its authors
accept no liability for any loss or damage arising from its use.
