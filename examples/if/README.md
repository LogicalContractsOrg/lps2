# Interactive fiction on LPS — the library and the stories

Phase 1 of `docs/InformPlan.md`. `world.le` is the library: a sliver of Inform's
Standard Rules as Logical English for LPS — rooms, things, containers,
supporters, doors, people, the map, a dozen actions with their preconditions
and effects, scenes, the clock, and one goal-seeking plan. Every other `.le`
here is a story that includes it:

```
the knowledge base my story includes these resources: world.
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

## How a story is driven

A turn is a burst of cycles. The player (`src/edges/lps_play.pl`) injects `the turn
begins` together with the command, steps until a cycle in which nothing happens,
injects `the turn ends` — on which every-turn rules and scheduled events key — and
steps to quiescence again. The `Test me with` scripts in the stories do the same with
four cycles per turn, and a play drops the script and the `maximum time`.

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

## Conventions worth knowing

- One condition per line, `and` first. A conjunction written on one line is
  read by Logical English as a single sentence.
- Constants are single words: `oak_door`, `silver_key`. The narrator (phase 2)
  gives them their names.
- A story's own action must not be named like a SWI-Prolog built-in — the
  library says `closes … ; known as shut` for that reason.
- The library's templates are declared but a story states facts for only some;
  the in-process translation declares the rest `:- dynamic`, so an absent door
  is false rather than an error.
