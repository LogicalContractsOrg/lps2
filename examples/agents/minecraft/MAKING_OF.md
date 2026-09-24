# How the examples in this folder were made

An AI agent wrote the programs in this folder: Claude, an AI model made by
Anthropic, working in the Claude Code tool at Miguel Calejo's request. They
were written new, while LPS2 itself was being built. Three small helper
scripts were added the next day in commits that do not say who wrote them.
The Minecraft libraries the scripts use (in `node_modules/`, not stored in the
repository) are other people's published software.

| File | Made by | How |
|---|---|---|
| `safety.lps`, `hungry.lps`, `craft.lps` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new: the bot's goals, as LPS programs. |
| `bot.mjs`, `world.mjs`, `demo.mjs`, `package.json`, `package-lock.json`, `.gitignore`, `README.md` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new: the scripts that start a local Minecraft world and connect the bot to an LPS session. The README was rewritten later. |
| `doctor.mjs`, `playerdata.mjs`, `reset.mjs` | Not recorded | Helper scripts added on 2026-08-05. The commits that added them do not say whether a person or the AI agent wrote them. |
| `DETAILS.md` | AI agent (Claude, in Claude Code), 2026-08-04; moved on 2026-09-23 | Mostly the text of the README the agent wrote, moved to a file of its own on 2026-09-23 in a commit that does not say who moved it. |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `6641236` (2026-08-04) "Part II and Part III: an agent that cannot authorise itself, and one that plays Minecraft": adds the programs and scripts; agent commit.
- commit `28fc45d` (2026-08-05) "fix fly.io deployment, minecraft example": adds `doctor.mjs`; no agent line.
- commit `f016578` (2026-08-05) "use safe_call, do not require LPS_TOKEN": adds `playerdata.mjs` and `reset.mjs`; no agent line.
- commit `25a8dfa` (2026-09-23) "examples READMEs": adds `DETAILS.md`; no agent line.
