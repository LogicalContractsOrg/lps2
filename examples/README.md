# LPS2 examples

LPS2's own example programs, by purpose. Each folder's README title reads
`Label — what it is`: the IDE and the start page show the folder under that
label and description.

| Folder | What |
|---|---|
| [`start/`](start/README.md) | the five programs the documentation walks through |
| [`collections/kowalski-book/`](collections/kowalski-book/README.md) | Kowalski's book, the chapters on time and agents |
| [`agents/`](agents/README.md) | programs driving an agent: an LLM, Minecraft |
| [`planning/`](planning/README.md) | PDDL planning problems, solved by LPS2's planner |
| [`if/`](if/README.md) | interactive fiction: the library, the stories, Inform 7 |
| [`le/`](le/README.md) | Logical English for LPS: programs written in English |
| [`migration/`](migration/README.md) | other systems' programs: twins of Daml, Drools and Solidity programs in Logical English for LPS, and (`drools/drl/`) DRL files LPS2 opens directly |

The original LPS corpus is in `legacy_lps1/examples`. An example is opened
by name, `/ide?example=start/blocks`; old names keep working through
`example_alias/2` in `src/edges/lps_http.pl`.
