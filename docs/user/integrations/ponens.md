# Ponens policies and LPS

*Kind: integration guide · Audience: users · Status: current (2026-10-16)*

Ponens is an open-source checker (MIT licence). Ponens reads the record of a session
of an AI coding agent. The record shows which actions the agent did, and in which
sequence. The record also shows the files and the results that each action used and
made. Ponens calls such a record a **trace**. Ponens compares a trace with
**policies**. A policy is a rule about the sequence of the actions. A policy is
written in a temporal logic. A temporal logic is a logic about what comes before and
what comes after. An example of a policy is:

```
G(Deploy → P(tested ∧ validated))
```

This policy means: at each step (`G`), a deployment (`Deploy`) must come after
(`P`, previously) a step that was tested and validated. The gallery of Ponens puts
213 policies into packs. There is one pack for each organisation whose rules the
policies state again. These organisations are the US National Institute of Standards
and Technology (NIST) and the European Securities and Markets Authority (ESMA). Other
packs are the coding standards of MISRA and CERT, the aviation standard DO-178C, and
others.

A policy is a rule about a process in time. A trace is a sequence of events. Both
agree directly with LPS (Logic Production System). A pack of policies becomes a
program of **Logical English for LPS**. In this program, each policy is a law that
records a breach: *the policy P is broken at step S*. Each trace becomes a scenario
of that program. A scenario is a set of events and facts that the program runs. Click
**Run**. Each breach then appears on the timeline at the step where its policy
failed.

## Contents

