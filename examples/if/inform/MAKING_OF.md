# How the examples in this folder were made

People wrote the eleven Inform 7 programs (`.ni` files) in this folder: the
authors of Inform, whose copyright is Graham Nelson's (2006–2022). An AI agent
copied them from the Inform repository and removed their explanatory prose.
The agent was Claude, an AI model made by Anthropic, working in the Claude
Code tool at Miguel Calejo's request. LPS2 turns each program into a Logical
English story when it opens it, so no story is stored here.

| File | Made by | How |
|---|---|---|
| `BostonCream.ni`, `C9SceneEndSequence.ni`, `GoingSouthIn.ni`, `IQTest.ni`, `ImplicitConnections.ni`, `MRE.ni`, `NPCGoingTwistily.ni`, `NegatedRP.ni`, `NothingAsTerm.ni`, `Regarding.ni`, `TakingInventory.ni` | People: the Inform authors | Copied by the AI agent on 2026-09-04 from https://github.com/ganelson/inform (Artistic License 2.0): test cases of `inform7/Tests/Test Cases/` and examples of *Writing with Inform* and *The Recipe Book*. The agent removed the examples' explanatory prose. |
| `NOTICE.md` | AI agent (Claude, in Claude Code), 2026-09-04 | Where the programs come from, and their licence. |
| `README.md` | AI agent (Claude, in Claude Code), 2026-09-16 | |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `141e4a4` (2026-09-04) "inform-phase4": adds the `.ni` files and `NOTICE.md`; agent commit.
- The reader that turns an Inform program into a story: `src/syntax/lps_inform.pl`; its check, `tools/inform_test.pl`.
