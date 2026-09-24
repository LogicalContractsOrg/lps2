# How the examples in this folder were made

An AI agent wrote the Logical English programs in this folder. The agent was
Claude, an AI model made by Anthropic, working in the Claude Code tool at
Miguel Calejo's request. Most of the programs are older LPS programs written
again in Logical English: people wrote those originals, for LPS1, the earlier
LPS system (most of them for the CLOUT workshop). The agent wrote each
translation itself, reading the original; no converter program was used.

| File | Made by | How |
|---|---|---|
| `badlight.le`, `bank_transfer.le`, `delivery_delay.le`, `dining_philosophers.le`, `escrow.le`, `fire_simple.le`, `goat.le`, `life.le`, `loan_agreement.le`, `map_colouring.le`, `prospective_goat.le`, `rock_paper_scissors_base.le`, `rock_paper_scissors_ethereum.le`, `rock_paper_scissors_minimal.le` | AI agent (Claude, in Claude Code), 2026-07-25 | Translated from the LPS1 program named on each file's `Source:` line (under `legacy_lps1/examples/`, written by the LPS1 authors). The three rock-paper-scissors programs rework the Logical English 1 versions of that game. `loan_agreement.le` follows Flood and Goodenough, "Contract as automaton". |
| `goat_declarative.le` | AI agent (Claude, in Claude Code), 2026-07-25 | Translated from `../start/goat_declarative.pl`, which the agent also wrote. |
| `badlight.lps`, `delivery_delay.lps`, `life.lps`, `loan_agreement.lps`, `rock_paper_scissors_ethereum.lps` | AI agent (Claude, in Claude Code), 2026-07-25 | Companion files: the parts of each program that the English leaves out, such as drawings and calendar settings, mostly taken from the LPS1 original. |
| `token.le`, `fee_token.le` | AI agent (Claude, in Claude Code), 2026-09-14 | Written new, to try the shorter Logical English for LPS (named constants, default values, one base extending another). |
| `functions.le` | Not recorded | Written new on 2026-09-18 to show `the functions are:`. The commit that added it does not say whether a person or the AI agent wrote it; the same feature was built by the AI agent that day. |
| `README.md` | AI agent (Claude, in Claude Code), 2026-09-16 | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`. These
programs were first written in the LogicalEnglish2 repository, in its
`examples/lps/` folder, and moved here on 2026-09-16.

- LogicalEnglish2 commit `bdfc02c` (2026-07-25) "M8b: Logical English for LPS, on paper": adds the translations and their companions; author "Miguel Calejo (via Claude)".
- LogicalEnglish2 commit `0005198` (2026-09-14) "LE for LPS, less verbose…": adds `token.le` and `fee_token.le`; agent commit.
- commit `ab291d2` (2026-09-16) "Examples cleanup, step 5: Logical English for LPS examples are LPS2's own": moves them here; agent commit.
- commit `032ff1e` (2026-09-18) "constants cleanup, functional notation, Sentry bug fixes": adds `functions.le`; no agent line.
