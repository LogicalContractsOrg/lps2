# LPS2 examples

LPS2's own example programs, by purpose. Each folder's README title reads
`Label — what it is`: the IDE and the start page show the folder under that
label and description.

| Folder | What |
|---|---|
| [`start/`](start/README.md) | the five programs the documentation walks through |
| [`collections/kowalski-book/`](collections/kowalski-book/README.md) | Kowalski's book, the chapters on time and agents |
| [`agents/`](agents/README.md) | programs driving an agent: an LLM, Minecraft |
| [`doors/`](doors/README.md) | other formalisms opened as LPS: PDDL, Drools |
| [`if/`](if/README.md) | interactive fiction: the library, the stories, Inform 7 |
| [`migration/`](migration/README.md) | twins of Daml, Drools and Solidity programs, in Logical English for LPS |

The original LPS corpus is in `legacy_lps1/examples`, and LE2's Logical
English for LPS examples in its checkout (`examples/lps`). An example is opened
by name, `/ide?example=start/blocks`; old names keep working through
`example_alias/2` in `src/edges/lps_http.pl`.
