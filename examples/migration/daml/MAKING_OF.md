# How the examples in this folder were made

A translator program wrote every Logical English program in this folder and
its subfolders. A translator is a program that reads another system's
program and writes it again in Logical English, here in Logical English for
LPS. People at Digital Asset wrote the originals, the Daml SDK's own
templates, which each twin keeps unmodified in its `sources/` folder. An AI
agent wrote the translator: Claude, an AI model made by Anthropic, working in
the Claude Code tool at Miguel Calejo's request.

| File | Made by | How |
|---|---|---|
| `*/sources/daml/**/*.daml`, `*/sources/LICENSE` | People: Digital Asset, the makers of Daml | Copied unmodified from the Daml SDK's templates (`daml-intro-choices`, `daml-intro-compose`, `daml-intro-constraints`, `daml-intro-daml-scripts`, `daml-intro-parties`, `daml-patterns`, `quickstart-java`, `skeleton`; SDK 3.5.10, Apache License 2.0) by the translator's fetch script. |
| `*/sources/NOTICE.txt` | AI agent (Claude, in Claude Code) | Where the sources come from, and their licence. |
| every `<twin>.le` (for example `simple_iou/simple_iou.le`, `compose/compose_test_trade.le`) | Translator program, 2026-09-15 to 2026-09-17 | Written by the Daml translator from the Daml sources beside it: each template becomes a fluent (a fact that holds for a while), each create and choice an action, each Daml Script a scenario. The expected final states come from running the same scripts on Daml itself. Not edited by hand. |
| every `<twin>.ledger.md` and `<twin>.ledger.json` | Translator program, same dates | The migration ledger: what each part of the twin was translated from, and how faithfully. |
| `README.md` | Not recorded | Moved here on 2026-09-16 in a commit that does not say who wrote it. |

## The record

The twins were built in the InsurLE2 repository and moved here on 2026-09-16.
The translator now lives in the private lpsPlus repository.

- InsurLE2 commit `65180a6` (2026-09-15) "Phase 2g: Daml / Canton both ways through Logical English": adds the translator; author "Miguel Calejo (via Claude)", with a `Co-Authored-By: Claude` line.
- LPS2 commit `294b1bf` (2026-09-16) "update telemetry, other changes relating to examples move": moves the twins here; no agent line (a move, not a new writing).
- translator: `lpsPlus/migration/daml/daml_twin.pl` (the twin and its ledger), `daml_import.pl` and `daml_syntax.pl` (the reader), `corpus.pl` (which templates), `fetch_sources.sh` (the sources), `daml_oracle.pl` (the runs on Daml). To write the twins again, from the LogicalEnglish2 folder: `./myswipl.sh -q /lpsPlus/migration/daml/build.pl` (or `… build.pl -- skeleton token` for some). The check: `lpsPlus/migration/daml/test_daml.pl`.
