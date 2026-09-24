# How the examples in this folder were made

A translator program wrote every Logical English program in this folder's
twin subfolders. A translator is a program that reads another system's
program and writes it again in Logical English. Two twins come from the
Drools project's own examples, written by the Drools authors. The other rule
bases, and the whole `drl/` folder, were written by an AI agent: Claude, an
AI model made by Anthropic, working in the Claude Code tool at Miguel Calejo's
request. The same agent wrote the translator.

| File | Made by | How |
|---|---|---|
| `fire_alarm/sources/Fire.drl` and its `.java` files, `honest_politician/sources/HonestPolitician.drl` and its `.java` files | People: the Drools authors (Apache Software Foundation) | Copied from the Drools examples (`fire/simple` and `honestpolitician`), Apache License 2.0. |
| `drl/discount.drl`, `drl/fire-alarm.drl` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new, in the shape of the Drools manual's examples; the fire alarm follows the manual's fire, sprinkler and alarm rule base. |
| `drl/insurance.drl`, `drl/shipping.drl`, `drl/traffic-light.drl` | AI agent (Claude, in Claude Code), 2026-08-04 | Written new, in the shape of the Drools tutorials each opening comment names. |
| `drl/fire-alarm.wording`, `drl/README.md` | Not recorded | Added on 2026-09-15 and 2026-09-16 in commits that do not say who wrote them. |
| `discount/sources/discount.drl`, `insurance/sources/insurance.drl`, `shipping/sources/shipping.drl` | AI agent (Claude, in Claude Code), 2026-09-14 | The rule bases of `drl/`, written out again as DRL (the Drools Rule Language) that Drools itself accepts, so that Drools can check the twins. |
| `fire_alarm/sources/Fire.wording` | AI agent (Claude, in Claude Code), 2026-09-15 | How the fire alarm's facts read in English. |
| every `<twin>.le` (for example `fire_alarm/fire_alarm.le`, `discount/discount_decision.le`) | Translator program, 2026-09-15 and 2026-09-16 | Written by the DRL translator from the sources beside it: each Drools rule becomes a reactive rule, and each change to Drools' working memory an event with its effect. The final states are checked against Drools itself. Not edited by hand. |
| every `<twin>.ledger.md` and `<twin>.ledger.json`, `*/sources/*.drools.json` | Translator program, same dates | The migration ledger (what each part of the twin was translated from), and the case the translator ran. |
| `README.md` | Not recorded | Moved here on 2026-09-16 in a commit that does not say who wrote it. |

## The record

In LPS2 every commit carries Miguel Calejo's name. A commit made by the AI
agent says so in its message, with a line `Co-Authored-By: Claude …`. The
twins were built in the InsurLE2 repository and moved here on 2026-09-16; the
translator now lives in the private lpsPlus repository.

- commit `f0b1c60` (2026-08-04) "M12a and M12d: PDDL and Drools as front ends": adds `drl/discount.drl` and `drl/fire-alarm.drl`, and the Drools reader; agent commit.
- commit `ae1e982` (2026-08-04) "Nine more PDDL problems, three more rule bases…": adds `drl/insurance.drl`, `drl/shipping.drl`, `drl/traffic-light.drl`; agent commit.
- InsurLE2 commit `05d14e5` (2026-09-14) "Phase 2e: Drools twins checked against a real KieSession": adds the translator; author "Miguel Calejo (via Claude)".
- LPS2 commit `294b1bf` (2026-09-16) "update telemetry, other changes relating to examples move": moves the twins here; no agent line (a move, not a new writing).
- translator: `lpsPlus/migration/drools/drl_twin.pl`, over `lpsPlus/migration/drools/lps_drools.pl` (LPS2's reading of a DRL file, moved to lpsPlus on 2026-09-19); `corpus.pl` lists the cases. To write the twins again, from the LogicalEnglish2 folder: `./myswipl.sh -q /lpsPlus/migration/drools/build.pl`. The check: `lpsPlus/migration/drools/test_drools.pl`, against the Drools program in `lpsPlus/migration/drools/oracle/`.
