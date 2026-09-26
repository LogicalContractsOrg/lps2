# A third pass: comments on Introducing LPS2, 2026-09

*Kind: user review · Status: addressed (2026-09-26)*

Robert Kowalski read `docs/user/overview/introducing-lps2.md` and left fifteen
comments in a copy of it. His overall judgement, on the audience line:

> if most readers are as non-technical as I am, then only about 60 % of this
> will be intelligible to them. Moreover, it will be hard work, intimidating and
> potentially offputting.

And on Part six:

> I don't understand most of the rest of this document. Maybe the intended
> audience should be changed from 'newcomer' to ?????

## What was done overall

The document was split in two. **Introducing LPS2** is now the tour for
newcomers, with or without a background in programming: what LPS2 does, shown
from the running system, with no file names, line counts, internal predicates or
build machinery unless the reader has to type them. **LPS2 in detail**
(`docs/user/overview/introducing-lps2-technical.md`) is a new companion for
programmers and readers who know LPS1. It holds the detail the tour dropped. The
tour points to the companion section by section wherever there is more behind a
section.

The tour's sections were renumbered. Links from the other documents were
updated.

## Comment by comment

| # | Where | Comment, in short | What was done |
|---|---|---|---|
| c0 | audience | only about 60 % intelligible to a non-technical reader | the split above; the audience is now "newcomers, with or without a background in programming" |
| c1 | bank transfer | "Wrong. The antecedent fixes the time T2 and the reply transfer happens from T2. T3 = T2+1." | corrected: the reply starts at `T2`, and ends at `T3 = T2 + 1` because an action takes one cycle; the record shows exactly that |
| c2 | when rules disagree | too much detail; some of it inaccurate: "not preconditions of the next state, but preconditions of actions" | the tour keeps one plain paragraph; the two examples moved to companion §1, rewritten to say *the preconditions of the actions chosen* |
| c3 | the editor | what purpose does the port number serve? | removed from the tour; companion §7 |
| c4 | the editor | esbuild and Node.js: neither understood nor needed | removed from the tour; companion §7 and §16 |
| c5 | the editor | the history of the two control panels is not relevant | removed |
| c6 | the editor | "there are two editors" is unintelligible | removed from the tour; companion §7 |
| c7 | the assistant | translate into what? can the user choose models? does the user need their own keys? why all the detail about the animation? | rewritten: what an API key is, the two ways to have one (the server's, or your own), where models are chosen, what the assistant can do in plain words; the design of the animation moved to companion §8 |
| c8 | command line | "mercifully short" | kept short; the web interface moved to companion §9 |
| c9 | Logical English | too much detail, mostly not understandable | rewritten around the English example and what each part of it is; the machinery moved to companion §11 |
| c10 | Logical English | would like to understand and try *English to Logical English* | a step-by-step "Trying it" list, and a plain description of **Edit ▸ Say it in English…**, with what it needs |
| c11 | interactive fiction | "the story's own templates are the grammar" is unclear | rewritten with an example template, a typed command that fits it, and what a new template adds |
| c12 | Minecraft | unintelligible; assumes the reader knows Minecraft; what are the supervisor and controller? | rewritten: what Minecraft is, what a bot is, the two layers explained with the comparison of a driver and their reflexes; setup moved to companion §14 |
| c13 | industrial control | what are the supervisor and controller supposed to represent? | rewritten: the existing controllers are the controller; an LPS program alongside them is the supervisor; the tool names moved to companion §15 |
| c14 | Part six | mostly not understood | Part six is now *where things stand*: what is missing, in plain terms, and where to start; deploying and how the system was built moved to companion §16 and §17 |

Two statements in the old Part six were found to be out of date and were
dropped rather than moved: the direction from the internal form back to LPS1's
written form now exists (`./lps dump --syntax legacy`), and so does the Model
Context Protocol interface ([LPS over MCP](../../user/api/mcp.md)).
