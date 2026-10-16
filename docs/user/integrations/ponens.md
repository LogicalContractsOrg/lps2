# Ponens policies and LPS

*Kind: integration guide · Audience: users · Status: current (2026-10-16)*

Ponens is a checker that Imandra publishes as open source (MIT licence). It
reads the record of a session of an AI coding agent: which actions the agent
took, in which order, and which files and results each action used and made.
Ponens calls such a record a **trace**. Ponens checks a trace against
**policies**. A policy is a rule about the order of the actions, written in a
temporal logic (a logic of what comes before and after), for instance:

```
G(Deploy → P(tested ∧ validated))
```

which reads: at every step (`G`), a deployment (`Deploy`) must come after
(`P`, previously) a step that was tested and validated. Ponens's gallery
groups 213 policies into packs, one per organisation whose rules they
restate: the US National Institute of Standards and Technology (NIST), the
European Securities and Markets Authority (ESMA), the coding standards of
MISRA and CERT, the aviation standard DO-178C, and others.

A policy is a rule about a process in time, and a trace is a sequence of
events. Both fit LPS (Logic Production System) directly. A pack of policies
becomes a program of **Logical English for LPS**, in which each policy is a
law that records a breach: *the policy P is broken at step S*. Each trace
becomes a scenario of that program. Press **Run**, and each breach appears
on the timeline at the step where its policy failed.

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
| Ponens → Logical English for LPS | **File ▸ Open…** | a policy (`.json`), a list of policies, or a trace that carries its policies | each policy a law that records a breach, each trace a scenario | Ponens's own evaluator, on every pack and every trace: 11,236 verdicts, all the same |
| Logical English for LPS → Ponens | **Misc ▸ Export to another system… ▸ Ponens** | a program whose laws record breaches | one policy file, ready for `ponens trace check --policy-file` | Ponens again: the written-back policies give the same 11,236 verdicts as the originals |

The translator belongs to the Logical English installation (the lpsPlus
translators), so it needs LE2, the Logical English editor, beside LPS2
(`LPS_LE2_LIB`, see [Logical English](../guide/ide.md#logical-english)), as
on the hosted service.

## How to use it

### The twins among the examples

The twins of all of Ponens's packs are in `examples/migration/ponens/`: one
folder per pack, fourteen in all, with the 213 policies. Each folder keeps,
under `sources/`, the pack's policies as Ponens publishes them, the pack's
description and specification, the page of its organisation, Ponens's
licence, and the pack's example traces with Ponens's verdicts on each.

Open a twin with **File ▸ Open example from server**, in the folder
*Migration twins*, for instance
`migration/ponens/esma_mifid_ai_investment_services`. The comment above each
scenario says what Ponens found on the same trace. Choose the scenario
`violating` and press **Run**: thirteen policies are broken, each at the step
Ponens names. Right-click a breach on the timeline and choose *Why*: the
explanation names the condition of the policy that the step failed.

### Opening a Ponens file

**File ▸ Open…** takes three kinds of Ponens file:

- **one policy** of the gallery (`gallery/policies/<name>.json`), or **a list
  of policies**, the file that `ponens trace check --policy-file` reads. The
  program has the laws and no scenario: add a scenario, one event for each
  fact of each step, to run it.
- **a trace that carries its policies** (a `"policies"` list inside the
  trace). The trace becomes the program's scenario. Reading a trace as Ponens
  reads it needs Ponens's own Python package on the server (`pip install
  ponens`); without it, the program has the laws and a note says why the
  scenario is missing.

The note at the top of the program says how many policies became laws, and
how many were kept as comments because Ponens's own parser cannot read them.

### Writing policies for Ponens

**Misc ▸ Export to another system… ▸ Ponens** writes the laws of a program
back as Ponens policies, one file in Ponens's format. A law is written back
when it records a breach (`the policy P is broken at step S`, or `the policy
P is broken`) and its conditions are of the forms the translator writes. A
law of another form is a problem, listed with its policy, and the export is
refused rather than written wrong.

## How a policy maps to LPS

| In Ponens | In Logical English for LPS |
|---|---|
| a step of a trace (an action) | the events `step 3 is a Deploy`, `step 3 shows "tested"`, `step 3 ends`, in that order, at times 6 and 7 |
| a kind of action (`Deploy`, `EditFile`) | `step S was a Deploy`, a fluent from the step on |
| a sign of a step (`tested`, `high_stakes_path`) | `step S has shown "tested"`, worked out by Ponens's own code when the trace is read |
| an artifact and its lineage (`derived_from`) | `artifact A derived from artifact B`, `artifact A was made by step S` |
| `G(φ)`, at every step | a law *when step a step ends … then the policy P is broken at step the step*, checked as each step ends; when φ looks forward (`F`, `X`, `U`), checked when the session ends |
| `P(φ)`, `P_chain(φ)`, `P_target(φ)`, `φ S_last ψ`, `φ S ψ` | a named condition, such as *an earlier step in its chain is a SystemRequirement*, defined by a rule over the steps that have ended |
| `F(φ)`, `X(φ)`, `φ U ψ` | a named condition over the later steps, read at the end of the session |
| `count(…) ≤ 20`, `∀ r ∈ residuals . …` | a count of the steps, or a condition on each item of a collection |
| the eight policies Ponens decides by its own code, by name (`data_flow_integrity`, `generated_tests_require_decomposition`, …) | a law that follows that code, written by hand once |

Every named condition is a rule you can read and ask about. The *Why*
explanation of a breach names the condition that failed, down to the step
and the fact.

## How it was checked

A gate (`migration/ponens/ponens_gate.py` in lpsPlus) runs every pack on
every trace of Ponens's examples, 53 traces, and compares the twin with
Ponens's own evaluator, policy by policy:

- a policy Ponens fails must be broken in the twin, and a policy it passes
  must not be;
- for a policy `G(φ)`, the steps where the twin records the breach must be
  the actions Ponens names as violating it.

All 11,236 verdicts are the same. The gate then writes each twin back
as Ponens policies and has Ponens check the traces again: the 11,236
verdicts are the same as with the original policies.

The gate found mistakes on both sides of the line, and each was fixed in the
translator or in LPS2. One kind of mistake is worth knowing when you write
Logical English yourself: a word written all in capitals (`HLR`, `LLR`) is a
variable, so a kind of that spelling is written in quotes (`"HLR"`).

## What is not translated

- One policy of Ponens's own defaults, `two_person_approval_for_infra`, is
  kept as a comment. It compares two approvers, which Ponens's own parser
  cannot read either; Ponens reports it as *unknown*.
- The signs of a step (`tested`, `high_stakes_path`, the results of an
  oracle) are worked out by Ponens's code when a trace is read, with Ponens's
  own matching of words in the text of an action. The twin takes them as
  facts of the scenario. A trace typed by hand into a scenario must state
  them.

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