- [At a glance](#at-a-glance)
- [How to use it](#how-to-use-it)
  - [The twins among the examples](#the-twins-among-the-examples)
  - [Opening a Ponens file](#opening-a-ponens-file)
  - [Writing policies for Ponens](#writing-policies-for-ponens)
- [How a policy maps to LPS](#how-a-policy-maps-to-lps)
- [How it was checked](#how-it-was-checked)
- [What is not translated](#what-is-not-translated)
- [See also](#see-also)

## At a glance

| Direction | Where (menu item) | Files | What you get | Checked against |
|---|---|---|---|---|
| Ponens → Logical English for LPS | **File ▸ Open…** | a policy (`.json`), a list of policies, or a trace that contains its policies | each policy becomes a law that records a breach, and each trace becomes a scenario | the evaluator of Ponens, on each pack and each trace: 11,236 verdicts, all the same |
| Logical English for LPS → Ponens | **Misc ▸ Export to another system… ▸ Ponens** | a program whose laws record breaches | one policy file, ready for `ponens trace check --policy-file` | Ponens again: the policies that the translator writes back give the same 11,236 verdicts as the original policies |

The translator is part of the Logical English installation (the lpsPlus
translators). Thus the translator needs LE2, the Logical English editor, adjacent to
LPS2 (`LPS_LE2_LIB`, refer to [Logical English](../guide/ide.md#logical-english)). The
hosted service has this installation.

## How to use it

### The twins among the examples

A twin is a program that a translator made from the source of a different system.
The twins of all the packs of Ponens are in `examples/migration/ponens/`. There is
one folder for each pack. There are fourteen folders, with the 213 policies. Each
folder has a `sources/` folder. The `sources/` folder contains these items:

- the policies of the pack, as Ponens publishes them
- the description and the specification of the pack
- the page of the organisation of the pack
- the licence of Ponens
- the example traces of the pack, with the verdict of Ponens on each trace.

To open a twin, do these steps:

1. Select **File ▸ Open example from server**.
2. Open the folder *Migration twins*.
3. Select a twin, for example `migration/ponens/esma_mifid_ai_investment_services`.

The comment above each scenario tells you what Ponens found on the same trace. To
run a twin, do these steps:

1. Select the scenario `violating`.
2. Click **Run**.

Thirteen policies are broken. Each policy is broken at the step that Ponens names. To
see why a breach occurred, do these steps:

1. Right-click a breach on the timeline.
2. Select *Why*.

The explanation names the condition of the policy that the step did not satisfy.

### Opening a Ponens file

**File ▸ Open…** opens three kinds of Ponens file:

- **One policy** of the gallery (`gallery/policies/<name>.json`), or **a list of
  policies**. A list of policies is the file that `ponens trace check --policy-file`
  reads. The program has the laws, but it has no scenario. To run the program, add a
  scenario with one event for each fact of each step.
- **A trace that contains its policies** (a `"policies"` list in the trace). The
  trace becomes the scenario of the program. To read a trace as Ponens reads it, the
  server must have the Python package of Ponens (`pip install ponens`). If the server
  does not have this package, the program has the laws only. A note then tells you
  why the scenario is not there.

The note at the top of the program tells you how many policies became laws. The note
also tells you how many policies stay as comments, because the parser of Ponens
cannot read them.

### Writing policies for Ponens

**Misc ▸ Export to another system… ▸ Ponens** writes the laws of a program back as
Ponens policies, in one file in the format of Ponens. The export writes back a law
when two conditions are true:

- The law records a breach (`the policy P is broken at step S`, or
  `the policy P is broken`).
- The conditions of the law have the forms that the translator writes.

A law of a different form is a problem. The editor shows the problem with its
policy. The export then stops, and it does not write an incorrect file.

## How a policy maps to LPS

| In Ponens | In Logical English for LPS |
|---|---|
| a step of a trace (an action) | the events `step 3 is a Deploy`, `step 3 shows "tested"`, `step 3 ends`, in that sequence, at times 6 and 7 |
| a kind of action (`Deploy`, `EditFile`) | `step S was a Deploy`, a fluent that is true from the step forward |
| a sign of a step (`tested`, `high_stakes_path`) | `step S has shown "tested"`, which the code of Ponens calculates when the translator reads the trace |
| an artifact and its lineage (`derived_from`) | `artifact A derived from artifact B`, `artifact A was made by step S` |
| `G(φ)`, at each step | a law *when step a step ends … then the policy P is broken at step the step*, examined when each step ends; when φ looks forward (`F`, `X`, `U`), examined when the session ends |
| `P(φ)`, `P_chain(φ)`, `P_target(φ)`, `φ S_last ψ`, `φ S ψ` | a condition with a name, for example *an earlier step in its chain is a SystemRequirement*, which a rule about the steps that ended defines |
| `F(φ)`, `X(φ)`, `φ U ψ` | a condition with a name about the later steps, read at the end of the session |
| `count(…) ≤ 20`, `∀ r ∈ residuals . …` | a count of the steps, or a condition on each item of a collection |
| the eight policies that Ponens decides with its own code, by name (`data_flow_integrity`, `generated_tests_require_decomposition`, …) | a law that does the same as that code, written by hand one time |

A fluent is a fact that can change with time. Each condition with a name is a rule.
You can read this rule and ask questions about it. The *Why* explanation of a breach
names the condition that was not satisfied, and the step and the fact.

## How it was checked

A gate is a program that compares the results of two systems. The gate
(`migration/ponens/ponens_gate.py` in lpsPlus) runs each pack on each trace of the
examples of Ponens. There are 53 traces. The gate compares the twin with the
evaluator of Ponens, one policy at a time:

- When a policy fails in Ponens, the policy must be broken in the twin. When a policy
  passes in Ponens, the policy must not be broken in the twin.
- For a policy `G(φ)`, the steps where the twin records the breach must be the
  actions that Ponens names as violations of the policy.

All 11,236 verdicts are the same. The gate then writes each twin back as Ponens
policies. Ponens then examines the traces again. The 11,236 verdicts are the same as
the verdicts with the original policies.

The gate found mistakes on the two sides of the comparison. Each mistake was
repaired in the translator or in LPS2. One kind of mistake is important when you
write Logical English yourself. A word in capital letters only (`HLR`, `LLR`) is a
variable. Thus you must write a kind with that spelling in quotes (`"HLR"`).

## What is not translated

- One of the default policies of Ponens, `two_person_approval_for_infra`, stays as a
  comment. This policy compares two approvers. The parser of Ponens also cannot read
  this policy. Ponens reports this policy as *unknown*.
- The code of Ponens calculates the signs of a step (`tested`, `high_stakes_path`,
  the results of an oracle) when it reads a trace. To do this, Ponens finds words in
  the text of an action with its own method. The twin uses these signs as facts of
  the scenario. If you type a trace into a scenario by hand, you must state these
  signs.

## See also

- Ponens: <https://ponens.dev>, its gallery of policies
  <https://ponens.dev/gallery/> and of organisations
  <https://ponens.dev/organizations/>, and its source
  <https://github.com/imandra-ai/ponens>.
- [Other systems](index.md), the map of the translators.
- [How a program runs](../tutorials/how-lps-runs.md), for what happens in
  each cycle.
- [Logical English for LPS](../reference/le-for-lps.md), the language the
  twins are written in.
