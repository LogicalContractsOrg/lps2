# How the examples in this folder were made

An AI agent wrote the interactive-fiction library and the stories in this
folder: Claude, an AI model made by Anthropic, working in the Claude Code tool
at Miguel Calejo's request, in September 2026. Most stories are Inform 7
programs, written by the Inform authors, that the agent wrote again in
Logical English for LPS, by reading them; no converter program wrote them. The
Alice story quotes Lewis Carroll's *Alice's Adventures in Wonderland* (1865).
The Inform programs themselves are in `inform/`, which has its own
`MAKING_OF.md`; the earlier trials are in `phase0/`, which has one too.

| File | Made by | How |
|---|---|---|
| `world.le` | AI agent (Claude, in Claude Code), 2026-09-04 | The library: rooms, things, doors, people and a dozen actions, modelled on a small part of Inform 7's Standard Rules (by Graham Nelson). |
| `implicit_connections.le`, `nothing_as_term.le`, `negated_rp.le`, `npc_going.le`, `regarding.le`, `scene.le` | AI agent (Claude, in Claude Code), 2026-09-04 | Each written from the Inform 7 test case its opening comment names (see `inform/`). |
| `iqtest.le`, `boston_cream.le`, `mre.le` | AI agent (Claude, in Claude Code), 2026-09-04 | Each written from the example of Inform's *Recipe Book* its opening comment names. |
| `doors.le` | AI agent (Claude, in Claude Code), 2026-09-04 | Written from the door example of *Writing with Inform*, §3.12. |
| `alice.le`, `alice.lps`, `alice_garden.le` | AI agent (Claude, in Claude Code), 2026-09-04 | Chapters I and II of Carroll's book as a story. The descriptions in `alice.lps` are Carroll's words, with a few joins by the agent. |
| `alice_pure_lps.le`, `alice_pure_lps.lps`, `turns.le` | Not recorded | Added on 2026-09-08 in a commit that does not say whether a person or the AI agent wrote them: `alice.le` without the turn, and the turn counter taken out of the library into a file of its own. |
| `iqtest.lps` | AI agent (Claude, in Claude Code), 2026-09-04 | Drawing settings for the IQ Test story. |
| `expected/*.pl` | AI agent (Claude, in Claude Code), 2026-09-04 (`alice_pure_lps.pl`: not recorded, 2026-09-08) | What each story must do: the events and final state, which the agent read from the transcript that Inform's authors ship with each test case. |
| `README.md`, `DETAILS.md` | AI agent (Claude, in Claude Code), 2026-09-04, rewritten later | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`. The plan
the agent followed is `docs/project/plans/InformPlan.md`.

- commit `e7e4ee9` (2026-09-04) "inform-phase1": adds `world.le`, the stories from test cases and the Recipe Book, `doors.le`, `expected/` and the README; agent commit.
- commit `a1512c7` (2026-09-04) "inform-phase3": adds the Alice stories; agent commit.
- commit `b01c512` (2026-09-04) "LPSForInformUsers: the stories drawn in 2D and 3D…": adds `iqtest.lps`; agent commit.
- commit `22108df` (2026-09-08) "use constants starting with 'the'; navigate to included resource; Alice without turns": adds `alice_pure_lps.*` and `turns.le`; no agent line.
- The check: `tools/if_test.pl` plays each story's script and compares it with `expected/`.
