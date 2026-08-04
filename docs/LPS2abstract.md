# LPS2

**A clean-room reimplementation of the LPS engine in SWI-Prolog, and a working
environment around it.** LPS — Logic Production System, Kowalski and Sadri — is
a language for programs that act over time: fluents that hold over intervals,
events and actions between them, causal laws saying what an action does, and
reactive rules and integrity constraints saying what must and must not happen.

![The LPS2 IDE](images/ide-overview.png)

## The claim, and its evidence

LPS2 reproduces **99 of LPS1's 108 recorded golden traces exactly**. The other
nine are adjudicated as stale goldens, each naming its evidence; there are no
unexplained failures. That is *trace* equivalence — same actions, same cycles,
same terms up to variable renaming — which is a far harder target than "the
examples still work", and the whole corpus is also run with clause order
reversed, the initial state reversed and the goal queue's discipline inverted,
to catch a program whose result depends on an accident. None does.

It is about **2.5× faster** than the engine it replaces, on a third to a half of
the memory.

## What is new

| | LPS1 | LPS2 |
|---|---|---|
| **planning** | goal reduction | `achieve`, with breadth-first and greedy best-first under a delete-relaxation heuristic, chosen automatically; concurrent action sets; replanning on failure |
| **explanation** | — | a derivation forest recorded on every run; five question forms; four distinct answers to *why not* |
| **hypotheticals** | — | forking a session is a unification: ~5 µs, whatever its size |
| **perpetual runs** | yes | plus asynchronous events over HTTP, per-channel allow-lists, a bounded trace, and mouse interaction |
| **animation** | paper.js in SWISH | Konva in 2D at full parity, three.js in 3D via `display3d/2`, an offline icon library |
| **editor** | SWISH | Monaco: tabs, one grammar for LPS-and-Prolog, in-context diagnostics, contextual explanations |
| **assistant** | — | an agentic loop whose tools are the IDE's own operations |
| **front ends** | LPS syntax | plus Logical English, PDDL and Drools |
| **deployment** | SWISH server | CLI, one HTTP endpoint, a container, and WebAssembly with no server at all |

## How it is built

Ten thousand lines of SWI-Prolog in three layers, and the top one is enforced:
**nothing in `src/core/` may touch threads, sockets, the clock, foreign code or
files**, checked by a linter on every commit. That single rule is why a session
is an immutable term (so forking is free), why traces are reproducible (time is
computed from the cycle number, never read), and why the whole engine compiles
to WebAssembly — a day's work rather than a rewrite.

The first deliverable was not code but `docs/selection_spec.md`: twenty numbered
rules saying where the engine *chooses* and what it chooses, which LPS1 never
wrote down and without which "reimplement LPS" is under-specified.

## Other languages, in

A **PDDL** precondition becomes a denial, an effect becomes a causal law, and the
problem's goal becomes `achieve` — so IPC benchmarks with known-optimal plan
lengths become a test of the planner. A **Drools** `when`/`then` becomes a
reactive rule and `modify(){}` becomes `updates … to … in …`; salience and Java
leaves are reported as diagnostics rather than guessed at. **Logical English**
compiles to the same internal syntax, with provenance, so an engine diagnostic
lands on the English sentence that caused it.

Each front end has an oracle written *before* its transpiler. That rule is what
makes them checkable, and it is what turned up the finding that the planner —
not the translation — is what limits the harder PDDL domains.

## Agents

**Part II** asks whether a symbolic engine can hold the line an LLM cannot be
trusted to hold. `examples/agent/` answers it structurally: the model perceives
(turns English into an event term) and does nothing else; the fluent that
authorises a destructive action is reachable only through a causal law fired by
an event that is not on the model's channel; and the constraint that blocks
execution is checked by the engine rather than by the thing being constrained.
Run it with a weak model, or one told to lie — the refusal is a property of the
wiring.

**Part III** puts it in a game. `examples/minecraft/` is a two-tier agent:
mineflayer at the game's twenty ticks a second doing walking and collision, an
LPS live session at two cycles a second deciding what to do. The supervisory
tier can be wrong without being dangerous, because everything it issues passes
the program's constraints first.

## Where to start

```sh
./lps run examples/goat_declarative.pl     # the language, stated not solved
cd ui && npm install && npm run build      # once
./lps ide                                  # everything else, on :3060
```

- **`docs/lps_tutorial.md`** — the teaching path, from a two-line program to
  live sessions.
- **`docs/UsingTheIDE.md`** — the environment, and a "how do I…" section.
- **`docs/IntroducingLPS2.md`** — the full tour, with screenshots taken from the
  running system.
- **`docs/lps_summary.md`** — the language reference.
- **`docs/LPSplusLLM.md`** — the plan of record, and the one place project
  status lives.
