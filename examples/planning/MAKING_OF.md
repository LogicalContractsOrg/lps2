# How the examples in this folder were made

These are planning problems written in PDDL (the Planning Domain Definition
Language). Some were copied unchanged from a public collection of the
International Planning Competition, and people wrote those. Others were
restated or written new by an AI agent: Claude, an AI model made by
Anthropic, working in the Claude Code tool at Miguel Calejo's request. LPS2
turns each problem into an LPS program when it opens it, so no LPS program is
stored here.

| File | Made by | How |
|---|---|---|
| `blocks-domain.pddl`, `blocks-p1.pddl` to `blocks-p3.pddl`, `gripper-domain.pddl`, `gripper-p1.pddl`, `gripper-p2.pddl`, `logistics-domain.pddl`, `logistics-p1.pddl` | People: the authors of the International Planning Competition problems | Copied from the collection at https://github.com/potassco/pddl-instances by the AI agent, 2026-08-04. |
| `hanoi-domain.pddl`, `elevator-domain.pddl`, `rover-domain.pddl` | AI agent (Claude, in Claude Code), 2026-08-04 | Restated from well-known competition domains, as each file's opening comment says: the towers of Hanoi of planning.domains, the Miconic elevator (Koehler and Schuster, 2000) and the Rovers domain (Long and Fox, 2002). The elevator and the rover were reduced to their simplest form. |
| `hanoi-p1.pddl`, `hanoi-p2.pddl`, `elevator-p1.pddl`, `elevator-p2.pddl`, `rover-p1.pddl`, `rover-p2.pddl` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new for those domains. |
| `lights-domain.pddl`, `lights-p1.pddl`, `lights-p2.pddl` | Not recorded | Written new for LPS2 ("Written for LPS2", says the domain's opening comment), to try the parts of PDDL that go beyond the simplest form. The commit that added them does not say whether a person or the AI agent wrote them. |
| `README.md` | Not recorded | Added in an unmarked commit on 2026-09-16. |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`.

- commit `f0b1c60` (2026-08-04) "M12a and M12d: PDDL and Drools as front ends": adds blocks, gripper and logistics; its message says they are "IPC instances from potassco/pddl-instances"; agent commit.
- commit `ae1e982` (2026-08-04) "Nine more PDDL problems, three more rule bases…": adds hanoi, elevator and rover; agent commit.
- commit `7464f01` (2026-09-16) "doc clean up, uncovered bugs fixed": adds lights; no agent line.
- The reader that turns PDDL into LPS: `src/syntax/lps_pddl.pl`; its check, `tools/pddl_test.pl`, verifies each plan against the PDDL itself.
