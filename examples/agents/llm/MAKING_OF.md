# How the examples in this folder were made

An AI agent wrote every file in this folder. The agent was Claude, an AI model
made by Anthropic, working in the Claude Code tool at Miguel Calejo's request,
while LPS2 itself was being built. The programs were written new, to show a
language model that may propose an action but not approve it.

| File | Made by | How |
|---|---|---|
| `approval.lps`, `demo.mjs` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new: the LPS program and the Node.js script that drives it. |
| `approval_ide.lps` | AI agent (Claude, in Claude Code), 2026-08-04 | The same demonstration, run inside the LPS2 editor. |
| `README.md` | AI agent (Claude, in Claude Code), 2026-09-16 | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `6641236` (2026-08-04) "Part II and Part III: an agent that cannot authorise itself, and one that plays Minecraft": adds `approval.lps` and `demo.mjs`; agent commit.
- commit `ae1e982` (2026-08-04) "Nine more PDDL problems, three more rule bases…": adds `approval_ide.lps`; agent commit.
- commit `1d0bdc1` (2026-09-16) "Examples cleanup, step 4": moves the files here and adds `README.md`; agent commit.
