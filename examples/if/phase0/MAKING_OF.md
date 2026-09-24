# How the examples in this folder were made

An AI agent wrote every file in this folder: Claude, an AI model made by
Anthropic, working in the Claude Code tool at Miguel Calejo's request, on
2026-09-04. These are the first trials of interactive fiction on LPS: three
Inform 7 programs, written by the Inform authors, that the agent wrote again
by reading them, once in LPS and once in Logical English. No converter program
was used.

| File | Made by | How |
|---|---|---|
| `lps/iqtest.lps`, `lps/iqtest_c.lps`, `lps/iqtest_obligation.lps`, `lps/mre.lps`, `lps/scene.lps` | AI agent (Claude, in Claude Code), 2026-09-04 | Written from Inform's *Recipe Book* examples IQ Test and MRE, and from its test case C9SceneEndSequence (see `../inform/`), with each program's test script as observations. The `iqtest` variants try two other ways of saying the same thing. |
| `le/iqtest.le`, `le/iqtest.lps`, `le/mre.le`, `le/mre.lps`, `le/scene.le` | AI agent (Claude, in Claude Code), 2026-09-04 | The same three, in Logical English for LPS. |
| `expected/*.events` | AI agent (Claude, in Claude Code), 2026-09-04 | The events each program must produce, read from the transcripts that ship with the Inform programs. |
| `check.sh`, `README.md` | AI agent (Claude, in Claude Code), 2026-09-04 | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `dd37027` (2026-09-04) "inform-phase0": adds every file here; agent commit. The plan: `docs/project/plans/InformPlan.md` §7 and §10.
