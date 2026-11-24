# Gloria and LPS — an evaluation and a migration plan

*Kind: plan · Status: proposed, not started (phase 0 spike done 2026-11-16)*

**Written 2026-11-16.** What exists is a checkout of the Gloria repository at `/gloria`
(19 commits, 2026-07-22 to 2026-11-12, head `3b64215`). Nothing in it was changed: every
run below used a copy in a scratch directory. Everything marked **[verified]** was
checked by reading the Gloria sources or by running Gloria's SWI-Prolog engine, LPS2, or
the legacy LPS1 engine; everything marked **[assessment]** is a judgement and should be
re-checked when work starts.

This document follows the house rule: it is the reasoning. If the plan is adopted, its
milestone (proposed: **M12h**, beside the other front ends of Part IV) goes into
`docs/project/plan-of-record.md`, and its status lives there and nowhere else.

---

## Contents

- [0. The recommendation, in one page](#0-the-recommendation-in-one-page)
- [1. What Gloria is](#1-what-gloria-is)
- [2. The Gloria language — a synopsis](#2-the-gloria-language-a-synopsis)
- [3. The examples and their expected answers](#3-the-examples-and-their-expected-answers)
- [4. Gloria, LPS and Logical English compared](#4-gloria-lps-and-logical-english-compared)
- [5. The spike](#5-the-spike-verified)
- [6. The mapping, Gloria → LE for LPS](#6-the-mapping-gloria-le-for-lps)
- [7. The plan — M12h, four phases and two optional ones](#7-the-plan-m12h-four-phases-and-two-optional-ones)
- [8. The other direction: LPS or LE → Gloria](#8-the-other-direction-lps-or-le-gloria)
- [9. Risks and open questions](#9-risks-and-open-questions)
- [10. Sources](#10-sources)

## 0. The recommendation, in one page

**Gloria is a close relative of LPS, not a competitor.** It is Jacinto Dávila's
abductive reactive agent (from his PhD thesis; version 1.1.3 of 2009,
maintained in the Galatea simulation project), written on the Kowalski–Sadri agent
cycle and the Fung–Kowalski IFF proof procedure — the same line of work from which
Kowalski and Sadri later derived LPS. Its goals are reactive rules (`if … then …`), its
beliefs are goal reductions (`to … do …`), its actions and observations are
*abducibles*. Every one of these has a direct counterpart in LPS and in Logical English
for LPS.

**Recommended direction: Gloria → Logical English for LPS, as migration twins.** Build
a deterministic translator, in the pattern of the other twins
(`examples/migration/README.md`, translators in `lpsPlus/migration/<language>/` —
*November 2026:* the translators are now open source, in LE2's `migration/<language>/`,
and `lpsPlus/migration/` in the phases below reads as LE2's `migration/`), that
reads an agent's `.kb` and `.main` and writes an LE-for-LPS document with a scenario for
each of Gloria's golden runs and a migration ledger. The spike of §5 translated three of
the nine agents by hand — `enclosure` (to LE for LPS and to LPS), `rentin` and
`marciano` (to LPS) — and LPS2 produced Gloria's actions step for step, one cycle
later, in all three.

Four reasons this is worth doing, and cheap:

1. **An oracle exists and runs here.** Gloria's SWI engine runs unchanged on this
   machine's `swipl`, and its repository carries a golden suite of nine scenarios
   (21 steps). Part IV's first rule — "do not start a transpiler before its oracle is
   specified" — is met before work starts.
2. **The fit is good where it matters.** Seven of the nine agents are reactive rules
   plus macro-actions over observations of one step; they translate with their meaning
   unchanged. The two hard points (§4.3) are named and small.
3. **What LPS adds is legible to a Gloria user**: state that persists between steps
   (fluents, instead of side effects in conditions), integrity constraints, the
   Timeline, *why* and *why not* explanations, and an English reading.
4. **The audience is close.** Gloria's author is a co-author of LPS and of Logical
   English (see `docs/user/history.md`); Gloria is used for teaching in Spanish, and
   Logical English already has a draft Spanish version (*Español Lógico*).

**Not recommended as a milestone: LPS → Gloria.** Gloria has no fluents, no causal laws
and no time beyond a step number, so most LPS programs have no Gloria reading (§8). The
one cheap thing in that direction is an adapter that offers Gloria's stepping interface
(`prolog_agent/5`, its MCP tools) over an LPS2 live session, so that Gloria's clients —
the Galatea simulator, the playground, its MCP server — can drive LPS programs. That is
phase 5, optional.

**Licence, before anything is copied:** Gloria is AGPL-3.0-or-later; LPS2 is
Apache-2.0. The translator reads Gloria files as data and copies no Gloria code, so it
is unaffected. The twins are derived from AGPL example programs; publishing them needs
the author's permission or must carry the AGPL in their `sources/` folder (§9).

## 1. What Gloria is

### 1.1 The project [verified]

| | |
|---|---|
| Author | Jacinto Dávila, CESIMO, Universidad de Los Andes, Mérida, Venezuela |
| Origin | the author's PhD thesis (`readme` links `phd-davila-jacinto.pdf`), `gloria.sourceforge.net`; maintained in Galatea (`galatea.sourceforge.net`). `readme`: version 1.1.3, 8 April 2009; `version` file: `1.1.2` |
| Licence | AGPL-3.0-or-later (`LICENSE`, `LICENSING.md`); the Ciao port in `ciao/gloria/src/` is also LGPL-3.0-or-later; `flach/` is third-party (Flach's implementation of Shapiro's MIS) |
| Engine | SWI-Prolog, no modules (the files `consult` each other): `gloria.pl` (agent cycle, 1340 lines), `rplan.pl` (the proof procedure), `implica.pl` (implications), `equiva.pl`, `rewrite.pl` (equality and inequality), `auxilia.pl`; `gcompile.pl` + `tokenizer.pl` (the surface-language compiler) |
| Second engine | a Ciao-Prolog port (`ciao/gloria/`), with a parity harness against SWI and a WebAssembly playground (`playground/`) with ten "Active Learning Documents" |
| Edges | an MCP server (`web/mcp/gloria_mcp.py` over a JSON-lines SWI worker, `web/mcp/runner.pl`); an SWI HTTP API with a React front end (`web/`); `opencode` skills, one per agent (`.opencode/skills/gloria-*`) |
| Files ending `.orig` | the pre-refactor engine, kept beside the refactored one (`GLORIA-REFACTOR-FULL-DESIGN.md`) |

The 2026 work (the Ciao port, the MCP server, the web app, the examples `emergencia`,
`piojo`, `marciano`) is recent and was evidently done with coding assistants; the
engine itself is the 2006–2009 code with module qualification added.

### 1.2 The theory, in one paragraph [verified by reading `rplan.pl`, `gloria.pl`]

`rplan.pl` calls itself "a reactive planner based on an abductive theorem prover … similar
to that of Kowalski-Fung's IFF proof procedure", with "any-timeness and interleaving of
action and execution and interleaving of planning and testing". An agent's goals are
*integrity constraints* (implications); its beliefs are *definitions* (iff-completed
clauses); actions and observations are *abducible* predicates. One step of the cycle
adds the step's observations to the set of assumptions, propagates them through the
implications, unfolds the resulting goals through the definitions, and keeps the
abducibles that are not observations as the actions to perform — all within a resource
bound (a number of inference steps, usually 400). **[assessment]** This is the agent of Kowalski and
Sadri's 1999 paper "Logic Programming Towards Multi-agent Systems", which the LPS paper
in `docs/project/historical/` cites as reference 15.

## 2. The Gloria language — a synopsis

A Gloria agent has **four layers**, of which only the middle two are needed to run it.

### 2.1 The model file `.g` (Galatea) [verified]

A Galatea simulation model, in sections `TITLE`, `NETWORK` (queueing-network nodes),
`AGENTS`, `INTERFACE` (Java methods that the simulator calls for each action), `INIT`
and `DECL`, ending `END.` Inside `AGENTS`, each agent is a block `Name { Prolog {…}
GOALS {…} BELIEFS {…} }`. `examples/taquilla/Taquilla.g` is a complete multi-agent
model (a bank with three tellers, a manager agent and a customer agent); the other `.g`
files use only the `AGENTS` section.

### 2.2 The surface language: Actilog and Openlog [verified]

`gcompile.pl` compiles two small controlled languages, in English or Spanish keywords:

| | English | Spanish | Compiles to |
|---|---|---|---|
| Goal (Actilog) | `if C1, C2 then G.` | `si C1, C2 entonces G.` | `if_((C1,C2), [G]).` |
| Belief (Openlog) | `to H do B1, B2.` | `para H haga B1, B2.` | `def(H, (B1,B2)).` |
| Assumption (Openlog) | `asume H.` | | `def(H, true).` |

Atoms are ordinary Prolog terms (`adjust_home(Time, Temp)`), not English sentences.
`process_g_file/1` writes `<agent>.kb` (goals and beliefs) and `<agent>.main` (the
`Prolog` block) for each agent of a `.g` file.

### 2.3 The internal form: `.kb` [verified]

```prolog
if_(Conditions, [Goal, …]).   % a goal: when Conditions hold, achieve the Goals
def(Head, Body).               % a belief: Head is achieved (or holds) if Body
```

Several `def/2` clauses for one head are alternatives (a disjunction). In a body:
`,` (and), `not(G)` (handled as the constraint `G → false`), `X eq Y` (equality),
and calls to *user-built* Prolog predicates. A head of `if_/2` may list several goals
(`marciano`: `[reportar((E2,N2)), voltear_derecha]`).

### 2.4 The configuration: `.main` [verified]

Ordinary Prolog, consulted into `user`:

| Declaration | Meaning |
|---|---|
| `abd(Name)` | predicates named `Name` are abducible (actions, observations, assumptions) — by name, any arity |
| `observable(Pattern)` | an abducible that the world reports; in a condition it is *tested* against the step's observations, never assumed |
| `for_testing_only(Pattern)` | older synonym of `observable` |
| `user_built(Pattern)` | a condition run as Prolog (`user_built(true)` when there are none) |
| `tracefile(F)` | Graphviz trace file (unused by the engine path tested here) |
| any other clauses | the user-built predicates themselves (`marciano.main`: grid arithmetic and the map memory) |

An abducible that is not observable is an **action**. The working memory available to
user-built predicates is `memoriza/1`, `recuerda/1`, `no_recuerda/1` (`gloria.pl:357–370`).

### 2.5 The cycle and the API [verified]

```prolog
make_module(Agent, 'examples/x/x.kb'),          % after consult('examples/x/x.main')
prolog_agent(Agent, Step, Resources, Observations, Actions).
% e.g. prolog_agent(enclosure0, 0, 400, [time_day(am), it_is(sunny)], A)
%      A = [do(shut(east_window),0), do(open(doors),0)]
```

`Step` is 0, 1, 2, …; each output is `do(Action, Step)`. The facts that shape a
translation:

1. **Each step starts from the goals afresh.** `gloria_step/7` retracts the agent's
   `goalsmem/3` (`gloria.pl:1187`) *before* it looks for the previous step's goals
   (`gloria.pl:1191`), so the look-up always fails and the integrity constraints are
   reloaded. Nothing is carried from one step to the next except the working memory
   `recuerda/1` — which is a single dynamic predicate in `user`, shared by every agent
   of the process.
2. **All actions of a step happen at that step.** A belief `to adjust_home(am,sunny)
   do shut(east_window), open(doors)` yields both actions with the same time stamp; the
   order of the body is not a sequence.
3. **Conditions are evaluated in source order, with side effects.** `marciano` relies on
   it: its comments say the rule "ya lo visité" must come *before* "no lo visité",
   because the second rule's condition records the visit.
4. **Observations of one step are not remembered.** `cleaning_previous_obs/2` drops
   them.
5. **A condition may be an action the agent itself decides in the same step.** In
   `rentin`, `abuso` is conditional on `no_merezco`, which is defined as the action
   `no_trabajo` that the other goal produces; the proof procedure finds it among the
   step's assumptions.
6. **Learning.** With the observation `learn`, the agent revises its rules by Shapiro's
   Model Inference System (`flach/mis.pl`). None of the nine agents uses it.

## 3. The examples and their expected answers

### 3.1 The agents [verified]

| Agent | Files | What it shows | Constructs |
|---|---|---|---|
| `enclosure` | `.g .kb .main .openlog .actilog` | a building's windows and doors by time of day and weather | goal with two observations; three alternative macro-actions |
| `emergencia` | `.g .kb .main` | press the alarm button in an emergency | a chain of two reductions |
| `mylamp` | `.g .kb .main` | motion turns a lamp on and logs it | variable passed from observation to actions |
| `piojo` | `.g .kb .main` | a woodlouse: three condition–action rules | priority by an extra condition (`descansado`) |
| `burocratin` | `.g .kb .main .openlog .actilog` | a bureaucrat follows (or invents) the procedure | alternatives; a user-built fact `existe/1`; a goal that never fires |
| `gerente` | `.g .kb .main`, `taquilla3/` | a bank manager opens and closes tellers | user-built `timing/1` with `gensym` (a side effect) |
| `rentin` | `.g .kb .main` | an opportunist who rationalises abuse | a deep chain of reductions; a condition on the agent's own action |
| `marciano` | `.g .kb .main` | a Mars explorer on a grid, with a map | arithmetic; working memory by side effects; four rules in priority order |
| `arch` | `ex-arch.kb`, `ex-arch.main`, `archmain.pl`, `arch.pl`, `larch.pl`, … | build an arch from observed columns and a beam | abducibles that are neither actions nor observations; an action named `do`; learning data |
| `taquilla` | `Taquilla.g`, two agents | the full Galatea bank simulation | multi-agent; Java interface |

### 3.2 The golden runs, re-run here [verified 2026-11-16]

These are the scenarios of Gloria's parity harness (`ciao/gloria/tests/parity_scenarios_check.sh`)
and of its Ciao unit tests (`t_engine.pl`, `t_playground.pl`). I ran each through
Gloria's SWI driver (`ciao/gloria/tests/driver_scenario_s.pl`, resources 400) on a
copy of the repository; every output equals the expected value written in the tests.
Each line is one step; the step number is the second argument of `do/2`.

| Agent | Observations, step by step | Actions |
|---|---|---|
| enclosure | `[time_day(am),it_is(sunny)]` | `do(shut(east_window),0), do(open(doors),0)` |
| | `[time_day(pm),it_is(rainy)]` | `do(shut(east_window),1), do(shut(west_window),1), do(shut(doors),1)` |
| burocratin | `[me_pide(juan,sacar_constancia)]` | `do(lee(sacar_constancia),0)` |
| gerente | `[timing(1),cola_larga]` | `do(revisa_cola(1),0), do(crear_taquilla,0)` |
| | `[timing(2),taq_vacias]` | `do(revisa_cola(2),1), do(eliminar_taquilla,1)` |
| arch | `[build(5),c(5),c(8),b(10)]` | `do(do(8),0), do(do(8),0), do(do_b(10),0)` |
| mylamp | `[motion(room)]` | `do(switch_on(lamp1),0), do(log(room),0)` |
| rentin | `[flojera,gano,no_hay_jueces_confiables,sin_observador]` | `do(no_trabajo,0), do(abuso,0)` |
| | `[flojera,gano,no_hay_jueces_confiables,observador_independiente]` | `do(no_trabajo,1)` |
| emergencia | `[emergencia]` | `do(pulsa_boton,0)` |
| | `[]` | none |
| piojo | `[frente_libre,descansado]` | `do(avanzar,0)` |
| | `[frente_libre,descansado]` | `do(avanzar,1)` |
| | `[obstaculo_al_frente,descansado]` | `do(voltear_derecha,2)` |
| | `[frente_libre,cansado]` | `do(detenerse,3)` |
| marciano | `[posicion(0,0),orientacion(este),frente_libre]` | `do(avanzar,0)` |
| | `[posicion(1,0),orientacion(este),frente_libre]` | `do(avanzar,1)` |
| | `[posicion(2,0),orientacion(este),obstaculo_al_frente]` | `do(voltear_derecha,2)` |
| | `[posicion(2,0),orientacion(sur),obstaculo_al_frente]` | `do(voltear_derecha,3)` |
| | `[posicion(2,0),orientacion(oeste),frente_libre]` | `do(voltear_derecha,4)` |
| | `[posicion(2,0),orientacion(norte),vida]` | `do(reportar((2,1)),5), do(voltear_derecha,5)` |

Extra runs, outside Gloria's suites (observed here, useful as further scenarios):
`enclosure` with `[time_day(pm),it_is(sunny)]` at step 2 gives
`do(shut(west_window),2), do(open(doors),2)`, and with `[]` gives nothing;
`burocratin` with `me_pide(ana,reporte)` gives `do(lee(reporte),1)` and with
`me_pide(ana,otra)` (no manual exists) gives nothing; `mylamp` with `[]` gives nothing.

Two answers deserve a note. **`arch`** repeats `do(do(8),0)`: both columns of the arch
were bound to the same observed column `c(8)`, and `c(5)` was not used. This is the
proof procedure's factoring at work, and a twin will not reproduce it without an
adjudication (§4.3). **`gerente`** gets its numbers from the observations
`timing(1)`, `timing(2)`; its `.main` also defines `timing/1` with `gensym`, which in a
fresh process happens to count 1, 2 as well, so the test cannot tell the two readings
apart.

### 3.3 The test assets [verified]

| Asset | What it checks | State |
|---|---|---|
| `ciao/gloria/tests/parity_scenarios_check.sh` | the nine scenarios above, SWI against Ciao, byte for byte | needs Ciao, which is not installed here; the SWI half runs |
| `ciao/gloria/tests/t_engine.pl` | seven of the scenarios (not `mylamp`, `rentin`) through the Ciao engine | Ciao only |
| `ciao/gloria/tests/t_playground.pl` | the nine scenarios through the playground's generated sources, and the playground's query rewriting (10 tests) | Ciao only |
| `examples/enclosure/enclosure_test.pl` + `test/test_matchers.pl` | one plunit test (`verify_actions(subset, …)`) | **broken**: it consults `enclosure0.kb`, which does not exist |
| `test_emergencia.py` | one step through the MCP worker | prints the reply, asserts nothing |
| `.opencode/skills/gloria-*/SKILL.md`, `playground/alds/*.md` | a "known-good sample run" per agent, in prose | documentation; agrees with the table above |
| `examples/*/…_trace.log` | one recorded step | a record, not a test |

Gloria's own documents disagree on the count of unit tests ("13 passed", "15/15",
"17/17"); the two files hold 17 tests.

### 3.4 What the `.g` sources are worth [verified]

I compiled each agent's `.g` with Gloria's `process_g_file/1` and compared the output
with the `.kb` in the repository:

- `enclosure`, `emergencia`, `mylamp`, `rentin`, `gerente`: the same clauses.
- `burocratin`: different — the `.g` says `pide_carta_autoridad` (and declares it
  observable), the `.kb` and `.main` say `pida_carta_autoridad` and do not.
- `piojo`, `marciano`: **an empty `.kb`**, silently. The compiler does not accept a
  parenthesised condition (`if (frente_libre, descansado) then …`), and these `.kb`
  files were written by hand.

So the `.kb` + `.main` pair is the form that is tested and run; the `.g` is
documentation that has drifted. **The translator reads `.kb` and `.main`.** A `.g` file
is opened by running Gloria's compiler first (or by our own reader of the `AGENTS`
section, phase 3), and its `NETWORK`/`INTERFACE` sections are reported, not translated.

## 4. Gloria, LPS and Logical English compared

### 4.1 The vocabulary, side by side

| Gloria | LPS (legacy syntax) | Logical English for LPS |
|---|---|---|
| goal `if_(C, [G])` | reactive rule `if C then G.` | `if C … then G ….` |
| belief `def(H, B)` with actions in `B` | composite event `H from T1 to T2 if B.` | `H from a first time to a second time if B …` |
| belief `def(H, B)` over observations only | composite event over the step's interval | the same |
| abducible + observable | event, given by `observe` | an event, given by a scenario |
| abducible, not observable | action | an action |
| user-built Prolog predicate | a timeless Prolog clause | a timeless rule, or Prolog in a companion `.lps` |
| working memory (`memoriza`, `recuerda`) | fluent, with `initiates`/`terminates` | a fluent, with `when … then …` |
| `not(G)` | `not G` | `it is not the case that G` |
| `X eq Y` | `X = Y` | `X is Y` |
| resource bound (400 steps) | — (cycle time limits) | — |
| step `0, 1, 2…` and `do(A, Step)` | cycle; `happens(A, T1, T2)` | the Timeline |
| — | integrity constraint `false …` | `it must not be true that …` |
| — | `initially`, causal laws | `initially …`, `when … then …` |
| learning (MIS) | — | — |

### 4.2 What each side has that the other lacks [assessment]

**LPS and LE have, Gloria lacks:** persistent state with a declarative frame (fluents and
causal laws), so that `marciano`'s map needs no side effects; integrity constraints on
actions; plans that last longer than one step (Gloria restarts every step, §2.5);
real ordering of actions in time; a planner (§I.7); explanations (`why`, `why not`); the
Timeline and the picture; an English reading of the whole program, not only the rules.

**Gloria has, LPS and LE lack:** abduction over predicates that are neither actions nor
events (`arch`'s `c/1`, `b/1`); the anytime resource bound; a condition on an action the
agent decides in the same step (`rentin`); rule learning by MIS; an integration with a
discrete-event simulator (Galatea) and a Java interface for actions; a Ciao/WebAssembly
playground with Active Learning Documents. Its controlled language is bilingual
(English and Spanish keywords) — but its atoms are Prolog terms, so it is far further
from natural language than LE.

### 4.3 The semantic gaps, named [verified unless marked]

| # | Gloria behaviour | In LPS | Verdict for a twin |
|---|---|---|---|
| G1 | observations of step *k* give actions stamped *k* | observations from *k+1* to *k+2* give actions from *k+2* to *k+3* | **encoded**: a fixed shift of one cycle, applied when comparing (§5) |
| G2 | all actions of a step at the same time | a composite body is sequential unless every part has the same interval | **encoded**: every part of a translated body is written `from T1 to T2` |
| G3 | a predicate with no definition and no declaration is false | an undeclared predicate is an existence error (seen in the spike) | **encoded**: the translator declares it as an event that is never observed |
| G4 | working memory changed by side effects in conditions, in source order (`marciano`) | conditions are side-effect free; state is fluents changed by actions | **approximated**: the effect moves onto the action (`avanzar` → `avanzar_a(Square)` that initiates `visitado(Square)`); the action gains an argument |
| G5 | a condition on the agent's own action of the same step (`rentin`) | a reactive rule's conditions are past events or fluents | **approximated**: replace the action by the observation that triggers it, when exactly one goal produces it; otherwise **residue** |
| G6 | abducibles that are neither actions nor observations, with factoring (`arch`) | no counterpart | **residue**; `arch` is not a twin candidate without an adjudication |
| G7 | `user_built` predicates with side effects (`gerente`'s `gensym`) | Prolog in a program is allowed but has no time | **approximated**: `timing(T)` becomes the cycle number |
| G8 | each step starts afresh; unfinished plans are dropped | goals persist until achieved | **[assessment]** no visible difference in any of the nine agents, because every plan finishes in its step; a twin of an agent with a longer plan would differ, and the ledger must say so |
| G9 | learning (`learn`, MIS) | none | **residue**, reported |
| G10 | `recuerda/1` shared by all agents of a process | each LPS program has its own state | **encoded** for one agent; noted for multi-agent models |

## 5. The spike [verified]

Three agents, translated by hand, run on LPS2 (`./lps run`) and, for one point, on the
legacy LPS1 engine:

| Agent | Into | Result |
|---|---|---|
| `enclosure`, 3 steps | LPS (`.lps`) and LE for LPS (`.le`) | the actions of each Gloria step *k* appear in the events of cycle *k+3* (from *k+2* to *k+3*); same actions, same grouping, in both syntaxes |
| `rentin`, 2 steps | LPS | `no_trabajo, abuso`, then `no_trabajo` — Gloria's answer, with G5 approximated |
| `marciano`, 6 steps | LPS | Gloria's six answers, with G4 approximated: `avanzar_a((1,0))`, `avanzar_a((2,0))`, `voltear_derecha` ×3, then `reportar((2,1)), voltear_derecha` |

The enclosure twin in LE for LPS, as it ran:

```
the target language is: lps.

the maximum time is 6.

the events are:
    the time of day is *a time*; known as time_day.
    it is *a weather*; known as it_is.
    the home is adjusted for *a time* and *a weather*; known as adjust_home.

the actions are:
    *a thing* is shut; known as shut.
    *a thing* is opened; known as open.

the knowledge base enclosure includes:

if the time of day is a time from a first time to a second time
    and it is a weather from the first time to the second time
then the home is adjusted for the time and the weather from the second time to a third time.

the home is adjusted for am and sunny from a first time to a second time if
    east_window is shut from the first time to the second time
    and doors is opened from the first time to the second time.

% … pm and sunny, and any time and rainy, the same way

scenario one is:
    the time of day is am from 1 to 2.
    it is sunny from 1 to 2.
    the time of day is pm from 2 to 3.
    it is rainy from 2 to 3.
```

The map of `marciano` in LPS — the part that changes most:

```prolog
fluents visitado(_,_).
actions avanzar_a(_), voltear_derecha, reportar(_).
initially visitado(0,0).
avanzar_a((E,N)) initiates visitado(E,N).

if posicion(E,N) from T1 to T2, orientacion(D) from T1 to T2, frente_libre from T1 to T2,
   adelante(E,N,D,E2,N2), not visitado(E2,N2) at T2
then avanzar_a((E2,N2)) from T2 to T3.
```

**One finding about LPS itself.** The fluent condition must be read `at T2`, the end of
the observation. Written `at T1`, the rule never fires — and the legacy LPS1 engine
(`psyntax:golps/2`, `dc`) behaves the same way, so this is LPS's semantics, not an LPS2
defect: by the time the events of T1–T2 are known, the state at T1 is no longer
queried. The translator writes `at T2`. (Also learned: a `.le` file compiles together
with a `.lps` file of the same name in its folder, so a spike's two versions must not
share a folder.)

## 6. The mapping, Gloria → LE for LPS

The translator applies these rules, one ledger row per source element, with the verdicts
*encoded*, *approximated* and *residue* of the other twins.

1. **Declarations.** For each `abd(N)`: observable or for-testing → an event; otherwise
   → an action. The arity comes from the uses in the `.kb`. Each `def/2` head → a
   composite event. Each predicate used but neither declared nor defined → an event
   that is never observed (G3).
2. **Templates.** Each predicate gets an LE template. The default is mechanical and
   honest — `*a thing* is shut` for `shut/1` needs a person — so the translator writes
   `shut(*a thing*)`-style templates from the Prolog name, and the readable templates
   are an overlay file, one per agent, written by a person or proposed by the LE
   assistant and reviewed. The overlay is input to the translator, never an edit of the
   twin (the rule "twins only by the converter").
3. **Goals.** `if_(C, [G1,…])` → `if C from a first time to a second time then G1 from
   the second time to a third time and …`. Observations in `C` share the interval;
   user-built conditions are timeless; working-memory conditions become fluents `at`
   the second time (§5).
4. **Beliefs.** `def(H, B)` → `H from a first time to a second time if B`, every part of
   `B` on the same interval (G2). Several clauses → several rules.
5. **User-built Prolog.** Pure predicates (`adelante/5`, `existe/1`) → timeless rules
   when they are facts or simple clauses; otherwise into a companion `.lps` file, as
   `badlight.lps` does. Side-effecting ones → G4/G7, or residue.
6. **Scenarios.** Each golden run of §3.2 → a scenario, observations of step *k* from
   *k+1* to *k+2*; the expected actions from Gloria's run, shifted by G1, go into the
   ledger and the gate.
7. **Sources.** The `.kb`, the `.main`, the `.g` and their licence under `sources/`.

## 7. The plan — M12h, four phases and two optional ones

The oracle throughout is **Gloria's own SWI engine**, run through its scenario driver
(`ciao/gloria/tests/driver_scenario_s.pl`) or its JSON-lines worker (`web/mcp/runner.pl`),
in a subprocess, on a copy of the repository — never in `/gloria` itself.

### Phase 0 — the spike — done 2026-11-16

§5. Result: the fit is good; G4 and G5 are the only approximations among the agents
tried; the one-cycle shift is constant.

### Phase 1 — the reader and the oracle

- `lpsPlus/migration/gloria/gloria_reader.pl`: `.kb` + `.main` → a model (goals,
  beliefs, declarations, user-built clauses, each with its line), using
  `read_term/3` with `subterm_positions`. The `.main` is *read*, never consulted.
- `gloria_oracle.pl` + `fetch_sources.sh`: copy the Gloria checkout (pinned commit) into
  `.cache/`, run each scenario through Gloria's driver in a subprocess, store
  `runs/<agent>.json`.
- **Gate:** the oracle reproduces §3.2 exactly, 21 steps out of 21.

### Phase 2 — the translator and the twins

- `gloria_twin.pl`: the model → LE for LPS by §6, with the ledger
  (`<agent>.ledger.json`, `.ledger.md`).
- `build.pl`: twins into `examples/migration/gloria/<agent>/` of this repository (they
  need time, so they live here, not in LE2), sources under `sources/`.
- **Gate (`gate.pl`):** for each agent, run the twin's scenarios with LPS2 and compare
  the actions of cycle *k+3* with Gloria's actions of step *k*, as sets per step, after
  the renamings the ledger records (G4). Expected: `enclosure`, `emergencia`, `mylamp`,
  `piojo`, `burocratin` exact; `rentin`, `marciano`, `gerente` exact after their
  approximations; `arch` reported as residue, not run.

### Phase 3 — File ▸ Open, the `.g` reader, documents

- `gloria_import.pl` through `lpsPlus/migration/le_importers.pl`: File ▸ Open of a `.kb`
  (with its `.main` beside it) or of a `.g` (only its `AGENTS` section; `NETWORK`,
  `INTERFACE`, `INIT`, `DECL` listed in the ledger as residue).
- `docs/user/integrations/gloria.md` (Simplified Technical English, like the others),
  and a line in `examples/migration/README.md`.
- Ask Gloria's author to review the twins and the ledger (the L4 twins had a role-play review only).

### Phase 4 — the readable templates

The template overlays of §6.2 for the nine agents, so that the twins read as English.
Because most of Gloria's agents and documents are in Spanish, consider writing these
overlays in Spanish once phase 6 exists.

### Phase 5 (optional) — Gloria's interface over LPS2

A Gloria-compatible stepping interface over an LPS2 live session (`./lps live`): the
four MCP tools of `web/mcp/gloria_mcp.py` (`list_agents`, `agent_info`, `run_step`,
`reset`) and the `prolog_agent/5` contract, answering `do(Action, Step)` from the
session's actions. With it, Galatea, the Gloria web app and the opencode skills drive a
twin unchanged — which is also the best demonstration that the twin is faithful.

### Phase 6 (optional) — Español Lógico for LPS

LE2's Spanish version (`docs/user/guide/languages.md` in LE2, a "draft") covers the
`prolog` target only: no Spanish keywords exist for events, actions, fluents or
`from … to`. Adding them is LE2 work (hard rule 5: check its branch, ask before
committing) and is the step that would make the twins readable to Gloria's own users.

### What is deliberately not in the plan

- **Porting Gloria's engine** into LPS2 or reproducing IFF abduction: the value is in
  the agents, not in a second proof procedure, and it would bring AGPL code in.
- **Learning** (MIS): no counterpart; reported per agent if a source uses it.
- **Galatea's simulation sections**: a Galatea model is a simulator, not an agent.

## 8. The other direction: LPS or LE → Gloria [assessment]

A program of LPS can be written as a Gloria agent only when it has no fluents, no causal
laws, no constraints, no sequence inside a composite event and no plan longer than a
step — that is, when it is already a set of condition–action rules over the events of
one cycle. Few LPS examples are; the goat, the bank transfer, the fire and the lights
are not. An exporter (`lps_gloria_write.pl`, writing `.kb` + `.main`) would be a
day's work for that subset, and it would give the Gloria playground and its Active
Learning Documents more examples, but it would not give a Gloria user anything they
lack. Recommended only if the author asks for it; phase 5 gives the integration value
without the loss.

LE → Gloria goes through LPS and has the same limits.

## 9. Risks and open questions

- **Licence.** Gloria is AGPL-3.0-or-later. The translator copies no Gloria code. The
  twins are translations of AGPL example programs; publishing them in an Apache-2.0
  repository needs the author's agreement (for example, permission to publish the
  examples and their twins under Apache-2.0) or the AGPL notice in each `sources/`
  folder and in the twin. **To ask the author before phase 2.**
- **The oracle's limits.** The golden suite has 21 steps, and some are thin (`[]` → no
  actions). Phase 1 should add the extra runs of §3.2 and, for each agent, the case in
  which a goal does *not* fire.
- **G8 is untested.** No golden scenario has a plan that outlasts its step. If the
  author's intent is that unfinished plans continue (the code comments say "if a
  reentrant, use previous goals"), the present behaviour is a defect of the refactor,
  and the twin should follow the intent. **To ask the author.**
- **`arch`** depends on factoring and on abducibles that are neither actions nor
  observations. Leave it as residue unless the author says which answer is intended.
- **Drift.** The `.g` and `.kb` of `burocratin` disagree, the `.g` of `piojo` and
  `marciano` do not compile, and `enclosure_test.pl` does not load. These are small, but
  they are reports to send back to Gloria, not things to fix in `/gloria`.
- **Spanish.** Without phase 6, the twins are English documents with Spanish atoms. That
  is acceptable for the gate, and poor for Gloria's readers.

## 10. Sources

All in `/gloria` at `3b64215`, unless stated:

- `README.md`, `readme` (2009), `NOTES.md`, `GLORIA-REFACTOR-FULL-DESIGN.md`,
  `BUILDING_NOTES.md`, `CIAO-PLAYGROUND-PROJECT.md`, `Como_agregar_otro_ejemplo.md`,
  `LICENSING.md`
- `gloria.pl` (cycle: `gloria_step/7` at line 1184, `make_module/2` at 1283, working
  memory at 357–370), `rplan.pl` (header comment; `demo_rules/6`), `gcompile.pl`
  (Actilog and Openlog grammars, `process_g_file/1`)
- `examples/*/` (the agents), `ciao/gloria/tests/` (parity harness, scenario drivers,
  unit tests), `.opencode/skills/gloria-*/SKILL.md`, `playground/alds/`
- In this repository: `docs/project/plan-of-record.md` Part IV;
  `examples/migration/README.md`; `docs/user/history.md`;
  `docs/project/historical/Combining Logic Programming and Imperative Programming in LPS/`
- In LE2: `docs/user/guide/languages.md`
- Spike files: written in a scratch directory and not kept; the two programs that matter
  are reproduced in §5.
