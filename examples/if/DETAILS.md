# Interactive fiction on LPS: the details

Phase 1 of `docs/project/plans/InformPlan.md`. `world.le` is the library: a sliver of Inform's
Standard Rules as Logical English for LPS — rooms, things, containers,
supporters, doors, people, the map, a dozen actions with their preconditions
and effects, scenes, and one goal-seeking plan. `turns.le` is the clock, Inform's
turn as a layer over LPS cycles: `the turn begins`, `the turn ends`, `the turn
is N`. Every other `.le` here is a story that includes the library, and all but
one the clock:

```
the knowledge base my story includes these resources: world, turns.
```

and adds its rooms, things, initial state, and its own rules and commands.

```sh
LPS_LE2_LIB=/LogicalEnglish2 ./lps play examples/if/doors.le      # play it: e / open door / e / why
LPS_LE2_LIB=/LogicalEnglish2 ./lps run  examples/if/doors.le      # replay its Test-me script
LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/if_test.pl')"   -g "if_test:main"   -t halt
LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/play_test.pl')" -g "play_test:main" -t halt
```

In the IDE, open a story and press **Play** in the top bar. **Fork** starts a second
game from where you are — Alice at the bottle — and **Diff** says what happened in
one and not the other; on the terminal, `fork`, `switch ID` and `diff`.

## The stories

Each plays an Inform program's `Test me with` script and is checked, by
`tools/if_test.pl`, against the event sequence and final state read by hand
from Inform's ideal transcript (`expected/`).

| story | Inform source | what it exercises |
|---|---|---|
| `implicit_connections` | test case ImplicitConnections | the map, both ways from one stated connection |
| `nothing_as_term` | test case NothingAsTerm | reaching into a carried container; put into |
| `negated_rp` | test case NegatedRP | openable or not; a refusal |
| `npc_going` | test case NPCGoingTwistily | a character moving every turn |
| `regarding` | test case Regarding | two actions in one turn (`drop all`) |
| `doors` | *Writing with Inform* §3.12, hand-written | a door: closed refuses passage, open allows it |
| `boston_cream` | Recipe Book, Boston Cream (first seven turns) | enter, close and lock from inside; a hungry character who fetches and eats |
| `scene` | test case C9SceneEndSequence | scenes as fluents |
| `iqtest` | Recipe Book, IQ Test | a character asked to fetch through a locked case; a story-added command |
| `mre` | Recipe Book, MRE | scheduled events that name a turn; every-turn rules; the end of the story |
| `alice` | *Alice's Adventures in Wonderland*, chapters I–II | the showcase: size, a pool that comes into being, a character on a route, two chapters as scenes; the book's path |
| `alice_garden` | the same, the other path | includes `alice` and adds its own script: key first, then the bottle, then the garden |
| `alice_pure_lps` | the same, without the clock | does not include `turns`: the Rabbit runs on when Alice reaches its room, the tears and the fall follow from the state, and the script is commands at cycles — the same states in the same order, no turn anywhere. Its companion is `alice.lps` (a symbolic link) |

## How a story is driven

A command is a burst of cycles. The player (`src/edges/lps_play.pl`) injects the
command, steps until a cycle in which nothing happens, and gives the prompt back.
For a story that includes `turns.le` it also marks the burst: `the turn begins` goes
in with the command, and `the turn ends` — on which every-turn rules and scheduled
events key — once the cycle has settled, followed by a second run to quiescence.
The `Test me with` scripts of those stories do the same with four cycles per turn;
`alice_pure_lps.le`'s script is commands at cycles with room between them. A play
drops the script and the `maximum time`.

What you type is matched against the story's own command templates: `the command is
to put *a thing* into *a container*` is the pattern `put <thing> into <container>`,
and a story that declares a new command has extended the parser. Inform's short forms
(`x`, `i`, `z`, `get`, `n`) are understood. What the templates do not take can go to
the assistant's translator, if a key is set. The words of the transcript are the
action templates', or a `narrate/2` clause in the story's companion; a refusal is the
engine's explanation of why the action did not happen.

A command is never an obligation: `the command is to take X` becomes `player
tries to take X`, a composite event whose first clause is the action and whose
second is `player cannot take X`. When the action's precondition refuses it, the
engine backtracks into the refusal, and

```sh
./lps explain examples/if/doors.le --ask "why_not(happened(go(player, east)), 3)"
```

names the sentence and the fluent that refused it. That is the refusal message.

## The drawings

`alice.lps` and `iqtest.lps` end with `display/2` and `display3d/2` clauses that a
language model wrote (their headers say which, and when) for the IDE's 2D and 3D
panes. They are one answer among many — regenerating gives another — and they change
nothing about what happens: the gates do not read them. `docs/user/tutorials/inform-users.md`
§6a shows them.

## Conventions worth knowing

- One condition per line, `and` first. A conjunction written on one line is
  read by Logical English as a single sentence.
- A constant is a word (`hall`, `bottle`) or a phrase beginning with `the` (`the
  oak door`, `the silver key`): Logical English reads `the oak door` as a constant
  where no `an oak door` introduced it earlier in the sentence. The player finds
  it by any of its words (`door`), and the narrator prints it as written.
- A story's own action must not be named like a SWI-Prolog built-in — the
  library says `closes … ; known as shut` for that reason.
- `; known as` is optional. It fixes the Prolog name of a template, and a story
  needs it only for the verbs its companion `.lps` names in `narrate/2` or
  `display/2`. Commands, `tries to` composites and refusals go unnamed: the
  player finds the action a refusal stands in for through the composite.
- The library's templates are declared but a story states facts for only some;
  the in-process translation declares the rest `:- dynamic`, so an absent door
  is false rather than an error.

## Inform sources

`inform/` holds eleven of Inform's own programs (see `inform/NOTICE.md`). The
front end `src/syntax/lps_inform.pl` turns an Inform program's *assertions* into a
story on the library and reports its *rules* as diagnostics:

```sh
LPS_LE2_LIB=/LogicalEnglish2 ./lps inform examples/if/inform/IQTest.ni            # print the story
LPS_LE2_LIB=/LogicalEnglish2 ./lps inform examples/if/inform/IQTest.ni --out build/story   # write it beside a copy of the library
LPS_LE2_LIB=/LogicalEnglish2 ./lps play   examples/if/inform/NegatedRP.ni         # or just play it
LPS_LE2_LIB=/LogicalEnglish2 tools/inform_test.sh
```

An imported world is a world to write rules for, in Logical English: Ogg's
persuasion and the thief's walk are the sentences the front end reports.
