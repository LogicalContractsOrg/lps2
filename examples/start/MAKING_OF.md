# How the examples in this folder were made

An AI agent wrote every program in this folder. The agent was Claude, an AI
model made by Anthropic, working in the Claude Code tool at Miguel Calejo's
request, while LPS2 itself was being built (July and August 2026). One program,
the wolf, goat and cabbage, restates a program of LPS1, the earlier LPS system,
whose examples were written by people.

| File | Made by | How |
|---|---|---|
| `goat_declarative.pl` and `goat_declarative.pl.lpst` | AI agent (Claude, in Claude Code), 2026-07-25 | Adapted from LPS1's `legacy_lps1/examples/forTesting/prospectiveGoat.pl` (written by the LPS1 authors): most lines are copied, and the agent replaced the step-by-step solution with rules that say when a crossing is allowed. The `.lpst` file is the expected run, which the agent recorded. |
| `blocks.lps`, `blocks3d.lps`, `lights.lps`, `thermostat.lps` | AI agent (Claude, in Claude Code), 2026-08-03 and 2026-08-04 | Written new, to show one feature each: planning, a drawing in three dimensions, a program that reacts to clicks, a program that runs until it is stopped. |
| `README.md` | AI agent (Claude, in Claude Code), 2026-09-16 | Written when the examples were regrouped by purpose. |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `5813196` (2026-07-25) "M6 — declarative planning mode": adds `goat_declarative.pl` and its `.lpst`; agent commit.
- commit `9e2b5aa` (2026-08-03) "M6 stage 2: a relaxed-plan heuristic…": adds `blocks.lps`; agent commit.
- commit `a603e1d` (2026-08-04) "examples/blocks3d.lps…": adds `blocks3d.lps`; agent commit.
- commit `41cbc41` (2026-08-04) "LPS2, not LPS(2)…; and an animation you can click on": adds `lights.lps`; agent commit.
- commit `9a0d09b` (2026-08-04) "M16 and M18: the assistant, and sessions that do not end": adds `thermostat.lps`; agent commit.
- commit `1d0bdc1` (2026-09-16) "Examples cleanup, step 4": moves the files here and adds `README.md`; agent commit.
