# Phase 0 — three Inform programs, by hand, as LPS and as Logical English

The spikes `docs/project/plans/InformPlan.md` §7 asked for, and what they found (§10 there).
Each is one of Inform's own scripted examples, translated by hand, with its
`Test me with` script as observations, and its event sequence checked against
the ideal transcript that ships beside the Inform source.

```sh
examples/if/phase0/check.sh                        # the LPS half
LPS_LE2_LIB=/LogicalEnglish2 examples/if/phase0/check.sh   # both halves
```

| program | Inform source | stresses |
|---|---|---|
| `scene` | test case `C9SceneEndSequence` | scenes as fluents; an Inform turn is several cycles |
| `iqtest` | Recipe Book *IQ Test* (Goal-Seeking Characters) | a character's plan as a composite event; the `instead` idiom |
| `iqtest_c` | the same | the **`try` idiom**: a command is not an obligation, and a refusal is narrated by `why_not` |
| `iqtest_obligation` | the same | the variant that **fails**, kept as evidence for `try` |
| `mre` | Recipe Book *MRE* (Future events) | story time as a fluent; the end of a turn as an event |

`lps/` is LPS external syntax. `le/` is Logical English with a `.lps` companion
holding the narration table — the text Inform writes in `say` phrases, kept out
of the English as `docs/user/reference/le-for-lps.md` §7 says. `expected/` holds the event
sequences `check.sh` compares against; they were read against the transcripts
by hand, once, and are regenerated only when a spike changes on purpose.
