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

**A folder's README.** The start page shows each folder's README in a panel
(📖 *About this folder*; `src/edges/readme_panel.js`, the same file as LE2's
`web_extras/landing/readme-panel.js`). A README of a substantial folder is
short (about 40 lines) and has the same parts: the title (`Label — what it
is`), one to three sentences on what the folder holds, **Start here** (two to
four programs), **Try this** (four to seven steps with what to expect),
**More** (a `DETAILS.md` beside it for the long material, the manual, and
online sources) and, for twins, the **Disclaimer**. Links are written as they
work on GitHub, relative to the README: a program opens in the IDE, `sub/`
opens that folder's README in the panel, and any other file opens on GitHub.
