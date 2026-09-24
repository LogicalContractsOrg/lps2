# How the examples in this folder were made

These programs were adapted from Robert Kowalski's book *Computational Logic
and Human Thinking* (Cambridge University Press, 2011) by an AI agent: Claude,
an AI model made by Anthropic, working in the Claude Code tool at Miguel
Calejo's request. The agent wrote each `.lps` program from the book's example.
A converter program, not the agent, then wrote each `.le` file from its
`.lps` file.

| File | Made by | How |
|---|---|---|
| `citizenship_time.lps`, `event_calculus.lps`, `fox_crow.lps`, `hunger.lps`, `louse.lps`, `mars_explorer.lps`, `penalty.lps`, `plan_generation.lps`, `trolley.lps`, `umbrella.lps`, `underground.lps`, `violations.lps` | AI agent (Claude, in Claude Code), 2026-08-04 | Adapted from the book's examples; each file's opening comment names its chapter and section. The agent chose them from the survey of the book's examples in LogicalEnglish2 (`docs/project/research/rk-book/bookExamples.md`). |
| the twelve `.le` files of the same names | Converter program, 2026-09-23 | Written by the LPS-to-Logical-English converter from the `.lps` file beside it. The first line of each, `% lps-converted-from: <name>.lps`, says so. A test checks that the two versions run alike. |
| `README.md`, `DETAILS.md` | AI agent (Claude, in Claude Code), 2026-08-04, rewritten on later dates | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `f1491fe` (2026-08-04) "M19: Kowalski's book examples, in the language they were waiting for": adds the `.lps` programs, `README.md` and `DETAILS.md`; agent commit.
- commit `493fca6` (2026-09-23) "LPS syntax to LE converter; conversion of Bob's book LPS examples": adds the converter and the `.le` files. The commit has no agent line, but the converter was built by the AI agent on 2026-09-22 (Claude Code session notes).
- converter: `src/syntax/lps_to_le.pl` in this repository, which calls `le_lps_from_internal/4` in LogicalEnglish2's `le_lps_write.pl`. To write one again: `LPS_LE2_LIB=<LogicalEnglish2 folder> ./lps le examples/collections/kowalski-book/<name>.lps --out <name>.le`. The check: `tools/lps_to_le_test.pl`.
